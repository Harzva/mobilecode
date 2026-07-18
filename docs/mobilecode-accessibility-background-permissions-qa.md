# MobileCode Accessibility and Background Permissions QA

Status: implementation-backed manual QA contract
Scope: T25 non-counted Android QA evidence

## Evidence Boundary

- Do not treat phone-use probe output as benchmark or experiment evidence.
- Keep `countsAsExperiment=false`, `countsAsStrategyAblationResult=false`, and `rawTextIncluded=false`.
- Do not save credentials, cookies, tokens, raw chat logs, private local paths, or screenshots containing secrets.
- Redact account names, notification text, repository private names, and provider usage data before sharing evidence.

## Device Matrix

- Android emulator: API level, device profile, app version, build type.
- Android real device: vendor, Android version, app version, build type.
- Record whether notification permission and battery optimization prompts were already granted before the run.

## Lifecycle Matrix

Verify all reachable states and record only their stable wire value:

| State | Expected evidence | Recovery |
| --- | --- | --- |
| `disabled` | Accessibility setting is off | User opens Android Accessibility settings and grants manually |
| `enabled_disconnected` | Setting is on, service connection is absent | Return to the app or reopen the service settings |
| `ready` | Connected and active-window observation works | None |
| `interrupted` | Service interruption/destruction was observed | Start recovery from the app's settings row |
| `background_restricted` | Battery optimization/background restriction can interrupt continuity | User reviews app details/battery settings |
| `recovering` | Recovery was requested and a healthy reconnection is pending | Refresh after returning from system settings |

MobileCode must never use `WRITE_SECURE_SETTINGS`, shell commands, or hidden
APIs to enable its own Accessibility service.

## Required Screenshots

- `01-settings-disabled`: MobileCode Settings shows `系统权限`, `无障碍服务`, and `后台运行权限`; accessibility state is disabled.
- `02-accessibility-settings-opened`: Android Accessibility settings opened from MobileCode.
- `03-settings-enabled-connected`: MobileCode Settings shows accessibility enabled and service connected after manual grant.
- `04-background-guide`: background permission bottom sheet is visible with app details and battery settings actions.
- `05-battery-settings-opened`: Android battery optimization or app details settings opened from MobileCode.
- `06-blocked-fallback`: fallback state when settings intent or service connection is unavailable.

## Manual Steps

1. Install the debug or release candidate build.
2. Open MobileCode Settings.
3. Capture the disabled permission state.
4. Tap `无障碍服务` and confirm Android opens Accessibility settings.
5. Manually enable `MobileCode PhoneUseAccessibilityService`; the app must not
   automate this secure-setting change.
6. Return to MobileCode Settings and refresh with a long press on the accessibility row.
7. Confirm status copy distinguishes enabled permission and service connection.
8. Tap `后台运行权限`.
9. Open app details and battery settings from the bottom sheet.
10. Disable or interrupt the service and confirm a blocked or fallback state is visible.
11. Capture a semantic snapshot, use one pinned `@eN~sGEN` ref for an approved
    action, then confirm the frame is expired and the same ref fails closed.
12. Run a login/credential probe with `secret_id`; confirm screenshot, video,
    logs, and raw hierarchy capture remain disabled until the sensitive step is
    complete.
13. From Auto Agent, observe the page and request a semantic action. Confirm it
    creates a target/risk preview card and does not execute before the user taps
    `Allow once` or the distinct transaction confirmation.
14. Wait past the card TTL or change the page, then tap the card. Confirm the
    ticket is expired/consumed and Android returns `approval_preview_expired`
    rather than dispatching the stale action.

## External device lane

For Mac/CI simulator or physical-device verification, use
`scripts/run_agent_device_mobilecode_qa.py` and the manual
`device-agent-qa.yml` workflow. The external CLI is QA infrastructure and must
not be packaged into the APK. `--approve-artifacts` is required for a
non-sensitive screenshot. The iOS Simulator lane can additionally use
`--approve-video`; video is simulator-only and also requires artifact approval.
`--sensitive-flow` rejects screenshot and video capture.

iOS recording must first target a system-temporary path. Direct `simctl`
recording to an external workspace volume can fail with Cocoa error 513 even
when the simulator and encoder are healthy. After recording, validate the MP4
header and digest before copying the file into the evidence directory. Do not
build or bundle a recorder app for this QA lane.

For a repeatable, non-production ordering flow on Android, use
`scripts/run_phone_use_takeout_qa.py`. It drives the debug-only takeout fixture
through a DUMP-permission-protected broadcast bridge, verifies stale refs,
coordinate mapping, native transaction-risk classification, full SHA-256 page
binding, screenshot policy, and the final transaction gate, then writes a
redacted evidence manifest. The fixture contains no merchant, account, address,
payment method, or real order endpoint. The bridge and fixture must be absent
from release APK manifests.

## Log Notes

- Keep log snippets short and redact private content before attaching them.
- Include only status transitions, method names, and failure kinds.
- Do not attach raw Accessibility node text or full UI hierarchy dumps unless fully sanitized.

## Pass Criteria

- Settings entries are visible and tappable.
- Accessibility settings intent opens successfully or shows clear fallback.
- Background permission guide opens app details or battery settings when supported.
- Service status covers disabled, enabled, connected, and blocked states.
- Semantic refs expire on mutation and stale refs return a typed failure.
- Each observe/action/capture step has redacted `ActionEvidence` with pre/post
  digests, approval, provider, device, failure, and artifact identifiers.
- No evidence file contains secrets, raw UI text, private paths, or counted benchmark claims.
- A critical/final transaction remains blocked after ordinary action approval
  until a separate approval ID matches the current preview digest.
- The Android release APK does not contain the debug QA fixture or bridge.
- Auto Agent can observe and request a semantic `phone_use_action` preview, but
  cannot act directly. Every mutation requires the user-visible, short-lived,
  one-shot card; model-provided approval and risk fields are ignored.
