#!/usr/bin/env python3
"""Generate a threats-to-validity matrix for the Mobile Harness draft."""

from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
BENCH_ROOT = ROOT / "docs" / "mobile-harness-benchmark"
REPORTS_ROOT = BENCH_ROOT / "reports"
PAPER_ROOT = ROOT / "paper" / "iclr-mobile-harness"

MAIN_TEX_PATH = PAPER_ROOT / "main.tex"
CLAIM_LEDGER_PATH = REPORTS_ROOT / "paper-claim-evidence-ledger.json"
EVIDENCE_MATURITY_PATH = REPORTS_ROOT / "evidence-maturity-matrix.json"
MOBILE_EVIDENCE_PACK_PATH = REPORTS_ROOT / "mobile-evidence-pack-readiness.json"
BASELINE_PILOT_READINESS_PATH = REPORTS_ROOT / "baseline-pilot-readiness.json"
BIBLIOGRAPHY_READINESS_PATH = REPORTS_ROOT / "bibliography-readiness.json"
SUBMISSION_READINESS_PATH = REPORTS_ROOT / "submission-readiness.json"

REPORT_JSON_PATH = REPORTS_ROOT / "threats-to-validity.json"
REPORT_MD_PATH = REPORTS_ROOT / "threats-to-validity.md"


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def load_json(path: Path) -> Any:
    if not path.exists():
        raise SystemExit(f"missing required artifact: {rel(path)}")
    return json.loads(path.read_text(encoding="utf-8"))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"threats-to-validity generation failed: {message}")


def extract_limitations_section(text: str) -> str:
    match = re.search(
        r"\\section\{Limitations and Threats to Validity\}(?P<body>.*?)\\section\{Reproducibility Statement\}",
        text,
        re.S,
    )
    require(match is not None, "main.tex must contain a Limitations and Threats to Validity section")
    return match.group("body")


def threat(
    threat_id: str,
    category: str,
    risk: str,
    mitigation: str,
    evidence_artifacts: list[Path],
    open_requirement: str | None,
) -> dict[str, Any]:
    missing = [rel(path) for path in evidence_artifacts if not path.exists()]
    require(not missing, f"{threat_id} has missing evidence artifacts: {missing}")
    return {
        "id": threat_id,
        "category": category,
        "risk": risk,
        "mitigation": mitigation,
        "status": "mitigated_with_open_requirement" if open_requirement else "mitigated_for_current_draft",
        "counts_as_experiment": False,
        "evidence_artifacts": [rel(path) for path in evidence_artifacts],
        "open_requirement": open_requirement,
    }


