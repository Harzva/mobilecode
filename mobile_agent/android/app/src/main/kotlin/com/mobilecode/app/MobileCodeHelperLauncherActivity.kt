package com.mobilecode.app

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
            val serviceIntent = Intent(this, MobileCodeHelperService::class.java)
            val authToken = (
                intent.getStringExtra(EXTRA_SHELL_AUTH_TOKEN)
                    ?: intent.getStringExtra(MobileCodeHelperService.EXTRA_AUTH_TOKEN)
                )?.takeIf { it.isNotBlank() }
            authToken?.let {
                serviceIntent.putExtra(MobileCodeHelperService.EXTRA_AUTH_TOKEN, it)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
            Log.i(
                TAG,
                "MobileCode helper service start requested from launcher; " +
                    "authProvided=${authToken != null}; authLength=${authToken?.length ?: 0}"
            )
        } catch (error: Throwable) {
            Log.e(TAG, "Failed to request MobileCode helper service start from launcher", error)
        }
    }

    companion object {
        private const val TAG = "MobileCodeHelperLauncher"
        const val EXTRA_SHELL_AUTH_TOKEN = "mobilecode_helper_auth_token"
    }
}
