# T12 GitRuntime Diagnostics UI

Status: [x] Completed
Priority: P1
Owner role: software-dev-pipeline
Depends on: T09, T13

## Objective

在 MobileCode App 内提供 GitRuntime 诊断和 QA scenarios，让用户清楚看到 Git 能力状态、read-only 结果、blocked 能力和 evidence。

## Read First

- `mobile_agent/lib/` current navigation and screens
- `mobile_agent/lib/services/runtime_manager.dart`
- `roadmap/tasks/T09-gitruntime-readonly-contract.md`
- `roadmap/tasks/T13-evidence-model.md`
- `docs/mobilecode-capability-matrix.md`

## Can Edit

- `mobile_agent/lib/` relevant screens/routes/widgets after locating existing patterns
- `docs/mobilecode-capability-matrix.md`
- `roadmp.md`
- this task file

## Do Not Edit

- GitRuntime backend behavior unless only adding UI-facing fields.
- Helper implementation.

## UI Requirements

- Show GitRuntime health.
- Show status/diff/file preview scenarios.
- Show blocked capabilities: push、pull、private clone、merge、rebase。
- Show why an operation is preview/dry-run/preflight-only.
- Provide evidence cards, not raw logs.
- Demo mode should work without credentials.

## Acceptance Criteria

- User can inspect GitRuntime readiness without reading docs.
- Blocked operations are visibly blocked.
- UI does not imply push/private clone are ready.
- No local build is required in this task; visual validation can be done later by app testing tasks.

## Completion Notes

- `mobile_agent/lib/screens/git_runtime_diagnostics_sheet.dart` implements the full diagnostics UI as a bottom sheet.
- Shows GitRuntime health (git version, workspace root, ready status).
- Shows Git status (branch, staged/modified/untracked counts).
- Shows file preview with redaction badges (redactionCount displayed when > 0).
- Shows commit plan dry-run with included/excluded files, suggested message, blocked operations.
- Shows secret scan results with CLEAN/BLOCKED indicators.
- Shows evidence cards with severity, status labels (READ-ONLY, DRY RUN, BLOCKED), and blocked operations list.
- Blocked capabilities panel explicitly lists: Push, Pull, Private Clone, Merge, Rebase as Blocked.
- Commit planning labeled as Preview (dry-run only).
- "No real git write operations execute from this screen" disclaimer.
- Demo mode uses `GitRuntimeMockController` — works without credentials.
- Entry point added to home_screen.dart tools tab as "GitRuntime diagnostics" shortcut.
- `_ModuleAction.gitRuntimeDiag` enum value and handler added.

## Validation

```powershell
Select-String -Path .\mobile_agent\lib\**\*.dart -Pattern "GitRuntime|git runtime|capability|Blocked"
```

## Handoff Prompt

请实现 T12。先找到现有导航和诊断页面模式，保持 MobileCode 当前 UI 风格。不要扩大 Git 后端能力，只展示 T09/T13 已提供的数据。
