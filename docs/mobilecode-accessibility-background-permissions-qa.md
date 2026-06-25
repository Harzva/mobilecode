# MobileCode Accessibility and Background Permissions QA

Status: template
Scope: T25 non-counted Android QA evidence

## Evidence Boundary

- Do not treat phone-use probe output as benchmark or experiment evidence.
- Keep `countsAsExperiment=false`, `countsAsStrategyAblationResult=false`, and `rawTextIncluded=false`.
- Do not save credentials, cookies, tokens, raw chat logs, private local paths, or screenshots containing secrets.
- Redact account names, notification text, repository private names, and provider usage data before sharing evidence.

## Device Matrix

- Android emulator: API level, device profile, app version, build type.
- Android real device: vendor, Android version, app version, build type.
- Record whether notification permission and battery optimization prompts were already granted before the run.

## Required Screenshots

- `01-settings-disabled`: MobileCode Settings shows `系统权限`, `无障碍服务`, and `后台运行权限`; accessibility state is disabled.
- `02-accessibility-settings-opened`: Android Accessibility settings opened from MobileCode.
- `03-settings-enabled-connected`: MobileCode Settings shows accessibility enabled and service connected after manual grant.
- `04-background-guide`: background permission bottom sheet is visible with app details and battery settings actions.
- `05-battery-settings-opened`: Android battery optimization or app details settings opened from MobileCode.
- `06-blocked-fallback`: fallback state when settings intent or service connection is unavailable.

## Manual Steps

1. Install the debug or release candidate build.
2. Open MobileCode Settings.
3. Capture the disabled permission state.
4. Tap `无障碍服务` and confirm Android opens Accessibility settings.
5. Manually enable `MobileCode PhoneUseAccessibilityService`.
6. Return to MobileCode Settings and refresh with a long press on the accessibility row.
7. Confirm status copy distinguishes enabled permission and service connection.
8. Tap `后台运行权限`.
9. Open app details and battery settings from the bottom sheet.
10. Disable or interrupt the service and confirm a blocked or fallback state is visible.

## Log Notes

- Keep log snippets short and redact private content before attaching them.
- Include only status transitions, method names, and failure kinds.
- Do not attach raw Accessibility node text or full UI hierarchy dumps unless fully sanitized.

## Pass Criteria

- Settings entries are visible and tappable.
- Accessibility settings intent opens successfully or shows clear fallback.
- Background permission guide opens app details or battery settings when supported.
- Service status covers disabled, enabled, connected, and blocked states.
- No evidence file contains secrets, raw UI text, private paths, or counted benchmark claims.
