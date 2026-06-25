# T22 Legacy Execution Migration

Status: [x] Implemented (inventory and migration doc)
Priority: P3
Owner role: quality-reviewer + software-dev-pipeline
Depends on: T02, T03, T09, T15

## Objective

系统迁移 MobileCode 中绕过 RuntimeManager 或直接 shell/git 的 legacy execution 路径，降低长期安全风险和行为分裂。

## Read First

- `docs/mobilecode-v1-runtime-release-closure.md`
- `docs/mobilecode-risk-register.md`
- `mobile_agent/lib/services/agent_action_system.dart`
- `mobile_agent/lib/services/project_manager.dart`
- `mobile_agent/lib/services/runtime_actions.dart`
- `mobile_agent/lib/services/runtime_manager.dart`

## Can Edit

- `mobile_agent/lib/services/agent_action_system.dart`
- `mobile_agent/lib/services/project_manager.dart`
- `mobile_agent/lib/services/runtime_actions.dart`
- `mobile_agent/lib/services/runtime_manager.dart`
- `docs/mobilecode-risk-register.md`
- `docs/mobilecode-capability-matrix.md`
- `roadmp.md`
- this task file

## Do Not Edit

- Unrelated UI.
- Git push implementation.
- Build outputs.

## Migration Targets

- Direct `Process.run` calls。
- Shell git commit。
- Shell git push。
- Raw command construction。
- Unstructured runtime errors。
- Any path that writes outside approved workspace。

## Strategy

- First mark legacy paths as deprecated or blocked in code comments and docs.
- Route safe actions through RuntimeManager.
- Route Git actions through GitRuntime dry-run/preflight.
- Remove or disable dangerous shortcuts only after equivalent safe path exists.

## Acceptance Criteria

- Known legacy paths are inventoried.
- Risk register links to each path.
- Shell git write paths are blocked, dry-run, or routed through safe GitRuntime.
- No user change is reverted while migrating.

## Validation

```powershell
Select-String -Path .\mobile_agent\lib\**\*.dart -Pattern "Process.run|git push|git commit|shell"
```

## Handoff Prompt

请实现 T22 时先盘点，不要一上来删除代码。迁移必须保持现有安全路径可用，并且所有 Git 写入改为 blocked/dry-run/preflight，直到 T16/T17 明确完成。

## Completion Notes

**Implemented**:
- `docs/mobilecode-legacy-execution-migration.md` — full inventory of legacy execution paths:
  - fail-closed git write paths across agent_action_system, terminal_service, project_manager quickCommit, self_action_registry, self_invocation_service
  - originally left 2 active legacy paths deferred (RunCommandAction, project_manager.initGit); T24 later made both fail closed
  - 4 runtime internal process usages (not bypasses)
  - 1 active read-only self-action git operation (git.status)
  - 4 GitHub API operations (not local git)
- Risk register R-001 updated with migration doc cross-reference.
- Capability matrix Git Read-Only section updated with migration doc reference.
- `project_manager.quickCommit()` now fails closed instead of running direct `git add` / `git commit`.

**Not done** (intentionally):
- T22 did not close `RunCommandAction` and `project_manager.initGit()`; T24 later closed both as fail-closed paths.
- No deletion of fail-closed paths — they serve as safety documentation.
- No changes to unrelated UI/构建代码.
