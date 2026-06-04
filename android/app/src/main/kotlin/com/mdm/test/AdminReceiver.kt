package com.mdm.test

import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.Context
import android.content.Intent
import android.os.Build

class AdminReceiver : DeviceAdminReceiver() {

  // Called after QR / NFC / Zero Touch fully managed device provisioning completes
  override fun onProfileProvisioningComplete(context: Context, intent: Intent) {
    ensureOrganizationId(context)
  }

  companion object {
    fun ensureOrganizationId(context: Context) {
      if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
      val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
      if (!dpm.isDeviceOwnerApp(context.packageName)) {
        android.util.Log.w(TAG, "ensureOrganizationId: not device owner, skip")
        return
      }
      try {
        dpm.setOrganizationId(context.packageName)
        android.util.Log.d(TAG, "ensureOrganizationId: set to '${context.packageName}'")
      } catch (e: IllegalStateException) {
        android.util.Log.d(TAG, "ensureOrganizationId: already set — ${e.message}")
      } catch (e: Exception) {
        android.util.Log.e(TAG, "ensureOrganizationId: error", e)
      }
    }

    const val TAG = "MdmSandbox"
  }
}
