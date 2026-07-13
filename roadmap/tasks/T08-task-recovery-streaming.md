# T08 Task Recovery 与 NDJSON Streaming

Status: [x] Completed (protocol and implementation alignment pass)
Priority: P1
Owner role: software-dev-pipeline + quality-reviewer
Depends on: T06

## Objective

强化 MobileCode 的长任务体验：任务可恢复、日志可续读、stop 语义真实、NDJSON 输出可截断且不泄漏敏感信息。

## Read First

- `docs/mobilecode-helper-runtime-protocol.md`
- `mobile_agent/lib/services/runtime_manager.dart`
- `mobile_agent/lib/services/mobile_code_helper_provider.dart`
- `mobile_agent/tooling/mobilecode_helper_daemon.py`
- `docs/mobilecode-v1-runtime-release-closure.md`

## Can Edit

- `docs/mobilecode-helper-runtime-protocol.md`
- `mobile_agent/lib/services/mobile_code_helper_provider.dart`
- `mobile_agent/lib/services/runtime_manager.dart`
- `mobile_agent/tooling/mobilecode_helper_daemon.py`
- `roadmp.md`
- this task file

## Do Not Edit

- GitRuntime code.
- UI redesign.
- GitHub Actions build pipelines.

## Scope

- Task ID stability。
- Current task lookup。
- Log pagination or tail semantics。
- Stream reconnect。
- Stop endpoint semantics。
- Redaction and truncation policy。

## Implementation Tasks

- [x] Define task lifecycle states in protocol.
- [x] Ensure `/v1/tasks/current` returns enough data to restore UI.
- [x] Ensure `/v1/tasks/:id/logs` supports tail retrieval.
- [x] Ensure stop request maps to actual process/task cancellation.
- [x] Add NDJSON event types: status, stdout, stderr, progress, warning, error, exit.
- [x] Document max log size, redaction, and truncation behavior.

## Acceptance Criteria

- App restart can recover visible task state from Helper.
- Stop does not only change Flutter UI state; it reaches the provider.
- Logs are redacted and bounded.
- Protocol describes what happens if a stream reconnects after completion.

## Completion Notes

- Protocol doc now defines task lifecycle states (`queued -> running -> succeeded/failed/cancelled/timedOut/lost`), NDJSON event types (`status`, `stdout`, `stderr`, `progress`, `warning`, `error`, `exit`), log limits (200 lines/task, 50 tasks max), truncation behavior (FIFO silent eviction), task ID stability, stream reconnect behavior (not resumable; poll + logs retrieval), and helper/client redaction policy.
- Android service stream exit event now includes `failureKind` for consistency with non-streaming endpoint.
- Python daemon stream exit event now includes `failureKind` for consistency with the Android service and non-streaming endpoint.
- Both Python daemon and Android service implement task persistence with `lost`/`runtimeLost` recovery on restart, task cancellation by ID, secret-pattern log redaction, log line truncation, and log tail via `?limit=N`.
- Stream reconnect is documented as not resumable — client must poll and retrieve logs post-hoc. This is an intentional simplicity choice; HTTP range/byte-offset cursors are out of scope.

## Validation

```powershell
Select-String -Path .\docs\mobilecode-helper-runtime-protocol.md -Pattern "NDJSON|/v1/tasks/current|/v1/tasks/:id/logs|stop"
Select-String -Path .\mobile_agent\tooling\mobilecode_helper_daemon.py -Pattern "tasks|stop|logs|token"
```

## Handoff Prompt

请实现 T08。重点是协议和任务生命周期清晰，不要扩大命令 allowlist。无法本地跑 Helper 时，请写明未运行原因，并依赖后续 CI 或手动 QA。
