# T16 Local Commit Beta

Status: [x] Completed — feature-flagged Helper structured commit beta
Priority: P2
Owner role: quality-reviewer + software-dev-pipeline
Depends on: T14, T15

## Objective

在 feature flag 默认关闭的前提下，提供受控 local commit beta。这个任务只有在 commit plan、secret scan、approval、audit 都完成后才能启动。

## Read First

- `roadmap/tasks/T15-commit-plan-secret-scan.md`
- `roadmap/tasks/T14-approval-queue-audit-log.md`
- `docs/mobilecode-security-model.md`
- `docs/mobilecode-risk-register.md`
- `mobile_agent/lib/core/git_runtime/`

## Can Edit

- `mobile_agent/lib/core/git_runtime/`
- Android Helper Git implementation after locating it
- `docs/mobilecode-capability-matrix.md`
- `docs/mobilecode-risk-register.md`
- `roadmp.md`
- this task file

## Do Not Edit

- Push.
- Pull.
- Merge.
- Rebase.
- Hooks.
- Arbitrary shell git execution.

## Required Gates

- `enableLocalCommitBeta` default false。
- Helper git binary available。
- Human approval。
- Secret scan clean。
- Workspace path validation clean。
- No hooks。
- No shell git。
- No push side effects。
- Audit log records outcome。

## Implementation Tasks

- [x] Define local commit beta request/response schema.
- [x] Add feature flag with default false.
- [x] Require T15 commit plan evidence.
- [x] Require T14 approval.
- [x] Implement Android Helper/JGit or equivalent structured commit path.
- [x] Record commit hash and changed files in audit log.
- [x] Add recovery advice for failure.

## Acceptance Criteria

- Default builds cannot accidentally commit.
- Enabling beta still requires approval and clean scan.
- No route triggers push.
- Audit log is enough to understand what happened.

## Validation

No local build. Use source checks and CI/manual QA later.

```powershell
Select-String -Path .\mobile_agent\lib\core\git_runtime\*.dart -Pattern "localCommit|feature|secretScan|approval"
Select-String -Path .\docs\mobilecode-capability-matrix.md -Pattern "local commit|Beta|feature"
```

## Handoff Prompt

请实现 T16 前先确认 T14/T15 已完成。严格保持 feature flag 默认关闭。不要实现 push 或 hooks。

## Completion Notes

**Implemented**:
- `LocalCommitBetaRequest` model with workingDir, message, evidence IDs, approval reference, dryRun flag.
- `LocalCommitBetaGateCheck` and `LocalCommitBetaGateResult` models aggregating the full gate chain.
- `LocalCommitBetaResult` model with success, dryRun, commitHash, changedFiles, auditEventId, recoveryAdvice.
- `kEnableLocalCommitBetaDefault = false` constant — feature flag defaults to off.
- `localCommitBetaGate()` and `localCommitBeta()` methods on `GitRuntimeController`.
- Helper-backed controller in `git_runtime_helper_controller.dart` calls `/v1/git/local-commit-beta/gate` and `/v1/git/local-commit-beta`, and records results through `recordLocalCommitBetaAudit()`.
- `local_commit_beta_audit.dart` records dry-run, blocked, failed, and executed results, including commit hash and changed files when present.
- Python daemon implements `POST /v1/git/local-commit-beta/gate` and `POST /v1/git/local-commit-beta`, disabled by default unless `--enable-local-commit-beta` or `MOBILECODE_ENABLE_LOCAL_COMMIT_BETA=true`.
- Android Helper implements the same endpoints, disabled by default unless `EXTRA_ENABLE_LOCAL_COMMIT_BETA=true`.
- Both helpers use structured `git` argv only, require git-binary/approval/clean-scan/audit gates, and run commits with `core.hooksPath=/dev/null`.
- Legacy agent, terminal, and self-action git commit/push/pull paths are now explicit blocked failures instead of direct git write execution.
- Capability matrix updated to describe Local Commit as feature-flagged Beta, default false.

**Not done** (intentionally):
- No UI toggle for enabling beta.
- No push, hooks, or shell git paths.
- T22 still owns broader legacy execution cleanup outside these Git actions.
