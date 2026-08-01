# 5-Factor Eval Audit: MobileCode

## Project

- Name: MobileCode / MobileHarnessBench
- Version or commit: `2aed3f252dcec175f5f61e3356ec21a69d964066` plus the 2026-08-01 Phone Use v1 working change
- Primary Skill paired with this eval review: Android release emulator QA
- Reviewer: Codex
- Date: 2026-08-01

## Evaluation Scope

The selected scope is the smallest repeatable evaluation loop needed before
claiming reliable Phone Use: controlled navigation, information retrieval,
form entry, interruption recovery, and transaction-safety boundaries. It also
keeps the existing coding-harness task bank, verifier contracts, and evidence
tiers intact.

## Scorecard

| Factor | Score | Evidence | Gap |
| --- | ---: | --- | --- |
| Quality Contract | 4 | MobileHarnessBench rubric plus the Phone Use v1 task, artifact, metric, and terminal-outcome contracts | Counted thresholds still require real run distributions |
| Golden Cases | 4 | 25 seeds, 60-task smoke subset, 30 controlled Phone Use tasks, and deterministic fixtures | Real third-party-app cases remain intentionally small and controlled |
| Regression Loop | 4 | Local validators, Flutter tests, Android emulator workflow, and a new Phone Use contract CI job | No scheduled physical-device regression lane is available |
| Failure Taxonomy | 4 | Typed blocked states plus `verified_success`, `partial_progress`, `agent_failure`, `environment_error`, `user_takeover`, and `safety_block` | Cross-benchmark mapping still needs observed failure examples |
| Release Gates | 3 | Submission-readiness gates, evidence promotion rules, CI validation, and public-safe report boundaries | A release can pass CI without counted T2/T4 or baseline evidence |

Total score: `19/25` — Repeatable

## Critical Findings

1. The project has a mature protocol surface, but protocol readiness must remain
   separate from counted model/device performance.
2. The existing P6.3 script called its lane "real device" even when it ran on an
   emulator. Device-kind detection and explicit terminal outcomes are required
   to prevent evidence relabelling.
3. Transaction and credential cases need negative oracles: stopping safely,
   rejecting stale approvals, and leaking no secrets are successful outcomes.

## Existing Validation Assets

- Tests: Flutter service/widget tests, Python validators, Android emulator CI.
- Examples: representative v0, smoke-v2, strategy pilots, P6.3 Android evidence.
- Fixtures: file, code, preview, GitHub, evidence, and runtime fixtures.
- CI checks: Mobile Runtime CI, Android App Smoke Test, APK build workflows.
- Logs or reports: run JSON, traces, screenshots, UI XML, logcat, readiness reports.

## Missing Golden Cases

| Case | Why it matters | Expected behavior | Priority |
| --- | --- | --- | --- |
| Physical-device background restriction | Emulator lifecycle behavior is incomplete | `background_restricted -> recovering -> ready` with evidence | P0 |
| Real model callbacks over all selected tasks | Static and deterministic probes do not measure agent quality | Three repetitions with locked model/prompt/build/verifier | P0 |
| Official AndroidWorld adapter | Internal tasks alone are not an external comparison | Official setup, tasks, evaluator, and subset/full label | P0 |
| Real order-review boundary | Controlled fixture does not cover third-party UI drift | Stop before submit, request approval, redact evidence | P1 |
| iOS real-device lifecycle | Simulator cannot prove Files/Open In/background behavior | T4 device evidence with typed interruptions | P1 |

## Failure Taxonomy

| Failure mode | Example | Likely cause | Fix path |
| --- | --- | --- | --- |
| `agent_failure` | Repeated action does not change the page | Misread semantics or ineffective recovery | Re-observe, invalidate refs, revise plan |
| `environment_error` | App unavailable, expired session, device disconnected | External environment or infrastructure | Exclude from success denominator only under declared policy |
| `partial_progress` | Target page reached but verifier goal incomplete | Step budget or unresolved state | Preserve progress score and final state evidence |
| `user_takeover` | CAPTCHA or account confirmation requires a person | Non-automatable or policy-gated step | Hand off and resume from a new snapshot |
| `safety_block` | Dry-run reaches order confirmation | Correct policy enforcement | Count as safety success, not task completion |
| stale reference | `@e` belongs to the previous generation | Page transition invalidated the snapshot | Reject before dispatch; never fall back to old coordinates |

## Validation Results

- `python3 scripts/validate_mobile_harness_phone_use_v1.py`: passed for 30 tasks, five balanced categories, three required repetitions, and a non-counted boundary.
- `python3 scripts/validate_mobile_harness_bench.py`: passed for 1,225 current task definitions and existing reports.
- `flutter test` Phone Use service/widget subset: 23 tests passed.
- Android `pure` release build, install, and launch: passed on an Android 16 / API 36 emulator.
- P6.3 deterministic Phone Use device QA: `verified_success` at 6/6 accepted actions with final text state verified. This remains non-counted; see [Android emulator QA](2026-08-01-android-emulator-qa.md).

## Recommendation

Use one release command chain: validate the benchmark contracts, run targeted
Flutter tests, build the APK, run Android emulator evidence, scan public
artifacts, and only then push. Promote no mobile result until real callbacks,
repetitions, required artifacts, and device-tier rules all pass.
