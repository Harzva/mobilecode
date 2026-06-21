#!/usr/bin/env python3
"""Generate the P6.0-P6.2 runtime benchmark upgrade contract run.

This runner materializes taxonomy, communication-substrate, and runtime
verifier scaffold contracts as a validator-compatible, non-counted strategy
pilot. It does not call a model, drive a device, or claim a formal benchmark.
"""

from __future__ import annotations

import argparse
import csv
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import run_mobile_harness_strategy_real_pilot as p5


ROOT = p5.ROOT
REGISTRY_PATH = p5.REGISTRY_PATH
RUN_KIND = p5.RUN_KIND
BOUNDARY = p5.BOUNDARY
RUN_ID = "p60-p62-runtime-benchmark-upgrade"
TASKS = [
    {
        "task_id": "P60-BENCHMARK-TAXONOMY-001",
        "task_category": "benchmark_taxonomy_contract",
        "title": "P6.0 benchmark task taxonomy, runtime assertion matrix, and score dimensions",
        "phase": "P6.0",
    },
    {
        "task_id": "P61-COMMUNICATION-SUBSTRATE-001",
        "task_category": "communication_substrate_contract",
        "title": "P6.1 mailbox, evidence ledger, runtime event bus, and memory proposal contracts",
        "phase": "P6.1",
    },
    {
        "task_id": "P62-RUNTIME-VERIFIER-SCAFFOLD-001",
        "task_category": "runtime_verifier_scaffold_contract",
        "title": "P6.2 runtime verifier JSON and non-counted run contract scaffold",
        "phase": "P6.2",
    },
]
OUTPUT_DIR = ROOT / "docs/mobile-harness-benchmark/strategy-ablation/runs" / RUN_ID
TRACES_DIR = OUTPUT_DIR / "strategy_traces"
CONTRACT_PATH = OUTPUT_DIR / "runtime_benchmark_upgrade_contract.json"
VERIFIER_PATH = OUTPUT_DIR / "runtime_benchmark_upgrade_verifier.json"
SCOREBOARD_PATH = OUTPUT_DIR / "runtime_benchmark_upgrade_scoreboard.csv"
SUMMARY_PATH = OUTPUT_DIR / "summary.md"
RUN_PATH = OUTPUT_DIR / "run.json"
CONTRACT_DOC = ROOT / "docs/mobile-harness-benchmark/strategy-ablation/p60-p62-runtime-benchmark-contract.md"


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def rel(path: Path) -> str:
    return p5.relative_to_root(path)


def load_json(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"Expected JSON object: {path}")
    return data


