package com.mdm.test

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.RestrictionsManager
import android.os.Bundle

class ManagedConfigReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action != Intent.ACTION_APPLICATION_RESTRICTIONS_CHANGED) return

    val rm = context.getSystemService(Context.RESTRICTIONS_SERVICE) as RestrictionsManager
    val config = bundleToMap(rm.applicationRestrictions)

    // Store so MainActivity can read on cold start
    MainActivity.latestManagedConfig = config

    // Push to Flutter if EventChannel is active (app in foreground)
    MainActivity.eventSink?.success(
      mapOf("event" to "managed_config_changed", "config" to config)
    )

    // Bring app to front (singleTop — won't create new instance if already running)
    val launch = Intent(context, MainActivity::class.java).apply {
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
      putExtra("launch_reason", "managed_config")
    }
    context.startActivity(launch)
  }

  private fun bundleToMap(bundle: Bundle): Map<String, String> =
    bundle.keySet().associateWith { bundle.get(it)?.toString() ?: "" }
}
