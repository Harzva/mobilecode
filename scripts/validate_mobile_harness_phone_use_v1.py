#!/usr/bin/env python3
"""Validate the controlled MobileHarnessBench Phone Use v1 task contract."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "docs/mobile-harness-benchmark/phone-use/controlled-task-set-v1.json"
DEFAULT_REPORT_JSON = ROOT / "docs/mobile-harness-benchmark/reports/phone-use-v1-readiness.json"
DEFAULT_REPORT_MD = ROOT / "docs/mobile-harness-benchmark/reports/phone-use-v1-readiness.md"

EXPECTED_OUTCOMES = {
    "verified_success",
    "partial_progress",
    "agent_failure",
    "environment_error",
    "user_takeover",
    "safety_block",
}
EXPECTED_CATEGORIES = {
    "system_navigation",
    "information_retrieval",
    "controlled_form_entry",
    "interruption_recovery",
    "transaction_safety",
}
EXPECTED_METRICS = {
    "task_success_rate",
    "verified_success_rate",
    "partial_progress_rate",
    "stale_reference_rejection_rate",
    "approval_correctness_rate",
    "approval_replay_rejection_rate",
    "secret_leakage_rate",
    "recovery_rate",
    "human_intervention_count",
    "steps_to_completion",
    "wall_time_ms",
}
EXPECTED_ARTIFACTS = {
    "device_metadata",
    "before_snapshot_summary",
    "after_snapshot_summary",
    "action_evidence",
    "verifier_result",
    "redaction_report",
}
RISK_LEVELS = {"low", "medium", "high"}
SECRET_POLICIES = {"none", "secret_id_only"}


class ValidationError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationError(message)


def load_manifest(path: Path) -> dict[str, Any]:
    require(path.is_file(), f"manifest not found: {path}")
    payload = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(payload, dict), "manifest root must be an object")
    return payload


def validate(payload: dict[str, Any]) -> dict[str, Any]:
    require(payload.get("schema_version") == 1, "schema_version must be 1")
    require(payload.get("benchmark") == "MobileHarnessBench-PhoneUse", "benchmark name mismatch")
    require(payload.get("task_set") == "controlled-phone-use-v1", "task_set mismatch")
    require(payload.get("status") == "frozen_protocol_no_counted_results", "status must remain non-counted")
    require(payload.get("counts_as_experiment") is False, "task manifest must not count as an experiment")
    require(payload.get("repetitions_per_task") == 3, "each counted task must require three repetitions")
    require(set(payload.get("terminal_outcomes", [])) == EXPECTED_OUTCOMES, "terminal outcomes mismatch")
    require(set(payload.get("primary_metrics", [])) == EXPECTED_METRICS, "primary metrics mismatch")
    require(set(payload.get("required_artifacts", [])) == EXPECTED_ARTIFACTS, "required artifacts mismatch")

    tasks = payload.get("tasks")
    require(isinstance(tasks, list), "tasks must be a list")
    require(len(tasks) == 30, "controlled-phone-use-v1 must contain 30 tasks")
    require(payload.get("task_count") == len(tasks), "task_count does not match tasks")

    ids: list[str] = []
    categories: Counter[str] = Counter()
    risks: Counter[str] = Counter()
    tiers: Counter[str] = Counter()
    surfaces: set[str] = set()
    for index, task in enumerate(tasks):
        require(isinstance(task, dict), f"task[{index}] must be an object")
        task_id = task.get("id")
        require(isinstance(task_id, str) and task_id.startswith("PU-"), f"task[{index}] invalid id")
        ids.append(task_id)

        category = task.get("category")
        require(category in EXPECTED_CATEGORIES, f"{task_id} invalid category: {category}")
        categories[category] += 1

        surface = task.get("surface")
        require(isinstance(surface, str) and surface.strip(), f"{task_id} missing surface")
        surfaces.add(surface)

        tier = task.get("tier")
        require(tier in {"T1-android-emulator", "T2-android-real-device"}, f"{task_id} invalid tier")
        tiers[tier] += 1

        require(isinstance(task.get("goal"), str) and task["goal"].strip(), f"{task_id} missing goal")
        require(isinstance(task.get("oracle"), str) and task["oracle"].strip(), f"{task_id} missing oracle")

        risk = task.get("risk")
        require(risk in RISK_LEVELS, f"{task_id} invalid risk")
        risks[risk] += 1
        approval_expected = task.get("approval_expected")
        require(isinstance(approval_expected, bool), f"{task_id} approval_expected must be boolean")
        if risk == "high":
            require(approval_expected is True, f"{task_id} high-risk task must require approval")
        if risk == "low":
            require(approval_expected is False, f"{task_id} low-risk task must not consume approval")

        secret_policy = task.get("secret_policy")
        require(secret_policy in SECRET_POLICIES, f"{task_id} invalid secret policy")
        if secret_policy == "secret_id_only":
            require(risk == "high", f"{task_id} secret_id use must be high risk")
            require(approval_expected is True, f"{task_id} secret_id use must require approval")

        require(task.get("external_state_mutation") is False, f"{task_id} must not mutate external state")

    require(len(ids) == len(set(ids)), "task ids must be unique")
    require(set(categories) == EXPECTED_CATEGORIES, "category coverage mismatch")
    require(all(categories[category] == 6 for category in EXPECTED_CATEGORIES), "each category must contain six tasks")
    require(tiers["T1-android-emulator"] == 29, "T1 must contain 29 controlled tasks")
    require(tiers["T2-android-real-device"] == 1, "T2 must contain one promotion-boundary task")

    adapters = payload.get("public_benchmark_adapters")
    require(isinstance(adapters, list) and len(adapters) >= 5, "five public benchmark adapter entries are required")
    adapter_names = {item.get("benchmark") for item in adapters if isinstance(item, dict)}
    require(
        {"AndroidWorld", "ScreenSpot-V2/Pro", "BFCL-v4", "Terminal-Bench 2.0", "MobileWorld"}.issubset(adapter_names),
        "public benchmark adapter registry is incomplete",
    )

    return {
        "task_count": len(tasks),
        "category_counts": dict(sorted(categories.items())),
        "risk_counts": dict(sorted(risks.items())),
        "tier_counts": dict(sorted(tiers.items())),
        "surface_count": len(surfaces),
        "public_adapter_count": len(adapters),
    }


def build_report(manifest_path: Path, summary: dict[str, Any], payload: dict[str, Any]) -> dict[str, Any]:
    return {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "status": "passed_with_open_requirements",
        "benchmark": payload["benchmark"],
        "task_set": payload["task_set"],
        "manifest": manifest_path.relative_to(ROOT).as_posix(),
        "counts_as_experiment": False,
        "ready_for_t1_non_counted_qa": True,
        "ready_for_counted_mobile_result": False,
        **summary,
        "terminal_outcomes": payload["terminal_outcomes"],
        "primary_metrics": payload["primary_metrics"],
        "required_artifacts": payload["required_artifacts"],
        "public_benchmark_adapters": payload["public_benchmark_adapters"],
        "open_requirements": [
            "execute_three_repetitions_per_t1_task_with_real_agent_callbacks",
            "attach_t2_physical_android_device_evidence",
            "run_at_least_one_official_public_benchmark_adapter",
            "lock_and_execute_counted_baselines",
        ],
    }


def write_report(report: dict[str, Any], json_path: Path, md_path: Path) -> None:
    json_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    categories = report["category_counts"]
    lines = [
        "# Phone Use v1 Readiness",
        "",
        f"Generated at: `{report['generated_at']}`",
        f"Status: `{report['status']}`",
        f"Counts as experiment: `{str(report['counts_as_experiment']).lower()}`",
        "",
        "## Evidence Boundary",
        "",
        "The 30-task contract, safety oracles, terminal taxonomy, and public adapter registry are machine-valid. No task result is counted until repeated model/tool/device runs and required evidence are attached.",
        "",
        "## Coverage",
        "",
        f"- Tasks: `{report['task_count']}`",
        f"- Repetitions required per task: `3`",
        f"- Distinct surfaces: `{report['surface_count']}`",
        f"- Public benchmark adapters registered: `{report['public_adapter_count']}`",
        "",
        "| Category | Tasks |",
        "| --- | ---: |",
    ]
    lines.extend(f"| `{category}` | {count} |" for category, count in categories.items())
    lines.extend(
        [
            "",
            "## Promotion Gates",
            "",
            "- T1 emulator runs remain non-counted until all task repetitions use real model/tool callbacks.",
            "- Physical-device claims require T2 device metadata and evidence; emulator evidence cannot be relabelled.",
            "- Transaction tasks never submit real orders or payments; the expected terminal outcome is `safety_block` at the boundary.",
            "- Login evidence stores only `secret_id` slot references and forbids raw credential values.",
            "",
            "## Open Requirements",
            "",
        ]
    )
    lines.extend(f"- `{item}`" for item in report["open_requirements"])
    lines.append("")
    md_path.write_text("\n".join(lines), encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", default=str(DEFAULT_MANIFEST))
    parser.add_argument("--write-report", action="store_true")
    parser.add_argument("--report-json", default=str(DEFAULT_REPORT_JSON))
    parser.add_argument("--report-md", default=str(DEFAULT_REPORT_MD))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    manifest_path = Path(args.manifest).resolve()
    payload = load_manifest(manifest_path)
    summary = validate(payload)
    report = build_report(manifest_path, summary, payload)
    if args.write_report:
        write_report(report, Path(args.report_json).resolve(), Path(args.report_md).resolve())
    print(
        f"Phone Use v1 contract valid: tasks={summary['task_count']} "
        f"categories={summary['category_counts']} counted=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
