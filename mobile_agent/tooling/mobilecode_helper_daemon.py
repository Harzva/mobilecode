#!/usr/bin/env python3
"""
MobileCode Helper daemon prototype.

Runs a localhost HTTP server that implements the MobileCode Helper Runtime
Protocol v1. It is intentionally small and dependency-free so it can run inside
Termux while the real Helper APK is being built.
"""

from __future__ import annotations

import argparse
import json
import os
import queue
import shlex
import signal
import subprocess
import sys
import threading
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


DEFAULT_ALLOWED_COMMANDS = {
    "pwd",
    "ls",
    "cat",
    "head",
    "tail",
    "grep",
    "find",
    "wc",
    "sort",
    "uniq",
    "sed",
    "awk",
    "mkdir",
    "touch",
    "cp",
    "mv",
    "rm",
    "git",
    "node",
    "npm",
    "npx",
    "python",
    "python3",
    "pip",
    "pip3",
    "dart",
    "flutter",
    "java",
    "javac",
    "gradle",
    "chmod",
    "tar",
    "zip",
    "unzip",
    "curl",
    "wget",
    "which",
    "whoami",
    "date",
    "echo",
}

DANGEROUS_FRAGMENTS = (
    "rm -rf /",
    "rm -rf /*",
    "mkfs",
    "dd if=",
    ":(){:|:&};:",
    "chmod -R 777 /",
    "chown -R",
    "reboot",
    "shutdown",
    "poweroff",
    "su ",
)


class HelperState:
    def __init__(self, workspace_root: Path, allow_unsafe: bool = False) -> None:
        self.workspace_root = workspace_root.resolve()
        self.allow_unsafe = allow_unsafe
        self.current_process: subprocess.Popen[str] | None = None
        self.current_lock = threading.Lock()
        self.task_file = self.workspace_root / ".mobilecode-helper-task.json"
        self.current_task: dict[str, Any] | None = None
        self._load_task()

    def capabilities(self) -> dict[str, bool]:
        return {
            "shell": True,
            "git": has_binary("git"),
            "node": has_binary("node") or has_binary("npm"),
            "python": has_binary("python") or has_binary("python3"),
            "flutter": has_binary("flutter"),
            "androidBuild": has_binary("flutter") and has_binary("java"),
            "pty": False,
            "backgroundService": False,
            "webViewPreview": True,
            "cloudBuild": False,
        }

    def validate_cwd(self, cwd: str | None) -> Path:
        if not cwd:
            return self.workspace_root
        path = Path(cwd).expanduser().resolve()
        if path == self.workspace_root or self.workspace_root in path.parents:
            return path
        raise ValueError(f"cwd is outside workspace root: {path}")

    def command_args(self, command: str) -> list[str]:
        if not command.strip():
            raise ValueError("command cannot be empty")
        lowered = command.lower()
        for fragment in DANGEROUS_FRAGMENTS:
            if fragment in lowered:
                raise ValueError(f"dangerous command fragment blocked: {fragment}")
        parts = shlex.split(command)
        if not parts:
            raise ValueError("command cannot be empty")
        if self.allow_unsafe:
            return parts
        executable = Path(parts[0]).name.lower()
        if executable.endswith(".exe"):
            executable = executable[:-4]
        if executable not in DEFAULT_ALLOWED_COMMANDS:
            raise ValueError(f"command is not allowed: {executable}")
        return parts

    def begin_task(self, command: str, cwd: Path) -> dict[str, Any]:
        task = {
            "id": f"task-{int(time.time() * 1000)}-{os.getpid()}",
            "taskId": "",
            "command": command,
            "cwd": str(cwd),
            "status": "running",
            "startedAtMs": int(time.time() * 1000),
            "finishedAtMs": 0,
            "durationMs": 0,
            "logs": [],
            "provider": "mobileCodeHelper",
        }
        task["taskId"] = task["id"]
        with self.current_lock:
            self.current_task = task
            self._persist_task_locked()
        return task

    def append_log(self, line: str) -> None:
        with self.current_lock:
            if self.current_task is None:
                return
            logs = self.current_task.setdefault("logs", [])
            if isinstance(logs, list):
                logs.append(line)
                del logs[:-200]
            self._persist_task_locked()

    def finish_task(self, status: str, exit_code: int | None, duration_ms: int, error: str | None = None) -> None:
        with self.current_lock:
            if self.current_task is None:
                return
            self.current_task["status"] = status
            self.current_task["finishedAtMs"] = int(time.time() * 1000)
            self.current_task["durationMs"] = duration_ms
            if exit_code is not None:
                self.current_task["exitCode"] = exit_code
            if error:
                self.current_task["error"] = error
            self._persist_task_locked()

    def task_snapshot(self) -> dict[str, Any]:
        with self.current_lock:
            task = dict(self.current_task or {})
            logs = task.get("logs", [])
            if isinstance(logs, list):
                task["logs"] = list(logs)
            return task

    def _load_task(self) -> None:
        if not self.task_file.exists():
            return
        try:
            loaded = json.loads(self.task_file.read_text(encoding="utf-8"))
            if not isinstance(loaded, dict):
                return
            self.current_task = loaded
            if loaded.get("status") == "running":
                loaded["status"] = "lost"
                loaded["finishedAtMs"] = int(time.time() * 1000)
                loaded["error"] = "Helper daemon restarted before this task completed."
                logs = loaded.setdefault("logs", [])
                if isinstance(logs, list):
                    logs.append("task lost after helper restart")
                self._persist_task_locked()
        except Exception:
            self.current_task = None

    def _persist_task_locked(self) -> None:
        if not self.current_task:
            return
        self.task_file.write_text(json.dumps(self.current_task, ensure_ascii=False), encoding="utf-8")


