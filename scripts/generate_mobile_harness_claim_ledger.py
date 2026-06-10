#!/usr/bin/env python3
"""Generate a claim-to-evidence ledger for the Mobile Harness paper draft.

The ledger keeps paper-facing claims tied to concrete benchmark artifacts. It is
not a substitute for mobile-device experiments; it makes the current evidence
boundary explicit and machine-checkable.
"""

from __future__ import annotations

import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
BENCH_ROOT = ROOT / "docs" / "mobile-harness-benchmark"
REPORTS_ROOT = BENCH_ROOT / "reports"

V2_BANK_PATH = BENCH_ROOT / "tasks" / "v2-task-bank.json"
V2_AUDIT_PATH = REPORTS_ROOT / "v2-quality-audit.json"
REPRESENTATIVE_RUN_PATH = BENCH_ROOT / "runs" / "2026-06-06-v0-dry-run" / "run.json"
SMOKE_RUN_PATH = BENCH_ROOT / "runs" / "2026-06-06-smoke-v2-t0" / "run.json"
FROZEN_SUBSET_PATH = BENCH_ROOT / "tasks" / "frozen-v2-paper-subset.json"
FROZEN_READINESS_PATH = REPORTS_ROOT / "frozen-subset-readiness.json"
MOBILE_READINESS_PATH = REPORTS_ROOT / "mobile-tier-readiness.json"
BASELINE_PROTOCOL_PATH = REPORTS_ROOT / "baseline-protocol-readiness.json"
BASELINE_RUN_CONTRACT_PATH = REPORTS_ROOT / "baseline-run-contract.json"
BASELINE_DRY_RUN_MANIFEST_PATH = BENCH_ROOT / "baselines" / "2026-06-06-baseline-dry-run-t0" / "manifest.json"
BASELINE_PILOT_PACK_MANIFEST_PATH = BENCH_ROOT / "baselines" / "2026-06-06-baseline-pilot-pack" / "manifest.json"
BASELINE_PILOT_READINESS_PATH = REPORTS_ROOT / "baseline-pilot-readiness.json"

LEDGER_JSON_PATH = REPORTS_ROOT / "paper-claim-evidence-ledger.json"
LEDGER_MD_PATH = REPORTS_ROOT / "paper-claim-evidence-ledger.md"


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def load_json(path: Path) -> Any:
    if not path.exists():
        raise SystemExit(f"missing required evidence artifact: {rel(path)}")
    return json.loads(path.read_text(encoding="utf-8"))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"claim ledger generation failed: {message}")


def status_counts(run: dict[str, Any]) -> dict[str, int]:
    summary = run.get("summary", {})
    return {
        "total": int(summary.get("total", 0)),
        "passed": int(summary.get("passed", 0)),
        "blocked": int(summary.get("blocked", 0)),
        "failed": int(summary.get("failed", 0)),
        "warning": int(summary.get("warning", 0)),
    }


def claim(
    claim_id: str,
    paper_claim: str,
    status: str,
    evidence_artifacts: list[Path],
    validated_values: dict[str, Any],
    *,
    counts_as_paper_evidence: bool,
    counts_as_mobile_experiment: bool,
    limitation: str,
) -> dict[str, Any]:
    missing = [rel(path) for path in evidence_artifacts if not path.exists()]
    require(not missing, f"{claim_id} has missing artifacts: {missing}")
    return {
        "id": claim_id,
        "paper_claim": paper_claim,
        "status": status,
        "counts_as_paper_evidence": counts_as_paper_evidence,
        "counts_as_mobile_experiment": counts_as_mobile_experiment,
        "validated_values": validated_values,
        "evidence_artifacts": [rel(path) for path in evidence_artifacts],
        "limitation": limitation,
    }


