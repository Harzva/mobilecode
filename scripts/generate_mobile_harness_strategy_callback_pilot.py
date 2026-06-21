#!/usr/bin/env python3
"""Generate a non-counted callback-pilot artifact for strategy ablation.

P4c uses deterministic fake callbacks to exercise the run artifact shape. It is
not a model/device/tool benchmark result and must remain
strategy_pilot_not_counted.
"""

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
BOUNDARY = "pilot_not_counted"
RUN_KIND = "strategy_pilot_not_counted"


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


def relative_to_root(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def parse_strategy_ids(value: str | None, registry: dict[str, dict[str, Any]]) -> list[str]:
    if not value or value.strip().lower() == "all":
        return list(registry)
    strategy_ids = [part.strip() for part in value.split(",") if part.strip()]
    unknown = [strategy_id for strategy_id in strategy_ids if strategy_id not in registry]
    if unknown:
        raise SystemExit(f"Unknown strategy id(s): {', '.join(unknown)}")
    return strategy_ids


def strategy_family_for_run(strategies: list[dict[str, Any]]) -> str:
    families = {strategy["strategy_family"] for strategy in strategies}
    if len(families) == 1:
        return next(iter(families))
    return "mixed_strategy_ablation"


def union_tools(strategies: list[dict[str, Any]]) -> list[str]:
    tools: set[str] = set()
    for strategy in strategies:
        tools.update(strategy.get("allowed_tools", []))
    return sorted(tools)


def fake_time_metrics(strategy_index: int, task_index: int) -> dict[str, int]:
    planning = 20 + strategy_index * 7
    execution = 40 + task_index * 3 + strategy_index * 11
    verification = 15 + strategy_index * 5
    reporting = 10
    return {
        "planning_ms": planning,
        "execution_ms": execution,
        "verification_ms": verification,
        "reporting_ms": reporting,
        "wall_ms": planning + execution + verification + reporting,
    }


def fake_token_metrics(strategy_index: int, task_index: int) -> dict[str, float | int | None]:
    prompt = 120 + strategy_index * 25 + task_index * 3
    completion = 80 + strategy_index * 15 + task_index * 2
    tool = 30 + strategy_index * 8
    total = prompt + completion + tool
    return {
        "prompt_tokens": prompt,
        "completion_tokens": completion,
        "estimated_tool_io_tokens": tool,
        "total_tokens": total,
        "estimated_cost_usd": None,
        "tokens_per_verified_success": None,
    }


def fake_effect_metrics(strategy: dict[str, Any]) -> dict[str, float | int | None]:
    handoff_count = 1 if "handoff" in strategy.get("strategy_id", "") else 0
    if strategy.get("strategy_family") == "multi_agent_swarm":
        handoff_count = 2
    return {
        "task_success": None,
        "verified_success": None,
        "trace_completeness": 1.0,
        "artifact_availability": None,
        "recovery_rate": None,
        "human_intervention_count": 0,
        "handoff_success_rate": None,
        "memory_reuse_score": 0.25,
        "steps_to_completion": 3 + handoff_count,
    }


def build_trace_events(strategy_id: str, task_id: str) -> list[dict[str, Any]]:
    base = f"{strategy_id}/{task_id}"
    return [
        {
            "event_id": "evt_001",
            "type": "scaffold",
            "role": "CallbackPilotHarness",
            "step_id": None,
            "started_at": "2026-01-01T00:00:00Z",
            "ended_at": "2026-01-01T00:00:00Z",
            "tool_name": None,
            "evidence_id": None,
            "summary": f"P4c fake callback pilot initialized for {base}; non-counted.",
        },
        {
            "event_id": "evt_002",
            "type": "plan",
            "role": "PlannerAgent",
            "step_id": "step_001",
            "started_at": "2026-01-01T00:00:01Z",
            "ended_at": "2026-01-01T00:00:01Z",
            "tool_name": None,
            "evidence_id": f"fake_model_log_{strategy_id}_{task_id}",
            "summary": "Fake model callback produced a compact non-secret plan.",
        },
        {
            "event_id": "evt_003",
            "type": "think",
            "role": "CodeAgent",
            "step_id": "step_001",
            "started_at": "2026-01-01T00:00:02Z",
            "ended_at": "2026-01-01T00:00:02Z",
            "tool_name": None,
            "evidence_id": f"fake_model_step_{strategy_id}_{task_id}",
            "summary": "Fake model callback selected a fake tool action.",
        },
        {
            "event_id": "evt_004",
            "type": "act",
            "role": "CodeAgent",
            "step_id": "step_001",
            "started_at": "2026-01-01T00:00:03Z",
            "ended_at": "2026-01-01T00:00:03Z",
            "tool_name": "fake_callback_tool",
            "evidence_id": f"fake_tool_ev_{strategy_id}_{task_id}",
            "summary": "Fake tool callback returned scripted observation; no real tool executed.",
        },
        {
            "event_id": "evt_005",
            "type": "observe",
            "role": "CodeAgent",
            "step_id": "step_001",
            "started_at": "2026-01-01T00:00:04Z",
            "ended_at": "2026-01-01T00:00:04Z",
            "tool_name": None,
            "evidence_id": f"fake_tool_ev_{strategy_id}_{task_id}",
            "summary": "Fake observation captured for validator-compatible pilot artifact.",
        },
        {
            "event_id": "evt_006",
            "type": "verify",
            "role": "VerifierAgent",
            "step_id": "step_001",
            "started_at": "2026-01-01T00:00:05Z",
            "ended_at": "2026-01-01T00:00:05Z",
            "tool_name": None,
            "evidence_id": f"fake_verifier_ev_{strategy_id}_{task_id}",
            "summary": "Fake verifier callback marked artifact as non-counted warning, not verified success.",
        },
        {
            "event_id": "evt_007",
            "type": "report",
            "role": "ReporterAgent",
            "step_id": None,
            "started_at": "2026-01-01T00:00:06Z",
            "ended_at": "2026-01-01T00:00:06Z",
            "tool_name": None,
            "evidence_id": None,
            "summary": "P4c callback pilot completed; no formal comparison may be inferred.",
        },
    ]


def build_result(
    *,
    run_id: str,
    strategy: dict[str, Any],
    task: dict[str, Any],
    strategy_index: int,
    task_index: int,
) -> dict[str, Any]:
    strategy_id = strategy["strategy_id"]
    task_id = task["id"]
    trace_id = f"strace_{run_id}_{strategy_id}_{task_id}_p4c"
    trace_events = build_trace_events(strategy_id, task_id)
    return {
        "strategy_id": strategy_id,
        "strategy_family": strategy["strategy_family"],
        "task_id": task_id,
        "task_category": task.get("category", "unknown"),
        "status": "warning",
        "strategy_trace": {
            "trace_id": trace_id,
            "strategy_id": strategy_id,
            "trace_status": BOUNDARY,
            "events": trace_events,
            "handoff_count": 1 if strategy["strategy_family"] in {"multi_agent_handoff", "multi_agent_swarm"} else 0,
            "planning_revisions": 0,
            "verification_failures_recovered": 0,
            "failure_kind": "fake_callback_pilot_not_counted",
        },
        "time_metrics": fake_time_metrics(strategy_index, task_index),
        "token_metrics": fake_token_metrics(strategy_index, task_index),
        "effect_metrics": fake_effect_metrics(strategy),
        "evidence": {
            "boundary": BOUNDARY,
            "artifact_paths": [],
            "trace_paths": [f"callback_traces/{strategy_id}_{task_id}.json"],
            "screenshot_paths": [],
            "logs": [
                "P4c fake callback harness generated this pilot artifact.",
                "No real model, provider, tool, device, network, or verifier was used.",
                "Metrics are deterministic fake callback instrumentation and are not benchmark results.",
            ],
            "verifier_outputs": [f"fake_verifier_ev_{strategy_id}_{task_id}"],
            "transcript_paths": [],
            "human_intervention_notes": [],
        },
        "counts_as_strategy_ablation_result": False,
    }


def average_metric(results: list[dict[str, Any]], group: str, key: str) -> float | int | None:
    values = [result[group].get(key) for result in results if result[group].get(key) is not None]
    if not values:
        return None
    avg = sum(values) / len(values)
    return round(avg, 4) if isinstance(avg, float) and not avg.is_integer() else int(avg)


def metrics_summary(results: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    return {
        "time": {
            "planning_ms": average_metric(results, "time_metrics", "planning_ms"),
            "execution_ms": average_metric(results, "time_metrics", "execution_ms"),
            "verification_ms": average_metric(results, "time_metrics", "verification_ms"),
            "reporting_ms": average_metric(results, "time_metrics", "reporting_ms"),
            "wall_ms": average_metric(results, "time_metrics", "wall_ms"),
        },
        "tokens": {
            "prompt_tokens": average_metric(results, "token_metrics", "prompt_tokens"),
            "completion_tokens": average_metric(results, "token_metrics", "completion_tokens"),
            "estimated_tool_io_tokens": average_metric(results, "token_metrics", "estimated_tool_io_tokens"),
            "total_tokens": average_metric(results, "token_metrics", "total_tokens"),
            "estimated_cost_usd": None,
            "tokens_per_verified_success": None,
        },
        "effectiveness": {
            "task_success": None,
            "verified_success": None,
            "trace_completeness": average_metric(results, "effect_metrics", "trace_completeness"),
            "artifact_availability": None,
            "recovery_rate": None,
            "human_intervention_count": average_metric(results, "effect_metrics", "human_intervention_count"),
            "handoff_success_rate": None,
            "memory_reuse_score": average_metric(results, "effect_metrics", "memory_reuse_score"),
            "steps_to_completion": average_metric(results, "effect_metrics", "steps_to_completion"),
        },
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

    run_id = args.run_id or Path(args.output).name
    if len(run_id) < 8:
        raise SystemExit("run_id must be at least 8 characters")

    results = [
        build_result(
            run_id=run_id,
            strategy=strategy,
            task=task,
            strategy_index=strategy_index,
            task_index=task_index,
        )
        for strategy_index, strategy in enumerate(strategies)
        for task_index, task in enumerate(tasks)
    ]
    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    warning_count = len(results)
    return {
        "benchmark": "MobileHarnessBench",
        "schema_version": "0.1.0",
        "run_id": run_id,
        "generated_at": now,
        "run_kind": RUN_KIND,
        "strategy_id": strategies[0]["strategy_id"] if len(strategies) == 1 else "multi_strategy_callback_pilot",
        "strategy_family": strategy_family_for_run(strategies),
        "strategies": [
            {"strategy_id": strategy["strategy_id"], "strategy_family": strategy["strategy_family"]}
            for strategy in strategies
        ],
        "task_subset": {
            "name": task_doc.get("task_set", args.task_set),
            "path": relative_to_root(task_path),
            "task_count": len(tasks),
        },
        "environment": {
            "mode": RUN_KIND,
            "model_provider": "fake_callback_harness",
            "model_name": "fake-callback-model",
            "execution_tier": "T0-callback-pilot",
            "device_profile": "not_run",
            "authorization_state": "not_required",
            "runtime_backend": "fake_callbacks_only",
        },
        "model_lock": {
            "status": "fake_callback_locked",
            "model_provider": "fake_callback_harness",
            "model_name": "fake-callback-model",
            "temperature": 0,
            "top_p": 1,
            "notes": "Deterministic fake callback model; no provider/API call is made.",
        },
        "tool_access_policy": {
            "allowed_tools": union_tools(strategies),
            "blocked_tools": ["network", "real_device", "provider_api", "secrets", "shell", "filesystem_mutation"],
            "max_tool_calls": 0,
        },
        "prompt_budget": {
            "max_prompt_tokens": 4096,
            "max_completion_tokens": 1024,
            "max_total_tokens": 8192,
        },
        "max_steps": max(int(strategy.get("max_steps", 1)) for strategy in strategies),
        "counts_as_experiment": False,
        "summary": {
            "total": len(results),
            "strategies": len(strategies),
            "tasks_per_strategy": len(tasks),
            "passed": 0,
            "failed": 0,
            "blocked": 0,
            "warning": warning_count,
            "not_run": 0,
            "metrics": metrics_summary(results),
        },
        "results": results,
        "evidence_boundary": (
            "pilot_not_counted: P4c generated deterministic fake callback traces and metrics only. "
            "No real model, provider API, mobile device, network, tool action, screenshot, or verifier execution was performed. "
            "These artifacts are validator-compatible pilot scaffolds, not benchmark results."
        ),
    }


def write_outputs(output: str, run: dict[str, Any]) -> Path:
    output_dir = Path(output)
    if not output_dir.is_absolute():
        output_dir = ROOT / output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    trace_dir = output_dir / "callback_traces"
    trace_dir.mkdir(exist_ok=True)

    (output_dir / "run.json").write_text(json.dumps(run, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    for result in run["results"]:
        trace_path = trace_dir / f"{result['strategy_id']}_{result['task_id']}.json"
        trace_path.write_text(json.dumps(result["strategy_trace"], indent=2, sort_keys=True) + "\n", encoding="utf-8")

    write_summary(output_dir, run)
    write_task_matrix(output_dir, run)
    return output_dir


def write_summary(output_dir: Path, run: dict[str, Any]) -> None:
    lines = [
        f"# {run['run_id']} P4c Callback Pilot",
        "",
        f"- Run kind: `{run['run_kind']}`",
        f"- Counts as experiment: `{str(run['counts_as_experiment']).lower()}`",
        f"- Task subset: `{run['task_subset']['name']}` ({run['task_subset']['task_count']} tasks)",
        f"- Strategies: {', '.join(strategy['strategy_id'] for strategy in run['strategies'])}",
        f"- Results: {run['summary']['total']} fake callback pilot rows, all `warning` and non-counted",
        "",
        "## Evidence Boundary",
        "",
        run["evidence_boundary"],
        "",
        "No strategy ranking or benchmark claim should be inferred from this pilot artifact.",
        "",
    ]
    (output_dir / "summary.md").write_text("\n".join(lines), encoding="utf-8")


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
                "wall_ms",
                "total_tokens",
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
                    "wall_ms": result["time_metrics"]["wall_ms"],
                    "total_tokens": result["token_metrics"]["total_tokens"],
                    "counts_as_strategy_ablation_result": result["counts_as_strategy_ablation_result"],
                }
            )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--task-set", default="smoke-v2", help="Task set name or JSON path.")
    parser.add_argument(
        "--strategies",
        default="react_single_agent,plan_execute_verify_single_agent",
        help="Comma-separated strategy IDs, or 'all'.",
    )
    parser.add_argument(
        "--output",
        default="docs/mobile-harness-benchmark/strategy-ablation/runs/p4c-callback-pilot",
        help="Output directory.",
    )
    parser.add_argument("--run-id", default="p4c-callback-pilot", help="Run ID; must be at least 8 chars.")
    parser.add_argument("--max-tasks", type=int, default=3, help="Limit tasks for local callback pilot.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    run = build_run(args)
    output_dir = write_outputs(args.output, run)
    print(f"Wrote non-counted callback pilot to {relative_to_root(output_dir)}")
    print(f"Run kind: {run['run_kind']}; counted={run['counts_as_experiment']}")
    print(f"Strategies: {run['summary']['strategies']}; tasks_per_strategy={run['summary']['tasks_per_strategy']}; results={run['summary']['total']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
