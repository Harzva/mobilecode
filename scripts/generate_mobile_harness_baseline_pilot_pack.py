#!/usr/bin/env python3
"""Generate the baseline pilot prompt/evidence pack without reporting results."""

from __future__ import annotations

import csv
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
V2_TASK_BANK_PATH = BENCH_ROOT / "tasks" / "v2-task-bank.json"
PILOT_ROOT = BASELINES_ROOT / "2026-06-06-baseline-pilot-pack"
SELECTED_TASK_ID = "MH-CE-209"

MODEL_LOCK_FIELDS = [
    "model_provider",
    "model_name",
    "model_version_or_snapshot",
    "temperature",
    "max_tokens",
    "system_prompt_hash",
    "task_prompt_hash",
    "operator_label",
    "run_started_at",
    "run_environment",
]

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


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def load_json(path: Path) -> Any:
    if not path.exists():
        raise SystemExit(f"missing required artifact: {rel(path)}")
    return json.loads(path.read_text(encoding="utf-8"))


def select_task(frozen_subset: dict[str, Any], task_bank: dict[str, Any]) -> dict[str, Any]:
    frozen_ids = {entry["id"] for entry in frozen_subset.get("tasks", [])}
    if SELECTED_TASK_ID not in frozen_ids:
        raise SystemExit(f"{SELECTED_TASK_ID} is not in the frozen subset")
    tasks = {entry["id"]: entry for entry in task_bank.get("tasks", [])}
    if SELECTED_TASK_ID not in tasks:
        raise SystemExit(f"{SELECTED_TASK_ID} is not in the v2 task bank")
    return tasks[SELECTED_TASK_ID]


def prompt_for_baseline(baseline: dict[str, Any], task: dict[str, Any]) -> str:
    allowed_tools = "\n".join(f"- {item}" for item in baseline.get("allowed_tools", []))
    evidence_requirements = "\n".join(f"- {item}" for item in baseline.get("evidence_requirements", []))
    expected_artifacts = "\n".join(f"- {item}" for item in task.get("expected_artifacts", []))
    verifiers = "\n".join(f"- {item}" for item in task.get("verifiers", []))
    blocked_conditions = "\n".join(f"- {item}" for item in task.get("blocked_conditions", []))

    return f"""# Baseline Pilot Prompt: {baseline['id']}

Status: `pilot_ready_no_results`
Counts as baseline result: `false`

## Baseline

- Name: {baseline['name']}
- Unit under test: {baseline['unit_under_test']}
- Expected limit: {baseline['expected_limit']}

## Task

- Task id: `{task['id']}`
- Category: `{task['category']}`
- Title: {task['title']}
- Fixture: `{task['input_fixture']['path']}`

## User Goal

{task['user_goal']}

## Allowed Tools

{allowed_tools}

## Expected Artifacts

{expected_artifacts}

## Verifiers

{verifiers}

## Evidence To Capture

{evidence_requirements}
- exact model/provider lock
- full prompt transcript
- artifact paths or explicit blocked output
- verifier outputs or reason verifier could not run
- human intervention rows using `human-intervention-sheet.csv`

## Blocked Conditions

{blocked_conditions}
- missing model/provider lock
- missing transcript
- missing artifact or blocked-output explanation
- missing human-intervention annotation

## Counting Rule

Do not set `counts_as_baseline_result=true` until this prompt is executed with a filled model lock, transcript, artifacts or blocked-output evidence, verifier outputs, and human-intervention annotations.
"""


def build_model_lock_template(protocol: dict[str, Any], task: dict[str, Any]) -> dict[str, Any]:
    return {
        "report": "baseline-model-lock-template",
        "status": "template_not_filled",
        "counts_as_experiment": False,
        "counts_as_baseline_result": False,
        "task_id": task["id"],
        "baseline_ids": [baseline["id"] for baseline in protocol.get("baselines", [])],
        "required_fields": MODEL_LOCK_FIELDS,
        "placeholders": {field: "to_be_filled_before_run" for field in MODEL_LOCK_FIELDS},
        "evidence_boundary": (
            "This model lock is a template. It records no model execution and must not be used as a baseline result."
        ),
    }


def build_evidence_template(baseline: dict[str, Any], task: dict[str, Any]) -> dict[str, Any]:
    return {
        "report": "baseline-pilot-evidence-template",
        "status": "template_not_filled",
        "baseline_id": baseline["id"],
        "task_id": task["id"],
        "counts_as_experiment": False,
        "counts_as_baseline_result": False,
        "required_before_counting": [
            "filled model-lock.json",
            "full prompt transcript",
            "baseline-run.json with run_kind=baseline_result",
            "baseline-summary.md",
            "baseline-traces.jsonl",
            "artifact paths or explicit blocked output",
            "verifier outputs",
            "human-intervention annotations",
        ],
        "expected_artifacts": task.get("expected_artifacts", []),
        "verifiers": task.get("verifiers", []),
        "evidence_requirements": task.get("evidence_requirements", []),
        "blocked_conditions": task.get("blocked_conditions", []),
        "evidence_boundary": (
            "This file is an evidence template only. It does not contain a pilot result or baseline comparison."
        ),
    }


