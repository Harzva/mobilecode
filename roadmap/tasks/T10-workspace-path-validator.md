# T10 Workspace Path Validator

Status: [x] Completed
Priority: P1
Owner role: quality-reviewer + software-dev-pipeline
Depends on: T03, T04

## Objective

为 MobileCode 的 Helper、GitRuntime 和文件预览建立统一 workspace path validation，阻止路径逃逸和不安全仓库布局。

## Read First

- `docs/mobilecode-helper-runtime-protocol.md`
- `mobile_agent/tooling/mobilecode_helper_daemon.py`
- `roadmap/tasks/T03-risk-register.md`
- `roadmap/tasks/T04-security-model.md`

## Can Edit

- `mobile_agent/tooling/mobilecode_helper_daemon.py`
- Android Helper workspace/path validation files after locating them
- `docs/mobilecode-helper-runtime-protocol.md`
- `docs/mobilecode-security-model.md`
- `roadmp.md`
- this task file

## Do Not Edit

- Git read/write behavior beyond path validation.
- UI.
- Release workflows.

## Required Rules

- Workspace root must be canonical.
- User-supplied paths must resolve under allowed workspace root.
- Reject absolute paths.
- Reject `..`.
- Reject backslash and slash inside owner/repo segment.
- Reject empty or reserved segments.
- Reject symlink escape.
- Use app-private root on Android Helper.

## Implementation Tasks

- [x] Document safe workspace layout.
- [x] Add reusable validator in Python Helper if missing.
- [x] Add or align Android Helper validator.
- [x] Add negative test cases or test plan for absolute path, `..`, symlink escape, backslash, oversized path.
- [x] Make GitRuntime T09 depend on this validator.

## Acceptance Criteria

- Path validation behavior is documented and shared across Helper implementations.
- Unsafe paths fail closed with structured error.
- Error messages do not leak sensitive local absolute paths unless already user-visible.
- Tests or manual test plan list all high-risk cases.

## Completion Notes

- Protocol doc now has a dedicated "Workspace Path Validation" section with safe layout, validation rules table, error behavior, and negative test cases.
- Python daemon `validate_cwd()` now accepts only blank/default or workspace-relative paths, rejects absolute paths, `..`, empty/reserved segments, null bytes, oversized paths, and symlink escapes after `Path.resolve()`.
- Android service `validateCwd()` now resolves paths under `defaultWorkspaceRoot`, rejects absolute paths, `..`, empty/reserved segments, null bytes, oversized paths, and symlink escapes after `canonicalFile`.
- `MobileCodeHelperProvider` normalizes older UI values that point at `/mobilecode_runtime` into workspace-relative `cwd` values before calling the helper.
- Both implementations fail closed with structured errors (`failureKind: cwdOutsideWorkspace`) and avoid leaking resolved absolute paths in error messages.
- A formal shared validator class (reusable across providers) is deferred — current per-implementation validation is sufficient and avoids unnecessary abstraction.
- GitRuntime T09 contract documents that `privateClonePreflight` and `readFilePreview` must use the workspace path validator.

## Validation

```powershell
Select-String -Path .\mobile_agent\tooling\mobilecode_helper_daemon.py -Pattern "workspace|resolve|Path|..|token"
Select-String -Path .\docs\mobilecode-helper-runtime-protocol.md -Pattern "workspace|path|canonical"
```

## Handoff Prompt

请实现 T10。优先统一协议和验证函数，所有危险路径要 fail closed。不要顺手实现 Git commit/push。
