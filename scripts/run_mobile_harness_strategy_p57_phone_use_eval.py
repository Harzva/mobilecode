#!/usr/bin/env python3
"""Run P5.7 Android phone-use contract evaluation.

This verifier checks the MobileCode app-internal Accessibility phone-use
contract: Android service declaration, safe MethodChannel bridge, Flutter UI
entry, action schema, and non-counted evidence boundary. It does not require a
model call and does not claim a formal benchmark result.
"""

from __future__ import annotations

import argparse
import csv
import json
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import run_mobile_harness_strategy_real_pilot as p5


ROOT = p5.ROOT
REGISTRY_PATH = p5.REGISTRY_PATH
RUN_KIND = p5.RUN_KIND
BOUNDARY = p5.BOUNDARY

ANDROID_NS = "{http://schemas.android.com/apk/res/android}"

TASKS = [
    {
        "task_id": "P57-PHONE-CONTRACT-001",
        "task_category": "android_phone_use_contract",
        "title": "Accessibility service and MethodChannel contract",
        "max_score": 100,
    },
    {
        "task_id": "P57-PHONE-ACTION-SCHEMA-002",
        "task_category": "android_phone_use_action_schema",
        "title": "Observe, gesture, text, and global action schema",
        "max_score": 100,
    },
    {
        "task_id": "P57-PHONE-BOUNDARY-003",
        "task_category": "android_phone_use_boundary",
        "title": "Non-counted, no raw text, redacted phone-use evidence boundary",
        "max_score": 100,
    },
]

FILES = {
    "manifest": ROOT / "mobile_agent/android/app/src/main/AndroidManifest.xml",
    "accessibility_xml": ROOT
    / "mobile_agent/android/app/src/main/res/xml/mobilecode_phone_use_accessibility_service.xml",
    "strings": ROOT / "mobile_agent/android/app/src/main/res/values/strings.xml",
    "kotlin_service": ROOT
    / "mobile_agent/android/app/src/main/kotlin/com/mobilecode/app/PhoneUseAccessibilityService.kt",
    "main_activity": ROOT
    / "mobile_agent/android/app/src/main/kotlin/com/mobilecode/app/MainActivity.kt",
    "dart_service": ROOT
    / "mobile_agent/lib/services/phone_use_accessibility_service.dart",
    "widget": ROOT / "mobile_agent/lib/widgets/phone_use_mode_card.dart",
    "home_screen": ROOT / "mobile_agent/lib/screens/home_screen.dart",
}


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""


def manifest_service_checks() -> dict[str, bool]:
    manifest_path = FILES["manifest"]
    checks = {
        "manifest_exists": manifest_path.is_file(),
        "phone_use_service_declared": False,
        "bind_accessibility_permission": False,
        "accessibility_intent_filter": False,
        "accessibility_metadata": False,
    }
    if not manifest_path.is_file():
        return checks
    root = ET.parse(manifest_path).getroot()
    for service in root.findall(".//service"):
        name = service.attrib.get(f"{ANDROID_NS}name", "")
        if name != ".PhoneUseAccessibilityService":
            continue
        checks["phone_use_service_declared"] = True
        checks["bind_accessibility_permission"] = (
            service.attrib.get(f"{ANDROID_NS}permission") == "android.permission.BIND_ACCESSIBILITY_SERVICE"
        )
        checks["accessibility_intent_filter"] = any(
            action.attrib.get(f"{ANDROID_NS}name") == "android.accessibilityservice.AccessibilityService"
            for action in service.findall(".//action")
        )
        checks["accessibility_metadata"] = any(
            metadata.attrib.get(f"{ANDROID_NS}name") == "android.accessibilityservice"
            and metadata.attrib.get(f"{ANDROID_NS}resource") == "@xml/mobilecode_phone_use_accessibility_service"
            for metadata in service.findall("meta-data")
        )
    return checks


