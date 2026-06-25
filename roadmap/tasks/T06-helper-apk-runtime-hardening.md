# T06 Helper APK Runtime Hardening

Status: [x] Completed
Priority: P1
Owner role: software-dev-pipeline + quality-reviewer
Depends on: T02, T04

## Objective

把 MobileCode Helper APK 从“可连接的运行时原型”推进到可恢复、可诊断、可发布的手机本地 runtime provider。

## Read First

- `docs/mobilecode-helper-runtime-protocol.md`
- `docs/mobilecode-version-policy.md`
- `docs/mobilecode-v1-runtime-release-closure.md`
- `mobile_agent/lib/services/runtime_provider.dart`
- `mobile_agent/lib/services/runtime_manager.dart`
- `mobile_agent/lib/services/mobile_code_helper_provider.dart`
- `mobile_agent/tooling/mobilecode_helper_daemon.py`

## Can Edit

- `docs/mobilecode-helper-runtime-protocol.md`
- `docs/mobilecode-version-policy.md`
- `mobile_agent/lib/services/mobile_code_helper_provider.dart`
- `mobile_agent/lib/services/runtime_provider.dart`
- Android Helper files only after locating current helper package
- `roadmp.md`
- this task file

## Do Not Edit

- GitRuntime implementation, unless only adding TODO links.
- Release workflows.
- Any local build output.

## Scope

- Health endpoint parity。
- Token requirement。
- Foreground service lifecycle。
- Runtime capability reporting。
- Error model alignment。
- Task status recovery。

## Out of Scope

- Real Git commit/push。
- Private clone。
- Full Termux integration。
- Cloud runtime。

## Implementation Tasks

- [x] Confirm Android Helper package location and current endpoints.
- [x] Align Helper APK endpoints with `/v1/health`, `/v1/execute`, `/v1/execute/stream`, `/v1/tasks/current`, `/v1/tasks`, `/v1/tasks/:id/logs`, `/v1/tasks/:id/stop`.
- [x] Add explicit capability flags in health response.
- [x] Require app-generated token by default.
- [x] Return structured failure kinds matching `RuntimeTaskFailureKind`.
- [x] Document foreground service requirements and user-visible states.
- [x] Update QA docs with Helper APK install/start/reconnect scenarios.

## Acceptance Criteria

- App can distinguish Helper unavailable, auth failure, unsupported command and task failure.
- Helper health tells the app what is ready, preview, beta or unavailable.
- Restarting the app does not lose current task state if Helper is still alive.
- No local build is required for this task acceptance; code review and CI evidence are enough.

## Completion Notes

- `MobileCodeHelperAuth.token` generates a process-local token in Flutter, `MobileCodeHelperProvider` sends it by default, and `home_screen.dart` passes it to `startHelperService`.
- `MobileCodeHelperService.kt` accepts the token via `EXTRA_AUTH_TOKEN`, validates `X-MobileCode-Token` / `Authorization: Bearer` on every request, returns HTTP 401 with `failureKind: authFailed` when invalid, and reports `authRequired` dynamically.
- `MainActivity.kt` `startHelperService(authToken)` passes the token to the service via Intent extra.
- 2026-06-25 follow-up: the service is now registered in `mobile_agent/android/app/src/main/AndroidManifest.xml` and copied into `mobile_agent/android/app/src/main/kotlin/com/mobilecode/app/MobileCodeHelperService.kt`, so `mobilecode/system_tools.startHelperService` targets a real Android foreground service rather than returning `false`.
- 2026-06-25 follow-up: if Android restarts the service without the app-provided token, `MobileCodeHelperService` generates a temporary token instead of exposing an unauthenticated localhost helper.
- 2026-06-25 follow-up: `MobileCodeHelperLauncherActivity` is now present in the Android app manifest and source tree for shell-only CI/ADB smoke tests; `.github/workflows/android-app-test.yml` starts it with a CI token and probes Helper endpoints using `X-MobileCode-Token`.
- 2026-06-25 follow-up: release/profile network security remains HTTPS-first while allowing cleartext only for `localhost` / `127.0.0.1`, which is required for app-local Helper and Termux daemon health/execute calls without opening LAN cleartext.
- Protocol doc updated to document Android token enforcement behavior, debug-only no-token mode, and runtime maturity gates.
- Stream exit event now includes `failureKind` for consistency with non-streaming endpoint.
- Helper logs and command output are bounded and pass through common secret redaction before storage/streaming/response.
- `roadmp.md` T06 is checked since the core infrastructure (protocol, service, token, validation) is complete.

## Validation

Use source checks and CI. Do not compile locally.

```powershell
Select-String -Path .\mobile_agent\lib\services\*.dart -Pattern "RuntimeTaskFailureKind|RuntimeProviderType|health"
Select-String -Path .\docs\mobilecode-helper-runtime-protocol.md -Pattern "/v1/health|/v1/tasks|token"
```

## Handoff Prompt

请实现 T06。先找出现有 Android Helper 代码，再对齐协议和错误模型。不要碰 Git 写入能力，不要本地构建。完成后更新 QA 文档和 checkbox。
