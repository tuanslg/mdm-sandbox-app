package com.mdm.test

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.RestrictionsManager
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  companion object {
    const val TAG = "MdmSandbox"
    var eventSink: EventChannel.EventSink? = null
    var latestManagedConfig: Map<String, String> = emptyMap()
    var isInForeground: Boolean = false
  }

  // Dynamic receiver needed — ACTION_APPLICATION_RESTRICTIONS_CHANGED is not delivered
  // to static manifest receivers on Android 8+ when app is running.
  private val managedConfigReceiver = ManagedConfigReceiver()

  private val METHOD_CHANNEL = "com.mdm.test/kiosk"
  private val EVENT_CHANNEL = "com.mdm.test/events"

  private var launchReason = "manual"

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    launchReason = intent?.getStringExtra("launch_reason") ?: "manual"

    val dpmInit = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
    val isOwner = dpmInit.isDeviceOwnerApp(packageName)
    Log.d(TAG, "configureFlutterEngine: isDeviceOwner=$isOwner sdk=${Build.VERSION.SDK_INT}")
    if (isOwner) {
      val admin = ComponentName(this, AdminReceiver::class.java)
      // Auto-grant READ_PHONE_STATE
      dpmInit.setPermissionGrantState(
        admin, packageName,
        android.Manifest.permission.READ_PHONE_STATE,
        DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED
      )
      // Ensure organizationId is set so getEnrollmentSpecificId() works
      AdminReceiver.ensureOrganizationId(this)
    }

    // Read managed config on cold start (AMAPI may have set it before app opened)
    if (latestManagedConfig.isEmpty()) {
      val rm = getSystemService(Context.RESTRICTIONS_SERVICE) as RestrictionsManager
      val bundle = rm.applicationRestrictions
      if (!bundle.isEmpty) {
        latestManagedConfig = bundle.keySet().associateWith { bundle.get(it)?.toString() ?: "" }
      }
    }

    setupMethodChannel(flutterEngine)
    setupEventChannel(flutterEngine)
  }

  override fun onResume() {
    super.onResume()
    isInForeground = true
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
      checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
    ) {
      requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 0)
    }
    requestOverlayPermissionIfNeeded()
  }

  // SYSTEM_ALERT_WINDOW (overlay) grants BAL exemption → startActivity() from background works
  private fun requestOverlayPermissionIfNeeded() {
    if (Settings.canDrawOverlays(this)) {
      Log.d(TAG, "overlay permission: already granted")
      return
    }
    Log.w(TAG, "overlay permission: NOT granted, opening settings")
    try {
      startActivity(
        Intent(
          Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
          Uri.parse("package:$packageName")
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      )
    } catch (e: Exception) {
      Log.e(TAG, "overlay permission: cannot open settings", e)
    }
  }

  override fun onPause() {
    super.onPause()
    isInForeground = false
  }

  override fun onStart() {
    super.onStart()
    startForegroundService(Intent(this, MdmForegroundService::class.java))
    Log.d(TAG, "onStart: MdmForegroundService started")
    val filter = IntentFilter(Intent.ACTION_APPLICATION_RESTRICTIONS_CHANGED)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      registerReceiver(managedConfigReceiver, filter, Context.RECEIVER_EXPORTED)
    } else {
      registerReceiver(managedConfigReceiver, filter)
    }
    Log.d(TAG, "onStart: dynamic ManagedConfigReceiver registered")
  }

  override fun onStop() {
    super.onStop()
    try { unregisterReceiver(managedConfigReceiver) } catch (_: Exception) {}
    Log.d(TAG, "onStop: dynamic ManagedConfigReceiver unregistered")
  }

  // Called when app is already running (singleTop) and a new Intent arrives
  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    val reason = intent.getStringExtra("launch_reason") ?: return
    launchReason = reason
    eventSink?.success(mapOf("event" to "launch_reason_changed", "reason" to reason))
  }

  private fun setupMethodChannel(flutterEngine: FlutterEngine) {
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "getLaunchReason" -> result.success(launchReason)

          "getManagedConfig" -> result.success(latestManagedConfig)

          "isDeviceOwner" -> {
            val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            result.success(dpm.isDeviceOwnerApp(packageName))
          }

          "isAdminActive" -> {
            val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            val admin = ComponentName(this, AdminReceiver::class.java)
            result.success(dpm.isAdminActive(admin))
          }

          "enterKiosk" -> {
            try { startLockTask(); result.success(true) }
            catch (e: Exception) { result.error("LOCK_TASK_FAILED", e.message, null) }
          }

          "exitKiosk" -> {
            try { stopLockTask(); result.success(true) }
            catch (e: Exception) { result.error("UNLOCK_TASK_FAILED", e.message, null) }
          }

          "getAppVersion" -> {
            val pInfo = packageManager.getPackageInfo(packageName, 0)
            result.success(mapOf(
              "versionName" to pInfo.versionName,
              "versionCode" to pInfo.longVersionCode.toString()
            ))
          }

          "getDeviceInfo" -> {
            val info = mutableMapOf<String, String>()

            info["androidId"] = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID) ?: "N/A"

            val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            val isOwner = dpm.isDeviceOwnerApp(packageName)
            Log.d(TAG, "getDeviceInfo: isDeviceOwner=$isOwner sdk=${Build.VERSION.SDK_INT}")
            info["enrollmentId"] = when {
              !isOwner -> "N/A (managed by AMAPI — use Managed Config)"
              Build.VERSION.SDK_INT < Build.VERSION_CODES.S -> "N/A (requires Android 12+)"
              else -> try {
                val id = dpm.enrollmentSpecificId
                id.ifEmpty { "N/A (empty)" }
              } catch (e: Exception) {
                Log.e(TAG, "getDeviceInfo: enrollmentSpecificId error", e)
                "N/A"
              }
            }

            info["imei"] = "N/A (restricted on Android 10+)"

            info["manufacturer"] = Build.MANUFACTURER
            info["model"] = Build.MODEL
            info["androidVersion"] = Build.VERSION.RELEASE
            info["sdkVersion"] = Build.VERSION.SDK_INT.toString()

            result.success(info)
          }

          "launchApp" -> {
            val pkg = call.argument<String>("packageName")
            if (pkg.isNullOrBlank()) {
              result.error("INVALID_ARG", "packageName required", null)
            } else {
              val launchIntent = packageManager.getLaunchIntentForPackage(pkg)
              if (launchIntent != null) {
                startActivity(launchIntent)
                result.success(true)
              } else {
                result.error("NOT_FOUND", "No launch intent for $pkg", null)
              }
            }
          }

          else -> result.notImplemented()
        }
      }
  }

  private fun setupEventChannel(flutterEngine: FlutterEngine) {
    EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
      .setStreamHandler(object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
          eventSink = events
          // Immediately emit current config if available
          if (latestManagedConfig.isNotEmpty()) {
            events.success(mapOf("event" to "managed_config_changed", "config" to latestManagedConfig))
          }
        }
        override fun onCancel(arguments: Any?) {
          eventSink = null
        }
      })
  }
}
