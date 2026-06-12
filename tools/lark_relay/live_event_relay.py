#!/usr/bin/env python3
"""Bridge lark-cli IM events into the local relay evidence loop."""

from __future__ import annotations

import argparse
import json
import shlex
import subprocess
import sys
import threading
from dataclasses import asdict
from pathlib import Path
from typing import Any, Optional

from mock_relay_runner import (
    DEFAULT_OUTPUT_DIR,
    MockEvent,
    _agent_stub,
    _new_dry_run_id,
    _new_request_id,
    _now_iso8601,
)


EVENT_KEY = "im.message.receive_v1"
DEFAULT_TOOL = "lark_relay.live_event_consume"


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Consume one or more Lark IM receive events via lark-cli, run the "
            "local agent stub, and write dry-run/live reply evidence."
        )
    )
    parser.add_argument("--as-identity", default="bot", choices=["bot", "user", "auto"])
    parser.add_argument("--max-events", type=int, default=1)
    parser.add_argument("--timeout", default="60s")
    parser.add_argument("--send-mode", choices=["dry-run", "live"], default="dry-run")
    parser.add_argument(
        "--allow-live",
        action="store_true",
        help="Required with --send-mode live to avoid accidental bot replies.",
    )
    parser.add_argument(
        "--trigger-prefix",
        help="Only reply when message text starts with this prefix.",
    )
    parser.add_argument(
        "--strip-trigger-prefix",
        action="store_true",
        help="Remove --trigger-prefix from the text passed to the agent stub.",
    )
    parser.add_argument(
        "--agent-mode",
        choices=["mock", "command"],
        default="mock",
        help="Use built-in mock agent (default) or invoke a local command for agent reply.",
    )
    parser.add_argument(
        "--agent-command",
        help="Local command to run when --agent-mode command is enabled. Message text is passed via stdin.",
    )
    parser.add_argument(
        "--ignore-sender-id",
        action="append",
        default=[],
        help="Open ID to ignore; repeatable. Useful to avoid reply loops.",
    )
    parser.add_argument(
        "--simulate-failure",
        choices=["none", "agent_error"],
        default="none",
        help="Inject an agent-side failure before reply.",
    )
    parser.add_argument(
        "--reply-in-thread",
        action="store_true",
        help="Pass --reply-in-thread to lark-cli im +messages-reply.",
    )
    parser.add_argument("--output-dir", default=str(DEFAULT_OUTPUT_DIR))
    parser.add_argument("--tool", default=DEFAULT_TOOL)
    return parser


def _event_consume_command(args: argparse.Namespace) -> list[str]:
    return [
        "lark-cli",
        "event",
        "consume",
        EVENT_KEY,
        "--as",
        args.as_identity,
        "--max-events",
        str(args.max_events),
        "--timeout",
        args.timeout,
    ]


def _reply_command(
    *,
    message_id: str,
    reply_text: str,
    idempotency_key: str,
    send_mode: str,
    identity: str,
    reply_in_thread: bool,
) -> list[str]:
    command = [
        "lark-cli",
        "im",
        "+messages-reply",
        "--as",
        identity,
        "--message-id",
        message_id,
        "--text",
        reply_text,
        "--idempotency-key",
        idempotency_key,
        "--format",
        "json",
    ]
    if reply_in_thread:
        command.append("--reply-in-thread")
    if send_mode == "dry-run":
        command.append("--dry-run")
    return command


def _collect_stderr(process: subprocess.Popen[str], lines: list[str], ready: threading.Event) -> None:
    assert process.stderr is not None
    for line in process.stderr:
        clean = line.rstrip("\n")
        lines.append(clean)
        if f"[event] ready event_key={EVENT_KEY}" in clean:
            ready.set()


def _normalize_event(payload: dict[str, Any]) -> tuple[MockEvent, dict[str, Any]]:
    message_text = str(payload.get("content") or payload.get("message_text") or "").strip()
    message_id = str(payload.get("message_id") or payload.get("id") or "")
    event_id = str(payload.get("event_id") or _new_request_id())
    request_id = str(payload.get("request_id") or payload.get("log_id") or _new_request_id())

    event = MockEvent(
        event_id=event_id,
        request_id=request_id,
        chat_id=str(payload.get("chat_id") or ""),
        sender_id=str(payload.get("sender_id") or ""),
        message_text=message_text,
        received_at=_now_iso8601(),
    )
    metadata = {
        "message_id": message_id,
        "message_type": payload.get("message_type"),
        "chat_type": payload.get("chat_type"),
        "event_type": payload.get("type"),
        "event_timestamp": payload.get("timestamp") or payload.get("create_time"),
    }
    return event, metadata


def _should_skip_event(event: MockEvent, args: argparse.Namespace) -> tuple[bool, str, str]:
    text = event.message_text
    if event.sender_id in set(args.ignore_sender_id):
        return True, "ignored_sender", text
    if args.trigger_prefix and not text.startswith(args.trigger_prefix):
        return True, "trigger_prefix_not_matched", text
    if args.trigger_prefix and args.strip_trigger_prefix and text.startswith(args.trigger_prefix):
        text = text[len(args.trigger_prefix) :].strip()
    return False, "none", text