def build_ledger() -> dict[str, Any]:
    v2_bank = load_json(V2_BANK_PATH)
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

    v2_tasks = v2_bank.get("tasks", [])
    require(len(v2_tasks) == 1000, "v2 task bank must contain 1000 tasks")
    category_count = dict(sorted(Counter(task.get("category") for task in v2_tasks).items()))
    require(v2_audit.get("status") == "passed_with_limits", "v2 audit must be passed_with_limits")
    failed_gates = v2_audit.get("failed_gates")
    require(isinstance(failed_gates, list) and not failed_gates, "v2 audit failed_gates must be an empty list")

    representative_counts = status_counts(representative_run)
    require(representative_counts == {"total": 5, "passed": 4, "blocked": 1, "failed": 0, "warning": 0},
            "representative-v0 counts changed")
    smoke_counts = status_counts(smoke_run)
    require(smoke_counts == {"total": 60, "passed": 50, "blocked": 10, "failed": 0, "warning": 0},
            "smoke-v2 T0 counts changed")

    frozen_tasks = frozen_subset.get("tasks", [])
    require(frozen_subset.get("status") == "draft_frozen_candidate", "frozen subset must stay draft")
    require(frozen_subset.get("counts_as_final_paper_subset") is False, "frozen subset must not count as final")
    require(len(frozen_tasks) == 60, "frozen subset must contain 60 tasks")
    frozen_category_count = dict(sorted(Counter(task.get("category") for task in frozen_tasks).items()))
    require(frozen_readiness.get("counts_as_final_paper_subset") is False,
            "frozen readiness must not count as final")

    require(mobile_readiness.get("counts_as_experiment") is False,
            "mobile readiness must be non-experimental")
    require(baseline_protocol.get("status") == "protocol_defined_no_results",
            "baseline protocol must be defined without results")
    require(baseline_protocol.get("counts_as_experiment") is False,
            "baseline protocol must be non-experimental")
    require(baseline_protocol.get("counts_as_baseline_result") is False,
            "baseline protocol must not count as baseline result")
    require(baseline_run_contract.get("status") == "contract_defined_no_results",
            "baseline run contract must be defined without results")
    require(baseline_run_contract.get("counts_as_baseline_result") is False,
            "baseline run contract must not count as baseline result")
    require(baseline_dry_run.get("status") == "dry_run_not_counted",
            "baseline dry run must be dry_run_not_counted")
    require(baseline_dry_run.get("counts_as_baseline_result") is False,
            "baseline dry run must not count as baseline result")
    require(baseline_dry_run.get("baseline_count") == 3,
            "baseline dry run must cover three baselines")
    require(baseline_pilot_pack.get("status") == "pilot_ready_no_results",
            "baseline pilot pack must be pilot_ready_no_results")
    require(baseline_pilot_pack.get("counts_as_baseline_result") is False,
            "baseline pilot pack must not count as baseline result")
    require(baseline_pilot_pack.get("baseline_count") == 3,
            "baseline pilot pack must cover three baselines")
    require(baseline_pilot_readiness.get("status") == "pilot_ready_no_results",
            "baseline pilot readiness must be pilot_ready_no_results")
    require(baseline_pilot_readiness.get("ready_for_counted_baseline_result") is False,
            "baseline pilot readiness must not be ready for counted result")
    tool_availability = mobile_readiness.get("tool_availability", {})
    readiness_status = {
        "android": mobile_readiness.get("android", {}).get("status"),
        "android_blocked_reason": mobile_readiness.get("android", {}).get("blocked_reason"),
        "ios": mobile_readiness.get("ios", {}).get("status"),
        "ios_blocked_reason": mobile_readiness.get("ios", {}).get("blocked_reason"),
    }

    claims = [
        claim(
            "v2_candidate_bank",
            "MobileHarnessBench v2 contains 1,000 differentiated candidate tasks across six categories.",
            "supported_non_experimental",
            [V2_BANK_PATH, V2_AUDIT_PATH],
            {
                "task_count": len(v2_tasks),
                "category_count": category_count,
                "audit_status": v2_audit.get("status"),
                "failed_gate_count": len(failed_gates),
            },
            counts_as_paper_evidence=False,
            counts_as_mobile_experiment=False,
            limitation="Candidate tasks are task supply, not completed experiments.",
        ),
        claim(
            "representative_v0_t0_run",
            "The five-task representative offline dry run produced four passed tasks and one blocked task.",
            "supported_t0_only",
            [REPRESENTATIVE_RUN_PATH],
            representative_counts,
            counts_as_paper_evidence=True,
            counts_as_mobile_experiment=False,
            limitation="T0 fixture evidence validates verifier machinery but not phone-device behavior.",
        ),
        claim(
            "smoke_v2_t0_run",
            "The 60-task smoke-v2 T0 run produced 50 passed tasks and 10 blocked GitHub-delivery tasks.",
            "supported_t0_only",
            [SMOKE_RUN_PATH],
            smoke_counts,
            counts_as_paper_evidence=True,
            counts_as_mobile_experiment=False,
            limitation="T0 fixture evidence is not Android/iOS mobile-tier evidence.",
        ),
        claim(
            "draft_frozen_paper_subset",
            "The draft frozen paper subset fixes 60 planned tasks but does not count as final paper evidence.",
            "supported_planning_only",
            [FROZEN_SUBSET_PATH, FROZEN_READINESS_PATH],
            {
                "task_count": len(frozen_tasks),
                "category_count": frozen_category_count,
                "counts_as_final_paper_subset": frozen_subset.get("counts_as_final_paper_subset"),
                "t0_result_count": frozen_readiness.get("t0_result_count"),
                "required_next_tier_count": frozen_readiness.get("required_next_tier_count"),
            },
            counts_as_paper_evidence=False,
            counts_as_mobile_experiment=False,
            limitation="Each task remains non-final until its required T2/T3/T5 evidence is attached.",
        ),
        claim(
            "mobile_tier_readiness",
            "The current local environment cannot claim Android/iOS mobile-tier results from this run.",
            "supported_blocked_non_experimental",
            [MOBILE_READINESS_PATH],
            {
                "counts_as_experiment": mobile_readiness.get("counts_as_experiment"),
                "tool_availability": tool_availability,
                "readiness_status": readiness_status,
            },
            counts_as_paper_evidence=False,
            counts_as_mobile_experiment=False,
            limitation="This is a readiness probe, not a mobile experiment.",
        ),
        {
            "id": "real_mobile_and_baseline_results",
            "paper_claim": "Real Android/iOS mobile-tier experiments and baseline comparisons remain open requirements.",
            "status": "open_requirement",
            "counts_as_paper_evidence": False,
            "counts_as_mobile_experiment": False,
            "validated_values": {
                "android_t2_completed": False,
                "ios_t3_completed": False,
                "github_t5_completed": False,
                "baseline_comparison_completed": False,
                "baseline_protocol_defined": True,
                "baseline_protocol_status": baseline_protocol.get("status"),
                "baseline_count": len(baseline_protocol.get("baselines", [])),
                "baseline_run_contract_defined": True,
                "baseline_run_contract_status": baseline_run_contract.get("status"),
                "baseline_run_contract_result_count": baseline_run_contract.get("result_count"),
                "baseline_dry_run_available": True,
                "baseline_dry_run_status": baseline_dry_run.get("status"),
                "baseline_dry_run_task_count_per_baseline": baseline_dry_run.get("task_count_per_baseline"),
                "baseline_dry_run_counts_as_result": baseline_dry_run.get("counts_as_baseline_result"),
                "baseline_pilot_pack_available": True,
                "baseline_pilot_pack_status": baseline_pilot_pack.get("status"),
                "baseline_pilot_pack_task_count_per_baseline": baseline_pilot_pack.get("task_count_per_baseline"),
                "baseline_pilot_pack_counts_as_result": baseline_pilot_pack.get("counts_as_baseline_result"),
                "baseline_pilot_readiness_status": baseline_pilot_readiness.get("status"),
                "baseline_pilot_ready_for_execution": baseline_pilot_readiness.get("ready_for_pilot_execution"),
                "baseline_pilot_ready_for_counted_result": baseline_pilot_readiness.get("ready_for_counted_baseline_result"),
            },
            "evidence_artifacts": [
                rel(MOBILE_READINESS_PATH),
                rel(BASELINE_PROTOCOL_PATH),
                rel(BASELINE_RUN_CONTRACT_PATH),
                rel(BASELINE_DRY_RUN_MANIFEST_PATH),
                rel(BASELINE_PILOT_PACK_MANIFEST_PATH),
                rel(BASELINE_PILOT_READINESS_PATH),
            ],
            "limitation": "The baseline protocol, run contract, one-task T0 dry run, pilot prompt/evidence pack and readiness gate are defined, but no final performance table should report baseline completion until counted run evidence is present.",
        },
    ]

    supported_claims = [entry for entry in claims if entry["status"] != "open_requirement"]
    open_requirements = [entry["id"] for entry in claims if entry["status"] == "open_requirement"]

    return {
        "report": "paper-claim-evidence-ledger",
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "status": "passed_with_open_requirements",
        "claim_count": len(claims),
        "supported_claim_count": len(supported_claims),
        "open_requirements": open_requirements,
        "evidence_boundary": (
            "T0 offline fixture results and draft planning manifests are separated from final mobile-tier "
            "experiments. Real Android/iOS/GitHub sandbox results remain unclaimed until their run artifacts exist."
        ),
        "claims": claims,
    }


