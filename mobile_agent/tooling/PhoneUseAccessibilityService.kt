package com.mobilecode.app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.app.ActivityManager
import android.content.ComponentName
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.text.TextUtils
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Embedded, user-authorized phone automation backend.
 *
 * The service exposes a bounded semantic snapshot rather than the raw
 * accessibility tree. Snapshot refs are valid for one active frame only and
 * are expired immediately before any operation that may change visible UI.
 */
class PhoneUseAccessibilityService : AccessibilityService() {
    override fun onServiceConnected() {
        activeService = this
        connectedAtMillis = System.currentTimeMillis()
        lastInterruptAtMillis = 0L
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        eventCounter.incrementAndGet()
        lastEventAtMillis = event.eventTime
        lastEvent = mapOf(
            "eventType" to event.eventType,
            "packageNameHash" to shortHash(event.packageName.safeString()),
            "className" to safeClassName(event.className.safeString()),
            "eventTime" to event.eventTime,
        )
        if (event.eventType and refInvalidatingEventMask != 0) {
            expireRefFrame("accessibility_event:${event.eventType}")
        }
    }

    override fun onInterrupt() {
        lastInterruptAtMillis = System.currentTimeMillis()
    }

    override fun onDestroy() {
        synchronized(frameLock) {
            refFrame = null
        }
        if (activeService === this) activeService = null
        super.onDestroy()
    }

    private fun dryProbe(): Map<String, Any?> {
        val snapshot = captureSemanticSnapshot(activateFrame = true, includeNodes = true)
        return mapOf(
            "status" to if (snapshot["canObserveActiveWindow"] == true) "passed" else "blocked",
            "probe" to "accessibility_semantic_snapshot_dry_probe",
            "observation" to snapshot,
            "snapshot" to snapshot,
            "supportedActions" to supportedActions,
            "countsAsExperiment" to false,
            "countsAsStrategyAblationResult" to false,
            "rawTextIncluded" to false,
            "redactionApplied" to true,
        )
    }

