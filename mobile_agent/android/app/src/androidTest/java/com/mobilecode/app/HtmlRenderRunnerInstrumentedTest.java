package com.mobilecode.app;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import android.app.Instrumentation;
import android.content.Context;
import android.content.Intent;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import io.flutter.plugin.common.MethodChannel;
import java.io.File;
import java.io.FileOutputStream;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.Test;
import org.junit.runner.RunWith;

@RunWith(AndroidJUnit4.class)
public class HtmlRenderRunnerInstrumentedTest {
    @Test
    public void capturesPngFromAppPrivateHtmlFile() throws Exception {
        Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        File html = new File(context.getCacheDir(), "html-render-probe.html");
        try (FileOutputStream output = new FileOutputStream(html)) {
            output.write(("<!doctype html><html><head><meta name=\"viewport\" "
                + "content=\"width=device-width,initial-scale=1\"></head>"
                + "<body style=\"margin:0;background:#10243d;color:white\">"
                + "<main style=\"width:390px;height:844px\"><h1>MobileCode probe</h1>"
                + "</main></body></html>").getBytes(java.nio.charset.StandardCharsets.UTF_8));
        }

        CountDownLatch completed = new CountDownLatch(1);
        AtomicReference<Map<String, Object>> value = new AtomicReference<>();
        AtomicReference<String> error = new AtomicReference<>();

        Intent intent = new Intent(context, MainActivity.class)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        MainActivity activity = (MainActivity) instrumentation.startActivitySync(intent);
        try {
            instrumentation.runOnMainSync(() -> {
                Map<String, Object> payload = new HashMap<>();
                payload.put("url", html.toURI().toString());
                payload.put("width", 390);
                payload.put("height", 844);
                payload.put("deviceScaleFactor", 1.0);
                payload.put("timeoutMs", 15000);
                new HtmlRenderRunner(activity).renderPng(payload, new MethodChannel.Result() {
                    @Override
                    public void success(Object result) {
                        if (result instanceof Map) {
                            value.set((Map<String, Object>) result);
                        }
                        completed.countDown();
                    }

                    @Override
                    public void error(String errorCode, String errorMessage, Object details) {
                        error.set(errorCode + ": " + errorMessage);
                        completed.countDown();
                    }

                    @Override
                    public void notImplemented() {
                        error.set("not_implemented");
                        completed.countDown();
                    }
                });
            });

            assertTrue("renderer callback timed out", completed.await(30, TimeUnit.SECONDS));
        } finally {
            activity.finishAndRemoveTask();
        }

        assertEquals("renderer error: " + error.get(), null, error.get());
        assertNotNull(value.get());
        File png = new File(String.valueOf(value.get().get("path")));
        assertTrue("PNG should exist: " + png, png.exists());
        assertTrue("PNG should be non-empty", png.length() > 100);
        assertEquals("image/png", value.get().get("mimeType"));
        assertEquals(390, ((Number) value.get().get("width")).intValue());
        assertEquals(844, ((Number) value.get().get("height")).intValue());
    }

    @Test
    public void capturesPdfFromAppPrivateHtmlFile() throws Exception {
        Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        File html = new File(context.getCacheDir(), "html-render-pdf-probe.html");
        try (FileOutputStream output = new FileOutputStream(html)) {
            output.write(("<!doctype html><html><body style=\"margin:0\"><h1>PDF probe</h1>"
                + "<p>MobileCode PDF export</p></body></html>")
                .getBytes(java.nio.charset.StandardCharsets.UTF_8));
        }

        CountDownLatch completed = new CountDownLatch(1);
        AtomicReference<Map<String, Object>> value = new AtomicReference<>();
        AtomicReference<String> error = new AtomicReference<>();
        Intent intent = new Intent(context, MainActivity.class)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        MainActivity activity = (MainActivity) instrumentation.startActivitySync(intent);
        try {
            instrumentation.runOnMainSync(() -> {
                Map<String, Object> payload = new HashMap<>();
                payload.put("url", html.toURI().toString());
                payload.put("width", 390);
                payload.put("height", 844);
                payload.put("deviceScaleFactor", 1.0);
                payload.put("timeoutMs", 15000);
                new HtmlRenderRunner(activity).renderPdf(payload, new MethodChannel.Result() {
                    @Override
                    public void success(Object result) {
                        if (result instanceof Map) {
                            value.set((Map<String, Object>) result);
                        }
                        completed.countDown();
                    }

                    @Override
                    public void error(String errorCode, String errorMessage, Object details) {
                        error.set(errorCode + ": " + errorMessage);
                        completed.countDown();
                    }

                    @Override
                    public void notImplemented() {
                        error.set("not_implemented");
                        completed.countDown();
                    }
                });
            });
            assertTrue("PDF renderer callback timed out", completed.await(30, TimeUnit.SECONDS));
        } finally {
            activity.finishAndRemoveTask();
        }

        assertEquals("renderer error: " + error.get(), null, error.get());
        assertNotNull(value.get());
        File pdf = new File(String.valueOf(value.get().get("path")));
        assertTrue("PDF should exist: " + pdf, pdf.exists());
        assertTrue("PDF should be non-empty", pdf.length() > 100);
        assertEquals("application/pdf", value.get().get("mimeType"));
        try (java.io.FileInputStream input = new java.io.FileInputStream(pdf)) {
            byte[] header = new byte[4];
            assertEquals(4, input.read(header));
            assertEquals("%PDF", new String(header, java.nio.charset.StandardCharsets.US_ASCII));
        }
    }
}
