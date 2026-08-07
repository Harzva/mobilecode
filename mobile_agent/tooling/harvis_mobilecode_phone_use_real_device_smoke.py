#!/usr/bin/env python3
"""Physical Android phone-use proof lane for MobileCode.

This lane is deliberately opt-in: it refuses emulators and refuses physical
devices unless both --serial and --allow-real-device are present.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def utc_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")


def run(command: list[str], *, output: Path | None = None, binary: bool = False) -> subprocess.CompletedProcess:
    completed = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    stdout = completed.stdout if binary else completed.stdout.decode(errors="replace")
    stderr = completed.stderr.decode(errors="replace")
    if output:
      if binary:
        output.write_bytes(completed.stdout)
      else:
        output.write_text(redact(f"{stdout}{stderr}"), encoding="utf-8")
    return completed


def redact(text: str) -> str:
    text = re.sub(r"(?i)(bearer\s+)[A-Za-z0-9._-]+", r"\1<redacted>", text)
    text = re.sub(r"(?i)[A-Za-z0-9_]*(token|cookie|secret|password)[A-Za-z0-9_]*=\S+", "redacted=<redacted>", text)
    return re.sub(r"/(?:Users|Volumes|private|var/folders)/\S+", "/[local-path]", text)


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def blocked(out: Path, reason: str) -> int:
    out.mkdir(parents=True, exist_ok=True)
    write_json(
        out / "summary.json",
        {
            "schema": "harvis_mobilecode_phone_use_real_device_smoke.v1",
            "ok": False,
            "blocked": True,
            "blocked_reason": reason,
            "boundary": "Physical Android device proof requires explicit serial and --allow-real-device.",
        },
    )
    return 2


def adb(serial: str, *args: str) -> list[str]:
    return ["adb", "-s", serial, *args]


def online_device_line(serial: str, devices_text: str) -> str:
    for line in devices_text.splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 2 and parts[0] == serial and parts[1] == "device":
            return line
    return ""


def is_emulator(serial: str, device_line: str) -> bool:
    return (
        serial.startswith("emulator-")
        or serial.startswith("127.0.0.1:")
        or serial.startswith("localhost:")
        or "device:emu" in device_line
    )


def find_edit_text_center(xml_path: Path) -> tuple[int, int, dict[str, Any]]:
    root = ET.parse(xml_path).getroot()
    for node in root.iter("node"):
        if "EditText" not in node.attrib.get("class", ""):
            continue
        bounds = node.attrib.get("bounds", "")
        match = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", bounds)
        if not match:
            continue
        x1, y1, x2, y2 = map(int, match.groups())
        target = {
            "strategy": "first_edit_text",
            "class": node.attrib.get("class", ""),
            "bounds": bounds,
            "x": (x1 + x2) // 2,
            "y": (y1 + y2) // 2,
        }
        return target["x"], target["y"], target
    raise RuntimeError("No EditText node found in UI hierarchy.")


def adb_safe_text(value: str) -> str:
    cleaned = "".join(char for char in value if char.isalnum() or char in "._-")
    return cleaned[:80] or "HarvisP5RealDevice"


def main(argv: list[str]) -> int:
    script_dir = Path(__file__).resolve().parent
    mobile_agent = script_dir.parent
    stamp = utc_stamp()
    parser = argparse.ArgumentParser(description="Run MobileCode P5 physical Android phone-use proof.")
    parser.add_argument("--serial", required=True)
    parser.add_argument("--allow-real-device", action="store_true")
    parser.add_argument("--apk", default=str(mobile_agent / "build/app/outputs/flutter-apk/app-debug.apk"))
    parser.add_argument("--package", default="com.mobilecode.app")
    parser.add_argument("--activity", default=".MainActivity")
    parser.add_argument("--output", default=str(mobile_agent / "qa-output" / f"harvis-mobilecode-phone-use-real-device-{stamp}"))
    parser.add_argument("--text", default=f"HarvisP5RealDevice{stamp.replace('-', '')}")
    parser.add_argument("--tap-x", type=int)
    parser.add_argument("--tap-y", type=int)
    parser.add_argument("--skip-install", action="store_true")
    args = parser.parse_args(argv)

    out = Path(args.output)
    out.mkdir(parents=True, exist_ok=True)
    if not args.allow_real_device:
        return blocked(out, "missing_allow_real_device")

    devices = run(["adb", "devices", "-l"])
    devices_text = devices.stdout.decode(errors="replace")
    (out / "adb-devices.txt").write_text(devices_text, encoding="utf-8")
    line = online_device_line(args.serial, devices_text)
    if not line:
        return blocked(out, "serial_not_online")
    if is_emulator(args.serial, line):
        return blocked(out, "emulator_not_allowed_in_real_device_lane")

    input_text = adb_safe_text(args.text)
    (out / "run-context.txt").write_text(
        "\n".join(
            [
                f"serial={args.serial}",
                f"package={args.package}",
                f"activity={args.activity}",
                f"input_text={input_text}",
                f"created_at={datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')}",
                "boundary=physical_android_explicit_allow",
            ]
        )
        + "\n",
        encoding="utf-8",
    )

    props = {
        "model": run(adb(args.serial, "shell", "getprop", "ro.product.model")).stdout.decode(errors="replace").strip(),
        "manufacturer": run(adb(args.serial, "shell", "getprop", "ro.product.manufacturer")).stdout.decode(errors="replace").strip(),
        "android_release": run(adb(args.serial, "shell", "getprop", "ro.build.version.release")).stdout.decode(errors="replace").strip(),
        "android_sdk": run(adb(args.serial, "shell", "getprop", "ro.build.version.sdk")).stdout.decode(errors="replace").strip(),
    }
    write_json(out / "device-props.json", props)

    install_exit = 0
    if args.skip_install:
        (out / "install.txt").write_text("skip-install=true\n", encoding="utf-8")
    else:
        apk = Path(args.apk)
        if not apk.exists():
            return blocked(out, "apk_missing")
        run(adb(args.serial, "install", "-r", "-d", str(apk)), output=out / "install.txt")
        install_exit = int(run(adb(args.serial, "shell", "echo", "0")).returncode)
        install_text = (out / "install.txt").read_text(encoding="utf-8", errors="replace")
        install_exit = 0 if "Success" in install_text else 1

    run(adb(args.serial, "logcat", "-c"))
    launch = run(adb(args.serial, "shell", "am", "start", "-W", "-n", f"{args.package}/{args.activity}"), output=out / "launch.txt")
    launch_exit = launch.returncode
    time.sleep(2)

    run(adb(args.serial, "exec-out", "screencap", "-p"), output=out / "observe-before.png", binary=True)
    run(adb(args.serial, "shell", "uiautomator", "dump", "/sdcard/harvis-mobilecode-real-before.xml"), output=out / "uiautomator-before.txt")
    run(adb(args.serial, "pull", "/sdcard/harvis-mobilecode-real-before.xml", str(out / "window-before.xml")), output=out / "uiautomator-before-pull.txt")

    if args.tap_x is not None and args.tap_y is not None:
        tap_x, tap_y = args.tap_x, args.tap_y
        target = {"strategy": "explicit_coordinates", "x": tap_x, "y": tap_y}
    else:
        tap_x, tap_y, target = find_edit_text_center(out / "window-before.xml")
    write_json(out / "tap-target.json", target)

    tap_exit = run(adb(args.serial, "shell", "input", "tap", str(tap_x), str(tap_y)), output=out / "tap.txt").returncode
    time.sleep(1)
    type_exit = run(adb(args.serial, "shell", "input", "text", input_text), output=out / "type.txt").returncode
    time.sleep(1)

    run(adb(args.serial, "exec-out", "screencap", "-p"), output=out / "observe-after.png", binary=True)
    run(adb(args.serial, "shell", "uiautomator", "dump", "/sdcard/harvis-mobilecode-real-after.xml"), output=out / "uiautomator-after.txt")
    run(adb(args.serial, "pull", "/sdcard/harvis-mobilecode-real-after.xml", str(out / "window-after.xml")), output=out / "uiautomator-after-pull.txt")
    focus = run(adb(args.serial, "shell", "dumpsys", "window")).stdout.decode(errors="replace")
    (out / "window-focus.txt").write_text("\n".join(line for line in focus.splitlines() if "mCurrentFocus" in line or "mFocusedApp" in line or "topResumedActivity" in line), encoding="utf-8")
    logcat = run(adb(args.serial, "logcat", "-d", "-t", "1500")).stdout.decode(errors="replace")
    (out / "logcat.txt").write_text(redact(logcat), encoding="utf-8")
    fatal = "\n".join(line for line in logcat.splitlines() if re.search(r"FATAL EXCEPTION|E/flutter|ANR|MissingPluginException|SIGSEGV", line))
    (out / "logcat-fatal-scan.txt").write_text(redact(fatal), encoding="utf-8")

    after_xml = (out / "window-after.xml").read_text(encoding="utf-8", errors="replace")
    scan = "\n".join(line for line in after_xml.splitlines() if input_text in line or "MobileCode" in line or "任务派发" in line or "No messages yet" in line)
    (out / "assert-ui-scan.txt").write_text(scan, encoding="utf-8")

    checks = {
        "install_ok": install_exit == 0,
        "launch_ok": launch_exit == 0 and "Status: ok" in (out / "launch.txt").read_text(encoding="utf-8", errors="replace"),
        "observe_before_ok": (out / "observe-before.png").stat().st_size > 0 and (out / "window-before.xml").exists(),
        "tap_ok": tap_exit == 0,
        "type_ok": type_exit == 0,
        "assert_ui_ok": input_text in after_xml,
        "focus_ok": args.package in (out / "window-focus.txt").read_text(encoding="utf-8", errors="replace"),
        "logcat_clean": not (out / "logcat-fatal-scan.txt").read_text(encoding="utf-8", errors="replace").strip(),
    }
    summary = {
        "schema": "harvis_mobilecode_phone_use_real_device_smoke.v1",
        "serial": args.serial,
        "package": args.package,
        "input_text": input_text,
        "install_exit": install_exit,
        "launch_exit": launch_exit,
        "tap_exit": tap_exit,
        "type_exit": type_exit,
        "checks": checks,
        "evidence": {
            "observe_before": "observe-before.png",
            "window_before": "window-before.xml",
            "tap_target": "tap-target.json",
            "tap": "tap.txt",
            "type": "type.txt",
            "observe_after": "observe-after.png",
            "window_after": "window-after.xml",
            "assert_ui_scan": "assert-ui-scan.txt",
            "focus": "window-focus.txt",
            "logcat": "logcat.txt",
        },
        "boundary": "Physical Android device explicit allow; not emulator.",
    }
    summary["ok"] = all(checks.values())
    write_json(out / "summary.json", summary)
    print(json.dumps(summary, indent=2, ensure_ascii=False))
    print(f"Evidence: {out}")
    return 0 if summary["ok"] else 4


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
