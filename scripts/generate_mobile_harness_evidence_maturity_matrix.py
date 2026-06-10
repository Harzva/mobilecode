#!/usr/bin/env python3
"""Generate an evidence maturity matrix for MobileHarnessBench claims."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
BENCH_ROOT = ROOT / "docs" / "mobile-harness-benchmark"
REPORTS_ROOT = BENCH_ROOT / "reports"
BASELINES_ROOT = BENCH_ROOT / "baselines"

V2_AUDIT_PATH = REPORTS_ROOT / "v2-quality-audit.json"
REPRESENTATIVE_RUN_PATH = BENCH_ROOT / "runs" / "2026-06-06-v0-dry-run" / "run.json"
SMOKE_RUN_PATH = BENCH_ROOT / "runs" / "2026-06-06-smoke-v2-t0" / "run.json"
FROZEN_SUBSET_PATH = BENCH_ROOT / "tasks" / "frozen-v2-paper-subset.json"
FROZEN_READINESS_PATH = REPORTS_ROOT / "frozen-subset-readiness.json"
MOBILE_READINESS_PATH = REPORTS_ROOT / "mobile-tier-readiness.json"
BASELINE_PROTOCOL_PATH = REPORTS_ROOT / "baseline-protocol-readiness.json"
BASELINE_RUN_CONTRACT_PATH = REPORTS_ROOT / "baseline-run-contract.json"
BASELINE_DRY_RUN_MANIFEST_PATH = BASELINES_ROOT / "2026-06-06-baseline-dry-run-t0" / "manifest.json"
BASELINE_PILOT_PACK_MANIFEST_PATH = BASELINES_ROOT / "2026-06-06-baseline-pilot-pack" / "manifest.json"
BASELINE_PILOT_READINESS_PATH = REPORTS_ROOT / "baseline-pilot-readiness.json"
CLAIM_LEDGER_PATH = REPORTS_ROOT / "paper-claim-evidence-ledger.json"

REPORT_JSON_PATH = REPORTS_ROOT / "evidence-maturity-matrix.json"
REPORT_MD_PATH = REPORTS_ROOT / "evidence-maturity-matrix.md"


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def load_json(path: Path) -> Any:
    if not path.exists():
        raise SystemExit(f"missing required artifact: {rel(path)}")
    return json.loads(path.read_text(encoding="utf-8"))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"evidence maturity generation failed: {message}")


def stage(
    stage_id: str,
    name: str,
    level: int,
    status: str,
    artifacts: list[Path],
    *,
    counts_as_paper_evidence: bool,
    counts_as_mobile_experiment: bool,
    counts_as_baseline_result: bool,
    can_be_reported_as: str,
    next_required_evidence: list[str],
) -> dict[str, Any]:
    missing = [rel(path) for path in artifacts if not path.exists()]
    require(not missing, f"{stage_id} missing artifacts: {missing}")
    return {
        "id": stage_id,
        "name": name,
        "maturity_level": level,
        "status": status,
        "counts_as_paper_evidence": counts_as_paper_evidence,
        "counts_as_mobile_experiment": counts_as_mobile_experiment,
        "counts_as_baseline_result": counts_as_baseline_result,
        "can_be_reported_as": can_be_reported_as,
        "evidence_artifacts": [rel(path) for path in artifacts],
        "next_required_evidence": next_required_evidence,
    }


def build_matrix() -> dict[str, Any]:
    v2_audit = load_json(V2_AUDIT_PATH)
    representative_run = load_json(REPRESENTATIVE_RUN_PATH)
    smoke_run = load_json(SMOKE_RUN_PATH)
    frozen_subset = load_json(FROZEN_SUBSET_PATH)
    frozen_readiness = load_json(FROZEN_READINESS_PATH)
    mobile_readiness = load_json(MOBILE_READINESS_PATH)
    baseline_protocol = load_json(BASELINE_PROTOCOL_PATH)
    baseline_run_contract = load_json(BASELINE_RUN_CONTRACT_PATH)
    baseline_dry_run = load_json(BASELINE_DRY_RUN_MANIFEST_PATH)
    baseline_pilot_pack = load_json(BASELINE_PILOT_PACK_MANIFEST_PATH)
    baseline_pilot_readiness = load_json(BASELINE_PILOT_READINESS_PATH)
    claim_ledger = load_json(CLAIM_LEDGER_PATH)

    require(v2_audit.get("status") == "passed_with_limits", "v2 audit must pass with limits")
    require(representative_run.get("summary", {}).get("total") == 5, "representative run total changed")
    require(smoke_run.get("summary", {}).get("total") == 60, "smoke run total changed")
    require(frozen_subset.get("counts_as_final_paper_subset") is False, "frozen subset must remain draft")
    require(frozen_readiness.get("counts_as_final_paper_subset") is False, "frozen readiness must remain draft")
    require(mobile_readiness.get("counts_as_experiment") is False, "mobile readiness must not count")
    require(baseline_protocol.get("counts_as_baseline_result") is False, "baseline protocol must not count")
    require(baseline_run_contract.get("result_count") == 0, "baseline contract must have zero results")
    require(baseline_dry_run.get("counts_as_baseline_result") is False, "baseline dry run must not count")
    require(baseline_pilot_pack.get("counts_as_baseline_result") is False, "baseline pilot pack must not count")
    require(baseline_pilot_readiness.get("ready_for_counted_baseline_result") is False,
            "baseline pilot readiness must not be counted")
    require(claim_ledger.get("status") == "passed_with_open_requirements", "claim ledger must keep open requirements")

    stages = [
        stage(
            "M0_candidate_supply",
            "Candidate task supply",
            0,
            "supported_non_experimental",
            [V2_AUDIT_PATH],
            counts_as_paper_evidence=False,
            counts_as_mobile_experiment=False,
            counts_as_baseline_result=False,
            can_be_reported_as="candidate task bank only",
            next_required_evidence=["human sampling review", "frozen subset promotion", "verifier/device evidence"],
        ),
        stage(
            "M1_t0_fixture_runs",
            "Deterministic T0 fixture evidence",
            1,
            "supported_t0_only",
            [REPRESENTATIVE_RUN_PATH, SMOKE_RUN_PATH],
            counts_as_paper_evidence=True,
            counts_as_mobile_experiment=False,
            counts_as_baseline_result=False,
            can_be_reported_as="offline fixture validation",
            next_required_evidence=["Android/iOS evidence for mobile-required tasks", "GitHub sandbox evidence"],
        ),
        stage(
            "M2_frozen_subset_planning",
            "Draft frozen paper subset planning",
            2,
            "supported_planning_only",
            [FROZEN_SUBSET_PATH, FROZEN_READINESS_PATH],
            counts_as_paper_evidence=False,
            counts_as_mobile_experiment=False,
            counts_as_baseline_result=False,
            can_be_reported_as="planned paper subset only",
            next_required_evidence=["T2/T3/T5 evidence attached per task", "final subset freeze"],
        ),
        stage(
            "M3_mobile_tier_readiness",
            "Mobile tier readiness probe",
            3,
            "supported_blocked_non_experimental",
            [MOBILE_READINESS_PATH],
            counts_as_paper_evidence=False,
            counts_as_mobile_experiment=False,
            counts_as_baseline_result=False,
            can_be_reported_as="environment readiness or blocker",
            next_required_evidence=["adb or Android device evidence", "xcrun/Xcode or iOS simulator evidence"],
        ),
        stage(
            "M4_baseline_protocol_contract",
            "Baseline protocol and result contract",
            4,
            "protocol_defined_no_results",
            [BASELINE_PROTOCOL_PATH, BASELINE_RUN_CONTRACT_PATH, BASELINE_DRY_RUN_MANIFEST_PATH],
            counts_as_paper_evidence=False,
            counts_as_mobile_experiment=False,
            counts_as_baseline_result=False,
            can_be_reported_as="baseline design and non-result dry run",
            next_required_evidence=["filled model lock", "transcripts", "artifacts", "verifier outputs"],
        ),
        stage(
            "M5_baseline_pilot_ready",
            "Baseline pilot ready but not counted",
            5,
            "pilot_ready_no_results",
            [BASELINE_PILOT_PACK_MANIFEST_PATH, BASELINE_PILOT_READINESS_PATH],
            counts_as_paper_evidence=False,
            counts_as_mobile_experiment=False,
            counts_as_baseline_result=False,
            can_be_reported_as="ready for non-counted baseline pilot",
            next_required_evidence=["execute pilot", "fill transcripts", "attach verifier outputs", "write baseline_result runs"],
        ),
        stage(
            "M6_counted_mobile_or_baseline_results",
            "Counted mobile or baseline results",
            6,
            "open_requirement",
            [CLAIM_LEDGER_PATH],
            counts_as_paper_evidence=False,
            counts_as_mobile_experiment=False,
            counts_as_baseline_result=False,
            can_be_reported_as="not yet available",
            next_required_evidence=[
                "real Android/iOS mobile-tier runs",
                "authorized GitHub sandbox runs",
                "baseline_result artifacts for all baselines",
            ],
        ),
    ]

    counted_mobile_stage_ids = [entry["id"] for entry in stages if entry["counts_as_mobile_experiment"]]
    counted_baseline_stage_ids = [entry["id"] for entry in stages if entry["counts_as_baseline_result"]]
    current_max_counted_level = max(
        (entry["maturity_level"] for entry in stages if entry["counts_as_paper_evidence"]),
        default=-1,
    )

    return {
        "report": "evidence-maturity-matrix",
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "status": "passed_with_open_requirements",
        "stage_count": len(stages),
        "max_stage_level": max(entry["maturity_level"] for entry in stages),
        "current_max_counted_paper_evidence_level": current_max_counted_level,
        "counted_mobile_stage_ids": counted_mobile_stage_ids,
        "counted_baseline_stage_ids": counted_baseline_stage_ids,
        "open_requirements": ["M6_counted_mobile_or_baseline_results"],
        "evidence_boundary": (
            "Only T0 fixture runs currently count as paper evidence, and they do not count as mobile "
            "experiments or baseline results. Mobile-tier and baseline comparison results remain open."
        ),
        "stages": stages,
    }


def write_markdown(matrix: dict[str, Any]) -> None:
    lines = [
        "# Evidence Maturity Matrix",
        "",
        f"Generated at: `{matrix['generated_at']}`",
        f"Status: `{matrix['status']}`",
        "",
        "## Evidence Boundary",
        "",
        matrix["evidence_boundary"],
        "",
        "## Stages",
        "",
        "| Level | Stage | Status | Paper evidence | Mobile experiment | Baseline result | Report as |",
        "| ---: | --- | --- | --- | --- | --- | --- |",
    ]
    for entry in matrix["stages"]:
        lines.append(
            "| {level} | {name} | {status} | {paper} | {mobile} | {baseline} | {report_as} |".format(
                level=entry["maturity_level"],
                name=entry["name"],
                status=entry["status"],
                paper=str(entry["counts_as_paper_evidence"]).lower(),
                mobile=str(entry["counts_as_mobile_experiment"]).lower(),
                baseline=str(entry["counts_as_baseline_result"]).lower(),
                report_as=entry["can_be_reported_as"],
            )
        )
    lines.extend(["", "## Open Requirements", ""])
    for requirement in matrix["open_requirements"]:
        lines.append(f"- `{requirement}`")
    lines.append("")
    REPORT_MD_PATH.write_text("\n".join(lines), encoding="utf-8", newline="")


def main() -> int:
    REPORTS_ROOT.mkdir(parents=True, exist_ok=True)
    matrix = build_matrix()
    REPORT_JSON_PATH.write_text(json.dumps(matrix, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_markdown(matrix)
    print("MobileHarnessBench evidence maturity matrix generated")
    print(f"report_json={rel(REPORT_JSON_PATH)}")
    print(f"report_md={rel(REPORT_MD_PATH)}")
    print(f"status={matrix['status']}")
    print(f"stage_count={matrix['stage_count']}")
    print(f"counted_mobile_stages={len(matrix['counted_mobile_stage_ids'])}")
    print(f"counted_baseline_stages={len(matrix['counted_baseline_stage_ids'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
