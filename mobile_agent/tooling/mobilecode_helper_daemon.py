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
import uuid
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, unquote, urlparse


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

PROJECT_MARKERS = {"package.json", "pubspec.yaml", "requirements.txt", "pyproject.toml", ".git"}


class HelperState:
    def __init__(
        self,
        workspace_root: Path,
        allow_unsafe: bool = False,
        auth_token: str | None = None,
        max_tasks: int = 50,
        max_concurrent_tasks: int = 1,
    ) -> None:
        self.workspace_root = workspace_root.resolve()
        self.allow_unsafe = allow_unsafe
        self.auth_token = (auth_token or "").strip()
        self.max_tasks = max_tasks
        self.max_concurrent_tasks = max(1, max_concurrent_tasks)
        self.current_lock = threading.Lock()
        self.task_condition = threading.Condition(self.current_lock)
        self.task_file = self.workspace_root / ".mobilecode-helper-task.json"
        self.task_database_file = self.workspace_root / ".mobilecode-helper-tasks.json"
        self.current_task: dict[str, Any] | None = None
        self.tasks: list[dict[str, Any]] = []
        self.processes: dict[str, subprocess.Popen[str]] = {}
        self._load_tasks()

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

    def begin_task(self, command: str, cwd: Path, priority: int = 0) -> dict[str, Any]:
        now_ms = int(time.time() * 1000)
        task = {
            "id": f"task-{now_ms}-{uuid.uuid4().hex[:8]}",
            "taskId": "",
            "command": command,
            "cwd": str(cwd),
            "status": "queued",
            "priority": priority,
            "enqueuedAtMs": now_ms,
            "startedAtMs": 0,
            "finishedAtMs": 0,
            "durationMs": 0,
            "logs": [],
            "provider": "mobileCodeHelper",
            "failureKind": "none",
        }
        task["taskId"] = task["id"]
        with self.current_lock:
            self.current_task = task
            self.tasks.insert(0, task)
            del self.tasks[self.max_tasks :]
            self._persist_tasks_locked()
            self.task_condition.notify_all()
        return task

    def wait_for_turn(self, task_id: str) -> bool:
        with self.task_condition:
            while True:
                task = self._find_task_locked(task_id)
                if task is None:
                    return False
                if task.get("status") == "cancelled":
                    return False
                if task.get("status") == "running":
                    return True
                next_task = self._next_queued_task_locked()
                if (
                    next_task is not None
                    and task_identity(next_task) == task_id
                    and self._running_task_count_locked() < self.max_concurrent_tasks
                ):
                    task["status"] = "running"
                    task["startedAtMs"] = int(time.time() * 1000)
                    self._append_task_log_locked(task, "task started")
                    self._sync_current_task_locked()
                    self._persist_tasks_locked()
                    self.task_condition.notify_all()
                    return True
                self.task_condition.wait(timeout=0.5)

    def register_process(self, task_id: str, process: subprocess.Popen[str]) -> None:
        with self.current_lock:
            if self._find_task_locked(task_id) is None:
                return
            self.processes[task_id] = process
            self._persist_tasks_locked()

    def clear_process(self, task_id: str, process: subprocess.Popen[str]) -> None:
        with self.current_lock:
            if self.processes.get(task_id) is process:
                self.processes.pop(task_id, None)
            self._persist_tasks_locked()
            self.task_condition.notify_all()

    def append_log(self, task_id: str, line: str) -> None:
        with self.current_lock:
            task = self._find_task_locked(task_id)
            if task is None:
                return
            self._append_task_log_locked(task, line)
            self._persist_tasks_locked()

    def finish_task(self, task_id: str, status: str, exit_code: int | None, duration_ms: int, error: str | None = None) -> None:
        with self.current_lock:
            task = self._find_task_locked(task_id)
            if task is None:
                return
            if task.get("status") == "cancelled":
                status = "cancelled"
                error = error or str(task.get("error") or "") or None
            task["status"] = status
            task["finishedAtMs"] = int(time.time() * 1000)
            task["durationMs"] = duration_ms
            if exit_code is not None:
                task["exitCode"] = exit_code
            if error:
                task["error"] = error
            task["failureKind"] = classify_failure(status, exit_code, error)
            self._sync_current_task_locked()
            self._persist_tasks_locked()
            self.task_condition.notify_all()

    def task_snapshot(self) -> dict[str, Any]:
        with self.current_lock:
            self._sync_current_task_locked()
            return clone_task(self.current_task or {})

    def task_list(self, limit: int = 20) -> list[dict[str, Any]]:
        with self.current_lock:
            tasks = self.tasks[: max(1, min(limit, self.max_tasks))]
            return [clone_task(task) for task in tasks]

    def task_logs(self, task_id: str, limit: int = 200) -> list[str]:
        with self.current_lock:
            for task in self.tasks:
                if task.get("id") == task_id or task.get("taskId") == task_id:
                    logs = task.get("logs", [])
                    if not isinstance(logs, list):
                        return []
                    return [str(line) for line in logs[-max(1, limit) :]]
        return []

    def find_task(self, task_id: str) -> dict[str, Any] | None:
        with self.current_lock:
            task = self._find_task_locked(task_id)
            if task is not None:
                return clone_task(task)
        return None

    def current_running_task_id(self) -> str | None:
        with self.current_lock:
            if self.current_task is not None:
                task_id = task_identity(self.current_task)
                if self.current_task.get("status") == "running" and task_id in self.processes:
                    return task_id
            for task in self.tasks:
                task_id = task_identity(task)
                if task.get("status") == "running" and task_id in self.processes:
                    return task_id
        return None

    def is_task_cancelled(self, task_id: str) -> bool:
        with self.current_lock:
            task = self._find_task_locked(task_id)
            return task is not None and task.get("status") == "cancelled"

    def cancel_task(self, task_id: str) -> tuple[subprocess.Popen[str] | None, dict[str, Any] | None, bool]:
        with self.current_lock:
            task = self._find_task_locked(task_id)
            if task is None:
                return None, None, False
            process = self.processes.pop(task_id, None)
            if process is None:
                if task.get("status") == "queued":
                    self._append_task_log_locked(task, "queued task cancelled")
                    finished_at_ms = int(time.time() * 1000)
                    enqueued_at_ms = int(task.get("enqueuedAtMs") or finished_at_ms)
                    task["status"] = "cancelled"
                    task["finishedAtMs"] = finished_at_ms
                    task["durationMs"] = max(0, finished_at_ms - enqueued_at_ms)
                    task["error"] = "Queued task cancelled by MobileCode."
                    task["failureKind"] = "cancelled"
                    self._sync_current_task_locked()
                    self._persist_tasks_locked()
                    self.task_condition.notify_all()
                    return None, clone_task(task), True
                return None, clone_task(task), False
            self._append_task_log_locked(task, "task stopped")
            finished_at_ms = int(time.time() * 1000)
            started_at_ms = int(task.get("startedAtMs") or finished_at_ms)
            task["status"] = "cancelled"
            task["finishedAtMs"] = finished_at_ms
            task["durationMs"] = max(0, finished_at_ms - started_at_ms)
            task["error"] = "Task cancelled by MobileCode."
            task["failureKind"] = "cancelled"
            self._sync_current_task_locked()
            self._persist_tasks_locked()
            self.task_condition.notify_all()
            return process, clone_task(task), True

    def _find_task_locked(self, task_id: str) -> dict[str, Any] | None:
        for task in self.tasks:
            if task.get("id") == task_id or task.get("taskId") == task_id:
                return task
        return None

    def _append_task_log_locked(self, task: dict[str, Any], line: str) -> None:
        logs = task.setdefault("logs", [])
        if isinstance(logs, list):
            logs.append(line)
            del logs[:-200]

    def _sync_current_task_locked(self) -> None:
        if not self.tasks:
            self.current_task = None
            return
        for task in self.tasks:
            if task.get("status") == "running" and task_identity(task) in self.processes:
                self.current_task = task
                return
        for task in self.tasks:
            if task.get("status") == "queued":
                self.current_task = task
                return
        self.current_task = self.tasks[0]

    def has_running_tasks(self) -> bool:
        with self.current_lock:
            return any(task.get("status") == "running" and task_identity(task) in self.processes for task in self.tasks)

    def running_task_count(self) -> int:
        with self.current_lock:
            return self._running_task_count_locked()

    def queued_task_count(self) -> int:
        with self.current_lock:
            return self._queued_task_count_locked()

    def _running_task_count_locked(self) -> int:
        return sum(1 for task in self.tasks if task.get("status") == "running")

    def _queued_task_count_locked(self) -> int:
        return sum(1 for task in self.tasks if task.get("status") == "queued")

    def _next_queued_task_locked(self) -> dict[str, Any] | None:
        queued = [task for task in self.tasks if task.get("status") == "queued"]
        if not queued:
            return None
        queued.sort(
            key=lambda task: (
                -int(task.get("priority") or 0),
                int(task.get("enqueuedAtMs") or task.get("startedAtMs") or 0),
            )
        )
        return queued[0]

    def cancel_current_task(self, task_id: str, process: Any) -> dict[str, Any] | None:
        with self.current_lock:
            task = self._find_task_locked(task_id)
            if task is None or self.processes.get(task_id) is not process:
                return None
            self.processes.pop(task_id, None)
            self._append_task_log_locked(task, "task stopped")
            finished_at_ms = int(time.time() * 1000)
            started_at_ms = int(task.get("startedAtMs") or finished_at_ms)
            task["status"] = "cancelled"
            task["finishedAtMs"] = finished_at_ms
            task["durationMs"] = max(0, finished_at_ms - started_at_ms)
            task["error"] = "Task cancelled by MobileCode."
            task["failureKind"] = "cancelled"
            self._sync_current_task_locked()
            self._persist_tasks_locked()
            return clone_task(task)

    def inspect_project(self, cwd: Path, max_depth: int = 2) -> list[str]:
        detected: set[str] = set()
        for root, dirs, files in os.walk(cwd):
            root_path = Path(root)
            depth = len(root_path.relative_to(cwd).parts)
            if depth >= max_depth:
                dirs[:] = []
            for directory in list(dirs):
                if directory in PROJECT_MARKERS:
                    detected.add(f"./{(root_path / directory).relative_to(cwd).as_posix()}")
                if directory == ".git":
                    dirs.remove(directory)
            for filename in files:
                if filename in PROJECT_MARKERS:
                    detected.add(f"./{(root_path / filename).relative_to(cwd).as_posix()}")
        return sorted(detected)

    def _load_tasks(self) -> None:
        try:
            loaded_tasks: list[dict[str, Any]] = []
            if self.task_database_file.exists():
                decoded = json.loads(self.task_database_file.read_text(encoding="utf-8"))
                if isinstance(decoded, dict):
                    decoded = decoded.get("tasks", [])
                if isinstance(decoded, list):
                    loaded_tasks = [item for item in decoded if isinstance(item, dict)]
            elif self.task_file.exists():
                decoded = json.loads(self.task_file.read_text(encoding="utf-8"))
                if isinstance(decoded, dict):
                    loaded_tasks = [decoded]

            for task in loaded_tasks:
                if task.get("status") == "running":
                    task["status"] = "lost"
                    task["finishedAtMs"] = int(time.time() * 1000)
                    task["failureKind"] = "runtimeLost"
                    task["error"] = "Helper daemon restarted before this task completed."
                    logs = task.setdefault("logs", [])
                    if isinstance(logs, list):
                        logs.append("task lost after helper restart")
                elif task.get("status") == "queued":
                    task["status"] = "cancelled"
                    task["finishedAtMs"] = int(time.time() * 1000)
                    task["failureKind"] = "cancelled"
                    task["error"] = "Queued task cancelled because Helper daemon restarted."
                    logs = task.setdefault("logs", [])
                    if isinstance(logs, list):
                        logs.append("queued task cancelled after helper restart")
                else:
                    task["failureKind"] = task.get("failureKind") or classify_failure(
                        str(task.get("status") or "unknown"),
                        int(task["exitCode"]) if isinstance(task.get("exitCode"), int) else None,
                        str(task.get("error") or "") or None,
                    )
            loaded_tasks.sort(key=lambda item: int(item.get("startedAtMs") or 0), reverse=True)
            self.tasks = loaded_tasks[: self.max_tasks]
            self._sync_current_task_locked()
            self._persist_tasks_locked()
        except Exception:
            self.current_task = None
            self.tasks = []

    def _persist_tasks_locked(self) -> None:
        self._sync_current_task_locked()
        if not self.current_task:
            return
        self.task_file.write_text(json.dumps(self.current_task, ensure_ascii=False), encoding="utf-8")
        payload = {"tasks": self.tasks[: self.max_tasks]}
        self.task_database_file.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")


