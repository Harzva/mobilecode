# Baseline Pilot Pack

Generated at: `2026-06-06T12:53:59Z`
Status: `pilot_ready_no_results`
Counts as baseline result: `false`

This pilot pack locks prompts and evidence templates for future baseline execution. It contains no model execution, no device execution, no transcript, and no baseline result.

## Selected Task

- `MH-CE-209` / `code_edit`

## Pilot Directories

- `docs/mobile-harness-benchmark/baselines/2026-06-06-baseline-pilot-pack/chat_only_mobile_coding_flow`
- `docs/mobile-harness-benchmark/baselines/2026-06-06-baseline-pilot-pack/desktop_remote_ide_flow`
- `docs/mobile-harness-benchmark/baselines/2026-06-06-baseline-pilot-pack/mobile_harness_flow`

## Required Before Counting

- Fill the model lock with provider, model, version, decoding parameters and prompt hashes.
- Execute each baseline with the same task fixture and time budget.
- Attach transcripts, artifacts or blocked-output evidence, verifier outputs and intervention rows.
- Only then create `baseline_result` runs.
