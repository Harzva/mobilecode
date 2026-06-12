#!/usr/bin/env python3
"""Invoke an OpenAI-compatible chat completions endpoint for Lark relay agent mode."""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path
from typing import Any
from urllib import error, request


DEFAULT_API_URL = "https://api.deepseek.com/chat/completions"
DEFAULT_MODEL = "deepseek-chat"


def _normalize_api_key(raw_value: str, *, allow_generic_candidate: bool = False) -> str:
    value = raw_value.strip()
    if not value:
        return ""

    bearer_match = re.fullmatch(r"Bearer\s+(.+)", value, flags=re.IGNORECASE)
    if bearer_match:
        value = bearer_match.group(1).strip()

    if _is_header_safe_token(value):
        return value

    prefixed = re.findall(r"sk-[A-Za-z0-9][A-Za-z0-9._~-]{8,}", value)
    if len(prefixed) == 1:
        return prefixed[0]
    if len(prefixed) > 1:
        print("error: multiple sk-style API key candidates found", file=sys.stderr)
        raise SystemExit(2)

    if not allow_generic_candidate:
        return ""

    candidates = re.findall(r"(?<![A-Za-z0-9._~+/=-])[A-Za-z0-9][A-Za-z0-9._~+/=-]{31,}(?![A-Za-z0-9._~+/=-])", value)
    candidates = [candidate for candidate in candidates if _is_header_safe_token(candidate)]
    unique_candidates = sorted(set(candidates))
    if len(unique_candidates) == 1:
        return unique_candidates[0]
    if len(unique_candidates) > 1:
        print("error: multiple API key candidates found", file=sys.stderr)
        raise SystemExit(2)

    return ""


def _is_header_safe_token(value: str) -> bool:
    return bool(value) and value.isascii() and not any(ch.isspace() for ch in value)


def _read_api_key() -> str:
    raw_value = os.environ.get("MOBILECODE_AGENT_API_KEY", "")
    key_file = os.environ.get("MOBILECODE_AGENT_API_KEY_FILE", "").strip()
    allow_generic_candidate = os.environ.get(
        "MOBILECODE_AGENT_ALLOW_GENERIC_API_KEY", ""
    ).strip().lower() in {"1", "true", "yes"}

    if not raw_value and key_file:
        try:
            raw_value = Path(key_file).read_text(encoding="utf-8", errors="ignore")
        except OSError as exc:
            print(f"error: cannot read MOBILECODE_AGENT_API_KEY_FILE: {exc}", file=sys.stderr)
            raise SystemExit(2)

    api_key = _normalize_api_key(
        raw_value,
        allow_generic_candidate=allow_generic_candidate,
    )
    if not api_key:
        source = "MOBILECODE_AGENT_API_KEY_FILE" if key_file else "MOBILECODE_AGENT_API_KEY"
        print(f"error: missing or invalid API key in {source}", file=sys.stderr)
        raise SystemExit(2)
    return api_key


def _read_stdin() -> str:
    text = sys.stdin.read()
    if not text.strip():
        print("error: no input message received on stdin", file=sys.stderr)
        raise SystemExit(3)
    return text.strip()


def _json_error_body(body: bytes, api_key: str) -> str:
    try:
        text = body.decode("utf-8").strip()
    except UnicodeDecodeError:
        return "<non-text response body>"
    if api_key:
        text = text.replace(api_key, "<redacted>")
    return text


def _extract_reply(response: dict[str, Any]) -> str:
    choices = response.get("choices")
    if not isinstance(choices, list) or not choices:
        raise ValueError("invalid OpenAI response: choices missing")

    first_choice = choices[0]
    if not isinstance(first_choice, dict):
        raise ValueError("invalid OpenAI response: choice entry malformed")

    message = first_choice.get("message")
    if isinstance(message, dict):
        content = message.get("content")
        if isinstance(content, str) and content.strip():
            return content.strip()

    text = first_choice.get("text")
    if isinstance(text, str) and text.strip():
        return text.strip()

    raise ValueError("invalid OpenAI response: empty or unsupported content")


def _build_messages(message_text: str, system_prompt: str) -> list[dict[str, str]]:
    messages: list[dict[str, str]] = []
    if system_prompt.strip():
        messages.append({"role": "system", "content": system_prompt.strip()})
    messages.append({"role": "user", "content": message_text})
    return messages


def main() -> int:
    api_url = os.getenv("MOBILECODE_AGENT_API_URL", DEFAULT_API_URL).strip() or DEFAULT_API_URL
    api_key = _read_api_key()
    model = os.getenv("MOBILECODE_AGENT_MODEL", DEFAULT_MODEL).strip() or DEFAULT_MODEL
    system_prompt = os.getenv("MOBILECODE_AGENT_SYSTEM_PROMPT", "")
    user_message = _read_stdin()

    payload = {
        "model": model,
        "messages": _build_messages(user_message, system_prompt),
        "stream": False,
    }

    request_data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = request.Request(
        api_url,
        data=request_data,
        method="POST",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
    )

    try:
        with request.urlopen(req, timeout=30) as response:
            raw = response.read().decode("utf-8")
    except error.HTTPError as exc:
        body = _json_error_body(exc.read(), api_key)
        status = exc.code
        print(f"error: API request failed with status {status}: {body}", file=sys.stderr)
        return 4
    except error.URLError as exc:
        print(f"error: API request failed: {exc}", file=sys.stderr)
        return 4
    except UnicodeEncodeError:
        print("error: API key contains characters that cannot be sent in an HTTP header", file=sys.stderr)
        return 4
    except TimeoutError as exc:
        print(f"error: API request timeout: {exc}", file=sys.stderr)
        return 4

    try:
        response_json = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"error: invalid JSON response: {exc}", file=sys.stderr)
        return 5

    try:
        reply = _extract_reply(response_json)
    except (KeyError, TypeError, ValueError, IndexError) as exc:
        print(f"error: cannot parse model reply: {exc}", file=sys.stderr)
        return 6

    print(reply)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