def write_markdown(ledger: dict[str, Any]) -> None:
    lines = [
        "# Paper Claim Evidence Ledger",
        "",
        f"Generated at: `{ledger['generated_at']}`",
        f"Status: `{ledger['status']}`",
        "",
        "## Evidence Boundary",
        "",
        ledger["evidence_boundary"],
        "",
        "## Claims",
        "",
        "| Claim | Status | Paper evidence | Mobile experiment | Evidence boundary |",
        "| --- | --- | --- | --- | --- |",
    ]
    for entry in ledger["claims"]:
        lines.append(
            "| {id} | {status} | {paper} | {mobile} | {limitation} |".format(
                id=entry["id"],
                status=entry["status"],
                paper=str(entry["counts_as_paper_evidence"]).lower(),
                mobile=str(entry["counts_as_mobile_experiment"]).lower(),
                limitation=entry["limitation"].replace("|", "/"),
            )
        )
    lines.extend(["", "## Open Requirements", ""])
    for requirement in ledger["open_requirements"]:
        lines.append(f"- {requirement}")
    lines.append("")
    LEDGER_MD_PATH.write_text("\n".join(lines), encoding="utf-8", newline="")


def main() -> int:
    REPORTS_ROOT.mkdir(parents=True, exist_ok=True)
    ledger = build_ledger()
    LEDGER_JSON_PATH.write_text(json.dumps(ledger, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_markdown(ledger)
    print("MobileHarnessBench paper claim ledger generated")
    print(f"report_json={rel(LEDGER_JSON_PATH)}")
    print(f"report_md={rel(LEDGER_MD_PATH)}")
    print(f"status={ledger['status']}")
    print(f"claims={ledger['claim_count']}")
    print(f"open_requirements={len(ledger['open_requirements'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
