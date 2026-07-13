package com.mobilecode.app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.ComponentName
import android.content.Context
import android.graphics.Path
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.text.TextUtils
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.max
import kotlin.math.min

class PhoneUseAccessibilityService : AccessibilityService() {
    override fun onServiceConnected() {
        activeService = this
        connectedAtMillis = System.currentTimeMillis()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        eventCounter.incrementAndGet()
        lastEvent = mapOf(
            "eventType" to event.eventType,
            "packageName" to event.packageName.safeString(),
            "className" to event.className.safeString(),
            "eventTime" to event.eventTime,
        )
    }

    override fun onInterrupt() {
        lastInterruptAtMillis = System.currentTimeMillis()
    }

    override fun onDestroy() {
        if (activeService === this) {
            activeService = null
        }
        super.onDestroy()
    }

    private fun dryProbe(): Map<String, Any?> {
        val observation = observeActiveWindow()
        return mapOf(
            "status" to "passed",
            "probe" to "accessibility_observe_dry_probe",
            "observation" to observation,
            "supportedActions" to supportedActions,
            "countsAsExperiment" to false,
            "countsAsStrategyAblationResult" to false,
            "rawTextIncluded" to false,
            "redactionApplied" to true,
        )
    }

    private fun performPhoneUseAction(action: Map<String, Any?>): Map<String, Any?> {
        val actionType = action["type"].safeString()
        val accepted = when (actionType) {
            "observe_ui" -> true
            "global_back" -> performGlobalAction(GLOBAL_ACTION_BACK)
            "global_home" -> performGlobalAction(GLOBAL_ACTION_HOME)
            "tap" -> dispatchTap(
                doubleValue(action["x"], 0.0).toFloat(),
                doubleValue(action["y"], 0.0).toFloat(),
            )
            "swipe" -> dispatchSwipe(
                doubleValue(action["x1"], 0.0).toFloat(),
                doubleValue(action["y1"], 0.0).toFloat(),
                doubleValue(action["x2"], 0.0).toFloat(),
                doubleValue(action["y2"], 0.0).toFloat(),
                longValue(action["durationMs"], 250L),
            )
            "set_text" -> setFocusedText(action["text"].safeString())
            else -> false
        }
        val status = if (accepted) "passed" else "blocked"
        return mapOf(
            "status" to status,
            "requestedAction" to actionType,
            "accepted" to accepted,
            "failureKind" to if (accepted) null else "unsupported_or_unaccepted_phone_use_action",
            "observation" to observeActiveWindow(),
            "countsAsExperiment" to false,
            "countsAsStrategyAblationResult" to false,
            "rawTextIncluded" to false,
            "redactionApplied" to true,
        )
    }

    private fun observeActiveWindow(): Map<String, Any?> {
        val root = rootInActiveWindow
            ?: return mapOf(
                "canObserveActiveWindow" to false,
                "nodeCount" to 0,
                "clickableNodeCount" to 0,
                "editableNodeCount" to 0,
                "focusableNodeCount" to 0,
                "visibleNodeCount" to 0,
                "rootPackageName" to null,
                "rootClassName" to null,
                "lastEvent" to lastEvent,
                "eventCount" to eventCounter.get(),
            )
        val stats = NodeStats()
        traverse(root, stats, 0)
        return mapOf(
            "canObserveActiveWindow" to true,
            "nodeCount" to stats.nodeCount,
            "clickableNodeCount" to stats.clickableNodeCount,
            "editableNodeCount" to stats.editableNodeCount,
            "focusableNodeCount" to stats.focusableNodeCount,
            "visibleNodeCount" to stats.visibleNodeCount,
            "rootPackageName" to root.packageName.safeString(),
            "rootClassName" to root.className.safeString(),
            "lastEvent" to lastEvent,
            "eventCount" to eventCounter.get(),
            "connectedAtMillis" to connectedAtMillis,
            "lastInterruptAtMillis" to lastInterruptAtMillis,
        )
    }

    private fun traverse(node: AccessibilityNodeInfo, stats: NodeStats, depth: Int) {
        if (depth > maxTraversalDepth || stats.nodeCount >= maxTraversalNodes) return
        stats.nodeCount += 1
        if (node.isClickable) stats.clickableNodeCount += 1
        if (node.isEditable) stats.editableNodeCount += 1
        if (node.isFocusable) stats.focusableNodeCount += 1
        if (node.isVisibleToUser) stats.visibleNodeCount += 1
        val childCount = min(node.childCount, maxChildrenPerNode)
        for (index in 0 until childCount) {
            val child = node.getChild(index) ?: continue
            try {
                traverse(child, stats, depth + 1)
            } finally {
                child.recycle()
            }
        }
    }

