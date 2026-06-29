# Harvis MobileCode P4/P5 Live Worker And Phone-Use

This runbook continues the Harvis MobileCode lane after the P1/P2 protocol
bridge and P3 Android Emulator install smoke.

## P4 Live Bidirectional Worker

Goal:

`Harvis handoff -> MobileCode remote worker ACK -> project_check/validate -> ActionEvidence -> lark-relay -> Harvis Agent Room`

Boundary:

- The worker lives in MobileCode tooling, not inside `lark-relay`.
- `lark-relay` remains transport and Harvis routing glue.
- MobileCode does not store Lark tokens, Harvis secrets, cookies, or `.env`
  values.
- The worker only accepts approved `mobilecode.handoff.v1` tasks.
- P4 actions are limited to `project_check` and `validate`.
- P5 adds a separate `phone_use_emulator` action. It must target
  `android_emulator` and still refuses physical devices.
- P4 still rejects phone/emulator/simulator-required handoffs.

Run once with the checked-in fixture:

```bash
mkdir -p mobile_agent/.harvis-mobilecode/inbox
cp mobile_agent/test/fixtures/harvis_mobilecode_handoff.project_check.json \
  mobile_agent/.harvis-mobilecode/inbox/handoff.project_check.json

python3 mobile_agent/tooling/mobilecode_remote_worker.py --once
```

Route ACK and ActionEvidence through `lark-relay` when a local relay config is
available:

```bash
python3 mobile_agent/tooling/mobilecode_remote_worker.py \
  --once \
  --route \
  --lark-relay-bin /path/to/lark-relay/src/cli.js \
  --relay-config /path/to/lark-relay.config.json \
  --chat-id <allowed-chat-id> \
  --sender-id mobilecode-remote-worker
```

Evidence files are written under:

`mobile_agent/.harvis-mobilecode/outbox/`

Expected files:

- `*.ack.json`
- `*.ack-event.json`
- `*.action-evidence.json`
- `*.action-evidence-event.json`
- optional `*.route-result.json` files when `--route` is enabled

Validate handoff fixture:

`mobile_agent/test/fixtures/harvis_mobilecode_handoff.validate.json`

Phone-use handoff fixture:

`mobile_agent/test/fixtures/harvis_mobilecode_handoff.phone_use_emulator.json`

## P5 Android Emulator Phone-Use Primitive

Goal:

`observe screenshot -> tap -> type -> assert UI -> evidence`

Boundary:

- Android Emulator only.
- Refuses physical Android devices.
- Does not send Lark messages.
- Does not call Harvis.
- Does not publish GitHub.
- Does not count as real-device phone-use proof.

Command:

```bash
mobile_agent/tooling/harvis_mobilecode_phone_use_emulator_smoke.sh \
  --serial emulator-5554 \
  --build-debug
```

When the app is already installed:

```bash
mobile_agent/tooling/harvis_mobilecode_phone_use_emulator_smoke.sh \
  --serial emulator-5554 \
  --skip-install
```

The script extracts the first `EditText` from the UI hierarchy and taps its
center. If the target screen changes, pass explicit coordinates:

```bash
mobile_agent/tooling/harvis_mobilecode_phone_use_emulator_smoke.sh \
  --serial emulator-5554 \
  --tap-x 360 \
  --tap-y 1180
```

Evidence files are written under:

`mobile_agent/qa-output/harvis-mobilecode-phone-use-<timestamp>/`

Required pass checks in `summary.json`:

- `install_ok`
- `launch_ok`
- `observe_before_ok`
- `tap_ok`
- `type_ok`
- `assert_ui_ok`
- `logcat_clean`

The same primitive is also exposed through the P5 `phone_use_emulator`
approval-gated handoff action in `mobilecode_remote_worker.py`. Real-device
proof remains a separate follow-up with an explicit target and evidence
contract.

## P5 Android Real-Device Proof Lane

Goal:

`physical Android device -> observe screenshot -> tap -> type -> assert UI -> evidence`

Boundary:

- Physical Android device only.
- Requires `--serial SERIAL`.
- Requires `--allow-real-device`.
- Refuses emulators.
- Device must be unlocked and visible to the operator.
- Does not send Lark messages.
- Does not call Harvis.
- Does not publish GitHub.

Command:

```bash
python3 mobile_agent/tooling/harvis_mobilecode_phone_use_real_device_smoke.py \
  --serial <physical-android-serial> \
  --allow-real-device \
  --apk mobile_agent/build/app/outputs/flutter-apk/app-debug.apk \
  --package com.mobilecode.app \
  --activity .MainActivity
```

Evidence files are written under:

`mobile_agent/qa-output/harvis-mobilecode-phone-use-real-device-<timestamp>/`

Required pass checks in `summary.json`:

- `install_ok`
- `launch_ok`
- `observe_before_ok`
- `tap_ok`
- `type_ok`
- `assert_ui_ok`
- `focus_ok`
- `logcat_clean`

## Evidence Runs

### 2026-06-30 P4 Worker Live Harvis Route

- Input: `mobile_agent/test/fixtures/harvis_mobilecode_handoff.project_check.json`.
- Command:
  `python3 mobile_agent/tooling/mobilecode_remote_worker.py --once --route ...`
- Result: worker accepted `hm_task_project_check_001`, wrote ACK and
  `mobilecode.action_evidence.v1`.
