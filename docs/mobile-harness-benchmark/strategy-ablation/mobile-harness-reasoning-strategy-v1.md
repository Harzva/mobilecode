# Mobile Harness Reasoning Strategy v1

## Goal

Design the first MobileCode reasoning strategy that explicitly combines:

- Plan-Execute-Verify as the outer task-control loop.
- ReAct as the inner tool/action loop.
- Supervisor/Handoff as the multi-agent coordination mechanism.
- Harness session memory as a filtered, redacted, resumable context layer.
- Evidence ledger records as the proof surface for every meaningful action.

This document is a design and scaffold contract. It does not report real
strategy-ablation results.

## External Design Inputs

The R1 design was based on the requested Agent Reasoning Zoo search and the
following small set of relevant files:

- `all-agentic-architectures/.../react.py`: explicit `think -> act -> tools`
  split so a model cannot skip thought before tool use.
- `all-agentic-architectures/.../planning.py`: plan up front, execute steps,
  replan only when the plan is exhausted or evidence says it is stale.
- `all-agentic-architectures/.../pev.py`: per-step verifier with retry on
  critique and `fail-accepted` after retry budget.
- `openai-agents-python/docs/handoffs.md`: handoff as a tool, structured
  handoff input, input filters, and nested history control.
- `openai-agents-python/docs/sessions/index.md` and
  `sessions/encrypted_session.md`: local session memory, history limiting,
  merge callbacks, encryption, and TTL.
- `swarms/.../planner_worker_swarm.md`: planner-worker-judge cycle, no
  worker-to-worker coordination, task queue, timeouts, judge feedback.
- `swarms/.../swarm_router/README.md` and
  `hierarchical_swarm/README.md`: routing by task characteristics and
  manager-worker hierarchy.

## Current MobileCode Fit

| Area | Current ability | Gap for v1 |
| --- | --- | --- |
| `AgentLoopController` | Tool-call loop, allowed-tool policy, mutation followed by verification, blocked recovery contract, `ActionEvidence` IDs. | No explicit outer PEV state, no structured `StrategyTrace`, no per-step verifier object, no run-level strategy metrics. |
| `AgentOrchestrator` | Product/UI-level Supervisor-Worker shape, workers with capabilities, pause/resume/cancel streams. | It is currently closer to simulated execution; it does not dispatch real tool calls or preserve evidence/handoff packets. |
| `MemoryService` | Project memory, code preferences, conversations, error patterns, snippets, user corrections, export/import. | No harness session memory, TTL, compaction, branch/correction support, role-specific handoff filtering, or secret redaction contract. |
| `ActionEvidenceStore` | Action-level evidence records with failure kind, logs, artifacts, URLs, and recovery actions. | No run-level evidence ledger joining strategy, handoff, step verification, token/time metrics, and memory commits. |

## Landing Update - 2026-06-20

The first app-side implementation has moved beyond the original P1/P2-only
prompt while preserving the non-counted safety boundary:

- Dart contracts exist for `HarnessMemoryPacket`, `HandoffPacket`,
  `StrategyTrace`, and `StepVerification`.
- `StrategyDispatcher.defaultSafe` maps the six registry strategies to
  release-gated runners and falls back unknown strategy IDs to the safe PEV
  runner.
- Runner coverage now includes ReAct, PEV, ReAct plus final verifier,
  Supervisor/Handoff, Swarm Router, and Hierarchical Swarm.
- Supervisor/Handoff emits filtered handoff packets for CodeAgent,
  RuntimeAgent, PreviewAgent, VerifierAgent, MemoryAgent, and ReporterAgent.
- `HarnessMemoryPacketService` bridges `MemoryService` into TTL-bound,
  compacted, redacted packets and proposal-only memory commits.

All of the above remains fake/dry-run/pilot infrastructure until real
provider/tool/device callbacks, verifier outputs, token records, and screenshot
evidence pass the promotion gate. App UI wiring and Android emulator QA are
required before this can be called product-ready.

## Default Algorithm

