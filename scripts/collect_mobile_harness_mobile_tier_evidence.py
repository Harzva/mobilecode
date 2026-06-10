#!/usr/bin/env python3
"""Probe mobile-tier readiness for MobileHarnessBench.

The script is intentionally conservative: it records environment readiness and
device metadata when tools are available, but it does not mark benchmark tasks
as experimentally completed. Real T2/T3/T4 results still require verifier
results, traces, summaries, screenshots/logs, and task-specific evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
BENCH_ROOT = ROOT / "docs" / "mobile-harness-benchmark"
REPORT_DIR = BENCH_ROOT / "reports"
REPORT_JSON_PATH = REPORT_DIR / "mobile-tier-readiness.json"
REPORT_MD_PATH = REPORT_DIR / "mobile-tier-readiness.md"
TASK_SET_PATHS = {
    "android-device-v2": BENCH_ROOT / "tasks" / "android-device-v2.json",
    "ios-simulator-v2": BENCH_ROOT / "tasks" / "ios-simulator-v2.json",
}
DEFAULT_ANDROID_PACKAGE = "com.mobilecode.app"


def command_available(command: str) -> bool:
    return shutil.which(command) is not None


def run_command(command: list[str], timeout: int = 15) -> dict[str, Any]:
    try:
        completed = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
        )
        return {
            "available": True,
            "returncode": completed.returncode,
            "stdout": completed.stdout.strip(),
            "stderr": completed.stderr.strip(),
        }
    except FileNotFoundError:
        return {"available": False, "returncode": None, "stdout": "", "stderr": "command not found"}
    except subprocess.TimeoutExpired:
        return {"available": True, "returncode": None, "stdout": "", "stderr": "command timed out"}


def anonymize(value: str) -> str:
    digest = hashlib.sha256(value.encode("utf-8")).hexdigest()[:12]
    return f"sha256:{digest}"


def load_task_set(name: str) -> dict[str, Any]:
    payload = json.loads(TASK_SET_PATHS[name].read_text(encoding="utf-8"))
    tasks = payload.get("tasks", [])
    categories = Counter(task["category"] for task in tasks)
    return {
        "name": name,
        "path": TASK_SET_PATHS[name].relative_to(ROOT).as_posix(),
        "task_count": len(tasks),
        "categories": dict(sorted(categories.items())),
    }


def parse_adb_devices(output: str) -> list[dict[str, str]]:
    devices: list[dict[str, str]] = []
    for line in output.splitlines():
        line = line.strip()
        if not line or line.startswith("List of devices"):
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        devices.append({"serial_hash": anonymize(parts[0]), "state": parts[1]})
    return devices


def adb_shell(serial: str, args: list[str]) -> str:
    command = ["adb", "-s", serial, "shell", *args]
    result = run_command(command, timeout=10)
    return result["stdout"] if result["returncode"] == 0 else ""


def probe_android(package_name: str) -> dict[str, Any]:
    if not command_available("adb"):
        return {
            "status": "blocked",
            "blocked_reason": "adb_missing",
            "tools": {"adb": False},
            "devices": [],
            "evidence_collected": [],
        }

    devices_result = run_command(["adb", "devices"], timeout=15)
    devices = parse_adb_devices(devices_result["stdout"])
    ready_devices = [device for device in devices if device["state"] == "device"]
    if not ready_devices:
        return {
            "status": "blocked",
            "blocked_reason": "no_android_device",
            "tools": {"adb": True},
            "devices": devices,
            "evidence_collected": ["adb_devices"],
        }

    raw_serials: list[str] = []
    for line in devices_result["stdout"].splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "device":
            raw_serials.append(parts[0])

    metadata: list[dict[str, Any]] = []
    for serial in raw_serials:
        package_resolve = run_command(
            ["adb", "-s", serial, "shell", "cmd", "package", "resolve-activity", "--brief", package_name],
            timeout=10,
        )
        metadata.append(
            {
                "serial_hash": anonymize(serial),
                "platform": "android",
                "environment": "real_device_or_emulator",
                "manufacturer": adb_shell(serial, ["getprop", "ro.product.manufacturer"]),
                "model": adb_shell(serial, ["getprop", "ro.product.model"]),
                "os_version": adb_shell(serial, ["getprop", "ro.build.version.release"]),
                "sdk": adb_shell(serial, ["getprop", "ro.build.version.sdk"]),
                "viewport": adb_shell(serial, ["wm", "size"]),
                "package_name": package_name,
                "package_activity_resolves": package_resolve["returncode"] == 0
                and bool(package_resolve["stdout"].strip()),
            }
        )

    return {
        "status": "ready_for_manual_t2_collection",
        "blocked_reason": None,
        "tools": {"adb": True},
        "devices": ready_devices,
        "device_metadata": metadata,
        "evidence_collected": ["adb_devices", "device_metadata", "package_activity_probe"],
    }


def probe_ios() -> dict[str, Any]:
    xcrun_available = command_available("xcrun")
    xcodebuild_available = command_available("xcodebuild")
    if not xcrun_available:
        return {
            "status": "blocked",
            "blocked_reason": "xcrun_missing",
            "tools": {"xcrun": False, "xcodebuild": xcodebuild_available},
            "booted_simulators": [],
            "evidence_collected": [],
        }
    result = run_command(["xcrun", "simctl", "list", "devices", "booted", "-j"], timeout=20)
    booted: list[dict[str, Any]] = []
    if result["returncode"] == 0 and result["stdout"]:
        payload = json.loads(result["stdout"])
        for runtime, devices in payload.get("devices", {}).items():
            for device in devices:
                booted.append(
                    {
                        "runtime": runtime,
                        "name": device.get("name"),
                        "udid_hash": anonymize(device.get("udid", "")),
                        "state": device.get("state"),
                    }
                )
    return {
        "status": "ready_for_manual_t3_collection" if booted else "blocked",
        "blocked_reason": None if booted else "no_booted_ios_simulator",
        "tools": {"xcrun": xcrun_available, "xcodebuild": xcodebuild_available},
        "booted_simulators": booted,
        "evidence_collected": ["simctl_booted_devices"] if booted else ["simctl_probe"],
    }


def build_report(package_name: str) -> dict[str, Any]:
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    android = probe_android(package_name)
    ios = probe_ios()
    return {
        "report": "mobile-tier-readiness",
        "generated_at": generated_at,
        "counts_as_experiment": False,
        "evidence_boundary": (
            "Readiness probe only. A paper-counted mobile run still requires run.json, "
            "summary.md, traces.jsonl, screenshots/logs and task-specific verifier results."
        ),
        "tool_availability": {
            "adb": command_available("adb"),
            "emulator": command_available("emulator"),
            "flutter": command_available("flutter"),
            "xcrun": command_available("xcrun"),
            "xcodebuild": command_available("xcodebuild"),
        },
        "task_sets": {
            "android-device-v2": load_task_set("android-device-v2"),
            "ios-simulator-v2": load_task_set("ios-simulator-v2"),
        },
        "android": android,
        "ios": ios,
        "next_required_actions": [
            "Install Android SDK platform-tools and connect a real Android device for T2 evidence.",
            "Install Flutter locally or provide a built APK before app-level Android task execution.",
            "Run iOS simulator collection on a Mac with Xcode for T3 evidence.",
            "Keep T2/T3/T4 results separate from T0 fixture results in paper tables.",
        ],
    }


def write_markdown(report: dict[str, Any]) -> None:
    lines = [
        "# MobileHarnessBench Mobile-Tier Readiness",
        "",
        f"Generated at: `{report['generated_at']}`",
        "",
        "## Evidence Boundary",
        "",
        report["evidence_boundary"],
        "",
        "This report is not a benchmark run and must not be counted as Android/iOS experimental evidence.",
        "",
        "## Tool Availability",
        "",
        "| Tool | Available |",
        "| --- | --- |",
    ]
    for tool, available in report["tool_availability"].items():
        lines.append(f"| `{tool}` | {str(available).lower()} |")

    lines.extend(
        [
            "",
            "## Task Sets Waiting For Mobile Evidence",
            "",
            "| Task set | Tasks | Categories | Manifest |",
            "| --- | ---: | --- | --- |",
        ]
    )
    for task_set in report["task_sets"].values():
        categories = ", ".join(f"{key}={value}" for key, value in task_set["categories"].items())
        lines.append(f"| `{task_set['name']}` | {task_set['task_count']} | {categories} | `{task_set['path']}` |")

    lines.extend(
        [
            "",
            "## Current Probe Result",
            "",
            f"- Android status: `{report['android']['status']}`",
            f"- Android blocked reason: `{report['android']['blocked_reason']}`",
            f"- iOS status: `{report['ios']['status']}`",
            f"- iOS blocked reason: `{report['ios']['blocked_reason']}`",
            "",
            "## Next Required Actions",
            "",
        ]
    )
    for action in report["next_required_actions"]:
        lines.append(f"- {action}")
    lines.append("")
    REPORT_MD_PATH.write_text("\n".join(lines), encoding="utf-8", newline="")


def write_report(report: dict[str, Any]) -> None:
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    REPORT_JSON_PATH.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    write_markdown(report)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--android-package", default=DEFAULT_ANDROID_PACKAGE)
    args = parser.parse_args()
    report = build_report(args.android_package)
    write_report(report)
    print("MobileHarnessBench mobile-tier readiness probe completed")
    print(f"report_md={REPORT_MD_PATH.relative_to(ROOT).as_posix()}")
    print(f"report_json={REPORT_JSON_PATH.relative_to(ROOT).as_posix()}")
    print(f"android_status={report['android']['status']}")
    print(f"ios_status={report['ios']['status']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
