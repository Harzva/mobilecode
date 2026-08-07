package com.mobilecode.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Base64
import android.util.Log
import java.io.File
import org.json.JSONArray
import org.json.JSONObject

/**
 * Debug-only ADB bridge for host-driven Phone Use acceptance.
 *
 * The manifest protects this exported receiver with android.permission.DUMP,
 * so normal third-party apps cannot use it. A receiver is intentional: unlike
 * an instrumentation process or Activity, it neither kills the accessibility
 * service nor changes the active window and invalidates freshly minted refs.
 */
class PhoneUseQaBridgeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val requestId = sanitizeRequestId(intent.getStringExtra(EXTRA_REQUEST_ID))
        try {
            val action = decodeAction(intent.getStringExtra(EXTRA_ACTION_BASE64))
            val actionType = safeLogToken(action["type"])
            when (action["type"]?.toString()) {
                "qa_state" -> complete(
                    context,
                    requestId,
                    mapOf(
                        "status" to "passed",
                        "stage" to PhoneUseTakeoutQaActivity.currentStage,
                        "commitAttempts" to PhoneUseTakeoutQaActivity.commitAttempts.get(),
                        "phoneUseStatus" to PhoneUseAccessibilityService.status(context),
                    ),
                    actionType,
                )
                "qa_capture_screenshot" -> PhoneUseAccessibilityService.captureScreenshot(
                    context,
                    approved = action["approved"] == true,
                    sensitiveFlow = action["sensitiveFlow"] == true,
                ) { result -> complete(context, requestId, result, actionType) }
                "qa_mark_recovery" -> complete(
                    context,
                    requestId,
                    PhoneUseAccessibilityService.markRecoveryRequested(context),
                    actionType,
                )
                else -> complete(
                    context,
                    requestId,
                    PhoneUseAccessibilityService.performPhoneUseAction(context, action),
                    actionType,
                )
            }
        } catch (error: Throwable) {
            complete(
                context,
                requestId,
                mapOf(
                    "status" to "blocked",
                    "failureKind" to "qa_bridge_request_failed",
                    "errorType" to error.javaClass.simpleName,
                    "rawInputIncluded" to false,
                ),
                "bridge_error",
            )
        }
    }

    private fun complete(
        context: Context,
        requestId: String,
        result: Map<String, Any?>,
        actionType: String,
    ) {
        val payload = JSONObject(
            mapOf(
                "requestId" to requestId,
                "completedAtEpochMs" to System.currentTimeMillis(),
                "result" to result,
            ),
        )
        val outputDirectory = File(context.filesDir, RESULT_DIRECTORY).apply { mkdirs() }
        File(outputDirectory, "$requestId.json").writeText(payload.toString(), Charsets.UTF_8)
        Log.i(
            TAG,
            "action=$actionType status=${safeLogToken(result["status"])} " +
                "failure=${safeLogToken(result["failureKind"])} rawValues=false",
        )
    }

    private fun decodeAction(encoded: String?): Map<String, Any?> {
        require(!encoded.isNullOrBlank()) { "Missing encoded action" }
        val bytes = Base64.decode(encoded, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
        val json = JSONObject(bytes.toString(Charsets.UTF_8))
        return json.keys().asSequence().associateWith { key -> jsonValue(json.get(key)) }
    }

    private fun jsonValue(value: Any?): Any? = when (value) {
        null, JSONObject.NULL -> null
        is JSONObject -> value.keys().asSequence().associateWith { key -> jsonValue(value.get(key)) }
        is JSONArray -> (0 until value.length()).map { index -> jsonValue(value.get(index)) }
        else -> value
    }

    private fun sanitizeRequestId(value: String?): String {
        val sanitized = value.orEmpty().replace(REQUEST_ID_PATTERN, "").take(80)
        require(sanitized.isNotBlank()) { "Missing request id" }
        return sanitized
    }

    private fun safeLogToken(value: Any?): String = value
        ?.toString()
        .orEmpty()
        .replace(LOG_TOKEN_PATTERN, "")
        .take(48)
        .ifBlank { "none" }

    companion object {
        private const val EXTRA_REQUEST_ID = "request_id"
        private const val EXTRA_ACTION_BASE64 = "action_b64"
        private const val RESULT_DIRECTORY = "phone-use-qa"
        private const val TAG = "PhoneUseQaBridge"
        private val REQUEST_ID_PATTERN = Regex("[^A-Za-z0-9_-]")
        private val LOG_TOKEN_PATTERN = Regex("[^A-Za-z0-9_-]")
    }
}
