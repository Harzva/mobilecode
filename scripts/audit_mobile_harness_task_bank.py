#!/usr/bin/env python3
"""Audit MobileHarnessBench v2 candidate-bank quality coverage.

This is a machine audit for structure, coverage, uniqueness and public-output
safety. It does not replace human review or real mobile-device experiments.
"""

from __future__ import annotations

import json
import re
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
BENCH_ROOT = ROOT / "docs" / "mobile-harness-benchmark"
TASK_BANK_PATH = BENCH_ROOT / "tasks" / "v2-task-bank.json"
REPORT_DIR = BENCH_ROOT / "reports"
REPORT_MD_PATH = REPORT_DIR / "v2-quality-audit.md"
REPORT_JSON_PATH = REPORT_DIR / "v2-quality-audit.json"

EXPECTED_CATEGORIES = {
    "code_edit",
    "file_intake",
    "github_delivery",
    "harness_evidence",
    "preview_verification",
    "runtime_orchestration",
}
EXPECTED_QUALITY_AXES = {
    "failure_recovery",
    "happy_path",
    "mobile_constraint",
    "public_report_safety",
}
EXPECTED_MOBILE_PROFILES = {
    "android_emulator_file_picker",
    "android_low_memory",
    "android_real_phone_share",
    "ios_real_open_in",
    "ios_simulator_document",
    "webview_only_preview",
}
TASK_SETS = {
    "smoke-v2": (BENCH_ROOT / "tasks" / "smoke-v2.json", 60),
    "android-device-v2": (BENCH_ROOT / "tasks" / "android-device-v2.json", 30),
    "ios-simulator-v2": (BENCH_ROOT / "tasks" / "ios-simulator-v2.json", 18),
}
PUBLIC_SAFETY_PATTERNS = [
    re.compile(r"media_id", re.IGNORECASE),
    re.compile(r"access_token", re.IGNORECASE),
    re.compile(r"wechat_(appid|secret)", re.IGNORECASE),
    re.compile(r"\bopenid\b", re.IGNORECASE),
    re.compile(r"\b[a-zA-Z]:\\"),
    re.compile(r"sk-[A-Za-z0-9_-]{12,}"),
]
MANDATORY_V2_FIELDS = (
    "scenario",
    "quality_gates",
    "sampling_tags",
    "test_oracle",
    "mobile_requirements",
)


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def counter(tasks: list[dict[str, Any]], key_path: tuple[str, ...]) -> Counter[str]:
    values: Counter[str] = Counter()
    for task in tasks:
        value: Any = task
        for key in key_path:
            value = value[key]
        values[str(value)] += 1
    return values


def sorted_counter_payload(values: Counter[str]) -> dict[str, int]:
    return dict(sorted(values.items(), key=lambda item: item[0]))


def compact_distribution(values: Counter[str], *, limit: int | None = None) -> str:
    items = sorted(values.items(), key=lambda item: (-item[1], item[0]))
    if limit is not None and len(items) > limit:
        shown = items[:limit]
        hidden = len(items) - limit
        return ", ".join(f"{key}={value}" for key, value in shown) + f", ... +{hidden} more"
    return ", ".join(f"{key}={value}" for key, value in items)


