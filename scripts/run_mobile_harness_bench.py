#!/usr/bin/env python3
"""Run deterministic MobileHarnessBench offline dry runs.

The runner is intentionally stdlib-only. It verifies the benchmark protocol and
offline fixtures without reading credentials, contacting GitHub, or depending on
device state.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from datetime import datetime, timezone
from html import escape
from html.parser import HTMLParser
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
BENCH_ROOT = ROOT / "docs" / "mobile-harness-benchmark"
TASKS_PATH = BENCH_ROOT / "tasks" / "v0-seed-tasks.json"
V2_TASK_BANK_PATH = BENCH_ROOT / "tasks" / "v2-task-bank.json"
REPRESENTATIVE_TASK_SET_PATH = BENCH_ROOT / "tasks" / "representative-v0.json"
SMOKE_V2_TASK_SET_PATH = BENCH_ROOT / "tasks" / "smoke-v2.json"
RUNS_ROOT = BENCH_ROOT / "runs"
TASK_SET_PATHS = {
    "representative-v0": REPRESENTATIVE_TASK_SET_PATH,
    "smoke-v2": SMOKE_V2_TASK_SET_PATH,
}

STATUS_ORDER = {"failed": 0, "blocked": 1, "warning": 2, "passed": 3}
PUBLIC_BLOCKLIST = [
    re.compile(r"media_id", re.IGNORECASE),
    re.compile(r"access_token", re.IGNORECASE),
    re.compile(r"wechat_(appid|secret)", re.IGNORECASE),
    re.compile(r"\bopenid\b", re.IGNORECASE),
    re.compile(r"\b[a-zA-Z]:\\"),
    re.compile(r"sk-[A-Za-z0-9_-]{12,}"),
]


class HtmlSummaryParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.title_parts: list[str] = []
        self.body_parts: list[str] = []
        self.tags: Counter[str] = Counter()
        self._in_title = False
        self._in_body = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.tags[tag.lower()] += 1
        if tag.lower() == "title":
            self._in_title = True
        if tag.lower() == "body":
            self._in_body = True

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() == "title":
            self._in_title = False
        if tag.lower() == "body":
            self._in_body = False

    def handle_data(self, data: str) -> None:
        text = " ".join(data.split())
        if not text:
            return
        if self._in_title:
            self.title_parts.append(text)
        if self._in_body:
            self.body_parts.append(text)

    @property
    def title(self) -> str:
        return " ".join(self.title_parts).strip()

    @property
    def body_text(self) -> str:
        return " ".join(self.body_parts).strip()


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def repo_rel(path: Path) -> str:
    return path.resolve().relative_to(ROOT.resolve()).as_posix()


def bench_rel(path: Path) -> str:
    return path.resolve().relative_to(BENCH_ROOT.resolve()).as_posix()


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def load_task_bank(path: Path) -> dict[str, dict[str, Any]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    tasks = payload.get("tasks")
    if not isinstance(tasks, list):
        fail("task payload must contain a tasks list")
    return {task["id"]: task for task in tasks}


def load_tasks(task_set: str) -> dict[str, dict[str, Any]]:
    if task_set == "representative-v0":
        return load_task_bank(TASKS_PATH)
    if task_set == "smoke-v2":
        return load_task_bank(V2_TASK_BANK_PATH)
    fail(f"unsupported task set: {task_set}")


def load_task_set(task_set: str) -> list[str]:
    task_set_path = TASK_SET_PATHS.get(task_set)
    if task_set_path is None:
        fail(f"unsupported task set: {task_set}")
    payload = json.loads(task_set_path.read_text(encoding="utf-8"))
    tasks = payload.get("tasks")
    if not isinstance(tasks, list) or not tasks:
        fail(f"{task_set_path.relative_to(ROOT)} must contain a non-empty tasks list")
    return [task["id"] for task in tasks]


def check(name: str, status: str, message: str, **details: Any) -> dict[str, Any]:
    item: dict[str, Any] = {"name": name, "status": status, "message": message}
    if details:
        item["details"] = details
    return item


def summarize_checks(checks: list[dict[str, Any]]) -> str:
    if any(item["status"] == "failed" for item in checks):
        return "failed"
    if any(item["status"] == "blocked" for item in checks):
        return "blocked"
    if any(item["status"] == "warning" for item in checks):
        return "warning"
    return "passed"


def score_for_status(status: str) -> int:
    return {"passed": 95, "warning": 75, "blocked": 0, "failed": 0}[status]


def parse_html(path: Path) -> dict[str, Any]:
    parser = HtmlSummaryParser()
    parser.feed(path.read_text(encoding="utf-8"))
    return {
        "title": parser.title,
        "body_text_length": len(parser.body_text),
        "heading_count": parser.tags["h1"] + parser.tags["h2"] + parser.tags["h3"],
        "has_viewport_meta": "viewport" in path.read_text(encoding="utf-8").lower(),
    }


def remove_json_trailing_commas(raw: str) -> str:
    return re.sub(r",(\s*[}\]])", r"\1", raw)


def preview_route(task_id: str, relative_path: str) -> str:
    return f"mobilecode-preview://bench/{task_id}/{relative_path}"


def task_fixture(task: dict[str, Any]) -> Path:
    fixture = BENCH_ROOT / task["input_fixture"]["path"]
    if not fixture.exists():
        fail(f"{task['id']} fixture does not exist: {task['input_fixture']['path']}")
    return fixture


def task_scope(task: dict[str, Any]) -> dict[str, Any]:
    scenario = task.get("scenario", {})
    mobile = task.get("mobile_requirements", {})
    return {
        "result_scope": "t0_offline_fixture_only",
        "counts_as_mobile_experiment": False,
        "mobile_profile": scenario.get("mobile_profile"),
        "os_target": scenario.get("os_target"),
        "input_surface": scenario.get("input_surface"),
        "requires_real_device": mobile.get("requires_real_device"),
        "device_evidence": "not_collected_in_t0",
    }


def write_text_artifact(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="")


def verify_v2_file_intake(task: dict[str, Any], run_dir: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    fixture = task_fixture(task)
    fixture_rel = repo_rel(fixture)
    fixture_kind = task["input_fixture"]["kind"]
    evidence_doc: dict[str, Any] = {
        "incoming_path": fixture_rel,
        "detected_type": fixture_kind,
        "fixture_bytes": fixture.stat().st_size,
        **task_scope(task),
    }
    checks = [
        check("fixture_exists", "passed", "incoming file fixture exists", path=fixture_rel),
        check("detected_type", "passed", "fixture kind is recorded", detected_type=fixture_kind),
    ]
    preview_urls: list[str] = []
    if fixture.suffix.lower() in {".html", ".htm"}:
        html = parse_html(fixture)
        route = preview_route(task["id"], bench_rel(fixture))
        preview_urls.append(route)
        evidence_doc["preview_url"] = route
        evidence_doc["html_summary"] = html
        checks.append(
            check(
                "html_preview",
                "passed" if html["title"] and html["body_text_length"] >= 40 else "failed",
                "HTML fixture has title and readable body text",
                title=html["title"],
                body_text_length=html["body_text_length"],
            )
        )
    artifact_path = run_dir / "artifacts" / task["id"] / "detected-file.json"
    write_json(artifact_path, evidence_doc)
    checks.append(check("artifact_exists", "passed", "detected-file report exists", path=repo_rel(artifact_path)))
    result = make_result(
        task,
        "passed",
        checks,
        {
            "artifact_paths": [repo_rel(artifact_path)],
            "preview_urls": preview_urls,
            "logs": ["external_file_open", "detect_file_type", "record_t0_fixture_result"],
            **task_scope(task),
        },
        "T0 fixture run verifies file-intake metadata and previewability; no real share-sheet evidence is collected.",
    )
    events = task_events(task["id"], fixture_rel, ["external_file_open", "detect_file_type", "report_result"], result)
    return result, events


def verify_v2_code_edit(task: dict[str, Any], run_dir: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    fixture = task_fixture(task)
    prompt = fixture.read_text(encoding="utf-8").strip()
    generated_html = (
        "<!doctype html>\n"
        "<html><head><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
        f"<title>{escape(task['id'])} benchmark dashboard</title></head>"
        "<body>"
        f"<h1>{escape(task['title'])}</h1>"
        f"<p>{escape(prompt)}</p>"
        "<section><h2>Status</h2><p>T0 fixture artifact generated by deterministic runner.</p></section>"
        "</body></html>\n"
    )
    artifact_path = run_dir / "artifacts" / task["id"] / "index.html"
    write_text_artifact(artifact_path, generated_html)
    html = parse_html(artifact_path)
    route = preview_route(task["id"], repo_rel(artifact_path))
    checks = [
        check("prompt_present", "passed" if prompt else "failed", "prompt fixture is non-empty"),
        check("artifact_exists", "passed" if artifact_path.exists() else "failed", "generated HTML artifact exists"),
        check(
            "html_preview",
            "passed" if html["title"] and html["body_text_length"] >= 40 else "failed",
            "generated HTML has previewable content",
            title=html["title"],
            body_text_length=html["body_text_length"],
        ),
        check("preview_route", "passed", "synthetic preview route is recorded", preview_url=route),
    ]
    result = make_result(
        task,
        "passed",
        checks,
        {
            "artifact_paths": [repo_rel(artifact_path)],
            "preview_urls": [route],
            "logs": ["read_prompt", "write_file", "readback_action", "html_preview", "record_t0_fixture_result"],
            **task_scope(task),
        },
        "T0 fixture run generates and reads back a single-file HTML artifact; no mobile editor UI evidence is collected.",
    )
    events = task_events(task["id"], repo_rel(fixture), ["read_prompt", "write_file", "readback_action", "html_preview"], result)
    return result, events


def verify_v2_preview(task: dict[str, Any], run_dir: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    fixture = task_fixture(task)
    html = parse_html(fixture)
    route = preview_route(task["id"], bench_rel(fixture))
    snapshot = {
        "viewport": task.get("scenario", {}).get("viewport", "unknown"),
        "title": html["title"],
        "dom_text_length": html["body_text_length"],
        "heading_count": html["heading_count"],
        "has_viewport_meta": html["has_viewport_meta"],
        "route": route,
        **task_scope(task),
    }
    artifact_path = run_dir / "artifacts" / task["id"] / "snapshot-summary.json"
    write_json(artifact_path, snapshot)
    checks = [
        check("fixture_exists", "passed", "preview fixture exists", path=repo_rel(fixture)),
        check(
            "snapshot_text",
            "passed" if html["body_text_length"] >= 40 else "failed",
            "snapshot has readable text",
            dom_text_length=html["body_text_length"],
        ),
        check("preview_url", "passed", "synthetic preview route is recorded", preview_url=route),
        check("artifact_exists", "passed", "snapshot summary exists", path=repo_rel(artifact_path)),
    ]
    result = make_result(
        task,
        "passed",
        checks,
        {
            "artifact_paths": [repo_rel(artifact_path)],
            "preview_urls": [route],
            "logs": ["preview_html", "snapshot_summary", "record_t0_fixture_result"],
            "snapshot_metadata": snapshot,
            **task_scope(task),
        },
        "T0 fixture run verifies preview metadata and snapshot summary; no WebView screenshot is collected.",
    )
    events = task_events(task["id"], repo_rel(fixture), ["preview_html", "snapshot_summary", "report_result"], result)
    return result, events


def verify_v2_github_delivery(task: dict[str, Any], run_dir: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    fixture = task_fixture(task)
    payload = json.loads(fixture.read_text(encoding="utf-8"))
    required = ["owner", "repo", "branch", "path", "operation"]
    missing = [key for key in required if not payload.get(key)]
    artifact_path = run_dir / "artifacts" / task["id"] / "github-delivery-blocked.json"
    report = {
        "repo": f"{payload.get('owner')}/{payload.get('repo')}",
        "branch": payload.get("branch"),
        "path": payload.get("path"),
        "operation": payload.get("operation"),
        "failure_kind": "github_auth_blocked",
        "recovery_suggestion": "Run this task in a GitHub sandbox tier with explicit authorization.",
        **task_scope(task),
    }
    write_json(artifact_path, report)
    checks = [
        check(
            "repo_metadata",
            "passed" if not missing else "failed",
            "repo delivery metadata is complete" if not missing else "repo delivery metadata is incomplete",
            missing=missing,
        ),
        check("external_auth", "blocked", "T0 offline run does not perform remote GitHub writes"),
        check("blocked_report", "passed", "typed blocked report is exported", path=repo_rel(artifact_path)),
    ]
    result = make_result(
        task,
        "blocked",
        checks,
        {
            "artifact_paths": [repo_rel(artifact_path)],
            "preview_urls": [],
            "logs": ["github_delivery_fixture_loaded", "record_blocked_result"],
            "repo": report["repo"],
            "branch": report["branch"],
            "failure_kind": "github_auth_blocked",
            "recovery_suggestion": report["recovery_suggestion"],
            **task_scope(task),
        },
        "T0 fixture run verifies GitHub metadata but blocks remote delivery because no authorized sandbox is used.",
    )
    events = task_events(task["id"], repo_rel(fixture), ["load_repo_task", "record_blocked_result"], result)
    return result, events


def verify_v2_harness_evidence(task: dict[str, Any], run_dir: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    fixture = task_fixture(task)
    payload = json.loads(fixture.read_text(encoding="utf-8"))
    actions = payload.get("actions", [])
    required_actions = ["write_file", "read_file", "preview_html", "report_result"]
    missing_actions = [action for action in required_actions if action not in actions]
    artifact_path = run_dir / "artifacts" / task["id"] / "trace-report.json"
    trace_report = {
        "user_prompt": payload.get("prompt"),
        "actions": actions,
        "result": payload.get("expected"),
        "artifact": repo_rel(artifact_path),
        "report": "summary.md",
        **task_scope(task),
    }
    write_json(artifact_path, trace_report)
    checks = [
        check("user_prompt", "passed" if payload.get("prompt") else "failed", "user prompt is recorded"),
        check(
            "action_sequence",
            "passed" if not missing_actions else "failed",
            "required action sequence is complete" if not missing_actions else "required action sequence is incomplete",
            missing_actions=missing_actions,
        ),
        check("result", "passed" if payload.get("expected") else "failed", "expected result is recorded"),
        check("report_artifact", "passed", "trace report artifact exists", path=repo_rel(artifact_path)),
    ]
    result = make_result(
        task,
        "passed",
        checks,
        {
            "artifact_paths": [repo_rel(artifact_path)],
            "preview_urls": [],
            "logs": ["action_evidence", "report_result", "record_t0_fixture_result"],
            **task_scope(task),
        },
        "T0 fixture run verifies trace completeness and exported report metadata.",
    )
    events = task_events(task["id"], repo_rel(fixture), actions, result)
    return result, events


def verify_v2_runtime_orchestration(task: dict[str, Any], run_dir: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    fixture = task_fixture(task)
    payload = json.loads(fixture.read_text(encoding="utf-8"))
    capabilities = payload.get("capabilities", [])
    required_capabilities = {"execute", "stream_logs", "stop_task", "runtime_log"}
    missing_capabilities = sorted(required_capabilities - set(capabilities))
    artifact_path = run_dir / "artifacts" / task["id"] / "runtime-report.json"
    runtime_report = {
        "provider": payload.get("provider"),
        "health_status": payload.get("health_status"),
        "selected_provider": payload.get("selected_provider"),
        "capabilities": capabilities,
        "missing_capabilities": missing_capabilities,
        **task_scope(task),
    }
    write_json(artifact_path, runtime_report)
    checks = [
        check(
            "runtime_health",
            "passed" if payload.get("health_status") == "healthy" else "failed",
            "runtime fixture reports healthy provider",
            health_status=payload.get("health_status"),
        ),
        check(
            "runtime_capabilities",
            "passed" if not missing_capabilities else "failed",
            "required runtime capabilities are present" if not missing_capabilities else "runtime capabilities are missing",
            missing_capabilities=missing_capabilities,
        ),
        check("report_artifact", "passed", "runtime report artifact exists", path=repo_rel(artifact_path)),
    ]
    result = make_result(
        task,
        "passed",
        checks,
        {
            "artifact_paths": [repo_rel(artifact_path)],
            "preview_urls": [],
            "logs": ["runtime_health", "capability_check", "record_t0_fixture_result"],
            **task_scope(task),
        },
        "T0 fixture run verifies runtime health metadata; no live helper process or device lifecycle evidence is collected.",
    )
    events = task_events(task["id"], repo_rel(fixture), ["runtime_health", "capability_check", "report_result"], result)
    return result, events


def make_result(
    task: dict[str, Any],
    status: str,
    checks: list[dict[str, Any]],
    evidence: dict[str, Any],
    notes: str,
) -> dict[str, Any]:
    computed_status = summarize_checks(checks)
    if STATUS_ORDER[computed_status] < STATUS_ORDER[status]:
        status = computed_status
    return {
        "task_id": task["id"],
        "category": task["category"],
        "title": task["title"],
        "status": status,
        "score": score_for_status(status),
        "failure_kind": "none" if status in {"passed", "warning"} else evidence.get("failure_kind", status),
        "checks": checks,
        "evidence": evidence,
        "notes": notes,
    }


def verify_mh_fi_001(task: dict[str, Any], run_dir: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    fixture = task_fixture(task)
    html = parse_html(fixture)
    fixture_rel = repo_rel(fixture)
    route = preview_route(task["id"], bench_rel(fixture))
    artifact_path = run_dir / "artifacts" / task["id"] / "detected-file.json"
    evidence_doc = {
        "incoming_path": fixture_rel,
        "detected_type": "html",
        "preview_url": route,
        "html_summary": html,
    }
    write_json(artifact_path, evidence_doc)
    checks = [
        check("incoming_path_recorded", "passed", "fixture path is repo-relative", incoming_path=fixture_rel),
        check("detected_type", "passed", "HTML file type detected", detected_type="html"),
        check(
            "html_preview",
            "passed" if html["body_text_length"] >= 40 and html["title"] else "failed",
            "preview contains title and readable body text",
            title=html["title"],
            body_text_length=html["body_text_length"],
        ),
        check("preview_route", "passed", "preview route is recorded", preview_url=route),
    ]
    result = make_result(
        task,
        "passed",
        checks,
        {
            "artifact_paths": [repo_rel(artifact_path)],
            "preview_urls": [route],
            "logs": ["external_file_open", "html_preview"],
        },
        "External HTML intake and WebView-style route are verified from the fixture.",
    )
    events = task_events(task["id"], fixture_rel, ["external_file_open", "html_preview", "report_result"], result)
    return result, events


def verify_mh_ce_004(task: dict[str, Any], run_dir: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    fixture = task_fixture(task)
    raw = fixture.read_text(encoding="utf-8")
    before_valid = True
    before_error = ""
    try:
        json.loads(raw)
    except json.JSONDecodeError as exc:
        before_valid = False
        before_error = str(exc)

    repaired = remove_json_trailing_commas(raw)
    payload = json.loads(repaired)
    artifact_path = run_dir / "artifacts" / task["id"] / "fixed-config.json"
    write_json(artifact_path, payload)

    checks = [
        check(
            "validation_before",
            "passed" if not before_valid else "failed",
            "fixture is invalid before repair",
            error=before_error,
        ),
        check("repair_action", "passed", "trailing comma was removed"),
        check("validation_after", "passed", "repaired JSON parses successfully", top_level_keys=sorted(payload)),
        check("artifact_exists", "passed" if artifact_path.exists() else "failed", "fixed JSON artifact exists"),
    ]
    result = make_result(
        task,
        "passed",
        checks,
        {
            "artifact_paths": [repo_rel(artifact_path)],
            "preview_urls": [],
            "logs": ["read_file", "write_file", "validate_json"],
            "validation_before": {"valid": before_valid, "error": before_error},
            "validation_after": {"valid": True, "top_level_keys": sorted(payload)},
        },
        "Invalid JSON fixture is repaired deterministically and written as a run artifact.",
    )
    events = task_events(task["id"], repo_rel(fixture), ["read_file", "repair_json", "write_file", "validate_json"], result)
    return result, events


def verify_mh_pv_001(task: dict[str, Any], run_dir: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    fixture = task_fixture(task)
    html = parse_html(fixture)
    route = preview_route(task["id"], bench_rel(fixture))
    snapshot = {
        "viewport": {"width": 390, "height": 844},
        "title": html["title"],
        "dom_text_length": html["body_text_length"],
        "heading_count": html["heading_count"],
        "route": route,
    }
    artifact_path = run_dir / "artifacts" / task["id"] / "snapshot-summary.json"
    write_json(artifact_path, snapshot)

    checks = [
        check("artifact_exists", "passed", "HTML preview fixture exists", path=repo_rel(fixture)),
        check(
            "snapshot_text",
            "passed" if html["body_text_length"] >= 40 else "failed",
            "snapshot has non-empty mobile preview text",
            dom_text_length=html["body_text_length"],
        ),
        check("preview_url", "passed", "preview route is recorded", preview_url=route),
    ]
    result = make_result(
        task,
        "passed",
        checks,
        {
            "artifact_paths": [repo_rel(artifact_path)],
            "preview_urls": [route],
            "logs": ["preview_html", "preview_snapshot"],
            "snapshot_metadata": snapshot,
        },
        "Generated HTML preview has a non-empty snapshot summary and route.",
    )
    events = task_events(task["id"], repo_rel(fixture), ["preview_html", "snapshot_summary", "report_result"], result)
    return result, events


def verify_mh_gd_001(task: dict[str, Any], run_dir: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    fixture = task_fixture(task)
    payload = json.loads(fixture.read_text(encoding="utf-8"))
    required = ["owner", "repo", "branch", "path", "operation"]
    missing = [key for key in required if not payload.get(key)]
    artifact_path = run_dir / "artifacts" / task["id"] / "github-delivery-blocked.json"
    report = {
        "repo": f"{payload.get('owner')}/{payload.get('repo')}",
        "branch": payload.get("branch"),
        "path": payload.get("path"),
        "operation": payload.get("operation"),
        "failure_kind": "github_auth_blocked",
        "recovery_suggestion": "Run this verifier again with an authorized GitHub delivery environment.",
    }
    write_json(artifact_path, report)
    checks = [
        check(
            "repo_metadata",
            "passed" if not missing else "failed",
            "repo delivery metadata is complete" if not missing else "repo delivery metadata is incomplete",
            missing=missing,
        ),
        check("external_auth", "blocked", "offline dry run does not perform remote GitHub writes"),
        check("blocked_report", "passed", "blocked delivery report is exported", path=repo_rel(artifact_path)),
    ]
    result = make_result(
        task,
        "blocked",
        checks,
        {
            "artifact_paths": [repo_rel(artifact_path)],
            "preview_urls": [],
            "logs": ["github_delivery_fixture_loaded", "blocked_report"],
            "repo": report["repo"],
            "branch": report["branch"],
            "failure_kind": "github_auth_blocked",
            "recovery_suggestion": report["recovery_suggestion"],
        },
        "GitHub delivery is intentionally marked blocked in the offline dry run; metadata and recovery path are still verified.",
    )
    events = task_events(task["id"], repo_rel(fixture), ["load_repo_task", "record_blocked_result"], result)
    return result, events


def verify_mh_he_001(task: dict[str, Any], run_dir: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    fixture = task_fixture(task)
    payload = json.loads(fixture.read_text(encoding="utf-8"))
    actions = payload.get("actions", [])
    required_actions = ["write_file", "read_file", "preview_html", "report_result"]
    missing_actions = [action for action in required_actions if action not in actions]
    artifact_path = run_dir / "artifacts" / task["id"] / "trace-report.json"
    trace_report = {
        "user_prompt": payload.get("prompt"),
        "actions": actions,
        "result": payload.get("expected"),
        "artifact": "docs/mobile-harness-benchmark/runs/<run-id>/artifacts",
        "report": "summary.md",
    }
    write_json(artifact_path, trace_report)
    checks = [
        check("user_prompt", "passed" if payload.get("prompt") else "failed", "user prompt is recorded"),
        check(
            "action_sequence",
            "passed" if not missing_actions else "failed",
            "required action sequence is complete" if not missing_actions else "required action sequence is incomplete",
            missing_actions=missing_actions,
        ),
        check("result", "passed" if payload.get("expected") else "failed", "expected result is recorded"),
        check("report_artifact", "passed" if artifact_path.exists() else "failed", "trace report artifact exists"),
    ]
    result = make_result(
        task,
        "passed",
        checks,
        {
            "artifact_paths": [repo_rel(artifact_path)],
            "preview_urls": [],
            "logs": ["action_evidence", "report_result"],
        },
        "Trace fixture has prompt, ordered actions, result and exported report artifact.",
    )
    events = task_events(task["id"], repo_rel(fixture), actions, result)
    return result, events


VERIFIER_BY_TASK_ID = {
    "MH-FI-001": verify_mh_fi_001,
    "MH-CE-004": verify_mh_ce_004,
    "MH-PV-001": verify_mh_pv_001,
    "MH-GD-001": verify_mh_gd_001,
    "MH-HE-001": verify_mh_he_001,
}
V2_VERIFIER_BY_CATEGORY = {
    "file_intake": verify_v2_file_intake,
    "code_edit": verify_v2_code_edit,
    "preview_verification": verify_v2_preview,
    "github_delivery": verify_v2_github_delivery,
    "harness_evidence": verify_v2_harness_evidence,
    "runtime_orchestration": verify_v2_runtime_orchestration,
}


def select_verifier(task: dict[str, Any]):
    verifier = VERIFIER_BY_TASK_ID.get(task["id"])
    if verifier is not None:
        return verifier
    verifier = V2_VERIFIER_BY_CATEGORY.get(task["category"])
    if verifier is not None:
        return verifier
    fail(f"no dry-run verifier implemented for {task['id']}")


def task_events(
    task_id: str,
    fixture_path: str,
    actions: list[str],
    result: dict[str, Any],
) -> list[dict[str, Any]]:
    events = [
        {
            "task_id": task_id,
            "event_index": 0,
            "kind": "input",
            "summary": "fixture loaded",
            "fixture_path": fixture_path,
        }
    ]
    for index, action in enumerate(actions, start=1):
        events.append(
            {
                "task_id": task_id,
                "event_index": index,
                "kind": "action",
                "action": action,
                "summary": f"{action} executed in deterministic dry run",
            }
        )
    events.append(
        {
            "task_id": task_id,
            "event_index": len(events),
            "kind": "result",
            "status": result["status"],
            "failure_kind": result["failure_kind"],
            "artifact_paths": result["evidence"].get("artifact_paths", []),
            "preview_urls": result["evidence"].get("preview_urls", []),
        }
    )
    return events


def assert_public_safe(paths: list[Path]) -> dict[str, Any]:
    findings: list[dict[str, str]] = []
    for path in paths:
        text = path.read_text(encoding="utf-8")
        for pattern in PUBLIC_BLOCKLIST:
            match = pattern.search(text)
            if match:
                findings.append({"path": repo_rel(path), "pattern": pattern.pattern, "match": match.group(0)})
    return {"status": "passed" if not findings else "failed", "findings": findings}


def write_summary(run_dir: Path, run_payload: dict[str, Any]) -> Path:
    summary_path = run_dir / "summary.md"
    task_set = run_payload["task_set"]
    is_smoke_v2 = task_set == "smoke-v2"
    title = "MobileHarnessBench T0 Smoke Run" if is_smoke_v2 else "MobileHarnessBench v0 Dry Run"
    intro = (
        "This T0 offline smoke run verifies 60 v2 tasks, ten per category, using repo fixtures only."
        if is_smoke_v2
        else "This offline dry run verifies five representative tasks, one per benchmark category."
    )
    boundary = (
        "It checks fixture-level artifacts, typed blocked states, traces and public-safe reports; it is not Android or iOS device evidence."
        if is_smoke_v2
        else "It uses repo fixtures only and records public-safe, repo-relative evidence."
    )
    lines = [
        f"# {title}: {run_payload['run_id']}",
        "",
        intro,
        boundary,
        "",
        "## Summary",
        "",
        f"- Total tasks: {run_payload['summary']['total']}",
        f"- Passed: {run_payload['summary']['passed']}",
        f"- Blocked: {run_payload['summary']['blocked']}",
        f"- Failed: {run_payload['summary']['failed']}",
        f"- Warning: {run_payload['summary']['warning']}",
        f"- Categories covered: {', '.join(sorted(run_payload['summary']['categories']))}",
        "",
        "## Results",
        "",
        "| Task | Category | Status | Score | Evidence | Notes |",
        "| --- | --- | --- | ---: | --- | --- |",
    ]
    for result in run_payload["results"]:
        evidence_paths = ", ".join(result["evidence"].get("artifact_paths", [])) or "none"
        lines.append(
            f"| `{result['task_id']}` | `{result['category']}` | `{result['status']}` | "
            f"{result['score']} | {evidence_paths} | {result['notes']} |"
        )
    if is_smoke_v2:
        lines.extend(
            [
                "",
                "## Interpretation",
                "",
                "- T0 fixture checks pass for file intake, code edit, preview, harness evidence and runtime metadata tasks.",
                "- GitHub delivery tasks are `blocked` by design because this run does not use an authorized GitHub sandbox.",
                "- Results include `counts_as_mobile_experiment=false`; they must not be counted as Android/iOS device evidence.",
                "- Device-tier claims still require T2 Android real-device or T3/T4 iOS evidence.",
            ]
        )
        summary_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return summary_path
    lines.extend(
        [
            "",
            "## Interpretation",
            "",
            "- The four local/offline tasks pass with concrete artifacts and trace events.",
            "- `MH-GD-001` is `blocked` by design because the dry run does not perform remote GitHub writes.",
            "- The blocked result still has a verifier result, typed failure kind and recovery suggestion.",
            "- Public output is constrained to repo-relative paths and synthetic preview routes.",
        ]
    )
    summary_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return summary_path


def run_benchmark(run_id: str, task_set: str, task_ids: list[str]) -> dict[str, Any]:
    tasks = load_tasks(task_set)
    run_dir = RUNS_ROOT / run_id
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "artifacts").mkdir(exist_ok=True)
    (run_dir / "screenshots").mkdir(exist_ok=True)

    results: list[dict[str, Any]] = []
    traces: list[dict[str, Any]] = []
    for task_id in task_ids:
        if task_id not in tasks:
            fail(f"unknown task id: {task_id}")
        verifier = select_verifier(tasks[task_id])
        result, events = verifier(tasks[task_id], run_dir)
        results.append(result)
        traces.extend(events)

    counts = Counter(result["status"] for result in results)
    categories = sorted({result["category"] for result in results})
    run_payload = {
        "benchmark": "MobileHarnessBench",
        "version": "0.2.0" if task_set == "smoke-v2" else "0.0.1",
        "run_id": run_id,
        "task_set": task_set,
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "environment": {
            "mode": "offline_fixture_dry_run",
            "model_provider": "none",
            "model_name": "deterministic-stdlib-verifiers",
            "runtime_backend": "fixture_runner",
            "app_version": "0.1.30+49",
        },
        "summary": {
            "total": len(results),
            "passed": counts["passed"],
            "blocked": counts["blocked"],
            "failed": counts["failed"],
            "warning": counts["warning"],
            "categories": categories,
        },
        "results": results,
    }

    run_json_path = run_dir / "run.json"
    traces_path = run_dir / "traces.jsonl"
    write_json(run_json_path, run_payload)
    traces_path.write_text(
        "".join(json.dumps(event, ensure_ascii=False) + "\n" for event in traces),
        encoding="utf-8",
    )
    summary_path = write_summary(run_dir, run_payload)
    privacy_check = assert_public_safe([run_json_path, traces_path, summary_path])
    run_payload["privacy_check"] = privacy_check
    write_json(run_json_path, run_payload)
    return {
        "run_dir": repo_rel(run_dir),
        "run_json": repo_rel(run_json_path),
        "summary": repo_rel(summary_path),
        "traces": repo_rel(traces_path),
        "result_counts": dict(sorted(counts.items())),
        "privacy_check": privacy_check,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", default="2026-06-06-v0-dry-run")
    parser.add_argument(
        "--task-set",
        default="representative-v0",
        choices=sorted(TASK_SET_PATHS),
        help="Dry-run task selection.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    result = run_benchmark(args.run_id, args.task_set, load_task_set(args.task_set))
    if result["privacy_check"]["status"] != "passed":
        print(json.dumps(result, ensure_ascii=False, indent=2), file=sys.stderr)
        raise SystemExit(1)
    print("MobileHarnessBench dry run completed")
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
