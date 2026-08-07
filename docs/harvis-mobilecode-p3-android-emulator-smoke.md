# Harvis MobileCode P3 Android Emulator Smoke

This runbook defines the first P3 device target for the Harvis MobileCode lane.
It must run on Android Emulator before any real phone proof.

## Target

- App: MobileCode Android APK.
- Package: `com.mobilecode.app` by default.
- Activity: `.MainActivity` by default.
- Handoff fixture:
  `mobile_agent/test/fixtures/harvis_mobilecode_handoff.project_check.json`.
- Scope: install and launch MobileCode, capture evidence, and prove the
  project-check handoff fixture is present beside the device evidence.

This smoke does not send Lark messages, call Harvis, publish GitHub, or control
a physical phone.

## Command

From the repo root:

```bash
mobile_agent/tooling/harvis_mobilecode_android_smoke.sh \
  --build-debug \
  --package com.mobilecode.app \
  --activity .MainActivity
```

When multiple emulators are online:

```bash
mobile_agent/tooling/harvis_mobilecode_android_smoke.sh \
  --serial emulator-5554 \
  --build-debug
```

TCP emulator endpoints such as `127.0.0.1:7555` are accepted as emulator
targets.

For a Dev Harness package, pass the explicit package/activity/APK:

```bash
mobile_agent/tooling/harvis_mobilecode_android_smoke.sh \
  --serial emulator-5554 \
  --apk mobile_agent/build/app/outputs/flutter-apk/app-debug.apk \
  --package com.mobilecode.app.dev \
  --activity .MainActivity
```

## Evidence

The script writes to:

`mobile_agent/qa-output/harvis-mobilecode-android-smoke-<timestamp>/`

Required files:

- `summary.json`
- `adb-devices.txt`
- `device-props.txt`
- `apk-sha256.txt`
- `install.txt`
- `launch.txt`
- `window-focus.txt`
- `screenshot-main.png`
- `window-main.xml`
- `window-marker-scan.txt`
- `logcat.txt`
- `logcat-fatal-scan.txt`
- `handoff-fixture.json`

## Pass Criteria

`summary.json` must report:

- `install_ok=true`
- `launch_ok=true`
- `focus_ok=true`
- `ui_marker_ok=true`
- `logcat_clean=true`

Manual review must confirm:

- Screenshot shows MobileCode UI, not Android launcher or a permission-only
  blank state.
- UI XML contains stable MobileCode text such as `MobileCode`, `No messages
  yet`, `Mimo`, `Single-shot`, `任务派发`, or `能力中心`.
- Logcat has no app-scoped `FATAL EXCEPTION`, `E/flutter`, `ANR`,
  `MissingPluginException`, or `SIGSEGV`.
- The copied handoff fixture is the `project_check` fixture and contains an
  approval id.

## Boundary

This is only P3 emulator smoke readiness. It does not prove:

- Lark live delivery from MobileCode.
- Harvis live routing.
- Phone-use automation.
- Android real-device behavior.
- iOS simulator or iPhone behavior.

After this emulator smoke passes, the next P3 step is a single end-to-end
fixture route:

`handoff fixture -> MobileCode ActionEvidence -> lark-relay route-file -> Harvis Agent Room`

## Evidence Runs

### 2026-06-29 Android Emulator Smoke

- Evidence directory:
  `mobile_agent/qa-output/harvis-mobilecode-android-smoke-20260629-234636/`
- Emulator: `emulator-5554`
- Package: `com.mobilecode.app`
- APK SHA-256:
  `5acc3d3b6f68a84a62f22cf2f021273f739fa0844cdb79f07e2e8fcaaf64f07e`
- Result: `summary.json` reports `ok=true`.
- Install: `Success`.
- Launch: `Status: ok`, activity `com.mobilecode.app/.MainActivity`.
- Focus: `com.mobilecode.app/com.mobilecode.app.MainActivity`.
- UI evidence: screenshot shows the MobileCode main UI with `No messages yet`;
  UI XML contains `MobileCode`, `No messages yet`, `Mimo`, `Single-shot`, and
  `任务派发`.
- Logcat fatal scan: no `FATAL EXCEPTION`, `E/flutter`, `ANR`,
  `MissingPluginException`, or `SIGSEGV`.
- Handoff fixture: copied as `handoff-fixture.json`, action `project_check`,
  approval id `appr_project_check_001`, expected evidence type includes
  `mobilecode.action_evidence.v1`.

Boundary: this proves P3 emulator install/launch/evidence readiness only. It
does not prove live Lark delivery, live Harvis routing, phone-use automation,
Android real-device behavior, or iOS behavior.
