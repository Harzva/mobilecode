# Baseline Protocol Readiness

Generated at: `2026-06-06T12:53:58Z`
Status: `protocol_defined_no_results`

## Evidence Boundary

This report defines the comparison protocol only. It contains no baseline result and must not be used as a performance table until run artifacts exist for all baselines.

## Planned Baselines

| Baseline | Unit under test | Expected limit |
| --- | --- | --- |
| chat_only_mobile_coding_flow | A mobile chat assistant without a harness evidence layer. | May produce plausible artifacts but lacks structured harness traces and verifier outputs. |
| desktop_remote_ide_flow | A conventional desktop or remote IDE workflow used from outside the phone. | Strong execution access, but not a phone-native control-plane baseline. |
| mobile_harness_flow | The proposed phone-native harness control loop. | Cannot count as final mobile evidence until T2/T3/T5 artifacts are attached. |

## Metrics

- task_success
- verified_success
- trace_completeness
- recovery_rate
- artifact_availability
- human_intervention_count
- steps_to_completion

## Fairness Controls

- Use the same frozen task subset for every baseline.
- Use the same input fixtures and task prompts.
- Record the exact model provider and model version for every run.
- Use the same authorization state for GitHub-delivery tasks; unavailable authorization is typed as blocked.
- Apply the same time budget and human-intervention logging.
- Do not compare T0 fixture evidence against T2/T3/T5 mobile-device evidence as if they were the same tier.

## Blocked Conditions

- No Android T2 run evidence is attached yet.
- No iOS T3/T4 run evidence is attached yet.
- No authorized GitHub T5 sandbox run evidence is attached yet.
- No model/provider lock file has been recorded for baseline runs yet.
- No human-intervention annotation sheet has been completed yet.
