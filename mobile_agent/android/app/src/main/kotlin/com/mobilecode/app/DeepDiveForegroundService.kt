package com.mobilecode.app

import android.app.Service
import android.content.Intent
import android.os.IBinder

class DeepDiveForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null
}
