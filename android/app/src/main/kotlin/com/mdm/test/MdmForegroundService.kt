package com.mdm.test

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.util.Log

class MdmForegroundService : Service() {

  private val managedConfigReceiver = ManagedConfigReceiver()

  override fun onCreate() {
    super.onCreate()
    val filter = IntentFilter(Intent.ACTION_APPLICATION_RESTRICTIONS_CHANGED)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      registerReceiver(managedConfigReceiver, filter, RECEIVER_EXPORTED)
    } else {
      registerReceiver(managedConfigReceiver, filter)
    }
    Log.d(TAG, "onCreate: dynamic ManagedConfigReceiver registered")
  }

  override fun onDestroy() {
    super.onDestroy()
    try { unregisterReceiver(managedConfigReceiver) } catch (_: Exception) {}
    Log.d(TAG, "onDestroy: dynamic ManagedConfigReceiver unregistered")
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    startForeground(NOTIF_ID, buildNotification())

    val action = intent?.getStringExtra("action")
    val pkg = intent?.getStringExtra("target_package")
    Log.d(TAG, "onStartCommand: action=$action pkg=$pkg canOverlay=${Settings.canDrawOverlays(this)}")

    when (action) {
      "launch_app" -> if (!pkg.isNullOrBlank()) doLaunchPackage(pkg) else doBringToFront()
      "bring_to_front" -> doBringToFront()
      // null = START_STICKY restart — stay alive, do nothing
    }

    return START_STICKY
  }

  private fun doLaunchPackage(pkg: String) {
    val launchIntent = packageManager.getLaunchIntentForPackage(pkg)?.apply {
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    if (launchIntent == null) {
      Log.w(TAG, "doLaunchPackage: no launch intent for $pkg")
      return
    }

    if (Settings.canDrawOverlays(this)) {
      // SYSTEM_ALERT_WINDOW grants BAL exemption — direct startActivity works
      startActivity(launchIntent)
      Log.d(TAG, "doLaunchPackage: started $pkg directly (overlay)")
    } else {
      // Fallback: notification with PendingIntent
      val pi = PendingIntent.getActivity(
        this, 0, launchIntent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
      )
      showCommandNotification("MDM: Open App", pkg, pi)
      Log.d(TAG, "doLaunchPackage: notification shown for $pkg (no overlay permission)")
    }
  }

  private fun doBringToFront() {
    val selfIntent = Intent(this, MainActivity::class.java).apply {
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
      putExtra("launch_reason", "managed_config")
    }

    if (Settings.canDrawOverlays(this)) {
      startActivity(selfIntent)
      Log.d(TAG, "doBringToFront: started directly (overlay)")
    } else {
      val pi = PendingIntent.getActivity(
        this, 1, selfIntent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
      )
      showCommandNotification("MDM: Open MDM Sandbox", "Tap to open", pi)
      Log.d(TAG, "doBringToFront: notification shown (no overlay permission)")
    }
  }

  private fun showCommandNotification(title: String, text: String, pendingIntent: PendingIntent) {
    val nm = getSystemService(NotificationManager::class.java)
    nm.createNotificationChannel(
      NotificationChannel(NOTIF_CMD_CHANNEL, "MDM Commands", NotificationManager.IMPORTANCE_HIGH)
    )
    nm.notify(
      NOTIF_CMD_ID,
      Notification.Builder(this, NOTIF_CMD_CHANNEL)
        .setContentTitle(title)
        .setContentText(text)
        .setSmallIcon(android.R.drawable.ic_dialog_info)
        .setContentIntent(pendingIntent)
        .setFullScreenIntent(pendingIntent, true)
        .setCategory(Notification.CATEGORY_CALL)
        .setAutoCancel(true)
        .build()
    )
  }

  private fun buildNotification(): Notification {
    getSystemService(NotificationManager::class.java).createNotificationChannel(
      NotificationChannel(NOTIF_CHANNEL, "MDM Agent", NotificationManager.IMPORTANCE_MIN)
    )
    return Notification.Builder(this, NOTIF_CHANNEL)
      .setContentTitle("MDM Agent")
      .setContentText("Listening for MDM commands")
      .setSmallIcon(android.R.drawable.ic_dialog_info)
      .build()
  }

  override fun onBind(intent: Intent?): IBinder? = null

  companion object {
    const val TAG = "MdmSandbox"
    const val NOTIF_CHANNEL = "mdm_agent"
    const val NOTIF_CMD_CHANNEL = "mdm_commands"
    const val NOTIF_ID = 1001
    const val NOTIF_CMD_ID = 1002
  }
}
