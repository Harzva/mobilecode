package com.mobilecode.app;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import android.content.Context;
import android.os.Build;
import android.util.Log;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.util.HashMap;
import java.util.Map;
import org.junit.Test;
import org.junit.runner.RunWith;

@RunWith(AndroidJUnit4.class)
public class LinuxSandboxRunnerInstrumentedTest {
    private static final String TAG = "MobileCodeLinuxProof";

    @Test
    public void linuxSandboxRunnerRunsProofTasksAndPackageProfiles() {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        LinuxSandboxRunner runner = new LinuxSandboxRunner(context);

        Log.i(TAG, "device model=" + Build.MODEL);
        Log.i(TAG, "android release=" + Build.VERSION.RELEASE + " sdk=" + Build.VERSION.SDK_INT);
        Log.i(TAG, "abis=" + String.join(",", Build.SUPPORTED_ABIS));

        Map<String, Object> setup = runner.setup(alpineManifestForDevice());
        assertSuccess("setup", setup);
        Log.i(TAG, "setup=" + summarize(setup));

        assertSuccess("package_install base", runner.runTypedTask(
            "package_install",
            packagePayload("base")
        ));
        assertSuccess("package_install devBasic", runner.runTypedTask(
            "package_install",
            packagePayload("devBasic")
        ));
        assertSuccess("package_install pythonPack", runner.runTypedTask(
            "package_install",
            packagePayload("pythonPack")
        ));
        assertSuccess("package_install nodePack", runner.runTypedTask(
            "package_install",
            packagePayload("nodePack")
        ));
        assertSuccess("package_install larkCli", runner.runTypedTask(
            "package_install",
            packagePayload("larkCli")
        ));

        assertOutputContains("apk_version", runner.runTypedTask("apk_version", new HashMap<>()), "apk-tools");
        assertOutputContains("git_version", runner.runTypedTask("git_version", new HashMap<>()), "git version");
        assertOutputContains("node_version", runner.runTypedTask("node_version", new HashMap<>()), "v");
        assertOutputContains("npm_version", runner.runTypedTask("npm_version", new HashMap<>()), ".");
        assertOutputContains("lark_cli_probe", runner.runTypedTask("lark_cli_probe", new HashMap<>()), ".");

        Log.i(TAG, "status=" + runner.status());
    }

    private static Map<String, Object> alpineManifestForDevice() {
        String abi = Build.SUPPORTED_ABIS.length > 0 ? Build.SUPPORTED_ABIS[0] : "arm64-v8a";
        Map<String, Object> manifest = new HashMap<>();
        manifest.put("version", "3.24.1");
        if (abi.startsWith("x86_64")) {
            manifest.put("id", "alpine-minirootfs-x86_64-3.24.1");
            manifest.put("arch", "x86_64");
            manifest.put(
                "url",
                "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/alpine-minirootfs-3.24.1-x86_64.tar.gz"
            );
            manifest.put("sha256", "41f73e3cf5fa919b8aa5ca6b30dc48f0da2720776d7423e2a7748211456fe081");
        } else {
            manifest.put("id", "alpine-minirootfs-aarch64-3.24.1");
            manifest.put("arch", "aarch64");
            manifest.put(
                "url",
                "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/aarch64/alpine-minirootfs-3.24.1-aarch64.tar.gz"
            );
            manifest.put("sha256", "f55a90f69052c5bd6f92cb09a8f47065970830b194c917a006fb94028e721259");
        }
        return manifest;
    }

    private static Map<String, Object> packagePayload(String profileId) {
        Map<String, Object> payload = new HashMap<>();
        payload.put("approved", true);
        payload.put("profileId", profileId);
        return payload;
    }

    private static void assertSuccess(String label, Map<String, ?> result) {
        Log.i(TAG, label + "=" + summarize(result));
        assertEquals(label + " should succeed", true, result.get("success"));
    }

    private static void assertOutputContains(String label, Map<String, ?> result, String expected) {
        assertSuccess(label, result);
        String stdout = String.valueOf(result.get("stdout"));
        assertTrue(label + " stdout should contain " + expected + ": " + stdout, stdout.contains(expected));
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
}
