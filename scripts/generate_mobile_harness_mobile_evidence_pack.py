#!/usr/bin/env python3
"""Generate mobile-tier evidence capture templates for MobileHarnessBench.

The pack prepares T2/T3 collection, but it does not create benchmark results.
Every generated template explicitly sets counts_as_mobile_experiment=false.
"""

from __future__ import annotations

import csv
import json
import shutil
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
BENCH_ROOT = ROOT / "docs" / "mobile-harness-benchmark"
TASKS_ROOT = BENCH_ROOT / "tasks"
REPORTS_ROOT = BENCH_ROOT / "reports"
PACK_ROOT = BENCH_ROOT / "mobile-evidence" / "2026-06-06-mobile-evidence-pack"

TASK_SET_PATHS = {
    "android-device-v2": TASKS_ROOT / "android-device-v2.json",
    "ios-simulator-v2": TASKS_ROOT / "ios-simulator-v2.json",
}

TIER_BY_SET = {
    "android-device-v2": "T2-android-real-device",
    "ios-simulator-v2": "T3-ios-simulator",
}

REPORT_JSON_PATH = REPORTS_ROOT / "mobile-evidence-pack-readiness.json"
REPORT_MD_PATH = REPORTS_ROOT / "mobile-evidence-pack-readiness.md"


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def rel_from_report(path: Path) -> str:
    return path.relative_to(REPORT_MD_PATH.parent).as_posix() if path.is_relative_to(REPORT_MD_PATH.parent) else "../" + path.relative_to(BENCH_ROOT).as_posix()


def load_task_set(task_set: str) -> dict[str, Any]:
    path = TASK_SET_PATHS[task_set]
    if not path.exists():
        raise SystemExit(f"missing task-set manifest: {rel(path)}")
    payload = json.loads(path.read_text(encoding="utf-8"))
    tasks = payload.get("tasks", [])
    if not isinstance(tasks, list) or not tasks:
        raise SystemExit(f"{rel(path)} must contain a non-empty tasks list")
    return payload


def task_template(task_set: str, task: dict[str, Any]) -> dict[str, Any]:
    tier = TIER_BY_SET[task_set]
    return {
        "schema": "mobile_harness_mobile_evidence_template/v0",
        "task_id": task["id"],
        "task_set": task_set,
        "category": task["category"],
        "test_tier": tier,
        "fixture": task["fixture"],
        "mobile_profile": task["mobile_profile"],
        "quality_axis": task["quality_axis"],
        "requires_real_device": bool(task.get("requires_real_device")),
        "status": "template_not_run",
        "counts_as_mobile_experiment": False,
        "required_before_counting": [
            "run.json with verifier result for this task",
            "summary.md for the run",
            "traces.jsonl with task events",
            "device-metadata.json with anonymized device fields",
            "at least one screenshot or screen recording marker",
            "platform log excerpt when available",
            "public-output safety scan result",
        ],
        "evidence_to_fill": {
            "run_id": None,
            "operator_label": None,
            "started_at": None,
            "completed_at": None,
            "device_metadata_path": None,
            "run_json_path": None,
            "summary_md_path": None,
            "traces_jsonl_path": None,
            "screenshot_paths": [],
            "screen_recording_paths": [],
            "log_paths": [],
            "artifact_paths": [],
            "verifier_output_paths": [],
            "failure_kind": None,
            "blocked_reason": None,
            "human_intervention_count": None,
            "public_safety_scan_passed": None,
        },
    }


def device_metadata_template(task_set: str) -> dict[str, Any]:
    platform = "android" if task_set == "android-device-v2" else "ios"
    environment = "real_device" if task_set == "android-device-v2" else "simulator"
    return {
        "schema": "mobile_harness_device_metadata_template/v0",
        "task_set": task_set,
        "test_tier": TIER_BY_SET[task_set],
        "platform": platform,
        "environment": environment,
        "counts_as_mobile_experiment": False,
        "device": {
            "model": None,
            "manufacturer": None if platform == "android" else "Apple",
            "os_version": None,
            "sdk_or_runtime": None,
            "serial_or_udid_hash": None,
        },
        "app": {
            "app_version": None,
            "build_type": None,
            "install_source": None,
        },
        "session": {
            "viewport": None,
            "network_profile": None,
            "input_surface": None,
            "evidence_capture_method": None,
            "log_capture_method": None,
        },
    }


