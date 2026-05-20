# MobileCode Release QA

This checklist defines the deployable release path for the Flutter app, Android APK, and MobileCode Runtime providers.

## CI Gates

Required GitHub Actions before publishing:

- `.github/workflows/mobile-runtime-ci.yml`
  - Runs `flutter pub get`.
  - Runs `flutter analyze` on the runtime provider files, Home/Build runtime surfaces, and runtime tests.
  - Runs RuntimeProvider tests for `RuntimeManager` and `MobileCodeHelperProvider`.
  - Compiles `mobile_agent/tooling/mobilecode_helper_daemon.py`.
  - Compiles `mobile_agent/tooling/prepare_android_project.py`, which injects the native Helper foreground service into generated Android projects.
  - Starts the helper daemon with a localhost token and smoke tests `/v1/health`, `/v1/execute`, `/v1/execute/stream`, `/v1/project/preflight`, `/v1/tasks/current`, `/v1/tasks`, and `/v1/tasks/:id/logs`.
- `.github/workflows/android-app-test.yml`
  - Builds a debug APK.
  - Installs and launches it on an Android emulator.
  - Captures screenshot and logcat artifacts.
  - Fails on common Android crash signatures.
- `.github/workflows/android-apk.yml`
  - Builds the release APK.
  - Uses stable signing when release keystore secrets are configured.
  - Uploads `mobilecode-v0.1.10.apk` as an artifact and GitHub Release asset.

## v0.1.10 Release Candidate

Release candidate:

- Branch: `v011-streaming-fix`
- App/build content commit: `39316ab0f1f466d1a9973bda5556ada06d9f2cf2`
- CI smoke workflow commit: `c0dc62fe0329b912a8337be353c3819f4fb1096f`
- Release: `https://github.com/Harzva/mobilecode/releases/tag/v0.1.10`
- APK asset: `https://github.com/Harzva/mobilecode/releases/download/v0.1.10/mobilecode-v0.1.10.apk`
- APK SHA256: `2603fc0b1ad4f5b5e4bb9b0a3c9f961b078e545174f6792972b87f81c5c8166c`

Required CI evidence:

| Gate | Run | Result |
| --- | --- | --- |
| Mobile Runtime CI | `https://github.com/Harzva/mobilecode/actions/runs/26015207199` | Passed |
| Build Android APK | `https://github.com/Harzva/mobilecode/actions/runs/26015207331` | Passed |
| Android App Smoke Test | `https://github.com/Harzva/mobilecode/actions/runs/26015653307` | Passed |

Validated coverage:

- Flutter scoped analyzer passed for runtime and Home entry surfaces.
- RuntimeProvider tests passed.
- Helper daemon protocol smoke passed.
- Android release APK built and uploaded as the `v0.1.10` release asset.
- Android emulator smoke verified Helper health/execute, launched the main app, captured screenshot/logcat artifacts, and checked common crash signatures.
- Runtime UX polish is included: folded long code viewing, bottom agent trace progress, respectful chat scrolling, and visual Role Recruit / RR mode without real multi-agent parallelism.

Manual device coverage:

- Verify GitHub Repo Hub with a signed-in account: current-user repos load, search/language/Pages/local filters work, watchlist survives app restart, and a repo can be added to the phone workspace.
- Verify repo cards show public/private, stars, language, Pages, default branch, recent push time, and local status without overflowing on a 360dp-wide screen.
- Verify an artifact stored under a remote-linked repo folder defaults the GitHub Pages deploy target to that bound owner/repo and explains token visibility errors.
- Verify Actions sheet refreshes workflow jobs, can dispatch a workflow, downloads artifact zip to the app-owned workspace, records it in Recent downloads, opens the zip/folder when Android allows it, and copies the local zip path.
- Verify Files sheet can browse repository folders, open a text file, edit it, commit through the GitHub Contents API with an explicit commit message, and recover from SHA conflicts by reloading the remote file.

## v0.1.6 Release Evidence

Release candidate:

- Branch: `v011-streaming-fix`
- App/build content commit: `f1a6381abbc9912c35d8ff712ef7ac0e9d0edd89`
- Release: `https://github.com/Harzva/mobilecode/releases/tag/v0.1.6`
- APK asset: `https://github.com/Harzva/mobilecode/releases/download/v0.1.6/mobilecode-v0.1.6.apk`
- APK SHA256: `4dd3a7e6fd266874b54d4ed060b27172e915716061ce16ff5ef6e2bb03641622`

