# MobileCode Release QA

This checklist defines the deployable release path for the Flutter app, Android APK, and MobileCode Runtime providers.

## CI Gates

Required GitHub Actions before publishing:

- `.github/workflows/mobile-app-release.yml`
  - Builds the release Android APK on Ubuntu.
  - Builds and smoke-launches an iOS simulator app on macOS.
  - Builds an unsigned iOS device archive on macOS.
  - Uploads `mobilecode-${release_tag}.apk`, `mobilecode-ios-simulator-${release_tag}.zip`, `mobilecode-ios-smoke.png`, `ios-runner.log`, `mobilecode-ios-archive-${release_tag}.xcarchive.zip`, and `ios-archive-summary.txt` as workflow artifacts and optional GitHub Release assets.
  - The iOS archive is unsigned by default; signed `.ipa` output requires Apple signing secrets and provisioning profile configuration.
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

## 2026-06-19 HTML Open-With QA

Feature scope:

- `.html` file open intents with missing MIME.
- HTML shared through `EXTRA_TEXT`.
- Clear user-facing error when an external file cannot be read.
- Real third-party entry checks from Android Files / DocumentsUI, Chrome, and WeChat/chat tools.

Evidence summary:

| Entry | Result | Evidence |
| --- | --- | --- |
| Android Files / DocumentsUI | Passed | `mobile_agent/qa-output/html-open-real-app-20260619-204552/03-documentsui-opened-in-mobilecode.png` |
| Android resolver for `.html` | Passed | `mobile_agent/qa-output/html-open-real-app-20260619-204552/02-documentsui-after-file-tap.png` |
| Chrome download direct tap | Not passed on emulator | `mobile_agent/qa-output/html-open-real-app-20260619-204552/10-chrome-download-open-attempt.png` |
| Chrome share alternate path | Share-asset captured, keep separate from direct-tap support | `docs/assets/qa/mobilecode-20260619/08-chrome-share-alternate.png` |
| WeChat / chat tool | Not completed | Emulator package list did not include WeChat. Requires real phone or logged-in WeChat environment. |
| Public-safe screenshots | Captured | `docs/assets/qa/mobilecode-20260619/README.md` |

Release decision:

- Do not claim universal third-party HTML open support yet.
- It is safe to claim Android Files / DocumentsUI `.html` open-with support.
- Chrome direct download tap needs a product decision or real-device retest because Chrome opened the downloaded HTML itself through `content://media/external/downloads/64`.
- WeChat QA remains a physical-device or logged-in third-party-app task.
- Real-device rerun guide: `docs/mobilecode-third-party-html-qa.md`.
- Evidence helper script: `scripts/qa_mobilecode_html_real_device.sh`.

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

## Manual APK Validation

After downloading the release APK:

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
