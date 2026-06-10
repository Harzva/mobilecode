# Mobile Evidence Pack Readiness

Generated at: `2026-06-06T15:06:41Z`
Status: `capture_ready_no_results`
Ready for capture: `true`
Ready for counted mobile experiment: `false`

## Evidence Boundary

This is a capture kit, not a mobile experiment. It prepares the files required to collect Android T2 and iOS T3 evidence without counting any result.

## Task Sets

| Task set | Tier | Tasks | Requires real device |
| --- | --- | ---: | ---: |
| `android-device-v2` | `T2-android-real-device` | 30 | 30 |
| `ios-simulator-v2` | `T3-ios-simulator` | 18 | 0 |

## Open Requirements

- `execute_android_t2_real_device_run`
- `execute_ios_t3_simulator_run`
- `fill_device_metadata_and_task_evidence`
- `attach_verifier_outputs_traces_screenshots_and_logs`
- `pass_public_output_safety_scan`

## Execution Playbook

- [execution-playbook.md](../mobile-evidence/2026-06-06-mobile-evidence-pack/execution-playbook.md)