Required CI evidence:

| Gate | Run | Result |
| --- | --- | --- |
| Mobile Runtime CI | `https://github.com/Harzva/mobilecode/actions/runs/25986990236` | Passed |
| Build Android APK | `https://github.com/Harzva/mobilecode/actions/runs/25986990949` | Passed |
| Android App Smoke Test | `https://github.com/Harzva/mobilecode/actions/runs/25986991684` | Passed |

Validated coverage:

- Flutter scoped analyzer passed for runtime and Home entry surfaces.
- RuntimeProvider tests passed.
- Helper daemon protocol smoke passed.
- Android release APK built and uploaded as the v0.1.6 release asset.
- Android emulator smoke installed and launched the debug APK, captured screenshot/logcat artifacts, and checked common crash signatures.
- GitHub Pages deploy passed for the demo Pages site.

Manual device coverage:

- Physical-device validation remains required before promoting `v0.1.6` beyond prerelease.
- Verify generated HTML can pass/fail the pre-publish check, GitHub Pages errors explain token/permission recovery, the published work card opens Pages/repo and shows a live thumbnail, Lark CLI structured actions remain dry-run unless explicitly reviewed, and the new theme/avatar polish does not create small-screen overflow.

## v0.1.5 Release Evidence

Release candidate:

- Branch: `v011-streaming-fix`
- App/build content commit: pending CI
- Release: pending
- APK asset: pending
- APK SHA256: pending

Required CI evidence:

| Gate | Run | Result |
| --- | --- | --- |
| Mobile Runtime CI | pending | Pending |
| Build Android APK | pending | Pending |
| Android App Smoke Test | pending | Pending |

Validated coverage:

- Pending after GitHub Pages pre-publish checks, published work cards with live Pages thumbnail, and Lark CLI structured dry-run actions pass CI.

## v0.1.4 Release Evidence

Release candidate:

- Branch: `v011-streaming-fix`
- App/build content commit: pending CI
- Release: pending
- APK asset: pending
- APK SHA256: pending

Required CI evidence:

| Gate | Run | Result |
| --- | --- | --- |
| Mobile Runtime CI | pending | Pending |
| Build Android APK | pending | Pending |
| Android App Smoke Test | pending | Pending |

Validated coverage:

- Pending after HTML/UI skill prompt injection, account-free curated GitHub skill/MCP source adapter, and Node 24 Actions updates pass CI.

## v0.1.3 Release Evidence

Release candidate:

- Branch: `v011-streaming-fix`
- App/build content commit: `1f266ca3c85810efdc0e609f8db6a99947898acf`
- Release: `https://github.com/Harzva/mobilecode/releases/tag/v0.1.3`
- APK asset: `https://github.com/Harzva/mobilecode/releases/download/v0.1.3/mobilecode-v0.1.3.apk`
- APK SHA256: `50e53bd2fb820aa3658bc6e6ff0fc3afab1a6c1ec69722013f4247a027561390`

Required CI evidence:

| Gate | Run | Result |
| --- | --- | --- |
| Mobile Runtime CI | `https://github.com/Harzva/mobilecode/actions/runs/25982172509` | Passed |
| Build Android APK | `https://github.com/Harzva/mobilecode/actions/runs/25982172502` | Passed |
| Android App Smoke Test | `https://github.com/Harzva/mobilecode/actions/runs/25982172557` | Passed |

Validated coverage:

- Flutter scoped analyzer passed for runtime and Home entry surfaces.
- RuntimeProvider tests passed.
- Helper daemon protocol smoke passed for health, execute, stream, task history, task logs, cancel, and project preflight.
- Android release APK build passed and uploaded the v0.1.3 release asset.
- Android emulator smoke built the debug APK, installed and launched the app, captured screenshot/logcat artifacts, and checked common crash signatures.

## v0.1.2 Release Evidence

Release candidate:

- Branch: `v011-streaming-fix`
- App/build content commit: `1e53204`
- Release: `https://github.com/Harzva/mobilecode/releases/tag/v0.1.2`
- APK asset: `https://github.com/Harzva/mobilecode/releases/download/v0.1.2/mobilecode-v0.1.2.apk`
- APK SHA256: `69295185daa8f07af5d3d9145e85d961993a4ee80432acbff104961ef19c9f4f`

Required CI evidence:

