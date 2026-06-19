#!/usr/bin/env python3
"""Run a bounded Lark dev-log E2E loop and write a sanitized summary."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Any, Optional
from uuid import uuid4

from evidence_feed_server import load_feed
from mock_relay_runner import DEFAULT_OUTPUT_DIR, _now_iso8601


RELAY_READY_MARKER = "[relay] ready event_key=im.message.receive_v1"
DEFAULT_AGENT_COMMAND = "python3 tools/lark_relay/agent_command_dev_log_docx.py"
DEFAULT_RELAY_URL = "http://127.0.0.1:8787"


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Start live_event_relay.py, optionally send a /mc trigger with "
            "lark-cli, wait for one event, and summarize local evidence."
        )
    )
    parser.add_argument("--trigger-text", default="/mc 写开发日志")
    parser.add_argument("--trigger-prefix", default="/mc ")
    parser.add_argument("--timeout", default="3m")
    parser.add_argument("--ready-timeout", type=float, default=30.0)
    parser.add_argument("--send-mode", choices=["dry-run", "live"], default="dry-run")
    parser.add_argument("--docx-mode", choices=["dry-run", "live"], default="dry-run")
    parser.add_argument(
        "--allow-live",
        action="store_true",
        help="Required if --send-mode live or --docx-mode live is selected.",
    )
    parser.add_argument("--as-identity", default="bot", choices=["bot", "user", "auto"])
    parser.add_argument("--docx-as", default="bot", choices=["bot", "user", "auto"])
    parser.add_argument(
        "--send-method",
        choices=["lark-cli", "manual", "none"],
        default="lark-cli",
        help="Use lark-cli to send the trigger, wait for manual send, or only run relay.",
    )
    parser.add_argument("--send-as", default="user", choices=["user", "bot"])
    parser.add_argument("--chat-id", help="Target chat ID for lark-cli trigger send.")
    parser.add_argument("--user-id", help="Target open_id for direct lark-cli trigger send.")
    parser.add_argument(
        "--no-latest-chat",
        action="store_true",
        help="Do not infer chat_id from ignored local relay evidence.",
    )
    parser.add_argument("--agent-command", default=DEFAULT_AGENT_COMMAND)
    parser.add_argument("--output-dir", default=str(DEFAULT_OUTPUT_DIR))
    parser.add_argument("--feed-limit", type=int, default=5)
    parser.add_argument("--relay-url", default=DEFAULT_RELAY_URL)
    parser.add_argument("--summary-output", help="Optional path for sanitized runner summary JSON.")
    return parser


def _duration_to_seconds(value: str) -> float:
    match = re.fullmatch(r"\s*(\d+(?:\.\d+)?)([smh]?)\s*", value)
    if not match:
        return 180.0
    number = float(match.group(1))
    unit = match.group(2)
    if unit == "h":
        return number * 3600
    if unit == "m":
        return number * 60
    return number


def _safe_text(value: str) -> str:
    if value.startswith("/mc "):
        return "/mc <redacted_user_prompt>"
    if value:
        return "<redacted_user_message>"
    return ""


def _compact(value: Any, limit: int = 240) -> str:
    text = str(value or "").strip().replace("\n", " ")
    if len(text) <= limit:
        return text
    return f"{text[:limit]}..."


def _safe_command(command: list[str]) -> list[str]:
    safe: list[str] = []
    redact_next = ""
    for item in command:
        if redact_next:
            safe.append(f"<{redact_next}>")
            redact_next = ""
            continue
        safe.append(item)
        if item == "--output-dir":
            redact_next = "local_evidence_dir"
    return safe


def _safe_log_tail(lines: list[str], limit: int) -> list[str]:
    safe: list[str] = []
    for line in lines[-limit:]:
        clean = line.strip()
        if clean.startswith("{") and clean.endswith("}"):
            safe.append("<redacted_json_evidence_line>")
        elif clean.startswith("evidence written: "):
            safe.append("evidence written: <local_evidence_file>")
        else:
            safe.append(_compact(clean))
    return safe


def _load_json(path: Path) -> dict[str, Any]:
    try:
        decoded = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return decoded if isinstance(decoded, dict) else {}


def _latest_chat_id(evidence_dir: Path) -> str:
    files = sorted(
        (
            path
            for path in evidence_dir.glob("*.json")
            if not path.name.endswith(".summary.json")
        ),
        key=lambda path: path.stat().st_mtime if path.exists() else 0,
        reverse=True,
    )
    for path in files:
        decoded = _load_json(path)
        event = decoded.get("event")
        if not isinstance(event, dict):
            continue
        chat_id = str(event.get("chat_id") or "").strip()
        if chat_id and not chat_id.startswith("<"):
            return chat_id
    return ""


def _relay_command(args: argparse.Namespace) -> list[str]:
    command = [
        "python3",
        "tools/lark_relay/live_event_relay.py",
        "--max-events",
        "1",
        "--timeout",
        args.timeout,
        "--send-mode",
        args.send_mode,
        "--trigger-prefix",
        args.trigger_prefix,
        "--strip-trigger-prefix",
        "--as-identity",
        args.as_identity,
        "--agent-mode",
        "command",
        "--agent-command",
        args.agent_command,
        "--output-dir",
        args.output_dir,
    ]
    if args.send_mode == "live":
        command.append("--allow-live")
    return command


def _relay_env(args: argparse.Namespace) -> dict[str, str]:
    env = os.environ.copy()
    env["MOBILECODE_LARK_DEVLOG_MODE"] = args.docx_mode
    env["MOBILECODE_LARK_DEVLOG_ALLOW_LIVE"] = "1" if args.docx_mode == "live" else "0"
    env["MOBILECODE_LARK_DEVLOG_AS"] = args.docx_as
    return env


def _send_trigger(args: argparse.Namespace, chat_id: str) -> dict[str, Any]:
    if args.send_method == "none":
        return {"method": "none", "sent": False, "status": "skipped"}
    if args.send_method == "manual":
        print(
            f"manual trigger required: send `{args.trigger_text}` to the Lark bot now.",
            file=sys.stderr,
        )
        return {"method": "manual", "sent": False, "status": "waiting_for_user"}

    target: list[str]
    if args.user_id:
        target = ["--user-id", args.user_id]
    elif args.chat_id:
        target = ["--chat-id", args.chat_id]
    elif chat_id:
        target = ["--chat-id", chat_id]
    else:
        return {
            "method": "lark-cli",
            "sent": False,
            "status": "missing_target",
            "next_action": "Pass --chat-id/--user-id or send the trigger manually.",
        }

    command = [
        "lark-cli",
        "im",
        "+messages-send",
        "--as",
        args.send_as,
        *target,
        "--text",
        args.trigger_text,
        "--idempotency-key",
        f"mobilecode-lark-e2e-{uuid4()}",
        "--format",
        "json",
    ]
    result = subprocess.run(command, capture_output=True, text=True, timeout=30)
    detail = (result.stderr or result.stdout or "").strip()
    return {
        "method": "lark-cli",
        "identity": args.send_as,
        "sent": result.returncode == 0,
        "status": "sent" if result.returncode == 0 else "failed",
        "returncode": result.returncode,
        "error_preview": "" if result.returncode == 0 else _compact(detail),
    }


def _start_pump(
    stream: Any,
    lines: list[str],
    ready: threading.Event,
) -> threading.Thread:
    def pump() -> None:
        for line in stream:
            clean = line.rstrip("\n")
            lines.append(clean)
            if RELAY_READY_MARKER in clean:
                ready.set()

    thread = threading.Thread(target=pump, daemon=True)
    thread.start()
    return thread


def _parse_evidence_from_stdout(stdout_lines: list[str]) -> tuple[dict[str, Any], str]:
    evidence_path = ""
    evidence: dict[str, Any] = {}
    for line in stdout_lines:
        if line.startswith("evidence written: "):
            evidence_path = line.split(": ", 1)[1].strip()
        if line.startswith("{") and line.endswith("}"):
            try:
                decoded = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(decoded, dict):
                evidence = decoded
    if not evidence and evidence_path:
        evidence = _load_json(Path(evidence_path))
    return evidence, evidence_path


def _summarize_evidence(evidence: dict[str, Any], evidence_path: str) -> dict[str, Any]:
    reply = evidence.get("reply") if isinstance(evidence.get("reply"), dict) else {}
    docx = evidence.get("lark_docx") if isinstance(evidence.get("lark_docx"), dict) else {}
    return {
        "source_file": Path(evidence_path).name if evidence_path else "",
        "send_mode": evidence.get("send_mode", ""),
        "failure_kind": evidence.get("failure_kind", ""),
        "next_action": evidence.get("next_action", ""),
        "chain_stage": evidence.get("chain_stage", ""),
        "reply_status": "sent"
        if reply.get("returncode") == 0 and evidence.get("send_mode") == "live"
        else ("dry_run_ok" if reply.get("returncode") == 0 else "not_sent"),
        "docx_status": docx.get("status", ""),
        "docx_mode": docx.get("mode", ""),
    }


def _feed_summary(evidence_dir: Path, limit: int) -> dict[str, Any]:
    feed = load_feed(evidence_dir, limit)
    items = feed.get("items") if isinstance(feed.get("items"), list) else []
    first = items[0] if items and isinstance(items[0], dict) else {}
    first_docx = first.get("lark_docx") if isinstance(first.get("lark_docx"), dict) else {}
    return {
        "schema": feed.get("schema", ""),
        "count": feed.get("count", 0),
        "generated_at": feed.get("generated_at", ""),
        "latest": {
            "send_mode": first.get("send_mode", ""),
            "failure_kind": first.get("failure_kind", ""),
            "chain_stage": first.get("chain_stage", ""),
            "docx_status": first_docx.get("status", ""),
            "next_action": first.get("next_action", ""),
        },
    }


def _write_summary(args: argparse.Namespace, summary: dict[str, Any]) -> Path:
    output = (
        Path(args.summary_output)
        if args.summary_output
        else Path(args.output_dir) / "summaries" / f"e2e-{uuid4()}.summary.json"
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    return output


def run(args: argparse.Namespace) -> int:
    if (args.send_mode == "live" or args.docx_mode == "live") and not args.allow_live:
        print("error: live send/docx modes require --allow-live", file=sys.stderr)
        return 2

    evidence_dir = Path(args.output_dir)
    latest_chat_id = "" if args.no_latest_chat else _latest_chat_id(evidence_dir)
    command = _relay_command(args)
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=_relay_env(args),
        bufsize=1,
    )
    assert process.stdout is not None
    assert process.stderr is not None
    stdout_lines: list[str] = []
    stderr_lines: list[str] = []
    ready = threading.Event()
    stdout_thread = _start_pump(process.stdout, stdout_lines, ready)
    stderr_thread = _start_pump(process.stderr, stderr_lines, ready)

    ready.wait(timeout=max(0.0, args.ready_timeout))
    trigger_result = _send_trigger(args, latest_chat_id)
    wait_seconds = _duration_to_seconds(args.timeout) + 45
    try:
        returncode = process.wait(timeout=wait_seconds)
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            returncode = process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            returncode = process.wait(timeout=5)
    stdout_thread.join(timeout=1)
    stderr_thread.join(timeout=1)

    evidence, evidence_path = _parse_evidence_from_stdout(stdout_lines)
    evidence_summary = _summarize_evidence(evidence, evidence_path)
    summary = {
        "schema": "mobilecode.lark_relay.e2e_devlog_runner.v1",
        "generated_at": _now_iso8601(),
        "status": "passed" if evidence_summary.get("failure_kind") == "none" else "failed",
        "relay_ready": ready.is_set(),
        "relay_returncode": returncode,
        "relay_command": _safe_command(command),
        "trigger": {
            **trigger_result,
            "text": _safe_text(args.trigger_text),
            "target": "<redacted>" if (args.chat_id or args.user_id or latest_chat_id) else "",
        },
        "evidence": evidence_summary,
        "feed": _feed_summary(evidence_dir, args.feed_limit),
        "app_validation": {
            "relay_url": args.relay_url,
            "next_action": "Open MobileCode Lark API Lab, choose Managed relay, set relay URL, then tap Sync evidence.",
            "expected": "failure_kind=none, chain_stage=event_to_docx_to_reply, docx_status=dry_run or created",
        },
        "stdout_tail": _safe_log_tail(stdout_lines, 8),
        "stderr_tail": _safe_log_tail(stderr_lines, 12),
    }
    summary_path = _write_summary(args, summary)
    summary["summary_file"] = str(summary_path)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0 if summary["status"] == "passed" else 1


def main(argv: Optional[list[str]] = None) -> int:
    parser = _build_parser()
    return run(parser.parse_args(argv))


if __name__ == "__main__":
    raise SystemExit(main())
