# Anonymous Supplement Boundary

This document defines what may be included in an anonymous ICLR-style supplement for the Mobile Harness paper.

## Purpose

The supplement should let reviewers inspect task definitions, fixtures, verifier scripts and run evidence without revealing author identity, repository ownership, local file paths, private accounts, WeChat publishing artifacts or non-public credentials.

## Include

- `paper/iclr-mobile-harness/main.pdf`
- `paper/iclr-mobile-harness/main.tex`
- `paper/iclr-mobile-harness/references.bib`
- top-level `README_SUPPLEMENT.md` with quickstart commands, reviewer checklist and evidence boundaries
- ICLR style files needed to compile the anonymous paper source.
- An anonymized `docs/mobile-harness-benchmark/` package:
  - task schemas
  - baseline run schema
  - seed tasks
  - v1/v2 candidate task banks
  - task-set manifests
  - draft frozen subset manifest
  - fixture files
  - verifier contract document and machine-readable verifier contract catalog
  - runbook and rubric
  - baseline scaffold files marked `scaffold_not_run`
  - baseline T0 dry-run files marked `dry_run_not_counted`
  - baseline pilot prompt/evidence pack marked `pilot_ready_no_results`
  - baseline pilot readiness report marked `pilot_ready_no_results`
  - evidence maturity matrix
  - machine quality audit report
  - baseline protocol readiness report
  - baseline run contract report
  - paper claim-to-evidence ledger
  - core claim readiness report
  - evaluation protocol readiness report
  - verifier contract readiness report
  - bibliography readiness report
  - threats-to-validity matrix
  - page-limit readiness report
  - reproducibility checklist
  - submission readiness gate
  - mobile-tier readiness report
  - mobile evidence capture pack, execution playbook and readiness report
  - offline dry-run reports
- Anonymized benchmark scripts:
  - `scripts/audit_mobile_harness_task_bank.py`
  - `scripts/collect_mobile_harness_mobile_tier_evidence.py`
  - `scripts/generate_mobile_harness_baseline_protocol.py`
  - `scripts/generate_mobile_harness_baseline_run_contract.py`
  - `scripts/generate_mobile_harness_baseline_scaffold.py`
  - `scripts/generate_mobile_harness_baseline_dry_run.py`
  - `scripts/generate_mobile_harness_baseline_pilot_pack.py`
  - `scripts/generate_mobile_harness_baseline_pilot_readiness.py`
  - `scripts/generate_mobile_harness_bibliography_readiness.py`
  - `scripts/generate_mobile_harness_evidence_maturity_matrix.py`
  - `scripts/generate_mobile_harness_evaluation_protocol_readiness.py`
  - `scripts/generate_mobile_harness_mobile_evidence_pack.py`
  - `scripts/generate_mobile_harness_page_limit_readiness.py`
  - `scripts/generate_mobile_harness_reproducibility_checklist.py`
  - `scripts/generate_mobile_harness_submission_readiness.py`
  - `scripts/generate_mobile_harness_threats_to_validity.py`
  - `scripts/generate_mobile_harness_verifier_contract_readiness.py`
  - `scripts/generate_mobile_harness_task_bank.py`
  - `scripts/generate_mobile_harness_frozen_subset.py`
  - `scripts/generate_mobile_harness_claim_ledger.py`
  - `scripts/generate_mobile_harness_core_claim_readiness.py`
  - `scripts/prepare_mobile_harness_supplement.py`
  - `scripts/run_mobile_harness_bench.py`
  - `scripts/validate_mobile_harness_bench.py`

## Exclude

- `docs/wechat/`
- GitHub Pages assets that expose repository ownership or public project URLs.
- Release artifacts, app binaries, signing files, token test outputs and account-specific GitHub evidence.
- Local absolute paths, including Windows drive-letter paths.
- Any credential, token, platform account id, upload media id, personal handle or organization name.
- Raw screenshots that show author accounts, chat avatars, file-system usernames, private repos or WeChat publish metadata.