def accessibility_xml_checks() -> dict[str, bool]:
    xml_path = FILES["accessibility_xml"]
    checks = {
        "accessibility_xml_exists": xml_path.is_file(),
        "can_retrieve_window_content": False,
        "can_perform_gestures": False,
        "reports_view_ids": False,
        "retrieves_interactive_windows": False,
        "has_description_and_summary": False,
    }
    if not xml_path.is_file():
        return checks
    root = ET.parse(xml_path).getroot()
    flags = root.attrib.get(f"{ANDROID_NS}accessibilityFlags", "")
    checks["can_retrieve_window_content"] = root.attrib.get(f"{ANDROID_NS}canRetrieveWindowContent") == "true"
    checks["can_perform_gestures"] = root.attrib.get(f"{ANDROID_NS}canPerformGestures") == "true"
    checks["reports_view_ids"] = "flagReportViewIds" in flags
    checks["retrieves_interactive_windows"] = "flagRetrieveInteractiveWindows" in flags
    checks["has_description_and_summary"] = bool(
        root.attrib.get(f"{ANDROID_NS}description") and root.attrib.get(f"{ANDROID_NS}summary")
    )
    return checks


def kotlin_contract_checks() -> dict[str, bool]:
    service = read_text(FILES["kotlin_service"])
    activity = read_text(FILES["main_activity"])
    return {
        "kotlin_service_exists": bool(service),
        "status_method": "fun status(context: Context)" in service,
        "dry_probe_method": "fun dryProbe(context: Context)" in service,
        "perform_action_method": "performPhoneUseAction" in service,
        "observe_ui_action": '"observe_ui"' in service,
        "tap_action": '"tap"' in service,
        "swipe_action": '"swipe"' in service,
        "set_text_action": '"set_text"' in service,
        "global_back_action": '"global_back"' in service,
        "global_home_action": '"global_home"' in service,
        "raw_text_not_returned": '"rawTextIncluded" to false' in service,
        "redaction_flag_returned": '"redactionApplied" to true' in service,
        "method_channel_status": '"getPhoneUseAccessibilityStatus"' in activity,
        "method_channel_settings": '"openPhoneUseAccessibilitySettings"' in activity,
        "method_channel_dry_probe": '"runPhoneUseDryProbe"' in activity,
        "method_channel_action": '"performPhoneUseAction"' in activity,
    }


def flutter_contract_checks() -> dict[str, bool]:
    dart_service = read_text(FILES["dart_service"])
    widget = read_text(FILES["widget"])
    home = read_text(FILES["home_screen"])
    return {
        "dart_service_exists": bool(dart_service),
        "flutter_status_method": "getPhoneUseAccessibilityStatus" in dart_service,
        "flutter_settings_method": "openPhoneUseAccessibilitySettings" in dart_service,
        "flutter_dry_probe_method": "runPhoneUseDryProbe" in dart_service,
        "flutter_action_method": "performPhoneUseAction" in dart_service,
        "flutter_non_counted_fallback": "'countsAsExperiment': false" in dart_service,
        "widget_exists": bool(widget),
        "widget_title": "Mobile Phone Use" in widget,
        "widget_non_counted_label": "counts_as_experiment=false" in widget,
        "widget_raw_text_label": "raw_text_included" in widget,
        "home_mounts_widget": "PhoneUseModeCard" in home,
    }


def score_checks(checks: dict[str, bool]) -> dict[str, Any]:
    total = len(checks)
    passed = sum(1 for value in checks.values() if value)
    score = round((passed / total) * 100, 2) if total else 0.0
    missing = [key for key, value in checks.items() if not value]
    return {
        "score_boundary": "pilot_phone_use_contract_score_not_counted",
        "total_score": score,
        "max_score": 100,
        "passed_checks": passed,
        "total_checks": total,
        "missing_checks": missing,
        "checks": checks,
    }