    private fun performPhoneUseAction(action: Map<String, Any?>): Map<String, Any?> {
        val actionType = action["type"].safeString()
        if (actionType == "observe_ui" || actionType == "semantic_snapshot") {
            val snapshot = captureSemanticSnapshot(activateFrame = true, includeNodes = true)
            val accepted = snapshot["canObserveActiveWindow"] == true
            return actionResult(
                actionType = actionType,
                accepted = accepted,
                failureKind = if (accepted) null else "active_window_unavailable",
                resolution = mapOf("kind" to "semantic_snapshot", "source" to "accessibility_tree"),
                preDigest = null,
                postSnapshot = snapshot,
                approved = action["approved"] == true,
            ) + mapOf("observation" to snapshot, "snapshot" to snapshot)
        }
        if (actionType == "risk_preview") {
            return previewActionRisk(action)
        }
        if (action["approved"] != true) {
            val snapshot = captureSemanticSnapshot(activateFrame = false, includeNodes = false)
            return actionResult(
                actionType = actionType,
                accepted = false,
                failureKind = "approval_required",
                resolution = mapOf("kind" to "approval_gate"),
                preDigest = currentFrameSummary()?.get("digest") as? String,
                postSnapshot = snapshot,
                approved = false,
            )
        }

        val preconditionDigest = action["preconditionSnapshotDigest"].safeString()
        if (preconditionDigest.isNotEmpty()) {
            val frame = synchronized(frameLock) { refFrame }
            val currentSnapshot = captureSemanticSnapshot(activateFrame = false, includeNodes = false)
            val currentDigest = currentSnapshot["digest"].safeString()
            if (
                frame == null ||
                frame.state != "active" ||
                frame.digest != preconditionDigest ||
                currentDigest != preconditionDigest
            ) {
                return actionResult(
                    actionType = actionType,
                    accepted = false,
                    failureKind = "approval_preview_expired",
                    resolution = mapOf(
                        "kind" to "approval_precondition",
                        "frameState" to (frame?.state ?: "missing"),
                        "digestMatched" to false,
                    ),
                    preDigest = frame?.digest,
                    postSnapshot = currentSnapshot,
                    approved = true,
                )
            }
        }

        val preFrame = currentFrameSummary()
        var failureKind: String? = null
        var resolution: Map<String, Any?> = mapOf("kind" to "none")
        val accepted = when (actionType) {
            "global_back" -> {
                expireRefFrame("global_back")
                resolution = mapOf("kind" to "global_action")
                performGlobalAction(GLOBAL_ACTION_BACK)
            }
            "global_home" -> {
                expireRefFrame("global_home")
                resolution = mapOf("kind" to "global_action")
                performGlobalAction(GLOBAL_ACTION_HOME)
            }
            "tap" -> {
                val x = doubleValue(action["x"], Double.NaN).toFloat()
                val y = doubleValue(action["y"], Double.NaN).toFloat()
                if (!x.isFinite() || !y.isFinite()) {
                    failureKind = "invalid_coordinates"
                    false
                } else {
                    expireRefFrame("tap")
                    resolution = coordinateResolution(x, y)
                    dispatchTap(x, y)
                }
            }
            "tap_ref" -> {
                val admission = admitRef(action["ref"].safeString())
                if (admission.failureKind != null) {
                    failureKind = admission.failureKind
                    resolution = admission.resolution
                    false
                } else {
                    val target = findCurrentNode(admission.descriptor!!)
                    if (target == null) {
                        failureKind = "ref_target_changed"
                        resolution = admission.resolution + mapOf("currentIdentityMatched" to false)
                        false
                    } else {
                        try {
                            expireRefFrame("tap_ref")
                            resolution = admission.resolution + mapOf("currentIdentityMatched" to true)
                            target.performAction(AccessibilityNodeInfo.ACTION_CLICK) ||
                                dispatchTap(
                                    admission.descriptor.bounds.exactCenterX().toFloat(),
                                    admission.descriptor.bounds.exactCenterY().toFloat(),
                                )
                        } finally {
                            target.recycle()
                        }
                    }
                }
            }
            "swipe" -> {
                val x1 = doubleValue(action["x1"], Double.NaN).toFloat()
                val y1 = doubleValue(action["y1"], Double.NaN).toFloat()
                val x2 = doubleValue(action["x2"], Double.NaN).toFloat()
                val y2 = doubleValue(action["y2"], Double.NaN).toFloat()
                if (listOf(x1, y1, x2, y2).any { !it.isFinite() }) {
                    failureKind = "invalid_coordinates"
                    false
                } else {
                    expireRefFrame("swipe")
                    resolution = mapOf(
                        "kind" to "coordinate",
                        "coordinateContract" to coordinateContract(),
                    )
                    dispatchSwipe(x1, y1, x2, y2, longValue(action["durationMs"], 250L))
                }
            }
            "set_text" -> {
                val root = rootInActiveWindow
                val target = try {
                    findEditable(root)
                } finally {
                    root?.recycle()
                }
                if (target == null) {
                    failureKind = "editable_target_unavailable"
                    false
                } else {
                    try {
                        expireRefFrame("set_text")
                        resolution = mapOf("kind" to "focused_or_first_editable")
                        setNodeText(target, action["text"].safeString())
                    } finally {
                        target.recycle()
                    }
                }
            }
            "set_text_ref" -> {
                val admission = admitRef(action["ref"].safeString())
                if (admission.failureKind != null) {
                    failureKind = admission.failureKind
                    resolution = admission.resolution
                    false
                } else if (admission.descriptor?.editable != true) {
                    failureKind = "ref_not_editable"
                    resolution = admission.resolution
                    false
                } else {
                    val target = findCurrentNode(admission.descriptor)
                    if (target == null) {
                        failureKind = "ref_target_changed"
                        resolution = admission.resolution + mapOf("currentIdentityMatched" to false)
                        false
                    } else {
                        try {
                            expireRefFrame("set_text_ref")
                            resolution = admission.resolution + mapOf("currentIdentityMatched" to true)
                            setNodeText(target, action["text"].safeString())
                        } finally {
                            target.recycle()
                        }
                    }
                }
            }
            else -> {
                failureKind = "unsupported_phone_use_action"
                false
            }
        }

        if (!accepted && failureKind == null) failureKind = "phone_use_action_not_accepted"
        val postSnapshot = captureSemanticSnapshot(activateFrame = false, includeNodes = false)
        return actionResult(
            actionType = actionType,
            accepted = accepted,
            failureKind = failureKind,
            resolution = resolution,
            preDigest = preFrame?.get("digest") as? String,
            postSnapshot = postSnapshot,
            approved = action["approved"] == true,
        ) + mapOf("preSnapshot" to preFrame, "postSnapshot" to postSnapshot)
    }

