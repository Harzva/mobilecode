#!/usr/bin/env python3
"""Serve sanitized Lark relay evidence for MobileCode Lark API Lab."""

from __future__ import annotations

import argparse
import json
import os
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

from mock_relay_runner import DEFAULT_OUTPUT_DIR


DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8787
FEED_SCHEMA = "mobilecode.lark_relay.evidence_feed.v1"
SENSITIVE_PATH_KEYS = {
    "chat_id",
    "sender_id",
    "message_id",
    "open_id",
    "openId",
    "user_id",
    "union_id",
    "idempotency_key",
}
COMMAND_REDACT_NEXT_FLAGS = {
    "--chat-id": "redacted_chat_id",
    "--idempotency-key": "redacted_idempotency_key",
    "--message-id": "redacted_message_id",
    "--open-id": "redacted_open_id",
    "--text": "redacted_message_text",
    "--user-id": "redacted_user_id",
}


def _now_iso8601() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _compact(value: Any, limit: int = 120) -> str:
    text = str(value).strip().replace("\n", " ")
    if len(text) <= limit:
        return text
    return f"{text[:limit]}..."


def _redacted(value: Any, label: str = "redacted") -> str:
    if value is None or str(value).strip() == "":
        return ""
    return f"<{label}>"


def _safe_message_text(value: Any) -> str:
    text = str(value or "").strip()
    if not text:
        return ""
    if text.startswith("/mc "):
        return "/mc <redacted_user_prompt>"
    return "<redacted_user_message>"


def _safe_reply_text(value: Any) -> str:
    text = str(value or "").strip()
    if not text:
        return ""
    return "<redacted_model_reply>"


def _sanitize_command(value: list[Any]) -> list[str]:
    sanitized: list[str] = []
    redact_next = ""
    for item in value[:30]:
        text = str(item)
        if redact_next:
            sanitized.append(f"<{redact_next}>")
            redact_next = ""
            continue
        sanitized.append(text)
        redact_next = COMMAND_REDACT_NEXT_FLAGS.get(text, "")
    return sanitized


def _sanitize_scalar(key: str, value: Any) -> Any:
    lower = key.lower()
    if lower in {"document_url", "documenturl", "document_reference", "documentreference"}:
        return _redacted(value, "redacted_docx_url")
    if key in SENSITIVE_PATH_KEYS or lower.endswith("_id") or lower.endswith("id"):
        if key in {"event_id", "request_id", "dry_run_id"}:
            return _compact(value, 96)
        return _redacted(value, f"redacted_{key}")
    if key == "token_mode":
        return _compact(value, 96)
    if "token" in lower or "secret" in lower or "authorization" in lower or "cookie" in lower:
        return _redacted(value, "redacted_secret")
    if key in {"message_text", "content", "text"}:
        return _safe_message_text(value)
    if key in {"reply_text", "stdout"}:
        return _safe_reply_text(value)
    if key in {"stderr", "stdout"}:
        return _compact(value, 240)
    return value


def sanitize_value(value: Any, key: str = "") -> Any:
    if isinstance(value, dict):
        return {str(item_key): sanitize_value(item_value, str(item_key)) for item_key, item_value in value.items()}
    if isinstance(value, list):
        if key == "command":
            return _sanitize_command(value)
        return [sanitize_value(item, key) for item in value[:20]]
    if isinstance(value, (str, int, float, bool)) or value is None:
        return _sanitize_scalar(key, value)
    return _compact(value)


def sanitize_evidence(record: dict[str, Any], source_path: Path) -> dict[str, Any]:
    sanitized = sanitize_value(record)
    if not isinstance(sanitized, dict):
        sanitized = {}
    sanitized["raw_json_preview_status"] = (
        "Sanitized relay evidence loaded from local feed; chat IDs, open IDs, message IDs, tokens, and content are redacted."
    )
    sanitized["raw_json_path"] = source_path.name
    return sanitized


def load_feed(evidence_dir: Path, limit: int) -> dict[str, Any]:
    files = sorted(
        (
            path
            for path in evidence_dir.glob("*.json")
            if not path.name.endswith(".summary.json")
        ),
        key=lambda path: path.stat().st_mtime if path.exists() else 0,
        reverse=True,
    )
    items = []
    for path in files[: max(0, limit)]:
        try:
            decoded = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            items.append(
                {
                    "tool": "lark_relay.evidence_feed",
                    "failure_kind": "evidence_json_decode_error",
                    "next_action": "inspect_or_remove_invalid_evidence_file",
                    "raw_json_path": path.name,
                    "raw_json_preview_status": f"Failed to parse sanitized source: {_compact(exc)}",
                }
            )
            continue
        if isinstance(decoded, dict):
            items.append(sanitize_evidence(decoded, path))
    return {
        "schema": FEED_SCHEMA,
        "generated_at": _now_iso8601(),
        "source": "tools/lark_relay/evidence",
        "count": len(items),
        "items": items,
    }


class EvidenceFeedHandler(BaseHTTPRequestHandler):
    evidence_dir: Path = DEFAULT_OUTPUT_DIR
    default_limit: int = 20
    bearer_token: str = ""

    def log_message(self, format: str, *args: Any) -> None:
        return

    def _send_json(self, status: int, payload: dict[str, Any]) -> None:
        body = json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self) -> bool:
        if not self.bearer_token:
            return True
        expected = f"Bearer {self.bearer_token}"
        return self.headers.get("Authorization", "") == expected

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self._send_json(
                200,
                {
                    "ok": True,
                    "service": "mobilecode-lark-relay-evidence-feed",
                    "generated_at": _now_iso8601(),
                    "auth_required": bool(self.bearer_token),
                },
            )
            return
        if parsed.path != "/lark/evidence":
            self._send_json(404, {"ok": False, "error": "not_found"})
            return
        if not self._authorized():
            self._send_json(401, {"ok": False, "error": "unauthorized"})
            return

        query = parse_qs(parsed.query)
        raw_limit = query.get("limit", [str(self.default_limit)])[0]
        try:
            limit = int(raw_limit)
        except ValueError:
            limit = self.default_limit
        limit = max(1, min(limit, 100))
        self._send_json(200, load_feed(self.evidence_dir, limit))


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Serve a sanitized MobileCode Lark relay evidence feed."
    )
    parser.add_argument("--evidence-dir", default=str(DEFAULT_OUTPUT_DIR))
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--limit", type=int, default=20)
    parser.add_argument(
        "--bearer-token-env",
        default="MOBILECODE_LARK_EVIDENCE_FEED_TOKEN",
        help="Read an optional bearer token from this environment variable.",
    )
    parser.add_argument(
        "--print-once",
        action="store_true",
        help="Print the sanitized feed JSON and exit instead of serving HTTP.",
    )
    return parser


def main() -> int:
    parser = _build_parser()
    args = parser.parse_args()
    evidence_dir = Path(args.evidence_dir)
    if args.print_once:
        print(json.dumps(load_feed(evidence_dir, args.limit), ensure_ascii=False, indent=2))
        return 0

    EvidenceFeedHandler.evidence_dir = evidence_dir
    EvidenceFeedHandler.default_limit = args.limit
    EvidenceFeedHandler.bearer_token = os.getenv(args.bearer_token_env, "").strip()
    server = ThreadingHTTPServer((args.host, args.port), EvidenceFeedHandler)
    print(f"serving sanitized Lark relay evidence feed at http://{args.host}:{args.port}/lark/evidence")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("stopping evidence feed server")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
