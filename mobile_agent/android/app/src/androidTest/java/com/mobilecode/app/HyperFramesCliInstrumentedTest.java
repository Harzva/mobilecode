package com.mobilecode.app;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import android.content.Context;
import android.os.Build;
import android.util.Log;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;
import org.junit.Test;
import org.junit.runner.RunWith;

@RunWith(AndroidJUnit4.class)
public class HyperFramesCliInstrumentedTest {
    private static final String TAG = "MobileCodeHyperFramesProof";

    @Test
    public void installsProfileChecksAndRendersEditableHtmlPoster() throws Exception {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        LinuxSandboxRunner runner = new LinuxSandboxRunner(context);

        Log.i(TAG, "device model=" + Build.MODEL);
        Log.i(TAG, "android release=" + Build.VERSION.RELEASE + " sdk=" + Build.VERSION.SDK_INT);
        Log.i(TAG, "abis=" + String.join(",", Build.SUPPORTED_ABIS));

        assertSuccess("setup", runner.setup(alpineManifestForDevice()));

        Map<String, Object> installPayload = new HashMap<>();
        installPayload.put("approved", true);
        installPayload.put("profileId", "hyperframesCli");
        Map<String, ?> install = runner.runTypedTask("package_install", installPayload);
        Log.i(TAG, "install-stdout-tail=" + tail(String.valueOf(install.get("stdout"))));
        Log.i(TAG, "install-stderr-tail=" + tail(String.valueOf(install.get("stderr"))));
        Log.i(TAG, "install-metadata=" + install.get("metadata"));
        assertSuccess("package_install hyperframesCli", install);
        Log.i(TAG, "install=" + summarize(install));

        Map<String, ?> probe = runner.runTypedTask("hyperframes_cli_probe", new HashMap<>());
        assertSuccess("hyperframes_cli_probe", probe);
        assertTrue(
            "probe should report a semver for HyperFrames: " + summarize(probe),
            String.valueOf(probe.get("stdout")).matches("(?s).*\\d+\\.\\d+\\.\\d+.*")
        );

        File projectDir = new File(
            new File(context.getExternalFilesDir(null), "sandbox-home"),
            "hyperframes-poster"
        );
        deleteRecursively(projectDir);
        assertTrue(projectDir.mkdirs());
        writeFile(new File(projectDir, "hyperframes.json"), "{\n  \"paths\": {\n    \"blocks\": \"compositions\",\n    \"components\": \"compositions/components\",\n    \"assets\": \"assets\"\n  }\n}\n");
        writeFile(new File(projectDir, "index.html"), posterHtml());

        Map<String, Object> taskPayload = new HashMap<>();
        taskPayload.put("cwd", "/root/hyperframes-poster");
        taskPayload.put("noContrast", true);
        taskPayload.put("samples", 1);
        Map<String, ?> lint = runner.runTypedTask("hyperframes_lint", taskPayload);
        assertSuccess("hyperframes_lint", lint);

        Map<String, ?> check = runner.runTypedTask("hyperframes_check", taskPayload);
        assertSuccess("hyperframes_check", check);
        assertTrue("check should report ok=true: " + summarize(check),
            String.valueOf(check.get("stdout")).contains("\"ok\": true"));
        Log.i(TAG, "check=" + summarize(check));

        Map<String, Object> renderPayload = new HashMap<>();
        renderPayload.put("cwd", "/root/hyperframes-poster");
        renderPayload.put("approved", true);
        renderPayload.put("output", "output.mp4");
        Map<String, ?> render = runner.runTypedTask("hyperframes_render", renderPayload);
        assertSuccess("hyperframes_render", render);
        File output = new File(projectDir, "output.mp4");
        assertTrue("rendered MP4 should exist: " + output, output.isFile());
        assertTrue("rendered MP4 should be non-empty", output.length() > 1024);
        Log.i(TAG, "render=" + summarize(render));
        Log.i(TAG, "artifact=" + output.getAbsolutePath() + " bytes=" + output.length());
        Log.i(TAG, "status=" + summarizeStatus(runner.status()));
    }

