# Paper Claim Evidence Ledger

Generated at: `2026-06-09T07:03:46Z`
Status: `passed_with_open_requirements`

## Evidence Boundary

T0 offline fixture results and draft planning manifests are separated from final mobile-tier experiments. Real Android/iOS/GitHub sandbox results remain unclaimed until their run artifacts exist.

## Claims

| Claim | Status | Paper evidence | Mobile experiment | Evidence boundary |
| --- | --- | --- | --- | --- |
| v2_candidate_bank | supported_non_experimental | false | false | Candidate tasks are task supply, not completed experiments. |
| representative_v0_t0_run | supported_t0_only | true | false | T0 fixture evidence validates verifier machinery but not phone-device behavior. |
| smoke_v2_t0_run | supported_t0_only | true | false | T0 fixture evidence is not Android/iOS mobile-tier evidence. |
| draft_frozen_paper_subset | supported_planning_only | false | false | Each task remains non-final until its required T2/T3/T5 evidence is attached. |
| mobile_tier_readiness | supported_blocked_non_experimental | false | false | This is a readiness probe, not a mobile experiment. |
| real_mobile_and_baseline_results | open_requirement | false | false | The baseline protocol, run contract, one-task T0 dry run, pilot prompt/evidence pack and readiness gate are defined, but no final performance table should report baseline completion until counted run evidence is present. |

## Open Requirements

- real_mobile_and_baseline_results
