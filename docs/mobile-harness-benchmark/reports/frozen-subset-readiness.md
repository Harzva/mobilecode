# Frozen Subset Readiness

Generated at: `2026-06-06T12:53:58+00:00`
Manifest: `docs/mobile-harness-benchmark/tasks/frozen-v2-paper-subset.json`
Status: `draft_frozen_candidate`

## Evidence Boundary

This manifest fixes candidate tasks and T0 evidence. It is not final experimental evidence; no entry counts as a paper result until its required_next_tier evidence is attached.

## Counts

- Tasks: 60
- T0 results: {'blocked': 10, 'passed': 50}
- Required next tiers: {'T2-android-real-device': 15, 'T2-or-T3-mobile-tier': 30, 'T3-ios-simulator': 5, 'T5-github-sandbox': 10}
- Categories: {'code_edit': 10, 'file_intake': 10, 'github_delivery': 10, 'harness_evidence': 10, 'preview_verification': 10, 'runtime_orchestration': 10}

## Readiness

- Android: `blocked` (adb_missing)
- iOS: `blocked` (xcrun_missing)

## Known Limits

- The manifest is frozen for planning only; it is not a final paper subset.
- T0 fixture results do not replace Android/iOS mobile-tier evidence.
- GitHub delivery entries require an authorized public sandbox run.