def status_for_score(score: float) -> str:
    if score >= 90:
        return "passed"
    if score >= 60:
        return "warning"
    return "failed"


def trace_for(strategy_id: str, task_id: str, verifier_path: str, status: str) -> dict[str, Any]:
    now = utc_now()
    return {
        "trace_id": f"strace_p57_{strategy_id}_{task_id}",
        "strategy_id": strategy_id,
        "trace_status": BOUNDARY,
        "events": [
            {
                "event_id": "evt_001",
                "type": "phone_use_contract_eval",
                "role": "PhoneUseContractVerifier",
                "step_id": "step_001",
                "started_at": now,
                "ended_at": now,
                "tool_name": "static_contract_checks",
                "evidence_id": f"phone_use_{strategy_id}_{task_id}",
                "summary": f"P5.7 phone-use contract task completed with status {status}.",
                "artifact_path": verifier_path,
            }
        ],
        "handoff_count": 0,
        "planning_revisions": 0,
        "verification_failures_recovered": 0,
        "failure_kind": None if status == "passed" else f"p57_phone_use_{status}",
    }


def write_scoreboard(path: Path, results: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows = []
    by_strategy: dict[str, list[dict[str, Any]]] = {}
    for result in results:
        by_strategy.setdefault(result["strategy_id"], []).append(result)
    for strategy_id, items in by_strategy.items():
        scores = [item["pilot_score"]["total_score"] for item in items]
        rows.append(
            {
                "strategy_id": strategy_id,
                "tasks": len(items),
                "average_phone_use_contract_score": round(sum(scores) / len(scores), 2),
                "min_phone_use_contract_score": min(scores),
                "max_phone_use_contract_score": max(scores),
                "passed": sum(1 for item in items if item["status"] == "passed"),
                "warning": sum(1 for item in items if item["status"] == "warning"),
                "failed": sum(1 for item in items if item["status"] == "failed"),
            }
        )
    rows.sort(key=lambda row: (-row["average_phone_use_contract_score"], row["strategy_id"]))
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "rank",
                "strategy_id",
                "tasks",
                "average_phone_use_contract_score",
                "min_phone_use_contract_score",
                "max_phone_use_contract_score",
                "passed",
                "warning",
                "failed",
            ],
            lineterminator="\n",
        )
        writer.writeheader()
        for index, row in enumerate(rows, 1):
            writer.writerow({"rank": index, **row})
    return rows


