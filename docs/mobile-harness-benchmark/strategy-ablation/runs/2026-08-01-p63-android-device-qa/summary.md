# P6.3 Android Device QA Lane

- run_id: `2026-08-01-p63-android-device-qa`
- run_kind: `strategy_pilot_not_counted`
- counts_as_experiment: `false`
- counts_as_strategy_ablation_result: `false`
- status: `passed`
- terminal_outcome: `verified_success`
- device_kind: `android_emulator`
- runtime_score: `100.0`
- action_acceptance: `6/6`
- back_action_verified: `True`
- home_action_verified: `True`

This verifier installs the latest APK on an Android emulator or physical device, records the device kind, verifies MobileCode Accessibility state, runs App-internal dry/action probes, verifies adb Back/Home foreground transitions, and saves screenshot/UI XML/logcat evidence. It is non-counted and does not prove strategy quality differences.

## Boundary

- This is local Android runtime QA, not a formal benchmark result.
- It exercises the phone-use tool contract once and mirrors the same score across strategies.
- P6 counted comparison still requires task-level model/tool callbacks, repeated samples, and promotion gates.