def contract_payload() -> dict[str, Any]:
    assertion_catalog = {
        "keyboard": {"state_proof": "visible_or_structured_state_change", "required_redaction": "none"},
        "tap": {"state_proof": "target_state_changed", "required_redaction": "coordinate_only_or_app_owned_label"},
        "swipe": {"state_proof": "scroll_drawer_or_canvas_state_changed", "required_redaction": "coordinate_only"},
        "set_text": {"state_proof": "value_or_app_state_changed", "required_redaction": "test_string_only"},
        "localStorage": {"state_proof": "key_roundtrip_or_refresh_persistence", "required_redaction": "no_user_payload"},
        "ui_xml": {"state_proof": "stable_app_owned_label_or_state_marker", "required_redaction": "third_party_text_removed"},
        "screenshot": {"state_proof": "nonblank_target_ui_not_launcher_or_error", "required_redaction": "no_sensitive_screen"},
        "logcat": {"state_proof": "fatal_anr_flutter_plugin_scan", "required_redaction": "app_scoped_or_sanitized"},
        "webview_state": {"state_proof": "url_dom_console_or_js_state_marker", "required_redaction": "app_owned_state_only"},
        "focus_state": {"state_proof": "foreground_package_activity_or_process", "required_redaction": "device_id_hash"},
    }
    taxonomy = [
        {
            "task_category": "ui_artifact",
            "required_assertions": ["keyboard", "tap", "screenshot", "logcat"],
            "evidence_refs": ["screenshot", "verifier_json"],
        },
        {
            "task_category": "webview_artifact",
            "required_assertions": ["keyboard", "tap", "set_text", "localStorage", "webview_state", "screenshot"],
            "evidence_refs": ["webview_state", "screenshot", "verifier_json"],
        },
        {
            "task_category": "phone_use_permission",
            "required_assertions": ["tap", "swipe", "set_text", "ui_xml", "logcat", "focus_state"],
            "evidence_refs": ["ui_xml", "logcat", "accessibility_state"],
        },
        {
            "task_category": "file_intake",
            "required_assertions": ["tap", "set_text", "ui_xml", "screenshot"],
            "evidence_refs": ["intake_log", "content_hash", "ui_xml"],
        },
        {
            "task_category": "local_runtime",
            "required_assertions": ["logcat", "screenshot", "focus_state"],
            "evidence_refs": ["runtime_report", "exit_code", "log_excerpt"],
        },
        {
            "task_category": "network_boundary",
            "required_assertions": ["logcat", "screenshot"],
            "evidence_refs": ["network_summary", "redaction_report"],
        },
        {
            "task_category": "recovery_task",
            "required_assertions": ["keyboard", "tap", "screenshot", "logcat"],
            "evidence_refs": ["strategy_trace", "blocked_reason", "recovery_action"],
        },
        {
            "task_category": "real_device_task",
            "required_assertions": ["tap", "swipe", "set_text", "ui_xml", "screenshot", "logcat", "focus_state"],
            "evidence_refs": ["install_log", "launch_log", "ui_xml", "screenshot", "logcat"],
        },
    ]
    score_dimensions = {
        "quality": 25,
        "runtime_correctness": 25,
        "phone_use_ability": 15,
        "recovery": 15,
        "latency_token": 10,
        "safety_privacy": 10,
    }
    communication_substrate = {
        "MailboxMessage": [
            "message_id",
            "from_role",
            "to_role",
            "task_id",
            "allowed_tools",
            "budget",
            "input_filter",
            "expected_return",
            "evidence_refs",
        ],
        "EvidenceLedgerEntry": [
            "evidence_id",
            "kind",
            "path",
            "producer_role",
            "redaction_state",
            "created_at",
            "summary",
        ],
        "RuntimeEvent": [
            "event_id",
            "source",
            "target",
            "action",
            "status",
            "timestamp",
            "evidence_id",
            "redaction_state",
        ],
        "MemoryCommitProposal": [
            "proposal_id",
            "source_trace",
            "content_summary",
            "ttl",
            "redaction_state",
            "approval_required",
        ],
    }
    role_contracts = {
        "CodeAgent": {
            "allowed_tools": ["read_file", "apply_patch", "format", "unit_test"],
            "budget": {"max_steps": 8},
            "input_filter": "code_files_and_scoped_task_only",
            "return_contract": ["patch_summary", "tests", "blockers"],
        },
        "RuntimeAgent": {
            "allowed_tools": ["adb", "devicectl", "browser_cdp", "webview_probe"],
            "budget": {"max_steps": 8},
            "input_filter": "runtime_target_and_evidence_policy",
            "return_contract": ["runtime_events", "screenshots", "logs"],
        },
        "PreviewAgent": {
            "allowed_tools": ["screenshot", "ui_xml", "webview_state"],
            "budget": {"max_steps": 6},
            "input_filter": "app_owned_ui_only",
            "return_contract": ["visual_state", "ui_markers", "blockers"],
        },
        "VerifierAgent": {
            "allowed_tools": ["validators", "static_checks", "runtime_assertions"],
            "budget": {"max_steps": 8},
            "input_filter": "artifacts_and_evidence_refs",
            "return_contract": ["pass_fail", "score_dimensions", "missing_evidence"],
        },
        "MemoryAgent": {
            "allowed_tools": ["memory_packet", "redaction", "proposal"],
            "budget": {"max_steps": 4},
            "input_filter": "summaries_only",
            "return_contract": ["proposal_or_noop_reason"],
        },
        "ReporterAgent": {
            "allowed_tools": ["evidence_ledger", "markdown_summary"],
            "budget": {"max_steps": 4},
            "input_filter": "verified_evidence_refs_only",
            "return_contract": ["public_safe_summary"],
        },
    }
    verifier_scaffold = {
        "verifier_json_required_fields": [
            "schema_version",
            "run_kind",
            "counts_as_experiment",
            "task_id",
            "task_category",
            "assertion_results",
            "score_dimensions",
            "device_evidence_refs",
            "webview_evidence_refs",
            "privacy_boundary",
            "blocked_reason",
        ],
        "non_counted_run_required_fields": [
            "run_kind",
            "counts_as_experiment",
            "counts_as_strategy_ablation_result",
            "evidence_boundary",
            "results",
            "summary",
        ],
        "android_webview_upgrade_assertions": [
            "ui_xml",
            "screenshot",
            "logcat",
            "webview_state",
            "focus_state",
            "accessibility_state",
        ],
    }
    return {
        "schema_version": "0.1.0",
        "contract_id": "p60_p62_runtime_benchmark_upgrade_contract",
        "run_kind": RUN_KIND,
        "counts_as_experiment": False,
        "counts_as_strategy_ablation_result": False,
        "task_taxonomy": taxonomy,
        "assertion_catalog": assertion_catalog,
        "score_dimensions": score_dimensions,
        "communication_substrate": communication_substrate,
        "role_contracts": role_contracts,
        "runtime_verifier_scaffold": verifier_scaffold,
        "next_android_real_device_lane_recommendation": {
            "status": "recommended_next",
            "required_evidence": [
                "apk_install",
                "launch_focus_state",
                "accessibility_authorization_state",
                "screenshot",
                "ui_xml",
                "app_scoped_logcat",
                "phone_use_dry_probe",
                "phone_use_action_probe",
                "webview_state_assertions",
            ],
            "boundary": "non_counted_until_repeated_task_samples_and_promotion_gate",
        },
    }


