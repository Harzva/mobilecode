# P6.3 Android Real Device Lane

- run_id: `p63-android-real-device-lane`
- run_kind: `strategy_pilot_not_counted`
- counts_as_experiment: `false`
- counts_as_strategy_ablation_result: `false`
- status: `passed`
- runtime_score: `100.0`
- action_acceptance: `4/4`
- back_action_verified: `True`
- home_action_verified: `True`

This verifier installs the latest APK on an Android emulator or real device, verifies MobileCode Accessibility state, runs App-internal dry/action probes, verifies adb Back/Home foreground transitions, and saves screenshot/UI XML/logcat evidence. It is non-counted and does not prove strategy quality differences.

## Boundary

- This is local Android runtime QA, not a formal benchmark result.
- It exercises the phone-use tool contract once and mirrors the same score across strategies.
- P6 counted comparison still requires task-level model/tool callbacks, repeated samples, and promotion gates.
