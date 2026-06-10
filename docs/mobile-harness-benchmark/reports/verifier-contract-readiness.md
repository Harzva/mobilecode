# Verifier Contract Readiness

Generated at: `2026-06-09T07:03:54Z`
Status: `passed`
Counts as experiment: `false`

## Evidence Boundary

This report checks machine-readable verifier contract coverage for task definitions. It does not claim full verifier implementation coverage or mobile-device execution.

## Coverage

- Contract count: `12`
- Covered verifier count: `12`
- Task banks checked: `3`
- Task definitions checked: `1225`

## Task Banks

| Task bank | Tasks | Unique verifiers | Path |
| --- | ---: | ---: | --- |
| v0-seed-tasks | 25 | 11 | `docs/mobile-harness-benchmark/tasks/v0-seed-tasks.json` |
| v1-task-bank | 200 | 11 | `docs/mobile-harness-benchmark/tasks/v1-task-bank.json` |
| v2-task-bank | 1000 | 12 | `docs/mobile-harness-benchmark/tasks/v2-task-bank.json` |

## Verifiers

- `artifact_exists_verifier`
- `diff_scope_verifier`
- `evidence_verifier`
- `external_file_verifier`
- `github_delivery_verifier`
- `html_preview_verifier`
- `json_verifier`
- `markdown_preview_verifier`
- `privacy_verifier`
- `runtime_verifier`
- `snapshot_verifier`
- `trace_verifier`

## Open Requirements

- `complete_full_seed_task_verifier_implementation`
- `execute_mobile_tier_verifiers_on_real_or_simulated_devices`
- `attach_verifier_outputs_to_final_frozen_subset`
