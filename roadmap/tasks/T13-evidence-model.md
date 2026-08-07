# T13 Evidence Model

Status: [x] Completed
Priority: P1
Owner role: software-dev-pipeline + quality-reviewer
Depends on: T04, T07, T09

## Objective

建立统一 Evidence Model，让 runtime、GitRuntime、collaboration、release QA 的结果能用同一种方式进入 UI、approval queue 和 audit log。

## Read First

- `roadmap/tasks/T04-security-model.md`
- `roadmap/tasks/T07-runtime-provider-selection-evidence.md`
- `roadmap/tasks/T09-gitruntime-readonly-contract.md`
- `mobile_agent/lib/services/runtime_provider.dart`
- `mobile_agent/lib/services/runtime_manager.dart`

## Can Edit

- `mobile_agent/lib/core/evidence/`
- `mobile_agent/lib/services/runtime_provider.dart`
- `mobile_agent/lib/services/runtime_manager.dart`
- `docs/mobilecode-security-model.md`
- `roadmp.md`
- this task file

## Do Not Edit

- Approval queue implementation; that belongs to T14.
- Git write operations.
- External collaboration adapters.

## Required Model Fields

- `id`
- `source`
- `category`
- `severity`
- `title`
- `summary`
- `details`
- `status`
- `dryRun`
- `blockedOperations`
- `redacted`
- `createdAt`
- `relatedActionId`

## Evidence Sources

- Runtime provider selection。
- Helper health。
- GitRuntime health/status/diff/file preview。
- Commit plan dry-run。
- Secret scan。
- Push preflight。
- Collaboration preview。
- Release readiness check。

## Acceptance Criteria

- Evidence can represent read-only, dry-run, preflight, blocked and executed results.
- Evidence does not contain raw secrets.
- Evidence is serializable for future local persistence.
- RuntimeManager can emit or expose at least one evidence example.

## Completion Notes

- `mobile_agent/lib/core/evidence/evidence_model.dart` defines the `Evidence` class with all required fields: `id`, `source`, `category`, `severity`, `title`, `summary`, `details`, `status`, `dryRun`, `blockedOperations`, `redacted`, `createdAt`, `relatedActionId`.
- Enums: `EvidenceSource` (runtimeProvider, helperHealth, gitRuntime, commitPlan, secretScan, pushPreflight, collaborationPreview, releaseReadiness, approvalQueue, auditLog), `EvidenceCategory`, `EvidenceSeverity`, `EvidenceStatus` (readOnly, dryRun, preflight, blocked, executed, failed).
- Full `toJson()` / `fromJson()` serialization. `copyWith()` method.
- `generateEvidenceId()` utility for unique IDs.
- `RuntimeManager.latestSelectionAsEvidence()` converts provider selection evidence into an `Evidence` record. Contains no tokens or secrets.
- GitRuntime diagnostics UI creates evidence records for health, file preview, commit plan, and secret scan.
- Evidence does not contain raw secrets — only redacted summaries and metadata.

## Validation

```powershell
Test-Path .\mobile_agent\lib\core\evidence
Select-String -Path .\mobile_agent\lib\core\evidence\*.dart -Pattern "Evidence|severity|dryRun|blocked"
```

## Handoff Prompt

请实现 T13。先设计轻量 Dart model，不要过度抽象。目标是让 T14 审批队列和 T12 UI 能复用。