| Gate | Run | Result |
| --- | --- | --- |
| Mobile Runtime CI | `https://github.com/Harzva/mobilecode/actions/runs/25980342388` | Passed |
| Build Android APK | `https://github.com/Harzva/mobilecode/actions/runs/25980342638` | Passed |
| Android App Smoke Test | `https://github.com/Harzva/mobilecode/actions/runs/25980342398` | Passed |

Validated coverage:

- Flutter scoped analyzer passed for runtime and Home entry surfaces.
- RuntimeProvider tests passed.
- Helper daemon protocol smoke passed for health, execute, stream, task history, task logs, cancel, and project preflight.
- Android release APK build passed and uploaded the release asset.
- Android emulator smoke installed the debug APK, started the Helper launcher, verified localhost Helper health and execute, launched the main app, captured screenshot/logcat artifacts, and checked common crash signatures.

Manual device coverage:

- Local `adb devices` showed no online device on 2026-05-17, so physical-device validation remains a manual release step.
- Before promoting `v0.1.2` beyond prerelease, verify provider/base URL settings, normal chat streaming, agent pause, new chat creation, recent chat turn counts, generated artifact browser preview, trace-step detail sheets, and Runtime Diagnostics on a real Android device.

## CI Artifact & Run References

Verified CI runs for the v1 runtime closure:

| Workflow | Run ID | Commit | Status | Artifact | URL |
|----------|--------|--------|--------|----------|-----|
| Mobile Runtime CI | `25960104143` | `8b051e4a76d6bc5348506071c208332c7bf93e2a` | PASSED | `mobilecode-helper-smoke` | https://github.com/Harzva/mobilecode/actions/runs/25960104143 |
| Android App Smoke Test | `25959749508` | `1bef790237fb38eefc6eb7651530e8a3c63fbeb1` | PASSED | `mobilecode-android-smoke` | https://github.com/Harzva/mobilecode/actions/runs/25959749508 |
| Build Android APK | `25960889017` | `594e6e51e794600e036b8a431f464dbf6f914313` | PASSED | `mobilecode-apk` | https://github.com/Harzva/mobilecode/actions/runs/25960889017 |

### Downloading CI Artifacts

Artifacts are uploaded by GitHub Actions and can be downloaded via the `gh` CLI or the Actions UI.

**Mobile Runtime CI** (run `25960104143`) — artifact `mobilecode-helper-smoke`:

```bash
gh run download 25960104143 --name mobilecode-helper-smoke --dir qa/ci-artifacts
```

This creates `qa/ci-artifacts/mobilecode-helper-smoke/` containing:
- `helper-health.json`, `helper-execute.json`, `helper-stream.ndjson`, `helper-task.json`, `helper-tasks.json`, `helper-task-logs.json` — helper protocol smoke evidence.
- `helper-project-preflight.json` — project preflight smoke evidence.
- `runtime-web-smoke.json` — web smoke test summary (7-step protocol result).

**Android App Smoke Test** (run `25959749508`) — artifact `mobilecode-android-smoke`:

```bash
gh run download 25959749508 --name mobilecode-android-smoke --dir qa/ci-artifacts
```

This creates `qa/ci-artifacts/mobilecode-android-smoke/` containing:
- `android-helper-health.json`, `android-helper-execute.json`, `android-helper-task.json` — emulator helper smoke evidence.
- `window-focus.txt` — window focus verification.
- `mobilecode-android-smoke.png` — home-screen capture after launch.
- `android-logcat.txt` — logcat dump from the test run.

Note: This artifact contains emulator smoke evidence only. It does **not** contain an installable APK.

**Build Android APK** (run `25960889017`) — artifact `mobilecode-apk`:

```bash
gh run download 25960889017 --name mobilecode-apk --dir qa/ci-artifacts
```

This creates `qa/ci-artifacts/mobilecode-apk/` containing:
- `mobilecode-v0.1.0.apk` — installable release APK.

This is the only artifact that contains an installable APK. The APK is also uploaded as a GitHub Release asset when release signing secrets are configured.

Alternatively, download from the browser:
1. Open the run URL listed above.
2. Scroll to **Artifacts** at the bottom of the run page.
3. Click each artifact name to download the ZIP.

## Manual Verification: Download → Install → Runtime Smoke

Full end-to-end manual verification using CI artifacts.

### Prerequisites

