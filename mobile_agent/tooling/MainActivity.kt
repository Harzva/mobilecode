package com.mobilecode.mobile_agent

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Debug
import android.os.Environment
import android.os.PowerManager
import android.os.StatFs
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var lastCpuTotal: Long? = null
    private var lastCpuIdle: Long? = null

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
                "getDeviceTelemetry" -> {
                    result.success(deviceTelemetry())
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

    private fun deviceTelemetry(): Map<String, Any> {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)

        val debugMemoryInfo = Debug.MemoryInfo()
        Debug.getMemoryInfo(debugMemoryInfo)
        val runtime = Runtime.getRuntime()
        val dataStat = StatFs(Environment.getDataDirectory().path)
        val battery = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val batteryLevel = batteryLevel(battery)
        val batteryStatus = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val charging = batteryStatus == BatteryManager.BATTERY_STATUS_CHARGING ||
            batteryStatus == BatteryManager.BATTERY_STATUS_FULL
        val batteryTemp = (battery?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) ?: 0) / 10.0
        val thermalStatus = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            (getSystemService(Context.POWER_SERVICE) as PowerManager).currentThermalStatus
        } else {
            -1
        }

        return mapOf(
            "platform" to "android",
            "manufacturer" to Build.MANUFACTURER.orEmpty(),
            "brand" to Build.BRAND.orEmpty(),
            "model" to Build.MODEL.orEmpty(),
            "androidVersion" to Build.VERSION.RELEASE.orEmpty(),
            "sdkInt" to Build.VERSION.SDK_INT,
            "abis" to Build.SUPPORTED_ABIS.toList(),
            "cpuCores" to runtime.availableProcessors(),
            "cpuUsagePercent" to sampleCpuUsagePercent(),
            "totalMemoryMb" to mb(memoryInfo.totalMem),
            "availableMemoryMb" to mb(memoryInfo.availMem),
            "lowMemory" to memoryInfo.lowMemory,
            "appRssMb" to debugMemoryInfo.totalPss / 1024,
            "appHeapMb" to mb(runtime.totalMemory() - runtime.freeMemory()),
            "storageTotalMb" to mb(dataStat.totalBytes),
            "storageFreeMb" to mb(dataStat.availableBytes),
            "batteryLevel" to batteryLevel,
            "batteryCharging" to charging,
            "batteryTemperatureC" to batteryTemp,
            "thermalStatus" to thermalStatus,
            "timestamp" to System.currentTimeMillis(),
            "fallback" to false
        )
    }

    private fun batteryLevel(intent: Intent?): Int {
        val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        if (level < 0 || scale <= 0) return -1
        return ((level * 100.0) / scale).toInt()
    }

    private fun mb(bytes: Long): Long = bytes / (1024L * 1024L)

    private fun sampleCpuUsagePercent(): Double {
        val sample = readCpuStat() ?: return 0.0
        val previousTotal = lastCpuTotal
        val previousIdle = lastCpuIdle
        lastCpuTotal = sample.first
        lastCpuIdle = sample.second
        if (previousTotal == null || previousIdle == null) return 0.0
        val totalDelta = sample.first - previousTotal
        val idleDelta = sample.second - previousIdle
        if (totalDelta <= 0) return 0.0
        val busy = (totalDelta - idleDelta).coerceAtLeast(0)
        return (busy * 100.0 / totalDelta).coerceIn(0.0, 100.0)
    }

    private fun readCpuStat(): Pair<Long, Long>? {
        return try {
            val firstLine = File("/proc/stat").bufferedReader().use { it.readLine() } ?: return null
            val parts = firstLine.trim().split(Regex("\\s+"))
            if (parts.isEmpty() || parts.first() != "cpu") return null
            val values = parts.drop(1).mapNotNull { it.toLongOrNull() }
            if (values.size < 5) return null
            val idle = values[3] + values[4]
            val total = values.sum()
            Pair(total, idle)
        } catch (_: Throwable) {
            null
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