```text
1. Intake
   - Normalize user goal.
   - Build HarnessMemoryPacket from recent session, pinned facts, project state,
     error patterns, and active constraints.
   - Redact secrets and cap packet size.

2. Supervisor Plan
   - Produce 3-7 verifiable steps.
   - Each step has intent, expected artifact/evidence, allowed tools, risk, and
     recommended specialist role.

3. Execute Step With ReAct
   - Think: one short thought without tool access.
   - Act: one tool call or final step answer.
   - Observe: convert ActionEvidence into a compact observation.
   - Repeat until step done, blocked, or step round limit reached.

4. Handoff If Needed
   - Supervisor may hand off to CodeAgent, RuntimeAgent, PreviewAgent,
     VerifierAgent, GitHubAgent, MemoryAgent, or ReporterAgent.
   - HandoffPacket contains only the filtered step context, not the full raw
     transcript.

5. Verify
   - StepVerification judges artifact, trace, runtime state, and recovery.
   - If failed and retry budget remains, send critique to the same step.
   - If failed after budget, record `fail_accepted` or `blocked` explicitly.

6. Report
   - Reporter summarizes files, previews, evidence IDs, blockers, and next
     actions.
   - No counted benchmark result is emitted without real verifier evidence.

7. Memory Commit
   - Propose compact memory items: project facts, user preferences, reusable
     fixes, failure patterns.
   - Sensitive or raw transcript data is not committed.
```

## Role Set

| Role | Responsibility | Default write access |
| --- | --- | --- |
| Supervisor | Owns plan, routing, budgets, and stop conditions. | No direct file writes. |
| PlannerAgent | Produces and revises verifiable steps. | No direct file writes. |
| CodeAgent | Reads, writes, patches, and explains project artifacts. | Scoped writes after snapshot/diff. |
| RuntimeAgent | Chooses WebView, Helper, Termux, Cloud, or Local runtime. | Typed runtime tasks only. |
| PreviewAgent | Opens previews, captures DOM/snapshot/screenshot evidence. | Read-only preview actions. |
| VerifierAgent | Applies verifier contract and step rubric. | Read-only. |
| GitHubAgent | Commits, Pages, Actions, artifact delivery when authorized. | Only sandbox/authorized typed routes. |
| MemoryAgent | Builds packets and proposes compact memory commits. | User-approved durable memory writes. |
| ReporterAgent | Final report with artifacts, evidence, blockers, and next steps. | No mutation. |

## Field Contracts

### HarnessMemoryPacket

```json
{
  "packet_id": "hmp_<run_id>_<turn>",
  "schema_version": "0.1.0",
  "session_id": "local-session-id",
  "run_id": "strategy-run-id",
  "created_at": "ISO-8601",
  "ttl_seconds": 86400,
  "source_limits": {
    "recent_turns": 12,
    "max_chars": 12000,
    "max_error_patterns": 5
  },
  "user_goal": "redacted user goal",
  "conversation_summary": "compact summary, not raw transcript",
  "recent_turns": [
    {
      "role": "user|assistant|tool",
      "summary": "compact turn summary",
      "evidence_ids": []
    }
  ],
  "project_facts": [
    {
      "fact": "repo uses Flutter/Dart",
      "source": "MemoryService|project_summary|manual",
      "confidence": 0.9
    }
  ],
  "user_preferences": [],
  "error_patterns": [],
  "active_constraints": [
    "do not commit secrets",
    "no counted result without device/model evidence"
  ],
  "redaction": {
    "applied": true,
    "classes": ["secret", "absolute_private_path", "token"]
  }
}
```

### HandoffPacket

```json
{
  "handoff_id": "hoff_<run_id>_<n>",
  "from_role": "Supervisor",
  "to_role": "CodeAgent",
  "reason": "step requires focused patching",
  "priority": "normal|high|critical",
  "step_id": "step_003",
  "task": "atomic task for recipient",
  "input_filter": "summary_only|remove_tool_calls|evidence_refs_only",
  "allowed_tools": ["read_file", "apply_patch", "validate_html"],
  "forbidden_tools": ["raw_shell", "untyped_termux"],
  "context": {
    "goal_summary": "compact goal",
    "dependency_results": [],
    "evidence_ids": [],
    "artifact_paths": []
  },
  "budget": {
    "max_rounds": 3,
    "max_tokens": 4000,
    "timeout_ms": 120000
  },
  "return_contract": {
    "must_return": ["status", "summary", "evidence_ids", "blockers"],
    "no_raw_secret_echo": true
  }
}
```

