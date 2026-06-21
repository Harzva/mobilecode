# P4c Callback Pilot Harness

## Purpose

P4c adds a local callback-pilot artifact generator for MobileHarnessBench strategy ablation.

It is designed to test the artifact shape after P4b introduced the callback-based real runner adapter skeleton. The P4c harness uses deterministic fake callbacks and writes a validator-compatible `strategy_pilot_not_counted` run directory.

## What It Does

The harness generates:

- `run.json`
- `summary.md`
- `task_strategy_matrix.csv`
- per-task/per-strategy callback traces under `callback_traces/`

The generated `run.json` is accepted by:

```bash
python3 scripts/validate_mobile_harness_strategy_ablation.py \
  --registry docs/mobile-harness-benchmark/strategy-ablation/strategy_registry.json \
  --run docs/mobile-harness-benchmark/strategy-ablation/runs/p4c-callback-pilot/run.json
```

## What It Does Not Do

P4c does not:

- call a real model provider,
- execute a real tool,
- start a device or emulator,
- use the network,
- read credentials,
- produce a counted benchmark result,
- compare or rank strategies.

All generated rows use:

```text
run_kind = strategy_pilot_not_counted
counts_as_experiment = false
counts_as_strategy_ablation_result = false
evidence.boundary = pilot_not_counted
strategy_trace.trace_status = pilot_not_counted
```

## Metrics Boundary

P4c includes deterministic fake time/token values to exercise the artifact schema and downstream report parsers. These values are callback-harness instrumentation only. They are not runtime measurements and must not be cited as benchmark results.

Effectiveness fields that would require real verifier/device/tool evidence remain `null`, except schema-completeness-style fields such as `trace_completeness` and `memory_reuse_score`, which only describe the generated fake callback artifact.

## Default Command

```bash
python3 scripts/generate_mobile_harness_strategy_callback_pilot.py \
  --task-set smoke-v2 \
  --strategies react_single_agent,plan_execute_verify_single_agent,supervisor_handoff_multi_agent \
  --max-tasks 4 \
  --run-id p4c-callback-pilot \
  --output docs/mobile-harness-benchmark/strategy-ablation/runs/p4c-callback-pilot
```

## Review Gate

Before P5, run the review protocol:

- `docs/mobile-harness-benchmark/strategy-ablation/subagent-review-protocol.md`

P5 must not enable real provider/tool/device callbacks until:

1. Flutter tests pass locally.
2. P4b adapter skeleton is reviewed.
3. P4c artifact is reviewed.
4. The evidence gate is extended to distinguish fake callback traces from real evidence.
