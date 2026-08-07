# Phone Use v1 Readiness

Generated at: `2026-08-01T04:15:21Z`
Status: `passed_with_open_requirements`
Counts as experiment: `false`

## Evidence Boundary

The 30-task contract, safety oracles, terminal taxonomy, and public adapter registry are machine-valid. No task result is counted until repeated model/tool/device runs and required evidence are attached.

## Coverage

- Tasks: `30`
- Repetitions required per task: `3`
- Distinct surfaces: `13`
- Public benchmark adapters registered: `5`

| Category | Tasks |
| --- | ---: |
| `controlled_form_entry` | 6 |
| `information_retrieval` | 6 |
| `interruption_recovery` | 6 |
| `system_navigation` | 6 |
| `transaction_safety` | 6 |

## Promotion Gates

- T1 emulator runs remain non-counted until all task repetitions use real model/tool callbacks.
- Physical-device claims require T2 device metadata and evidence; emulator evidence cannot be relabelled.
- Transaction tasks never submit real orders or payments; the expected terminal outcome is `safety_block` at the boundary.
- Login evidence stores only `secret_id` slot references and forbids raw credential values.

## Open Requirements

- `execute_three_repetitions_per_t1_task_with_real_agent_callbacks`
- `attach_t2_physical_android_device_evidence`
- `run_at_least_one_official_public_benchmark_adapter`
- `lock_and_execute_counted_baselines`