### StrategyTrace

```json
{
  "trace_id": "strace_<run_id>_<task_id>_<strategy_id>",
  "strategy_id": "plan_execute_verify_single_agent",
  "trace_status": "scaffold_not_run|running|passed|blocked|failed",
  "events": [
    {
      "event_id": "evt_001",
      "type": "plan|think|act|observe|handoff|verify|replan|report|memory_commit",
      "role": "Supervisor",
      "step_id": "step_001",
      "started_at": "ISO-8601",
      "ended_at": "ISO-8601",
      "tool_name": "read_file",
      "evidence_id": "ev-...",
      "summary": "compact non-secret event summary"
    }
  ],
  "handoff_count": 0,
  "planning_revisions": 0,
  "verification_failures_recovered": 0,
  "failure_kind": null
}
```

### StepVerification

```json
{
  "step_id": "step_001",
  "verifier_id": "mobilecode_step_verifier_v1",
  "status": "pass|fail|blocked|fail_accepted|not_run",
  "confidence": 0.0,
  "checks": [
    {
      "name": "artifact_exists",
      "status": "pass|fail|blocked|not_run",
      "evidence_id": "ev-..."
    }
  ],
  "issues": [],
  "critique": "specific retry guidance if failed",
  "retry_allowed": true,
  "retry_count": 0,
  "evidence_ids": [],
  "counts_as_verified_success": false
}
```

## Phased Landing Plan

### P0: Documents And Schema

- Add this design document, taxonomy, metrics contract, strategy registry,
  run schema, scaffold runner, and validator.
- Generate a `strategy_scaffold_not_run` example run.
- Keep all metrics null and all results non-counted.

### P1: Harness Session Memory Contract

- Add Dart models for `HarnessMemoryPacket`, role filters, TTL, redaction, and
  compaction.
- Bridge existing `MemoryService` into packet generation without changing its
  durable storage semantics.
- Add unit tests for redaction, limit enforcement, and packet JSON roundtrip.

### P2: Strategy Trace + PEV Runner Scaffold

- Extend `AgentLoopController` or a new `ReasoningStrategyController` to emit
  `StrategyTrace` events.
- Implement plan, execute, verify, retry, and final report states against fake
  provider/tool adapters first.
- Add benchmark dry-run fixtures for non-counted traces.

### P3: App-Level Supervisor/Handoff Minimum Loop

- Replace simulated `AgentOrchestrator` execution with typed handoff packets or
  introduce a new orchestrator that can coexist with the UI prototype.
- Route to Code, Runtime, Preview, Verifier, Memory, and Reporter roles.
- Enforce role-specific tool allowlists.

### P4: Benchmark Ablation Pilot

- Lock one model, one task subset, one device/emulator tier, one prompt budget,
  and one max-step policy.
- Run non-counted pilots first.
- Promote to `strategy_ablation_result` only when model logs, token records,
  verifier outputs, device evidence, and screenshots are present.

## Goal Prompt For The Next Implementation Worker

```text
Continue MobileCode Mobile Harness Reasoning Strategy v1 from the app-side
non-counted runner layer toward release readiness.

Do not replace AgentLoopController or existing provider/runtime execution
paths. Keep all strategy outputs non-counted unless real provider logs, token
records, verifier outputs, tool evidence, device/emulator evidence, and
screenshots pass PromotionGate.

Next required work:
1. Wire App UI strategy mode selector: Auto, ReAct, Plan-Execute-Verify,
   Supervisor/Handoff, Experimental Swarm.
2. Display current strategy, run status, trace summary, evidence summary,
   blocked reason, retry/replan state, and memory/handoff summaries.
3. Install the latest APK in Android emulator, run one non-counted strategy
   trace, and save screenshots under the strategy evidence directory.
4. Keep fake/scaffold/pilot artifacts clearly labeled non-counted.
5. Run `flutter test test/services/`, Python validators, and `git diff --check`.
```
