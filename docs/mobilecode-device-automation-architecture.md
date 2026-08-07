# MobileCode Device Automation Architecture

Status: implementation-backed design contract

This design incorporates the useful boundaries from
[agent-device](https://github.com/callstack/agent-device) and
[Mobilerun](https://github.com/droidrun/mobilerun) without embedding either
project's host runtime in the MobileCode APK. The article-linked repositories
are references for the device loop; MobileCode retains its own approval,
evidence, redaction, and runtime-provider contracts.

## Non-negotiable boundaries

- The Android APK contains only the embedded Accessibility provider. It does
  not start Node, Python, ADB, XCTest, `agent-device`, or Mobilerun.
- `DeviceAutomationProvider` is independent of the code-execution
  `RuntimeProvider`. A provider can automate a device without becoming a shell
  runtime, and a runtime cannot silently acquire phone-control authority.
- Every observe, act, capture, and replay request passes through one approval
  and `ActionEvidence` seam.
- Side-effecting actions and screenshot capture require explicit approval.
- External transactions require a second approval bound to the current final
  preview digest; ordinary action approval cannot authorize an order commit.
- Credential values, OAuth codes, cookies, tokens, typed text, and raw
  accessibility trees are absent from persisted evidence.
- The provider-native Auto Agent exposes `phone_use_observe` and a semantic
  `phone_use_action` preview tool. The latter cannot execute or self-approve:
  it can only mint a short-lived, one-shot approval card after trusted native
  risk classification. Model-provided `approved`, risk, transaction digest,
  or approval ID fields are ignored.
- Android secure accessibility settings are changed only by the user in system
  Settings. MobileCode can open the settings surface and report recovery state;
  it cannot grant itself the service.

## Provider matrix

| Provider | Process boundary | Purpose | Semantic refs | Screenshot/video/logs | Physical devices |
| --- | --- | --- | --- | --- | --- |
| Android embedded Accessibility | APK process | On-device Phone Use | Yes | Local screenshot only; explicitly approved | Yes |
| External `agent-device` QA | Mac/CI host | Simulator, emulator, physical-device verification and replay | Yes | Host-side reviewed artifacts | Yes |
| iOS XCTest helper | Mac/CI host | Future first-party iOS automation adapter | Planned | Planned | Planned |
| Cloud device provider | Remote adapter | Future managed-device execution | Planned | Provider artifact IDs only | Planned |

The external QA adapter is pinned to `agent-device` 0.19.3 in the current
workflow. Upgrade it deliberately after checking its command and redaction
contracts.

## Semantic snapshot and ref lifetime

An Android observation returns a bounded, sanitized accessibility snapshot:

```text
frame=s42 digest=<sha256> state=active
@e1~s42 [Button] "Continue" bounds=(...)
@e2~s42 [TextField] "[redacted-credential]" bounds=(...)
```

The wire ref is `@eN`; persisted plans should pin the generation as
`@eN~sGENERATION`. Only the latest explicitly captured frame is active. Any
tap, swipe, text mutation, Back, or Home action expires it before dispatch.
Resolution re-finds the current node by its sanitized identity hash and fails
closed when the generation, frame state, issued ref, or current identity does
not match. A post-action snapshot verifies the result but does not mint a fresh
actionable ref frame; the next action sequence starts with a new observation.

Stable failure kinds include `ref_frame_missing`, `ref_frame_expired`,
`ref_generation_mismatch`, `ref_not_issued`, `ref_target_changed`, and
`ref_not_editable`.

## Hybrid observation and coordinate contract

Accessibility is the primary control plane. A screenshot is a visual fallback
only when the semantic tree is sparse, the flow is non-sensitive, and artifact
capture was explicitly approved. Each snapshot or screenshot declares:

- source and input coordinate spaces;
- source and input width/height;
- X/Y scale;
- top-left origin.

Coordinate fallback is therefore auditable instead of assuming that screenshot
pixels, logical Flutter coordinates, and Android gesture pixels are identical.
The contract travels with screenshot metadata and action evidence.

## Unified action evidence

Each step stores one redacted `ActionEvidence` record with:

- provider type/name and action kind;
- target ref or numeric coordinates, never raw typed text;
- approval required/granted/source;
- pre/post snapshot digest and ref-frame state;
- ref or coordinate resolution metadata;
- current package hash and page/class name;
- screenshot, video, log, or replay artifact IDs when produced;
- device platform/model/API metadata;
- failure kind and recovery actions;
- redaction flags and start/end timestamps;
- `countsAsExperiment=false` and
  `countsAsStrategyAblationResult=false` for QA-only runs.

Embedded screenshots remain local-only and are never marked shareable without
review. External QA stores result digests and artifact IDs, not raw CLI output.

## Permission and background lifecycle

The user-visible lifecycle is:

```text
disabled -> enabled_disconnected -> ready -> interrupted
                                      |             |
                                      v             v
                           background_restricted -> recovering
                                                        |
                                                        v
                                                      ready
```

- `disabled`: user has not enabled the Accessibility service.
- `enabled_disconnected`: system setting is enabled but the service has no live
  connection.
- `ready`: connected with window observation available.
- `interrupted`: service was interrupted or destroyed.
- `background_restricted`: battery/background policy can prevent continuity.
- `recovering`: the user has opened the relevant system settings or returned
  from an interruption and MobileCode is waiting for a healthy connection.

Recovery actions are hints and links to system settings, never programmatic
secure-setting changes.

Android derives `background_restricted` from the OS background-restriction
signal, not merely from whether a MobileCode Activity is visible. This avoids
misclassifying normal cross-app Phone Use as restricted while still detecting
the user's explicit “Allow background usage” policy.

## One-shot approval and trusted transaction gate

The main Agent can request only an approval preview. Android classifies that
preview inside the Accessibility service from the current admitted semantic
ref, sanitized target label, target identity, action kind, and active snapshot.
Policy `phone_use_transaction_risk_v1` treats unlabeled/sensitive taps,
coordinate taps, and checkout/payment/order/transfer/subscription/publish or
account-deletion labels (including Chinese equivalents) as
`externalTransaction`. Classifier failure is fail-closed; model output cannot
downgrade the result.

The preview returns full SHA-256 frame and action digests. The coordinator mints
an in-memory ticket with a 20-second TTL, shorter than the semantic ref TTL. The
card displays the sanitized target, trusted risk, policy reason, and expiry.
Ordinary actions show `Allow once`; transaction actions show a distinct red
confirmation. The ticket is removed before provider execution, so double taps,
replay, and retries cannot execute it twice.

Approved execution carries the preview frame digest back to Android. If the
page or active ref frame changed, Android returns `approval_preview_expired`
before dispatch. External transactions additionally require a user-generated
approval ID and an approval digest exactly matching the trusted preview digest.
There is no automatic retry after either gate rejects the action.

## Login and credential QA

Approved credential input uses `secret_id` as an opaque slot. The secret
resolver retrieves the value only at execution time and passes it over the
native action channel; evidence stores `credentialSlot`, text length at most,
and redaction flags. It never stores the value.

The production resolver accepts only `[A-Za-z0-9._-]` slot IDs up to 48
characters and maps them exclusively to the `phone_use_slot_` secure-storage
namespace. It cannot use a caller-controlled key to read provider API keys or
other application secrets. Invalid, locked, or missing slots fail closed.

The Phone Use settings card now provides explicit local store/delete controls.
The value field is obscured and stored through Android Keystore or iOS Keychain;
the agent receives only `secret_id`. Slot values cannot be enumerated through
the Phone Use service and are resolved only after the one-shot card is approved.

During OAuth, password, cookie, or token entry:

- set `sensitiveFlow=true`;
- do not capture screenshots or video;
- do not start app logs, logcat, network capture, or raw hierarchy dumps;
- do not place the secret on a CLI argument or in a replay file;
- resume reviewed artifact capture only after navigating to a non-sensitive
  confirmation surface.

## Mac and CI QA

Use the host adapter, never the APK, for `agent-device`:

```bash
npm install --global agent-device@0.19.3
agent-device doctor
python3 scripts/run_agent_device_mobilecode_qa.py \
  --platform android \
  --app-id com.mobilecode.app \
  --device emulator-5554 \
  --approve-artifacts
```

For credential/login validation, replace artifact approval with
`--sensitive-flow`. The adapter runs device/app discovery, opens the app,
captures an interactive semantic snapshot, optionally captures one approved
non-sensitive screenshot, closes the session, and writes a sanitized evidence
manifest. iOS Simulator video is opt-in through `--approve-video`; it is
forbidden for sensitive flows and is staged on the system volume before being
copied into reviewed output.

Recording remains a host-side evidence adapter, not a second recorder app.
`simctl` can fail with Cocoa error 513 when asked to stream directly to some
external volumes, so the wrapper records into the system temporary directory,
validates the MP4 container, then copies it into the approved evidence folder.
Android likewise uses host-side `screenrecord`. A separate on-device recorder
would add screen-capture consent, foreground-service, storage, and secret-leak
surfaces without improving Phone Use control fidelity.

Android ordering-like acceptance uses the separate host runner:

```bash
python3 scripts/run_phone_use_takeout_qa.py \
  --serial emulator-5554 \
  --output mobile_agent/qa-output/phone-use-takeout \
  --approve-artifacts
```

The Android runner records only hashes, assertions, safe lifecycle values, and
reviewed artifact IDs. Agent-device may record the fake-data run externally;
reviewed video, gesture telemetry, and filtered logcat are attached by digest.

The manual GitHub workflow offers an iOS simulator lane and a self-hosted Mac
physical-device lane. Real-device runners must carry the
`mobilecode-device-lab` label and have the target app installed when the
physical lane starts.

## Latest acceptance evidence (2026-07-18)

- Full Flutter suite: 534 tests passed.
- Android native compilation: `devharnessDebug` and `pureDebug` Kotlin variants
  passed.
- Android fake ordering run: 29 redacted steps and 11 assertions passed. The
  trusted classifier marked `Confirm order` as `externalTransaction`, a wrong
  page digest was rejected, the unapproved final commit remained blocked,
  sensitive screenshot capture remained blocked, and commit attempts stayed
  at zero. Manifest SHA-256:
  `93ce81cc52ca4c618661bc5b9a6b07676f63b1c325744aaa2ff1e602ed9a85e4`.
- Controlled credential tests passed through provisioning, preview, approval,
  native-call resolution, and evidence serialization using fake account data;
  the value was absent from evidence and UI text output.
- Unsigned iOS device profile build passed. A signed physical-device build is
  currently blocked by missing provisioning-profile/account readiness.
- Connected device inventory at acceptance time: two Android emulators, zero
  Android physical devices, and zero available iOS physical devices. Therefore
  no Android/iOS physical-device or real external-account pass is claimed.

## Acceptance criteria

- A stale or mutated ref fails with a typed failure and cannot act.
- A mutation without explicit approval does not reach the provider.
- Swipe coordinates arrive at Android as `x1/y1/x2/y2`.
- Secret values are absent from `ActionEvidence` JSON.
- Sensitive flows cannot invoke screenshot capture.
- Approval tickets expire, are consumed before execution, and cannot replay.
- Native risk classification can upgrade an action to external transaction but
  model input cannot downgrade it.
- A page digest change between preview and user tap blocks execution.
- Kotlin compiles, Dart analysis has no errors, focused unit/widget tests pass,
  and the host adapter's dry-run manifest contains no raw app/device identifier.
