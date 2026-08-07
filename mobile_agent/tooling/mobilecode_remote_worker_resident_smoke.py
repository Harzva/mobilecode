#!/usr/bin/env python3
"""Smoke-test the resident MobileCode Harvis remote worker loop."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def utc_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")


def script_paths() -> tuple[Path, Path, Path]:
    script_dir = Path(__file__).resolve().parent
    mobile_agent_dir = script_dir.parent
    repo_root = mobile_agent_dir.parent
    return script_dir, mobile_agent_dir, repo_root


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def read_json(path: Path) -> dict[str, Any]:
    decoded = json.loads(path.read_text(encoding="utf-8"))
    return decoded if isinstance(decoded, dict) else {}


def wait_for_evidence(outbox: Path, count: int, deadline: float) -> list[Path]:
    while time.time() < deadline:
        evidence = sorted(outbox.glob("*.action-evidence.json"))
        if len(evidence) >= count:
            return evidence
        time.sleep(0.1)
    return sorted(outbox.glob("*.action-evidence.json"))


def evidence_for_action(payloads: list[dict[str, Any]], action: str) -> list[dict[str, Any]]:
    return [payload for payload in payloads if payload.get("action") == action]


def terminate_worker(process: subprocess.Popen[str], stdout_path: Path, stderr_path: Path) -> None:
    if process.poll() is None:
        process.terminate()
        try:
            stdout, stderr = process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            stdout, stderr = process.communicate(timeout=5)
    else:
        stdout, stderr = process.communicate(timeout=5)
    stdout_path.write_text(stdout, encoding="utf-8")
    stderr_path.write_text(stderr, encoding="utf-8")


def parse_args(argv: list[str]) -> argparse.Namespace:
    script_dir, mobile_agent_dir, repo_root = script_paths()
    stamp = utc_stamp()
    parser = argparse.ArgumentParser(description="Run a resident MobileCode remote worker smoke test.")
    parser.add_argument("--workspace-root", type=Path, default=repo_root)
    parser.add_argument("--worker", type=Path, default=script_dir / "mobilecode_remote_worker.py")
    parser.add_argument(
        "--project-check-fixture",
        type=Path,
        default=mobile_agent_dir / "test" / "fixtures" / "harvis_mobilecode_handoff.project_check.json",
    )
    parser.add_argument(
        "--validate-fixture",
        type=Path,
        default=mobile_agent_dir / "test" / "fixtures" / "harvis_mobilecode_handoff.validate.json",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=mobile_agent_dir / "qa-output" / f"harvis-mobilecode-resident-worker-smoke-{stamp}",
    )
    parser.add_argument("--timeout", type=float, default=15.0)
    parser.add_argument("--poll-interval", type=float, default=0.2)
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    output = args.output.resolve()
    queue = output / "queue"
    inbox = queue / "inbox"
    outbox = queue / "outbox"
    processed = queue / "processed"
    failed = queue / "failed"
    logs = output / "logs"
    for directory in (inbox, outbox, processed, failed, logs):
        directory.mkdir(parents=True, exist_ok=True)

    command = [
        sys.executable,
        str(args.worker),
        "--workspace-root",
        str(args.workspace_root),
        "--inbox",
        str(inbox),
        "--outbox",
        str(outbox),
        "--processed-dir",
        str(processed),
        "--failed-dir",
        str(failed),
        "--poll-interval",
        str(args.poll_interval),
    ]
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    time.sleep(min(args.poll_interval, 0.2))
    worker_started = process.poll() is None
    first_alive = False
    try:
        shutil.copy(args.project_check_fixture, inbox / "001-project-check.json")
        wait_for_evidence(outbox, 1, time.time() + args.timeout)
        first_alive = process.poll() is None
        shutil.copy(args.validate_fixture, inbox / "002-validate.json")
        evidence_files = wait_for_evidence(outbox, 2, time.time() + args.timeout)
    finally:
        terminate_worker(process, logs / "worker.stdout.jsonl", logs / "worker.stderr.txt")

    evidence_payloads = [read_json(path) for path in sorted(outbox.glob("*.action-evidence.json"))]
    project_check_payloads = evidence_for_action(evidence_payloads, "project_check")
    validate_payloads = evidence_for_action(evidence_payloads, "validate")
    checks = {
        "worker_started": worker_started,
        "worker_continued_after_first_handoff": first_alive,
        "project_check_verified": len(project_check_payloads) == 1
        and project_check_payloads[0].get("status") == "verified",
        "validate_verified": len(validate_payloads) == 1
        and validate_payloads[0].get("status") == "verified",
        "two_evidence_payloads": len(evidence_files) >= 2,
        "no_duplicate_action_evidence": len(project_check_payloads) == 1
        and len(validate_payloads) == 1,
        "two_processed_files": len(list(processed.iterdir())) >= 2,
        "failed_dir_empty": not list(failed.iterdir()),
    }
    summary = {
        "schema": "harvis_mobilecode_resident_worker_smoke.v1",
        "ok": all(checks.values()),
        "checks": checks,
        "artifacts": {
            "queue": "queue",
            "outbox": "queue/outbox",
            "processed": "queue/processed",
            "worker_stdout": "logs/worker.stdout.jsonl",
            "worker_stderr": "logs/worker.stderr.txt",
        },
        "created_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    }
    write_json(output / "summary.json", summary)
    print(json.dumps(summary, indent=2, ensure_ascii=False))
    print(f"Evidence: {output}")
    return 0 if summary["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