def write_summary(path: Path, run: dict[str, Any], scoreboard: list[dict[str, Any]]) -> None:
    spread = (
        scoreboard[0]["average_phone_use_contract_score"]
        - scoreboard[-1]["average_phone_use_contract_score"]
        if len(scoreboard) > 1
        else 0
    )
    lines = [
        "# P5.7 Android Phone-Use Contract Eval",
        "",
        f"- run_id: `{run['run_id']}`",
        f"- run_kind: `{run['run_kind']}`",
        "- counts_as_experiment: `false`",
        "- counts_as_strategy_ablation_result: `false`",
        f"- phone_use_contract_score_spread: `{round(spread, 2)}`",
        "",
        "This eval checks MobileCode's app-internal Accessibility phone-use contract. It does not grant Android Accessibility permission, does not drive another app, and does not produce a formal benchmark result.",
        "",
        "| Rank | Strategy | Contract avg | Min | Max | Passed | Warning | Failed |",
        "| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for index, row in enumerate(scoreboard, 1):
        lines.append(
            "| {rank} | `{strategy}` | {avg} | {min_score} | {max_score} | {passed} | {warning} | {failed} |".format(
                rank=index,
                strategy=row["strategy_id"],
                avg=row["average_phone_use_contract_score"],
                min_score=row["min_phone_use_contract_score"],
                max_score=row["max_phone_use_contract_score"],
                passed=row["passed"],
                warning=row["warning"],
                failed=row["failed"],
            )
        )
    lines.extend(
        [
            "",
            "## Boundary",
            "",
            "- This is a non-counted contract eval, not a runtime Android phone-use benchmark.",
            "- UI text from other apps is not stored; the contract records counts and class/package metadata only.",
            "- Runtime proof still requires emulator/real-device Accessibility authorization and adb/WebView evidence.",
            "",
        ]
    )
    path.write_text("\n".join(lines), encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", default="p57-android-phone-use-contract")
    parser.add_argument("--output", default="docs/mobile-harness-benchmark/strategy-ablation/runs/p57-android-phone-use-contract")
    parser.add_argument("--strategies", default="all")
    return parser.parse_args()


def run(args: argparse.Namespace) -> int:
    registry_payload = p5.load_json(REGISTRY_PATH)
    registry = {item["strategy_id"]: item for item in registry_payload["strategies"]}
    strategy_ids = p5.parse_strategy_ids(args.strategies, registry)
    selected_strategies = [registry[strategy_id] for strategy_id in strategy_ids]
    output_dir = ROOT / args.output if not Path(args.output).is_absolute() else Path(args.output)
    verifier_dir = output_dir / "verifier_outputs"
    trace_dir = output_dir / "strategy_traces"
    for directory in (output_dir, verifier_dir, trace_dir):
        directory.mkdir(parents=True, exist_ok=True)

    contract_checks = {
        "P57-PHONE-CONTRACT-001": {
            **manifest_service_checks(),
            **accessibility_xml_checks(),
            **{
                key: value
                for key, value in kotlin_contract_checks().items()
                if key.startswith("kotlin_") or key.startswith("method_channel_")
            },
        },
        "P57-PHONE-ACTION-SCHEMA-002": {
            key: value
            for key, value in kotlin_contract_checks().items()
            if key.endswith("_action") or key in {"perform_action_method", "dry_probe_method", "status_method"}
        },
        "P57-PHONE-BOUNDARY-003": {
            "strings_exist": FILES["strings"].is_file(),
            **{
                key: value
                for key, value in kotlin_contract_checks().items()
                if key in {"raw_text_not_returned", "redaction_flag_returned"}
            },
            **{
                key: value
                for key, value in flutter_contract_checks().items()
                if key
                in {
                    "dart_service_exists",
                    "flutter_non_counted_fallback",
                    "widget_exists",
                    "widget_title",
                    "widget_non_counted_label",
                    "widget_raw_text_label",
                    "home_mounts_widget",
                }
            },
        },
    }

    results: list[dict[str, Any]] = []
    started_run = time.time()
    for strategy in selected_strategies:
        strategy_id = strategy["strategy_id"]
        for task in TASKS:
            started = time.time()
            task_id = task["task_id"]
            score = score_checks(contract_checks[task_id])
            status = status_for_score(score["total_score"])
            verifier_path = verifier_dir / f"{task_id.lower()}_{strategy_id}.json"
            verifier_payload = {
                "strategy_id": strategy_id,
                "task_id": task_id,
                "status": status,
                "score": score,
                "files": {key: p5.relative_to_root(path) for key, path in FILES.items()},
                "counts_as_experiment": False,
                "counts_as_strategy_ablation_result": False,
            }
            verifier_path.write_text(json.dumps(verifier_payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
            trace = trace_for(strategy_id, task_id, p5.relative_to_root(verifier_path), status)
            trace_path = trace_dir / f"{strategy_id}_{task_id}.json"
            trace_path.write_text(json.dumps(trace, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
            wall_ms = int((time.time() - started) * 1000)
            verified = 1.0 if status == "passed" else 0.0
            results.append(
                {
                    "strategy_id": strategy_id,
                    "strategy_family": strategy["strategy_family"],
                    "task_id": task_id,
                    "task_category": task["task_category"],
                    "status": status,
                    "strategy_trace": trace,
                    "time_metrics": {
                        "planning_ms": 0,
                        "execution_ms": wall_ms,
                        "verification_ms": wall_ms,
                        "reporting_ms": 0,
                        "wall_ms": wall_ms,
                    },
                    "token_metrics": {
                        "prompt_tokens": 0,
                        "completion_tokens": 0,
                        "estimated_tool_io_tokens": 0,
                        "total_tokens": 0,
                        "estimated_cost_usd": 0,
                        "tokens_per_verified_success": 0 if verified else None,
                    },
                    "effect_metrics": {
                        "task_success": 1.0 if status == "passed" else 0.5 if status == "warning" else 0.0,
                        "verified_success": verified,
                        "trace_completeness": 1.0,
                        "artifact_availability": 1.0,
                        "recovery_rate": None,
                        "human_intervention_count": 0,
                        "handoff_success_rate": None,
                        "memory_reuse_score": None,
                        "steps_to_completion": 1,
                    },
                    "evidence": {
                        "boundary": BOUNDARY,
                        "artifact_paths": [],
                        "trace_paths": [p5.relative_to_root(trace_path)],
                        "screenshot_paths": [],
                        "logs": [
                            "P5.7 Android phone-use contract eval executed.",
                            "Run is non-counted and must not be cited as a formal benchmark.",
                            "Runtime Accessibility permission grant and adb/WebView proof remain separate gates.",
                        ],
                        "verifier_outputs": [p5.relative_to_root(verifier_path)],
                        "transcript_paths": [],
                        "human_intervention_notes": [],
                    },
                    "pilot_verifier": {
                        "score_boundary": score["score_boundary"],
                        "verifier_output": p5.relative_to_root(verifier_path),
                        "missing_checks": score["missing_checks"],
                    },
                    "pilot_score": score,
                    "counts_as_strategy_ablation_result": False,
                }
            )
            print(f"{strategy_id} {task_id}: {status} score={score['total_score']}")

    scoreboard = write_scoreboard(output_dir / "phone_use_contract_scoreboard.csv", results)
    summary = {
        "total": len(results),
        "strategies": len(strategy_ids),
        "tasks_per_strategy": len(TASKS),
        "passed": sum(1 for item in results if item["status"] == "passed"),
        "warning": sum(1 for item in results if item["status"] == "warning"),
        "failed": sum(1 for item in results if item["status"] == "failed"),
        "blocked": 0,
        "not_run": 0,
        "average_phone_use_contract_score": round(
            sum(item["pilot_score"]["total_score"] for item in results) / len(results),
            2,
        ),
        "wall_ms": int((time.time() - started_run) * 1000),
    }
    run_payload = {
        "benchmark": "MobileHarnessBench",
        "run_id": args.run_id,
        "created_at": utc_now(),
        "counts_as_experiment": False,
        "counts_as_strategy_ablation_result": False,
        "run_kind": RUN_KIND,
        "evidence_boundary": f"{BOUNDARY}:p57_android_phone_use_contract_eval_not_runtime",
        "strategy_family": "mixed_strategy_ablation",
        "mode": {
            "name": "P5.7 Android phone-use contract eval",
            "mode": RUN_KIND,
            "non_counted_reason": "Contract-only phone-use eval; no Accessibility permission grant or runtime adb/WebView execution.",
            "runtime_android_permission_required": True,
        },
        "strategies": [
            {
                "strategy_id": item["strategy_id"],
                "strategy_family": item["strategy_family"],
                "description": item.get("description", ""),
            }
            for item in selected_strategies
        ],
        "task_subset": {
            "name": "p57-android-phone-use-contract",
            "task_count": len(TASKS),
            "tasks": TASKS,
        },
        "results": results,
        "summary": summary,
    }
    (output_dir / "run.json").write_text(json.dumps(run_payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    write_summary(output_dir / "summary.md", run_payload, scoreboard)
    return 0


def main() -> int:
    return run(parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