    private fun previewActionRisk(action: Map<String, Any?>): Map<String, Any?> {
        val requestedAction = action["requestedAction"].safeString()
        val currentSnapshot = captureSemanticSnapshot(activateFrame = false, includeNodes = false)
        val frame = synchronized(frameLock) { refFrame }
        if (
            frame == null ||
            frame.state != "active" ||
            System.currentTimeMillis() - frame.createdAtMillis > refTtlMillis ||
            currentSnapshot["digest"].safeString() != frame.digest
        ) {
            if (frame != null && System.currentTimeMillis() - frame.createdAtMillis > refTtlMillis) {
                expireRefFrame("ttl_expired")
            }
            return mapOf(
                "status" to "blocked",
                "accepted" to false,
                "requestedAction" to requestedAction,
                "failureKind" to "risk_preview_surface_unavailable",
                "refFrame" to currentFrameSummary(),
                "riskAssessment" to mapOf(
                    "trusted" to true,
                    "policyId" to transactionRiskPolicyId,
                    "reason" to "active_semantic_frame_required",
                ),
                "rawTextIncluded" to false,
                "redactionApplied" to true,
            )
        }

        var descriptor: SemanticNode? = null
        var resolution: Map<String, Any?> = mapOf("kind" to "active_frame")
        if (requestedAction == "tap_ref" || requestedAction == "set_text_ref") {
            val admission = admitRef(action["ref"].safeString())
            if (admission.failureKind != null) {
                return mapOf(
                    "status" to "blocked",
                    "accepted" to false,
                    "requestedAction" to requestedAction,
                    "failureKind" to admission.failureKind,
                    "resolution" to admission.resolution,
                    "refFrame" to currentFrameSummary(),
                    "riskAssessment" to mapOf(
                        "trusted" to true,
                        "policyId" to transactionRiskPolicyId,
                        "reason" to "semantic_ref_not_admitted",
                    ),
                    "rawTextIncluded" to false,
                    "redactionApplied" to true,
                )
            }
            descriptor = admission.descriptor
            resolution = admission.resolution
        }

        val targetLabel = descriptor?.label.orEmpty()
        val normalizedLabel = targetLabel.lowercase()
        val riskClass: String
        val reason: String
        when {
            requestedAction == "tap" -> {
                riskClass = "externalTransaction"
                reason = "coordinate_target_unverifiable"
            }
            requestedAction == "tap_ref" && targetLabel.isBlank() -> {
                riskClass = "externalTransaction"
                reason = "unlabeled_click_target"
            }
            requestedAction == "tap_ref" && descriptor?.password == true -> {
                riskClass = "externalTransaction"
                reason = "sensitive_click_target"
            }
            requestedAction == "tap_ref" && transactionRiskPattern.containsMatchIn(normalizedLabel) -> {
                riskClass = "externalTransaction"
                reason = "trusted_policy_high_impact_label"
            }
            else -> {
                riskClass = "reversible"
                reason = "trusted_policy_reversible_action"
            }
        }
        val previewCanonical = listOf(
            transactionRiskPolicyId,
            frame.digest,
            requestedAction,
            descriptor?.identityHash.orEmpty(),
            riskClass,
        ).joinToString("|")
        val previewDigest = fullSha256(previewCanonical.toByteArray(Charsets.UTF_8))
        return mapOf(
            "status" to "passed",
            "accepted" to true,
            "requestedAction" to requestedAction,
            "resolution" to resolution,
            "refFrame" to currentFrameSummary(),
            "currentPackageNameHash" to currentSnapshot["rootPackageNameHash"],
            "currentClassName" to currentSnapshot["rootClassName"],
            "riskAssessment" to mapOf(
                "trusted" to true,
                "policyId" to transactionRiskPolicyId,
                "riskClass" to riskClass,
                "reason" to reason,
                "targetLabel" to if (targetLabel.isBlank()) "<unlabeled>" else targetLabel,
                "targetLabelHash" to descriptor?.labelHash,
                "targetIdentityHash" to descriptor?.identityHash,
                "frameDigest" to frame.digest,
                "previewDigest" to previewDigest,
            ),
            "device" to deviceMetadata(),
            "rawTextIncluded" to false,
            "redactionApplied" to true,
        )
    }

    private fun actionResult(
        actionType: String,
        accepted: Boolean,
        failureKind: String?,
        resolution: Map<String, Any?>,
        preDigest: String?,
        postSnapshot: Map<String, Any?>,
        approved: Boolean,
    ): Map<String, Any?> = mapOf(
        "status" to if (accepted) "passed" else "blocked",
        "requestedAction" to actionType,
        "accepted" to accepted,
        "failureKind" to failureKind,
        "resolution" to resolution,
        "preSnapshotDigest" to preDigest,
        "postSnapshotDigest" to postSnapshot["digest"],
        "currentPackageNameHash" to postSnapshot["rootPackageNameHash"],
        "currentClassName" to postSnapshot["rootClassName"],
        "refFrame" to currentFrameSummary(),
        "approval" to mapOf(
            "required" to (actionType != "observe_ui" && actionType != "semantic_snapshot"),
            "granted" to approved,
            "enforcedBy" to "device_automation_coordinator",
        ),
        "device" to deviceMetadata(),
        "countsAsExperiment" to false,
        "countsAsStrategyAblationResult" to false,
        "rawTextIncluded" to false,
        "redactionApplied" to true,
    )

    private fun captureSemanticSnapshot(
        activateFrame: Boolean,
        includeNodes: Boolean,
    ): Map<String, Any?> {
        val root = rootInActiveWindow
            ?: return emptySnapshot("active_window_unavailable")
        return try {
            val stats = NodeStats()
            val descriptors = mutableListOf<SemanticNode>()
            traverse(root, stats, descriptors, 0)
            val digest = snapshotDigest(descriptors, root.packageName.safeString(), root.className.safeString())

            val frame = if (activateFrame) {
                val generation = generationCounter.incrementAndGet()
                RefFrame(
                    generation = generation,
                    state = "active",
                    createdAtMillis = System.currentTimeMillis(),
                    digest = digest,
                    nodes = descriptors.associateBy { it.ref },
                    expiredReason = null,
                ).also { synchronized(frameLock) { refFrame = it } }
            } else {
                synchronized(frameLock) { refFrame }
            }

            mapOf(
                "canObserveActiveWindow" to true,
                "frameId" to frame?.let { "s${it.generation}" },
                "refsGeneration" to frame?.generation,
                "frameState" to (frame?.state ?: "none"),
                "frameExpiredReason" to frame?.expiredReason,
                "digest" to digest,
                "captureMode" to "accessibility_tree",
                "interactiveNodes" to if (includeNodes) descriptors.map { it.toMap() } else emptyList<Map<String, Any?>>(),
                "interactiveNodeCount" to descriptors.size,
                "nodeCount" to stats.nodeCount,
                "clickableNodeCount" to stats.clickableNodeCount,
                "editableNodeCount" to stats.editableNodeCount,
                "focusableNodeCount" to stats.focusableNodeCount,
                "visibleNodeCount" to stats.visibleNodeCount,
                "truncated" to stats.truncated,
                "rootPackageNameHash" to shortHash(root.packageName.safeString()),
                "rootClassName" to safeClassName(root.className.safeString()),
                "coordinateContract" to coordinateContract(),
                "screenshotFallbackRecommended" to (descriptors.size < sparseInteractiveNodeThreshold),
                "lastEvent" to lastEvent,
                "eventCount" to eventCounter.get(),
                "capturedAtMillis" to System.currentTimeMillis(),
                "rawTextIncluded" to false,
                "redactionApplied" to true,
            )
        } finally {
            root.recycle()
        }
    }