- Android device or emulator with USB debugging enabled.
- `adb` installed and on PATH.
- `gh` CLI authenticated (for artifact download).

### Steps

**1. Download artifacts**

```bash
gh run download 25960104143 --name mobilecode-helper-smoke --dir qa/ci-artifacts
gh run download 25959749508 --name mobilecode-android-smoke --dir qa/ci-artifacts
gh run download 25960889017 --name mobilecode-apk --dir qa/ci-artifacts
```

**2. Install the APK**

The APK comes from the `mobilecode-apk` artifact (Build Android APK workflow), not from the Android App Smoke Test artifact.

```bash
adb install -r qa/ci-artifacts/mobilecode-apk/mobilecode-v0.1.0.apk
```

If install fails with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, uninstall first:

```bash
adb uninstall com.mobilecode.mobile_agent
adb install -r qa/ci-artifacts/mobilecode-apk/mobilecode-v0.1.0.apk
```

**3. Launch the app**

```bash
adb shell monkey -p com.mobilecode.mobile_agent -c android.intent.category.LAUNCHER 1
```

Wait 3-5 seconds for the app to reach the home screen.

**4. Verify home screen renders**

```bash
adb shell screencap -p /sdcard/mobilecode-home.png
adb pull /sdcard/mobilecode-home.png qa/manual-verification-home.png
```

Open the screenshot and confirm:
- Home screen is visible (no Flutter red-screen error).
- Runtime banner area renders (may show "Runtime not started" — that is expected).

**5. Check Runtime Diagnostics**

In the app:
- Tap the Runtime Diagnostics icon (gear/info icon in the toolbar).
- Verify the diagnostics sheet opens without crash.
- Verify the provider list shows at least one entry (Helper or External Termux or Cloud or WebViewOnly).

**6. Run helper smoke (if helper daemon is reachable)**

If the device can reach the host helper daemon:

```bash
# On host machine, start helper daemon
python3 mobile_agent/tooling/mobilecode_helper_daemon.py \
  --host 0.0.0.0 --port 8765 \
  --workspace-root "$HOME/mobilecode_projects" \
  --auth-token "$MOBILECODE_HELPER_TOKEN"

# On device, use the app's Tools -> Runtime providers to connect,
# then trigger Project Preflight from Runtime Actions.
```

Expected: preflight completes, project markers detected, no crash.

**7. Collect verification evidence**

```bash
adb logcat -d -t 1200 > qa/manual-verification-logcat.txt
adb shell screencap -p /sdcard/mobilecode-post-check.png
adb pull /sdcard/mobilecode-post-check.png qa/manual-verification-post-check.png
```

### Pass criteria

- APK installs without error.
- App launches beyond splash screen.
- Home Runtime banner renders without Flutter red-screen errors.
- Runtime Diagnostics sheet opens and shows provider list.
- Logcat has no `FATAL EXCEPTION`, `AndroidRuntime`, `MissingPluginException`, or `ANR in com.mobilecode.mobile_agent`.

## Failure Evidence & Recovery

When a manual verification step fails, record evidence before retrying.

### Recording failure evidence

```bash
# Capture logcat immediately after failure
adb logcat -d -t 3000 > qa/failure-logcat-$(date +%Y%m%d-%H%M%S).txt

# Capture current screen
adb shell screencap -p /sdcard/mobilecode-failure.png
adb pull /sdcard/mobilecode-failure.png qa/failure-screenshot-$(date +%Y%m%d-%H%M%S).png

# Record device info
adb shell getprop ro.build.fingerprint > qa/device-info.txt
adb shell getprop ro.build.version.sdk >> qa/device-info.txt
```

### Common failures and recovery

| Failure | Evidence | Recovery |
|---------|----------|----------|
| APK install fails | `adb install` stderr | Check ABI match; uninstall old version first; verify APK is not corrupted (`unzip -t`) |
| App crashes on launch | Logcat `FATAL EXCEPTION` | Check `AndroidRuntime` stack trace; verify `minSdkVersion` matches device; check for missing plugin |
| Flutter red screen | Screenshot + logcat | Check `FlutterError` in logcat; likely a Dart exception — file issue with stack trace |
| Runtime banner not visible | Screenshot | Check if runtime provider initialization failed in logcat; try Tools -> Runtime providers refresh |
| Diagnostics sheet crash | Logcat `ANR` or exception | Check `FlutterError` or `AndroidRuntime` in logcat; capture the diagnostics entry point used |
| Helper daemon unreachable | App shows "Helper not connected" | Verify host daemon is running and port is open; check `adb reverse tcp:8765 tcp:8765` for emulator |

