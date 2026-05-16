package com.mobilecode.mobile_agent

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log

class MobileCodeHelperLauncherActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startHelperService()
        finish()
        overridePendingTransition(0, 0)
    }

    private fun startHelperService() {
        try {
            val intent = Intent(this, MobileCodeHelperService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            Log.i(TAG, "MobileCode helper service start requested from launcher")
        } catch (error: Throwable) {
            Log.e(TAG, "Failed to request MobileCode helper service start from launcher", error)
        }
    }

    companion object {
        private const val TAG = "MobileCodeHelperLauncher"
    }
}