    private fun emptySnapshot(reason: String): Map<String, Any?> = mapOf(
        "canObserveActiveWindow" to false,
        "failureKind" to reason,
        "frameId" to null,
        "refsGeneration" to null,
        "frameState" to "none",
        "digest" to null,
        "captureMode" to "accessibility_tree",
        "interactiveNodes" to emptyList<Map<String, Any?>>(),
        "interactiveNodeCount" to 0,
        "nodeCount" to 0,
        "coordinateContract" to coordinateContract(),
        "screenshotFallbackRecommended" to true,
        "lastEvent" to lastEvent,
        "eventCount" to eventCounter.get(),
        "rawTextIncluded" to false,
        "redactionApplied" to true,
    )

    private fun traverse(
        node: AccessibilityNodeInfo,
        stats: NodeStats,
        descriptors: MutableList<SemanticNode>,
        depth: Int,
    ) {
        if (depth > maxTraversalDepth || stats.nodeCount >= maxTraversalNodes) {
            stats.truncated = true
            return
        }
        stats.nodeCount += 1
        if (node.isClickable) stats.clickableNodeCount += 1
        if (node.isEditable) stats.editableNodeCount += 1
        if (node.isFocusable) stats.focusableNodeCount += 1
        if (node.isVisibleToUser) stats.visibleNodeCount += 1
        if (
            node.isVisibleToUser &&
            descriptors.size < maxInteractiveNodes &&
            isInteractive(node)
        ) {
            descriptors += semanticNode(node, "@e${descriptors.size + 1}")
        } else if (descriptors.size >= maxInteractiveNodes) {
            stats.truncated = true
        }

        val childCount = min(node.childCount, maxChildrenPerNode)
        for (index in 0 until childCount) {
            val child = node.getChild(index) ?: continue
            try {
                traverse(child, stats, descriptors, depth + 1)
            } finally {
                child.recycle()
            }
        }
        if (node.childCount > maxChildrenPerNode) stats.truncated = true
    }

    private fun isInteractive(node: AccessibilityNodeInfo): Boolean =
        node.isClickable || node.isEditable || node.isFocusable || node.isScrollable ||
            node.isLongClickable || node.isCheckable

    private fun semanticNode(node: AccessibilityNodeInfo, ref: String): SemanticNode {
        val bounds = Rect().also(node::getBoundsInScreen)
        val role = safeClassName(node.className.safeString())
        val label = sanitizedLabel(node)
        val resourceIdHash = shortHash(node.viewIdResourceName.safeString())
        val actions = buildList {
            if (node.isClickable) add("click")
            if (node.isEditable) add("set_text")
            if (node.isScrollable) add("scroll")
            if (node.isLongClickable) add("long_click")
            if (node.isCheckable) add("toggle")
        }
        return SemanticNode(
            ref = ref,
            role = role,
            label = label,
            labelHash = shortHash(label),
            resourceIdHash = resourceIdHash,
            identityHash = identityHash(role, label, resourceIdHash, bounds),
            bounds = bounds,
            clickable = node.isClickable,
            editable = node.isEditable,
            enabled = node.isEnabled,
            password = node.isPassword,
            actions = actions,
        )
    }

