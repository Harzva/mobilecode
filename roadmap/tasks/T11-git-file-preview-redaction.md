# T11 Git File Preview 与 Redaction

Status: [x] Completed
Priority: P1
Owner role: quality-reviewer + software-dev-pipeline
Depends on: T09, T10

## Objective

为 GitRuntime 的 `readFilePreview` 建立安全文件预览规则：限制大小、识别 binary、脱敏 secret、避免泄漏完整敏感文件。

## Read First

- `roadmap/tasks/T09-gitruntime-readonly-contract.md`
- `roadmap/tasks/T10-workspace-path-validator.md`
- `docs/mobilecode-security-model.md`
- `mobile_agent/tooling/mobilecode_helper_daemon.py`

## Can Edit

- `mobile_agent/lib/core/git_runtime/`
- `mobile_agent/tooling/mobilecode_helper_daemon.py`
- Android Helper file preview code after locating it
- `docs/mobilecode-helper-runtime-protocol.md`
- `docs/mobilecode-security-model.md`
- `roadmp.md`
- this task file

## Do Not Edit

- Commit, push or private clone behavior.
- UI beyond model fields required for preview.

## Required Preview Fields

- `path`
- `exists`
- `isBinary`
- `isTruncated`
- `lineCount`
- `maxLines`
- `maxBytes`
- `redactionCount`
- `preview`
- `warnings`

## Required Redaction Targets

- API keys。
- Bearer tokens。
- GitHub tokens。
- Private key blocks。
- `.env` style secrets。
- Lark/GitHub/WeChat tokens。

## Acceptance Criteria

- Binary files are not dumped as text.
- Large files are truncated.
- Suspected secrets are redacted.
- Preview response includes enough metadata for UI to explain truncation.
- All preview paths pass T10 validator first.

## Completion Notes

- `ReadFilePreviewResult` now includes all required fields: `path`, `exists`, `isBinary`, `isTruncated`, `lineCount`, `maxLines`, `maxBytes`, `redactionCount`, `preview`, `warnings`. Legacy fields (`content`, `truncated`, `size`, `binary`) retained for backward compatibility.
- `git_runtime_redaction.dart` implements: binary detection by extension and content analysis, secret redaction (10+ patterns: API keys, Bearer tokens, GitHub tokens, private keys, `.env` secrets, AWS keys, Lark/WeChat tokens), truncation by bytes and lines, path validation (T10 rules).
- `GitRuntimeMockController.readFilePreview()` returns T11-compliant fields.
- `ReadFilePreviewResult.fromJson()` factory added for deserialization.
- All preview paths validated via `validatePreviewPath()` before reading (rejects absolute, traversal, null-byte, oversized paths).

## Validation

```powershell
Select-String -Path .\docs\mobilecode-helper-runtime-protocol.md -Pattern "file preview|redact|binary|truncated"
Select-String -Path .\mobile_agent\lib\core\git_runtime\*.dart -Pattern "redact|preview|binary|truncated"
```

## Handoff Prompt

请实现 T11。只处理文件预览安全，不要加入编辑文件或写文件功能。任何疑似 secret 必须默认 redacted。
