# Strategy Ablation Metrics Contract

R1 records raw metrics first. Derived scores may be added later, but they must
not hide missing evidence.

## Time Metrics

| Field | Meaning |
| --- | --- |
| `planning_ms` | Time spent creating or revising the plan. |
| `execution_ms` | Time spent in tool/action execution. |
| `verification_ms` | Time spent checking artifacts and traces. |
| `reporting_ms` | Time spent generating final report and evidence summary. |
| `wall_ms` | End-to-end elapsed time for the task-strategy pair. |

All fields stay `null` for `strategy_scaffold_not_run`,
`strategy_dry_run_not_counted`, and `strategy_pilot_not_counted` unless the
runner actually measured them in a declared non-counted pilot.

## Token And Cost Metrics

| Field | Meaning |
| --- | --- |
| `prompt_tokens` | Prompt/input tokens billed or measured by provider. |
| `completion_tokens` | Completion/output tokens billed or measured by provider. |
| `estimated_tool_io_tokens` | Token estimate for tool observations and logs. |
| `total_tokens` | Provider tokens plus estimated tool I/O tokens. |
| `estimated_cost_usd` | Provider/model cost estimate when available. |
| `tokens_per_verified_success` | Total tokens divided by verified successful tasks. |

Provider keys, request IDs, raw private transcripts, and credential-bearing logs
must not be stored in benchmark artifacts.

## Effectiveness Metrics

| Field | Meaning |
| --- | --- |
| `task_success` | Task reached an acceptable final state. |
| `verified_success` | A verifier confirmed the final state. |
| `trace_completeness` | Required plan/action/observe/verify events were recorded. |
| `artifact_availability` | Required files/screenshots/logs are present. |
| `recovery_rate` | Failed steps that recovered within retry budget. |
| `human_intervention_count` | Human actions needed to finish. |
| `handoff_success_rate` | Handoffs that returned the required contract. |
| `memory_reuse_score` | Whether relevant memory helped without stale leakage. |
| `steps_to_completion` | Count of executed strategy steps. |

Binary scores use `0` or `1`. Ratio scores use `0..1`. Missing values are
`null`, not `0`.

## Non-Counted Boundary

If `run_kind` is not `strategy_ablation_result`, the run must set:

- `counts_as_experiment=false`
- `counts_as_strategy_ablation_result=false` for every result
- no generated comparison claim
- evidence boundary equal to scaffold, dry-run, or pilot wording

The validator enforces this boundary so R1 outputs cannot accidentally become
paper or marketing claims.
