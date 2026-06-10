#!/usr/bin/env python3
"""Generate a submission-readiness gate for the Mobile Harness paper draft.

The report is intentionally conservative: it can pass as a draft gate while
still declaring that upload-ready evidence is incomplete.
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
BENCH_ROOT = ROOT / "docs" / "mobile-harness-benchmark"
REPORTS_ROOT = BENCH_ROOT / "reports"
PAPER_ROOT = ROOT / "paper" / "iclr-mobile-harness"

MAIN_TEX_PATH = PAPER_ROOT / "main.tex"
MAIN_PDF_PATH = PAPER_ROOT / "main.pdf"
SUPPLEMENT_BOUNDARY_PATH = PAPER_ROOT / "SUPPLEMENT_BOUNDARY.md"
SUBMISSION_TODO_PATH = PAPER_ROOT / "SUBMISSION_TODO.md"
PREPARE_SUPPLEMENT_SCRIPT_PATH = ROOT / "scripts" / "prepare_mobile_harness_supplement.py"
CLAIM_LEDGER_PATH = REPORTS_ROOT / "paper-claim-evidence-ledger.json"
CORE_CLAIM_READINESS_PATH = REPORTS_ROOT / "core-claim-readiness.json"
EVIDENCE_MATURITY_PATH = REPORTS_ROOT / "evidence-maturity-matrix.json"
MOBILE_READINESS_PATH = REPORTS_ROOT / "mobile-tier-readiness.json"
MOBILE_EVIDENCE_PACK_READINESS_PATH = REPORTS_ROOT / "mobile-evidence-pack-readiness.json"
VERIFIER_CONTRACT_READINESS_PATH = REPORTS_ROOT / "verifier-contract-readiness.json"
BASELINE_PILOT_READINESS_PATH = REPORTS_ROOT / "baseline-pilot-readiness.json"
BIBLIOGRAPHY_READINESS_PATH = REPORTS_ROOT / "bibliography-readiness.json"
THREATS_TO_VALIDITY_PATH = REPORTS_ROOT / "threats-to-validity.json"
EVALUATION_PROTOCOL_READINESS_PATH = REPORTS_ROOT / "evaluation-protocol-readiness.json"
PAGE_LIMIT_READINESS_PATH = REPORTS_ROOT / "page-limit-readiness.json"
REPRODUCIBILITY_CHECKLIST_PATH = REPORTS_ROOT / "reproducibility-checklist.json"
METHOD_PRESENTATION_READINESS_PATH = REPORTS_ROOT / "method-presentation-readiness.json"
REPORT_JSON_PATH = REPORTS_ROOT / "submission-readiness.json"
REPORT_MD_PATH = REPORTS_ROOT / "submission-readiness.md"


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def load_json(path: Path) -> Any:
    if not path.exists():
        raise SystemExit(f"missing required artifact: {rel(path)}")
    return json.loads(path.read_text(encoding="utf-8"))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"submission readiness generation failed: {message}")


def require_terms(path: Path, terms: list[str], label: str) -> None:
    if not path.exists():
        raise SystemExit(f"missing required artifact: {rel(path)}")
    text = path.read_text(encoding="utf-8")
    missing = [term for term in terms if term not in text]
    require(not missing, f"{label} missing terms: {missing}")


def gate(
    gate_id: str,
    name: str,
    status: str,
    evidence_artifacts: list[Path],
    rationale: str,
    next_actions: list[str],
) -> dict[str, Any]:
    missing = [rel(path) for path in evidence_artifacts if not path.exists()]
    require(not missing, f"{gate_id} has missing artifacts: {missing}")
    return {
        "id": gate_id,
        "name": name,
        "status": status,
        "evidence_artifacts": [rel(path) for path in evidence_artifacts],
        "rationale": rationale,
        "next_actions": next_actions,
    }


def build_report() -> dict[str, Any]:
    claim_ledger = load_json(CLAIM_LEDGER_PATH)
    core_claim = load_json(CORE_CLAIM_READINESS_PATH)
    maturity = load_json(EVIDENCE_MATURITY_PATH)
    mobile_readiness = load_json(MOBILE_READINESS_PATH)
    mobile_evidence_pack = load_json(MOBILE_EVIDENCE_PACK_READINESS_PATH)
    verifier_contract = load_json(VERIFIER_CONTRACT_READINESS_PATH)
    baseline_pilot = load_json(BASELINE_PILOT_READINESS_PATH)
    bibliography = load_json(BIBLIOGRAPHY_READINESS_PATH)
    threats = load_json(THREATS_TO_VALIDITY_PATH)
    evaluation_protocol = load_json(EVALUATION_PROTOCOL_READINESS_PATH)
    page_limit = load_json(PAGE_LIMIT_READINESS_PATH)
    reproducibility = load_json(REPRODUCIBILITY_CHECKLIST_PATH)
    method_presentation = load_json(METHOD_PRESENTATION_READINESS_PATH)

    require(claim_ledger.get("status") == "passed_with_open_requirements",
            "claim ledger must preserve open requirements")
    require(core_claim.get("status") == "passed_with_open_requirements",
            "core claim readiness must preserve open requirements")
    require(core_claim.get("claim_count") == 4,
            "core claim readiness must cover four positioning claims")
    require(core_claim.get("counts_as_experiment") is False,
            "core claim readiness must not count as experiment")
    require(maturity.get("status") == "passed_with_open_requirements",
            "evidence maturity matrix must preserve open requirements")
    require(maturity.get("current_max_counted_paper_evidence_level") == 1,
            "only T0 fixture evidence may count in this draft")
    require(maturity.get("counted_mobile_stage_ids") == [],
            "mobile experiment stages must remain uncounted")
    require(maturity.get("counted_baseline_stage_ids") == [],
            "baseline stages must remain uncounted")
    require(mobile_readiness.get("counts_as_experiment") is False,
            "mobile readiness must not count as experiment")
    require(mobile_evidence_pack.get("status") == "capture_ready_no_results",
            "mobile evidence pack must be capture_ready_no_results")
    require(mobile_evidence_pack.get("ready_for_capture") is True,
            "mobile evidence pack must be ready for capture")
    require(mobile_evidence_pack.get("ready_for_counted_mobile_experiment") is False,
            "mobile evidence pack must not count as mobile experiment")
    require(mobile_evidence_pack.get("task_count") == 48,
            "mobile evidence pack must cover 48 mobile-tier tasks")
    require(verifier_contract.get("status") == "passed",
            "verifier contract readiness must pass")
    require(verifier_contract.get("counts_as_experiment") is False,
            "verifier contract readiness must not count as experiment")
    require(verifier_contract.get("contract_count") == 12,
            "verifier contract readiness must cover twelve verifier contracts")
    require(verifier_contract.get("task_count_checked") == 1225,
            "verifier contract readiness must check all current task definitions")
    require(baseline_pilot.get("ready_for_counted_baseline_result") is False,
            "baseline pilot must not count as result")
    require(bibliography.get("status") == "passed",
            "bibliography readiness must pass before submission readiness is regenerated")
    require(bibliography.get("entry_count") == 9,
            "bibliography readiness must cover the nine current related-work entries")
    require(bibliography.get("remaining_draft_entries") == [],
            "bibliography readiness must have zero draft entries")
    require(threats.get("status") == "passed_with_open_requirements",
            "threats-to-validity matrix must preserve open requirements")
    require(threats.get("threat_count") == 6,
            "threats-to-validity matrix must cover six threats")
    require(evaluation_protocol.get("status") == "passed_with_open_requirements",
            "evaluation protocol readiness must preserve open requirements")
    require(evaluation_protocol.get("protocol_count") == 5,
            "evaluation protocol readiness must cover E1-E5")
    require(evaluation_protocol.get("counts_as_complete_evaluation") is False,
            "evaluation protocol readiness must not mark the evaluation complete")
    require(page_limit.get("status") == "passed",
            "page-limit readiness must pass for the current compiled PDF")
    require(page_limit.get("main_text_page_limit") == 9,
            "page-limit readiness must use the current nine-page main text limit")
    require(page_limit.get("within_main_text_limit") is True,
            "page-limit readiness must keep the main text within the current limit")
    require(page_limit.get("references_are_unlimited") is True,
            "page-limit readiness must record citations as unlimited pages")
    require(page_limit.get("counts_as_experiment") is False,
            "page-limit readiness must not count as experiment")
    require(reproducibility.get("status") == "passed_with_open_requirements",
            "reproducibility checklist must preserve open requirements")
    require(reproducibility.get("command_count") == 16,
            "reproducibility checklist must cover sixteen commands")
    require(reproducibility.get("ready_for_draft_reproduction") is True,
            "reproducibility checklist must mark draft reproduction ready")
    require(reproducibility.get("ready_for_full_empirical_reproduction") is False,
            "reproducibility checklist must not mark full empirical reproduction ready")
    require(method_presentation.get("status") == "passed",
            "method presentation readiness must pass")
    require(method_presentation.get("ready_for_method_review") is True,
            "method presentation readiness must mark method review ready")
    require(method_presentation.get("counts_as_experiment") is False,
            "method presentation readiness must not count as experiment")
    require(method_presentation.get("check_count") == 5,
            "method presentation readiness must cover five checks")
    require_terms(
        PREPARE_SUPPLEMENT_SCRIPT_PATH,
        [
            "REVIEWER_MANIFEST_REQUIRED_TERMS",
            "validate_reviewer_manifest",
            "## Claim Review Map",
            "## Evidence Label Quick Reference",
            "`candidate_supply`",
            "`t0_fixture_evidence`",
            "`capture_ready_no_results`",
            "`pilot_ready_no_results`",
            "`counts_as_experiment=false`",
            "`open_requirement`",
            "Do not report Android/iOS mobile-tier results",
        ],
        "reviewer manifest staging gate",
    )
    require_terms(
        SUPPLEMENT_BOUNDARY_PATH,
        [
            "README_SUPPLEMENT.md",
            "claim review map",
            "evidence labels",
            "`candidate_supply`",
            "`t0_fixture_evidence`",
            "`capture_ready_no_results`",
            "`pilot_ready_no_results`",
            "`counts_as_experiment=false`",
            "`open_requirement`",
        ],
        "anonymous supplement boundary",
    )

    paper_bytes = MAIN_PDF_PATH.stat().st_size if MAIN_PDF_PATH.exists() else 0
    gates = [
        gate(
            "S0_manuscript_artifacts",
            "Manuscript source and compiled PDF exist",
            "passed",
            [MAIN_TEX_PATH, MAIN_PDF_PATH],
            "The anonymous ICLR-style draft has LaTeX source and a compiled PDF.",
            ["Recompile after every text or bibliography change."],
        ),
        gate(
            "S1_claim_evidence_boundary",
            "Claims are mapped to evidence boundaries",
            "passed_with_open_requirements",
            [CLAIM_LEDGER_PATH, EVIDENCE_MATURITY_PATH],
            "T0 fixture evidence is separated from real mobile and baseline claims.",
            ["Keep new claims tied to concrete artifacts before adding them to the paper."],
        ),
        gate(
            "S1a_core_claim_positioning",
            "Core positioning claim is evidence-bounded",
            "passed_with_open_requirements",
            [CORE_CLAIM_READINESS_PATH],
            "The paper frames mobile AI coding as a harness control plane rather than a full mobile IDE or a general phone-use benchmark.",
            ["Regenerate the core claim readiness report after changing the abstract, introduction, motivation, scope or related-work positioning."],
        ),
        gate(
            "S2_mobile_experiment_boundary",
            "Mobile-tier results are not over-claimed",
            "open_requirement",
            [MOBILE_READINESS_PATH],
            "Android/iOS readiness is recorded, but no T2/T3/T4 result is claimed.",
            ["Run Android real-device subset.", "Run Mac iOS simulator subset.", "Attach screenshots, logs, traces, and device metadata."],
        ),
        gate(
            "S3_mobile_evidence_capture_pack",
            "Mobile-tier evidence capture pack is ready",
            "passed",
            [MOBILE_EVIDENCE_PACK_READINESS_PATH],
            "Android T2 and iOS T3 task-level evidence templates are generated but not counted as results.",
            ["Fill the templates only during real Android or Mac iOS simulator collection."],
        ),
        gate(
            "S3a_verifier_contract_readiness",
            "Verifier contracts cover current task banks",
            "passed",
            [VERIFIER_CONTRACT_READINESS_PATH],
            "All verifier ids referenced by the current v0/v1/v2 task banks are covered by machine-readable verifier contracts.",
            ["Regenerate the verifier contract readiness report after adding task categories, verifier ids, or verifier evidence requirements."],
        ),
        gate(
            "S4_baseline_result_boundary",
            "Baseline comparison remains protocol-only",
            "open_requirement",
            [BASELINE_PILOT_READINESS_PATH],
            "The baseline pilot pack is ready for execution but not ready for counted results.",
            ["Execute the pilot with locked model settings.", "Attach transcripts, verifier outputs, artifacts, and human-intervention records."],
        ),
        gate(
            "S5_anonymous_supplement_boundary",
            "Anonymous supplement boundary is defined",
            "passed",
            [SUPPLEMENT_BOUNDARY_PATH],
            "The boundary document defines included artifacts, repo-compatible supplement layout, excluded private materials, and scan rules.",
            ["Regenerate the supplement zip after real mobile runs, baseline runs, citation changes, and this readiness report."],
        ),
        gate(
            "S5a_reviewer_manifest_gate",
            "Reviewer manifest evidence labels are machine-gated",
            "passed",
            [SUPPLEMENT_BOUNDARY_PATH, PREPARE_SUPPLEMENT_SCRIPT_PATH],
            "The supplement staging script fails if README_SUPPLEMENT.md loses its claim map, evidence labels, or mobile-result boundary.",
            ["Keep reviewer-facing labels synchronized with new evidence states before regenerating the supplement."],
        ),
        gate(
            "S6_submission_metadata",
            "Venue, template, and authorship remain draft",
            "open_requirement",
            [SUBMISSION_TODO_PATH],
            "The draft still needs venue/year confirmation, official template confirmation, and author OpenReview checks.",
            ["Confirm target venue/year and official template.", "Confirm author OpenReview profiles before upload."],
        ),
        gate(
            "S7_bibliography_metadata",
            "Related-work bibliography metadata is verified",
            "passed",
            [BIBLIOGRAPHY_READINESS_PATH],
            "The current cited related-work entries have source URLs, eprint metadata where available, and no author placeholders.",
            ["Regenerate the bibliography readiness report after adding, removing, or replacing citations."],
        ),
        gate(
            "S8_threats_to_validity",
            "Threats to validity are tracked",
            "passed_with_open_requirements",
            [THREATS_TO_VALIDITY_PATH],
            "Construct, internal, external, baseline, privacy and submission threats are explicit and tied to open requirements.",
            ["Regenerate the threats matrix after changing claims, evidence levels, baselines, mobile collection or submission metadata."],
        ),
        gate(
            "S9_evaluation_protocol_readiness",
            "Evaluation protocol is machine-checkable",
            "passed_with_open_requirements",
            [EVALUATION_PROTOCOL_READINESS_PATH],
            "E1-E5 are tied to task sets, current evidence artifacts and non-counted open requirements.",
            ["Regenerate the evaluation protocol readiness report after changing E1-E5, task subsets, mobile collection or baseline protocols."],
        ),
        gate(
            "S9a_method_presentation_readiness",
            "Method presentation is reviewable",
            "passed",
            [METHOD_PRESENTATION_READINESS_PATH],
            "The draft has machine-checked visuals, algorithms, module interfaces, formulas and evidence-boundary language.",
            ["Regenerate the method presentation readiness report after changing system, benchmark, verifier, evaluation or limitation sections."],
        ),
        gate(
            "S10_reproducibility_checklist",
            "Draft reproducibility checklist is available",
            "passed_with_open_requirements",
            [REPRODUCIBILITY_CHECKLIST_PATH],
            "The draft command matrix maps reproducible commands to expected artifacts while keeping full empirical reproduction open.",
            ["Regenerate the reproducibility checklist after changing scripts, output artifacts, paper compilation, supplement staging, or validation commands."],
        ),
        gate(
            "S11_page_limit_readiness",
            "Compiled PDF page boundary is checked",
            "passed",
            [PAGE_LIMIT_READINESS_PATH],
            "The compiled draft records total PDF pages, the ethics page and the References start page, and keeps the main text within the current page limit.",
            ["Regenerate the page-limit readiness report after paper text, bibliography, style-file or template changes."],
        ),
    ]
    open_gate_ids = [entry["id"] for entry in gates if entry["status"] == "open_requirement"]

    return {
        "report": "submission-readiness",
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "status": "passed_with_open_requirements",
        "ready_for_submission_upload": False,
        "ready_for_counted_mobile_experiment": False,
        "ready_for_counted_baseline_result": False,
        "manuscript_pdf_bytes": paper_bytes,
        "gate_count": len(gates),
        "open_gate_ids": open_gate_ids,
        "open_requirements": [
            "venue_template_author_confirmation",
            "real_android_or_ios_mobile_tier_evidence",
            "counted_baseline_comparison_results",
            "final_anonymous_supplement_after_new_evidence",
        ],
        "evidence_boundary": (
            "The draft can be reviewed as a system-and-benchmark proposal with T0 fixture evidence, "
            "but it is not upload-ready as a final empirical paper until mobile-tier and baseline evidence are attached."
        ),
        "gates": gates,
    }


def write_markdown(report: dict[str, Any]) -> None:
    lines = [
        "# Submission Readiness Gate",
        "",
        f"Generated at: `{report['generated_at']}`",
        f"Status: `{report['status']}`",
        f"Ready for submission upload: `{str(report['ready_for_submission_upload']).lower()}`",
        "",
        "## Evidence Boundary",
        "",
        report["evidence_boundary"],
        "",
        "## Gates",
        "",
        "| Gate | Status | Rationale |",
        "| --- | --- | --- |",
    ]
    for entry in report["gates"]:
        lines.append(
            "| {name} | {status} | {rationale} |".format(
                name=entry["name"],
                status=entry["status"],
                rationale=entry["rationale"].replace("|", "/"),
            )
        )
    lines.extend(["", "## Open Requirements", ""])
    for requirement in report["open_requirements"]:
        lines.append(f"- `{requirement}`")
    lines.append("")
    REPORT_MD_PATH.write_text("\n".join(lines), encoding="utf-8", newline="")


def main() -> int:
    REPORTS_ROOT.mkdir(parents=True, exist_ok=True)
    report = build_report()
    REPORT_JSON_PATH.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_markdown(report)
    print("MobileHarnessBench submission readiness gate generated")
    print(f"report_json={rel(REPORT_JSON_PATH)}")
    print(f"report_md={rel(REPORT_MD_PATH)}")
    print(f"status={report['status']}")
    print(f"ready_for_submission_upload={report['ready_for_submission_upload']}")
    print(f"open_gates={len(report['open_gate_ids'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
