#!/usr/bin/env python3
"""Generate a draft frozen paper subset manifest for MobileHarnessBench.

The manifest fixes candidate task selection and evidence requirements for the
paper, but it deliberately remains non-final until mobile-tier evidence exists.
"""

from __future__ import annotations

import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
BENCH_ROOT = ROOT / "docs" / "mobile-harness-benchmark"
TASKS_DIR = BENCH_ROOT / "tasks"
RUNS_DIR = BENCH_ROOT / "runs"
REPORTS_DIR = BENCH_ROOT / "reports"

V2_BANK_PATH = TASKS_DIR / "v2-task-bank.json"
SMOKE_TASK_SET_PATH = TASKS_DIR / "smoke-v2.json"
ANDROID_TASK_SET_PATH = TASKS_DIR / "android-device-v2.json"
IOS_TASK_SET_PATH = TASKS_DIR / "ios-simulator-v2.json"
SMOKE_RUN_PATH = RUNS_DIR / "2026-06-06-smoke-v2-t0" / "run.json"
READINESS_PATH = REPORTS_DIR / "mobile-tier-readiness.json"
OUTPUT_PATH = TASKS_DIR / "frozen-v2-paper-subset.json"
REPORT_MD_PATH = REPORTS_DIR / "frozen-subset-readiness.md"
REPORT_JSON_PATH = REPORTS_DIR / "frozen-subset-readiness.json"


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def repo_rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def select_required_next_tier(task: dict[str, Any], in_android: bool, in_ios: bool) -> str:
    category = task["category"]
    if category == "github_delivery":
        return "T5-github-sandbox"
    if in_android and task.get("mobile_requirements", {}).get("requires_real_device") is True:
        return "T2-android-real-device"
    if in_ios:
        return "T3-ios-simulator"
    return "T2-or-T3-mobile-tier"


