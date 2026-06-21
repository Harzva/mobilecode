#!/usr/bin/env python3
"""Generate a non-counted MobileHarnessBench strategy ablation scaffold run."""

from __future__ import annotations

import argparse
import csv
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
BENCH_ROOT = ROOT / "docs" / "mobile-harness-benchmark"
REGISTRY_PATH = BENCH_ROOT / "strategy-ablation" / "strategy_registry.json"
TASKS_DIR = BENCH_ROOT / "tasks"

BOUNDARY_BY_KIND = {
    "strategy_scaffold_not_run": "scaffold_not_run",
    "strategy_dry_run_not_counted": "dry_run_not_counted",
    "strategy_pilot_not_counted": "pilot_not_counted",
}

NULL_TIME_METRICS = {
    "planning_ms": None,
    "execution_ms": None,
    "verification_ms": None,
    "reporting_ms": None,
    "wall_ms": None,
}

NULL_TOKEN_METRICS = {
    "prompt_tokens": None,
    "completion_tokens": None,
    "estimated_tool_io_tokens": None,
    "total_tokens": None,
    "estimated_cost_usd": None,
    "tokens_per_verified_success": None,
}

NULL_EFFECT_METRICS = {
    "task_success": None,
    "verified_success": None,
    "trace_completeness": None,
    "artifact_availability": None,
    "recovery_rate": None,
    "human_intervention_count": None,
    "handoff_success_rate": None,
    "memory_reuse_score": None,
    "steps_to_completion": None,
}


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise SystemExit(f"Expected JSON object: {path}")
    return data


def resolve_task_set(name_or_path: str) -> tuple[Path, dict[str, Any]]:
    candidate = Path(name_or_path)
    if not candidate.suffix:
        candidate = TASKS_DIR / f"{name_or_path}.json"
    elif not candidate.is_absolute():
        candidate = ROOT / candidate

    if not candidate.exists():
        raise SystemExit(f"Task set not found: {candidate}")
    return candidate, load_json(candidate)


def parse_strategy_ids(value: str | None, registry: dict[str, dict[str, Any]]) -> list[str]:
    if not value or value.strip().lower() == "all":
        return list(registry)
    strategy_ids = [part.strip() for part in value.split(",") if part.strip()]
    unknown = [strategy_id for strategy_id in strategy_ids if strategy_id not in registry]
    if unknown:
        raise SystemExit(f"Unknown strategy id(s): {', '.join(unknown)}")
    return strategy_ids


