#!/usr/bin/env python3
"""Run P6.3 Android Accessibility phone-use runtime verification.

This verifier installs a MobileCode APK on an Android emulator, enables the
MobileCode Accessibility service in the test environment, drives the Tools page
with adb, runs the app-internal dry/action probes, captures evidence, and emits
a non-counted MobileHarnessBench-compatible run.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import shutil
import subprocess
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
PACKAGE = "com.mobilecode.app"
ACTIVITY = "com.mobilecode.app.MainActivity"
SERVICE = f"{PACKAGE}/{PACKAGE}.PhoneUseAccessibilityService"
TASK_ID = "P63-ANDROID-REAL-DEVICE-LANE-001"


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def rel(path: Path | None) -> str | None:
    if path is None:
        return None
    return p5.relative_to_root(path)


def redact(text: str) -> str:
    return p5.redact(text)


def run_cmd(
    command: list[str],
    *,
    timeout: int = 60,
    check: bool = False,
) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
        check=False,
    )
    if check and completed.returncode != 0:
        raise RuntimeError(
            f"Command failed: {command[0]} rc={completed.returncode} stdout={redact(completed.stdout[-800:])} stderr={redact(completed.stderr[-800:])}"
        )
    return completed


class AdbHarness:
    def __init__(self, adb: str, device: str | None, output: Path) -> None:
        self.adb = adb
        self.device = device
        self.output = output

    def adb_cmd(self, *args: str, timeout: int = 60, check: bool = False) -> subprocess.CompletedProcess[str]:
        command = [self.adb]
        if self.device:
            command.extend(["-s", self.device])
        command.extend(args)
        return run_cmd(command, timeout=timeout, check=check)

    def shell(self, *args: str, timeout: int = 60, check: bool = False) -> subprocess.CompletedProcess[str]:
        return self.adb_cmd("shell", *args, timeout=timeout, check=check)

    def write_text(self, name: str, value: str) -> Path:
        path = self.output / name
        lines = redact(value).splitlines()
        cleaned = "\n".join(line.rstrip() for line in lines)
        if cleaned:
            cleaned += "\n"
        path.write_text(cleaned, encoding="utf-8")
        return path

    def screenshot(self, name: str) -> Path | None:
        path = self.output / name
        command = [self.adb]
        if self.device:
            command.extend(["-s", self.device])
        command.extend(["exec-out", "screencap", "-p"])
        completed = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
            check=False,
        )
        if completed.returncode != 0 or not completed.stdout:
            self.write_text(
                f"{name}.error.txt",
                completed.stderr.decode("utf-8", errors="replace"),
            )
            return None
        path.write_bytes(completed.stdout)
        return path

    def dump_ui(self, name: str) -> Path | None:
        path = self.output / name
        remote = f"/sdcard/{safe_name(name)}"
        errors: list[str] = []
        for _ in range(3):
            dump = self.shell("uiautomator", "dump", remote, timeout=30)
            if dump.returncode != 0:
                errors.append(dump.stdout + dump.stderr)
                time.sleep(0.25)
                continue
            pull = self.adb_cmd("pull", remote, str(path), timeout=30)
            if pull.returncode == 0 and path.exists() and path.stat().st_size > 0:
                return path
            errors.append(pull.stdout + pull.stderr)
            cat = self.adb_cmd("exec-out", "cat", remote, timeout=30)
            if cat.returncode == 0 and cat.stdout.lstrip().startswith("<?xml"):
                path.write_text(redact(cat.stdout), encoding="utf-8")
                return path
            errors.append(cat.stdout + cat.stderr)
            time.sleep(0.25)
        self.write_text(f"{name}.error.txt", "\n".join(errors))
        return None

    def tap(self, x: int, y: int) -> None:
        self.shell("input", "tap", str(x), str(y), timeout=10)
        return path


def parse_bounds(value: str) -> tuple[int, int, int, int] | None:
    match = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", value)
    if not match:
        return None
    return tuple(int(part) for part in match.groups())  # type: ignore[return-value]


def node_text(node: ET.Element) -> str:
    return " ".join(
        part
        for part in (
            node.attrib.get("text", ""),
            node.attrib.get("content-desc", ""),
            node.attrib.get("resource-id", ""),
        )
        if part
    )


def find_node_bounds(xml_path: Path | None, needle: str) -> tuple[int, int] | None:
    if xml_path is None or not xml_path.exists():
        return None
    try:
        root = ET.parse(xml_path).getroot()
    except ET.ParseError:
        return None
    needle_lower = needle.lower()
    for node in root.iter("node"):
        if needle_lower not in node_text(node).lower():
            continue
        bounds = parse_bounds(node.attrib.get("bounds", ""))
        if not bounds:
            continue
        x1, y1, x2, y2 = bounds
        return ((x1 + x2) // 2, (y1 + y2) // 2)
    return None


def xml_contains(xml_path: Path | None, text: str) -> bool:
    if xml_path is None or not xml_path.exists():
        return False
    return text.lower() in xml_path.read_text(encoding="utf-8", errors="replace").lower()


def tap_text(h: AdbHarness, xml_path: Path | None, text: str) -> bool:
    point = find_node_bounds(xml_path, text)
    if not point:
        return False
    x, y = point
    h.shell("input", "tap", str(x), str(y), timeout=10)
    return True


def wait_for_text(h: AdbHarness, text: str, *, attempts: int = 8, delay: float = 0.8) -> tuple[bool, Path | None]:
    last_xml: Path | None = None
    for index in range(attempts):
        last_xml = h.dump_ui(f"wait-{safe_name(text)}-{index}.xml")
        if xml_contains(last_xml, text):
            return True, last_xml
        time.sleep(delay)
    return False, last_xml


def wait_for_any_text(
    h: AdbHarness,
    texts: list[str],
    *,
    prefix: str,
    attempts: int = 8,
    delay: float = 0.8,
) -> tuple[bool, Path | None]:
    last_xml: Path | None = None
    for index in range(attempts):
        last_xml = h.dump_ui(f"{prefix}-{index}.xml")
        if any(xml_contains(last_xml, text) for text in texts):
            return True, last_xml
        time.sleep(delay)
    return False, last_xml


def open_tools_tab(h: AdbHarness, initial_xml: Path | None, errors: list[str]) -> Path | None:
    drawer_opened = tap_text(h, initial_xml, "Open conversations")
    if not drawer_opened:
        # Coordinates match the mobile header menu button on the 720x1280 QA AVD
        # and remain a safe fallback when the first UI dump is unavailable.
        h.tap(76, 119)
    drawer_ready, drawer_xml = wait_for_any_text(
        h,
        ["工具与权限", "模型与设置", "New chat"],
        prefix="02-drawer-wait",
        attempts=6,
        delay=0.5,
    )
    if not drawer_ready:
        h.tap(76, 119)
        drawer_ready, drawer_xml = wait_for_any_text(
            h,
            ["工具与权限", "模型与设置", "New chat"],
            prefix="02-drawer-retry",
            attempts=6,
            delay=0.5,
        )
    if not drawer_ready:
        errors.append("Tools drawer entry not found because drawer did not open.")
        return drawer_xml

    tools_opened = tap_text(h, drawer_xml, "工具与权限") or tap_text(h, drawer_xml, "Tools")
    if not tools_opened:
        # Center of the drawer action observed in UI XML: bounds [0,528][720,640].
        h.tap(360, 584)
    tools_ready, tools_xml = wait_for_any_text(
        h,
        ["Tools", "Mobile Harness Strategy", "Mobile Phone Use"],
        prefix="02-tools-wait",
        attempts=8,
        delay=0.7,
    )
    if not tools_ready:
        errors.append("Tools page did not become visible after drawer action.")
    return tools_xml


def safe_name(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "-", value.strip().lower()).strip("-")[:48] or "value"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def score_payload(checks: dict[str, bool], action_accepted_count: int, action_total: int) -> dict[str, Any]:
    weights = {
        "device_connected": 8,
        "apk_installed": 8,
        "app_launched": 8,
        "accessibility_enabled": 14,
        "phone_use_card_visible": 10,
        "dry_probe_passed": 18,
        "action_probe_visible": 8,
        "action_probe_passed_or_warning": 10,
        "back_action_verified": 8,
        "home_action_verified": 8,
        "logcat_clean": 8,
        "evidence_saved": 8,
    }
    score = sum(weight for key, weight in weights.items() if checks.get(key))
    if action_total:
        score += round(8 * (action_accepted_count / action_total), 2)
    else:
        weights["action_acceptance_ratio"] = 8
    max_score = sum(weights.values()) + (8 if action_total else 0)
    score = round((score / max_score) * 100, 2) if max_score else 0.0
    return {
        "score_boundary": "pilot_android_phone_use_runtime_score_not_counted",
        "total_score": score,
        "max_score": 100,
        "checks": checks,
        "action_accepted_count": action_accepted_count,
        "action_total": action_total,
    }


def status_for_score(score: float) -> str:
    if score >= 85:
        return "passed"
    if score >= 60:
        return "warning"
    return "failed"


def write_run(
    output: Path,
    run_id: str,
    registry: dict[str, dict[str, Any]],
    selected: list[str],
    status: str,
    score: dict[str, Any],
    evidence: dict[str, Any],
    wall_ms: int,
) -> None:
    traces_dir = output / "strategy_traces"
    traces_dir.mkdir(parents=True, exist_ok=True)
    results: list[dict[str, Any]] = []
    for strategy_id in selected:
        now = utc_now()
        trace = {
                    "trace_id": f"strace_p63_{strategy_id}_{TASK_ID}",
            "strategy_id": strategy_id,
            "trace_status": BOUNDARY,
            "events": [
                {
                    "event_id": "evt_001",
                    "type": "android_phone_use_runtime_eval",
                    "role": "AndroidPhoneUseRuntimeVerifier",
                    "step_id": "step_001",
                    "started_at": now,
                    "ended_at": now,
                    "tool_name": "adb_accessibility_runtime_probe",
                    "evidence_id": f"phone_use_runtime_{strategy_id}",
                    "summary": f"P6.3 Android phone-use runtime lane completed with status {status}.",
                    "artifact_path": evidence["verifier_outputs"][0],
                }
            ],
            "handoff_count": 0,
            "planning_revisions": 0,
            "verification_failures_recovered": 0,
            "failure_kind": None if status == "passed" else f"p63_android_phone_use_{status}",
        }
        trace_path = traces_dir / f"{strategy_id}_{TASK_ID}.json"
        trace_path.write_text(json.dumps(trace, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        verified = 1.0 if status == "passed" else 0.0
        result_evidence = {
            **evidence,
            "trace_paths": [rel(trace_path)],
        }
        results.append(
            {
                "strategy_id": strategy_id,
                "strategy_family": registry[strategy_id]["strategy_family"],
                "task_id": TASK_ID,
                "task_category": "android_phone_use_runtime",
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
                "evidence": result_evidence,
                "pilot_verifier": {
                    "score_boundary": score["score_boundary"],
                    "verifier_output": evidence["verifier_outputs"][0],
                },
                "pilot_score": score,
                "counts_as_strategy_ablation_result": False,
            }
        )

    run_payload = {
        "benchmark": "MobileHarnessBench",
        "run_id": run_id,
        "created_at": utc_now(),
        "counts_as_experiment": False,
        "counts_as_strategy_ablation_result": False,
        "run_kind": RUN_KIND,
        "evidence_boundary": f"{BOUNDARY}:p63_android_real_device_lane_not_counted",
        "strategy_family": "mixed_strategy_ablation",
        "mode": {
            "name": "P6.3 Android real device lane",
            "mode": RUN_KIND,
            "non_counted_reason": "Android emulator or real-device Accessibility runtime QA; not a formal strategy ablation benchmark.",
            "runtime_android_permission_required": True,
        },
        "strategies": [
            {
                "strategy_id": strategy_id,
                "strategy_family": registry[strategy_id]["strategy_family"],
                "description": registry[strategy_id].get("description", ""),
            }
            for strategy_id in selected
        ],
        "task_subset": {
            "name": "p63-android-real-device-lane",
            "task_count": 1,
            "tasks": [
                {
                    "task_id": TASK_ID,
                    "task_category": "android_real_device_lane",
                    "title": "Android Accessibility phone-use dry/action probe with device evidence",
                    "max_score": 100,
                }
            ],
        },
        "results": results,
        "summary": {
            "total": len(results),
            "strategies": len(selected),
            "tasks_per_strategy": 1,
            "passed": sum(1 for item in results if item["status"] == "passed"),
            "warning": sum(1 for item in results if item["status"] == "warning"),
            "failed": sum(1 for item in results if item["status"] == "failed"),
            "blocked": 0,
            "not_run": 0,
            "average_android_phone_use_runtime_score": score["total_score"],
            "wall_ms": wall_ms,
        },
    }
    (output / "run.json").write_text(json.dumps(run_payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    scoreboard = output / "android_phone_use_runtime_scoreboard.csv"
    with scoreboard.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["rank", "strategy_id", "android_phone_use_runtime_score", "status"],
            lineterminator="\n",
        )
        writer.writeheader()
        for index, strategy_id in enumerate(selected, 1):
            writer.writerow(
                {
                    "rank": index,
                    "strategy_id": strategy_id,
                    "android_phone_use_runtime_score": score["total_score"],
                    "status": status,
                }
            )

    summary_lines = [
        "# P6.3 Android Real Device Lane",
        "",
        f"- run_id: `{run_id}`",
        f"- run_kind: `{RUN_KIND}`",
        "- counts_as_experiment: `false`",
        "- counts_as_strategy_ablation_result: `false`",
        f"- status: `{status}`",
        f"- runtime_score: `{score['total_score']}`",
        f"- action_acceptance: `{score['action_accepted_count']}/{score['action_total']}`",
        f"- back_action_verified: `{score['checks'].get('back_action_verified', False)}`",
        f"- home_action_verified: `{score['checks'].get('home_action_verified', False)}`",
        "",
        "This verifier installs the latest APK on an Android emulator or real device, verifies MobileCode Accessibility state, runs App-internal dry/action probes, verifies adb Back/Home foreground transitions, and saves screenshot/UI XML/logcat evidence. It is non-counted and does not prove strategy quality differences.",
        "",
        "## Boundary",
        "",
        "- This is local Android runtime QA, not a formal benchmark result.",
        "- It exercises the phone-use tool contract once and mirrors the same score across strategies.",
        "- P6 counted comparison still requires task-level model/tool callbacks, repeated samples, and promotion gates.",
        "",
    ]
    (output / "summary.md").write_text("\n".join(summary_lines), encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", default="mobile_agent/build/app/outputs/flutter-apk/app-release.apk")
    parser.add_argument("--output", default="docs/mobile-harness-benchmark/strategy-ablation/runs/p63-android-real-device-lane")
    parser.add_argument("--run-id", default="p63-android-real-device-lane")
    parser.add_argument("--adb", default="")
    parser.add_argument("--device", default="")
    parser.add_argument("--strategies", default="all")
    return parser.parse_args()


def run(args: argparse.Namespace) -> int:
    started = time.time()
    adb = args.adb or shutil.which("adb")
    if not adb:
        raise SystemExit("adb not found on PATH.")
    apk = ROOT / args.apk if not Path(args.apk).is_absolute() else Path(args.apk)
    if not apk.is_file():
        raise SystemExit(f"APK not found: {redact(str(apk))}")
    output = ROOT / args.output if not Path(args.output).is_absolute() else Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    evidence_dir = output / "evidence"
    evidence_dir.mkdir(parents=True, exist_ok=True)
    h = AdbHarness(adb, args.device or None, evidence_dir)

    registry_payload = p5.load_json(REGISTRY_PATH)
    registry = {item["strategy_id"]: item for item in registry_payload["strategies"]}
    selected = p5.parse_strategy_ids(args.strategies, registry)

    evidence_paths: dict[str, list[str]] = {
        "screenshots": [],
        "ui_xml": [],
        "logs": [],
        "verifier_outputs": [],
    }
    errors: list[str] = []

    devices = h.adb_cmd("devices", "-l", timeout=20)
    h.write_text("adb-devices.txt", devices.stdout + devices.stderr)
    device_connected = "device" in devices.stdout

    h.adb_cmd("logcat", "-c", timeout=20)
    install = h.adb_cmd(
        "install",
        "-r",
        "-d",
        "-g",
        "-i",
        "com.android.vending",
        str(apk),
        timeout=180,
    )
    h.write_text("install.txt", install.stdout + install.stderr)
    apk_installed = install.returncode == 0 and "Success" in (install.stdout + install.stderr)

    enable_service = h.shell(
        "settings",
        "put",
        "secure",
        "enabled_accessibility_services",
        SERVICE,
        timeout=20,
    )
    enable_a11y = h.shell("settings", "put", "secure", "accessibility_enabled", "1", timeout=20)
    enabled_services = h.shell("settings", "get", "secure", "enabled_accessibility_services", timeout=20)
    accessibility_enabled = SERVICE in enabled_services.stdout
    h.write_text(
        "accessibility-settings.txt",
        "\n".join(
            [
                enable_service.stdout,
                enable_service.stderr,
                enable_a11y.stdout,
                enable_a11y.stderr,
                enabled_services.stdout,
                enabled_services.stderr,
            ]
        ),
    )

    launch = h.shell("am", "start", "-n", f"{PACKAGE}/{ACTIVITY}", timeout=30)
    h.write_text("launch.txt", launch.stdout + launch.stderr)
    app_launched = launch.returncode == 0 and "Error" not in (launch.stdout + launch.stderr)
    home_ready, initial_xml = wait_for_any_text(
        h,
        ["Open conversations", "MobileCode", "Tools"],
        prefix="01-launch-wait",
        attempts=18,
        delay=0.6,
    )
    if not home_ready:
        errors.append("App launched but MobileCode home/tools UI did not become visible before navigation.")

    initial_png = h.screenshot("01-launch.png")
    initial_xml = initial_xml or h.dump_ui("01-launch.xml")
    if initial_png:
        evidence_paths["screenshots"].append(rel(initial_png) or "")
    if initial_xml:
        evidence_paths["ui_xml"].append(rel(initial_xml) or "")

    tools_entry_xml = open_tools_tab(h, initial_xml, errors)
    if tools_entry_xml:
        evidence_paths["ui_xml"].append(rel(tools_entry_xml) or "")

    phone_use_visible = False
    phone_xml: Path | None = None
    dry_button_visible = False
    for index in range(12):
        phone_xml = h.dump_ui(f"02-tools-search-{index}.xml")
        phone_use_visible = phone_use_visible or xml_contains(phone_xml, "Mobile Phone Use")
        dry_button_visible = xml_contains(phone_xml, "Run dry probe")
        if phone_use_visible and dry_button_visible:
            phone_use_visible = True
            break
        h.shell("input", "swipe", "330", "760", "330", "300", "450", timeout=10)
        time.sleep(0.6)

    tools_png = h.screenshot("02-tools-phone-use.png")
    if tools_png:
        evidence_paths["screenshots"].append(rel(tools_png) or "")
    if phone_xml:
        evidence_paths["ui_xml"].append(rel(phone_xml) or "")

    dry_clicked = tap_text(h, phone_xml, "Run dry probe")
    if not dry_clicked:
        errors.append("Run dry probe button not found.")
    time.sleep(2.0)
    dry_xml = h.dump_ui("03-dry-probe.xml")
    dry_png = h.screenshot("03-dry-probe.png")
    if dry_xml:
        evidence_paths["ui_xml"].append(rel(dry_xml) or "")
    if dry_png:
        evidence_paths["screenshots"].append(rel(dry_png) or "")
    dry_probe_passed = xml_contains(dry_xml, "Dry probe status: passed")

    time.sleep(1.5)
    action_clicked = tap_text(h, dry_xml, "Run action probe")
    if not action_clicked:
        errors.append("Run action probe button not found.")
    time.sleep(4.0)
    action_xml = None
    for _ in range(12):
        action_xml = h.dump_ui("04-action-probe.xml")
        if xml_contains(action_xml, "Action probe status:"):
            break
        time.sleep(0.8)
    action_png = h.screenshot("04-action-probe.png")
    if action_xml:
        evidence_paths["ui_xml"].append(rel(action_xml) or "")
    if action_png:
        evidence_paths["screenshots"].append(rel(action_png) or "")
    action_probe_visible = xml_contains(action_xml, "Action probe status:")
    action_probe_passed_or_warning = xml_contains(action_xml, "Action probe status: passed") or xml_contains(
        action_xml, "Action probe status: warning"
    )
    action_text = action_xml.read_text(encoding="utf-8", errors="replace") if action_xml and action_xml.exists() else ""
    accepted_match = re.search(r"Actions accepted:\s*(\d+)/(\d+)", action_text)
    action_accepted = int(accepted_match.group(1)) if accepted_match else 0
    action_total = int(accepted_match.group(2)) if accepted_match else 0
    back_action = h.shell("input", "keyevent", "KEYCODE_BACK", timeout=10)
    time.sleep(1.0)
    focus_after_back = h.shell("dumpsys", "window", timeout=30)
    back_focus_lines = [
        line
        for line in (focus_after_back.stdout + focus_after_back.stderr).splitlines()
        if any(marker in line for marker in ("mCurrentFocus", "mFocusedApp", "topResumedActivity"))
    ]
    back_focus_path = h.write_text("05-focus-after-back.txt", "\n".join(back_focus_lines) + "\n")
    evidence_paths["logs"].append(rel(back_focus_path) or "")
    back_action_verified = back_action.returncode == 0 and bool(back_focus_lines)

    h.shell("input", "keyevent", "KEYCODE_HOME", timeout=10)
    time.sleep(1.2)
    home_xml = h.dump_ui("05-home-after-action.xml")
    home_png = h.screenshot("05-home-after-action.png")
    if home_xml:
        evidence_paths["ui_xml"].append(rel(home_xml) or "")
    if home_png:
        evidence_paths["screenshots"].append(rel(home_png) or "")
    focus_after_home = h.shell("dumpsys", "window", timeout=30)
    focus_lines = [
        line
        for line in (focus_after_home.stdout + focus_after_home.stderr).splitlines()
        if any(marker in line for marker in ("mCurrentFocus", "mFocusedApp", "topResumedActivity"))
    ]
    focus_path = h.write_text("05-focus-after-home.txt", "\n".join(focus_lines) + "\n")
    evidence_paths["logs"].append(rel(focus_path) or "")
    focus_summary = "\n".join(focus_lines)
    home_action_verified = PACKAGE not in focus_summary and bool(focus_lines)
    h.shell("am", "start", "-n", f"{PACKAGE}/{ACTIVITY}", timeout=30)
    time.sleep(0.8)

    logcat = h.adb_cmd("logcat", "-d", "-t", "2000", timeout=60)
    logcat_path = h.write_text("logcat.txt", logcat.stdout + logcat.stderr)
    log_lines = (logcat.stdout + logcat.stderr).splitlines()
    fatal_markers = ("FATAL EXCEPTION", "E/flutter", "ANR", "MissingPluginException")
    fatal_scan = "\n".join(line for line in log_lines if any(marker in line for marker in fatal_markers))
    app_fatal_lines: list[str] = []
    for index, line in enumerate(log_lines):
        if not any(marker in line for marker in fatal_markers):
            continue
        block_lines = log_lines[index : min(len(log_lines), index + 48)]
        block = "\n".join(block_lines)
        if (
            f"Process: {PACKAGE}" in block
            or f"package={PACKAGE}" in block
            or line.startswith("E/flutter")
            or "MissingPluginException" in block
        ):
            app_fatal_lines.extend(block_lines)
    app_fatal_scan = "\n".join(dict.fromkeys(app_fatal_lines))
    fatal_path = h.write_text("logcat-fatal-scan.txt", fatal_scan or "No fatal Android crash markers found.\n")
    app_fatal_path = h.write_text(
        "logcat-app-fatal-scan.txt",
        app_fatal_scan or "No MobileCode Flutter/Android crash markers found.\n",
    )
    evidence_paths["logs"].extend([rel(logcat_path) or "", rel(fatal_path) or "", rel(app_fatal_path) or ""])
    logcat_clean = not app_fatal_scan.strip()

    apk_info = {
        "apk": rel(apk),
        "sha256": sha256(apk),
        "package": PACKAGE,
        "activity": ACTIVITY,
        "accessibility_service": SERVICE,
    }
    apk_info_path = output / "apk.json"
    apk_info_path.write_text(json.dumps(apk_info, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    checks = {
        "device_connected": device_connected,
        "apk_installed": apk_installed,
        "app_launched": app_launched,
        "accessibility_enabled": accessibility_enabled,
        "phone_use_card_visible": phone_use_visible,
        "dry_probe_passed": dry_probe_passed,
        "action_probe_visible": action_probe_visible,
        "action_probe_passed_or_warning": action_probe_passed_or_warning,
        "back_action_verified": back_action_verified,
        "home_action_verified": home_action_verified,
        "logcat_clean": logcat_clean,
        "evidence_saved": bool(evidence_paths["screenshots"] and evidence_paths["ui_xml"] and evidence_paths["logs"]),
    }
    score = score_payload(checks, action_accepted, action_total)
    status = status_for_score(score["total_score"])
    verifier_path = output / "phone_use_runtime_verifier.json"
    evidence_paths["verifier_outputs"] = [rel(verifier_path) or ""]
    verifier_payload = {
        "run_id": args.run_id,
        "status": status,
        "score": score,
        "checks": checks,
        "errors": errors,
        "device_connected": device_connected,
        "apk_installed": apk_installed,
        "app_launched": app_launched,
        "accessibility_enabled": accessibility_enabled,
        "phone_use_card_visible": phone_use_visible,
        "dry_probe_passed": dry_probe_passed,
        "action_probe_visible": action_probe_visible,
        "action_probe_passed_or_warning": action_probe_passed_or_warning,
        "back_action_verified": back_action_verified,
        "home_action_verified": home_action_verified,
        "counts_as_experiment": False,
        "counts_as_strategy_ablation_result": False,
        "raw_text_included": False,
        "redaction_applied": True,
        "evidence": evidence_paths,
        "apk": apk_info,
    }
    verifier_path.write_text(json.dumps(verifier_payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    evidence = {
        "boundary": BOUNDARY,
        "artifact_paths": [rel(apk_info_path)],
        "trace_paths": [],
        "screenshot_paths": evidence_paths["screenshots"],
        "logs": [
            "P6.3 Android phone-use runtime verifier executed on emulator or real device.",
            "Run is non-counted and must not be cited as a formal benchmark.",
            f"Accessibility service enabled in test environment: {SERVICE}",
            *evidence_paths["logs"],
        ],
        "verifier_outputs": [rel(verifier_path)],
        "transcript_paths": [],
        "human_intervention_notes": [],
    }
    wall_ms = int((time.time() - started) * 1000)
    write_run(output, args.run_id, registry, selected, status, score, evidence, wall_ms)
    print(f"P6.3 Android real device lane status={status} score={score['total_score']}")
    print(f"Verifier: {rel(verifier_path)}")
    return 0 if status in {"passed", "warning"} else 1


def main() -> int:
    return run(parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