def build_manifest() -> tuple[dict[str, Any], dict[str, Any]]:
    bank = load_json(V2_BANK_PATH)
    tasks_by_id = {task["id"]: task for task in bank["tasks"]}
    smoke_set = load_json(SMOKE_TASK_SET_PATH)
    android_ids = {entry["id"] for entry in load_json(ANDROID_TASK_SET_PATH)["tasks"]}
    ios_ids = {entry["id"] for entry in load_json(IOS_TASK_SET_PATH)["tasks"]}
    smoke_run = load_json(SMOKE_RUN_PATH)
    readiness = load_json(READINESS_PATH)
    run_results = {result["task_id"]: result for result in smoke_run["results"]}

    entries: list[dict[str, Any]] = []
    for entry in smoke_set["tasks"]:
        task = tasks_by_id[entry["id"]]
        result = run_results.get(task["id"])
        if result is None:
            raise ValueError(f"missing smoke-v2 run result for {task['id']}")
        next_tier = select_required_next_tier(task, task["id"] in android_ids, task["id"] in ios_ids)
        entries.append(
            {
                "id": task["id"],
                "category": task["category"],
                "title": task["title"],
                "fixture": task["input_fixture"]["path"],
                "quality_axis": task["scenario"]["quality_axis"],
                "mobile_profile": task["scenario"]["mobile_profile"],
                "requires_real_device": task["mobile_requirements"]["requires_real_device"],
                "t0_status": result["status"],
                "t0_score": result["score"],
                "t0_artifacts": result["evidence"].get("artifact_paths", []),
                "counts_as_final_paper_result": False,
                "paper_counting_status": "t0_only_not_mobile_counted",
                "required_next_tier": next_tier,
                "required_next_evidence": [
                    "device-metadata.json",
                    "run.json",
                    "summary.md",
                    "traces.jsonl",
                    "screenshots_or_logs",
                    "task_specific_verifier_result",
                ],
            }
        )

    category_counts = Counter(item["category"] for item in entries)
    next_tier_counts = Counter(item["required_next_tier"] for item in entries)
    t0_counts = Counter(item["t0_status"] for item in entries)
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat()

    manifest = {
        "subset": "frozen-v2-paper-subset",
        "status": "draft_frozen_candidate",
        "generated_at": generated_at,
        "frozen": False,
        "counts_as_final_paper_subset": False,
        "source_task_bank": repo_rel(V2_BANK_PATH),
        "source_task_set": repo_rel(SMOKE_TASK_SET_PATH),
        "source_t0_run": repo_rel(SMOKE_RUN_PATH),
        "mobile_tier_readiness": repo_rel(READINESS_PATH),
        "task_count": len(entries),
        "category_count": dict(sorted(category_counts.items())),
        "t0_result_count": dict(sorted(t0_counts.items())),
        "required_next_tier_count": dict(sorted(next_tier_counts.items())),
        "selection_rule": (
            "Start from smoke-v2: ten tasks per category. Freeze ids for paper planning, "
            "but keep all entries non-final until required mobile or GitHub sandbox evidence exists."
        ),
        "evidence_boundary": (
            "This manifest fixes candidate tasks and T0 evidence. It is not final experimental evidence; "
            "no entry counts as a paper result until its required_next_tier evidence is attached."
        ),
        "tasks": entries,
    }

    report = {
        "report": "frozen-subset-readiness",
        "generated_at": generated_at,
        "manifest": repo_rel(OUTPUT_PATH),
        "status": manifest["status"],
        "counts_as_final_paper_subset": False,
        "task_count": len(entries),
        "category_count": manifest["category_count"],
        "t0_result_count": manifest["t0_result_count"],
        "required_next_tier_count": manifest["required_next_tier_count"],
        "readiness_status": {
            "android": readiness.get("android", {}).get("status"),
            "android_blocked_reason": readiness.get("android", {}).get("blocked_reason"),
            "ios": readiness.get("ios", {}).get("status"),
            "ios_blocked_reason": readiness.get("ios", {}).get("blocked_reason"),
        },
        "known_limits": [
            "The manifest is frozen for planning only; it is not a final paper subset.",
            "T0 fixture results do not replace Android/iOS mobile-tier evidence.",
            "GitHub delivery entries require an authorized public sandbox run.",
        ],
    }
    return manifest, report


def write_markdown_report(report: dict[str, Any], manifest: dict[str, Any]) -> None:
    lines = [
        "# Frozen Subset Readiness",
        "",
        f"Generated at: `{report['generated_at']}`",
        f"Manifest: `{report['manifest']}`",
        f"Status: `{report['status']}`",
        "",
        "## Evidence Boundary",
        "",
        manifest["evidence_boundary"],
        "",
        "## Counts",
        "",
        f"- Tasks: {report['task_count']}",
        f"- T0 results: {report['t0_result_count']}",
        f"- Required next tiers: {report['required_next_tier_count']}",
        f"- Categories: {report['category_count']}",
        "",
        "## Readiness",
        "",
        f"- Android: `{report['readiness_status']['android']}` ({report['readiness_status']['android_blocked_reason']})",
        f"- iOS: `{report['readiness_status']['ios']}` ({report['readiness_status']['ios_blocked_reason']})",
        "",
        "## Known Limits",
        "",
    ]
    for item in report["known_limits"]:
        lines.append(f"- {item}")
    lines.append("")
    REPORT_MD_PATH.write_text("\n".join(lines), encoding="utf-8", newline="")


def main() -> int:
    manifest, report = build_manifest()
    OUTPUT_PATH.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    REPORT_JSON_PATH.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_markdown_report(report, manifest)
    print("MobileHarnessBench frozen subset manifest generated")
    print(f"manifest={repo_rel(OUTPUT_PATH)}")
    print(f"report_md={repo_rel(REPORT_MD_PATH)}")
    print(f"task_count={manifest['task_count']}")
    print(f"counts_as_final_paper_subset={manifest['counts_as_final_paper_subset']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
