# MobileHarnessBench v2 Quality Audit

Audit date: 2026-06-06
Source: `docs/mobile-harness-benchmark/tasks/v2-task-bank.json`
Status: `passed_with_limits`

## Evidence Boundary

This is a deterministic machine audit for structure, coverage, uniqueness and public-output safety.
It does not claim that the 1,000 candidate tasks have been executed as experiments.
Only tasks with verifier result, trace, summary and the required mobile-tier evidence should be counted in paper tables.

## Machine Gates

| Gate | Status | Evidence |
| --- | --- | --- |
| v2 task count | passed | 1000 tasks |
| unique task ids | passed | 1000/1000 unique |
| unique titles | passed | 1000/1000 unique |
| unique user goals | passed | 1000/1000 unique |
| six-category coverage | passed | code_edit=167, file_intake=167, github_delivery=167, preview_verification=167, harness_evidence=166, runtime_orchestration=166 |
| category balance | passed | code_edit=167, file_intake=167, github_delivery=167, preview_verification=167, harness_evidence=166, runtime_orchestration=166 |
| quality-axis coverage | passed | failure_recovery=252, happy_path=252, public_report_safety=250, mobile_constraint=246 |
| mobile-profile coverage | passed | android_emulator_file_picker=168, android_real_phone_share=168, ios_real_open_in=168, ios_simulator_document=168, android_low_memory=166, webview_only_preview=162 |
| mandatory quality fields | passed | missing=0 |
| test oracle coverage | passed | missing=0 |
| mobile evidence requirements | passed | missing=0 |
| public-output safety marker scan | passed | findings=0 |
| smoke-v2 manifest coverage | passed | count=60, categories={'code_edit': 10, 'file_intake': 10, 'github_delivery': 10, 'harness_evidence': 10, 'preview_verification': 10, 'runtime_orchestration': 10} |
| android-device-v2 manifest coverage | passed | count=30, categories={'code_edit': 5, 'file_intake': 5, 'github_delivery': 5, 'harness_evidence': 5, 'preview_verification': 5, 'runtime_orchestration': 5} |
| ios-simulator-v2 manifest coverage | passed | count=18, categories={'code_edit': 3, 'file_intake': 3, 'github_delivery': 3, 'harness_evidence': 3, 'preview_verification': 3, 'runtime_orchestration': 3} |

## Coverage Snapshot

| Dimension | Unique values | Distribution |
| --- | ---: | --- |
| Category | 6 | code_edit=167, file_intake=167, github_delivery=167, preview_verification=167, harness_evidence=166, runtime_orchestration=166 |
| Quality axis | 4 | failure_recovery=252, happy_path=252, public_report_safety=250, mobile_constraint=246 |
| Mobile profile | 6 | android_emulator_file_picker=168, android_real_phone_share=168, ios_real_open_in=168, ios_simulator_document=168, android_low_memory=166, webview_only_preview=162 |
| OS target | 5 | android_real_device=334, android_emulator=168, ios_real_device=168, ios_simulator=168, android_or_ios=162 |
| Fixture kind | 9 | html=167, repo_task=167, runtime_task=166, trace_task=166, markdown=127, json=80, prompt=80, unknown_text=40, binary=7 |
| Requires real device | 2 | True=502, False=498 |

## Task-Set Manifests

| Task set | Count | Categories | Path |
| --- | ---: | --- | --- |
| smoke-v2 | 60 | code_edit=10, file_intake=10, github_delivery=10, harness_evidence=10, preview_verification=10, runtime_orchestration=10 | `docs/mobile-harness-benchmark/tasks/smoke-v2.json` |
| android-device-v2 | 30 | code_edit=5, file_intake=5, github_delivery=5, harness_evidence=5, preview_verification=5, runtime_orchestration=5 | `docs/mobile-harness-benchmark/tasks/android-device-v2.json` |
| ios-simulator-v2 | 18 | code_edit=3, file_intake=3, github_delivery=3, harness_evidence=3, preview_verification=3, runtime_orchestration=3 | `docs/mobile-harness-benchmark/tasks/ios-simulator-v2.json` |

## Known Limits

- This audit checks machine-readable structure and coverage, not semantic novelty.
- The 1,000 tasks remain a candidate bank until a frozen subset has verifier results.
- The audit does not provide Android real-device, iOS simulator, or baseline-comparison evidence.
- Human review is still required for task realism, ambiguity, and paper relevance.
