#!/usr/bin/env python3
"""Generate a readiness report for the baseline pilot pack."""

from __future__ import annotations

import csv
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
BENCH_ROOT = ROOT / "docs" / "mobile-harness-benchmark"
REPORTS_ROOT = BENCH_ROOT / "reports"
BASELINES_ROOT = BENCH_ROOT / "baselines"

BASELINE_PROTOCOL_PATH = REPORTS_ROOT / "baseline-protocol-readiness.json"
BASELINE_CONTRACT_PATH = REPORTS_ROOT / "baseline-run-contract.json"
PILOT_ROOT = BASELINES_ROOT / "2026-06-06-baseline-pilot-pack"
PILOT_MANIFEST_PATH = PILOT_ROOT / "manifest.json"
MODEL_LOCK_TEMPLATE_PATH = PILOT_ROOT / "model-lock-template.json"
HUMAN_INTERVENTION_SHEET_PATH = PILOT_ROOT / "human-intervention-sheet.csv"

REPORT_JSON_PATH = REPORTS_ROOT / "baseline-pilot-readiness.json"
REPORT_MD_PATH = REPORTS_ROOT / "baseline-pilot-readiness.md"

BASELINE_IDS = {
    "chat_only_mobile_coding_flow",
    "desktop_remote_ide_flow",
    "mobile_harness_flow",
}
HUMAN_INTERVENTION_COLUMNS = [
    "baseline_id",
    "task_id",
    "intervention_index",
    "actor_role",
    "trigger",
    "action_taken",
    "duration_seconds",
    "counts_as_human_intervention",
    "notes",
]
BLOCKED_BEFORE_COUNTING = [
    "model_lock_not_filled",
    "no_model_execution",
    "no_prompt_transcripts",
    "no_artifacts_or_blocked_outputs",
    "no_verifier_outputs",
    "no_baseline_result_runs",
]


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def load_json(path: Path) -> Any:
    if not path.exists():
        raise SystemExit(f"missing required artifact: {rel(path)}")
    return json.loads(path.read_text(encoding="utf-8"))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"baseline pilot readiness failed: {message}")


def inspect_pilot_pack() -> dict[str, Any]:
    protocol = load_json(BASELINE_PROTOCOL_PATH)
    contract = load_json(BASELINE_CONTRACT_PATH)
    manifest = load_json(PILOT_MANIFEST_PATH)
    model_lock = load_json(MODEL_LOCK_TEMPLATE_PATH)

    require(protocol.get("status") == "protocol_defined_no_results", "baseline protocol must define no results")
    require(contract.get("status") == "contract_defined_no_results", "baseline contract must define no results")
    require(manifest.get("status") == "pilot_ready_no_results", "pilot pack must be pilot_ready_no_results")
    require(manifest.get("counts_as_baseline_result") is False, "pilot pack must not count as a result")
    require(model_lock.get("status") == "template_not_filled", "model lock must remain template_not_filled")
    require(model_lock.get("counts_as_baseline_result") is False, "model lock must not count as a result")

    selected_task = manifest.get("selected_task", {})
    selected_task_id = selected_task.get("id")
    require(isinstance(selected_task_id, str) and selected_task_id, "selected task id is required")

    prompt_paths: list[str] = []
    evidence_template_paths: list[str] = []
    seen_baselines: set[str] = set()
    for pilot_dir_text in manifest.get("pilot_dirs", []):
        pilot_dir = ROOT / pilot_dir_text
        baseline_id = pilot_dir.name
        require(baseline_id in BASELINE_IDS, f"unknown baseline id: {baseline_id}")
        seen_baselines.add(baseline_id)
        prompt_path = pilot_dir / "prompt.md"
        evidence_path = pilot_dir / "evidence-template.json"
        require(prompt_path.exists(), f"missing prompt: {rel(prompt_path)}")
        require(evidence_path.exists(), f"missing evidence template: {rel(evidence_path)}")
        prompt_text = prompt_path.read_text(encoding="utf-8")
        require(baseline_id in prompt_text, f"prompt missing baseline id: {baseline_id}")
        require(selected_task_id in prompt_text, f"prompt missing selected task: {selected_task_id}")
        evidence = load_json(evidence_path)
        require(evidence.get("status") == "template_not_filled", f"{rel(evidence_path)} must be template_not_filled")
        require(evidence.get("counts_as_baseline_result") is False, f"{rel(evidence_path)} must not count")
        prompt_paths.append(rel(prompt_path))
        evidence_template_paths.append(rel(evidence_path))
    require(seen_baselines == BASELINE_IDS, f"pilot pack must cover all baselines: {sorted(seen_baselines)}")

    with HUMAN_INTERVENTION_SHEET_PATH.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        require(reader.fieldnames == HUMAN_INTERVENTION_COLUMNS, "human intervention sheet header mismatch")
        rows = list(reader)
    require({row.get("baseline_id") for row in rows} == BASELINE_IDS, "human intervention rows must cover baselines")
    require({row.get("task_id") for row in rows} == {selected_task_id}, "human intervention rows must use selected task")

    return {
        "selected_task": selected_task,
        "baseline_ids": sorted(seen_baselines),
        "prompt_paths": prompt_paths,
        "evidence_template_paths": evidence_template_paths,
        "model_lock_template": rel(MODEL_LOCK_TEMPLATE_PATH),
        "human_intervention_sheet": rel(HUMAN_INTERVENTION_SHEET_PATH),
        "source_artifacts": [
            rel(BASELINE_PROTOCOL_PATH),
            rel(BASELINE_CONTRACT_PATH),
            rel(PILOT_MANIFEST_PATH),
            rel(MODEL_LOCK_TEMPLATE_PATH),
            rel(HUMAN_INTERVENTION_SHEET_PATH),
        ],
    }


