#!/usr/bin/env python3
"""MobileCode <-> Harvis file-queue worker.

This is the first live-worker lane for the Harvis bridge. It intentionally uses
plain files as the queue boundary so Lark Relay can hand off approved tasks
without requiring MobileCode to own Lark credentials or Harvis tokens.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ALLOWED_ACTIONS = {"project_check", "validate", "phone_use_emulator"}
P4_ACTIONS = {"project_check", "validate"}
LOCAL_PATH_MARKERS = ("/Users/", "/Volumes/", "/private/", "/var/folders/")


class WorkerError(Exception):
    def __init__(self, message: str, details: list[str] | None = None) -> None:
        super().__init__(message)
        self.details = details or []


@dataclass(frozen=True)
class Handoff:
    task_id: str
    correlation_id: str
    action: str
    approval_id: str
    title: str
    input: dict[str, Any]
    source: dict[str, Any]
    evidence_contract: dict[str, Any]


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def read_jsonish(path: Path) -> dict[str, Any]:
    raw = path.read_text(encoding="utf-8").strip()
    if raw.startswith("[mobilecode-handoff]"):
        raw = raw[raw.index("{") :]
    decoded = json.loads(raw)
    if not isinstance(decoded, dict):
        raise WorkerError("handoff file must contain a JSON object")
    if (
        decoded.get("type") != "mobilecode.handoff.v1"
        and decoded.get("schema_version") == "mobilecode.harvis.task.v1"
    ):
        return transport_from_task_envelope(decoded)
    return decoded


def transport_from_task_envelope(envelope: dict[str, Any]) -> dict[str, Any]:
    task = map_value(envelope.get("task"))
    handoff = map_value(envelope.get("handoff"))
    return {
        "type": "mobilecode.handoff.v1",
        "schema_version": envelope.get("schema_version"),
        "task_id": envelope.get("task_id"),
        "correlation_id": envelope.get("correlation_id"),
        "action": task.get("kind"),
        "approval": {
            "required": True,
            "approval_id": handoff.get("approval_id"),
            "risk": handoff.get("risk"),
            "summary": handoff.get("human_summary") or task.get("title"),
        },
        "source": envelope.get("source"),
        "target": envelope.get("target"),
        "task": {
            "title": task.get("title"),
            "input": task.get("input"),
            "timeout_ms": task.get("timeout_ms"),
        },
        "evidence_contract": envelope.get("evidence_contract"),
    }


def parse_handoff(payload: dict[str, Any]) -> Handoff:
    errors: list[str] = []
    if payload.get("type") != "mobilecode.handoff.v1":
        errors.append("type must be mobilecode.handoff.v1.")
    if payload.get("schema_version") != "mobilecode.harvis.task.v1":
        errors.append("schema_version must be mobilecode.harvis.task.v1.")

    task_id = string_value(payload.get("task_id"))
    if not task_id.startswith("hm_task_"):
        errors.append("task_id must start with hm_task_.")
    correlation_id = string_value(payload.get("correlation_id"))
    if not correlation_id.startswith("corr_"):
        errors.append("correlation_id must start with corr_.")

    action = string_value(payload.get("action"))
    if action not in ALLOWED_ACTIONS:
        errors.append("action must be project_check, validate, or phone_use_emulator.")

    approval = map_value(payload.get("approval"))
    if approval.get("required") is not True:
        errors.append("approval.required must be true.")
    approval_id = string_value(approval.get("approval_id"))
    if not approval_id.startswith("appr_"):
        errors.append("approval.approval_id is required and must start with appr_.")

    source = map_value(payload.get("source"))
    if source.get("system") != "harvis":
        errors.append("source.system must be harvis.")

    target = map_value(payload.get("target"))
    selector = map_value(target.get("device_selector"))
    if action in P4_ACTIONS and selector.get("required") is True:
        errors.append("P4 worker handoff cannot require a device.")
    selector_kind = string_value(selector.get("kind"))
    if action in P4_ACTIONS and selector_kind and selector_kind != "none":
        errors.append("P4 worker device_selector.kind must be none.")
    if action == "phone_use_emulator":
        if selector.get("required") is not True:
            errors.append("P5 phone_use_emulator requires target.device_selector.required=true.")
        if selector_kind != "android_emulator":
            errors.append("P5 phone_use_emulator requires target.device_selector.kind=android_emulator.")

    contract = map_value(payload.get("evidence_contract"))
    expected = contract.get("expected_types")
    if not isinstance(expected, list) or "mobilecode.action_evidence.v1" not in expected:
        errors.append(
            "evidence_contract.expected_types must include mobilecode.action_evidence.v1."
        )

    task = map_value(payload.get("task"))
    title = string_value(task.get("title")) or "Harvis MobileCode handoff"
    task_input = map_value(task.get("input"))

    if errors:
        raise WorkerError("MobileCode handoff validation failed.", errors)
    return Handoff(
        task_id=task_id,
        correlation_id=correlation_id,
        action=action,
        approval_id=approval_id,
        title=title,
        input=task_input,
        source=source,
        evidence_contract=contract,
    )


def build_status(handoff: Handoff, state: str, summary: str) -> dict[str, Any]:
    return {
        "type": "mobilecode.status.v1",
        "task_id": handoff.task_id,
        "correlation_id": handoff.correlation_id,
        "runtime": {
            "name": "mobilecode",
            "mode": "remote_worker_file_queue",
            "version": "p4-live-bidirectional-worker",
            "host": "local",
        },
        "state": state,
        "phase": handoff.action,
        "summary": summary,
        "progress": {"completed": 0, "total": 1, "current": state},
        "capabilities": [
            "handoff_ack",
            "project_check",
            "validate",
            "phone_use_emulator",
            "evidence_export",
        ],
        "device": device_status_for(handoff),
        "approval": {
            "required": True,
            "approval_id": handoff.approval_id,
            "status": "consumed" if state in {"running", "verified"} else "accepted",
        },
        "updated_at": utc_now(),
        "next_action": "execute_handoff" if state == "accepted" else "render_in_harvis_agent_room",
    }


def device_status_for(handoff: Handoff) -> dict[str, Any]:
    if handoff.action == "phone_use_emulator":
        return {"kind": "android_emulator", "required": True, "status": "required"}
    return {"kind": "none", "required": False, "status": "not_required"}


def execute_handoff(handoff: Handoff, workspace_root: Path, args: argparse.Namespace) -> dict[str, Any]:
    if handoff.action == "project_check":
        return run_project_check(handoff, workspace_root)
    if handoff.action == "validate":
        return run_validate(handoff, workspace_root)
    return run_phone_use_emulator(handoff, workspace_root, args)


def run_project_check(handoff: Handoff, workspace_root: Path) -> dict[str, Any]:
    required = [
        "mobile_agent/lib/services/harvis_mobilecode_bridge_service.dart",
        "mobile_agent/test/fixtures/harvis_mobilecode_handoff.project_check.json",
        "mobile_agent/tooling/mobilecode_remote_worker.py",
    ]
    observations = []
    ok = True
    for relative in required:
        exists = (workspace_root / relative).exists()
        ok = ok and exists
        observations.append(
            {
                "kind": "file_check",
                "status": "passed" if exists else "failed",
                "message": f"{relative} {'exists' if exists else 'is missing'}",
            }
        )
    checks = handoff.input.get("checks")
    if isinstance(checks, list) and checks:
        observations.append(
            {
                "kind": "handoff_input",
                "status": "passed",
                "message": f"{len(checks)} requested check(s) received",
            }
        )
    return action_evidence(
        handoff,
        ok=ok,
        summary="MobileCode remote worker completed project_check."
        if ok
        else "MobileCode remote worker project_check found missing files.",
        observations=observations,
        artifacts=[
            {
                "kind": "json",
                "label": "handoff_contract",
                "ref": "mobile_agent/test/fixtures/harvis_mobilecode_handoff.project_check.json",
            }
        ],
    )


def run_validate(handoff: Handoff, workspace_root: Path) -> dict[str, Any]:
    requested_path = string_value(handoff.input.get("path"))
    observations: list[dict[str, Any]] = []
    ok = True
    if requested_path:
        target = safe_workspace_path(workspace_root, requested_path)
        if target is None or not target.exists():
            ok = False
            observations.append(
                {
                    "kind": "validate_path",
                    "status": "failed",
                    "message": "requested path is missing or outside workspace",
                }
            )
        elif target.suffix == ".json":
            try:
                json.loads(target.read_text(encoding="utf-8"))
                observations.append(
                    {
                        "kind": "validate_json",
                        "status": "passed",
                        "message": f"{requested_path} is valid JSON",
                    }
                )
            except json.JSONDecodeError as error:
                ok = False
                observations.append(
                    {
                        "kind": "validate_json",
                        "status": "failed",
                        "message": f"invalid JSON: {error.msg}",
                    }
                )
        else:
            observations.append(
                {
                    "kind": "validate_file",
                    "status": "passed",
                    "message": f"{requested_path} is present",
                }
            )
    else:
        observations.append(
            {
                "kind": "validate_handoff",
                "status": "passed",
                "message": "handoff payload passed schema and approval gates",
            }
        )
    return action_evidence(
        handoff,
        ok=ok,
        summary="MobileCode remote worker validation passed."
        if ok
        else "MobileCode remote worker validation failed.",
        observations=observations,
        artifacts=[],
    )


def run_phone_use_emulator(
    handoff: Handoff,
    workspace_root: Path,
    args: argparse.Namespace,
) -> dict[str, Any]:
    script = Path(args.phone_use_script)
    if not script.is_absolute():
        script = workspace_root / script
    if not script.exists():
        return action_evidence(
            handoff,
            ok=False,
            summary="MobileCode phone-use emulator script is missing.",
            observations=[
                {
                    "kind": "phone_use_emulator",
                    "status": "failed",
                    "message": "phone-use emulator script is missing",
                }
            ],
            artifacts=[],
        )

    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    output_dir = workspace_root / "mobile_agent" / "qa-output" / f"harvis-mobilecode-phone-use-handoff-{stamp}"
    text = safe_adb_text(string_value(handoff.input.get("text")) or f"HarvisP5Handoff{stamp}")
    command = [
        str(script),
        "--output",
        str(output_dir),
        "--text",
        text,
    ]
    serial = string_value(handoff.input.get("serial")) or string_value(args.phone_use_serial)
    if serial:
        command.extend(["--serial", serial])
    package_name = string_value(handoff.input.get("package")) or args.phone_use_package
    if package_name:
        command.extend(["--package", package_name])
    activity = string_value(handoff.input.get("activity")) or args.phone_use_activity
    if activity:
        command.extend(["--activity", activity])
    apk = string_value(handoff.input.get("apk")) or args.phone_use_apk
    if apk:
        command.extend(["--apk", apk])
    if handoff.input.get("skip_install") is True or args.phone_use_skip_install:
        command.append("--skip-install")
    if handoff.input.get("build_debug") is True or args.phone_use_build_debug:
        command.append("--build-debug")

    completed = subprocess.run(
        command,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    summary_path = output_dir / "summary.json"
    summary = read_optional_summary(summary_path)
    ok = completed.returncode == 0 and summary.get("ok") is True
    observations = [
        {
            "kind": "phone_use_emulator",
            "status": "passed" if ok else "failed",
            "message": "observe -> tap -> type -> assert UI completed"
            if ok
            else "phone-use emulator primitive failed",
        },
        {
            "kind": "phone_use_command",
            "status": "passed" if completed.returncode == 0 else "failed",
            "message": f"exit_code={completed.returncode}",
        },
    ]
    checks = summary.get("checks")
    if isinstance(checks, dict):
        for key, value in checks.items():
            observations.append(
                {
                    "kind": f"phone_use_check:{key}",
                    "status": "passed" if value is True else "failed",
                    "message": f"{key}={value}",
                }
            )

    artifacts = [
        {
            "kind": "json",
            "label": "phone_use_summary",
            "ref": display_path(summary_path, workspace_root),
        },
        {
            "kind": "screenshot",
            "label": "observe_after",
            "ref": display_path(output_dir / "observe-after.png", workspace_root),
        },
        {
            "kind": "xml",
            "label": "window_after",
            "ref": display_path(output_dir / "window-after.xml", workspace_root),
        },
    ]
    return action_evidence(
        handoff,
        ok=ok,
        summary="MobileCode phone-use emulator handoff passed."
        if ok
        else "MobileCode phone-use emulator handoff failed.",
        observations=observations,
        artifacts=artifacts,
    )


def action_evidence(
    handoff: Handoff,
    *,
    ok: bool,
    summary: str,
    observations: list[dict[str, Any]],
    artifacts: list[dict[str, Any]],
) -> dict[str, Any]:
    return {
        "type": "mobilecode.action_evidence.v1",
        "task_id": handoff.task_id,
        "correlation_id": handoff.correlation_id,
        "action": handoff.action,
        "status": "verified" if ok else "failed",
        "summary": summary,
        "observations": observations,
        "artifacts": redact(artifacts),
        "approval": {
            "required": True,
            "approval_id": handoff.approval_id,
            "status": "consumed",
        },
        "redaction": "public_safe",
        "created_at": utc_now(),
        "next_action": "render_in_harvis_agent_room",
    }


def wrap_lark_event(payload: dict[str, Any], *, chat_id: str, sender_id: str) -> dict[str, Any]:
    event_suffix = event_safe_token(
        string_value(payload.get("created_at"))
        or string_value(payload.get("updated_at"))
        or utc_now()
    )
    event_id = f"evt_{payload['type'].replace('.', '_')}_{payload['task_id']}_{event_suffix}"
    return {
        "event_id": event_id,
        "request_id": f"req_{payload['task_id']}_{event_suffix}",
        "chat_id": chat_id,
        "sender_id": sender_id,
        "message_id": f"om_{payload['type'].replace('.', '_')}_{payload['task_id']}_{event_suffix}",
        "message_type": "text",
        "content": json.dumps({"text": f"[mobilecode] {json.dumps(payload, separators=(',', ':'))}"}),
    }


def route_with_lark_relay(
    event_file: Path,
    *,
    relay_bin: str,
    relay_config: str | None,
    output_file: Path,
) -> None:
    command = [relay_bin, "route-file", "--file", str(event_file), "--no-reply"]
    if relay_config:
        command.extend(["--config", relay_config])
    completed = subprocess.run(
        command,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    output_file.write_text(
        json.dumps(
            {
                "command": redact(command),
                "returncode": completed.returncode,
                "stdout": redact(completed.stdout),
                "stderr": redact(completed.stderr),
            },
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )
    if completed.returncode != 0:
        raise WorkerError(f"lark-relay route-file failed for {event_file.name}")


def process_file(path: Path, args: argparse.Namespace) -> dict[str, Any]:
    payload = read_jsonish(path)
    handoff = parse_handoff(payload)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    prefix = f"{stamp}-{handoff.task_id}"
    args.outbox.mkdir(parents=True, exist_ok=True)

    ack = build_status(handoff, "accepted", "MobileCode remote worker accepted approved handoff.")
    ack_payload_path = args.outbox / f"{prefix}.ack.json"
    ack_event_path = args.outbox / f"{prefix}.ack-event.json"
    write_json(ack_payload_path, ack)
    write_json(
        ack_event_path,
        wrap_lark_event(ack, chat_id=args.chat_id, sender_id=args.sender_id),
    )

    evidence = execute_handoff(handoff, args.workspace_root, args)
    evidence_payload_path = args.outbox / f"{prefix}.action-evidence.json"
    evidence_event_path = args.outbox / f"{prefix}.action-evidence-event.json"
    write_json(evidence_payload_path, evidence)
    write_json(
        evidence_event_path,
        wrap_lark_event(evidence, chat_id=args.chat_id, sender_id=args.sender_id),
    )

    route_results = []
    if args.route:
        for event_file in (ack_event_path, evidence_event_path):
            route_output = event_file.with_suffix(".route-result.json")
            route_with_lark_relay(
                event_file,
                relay_bin=args.lark_relay_bin,
                relay_config=args.relay_config,
                output_file=route_output,
            )
            route_results.append(route_output.name)

    args.processed_dir.mkdir(parents=True, exist_ok=True)
    shutil.move(str(path), args.processed_dir / f"{prefix}.{path.name}")
    return {
        "ok": evidence["status"] == "verified",
        "task_id": handoff.task_id,
        "action": handoff.action,
        "ack": str(ack_event_path),
        "action_evidence": str(evidence_event_path),
        "route_results": route_results,
    }


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(redact(value), indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def safe_workspace_path(workspace_root: Path, requested_path: str) -> Path | None:
    target = (workspace_root / requested_path).resolve()
    try:
        target.relative_to(workspace_root.resolve())
    except ValueError:
        return None
    return target


def display_path(path: Path, workspace_root: Path) -> str:
    try:
        return str(path.resolve().relative_to(workspace_root.resolve()))
    except ValueError:
        return str(path)


def read_optional_summary(path: Path) -> dict[str, Any]:
    try:
        decoded = json.loads(path.read_text(encoding="utf-8"))
        return decoded if isinstance(decoded, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def safe_adb_text(value: str) -> str:
    cleaned = "".join(char for char in value if char.isalnum() or char in "._-")
    return cleaned[:80] or "HarvisP5Handoff"


def event_safe_token(value: str) -> str:
    token = "".join(char if char.isalnum() else "_" for char in value)
    return token.strip("_")[:80] or "event"


def redact(value: Any) -> Any:
    if isinstance(value, str):
        redacted = value
        for marker in LOCAL_PATH_MARKERS:
            if marker in redacted:
                parts = redacted.split(marker)
                redacted = parts[0] + marker.rstrip("/") + "/[local-path]"
        return redacted
    if isinstance(value, list):
        return [redact(item) for item in value]
    if isinstance(value, dict):
        return {str(key): redact(item) for key, item in value.items()}
    return value


def map_value(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def string_value(value: Any) -> str:
    return "" if value is None else str(value).strip()


def find_handoff_files(inbox: Path) -> list[Path]:
    if not inbox.exists():
        return []
    return sorted(
        path
        for path in inbox.iterdir()
        if path.is_file() and path.suffix in {".json", ".txt", ".handoff"}
    )


def parse_args(argv: list[str]) -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent
    mobile_agent_dir = script_dir.parent
    repo_root = mobile_agent_dir.parent
    parser = argparse.ArgumentParser(description="Run the P4 MobileCode Harvis remote worker.")
    parser.add_argument("--inbox", type=Path, default=mobile_agent_dir / ".harvis-mobilecode" / "inbox")
    parser.add_argument("--outbox", type=Path, default=mobile_agent_dir / ".harvis-mobilecode" / "outbox")
    parser.add_argument(
        "--processed-dir",
        type=Path,
        default=mobile_agent_dir / ".harvis-mobilecode" / "processed",
    )
    parser.add_argument(
        "--failed-dir",
        type=Path,
        default=mobile_agent_dir / ".harvis-mobilecode" / "failed",
    )
    parser.add_argument("--workspace-root", type=Path, default=repo_root)
    parser.add_argument("--once", action="store_true", help="Process at most one handoff and exit.")
    parser.add_argument("--poll-interval", type=float, default=2.0)
    parser.add_argument("--route", action="store_true", help="Route ACK/evidence events via lark-relay.")
    parser.add_argument("--lark-relay-bin", default="lark-relay")
    parser.add_argument("--relay-config")
    parser.add_argument("--chat-id", default="oc_mobilecode_remote_worker")
    parser.add_argument("--sender-id", default="ou_mobilecode_remote_worker")
    parser.add_argument(
        "--phone-use-script",
        default=str(mobile_agent_dir / "tooling" / "harvis_mobilecode_phone_use_emulator_smoke.sh"),
    )
    parser.add_argument("--phone-use-serial", default="")
    parser.add_argument("--phone-use-apk", default="")
    parser.add_argument("--phone-use-package", default="com.mobilecode.app")
    parser.add_argument("--phone-use-activity", default=".MainActivity")
    parser.add_argument("--phone-use-skip-install", action="store_true")
    parser.add_argument("--phone-use-build-debug", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    args.inbox.mkdir(parents=True, exist_ok=True)
    args.outbox.mkdir(parents=True, exist_ok=True)
    args.failed_dir.mkdir(parents=True, exist_ok=True)

    while True:
        files = find_handoff_files(args.inbox)
        if not files:
            if args.once:
                print(json.dumps({"ok": True, "processed": 0}, indent=2))
                return 0
            time.sleep(args.poll_interval)
            continue
        path = files[0]
        try:
            result = process_file(path, args)
            print(json.dumps(redact(result), indent=2, ensure_ascii=False))
            if args.once:
                return 0 if result["ok"] else 1
        except WorkerError as error:
            args.failed_dir.mkdir(parents=True, exist_ok=True)
            failed_target = args.failed_dir / f"{datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')}.{path.name}"
            shutil.move(str(path), failed_target)
            report = {"ok": False, "error": str(error), "details": error.details, "file": str(failed_target)}
            print(json.dumps(redact(report), indent=2, ensure_ascii=False), file=sys.stderr)
            if args.once:
                return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
