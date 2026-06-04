package com.mdm.test

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.RestrictionsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  companion object {
    var eventSink: EventChannel.EventSink? = null
    var latestManagedConfig: Map<String, String> = emptyMap()
  }

  private val METHOD_CHANNEL = "com.mdm.test/kiosk"
  private val EVENT_CHANNEL = "com.mdm.test/events"

  private var launchReason = "manual"

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    launchReason = intent?.getStringExtra("launch_reason") ?: "manual"

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