def build_report() -> dict[str, Any]:
    inspected = inspect_pilot_pack()
    return {
        "report": "baseline-pilot-readiness",
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "status": "pilot_ready_no_results",
        "counts_as_experiment": False,
        "counts_as_baseline_result": False,
        "baseline_count": len(inspected["baseline_ids"]),
        "task_count_per_baseline": 1,
        "selected_task": inspected["selected_task"],
        "ready_for_pilot_execution": True,
        "ready_for_counted_baseline_result": False,
        "readiness_checks": {
            "protocol_defined": True,
            "run_contract_defined": True,
            "prompt_template_count": len(inspected["prompt_paths"]),
            "evidence_template_count": len(inspected["evidence_template_paths"]),
            "model_lock_template_present": True,
            "human_intervention_sheet_present": True,
            "baseline_ids": inspected["baseline_ids"],
        },
        "blocked_before_counting": BLOCKED_BEFORE_COUNTING,
        "required_next_artifacts": [
            "filled model-lock.json",
            "prompt transcripts for every baseline",
            "artifact paths or explicit blocked-output evidence",
            "verifier outputs for every baseline",
            "filled human-intervention rows",
            "baseline_result run files for all baselines",
        ],
        "prompt_paths": inspected["prompt_paths"],
        "evidence_template_paths": inspected["evidence_template_paths"],
        "model_lock_template": inspected["model_lock_template"],
        "human_intervention_sheet": inspected["human_intervention_sheet"],
        "source_artifacts": inspected["source_artifacts"],
        "evidence_boundary": (
            "The pilot package is ready to execute a non-counted pilot, but it still contains no filled model "
            "lock, transcript, artifact, verifier output, or baseline_result run. It must not be reported as a "
            "baseline comparison."
        ),
    }


def write_markdown(report: dict[str, Any]) -> None:
    lines = [
        "# Baseline Pilot Readiness",
        "",
        f"Generated at: `{report['generated_at']}`",
        f"Status: `{report['status']}`",
        "Counts as baseline result: `false`",
        "",
        "## Evidence Boundary",
        "",
        report["evidence_boundary"],
        "",
        "## Selected Task",
        "",
        f"- `{report['selected_task']['id']}` / `{report['selected_task']['category']}`",
        "",
        "## Readiness Checks",
        "",
        f"- Baselines: {report['baseline_count']}",
        f"- Prompt templates: {report['readiness_checks']['prompt_template_count']}",
        f"- Evidence templates: {report['readiness_checks']['evidence_template_count']}",
        f"- Ready for non-counted pilot execution: `{str(report['ready_for_pilot_execution']).lower()}`",
        f"- Ready for counted baseline result: `{str(report['ready_for_counted_baseline_result']).lower()}`",
        "",
        "## Blocked Before Counting",
        "",
        *[f"- `{item}`" for item in report["blocked_before_counting"]],
        "",
    ]
    REPORT_MD_PATH.write_text("\n".join(lines), encoding="utf-8", newline="")


def main() -> int:
    REPORTS_ROOT.mkdir(parents=True, exist_ok=True)
    report = build_report()
    REPORT_JSON_PATH.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_markdown(report)
    print("MobileHarnessBench baseline pilot readiness generated")
    print(f"report_json={rel(REPORT_JSON_PATH)}")
    print(f"report_md={rel(REPORT_MD_PATH)}")
    print(f"status={report['status']}")
    print(f"ready_for_counted_baseline_result={report['ready_for_counted_baseline_result']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
