# T07 Runtime Provider Selection Evidence

Status: [x] Completed
Priority: P1
Owner role: software-dev-pipeline
Depends on: T06

## Objective

让 RuntimeManager 在选择 Helper、Termux、cloud、webViewOnly 等 provider 时产生可解释证据，方便用户和后续 Agent 理解“为什么选这个运行时”。

## Read First

- `mobile_agent/lib/services/runtime_provider.dart`
- `mobile_agent/lib/services/runtime_manager.dart`
- `mobile_agent/lib/services/mobile_code_helper_provider.dart`
- `docs/mobilecode-helper-runtime-protocol.md`
- `roadmap/tasks/T13-evidence-model.md`

## Can Edit

- `mobile_agent/lib/services/runtime_provider.dart`
- `mobile_agent/lib/services/runtime_manager.dart`
- `docs/mobilecode-helper-runtime-protocol.md`
- `roadmp.md`
- this task file

## Do Not Edit

- UI screens unless a minimal text diagnostic hook already exists.
- Helper daemon implementation.
- Build workflows.

## Scope

- Provider selection reason。
- Capability mismatch reason。
- Runtime health evidence。
- Fallback chain。
- User-visible diagnostic summary。

## Implementation Tasks

- [x] Add provider selection evidence model or temporary DTO.
- [x] Record candidate providers and why each was accepted/rejected.
- [x] Include token/auth, network, workspace, platform and capability reasons.
- [x] Expose latest selection evidence through RuntimeManager.
- [x] Add docs to helper protocol explaining capability negotiation.
- [x] Keep this compatible with future T13 Evidence Model.

## Acceptance Criteria

- [x] A developer can inspect why MobileCode picked Helper vs webViewOnly.
- [x] Rejected provider reasons are structured, not just free text.
- [x] Evidence contains no token or secret.
- [x] Future UI can render this without parsing logs.

## Completion Notes

- `ProviderSelectionCandidate` has an explicit `selected` field so ready fallback providers are not mislabeled as selected.
- `RuntimeManager.latestSelectionEvidence` records candidate availability, readiness, selected provider, and rejection reasons without tokens or secrets.
- 2026-06-25 follow-up: `RuntimeManager.withExternalTermux()` now prefers `MobileCode Helper`, then `External Termux daemon`, then legacy `External Termux`, with `Embedded Lite Runtime` behind those providers until controlled-task support is ready.
- 2026-06-25 follow-up: `MobileCodeHelperProvider` rejects `/v1/health` payloads marked `runtimeKind=termuxDaemon` or `termux=true`, so the Termux daemon is selected by `TermuxDaemonProvider` as an external strong runtime rather than being claimed by the Helper APK provider.

## Validation

```powershell
Select-String -Path .\mobile_agent\lib\services\runtime_manager.dart -Pattern "evidence|reason|provider"
Select-String -Path .\mobile_agent\lib\services\runtime_provider.dart -Pattern "capabilit|health|failure"
```

## Handoff Prompt

请实现 T07。目标是 runtime provider 选择证据，不是新运行时。保持结构简单，未来可以并入 T13 的统一 Evidence Model。
