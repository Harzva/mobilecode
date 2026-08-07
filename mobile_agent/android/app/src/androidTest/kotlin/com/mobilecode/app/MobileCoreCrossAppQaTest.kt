package com.mobilecode.app

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.util.Base64
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import kotlin.math.PI
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * Runs inside MobileCode's process against MobileCore's loopback service. Host
 * QA starts MobileCore and loads a model first; this proves app-to-app access,
 * not merely host-to-MobileCore access through adb forwarding.
 */
@RunWith(AndroidJUnit4::class)
class MobileCoreCrossAppQaTest {
    @Test
    fun thirtyControlledOfflineTextAndStreamTasks() {
        val healthJson = readyHealth()
        val model = healthJson.getString("active_model")

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

    @Test
    fun controlledLocalImageQualityTasks() {
        val health = readyHealth()
        assertTrue(
            "MobileCore must advertise image_input before image QA",
            health.getJSONObject("capabilities").getBoolean("image_input"),
        )
        val model = health.getString("active_model")
        val seven = imageChat(model, label = "7", color = Color.RED)
        val three = imageChat(model, label = "3", color = Color.BLUE)

        assertRelevant(seven, setOf("7", "seven", "七"), "image-seven")
        assertRelevant(three, setOf("3", "three", "三"), "image-three")
        assertNotEquals(
            "controlled image cases returned identical normalized output",
            digest(seven),
            digest(three),
        )
        assertMetricsContainNoControlledPayloadMarker()
    }

    @Test
    fun controlledLocalAudioQualityTasks() {
        val health = readyHealth()
        assertTrue(
            "MobileCore must advertise audio_input before audio QA",
            health.getJSONObject("capabilities").getBoolean("audio_input"),
        )
        val sampleRate = health.optInt("audio_sample_rate_hz", 0)
        assertTrue("MobileCore must advertise a valid audio sample rate", sampleRate in 8_000..96_000)
        val model = health.getString("active_model")
        val tone = audioChat(model, createPcmWav(sampleRate, toneHz = 440.0))
        val silence = audioChat(model, createPcmWav(sampleRate, toneHz = null))

        assertRelevant(tone, setOf("tone", "beep", "音调", "哔"), "audio-tone")
        assertRelevant(
            silence,
            setOf("silence", "silent", "quiet", "静音", "无声"),
            "audio-silence",
        )
        assertNotEquals(
            "controlled audio cases returned identical normalized output",
            digest(tone),
            digest(silence),
        )
        assertMetricsContainNoControlledPayloadMarker()
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

    private fun readyHealth(): JSONObject {
        val health = request("GET", "/health")
        assertEquals(200, health.code)
        val payload = JSONObject(health.body)
        assertEquals("mobilecore", payload.getString("service"))
        assertTrue(
            "MobileCore must load a real model before cross-app QA",
            payload.getBoolean("model_loaded"),
        )
        assertTrue(payload.getString("active_model").isNotBlank())
        return payload
    }

    private fun imageChat(model: String, label: String, color: Int): String {
        val bitmap = Bitmap.createBitmap(512, 512, Bitmap.Config.ARGB_8888)
        val encoded = try {
            val canvas = Canvas(bitmap)
            canvas.drawColor(Color.WHITE)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                this.color = color
                textAlign = Paint.Align.CENTER
                textSize = 360f
                typeface = android.graphics.Typeface.DEFAULT_BOLD
            }
            val baseline = bitmap.height / 2f - (paint.ascent() + paint.descent()) / 2f
            canvas.drawText(label, bitmap.width / 2f, baseline, paint)
            ByteArrayOutputStream().use { output ->
                assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, output))
                Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP)
            }
        } finally {
            bitmap.recycle()
        }
        val content = JSONArray()
            .put(JSONObject().apply {
                put("type", "text")
                put("text", "Read the single large digit in this controlled image. Reply with the digit only.")
            })
            .put(JSONObject().apply {
                put("type", "image_url")
                put("image_url", JSONObject().put("url", "data:image/png;base64,$encoded"))
            })
        return structuredChat(model, content, caseName = "controlled-image")
    }

    private fun audioChat(model: String, wav: ByteArray): String {
        val encoded = Base64.encodeToString(wav, Base64.NO_WRAP)
        val content = JSONArray()
            .put(JSONObject().apply {
                put("type", "text")
                put(
                    "text",
                    "Is this controlled audio mainly a clear tone or silence? Reply only TONE or SILENCE.",
                )
            })
            .put(JSONObject().apply {
                put("type", "input_audio")
                put(
                    "input_audio",
                    JSONObject().apply {
                        put("data", encoded)
                        put("format", "wav")
                    },
                )
            })
        return structuredChat(model, content, caseName = "controlled-audio")
    }

    private fun structuredChat(model: String, content: JSONArray, caseName: String): String {
        val body = JSONObject().apply {
            put("model", model)
            put("max_tokens", 16)
            put("temperature", 0.0)
            put("stream", false)
            put("modalities", JSONArray().put("text"))
            put("messages", JSONArray().put(JSONObject().apply {
                put("role", "user")
                put("content", content)
            }))
        }.toString()
        val response = request(
            "POST",
            "/v1/chat/completions",
            body,
            readTimeoutMs = 180_000,
        )
        assertEquals("$caseName request failed", 200, response.code)
        val text = JSONObject(response.body)
            .getJSONArray("choices")
            .getJSONObject(0)
            .getJSONObject("message")
            .getString("content")
            .trim()
        assertTrue("$caseName returned empty text", text.isNotBlank())
        return text
    }

    private fun createPcmWav(sampleRate: Int, toneHz: Double?): ByteArray {
        val sampleCount = sampleRate * 3 / 2
        val pcmBytes = sampleCount * 2
        return ByteArrayOutputStream(44 + pcmBytes).use { output ->
            output.writeAscii("RIFF")
            output.writeLittleEndian(36 + pcmBytes, 4)
            output.writeAscii("WAVEfmt ")
            output.writeLittleEndian(16, 4)
            output.writeLittleEndian(1, 2)
            output.writeLittleEndian(1, 2)
            output.writeLittleEndian(sampleRate, 4)
            output.writeLittleEndian(sampleRate * 2, 4)
            output.writeLittleEndian(2, 2)
            output.writeLittleEndian(16, 2)
            output.writeAscii("data")
            output.writeLittleEndian(pcmBytes, 4)
            repeat(sampleCount) { index ->
                val sample = if (toneHz == null) {
                    0
                } else {
                    (sin(2.0 * PI * toneHz * index / sampleRate) * 8_000.0).roundToInt()
                }
                output.writeLittleEndian(sample, 2)
            }
            output.toByteArray()
        }
    }

    private fun assertRelevant(output: String, terms: Set<String>, caseName: String) {
        val normalized = normalize(output)
        assertTrue(
            "$caseName failed its aggregate semantic sanity gate",
            terms.any(normalized::contains),
        )
    }

    private fun assertMetricsContainNoControlledPayloadMarker() {
        val metrics = request("GET", "/metrics")
        assertEquals(200, metrics.code)
        assertFalse(metrics.body.contains("controlled-image", ignoreCase = true))
        assertFalse(metrics.body.contains("controlled-audio", ignoreCase = true))
        assertFalse(metrics.body.contains("data:image", ignoreCase = true))
        assertFalse(metrics.body.contains("input_audio", ignoreCase = true))
    }

    private fun normalize(value: String): String = value
        .trim()
        .lowercase()
        .replace(Regex("\\s+"), " ")

    private fun digest(value: String): String = MessageDigest
        .getInstance("SHA-256")
        .digest(normalize(value).toByteArray(Charsets.UTF_8))
        .joinToString("") { byte -> "%02x".format(byte) }

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

    private fun ByteArrayOutputStream.writeAscii(value: String) {
        write(value.toByteArray(Charsets.US_ASCII))
    }

    private fun ByteArrayOutputStream.writeLittleEndian(value: Int, byteCount: Int) {
        repeat(byteCount) { offset ->
            write(value shr (offset * 8) and 0xff)
        }
    }
}
