# Android Emulator Release QA — 2026-08-01

## Outcome

- Release build: `passed`
- APK install and launch: `passed`
- Phone Use device QA: `passed`
- Terminal outcome: `verified_success`
- Counts as experiment: `false`

The `pure` release APK installed and launched on a clean Android 16 / API 36
ARM64 emulator. The Accessibility service reached `ready`; semantic observation,
semantic-ref focus, fresh re-observation, `setTextRef`, coordinate tap, swipe,
Back, and Home checks succeeded. The action probe accepted and verified all 6
actions, including the final text value.

## Build

- Artifact: `mobile_agent/build/app/outputs/flutter-apk/app-pure-release.apk`
- Size: `32,881,516` bytes
- SHA-256: `ac57246a5007610bd0ca09b884f41c085d3b32235f6755d01e5271bfce52b013`
- Package: `com.mobilecode.app`
- Activity: `com.mobilecode.app.MainActivity`

## Device

- Kind: `android_emulator`
- Android: `16` (`API 36`)
- ABI: `arm64-v8a`
- Display: `720x1280` at density `320`
- Raw device serial included: `false`

## Evidence

- [Run summary](../strategy-ablation/runs/2026-08-01-p63-android-device-qa/summary.md)
- [Verifier output](../strategy-ablation/runs/2026-08-01-p63-android-device-qa/phone_use_runtime_verifier.json)
- [Redacted device metadata](../strategy-ablation/runs/2026-08-01-p63-android-device-qa/device.json)
- [Ready-state screenshot](../strategy-ablation/runs/2026-08-01-p63-android-device-qa/evidence/03-dry-probe.png)
- [Action-probe UI tree](../strategy-ablation/runs/2026-08-01-p63-android-device-qa/evidence/04-action-probe.xml)
- [Home transition screenshot](../strategy-ablation/runs/2026-08-01-p63-android-device-qa/evidence/05-home-after-action.png)

The public evidence removes the raw device serial and contains no credential
values. This is an emulator QA artifact, not a physical-device result, model
benchmark, or proof that MobileCode can safely complete a real transaction.

## Open Requirement

Counted evaluation still requires three real-agent repetitions per selected
task, locked model/prompt/build/verifier inputs, and separate physical-device
promotion evidence. This successful deterministic probe does not satisfy those
requirements by itself.
