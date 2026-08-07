#!/usr/bin/env python3
"""macOS LaunchAgent helper for the MobileCode Harvis remote worker."""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import subprocess
import sys
from pathlib import Path
from typing import Any


DEFAULT_LABEL = "com.mobilecode.harvis.remote-worker"


def script_paths() -> tuple[Path, Path, Path]:
    script_dir = Path(__file__).resolve().parent
    mobile_agent_dir = script_dir.parent
    repo_root = mobile_agent_dir.parent
    return script_dir, mobile_agent_dir, repo_root


def default_queue_dir(mobile_agent_dir: Path) -> Path:
    return mobile_agent_dir / ".harvis-mobilecode"


def default_launch_agents_dir() -> Path:
    return Path.home() / "Library" / "LaunchAgents"


def build_worker_args(args: argparse.Namespace) -> list[str]:
    command = [
        args.python_bin,
        str(args.worker),
        "--workspace-root",
        str(args.workspace_root),
        "--inbox",
        str(args.inbox),
        "--outbox",
        str(args.outbox),
        "--processed-dir",
        str(args.processed_dir),
        "--failed-dir",
        str(args.failed_dir),
        "--poll-interval",
        str(args.poll_interval),
        "--chat-id",
        args.chat_id,
        "--sender-id",
        args.sender_id,
    ]
    if args.route:
        command.append("--route")
        command.extend(["--lark-relay-bin", args.lark_relay_bin])
        if args.relay_config:
            command.extend(["--relay-config", args.relay_config])
    if args.phone_use_serial:
        command.extend(["--phone-use-serial", args.phone_use_serial])
    if args.phone_use_apk:
        command.extend(["--phone-use-apk", args.phone_use_apk])
    if args.phone_use_skip_install:
        command.append("--phone-use-skip-install")
    if args.phone_use_build_debug:
        command.append("--phone-use-build-debug")
    if args.phone_use_allow_real_device:
        command.append("--phone-use-allow-real-device")
    return command


def build_plist(args: argparse.Namespace) -> dict[str, Any]:
    logs_dir = args.logs_dir
    return {
        "Label": args.label,
        "ProgramArguments": build_worker_args(args),
        "WorkingDirectory": str(args.workspace_root),
        "RunAtLoad": True,
        "KeepAlive": True,
        "StandardOutPath": str(logs_dir / "mobilecode-remote-worker.out.log"),
        "StandardErrorPath": str(logs_dir / "mobilecode-remote-worker.err.log"),
        "EnvironmentVariables": {
            "PYTHONUNBUFFERED": "1",
        },
    }


def write_plist(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(plistlib.dumps(value, sort_keys=True))


def load_plist(path: Path, label: str) -> None:
    bootstrap_target = f"gui/{os.getuid()}"
    subprocess.run(["launchctl", "bootout", bootstrap_target, str(path)], check=False)
    subprocess.run(["launchctl", "bootstrap", bootstrap_target, str(path)], check=True)
    subprocess.run(["launchctl", "enable", f"{bootstrap_target}/{label}"], check=False)
    subprocess.run(["launchctl", "kickstart", "-k", f"{bootstrap_target}/{label}"], check=False)


def unload_plist(path: Path) -> None:
    subprocess.run(["launchctl", "bootout", f"gui/{os.getuid()}", str(path)], check=False)


def print_status(label: str) -> int:
    completed = subprocess.run(
        ["launchctl", "print", f"gui/{os.getuid()}/{label}"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    output = completed.stdout if completed.returncode == 0 else completed.stderr
    print(output, end="")
    return completed.returncode


def normalize_args(args: argparse.Namespace) -> argparse.Namespace:
    _, mobile_agent_dir, repo_root = script_paths()
    queue_dir = default_queue_dir(mobile_agent_dir)
    args.workspace_root = (args.workspace_root or repo_root).resolve()
    args.worker = (args.worker or mobile_agent_dir / "tooling" / "mobilecode_remote_worker.py").resolve()
    args.inbox = (args.inbox or queue_dir / "inbox").resolve()
    args.outbox = (args.outbox or queue_dir / "outbox").resolve()
    args.processed_dir = (args.processed_dir or queue_dir / "processed").resolve()
    args.failed_dir = (args.failed_dir or queue_dir / "failed").resolve()
    args.logs_dir = (args.logs_dir or queue_dir / "logs").resolve()
    args.plist_path = (
        args.plist_path or default_launch_agents_dir() / f"{args.label}.plist"
    ).resolve()
    return args


def add_common_options(parser: argparse.ArgumentParser) -> None:
    _, mobile_agent_dir, repo_root = script_paths()
    queue_dir = default_queue_dir(mobile_agent_dir)
    parser.add_argument("--label", default=DEFAULT_LABEL)
    parser.add_argument("--plist-path", type=Path)
    parser.add_argument("--python-bin", default=sys.executable)
    parser.add_argument("--worker", type=Path)
    parser.add_argument("--workspace-root", type=Path, default=repo_root)
    parser.add_argument("--inbox", type=Path, default=queue_dir / "inbox")
    parser.add_argument("--outbox", type=Path, default=queue_dir / "outbox")
    parser.add_argument("--processed-dir", type=Path, default=queue_dir / "processed")
    parser.add_argument("--failed-dir", type=Path, default=queue_dir / "failed")
    parser.add_argument("--logs-dir", type=Path, default=queue_dir / "logs")
    parser.add_argument("--poll-interval", type=float, default=2.0)
    parser.add_argument("--route", action="store_true")
    parser.add_argument("--lark-relay-bin", default="lark-relay")
    parser.add_argument("--relay-config", default="")
    parser.add_argument("--chat-id", default="oc_mobilecode_remote_worker")
    parser.add_argument("--sender-id", default="ou_mobilecode_remote_worker")
    parser.add_argument("--phone-use-serial", default="")
    parser.add_argument("--phone-use-apk", default="")
    parser.add_argument("--phone-use-skip-install", action="store_true")
    parser.add_argument("--phone-use-build-debug", action="store_true")
    parser.add_argument("--phone-use-allow-real-device", action="store_true")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Manage the MobileCode Harvis remote worker LaunchAgent.")
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in ("render-plist", "install", "uninstall", "status"):
        subparser = subparsers.add_parser(command)
        add_common_options(subparser)
    return normalize_args(parser.parse_args(argv))


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.command == "status":
        return print_status(args.label)
    if args.command == "uninstall":
        unload_plist(args.plist_path)
        print(json.dumps({"ok": True, "action": "uninstall", "plist": str(args.plist_path)}, indent=2))
        return 0

    plist = build_plist(args)
    write_plist(args.plist_path, plist)
    args.logs_dir.mkdir(parents=True, exist_ok=True)
    if args.command == "render-plist":
        print(json.dumps({"ok": True, "action": "render-plist", "plist": str(args.plist_path)}, indent=2))
        return 0

    load_plist(args.plist_path, args.label)
    print(json.dumps({"ok": True, "action": "install", "plist": str(args.plist_path)}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
