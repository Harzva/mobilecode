# T15 Commit Plan 与 Secret Scan

Status: [x] Completed
Priority: P1
Owner role: software-dev-pipeline + quality-reviewer
Depends on: T09, T10, T11, T13, T14

## Objective

支持“准备提交”的 dry-run 体验：展示将要提交的文件、建议 commit message、风险摘要和 secret scan 结果，但不默认真实 commit。

## Read First

- `roadmap/tasks/T09-gitruntime-readonly-contract.md`
- `roadmap/tasks/T10-workspace-path-validator.md`
- `roadmap/tasks/T11-git-file-preview-redaction.md`
- `roadmap/tasks/T13-evidence-model.md`
- `roadmap/tasks/T14-approval-queue-audit-log.md`
- `mobile_agent/lib/services/runtime_actions.dart`

## Can Edit

- `mobile_agent/lib/core/git_runtime/`
- `mobile_agent/lib/services/runtime_actions.dart`
- `docs/mobilecode-capability-matrix.md`
- `docs/mobilecode-risk-register.md`
- `roadmp.md`
- this task file

## Do Not Edit

- Real local commit.
- Push.
- Private clone.

## Required API

- `commitPlanDryRun`
- `secretScanPlan`

## Required Behavior

- Returns changed files and intended included/excluded files。
- Suggests commit message without writing。
- Detects likely secrets。
- Converts result to Evidence。
- Can be queued for approval but does not execute real commit in this task。
- Replaces legacy `RuntimeAction.gitCommit` shell command with dry-run planning or marks it blocked.

## Acceptance Criteria

- User can see what would be committed.
- Secret findings block future commit beta gate.
- No real commit happens.
- Capability matrix says commit planning is Preview. After T16, local commit is feature-flagged Beta and remains default-off.

## Completion Notes

- `git_runtime_models.dart` adds `CommitPlanDryRunResult`, `CommitPlanFileEntry`, `SecretScanPlanResult`, `SecretFinding` with full toJson serialization.
- `git_runtime_controller.dart` adds `commitPlanDryRun()` and `secretScanPlan()` methods to the abstract interface.
- `git_runtime_mock.dart` implements both methods with realistic demo data (3 files, one excluded `.env`, no secret findings, blocked operations list).
- `runtime_actions.dart` legacy `gitCommit` remains blocked with explicit comment: "Use GitRuntime.commitPlanDryRun (T15) for planning and secret scanning."
- Capability matrix updated: Git Commit Planning changed from "Blocked" to "Preview (dry-run only)".
- GitRuntime diagnostics UI (T12) shows commit plan dry-run and secret scan results with DRY RUN/BLOCKED/CLEAN labels.
- No real `git add`, `git commit`, or filesystem mutations happen.
- Secret findings would block future commit beta gate (via `SecretScanPlanResult.blockCommit`).
- `runtime_actions.dart` does not contain shell `git add .`, `git commit -m`, or `git push origin HEAD`.

## Validation

```powershell
Select-String -Path .\mobile_agent\lib\core\git_runtime\*.dart -Pattern "commitPlan|secretScan|dryRun"
Select-String -Path .\mobile_agent\lib\services\runtime_actions.dart -Pattern "gitCommit|commitPlan|dry"
```

## Handoff Prompt

请实现 T15。把 git commit 从“直接 shell 执行”迁到“计划和 secret scan”。不要实现真实 commit。完成后更新 capability matrix。
