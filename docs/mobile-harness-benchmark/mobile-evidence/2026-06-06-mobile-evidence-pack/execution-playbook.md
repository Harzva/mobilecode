# Mobile Evidence Execution Playbook

This playbook turns the capture templates into a deterministic operator flow.
It is not a benchmark result and does not count as a mobile experiment.

## Promotion Rule

A task remains `template_not_run` until all required run files, task evidence, device metadata, verifier outputs, screenshots or recordings, logs when available, and public-output safety scans are attached.
Only then can a separate reviewed result promote it toward paper-counted mobile evidence.

## Execution Order

| Step | Android T2 real device | iOS T3 simulator | Required output | Counts as result |
| --- | --- | --- | --- | --- |
| 1 | Select `android-device-v2` task set | Select `ios-simulator-v2` task set | task-set manifest id | false |
| 2 | Fill device metadata from real phone | Fill simulator metadata from Mac/Xcode | `device-metadata.json` | false |
| 3 | Install or launch the current app build | Install or launch the current simulator app build | app build metadata | false |
| 4 | Execute each task through the app harness | Execute each task through the app harness | `run.json`, `summary.md`, `traces.jsonl` | false until verifier review |
| 5 | Capture screenshots or screen recording | Capture simulator screenshots | `screenshots/` or `recordings/` | false |
| 6 | Capture platform logs when available | Capture Xcode/simulator logs when available | `logs/` | false |
| 7 | Attach verifier outputs and artifacts | Attach verifier outputs and artifacts | verifier/artifact paths | false |
| 8 | Run public-output safety scan | Run public-output safety scan | safety scan status | false |
| 9 | Review promotion checklist | Review promotion checklist | completed task evidence template | promotion candidate only |

## Task Sets

| Task set | Tier | Tasks | Requires real device | Template dir |
| --- | --- | ---: | ---: | --- |
| `android-device-v2` | `T2-android-real-device` | 30 | 30 | `docs/mobile-harness-benchmark/mobile-evidence/2026-06-06-mobile-evidence-pack/android-device-v2` |
| `ios-simulator-v2` | `T3-ios-simulator` | 18 | 0 | `docs/mobile-harness-benchmark/mobile-evidence/2026-06-06-mobile-evidence-pack/ios-simulator-v2` |

## Non-Result Boundary

- This playbook is a collection protocol, not a completed run.
- It must not be cited as Android/iOS performance evidence.
- It must be regenerated when task sets, required evidence, or verifier promotion rules change.
