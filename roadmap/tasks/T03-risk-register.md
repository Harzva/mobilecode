# T03 Risk Register

Status: [x] Completed
Priority: P0
Owner role: quality-reviewer + Codex current model
Depends on: T02

## Objective

建立 MobileCode 风险寄存器，把运行时、Git、Helper、token、workspace、release claim 等风险显式化，作为后续实现和发布门禁的依据。

## Read First

- `roadmap/tasks/T01-mobileagent-borrowing-inventory.md`
- `roadmap/tasks/T02-capability-matrix.md`
- `docs/mobilecode-helper-runtime-protocol.md`
- `docs/mobilecode-v1-runtime-release-closure.md`
- `mobile_agent/tooling/mobilecode_helper_daemon.py`
- `mobile_agent/lib/services/runtime_actions.dart`
- `mobile_agent/lib/services/agent_action_system.dart`
- `mobile_agent/lib/services/project_manager.dart`

## Can Edit

- `docs/mobilecode-risk-register.md`
- `roadmp.md`
- this task file

## Do Not Edit

- Runtime implementation.
- Helper implementation.
- README capability claims, unless T02 has already created the matrix link and this task finds a critical contradiction.

## Required Risk Areas

- Generic shell command execution。
- Legacy direct `Process.run` paths。
- Shell-based git commit/push。
- Token leakage in logs, audit, workspace or crash reports。
- Workspace path escape。
- Helper daemon and Android Helper behavior drift。
- Task cancellation not actually stopping process。
- NDJSON log replay or truncation confusion。
- Release note overclaiming unverified features。
- User misunderstanding demo/dry-run as real execution。
- Private clone and push token scope。
- Branch protection and non-fast-forward push。

## Risk Entry Format

Each risk should include:

- ID。
- Title。
- Severity。
- Current exposure。
- User impact。
- Mitigation。
- Stop line。
- Linked roadmap task。
- Evidence needed before status can improve。

## Acceptance Criteria

- [x] `docs/mobilecode-risk-register.md` exists.
- [x] Every P0/P1 roadmap task links to at least one risk or explicitly states no new risk.
- [x] Git write and external write risks are not hidden under generic wording.
- [x] The register names known legacy paths instead of pretending they do not exist.

## Completion Notes

- `docs/mobilecode-risk-register.md` created with 12 risk entries (R-001 through R-012).
- All required risk areas covered: legacy `Process.run`, shell git commit/push, token leakage, workspace escape, Helper drift, task cancellation, NDJSON replay, release overclaim, demo/dry-run misunderstanding, private clone/push auth, branch protection/non-fast-forward, generic shell execution.
- Each risk entry has ID, Title, Severity, Current exposure, User impact, Mitigation, Stop line, Linked roadmap task, and Evidence needed.
- Summary table maps every risk to its severity and linked roadmap task.
- Codex review corrected summary statuses so T10/T05/T20-linked risks remain open or partially mitigated until their follow-up tasks are implemented.
- Codex review also updated R-008 after tightening README wording, so the risk now tracks future release/marketing drift rather than an already-fixed README contradiction.
- Evidence sources: `agent_action_system.dart` (Process.run paths), `runtime_actions.dart` (commit/push plans), `runtime_provider.dart` (failure kinds), `mobilecode-helper-runtime-protocol.md` (auth/workspace), `mobilecode-release-qa.md` (CI evidence).

## Validation

```powershell
Test-Path .\docs\mobilecode-risk-register.md
Select-String -Path .\docs\mobilecode-risk-register.md -Pattern "Process.run|git push|token|workspace|Blocked|Stop line"
```

## Handoff Prompt

请实现 T03。目标是写风险文档，不修代码。重点把 MobileCode 已知 legacy execution、generic shell、Git 写入和 release overclaim 风险讲清楚。完成后更新 checkbox。
