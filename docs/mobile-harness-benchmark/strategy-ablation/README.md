# Mobile Harness Reasoning Strategy Ablation

This directory defines the R1 scaffold for comparing agent reasoning and
collaboration strategies inside MobileHarnessBench. It is a benchmark contract,
not an experiment result.

## Positioning

MobileHarnessBench measures whether a phone-native coding harness can close the
loop from user intent to file intake, code edit, preview, verification, runtime
fallback, GitHub delivery, and evidence reporting. This strategy ablation layer
adds one independent variable:

- Independent variable: `agent strategy`.
- Controlled variables: task subset, model lock, device tier, runtime backend,
  tool access policy, prompt budget, max steps, and verifier contract.
- Dependent metrics: time, token/cost, and effectiveness.

The current R1 artifacts are `strategy_scaffold_not_run` or
`strategy_dry_run_not_counted` only. They do not prove that one strategy is
better than another, and they must not be cited as counted model/device results.

## Why MobileCode Needs This Layer

Desktop and cloud coding harnesses often assume a capable shell, stable file
paths, and enough memory for long context. MobileCode has a different failure
surface: Android/iOS permissions, WebView preview state, content URI grants,
helper/Termux availability, local model readiness, battery/RAM limits, and
share/open-with entry points. A mobile harness therefore needs explicit session
memory, handoff filtering, per-step verification, and evidence-ledger output.

R1 uses this default flow:

```text
User Goal
  -> Goal Intake + HarnessMemoryPacket
  -> Supervisor Plan
  -> Plan-Execute-Verify outer loop
  -> ReAct Think -> Act -> Observe inner loop per step
  -> optional Supervisor/Handoff to specialist roles
  -> StepVerification gate
  -> Reporter summary + evidence ledger
  -> Memory commit proposal
```

See [mobile-harness-reasoning-strategy-v1.md](mobile-harness-reasoning-strategy-v1.md)
for the full flow and packet contracts.

## R1 Strategy Set

The initial registry compares six strategies:

- `react_single_agent`
- `plan_execute_verify_single_agent`
- `react_with_final_verifier`
- `supervisor_handoff_multi_agent`
- `swarm_router_multi_agent`
- `hierarchical_swarm_multi_agent`

See [strategy-taxonomy.md](strategy-taxonomy.md) and
[strategy_registry.json](strategy_registry.json).

## Metrics

R1 keeps raw metrics first:

- Time: planning, execution, verification, reporting, wall time.
- Token/cost: prompt tokens, completion tokens, tool I/O chars, estimated tool
  tokens, tokens per successful task.
- Effectiveness: task success, verified success, trace completeness, artifact
  availability, recovery rate, human intervention, steps to completion.

Derived scores are documentation-only in R1. See
[metrics-contract.md](metrics-contract.md).

## Evidence Boundary

For any run where `run_kind` is not `strategy_ablation_result`:

- `counts_as_experiment=false`
- every result must have `counts_as_strategy_ablation_result=false`
- metrics must remain `null` unless produced by a real runner
- evidence must say `scaffold_not_run`, `dry_run_not_counted`, or
  `pilot_not_counted`

The R1 runner is intentionally stdlib-only. It does not call an LLM, does not
open the network, does not read API keys, and does not access a real device.

## App Implementation Status - 2026-06-20

MobileCode now has an app-side non-counted strategy framework:

- `StrategyDispatcher.defaultSafe` routes the six registered strategy IDs.
- `ReactStrategyRunner`, `PlanExecuteVerifyStrategyRunner`,
  `ReactWithFinalVerifierStrategyRunner`,
  `SupervisorHandoffStrategyRunner`, `SwarmRouterStrategyRunner`, and
  `HierarchicalSwarmStrategyRunner` emit `StrategyTrace`,
  `StepVerification`, and `ActionEvidence`.
- `HarnessMemoryPacketService` builds TTL-bound, compacted, redacted memory
  packets from `MemoryService` and only creates proposal-style memory commits.
- `SupervisorHandoffStrategyRunner` uses filtered `HandoffPacket`s for
  CodeAgent, RuntimeAgent, PreviewAgent, VerifierAgent, MemoryAgent, and
  ReporterAgent.
- Experimental swarm strategies remain capability-gated and non-counted by
  default.

This is still not a counted benchmark result. The release blockers for a
publishable product claim are the App UI strategy selector/trace panel,
Android emulator QA screenshots, and real model/tool/device callback evidence.

## Minimal Scaffold Command

```bash
python3 scripts/run_mobile_harness_strategy_ablation.py \
  --task-set smoke-v2 \
  --strategies react_single_agent,plan_execute_verify_single_agent,supervisor_handoff_multi_agent,swarm_router_multi_agent \
  --run-kind strategy_scaffold_not_run \
  --output docs/mobile-harness-benchmark/strategy-ablation/runs/r1-scaffold

python3 scripts/validate_mobile_harness_strategy_ablation.py \
  --registry docs/mobile-harness-benchmark/strategy-ablation/strategy_registry.json \
  --run docs/mobile-harness-benchmark/strategy-ablation/runs/r1-scaffold/run.json
```

## Threats To Validity

- Model nondeterminism can dominate small task sets.
- Strategy overhead may look worse on short tasks and better on long tasks.
- Tool permissions and device tier can change success independently of strategy.
- Cached previews, local files, or prior Git state can leak across runs.
- Human intervention must be logged consistently across strategies.
- Handoff history can leak irrelevant tool traces unless filtered.

## README Summary Draft

Mobile Harness Reasoning Strategy v1 adds a measurable reasoning-control layer
to MobileCode: Plan-Execute-Verify governs the task, ReAct governs each mobile
action, Supervisor/Handoff routes specialist work, and session memory is filtered
through explicit packets rather than raw transcript sprawl. R1 is a scaffold for
future ablation, not an experiment result.
