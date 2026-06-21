#!/usr/bin/env python3
"""Validate a MobileHarnessBench strategy ablation registry and run file."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]

REQUIRED_STRATEGY_FIELDS = {
    "strategy_id",
    "strategy_family",
    "description",
    "agent_roles",
    "reasoning_loop",
    "allowed_tools",
    "max_steps",
    "max_handoffs",
    "verification_policy",
    "memory_policy",
    "handoff_policy",
    "expected_overhead",
    "primary_comparison_targets",
}

ALLOWED_FAMILIES = {
    "single_agent_reasoning",
    "single_agent_with_verifier",
    "multi_agent_handoff",
    "multi_agent_swarm",
}

ALLOWED_RUN_FAMILIES = ALLOWED_FAMILIES | {"mixed_strategy_ablation"}

ALLOWED_RUN_KINDS = {
    "strategy_scaffold_not_run",
    "strategy_dry_run_not_counted",
    "strategy_pilot_not_counted",
    "strategy_ablation_result",
}

BOUNDARY_BY_KIND = {
    "strategy_scaffold_not_run": "scaffold_not_run",
    "strategy_dry_run_not_counted": "dry_run_not_counted",
    "strategy_pilot_not_counted": "pilot_not_counted",
}

ALLOWED_STATUS = {"passed", "warning", "failed", "blocked", "not_run"}

TIME_KEYS = {"planning_ms", "execution_ms", "verification_ms", "reporting_ms", "wall_ms"}
TOKEN_KEYS = {
    "prompt_tokens",
    "completion_tokens",
    "estimated_tool_io_tokens",
    "total_tokens",
    "estimated_cost_usd",
    "tokens_per_verified_success",
}
EFFECT_KEYS = {
    "task_success",
    "verified_success",
    "trace_completeness",
    "artifact_availability",
    "recovery_rate",
    "human_intervention_count",
    "handoff_success_rate",
    "memory_reuse_score",
    "steps_to_completion",
}


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError(f"Expected JSON object: {path}")
    return data


def resolve_path(value: str) -> Path:
    path = Path(value)
    if not path.is_absolute():
        path = ROOT / path
    return path


def require(condition: bool, message: str, errors: list[str]) -> None:
    if not condition:
        errors.append(message)


def all_null(values: dict[str, Any]) -> bool:
    return all(value is None for value in values.values())


def validate_registry(registry: dict[str, Any], errors: list[str]) -> dict[str, dict[str, Any]]:
    strategies = registry.get("strategies")
    require(isinstance(strategies, list) and bool(strategies), "registry.strategies must be a non-empty list", errors)
    if not isinstance(strategies, list):
        return {}

    by_id: dict[str, dict[str, Any]] = {}
    for index, strategy in enumerate(strategies):
        if not isinstance(strategy, dict):
            errors.append(f"registry.strategies[{index}] is not an object")
            continue
        missing = REQUIRED_STRATEGY_FIELDS - strategy.keys()
        if missing:
            errors.append(f"{strategy.get('strategy_id', index)} missing fields: {sorted(missing)}")
        strategy_id = strategy.get("strategy_id")
        if not isinstance(strategy_id, str) or not strategy_id:
            errors.append(f"registry.strategies[{index}] has invalid strategy_id")
            continue
        if strategy_id in by_id:
            errors.append(f"duplicate strategy_id: {strategy_id}")
        by_id[strategy_id] = strategy
        require(strategy.get("strategy_family") in ALLOWED_FAMILIES, f"{strategy_id} has invalid strategy_family", errors)
        require(isinstance(strategy.get("agent_roles"), list), f"{strategy_id}.agent_roles must be a list", errors)
        require(isinstance(strategy.get("reasoning_loop"), list), f"{strategy_id}.reasoning_loop must be a list", errors)
        require(isinstance(strategy.get("allowed_tools"), list), f"{strategy_id}.allowed_tools must be a list", errors)
        require(isinstance(strategy.get("max_steps"), int) and strategy.get("max_steps", 0) > 0, f"{strategy_id}.max_steps invalid", errors)
        require(isinstance(strategy.get("max_handoffs"), int) and strategy.get("max_handoffs", -1) >= 0, f"{strategy_id}.max_handoffs invalid", errors)
    return by_id


def validate_metric_object(name: str, value: Any, expected_keys: set[str], errors: list[str]) -> None:
    if not isinstance(value, dict):
        errors.append(f"{name} must be an object")
        return
    missing = expected_keys - value.keys()
    extra = value.keys() - expected_keys
    if missing:
        errors.append(f"{name} missing keys: {sorted(missing)}")
    if extra:
        errors.append(f"{name} has extra keys: {sorted(extra)}")


def validate_run(run: dict[str, Any], registry: dict[str, dict[str, Any]], errors: list[str]) -> None:
    require(run.get("benchmark") == "MobileHarnessBench", "run.benchmark must be MobileHarnessBench", errors)
    run_kind = run.get("run_kind")
    require(run_kind in ALLOWED_RUN_KINDS, "run.run_kind invalid", errors)
    require(run.get("strategy_family") in ALLOWED_RUN_FAMILIES, "run.strategy_family invalid", errors)

    strategies = run.get("strategies")
    require(isinstance(strategies, list) and bool(strategies), "run.strategies must be non-empty", errors)
    strategy_ids: list[str] = []
    if isinstance(strategies, list):
        for index, strategy_ref in enumerate(strategies):
            if not isinstance(strategy_ref, dict):
                errors.append(f"run.strategies[{index}] is not an object")
                continue
            strategy_id = strategy_ref.get("strategy_id")
            family = strategy_ref.get("strategy_family")
            strategy_ids.append(strategy_id)
            require(strategy_id in registry, f"run strategy not found in registry: {strategy_id}", errors)
            if strategy_id in registry:
                require(family == registry[strategy_id]["strategy_family"], f"{strategy_id} family mismatch", errors)

    task_subset = run.get("task_subset", {})
    task_count = task_subset.get("task_count") if isinstance(task_subset, dict) else None
    require(isinstance(task_count, int) and task_count > 0, "run.task_subset.task_count invalid", errors)

    require(run.get("counts_as_experiment") is (run_kind == "strategy_ablation_result"), "counts_as_experiment does not match run_kind", errors)

    results = run.get("results")
    require(isinstance(results, list), "run.results must be a list", errors)
    if not isinstance(results, list) or not isinstance(task_count, int):
        return

    expected_result_count = len(strategy_ids) * task_count
    require(len(results) == expected_result_count, f"result count {len(results)} != expected {expected_result_count}", errors)

    summary = run.get("summary", {})
    if isinstance(summary, dict):
        require(summary.get("total") == len(results), "summary.total does not match results", errors)
        require(summary.get("strategies") == len(strategy_ids), "summary.strategies mismatch", errors)
        require(summary.get("tasks_per_strategy") == task_count, "summary.tasks_per_strategy mismatch", errors)
    else:
        errors.append("run.summary must be an object")

    boundary = BOUNDARY_BY_KIND.get(run_kind)
    if boundary:
        require(boundary in str(run.get("evidence_boundary", "")), "run.evidence_boundary missing run boundary", errors)

    for index, result in enumerate(results):
        if not isinstance(result, dict):
            errors.append(f"results[{index}] is not an object")
            continue
        prefix = f"results[{index}]"
        strategy_id = result.get("strategy_id")
        require(strategy_id in strategy_ids, f"{prefix}.strategy_id not selected: {strategy_id}", errors)
        require(result.get("status") in ALLOWED_STATUS, f"{prefix}.status invalid", errors)
        require(
            result.get("counts_as_strategy_ablation_result") is (run_kind == "strategy_ablation_result"),
            f"{prefix}.counts_as_strategy_ablation_result does not match run_kind",
            errors,
        )

        validate_metric_object(f"{prefix}.time_metrics", result.get("time_metrics"), TIME_KEYS, errors)
        validate_metric_object(f"{prefix}.token_metrics", result.get("token_metrics"), TOKEN_KEYS, errors)
        validate_metric_object(f"{prefix}.effect_metrics", result.get("effect_metrics"), EFFECT_KEYS, errors)

        if run_kind in {"strategy_scaffold_not_run", "strategy_dry_run_not_counted"}:
            for metric_name in ("time_metrics", "token_metrics", "effect_metrics"):
                metric = result.get(metric_name)
                if isinstance(metric, dict):
                    require(all_null(metric), f"{prefix}.{metric_name} must remain null for {run_kind}", errors)
            require(result.get("status") == "not_run", f"{prefix}.status must be not_run for {run_kind}", errors)

        evidence = result.get("evidence")
        if not isinstance(evidence, dict):
            errors.append(f"{prefix}.evidence must be an object")
        elif boundary:
            require(evidence.get("boundary") == boundary, f"{prefix}.evidence.boundary mismatch", errors)

        trace = result.get("strategy_trace")
        if not isinstance(trace, dict):
            errors.append(f"{prefix}.strategy_trace must be an object")
        elif boundary:
            require(trace.get("trace_status") == boundary, f"{prefix}.strategy_trace.trace_status mismatch", errors)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry", required=True, help="Path to strategy_registry.json")
    parser.add_argument("--run", required=True, help="Path to strategy ablation run.json")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    errors: list[str] = []
    registry = load_json(resolve_path(args.registry))
    run = load_json(resolve_path(args.run))
    registry_by_id = validate_registry(registry, errors)
    validate_run(run, registry_by_id, errors)

    if errors:
        print("FAIL strategy ablation validation")
        for error in errors:
            print(f"- {error}")
        return 1

    print("PASS strategy ablation validation")
    print(f"Strategies: {len(registry_by_id)}")
    print(f"Results: {len(run.get('results', []))}")
    print(f"Run kind: {run.get('run_kind')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