### Where to file evidence

- Attach failure screenshots and logcat to the relevant GitHub issue or PR comment.
- For CI-related failures, reference the run URL and artifact name.
- For local-only failures, include device info (`ro.build.fingerprint`, SDK version) in the report.

## Latest APK Evidence

Build run: [25960889017](https://github.com/Harzva/mobilecode/actions/runs/25960889017), head `594e6e51e794600e036b8a431f464dbf6f914313`.

| Evidence | Value |
|----------|-------|
| APK file | `mobilecode-v0.1.0.apk` |
| APK size | `53051517` bytes |
| Local SHA256 | `A13C0381EE2DEC6DA4C055CEC86A0990AE67344B7FE696641EB0B2682A8F928D` |
| GitHub Release asset digest | `sha256:a13c0381ee2dec6da4c055cec86a0990ae67344b7fe696641eb0b2682a8f928d` |
| Checksum match | Verified |
| Release asset updated | `2026-05-16T11:40:29Z` |
| Manual install/launch | **BLOCKED** — no online adb device |

Local QA script `qa/release-apk-25960889017/summary.json`: status `blocked`, error `No online adb device. Start MuMu or another emulator and rerun.`

**Recovery steps**: start MuMu or another Android emulator, ensure `adb devices` shows the device, then rerun:

```bash
python "C:\Users\harzva\.codex\skills\android-release-emulator-qa-skill\scripts\android_release_qa.py" \
  --apk "qa\build-apk-25960889017\mobilecode-v0.1.0.apk" \
  --package com.mobilecode.mobile_agent \
  --github-release Harzva/mobilecode@v0.1.0 \
  --output "qa\release-apk-25960889017"
```

## Android Release Signing

Configure these repository secrets for stable release signing:

- `MOBILECODE_RELEASE_KEYSTORE_BASE64`
- `MOBILECODE_RELEASE_STORE_PASSWORD`
- `MOBILECODE_RELEASE_KEY_ALIAS`
- `MOBILECODE_RELEASE_KEY_PASSWORD`

Optional private/debug provider injection:

- `MOBILECODE_MANAGED_API_KEY`

Treat APKs built with embedded debug provider credentials as private artifacts. Client-side secrets can be extracted from compiled apps.

## Runtime Smoke Test

Android foreground-service prototype:

- Open MobileCode.
- Use Home or Tools -> Runtime providers.
- The app calls `startHelperService` through the native `mobilecode/system_tools` channel.
- Verify the Runtime banner reports `MobileCode Helper Service` and capabilities include `shell` and `bg`.
- Open Runtime Diagnostics and verify the provider list, fallback visibility, and task snapshot panels render.

Termux/Python helper daemon fallback:

```bash
cd mobile_agent
mkdir -p "$HOME/mobilecode_projects"
python3 tooling/mobilecode_helper_daemon.py \
  --host 127.0.0.1 \
  --port 8765 \
  --workspace-root "$HOME/mobilecode_projects" \
  --auth-token "$MOBILECODE_HELPER_TOKEN"
```

Probe from another shell:

```bash
AUTH_HEADER="X-MobileCode-Token: $MOBILECODE_HELPER_TOKEN"
curl -fsS -H "$AUTH_HEADER" http://127.0.0.1:8765/v1/health
curl -fsS -H "$AUTH_HEADER" -H 'Content-Type: application/json' \
  -X POST http://127.0.0.1:8765/v1/execute \
  -d '{"command":"python3 -c \"print(42)\"","cwd":"'$HOME'/mobilecode_projects","timeoutMs":10000}'
curl -fsS -N -H "$AUTH_HEADER" -H 'Content-Type: application/json' \
  -H 'Accept: application/x-ndjson' \
  -X POST http://127.0.0.1:8765/v1/execute/stream \
  -d '{"command":"python3 -c \"print(43)\"","cwd":"'$HOME'/mobilecode_projects","timeoutMs":10000}'
curl -fsS -H "$AUTH_HEADER" http://127.0.0.1:8765/v1/tasks/current
curl -fsS -H "$AUTH_HEADER" 'http://127.0.0.1:8765/v1/tasks?limit=5'
curl -fsS -H "$AUTH_HEADER" 'http://127.0.0.1:8765/v1/tasks/<taskId>/logs?limit=50'
curl -fsS -H "$AUTH_HEADER" -H 'Content-Type: application/json' \
  -X POST http://127.0.0.1:8765/v1/project/preflight \
  -d '{"cwd":"'$HOME'/mobilecode_projects"}'
```

Expected result:

- `/v1/health` returns `ready: true`.
- `/v1/execute` returns `exitCode: 0`.
- `/v1/execute/stream` emits at least one `stdout` event and one `exit` event.
- `/v1/tasks/current` returns a task object with `taskId`, `status`, `failureKind`, and recent `logs`.
- `/v1/tasks` returns persisted task history after daemon restart; interrupted running tasks are marked `lost`/`runtimeLost`.
- `/v1/tasks/:id/logs` returns recent logs for the selected task.
- `/v1/project/preflight` returns project markers without requiring shell-specific `find` behavior.
- MobileCode Home/Tools shows a Runtime-ready banner when the Helper provider is reachable.

## Small Web Project Runtime Smoke

End-to-end smoke verifying the helper daemon can manage a minimal web project
through create/import -> build/test -> preview/recovery.

### Local verification

```bash
python3 mobile_agent/tooling/runtime_web_smoke.py
```

Exit 0 means all steps passed. The script prints a JSON summary to stdout.

### CI verification

The `helper-daemon-smoke` job in `.github/workflows/mobile-runtime-ci.yml`
runs the same script automatically. The output is uploaded as
`artifacts/runtime-web-smoke.json` in the `mobilecode-helper-smoke` artifact.

### Steps exercised

1. `/v1/health` - daemon is ready and authenticated.
2. `/v1/project/preflight` - detects `package.json` in the workspace.
3. `/v1/execute` (test) - runs `python3 -c "print('test passed')"`, expects
   exit code 0 and stdout containing `test passed`.
4. `/v1/execute` (build) - copies `index.html` into `dist/index.html` without
   npm install or network. Expects exit code 0 and `dist/index.html` existing.
5. `/v1/tasks?limit=10` - at least 2 tasks recorded (test + build).
6. `/v1/tasks/:id/logs` - build task has logs.
7. Preview evidence - `dist/index.html` is readable and contains the expected
   content. On-device WebView preview uses this build artifact.

### Expected result

All 7 steps report `ok: true`. The JSON output has `"passed": true`.

### Failure recovery

- If the daemon fails to start, check that port is not in use and Python 3.10+
  is available.
- If `/v1/health` times out, increase the timeout or check for firewall
  blocking localhost.
- If build fails, verify `python3` and `shutil` are available (standard
  library).
- If `dist/index.html` is missing, the build command may have run in the wrong
  working directory; check the `cwd` field in the execute response.

## Manual APK Validation

After downloading the release APK from the `mobilecode-apk` artifact (Build Android APK workflow) or from a local build output:

```bash
adb install -r mobilecode-v0.1.10.apk
adb shell monkey -p com.mobilecode.mobile_agent -c android.intent.category.LAUNCHER 1
adb shell pidof com.mobilecode.mobile_agent
adb logcat -d -t 1200 > android-logcat.txt
```

Pass criteria:

- App launches beyond splash.
- Home Runtime banner renders without Flutter red-screen errors.
- Tools -> Runtime providers can detect Helper or External Termux fallback.
- Runtime Diagnostics can refresh without starting a crashing foreground service.
- Build / release page exposes structured runtime actions without missing plugin errors.
- Runtime Actions can run Project Preflight, detect `package.json` / `pubspec.yaml` / `requirements.txt` / `pyproject.toml`, then run the Validate loop with the selected profile.
- Validate stops at the first failed step, shows a recovery hint, and can retry the failed step after runtime refresh.
- Logcat has no `FATAL EXCEPTION`, `AndroidRuntime`, `MissingPluginException`, or `ANR in com.mobilecode.mobile_agent`.

## Release Readiness

Publish only when:

- Runtime provider selection degrades cleanly: Helper > External Termux > Cloud > WebView-only.
- Unsupported tasks explain the missing capability and recovery action.
- Helper command execution is workspace-bounded, allowlisted, timed, and log-streamable.
- Helper task state is recoverable after app reconnect and reports `lost` after helper restart.
- APK artifact, smoke screenshot, logcat, helper smoke artifacts, and release notes are attached or linked.