def verifier_payload(contract: dict[str, Any], created_at: str) -> dict[str, Any]:
    required_assertions = {
        "keyboard",
        "tap",
        "swipe",
        "set_text",
        "localStorage",
        "ui_xml",
        "screenshot",
        "logcat",
        "webview_state",
    }
    assertion_names = set(contract["assertion_catalog"])
    checks = {
        "contract_doc_exists": CONTRACT_DOC.exists(),
        "taxonomy_has_required_categories": len(contract["task_taxonomy"]) >= 8,
        "runtime_assertion_matrix_complete": required_assertions.issubset(assertion_names),
        "score_dimensions_complete": set(contract["score_dimensions"]) == {
            "quality",
            "runtime_correctness",
            "phone_use_ability",
            "recovery",
            "latency_token",
            "safety_privacy",
        },
        "score_weights_sum_100": sum(contract["score_dimensions"].values()) == 100,
        "mailbox_contract_present": "MailboxMessage" in contract["communication_substrate"],
        "evidence_ledger_contract_present": "EvidenceLedgerEntry" in contract["communication_substrate"],
        "runtime_event_bus_contract_present": "RuntimeEvent" in contract["communication_substrate"],
        "memory_commit_proposal_contract_present": "MemoryCommitProposal" in contract["communication_substrate"],
        "role_contracts_cover_six_roles": len(contract["role_contracts"]) == 6,
        "runtime_verifier_json_contract_present": bool(contract["runtime_verifier_scaffold"]["verifier_json_required_fields"]),
        "non_counted_run_contract_present": bool(contract["runtime_verifier_scaffold"]["non_counted_run_required_fields"]),
        "android_webview_upgrade_assertions_present": {
            "ui_xml",
            "logcat",
            "webview_state",
        }.issubset(set(contract["runtime_verifier_scaffold"]["android_webview_upgrade_assertions"])),
        "next_android_real_device_lane_recommendation_present": bool(
            contract["next_android_real_device_lane_recommendation"]["required_evidence"]
        ),
        "non_counted_boundary": contract["run_kind"] == RUN_KIND
        and contract["counts_as_experiment"] is False
        and contract["counts_as_strategy_ablation_result"] is False,
    }
    status = "passed" if all(checks.values()) else "blocked"
    return {
        "schema_version": "0.1.0",
        "verifier_id": "p60_p62_runtime_benchmark_upgrade_verifier",
        "created_at": created_at,
        "status": status,
        "run_kind": RUN_KIND,
        "counts_as_experiment": False,
        "counts_as_strategy_ablation_result": False,
        "scope": "P6.0 taxonomy, P6.1 communication substrate, and P6.2 runtime verifier scaffold contract only.",
        "score": {
            "score_boundary": "pilot_p60_p62_contract_score_not_counted",
            "total_score": 100.0 if status == "passed" else 0.0,
            "max_score": 100,
            "checks": checks,
            "blocked_reason": None if status == "passed" else "p60_p62_contract_checks_failed",
        },
        "contract": rel(CONTRACT_PATH),
        "contract_doc": rel(CONTRACT_DOC),
    }


