#!/usr/bin/env python3
"""Generate baseline-run scaffolds without reporting baseline results."""

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
SCAFFOLD_ROOT = BASELINES_ROOT / "2026-06-06-baseline-scaffold"

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


def empty_evidence() -> dict[str, list[str]]:
    return {
        "artifact_paths": [],
        "trace_paths": [],
        "screenshot_paths": [],
        "logs": [],
        "verifier_outputs": [],
        "transcript_paths": [],
        "human_intervention_notes": ["not_run_scaffold"],
    }


def build_result(task_id: str) -> dict[str, Any]:
    return {
        "task_id": task_id,
        "status": "not_run",
        "metrics": empty_metrics(),
        "evidence": empty_evidence(),
        "counts_as_mobile_experiment": False,
    }


def build_run(baseline: dict[str, Any], task_ids: list[str]) -> dict[str, Any]:
    baseline_id = baseline["id"]
    return {
        "benchmark": "MobileHarnessBench",
        "schema_version": "0.1.0",
        "run_id": f"2026-06-06-baseline-scaffold-{baseline_id}",
        "run_kind": "scaffold_not_run",
        "task_subset": {
            "name": "frozen-v2-paper-subset",
            "path": rel(FROZEN_SUBSET_PATH),
            "task_count": len(task_ids),
        },
        "baseline_id": baseline_id,
        "environment": {
            "mode": "scaffold_not_run",
            "model_provider": "not_selected",
            "model_name": "not_selected",
            "execution_tier": "not_run",
            "device_profile": "not_collected",
            "authorization_state": "not_requested",
        },
        "counts_as_experiment": False,
        "counts_as_baseline_result": False,
        "summary": {
            "total": len(task_ids),
            "passed": 0,
            "failed": 0,
            "blocked": 0,
            "warning": 0,
            "not_run": len(task_ids),
            "metrics": empty_metrics(),
        },
        "results": [build_result(task_id) for task_id in task_ids],
        "evidence_boundary": (
            "This baseline scaffold validates result shape only. It has not run any model, device, "
            "or GitHub sandbox flow and must not be reported as a baseline result."
        ),
    }


def write_summary(path: Path, run: dict[str, Any], baseline: dict[str, Any]) -> None:
    lines = [
        f"# Baseline Scaffold: {baseline['id']}",
        "",
        f"Run id: `{run['run_id']}`",
        "Status: `scaffold_not_run`",
        "",
        "## Evidence Boundary",
        "",
        run["evidence_boundary"],
        "",
        "## Counts",
        "",
        f"- Total: {run['summary']['total']}",
        "- Passed: 0",
        "- Failed: 0",
        "- Blocked: 0",
        "- Warning: 0",
        f"- Not run: {run['summary']['not_run']}",
        "",
        "## Required Next Evidence",
        "",
        "- Execute this baseline against the frozen subset.",
        "- Attach transcript, traces, artifacts, verifier outputs and human-intervention notes.",
        "- Keep `counts_as_baseline_result=false` until all required result artifacts exist.",
        "",
    ]
    path.write_text("\n".join(lines), encoding="utf-8", newline="")


def write_traces(path: Path, run: dict[str, Any]) -> None:
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    with path.open("w", encoding="utf-8", newline="") as handle:
        for result in run["results"]:
            event = {
                "run_id": run["run_id"],
                "baseline_id": run["baseline_id"],
                "task_id": result["task_id"],
                "event": "baseline_scaffold_not_run",
                "status": "not_run",
                "counts_as_baseline_result": False,
                "counts_as_mobile_experiment": False,
                "generated_at": generated_at,
            }
            handle.write(json.dumps(event, ensure_ascii=False) + "\n")


def main() -> int:
    protocol = load_json(BASELINE_PROTOCOL_PATH)
    contract = load_json(BASELINE_CONTRACT_PATH)
    frozen_subset = load_json(FROZEN_SUBSET_PATH)

    if protocol.get("status") != "protocol_defined_no_results":
        raise SystemExit("baseline protocol must be protocol_defined_no_results")
    if contract.get("status") != "contract_defined_no_results":
        raise SystemExit("baseline run contract must be contract_defined_no_results")
    if frozen_subset.get("counts_as_final_paper_subset") is not False:
        raise SystemExit("baseline scaffold requires non-final frozen subset")

    task_ids = [entry["id"] for entry in frozen_subset.get("tasks", [])]
    if len(task_ids) != 60:
        raise SystemExit(f"expected 60 draft frozen tasks; got {len(task_ids)}")

    if SCAFFOLD_ROOT.exists():
        shutil.rmtree(SCAFFOLD_ROOT)
    SCAFFOLD_ROOT.mkdir(parents=True)

    baseline_dirs: list[str] = []
    for baseline in protocol.get("baselines", []):
        baseline_id = baseline["id"]
        run = build_run(baseline, task_ids)
        baseline_dir = SCAFFOLD_ROOT / baseline_id
        baseline_dir.mkdir(parents=True)
        (baseline_dir / "baseline-run.json").write_text(
            json.dumps(run, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        write_summary(baseline_dir / "baseline-summary.md", run, baseline)
        write_traces(baseline_dir / "baseline-traces.jsonl", run)
        baseline_dirs.append(rel(baseline_dir))

    manifest = {
        "report": "baseline-scaffold-manifest",
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "status": "scaffold_not_run",
        "counts_as_experiment": False,
        "counts_as_baseline_result": False,
        "baseline_count": len(baseline_dirs),
        "task_count_per_baseline": len(task_ids),
        "baseline_dirs": baseline_dirs,
        "evidence_boundary": (
            "Generated scaffold files validate baseline result shape only. They are not baseline performance "
            "results and contain no model, device, or GitHub execution."
        ),
        "source_artifacts": [
            rel(BASELINE_PROTOCOL_PATH),
            rel(BASELINE_CONTRACT_PATH),
            rel(FROZEN_SUBSET_PATH),
        ],
    }
    (SCAFFOLD_ROOT / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    lines = [
        "# Baseline Scaffold Manifest",
        "",
        f"Generated at: `{manifest['generated_at']}`",
        "Status: `scaffold_not_run`",
        "",
        manifest["evidence_boundary"],
        "",
        "## Baseline Directories",
        "",
        *[f"- `{item}`" for item in baseline_dirs],
        "",
    ]
    (SCAFFOLD_ROOT / "README.md").write_text("\n".join(lines), encoding="utf-8", newline="")

    print("MobileHarnessBench baseline scaffold generated")
    print(f"scaffold_root={rel(SCAFFOLD_ROOT)}")
    print(f"baselines={len(baseline_dirs)}")
    print(f"task_count_per_baseline={len(task_ids)}")
    print("counts_as_baseline_result=False")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
