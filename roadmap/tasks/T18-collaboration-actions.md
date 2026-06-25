# T18 Collaboration Actions

Status: [x] Implemented (generic model and demo preview builder; real adapters deferred)
Priority: P2
Owner role: software-dev-pipeline + quality-reviewer
Depends on: T13, T14, T17

## Objective

把 MobileAgent 的 MobileLark preview-first 思路改造成 MobileCode 通用 Collaboration Actions，支持 Lark、GitHub、WeChat 等 adapter，但默认不真实发送。

## Read First

- `roadmap/tasks/T13-evidence-model.md`
- `roadmap/tasks/T14-approval-queue-audit-log.md`
- `roadmap/tasks/T17-push-preflight-export.md`
- `docs/mobilecode-security-model.md`
- `docs/mobilecode-capability-matrix.md`

## Can Edit

- `mobile_agent/lib/modules/collaboration/`
- `mobile_agent/lib/core/evidence/`
- `mobile_agent/lib/core/approvals/`
- `docs/mobilecode-capability-matrix.md`
- `roadmp.md`
- this task file

## Do Not Edit

- Real external API send implementation unless a separate task approves it.
- GitHub workflow assistant internals; that belongs to T19.
- Token storage.

## Required Action Types

- `sendMessage`
- `createDoc`
- `createTask`
- `createIssueComment`
- `createReleaseNote`
- `createWechatDraft`

## Required Fields

- `id`
- `type`
- `title`
- `summary`
- `payload`
- `risk`
- `dryRun`
- `idempotencyKey`
- `preview`
- `evidence`

## Acceptance Criteria

- Collaboration action can preview without credentials.
- High-risk actions enter approval queue.
- Demo mode never calls external APIs.
- UI/copy clearly distinguishes draft, preview and sent.
- Capability matrix does not imply real send is ready.

## Validation

```powershell
Test-Path .\mobile_agent\lib\modules\collaboration
Select-String -Path .\mobile_agent\lib\modules\collaboration\*.dart -Pattern "dryRun|preview|risk|idempotency"
```

## Handoff Prompt

请实现 T18。先做通用模型和 demo preview。不要把 Lark 写成唯一协作层，不要真实发送任何外部消息。

## Completion Notes

**Implemented**:
- `CollaborationAction` model with id, type, title, summary, payload, risk, dryRun, idempotencyKey, preview, evidenceIds, status, targetAdapter.
- `CollaborationActionType` enum: sendMessage, createDoc, createTask, createIssueComment, createReleaseNote, createWechatDraft, createLarkReport, createGitHubPR, createGitHubIssue, custom.
- `CollaborationRiskLevel` enum: low, medium, high, critical.
- `CollaborationActionStatus` enum: draft, preview, approved, sent, failed, blocked.
- `CollaborationPreview` model with title, body, format, targetAdapter, metadata.
- `CollaborationAction.requiresApproval`, `approvalRiskLevel`, and `toApprovalRequest()` bridge action metadata into the T14 approval model.
- `CollaborationApprovalBridge.queueIfRequired()` adds high/critical-risk previews to `ApprovalStore` and attaches `approvalRequestId`.
- `CollaborationDemoPreviewBuilder` — produces realistic previews for all 10 action types without external API calls.
- JSON serialization for all models.
- Capability matrix updated: Collaboration Actions changed from Coming Soon to Preview.

**Not done** (intentionally):
- No real external API calls (Lark, GitHub, WeChat).
- No token storage.
- No real adapter implementations.
