#!/usr/bin/env python3
"""Generate a single-task baseline dry run that is not counted as evidence."""

from __future__ import annotations

import json
import shutil
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
BENCH_ROOT = ROOT / "docs" / "mobile-harness-benchmark"
REPORTS_ROOT = BENCH_ROOT / "reports"
BASELINES_ROOT = BENCH_ROOT / "baselines"

BASELINE_PROTOCOL_PATH = REPORTS_ROOT / "baseline-protocol-readiness.json"
BASELINE_CONTRACT_PATH = REPORTS_ROOT / "baseline-run-contract.json"
FROZEN_SUBSET_PATH = BENCH_ROOT / "tasks" / "frozen-v2-paper-subset.json"
DRY_RUN_ROOT = BASELINES_ROOT / "2026-06-06-baseline-dry-run-t0"

METRIC_KEYS = [
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


def empty_metrics() -> dict[str, None]:
    return {key: None for key in METRIC_KEYS}


def dry_run_evidence(baseline_id: str) -> dict[str, list[str]]:
    return {
        "artifact_paths": [],
        "trace_paths": [],
        "screenshot_paths": [],
        "logs": [
            "baseline_dry_run_not_counted",
            "no_model_provider_selected",
            "no_device_execution",
            "no_github_sandbox_execution",
            f"baseline_id={baseline_id}",
        ],
        "verifier_outputs": [],
        "transcript_paths": [],
        "human_intervention_notes": [
            "dry_run_not_counted",
            "blocked_before_execution_to_preserve_evidence_boundary",
        ],
    }


def select_task(frozen_subset: dict[str, Any]) -> dict[str, Any]:
    tasks = frozen_subset.get("tasks", [])
    for task in tasks:
        if task.get("category") != "github_delivery" and task.get("requires_real_device") is False:
            return task
    for task in tasks:
        if task.get("category") != "github_delivery":
            return task
    raise SystemExit("no suitable non-github frozen task found")


def build_result(task: dict[str, Any], baseline_id: str) -> dict[str, Any]:
    return {
        "task_id": task["id"],
        "status": "blocked",
        "metrics": empty_metrics(),
        "evidence": dry_run_evidence(baseline_id),
        "counts_as_mobile_experiment": False,
    }


def build_run(baseline: dict[str, Any], selected_task: dict[str, Any]) -> dict[str, Any]:
    baseline_id = baseline["id"]
    return {
        "benchmark": "MobileHarnessBench",
        "schema_version": "0.1.0",
        "run_id": f"2026-06-06-baseline-dry-run-t0-{baseline_id}",
        "run_kind": "dry_run_not_counted",
        "task_subset": {
            "name": "baseline-single-task-t0",
            "path": rel(FROZEN_SUBSET_PATH),
            "task_count": 1,
        },
        "baseline_id": baseline_id,
        "environment": {
            "mode": "dry_run_not_counted",
            "model_provider": "not_selected",
            "model_name": "not_selected",
            "execution_tier": "T0-contract-dry-run",
            "device_profile": "not_collected",
            "authorization_state": "not_requested",
        },
        "counts_as_experiment": False,
        "counts_as_baseline_result": False,
        "summary": {
            "total": 1,
            "passed": 0,
            "failed": 0,
            "blocked": 1,
            "warning": 0,
            "not_run": 0,
            "metrics": empty_metrics(),
        },
        "results": [build_result(selected_task, baseline_id)],
        "evidence_boundary": (
            "This T0 baseline dry run exercises the baseline-run contract for one frozen-subset task only. "
            "It did not execute a model, mobile device, simulator, or GitHub sandbox and must not be "
            "reported as a baseline comparison or mobile experiment."
        ),
    }


def write_summary(path: Path, run: dict[str, Any], baseline: dict[str, Any], selected_task: dict[str, Any]) -> None:
    lines = [
        f"# Baseline Dry Run T0: {baseline['id']}",
        "",
        f"Run id: `{run['run_id']}`",
        "Status: `dry_run_not_counted`",
        "Counts as experiment: `false`",
        "Counts as baseline result: `false`",
        "",
        "## Selected Task",
        "",
        f"- Task id: `{selected_task['id']}`",
        f"- Category: `{selected_task['category']}`",
        f"- Required next tier: `{selected_task.get('required_next_tier', 'unknown')}`",
        "",
        "## Evidence Boundary",
        "",
        run["evidence_boundary"],
        "",
        "## Counts",
        "",
        "- Total: 1",
        "- Passed: 0",
        "- Failed: 0",
        "- Blocked: 1",
        "- Warning: 0",
        "- Not run: 0",
        "",
        "## Required Next Evidence",
        "",
        "- Select the actual model/provider and prompt contract.",
        "- Execute the baseline flow against the frozen subset under the same task conditions.",
        "- Attach transcripts, traces, artifacts, verifier outputs and human-intervention notes.",
        "- Keep `counts_as_baseline_result=false` until valid result evidence exists for all compared flows.",
        "",
    ]
    path.write_text("\n".join(lines), encoding="utf-8", newline="")


def write_traces(path: Path, run: dict[str, Any]) -> None:
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    result = run["results"][0]
    event = {
        "run_id": run["run_id"],
        "baseline_id": run["baseline_id"],
        "task_id": result["task_id"],
        "event": "baseline_dry_run_blocked_before_execution",
        "status": "blocked",
        "run_kind": "dry_run_not_counted",
        "counts_as_baseline_result": False,
        "counts_as_mobile_experiment": False,
        "generated_at": generated_at,
        "reason": "no model, device, simulator, or sandbox execution was performed",
    }
    path.write_text(json.dumps(event, ensure_ascii=False) + "\n", encoding="utf-8", newline="")


def main() -> int:
    protocol = load_json(BASELINE_PROTOCOL_PATH)
    contract = load_json(BASELINE_CONTRACT_PATH)
    frozen_subset = load_json(FROZEN_SUBSET_PATH)

    if protocol.get("status") != "protocol_defined_no_results":
        raise SystemExit("baseline protocol must be protocol_defined_no_results")
    if contract.get("status") != "contract_defined_no_results":
        raise SystemExit("baseline run contract must be contract_defined_no_results")
    if frozen_subset.get("counts_as_final_paper_subset") is not False:
        raise SystemExit("baseline dry run requires non-final frozen subset")

    selected_task = select_task(frozen_subset)

    if DRY_RUN_ROOT.exists():
        shutil.rmtree(DRY_RUN_ROOT)
    DRY_RUN_ROOT.mkdir(parents=True)

    baseline_dirs: list[str] = []
    for baseline in protocol.get("baselines", []):
        baseline_id = baseline["id"]
        run = build_run(baseline, selected_task)
        baseline_dir = DRY_RUN_ROOT / baseline_id
        baseline_dir.mkdir(parents=True)
        (baseline_dir / "baseline-run.json").write_text(
            json.dumps(run, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        write_summary(baseline_dir / "baseline-summary.md", run, baseline, selected_task)
        write_traces(baseline_dir / "baseline-traces.jsonl", run)
        baseline_dirs.append(rel(baseline_dir))

    manifest = {
        "report": "baseline-dry-run-t0-manifest",
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "status": "dry_run_not_counted",
        "counts_as_experiment": False,
        "counts_as_baseline_result": False,
        "baseline_count": len(baseline_dirs),
        "task_count_per_baseline": 1,
        "selected_task": {
            "id": selected_task["id"],
            "category": selected_task["category"],
            "required_next_tier": selected_task.get("required_next_tier"),
        },
        "baseline_dirs": baseline_dirs,
        "evidence_boundary": (
            "Generated T0 dry-run files exercise baseline result shape for one task only. They are blocked "
            "before execution and are not baseline performance results."
        ),
        "source_artifacts": [
            rel(BASELINE_PROTOCOL_PATH),
            rel(BASELINE_CONTRACT_PATH),
            rel(FROZEN_SUBSET_PATH),
        ],
    }
    (DRY_RUN_ROOT / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    lines = [
        "# Baseline Dry Run T0 Manifest",
        "",
        f"Generated at: `{manifest['generated_at']}`",
        "Status: `dry_run_not_counted`",
        "Counts as baseline result: `false`",
        "",
        manifest["evidence_boundary"],
        "",
        "## Selected Task",
        "",
        f"- `{selected_task['id']}` / `{selected_task['category']}` / `{selected_task.get('required_next_tier')}`",
        "",
        "## Baseline Directories",
        "",
        *[f"- `{item}`" for item in baseline_dirs],
        "",
    ]
    (DRY_RUN_ROOT / "README.md").write_text("\n".join(lines), encoding="utf-8", newline="")

    print("MobileHarnessBench baseline T0 dry run generated")
    print(f"dry_run_root={rel(DRY_RUN_ROOT)}")
    print(f"selected_task={selected_task['id']}")
    print(f"baselines={len(baseline_dirs)}")
    print("counts_as_baseline_result=False")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
