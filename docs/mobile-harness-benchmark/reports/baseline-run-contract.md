# Baseline Run Contract

Generated at: `2026-06-06T12:53:58Z`
Status: `contract_defined_no_results`

## Evidence Boundary

This contract defines future baseline result shape only. It has zero results and must not be reported as a baseline comparison until valid baseline-run artifacts exist for all three flows.

## Required Top-Level Fields

- `benchmark`
- `schema_version`
- `run_id`
- `run_kind`
- `task_subset`
- `baseline_id`
- `environment`
- `counts_as_experiment`
- `counts_as_baseline_result`
- `summary`
- `results`
- `evidence_boundary`

## Required Metrics

- `task_success`
- `verified_success`
- `trace_completeness`
- `recovery_rate`
- `artifact_availability`
- `human_intervention_count`
- `steps_to_completion`

## Required Evidence Fields

- `artifact_paths`
- `trace_paths`
- `screenshot_paths`
- `logs`
- `verifier_outputs`
- `transcript_paths`
- `human_intervention_notes`

## Future Artifacts

- `docs/mobile-harness-benchmark/baselines/<run-id>/baseline-run.json`
- `docs/mobile-harness-benchmark/baselines/<run-id>/baseline-summary.md`
- `docs/mobile-harness-benchmark/baselines/<run-id>/baseline-traces.jsonl`
- `docs/mobile-harness-benchmark/baselines/<run-id>/artifacts/`