    private fun dispatchTap(x: Float, y: Float): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val path = Path().apply { moveTo(x, y) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 50))
            .build()
        return dispatchGesture(gesture, null, null)
    }

    private fun dispatchSwipe(
        x1: Float,
        y1: Float,
        x2: Float,
        y2: Float,
        durationMs: Long,
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val duration = max(80L, min(durationMs, 5000L))
        val path = Path().apply {
            moveTo(x1, y1)
            lineTo(x2, y2)
        }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, duration))
            .build()
        return dispatchGesture(gesture, null, null)
    }

    private fun setFocusedText(text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val target = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: findEditable(root)
        if (target == null) return false
        val args = Bundle().apply {
            putCharSequence(
                AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                text.take(maxSetTextChars),
            )
        }
        return target.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    private fun findEditable(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (node.isEditable) return node
        val childCount = min(node.childCount, maxChildrenPerNode)
        for (index in 0 until childCount) {
            val child = node.getChild(index) ?: continue
            val found = findEditable(child)
            if (found != null) return found
            child.recycle()
        }
        return null
    }

    private data class NodeStats(
        var nodeCount: Int = 0,
        var clickableNodeCount: Int = 0,
        var editableNodeCount: Int = 0,
        var focusableNodeCount: Int = 0,
        var visibleNodeCount: Int = 0,
    )

    companion object {
        @Volatile
        private var activeService: PhoneUseAccessibilityService? = null

        @Volatile
        private var connectedAtMillis: Long = 0

        @Volatile
        private var lastInterruptAtMillis: Long = 0

        @Volatile
        private var lastEvent: Map<String, Any?> = emptyMap()

        private val eventCounter = AtomicInteger(0)
        private const val maxTraversalDepth = 12
        private const val maxTraversalNodes = 500
        private const val maxChildrenPerNode = 80
        private const val maxSetTextChars = 500

        private val supportedActions = listOf(
            "observe_ui",
            "global_back",
            "global_home",
            "tap",
            "swipe",
            "set_text",
        )

        fun status(context: Context): Map<String, Any?> {
            val enabled = isServiceEnabled(context)
            val serviceConnected = activeService != null
            return mapOf(
                "platform" to "android",
                "supported" to true,
                "serviceId" to serviceId(context),
                "accessibilityEnabled" to enabled,
                "serviceConnected" to serviceConnected,
                "canObserveActiveWindow" to (enabled && serviceConnected),
                "canPerformGestures" to (enabled && serviceConnected && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N),
                "canSetText" to (enabled && serviceConnected),
                "supportedActions" to supportedActions,
                "lastEvent" to lastEvent,
                "eventCount" to eventCounter.get(),
                "connectedAtMillis" to connectedAtMillis,
                "lastInterruptAtMillis" to lastInterruptAtMillis,
                "blockedReason" to blockedReason(enabled, serviceConnected),
                "countsAsExperiment" to false,
                "countsAsStrategyAblationResult" to false,
                "rawTextIncluded" to false,
                "redactionApplied" to true,
            )
        }

        fun dryProbe(context: Context): Map<String, Any?> {
            val enabled = isServiceEnabled(context)
            val service = activeService
            if (!enabled || service == null) {
                return status(context) + mapOf(
                    "status" to "blocked",
                    "probe" to "accessibility_observe_dry_probe",
                    "failureKind" to blockedReason(enabled, service != null),
                )
            }
            return status(context) + service.dryProbe()
        }

        fun performPhoneUseAction(context: Context, action: Map<String, Any?>): Map<String, Any?> {
            val enabled = isServiceEnabled(context)
            val service = activeService
            if (!enabled || service == null) {
                return status(context) + mapOf(
                    "status" to "blocked",
                    "requestedAction" to action["type"].safeString(),
                    "accepted" to false,
                    "failureKind" to blockedReason(enabled, service != null),
                )
            }
            return status(context) + service.performPhoneUseAction(action)
        }

        private fun blockedReason(enabled: Boolean, serviceConnected: Boolean): String? {
            if (!enabled) return "accessibility_permission_required"
            if (!serviceConnected) return "accessibility_service_not_connected"
            return null
        }

        private fun serviceId(context: Context): String {
            return ComponentName(context, PhoneUseAccessibilityService::class.java).flattenToString()
        }

        private fun isServiceEnabled(context: Context): Boolean {
            val resolver = context.contentResolver
            val accessibilityEnabled = Settings.Secure.getInt(
                resolver,
                Settings.Secure.ACCESSIBILITY_ENABLED,
                0,
            ) == 1
            if (!accessibilityEnabled) return false
            val enabledServices = Settings.Secure.getString(
                resolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
            ) ?: return false
            val expected = serviceId(context)
            val shortExpected = "${context.packageName}/.PhoneUseAccessibilityService"
            val splitter = TextUtils.SimpleStringSplitter(':')
            splitter.setString(enabledServices)
            while (splitter.hasNext()) {
                val enabledService = splitter.next()
                if (
                    enabledService.equals(expected, ignoreCase = true) ||
                    enabledService.equals(shortExpected, ignoreCase = true)
                ) {
                    return true
                }
            }
            return false
        }

    }
}

private fun Any?.safeString(): String {
    return this?.toString().orEmpty()
}

private fun doubleValue(value: Any?, fallback: Double): Double {
    return when (value) {
        is Number -> value.toDouble()
        is String -> value.toDoubleOrNull() ?: fallback
        else -> fallback
    }
}

private fun longValue(value: Any?, fallback: Long): Long {
    return when (value) {
        is Number -> value.toLong()
        is String -> value.toLongOrNull() ?: fallback
        else -> fallback
    }
}
