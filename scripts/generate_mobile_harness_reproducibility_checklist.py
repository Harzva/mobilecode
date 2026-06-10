#!/usr/bin/env python3
"""Generate a reproducibility checklist for the Mobile Harness draft."""

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
SUPPLEMENT_ZIP_PATH = PAPER_ROOT / "build" / "mobile-harness-anonymous-supplement.zip"
PAGE_LIMIT_READINESS_PATH = REPORTS_ROOT / "page-limit-readiness.json"
VERIFIER_CONTRACT_READINESS_PATH = REPORTS_ROOT / "verifier-contract-readiness.json"
METHOD_PRESENTATION_READINESS_PATH = REPORTS_ROOT / "method-presentation-readiness.json"

REPORT_JSON_PATH = REPORTS_ROOT / "reproducibility-checklist.json"
REPORT_MD_PATH = REPORTS_ROOT / "reproducibility-checklist.md"


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"reproducibility checklist generation failed: {message}")


def command_entry(
    entry_id: str,
    command: str,
    expected_outputs: list[Path],
    boundary: str,
    *,
    counts_as_experiment: bool = False,
) -> dict[str, Any]:
    missing = [rel(path) for path in expected_outputs if not path.exists()]
    require(not missing, f"{entry_id} missing outputs: {missing}")
    return {
        "id": entry_id,
        "command": command,
        "status": "ready",
        "expected_outputs": [rel(path) for path in expected_outputs],
        "counts_as_experiment": counts_as_experiment,
        "boundary": boundary,
    }


def assert_main_tex_reproducibility() -> list[str]:
    text = MAIN_TEX_PATH.read_text(encoding="utf-8")
    required_terms = [
        "\\section{Reproducibility Statement}",
        "machine-readable task definitions",
        "deterministic task-bank generator",
        "Algorithm 3: Differentiated candidate-bank construction",
        "\\mathcal{B}=\\mathrm{Assemble}",
        "\\Delta(t_i,t_j)",
        "offline verifier runner",
        "machine-readable verifier catalog",
        "validator",
        "claim-evidence ledger",
        "evidence maturity matrix",
        "evaluation-protocol",
        "method-presentation",
        "verifier-contract",
        "submission-readiness",
        "page-limit",
        "reproducibility readiness reports",
        "counts\\_as\\_final\\_paper\\_subset=false",
        "Future experimental runs will add device metadata",
    ]
    missing = [term for term in required_terms if term not in text]
    require(not missing, f"main.tex missing reproducibility terms: {missing}")
    return required_terms