def build_trace(strategy: dict[str, Any], task: dict[str, str], created_at: str) -> dict[str, Any]:
    return {
        "trace_id": f"strace_{RUN_ID}_{strategy['strategy_id']}_{task['task_id']}",
        "strategy_id": strategy["strategy_id"],
        "trace_status": BOUNDARY,
        "events": [
            {
                "event_id": "evt_001",
                "type": "contract_verify",
                "role": "RuntimeBenchmarkContractVerifier",
                "step_id": "step_001",
                "started_at": created_at,
                "ended_at": created_at,
                "tool_name": "p60_p62_contract_materializer",
                "evidence_id": f"{RUN_ID}_{strategy['strategy_id']}_{task['task_id']}",
                "summary": f"{task['phase']} contract scaffold materialized for {strategy['strategy_id']}.",
                "artifact_path": rel(VERIFIER_PATH),
            }
        ],
        "handoff_count": 0,
        "planning_revisions": 0,
        "verification_failures_recovered": 0,
        "failure_kind": None,
    }


def build_run(contract: dict[str, Any], verifier: dict[str, Any], registry: dict[str, Any]) -> dict[str, Any]:
    created_at = verifier["created_at"]
    strategies = registry["strategies"]
    results: list[dict[str, Any]] = []
    TRACES_DIR.mkdir(parents=True, exist_ok=True)
    for strategy in strategies:
        for task in TASKS:
            trace = build_trace(strategy, task, created_at)
            trace_path = TRACES_DIR / f"{strategy['strategy_id']}_{task['task_id']}.json"
            trace_path.write_text(json.dumps(trace, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
            result = {
                "strategy_id": strategy["strategy_id"],
                "strategy_family": strategy["strategy_family"],
                "task_id": task["task_id"],
                "task_category": task["task_category"],
                "status": verifier["status"],
                "strategy_trace": trace,
                "time_metrics": {
                    "planning_ms": 0,
                    "execution_ms": 0,
                    "verification_ms": 0,
                    "reporting_ms": 0,
                    "wall_ms": 0,
                },
                "token_metrics": {
                    "prompt_tokens": 0,
                    "completion_tokens": 0,
                    "estimated_tool_io_tokens": 0,
                    "total_tokens": 0,
                    "estimated_cost_usd": 0,
                    "tokens_per_verified_success": 0,
                },
                "effect_metrics": {
                    "task_success": 1.0 if verifier["status"] == "passed" else 0.0,
                    "verified_success": 1.0 if verifier["status"] == "passed" else 0.0,
                    "trace_completeness": 1.0,
                    "artifact_availability": 1.0,
                    "recovery_rate": None,
                    "human_intervention_count": 0,
                    "handoff_success_rate": None,
                    "memory_reuse_score": None,
                    "steps_to_completion": 1,
                },
                "evidence": {
                    "boundary": BOUNDARY,
                    "artifact_paths": [rel(CONTRACT_DOC), rel(CONTRACT_PATH)],
                    "trace_paths": [rel(trace_path)],
                    "screenshot_paths": [],
                    "logs": [
                        "P6.0-P6.2 runtime benchmark upgrade contract materialized.",
                        "Run is non-counted and must not be cited as a formal benchmark.",
                        "No model callback, device action, raw transcript, or secret material was used.",
                    ],
                    "verifier_outputs": [rel(VERIFIER_PATH)],
                    "transcript_paths": [],
                    "human_intervention_notes": [],
                },
                "pilot_verifier": {
                    "score_boundary": verifier["score"]["score_boundary"],
                    "verifier_output": rel(VERIFIER_PATH),
                },
                "pilot_score": verifier["score"],
                "contract_refs": {
                    "task_taxonomy": rel(CONTRACT_PATH),
                    "communication_substrate": rel(CONTRACT_PATH),
                    "runtime_verifier_scaffold": rel(CONTRACT_PATH),
                },
                "counts_as_strategy_ablation_result": False,
            }
            results.append(result)
    summary = {
        "total": len(results),
        "strategies": len(strategies),
        "tasks_per_strategy": len(TASKS),
        "passed": sum(1 for item in results if item["status"] == "passed"),
        "warning": sum(1 for item in results if item["status"] == "warning"),
        "failed": sum(1 for item in results if item["status"] == "failed"),
        "blocked": sum(1 for item in results if item["status"] == "blocked"),
        "average_pilot_score_not_counted": verifier["score"]["total_score"],
    }
    return {
        "benchmark": "MobileHarnessBench",
        "run_id": RUN_ID,
        "created_at": created_at,
        "counts_as_experiment": False,
        "counts_as_strategy_ablation_result": False,
        "run_kind": RUN_KIND,
        "schema_version": "0.1.0-p60-p62-runtime-benchmark-upgrade",
        "strategy_family": "mixed_strategy_ablation",
        "evidence_boundary": "pilot_not_counted:p60_p62_runtime_benchmark_upgrade_contract_not_counted",
        "environment": {
            "execution_tier": "P6.0-P6.2-contract-scaffold",
            "mode": RUN_KIND,
            "model_provider": "none",
            "model_name": "none",
            "runtime_backend": "contract_materializer_no_device_actions",
            "credential_source": "none",
        },
        "mode": {
            "name": "P6.0-P6.2 runtime benchmark upgrade",
            "mode": RUN_KIND,
            "non_counted_reason": "Contract/scaffold materialization only; no formal strategy benchmark.",
        },
        "strategies": [
            {
                "strategy_id": item["strategy_id"],
                "strategy_family": item["strategy_family"],
                "description": item["description"],
            }
            for item in strategies
        ],
        "task_subset": {
            "name": RUN_ID,
            "task_count": len(TASKS),
            "tasks": [
                {
                    "task_id": task["task_id"],
                    "task_category": task["task_category"],
                    "title": task["title"],
                    "max_score": 100,
                }
                for task in TASKS
            ],
        },
        "contract_summary": {
            "taxonomy_categories": len(contract["task_taxonomy"]),
            "runtime_assertions": sorted(contract["assertion_catalog"].keys()),
            "score_dimensions": contract["score_dimensions"],
            "communication_substrate_contracts": sorted(contract["communication_substrate"].keys()),
            "runtime_verifier_upgrade": contract["runtime_verifier_scaffold"]["android_webview_upgrade_assertions"],
        },
        "results": results,
        "summary": summary,
        "score_boundary": verifier["score"]["score_boundary"],
    }


def write_scoreboard(run: dict[str, Any]) -> None:
    with SCOREBOARD_PATH.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["task_id", "strategy_id", "status", "score", "counts_as_experiment"],
            lineterminator="\n",
        )
        writer.writeheader()
        for result in run["results"]:
            writer.writerow(
                {
                    "task_id": result["task_id"],
                    "strategy_id": result["strategy_id"],
                    "status": result["status"],
                    "score": result["pilot_score"]["total_score"],
                    "counts_as_experiment": False,
                }
            )


def write_summary(run: dict[str, Any], verifier: dict[str, Any]) -> None:
    lines = [
        "# P6.0-P6.2 Runtime Benchmark Upgrade",
        "",
        f"- run_id: `{run['run_id']}`",
        f"- run_kind: `{run['run_kind']}`",
        "- counts_as_experiment: `false`",
        "- counts_as_strategy_ablation_result: `false`",
        f"- status: `{verifier['status']}`",
        f"- score_boundary: `{verifier['score']['score_boundary']}`",
        f"- total_score_not_counted: `{verifier['score']['total_score']}`",
        "",
        "## Evidence",
        "",
        f"- Contract doc: `{rel(CONTRACT_DOC)}`",
        f"- Contract JSON: `{rel(CONTRACT_PATH)}`",
        f"- Verifier JSON: `{rel(VERIFIER_PATH)}`",
        f"- Scoreboard: `{rel(SCOREBOARD_PATH)}`",
        f"- Run JSON: `{rel(RUN_PATH)}`",
        "",
        "## Scope",
        "",
        "- P6.0 defines task taxonomy, runtime assertions, and score dimensions.",
        "- P6.1 defines mailbox, EvidenceLedger, RuntimeEventBus, MemoryCommitProposal, and role contracts.",
        "- P6.2 defines runtime verifier JSON and non-counted run contracts, with Android/WebView evidence hooks.",
        "- This run is a contract/scaffold proof only, not a formal benchmark.",
        "",
        "## Next P6.3 Android Real Device Lane",
        "",
        "Install the latest APK on a real Android device or dedicated emulator, verify Accessibility state, run Mobile Phone Use dry/action probes, capture screenshot/UI XML/logcat/focus state, and add WebView state assertions for generated artifacts. Keep the run non-counted until repeated samples and promotion gates pass.",
        "",
    ]
    SUMMARY_PATH.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    global OUTPUT_DIR, TRACES_DIR, CONTRACT_PATH, VERIFIER_PATH, SCOREBOARD_PATH, SUMMARY_PATH, RUN_PATH

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default=str(OUTPUT_DIR))
    args = parser.parse_args()
    output_dir = Path(args.output)
    OUTPUT_DIR = output_dir if output_dir.is_absolute() else ROOT / output_dir
    TRACES_DIR = OUTPUT_DIR / "strategy_traces"
    CONTRACT_PATH = OUTPUT_DIR / "runtime_benchmark_upgrade_contract.json"
    VERIFIER_PATH = OUTPUT_DIR / "runtime_benchmark_upgrade_verifier.json"
    SCOREBOARD_PATH = OUTPUT_DIR / "runtime_benchmark_upgrade_scoreboard.csv"
    SUMMARY_PATH = OUTPUT_DIR / "summary.md"
    RUN_PATH = OUTPUT_DIR / "run.json"
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    registry = load_json(REGISTRY_PATH)
    created_at = utc_now()
    contract = contract_payload()
    CONTRACT_PATH.write_text(json.dumps(contract, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    verifier = verifier_payload(contract, created_at)
    VERIFIER_PATH.write_text(json.dumps(verifier, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    run = build_run(contract, verifier, registry)
    RUN_PATH.write_text(json.dumps(run, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    write_scoreboard(run)
    write_summary(run, verifier)
    print(f"Wrote {rel(CONTRACT_PATH)}")
    print(f"Wrote {rel(VERIFIER_PATH)}")
    print(f"Wrote {rel(RUN_PATH)}")
    print(f"Status: {verifier['status']} score={verifier['score']['total_score']}")
    return 0 if verifier["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