def run_manifest_template(task_set: str, task_ids: list[str]) -> dict[str, Any]:
    return {
        "schema": "mobile_harness_mobile_run_manifest_template/v0",
        "task_set": task_set,
        "test_tier": TIER_BY_SET[task_set],
        "task_ids": task_ids,
        "task_count": len(task_ids),
        "status": "template_not_run",
        "counts_as_mobile_experiment": False,
        "required_run_files": [
            "run.json",
            "summary.md",
            "traces.jsonl",
            "device-metadata.json",
            "screenshots/",
            "logs/",
        ],
        "promotion_rule": (
            "A task can become paper-counted only after the run manifest is filled, "
            "task evidence templates are completed, verifier outputs exist, and public-output safety passes."
        ),
    }


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def write_checklist(path: Path, rows: list[dict[str, Any]]) -> None:
    fieldnames = [
        "task_set",
        "task_id",
        "category",
        "test_tier",
        "device_metadata",
        "run_json",
        "summary_md",
        "traces_jsonl",
        "screenshot_or_recording",
        "logs",
        "verifier_outputs",
        "public_safety_scan",
        "counts_as_mobile_experiment",
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def write_execution_playbook(path: Path, task_set_summaries: list[dict[str, Any]]) -> None:
    lines = [
        "# Mobile Evidence Execution Playbook",
        "",
        "This playbook turns the capture templates into a deterministic operator flow.",
        "It is not a benchmark result and does not count as a mobile experiment.",
        "",
        "## Promotion Rule",
        "",
        "A task remains `template_not_run` until all required run files, task evidence, device metadata, verifier outputs, screenshots or recordings, logs when available, and public-output safety scans are attached.",
        "Only then can a separate reviewed result promote it toward paper-counted mobile evidence.",
        "",
        "## Execution Order",
        "",
        "| Step | Android T2 real device | iOS T3 simulator | Required output | Counts as result |",
        "| --- | --- | --- | --- | --- |",
        "| 1 | Select `android-device-v2` task set | Select `ios-simulator-v2` task set | task-set manifest id | false |",
        "| 2 | Fill device metadata from real phone | Fill simulator metadata from Mac/Xcode | `device-metadata.json` | false |",
        "| 3 | Install or launch the current app build | Install or launch the current simulator app build | app build metadata | false |",
        "| 4 | Execute each task through the app harness | Execute each task through the app harness | `run.json`, `summary.md`, `traces.jsonl` | false until verifier review |",
        "| 5 | Capture screenshots or screen recording | Capture simulator screenshots | `screenshots/` or `recordings/` | false |",
        "| 6 | Capture platform logs when available | Capture Xcode/simulator logs when available | `logs/` | false |",
        "| 7 | Attach verifier outputs and artifacts | Attach verifier outputs and artifacts | verifier/artifact paths | false |",
        "| 8 | Run public-output safety scan | Run public-output safety scan | safety scan status | false |",
        "| 9 | Review promotion checklist | Review promotion checklist | completed task evidence template | promotion candidate only |",
        "",
        "## Task Sets",
        "",
        "| Task set | Tier | Tasks | Requires real device | Template dir |",
        "| --- | --- | ---: | ---: | --- |",
    ]
    for summary in task_set_summaries:
        lines.append(
            f"| `{summary['task_set']}` | `{summary['test_tier']}` | {summary['task_count']} | {summary['requires_real_device_count']} | `{summary['template_dir']}` |"
        )
    lines.extend(
        [
            "",
            "## Non-Result Boundary",
            "",
            "- This playbook is a collection protocol, not a completed run.",
            "- It must not be cited as Android/iOS performance evidence.",
            "- It must be regenerated when task sets, required evidence, or verifier promotion rules change.",
            "",
        ]
    )
    path.write_text("\n".join(lines), encoding="utf-8", newline="")


def build_pack() -> dict[str, Any]:
    if PACK_ROOT.exists():
        shutil.rmtree(PACK_ROOT)
    PACK_ROOT.mkdir(parents=True)

    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    task_set_summaries: list[dict[str, Any]] = []
    template_paths: list[str] = []
    checklist_rows: list[dict[str, Any]] = []

    for task_set in sorted(TASK_SET_PATHS):
        payload = load_task_set(task_set)
        tasks = payload["tasks"]
        categories = Counter(task["category"] for task in tasks)
        task_set_dir = PACK_ROOT / task_set

        metadata_path = task_set_dir / "device-metadata-template.json"
        run_manifest_path = task_set_dir / "run-manifest-template.json"
        write_json(metadata_path, device_metadata_template(task_set))
        write_json(run_manifest_path, run_manifest_template(task_set, [task["id"] for task in tasks]))
        template_paths.extend([rel(metadata_path), rel(run_manifest_path)])

        for task in tasks:
            evidence_path = task_set_dir / "tasks" / task["id"] / "evidence-template.json"
            write_json(evidence_path, task_template(task_set, task))
            template_paths.append(rel(evidence_path))
            checklist_rows.append(
                {
                    "task_set": task_set,
                    "task_id": task["id"],
                    "category": task["category"],
                    "test_tier": TIER_BY_SET[task_set],
                    "device_metadata": "required",
                    "run_json": "required",
                    "summary_md": "required",
                    "traces_jsonl": "required",
                    "screenshot_or_recording": "required",
                    "logs": "required_when_available",
                    "verifier_outputs": "required",
                    "public_safety_scan": "required",
                    "counts_as_mobile_experiment": "false",
                }
            )

        task_set_summaries.append(
            {
                "task_set": task_set,
                "test_tier": TIER_BY_SET[task_set],
                "task_count": len(tasks),
                "categories": dict(sorted(categories.items())),
                "requires_real_device_count": sum(1 for task in tasks if task.get("requires_real_device")),
                "template_dir": rel(task_set_dir),
            }
        )

    checklist_path = PACK_ROOT / "mobile-evidence-checklist.csv"
    write_checklist(checklist_path, checklist_rows)
    template_paths.append(rel(checklist_path))
    playbook_path = PACK_ROOT / "execution-playbook.md"
    write_execution_playbook(playbook_path, task_set_summaries)

    manifest = {
        "schema": "mobile_harness_mobile_evidence_pack_manifest/v0",
        "generated_at": generated_at,
        "status": "capture_ready_no_results",
        "counts_as_experiment": False,
        "counts_as_mobile_experiment": False,
        "ready_for_capture": True,
        "ready_for_counted_mobile_experiment": False,
        "pack_root": rel(PACK_ROOT),
        "task_set_count": len(task_set_summaries),
        "task_count": sum(item["task_count"] for item in task_set_summaries),
        "template_count": len(template_paths),
        "execution_playbook_path": rel(playbook_path),
        "task_sets": task_set_summaries,
        "template_paths": template_paths,
        "open_requirements": [
            "execute_android_t2_real_device_run",
            "execute_ios_t3_simulator_run",
            "fill_device_metadata_and_task_evidence",
            "attach_verifier_outputs_traces_screenshots_and_logs",
            "pass_public_output_safety_scan",
        ],
    }
    manifest_path = PACK_ROOT / "manifest.json"
    write_json(manifest_path, manifest)

    readme = [
        "# Mobile Evidence Capture Pack",
        "",
        f"Generated at: `{generated_at}`",
        "",
        "This pack prepares Android T2 and iOS T3 evidence collection. It is not a benchmark run.",
        "",
        "- Status: `capture_ready_no_results`",
        "- Counts as experiment: `false`",
        "- Counts as mobile experiment: `false`",
        "",
        "A task can be promoted only after the run files, task evidence template, device metadata, verifier outputs, screenshots/logs and public-output safety scan are complete.",
        "",
        "## Task Sets",
        "",
        "| Task set | Tier | Tasks | Requires real device |",
        "| --- | --- | ---: | ---: |",
    ]
    for summary in task_set_summaries:
        readme.append(
            f"| `{summary['task_set']}` | `{summary['test_tier']}` | {summary['task_count']} | {summary['requires_real_device_count']} |"
        )
    readme.extend(
        [
            "",
            "## Files",
            "",
            "- `manifest.json`: pack-level status and open requirements.",
            "- `mobile-evidence-checklist.csv`: task-level evidence checklist.",
            "- `execution-playbook.md`: operator execution order and promotion boundary.",
            "- `<task-set>/device-metadata-template.json`: platform metadata template.",
            "- `<task-set>/run-manifest-template.json`: run-level evidence template.",
            "- `<task-set>/tasks/<task-id>/evidence-template.json`: task-level evidence template.",
            "",
        ]
    )
    (PACK_ROOT / "README.md").write_text("\n".join(readme), encoding="utf-8", newline="")

    return manifest


def write_report(manifest: dict[str, Any]) -> None:
    REPORTS_ROOT.mkdir(parents=True, exist_ok=True)
    report = {
        "report": "mobile-evidence-pack-readiness",
        "generated_at": manifest["generated_at"],
        "status": manifest["status"],
        "counts_as_experiment": False,
        "counts_as_mobile_experiment": False,
        "ready_for_capture": True,
        "ready_for_counted_mobile_experiment": False,
        "pack_root": manifest["pack_root"],
        "task_set_count": manifest["task_set_count"],
        "task_count": manifest["task_count"],
        "template_count": manifest["template_count"],
        "task_sets": manifest["task_sets"],
        "open_requirements": manifest["open_requirements"],
        "evidence_boundary": (
            "This is a capture kit, not a mobile experiment. It prepares the files required to "
            "collect Android T2 and iOS T3 evidence without counting any result."
        ),
        "evidence_artifacts": [
            rel(PACK_ROOT / "manifest.json"),
            rel(PACK_ROOT / "README.md"),
            manifest["execution_playbook_path"],
        ],
    }
    REPORT_JSON_PATH.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    lines = [
        "# Mobile Evidence Pack Readiness",
        "",
        f"Generated at: `{report['generated_at']}`",
        f"Status: `{report['status']}`",
        f"Ready for capture: `{str(report['ready_for_capture']).lower()}`",
        f"Ready for counted mobile experiment: `{str(report['ready_for_counted_mobile_experiment']).lower()}`",
        "",
        "## Evidence Boundary",
        "",
        report["evidence_boundary"],
        "",
        "## Task Sets",
        "",
        "| Task set | Tier | Tasks | Requires real device |",
        "| --- | --- | ---: | ---: |",
    ]
    for summary in report["task_sets"]:
        lines.append(
            f"| `{summary['task_set']}` | `{summary['test_tier']}` | {summary['task_count']} | {summary['requires_real_device_count']} |"
        )
    lines.extend(["", "## Open Requirements", ""])
    for requirement in report["open_requirements"]:
        lines.append(f"- `{requirement}`")
    playbook_path = ROOT / manifest["execution_playbook_path"]
    lines.extend(["", "## Execution Playbook", "", f"- [{playbook_path.name}]({rel_from_report(playbook_path)})"])
    lines.append("")
    REPORT_MD_PATH.write_text("\n".join(lines), encoding="utf-8", newline="")


def main() -> int:
    manifest = build_pack()
    write_report(manifest)
    print("MobileHarnessBench mobile evidence capture pack generated")
    print(f"pack_root={manifest['pack_root']}")
    print(f"status={manifest['status']}")
    print(f"task_count={manifest['task_count']}")
    print(f"template_count={manifest['template_count']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
