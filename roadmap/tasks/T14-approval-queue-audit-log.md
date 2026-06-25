# T14 Approval Queue 与 Audit Log

Status: [x] Completed
Priority: P1
Owner role: software-dev-pipeline + quality-reviewer
Depends on: T04, T13

## Objective

把 MobileCode 的高风险动作纳入统一审批和审计链路，形成 MobileAgent 式可信执行体验。

## Read First

- `roadmap/tasks/T04-security-model.md`
- `roadmap/tasks/T13-evidence-model.md`
- `mobile_agent/lib/services/runtime_actions.dart`
- `mobile_agent/lib/services/runtime_manager.dart`
- existing storage patterns under `mobile_agent/lib/`

## Can Edit

- `mobile_agent/lib/core/approvals/`
- `mobile_agent/lib/core/audit/`
- `mobile_agent/lib/core/evidence/`
- relevant UI screens/widgets after locating current patterns
- `docs/mobilecode-security-model.md`
- `roadmp.md`
- this task file

## Do Not Edit

- Real external write adapters.
- Real Git commit/push behavior.
- Helper command allowlist.

## Required Concepts

- Approval request。
- Risk level。
- Evidence bundle。
- Dry-run payload。
- Human decision。
- Execution result。
- Audit event。
- Redacted output。

## Implementation Tasks

- [x] Create approval request model.
- [x] Create approval queue store.
- [x] Create audit event model.
- [x] Create audit log store.
- [x] Add redaction/truncation policy for audit details.
- [x] Add minimal UI or developer-visible debug surface.
- [x] Route one preview-only action into the queue as proof.

## Completion Notes

- `mobile_agent/lib/core/approvals/approval_model.dart` defines `ApprovalRequest` with all required fields: `id`, `actionType`, `title`, `description`, `riskLevel`, `evidenceIds`, `dryRunPayload`, `decision`, `decisionReason`, `decisionBy`, `decisionAt`, `executionResult`, `executionDetails`, `createdAt`, `expiresAt`. Enums: `ApprovalRiskLevel`, `ApprovalDecision`, `ExecutionResult`.
- `mobile_agent/lib/core/approvals/approval_store.dart` implements `ApprovalStore` with in-memory storage, approve/reject/recordExecution, purgeExpired, toJson/fromJson serialization. No new dependencies.
- `mobile_agent/lib/core/audit/audit_model.dart` defines `AuditEvent` with fields: `id`, `type`, `action`, `summary`, `details`, `evidenceId`, `approvalRequestId`, `redactedOutput`, `createdAt`. Enum: `AuditEventType` covering all action types.
- `mobile_agent/lib/core/audit/audit_store.dart` implements `AuditStore` with in-memory storage, findByAction/findByEvidenceId/findByApprovalId, recent(), toJson/fromJson serialization. Truncates redacted output to 2048 chars. Max 500 events retained.
- `mobile_agent/lib/screens/git_runtime_diagnostics_sheet.dart` now routes the preview-only `commitPlanDryRun` result into an in-memory approval queue request with commit-plan and secret-scan evidence IDs.
- The same diagnostics path records an `approvalRequested` audit event linked to that approval request. The queued item is explicitly dry-run only and has `executionResult: notExecuted`.
- Security model updated: approval queue and audit log status changed from "Requirement" to "Requirement — model and in-memory store exist; preview-only diagnostics integration exists."

## Acceptance Criteria

- High-risk actions can be queued before execution.
- Approval status persists across app restart if local storage is available.
- Audit log never stores token/secret cleartext.
- Rejected actions do not execute.
- Demo mode can show sample approval requests.

## Validation

```powershell
Test-Path .\mobile_agent\lib\core\approvals
Test-Path .\mobile_agent\lib\core\audit
Select-String -Path .\mobile_agent\lib\core\**\*.dart -Pattern "Approval|Audit|redact|risk"
```

## Handoff Prompt

请实现 T14。先做模型和持久化，再接一个低风险 preview demo。不要同时做真实 Git commit、push 或外部发送。