def has_binary(name: str) -> bool:
    path_env = os.environ.get("PATH", "")
    for directory in path_env.split(os.pathsep):
        candidate = Path(directory) / name
        if candidate.exists() and os.access(candidate, os.X_OK):
            return True
    return False


def json_bytes(payload: dict[str, Any]) -> bytes:
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def read_json(handler: BaseHTTPRequestHandler) -> dict[str, Any]:
    length = int(handler.headers.get("Content-Length", "0"))
    if length <= 0:
        return {}
    data = handler.rfile.read(length)
    decoded = json.loads(data.decode("utf-8"))
    if not isinstance(decoded, dict):
        raise ValueError("JSON body must be an object")
    return decoded


def command_result(
    command: str,
    args: list[str],
    cwd: Path,
    env: dict[str, str] | None,
    timeout_ms: int,
) -> dict[str, Any]:
    started = time.monotonic()
    merged_env = os.environ.copy()
    if env:
        merged_env.update({str(k): str(v) for k, v in env.items()})
    completed = subprocess.run(
        args,
        cwd=str(cwd),
        env=merged_env,
        text=True,
        capture_output=True,
        timeout=max(timeout_ms / 1000, 1),
    )
    duration_ms = int((time.monotonic() - started) * 1000)
    return {
        "command": command,
        "stdout": completed.stdout,
        "stderr": completed.stderr,
        "exitCode": completed.returncode,
        "durationMs": duration_ms,
    }