def has_binary(name: str) -> bool:
    path_env = os.environ.get("PATH", "")
    for directory in path_env.split(os.pathsep):
        candidate = Path(directory) / name
        if candidate.exists() and os.access(candidate, os.X_OK):
            return True
    return False


def clone_task(task: dict[str, Any]) -> dict[str, Any]:
    copied = dict(task)
    logs = copied.get("logs", [])
    if isinstance(logs, list):
        copied["logs"] = [str(line) for line in logs]
    return copied


def task_identity(task: dict[str, Any]) -> str:
    return str(task.get("id") or task.get("taskId") or "")


def classify_failure(status: str, exit_code: int | None, error: str | None) -> str:
    normalized_status = status.strip()
    message = (error or "").lower()
    if normalized_status == "succeeded":
        return "none"
    if normalized_status == "cancelled":
        return "cancelled"
    if normalized_status == "timedOut":
        return "timeout"
    if normalized_status == "lost":
        return "runtimeLost"
    if "outside workspace" in message:
        return "cwdOutsideWorkspace"
    if "not allowed" in message or "dangerous command" in message:
        return "commandBlocked"
    dependency_markers = (
        "command not found",
        "no such file or directory",
        "not found",
        "cannot find",
        "is not recognized",
    )
    if any(marker in message for marker in dependency_markers):
        return "dependencyMissing"
    if exit_code is not None and exit_code != 0:
        return "processFailed"
    return "unknown"


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
            if not self.authorized():
                self.send_error_json(HTTPStatus.UNAUTHORIZED, "Missing or invalid MobileCode Helper token", "authFailed")
                return

            parsed = urlparse(self.path)
            path = parsed.path
            query = parse_qs(parsed.query)
            if path == "/v1/health":
                self.send_json(
                    {
                        "name": "MobileCode Helper Prototype",
                        "available": True,
                        "ready": True,
                        "status": f"Helper daemon running at {self.server.server_address}",
                        "protocolVersion": 1,
                        "authRequired": bool(self.state.auth_token),
                        "capabilities": self.state.capabilities(),
                        "taskRegistry": {
                            "runningCount": self.state.running_task_count(),
                            "queueDepth": self.state.queued_task_count(),
                            "maxTasks": self.state.max_tasks,
                            "maxConcurrentTasks": self.state.max_concurrent_tasks,
                        },
                        "missingDependencies": [],
                        "recoveryActions": [],
                    }
                )
                return
            if path == "/v1/tasks/current":
                task = self.state.task_snapshot()
                self.send_json(
                    {
                        "running": task.get("status") == "running",
                        "runningCount": self.state.running_task_count(),
                        "taskId": task.get("id", ""),
                        "command": task.get("command", ""),
                        "logs": task.get("logs", []),
                        "task": task,
                    }
                )
                return
            if path == "/v1/tasks":
                limit = int((query.get("limit") or ["20"])[0])
                tasks = self.state.task_list(limit)
                self.send_json({"tasks": tasks, "count": len(tasks)})
                return
            if path.startswith("/v1/tasks/") and path.endswith("/logs"):
                task_id = unquote(path.removeprefix("/v1/tasks/").removesuffix("/logs").strip("/"))
                limit = int((query.get("limit") or ["200"])[0])
                self.send_json({"taskId": task_id, "logs": self.state.task_logs(task_id, limit)})
                return
            self.send_error_json(HTTPStatus.NOT_FOUND, "Unknown endpoint")
        except Exception as exc:  # pragma: no cover - defensive server boundary
            self.send_error_json(HTTPStatus.INTERNAL_SERVER_ERROR, str(exc))

    def do_POST(self) -> None:  # noqa: N802
        try:
            if not self.authorized():
                self.send_error_json(HTTPStatus.UNAUTHORIZED, "Missing or invalid MobileCode Helper token", "authFailed")
                return

            path = urlparse(self.path).path
            if path == "/v1/execute":
                self.handle_execute()
                return
            if path == "/v1/execute/stream":
                self.handle_execute_stream()
                return
            if path == "/v1/project/preflight":
                self.handle_project_preflight()
                return
            if path == "/v1/task/stop":
                self.handle_stop()
                return
            if path.startswith("/v1/tasks/") and path.endswith("/stop"):
                task_id = unquote(path.removeprefix("/v1/tasks/").removesuffix("/stop").strip("/"))
                self.handle_stop(task_id=task_id)
                return
            self.send_error_json(HTTPStatus.NOT_FOUND, "Endpoint is not implemented in prototype")
        except Exception as exc:
            self.send_error_json(HTTPStatus.BAD_REQUEST, str(exc))

    def authorized(self) -> bool:
        token = self.state.auth_token
        if not token:
            return True
        header_token = self.headers.get("X-MobileCode-Token", "")
        bearer = self.headers.get("Authorization", "")
        return header_token == token or bearer == f"Bearer {token}"

    def handle_execute(self) -> None:
        payload = read_json(self)
        command = str(payload.get("command", ""))
        cwd = self.state.validate_cwd(payload.get("cwd"))
        env = payload.get("env") if isinstance(payload.get("env"), dict) else None
        timeout_ms = int(payload.get("timeoutMs", 120000))
        priority = int(payload.get("priority", 0))
        args = self.state.command_args(command)
        task = self.state.begin_task(command, cwd, priority=priority)
        task_id = str(task["id"])
        self.state.append_log(task_id, f"task {task_id} queued: {command}")
        if not self.state.wait_for_turn(task_id):
            snapshot = self.state.find_task(task_id) or {}
            self.send_json(
                {
                    "command": command,
                    "stdout": "",
                    "stderr": str(snapshot.get("error") or "Task cancelled before it started."),
                    "exitCode": 130,
                    "durationMs": int(snapshot.get("durationMs") or 0),
                    "taskId": task_id,
                    "failureKind": snapshot.get("failureKind", "cancelled"),
                }
            )
            return
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
        self.state.register_process(task_id, process)
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
            self.state.append_log(task_id, f"stdout: {line}")
        for line in (stderr or "").splitlines():
            self.state.append_log(task_id, f"stderr: {line}")
        self.state.clear_process(task_id, process)
        cancelled = self.state.is_task_cancelled(task_id)
        status = "cancelled" if cancelled else "timedOut" if timed_out else "succeeded" if exit_code == 0 else "failed"
        self.state.finish_task(task_id, status, exit_code, duration_ms, (stderr or "").strip() or None)
        failure_kind = (self.state.find_task(task_id) or {}).get("failureKind", "none")
        self.send_json(
            {
                "command": command,
                "stdout": stdout or "",
                "stderr": stderr or "",
                "exitCode": exit_code,
                "durationMs": duration_ms,
                "taskId": task_id,
                "failureKind": failure_kind,
            }
        )

    def handle_execute_stream(self) -> None:
        payload = read_json(self)
        command = str(payload.get("command", ""))
        cwd = self.state.validate_cwd(payload.get("cwd"))
        env = payload.get("env") if isinstance(payload.get("env"), dict) else None
        priority = int(payload.get("priority", 0))
        args = self.state.command_args(command)
        task = self.state.begin_task(command, cwd, priority=priority)
        task_id = str(task["id"])
        self.state.append_log(task_id, f"task {task_id} stream queued: {command}")

        merged_env = os.environ.copy()
        if env:
            merged_env.update({str(k): str(v) for k, v in env.items()})

        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "application/x-ndjson")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.write_ndjson({"type": "status", "status": "queued", "taskId": task_id})
        if not self.state.wait_for_turn(task_id):
            snapshot = self.state.find_task(task_id) or {}
            self.write_ndjson(
                {
                    "type": "exit",
                    "exitCode": 130,
                    "durationMs": int(snapshot.get("durationMs") or 0),
                    "taskId": task_id,
                    "failureKind": snapshot.get("failureKind", "cancelled"),
                }
            )
            return
        self.write_ndjson({"type": "status", "status": "running", "taskId": task_id})

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
        self.state.register_process(task_id, process)

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
            self.state.append_log(task_id, f"{stream_type}: {line}")
            self.write_ndjson({"type": stream_type, "data": line})

        exit_code = process.wait()
        duration_ms = int((time.monotonic() - started) * 1000)
        self.state.clear_process(task_id, process)
        cancelled = self.state.is_task_cancelled(task_id)
        status = "cancelled" if cancelled else "succeeded" if exit_code == 0 else "failed"
        self.state.finish_task(task_id, status, exit_code, duration_ms)
        self.write_ndjson({"type": "exit", "exitCode": exit_code, "durationMs": duration_ms, "taskId": task_id})

    def handle_project_preflight(self) -> None:
        payload = read_json(self)
        cwd = self.state.validate_cwd(payload.get("cwd"))
        detected_files = self.state.inspect_project(cwd)
        self.send_json(
            {
                "success": True,
                "cwd": str(cwd),
                "detectedFiles": detected_files,
            }
        )

    def handle_stop(self, task_id: str | None = None) -> None:
        if task_id is None:
            task_id = self.state.current_running_task_id()
            if task_id is None:
                self.send_json({"success": True, "stopped": False})
                return
        if task_id:
            task = self.state.find_task(task_id)
            if task is None:
                self.send_error_json(HTTPStatus.NOT_FOUND, f"Task not found: {task_id}", "unknown")
                return
        process, snapshot, stopped = self.state.cancel_task(task_id)
        if not stopped:
            self.send_json({"success": True, "stopped": False, "taskId": task_id, "task": snapshot or task})
            return
        if process is None:
            self.send_json({"success": True, "stopped": True, "taskId": task_id, "task": snapshot or task})
            return
        process.send_signal(signal.SIGTERM)
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
        snapshot = self.state.find_task(task_id) or snapshot or {}
        self.send_json({"success": True, "stopped": True, "taskId": snapshot.get("id", task_id or ""), "task": snapshot})

    def send_json(self, payload: dict[str, Any], status: HTTPStatus = HTTPStatus.OK) -> None:
        data = json_bytes(payload)
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def send_error_json(self, status: HTTPStatus, message: str, failure_kind: str | None = None) -> None:
        payload: dict[str, Any] = {"error": message, "success": False}
        if failure_kind:
            payload["failureKind"] = failure_kind
        self.send_json(payload, status=status)

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
    parser.add_argument(
        "--auth-token",
        default=os.environ.get("MOBILECODE_HELPER_TOKEN", ""),
        help="Optional localhost token required through X-MobileCode-Token or Authorization: Bearer.",
    )
    parser.add_argument(
        "--max-tasks",
        default=50,
        type=int,
        help="Maximum recoverable task snapshots to keep, default: 50.",
    )
    parser.add_argument(
        "--max-concurrent-tasks",
        default=int(os.environ.get("MOBILECODE_HELPER_MAX_CONCURRENT_TASKS", "1")),
        type=int,
        help="Maximum concurrently running tasks before new tasks queue, default: 1.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    workspace_root = Path(args.workspace_root).expanduser()
    workspace_root.mkdir(parents=True, exist_ok=True)
    state = HelperState(
        workspace_root=workspace_root,
        allow_unsafe=args.allow_unsafe,
        auth_token=args.auth_token,
        max_tasks=max(1, args.max_tasks),
        max_concurrent_tasks=max(1, args.max_concurrent_tasks),
    )
    server = MobileCodeServer((args.host, args.port), state)
    auth_label = "auth: required" if state.auth_token else "auth: disabled"
    print(
        f"MobileCode Helper daemon listening on http://{args.host}:{args.port} "
        f"(workspace: {state.workspace_root}, {auth_label})",
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
