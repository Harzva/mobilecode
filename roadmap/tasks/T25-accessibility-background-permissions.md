# T25 Accessibility 与后台权限产品化

Status: [ ] Implemented in code; local Mac build/smoke passed; pending remote emulator and real-device QA evidence
Priority: P1
Owner role: software-dev-pipeline + mobilecode-mac-local-qa + quality-reviewer
Depends on: T06, T13, T20

## Objective

把现有 `PhoneUseAccessibilityService`、`mobilecode/system_tools` MethodChannel 和 phone-use probe 产品化到设置页，让用户能看见、理解并开启无障碍服务与后台运行权限。

## Read First

- `roadmp.md`
- `roadmap/tasks/T06-helper-apk-runtime-hardening.md`
- `roadmap/tasks/T13-evidence-model.md`
- `mobile_agent/lib/screens/settings_screen.dart`
- `mobile_agent/lib/services/phone_use_accessibility_service.dart`
- `mobile_agent/lib/widgets/phone_use_mode_card.dart`
- `mobile_agent/android/app/src/main/kotlin/com/mobilecode/app/MainActivity.kt`
- `mobile_agent/android/app/src/main/AndroidManifest.xml`
- `docs/mobilecode-accessibility-background-permissions-qa.md`

## Can Edit

- `mobile_agent/lib/screens/settings_screen.dart`
- `mobile_agent/lib/services/phone_use_accessibility_service.dart`
- `mobile_agent/lib/widgets/phone_use_mode_card.dart`
- new settings/detail screens for permission guidance
- Android `MainActivity.kt` only for missing safe settings intents
- Android manifest/xml only if existing metadata needs wording or status alignment
- `mobile_agent/test/services/phone_use_accessibility_service_test.dart`
- widget tests for settings permission rows
- QA templates under `docs/` or `qa/`
- `roadmp.md`
- this task file

## Do Not Edit

- Do not add a second AccessibilityService.
- Do not bypass `PhoneUseAccessibilityService` or `mobilecode/system_tools`.
- Do not auto-grant or silently attempt restricted Android permissions.
- Do not mark phone-use traces as counted benchmark evidence.
- Do not store raw UI text, screenshots with secrets, credential dumps, or local private paths.

## Scope

- Add Settings entries for `无障碍服务` and `后台运行权限`.
- Show status states: `未开启`, `已开启`, `service connected`, and `blocked reason`.
- Open Android Accessibility settings via the existing `ACTION_ACCESSIBILITY_SETTINGS` bridge.
- Add a background permission guide that can open app details or battery optimization settings when supported.
- Keep phone-use evidence boundaries visible: `countsAsExperiment=false`, `countsAsStrategyAblationResult=false`, `rawTextIncluded=false`.

## Out of Scope

- Full automated phone-use execution beyond the existing explicit probe/action model.
- Real benchmark promotion.
- OEM-specific automatic permission toggles.
- New cloud runtime or Helper APK protocol changes.

## Implementation Tasks

### Phase 1: Settings Entry and Status

- [x] Add a `系统权限` section in Settings with `无障碍服务` and `后台运行权限`.
- [x] Reuse `PhoneUseAccessibilityService.getStatus()` for status display.
- [x] Surface `serviceId`, `serviceConnected`, `ready`, and `blockedReason` in user-readable copy.
- [x] Provide an app action that opens Android Accessibility settings.
- [x] Keep all actions user-initiated and reversible.

### Phase 2: Background Permission Guidance

- [x] Add a background permission detail page or bottom sheet.
- [x] Explain foreground/background runtime purpose without claiming guaranteed OEM behavior.
- [x] Add Android app details or battery optimization settings intent where safe.
- [x] Add fallback copy when the platform channel or settings intent is unavailable.
- [x] Record QA evidence requirements for Android emulator and real-device checks.

### Pending Verification

- [x] Run local Mac targeted `flutter analyze` for the T25/workflow entry surfaces.
- [x] Run local Mac focused Flutter tests:
  - `flutter test test/services/phone_use_accessibility_service_test.dart`
  - `flutter test test/widgets/settings_screen_permissions_test.dart`
- [x] Build local Mac Android debug APK:
  - `flutter build apk --debug --target lib/main.dart`
- [x] Run local Mac Android emulator smoke for install, Helper launcher, Helper health/execute, MainActivity launch, screenshot, and logcat capture.
- [ ] Resolve or quarantine pre-existing repo-wide `flutter analyze` failures before using full-repo analyze as the release gate.
- [ ] Keep GitHub Actions as remote CI/release-side verification.
- [ ] Android emulator QA evidence: disabled state, Accessibility settings opened, enabled/connected state, background permission guide, battery/app settings opened, blocked fallback.
- [ ] Android real-device QA evidence using the same screenshot set when device access is available.

## Acceptance Criteria

- Settings shows `无障碍服务` and `后台运行权限`.
- Accessibility row can display disabled, enabled, service connected, and blocked states.
- Android can open Accessibility settings from the app.
- Background permission guide can open a relevant Android settings page or show a clear fallback.
- `countsAsExperiment=false` and `rawTextIncluded=false` remain unchanged in service/probe results.
- Widget/service tests cover status display, channel fallback, and settings actions.
- Android QA template includes screenshots for disabled, settings opened, enabled/connected, and blocked fallback states.

## Validation

Mac local build/test is a first-class supported path and should run before relying on GitHub Actions when the local toolchain is available:

