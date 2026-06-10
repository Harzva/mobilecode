# Evaluation Protocol Readiness

Generated at: `2026-06-09T07:03:46Z`
Status: `passed_with_open_requirements`
Complete evaluation: `false`

## Evidence Boundary

The E1-E5 protocol is executable and artifact-bound, but only E1 has T0 fixture evidence. E2-E5 remain capture-ready or protocol-only and must not be reported as completed mobile or baseline experiments.

## Protocols

| Protocol | Status | Evidence tier | Boundary |
| --- | --- | --- | --- |
| T0 smoke over v2 | `counted_t0_fixture_evidence_available` | `T0-offline-fixture` | mobile=false; baseline=false |
| Android real-device subset | `capture_ready_no_results` | `T2-android-real-device` | mobile=false; baseline=false |
| Mac iOS simulator subset | `capture_ready_no_results` | `T3-ios-simulator` | mobile=false; baseline=false |
| GitHub sandbox delivery | `protocol_defined_t0_blocked_no_remote_write` | `T5-authorized-github-sandbox` | mobile=false; baseline=false |
| Baseline comparison | `protocol_defined_pilot_ready_no_results` | `T6-baseline-comparison` | mobile=false; baseline=false |

## Primary Metrics

Metric contract checked: `true`

- `task_success`
- `verified_success`
- `trace_completeness`
- `recovery_rate`
- `artifact_availability`
- `human_intervention_count`
- `steps_to_completion`

## Open Requirements

- `attach_device_metadata_screenshots_logs_traces_and_verifier_outputs`
- `attach_public_safe_remote_evidence`
- `attach_simulator_screenshots_logs_traces_and_verifier_outputs`
- `attach_transcripts_artifacts_verifiers_and_human_intervention_records`
- `execute_android_t2_real_device_run`
- `execute_counted_baseline_runs_with_locked_settings`
- `execute_ios_t3_simulator_run_on_mac`
- `replace_or_extend_with_mobile_tier_evidence_for_tasks_that_require_devices`
- `run_authorized_github_sandbox_delivery_tasks`
