#!/usr/bin/env python3
"""Small HTTP bridge from MobileCode to a HyperFrames render host.

The phone sends a bounded JSON render request. This process owns Node.js,
Chromium and FFmpeg, then exposes the finished MP4 through a short-lived
artifact URL. It intentionally binds to loopback by default.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import tempfile
import threading
import time
import uuid
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse
from urllib.request import Request, urlopen


PROTOCOL_VERSION = "mobilecode.html-render.v1"
ARTIFACT_PATTERN = re.compile(r"^/v1/render/artifacts/([a-f0-9-]+)$")


class WorkerError(Exception):
    """A client-visible, non-secret render failure."""


class HyperFramesWorker:
    def __init__(self, args: argparse.Namespace) -> None:
        self.bind_host = args.host
        self.port = args.port
        self.public_base_url = args.public_base_url.rstrip("/")
        self.token = args.token
        self.source_root = Path(args.source_root).expanduser().resolve()
        self.artifact_root = Path(args.artifact_root).expanduser().resolve()
        self.artifact_root.mkdir(parents=True, exist_ok=True)
        self.hyperframes_bin = args.hyperframes_bin
        self.max_body_bytes = args.max_body_mb * 1024 * 1024
        self.artifacts: dict[str, tuple[Path, float]] = {}
        self.lock = threading.Lock()

    def authorize(self, headers: dict[str, str]) -> bool:
        if not self.token:
            return True
        return headers.get("authorization", "") == f"Bearer {self.token}"

    def render(self, payload: dict[str, Any]) -> dict[str, Any]:
        if payload.get("protocolVersion") != PROTOCOL_VERSION:
            raise WorkerError("unsupported protocolVersion")
        if payload.get("engine") != "hyperframes":
            raise WorkerError("engine must be hyperframes")
        request = payload.get("request")
        if not isinstance(request, dict):
            raise WorkerError("request must be an object")
        if request.get("format") != "mp4":
            raise WorkerError("HyperFrames worker currently produces MP4 only")

        width = self._bounded_int(request.get("width"), 1080, 240, 4096)
        height = self._bounded_int(request.get("height"), 1920, 320, 4096)
        timeout_ms = self._bounded_int(request.get("timeoutMs"), 300_000, 5_000, 900_000)
        project = Path(tempfile.mkdtemp(prefix="mobilecode-hyperframes-", dir=self.artifact_root))
        composition = self._materialize_composition(request, project)
        output = project / "render.mp4"

        command = [
            *self.hyperframes_bin,
            "render",
            "-c",
            str(composition),
            "-o",
            str(output),
        ]
        environment = os.environ.copy()
        environment["MOBILECODE_RENDER_WIDTH"] = str(width)
        environment["MOBILECODE_RENDER_HEIGHT"] = str(height)
        try:
            completed = subprocess.run(
                command,
                cwd=project,
                env=environment,
                capture_output=True,
                text=True,
                timeout=timeout_ms / 1000,
                check=False,
            )
        except FileNotFoundError as error:
            raise WorkerError(
                "HyperFrames command is unavailable; install Node.js 22+, FFmpeg and the hyperframes CLI"
            ) from error
        except subprocess.TimeoutExpired as error:
            raise WorkerError(f"HyperFrames render timed out after {timeout_ms}ms") from error

        if completed.returncode != 0:
            detail = (completed.stderr or completed.stdout).strip()[-4000:]
            raise WorkerError(f"HyperFrames render failed ({completed.returncode}): {detail}")
        if not output.exists() or output.stat().st_size == 0:
            raise WorkerError("HyperFrames completed without a non-empty MP4 artifact")

        artifact_id = str(uuid.uuid4())
        with self.lock:
            self.artifacts[artifact_id] = (output, time.time())
            self._prune_artifacts_locked()
        return {
            "success": True,
            "protocolVersion": PROTOCOL_VERSION,
            "format": "mp4",
            "mimeType": "video/mp4",
            "backend": "hyperframes_cli",
            "artifactUrl": f"{self.public_base_url}/v1/render/artifacts/{artifact_id}",
            "bytes": output.stat().st_size,
            "metadata": {
                "width": width,
                "height": height,
                "source": "mobilecode_html_render_request",
            },
        }

    def artifact(self, artifact_id: str) -> tuple[Path, str] | None:
        with self.lock:
            record = self.artifacts.get(artifact_id)
            if record is None:
                return None
            path, _ = record
            if not path.exists():
                self.artifacts.pop(artifact_id, None)
                return None
            return path, "video/mp4"

    def _materialize_composition(self, request: dict[str, Any], project: Path) -> Path:
        inline_html = request.get("inlineHtml")
        if isinstance(inline_html, str) and inline_html.strip():
            composition = project / "index.html"
            composition.write_text(inline_html, encoding="utf-8")
            return composition

        source_path = request.get("sourcePath")
        if isinstance(source_path, str) and source_path.strip():
            source = Path(source_path).expanduser().resolve()
            try:
                source.relative_to(self.source_root)
            except ValueError as error:
                raise WorkerError("sourcePath is outside the configured worker source root") from error
            if source.is_dir():
                index = source / "index.html"
                if not index.is_file():
                    raise WorkerError(f"sourcePath directory has no index.html: {source.name}")
                composition = project / "composition"
                shutil.copytree(source, composition)
                return composition / "index.html"
            if not source.is_file():
                raise WorkerError(f"sourcePath does not exist: {source.name}")
            composition = project / source.name
            shutil.copy2(source, composition)
            return composition

        source_url = str(request.get("url") or "").strip()
        parsed = urlparse(source_url)
        if parsed.scheme not in {"http", "https"}:
            raise WorkerError("provide inlineHtml, sourcePath, or an http(s) url visible to the worker")
        try:
            response_request = Request(source_url, headers={"User-Agent": "MobileCode-HyperFrames-Worker/1"})
            with urlopen(response_request, timeout=30) as response:
                html = response.read(self.max_body_bytes).decode("utf-8", errors="replace")
        except Exception as error:
            raise WorkerError(f"worker could not fetch source url: {error}") from error
        composition = project / "index.html"
        composition.write_text(html, encoding="utf-8")
        return composition

    def _prune_artifacts_locked(self) -> None:
        cutoff = time.time() - 900
        for artifact_id, (path, created_at) in list(self.artifacts.items()):
            if created_at < cutoff:
                self.artifacts.pop(artifact_id, None)
                shutil.rmtree(path.parent, ignore_errors=True)

    @staticmethod
    def _bounded_int(value: Any, fallback: int, lower: int, upper: int) -> int:
        try:
            return max(lower, min(upper, int(value)))
        except (TypeError, ValueError):
            return fallback


class Handler(BaseHTTPRequestHandler):
    server: "WorkerServer"

    def do_GET(self) -> None:  # noqa: N802
        match = ARTIFACT_PATTERN.match(urlparse(self.path).path)
        if not match:
            self._json(HTTPStatus.NOT_FOUND, {"success": False, "error": "not_found"})
            return
        if not self._authorized():
            self._json(HTTPStatus.UNAUTHORIZED, {"success": False, "error": "auth_failed"})
            return
        artifact = self.server.worker.artifact(match.group(1))
        if artifact is None:
            self._json(HTTPStatus.NOT_FOUND, {"success": False, "error": "artifact_not_found"})
            return
        path, mime_type = artifact
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", mime_type)
        self.send_header("Content-Length", str(path.stat().st_size))
        self.end_headers()
        with path.open("rb") as stream:
            shutil.copyfileobj(stream, self.wfile)

    def do_POST(self) -> None:  # noqa: N802
        if urlparse(self.path).path != "/v1/render/html":
            self._json(HTTPStatus.NOT_FOUND, {"success": False, "error": "not_found"})
            return
        if not self._authorized():
            self._json(HTTPStatus.UNAUTHORIZED, {"success": False, "error": "auth_failed"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > self.server.worker.max_body_bytes:
                raise WorkerError("request body is empty or exceeds the configured limit")
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            if not isinstance(payload, dict):
                raise WorkerError("request body must be a JSON object")
            response = self.server.worker.render(payload)
        except WorkerError as error:
            self._json(HTTPStatus.BAD_REQUEST, {"success": False, "error": str(error)})
            return
        except Exception as error:  # keep server alive and avoid a traceback response
            self._json(HTTPStatus.INTERNAL_SERVER_ERROR, {"success": False, "error": str(error)})
            return
        self._json(HTTPStatus.OK, response)

    def _authorized(self) -> bool:
        return self.server.worker.authorize({key.lower(): value for key, value in self.headers.items()})

    def _json(self, status: HTTPStatus, payload: dict[str, Any]) -> None:
        body = json.dumps(payload, ensure_ascii=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: Any) -> None:
        print(f"[mobilecode-hyperframes] {format % args}", flush=True)


class WorkerServer(ThreadingHTTPServer):
    def __init__(self, address: tuple[str, int], worker: HyperFramesWorker) -> None:
        super().__init__(address, Handler)
        self.worker = worker


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default=os.environ.get("MOBILECODE_HTML_WORKER_HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("MOBILECODE_HTML_WORKER_PORT", "8790")))
    parser.add_argument(
        "--public-base-url",
        default=os.environ.get("MOBILECODE_HTML_WORKER_PUBLIC_BASE_URL", "http://127.0.0.1:8790"),
    )
    parser.add_argument("--token", default=os.environ.get("MOBILECODE_HTML_WORKER_TOKEN", ""))
    parser.add_argument("--source-root", default=os.environ.get("MOBILECODE_HTML_WORKER_SOURCE_ROOT", os.getcwd()))
    parser.add_argument(
        "--artifact-root",
        default=os.environ.get("MOBILECODE_HTML_WORKER_ARTIFACT_ROOT", tempfile.gettempdir()),
    )
    parser.add_argument(
        "--hyperframes-bin",
        nargs="+",
        default=os.environ.get("MOBILECODE_HYPERFRAMES_BIN", "npx --yes hyperframes").split(),
    )
    parser.add_argument("--max-body-mb", type=int, default=8)
    args = parser.parse_args()
    worker = HyperFramesWorker(args)
    server = WorkerServer((worker.bind_host, worker.port), worker)
    print(
        f"MobileCode HyperFrames worker listening on http://{worker.bind_host}:{worker.port} "
        f"(source root: {worker.source_root})",
        flush=True,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