```bash
cd mobile_agent
flutter analyze lib/main.dart lib/screens/home_screen.dart lib/screens/settings_screen.dart lib/screens/github_screen.dart lib/screens/github_repo_hub_screen.dart lib/screens/role_manager_screen.dart lib/screens/api_usage_screen.dart lib/screens/device_telemetry_screen.dart lib/services/github_deep_service.dart lib/services/github_oauth_flow.dart lib/services/role_library_service.dart lib/services/token_usage_service.dart lib/services/token_pricing_service.dart lib/services/device_telemetry_service.dart lib/services/mobile_code_helper_auth.dart lib/services/phone_use_accessibility_service.dart --no-fatal-infos --no-fatal-warnings
flutter test test/services/phone_use_accessibility_service_test.dart
flutter test test/widgets/settings_screen_permissions_test.dart
flutter build apk --debug --target lib/main.dart
```

Android QA should install the app, open Settings, tap `无障碍服务`, enable the service manually, return to MobileCode, refresh status, and save screenshots/UI XML/logcat as non-counted evidence.

QA template: `docs/mobilecode-accessibility-background-permissions-qa.md`

## Current Implementation Evidence

- `mobile_agent/lib/screens/settings_screen.dart` adds the `系统权限` section, permission state pill, accessibility status copy, and background permission bottom sheet.
- `mobile_agent/lib/services/phone_use_accessibility_service.dart` exposes `openAppSettings()` and `openBatteryOptimizationSettings()` through `mobilecode/system_tools`.
- `mobile_agent/android/app/src/main/kotlin/com/mobilecode/app/MainActivity.kt` handles `openAppSettings` and `openBatteryOptimizationSettings` with safe Android settings intents and fallback.
- `mobile_agent/test/services/phone_use_accessibility_service_test.dart` covers permission settings channel calls and non-counted fallback boundaries.
- `mobile_agent/test/widgets/settings_screen_permissions_test.dart` covers Settings permission rows, disabled state, enabled-but-service-disconnected state, status text, Accessibility settings action, and battery settings action.
- `docs/mobilecode-accessibility-background-permissions-qa.md` defines non-counted Android QA screenshot and log requirements.
- `.github/workflows/mobile-runtime-ci.yml` now includes `settings_screen.dart`, `phone_use_accessibility_service.dart`, `mobile_code_helper_auth.dart`, and the focused T25 service/widget tests in the remote analyze/test gate.
- `.github/workflows/mobile-runtime-ci.yml` also checks Android projection assets so `prepare_android_project.py`, `MobileCodeHelperService.kt`, `MobileCodeHelperLauncherActivity.kt`, and `PhoneUseAccessibilityService.kt` stay aligned with the app source used by GitHub Actions.
- `.github/workflows/android-app-test.yml` now runs on pull requests touching T25/mobile_agent paths, analyzes T25 Settings/service sources, starts `com.mobilecode.app/.MobileCodeHelperLauncherActivity` with a CI token, and checks Helper health/execute endpoints with `X-MobileCode-Token`.
- `mobile_agent/tooling/prepare_android_project.py` now projects `PhoneUseAccessibilityService.kt`, the AccessibilityService manifest entry, `mobilecode_phone_use_accessibility_service.xml`, required string resources, and the canonical `com.mobilecode.app` namespace/applicationId when GitHub Actions recreates the Android project.
- Local Mac validation on 2026-06-25 passed focused T25 tests, targeted analyzer gate, debug APK build, local emulator install, tokenized Helper launcher, Helper `/health`, Helper `/v1/execute` (`pwd`), MainActivity launch, screenshot capture, and logcat crash-keyword scan.
- Full-repo `flutter analyze` still reports pre-existing issues outside the T25 change surface, so it is tracked separately before it can become the final release gate.

Non-build checks run locally:

```bash
dart format -o none --set-exit-if-changed mobile_agent/lib/screens/home_screen.dart mobile_agent/lib/screens/settings_screen.dart mobile_agent/lib/services/mobile_code_helper_auth.dart mobile_agent/lib/services/mobile_code_helper_provider.dart mobile_agent/lib/services/phone_use_accessibility_service.dart mobile_agent/lib/services/runtime_manager.dart mobile_agent/test/services/mobile_code_helper_provider_test.dart mobile_agent/test/services/phone_use_accessibility_service_test.dart mobile_agent/test/services/runtime_manager_test.dart mobile_agent/test/widgets/settings_screen_permissions_test.dart
git diff --check
rg -n "^(<<<<<<<|=======|>>>>>>>)" .
xmllint --noout mobile_agent/android/app/src/main/AndroidManifest.xml
ruby -e 'require "yaml"; ARGV.each { |f| YAML.load_file(f) }' .github/workflows/android-app-test.yml .github/workflows/mobile-runtime-ci.yml
python3 -m py_compile mobile_agent/tooling/prepare_android_project.py
cmp -s mobile_agent/tooling/PhoneUseAccessibilityService.kt mobile_agent/android/app/src/main/kotlin/com/mobilecode/app/PhoneUseAccessibilityService.kt
```

## Handoff Prompt

请实现 T25。先复查现有 `PhoneUseAccessibilityService` 和 MethodChannel，不要新增第二套无障碍服务。把设置页入口、状态检测、系统设置跳转、后台权限引导和 QA 模板补齐。保持所有 phone-use evidence 为 non-counted，不保存 raw UI text 或敏感截图。
