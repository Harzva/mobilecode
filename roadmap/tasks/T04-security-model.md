# T04 Security Model

Status: [x] Completed
Priority: P0
Owner role: quality-reviewer + software-dev-pipeline
Depends on: T02, T03

## Objective

定义 MobileCode 的安全模型，明确从用户意图到真实执行之间必须经过哪些边界，尤其是 runtime、Git、外部协作、token 和审计。

## Read First

- `docs/mobilecode-helper-runtime-protocol.md`
- `docs/mobile-runtime-permissions.md`
- `docs/mobilecode-production-hardening.md`
- `roadmap/tasks/T03-risk-register.md`
- `mobile_agent/lib/services/runtime_manager.dart`
- `mobile_agent/lib/services/mobile_code_helper_provider.dart`

## Can Edit

- `docs/mobilecode-security-model.md`
- `roadmp.md`
- this task file

## Do Not Edit

- Runtime code.
- Helper code.
- Android permissions.

## Required Security Chain

```text
User Intent
-> Plan
-> Dry-run Preview
-> Risk Classification
-> Approval Queue
-> Human Approval
-> Execution Boundary
-> Redacted Result
-> Audit Log
```

## Required Sections

- Trust boundaries: Flutter app、Python Helper daemon、Android Helper APK、External Termux、Cloud runtime、GitHub/Lark/WeChat。
- Token policy: storage、transmission、redaction、logging ban。
- Workspace policy: app-private root、canonical path validation、safe project layout。
- Command policy: allowlist、no shell expansion、structured GitRuntime。
- External write policy: preview-first、approval-required、idempotency key、audit。
- Demo mode policy: no real external effects。
- Release claim policy: docs must match capability matrix。

## Acceptance Criteria

- 文档给出清晰安全链路。
- 每个 runtime provider 的边界明确。
- Git 和协作写入都被纳入同一 approval/audit 思路。
- 文档不承诺尚未实现的安全存储或真实外部写入。

## Validation

```powershell
Test-Path .\docs\mobilecode-security-model.md
Select-String -Path .\docs\mobilecode-security-model.md -Pattern "Dry-run|Approval|Audit|Token|Workspace|Demo"
```

## Handoff Prompt

请实现 T04。只写安全模型文档。不要把未来能力写成已经完成；所有 production 要求必须标注为 requirement 或 future gate。
