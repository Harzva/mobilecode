# Subagent Review Protocol For Reasoning Strategy Benchmark

This protocol is mandatory for any Codex/subagent output that touches Mobile Harness Reasoning Strategy, MobileHarnessBench, or agent strategy ablation code.

## Principle

Subagents may generate candidate code, tests, schemas, and documents, but their output is not accepted until a separate review gate checks correctness, scope control, evidence boundaries, and benchmark integrity.

The benchmark goal is to compare reasoning/collaboration strategies such as ReAct, Plan-Execute-Verify, Supervisor/Handoff, SwarmRouter, and HierarchicalSwarm under controlled task/model/tool/device settings. Any code that changes benchmark semantics must preserve the time/token/effectiveness metric contract.

## Review Gate Checklist

### 1. Scope Boundary

- Does the change stay within the requested phase, such as P1/P2/P3-lite/P4 pilot?
- Does it avoid replacing `AgentLoopController` unless explicitly requested?
- Does it avoid changing real provider/model/tool/device execution paths unless the phase requires it?
- Does it avoid large UI/business rewrites when the task is benchmark infrastructure?

### 2. Evidence Boundary

- No fake output may be labeled as a real benchmark result.
- Fake/scaffold output must keep:
  - `counts_as_experiment=false`
  - `counts_as_strategy_ablation_result=false`
  - `strategy_scaffold_not_run`, `strategy_dry_run_not_counted`, or `strategy_pilot_not_counted`
- Promotion to `strategy_ablation_result` requires real model logs, token usage, verifier output, and device/tool evidence.

### 3. Metric Integrity

- Time metrics must come from real timers or remain null.
- Token metrics must come from actual provider/token logger or remain null.
- Effectiveness metrics must come from verifier/task evidence or remain null.
- Derived scores must not replace raw metrics.

### 4. Safety And Privacy

- No API calls, network calls, or credential reads unless explicitly approved.
- No raw transcript in `HarnessMemoryPacket` or `HandoffPacket`.
- Handoff contexts must use filters such as `summary_only`, `remove_tool_calls`, or `evidence_refs_only`.
- No secrets, tokens, private absolute paths, or raw credentials in persistent memory/evidence.

### 5. Testability

- New Dart model/controller code should have JSON roundtrip tests.
- Fake runners should test happy path, retry path, blocked/failure path, and stable event ordering.
- Python benchmark scripts should pass `py_compile`.
- Strategy runs should pass `validate_mobile_harness_strategy_ablation.py`.
- `git diff --check` should pass.

### 6. Code Quality

- Prefer additive files and small adapters over rewriting large existing files.
- Keep fake runner deterministic.
- Keep field names aligned with `mobile-harness-reasoning-strategy-v1.md`.
- Dart fields may be camelCase, but benchmark JSON should preserve snake_case contract.

### 7. App-Side Strategy Runner Gate

For changes touching the MobileCode Flutter app strategy layer:

- `StrategyDispatcher.defaultSafe` must route every registered strategy ID and
  fall back unknown IDs to a safe PEV path.
- Disabled or experimental strategies must return a blocked trace, not silently
  run.
- ReAct, PEV, final verifier, Supervisor/Handoff, Swarm Router, and
  Hierarchical Swarm runners must keep outputs non-counted unless PromotionGate
  has real evidence.
- Supervisor/Handoff must include CodeAgent, RuntimeAgent, PreviewAgent,
  VerifierAgent, MemoryAgent, and ReporterAgent with role-specific tool
  allowlists.
- Handoff packets must use `summary_only`, `remove_tool_calls`, or
  `evidence_refs_only`, and must not include raw transcript text.
- `HarnessMemoryPacketService` may build packets and proposals, but must not
  silently persist durable memory.
- UI changes must keep API keys, private paths, raw transcript, and raw provider
  errors out of screenshots and public evidence.

## Strategy Adjustment Loop

After each subagent output:

1. Summarize changed files.
2. Classify the change as documentation, schema, fake scaffold, controller adapter, real pilot, or counted experiment.
3. Run validation commands available in the environment.
4. Identify violations or missing evidence.
5. Decide one of:
   - accept as-is,
   - request narrow patch,
   - revert only that subagent's files,
   - downgrade claims to non-counted scaffold,
   - split the next phase into smaller work packages.
6. Update the next prompt so later subagents do not repeat the same mistake.

## Recommended Subagent Roles

- Builder subagent: writes candidate implementation only.
- Test subagent: adds or repairs tests only.
- Reviewer subagent: reads diff, schema, docs, and run artifacts; does not implement features.
- Benchmark auditor subagent: checks metric/evidence validity and claim boundaries.

Do not allow two builder subagents to edit the same worktree paths at the same time. Use isolated git worktrees for true parallel work.
