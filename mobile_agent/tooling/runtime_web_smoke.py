#!/usr/bin/env python3
"""
MobileCode runtime web-project end-to-end smoke test.

Creates a minimal web project in a temp workspace, starts the helper daemon on
a temporary localhost port, then exercises the Helper Runtime Protocol v1:
  /v1/health
  /v1/project/preflight
  /v1/execute  (test script)
  /v1/execute  (build script)
  /v1/tasks?limit=...
  /v1/tasks/:id/logs

The build step copies index.html into dist/ without requiring npm install or
network access.  "Preview" evidence is dist/index.html existing and being
readable.

Exit 0 on success, non-zero on failure.
"""

from __future__ import annotations

import argparse
import json
import signal
import socket
import subprocess
import sys
import tempfile
import time
from http.client import HTTPConnection
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
HELPER_DAEMON = SCRIPT_DIR / "mobilecode_helper_daemon.py"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _helper_python_command() -> str:
    """Return the python executable name suitable for the Helper allowlist.

    On Windows ``python3`` is not available; the launcher is ``python``.
    On POSIX ``python3`` is the canonical name.
    """
    if sys.platform == "win32":
        return "python"
    return "python3"


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _http_json(
    conn: HTTPConnection,
    method: str,
    path: str,
    body: dict | None,
    token: str,
) -> dict:
    headers = {
        "X-MobileCode-Token": token,
        "Content-Type": "application/json",
    }
    payload = json.dumps(body or {}).encode()
    conn.request(method, path, body=payload, headers=headers)
    resp = conn.getresponse()
    data = resp.read().decode()
    result = json.loads(data)
    result["_status"] = resp.status
    return result


def _wait_ready(conn: HTTPConnection, token: str, timeout: float = 10.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            r = _http_json(conn, "GET", "/v1/health", None, token)
            if r.get("ready"):
                return True
        except Exception:
            pass
        time.sleep(0.3)
    return False


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        default=None,
        help="Write JSON result to this path (default: stdout only).",
    )
    args = parser.parse_args()

    results: dict[str, object] = {"steps": []}
    passed = True

    with tempfile.TemporaryDirectory(prefix="mc-web-smoke-") as tmpdir:
        workspace = Path(tmpdir)
        token = "smoke-token"
        port = _free_port()

        # -- Create minimal web project -----------------------------------
        py = _helper_python_command()
        pkg = {
            "name": "smoke-web",
            "version": "0.0.0",
            "private": True,
            "scripts": {
                "test": f"{py} -c \"print('test passed')\"",
                "build": f"{py} -c \"import shutil,os;os.makedirs('dist',exist_ok=True);shutil.copy('index.html','dist/index.html')\"",
            },
        }
        (workspace / "package.json").write_text(json.dumps(pkg, indent=2), encoding="utf-8")
        (workspace / "index.html").write_text(
            "<!DOCTYPE html>\n<html><body><h1>MobileCode Smoke</h1></body></html>\n",
            encoding="utf-8",
        )

        # -- Start helper daemon ------------------------------------------
        daemon_proc = subprocess.Popen(
            [
                sys.executable,
                str(HELPER_DAEMON),
                "--port",
                str(port),
                "--workspace-root",
                str(workspace),
                "--auth-token",
                token,
                "--max-concurrent-tasks",
                "1",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        try:
            conn = HTTPConnection("127.0.0.1", port, timeout=15)

            # Step 1: /v1/health
            if not _wait_ready(conn, token):
                results["steps"].append({"name": "health", "ok": False, "error": "daemon not ready"})
                passed = False
            else:
                health = _http_json(conn, "GET", "/v1/health", None, token)
                ok = health.get("ready") is True and health.get("_status") == 200
                results["steps"].append({"name": "health", "ok": ok, "response": health})
                if not ok:
                    passed = False

            # Step 2: /v1/project/preflight
            preflight = _http_json(
                conn, "POST", "/v1/project/preflight", {"cwd": str(workspace)}, token
            )
            detected = preflight.get("detectedFiles", [])
            ok = preflight.get("success") is True and "./package.json" in detected
            results["steps"].append({"name": "preflight", "ok": ok, "response": preflight})
            if not ok:
                passed = False

            # Step 3: /v1/execute test
            test_exec = _http_json(
                conn,
                "POST",
                "/v1/execute",
                {
                    "command": f"{py} -c \"print('test passed')\"",
                    "cwd": str(workspace),
                    "timeoutMs": 10000,
                },
                token,
            )
            ok = test_exec.get("exitCode") == 0 and "test passed" in test_exec.get("stdout", "")
            results["steps"].append({"name": "execute-test", "ok": ok, "response": test_exec})
            if not ok:
                passed = False

            # Step 4: /v1/execute build (copy index.html -> dist/index.html)
            build_cmd = (
                f"{py} -c \"import shutil,os;os.makedirs('dist',exist_ok=True);"
                "shutil.copy('index.html','dist/index.html')\""
            )
            build_exec = _http_json(
                conn,
                "POST",
                "/v1/execute",
                {"command": build_cmd, "cwd": str(workspace), "timeoutMs": 10000},
                token,
            )
            dist_file = workspace / "dist" / "index.html"
            ok = build_exec.get("exitCode") == 0 and dist_file.is_file()
            results["steps"].append({"name": "execute-build", "ok": ok, "response": build_exec})
            if not ok:
                passed = False

            # Step 5: /v1/tasks?limit=10
            tasks_resp = _http_json(conn, "GET", "/v1/tasks?limit=10", None, token)
            task_count = tasks_resp.get("count", 0)
            ok = task_count >= 2
            results["steps"].append({"name": "tasks-list", "ok": ok, "response": tasks_resp})
            if not ok:
                passed = False

            # Step 6: /v1/tasks/:id/logs for the build task
            build_task_id = build_exec.get("taskId", "")
            if build_task_id:
                logs_resp = _http_json(
                    conn, "GET", f"/v1/tasks/{build_task_id}/logs?limit=20", None, token
                )
                has_logs = bool(logs_resp.get("logs"))
                results["steps"].append(
                    {"name": "task-logs", "ok": has_logs, "response": logs_resp}
                )
                if not has_logs:
                    passed = False
            else:
                results["steps"].append(
                    {"name": "task-logs", "ok": False, "error": "no build taskId"}
                )
                passed = False

            # Step 7: preview evidence - dist/index.html readable
            if dist_file.is_file():
                content = dist_file.read_text(encoding="utf-8")
                ok = "MobileCode Smoke" in content
                results["steps"].append(
                    {"name": "preview-evidence", "ok": ok, "path": str(dist_file)}
                )
                if not ok:
                    passed = False
            else:
                results["steps"].append(
                    {"name": "preview-evidence", "ok": False, "error": "dist/index.html missing"}
                )
                passed = False

            conn.close()

        finally:
            daemon_proc.send_signal(signal.SIGTERM)
            try:
                daemon_proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                daemon_proc.kill()
                daemon_proc.wait()

    results["passed"] = passed
    results["totalSteps"] = len(results["steps"])
    results["passedSteps"] = sum(1 for s in results["steps"] if s.get("ok"))

    output_text = json.dumps(results, indent=2, ensure_ascii=False)
    print(output_text)

    if args.output:
        out_path = Path(args.output)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(output_text + "\n", encoding="utf-8")

    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
