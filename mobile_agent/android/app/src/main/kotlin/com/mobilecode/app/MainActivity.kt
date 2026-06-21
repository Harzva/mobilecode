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
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

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
                    "getPhoneUseAccessibilityStatus" -> result.success(PhoneUseAccessibilityService.status(this))
                    "openPhoneUseAccessibilitySettings" -> result.success(openPhoneUseAccessibilitySettings())
                    "runPhoneUseDryProbe" -> result.success(PhoneUseAccessibilityService.dryProbe(this))
                    "performPhoneUseAction" -> {
                        @Suppress("UNCHECKED_CAST")
                        val action = call.argument<Map<String, Any?>>("action") ?: emptyMap()
                        result.success(PhoneUseAccessibilityService.performPhoneUseAction(this, action))
                    }
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
        val action = intent.action
        val scheme = intent.data?.scheme
        val isShareIntent = action == Intent.ACTION_SEND
        val isFileViewIntent = action == Intent.ACTION_VIEW &&
            (scheme == "content" || scheme == "file")
        if (isShareIntent || isFileViewIntent) {
            pendingSharedIntent = intent
        }
    }

    private fun consumePendingSharedFile(): Map<String, Any?>? {
        val sharedIntent = pendingSharedIntent ?: return null
        pendingSharedIntent = null
        val uri = sharedIntent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            ?: sharedIntent.data
        if (uri != null) return consumeSharedUri(sharedIntent, uri)
        return consumeSharedText(sharedIntent)
    }

    private fun consumeSharedUri(sharedIntent: Intent, uri: Uri): Map<String, Any?> {
        return try {
            val mimeType = contentResolver.getType(uri) ?: sharedIntent.type ?: ""
            val name = uri.lastPathSegment?.substringAfterLast('/') ?: "shared-file"
            val target = File(cacheDir, "shared_${System.currentTimeMillis()}_$name")
            val inputStream = contentResolver.openInputStream(uri)
                ?: throw IllegalStateException("No readable stream for shared URI")
            inputStream.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            }
            mapOf(
                "path" to target.absolutePath,
                "displayName" to name,
                "mimeType" to mimeType,
                "sizeBytes" to target.length(),
                "source" to "android_intent",
            )
        } catch (error: Exception) {
            sharedFileError(
                code = "read_failed",
                displayName = uri.lastPathSegment?.substringAfterLast('/') ?: "shared-file",
                source = "android_intent",
                detail = error.localizedMessage ?: error.javaClass.simpleName,
            )
        }
    }

    private fun consumeSharedText(sharedIntent: Intent): Map<String, Any?>? {
        val text = sharedIntent.getStringExtra(Intent.EXTRA_TEXT) ?: return null
        if (text.isBlank()) return null
        return try {
            val intentMimeType = sharedIntent.type ?: ""
            val html = isHtmlMime(intentMimeType) || looksHtml(text)
            val extension = if (html) "html" else "txt"
            val mimeType = if (html) "text/html" else "text/plain"
            val target = File(cacheDir, "shared_text_${System.currentTimeMillis()}.$extension")
            target.writeText(text, Charsets.UTF_8)
            mapOf(
                "path" to target.absolutePath,
                "displayName" to "shared-text.$extension",
                "mimeType" to mimeType,
                "sizeBytes" to target.length(),
                "source" to "android_extra_text",
            )
        } catch (error: Exception) {
            sharedFileError(
                code = "extra_text_failed",
                displayName = "shared-text.html",
                source = "android_extra_text",
                detail = error.localizedMessage ?: error.javaClass.simpleName,
            )
        }
    }

    private fun sharedFileError(
        code: String,
        displayName: String,
        source: String,
        detail: String,
    ): Map<String, Any?> = mapOf(
        "error" to code,
        "displayName" to displayName,
        "source" to source,
        "message" to "MobileCode cannot read shared $displayName. Grant file access and try again. $detail",
    )

    private fun isHtmlMime(mimeType: String): Boolean {
        val lower = mimeType.lowercase(Locale.ROOT)
        return lower == "text/html" || lower == "application/xhtml+xml"
    }

    private fun looksHtml(text: String): Boolean {
        val lower = text.trimStart().lowercase(Locale.ROOT)
        return lower.startsWith("<!doctype html") ||
            lower.startsWith("<html") ||
            lower.contains("<body")
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

    private fun openPhoneUseAccessibilitySettings(): Boolean {
        return try {
            val settingsIntent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(settingsIntent)
            true
        } catch (_: Exception) {
            false
        }
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
