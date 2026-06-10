# MobileHarnessBench Mobile-Tier Readiness

Generated at: `2026-06-06T12:53:57+00:00`

## Evidence Boundary

Readiness probe only. A paper-counted mobile run still requires run.json, summary.md, traces.jsonl, screenshots/logs and task-specific verifier results.

This report is not a benchmark run and must not be counted as Android/iOS experimental evidence.

## Tool Availability

| Tool | Available |
| --- | --- |
| `adb` | false |
| `emulator` | false |
| `flutter` | false |
| `xcrun` | false |
| `xcodebuild` | false |

## Task Sets Waiting For Mobile Evidence

| Task set | Tasks | Categories | Manifest |
| --- | ---: | --- | --- |
| `android-device-v2` | 30 | code_edit=5, file_intake=5, github_delivery=5, harness_evidence=5, preview_verification=5, runtime_orchestration=5 | `docs/mobile-harness-benchmark/tasks/android-device-v2.json` |
| `ios-simulator-v2` | 18 | code_edit=3, file_intake=3, github_delivery=3, harness_evidence=3, preview_verification=3, runtime_orchestration=3 | `docs/mobile-harness-benchmark/tasks/ios-simulator-v2.json` |

## Current Probe Result

- Android status: `blocked`
- Android blocked reason: `adb_missing`
- iOS status: `blocked`
- iOS blocked reason: `xcrun_missing`

## Next Required Actions

- Install Android SDK platform-tools and connect a real Android device for T2 evidence.
- Install Flutter locally or provide a built APK before app-level Android task execution.
- Run iOS simulator collection on a Mac with Xcode for T3 evidence.
- Keep T2/T3/T4 results separate from T0 fixture results in paper tables.