def _run_command_agent(command: str, message_text: str) -> tuple[str, str, Optional[int], str, str]:
    try:
        argv = shlex.split(command)
    except ValueError as exc:
        return "agent_command_parse_error", "", None, "", str(exc)

    if not argv:
        return "agent_command_empty", "", None, "", "empty --agent-command"

    try:
        result = subprocess.run(
            argv,
            input=message_text,
            capture_output=True,
            text=True,
            timeout=15,
        )
    except FileNotFoundError as exc:
        return "agent_command_not_found", "", None, "", str(exc)
    except subprocess.TimeoutExpired as exc:
        return "agent_command_timeout", "", None, "", f"agent command timed out: {exc.timeout}s"
    except OSError as exc:
        return "agent_command_failed", "", None, "", str(exc)

    stdout = (result.stdout or "").strip()
    stderr = (result.stderr or "").strip()
    if result.returncode != 0:
        return "agent_command_failed", "", result.returncode, stdout, stderr
    if not stdout:
        return "agent_empty_reply", "", result.returncode, stdout, stderr
    return "none", stdout, result.returncode, stdout, stderr


def _run_agent(
    args: argparse.Namespace, message_text: str
) -> tuple[str, str, Optional[int], str, str]:
    if args.agent_mode == "mock":
        failure_kind, agent_reply = _agent_stub(message_text, args.simulate_failure)
        return failure_kind, agent_reply, None, "", ""

    if not args.agent_command:
        return "agent_command_missing", "", None, "", "missing --agent-command"

    return _run_command_agent(args.agent_command, message_text)


def _write_evidence(output_dir: Path, evidence: dict[str, Any]) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    output = output_dir / f"{evidence['dry_run_id']}.json"
    output.write_text(json.dumps(evidence, ensure_ascii=False, indent=2), encoding="utf-8")
    return output


def _run_reply(command: list[str]) -> tuple[int, str, str, Optional[dict[str, Any]]]:
    result = subprocess.run(command, capture_output=True, text=True)
    parsed: Optional[dict[str, Any]] = None
    if result.stdout.strip():
        try:
            parsed = json.loads(result.stdout)
        except json.JSONDecodeError:
            parsed = None
    return result.returncode, result.stdout, result.stderr, parsed


def _build_evidence(
    *,
    args: argparse.Namespace,
    event: MockEvent,
    event_metadata: dict[str, Any],
    consumer_command: list[str],
    consumer_stderr: list[str],
    agent_mode: str,
    agent_command: Optional[str],
    agent_returncode: Optional[int],
    agent_stdout: str,
    agent_stderr: str,
    reply_command: Optional[list[str]],
    reply_returncode: Optional[int],
    reply_stdout: str,
    reply_stderr: str,
    reply_json: Optional[dict[str, Any]],
    failure_kind: str,
    next_action: str,
    reply_text: str,
    skipped: bool,
    skip_reason: str,
) -> dict[str, Any]:
    dry_run_id = _new_dry_run_id()
    return {
        "tool": args.tool,
        "event_key": EVENT_KEY,
        "send_mode": args.send_mode,
        "event": asdict(event),
        "event_metadata": event_metadata,
        "event_id": event.event_id,
        "request_id": event.request_id,
        "dry_run_id": dry_run_id,
        "failure_kind": failure_kind,
        "next_action": next_action,
        "message_text": event.message_text,
        "reply_text": reply_text,
        "skipped": skipped,
        "skip_reason": skip_reason,
        "timestamp": _now_iso8601(),
        "consumer": {
            "command": consumer_command,
            "ready": any(f"[event] ready event_key={EVENT_KEY}" in line for line in consumer_stderr),
            "stderr_tail": consumer_stderr[-20:],
        },
        "reply": {
            "command": reply_command,
            "returncode": reply_returncode,
            "stdout": reply_stdout,
            "stderr": reply_stderr,
            "json": reply_json,
        },
        "agent": {
            "mode": agent_mode,
            "command": agent_command,
            "returncode": agent_returncode,
            "stdout": agent_stdout,
            "stderr": agent_stderr,
        },
    }


