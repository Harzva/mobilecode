package com.mobilecode.app

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * Runs inside MobileCode's process against MobileCore's loopback service. Host
 * QA starts MobileCore and loads a model first; this proves app-to-app access,
 * not merely host-to-MobileCore access through adb forwarding.
 */
@RunWith(AndroidJUnit4::class)
class MobileCoreCrossAppQaTest {
    @Test
    fun thirtyControlledOfflineTextAndStreamTasks() {
        val health = request("GET", "/health")
        assertEquals(200, health.code)
        val healthJson = JSONObject(health.body)
        assertEquals("mobilecore", healthJson.getString("service"))
        assertTrue("MobileCore must load a real model before cross-app QA", healthJson.getBoolean("model_loaded"))
        val model = healthJson.getString("active_model")
        assertTrue(model.isNotBlank())

        repeat(30) { index ->
            val task = index + 1
            val stream = task > 15
            val prompt = "Controlled local QA task $task. Reply exactly: OK."
            val response = chat(model = model, prompt = prompt, stream = stream)
            assertEquals("task $task", 200, response.code)
            if (stream) {
                assertTrue("task $task missing SSE completion", response.body.contains("data: [DONE]"))
                assertTrue("task $task missing SSE text", streamText(response.body).isNotBlank())
            } else {
                val json = JSONObject(response.body)
                val text = json.getJSONArray("choices")
                    .getJSONObject(0)
                    .getJSONObject("message")
                    .getString("content")
                assertTrue("task $task returned empty text", text.isNotBlank())
                assertTrue("task $task missing local metrics", json.has("mobilecore"))
            }
        }

        val metrics = request("GET", "/metrics")
        assertEquals(200, metrics.code)
        val metricsJson = JSONObject(metrics.body)
        assertEquals(model, metricsJson.getString("active_model"))
        assertTrue(metricsJson.getDouble("last_decode_tokens_per_second") >= 0.0)
        assertFalse(metrics.body.contains("Controlled local QA task"))
    }

    private fun chat(model: String, prompt: String, stream: Boolean): HttpResult {
        val body = JSONObject().apply {
            put("model", model)
            put("max_tokens", 4)
            put("temperature", 0.0)
            put("stream", stream)
            put("messages", JSONArray().put(JSONObject().apply {
                put("role", "user")
                put("content", prompt)
            }))
        }.toString()
        return request("POST", "/v1/chat/completions", body, readTimeoutMs = 120_000)
    }

    private fun request(
        method: String,
        path: String,
        body: String? = null,
        readTimeoutMs: Int = 10_000,
    ): HttpResult {
        val connection = URL("http://127.0.0.1:8080$path").openConnection() as HttpURLConnection
        try {
            connection.requestMethod = method
            connection.connectTimeout = 5_000
            connection.readTimeout = readTimeoutMs
            connection.setRequestProperty("Authorization", "Bearer local")
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("X-MobileCore-Client", "mobilecode-android-test")
            if (body != null) {
                connection.doOutput = true
                connection.outputStream.use { output ->
                    output.write(body.toByteArray(Charsets.UTF_8))
                }
            }
            val code = connection.responseCode
            val stream = if (code >= 400) connection.errorStream else connection.inputStream
            val response = stream?.use { input ->
                ByteArrayOutputStream().use { output ->
                    input.copyTo(output)
                    output.toString(Charsets.UTF_8.name())
                }
            }.orEmpty()
            return HttpResult(code, response)
        } finally {
            connection.disconnect()
        }
    }

    private fun streamText(body: String): String = body.lineSequence()
        .filter { it.startsWith("data: ") && it != "data: [DONE]" }
        .mapNotNull { line ->
            runCatching {
                JSONObject(line.removePrefix("data: "))
                    .getJSONArray("choices")
                    .getJSONObject(0)
                    .getJSONObject("delta")
                    .optString("content")
            }.getOrNull()
        }
        .joinToString("")

    private data class HttpResult(val code: Int, val body: String)
}
