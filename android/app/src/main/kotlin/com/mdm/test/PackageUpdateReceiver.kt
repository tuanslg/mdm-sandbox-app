package com.mdm.test

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class PackageUpdateReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
    // startActivity() is BAL-blocked on Android 10+ from static receivers — use service instead
    context.startForegroundService(
      Intent(context, MdmForegroundService::class.java).apply {
        putExtra("action", "bring_to_front")
      }
    )
  }
}
