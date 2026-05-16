package com.mobilecode.mobile_agent

import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        maybeStartHelperFromIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        maybeStartHelperFromIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mobilecode/system_tools").setMethodCallHandler { call, result ->
            when (call.method) {
                "isPackageInstalled" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName.isNullOrBlank()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    result.success(isPackageInstalled(packageName))
                }
                "launchPackage" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName.isNullOrBlank()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val intent = packageManager.getLaunchIntentForPackage(packageName)
                    if (intent == null) {
                        result.success(false)
                    } else {
                        intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    }
                }
                "rootProbe" -> {
                    result.success(rootProbe())
                }
                "startHelperService" -> {
                    result.success(startHelperService())
                }
                "stopHelperService" -> {
                    stopService(Intent(this, MobileCodeHelperService::class.java).setAction(MobileCodeHelperService.ACTION_STOP))
                    result.success(true)
                }
                "helperServiceStatus" -> {
                    result.success(MobileCodeHelperService.status())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isPackageInstalled(packageName: String): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, 0)
            }
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun rootProbe(): Map<String, Any> {
        val knownPaths = listOf(
            "/system/bin/su",
            "/system/xbin/su",
            "/sbin/su",
            "/su/bin/su",
            "/data/adb/magisk/su",
            "/debug_ramdisk/su"
        )
        val existingPath = knownPaths.firstOrNull { File(it).exists() && File(it).canExecute() }
        if (existingPath != null) {
            return mapOf(
                "available" to true,
                "detail" to "su binary visible at $existingPath. Grant root when Android prompts."
            )
        }
        return try {
            val process = ProcessBuilder("which", "su")
                .redirectErrorStream(true)
                .start()
            val finished = process.waitFor(900, java.util.concurrent.TimeUnit.MILLISECONDS)
            val output = process.inputStream.bufferedReader().readText().trim()
            val ok = finished && process.exitValue() == 0 && output.isNotBlank()
            mapOf(
                "available" to ok,
                "detail" to if (ok) "su found at $output. Grant root when Android prompts." else "No executable su was found from the app process."
            )
        } catch (_: Throwable) {
            mapOf(
                "available" to false,
                "detail" to "Root probe failed; the app process cannot see su."
            )
        }
    }

    private fun startHelperService(): Boolean {
        return try {
            val intent = Intent(this, MobileCodeHelperService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            Log.i(TAG, "MobileCode helper service start requested")
            true
        } catch (error: Throwable) {
            Log.e(TAG, "Failed to request MobileCode helper service start", error)
            false
        }
    }

    private fun maybeStartHelperFromIntent(intent: Intent?) {
        if (intent?.getBooleanExtra(EXTRA_START_HELPER, false) == true) {
            Log.i(TAG, "mobilecode_start_helper intent received")
            startHelperService()
        }
    }

    companion object {
        private const val TAG = "MobileCodeMain"
        private const val EXTRA_START_HELPER = "mobilecode_start_helper"
    }
}
