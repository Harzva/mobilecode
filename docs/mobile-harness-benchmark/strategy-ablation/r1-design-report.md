# R1 Design Report: Mobile Harness Reasoning Strategies

## Summary

MobileCode already has the beginning of a mobile coding harness: an agent loop,
tool policy, action evidence, preview/runtime concepts, and app memory. What is
still missing is the reasoning-control layer that makes complex mobile tasks
repeatable: session memory packets, structured handoffs, run-level strategy
traces, and per-step verification.

R1 adds that layer as a benchmark scaffold. It is intentionally conservative:
the code produced here can generate and validate a non-counted run skeleton, but
it does not execute a model, does not open a device, and does not report real
strategy performance.

## Why Mobile Harness Needs More Than Desktop Harness

Desktop coding harnesses can usually assume a shell, stable paths, rich process
control, and enough context. MobileCode must also manage:

- Android/iOS permission and content-URI behavior.
- WebView preview, screenshots, and downloaded/shared files.
- Multiple runtimes: WebView, Helper, external Termux, cloud, and future local
  model runtime.
- Battery, memory, and background execution limits.
- App-store safety constraints and user-visible privacy boundaries.
- Evidence that can be shared as screenshots and run ledgers.

That is why the default strategy is:

```text
Plan-Execute-Verify outer loop
  + ReAct inner loop
  + Supervisor/Handoff for mobile specialists
  + HarnessMemoryPacket for compact session memory
  + StrategyTrace and StepVerification for evidence
```

## Current MobileCode Mapping

- `AgentLoopController` is closest to the ReAct executor and already has tool
  policy, evidence IDs, blocked recovery, and mutation verification hooks.
- `AgentOrchestrator` has a useful Supervisor/Worker product shape, but it is
  still a UI/prototype-style orchestrator rather than a real evidence-bearing
  dispatcher.
- `MemoryService` stores useful project/user/error records, but it does not yet
  produce scoped, redacted, TTL-bound harness packets.
- `ActionEvidenceStore` records action-level evidence, but a strategy ablation
  needs run-level traces that connect plan, handoff, verification, metrics, and
  memory decisions.

## R1 Scope

Included:

- Strategy taxonomy.
- Strategy registry.
- Run schema.
- Scaffold runner.
- Validator.
- One generated `strategy_scaffold_not_run` example run.

Excluded:

- Real model calls.
- Real phone/emulator execution.
- Token measurement.
- Performance claims.
- Durable memory writes.
- Replacing current app controllers.

## Next Engineering Landing

P1 should add Dart models and tests for:

- `HarnessMemoryPacket`
- `HandoffPacket`
- `StrategyTrace`
- `StepVerification`

P2 should add a fake, non-network PEV runner that emits `StrategyTrace` events.
Only after that should MobileCode wire real model/tool/device execution into the
strategy layer.
