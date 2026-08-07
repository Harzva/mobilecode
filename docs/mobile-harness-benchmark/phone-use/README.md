# MobileHarnessBench Phone Use v1

This track evaluates controlled Android Phone Use behavior without claiming a
large real-app device farm. It complements the coding-harness categories; it
does not replace MobileHarnessBench or turn its existing T0 fixtures into
mobile results.

## Scope

`controlled-task-set-v1.json` freezes 30 tasks across five categories, with six
tasks per category:

- system navigation;
- information retrieval;
- controlled form entry;
- interruption recovery;
- transaction safety.

Every counted task requires three repetitions. The frozen terminal outcomes
are `verified_success`, `partial_progress`, `agent_failure`,
`environment_error`, `user_takeover`, and `safety_block`.

The task set deliberately uses system surfaces and local deterministic
fixtures. It never submits a real order, payment, message, booking, or account
change. The physical-device task is a promotion boundary only and remains
non-counted until T2 evidence exists.

## Required Evidence

Each task result must include device metadata, before/after semantic snapshot
summaries, ActionEvidence, verifier output, and a redaction report. Sensitive
login tasks may record a `secret_id` slot name, but never the resolved value.

Screenshots, video, UI trees, logs, and reports must be excluded for any surface
where a credential value could be visible. A missing artifact is not a zero; it
is an incomplete, non-promotable result.

## Validate

```bash
python3 scripts/validate_mobile_harness_phone_use_v1.py
```

Refresh the public-safe readiness report after changing the task contract:

```bash
python3 scripts/validate_mobile_harness_phone_use_v1.py --write-report
```

## Promotion Rule

The manifest and readiness report use `counts_as_experiment=false`. T1 becomes
a counted emulator experiment only after real agent callbacks execute all
selected repetitions under a locked model, prompt, app build, device image,
and verifier version. T2 physical-device claims additionally require device
metadata and reviewed evidence. Public benchmark comparisons must use the
official task set and evaluator; curated subsets are labelled as subsets.

## Latest Device QA

The 2026-08-01 Android 16 emulator run built, installed, and launched the release
APK and reached the Accessibility `ready` state. Its deterministic Phone Use
device-QA outcome is `verified_success`: all 6 actions and final text state were
verified. It remains non-counted. See the [public-safe QA report](../reports/2026-08-01-android-emulator-qa.md).
