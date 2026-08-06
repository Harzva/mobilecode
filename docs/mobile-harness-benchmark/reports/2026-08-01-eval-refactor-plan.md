# Phone Use Eval Execution Plan

## Goal

Create a repeatable Phone Use evaluation loop that improves release confidence
without presenting emulator or protocol evidence as physical-device results.

## Phase 1 — Minimum Useful Eval Harness

- [x] Define the Phone Use quality, safety, metric, and artifact contract.
- [x] Freeze 30 controlled cases across five categories.
- [x] Require three repetitions before a task can become counted evidence.
- [x] Add one validation command and stable JSON/Markdown readiness reports.
- [x] Add the contract validator to Mobile Runtime CI.
- [x] Make the Android QA lane record emulator versus physical-device kind.

## Phase 2 — Regression Confidence

- [ ] Execute a real model/tool callback pilot over one task per category.
- [ ] Execute all T1 tasks three times under a locked model, prompt, APK, AVD,
  and verifier version.
- [ ] Add an official AndroidWorld adapter and preserve official evaluator output.
- [ ] Add ScreenSpot grounding and BFCL typed-tool baselines.
- [ ] Record observed failures against the frozen terminal taxonomy.

## Phase 3 — Release-Grade Validation

- [ ] Capture at least one Android T2 physical-device run with reviewed evidence.
- [ ] Capture iOS T3 simulator and T4 physical-device lifecycle evidence.
- [ ] Run locked chat-only, desktop remote IDE, and MobileCode harness baselines.
- [ ] Add confidence intervals and ablations for semantic refs, ActionEvidence,
  approvals, recovery, and runtime routing.
- [ ] Promote results only after the submission-readiness and privacy gates pass.

## Risks

- Small controlled tasks can overestimate performance on changing third-party apps.
- A single emulator run can hide model nondeterminism and device fragmentation.
- Environment errors can inflate success if excluded without a fixed policy.
- Screenshots and logs can leak account or credential content.
- Safety blocks can be misreported as task failures instead of policy successes.

## Done Definition

A maintainer can run the contract validator, targeted tests, APK build, and
Android device QA; inspect typed failures and public-safe evidence; and decide
whether a change is safe without claiming unavailable physical-device results.
