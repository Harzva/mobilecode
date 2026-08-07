# T09 GitRuntime Read-only Contract

Status: [x] Completed (skeleton and contract established; helper integration deferred)
Priority: P1
Owner role: software-dev-pipeline + quality-reviewer
Depends on: T02, T03, T04, T10

## Objective

为 MobileCode 建立结构化 GitRuntime read-only contract，替代长期依赖 shell git 字符串的做法。

## Read First

- `roadmap/tasks/T01-mobileagent-borrowing-inventory.md`
- `roadmap/tasks/T10-workspace-path-validator.md`
- `mobile_agent/lib/services/runtime_actions.dart`
- `mobile_agent/lib/services/agent_action_system.dart`
- `mobile_agent/lib/services/project_manager.dart`
- `docs/mobilecode-helper-runtime-protocol.md`

## Can Edit

- `mobile_agent/lib/core/git_runtime/`
- `mobile_agent/lib/services/runtime_actions.dart` only to deprecate shell git paths or route to dry-run
- `docs/mobilecode-helper-runtime-protocol.md`
- `docs/mobilecode-capability-matrix.md`
- `roadmp.md`
- this task file

## Do Not Edit

- Local commit beta implementation.
- Push implementation.
- Private clone implementation.

## Required Read-only API

- `gitHealth`
- `cloneDryRun`
- `gitStatus`
- `gitDiffSummary`
- `gitDiffStat`
- `readFilePreview`
- `privateClonePreflight`

## Required Design Rules

- JSON request/response only。
- No arbitrary git command string。
- No push, pull, merge, rebase, hook execution。
- Private clone preflight never performs clone。
- Results must be convertible into future Evidence Model。

## Implementation Tasks

- [x] Create `mobile_agent/lib/core/git_runtime/` skeleton.
- [x] Add model classes for health, status, diff, file preview and preflight.
- [x] Add abstract controller interface.
- [x] Add mock controller for demo/dev.
- [x] Add provider selection that can later route to Helper or Runner.
- [x] Block legacy shell git actions and point to structured future tasks.
- [x] Update capability matrix after behavior is clear.

## Acceptance Criteria

- Git read-only calls can be represented without shell command strings.
- The API shape can be implemented by Python Helper, Android Helper or cloud runtime.
- Push and local commit remain out of scope.
- Private clone remains preflight-only.

## Completion Notes

- `mobile_agent/lib/core/git_runtime/git_runtime_models.dart` defines JSON-serializable models: `GitHealthResult`, `CloneDryRunResult`, `GitStatusResult`, `GitDiffSummaryResult`, `GitDiffStatResult`, `ReadFilePreviewResult`, `PrivateClonePreflightResult`.
- `mobile_agent/lib/core/git_runtime/git_runtime_controller.dart` defines the abstract `GitRuntimeController` interface with 7 read-only methods. No arbitrary git command strings. No write operations.
- `mobile_agent/lib/core/git_runtime/git_runtime_mock.dart` implements `GitRuntimeMockController` returning realistic canned data for demo/dev/testing.
- `mobile_agent/lib/core/git_runtime/git_runtime_provider.dart` provides `GitRuntimeProvider.select()` routing (currently returns mock; helper/cloud backed controllers are future work).
- `runtime_actions.dart` marks `gitCommit` and `publishPages` as `@Deprecated`, blocks planning them through legacy shell commands, and points to T15/T17 structured replacements.
- Helper-backed and cloud-backed implementations are deferred — the contract is established, but actual HTTP delegation to `/v1/git/*` endpoints requires new helper endpoints.

## Validation

No local Flutter build. Use source checks:

```powershell
Test-Path .\mobile_agent\lib\core\git_runtime
Select-String -Path .\mobile_agent\lib\core\git_runtime\*.dart -Pattern "gitHealth|gitStatus|readFilePreview|privateClonePreflight"
```

## Handoff Prompt

请实现 T09。只做 read-only GitRuntime contract 和 mock/demo wiring。不要实现真实 commit、push、pull、private clone。完成后更新 capability matrix 和 roadmap checkbox。
