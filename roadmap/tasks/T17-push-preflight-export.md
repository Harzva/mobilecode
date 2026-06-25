# T17 Push Preflight 与 Evidence Export

Status: [x] Implemented (preflight checks and draft export models; push remains blocked)
Priority: P2
Owner role: quality-reviewer + software-dev-pipeline
Depends on: T13, T14, T15

## Objective

提供 push 风险预检和安全导出方案，让用户理解为什么手机端不能直接 push，并能把 evidence 交给桌面端或 CI 接手。

## Read First

- `roadmap/tasks/T13-evidence-model.md`
- `roadmap/tasks/T14-approval-queue-audit-log.md`
- `roadmap/tasks/T15-commit-plan-secret-scan.md`
- `docs/mobilecode-risk-register.md`
- `docs/mobilecode-capability-matrix.md`

## Can Edit

- `mobile_agent/lib/core/git_runtime/`
- `docs/mobilecode-capability-matrix.md`
- `docs/mobilecode-risk-register.md`
- `roadmp.md`
- this task file

## Do Not Edit

- Real `git push`.
- PR creation.
- Lark/WeChat/GitHub message sending.
- Token storage implementation.

## Required API

- `pushPreflight`
- `pushEvidenceExport`

## Required Preflight Checks

- Remote configured。
- Current branch。
- Upstream branch。
- Dirty state。
- Non-fast-forward possibility。
- Branch protection unknown/known。
- Token scope missing/unknown。
- Network state。
- Local commit beta status。

## Required Exports

- Markdown audit note。
- PR fallback draft。
- Lark/WeChat report draft。
- Remote-linked task summary。

All exports are drafts only.

## Acceptance Criteria

- No path executes `git push`.
- User receives concrete next-step guidance.
- Exported drafts clearly say they were not sent.
- Capability matrix marks push as preflight/export-only or blocked.

## Validation

```powershell
Select-String -Path .\mobile_agent\lib\core\git_runtime\*.dart -Pattern "pushPreflight|pushEvidence|draft|blocked"
Select-String -Path .\docs\mobilecode-capability-matrix.md -Pattern "push|preflight|blocked"
```

## Handoff Prompt

请实现 T17。只做 preflight 和草稿导出。不要创建 PR、不要发送消息、不要 push。

## Completion Notes

**Implemented**:
- `PushPreflightCheck` model with name, status (pass/warn/fail/unknown), detail.
- `PushPreflightResult` model with pushBlocked (always true), checks list, branch/remote info, recommendation.
- `PushEvidenceDraft` model with format (markdown/prDraft/larkReport), title, body, isSent (always false).
- `PushEvidenceExportResult` model with drafts list, evidence IDs, exportedAt.
- `pushPreflight()` and `pushEvidenceExport()` methods on `GitRuntimeController`.
- Mock implementation: 9 preflight checks, 4 draft formats (markdown audit note, PR draft, Lark report, remote-linked task summary).
- Capability matrix updated with Push Preflight & Evidence Export as Preview.

**Not done** (intentionally):
- No real git push execution.
- No real PR creation.
- No real Lark/WeChat message sending.
- No token storage.