class MobileCodeHandler(BaseHTTPRequestHandler):
    server_version = "MobileCodeHelper/0.1"

    @property
    def state(self) -> HelperState:
        return self.server.state  # type: ignore[attr-defined]

    def do_GET(self) -> None:  # noqa: N802
        try:
            if self.path == "/v1/health":
                self.send_json(
                    {
                        "name": "MobileCode Helper Prototype",
                        "available": True,
                        "ready": True,
                        "status": f"Helper daemon running at {self.server.server_address}",
                        "capabilities": self.state.capabilities(),
                        "missingDependencies": [],
                        "recoveryActions": [],
                    }
                )
                return
            if self.path == "/v1/tasks/current":
                task = self.state.task_snapshot()
                self.send_json(
                    {
                        "running": task.get("status") == "running",
                        "taskId": task.get("id", ""),
                        "command": task.get("command", ""),
                        "logs": task.get("logs", []),
                        "task": task,
                    }
                )
                return
            self.send_error_json(HTTPStatus.NOT_FOUND, "Unknown endpoint")
        except Exception as exc:  # pragma: no cover - defensive server boundary
            self.send_error_json(HTTPStatus.INTERNAL_SERVER_ERROR, str(exc))

    def do_POST(self) -> None:  # noqa: N802
        try:
            if self.path == "/v1/execute":
                self.handle_execute()
                return
            if self.path == "/v1/execute/stream":
                self.handle_execute_stream()
                return
            if self.path == "/v1/task/stop":
                self.handle_stop()
                return
            self.send_error_json(HTTPStatus.NOT_FOUND, "Endpoint is not implemented in prototype")
        except Exception as exc:
            self.send_error_json(HTTPStatus.BAD_REQUEST, str(exc))

    def handle_execute(self) -> None:
        payload = read_json(self)
        command = str(payload.get("command", ""))
        cwd = self.state.validate_cwd(payload.get("cwd"))
        env = payload.get("env") if isinstance(payload.get("env"), dict) else None
        timeout_ms = int(payload.get("timeoutMs", 120000))
        args = self.state.command_args(command)
        task = self.state.begin_task(command, cwd)
        self.state.append_log(f"task {task['id']}: {command}")
        started = time.monotonic()
        merged_env = os.environ.copy()
        if env:
            merged_env.update({str(k): str(v) for k, v in env.items()})
        process = subprocess.Popen(
            args,
            cwd=str(cwd),
            env=merged_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        with self.state.current_lock:
            self.state.current_process = process
        timed_out = False
        try:
            stdout, stderr = process.communicate(timeout=max(timeout_ms / 1000, 1))
        except subprocess.TimeoutExpired:
            timed_out = True
            process.kill()
            stdout, stderr = process.communicate()
            stderr = (stderr or "") + f"\nCommand timed out after {timeout_ms}ms.\n"
        duration_ms = int((time.monotonic() - started) * 1000)
        exit_code = 124 if timed_out else process.returncode
        for line in (stdout or "").splitlines():
            self.state.append_log(f"stdout: {line}")
        for line in (stderr or "").splitlines():
            self.state.append_log(f"stderr: {line}")
        with self.state.current_lock:
            if self.state.current_process is process:
                self.state.current_process = None
            cancelled = self.state.current_task is not None and self.state.current_task.get("status") == "cancelled"
        status = "cancelled" if cancelled else "timedOut" if timed_out else "succeeded" if exit_code == 0 else "failed"
        self.state.finish_task(status, exit_code, duration_ms, (stderr or "").strip() or None)
        self.send_json(
            {
                "command": command,
                "stdout": stdout or "",
                "stderr": stderr or "",
                "exitCode": exit_code,
                "durationMs": duration_ms,
                "taskId": task["id"],
            }
        )

    def handle_execute_stream(self) -> None:
        payload = read_json(self)
        command = str(payload.get("command", ""))
        cwd = self.state.validate_cwd(payload.get("cwd"))
        env = payload.get("env") if isinstance(payload.get("env"), dict) else None
        args = self.state.command_args(command)
        task = self.state.begin_task(command, cwd)
        self.state.append_log(f"task {task['id']} stream: {command}")

        merged_env = os.environ.copy()
        if env:
            merged_env.update({str(k): str(v) for k, v in env.items()})

        process = subprocess.Popen(
            args,
            cwd=str(cwd),
            env=merged_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=1,
            universal_newlines=True,
        )

        with self.state.current_lock:
            self.state.current_process = process

        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "application/x-ndjson")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()

        started = time.monotonic()
        output_queue: queue.Queue[tuple[str, str | None]] = queue.Queue()

        def pump(stream: Any, stream_type: str) -> None:
            for line in iter(stream.readline, ""):
                output_queue.put((stream_type, line.rstrip("\n")))
            output_queue.put((stream_type, None))

        threads = [
            threading.Thread(target=pump, args=(process.stdout, "stdout"), daemon=True),
            threading.Thread(target=pump, args=(process.stderr, "stderr"), daemon=True),
        ]
        for thread in threads:
            thread.start()

        ended_streams = 0
        while ended_streams < 2:
            stream_type, line = output_queue.get()
            if line is None:
                ended_streams += 1
                continue
            self.state.append_log(f"{stream_type}: {line}")
            self.write_ndjson({"type": stream_type, "data": line})

        exit_code = process.wait()
        duration_ms = int((time.monotonic() - started) * 1000)
        with self.state.current_lock:
            if self.state.current_process is process:
                self.state.current_process = None
            cancelled = self.state.current_task is not None and self.state.current_task.get("status") == "cancelled"
        status = "cancelled" if cancelled else "succeeded" if exit_code == 0 else "failed"
        self.state.finish_task(status, exit_code, duration_ms)
        self.write_ndjson({"type": "exit", "exitCode": exit_code, "durationMs": duration_ms, "taskId": task["id"]})

    def handle_stop(self) -> None:
        with self.state.current_lock:
            process = self.state.current_process
        if process is None:
            self.send_json({"success": True, "stopped": False})
            return
        process.send_signal(signal.SIGTERM)
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
        self.state.append_log("task stopped")
        self.state.finish_task("cancelled", None, 0, "Task cancelled by MobileCode.")
        self.send_json({"success": True, "stopped": True})

    def send_json(self, payload: dict[str, Any], status: HTTPStatus = HTTPStatus.OK) -> None:
        data = json_bytes(payload)
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def send_error_json(self, status: HTTPStatus, message: str) -> None:
        self.send_json({"error": message, "success": False}, status=status)

    def write_ndjson(self, payload: dict[str, Any]) -> None:
        self.wfile.write(json_bytes(payload) + b"\n")
        self.wfile.flush()

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write("[mobilecode-helper] " + fmt % args + "\n")


class MobileCodeServer(ThreadingHTTPServer):
    def __init__(self, address: tuple[str, int], state: HelperState) -> None:
        super().__init__(address, MobileCodeHandler)
        self.state = state


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the MobileCode Helper daemon prototype.")
    parser.add_argument("--host", default="127.0.0.1", help="Bind host, default: 127.0.0.1")
    parser.add_argument("--port", default=8765, type=int, help="Bind port, default: 8765")
    parser.add_argument(
        "--workspace-root",
        default=os.environ.get("MOBILECODE_WORKSPACE_ROOT", str(Path.home() / "mobilecode_projects")),
        help="Allowed workspace root for command cwd.",
    )
    parser.add_argument(
        "--allow-unsafe",
        action="store_true",
        help="Disable command allowlist. Only use for trusted local debugging.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    workspace_root = Path(args.workspace_root).expanduser()
    workspace_root.mkdir(parents=True, exist_ok=True)
    state = HelperState(workspace_root=workspace_root, allow_unsafe=args.allow_unsafe)
    server = MobileCodeServer((args.host, args.port), state)
    print(
        f"MobileCode Helper daemon listening on http://{args.host}:{args.port} "
        f"(workspace: {state.workspace_root})",
        flush=True,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping MobileCode Helper daemon.", flush=True)
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