    private fun sanitizedLabel(node: AccessibilityNodeInfo): String {
        if (node.isPassword) return "<sensitive>"
        val hint = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) node.hintText else null
        val raw = sequenceOf(node.contentDescription, hint, node.text)
            .map { it.safeString().trim() }
            .firstOrNull { it.isNotEmpty() }
            .orEmpty()
        if (raw.isEmpty()) return ""
        var value = raw.replace(Regex("\\s+"), " ")
        value = value.replace(emailPattern, "<email>")
        value = value.replace(phonePattern, "<phone>")
        value = value.replace(credentialPattern, "<credential>")
        if (highEntropyPattern.containsMatchIn(value)) value = "<redacted>"
        return value.take(maxLabelChars)
    }

    private fun admitRef(rawRef: String): RefAdmission {
        val match = refPattern.matchEntire(rawRef)
            ?: return RefAdmission(null, "invalid_ref", mapOf("kind" to "ref", "ref" to rawRef.take(32)))
        val refBody = match.groupValues[1]
        val pinnedGeneration = match.groupValues.getOrNull(2)?.toIntOrNull()
        val frame = synchronized(frameLock) { refFrame }
            ?: return RefAdmission(null, "ref_frame_missing", mapOf("kind" to "ref", "ref" to refBody))
        if (System.currentTimeMillis() - frame.createdAtMillis > refTtlMillis) {
            expireRefFrame("ttl_expired")
            return RefAdmission(
                null,
                "ref_frame_expired",
                mapOf(
                    "kind" to "ref",
                    "ref" to refBody,
                    "currentGeneration" to frame.generation,
                    "frameState" to "expired",
                    "expiredReason" to "ttl_expired",
                ),
            )
        }
        if (frame.state != "active") {
            return RefAdmission(
                null,
                "ref_frame_expired",
                mapOf(
                    "kind" to "ref",
                    "ref" to refBody,
                    "currentGeneration" to frame.generation,
                    "frameState" to frame.state,
                    "expiredReason" to frame.expiredReason,
                ),
            )
        }
        if (pinnedGeneration != null && pinnedGeneration != frame.generation) {
            return RefAdmission(
                null,
                "ref_generation_mismatch",
                mapOf(
                    "kind" to "ref",
                    "ref" to refBody,
                    "currentGeneration" to frame.generation,
                    "mintedGeneration" to pinnedGeneration,
                ),
            )
        }
        val descriptor = frame.nodes[refBody]
            ?: return RefAdmission(
                null,
                "ref_not_issued",
                mapOf("kind" to "ref", "ref" to refBody, "currentGeneration" to frame.generation),
            )
        return RefAdmission(
            descriptor,
            null,
            mapOf(
                "kind" to "semantic_ref",
                "ref" to refBody,
                "refsGeneration" to frame.generation,
                "identityHash" to descriptor.identityHash,
            ),
        )
    }

    private fun findCurrentNode(descriptor: SemanticNode): AccessibilityNodeInfo? {
        val root = rootInActiveWindow ?: return null
        return try {
            findCurrentNode(root, descriptor, 0)
        } finally {
            root.recycle()
        }
    }

    private fun findCurrentNode(
        node: AccessibilityNodeInfo,
        descriptor: SemanticNode,
        depth: Int,
    ): AccessibilityNodeInfo? {
        if (depth > maxTraversalDepth) return null
        if (isInteractive(node)) {
            val candidate = semanticNode(node, descriptor.ref)
            if (candidate.identityHash == descriptor.identityHash) {
                return AccessibilityNodeInfo.obtain(node)
            }
        }
        val childCount = min(node.childCount, maxChildrenPerNode)
        for (index in 0 until childCount) {
            val child = node.getChild(index) ?: continue
            val found = try {
                findCurrentNode(child, descriptor, depth + 1)
            } finally {
                child.recycle()
            }
            if (found != null) return found
        }
        return null
    }

    private fun expireRefFrame(reason: String) {
        synchronized(frameLock) {
            val current = refFrame ?: return
            if (current.state == "expired") return
            refFrame = current.copy(state = "expired", expiredReason = reason)
        }
    }

    private fun currentFrameSummary(): Map<String, Any?>? {
        val frame = synchronized(frameLock) { refFrame } ?: return null
        return mapOf(
            "frameId" to "s${frame.generation}",
            "refsGeneration" to frame.generation,
            "state" to frame.state,
            "digest" to frame.digest,
            "issuedRefCount" to frame.nodes.size,
            "createdAtMillis" to frame.createdAtMillis,
            "expiredReason" to frame.expiredReason,
        )
    }

    private fun findEditable(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) return null
        val focused = node.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        if (focused?.isEditable == true) return focused
        focused?.recycle()
        return findEditableRecursive(node, 0)
    }

    private fun findEditableRecursive(node: AccessibilityNodeInfo, depth: Int): AccessibilityNodeInfo? {
        if (depth > maxTraversalDepth) return null
        if (node.isEditable) return AccessibilityNodeInfo.obtain(node)
        val childCount = min(node.childCount, maxChildrenPerNode)
        for (index in 0 until childCount) {
            val child = node.getChild(index) ?: continue
            val found = try {
                findEditableRecursive(child, depth + 1)
            } finally {
                child.recycle()
            }
            if (found != null) return found
        }
        return null
    }

    private fun setNodeText(target: AccessibilityNodeInfo, text: String): Boolean {
        val args = Bundle().apply {
            putCharSequence(
                AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                text.take(maxSetTextChars),
            )
        }
        return target.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
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

    private fun coordinateResolution(x: Float, y: Float): Map<String, Any?> = mapOf(
        "kind" to "coordinate",
        "x" to x.roundToInt(),
        "y" to y.roundToInt(),
        "coordinateContract" to coordinateContract(),
    )

    private fun coordinateContract(
        screenshotWidth: Int? = null,
        screenshotHeight: Int? = null,
    ): Map<String, Any?> {
        val metrics = resources.displayMetrics
        val inputWidth = metrics.widthPixels
        val inputHeight = metrics.heightPixels
        val sourceWidth = screenshotWidth ?: inputWidth
        val sourceHeight = screenshotHeight ?: inputHeight
        return mapOf(
            "sourceSpace" to if (screenshotWidth == null) "accessibility_screen_pixels" else "screenshot_pixels",
            "inputSpace" to "android_display_pixels",
            "sourceWidth" to sourceWidth,
            "sourceHeight" to sourceHeight,
            "inputWidth" to inputWidth,
            "inputHeight" to inputHeight,
            "scaleX" to if (sourceWidth > 0) inputWidth.toDouble() / sourceWidth else 1.0,
            "scaleY" to if (sourceHeight > 0) inputHeight.toDouble() / sourceHeight else 1.0,
            "origin" to "top_left",
        )
    }

    private fun snapshotDigest(
        nodes: List<SemanticNode>,
        packageName: String,
        className: String,
    ): String {
        val canonical = buildString {
            append(shortHash(packageName)).append('|').append(safeClassName(className))
            nodes.forEach { node ->
                append('|').append(node.ref).append(':').append(node.identityHash)
                    .append(':').append(node.enabled)
            }
        }
        return fullSha256(canonical.toByteArray(Charsets.UTF_8))
    }

    private fun deviceMetadata(): Map<String, Any?> = mapOf(
        "platform" to "android",
        "manufacturer" to Build.MANUFACTURER.take(40),
        "model" to Build.MODEL.take(60),
        "androidVersion" to Build.VERSION.RELEASE,
        "sdkInt" to Build.VERSION.SDK_INT,
        "appPackageHash" to shortHash(packageName),
    )

    private data class NodeStats(
        var nodeCount: Int = 0,
        var clickableNodeCount: Int = 0,
        var editableNodeCount: Int = 0,
        var focusableNodeCount: Int = 0,
        var visibleNodeCount: Int = 0,
        var truncated: Boolean = false,
    )

    private data class SemanticNode(
        val ref: String,
        val role: String,
        val label: String,
        val labelHash: String,
        val resourceIdHash: String,
        val identityHash: String,
        val bounds: Rect,
        val clickable: Boolean,
        val editable: Boolean,
        val enabled: Boolean,
        val password: Boolean,
        val actions: List<String>,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "ref" to ref,
            "role" to role,
            "label" to label,
            "labelHash" to labelHash,
            "resourceIdHash" to resourceIdHash,
            "identityHash" to identityHash,
            "bounds" to mapOf(
                "left" to bounds.left,
                "top" to bounds.top,
                "right" to bounds.right,
                "bottom" to bounds.bottom,
                "centerX" to bounds.exactCenterX().roundToInt(),
                "centerY" to bounds.exactCenterY().roundToInt(),
            ),
            "clickable" to clickable,
            "editable" to editable,
            "enabled" to enabled,
            "sensitive" to password,
            "actions" to actions,
        )
    }

    private data class RefFrame(
        val generation: Int,
        val state: String,
        val createdAtMillis: Long,
        val digest: String,
        val nodes: Map<String, SemanticNode>,
        val expiredReason: String?,
    )

    private data class RefAdmission(
        val descriptor: SemanticNode?,
        val failureKind: String?,
        val resolution: Map<String, Any?>,
    )

    companion object {
        @Volatile
        private var activeService: PhoneUseAccessibilityService? = null

        @Volatile
        private var connectedAtMillis: Long = 0

        @Volatile
        private var lastInterruptAtMillis: Long = 0

        @Volatile
        private var lastEventAtMillis: Long = 0

        @Volatile
        private var recoveryRequestedAtMillis: Long = 0

        @Volatile
        private var lastEvent: Map<String, Any?> = emptyMap()

        private val eventCounter = AtomicInteger(0)
        private val generationCounter = AtomicInteger((System.currentTimeMillis() % 100_000).toInt())
        private val screenshotCounter = AtomicLong(0)
        private val frameLock = Any()

        @Volatile
        private var refFrame: RefFrame? = null

        private const val maxTraversalDepth = 14
        private const val maxTraversalNodes = 700
        private const val maxChildrenPerNode = 100
        private const val maxInteractiveNodes = 160
        private const val maxSetTextChars = 500
        private const val maxLabelChars = 96
        private const val sparseInteractiveNodeThreshold = 2
        private const val recoveryWindowMillis = 15_000L
        private const val refTtlMillis = 30_000L

        private const val refInvalidatingEventMask =
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                AccessibilityEvent.TYPE_WINDOWS_CHANGED or
                AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED or
                AccessibilityEvent.TYPE_VIEW_CLICKED or
                AccessibilityEvent.TYPE_VIEW_FOCUSED or
                AccessibilityEvent.TYPE_VIEW_SCROLLED or
                AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED

        private val refPattern = Regex("^(@e\\d+)(?:~s(\\d+))?$")
        private val emailPattern = Regex("[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}")
        private val phonePattern = Regex("(?<![A-Za-z0-9])\\+?\\d[\\d ()-]{6,}\\d")
        private val credentialPattern = Regex(
            "(?i)(oauth|token|cookie|password|passwd|secret|api[_ -]?key)[=: ]+[^ ]+",
        )
        private val highEntropyPattern = Regex("[A-Za-z0-9_\\-]{32,}")
        private const val transactionRiskPolicyId = "phone_use_transaction_risk_v1"
        private val transactionRiskPattern = Regex(
            "(?i)(pay|payment|purchase|place[ _-]?order|confirm[ _-]?order|submit[ _-]?order|" +
                "buy[ _-]?now|checkout|subscribe|transfer|send[ _-]?money|withdraw|deposit|" +
                "book[ _-]?now|reserve|publish|post|delete[ _-]?account|" +
                "支付|付款|买单|提交订单|确认订单|下单|立即购买|结算|订阅|转账|汇款|" +
                "充值|提现|预订|预约|发布|发送|删除账号|确认并支付)",
        )

        private val supportedActions = listOf(
            "semantic_snapshot",
            "observe_ui",
            "risk_preview",
            "tap_ref",
            "set_text_ref",
            "global_back",
            "global_home",
            "tap",
            "swipe",
            "set_text",
            "capture_screenshot",
        )

        fun status(context: Context): Map<String, Any?> {
            val enabled = isServiceEnabled(context)
            val serviceConnected = activeService != null
            val lifecycleState = lifecycleState(context, enabled, serviceConnected)
            val batteryOptimizationIgnored = isBatteryOptimizationIgnored(context)
            val systemBackgroundRestricted =
                isSystemBackgroundRestricted(context) && !batteryOptimizationIgnored
            return mapOf(
                "platform" to "android",
                "supported" to true,
                "serviceId" to serviceId(context),
                "accessibilityEnabled" to enabled,
                "serviceConnected" to serviceConnected,
                "lifecycleState" to lifecycleState,
                "canObserveActiveWindow" to (enabled && serviceConnected),
                "canPerformGestures" to (enabled && serviceConnected && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N),
                "canSetText" to (enabled && serviceConnected),
                "canCaptureScreenshot" to (enabled && serviceConnected && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R),
                "batteryOptimizationIgnored" to batteryOptimizationIgnored,
                "backgroundRestricted" to systemBackgroundRestricted,
                "supportedActions" to supportedActions,
                "lastEvent" to lastEvent,
                "eventCount" to eventCounter.get(),
                "connectedAtMillis" to connectedAtMillis,
                "lastInterruptAtMillis" to lastInterruptAtMillis,
                "lastEventAtMillis" to lastEventAtMillis,
                "recoveryRequestedAtMillis" to recoveryRequestedAtMillis,
                "refFrame" to activeService?.currentFrameSummary(),
                "blockedReason" to blockedReason(lifecycleState),
                "recoveryActions" to recoveryActions(lifecycleState),
                "countsAsExperiment" to false,
                "countsAsStrategyAblationResult" to false,
                "rawTextIncluded" to false,
                "redactionApplied" to true,
            )
        }

        fun dryProbe(context: Context): Map<String, Any?> {
            val service = activeService
            if (!isServiceEnabled(context) || service == null) {
                return status(context) + mapOf(
                    "status" to "blocked",
                    "probe" to "accessibility_semantic_snapshot_dry_probe",
                    "failureKind" to blockedReason(lifecycleState(context, isServiceEnabled(context), service != null)),
                )
            }
            return status(context) + service.dryProbe()
        }

        fun performPhoneUseAction(context: Context, action: Map<String, Any?>): Map<String, Any?> {
            val service = activeService
            val enabled = isServiceEnabled(context)
            if (!enabled || service == null) {
                return status(context) + mapOf(
                    "status" to "blocked",
                    "requestedAction" to action["type"].safeString(),
                    "accepted" to false,
                    "failureKind" to blockedReason(lifecycleState(context, enabled, service != null)),
                )
            }
            return status(context) + service.performPhoneUseAction(action)
        }

        fun markRecoveryRequested(context: Context): Map<String, Any?> {
            recoveryRequestedAtMillis = System.currentTimeMillis()
            return status(context)
        }

        fun captureScreenshot(
            context: Context,
            approved: Boolean,
            sensitiveFlow: Boolean,
            callback: (Map<String, Any?>) -> Unit,
        ) {
            if (sensitiveFlow) {
                callback(
                    status(context) + mapOf(
                        "status" to "blocked",
                        "failureKind" to "sensitive_artifact_capture_blocked",
                    ),
                )
                return
            }
            if (!approved) {
                callback(
                    status(context) + mapOf(
                        "status" to "blocked",
                        "failureKind" to "approval_required",
                    ),
                )
                return
            }
            val service = activeService
            if (!isServiceEnabled(context) || service == null) {
                callback(status(context) + mapOf("status" to "blocked", "failureKind" to "accessibility_service_not_ready"))
                return
            }
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                callback(status(context) + mapOf("status" to "blocked", "failureKind" to "screenshot_requires_android_11"))
                return
            }
            service.takeScreenshot(
                Display.DEFAULT_DISPLAY,
                context.mainExecutor,
                object : TakeScreenshotCallback {
                    override fun onSuccess(screenshot: ScreenshotResult) {
                        val buffer = screenshot.hardwareBuffer
                        try {
                            val wrapped = Bitmap.wrapHardwareBuffer(buffer, screenshot.colorSpace)
                                ?: throw IllegalStateException("Cannot wrap screenshot buffer")
                            val bitmap = wrapped.copy(Bitmap.Config.ARGB_8888, false)
                                ?: throw IllegalStateException("Cannot copy screenshot bitmap")
                            try {
                                val artifactId = "phone-use-screenshot-${System.currentTimeMillis()}-${screenshotCounter.incrementAndGet()}"
                                val folder = File(context.cacheDir, "phone-use-evidence").apply { mkdirs() }
                                val file = File(folder, "$artifactId.png")
                                FileOutputStream(file).use { output ->
                                    check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, output))
                                }
                                callback(
                                    status(context) + mapOf(
                                        "status" to "passed",
                                        "artifactId" to artifactId,
                                        "artifactPath" to file.absolutePath,
                                        "artifactKind" to "screenshot",
                                        "sha256" to fullSha256(file.readBytes()),
                                        "width" to bitmap.width,
                                        "height" to bitmap.height,
                                        "coordinateContract" to service.coordinateContract(bitmap.width, bitmap.height),
                                        "localOnly" to true,
                                        "containsPotentiallySensitiveUi" to true,
                                        "shareableWithoutReview" to false,
                                        "rawTextIncluded" to false,
                                        "redactionApplied" to false,
                                    ),
                                )
                            } finally {
                                bitmap.recycle()
                            }
                        } catch (error: Throwable) {
                            callback(
                                status(context) + mapOf(
                                    "status" to "blocked",
                                    "failureKind" to "screenshot_capture_failed",
                                    "errorType" to error.javaClass.simpleName,
                                ),
                            )
                        } finally {
                            buffer.close()
                        }
                    }

                    override fun onFailure(errorCode: Int) {
                        callback(
                            status(context) + mapOf(
                                "status" to "blocked",
                                "failureKind" to "screenshot_capture_failed",
                                "platformErrorCode" to errorCode,
                            ),
                        )
                    }
                },
            )
        }

        private fun lifecycleState(context: Context, enabled: Boolean, connected: Boolean): String {
            if (!enabled) return "disabled"
            val now = System.currentTimeMillis()
            val recoveryRecent = recoveryRequestedAtMillis > 0 && now - recoveryRequestedAtMillis < recoveryWindowMillis
            if (!connected) return if (recoveryRecent) "recovering" else "enabled_disconnected"
            if (lastInterruptAtMillis > connectedAtMillis) {
                return if (recoveryRecent) "recovering" else "interrupted"
            }
            if (isSystemBackgroundRestricted(context) && !isBatteryOptimizationIgnored(context)) {
                return if (recoveryRecent) "recovering" else "background_restricted"
            }
            return "ready"
        }

        private fun blockedReason(state: String): String? = when (state) {
            "disabled" -> "accessibility_permission_required"
            "enabled_disconnected" -> "accessibility_service_not_connected"
            "interrupted" -> "accessibility_service_interrupted"
            "background_restricted" -> "background_execution_restricted"
            "recovering" -> "accessibility_service_recovering"
            else -> null
        }

        private fun recoveryActions(state: String): List<String> = when (state) {
            "disabled" -> listOf("Open Android Accessibility settings and enable MobileCode manually.")
            "enabled_disconnected", "interrupted", "recovering" -> listOf(
                "Return to Android Accessibility settings and re-confirm the MobileCode service.",
                "Do not automate secure settings changes; user authorization is required.",
            )
            "background_restricted" -> listOf("Review battery optimization and background restrictions for MobileCode.")
            else -> emptyList()
        }

        private fun isBatteryOptimizationIgnored(context: Context): Boolean = try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            powerManager.isIgnoringBatteryOptimizations(context.packageName)
        } catch (_: Throwable) {
            false
        }

        private fun isSystemBackgroundRestricted(context: Context): Boolean = try {
            val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && manager.isBackgroundRestricted
        } catch (_: Throwable) {
            false
        }

        private fun serviceId(context: Context): String =
            ComponentName(context, PhoneUseAccessibilityService::class.java).flattenToString()

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
                ) return true
            }
            return false
        }
    }
}

private fun Any?.safeString(): String = this?.toString().orEmpty()

private fun safeClassName(value: String): String = value.substringAfterLast('.').take(80)

private fun doubleValue(value: Any?, fallback: Double): Double = when (value) {
    is Number -> value.toDouble()
    is String -> value.toDoubleOrNull() ?: fallback
    else -> fallback
}

private fun longValue(value: Any?, fallback: Long): Long = when (value) {
    is Number -> value.toLong()
    is String -> value.toLongOrNull() ?: fallback
    else -> fallback
}

private fun identityHash(role: String, label: String, resourceIdHash: String, bounds: Rect): String =
    shortHash("$role|$label|$resourceIdHash|${bounds.left},${bounds.top},${bounds.right},${bounds.bottom}", 20)

private fun shortHash(value: String, length: Int = 16): String =
    shortHash(value.toByteArray(Charsets.UTF_8), length)

private fun shortHash(value: ByteArray, length: Int = 16): String =
    fullSha256(value).take(length)

private fun fullSha256(value: ByteArray): String =
    MessageDigest.getInstance("SHA-256")
        .digest(value)
        .joinToString("") { byte -> "%02x".format(byte) }
