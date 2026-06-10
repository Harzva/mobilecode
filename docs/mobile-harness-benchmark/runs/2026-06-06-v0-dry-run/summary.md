# MobileHarnessBench v0 Dry Run: 2026-06-06-v0-dry-run

This offline dry run verifies five representative tasks, one per benchmark category.
It uses repo fixtures only and records public-safe, repo-relative evidence.

## Summary

- Total tasks: 5
- Passed: 4
- Blocked: 1
- Failed: 0
- Warning: 0
- Categories covered: code_edit, file_intake, github_delivery, harness_evidence, preview_verification

## Results

| Task | Category | Status | Score | Evidence | Notes |
| --- | --- | --- | ---: | --- | --- |
| `MH-FI-001` | `file_intake` | `passed` | 95 | docs/mobile-harness-benchmark/runs/2026-06-06-v0-dry-run/artifacts/MH-FI-001/detected-file.json | External HTML intake and WebView-style route are verified from the fixture. |
| `MH-CE-004` | `code_edit` | `passed` | 95 | docs/mobile-harness-benchmark/runs/2026-06-06-v0-dry-run/artifacts/MH-CE-004/fixed-config.json | Invalid JSON fixture is repaired deterministically and written as a run artifact. |
| `MH-PV-001` | `preview_verification` | `passed` | 95 | docs/mobile-harness-benchmark/runs/2026-06-06-v0-dry-run/artifacts/MH-PV-001/snapshot-summary.json | Generated HTML preview has a non-empty snapshot summary and route. |
| `MH-GD-001` | `github_delivery` | `blocked` | 0 | docs/mobile-harness-benchmark/runs/2026-06-06-v0-dry-run/artifacts/MH-GD-001/github-delivery-blocked.json | GitHub delivery is intentionally marked blocked in the offline dry run; metadata and recovery path are still verified. |
| `MH-HE-001` | `harness_evidence` | `passed` | 95 | docs/mobile-harness-benchmark/runs/2026-06-06-v0-dry-run/artifacts/MH-HE-001/trace-report.json | Trace fixture has prompt, ordered actions, result and exported report artifact. |

## Interpretation

- The four local/offline tasks pass with concrete artifacts and trace events.
- `MH-GD-001` is `blocked` by design because the dry run does not perform remote GitHub writes.
- The blocked result still has a verifier result, typed failure kind and recovery suggestion.
- Public output is constrained to repo-relative paths and synthetic preview routes.
