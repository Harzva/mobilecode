# Mobile Evidence Capture Pack

Generated at: `2026-06-06T15:06:41Z`

This pack prepares Android T2 and iOS T3 evidence collection. It is not a benchmark run.

- Status: `capture_ready_no_results`
- Counts as experiment: `false`
- Counts as mobile experiment: `false`

A task can be promoted only after the run files, task evidence template, device metadata, verifier outputs, screenshots/logs and public-output safety scan are complete.

## Task Sets

| Task set | Tier | Tasks | Requires real device |
| --- | --- | ---: | ---: |
| `android-device-v2` | `T2-android-real-device` | 30 | 30 |
| `ios-simulator-v2` | `T3-ios-simulator` | 18 | 0 |

## Files

- `manifest.json`: pack-level status and open requirements.
- `mobile-evidence-checklist.csv`: task-level evidence checklist.
- `execution-playbook.md`: operator execution order and promotion boundary.
- `<task-set>/device-metadata-template.json`: platform metadata template.
- `<task-set>/run-manifest-template.json`: run-level evidence template.
- `<task-set>/tasks/<task-id>/evidence-template.json`: task-level evidence template.
