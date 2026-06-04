package com.mdm.test

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.RestrictionsManager
import android.os.Bundle
import android.util.Log

class ManagedConfigReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    Log.d(TAG, "onReceive: action=${intent.action}")
    if (intent.action != Intent.ACTION_APPLICATION_RESTRICTIONS_CHANGED) return

    val rm = context.getSystemService(Context.RESTRICTIONS_SERVICE) as RestrictionsManager
    val config = bundleToMap(rm.applicationRestrictions)
    Log.d(TAG, "onReceive: config keys=${config.keys}")

    // Dedup: both static and dynamic receivers may fire for the same event
    val commandId = config["commandId"]
    if (commandId != null && commandId == lastCommandId) {
      Log.d(TAG, "onReceive: duplicate commandId=$commandId, skipping")
      return
    }
    if (commandId != null) lastCommandId = commandId

    MainActivity.latestManagedConfig = config

    val action = config["action"]

    // App in foreground — Flutter can call startActivity() from visible Activity context
    if (MainActivity.isInForeground && MainActivity.eventSink != null) {
      MainActivity.eventSink?.success(
        mapOf("event" to "mdm_command", "action" to (action ?: "managed_config"), "config" to config)
      )
      Log.d(TAG, "onReceive: dispatched to Flutter via eventSink, action=$action")
      return
    }

    // App in background — startActivity() blocked on Android 12+, use notification instead
    Log.w(TAG, "onReceive: app in background, delegating to MdmForegroundService, action=$action")
    val serviceIntent = Intent(context, MdmForegroundService::class.java).apply {
      putExtra("action", action ?: "bring_to_front")
      config["target_package"]?.let { putExtra("target_package", it) }
    }
    context.startForegroundService(serviceIntent)
  }

  private fun bundleToMap(bundle: Bundle): Map<String, String> =
    bundle.keySet().associateWith { bundle.get(it)?.toString() ?: "" }

  companion object {
    const val TAG = "MdmSandbox"
    var lastCommandId: String = ""
  }
}
