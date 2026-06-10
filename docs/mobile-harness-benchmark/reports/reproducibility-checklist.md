# Reproducibility Checklist

Generated at: `2026-06-09T12:15:10Z`
Status: `passed_with_open_requirements`
Draft reproduction ready: `true`
Full empirical reproduction ready: `false`

## Evidence Boundary

The checklist makes the current draft package reproducible as a T0/system-and-benchmark artifact. It does not claim full empirical reproduction because real mobile-tier, GitHub sandbox and counted baseline results remain open.

## Commands

| Step | Status | Boundary |
| --- | --- | --- |
| `python scripts/generate_mobile_harness_task_bank.py` | `ready` | Regenerates candidate task supply; does not count tasks as completed experiments. |
| `python scripts/audit_mobile_harness_task_bank.py` | `ready` | Checks structure, coverage, uniqueness and public-output safety; does not replace human review. |
| `python scripts/run_mobile_harness_bench.py --task-set smoke-v2 --run-id 2026-06-06-smoke-v2-t0` | `ready` | Counts as T0 fixture evidence only; does not count as Android/iOS mobile-tier evidence. |
| `python scripts/collect_mobile_harness_mobile_tier_evidence.py` | `ready` | Records local Android/iOS tooling availability; does not count as a mobile experiment. |
| `python scripts/generate_mobile_harness_mobile_evidence_pack.py` | `ready` | Creates T2/T3 capture templates; does not count as mobile experiment results. |
| `python scripts/generate_mobile_harness_verifier_contract_readiness.py` | `ready` | Checks machine-readable verifier contracts against all current task-bank verifier references. |
| `python scripts/generate_mobile_harness_baseline_protocol.py && python scripts/generate_mobile_harness_baseline_pilot_readiness.py` | `ready` | Defines baseline comparison protocol and pilot readiness; no baseline performance result is claimed. |
| `python scripts/generate_mobile_harness_claim_ledger.py && python scripts/generate_mobile_harness_core_claim_readiness.py` | `ready` | Maps paper-facing claims to evidence and positioning boundaries. |
| `python scripts/generate_mobile_harness_evidence_maturity_matrix.py && python scripts/generate_mobile_harness_evaluation_protocol_readiness.py` | `ready` | Separates T0 evidence from open mobile, GitHub sandbox and baseline requirements. |
| `python scripts/generate_mobile_harness_bibliography_readiness.py && python scripts/generate_mobile_harness_threats_to_validity.py` | `ready` | Checks current citation metadata and review-risk boundaries. |
| `python scripts/generate_mobile_harness_method_presentation_readiness.py` | `ready` | Checks that the paper has reviewable visuals, algorithms, module interfaces, formulas and evidence boundaries. |
| `latexmk -pdf -interaction=nonstopmode -halt-on-error main.tex` | `ready` | Compiles the anonymous paper draft; local TeX availability is required. |
| `python scripts/generate_mobile_harness_page_limit_readiness.py` | `ready` | Checks current compiled PDF page boundary and records where references begin. |
| `python scripts/generate_mobile_harness_submission_readiness.py` | `ready` | Checks draft upload gates while keeping upload readiness false. |
| `python scripts/prepare_mobile_harness_supplement.py` | `ready` | Builds a locally anonymized reviewer package and scans it for identity/path/token markers. |
| `python scripts/validate_mobile_harness_bench.py` | `ready` | Validates task banks, task sets, runs, reports, and evidence-boundary invariants. |

## Open Requirements

- `real_android_or_ios_mobile_tier_evidence`
- `authorized_github_sandbox_delivery_evidence`
- `counted_baseline_comparison_results`
- `final_anonymous_supplement_after_new_evidence`
