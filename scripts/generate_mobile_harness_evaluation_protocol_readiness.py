#!/usr/bin/env python3
"""Generate a machine-checkable readiness report for the E1-E5 protocol."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
BENCH_ROOT = ROOT / "docs" / "mobile-harness-benchmark"
TASKS_ROOT = BENCH_ROOT / "tasks"
RUNS_ROOT = BENCH_ROOT / "runs"
REPORTS_ROOT = BENCH_ROOT / "reports"
PAPER_ROOT = ROOT / "paper" / "iclr-mobile-harness"

MAIN_TEX_PATH = PAPER_ROOT / "main.tex"
SMOKE_TASK_SET_PATH = TASKS_ROOT / "smoke-v2.json"
ANDROID_TASK_SET_PATH = TASKS_ROOT / "android-device-v2.json"
IOS_TASK_SET_PATH = TASKS_ROOT / "ios-simulator-v2.json"
FROZEN_SUBSET_PATH = TASKS_ROOT / "frozen-v2-paper-subset.json"
SMOKE_RUN_PATH = RUNS_ROOT / "2026-06-06-smoke-v2-t0" / "run.json"
SMOKE_SUMMARY_PATH = RUNS_ROOT / "2026-06-06-smoke-v2-t0" / "summary.md"
SMOKE_TRACES_PATH = RUNS_ROOT / "2026-06-06-smoke-v2-t0" / "traces.jsonl"
MOBILE_TIER_READINESS_PATH = REPORTS_ROOT / "mobile-tier-readiness.json"
MOBILE_EVIDENCE_PACK_READINESS_PATH = REPORTS_ROOT / "mobile-evidence-pack-readiness.json"
BASELINE_PROTOCOL_PATH = REPORTS_ROOT / "baseline-protocol-readiness.json"
BASELINE_RUN_CONTRACT_PATH = REPORTS_ROOT / "baseline-run-contract.json"
BASELINE_PILOT_READINESS_PATH = REPORTS_ROOT / "baseline-pilot-readiness.json"

REPORT_JSON_PATH = REPORTS_ROOT / "evaluation-protocol-readiness.json"
REPORT_MD_PATH = REPORTS_ROOT / "evaluation-protocol-readiness.md"

METRICS = [
    "task_success",
    "verified_success",
    "trace_completeness",
    "recovery_rate",
    "artifact_availability",
    "human_intervention_count",
    "steps_to_completion",
]


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def load_json(path: Path) -> Any:
    if not path.exists():
        raise SystemExit(f"missing required artifact: {rel(path)}")
    return json.loads(path.read_text(encoding="utf-8"))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"evaluation protocol readiness generation failed: {message}")


def assert_main_tex_protocol() -> None:
    text = MAIN_TEX_PATH.read_text(encoding="utf-8")
    required_terms = [
        "E1: T0 smoke over v2",
        "E2: Android real-device subset",
        "E3: Mac iOS simulator subset",
        "E4: GitHub sandbox delivery",
        "E5: Baseline comparison",
        "artifact-bound",
        "promotion gate",
        "\\pi(t,r)",
        "\\mathrm{tier}(t,r)",
        "Primary metrics",
        "TaskSuccess",
        "VerifiedSuccess",
        "TraceCompleteness",
        "RecoveryRate",
        "ArtifactAvailability",
        "mean human interventions",
        "mean steps to completion",
        "counts\\_as\\_experiment=false",
        "scaffold\\_not\\_run",
        "dry\\_run\\_not\\_counted",
        "capture\\_ready\\_no\\_results",
        "pilot\\_ready\\_no\\_results",
    ]
    missing = [term for term in required_terms if term not in text]
    require(not missing, f"main.tex missing evaluation protocol terms: {missing}")


def task_set_summary(path: Path, expected_count: int) -> dict[str, Any]:
    payload = load_json(path)
    require(payload.get("task_count") == expected_count, f"{rel(path)} task_count must be {expected_count}")
    categories = payload.get("categories")
    require(isinstance(categories, dict) and categories, f"{rel(path)} missing categories")
    tasks = payload.get("tasks")
    require(isinstance(tasks, list) and len(tasks) == expected_count, f"{rel(path)} tasks length mismatch")
    return {
        "path": rel(path),
        "task_count": expected_count,
        "categories": categories,
    }


def smoke_run_summary() -> dict[str, Any]:
    payload = load_json(SMOKE_RUN_PATH)
    summary = payload.get("summary", {})
    require(payload.get("task_set") == "smoke-v2", "smoke run must bind to smoke-v2")
    require(payload.get("environment", {}).get("mode") == "offline_fixture_dry_run", "smoke run must be T0 offline")
    require(summary.get("total") == 60, "smoke run must contain 60 tasks")
    require(summary.get("passed") == 50, "smoke run must preserve 50 fixture passes")
    require(summary.get("blocked") == 10, "smoke run must preserve 10 typed blocks")
    require(summary.get("failed") == 0, "smoke run must preserve zero failures")
    results = payload.get("results")
    require(isinstance(results, list) and len(results) == 60, "smoke run results length mismatch")
    require(all(result.get("evidence", {}).get("counts_as_mobile_experiment") is False for result in results),
            "smoke results must not count as mobile experiments")
    github_results = [result for result in results if result.get("category") == "github_delivery"]
    require(len(github_results) == 10, "smoke run must contain ten GitHub-delivery tasks")
    require(all(result.get("status") == "blocked" for result in github_results),
            "T0 GitHub-delivery tasks must remain typed blocked cases")
    for artifact in (SMOKE_RUN_PATH, SMOKE_SUMMARY_PATH, SMOKE_TRACES_PATH):
        require(artifact.exists(), f"missing smoke artifact: {rel(artifact)}")
    return {
        "run_id": payload.get("run_id"),
        "summary": summary,
        "github_delivery_blocked": len(github_results),
        "evidence_artifacts": [rel(SMOKE_RUN_PATH), rel(SMOKE_SUMMARY_PATH), rel(SMOKE_TRACES_PATH)],
    }


def build_protocol(
    protocol_id: str,
    name: str,
    status: str,
    evidence_tier: str,
    counts_as_mobile_experiment: bool,
    counts_as_baseline_result: bool,
    evidence_artifacts: list[Path],
    summary: dict[str, Any],
    open_requirements: list[str],
) -> dict[str, Any]:
    missing = [rel(path) for path in evidence_artifacts if not path.exists()]
    require(not missing, f"{protocol_id} missing artifacts: {missing}")
    return {
        "id": protocol_id,
        "name": name,
        "status": status,
        "evidence_tier": evidence_tier,
        "counts_as_mobile_experiment": counts_as_mobile_experiment,
        "counts_as_baseline_result": counts_as_baseline_result,
        "evidence_artifacts": [rel(path) for path in evidence_artifacts],
        "summary": summary,
        "open_requirements": open_requirements,
    }


def build_report() -> dict[str, Any]:
    assert_main_tex_protocol()
    smoke_task_set = task_set_summary(SMOKE_TASK_SET_PATH, 60)
    android_task_set = task_set_summary(ANDROID_TASK_SET_PATH, 30)
    ios_task_set = task_set_summary(IOS_TASK_SET_PATH, 18)
    frozen_subset = load_json(FROZEN_SUBSET_PATH)
    smoke_run = smoke_run_summary()
    mobile_tier = load_json(MOBILE_TIER_READINESS_PATH)
    mobile_pack = load_json(MOBILE_EVIDENCE_PACK_READINESS_PATH)
    baseline_protocol = load_json(BASELINE_PROTOCOL_PATH)
    baseline_contract = load_json(BASELINE_RUN_CONTRACT_PATH)
    baseline_pilot = load_json(BASELINE_PILOT_READINESS_PATH)

    require(frozen_subset.get("task_count") == 60, "frozen subset must contain 60 tasks")
    require(frozen_subset.get("counts_as_final_paper_subset") is False,
            "frozen subset must remain draft until mobile/GitHub evidence is attached")
    require(mobile_tier.get("counts_as_experiment") is False, "mobile-tier readiness must be non-experimental")
    require(mobile_pack.get("status") == "capture_ready_no_results",
            "mobile evidence pack must be capture-ready with no results")
    require(mobile_pack.get("task_count") == 48, "mobile evidence pack must cover Android+iOS task sets")
    require(baseline_protocol.get("counts_as_baseline_result") is False,
            "baseline protocol must not count as a result")
    require(baseline_contract.get("result_count") == 0, "baseline contract must contain zero results")
    require(baseline_pilot.get("ready_for_pilot_execution") is True, "baseline pilot must be ready to execute")
    require(baseline_pilot.get("ready_for_counted_baseline_result") is False,
            "baseline pilot must not be counted")
    require(baseline_protocol.get("metrics") == METRICS, "baseline protocol metrics must match paper primary metrics")

    protocols = [
        build_protocol(
            "E1_t0_smoke_v2",
            "T0 smoke over v2",
            "counted_t0_fixture_evidence_available",
            "T0-offline-fixture",
            False,
            False,
            [SMOKE_TASK_SET_PATH, SMOKE_RUN_PATH, SMOKE_SUMMARY_PATH, SMOKE_TRACES_PATH],
            {"task_set": smoke_task_set, "run": smoke_run},
            ["replace_or_extend_with_mobile_tier_evidence_for_tasks_that_require_devices"],
        ),
        build_protocol(
            "E2_android_real_device_subset",
            "Android real-device subset",
            "capture_ready_no_results",
            "T2-android-real-device",
            False,
            False,
            [ANDROID_TASK_SET_PATH, MOBILE_TIER_READINESS_PATH, MOBILE_EVIDENCE_PACK_READINESS_PATH],
            {
                "task_set": android_task_set,
                "tool_status": mobile_tier.get("android", {}),
                "capture_pack_status": mobile_pack.get("status"),
            },
            ["execute_android_t2_real_device_run", "attach_device_metadata_screenshots_logs_traces_and_verifier_outputs"],
        ),
        build_protocol(
            "E3_ios_simulator_subset",
            "Mac iOS simulator subset",
            "capture_ready_no_results",
            "T3-ios-simulator",
            False,
            False,
            [IOS_TASK_SET_PATH, MOBILE_TIER_READINESS_PATH, MOBILE_EVIDENCE_PACK_READINESS_PATH],
            {
                "task_set": ios_task_set,
                "tool_status": mobile_tier.get("ios", {}),
                "capture_pack_status": mobile_pack.get("status"),
            },
            ["execute_ios_t3_simulator_run_on_mac", "attach_simulator_screenshots_logs_traces_and_verifier_outputs"],
        ),
        build_protocol(
            "E4_github_sandbox_delivery",
            "GitHub sandbox delivery",
            "protocol_defined_t0_blocked_no_remote_write",
            "T5-authorized-github-sandbox",
            False,
            False,
            [SMOKE_RUN_PATH, BASELINE_PROTOCOL_PATH],
            {
                "t0_github_delivery_blocked": smoke_run["github_delivery_blocked"],
                "required_future_evidence": [
                    "commit SHAs",
                    "Pages URLs",
                    "Actions run URLs",
                    "artifact metadata",
                    "typed blocked cases",
                ],
            },
            ["run_authorized_github_sandbox_delivery_tasks", "attach_public_safe_remote_evidence"],
        ),
        build_protocol(
            "E5_baseline_comparison",
            "Baseline comparison",
            "protocol_defined_pilot_ready_no_results",
            "T6-baseline-comparison",
            False,
            False,
            [FROZEN_SUBSET_PATH, BASELINE_PROTOCOL_PATH, BASELINE_RUN_CONTRACT_PATH, BASELINE_PILOT_READINESS_PATH],
            {
                "baseline_count": baseline_protocol.get("baselines") and len(baseline_protocol["baselines"]),
                "metrics": baseline_protocol.get("metrics"),
                "pilot_status": baseline_pilot.get("status"),
            },
            ["execute_counted_baseline_runs_with_locked_settings", "attach_transcripts_artifacts_verifiers_and_human_intervention_records"],
        ),
    ]
    open_requirements = sorted({item for protocol in protocols for item in protocol["open_requirements"]})
    return {
        "report": "evaluation-protocol-readiness",
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "status": "passed_with_open_requirements",
        "protocol_count": len(protocols),
        "evaluation_section_checked": True,
        "metric_contract_checked": True,
        "metric_count": len(METRICS),
        "counts_as_complete_evaluation": False,
        "ready_for_counted_mobile_experiment": False,
        "ready_for_counted_baseline_result": False,
        "counted_protocol_ids": ["E1_t0_smoke_v2"],
        "non_counted_protocol_ids": [protocol["id"] for protocol in protocols if protocol["id"] != "E1_t0_smoke_v2"],
        "primary_metrics": METRICS,
        "open_requirements": open_requirements,
        "evidence_boundary": (
            "The E1-E5 protocol is executable and artifact-bound, but only E1 has T0 fixture evidence. "
            "E2-E5 remain capture-ready or protocol-only and must not be reported as completed mobile or baseline experiments."
        ),
        "protocols": protocols,
    }


def write_markdown(report: dict[str, Any]) -> None:
    lines = [
        "# Evaluation Protocol Readiness",
        "",
        f"Generated at: `{report['generated_at']}`",
        f"Status: `{report['status']}`",
        f"Complete evaluation: `{str(report['counts_as_complete_evaluation']).lower()}`",
        "",
        "## Evidence Boundary",
        "",
        report["evidence_boundary"],
        "",
        "## Protocols",
        "",
        "| Protocol | Status | Evidence tier | Boundary |",
        "| --- | --- | --- | --- |",
    ]
    for protocol in report["protocols"]:
        boundary = "mobile=false; baseline=false"
        lines.append(
            f"| {protocol['name']} | `{protocol['status']}` | `{protocol['evidence_tier']}` | {boundary} |"
        )
    lines.extend(["", "## Primary Metrics", ""])
    lines.append(f"Metric contract checked: `{str(report['metric_contract_checked']).lower()}`")
    lines.append("")
    for metric in report["primary_metrics"]:
        lines.append(f"- `{metric}`")
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
    print("MobileHarnessBench evaluation protocol readiness generated")
    print(f"report_json={rel(REPORT_JSON_PATH)}")
    print(f"report_md={rel(REPORT_MD_PATH)}")
    print(f"status={report['status']}")
    print(f"protocols={report['protocol_count']}")
    print(f"metrics={report['metric_count']}")
    print(f"complete_evaluation={report['counts_as_complete_evaluation']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
