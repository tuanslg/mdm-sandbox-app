package com.mdm.test

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class PackageUpdateReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
      val launch = Intent(context, MainActivity::class.java).apply {
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        putExtra("launch_reason", "app_updated")
      }
      context.startActivity(launch)
    }
  }
}
