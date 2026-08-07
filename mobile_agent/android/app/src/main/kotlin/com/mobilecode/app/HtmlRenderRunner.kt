package com.mobilecode.app

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.pdf.PdfDocument
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.roundToInt

/** Captures a deterministic viewport bitmap from an Android WebView. */
class HtmlRenderRunner(private val activity: Activity) {
    private val mainHandler = Handler(Looper.getMainLooper())

    fun renderPng(
        payload: Map<String, Any?>,
        result: io.flutter.plugin.common.MethodChannel.Result,
    ) {
        render(payload, result, RenderFormat.PNG)
    }

    fun renderPdf(
        payload: Map<String, Any?>,
        result: io.flutter.plugin.common.MethodChannel.Result,
    ) {
        render(payload, result, RenderFormat.PDF)
    }

    private fun render(
        payload: Map<String, Any?>,
        result: io.flutter.plugin.common.MethodChannel.Result,
        format: RenderFormat,
    ) {
        val url = payload["url"]?.toString()?.trim().orEmpty()
        if (url.isEmpty()) {
            result.error("invalid_request", "render${format.suffix} requires a non-empty url", null)
            return
        }
        val width = number(payload["width"], 390).coerceIn(240, 4096)
        val height = number(payload["height"], 844).coerceIn(320, 4096)
        val scale = (payload["deviceScaleFactor"] as? Number)?.toDouble()
            ?.coerceIn(0.5, 4.0) ?: 1.0
        val timeoutMs = number(payload["timeoutMs"], 15000).coerceIn(1000, 60000)
        val widthPx = (width * scale).roundToInt().coerceIn(240, 8192)
        val heightPx = (height * scale).roundToInt().coerceIn(320, 8192)

        val root = activity.findViewById<ViewGroup>(android.R.id.content)
        if (root == null) {
            result.error("renderer_unavailable", "Android content root is unavailable", null)
            return
        }

        val webView = WebView(activity)
        val completed = AtomicBoolean(false)
        val timeout = Runnable {
            finish(
                webView = webView,
                root = root,
                completed = completed,
                result = result,
                errorCode = "timeout",
                errorMessage = "HTML renderer timed out after ${timeoutMs}ms",
            )
        }

        webView.alpha = 0f
        webView.isFocusable = false
        webView.isFocusableInTouchMode = false
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = true
            allowContentAccess = true
            allowFileAccessFromFileURLs = true
            allowUniversalAccessFromFileURLs = true
            cacheMode = WebSettings.LOAD_NO_CACHE
            useWideViewPort = false
            loadWithOverviewMode = false
        }
        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView, pageUrl: String) {
                view.evaluateJavascript(
                    "(function(){var m=document.querySelector('meta[name=viewport]');" +
                        "if(!m){m=document.createElement('meta');m.name='viewport';" +
                        "document.head.appendChild(m);}m.content='width=device-width," +
                        "initial-scale=1,maximum-scale=1,user-scalable=no';})();",
                ) {
                    mainHandler.postDelayed({
                        capture(
                            webView = view,
                            root = root,
                            widthPx = widthPx,
                            heightPx = heightPx,
                            scale = scale,
                            completed = completed,
                            result = result,
                            timeout = timeout,
                            format = format,
                        )
                    }, 250)
                }
            }

            override fun onReceivedError(
                view: WebView,
                request: WebResourceRequest,
                error: WebResourceError,
            ) {
                if (request.isForMainFrame) {
                    finish(
                        webView = view,
                        root = root,
                        completed = completed,
                        result = result,
                        errorCode = "load_failed",
                        errorMessage = error.description?.toString() ?: "HTML page failed to load",
                    )
                }
            }
        }
        webView.layoutParams = ViewGroup.LayoutParams(widthPx, heightPx)
        root.addView(webView)
        webView.measure(
            View.MeasureSpec.makeMeasureSpec(widthPx, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(heightPx, View.MeasureSpec.EXACTLY),
        )
        webView.layout(0, 0, widthPx, heightPx)
        mainHandler.postDelayed(timeout, timeoutMs.toLong())
        webView.loadUrl(url)
    }

    private fun capture(
        webView: WebView,
        root: ViewGroup,
        widthPx: Int,
        heightPx: Int,
        scale: Double,
        completed: AtomicBoolean,
        result: io.flutter.plugin.common.MethodChannel.Result,
        timeout: Runnable,
        format: RenderFormat,
    ) {
        if (completed.get()) return
        mainHandler.removeCallbacks(timeout)
        if (format == RenderFormat.PDF) {
            writePdf(
                webView = webView,
                root = root,
                widthPx = widthPx,
                heightPx = heightPx,
                scale = scale,
                completed = completed,
                result = result,
                timeout = timeout,
            )
            return
        }
        try {
            val bitmap = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
            webView.draw(Canvas(bitmap))
            val outputDir = File(activity.cacheDir, "mobilecode-render")
            outputDir.mkdirs()
            val output = File(outputDir, "preview_${System.currentTimeMillis()}.png")
            FileOutputStream(output).use { stream ->
                check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)) {
                    "Android WebView could not encode PNG"
                }
            }
            bitmap.recycle()
            finish(
                webView = webView,
                root = root,
                completed = completed,
                result = result,
                value = mapOf(
                    "path" to output.absolutePath,
                    "mimeType" to "image/png",
                    "width" to widthPx,
                    "height" to heightPx,
                    "backend" to "android_webview_draw",
                    "metadata" to mapOf("deviceScaleFactor" to scale),
                ),
            )
        } catch (error: Throwable) {
            finish(
                webView = webView,
                root = root,
                completed = completed,
                result = result,
                errorCode = "capture_failed",
                errorMessage = error.message ?: error.javaClass.simpleName,
            )
        }
    }

    private fun writePdf(
        webView: WebView,
        root: ViewGroup,
        widthPx: Int,
        heightPx: Int,
        scale: Double,
        completed: AtomicBoolean,
        result: io.flutter.plugin.common.MethodChannel.Result,
        timeout: Runnable,
    ) {
        val outputDir = File(activity.cacheDir, "mobilecode-render")
        outputDir.mkdirs()
        val output = File(outputDir, "preview_${System.currentTimeMillis()}.pdf")
        try {
            val document = PdfDocument()
            try {
                val pageInfo = PdfDocument.PageInfo.Builder(widthPx, heightPx, 1).create()
                val page = document.startPage(pageInfo)
                webView.draw(page.canvas)
                document.finishPage(page)
                FileOutputStream(output).use { stream -> document.writeTo(stream) }
            } finally {
                document.close()
            }
            finish(
                webView = webView,
                root = root,
                completed = completed,
                result = result,
                value = mapOf(
                    "path" to output.absolutePath,
                    "mimeType" to "application/pdf",
                    "width" to widthPx,
                    "height" to heightPx,
                    "backend" to "android_webview_pdf_document",
                    "metadata" to mapOf(
                        "deviceScaleFactor" to scale,
                        "pageCount" to 1,
                        "pageMode" to "raster_viewport",
                    ),
                ),
            )
        } catch (error: Throwable) {
            finish(
                webView = webView,
                root = root,
                completed = completed,
                result = result,
                errorCode = "capture_failed",
                errorMessage = error.message ?: error.javaClass.simpleName,
            )
        }
    }

    private fun finish(
        webView: WebView,
        root: ViewGroup,
        completed: AtomicBoolean,
        result: io.flutter.plugin.common.MethodChannel.Result,
        value: Map<String, Any?>? = null,
        errorCode: String? = null,
        errorMessage: String? = null,
    ) {
        if (!completed.compareAndSet(false, true)) return
        mainHandler.removeCallbacksAndMessages(null)
        root.removeView(webView)
        webView.stopLoading()
        webView.destroy()
        activity.runOnUiThread {
            if (errorCode != null) {
                result.error(errorCode, errorMessage ?: errorCode, null)
            } else {
                result.success(value)
            }
        }
    }

    private fun number(value: Any?, fallback: Int): Int =
        (value as? Number)?.toInt() ?: fallback

    private enum class RenderFormat(val suffix: String) {
        PNG("Png"),
        PDF("Pdf"),
    }
}
