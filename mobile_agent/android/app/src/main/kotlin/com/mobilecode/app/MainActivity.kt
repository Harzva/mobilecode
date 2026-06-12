package com.mobilecode.app

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingInitialDeepLink: String? = null
    private var pendingSharedIntent: Intent? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        captureIntent(intent)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mobilecode/system_tools")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumePendingSharedFile" -> result.success(consumePendingSharedFile())
                    "consumeInitialDeepLink" -> {
                        val value = pendingInitialDeepLink
                        pendingInitialDeepLink = null
                        result.success(value)
                    }
                    "getDeviceTelemetry" -> result.success(deviceTelemetry())
                    "isPackageInstalled" -> result.success(isPackageInstalled(call.argument<String>("packageName")))
                    "launchPackage" -> result.success(launchPackage(call.argument<String>("packageName")))
                    "startHelperService" -> result.success(false)
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mobile_coding/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getBuildTags" -> result.success(Build.TAGS ?: "")
                    "getInstallerPackage" -> result.success(installerPackage())
                    "isAppStoreBuild" -> result.success(false)
                    "verifySignature" -> result.success(true)
                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureIntent(intent)
    }

    private fun captureIntent(intent: Intent?) {
        if (intent == null) return
        intent.dataString?.let { pendingInitialDeepLink = it }
        if (intent.action == Intent.ACTION_SEND || intent.action == Intent.ACTION_VIEW) {
            pendingSharedIntent = intent
        }
    }

    private fun consumePendingSharedFile(): Map<String, Any?>? {
        val sharedIntent = pendingSharedIntent ?: return null
        pendingSharedIntent = null
        val uri = sharedIntent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            ?: sharedIntent.data
            ?: return null
        return try {
            val mimeType = contentResolver.getType(uri) ?: sharedIntent.type ?: ""
            val name = uri.lastPathSegment?.substringAfterLast('/') ?: "shared-file"
            val target = File(cacheDir, "shared_${System.currentTimeMillis()}_$name")
            contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            } ?: return null
            mapOf(
                "path" to target.absolutePath,
                "displayName" to name,
                "mimeType" to mimeType,
                "sizeBytes" to target.length(),
                "source" to "android_intent",
            )
        } catch (_: Exception) {
            null
        }
    }

    private fun isPackageInstalled(packageName: String?): Boolean {
        if (packageName.isNullOrBlank()) return false
        return try {
            packageManager.getPackageInfo(packageName, 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun launchPackage(packageName: String?): Boolean {
        if (packageName.isNullOrBlank()) return false
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName) ?: return false
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(launchIntent)
        return true
    }

    private fun installerPackage(): String? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            packageManager.getInstallSourceInfo(packageName).installingPackageName
        } else {
            @Suppress("DEPRECATION")
            packageManager.getInstallerPackageName(packageName)
        }
    }

    private fun deviceTelemetry(): Map<String, Any?> {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)
        val runtime = Runtime.getRuntime()
        val storage = StatFs(Environment.getDataDirectory().absolutePath)
        val battery = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val batteryLevel = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val batteryStatus = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val batteryTemp = (battery?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) ?: 0) / 10.0
        return mapOf(
            "platform" to "android",
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "androidVersion" to Build.VERSION.RELEASE,
            "sdkInt" to Build.VERSION.SDK_INT,
            "abis" to Build.SUPPORTED_ABIS.toList(),
            "cpuCores" to Runtime.getRuntime().availableProcessors(),
            "cpuUsagePercent" to 0.0,
            "totalMemoryMb" to memoryInfo.totalMem / 1024 / 1024,
            "availableMemoryMb" to memoryInfo.availMem / 1024 / 1024,
            "lowMemory" to memoryInfo.lowMemory,
            "appRssMb" to 0,
            "appHeapMb" to (runtime.totalMemory() - runtime.freeMemory()) / 1024 / 1024,
            "storageTotalMb" to storage.totalBytes / 1024 / 1024,
            "storageFreeMb" to storage.availableBytes / 1024 / 1024,
            "batteryLevel" to batteryLevel,
            "batteryCharging" to (
                batteryStatus == BatteryManager.BATTERY_STATUS_CHARGING ||
                    batteryStatus == BatteryManager.BATTERY_STATUS_FULL
                ),
            "batteryTemperatureC" to batteryTemp,
            "thermalStatus" to -1,
            "timestamp" to System.currentTimeMillis(),
            "fallback" to false,
        )
    }
}