## Redaction Rules

- Replace public repository URLs with neutral placeholders such as `https://anonymous.example/mobile-harness`.
- Replace product-specific public branding with anonymous paper terms when needed:
  - public product name -> `MobileHarness prototype`
  - owner handles or organization names -> `anonymous`
- Keep benchmark task ids stable.
- Keep task categories, verifier names, task-set names, fixture names and run ids stable unless they reveal identity.
- Public-safe evidence paths must be repo-relative and must not include local drive letters or user folders.

## Source-Tree Risks

- Source benchmark docs may be product-facing and may contain public product terminology.
- Source schema `$id` values may point to public repository URLs before staging.
- Root README and GitHub Pages links are not anonymous and must not be copied into the supplement.
- `docs/wechat/` contains publishing artifacts and must stay outside any anonymous supplement package.

The staging script is responsible for producing the reviewer-facing package from these source materials. The current staged package uses repo-compatible paths, includes a top-level `README_SUPPLEMENT.md`, and passes the local identity/path/token scan before the zip is written.

## Reviewer Claim Map

The top-level `README_SUPPLEMENT.md` should include a claim review map so reviewers can separate evidence-backed claims from open requirements without reading the full repository first.
It should also include the evidence labels below so reviewers do not treat readiness materials as completed results.

- System abstraction and design invariants: inspect `paper/iclr-mobile-harness/main.pdf` plus `docs/mobile-harness-benchmark/reports/core-claim-readiness.md`.
- Candidate task supply: inspect `docs/mobile-harness-benchmark/tasks/v2-task-bank.json` plus `docs/mobile-harness-benchmark/reports/v2-quality-audit.md`; quality-axis fields are coverage tags, not difficulty or result claims.
- Counted T0 evidence: inspect `docs/mobile-harness-benchmark/runs/2026-06-06-smoke-v2-t0/summary.md` plus `docs/mobile-harness-benchmark/reports/paper-claim-evidence-ledger.md`.
- Non-counted readiness artifacts: inspect `docs/mobile-harness-benchmark/reports/evidence-maturity-matrix.md` before treating mobile packs, baseline scaffolds or pilot packs as results.
- Submission blockers: inspect `docs/mobile-harness-benchmark/reports/submission-readiness.md` before treating the draft as upload-ready.

## Evidence Labels

Reviewer-facing files should preserve these labels exactly when a result is not counted:

- `candidate_supply`: task-bank scale or coverage, not execution evidence.
- `t0_fixture_evidence`: deterministic offline verifier output, not Android/iOS behavior.
- `capture_ready_no_results`: mobile evidence templates prepared for future device runs.
- `pilot_ready_no_results`: baseline prompts and evidence sheets prepared for future comparison.
- `counts_as_experiment=false`: explicit guardrail for readiness reports, scaffolds and dry-run contracts.
- `open_requirement`: a blocker that must remain visible in the claim ledger and submission readiness gate.

## Verification Gate

Before a supplement zip is produced, run the repository-root staging command:

```powershell
python scripts\prepare_mobile_harness_supplement.py
```

The command stages `paper/iclr-mobile-harness/build/anonymous-supplement/`, runs a text scan over the staged supplement folder for the local project-specific forbidden-term list, and writes `paper/iclr-mobile-harness/build/mobile-harness-anonymous-supplement.zip` only if the scan passes.
At minimum, the list should cover:

```text
public product name
repository owner handle
public project URL
GitHub Pages URL
Windows drive-letter absolute paths
chat app account identifiers
upload media identifiers
API access token names
platform account identifiers
secret-key prefixes
```

The supplement is uploadable only if the scan has no identity, path or credential hits, except intentional anonymous paper terms such as `MobileHarness` and `MobileHarnessBench`.
Do not include the local forbidden-term list itself in the uploaded supplement.
Regenerate the package after every paper, benchmark, script, citation, real-device-result or baseline-result change.