def relative_to_root(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def union_tools(strategies: list[dict[str, Any]]) -> list[str]:
    tools: set[str] = set()
    for strategy in strategies:
        tools.update(strategy.get("allowed_tools", []))
    return sorted(tools)


def strategy_family_for_run(strategies: list[dict[str, Any]]) -> str:
    families = {strategy["strategy_family"] for strategy in strategies}
    if len(families) == 1:
        return next(iter(families))
    return "mixed_strategy_ablation"


def build_result(
    *,
    run_id: str,
    run_kind: str,
    boundary: str,
    strategy: dict[str, Any],
    task: dict[str, Any],
) -> dict[str, Any]:
    strategy_id = strategy["strategy_id"]
    task_id = task["id"]
    trace_id = f"strace_{run_id}_{strategy_id}_{task_id}"
    return {
        "strategy_id": strategy_id,
        "strategy_family": strategy["strategy_family"],
        "task_id": task_id,
        "task_category": task.get("category", "unknown"),
        "status": "not_run",
        "strategy_trace": {
            "trace_id": trace_id,
            "strategy_id": strategy_id,
            "trace_status": boundary,
            "events": [
                {
                    "event_id": "evt_001",
                    "type": "scaffold",
                    "role": "scaffold_runner",
                    "step_id": None,
                    "started_at": None,
                    "ended_at": None,
                    "tool_name": None,
                    "evidence_id": None,
                    "summary": f"{run_kind}: no model, tool, device, network, or verifier execution was performed.",
                }
            ],
            "handoff_count": 0,
            "planning_revisions": 0,
            "verification_failures_recovered": 0,
            "failure_kind": None,
        },
        "time_metrics": dict(NULL_TIME_METRICS),
        "token_metrics": dict(NULL_TOKEN_METRICS),
        "effect_metrics": dict(NULL_EFFECT_METRICS),
        "evidence": {
            "boundary": boundary,
            "artifact_paths": [],
            "trace_paths": [],
            "screenshot_paths": [],
            "logs": [
                "R1 scaffold runner did not call an LLM, device, network, shell task, or verifier.",
                "This result is a task-strategy matrix placeholder only.",
            ],
            "verifier_outputs": [],
            "transcript_paths": [],
            "human_intervention_notes": [],
        },
        "counts_as_strategy_ablation_result": False,
    }


def build_run(args: argparse.Namespace) -> dict[str, Any]:
    registry_doc = load_json(REGISTRY_PATH)
    registry = {
        strategy["strategy_id"]: strategy
        for strategy in registry_doc.get("strategies", [])
        if isinstance(strategy, dict) and "strategy_id" in strategy
    }
    strategy_ids = parse_strategy_ids(args.strategies, registry)
    strategies = [registry[strategy_id] for strategy_id in strategy_ids]

    task_path, task_doc = resolve_task_set(args.task_set)
    tasks = task_doc.get("tasks", [])
    if not isinstance(tasks, list) or not tasks:
        raise SystemExit(f"Task set has no tasks: {task_path}")
    if args.max_tasks is not None:
        tasks = tasks[: args.max_tasks]

    run_kind = "strategy_dry_run_not_counted" if args.dry_run else args.run_kind
    if run_kind == "strategy_ablation_result":
        raise SystemExit("This scaffold runner cannot generate counted strategy_ablation_result runs.")
    boundary = BOUNDARY_BY_KIND[run_kind]

    output = Path(args.output)
    run_id = args.run_id or output.name
    if len(run_id) < 8:
        raise SystemExit("run_id must be at least 8 characters")

    results = [
        build_result(
            run_id=run_id,
            run_kind=run_kind,
            boundary=boundary,
            strategy=strategy,
            task=task,
        )
        for strategy in strategies
        for task in tasks
    ]

    run_family = strategy_family_for_run(strategies)
    run_strategy_id = strategies[0]["strategy_id"] if len(strategies) == 1 else "multi_strategy_comparison"
    max_steps = max(int(strategy.get("max_steps", 1)) for strategy in strategies)
    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat()

    return {
        "benchmark": "MobileHarnessBench",
        "schema_version": "0.1.0",
        "run_id": run_id,
        "generated_at": now,
        "run_kind": run_kind,
        "strategy_id": run_strategy_id,
        "strategy_family": run_family,
        "strategies": [
            {
                "strategy_id": strategy["strategy_id"],
                "strategy_family": strategy["strategy_family"],
            }
            for strategy in strategies
        ],
        "task_subset": {
            "name": task_doc.get("task_set", args.task_set),
            "path": relative_to_root(task_path),
            "task_count": len(tasks),
        },
        "environment": {
            "mode": run_kind,
            "model_provider": "not_locked",
            "model_name": "not_run",
            "execution_tier": "T0-scaffold",
            "device_profile": "not_run",
            "authorization_state": "not_required",
            "runtime_backend": "none",
        },
        "model_lock": {
            "status": "not_locked_scaffold",
            "model_provider": "not_locked",
            "model_name": "not_run",
            "temperature": None,
            "top_p": None,
            "notes": "No model call is made by the R1 scaffold runner.",
        },
        "tool_access_policy": {
            "allowed_tools": union_tools(strategies),
            "blocked_tools": ["network", "real_device", "provider_api", "secrets"],
            "max_tool_calls": 0,
        },
        "prompt_budget": {
            "max_prompt_tokens": None,
            "max_completion_tokens": None,
            "max_total_tokens": None,
        },
        "max_steps": max_steps,
        "counts_as_experiment": False,
        "summary": {
            "total": len(results),
            "strategies": len(strategies),
            "tasks_per_strategy": len(tasks),
            "passed": 0,
            "failed": 0,
            "blocked": 0,
            "warning": 0,
            "not_run": len(results),
            "metrics": {
                "time": dict(NULL_TIME_METRICS),
                "tokens": dict(NULL_TOKEN_METRICS),
                "effectiveness": dict(NULL_EFFECT_METRICS),
            },
        },
        "results": results,
        "evidence_boundary": (
            f"{boundary}: R1 generated only a task-strategy scaffold. "
            "It did not run a model, phone, emulator, verifier, network call, or tool action."
        ),
    }


def write_summary(output_dir: Path, run: dict[str, Any]) -> None:
    strategies = ", ".join(strategy["strategy_id"] for strategy in run["strategies"])
    lines = [
        f"# {run['run_id']} Strategy Scaffold",
        "",
        f"- Run kind: `{run['run_kind']}`",
        f"- Counts as experiment: `{str(run['counts_as_experiment']).lower()}`",
        f"- Task subset: `{run['task_subset']['name']}` ({run['task_subset']['task_count']} tasks)",
        f"- Strategies: {strategies}",
        f"- Results: {run['summary']['total']} placeholders, all `not_run`",
        "",
        "## Evidence Boundary",
        "",
        run["evidence_boundary"],
        "",
        "No performance comparison should be inferred from this scaffold.",
        "",
    ]
    (output_dir / "summary.md").write_text("\n".join(lines), encoding="utf-8")


def write_strategy_table(output_dir: Path, run: dict[str, Any]) -> None:
    lines = [
        "# Strategy Comparison Table",
        "",
        "| Strategy | Family | Tasks | Status | Counted |",
        "| --- | --- | ---: | --- | --- |",
    ]
    task_count = run["task_subset"]["task_count"]
    for strategy in run["strategies"]:
        lines.append(
            f"| `{strategy['strategy_id']}` | `{strategy['strategy_family']}` | "
            f"{task_count} | `not_run` | `false` |"
        )
    lines.extend(["", "All rows are scaffold placeholders."])
    (output_dir / "strategy_comparison_table.md").write_text("\n".join(lines), encoding="utf-8")


def write_task_matrix(output_dir: Path, run: dict[str, Any]) -> None:
    with (output_dir / "task_strategy_matrix.csv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "task_id",
                "task_category",
                "strategy_id",
                "strategy_family",
                "status",
                "counts_as_strategy_ablation_result",
            ],
        )
        writer.writeheader()
        for result in run["results"]:
            writer.writerow(
                {
                    "task_id": result["task_id"],
                    "task_category": result["task_category"],
                    "strategy_id": result["strategy_id"],
                    "strategy_family": result["strategy_family"],
                    "status": result["status"],
                    "counts_as_strategy_ablation_result": result["counts_as_strategy_ablation_result"],
                }
            )


