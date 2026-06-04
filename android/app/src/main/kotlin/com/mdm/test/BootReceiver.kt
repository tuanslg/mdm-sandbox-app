package com.mdm.test

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    val action = intent.action ?: return
    if (action != Intent.ACTION_BOOT_COMPLETED && action != "android.intent.action.QUICKBOOT_POWERON") return

    // Start foreground service — it will bring app to front once running.
    // Direct startActivity() from boot receiver is blocked on Android 10+ without Device Owner.
    context.startForegroundService(
      Intent(context, MdmForegroundService::class.java).apply {
        putExtra("action", "bring_to_front")
      }
    )
  }
}