def build_report() -> dict[str, Any]:
    checked_terms = assert_main_tex_reproducibility()
    commands = [
        command_entry(
            "R0_generate_task_bank",
            "python scripts/generate_mobile_harness_task_bank.py",
            [
                BENCH_ROOT / "tasks" / "v1-task-bank.json",
                BENCH_ROOT / "tasks" / "v2-task-bank.json",
            ],
            "Regenerates candidate task supply; does not count tasks as completed experiments.",
        ),
        command_entry(
            "R1_audit_task_bank",
            "python scripts/audit_mobile_harness_task_bank.py",
            [REPORTS_ROOT / "v2-quality-audit.json", REPORTS_ROOT / "v2-quality-audit.md"],
            "Checks structure, coverage, uniqueness and public-output safety; does not replace human review.",
        ),
        command_entry(
            "R2_run_offline_smoke",
            "python scripts/run_mobile_harness_bench.py --task-set smoke-v2 --run-id 2026-06-06-smoke-v2-t0",
            [
                BENCH_ROOT / "runs" / "2026-06-06-smoke-v2-t0" / "run.json",
                BENCH_ROOT / "runs" / "2026-06-06-smoke-v2-t0" / "summary.md",
                BENCH_ROOT / "runs" / "2026-06-06-smoke-v2-t0" / "traces.jsonl",
            ],
            "Counts as T0 fixture evidence only; does not count as Android/iOS mobile-tier evidence.",
        ),
        command_entry(
            "R3_generate_mobile_readiness",
            "python scripts/collect_mobile_harness_mobile_tier_evidence.py",
            [REPORTS_ROOT / "mobile-tier-readiness.json", REPORTS_ROOT / "mobile-tier-readiness.md"],
            "Records local Android/iOS tooling availability; does not count as a mobile experiment.",
        ),
        command_entry(
            "R4_generate_mobile_capture_pack",
            "python scripts/generate_mobile_harness_mobile_evidence_pack.py",
            [REPORTS_ROOT / "mobile-evidence-pack-readiness.json", REPORTS_ROOT / "mobile-evidence-pack-readiness.md"],
            "Creates T2/T3 capture templates; does not count as mobile experiment results.",
        ),
        command_entry(
            "R5_generate_verifier_contract_readiness",
            "python scripts/generate_mobile_harness_verifier_contract_readiness.py",
            [VERIFIER_CONTRACT_READINESS_PATH, REPORTS_ROOT / "verifier-contract-readiness.md"],
            "Checks machine-readable verifier contracts against all current task-bank verifier references.",
        ),
        command_entry(
            "R6_generate_baseline_readiness",
            "python scripts/generate_mobile_harness_baseline_protocol.py && python scripts/generate_mobile_harness_baseline_pilot_readiness.py",
            [
                REPORTS_ROOT / "baseline-protocol-readiness.json",
                REPORTS_ROOT / "baseline-run-contract.json",
                REPORTS_ROOT / "baseline-pilot-readiness.json",
            ],
            "Defines baseline comparison protocol and pilot readiness; no baseline performance result is claimed.",
        ),
        command_entry(
            "R7_generate_claim_reports",
            "python scripts/generate_mobile_harness_claim_ledger.py && python scripts/generate_mobile_harness_core_claim_readiness.py",
            [
                REPORTS_ROOT / "paper-claim-evidence-ledger.json",
                REPORTS_ROOT / "core-claim-readiness.json",
            ],
            "Maps paper-facing claims to evidence and positioning boundaries.",
        ),
        command_entry(
            "R8_generate_evidence_protocol_reports",
            "python scripts/generate_mobile_harness_evidence_maturity_matrix.py && python scripts/generate_mobile_harness_evaluation_protocol_readiness.py",
            [
                REPORTS_ROOT / "evidence-maturity-matrix.json",
                REPORTS_ROOT / "evaluation-protocol-readiness.json",
            ],
            "Separates T0 evidence from open mobile, GitHub sandbox and baseline requirements.",
        ),
        command_entry(
            "R9_generate_bibliography_and_threats",
            "python scripts/generate_mobile_harness_bibliography_readiness.py && python scripts/generate_mobile_harness_threats_to_validity.py",
            [
                REPORTS_ROOT / "bibliography-readiness.json",
                REPORTS_ROOT / "threats-to-validity.json",
            ],
            "Checks current citation metadata and review-risk boundaries.",
        ),
        command_entry(
            "R10_generate_method_presentation_readiness",
            "python scripts/generate_mobile_harness_method_presentation_readiness.py",
            [METHOD_PRESENTATION_READINESS_PATH, REPORTS_ROOT / "method-presentation-readiness.md"],
            "Checks that the paper has reviewable visuals, algorithms, module interfaces, formulas and evidence boundaries.",
        ),
        command_entry(
            "R11_compile_paper",
            "latexmk -pdf -interaction=nonstopmode -halt-on-error main.tex",
            [MAIN_TEX_PATH, MAIN_PDF_PATH],
            "Compiles the anonymous paper draft; local TeX availability is required.",
        ),
        command_entry(
            "R12_generate_page_limit_readiness",
            "python scripts/generate_mobile_harness_page_limit_readiness.py",
            [PAGE_LIMIT_READINESS_PATH, REPORTS_ROOT / "page-limit-readiness.md"],
            "Checks current compiled PDF page boundary and records where references begin.",
        ),
        command_entry(
            "R13_generate_submission_readiness",
            "python scripts/generate_mobile_harness_submission_readiness.py",
            [REPORTS_ROOT / "submission-readiness.json", REPORTS_ROOT / "submission-readiness.md"],
            "Checks draft upload gates while keeping upload readiness false.",
        ),
        command_entry(
            "R14_stage_anonymous_supplement",
            "python scripts/prepare_mobile_harness_supplement.py",
            [SUPPLEMENT_BOUNDARY_PATH, SUPPLEMENT_ZIP_PATH],
            "Builds a locally anonymized reviewer package and scans it for identity/path/token markers.",
        ),
        command_entry(
            "R15_validate_benchmark",
            "python scripts/validate_mobile_harness_bench.py",
            [
                BENCH_ROOT / "tasks" / "v0-seed-tasks.json",
                BENCH_ROOT / "tasks" / "v2-task-bank.json",
                REPORTS_ROOT / "submission-readiness.json",
            ],
            "Validates task banks, task sets, runs, reports, and evidence-boundary invariants.",
        ),
    ]
    return {
        "report": "reproducibility-checklist",
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "status": "passed_with_open_requirements",
        "command_count": len(commands),
        "counts_as_experiment": False,
        "ready_for_draft_reproduction": True,
        "ready_for_full_empirical_reproduction": False,
        "main_tex_reproducibility_terms": checked_terms,
        "open_requirements": [
            "real_android_or_ios_mobile_tier_evidence",
            "authorized_github_sandbox_delivery_evidence",
            "counted_baseline_comparison_results",
            "final_anonymous_supplement_after_new_evidence",
        ],
        "evidence_boundary": (
            "The checklist makes the current draft package reproducible as a T0/system-and-benchmark artifact. "
            "It does not claim full empirical reproduction because real mobile-tier, GitHub sandbox and counted baseline results remain open."
        ),
        "commands": commands,
    }


def write_markdown(report: dict[str, Any]) -> None:
    lines = [
        "# Reproducibility Checklist",
        "",
        f"Generated at: `{report['generated_at']}`",
        f"Status: `{report['status']}`",
        f"Draft reproduction ready: `{str(report['ready_for_draft_reproduction']).lower()}`",
        f"Full empirical reproduction ready: `{str(report['ready_for_full_empirical_reproduction']).lower()}`",
        "",
        "## Evidence Boundary",
        "",
        report["evidence_boundary"],
        "",
        "## Commands",
        "",
        "| Step | Status | Boundary |",
        "| --- | --- | --- |",
    ]
    for entry in report["commands"]:
        lines.append(f"| `{entry['command']}` | `{entry['status']}` | {entry['boundary']} |")
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
    print("MobileHarnessBench reproducibility checklist generated")
    print(f"report_json={rel(REPORT_JSON_PATH)}")
    print(f"report_md={rel(REPORT_MD_PATH)}")
    print(f"status={report['status']}")
    print(f"commands={report['command_count']}")
    print(f"full_empirical_reproduction={report['ready_for_full_empirical_reproduction']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