def write_outputs(output: str, run: dict[str, Any]) -> Path:
    output_dir = Path(output)
    if not output_dir.is_absolute():
        output_dir = ROOT / output_dir
    output_dir.mkdir(parents=True, exist_ok=True)

    (output_dir / "run.json").write_text(
        json.dumps(run, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    write_summary(output_dir, run)
    write_strategy_table(output_dir, run)
    write_task_matrix(output_dir, run)
    return output_dir


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--task-set", default="smoke-v2", help="Task set name or JSON path.")
    parser.add_argument(
        "--strategies",
        default="all",
        help="Comma-separated strategy IDs, or 'all'.",
    )
    parser.add_argument(
        "--run-kind",
        default="strategy_scaffold_not_run",
        choices=[
            "strategy_scaffold_not_run",
            "strategy_dry_run_not_counted",
            "strategy_pilot_not_counted",
            "strategy_ablation_result",
        ],
    )
    parser.add_argument(
        "--output",
        default="docs/mobile-harness-benchmark/strategy-ablation/runs/r1-scaffold",
        help="Output directory.",
    )
    parser.add_argument("--run-id", default=None, help="Optional run_id override.")
    parser.add_argument("--max-tasks", type=int, default=None, help="Limit tasks for local smoke checks.")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Alias for --run-kind strategy_dry_run_not_counted.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    run = build_run(args)
    output_dir = write_outputs(args.output, run)
    print(f"Wrote non-counted strategy scaffold to {relative_to_root(output_dir)}")
    print(f"Results: {run['summary']['total']} placeholders; counted=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
