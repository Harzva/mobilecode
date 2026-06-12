#!/usr/bin/env python3
"""Invoke an OpenAI-compatible chat completions endpoint for Lark relay agent mode."""

from __future__ import annotations

import json
import os
import sys
from typing import Any
from urllib import error, request


DEFAULT_API_URL = "https://api.deepseek.com/chat/completions"
DEFAULT_MODEL = "deepseek-chat"


def _env_required(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        print(f"error: missing required env var {name}", file=sys.stderr)
        raise SystemExit(2)
    return value


def _read_stdin() -> str:
    text = sys.stdin.read()
    if not text.strip():
        print("error: no input message received on stdin", file=sys.stderr)
        raise SystemExit(3)
    return text.strip()


def _json_error_body(body: bytes) -> str:
    try:
        return body.decode("utf-8").strip()
    except UnicodeDecodeError:
        return "<non-text response body>"


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
    api_key = _env_required("MOBILECODE_AGENT_API_KEY")
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
        body = _json_error_body(exc.read())
        status = exc.code
        print(f"error: API request failed with status {status}: {body}", file=sys.stderr)
        return 4
    except error.URLError as exc:
        print(f"error: API request failed: {exc}", file=sys.stderr)
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