- Relay route: both ACK and ActionEvidence event files were passed to
  `lark-relay route-file --no-reply` with live localhost Harvis routing enabled.
- Relay evidence result: both route attempts returned `failureKind=none`.
- Harvis result: `routerMessage.ok=true`, `agentRoomMessage.ok=true`, and
  `taskStatus.ok=true` for both ACK and ActionEvidence.
- Boundary: Lark reply was dry-run; no Lark message was sent by this
  verification.

### 2026-06-30 P4 Validate Live Harvis Route

- Input: `mobile_agent/test/fixtures/harvis_mobilecode_handoff.validate.json`.
- Result: worker accepted `hm_task_validate_001`, validated the checked-in
  `project_check` fixture JSON, and wrote `mobilecode.action_evidence.v1`.
- Relay route: ACK and ActionEvidence event files were passed to
  `lark-relay route-file --no-reply` with live localhost Harvis routing enabled.
- Harvis result: `routerMessage.ok=true`, `agentRoomMessage.ok=true`, and
  `taskStatus.ok=true` for both ACK and ActionEvidence.
- Boundary: Lark reply was dry-run; no Lark message was sent by this
  verification.

### 2026-06-30 P5 Android Emulator Phone-Use

- Evidence directory:
  `mobile_agent/qa-output/harvis-mobilecode-phone-use-20260630-001527/`
- Emulator: `emulator-5554`.
- Package/activity: `com.mobilecode.app/.MainActivity`.
- Input marker: `HarvisP5PhoneUse20260630001527`.
- Tap target: first `android.widget.EditText`, bounds `[66,2190][783,2295]`,
  center `(424,2242)`.
- Result: `summary.json` reports `ok=true`.
- Checks:
  - `install_ok=true`
  - `launch_ok=true`
  - `observe_before_ok=true`
  - `tap_ok=true`
  - `type_ok=true`
  - `assert_ui_ok=true`
  - `logcat_clean=true`
- UI evidence: `window-after.xml` contains the input marker in the MobileCode
  `EditText`; `window-focus.txt` shows `com.mobilecode.app/.MainActivity`.
- Screenshot evidence: `observe-after.png` shows the MobileCode UI with the
  typed marker in the focused input field.
- Boundary: emulator-only phone-use primitive; not a real-device proof and not
  Accessibility-service proof.

### 2026-06-30 P5 Phone-Use Handoff Fixture

- Input:
  `mobile_agent/test/fixtures/harvis_mobilecode_handoff.phone_use_emulator.json`.
- Worker action: `phone_use_emulator`.
- Safety gate: approval id `appr_phone_use_emulator_001`; target selector must
  be `android_emulator` with `required=true`.
- Execution: worker calls
  `mobile_agent/tooling/harvis_mobilecode_phone_use_emulator_smoke.sh`.
- Unit evidence: `test_mobilecode_remote_worker.py` uses a fake phone-use
  runner to verify ACK generation, `mobilecode.action_evidence.v1` writeback,
  and `phone_use_check:*` observations without requiring an emulator.
- Runtime evidence: live Android Emulator handoff passed on 2026-06-30.

### 2026-06-30 P5 Phone-Use Handoff Live Route

- Input:
  `mobile_agent/test/fixtures/harvis_mobilecode_handoff.phone_use_emulator.json`.
- Evidence directory:
  `mobile_agent/qa-output/harvis-mobilecode-phone-use-handoff-20260629-163319/`
- Emulator: `emulator-5554`.
- Worker result: `ok=true`, task `hm_task_phone_use_emulator_001`, action
  `phone_use_emulator`.
- Phone-use summary: `summary.json` reports `ok=true`.
- Checks:
  - `install_ok=true`
  - `launch_ok=true`
  - `observe_before_ok=true`
  - `tap_ok=true`
  - `type_ok=true`
  - `assert_ui_ok=true`
  - `logcat_clean=true`
- Harvis route: ACK and ActionEvidence were passed to
  `lark-relay route-file --no-reply` with live localhost Harvis routing enabled.
- Harvis result: `routerMessage.ok=true`, `agentRoomMessage.ok=true`, and
  `taskStatus.ok=true` for both ACK and ActionEvidence.
- UI evidence: `window-after.xml` contains `HarvisP5HandoffFixture` in the
  MobileCode `EditText`; `window-focus.txt` shows
  `com.mobilecode.app/.MainActivity`.
- Screenshot evidence: `observe-after.png` shows the MobileCode UI with the
  typed handoff marker in the focused input field.
- Regression fixed: worker-generated Lark event ids now include
  `created_at`/`updated_at` so repeated handoff runs do not collide with
  earlier `route-file` state.

### 2026-06-30 P5 Real-Device Lane Prepared

- Script:
  `mobile_agent/tooling/harvis_mobilecode_phone_use_real_device_smoke.py`.
- Safety: refuses execution unless both `--serial` and `--allow-real-device`
  are provided.
- Safety: refuses emulator serials such as `emulator-*`, `127.0.0.1:*`,
  `localhost:*`, or devices tagged `device:emu`.
- Evidence: writes blocked or passed `summary.json` under
  `mobile_agent/qa-output/harvis-mobilecode-phone-use-real-device-<timestamp>/`.
- Current status: no physical Android device is online on this host, so no
  real-device proof has been claimed.