def build_report() -> dict[str, Any]:
    paper_text = MAIN_TEX_PATH.read_text(encoding="utf-8")
    limitations = extract_limitations_section(paper_text)
    claim_ledger = load_json(CLAIM_LEDGER_PATH)
    maturity = load_json(EVIDENCE_MATURITY_PATH)
    mobile_pack = load_json(MOBILE_EVIDENCE_PACK_PATH)
    baseline_pilot = load_json(BASELINE_PILOT_READINESS_PATH)
    bibliography = load_json(BIBLIOGRAPHY_READINESS_PATH)
    submission = load_json(SUBMISSION_READINESS_PATH)

    require(claim_ledger.get("status") == "passed_with_open_requirements", "claim ledger must preserve open requirements")
    require(maturity.get("counted_mobile_stage_ids") == [], "mobile stages must remain uncounted")
    require(maturity.get("counted_baseline_stage_ids") == [], "baseline stages must remain uncounted")
    require(mobile_pack.get("ready_for_counted_mobile_experiment") is False, "mobile pack must not count as experiment")
    require(baseline_pilot.get("ready_for_counted_baseline_result") is False, "baseline pilot must not count")
    require(bibliography.get("status") == "passed", "bibliography readiness must pass")
    require(submission.get("ready_for_submission_upload") is False, "submission readiness must remain false")

    required_terms = {
        "candidate_bank": r"candidate bank",
        "offline_t0": r"T0|offline",
        "android_ios": r"Android|iOS",
        "general_phone_use": r"general phone-use|phone-use benchmark",
        "github_sandbox": r"GitHub|sandbox",
        "venue_metadata": r"venue|template|OpenReview|bibliography",
    }
    missing_terms = [name for name, pattern in required_terms.items() if not re.search(pattern, limitations, re.I)]
    require(not missing_terms, f"limitations section missing coverage terms: {missing_terms}")

    threats = [
        threat(
            "TTV1_construct_candidate_bank",
            "Construct validity",
            "The 1,000-task bank could be mistaken for completed experiments.",
            "The paper, claim ledger and maturity matrix mark it as task supply only.",
            [MAIN_TEX_PATH, CLAIM_LEDGER_PATH, EVIDENCE_MATURITY_PATH],
            "human_review_and_final_frozen_subset",
        ),
        threat(
            "TTV2_internal_t0_evidence",
            "Internal validity",
            "Offline T0 results validate fixtures and verifiers but not phone behavior.",
            "T0 is reported separately and mobile tiers remain open.",
            [MAIN_TEX_PATH, CLAIM_LEDGER_PATH, EVIDENCE_MATURITY_PATH],
            "real_mobile_tier_runs",
        ),
        threat(
            "TTV3_external_device_diversity",
            "External validity",
            "A single Android/iOS environment would not cover device, OS, vendor and network diversity.",
            "The mobile evidence pack records device metadata, logs and screenshots before counting results.",
            [MOBILE_EVIDENCE_PACK_PATH],
            "multi_device_mobile_collection",
        ),
        threat(
            "TTV4_baseline_fairness",
            "Baseline validity",
            "Baseline comparisons can be biased by model settings, prompts and human intervention.",
            "The baseline pilot pack requires model locks, transcripts, verifier outputs and intervention records.",
            [BASELINE_PILOT_READINESS_PATH],
            "counted_baseline_runs_with_locked_settings",
        ),
        threat(
            "TTV5_privacy_and_delivery",
            "Privacy and delivery validity",
            "GitHub and public reports could leak private repositories, credentials or account identifiers.",
            "The supplement boundary, public-output safety checks and GitHub sandbox rule constrain public artifacts.",
            [MAIN_TEX_PATH, SUBMISSION_READINESS_PATH],
            "authorized_github_sandbox_runs",
        ),
        threat(
            "TTV6_submission_metadata",
            "Submission validity",
            "A strong draft can still be invalid for a specific venue if year, template, author profiles or citations drift.",
            "Bibliography metadata is verified now, while venue/template/authorship remain open in submission readiness.",
            [BIBLIOGRAPHY_READINESS_PATH, SUBMISSION_READINESS_PATH],
            "venue_template_author_confirmation",
        ),
    ]

    return {
        "report": "threats-to-validity",
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "status": "passed_with_open_requirements",
        "threat_count": len(threats),
        "counts_as_experiment": False,
        "limitations_section_checked": True,
        "open_requirements": sorted({entry["open_requirement"] for entry in threats if entry["open_requirement"]}),
        "evidence_boundary": (
            "Threats are tracked as review-quality controls, not as empirical results. "
            "Open threats remain open until mobile-tier and baseline evidence exists."
        ),
        "evidence_artifacts": [
            rel(MAIN_TEX_PATH),
            rel(CLAIM_LEDGER_PATH),
            rel(EVIDENCE_MATURITY_PATH),
            rel(MOBILE_EVIDENCE_PACK_PATH),
            rel(BASELINE_PILOT_READINESS_PATH),
            rel(BIBLIOGRAPHY_READINESS_PATH),
            rel(SUBMISSION_READINESS_PATH),
        ],
        "threats": threats,
    }


def write_markdown(report: dict[str, Any]) -> None:
    lines = [
        "# Threats To Validity Matrix",
        "",
        f"Generated at: `{report['generated_at']}`",
        f"Status: `{report['status']}`",
        "",
        "## Evidence Boundary",
        "",
        report["evidence_boundary"],
        "",
        "## Threats",
        "",
        "| Threat | Category | Status | Open requirement |",
        "| --- | --- | --- | --- |",
    ]
    for entry in report["threats"]:
        open_req = entry["open_requirement"] or "none"
        lines.append(f"| `{entry['id']}` | {entry['category']} | `{entry['status']}` | `{open_req}` |")
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
    print("MobileHarnessBench threats-to-validity matrix generated")
    print(f"report_json={rel(REPORT_JSON_PATH)}")
    print(f"report_md={rel(REPORT_MD_PATH)}")
    print(f"status={report['status']}")
    print(f"threats={report['threat_count']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
