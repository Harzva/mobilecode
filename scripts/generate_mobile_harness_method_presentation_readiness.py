#!/usr/bin/env python3
"""Generate a method-presentation readiness report for the Mobile Harness draft."""

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
REPORT_JSON_PATH = REPORTS_ROOT / "method-presentation-readiness.json"
REPORT_MD_PATH = REPORTS_ROOT / "method-presentation-readiness.md"


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"method presentation readiness generation failed: {message}")


def count_pattern(text: str, pattern: str) -> int:
    return len(re.findall(pattern, text))


def require_terms(text: str, terms: list[str], label: str) -> list[str]:
    missing = [term for term in terms if term not in text]
    require(not missing, f"{label} missing terms: {missing}")
    return terms


def build_report() -> dict[str, Any]:
    require(MAIN_TEX_PATH.exists(), f"missing paper source: {rel(MAIN_TEX_PATH)}")
    text = MAIN_TEX_PATH.read_text(encoding="utf-8")

    visual_terms = require_terms(
        text,
        [
            "\\begin{figure}[t]",
            "\\label{fig:architecture}",
            "\\label{fig:promotion-flow}",
            "\\begin{table}[t]",
            "\\label{tab:positioning}",
            "\\label{tab:categories}",
            "\\label{tab:tiers}",
            "\\label{tab:dryrun}",
        ],
        "visual/table presentation",
    )
    algorithm_terms = require_terms(
        text,
        [
            "Algorithm 1: Mobile harness execution loop",
            "Algorithm 2: Evidence-gated verifier module",
            "Algorithm 3: Differentiated candidate-bank construction",
            "Algorithm 4: Mobile-tier promotion audit",
        ],
        "algorithm presentation",
    )
    module_terms = require_terms(
        text,
        [
            "\\mathcal{H}=\\mathcal{V}\\circ\\mathcal{L}\\circ\\Phi\\circ\\Omega\\circ\\Pi\\circ N_{\\mathcal{I}}",
            "The typed interfaces are",
            "\\Omega:(t,\\mathcal{R}_t)\\mapsto r^\\star",
            "RuntimeProvider is the executable module contract",
            "\\mathrm{admit}(r,t)",
            "EvidenceLedger appends traces",
        ],
        "module/interface presentation",
    )
    formula_terms = require_terms(
        text,
        [
            "\\mathrm{MCH}=\\mathrm{PhoneOS}",
            "\\mathcal{H}=(\\mathcal{I},\\mathcal{C},\\mathcal{P},\\mathcal{R},\\mathcal{D},\\mathcal{E},\\mathcal{V})",
            "r_t^\\star",
            "\\mathcal{I}_{\\mathcal{H}}(t)",
            "t=(id,c,g,i,\\kappa,a,\\nu,e,b,\\mu,o)",
            "\\mathcal{B}=\\mathrm{Assemble}",
            "\\Delta(t_i,t_j)",
            "\\mathrm{tier}(t,r)",
            "\\mathrm{counted}(t)",
            "\\pi(t,r)",
            "\\mathbf{m}_w",
            "\\Gamma_j=(\\mathrm{claim}_j,A_j,\\eta_j)",
        ],
        "formula presentation",
    )
    boundary_terms = require_terms(
        text,
        [
            "candidate bank, not a claim of 1,000 completed experiments",
            "fixture-only T0 evidence",
            "not Android/iOS device evidence",
            "\\texttt{counts\\_as\\_experiment=false}",
            "not yet reproducible as a full empirical result",
            "Future experimental runs will add device metadata before promotion",
        ],
        "evidence-boundary presentation",
    )

    counts = {
        "figures": count_pattern(text, r"\\begin\{figure\}"),
        "tables": count_pattern(text, r"\\begin\{table\}"),
        "algorithm_markers": count_pattern(text, r"Algorithm [1-4]:"),
        "display_math_blocks": count_pattern(text, r"\\\[[\s\S]*?\\\]"),
        "equation_symbols": sum(1 for term in formula_terms if term in text),
    }
    require(counts["figures"] >= 2, "paper must contain at least two method/evidence figures")
    require(counts["tables"] >= 4, "paper must contain at least four review-supporting tables")
    require(counts["algorithm_markers"] >= 4, "paper must contain four algorithm markers")
    require(counts["display_math_blocks"] >= 8, "paper must retain enough display math for method formalization")

    checks = [
        {
            "id": "MP1_visual_scaffolding",
            "name": "Architecture and evidence-flow visuals are present",
            "status": "passed",
            "required_terms": visual_terms,
            "counts_as_experiment": False,
        },
        {
            "id": "MP2_algorithmic_methods",
            "name": "Core methods are named as algorithms",
            "status": "passed",
            "required_terms": algorithm_terms,
            "counts_as_experiment": False,
        },
        {
            "id": "MP3_module_interfaces",
            "name": "Harness modules have typed interfaces and contracts",
            "status": "passed",
            "required_terms": module_terms,
            "counts_as_experiment": False,
        },
        {
            "id": "MP4_formula_contracts",
            "name": "Benchmark and verifier claims are formula-bound",
            "status": "passed",
            "required_terms": formula_terms,
            "counts_as_experiment": False,
        },
        {
            "id": "MP5_evidence_boundaries",
            "name": "Method presentation does not over-claim evidence",
            "status": "passed",
            "required_terms": boundary_terms,
            "counts_as_experiment": False,
        },
    ]

    return {
        "report": "method-presentation-readiness",
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "status": "passed",
        "ready_for_method_review": True,
        "counts_as_experiment": False,
        "check_count": len(checks),
        "method_surface_counts": counts,
        "open_requirements": [
            "real_android_or_ios_mobile_tier_evidence",
            "counted_baseline_comparison_results",
            "venue_template_author_confirmation",
        ],
        "evidence_boundary": (
            "This report checks that the paper presents the harness and benchmark as reviewable methods "
            "with visuals, algorithms, module interfaces, formulas and evidence boundaries. It does not "
            "count as mobile-device or baseline evidence."
        ),
        "checks": checks,
        "evidence_artifacts": [rel(MAIN_TEX_PATH)],
    }


def write_markdown(report: dict[str, Any]) -> None:
    lines = [
        "# Method Presentation Readiness",
        "",
        f"Generated at: `{report['generated_at']}`",
        f"Status: `{report['status']}`",
        f"Ready for method review: `{str(report['ready_for_method_review']).lower()}`",
        "",
        "## Evidence Boundary",
        "",
        report["evidence_boundary"],
        "",
        "## Surface Counts",
        "",
        "| Surface | Count |",
        "| --- | ---: |",
    ]
    for key, value in report["method_surface_counts"].items():
        lines.append(f"| `{key}` | {value} |")
    lines.extend(["", "## Checks", "", "| Check | Status | Boundary |", "| --- | --- | --- |"])
    for check in report["checks"]:
        lines.append(
            "| {name} | `{status}` | counts_as_experiment=`{counts}` |".format(
                name=check["name"],
                status=check["status"],
                counts=str(check["counts_as_experiment"]).lower(),
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
    print("MobileHarnessBench method presentation readiness generated")
    print(f"report_json={rel(REPORT_JSON_PATH)}")
    print(f"report_md={rel(REPORT_MD_PATH)}")
    print(f"status={report['status']}")
    print(f"checks={report['check_count']}")
    print(f"ready_for_method_review={report['ready_for_method_review']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
