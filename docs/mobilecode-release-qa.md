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
  - Uploads `mobilecode-v0.1.0.apk` as an artifact and GitHub Release asset.

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

After downloading the release APK:

```bash
adb install -r mobilecode-v0.1.0.apk
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