    private static String posterHtml() {
        return "<!doctype html><html><head><meta charset=\"utf-8\"><style>"
            + "@font-face{font-family:Inter;src:local(Arial);font-weight:100 900}"
            + "*{box-sizing:border-box}html,body{margin:0;width:640px;height:360px;overflow:hidden}"
            + "body{font-family:Inter,sans-serif;color:#f7f8fb;background:#10131a}"
            + ".poster{width:640px;height:360px;padding:38px 42px;display:flex;flex-direction:column;"
            + "justify-content:space-between;background:linear-gradient(135deg,#10131a,#23466e,#db5b3f)}"
            + "h1{font-size:46px;line-height:1;margin:24px 0 0}.eyebrow{color:#f5c26b;font-size:13px;letter-spacing:2px}"
            + ".subtitle{color:#c8d0dc;font-size:16px;max-width:430px}.footer{color:#aeb9c9;font-size:12px}"
            + "</style></head><body><div id=\"root\" data-composition-id=\"main\" data-start=\"0\""
            + " data-duration=\"1\" data-width=\"640\" data-height=\"360\"><div class=\"poster\">"
            + "<div><div class=\"eyebrow\">MOBILECODE / HYPERFRAMES</div><h1>Editable HTML Poster</h1>"
            + "<p class=\"subtitle\">Change the source, then export pixels or video.</p></div>"
            + "<div class=\"footer\">HTML is the source · pixels are the artifact</div></div></div>"
            + "<script>window.__timelines=window.__timelines||{};let t=0;const tl={pause(){return this;},"
            + "play(){return this;},duration(){return 1;},totalTime(v){if(typeof v===\"number\"){t=Math.max(0,Math.min(1,v));"
            + "document.querySelector(\"h1\").style.opacity=Math.min(1,t);return this;}return t;},seek(v){return this.totalTime(v);},"
            + "progress(v){return this.totalTime(v);}};window.__timelines['main']=tl;</script></body></html>";
    }

    private static void writeFile(File file, String content) throws Exception {
        try (FileOutputStream output = new FileOutputStream(file)) {
            output.write(content.getBytes(StandardCharsets.UTF_8));
        }
    }

    private static Map<String, Object> alpineManifestForDevice() {
        String abi = Build.SUPPORTED_ABIS.length > 0 ? Build.SUPPORTED_ABIS[0] : "arm64-v8a";
        Map<String, Object> manifest = new HashMap<>();
        manifest.put("version", "3.24.1");
        // The emulator's loopback is reverse-forwarded to a local HTTP cache
        // by the QA command, keeping Alpine apk extraction inside the device
        // while removing the slow CDN hop from the cold-start proof.
        manifest.put("repositoryBaseUrl", "http://10.0.2.2:8080");
        if (abi.startsWith("x86_64")) {
            manifest.put("id", "alpine-minirootfs-x86_64-3.24.1");
            manifest.put("arch", "x86_64");
            manifest.put("url", "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/alpine-minirootfs-3.24.1-x86_64.tar.gz");
            manifest.put("sha256", "41f73e3cf5fa919b8aa5ca6b30dc48f0da2720776d7423e2a7748211456fe081");
        } else {
            manifest.put("id", "alpine-minirootfs-aarch64-3.24.1");
            manifest.put("arch", "aarch64");
            manifest.put("url", "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/aarch64/alpine-minirootfs-3.24.1-aarch64.tar.gz");
            manifest.put("sha256", "f55a90f69052c5bd6f92cb09a8f47065970830b194c917a006fb94028e721259");
        }
        return manifest;
    }

    private static void assertSuccess(String label, Map<String, ?> result) {
        Log.i(TAG, label + "=" + summarize(result));
        assertEquals(label + " should succeed", true, result.get("success"));
    }

    private static void assertOutputContains(String label, Map<String, ?> result, String expected) {
        assertSuccess(label, result);
        assertTrue(label + " stdout should contain " + expected + ": " + summarize(result),
            String.valueOf(result.get("stdout")).toLowerCase().contains(expected.toLowerCase()));
    }

    private static String summarize(Map<String, ?> result) {
        String stdout = String.valueOf(result.get("stdout"));
        String stderr = String.valueOf(result.get("stderr"));
        return "success=" + result.get("success")
            + " failureKind=" + result.get("failureKind")
            + " exitCode=" + result.get("exitCode")
            + " durationMs=" + result.get("durationMs")
            + " stdout=" + stdout.replace('\n', ' ').trim()
            + " stderr=" + stderr.replace('\n', ' ').trim();
    }

    private static String summarizeStatus(Map<String, ?> status) {
        return "installed=" + status.get("installed")
            + " ready=" + status.get("ready")
            + " rootfsPath=" + status.get("rootfsPath")
            + " hyperframesCli=" + ((Map<?, ?>) status.get("packages")).get("hyperframesCli");
    }

    private static String tail(String value) {
        String normalized = value.replace('\n', ' ').trim();
        return normalized.length() <= 1400 ? normalized : normalized.substring(normalized.length() - 1400);
    }

    private static void deleteRecursively(File file) {
        if (!file.exists()) return;
        File[] children = file.listFiles();
        if (children != null) {
            for (File child : children) deleteRecursively(child);
        }
        file.delete();
    }
}
