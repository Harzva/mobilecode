#!/usr/bin/env python3
"""Run a non-counted real-provider strategy pilot.

This P5 runner is intentionally narrow:

- it calls a real OpenAI-compatible provider only when explicitly authorized;
- it writes generated artifacts and redacted model logs;
- it computes a local pilot score from the MobileHarnessBench rubric;
- it always emits strategy_pilot_not_counted output.

It is not a counted benchmark runner.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
REGISTRY_PATH = ROOT / "docs" / "mobile-harness-benchmark" / "strategy-ablation" / "strategy_registry.json"
RUN_KIND = "strategy_pilot_not_counted"
BOUNDARY = "pilot_not_counted"
TASK_ID = "P5-SNAKE-001"

RUBRIC_WEIGHTS = {
    "task_success": 30,
    "verified_success": 30,
    "trace_completeness": 15,
    "recovery": 10,
    "artifact_availability": 10,
    "human_intervention": 5,
}

SNAKE_TASK = """Build a complete standalone single-file HTML5 Snake game.
Hard requirements:
- No external assets, URLs, imports, CDNs, or libraries.
- One HTML file only, with embedded CSS and JS.
- Canvas-based snake board.
- Keyboard controls: Arrow keys and WASD.
- Mobile/touch controls or on-screen direction buttons.
- Score, best score using localStorage, pause/resume, restart, game-over state.
- Responsive layout suitable for phone viewport around 390x844.
- Game loop must actually move the snake and spawn food.
- Return JSON only: {"html":"...", "design_notes":"...", "self_check":["..."]}.
Do not include secrets, private local paths, or raw transcripts."""

STRATEGY_PROMPTS = {
    "react_single_agent": "Use a ReAct single-agent loop internally: reason about the next implementation action, implement it, observe likely runtime behavior, then continue until the game is complete. Favor compact direct code with clear state transitions.",
    "plan_execute_verify_single_agent": "Use Plan-Execute-Verify internally: first form a short implementation plan, execute the game in coherent modules, then verify every hard requirement before final output. Favor organized functions and explicit self-checks.",
    "react_with_final_verifier": "Use ReAct for implementation, then run a strict FinalVerifier pass before final output. Favor robust edge cases such as wall collision, self collision, restart cleanup, and input buffering.",
    "supervisor_handoff_multi_agent": "Simulate Supervisor/Handoff internally: Supervisor assigns CodeAgent, RuntimeAgent, PreviewAgent, VerifierAgent, MemoryAgent, and ReporterAgent roles. Integrate their results into one polished game. Favor role-separated code organization.",
    "swarm_router_multi_agent": "Simulate a SwarmRouter internally: route UI, gameplay, input, and verification concerns to specialized lightweight agents, then merge the strongest proposal. Favor a slightly richer interface while staying single-file.",
    "hierarchical_swarm_multi_agent": "Simulate a HierarchicalSwarm internally: a lead planner decomposes into UI swarm, game-logic swarm, input swarm, and verifier swarm, then reconciles conflicts. Favor layered architecture and resilient responsive controls.",
}

SECRET_PATTERN = re.compile(
    r"(sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|"
    r"xox[baprs]-[A-Za-z0-9-]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{20,})"
)
PRIVATE_PATH_PATTERN = re.compile(r"(/Volumes/[^\\s'\"<>]+|/Users/[^\\s'\"<>]+|[A-Za-z]:\\\\[^\\s'\"<>]+)")


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise SystemExit(f"Expected JSON object: {path}")
    return data


def relative_to_root(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def redact(value: str, api_key: str | None = None) -> str:
    text = value
    if api_key:
        text = text.replace(api_key, "[REDACTED_API_KEY]")
    text = SECRET_PATTERN.sub("[REDACTED_SECRET]", text)
    text = PRIVATE_PATH_PATTERN.sub("[REDACTED_PRIVATE_PATH]", text)
    return text


def extract_api_key(raw: str) -> str | None:
    match = re.search(r"(sk-[A-Za-z0-9_-]{20,})", raw)
    if match:
        return match.group(1)
    for line in reversed(raw.splitlines()):
        stripped = line.strip()
        if stripped and not stripped.lower().startswith(("base_url", "model")):
            if len(stripped) >= 20 and " " not in stripped:
                return stripped
    return None


def read_api_key(args: argparse.Namespace) -> tuple[str, str]:
    env_value = os.environ.get(args.api_key_env, "").strip()
    if env_value:
        return env_value, f"env:{args.api_key_env}"
    access_file = args.access_file or os.environ.get(args.access_file_env, "")
    if access_file:
        path = Path(access_file).expanduser()
        if not path.is_file():
            raise SystemExit("Access file does not exist; path redacted.")
        key = extract_api_key(path.read_text(encoding="utf-8", errors="replace"))
        if not key:
            raise SystemExit("Access file did not contain a parseable API key; content not printed.")
        return key, f"access_file_env:{args.access_file_env if not args.access_file else 'explicit_redacted'}"
    raise SystemExit(
        f"Missing provider authorization. Set {args.api_key_env} or {args.access_file_env}, "
        "or pass --access-file."
    )


def parse_strategy_ids(value: str, registry: dict[str, dict[str, Any]]) -> list[str]:
    if value.strip().lower() == "all":
        return list(registry)
    strategy_ids = [part.strip() for part in value.split(",") if part.strip()]
    unknown = [strategy_id for strategy_id in strategy_ids if strategy_id not in registry]
    if unknown:
        raise SystemExit(f"Unknown strategy id(s): {', '.join(unknown)}")
    return strategy_ids


def chat_completion(
    *,
    base_url: str,
    api_key: str,
    model: str,
    system_prompt: str,
    user_prompt: str,
    temperature: float,
    max_tokens: int,
    timeout: int,
) -> dict[str, Any]:
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        "temperature": temperature,
        "top_p": 0.95,
        "max_tokens": max_tokens,
        "response_format": {"type": "json_object"},
        "stream": False,
    }
    request = urllib.request.Request(
        base_url.rstrip("/") + "/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")[:800]
        raise RuntimeError(f"provider_http_{exc.code}: {body}") from None


def parse_model_json(content: str) -> dict[str, Any] | None:
    try:
        parsed = json.loads(content)
        return parsed if isinstance(parsed, dict) else None
    except json.JSONDecodeError:
        pass
    fence = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", content, flags=re.S)
    if fence:
        try:
            parsed = json.loads(fence.group(1))
            return parsed if isinstance(parsed, dict) else None
        except json.JSONDecodeError:
            return None
    start = content.find("{")
    end = content.rfind("}")
    if start >= 0 and end > start:
        try:
            parsed = json.loads(content[start : end + 1])
            return parsed if isinstance(parsed, dict) else None
        except json.JSONDecodeError:
            return None
    return None


def artifact_checks(html_text: str) -> dict[str, bool]:
    text = html_text.lower()
    return {
        "doctype": "<!doctype html" in text,
        "canvas": "<canvas" in text,
        "keyboard": "keydown" in text and ("arrowup" in text or "keyw" in text or "wasd" in text),
        "touch_or_buttons": any(term in text for term in ("touchstart", "pointerdown", "data-dir", "control")),
        "score": "score" in text,
        "best_score": "localstorage" in text,
        "restart": "restart" in text or "resetgame" in text,
        "game_loop": "requestanimationframe" in text or "setinterval" in text,
        "no_external_urls": not bool(re.search(r"https?://|//cdn|@import", html_text, flags=re.I)),
        "no_secret_pattern": not bool(SECRET_PATTERN.search(html_text)),
        "no_private_path": not bool(PRIVATE_PATH_PATTERN.search(html_text)),
    }


def find_chrome(explicit: str | None) -> str | None:
    candidates = []
    if explicit:
        candidates.append(explicit)
    candidates.extend(
        [
            os.environ.get("CHROME_PATH", ""),
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "google-chrome",
            "chromium",
            "chromium-browser",
        ]
    )
    for candidate in candidates:
        if not candidate:
            continue
        if "/" in candidate and Path(candidate).exists():
            return candidate
        resolved = shutil.which(candidate)
        if resolved:
            return resolved
    return None


def sampled_color_count_with_magick(path: Path) -> int | None:
    magick = shutil.which("magick")
    if not magick:
        return None
    try:
        result = subprocess.run(
            [magick, str(path), "-resize", "39x84!", "-format", "%k", "info:"],
            check=True,
            capture_output=True,
            text=True,
            timeout=10,
        )
        return int(result.stdout.strip())
    except (subprocess.SubprocessError, ValueError):
        return None


def capture_screenshot(
    *,
    chrome: str | None,
    html_path: Path,
    screenshot_path: Path,
    timeout_seconds: int,
) -> dict[str, Any]:
    if not chrome:
        return {
            "requested": True,
            "available": False,
            "reason": "chrome_not_found",
            "screenshot": None,
            "nonblank": None,
        }
    profile = Path(tempfile.mkdtemp(prefix="mobile-harness-p5-chrome-"))
    cmd = [
        chrome,
        "--headless=new",
        "--disable-gpu",
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-extensions",
        "--disable-background-networking",
        "--run-all-compositor-stages-before-draw",
        "--window-size=390,844",
        f"--user-data-dir={profile}",
        f"--screenshot={screenshot_path}",
        f"file://{html_path}",
    ]
    started = time.time()
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    timed_out = False
    try:
        stdout, stderr = process.communicate(timeout=timeout_seconds)
    except subprocess.TimeoutExpired:
        timed_out = True
        process.kill()
        stdout, stderr = process.communicate(timeout=5)
    finally:
        shutil.rmtree(profile, ignore_errors=True)
    elapsed_ms = int((time.time() - started) * 1000)
    image_ok = screenshot_path.exists() and screenshot_path.stat().st_size > 1000
    colors = sampled_color_count_with_magick(screenshot_path) if image_ok else None
    nonblank = image_ok if colors is None else colors > 8
    return {
        "requested": True,
        "available": image_ok,
        "reason": None if image_ok else "screenshot_missing_or_too_small",
        "screenshot": relative_to_root(screenshot_path) if screenshot_path.exists() else None,
        "chrome_exit_code": process.returncode,
        "timed_out_after_screenshot_window": timed_out,
        "elapsed_ms": elapsed_ms,
        "sampled_color_count": colors,
        "nonblank": nonblank,
        "stderr_has_js_exception_text": "Uncaught" in (stderr or "") or "Exception" in (stderr or ""),
        "stdout_tail": redact((stdout or "")[-400:]),
        "stderr_tail": redact((stderr or "")[-400:]),
    }


def score_result(
    *,
    checks: dict[str, bool],
    render_check: dict[str, Any] | None,
    trace_events: list[dict[str, Any]],
    artifact_path: Path,
) -> tuple[dict[str, Any], dict[str, float | int]]:
    required_static = [
        "canvas",
        "keyboard",
        "touch_or_buttons",
        "score",
        "best_score",
        "restart",
        "game_loop",
        "no_external_urls",
        "no_secret_pattern",
        "no_private_path",
    ]
    task_success = 1.0 if all(checks.get(key) for key in required_static) else 0.0
    render_ok = render_check is None or render_check.get("nonblank") is True
    verified_success = 1.0 if task_success and render_ok else 0.0
    trace_completeness = 1.0 if len(trace_events) >= 5 else 0.5
    artifact_availability = 1.0 if artifact_path.is_file() else 0.0
    recovery = 1.0 if checks.get("restart") else 0.0
    human_intervention = 1.0
    score = (
        task_success * RUBRIC_WEIGHTS["task_success"]
        + verified_success * RUBRIC_WEIGHTS["verified_success"]
        + trace_completeness * RUBRIC_WEIGHTS["trace_completeness"]
        + recovery * RUBRIC_WEIGHTS["recovery"]
        + artifact_availability * RUBRIC_WEIGHTS["artifact_availability"]
        + human_intervention * RUBRIC_WEIGHTS["human_intervention"]
    )
    score_breakdown = {
        "score_boundary": "pilot_score_not_counted",
        "total_score": round(score, 2),
        "max_score": 100,
        "task_success_points": round(task_success * RUBRIC_WEIGHTS["task_success"], 2),
        "verified_success_points": round(verified_success * RUBRIC_WEIGHTS["verified_success"], 2),
        "trace_completeness_points": round(trace_completeness * RUBRIC_WEIGHTS["trace_completeness"], 2),
        "recovery_points": round(recovery * RUBRIC_WEIGHTS["recovery"], 2),
        "artifact_availability_points": round(artifact_availability * RUBRIC_WEIGHTS["artifact_availability"], 2),
        "human_intervention_points": round(human_intervention * RUBRIC_WEIGHTS["human_intervention"], 2),
    }
    effect_values = {
        "task_success": task_success,
        "verified_success": verified_success,
        "trace_completeness": trace_completeness,
        "artifact_availability": artifact_availability,
        "recovery_rate": recovery,
        "human_intervention_count": 0,
        "handoff_success_rate": None,
        "memory_reuse_score": None,
        "steps_to_completion": 1,
    }
    return score_breakdown, effect_values


def strategy_user_prompt(strategy_id: str, task: str) -> str:
    return (
        f"STRATEGY_ID: {strategy_id}\n"
        f"STRATEGY_INSTRUCTIONS:\n{STRATEGY_PROMPTS[strategy_id]}\n\n"
        f"TASK:\n{task}"
    )


def build_trace_events(
    *,
    run_id: str,
    strategy_id: str,
    artifact_rel: str | None,
    model_log_rel: str,
    verifier_rel: str,
    status: str,
) -> list[dict[str, Any]]:
    base = f"{strategy_id}/{TASK_ID}"
    return [
        {
            "event_id": "evt_001",
            "type": "plan",
            "role": "StrategyPilotRunner",
            "step_id": "step_001",
            "started_at": utc_now(),
            "ended_at": utc_now(),
            "tool_name": None,
            "evidence_id": f"model_log_{strategy_id}",
            "summary": f"P5 real provider pilot initialized for {base}; non-counted.",
            "artifact_path": model_log_rel,
        },
        {
            "event_id": "evt_002",
            "type": "think",
            "role": "ModelCallback",
            "step_id": "step_001",
            "started_at": utc_now(),
            "ended_at": utc_now(),
            "tool_name": "deepseek_chat_completion",
            "evidence_id": f"model_log_{strategy_id}",
            "summary": "Real provider callback returned a redacted completion.",
        },
        {
            "event_id": "evt_003",
            "type": "act",
            "role": "ArtifactWriter",
            "step_id": "step_001",
            "started_at": utc_now(),
            "ended_at": utc_now(),
            "tool_name": "write_html_artifact",
            "evidence_id": f"artifact_{strategy_id}",
            "summary": "Wrote standalone HTML artifact from provider output.",
            "artifact_path": artifact_rel,
        },
        {
            "event_id": "evt_004",
            "type": "verify",
            "role": "StaticVerifier",
            "step_id": "step_001",
            "started_at": utc_now(),
            "ended_at": utc_now(),
            "tool_name": "static_html_snake_verifier",
            "evidence_id": f"verifier_{strategy_id}",
            "summary": f"Static verifier completed with status {status}.",
            "artifact_path": verifier_rel,
        },
        {
            "event_id": "evt_005",
            "type": "report",
            "role": "ReporterAgent",
            "step_id": None,
            "started_at": utc_now(),
            "ended_at": utc_now(),
            "tool_name": None,
            "evidence_id": None,
            "summary": "P5 real callback pilot result recorded as non-counted.",
        },
    ]


def matrix_writer(path: Path, results: list[dict[str, Any]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "strategy_id",
                "task_id",
                "status",
                "score_boundary",
                "total_score",
                "artifact_path",
                "screenshot_path",
            ],
            lineterminator="\n",
        )
        writer.writeheader()
        for result in results:
            screenshot_paths = result["evidence"].get("screenshot_paths", [])
            artifact_paths = result["evidence"].get("artifact_paths", [])
            writer.writerow(
                {
                    "strategy_id": result["strategy_id"],
                    "task_id": result["task_id"],
                    "status": result["status"],
                    "score_boundary": result["pilot_score"]["score_boundary"],
                    "total_score": result["pilot_score"]["total_score"],
                    "artifact_path": artifact_paths[0] if artifact_paths else "",
                    "screenshot_path": screenshot_paths[0] if screenshot_paths else "",
                }
            )


def write_summary(path: Path, run: dict[str, Any]) -> None:
    lines = [
        "# P5 Real Callback Snake Pilot",
        "",
        f"- run_id: `{run['run_id']}`",
        f"- run_kind: `{run['run_kind']}`",
        "- counts_as_experiment: `false`",
        "- counts_as_strategy_ablation_result: `false`",
        f"- model_provider: `{run['environment']['model_provider']}`",
        f"- model_name: `{run['environment']['model_name']}`",
        "- credential_source: redacted local authorization",
        "",
        "This is a real-provider pilot and a non-counted strategy artifact. It must not be reported as a formal benchmark result.",
        "",
        "## Results",
        "",
        "| Strategy | Status | Score | Static pass | Screenshot nonblank | Artifact |",
        "| --- | --- | ---: | ---: | ---: | --- |",
    ]
    for result in run["results"]:
        render = result.get("render_check") or {}
        lines.append(
            "| `{strategy}` | `{status}` | {score} | `{static}` | `{nonblank}` | `{artifact}` |".format(
                strategy=result["strategy_id"],
                status=result["status"],
                score=result["pilot_score"]["total_score"],
                static=str(result["pilot_verifier"]["static_pass"]).lower(),
                nonblank=str(render.get("nonblank")).lower(),
                artifact=result["evidence"].get("artifact_paths", [""])[0],
            )
        )
    lines.extend(
        [
            "",
            "## Boundary",
            "",
            "- No counted benchmark claim is made.",
            "- Real provider output is used only for this local pilot.",
            "- Model logs are redacted and do not include API keys or access-file bodies.",
            "- Promotion to `strategy_ablation_result` still requires the full evidence gate.",
            "",
        ]
    )
    path.write_text("\n".join(lines), encoding="utf-8")


def run(args: argparse.Namespace) -> int:
    registry_payload = load_json(REGISTRY_PATH)
    registry = {item["strategy_id"]: item for item in registry_payload["strategies"]}
    strategy_ids = parse_strategy_ids(args.strategies, registry)
    selected_strategies = [registry[strategy_id] for strategy_id in strategy_ids]
    api_key, credential_source = read_api_key(args)
    run_id = args.run_id
    output_dir = (ROOT / args.output).resolve() if not Path(args.output).is_absolute() else Path(args.output)
    artifacts_dir = output_dir / "artifacts"
    traces_dir = output_dir / "strategy_traces"
    model_logs_dir = output_dir / "model_logs"
    verifier_dir = output_dir / "verifier_outputs"
    screenshots_dir = output_dir / "screenshots"
    for directory in (output_dir, artifacts_dir, traces_dir, model_logs_dir, verifier_dir, screenshots_dir):
        directory.mkdir(parents=True, exist_ok=True)

    chrome = None if args.skip_screenshots else find_chrome(args.chrome_path)
    system_prompt = (
        "You are a senior mobile-web game engineer. Produce production-quality, "
        "self-contained HTML. Return strict JSON only."
    )
    results: list[dict[str, Any]] = []
    score_rows: list[dict[str, Any]] = []

    for strategy_index, strategy_id in enumerate(strategy_ids):
        started = time.time()
        user_prompt = strategy_user_prompt(strategy_id, args.task)
        status = "failed"
        html_text = ""
        design_notes = ""
        self_check: list[str] = []
        provider_error = None
        response_payload: dict[str, Any] | None = None
        usage: dict[str, Any] = {}
        content = ""
        attempts: list[dict[str, Any]] = []
        for attempt_index in range(args.retries + 1):
            retry_suffix = ""
            if attempt_index:
                retry_suffix = (
                    "\n\nRETRY_INSTRUCTIONS:\n"
                    "Your previous response was empty, truncated, or invalid JSON. "
                    "Return compact valid JSON only. Keep HTML under 12000 characters. "
                    "Do not include markdown fences."
                )
            try:
                response_payload = chat_completion(
                    base_url=args.base_url,
                    api_key=api_key,
                    model=args.model,
                    system_prompt=system_prompt,
                    user_prompt=user_prompt + retry_suffix,
                    temperature=args.temperature if not attempt_index else min(args.temperature, 0.2),
                    max_tokens=args.max_tokens,
                    timeout=args.timeout_seconds,
                )
                usage = response_payload.get("usage", {}) if isinstance(response_payload.get("usage"), dict) else {}
                choice = response_payload.get("choices", [{}])[0]
                content = choice.get("message", {}).get("content", "") if isinstance(choice, dict) else ""
                parsed = parse_model_json(content)
                attempts.append(
                    {
                        "attempt": attempt_index + 1,
                        "status": "parseable" if parsed and isinstance(parsed.get("html"), str) else "unparseable",
                        "usage": usage,
                        "content_sha256": hashlib.sha256(content.encode("utf-8")).hexdigest() if content else None,
                    }
                )
                if parsed and isinstance(parsed.get("html"), str):
                    html_text = parsed["html"]
                    design_notes = str(parsed.get("design_notes", ""))
                    maybe_self_check = parsed.get("self_check", [])
                    self_check = [str(item) for item in maybe_self_check] if isinstance(maybe_self_check, list) else []
                    status = "passed"
                    provider_error = None
                    break
                provider_error = "unparseable_provider_json"
            except Exception as exc:  # noqa: BLE001 - store redacted provider failure.
                provider_error = redact(str(exc), api_key)
                attempts.append(
                    {
                        "attempt": attempt_index + 1,
                        "status": "provider_error",
                        "error": provider_error,
                    }
                )

        html_text = redact(html_text, api_key)
        artifact_path = artifacts_dir / f"snake_{strategy_id}.html"
        if html_text:
            artifact_path.write_text(html_text, encoding="utf-8")

        checks = artifact_checks(html_text) if html_text else {key: False for key in artifact_checks("<html></html>")}
        static_pass = all(checks.values())
        if status == "passed" and not static_pass:
            status = "warning"

        screenshot_path = screenshots_dir / f"snake_{strategy_id}.png"
        render_check = None
        if html_text and not args.skip_screenshots:
            render_check = capture_screenshot(
                chrome=chrome,
                html_path=artifact_path,
                screenshot_path=screenshot_path,
                timeout_seconds=args.screenshot_timeout_seconds,
            )

        wall_ms = int((time.time() - started) * 1000)
        artifact_rel = relative_to_root(artifact_path) if artifact_path.exists() else None
        model_log_path = model_logs_dir / f"{strategy_id}.json"
        verifier_path = verifier_dir / f"{strategy_id}.json"
        trace_events = build_trace_events(
            run_id=run_id,
            strategy_id=strategy_id,
            artifact_rel=artifact_rel,
            model_log_rel=relative_to_root(model_log_path),
            verifier_rel=relative_to_root(verifier_path),
            status=status,
        )
        score_breakdown, effect_metrics = score_result(
            checks=checks,
            render_check=render_check,
            trace_events=trace_events,
            artifact_path=artifact_path,
        )
        verifier_payload = {
            "strategy_id": strategy_id,
            "task_id": TASK_ID,
            "status": status,
            "static_checks": checks,
            "static_pass": static_pass,
            "render_check": render_check,
            "score": score_breakdown,
            "provider_error": provider_error,
            "counts_as_experiment": False,
            "counts_as_strategy_ablation_result": False,
        }
        verifier_path.write_text(json.dumps(verifier_payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        model_log = {
            "strategy_id": strategy_id,
            "task_id": TASK_ID,
            "provider": args.provider,
            "model": args.model,
            "credential_source": credential_source,
            "prompt_sha256": hashlib.sha256(user_prompt.encode("utf-8")).hexdigest(),
            "completion_sha256": hashlib.sha256(content.encode("utf-8")).hexdigest() if content else None,
            "usage": usage,
            "attempts": attempts,
            "status": "completed" if content else "failed",
            "provider_error": provider_error,
            "redaction": "api keys, secret patterns, and access-file bodies are not stored",
            "content_preview": redact(content[:800], api_key),
        }
        model_log_path.write_text(json.dumps(model_log, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        trace_path = traces_dir / f"{strategy_id}_{TASK_ID}.json"
        strategy_trace = {
            "trace_id": f"strace_{run_id}_{strategy_id}_{TASK_ID}_p5",
            "strategy_id": strategy_id,
            "trace_status": BOUNDARY,
            "events": trace_events,
            "handoff_count": 1 if registry[strategy_id]["strategy_family"] in {"multi_agent_handoff", "multi_agent_swarm"} else 0,
            "planning_revisions": 0,
            "verification_failures_recovered": 0,
            "failure_kind": None if status == "passed" else f"p5_real_pilot_{status}",
        }
        trace_path.write_text(json.dumps(strategy_trace, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

        prompt_tokens = int(usage.get("prompt_tokens") or 0)
        completion_tokens = int(usage.get("completion_tokens") or 0)
        tool_io = len(html_text.encode("utf-8")) if html_text else 0
        estimated_tool_tokens = int(tool_io / 4)
        token_total = int(usage.get("total_tokens") or (prompt_tokens + completion_tokens + estimated_tool_tokens))
        evidence = {
            "boundary": BOUNDARY,
            "artifact_paths": [artifact_rel] if artifact_rel else [],
            "trace_paths": [relative_to_root(trace_path)],
            "screenshot_paths": [render_check["screenshot"]] if render_check and render_check.get("screenshot") else [],
            "logs": [
                "P5 real provider callback pilot executed.",
                "Run is non-counted and must not be cited as a formal benchmark.",
                "Model log is redacted and excludes credential material.",
            ],
            "verifier_outputs": [relative_to_root(verifier_path)],
            "transcript_paths": [],
            "human_intervention_notes": [],
        }
        result = {
            "strategy_id": strategy_id,
            "strategy_family": registry[strategy_id]["strategy_family"],
            "task_id": TASK_ID,
            "task_category": "code_edit",
            "status": status,
            "strategy_trace": strategy_trace,
            "time_metrics": {
                "planning_ms": 0,
                "execution_ms": wall_ms,
                "verification_ms": render_check.get("elapsed_ms", 0) if render_check else 0,
                "reporting_ms": 0,
                "wall_ms": wall_ms,
            },
            "token_metrics": {
                "prompt_tokens": prompt_tokens,
                "completion_tokens": completion_tokens,
                "estimated_tool_io_tokens": estimated_tool_tokens,
                "total_tokens": token_total,
                "estimated_cost_usd": None,
                "tokens_per_verified_success": token_total if effect_metrics["verified_success"] == 1.0 else None,
            },
            "effect_metrics": effect_metrics,
            "evidence": evidence,
            "pilot_verifier": {
                "static_pass": static_pass,
                "checks": checks,
                "verifier_output": relative_to_root(verifier_path),
            },
            "pilot_score": score_breakdown,
            "render_check": render_check,
            "counts_as_strategy_ablation_result": False,
        }
        results.append(result)
        score_rows.append(
            {
                "strategy_id": strategy_id,
                "status": status,
                "total_score": score_breakdown["total_score"],
                "static_pass": static_pass,
                "render_nonblank": render_check.get("nonblank") if render_check else None,
                "artifact_path": artifact_rel,
                "sha256": hashlib.sha256(html_text.encode("utf-8")).hexdigest() if html_text else None,
                "bytes": len(html_text.encode("utf-8")) if html_text else 0,
                "provider_error": provider_error,
            }
        )
        print(
            f"{strategy_index + 1}/{len(strategy_ids)} {strategy_id}: "
            f"status={status} score={score_breakdown['total_score']} "
            f"static_pass={static_pass} artifact={artifact_rel}"
        )

    summary = {
        "total": len(results),
        "strategies": len(strategy_ids),
        "tasks_per_strategy": 1,
        "passed": sum(1 for item in results if item["status"] == "passed"),
        "warning": sum(1 for item in results if item["status"] == "warning"),
        "failed": sum(1 for item in results if item["status"] == "failed"),
        "blocked": sum(1 for item in results if item["status"] == "blocked"),
        "average_pilot_score_not_counted": round(
            sum(item["pilot_score"]["total_score"] for item in results) / len(results), 2
        )
        if results
        else None,
    }
    run_payload = {
        "benchmark": "MobileHarnessBench",
        "counts_as_experiment": False,
        "counts_as_strategy_ablation_result": False,
        "run_id": run_id,
        "run_kind": RUN_KIND,
        "schema_version": "0.1.0-p5-real-pilot",
        "strategy_family": "mixed_strategy_ablation",
        "environment": {
            "execution_tier": "P5-real-callback-pilot",
            "mode": RUN_KIND,
            "model_provider": args.provider,
            "model_name": args.model,
            "runtime_backend": "real_provider_local_artifact_verifier",
            "credential_source": "redacted_local_authorization",
        },
        "evidence_boundary": (
            "pilot_not_counted: P5 used real provider callbacks and local artifact/verifier evidence, "
            "but this run is not a formal benchmark result and must not be counted."
        ),
        "model": {
            "provider": args.provider,
            "name": args.model,
            "notes": "Real provider callback; credentials redacted.",
            "status": "real_callback_pilot",
        },
        "strategies": [
            {
                "strategy_id": item["strategy_id"],
                "strategy_family": item["strategy_family"],
            }
            for item in selected_strategies
        ],
        "task_subset": {
            "task_set": "p5-real-snake-pilot",
            "task_count": 1,
            "tasks": [
                {
                    "id": TASK_ID,
                    "category": "code_edit",
                    "description": "Standalone HTML Snake game generated under strategy-specific prompting.",
                }
            ],
        },
        "summary": summary,
        "results": results,
        "score_boundary": "pilot_score_not_counted",
        "created_at": utc_now(),
    }
    (output_dir / "run.json").write_text(json.dumps(run_payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (output_dir / "rubric_scores.json").write_text(json.dumps(score_rows, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    matrix_writer(output_dir / "task_strategy_matrix.csv", results)
    write_summary(output_dir / "summary.md", run_payload)
    print(f"RUN_JSON={relative_to_root(output_dir / 'run.json')}")
    print(f"SUMMARY={relative_to_root(output_dir / 'summary.md')}")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--provider", default="deepseek")
    parser.add_argument("--base-url", default="https://api.deepseek.com")
    parser.add_argument("--model", default="deepseek-v4-flash")
    parser.add_argument("--api-key-env", default="DEEPSEEK_API_KEY")
    parser.add_argument("--access-file-env", default="DEEPSEEK_API_ACCESS_FILE")
    parser.add_argument("--access-file", default="")
    parser.add_argument("--strategies", default="all")
    parser.add_argument("--task", default=SNAKE_TASK)
    parser.add_argument("--run-id", default="p5-real-snake-pilot")
    parser.add_argument(
        "--output",
        default="docs/mobile-harness-benchmark/strategy-ablation/runs/p5-real-snake-pilot",
    )
    parser.add_argument("--temperature", type=float, default=0.35)
    parser.add_argument("--max-tokens", type=int, default=8192)
    parser.add_argument("--retries", type=int, default=1)
    parser.add_argument("--timeout-seconds", type=int, default=180)
    parser.add_argument("--skip-screenshots", action="store_true")
    parser.add_argument("--chrome-path", default="")
    parser.add_argument("--screenshot-timeout-seconds", type=int, default=8)
    return parser.parse_args()


if __name__ == "__main__":
    raise SystemExit(run(parse_args()))
