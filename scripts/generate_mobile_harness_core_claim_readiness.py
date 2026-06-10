#!/usr/bin/env python3
"""Generate a core-claim readiness report for the Mobile Harness paper."""

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
CLAIM_LEDGER_PATH = REPORTS_ROOT / "paper-claim-evidence-ledger.json"
EVIDENCE_MATURITY_PATH = REPORTS_ROOT / "evidence-maturity-matrix.json"
EVALUATION_PROTOCOL_PATH = REPORTS_ROOT / "evaluation-protocol-readiness.json"
THREATS_TO_VALIDITY_PATH = REPORTS_ROOT / "threats-to-validity.json"

REPORT_JSON_PATH = REPORTS_ROOT / "core-claim-readiness.json"
REPORT_MD_PATH = REPORTS_ROOT / "core-claim-readiness.md"


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def load_json(path: Path) -> Any:
    if not path.exists():
        raise SystemExit(f"missing required artifact: {rel(path)}")
    return json.loads(path.read_text(encoding="utf-8"))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"core claim readiness generation failed: {message}")


def require_terms(text: str, terms: list[str], claim_id: str) -> list[str]:
    missing = [term for term in terms if term not in text]
    require(not missing, f"{claim_id} missing paper terms: {missing}")
    return terms


def core_claim(
    claim_id: str,
    statement: str,
    paper_terms: list[str],
    evidence_artifacts: list[Path],
    boundary: str,
) -> dict[str, Any]:
    missing = [rel(path) for path in evidence_artifacts if not path.exists()]
    require(not missing, f"{claim_id} missing artifacts: {missing}")
    return {
        "id": claim_id,
        "statement": statement,
        "status": "supported_as_positioning_claim",
        "counts_as_experiment": False,
        "paper_terms": paper_terms,
        "evidence_artifacts": [rel(path) for path in evidence_artifacts],
        "boundary": boundary,
    }


def build_report() -> dict[str, Any]:
    text = MAIN_TEX_PATH.read_text(encoding="utf-8")
    claim_ledger = load_json(CLAIM_LEDGER_PATH)
    maturity = load_json(EVIDENCE_MATURITY_PATH)
    evaluation = load_json(EVALUATION_PROTOCOL_PATH)
    threats = load_json(THREATS_TO_VALIDITY_PATH)

    require(claim_ledger.get("status") == "passed_with_open_requirements",
            "claim ledger must keep open requirements")
    require(maturity.get("current_max_counted_paper_evidence_level") == 1,
            "core claim readiness expects T0-only counted paper evidence")
    require(evaluation.get("protocol_count") == 5,
            "evaluation protocol readiness must cover E1-E5")
    require(evaluation.get("counts_as_complete_evaluation") is False,
            "evaluation protocol readiness must not mark evaluation complete")
    require(threats.get("threat_count") == 6,
            "threats-to-validity must cover six threats")

    claims = [
        core_claim(
            "C1_not_full_mobile_ide",
            "Phone-native AI coding should be framed as a harness control plane, not as compressing a full IDE onto a phone.",
            require_terms(
                text,
                [
                    "not as ``putting a full IDE on a phone''",
                    "control plane",
                    "not served well by compressing a desktop IDE into a small screen",
                ],
                "C1_not_full_mobile_ide",
            ),
            [MAIN_TEX_PATH, CLAIM_LEDGER_PATH],
            "This is a positioning claim, not an empirical performance result.",
        ),
        core_claim(
            "C2_harness_is_research_object",
            "The research object is the harness layer that coordinates mobile inputs, artifacts, runtime or delivery routes, and evidence.",
            require_terms(
                text,
                [
                    "The harness is the research object",
                    "mobile input surfaces",
                    "coding artifacts",
                    "execution or delivery routes",
                    "verifier evidence",
                    "Design invariants",
                    "route explicitness",
                    "evidence monotonicity",
                    "public-report safety",
                ],
                "C2_harness_is_research_object",
            ),
            [MAIN_TEX_PATH, CLAIM_LEDGER_PATH, EVIDENCE_MATURITY_PATH],
            "The current implementation and benchmark support the abstraction, while real mobile performance remains open.",
        ),
        core_claim(
            "C3_not_general_phone_use_benchmark",
            "MobileHarnessBench is scoped to phone-native AI coding harnesses rather than general app-control phone-use agents.",
            require_terms(
                text,
                [
                    "not ask whether an agent can operate arbitrary consumer apps",
                    "phone-native coding harness",
                    "not a completed benchmark release",
                ],
                "C3_not_general_phone_use_benchmark",
            ),
            [MAIN_TEX_PATH, THREATS_TO_VALIDITY_PATH],
            "The scope is intentionally narrower than general phone-use benchmarks.",
        ),
        core_claim(
            "C4_evidence_first_counting",
            "Benchmark claims count evidence, traces, verifiers and mobile-tier artifacts rather than task intention or generated text.",
            require_terms(
                text,
                [
                    "A mobile benchmark must count evidence, not intention",
                    "A task is counted only when its verifier result, trace, summary, artifacts, and required mobile-tier evidence are present",
                    "counts\\_as\\_experiment=false",
                    "\\section{Conclusion}",
                    "evidence-gated benchmark protocol",
                    "The remaining work is empirical",
                ],
                "C4_evidence_first_counting",
            ),
            [MAIN_TEX_PATH, CLAIM_LEDGER_PATH, EVIDENCE_MATURITY_PATH, EVALUATION_PROTOCOL_PATH],
            "Only T0 fixture evidence is counted in the current draft; mobile and baseline results remain open.",
        ),
    ]
    return {
        "report": "core-claim-readiness",
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "status": "passed_with_open_requirements",
        "claim_count": len(claims),
        "counts_as_experiment": False,
        "paper_positioning_checked": True,
        "open_requirements": [
            "real_mobile_tier_runs",
            "counted_baseline_comparison_results",
            "final_frozen_subset_after_mobile_and_github_evidence",
        ],
        "evidence_boundary": (
            "The core positioning claims are present in the paper and linked to evidence-boundary artifacts, "
            "but they do not substitute for real mobile-tier or baseline experiments."
        ),
        "claims": claims,
    }


def write_markdown(report: dict[str, Any]) -> None:
    lines = [
        "# Core Claim Readiness",
        "",
        f"Generated at: `{report['generated_at']}`",
        f"Status: `{report['status']}`",
        f"Counts as experiment: `{str(report['counts_as_experiment']).lower()}`",
        "",
        "## Evidence Boundary",
        "",
        report["evidence_boundary"],
        "",
        "## Claims",
        "",
        "| Claim | Status | Boundary |",
        "| --- | --- | --- |",
    ]
    for claim in report["claims"]:
        lines.append(f"| {claim['statement']} | `{claim['status']}` | {claim['boundary']} |")
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
    print("MobileHarnessBench core claim readiness generated")
    print(f"report_json={rel(REPORT_JSON_PATH)}")
    print(f"report_md={rel(REPORT_MD_PATH)}")
    print(f"status={report['status']}")
    print(f"claims={report['claim_count']}")
    print(f"counts_as_experiment={report['counts_as_experiment']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