def scan_public_safety(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    findings: list[str] = []
    for pattern in PUBLIC_SAFETY_PATTERNS:
        for match in pattern.finditer(text):
            line = text.count("\n", 0, match.start()) + 1
            findings.append(f"{path.relative_to(ROOT).as_posix()}:{line}: {match.group(0)}")
    return findings


def audit_task_sets(tasks_by_id: dict[str, dict[str, Any]]) -> dict[str, Any]:
    task_set_results: dict[str, Any] = {}
    for name, (path, expected_count) in TASK_SETS.items():
        payload = load_json(path)
        entries = payload.get("tasks", [])
        ids = [entry.get("id") for entry in entries]
        unknown_ids = sorted(task_id for task_id in ids if task_id not in tasks_by_id)
        duplicate_ids = sorted(task_id for task_id, count in Counter(ids).items() if count > 1)
        categories = Counter(tasks_by_id[task_id]["category"] for task_id in ids if task_id in tasks_by_id)
        task_set_results[name] = {
            "path": path.relative_to(ROOT).as_posix(),
            "expected_count": expected_count,
            "actual_count": len(entries),
            "unknown_ids": unknown_ids,
            "duplicate_ids": duplicate_ids,
            "category_count": sorted_counter_payload(categories),
            "categories_covered": sorted(categories),
        }
    return task_set_results


def gate(status: bool, name: str, evidence: str) -> dict[str, str]:
    return {"name": name, "status": "passed" if status else "failed", "evidence": evidence}


def build_audit() -> dict[str, Any]:
    payload = load_json(TASK_BANK_PATH)
    tasks = payload.get("tasks", [])
    if not isinstance(tasks, list):
        raise ValueError("v2 task bank has no top-level tasks list")

    ids = [task.get("id") for task in tasks]
    titles = [task.get("title") for task in tasks]
    goals = [task.get("user_goal") for task in tasks]
    tasks_by_id = {str(task["id"]): task for task in tasks}

    categories = counter(tasks, ("category",))
    quality_axes = counter(tasks, ("scenario", "quality_axis"))
    mobile_profiles = counter(tasks, ("scenario", "mobile_profile"))
    os_targets = counter(tasks, ("scenario", "os_target"))
    input_surfaces = counter(tasks, ("scenario", "input_surface"))
    app_states = counter(tasks, ("scenario", "app_state"))
    network_profiles = counter(tasks, ("scenario", "network_profile"))
    fixture_kinds = counter(tasks, ("input_fixture", "kind"))
    fixture_paths = counter(tasks, ("input_fixture", "path"))
    real_device = counter(tasks, ("mobile_requirements", "requires_real_device"))

    missing_quality_fields = [
        task["id"]
        for task in tasks
        if any(field not in task or not task[field] for field in MANDATORY_V2_FIELDS)
    ]
    missing_oracle = [
        task["id"]
        for task in tasks
        if not isinstance(task.get("test_oracle", {}).get("must_satisfy"), list)
        or not task["test_oracle"]["must_satisfy"]
    ]
    missing_mobile_evidence = [
        task["id"]
        for task in tasks
        if not isinstance(task.get("mobile_requirements", {}).get("evidence_capture"), list)
        or not task["mobile_requirements"]["evidence_capture"]
    ]
    safety_findings = scan_public_safety(TASK_BANK_PATH)
    task_set_results = audit_task_sets(tasks_by_id)

    gates = [
        gate(len(tasks) == 1000, "v2 task count", f"{len(tasks)} tasks"),
        gate(len(set(ids)) == len(ids), "unique task ids", f"{len(set(ids))}/{len(ids)} unique"),
        gate(len(set(titles)) == len(titles), "unique titles", f"{len(set(titles))}/{len(titles)} unique"),
        gate(len(set(goals)) == len(goals), "unique user goals", f"{len(set(goals))}/{len(goals)} unique"),
        gate(set(categories) == EXPECTED_CATEGORIES, "six-category coverage", compact_distribution(categories)),
        gate(max(categories.values()) - min(categories.values()) <= 1, "category balance", compact_distribution(categories)),
        gate(set(quality_axes) == EXPECTED_QUALITY_AXES, "quality-axis coverage", compact_distribution(quality_axes)),
        gate(set(mobile_profiles) == EXPECTED_MOBILE_PROFILES, "mobile-profile coverage", compact_distribution(mobile_profiles)),
        gate(not missing_quality_fields, "mandatory quality fields", f"missing={len(missing_quality_fields)}"),
        gate(not missing_oracle, "test oracle coverage", f"missing={len(missing_oracle)}"),
        gate(not missing_mobile_evidence, "mobile evidence requirements", f"missing={len(missing_mobile_evidence)}"),
        gate(not safety_findings, "public-output safety marker scan", f"findings={len(safety_findings)}"),
    ]
    for name, result in task_set_results.items():
        count_ok = result["actual_count"] == result["expected_count"]
        refs_ok = not result["unknown_ids"] and not result["duplicate_ids"]
        categories_ok = set(result["categories_covered"]) == EXPECTED_CATEGORIES
        gates.append(
            gate(
                count_ok and refs_ok and categories_ok,
                f"{name} manifest coverage",
                f"count={result['actual_count']}, categories={result['category_count']}",
            )
        )

    failed_gates = [item for item in gates if item["status"] != "passed"]

    return {
        "audit_date": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "status": "passed_with_limits" if not failed_gates else "failed",
        "source": TASK_BANK_PATH.relative_to(ROOT).as_posix(),
        "task_count": len(tasks),
        "unique": {
            "ids": len(set(ids)),
            "titles": len(set(titles)),
            "user_goals": len(set(goals)),
        },
        "coverage": {
            "category": sorted_counter_payload(categories),
            "quality_axis": sorted_counter_payload(quality_axes),
            "mobile_profile": sorted_counter_payload(mobile_profiles),
            "os_target": sorted_counter_payload(os_targets),
            "input_surface": sorted_counter_payload(input_surfaces),
            "app_state": sorted_counter_payload(app_states),
            "network_profile": sorted_counter_payload(network_profiles),
            "fixture_kind": sorted_counter_payload(fixture_kinds),
            "fixture_path": sorted_counter_payload(fixture_paths),
            "requires_real_device": sorted_counter_payload(real_device),
        },
        "task_sets": task_set_results,
        "gates": gates,
        "failed_gates": failed_gates,
        "known_limits": [
            "This audit checks machine-readable structure and coverage, not semantic novelty.",
            "The 1,000 tasks remain a candidate bank until a frozen subset has verifier results.",
            "The audit does not provide Android real-device, iOS simulator, or baseline-comparison evidence.",
            "Human review is still required for task realism, ambiguity, and paper relevance.",
        ],
    }


def write_reports(audit: dict[str, Any]) -> None:
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    REPORT_JSON_PATH.write_text(json.dumps(audit, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    coverage = audit["coverage"]
    rows = [
        ("Category", len(coverage["category"]), compact_distribution(Counter(coverage["category"]))),
        ("Quality axis", len(coverage["quality_axis"]), compact_distribution(Counter(coverage["quality_axis"]))),
        ("Mobile profile", len(coverage["mobile_profile"]), compact_distribution(Counter(coverage["mobile_profile"]))),
        ("OS target", len(coverage["os_target"]), compact_distribution(Counter(coverage["os_target"]))),
        ("Fixture kind", len(coverage["fixture_kind"]), compact_distribution(Counter(coverage["fixture_kind"]))),
        ("Requires real device", len(coverage["requires_real_device"]), compact_distribution(Counter(coverage["requires_real_device"]))),
    ]

    lines = [
        "# MobileHarnessBench v2 Quality Audit",
        "",
        f"Audit date: {audit['audit_date']}",
        f"Source: `{audit['source']}`",
        f"Status: `{audit['status']}`",
        "",
        "## Evidence Boundary",
        "",
        "This is a deterministic machine audit for structure, coverage, uniqueness and public-output safety.",
        "It does not claim that the 1,000 candidate tasks have been executed as experiments.",
        "Only tasks with verifier result, trace, summary and the required mobile-tier evidence should be counted in paper tables.",
        "",
        "## Machine Gates",
        "",
        "| Gate | Status | Evidence |",
        "| --- | --- | --- |",
    ]
    for item in audit["gates"]:
        lines.append(f"| {item['name']} | {item['status']} | {item['evidence']} |")

    lines.extend(
        [
            "",
            "## Coverage Snapshot",
            "",
            "| Dimension | Unique values | Distribution |",
            "| --- | ---: | --- |",
        ]
    )
    for name, unique_count, distribution in rows:
        lines.append(f"| {name} | {unique_count} | {distribution} |")

    lines.extend(
        [
            "",
            "## Task-Set Manifests",
            "",
            "| Task set | Count | Categories | Path |",
            "| --- | ---: | --- | --- |",
        ]
    )
    for name, result in audit["task_sets"].items():
        categories = compact_distribution(Counter(result["category_count"]))
        lines.append(f"| {name} | {result['actual_count']} | {categories} | `{result['path']}` |")

    lines.extend(["", "## Known Limits", ""])
    for item in audit["known_limits"]:
        lines.append(f"- {item}")

    lines.append("")
    REPORT_MD_PATH.write_text("\n".join(lines), encoding="utf-8", newline="")


def main() -> int:
    audit = build_audit()
    write_reports(audit)
    print(f"MobileHarnessBench v2 quality audit {audit['status']}")
    print(f"report_md={REPORT_MD_PATH.relative_to(ROOT).as_posix()}")
    print(f"report_json={REPORT_JSON_PATH.relative_to(ROOT).as_posix()}")
    print(f"task_count={audit['task_count']}")
    print(f"failed_gates={len(audit['failed_gates'])}")
    if audit["failed_gates"]:
        for item in audit["failed_gates"]:
            print(f"ERROR: {item['name']}: {item['evidence']}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