def write_human_intervention_sheet(path: Path, baselines: list[dict[str, Any]], task: dict[str, Any]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=HUMAN_INTERVENTION_COLUMNS)
        writer.writeheader()
        for baseline in baselines:
            writer.writerow(
                {
                    "baseline_id": baseline["id"],
                    "task_id": task["id"],
                    "intervention_index": "template",
                    "actor_role": "operator",
                    "trigger": "to_be_filled_before_run",
                    "action_taken": "to_be_filled_before_run",
                    "duration_seconds": "to_be_filled_before_run",
                    "counts_as_human_intervention": "to_be_filled_before_run",
                    "notes": "template_row_not_result",
                }
            )


def write_readme(path: Path, manifest: dict[str, Any]) -> None:
    lines = [
        "# Baseline Pilot Pack",
        "",
        f"Generated at: `{manifest['generated_at']}`",
        "Status: `pilot_ready_no_results`",
        "Counts as baseline result: `false`",
        "",
        manifest["evidence_boundary"],
        "",
        "## Selected Task",
        "",
        f"- `{manifest['selected_task']['id']}` / `{manifest['selected_task']['category']}`",
        "",
        "## Pilot Directories",
        "",
        *[f"- `{item}`" for item in manifest["pilot_dirs"]],
        "",
        "## Required Before Counting",
        "",
        "- Fill the model lock with provider, model, version, decoding parameters and prompt hashes.",
        "- Execute each baseline with the same task fixture and time budget.",
        "- Attach transcripts, artifacts or blocked-output evidence, verifier outputs and intervention rows.",
        "- Only then create `baseline_result` runs.",
        "",
    ]
    path.write_text("\n".join(lines), encoding="utf-8", newline="")


def main() -> int:
    protocol = load_json(BASELINE_PROTOCOL_PATH)
    contract = load_json(BASELINE_CONTRACT_PATH)
    frozen_subset = load_json(FROZEN_SUBSET_PATH)
    task_bank = load_json(V2_TASK_BANK_PATH)

    if protocol.get("status") != "protocol_defined_no_results":
        raise SystemExit("baseline protocol must be protocol_defined_no_results")
    if contract.get("status") != "contract_defined_no_results":
        raise SystemExit("baseline run contract must be contract_defined_no_results")
    if frozen_subset.get("counts_as_final_paper_subset") is not False:
        raise SystemExit("pilot pack requires non-final frozen subset")

    task = select_task(frozen_subset, task_bank)
    baselines = protocol.get("baselines", [])

    if PILOT_ROOT.exists():
        shutil.rmtree(PILOT_ROOT)
    PILOT_ROOT.mkdir(parents=True)

    pilot_dirs: list[str] = []
    for baseline in baselines:
        baseline_dir = PILOT_ROOT / baseline["id"]
        baseline_dir.mkdir(parents=True)
        (baseline_dir / "prompt.md").write_text(prompt_for_baseline(baseline, task), encoding="utf-8", newline="")
        (baseline_dir / "evidence-template.json").write_text(
            json.dumps(build_evidence_template(baseline, task), ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        lines = [
            f"# Baseline Pilot: {baseline['id']}",
            "",
            "This folder is ready for a future pilot run but contains no result.",
            "",
            "- `prompt.md`: locked task prompt and baseline constraints.",
            "- `evidence-template.json`: required evidence before any counted baseline result.",
            "",
        ]
        (baseline_dir / "README.md").write_text("\n".join(lines), encoding="utf-8", newline="")
        pilot_dirs.append(rel(baseline_dir))

    model_lock = build_model_lock_template(protocol, task)
    (PILOT_ROOT / "model-lock-template.json").write_text(
        json.dumps(model_lock, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    write_human_intervention_sheet(PILOT_ROOT / "human-intervention-sheet.csv", baselines, task)

    manifest = {
        "report": "baseline-pilot-pack-manifest",
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "status": "pilot_ready_no_results",
        "counts_as_experiment": False,
        "counts_as_baseline_result": False,
        "baseline_count": len(pilot_dirs),
        "task_count_per_baseline": 1,
        "selected_task": {
            "id": task["id"],
            "category": task["category"],
            "fixture": task["input_fixture"]["path"],
            "required_capabilities": task.get("required_capabilities", []),
        },
        "model_lock_template": rel(PILOT_ROOT / "model-lock-template.json"),
        "human_intervention_sheet": rel(PILOT_ROOT / "human-intervention-sheet.csv"),
        "pilot_dirs": pilot_dirs,
        "source_artifacts": [
            rel(BASELINE_PROTOCOL_PATH),
            rel(BASELINE_CONTRACT_PATH),
            rel(FROZEN_SUBSET_PATH),
            rel(V2_TASK_BANK_PATH),
        ],
        "evidence_boundary": (
            "This pilot pack locks prompts and evidence templates for future baseline execution. It contains "
            "no model execution, no device execution, no transcript, and no baseline result."
        ),
    }
    (PILOT_ROOT / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    write_readme(PILOT_ROOT / "README.md", manifest)

    print("MobileHarnessBench baseline pilot pack generated")
    print(f"pilot_root={rel(PILOT_ROOT)}")
    print(f"selected_task={task['id']}")
    print(f"baselines={len(pilot_dirs)}")
    print("counts_as_baseline_result=False")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