def run_live_relay(args: argparse.Namespace) -> int:
    if args.send_mode == "live" and not args.allow_live:
        print("error: --send-mode live requires --allow-live", file=sys.stderr)
        return 2
    if args.agent_mode == "command" and not args.agent_command:
        print("error: --agent-mode command requires --agent-command", file=sys.stderr)
        return 2

    consumer_command = _event_consume_command(args)
    consumer_stderr: list[str] = []
    ready = threading.Event()
    output_dir = Path(args.output_dir)
    processed = 0

    process = subprocess.Popen(
        consumer_command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        stdin=subprocess.DEVNULL,
        text=True,
        bufsize=1,
    )
    stderr_thread = threading.Thread(
        target=_collect_stderr,
        args=(process, consumer_stderr, ready),
        daemon=True,
    )
    stderr_thread.start()
    ready.wait(timeout=15)

    assert process.stdout is not None
    for line in process.stdout:
        raw = line.strip()
        if not raw:
            continue
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError as exc:
            evidence = {
                "tool": args.tool,
                "event_key": EVENT_KEY,
                "send_mode": args.send_mode,
                "dry_run_id": _new_dry_run_id(),
                "failure_kind": "event_json_decode_error",
                "next_action": "inspect_lark_cli_event_stdout",
                "raw_event": raw,
                "error": str(exc),
                "timestamp": _now_iso8601(),
                "consumer": {
                    "command": consumer_command,
                    "ready": ready.is_set(),
                    "stderr_tail": consumer_stderr[-20:],
                },
            }
            output = _write_evidence(output_dir, evidence)
            print(f"evidence written: {output}")
            processed += 1
            continue

        event, metadata = _normalize_event(payload)
        skipped, skip_reason, agent_input = _should_skip_event(event, args)
        reply_text = ""
        reply_command = None
        reply_returncode = None
        reply_stdout = ""
        reply_stderr = ""
        reply_json = None
        agent_returncode = None
        agent_stdout = ""
        agent_stderr = ""
        failure_kind = "none"
        next_action = "reply_dry_run_written" if args.send_mode == "dry-run" else "reply_sent"

        if skipped:
            failure_kind = skip_reason
            next_action = "wait_for_matching_event"
        else:
            agent_failure, agent_reply, agent_returncode, agent_stdout, agent_stderr = _run_agent(args, agent_input)
            if agent_failure != "none":
                failure_kind = agent_failure
                if args.agent_mode == "mock":
                    next_action = "retry_agent_or_switch_stub"
                else:
                    next_action = "inspect_agent_command_or_reconfigure"
            elif not metadata["message_id"]:
                failure_kind = "missing_message_id"
                next_action = "inspect_event_schema_or_lark_cli_output"
            else:
                reply_text = agent_reply
                idempotency_key = _new_dry_run_id()
                reply_command = _reply_command(
                    message_id=str(metadata["message_id"]),
                    reply_text=reply_text,
                    idempotency_key=idempotency_key,
                    send_mode=args.send_mode,
                    identity=args.as_identity,
                    reply_in_thread=args.reply_in_thread,
                )
                reply_returncode, reply_stdout, reply_stderr, reply_json = _run_reply(reply_command)
                if reply_returncode != 0:
                    failure_kind = "im_reply_failed"
                    next_action = "inspect_reply_error_scope_or_membership"

        evidence = _build_evidence(
            args=args,
            event=event,
            event_metadata=metadata,
            consumer_command=consumer_command,
            consumer_stderr=consumer_stderr,
            agent_mode=args.agent_mode,
            agent_command=args.agent_command,
            agent_returncode=agent_returncode,
            agent_stdout=agent_stdout,
            agent_stderr=agent_stderr,
            reply_command=reply_command,
            reply_returncode=reply_returncode,
            reply_stdout=reply_stdout,
            reply_stderr=reply_stderr,
            reply_json=reply_json,
            failure_kind=failure_kind,
            next_action=next_action,
            reply_text=reply_text,
            skipped=skipped,
            skip_reason=skip_reason,
        )
        output = _write_evidence(output_dir, evidence)
        print(f"evidence written: {output}")
        print(json.dumps(evidence, ensure_ascii=False))
        processed += 1

    process.wait()
    stderr_thread.join(timeout=2)
    if process.returncode != 0:
        evidence = {
            "tool": args.tool,
            "event_key": EVENT_KEY,
            "send_mode": args.send_mode,
            "dry_run_id": _new_dry_run_id(),
            "failure_kind": "event_consumer_failed",
            "next_action": "inspect_event_consumer_scope_or_console_event",
            "timestamp": _now_iso8601(),
            "consumer": {
                "command": consumer_command,
                "returncode": process.returncode,
                "ready": ready.is_set(),
                "stderr_tail": consumer_stderr[-40:],
            },
        }
        output = _write_evidence(output_dir, evidence)
        print(f"evidence written: {output}")
        print(json.dumps(evidence, ensure_ascii=False), file=sys.stderr)
        return process.returncode

    if processed == 0:
        evidence = {
            "tool": args.tool,
            "event_key": EVENT_KEY,
            "send_mode": args.send_mode,
            "dry_run_id": _new_dry_run_id(),
            "failure_kind": "event_timeout_no_message",
            "next_action": "send_a_feishu_message_to_the_bot_and_rerun",
            "timestamp": _now_iso8601(),
            "consumer": {
                "command": consumer_command,
                "returncode": process.returncode,
                "ready": ready.is_set(),
                "stderr_tail": consumer_stderr[-40:],
            },
        }
        output = _write_evidence(output_dir, evidence)
        print(f"evidence written: {output}")
        print(json.dumps(evidence, ensure_ascii=False))

    return 0


def main(argv: Optional[list[str]] = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)
    return run_live_relay(args)


if __name__ == "__main__":
    raise SystemExit(main())
