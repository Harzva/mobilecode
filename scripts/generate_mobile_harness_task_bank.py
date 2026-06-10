#!/usr/bin/env python3
"""Generate MobileHarnessBench candidate task banks.

The generated banks are task-definition data, not experimental results. A task
only counts in paper experiments after it has verifier results, traces and a
summary report.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
BENCH_ROOT = ROOT / "docs" / "mobile-harness-benchmark"
TASKS_ROOT = BENCH_ROOT / "tasks"
OUTPUT_V1_PATH = TASKS_ROOT / "v1-task-bank.json"
OUTPUT_V2_PATH = TASKS_ROOT / "v2-task-bank.json"
SMOKE_V2_PATH = TASKS_ROOT / "smoke-v2.json"
ANDROID_DEVICE_V2_PATH = TASKS_ROOT / "android-device-v2.json"
IOS_SIMULATOR_V2_PATH = TASKS_ROOT / "ios-simulator-v2.json"

V1_CONTEXTS = [
    ("wechat_share", "from a chat share sheet"),
    ("system_file_picker", "from the Android file picker"),
    ("workspace_import", "from a MobileCode workspace import"),
    ("webview_return", "after returning from WebView preview"),
    ("offline_mode", "while the phone is offline"),
    ("low_memory", "after a low-memory app resume"),
    ("narrow_viewport", "on a narrow mobile viewport"),
    ("public_report", "with a public report export requirement"),
]

V2_CONTEXTS = V1_CONTEXTS + [
    ("background_resume", "after the app returns from background"),
    ("poor_network", "under unstable mobile network conditions"),
]

QUALITY_MODES = [
    {
        "name": "happy_path",
        "label": "happy path",
        "difficulty": "easy",
        "gates": ["task_goal_satisfied", "required_artifact_present", "verifier_passed"],
        "tags": ["smoke", "offline_candidate"],
    },
    {
        "name": "failure_recovery",
        "label": "failure recovery",
        "difficulty": "medium",
        "gates": ["typed_failure_kind", "recovery_suggestion", "no_silent_success"],
        "tags": ["recovery", "edge_case"],
    },
    {
        "name": "public_report_safety",
        "label": "public report safety",
        "difficulty": "hard",
        "gates": ["repo_relative_paths", "redaction_checked", "public_summary_exported"],
        "tags": ["privacy", "paper_safe"],
    },
    {
        "name": "mobile_constraint",
        "label": "mobile constraint",
        "difficulty": "edge",
        "gates": ["bounded_viewport", "low_resource_path", "human_action_minimized"],
        "tags": ["device_candidate", "mobile_ux"],
    },
]

MOBILE_VARIANTS = [
    {
        "profile": "android_real_phone_share",
        "os_target": "android_real_device",
        "input_surface": "Android Sharesheet",
        "app_state": "cold_start",
        "network_profile": "wifi",
        "viewport": "393x873",
        "requires_real_device": True,
        "evidence_capture": ["screen_recording", "logcat_excerpt", "run_json"],
    },
    {
        "profile": "android_emulator_file_picker",
        "os_target": "android_emulator",
        "input_surface": "Android file picker",
        "app_state": "warm_resume",
        "network_profile": "offline",
        "viewport": "411x891",
        "requires_real_device": False,
        "evidence_capture": ["screenshot", "dom_summary", "run_json"],
    },
    {
        "profile": "ios_simulator_document",
        "os_target": "ios_simulator",
        "input_surface": "iOS document picker",
        "app_state": "fresh_install",
        "network_profile": "wifi",
        "viewport": "390x844",
        "requires_real_device": False,
        "evidence_capture": ["simulator_screenshot", "xcode_log_excerpt", "run_json"],
    },
    {
        "profile": "ios_real_open_in",
        "os_target": "ios_real_device",
        "input_surface": "iOS Open In",
        "app_state": "background_resume",
        "network_profile": "cellular",
        "viewport": "430x932",
        "requires_real_device": True,
        "evidence_capture": ["device_screenshot", "share_flow_note", "run_json"],
    },
    {
        "profile": "android_low_memory",
        "os_target": "android_real_device",
        "input_surface": "MobileCode workspace picker",
        "app_state": "low_memory_resume",
        "network_profile": "poor_network",
        "viewport": "360x800",
        "requires_real_device": True,
        "evidence_capture": ["memory_snapshot", "runtime_log", "run_json"],
    },
    {
        "profile": "webview_only_preview",
        "os_target": "android_or_ios",
        "input_surface": "in-app WebView preview",
        "app_state": "preview_return",
        "network_profile": "offline",
        "viewport": "375x812",
        "requires_real_device": False,
        "evidence_capture": ["dom_summary", "preview_route", "run_json"],
    },
]

QUALITY_GOAL_CLAUSES = {
    "happy_path": "The success path must complete without manual recovery.",
    "failure_recovery": "If a required capability is unavailable, the result must use a typed failure and recovery suggestion.",
    "public_report_safety": "The exported report must avoid private identifiers and use public-safe relative evidence.",
    "mobile_constraint": "The task must remain usable under the declared mobile viewport, app state and resource constraints.",
}

QUALITY_ORACLES = {
    "happy_path": ["artifact_available", "verifier_status_passed", "trace_complete"],
    "failure_recovery": ["failure_kind_stable", "recovery_suggestion_present", "blocked_not_failed_when_external"],
    "public_report_safety": ["no_private_paths", "no_raw_private_values", "public_summary_present"],
    "mobile_constraint": ["viewport_bounded", "app_resume_recorded", "manual_steps_within_limit"],
}

V2_CATEGORY_TARGETS = {
    "file_intake": 167,
    "code_edit": 167,
    "preview_verification": 167,
    "github_delivery": 167,
    "harness_evidence": 166,
    "runtime_orchestration": 166,
}


def fixture(kind: str, path: str, description: str) -> dict[str, str]:
    return {"kind": kind, "path": path, "description": description}


CATEGORY_BLUEPRINTS: dict[str, dict[str, Any]] = {
    "file_intake": {
        "prefix": "FI",
        "fixtures": [
            {
                "label": "HTML",
                "fixture": fixture("html", "fixtures/file-intake/simple-page.html", "A valid small HTML page."),
                "capabilities": ["external_file_open", "html_preview"],
                "artifacts": ["preview_route", "detected_file_type"],
                "verifiers": ["external_file_verifier", "html_preview_verifier"],
                "evidence": ["incoming_path", "detected_type", "preview_url"],
                "blocked": ["platform share intent unavailable"],
            },
            {
                "label": "Markdown",
                "fixture": fixture("markdown", "fixtures/file-intake/article.md", "Markdown with title, paragraphs, list and image reference."),
                "capabilities": ["external_file_open", "markdown_preview"],
                "artifacts": ["preview_route", "markdown_summary"],
                "verifiers": ["external_file_verifier", "markdown_preview_verifier"],
                "evidence": ["incoming_path", "heading_count", "paragraph_count"],
                "blocked": ["platform share intent unavailable"],
            },
            {
                "label": "unknown extension text",
                "fixture": fixture("unknown_text", "fixtures/file-intake/wechat-export.dat", "UTF-8 text with an uncommon extension."),
                "capabilities": ["external_file_open", "text_preview_fallback"],
                "artifacts": ["detected_file_type", "fallback_preview"],
                "verifiers": ["external_file_verifier", "evidence_verifier"],
                "evidence": ["fallback_reason", "text_preview"],
                "blocked": ["file cannot be read by OS permission"],
            },
            {
                "label": "JSON",
                "fixture": fixture("json", "fixtures/file-intake/config.json", "Small JSON document."),
                "capabilities": ["external_file_open", "json_validate"],
                "artifacts": ["json_validation_result"],
                "verifiers": ["external_file_verifier", "json_verifier"],
                "evidence": ["json_valid", "top_level_keys"],
                "blocked": ["file cannot be read by OS permission"],
            },
            {
                "label": "unsupported binary",
                "fixture": fixture("binary", "fixtures/file-intake/sample.bin", "Unsupported binary payload."),
                "capabilities": ["external_file_open", "safe_blocked_state"],
                "artifacts": ["blocked_result"],
                "verifiers": ["external_file_verifier", "evidence_verifier"],
                "evidence": ["failure_kind", "user_message"],
                "blocked": ["expected unsupported type"],
            },
        ],
        "goal": "Handle a shared {label} file {context} and produce a verified intake result.",
        "title": "Intake {label}",
    },
    "code_edit": {
        "prefix": "CE",
        "fixtures": [
            {
                "label": "HTML artifact prompt",
                "fixture": fixture("prompt", "fixtures/code-edit/html-prompt.txt", "Prompt for a small landing page."),
                "capabilities": ["write_file", "read_file", "html_preview"],
                "artifacts": ["index.html", "preview_route"],
                "verifiers": ["artifact_exists_verifier", "html_preview_verifier"],
                "evidence": ["write_action", "readback_action", "artifact_path"],
                "blocked": ["workspace unavailable"],
            },
            {
                "label": "existing HTML page",
                "fixture": fixture("html", "fixtures/code-edit/existing-page.html", "HTML page requiring a new section."),
                "capabilities": ["read_file", "apply_patch", "preview_html"],
                "artifacts": ["patched_html", "diff_summary"],
                "verifiers": ["artifact_exists_verifier", "html_preview_verifier", "trace_verifier"],
                "evidence": ["before_read", "patch_action", "after_read"],
                "blocked": ["workspace unavailable"],
            },
            {
                "label": "Markdown report prompt",
                "fixture": fixture("prompt", "fixtures/code-edit/report-prompt.txt", "Prompt for a structured report."),
                "capabilities": ["write_file", "validate_markdown"],
                "artifacts": ["report.md"],
                "verifiers": ["markdown_preview_verifier", "artifact_exists_verifier"],
                "evidence": ["markdown_validation", "artifact_path"],
                "blocked": ["workspace unavailable"],
            },
            {
                "label": "invalid JSON config",
                "fixture": fixture("json", "fixtures/code-edit/broken-config.json", "Invalid JSON with trailing comma."),
                "capabilities": ["read_file", "write_file", "validate_json"],
                "artifacts": ["fixed_json"],
                "verifiers": ["json_verifier", "trace_verifier"],
                "evidence": ["validation_before", "repair_action", "validation_after"],
                "blocked": ["workspace unavailable"],
            },
            {
                "label": "multi-section Markdown",
                "fixture": fixture("markdown", "fixtures/code-edit/multi-section.md", "Markdown with multiple sections."),
                "capabilities": ["read_file", "apply_patch", "virtual_diff"],
                "artifacts": ["diff_summary"],
                "verifiers": ["diff_scope_verifier", "trace_verifier"],
                "evidence": ["diff", "changed_sections"],
                "blocked": ["workspace unavailable"],
            },
        ],
        "goal": "Complete a code-edit workflow on {label} {context} and export verifier evidence.",
        "title": "Edit {label}",
    },
    "preview_verification": {
        "prefix": "PV",
        "fixtures": [
            {
                "label": "generated HTML",
                "fixture": fixture("html", "fixtures/preview/index.html", "Valid generated HTML."),
                "capabilities": ["preview_html", "preview_snapshot"],
                "artifacts": ["preview_url", "snapshot_summary"],
                "verifiers": ["html_preview_verifier", "snapshot_verifier"],
                "evidence": ["preview_url", "snapshot_metadata"],
                "blocked": ["webview unavailable"],
            },
            {
                "label": "blank HTML",
                "fixture": fixture("html", "fixtures/preview/blank.html", "Blank HTML document."),
                "capabilities": ["preview_html", "preview_snapshot"],
                "artifacts": ["failed_verifier_result"],
                "verifiers": ["html_preview_verifier", "evidence_verifier"],
                "evidence": ["failure_kind", "dom_text_length"],
                "blocked": ["webview unavailable"],
            },
            {
                "label": "dense Markdown",
                "fixture": fixture("markdown", "fixtures/preview/dense.md", "Dense Markdown text."),
                "capabilities": ["markdown_preview", "validate_markdown"],
                "artifacts": ["markdown_readability_report"],
                "verifiers": ["markdown_preview_verifier"],
                "evidence": ["heading_count", "paragraph_density"],
                "blocked": ["markdown preview unavailable"],
            },
            {
                "label": "Markdown with local images",
                "fixture": fixture("markdown", "fixtures/preview/images.md", "Markdown containing local image references."),
                "capabilities": ["markdown_preview", "file_access"],
                "artifacts": ["image_reference_report"],
                "verifiers": ["markdown_preview_verifier", "evidence_verifier"],
                "evidence": ["image_count", "missing_images"],
                "blocked": ["image files unavailable"],
            },
            {
                "label": "malformed HTML",
                "fixture": fixture("html", "fixtures/preview/invalid.html", "Malformed HTML."),
                "capabilities": ["preview_html", "report_result"],
                "artifacts": ["recovery_suggestion"],
                "verifiers": ["snapshot_verifier", "evidence_verifier"],
                "evidence": ["failure_kind", "recovery_suggestion"],
                "blocked": ["webview unavailable"],
            },
        ],
        "goal": "Verify preview behavior for {label} {context} and record the snapshot or recovery evidence.",
        "title": "Preview {label}",
    },
    "github_delivery": {
        "prefix": "GD",
        "fixtures": [
            {
                "label": "commit artifact",
                "fixture": fixture("repo_task", "fixtures/github/commit-artifact.json", "Repo and file metadata for commit test."),
                "capabilities": ["github_contents_api", "commit"],
                "artifacts": ["commit_sha"],
                "verifiers": ["github_delivery_verifier"],
                "evidence": ["repo", "branch", "commit_sha"],
                "blocked": ["github_auth_blocked", "repo_permission_missing"],
            },
            {
                "label": "SHA conflict",
                "fixture": fixture("repo_task", "fixtures/github/sha-conflict.json", "Simulated stale SHA edit."),
                "capabilities": ["github_contents_api", "conflict_handling"],
                "artifacts": ["conflict_report"],
                "verifiers": ["github_delivery_verifier", "evidence_verifier"],
                "evidence": ["failure_kind", "recovery_suggestion"],
                "blocked": ["github_auth_blocked"],
            },
            {
                "label": "Pages publish",
                "fixture": fixture("repo_task", "fixtures/github/pages-publish.json", "Repo metadata for Pages publish."),
                "capabilities": ["github_pages", "html_preview"],
                "artifacts": ["pages_url"],
                "verifiers": ["github_delivery_verifier", "html_preview_verifier"],
                "evidence": ["pages_url", "commit_sha"],
                "blocked": ["github_auth_blocked", "pages_not_enabled"],
            },
            {
                "label": "Actions dispatch",
                "fixture": fixture("repo_task", "fixtures/github/actions-dispatch.json", "Workflow dispatch metadata."),
                "capabilities": ["github_actions_dispatch", "github_actions_read"],
                "artifacts": ["actions_run_url"],
                "verifiers": ["github_delivery_verifier"],
                "evidence": ["workflow", "run_url", "run_status"],
                "blocked": ["github_auth_blocked", "workflow_dispatch_disabled"],
            },
            {
                "label": "release artifact",
                "fixture": fixture("repo_task", "fixtures/github/artifact-download.json", "Completed workflow run metadata."),
                "capabilities": ["github_actions_read", "artifact_list"],
                "artifacts": ["artifact_metadata"],
                "verifiers": ["github_delivery_verifier"],
                "evidence": ["artifact_name", "artifact_size", "run_url"],
                "blocked": ["github_auth_blocked", "artifact_expired"],
            },
        ],
        "goal": "Execute or safely block a GitHub delivery workflow for {label} {context} with typed evidence.",
        "title": "Deliver {label}",
    },
    "harness_evidence": {
        "prefix": "HE",
        "fixtures": [
            {
                "label": "complete trace",
                "fixture": fixture("trace_task", "fixtures/evidence/complete-trace.json", "Trace completeness test."),
                "capabilities": ["action_evidence", "report_result"],
                "artifacts": ["trace_report"],
                "verifiers": ["trace_verifier"],
                "evidence": ["user_prompt", "action", "result", "artifact", "report"],
                "blocked": ["evidence_store_unavailable"],
            },
            {
                "label": "typed failure",
                "fixture": fixture("trace_task", "fixtures/evidence/failure-kind.json", "Failed action with expected failure kind."),
                "capabilities": ["action_evidence"],
                "artifacts": ["failure_report"],
                "verifiers": ["evidence_verifier"],
                "evidence": ["failure_kind", "user_message"],
                "blocked": ["evidence_store_unavailable"],
            },
            {
                "label": "runtime blocked recovery",
                "fixture": fixture("trace_task", "fixtures/evidence/runtime-blocked.json", "Runtime unavailable trace."),
                "capabilities": ["runtime_health", "report_result"],
                "artifacts": ["recovery_report"],
                "verifiers": ["evidence_verifier"],
                "evidence": ["runtime_status", "recovery_suggestion"],
                "blocked": ["runtime_unavailable"],
            },
            {
                "label": "public report redaction",
                "fixture": fixture("trace_task", "fixtures/evidence/redaction.json", "Trace containing private local details."),
                "capabilities": ["report_export", "redaction"],
                "artifacts": ["public_report"],
                "verifiers": ["privacy_verifier", "trace_verifier"],
                "evidence": ["redaction_summary", "public_report_path"],
                "blocked": ["report_export_unavailable"],
            },
            {
                "label": "run comparison",
                "fixture": fixture("trace_task", "fixtures/evidence/run-compare.json", "Two run reports for comparison."),
                "capabilities": ["trace_compare", "report_result"],
                "artifacts": ["comparison_report"],
                "verifiers": ["trace_verifier"],
                "evidence": ["run_a", "run_b", "comparison_metrics"],
                "blocked": ["trace_compare_unavailable"],
            },
        ],
        "goal": "Produce harness evidence for {label} {context} and make the result reviewable.",
        "title": "Evidence {label}",
    },
    "runtime_orchestration": {
        "prefix": "RT",
        "fixtures": [
            {
                "label": "Helper health",
                "fixture": fixture("runtime_task", "fixtures/runtime/helper-health.json", "Helper runtime health and capability metadata."),
                "capabilities": ["runtime_health", "provider_select"],
                "artifacts": ["runtime_health_report"],
                "verifiers": ["runtime_verifier", "evidence_verifier"],
                "evidence": ["provider", "health_status", "capabilities"],
                "blocked": ["runtime_unavailable"],
            },
            {
                "label": "Termux unavailable fallback",
                "fixture": fixture("runtime_task", "fixtures/runtime/termux-unavailable.json", "External Termux unavailable fallback case."),
                "capabilities": ["runtime_fallback", "report_result"],
                "artifacts": ["fallback_report"],
                "verifiers": ["runtime_verifier", "evidence_verifier"],
                "evidence": ["fallback_reason", "selected_provider", "user_message"],
                "blocked": ["external_runtime_missing"],
            },
            {
                "label": "WebViewOnly route",
                "fixture": fixture("runtime_task", "fixtures/runtime/webview-only.json", "WebViewOnly preview-capable runtime case."),
                "capabilities": ["webview_only_runtime", "preview_html"],
                "artifacts": ["preview_route", "runtime_mode"],
                "verifiers": ["runtime_verifier", "html_preview_verifier"],
                "evidence": ["runtime_mode", "preview_url", "blocked_actions"],
                "blocked": ["shell_execution_unavailable"],
            },
            {
                "label": "runtime switch",
                "fixture": fixture("runtime_task", "fixtures/runtime/runtime-switch.json", "Runtime provider switch request."),
                "capabilities": ["provider_select", "action_runner_boundary"],
                "artifacts": ["provider_switch_report"],
                "verifiers": ["runtime_verifier", "trace_verifier"],
                "evidence": ["previous_provider", "selected_provider", "decision_reason"],
                "blocked": ["provider_not_configured"],
            },
            {
                "label": "long task stop",
                "fixture": fixture("runtime_task", "fixtures/runtime/long-task-stop.json", "Long-running task stop and recovery case."),
                "capabilities": ["task_stop", "runtime_log", "report_result"],
                "artifacts": ["stop_report", "runtime_log_summary"],
                "verifiers": ["runtime_verifier", "trace_verifier"],
                "evidence": ["stop_action", "final_status", "log_tail"],
                "blocked": ["runtime_stop_unavailable"],
            },
        ],
        "goal": "Orchestrate runtime behavior for {label} {context} and prove the selected execution boundary.",
        "title": "Runtime {label}",
    },
}


def build_task(
    category: str,
    blueprint: dict[str, Any],
    fixture_case: dict[str, Any],
    context: tuple[str, str],
    *,
    task_number: int,
    bank_version: str,
    quality_mode: dict[str, Any] | None = None,
    variant: dict[str, Any] | None = None,
) -> dict[str, Any]:
    context_name, context_text = context
    task_id = f"MH-{blueprint['prefix']}-{task_number:03d}"
    title_parts = [blueprint["title"].format(label=fixture_case["label"]), context_name]
    if quality_mode:
        title_parts.append(quality_mode["name"])
    if variant:
        title_parts.append(variant["profile"])
    goal = blueprint["goal"].format(label=fixture_case["label"], context=context_text)
    if quality_mode:
        goal = f"{goal} {QUALITY_GOAL_CLAUSES[quality_mode['name']]}"
    if variant:
        goal = (
            f"{goal} Target mobile profile: {variant['profile']} via "
            f"{variant['input_surface']} on {variant['os_target']}."
        )
    task = {
        "id": task_id,
        "category": category,
        "title": " ".join(title_parts),
        "user_goal": goal,
        "input_fixture": fixture_case["fixture"],
        "required_capabilities": fixture_case["capabilities"],
        "expected_artifacts": fixture_case["artifacts"],
        "verifiers": fixture_case["verifiers"],
        "evidence_requirements": fixture_case["evidence"],
        "blocked_conditions": fixture_case["blocked"],
        "scenario": {
            "context": context_name,
            "difficulty": quality_mode["difficulty"] if quality_mode else "medium",
            "source": "capability_matrix",
            "fixture_family": fixture_case["label"],
            "bank_version": bank_version,
        },
        "notes": f"{bank_version} candidate task; requires verifier/device dry run before being counted as experimentally validated.",
    }
    if quality_mode:
        task["scenario"]["quality_axis"] = quality_mode["name"]
        task["quality_gates"] = quality_mode["gates"]
        task["sampling_tags"] = quality_mode["tags"] + [category, context_name]
        task["test_oracle"] = {
            "must_satisfy": QUALITY_ORACLES[quality_mode["name"]],
            "failure_policy": "Use blocked for external/platform constraints; use failed for missing artifacts or verifier violations.",
        }
    if variant:
        task["scenario"]["mobile_profile"] = variant["profile"]
        task["scenario"]["os_target"] = variant["os_target"]
        task["scenario"]["input_surface"] = variant["input_surface"]
        task["scenario"]["app_state"] = variant["app_state"]
        task["scenario"]["network_profile"] = variant["network_profile"]
        task["scenario"]["viewport"] = variant["viewport"]
        task["mobile_requirements"] = {
            "os_target": variant["os_target"],
            "input_surface": variant["input_surface"],
            "app_state": variant["app_state"],
            "network_profile": variant["network_profile"],
            "viewport": variant["viewport"],
            "requires_real_device": variant["requires_real_device"],
            "evidence_capture": variant["evidence_capture"],
        }
    return task


def generate_v1_tasks() -> list[dict[str, Any]]:
    tasks: list[dict[str, Any]] = []
    task_categories = ["file_intake", "code_edit", "preview_verification", "github_delivery", "harness_evidence"]
    for category in task_categories:
        blueprint = CATEGORY_BLUEPRINTS[category]
        for fixture_index, fixture_case in enumerate(blueprint["fixtures"]):
            for context_index, context in enumerate(V1_CONTEXTS):
                task_number = 101 + fixture_index * len(V1_CONTEXTS) + context_index
                tasks.append(
                    build_task(
                        category,
                        blueprint,
                        fixture_case,
                        context,
                        task_number=task_number,
                        bank_version="v1",
                    )
                )
    return tasks


def generate_v2_tasks() -> list[dict[str, Any]]:
    tasks: list[dict[str, Any]] = []
    for category, target_count in V2_CATEGORY_TARGETS.items():
        blueprint = CATEGORY_BLUEPRINTS[category]
        candidates: list[dict[str, Any]] = []
        for fixture_case in blueprint["fixtures"]:
            for context in V2_CONTEXTS:
                for quality_mode in QUALITY_MODES:
                    candidates.append(
                        (fixture_case, context, quality_mode)
                    )
        if len(candidates) < target_count:
            raise ValueError(f"{category} has only {len(candidates)} candidate combinations")
        for offset, (fixture_case, context, quality_mode) in enumerate(candidates[:target_count]):
            variant = MOBILE_VARIANTS[offset % len(MOBILE_VARIANTS)]
            tasks.append(
                build_task(
                    category,
                    blueprint,
                    fixture_case,
                    context,
                    task_number=201 + offset,
                    bank_version="v2",
                    quality_mode=quality_mode,
                    variant=variant,
                )
            )
    return tasks


def write_bank(path: Path, version: str, status: str, tasks: list[dict[str, Any]]) -> None:
    category_count = {}
    for task in tasks:
        category_count[task["category"]] = category_count.get(task["category"], 0) + 1
    payload = {
        "benchmark": "MobileHarnessBench",
        "version": version,
        "created_at": "2026-06-06",
        "status": status,
        "source": "scripts/generate_mobile_harness_task_bank.py",
        "task_count": len(tasks),
        "category_count": dict(sorted(category_count.items())),
        "quality_model": {
            "candidate_only": True,
            "experiment_counting_rule": "Only tasks with verifier result, trace and summary can be counted in paper experiments.",
            "quality_axes": [mode["name"] for mode in QUALITY_MODES],
            "mobile_profiles": [variant["profile"] for variant in MOBILE_VARIANTS],
        },
        "tasks": tasks,
    }
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def select_per_category(tasks: list[dict[str, Any]], count: int, predicate: Any) -> list[dict[str, Any]]:
    selected: list[dict[str, Any]] = []
    for category in sorted({task["category"] for task in tasks}):
        matches = [task for task in tasks if task["category"] == category and predicate(task)]
        if len(matches) < count:
            raise ValueError(f"{category} has only {len(matches)} matches; need {count}")
        selected.extend(matches[:count])
    return selected


def write_task_set(path: Path, task_set: str, description: str, test_tier: str, tasks: list[dict[str, Any]]) -> None:
    entries = []
    for task in tasks:
        entries.append(
            {
                "id": task["id"],
                "category": task["category"],
                "fixture": task["input_fixture"]["path"],
                "test_tier": test_tier,
                "mobile_profile": task["scenario"]["mobile_profile"],
                "quality_axis": task["scenario"]["quality_axis"],
                "requires_real_device": task["mobile_requirements"]["requires_real_device"],
            }
        )
    payload = {
        "task_set": task_set,
        "description": description,
        "source_task_bank": "tasks/v2-task-bank.json",
        "task_count": len(entries),
        "categories": dict(sorted({category: sum(1 for entry in entries if entry["category"] == category) for category in {entry["category"] for entry in entries}}.items())),
        "tasks": entries,
    }
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def write_v2_task_sets(v2_tasks: list[dict[str, Any]]) -> None:
    smoke_tasks = select_per_category(
        v2_tasks,
        10,
        lambda task: task["scenario"]["quality_axis"] == "happy_path",
    )
    android_device_tasks = select_per_category(
        v2_tasks,
        5,
        lambda task: task["mobile_requirements"]["os_target"] == "android_real_device"
        and task["mobile_requirements"]["requires_real_device"],
    )
    ios_simulator_tasks = select_per_category(
        v2_tasks,
        3,
        lambda task: task["mobile_requirements"]["os_target"] == "ios_simulator",
    )
    write_task_set(
        SMOKE_V2_PATH,
        "smoke-v2",
        "Sixty v2 smoke tasks, ten per category, for the first T0 offline verifier expansion.",
        "T0-offline-fixture",
        smoke_tasks,
    )
    write_task_set(
        ANDROID_DEVICE_V2_PATH,
        "android-device-v2",
        "Thirty v2 Android real-device tasks, five per category, for T2 mobile evidence.",
        "T2-android-real-device",
        android_device_tasks,
    )
    write_task_set(
        IOS_SIMULATOR_V2_PATH,
        "ios-simulator-v2",
        "Eighteen v2 iOS simulator tasks, three per category, for T3 Mac simulator regression.",
        "T3-ios-simulator",
        ios_simulator_tasks,
    )


def main() -> None:
    v1_tasks = generate_v1_tasks()
    v2_tasks = generate_v2_tasks()
    write_bank(OUTPUT_V1_PATH, "0.1.0", "v1_candidate_bank", v1_tasks)
    write_bank(OUTPUT_V2_PATH, "0.2.0", "v2_candidate_bank", v2_tasks)
    write_v2_task_sets(v2_tasks)
    print(f"wrote {OUTPUT_V1_PATH.relative_to(ROOT)} tasks={len(v1_tasks)}")
    print(f"wrote {OUTPUT_V2_PATH.relative_to(ROOT)} tasks={len(v2_tasks)}")
    print(f"wrote {SMOKE_V2_PATH.relative_to(ROOT)} tasks=60")
    print(f"wrote {ANDROID_DEVICE_V2_PATH.relative_to(ROOT)} tasks=30")
    print(f"wrote {IOS_SIMULATOR_V2_PATH.relative_to(ROOT)} tasks=18")


if __name__ == "__main__":
    main()
