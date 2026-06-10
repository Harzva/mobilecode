#!/usr/bin/env python3
"""Validate the MobileHarnessBench seed task file with stdlib checks."""

from __future__ import annotations

import csv
import fnmatch
import json
import os
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BENCH_ROOT = ROOT / "docs" / "mobile-harness-benchmark"
PAPER_ROOT = ROOT / "paper" / "iclr-mobile-harness"
TASKS_PATH = ROOT / "docs" / "mobile-harness-benchmark" / "tasks" / "v0-seed-tasks.json"
V1_TASK_BANK_PATH = ROOT / "docs" / "mobile-harness-benchmark" / "tasks" / "v1-task-bank.json"
V2_TASK_BANK_PATH = ROOT / "docs" / "mobile-harness-benchmark" / "tasks" / "v2-task-bank.json"
FROZEN_SUBSET_PATH = ROOT / "docs" / "mobile-harness-benchmark" / "tasks" / "frozen-v2-paper-subset.json"
RUNS_ROOT = BENCH_ROOT / "runs"
BASELINES_ROOT = BENCH_ROOT / "baselines"
REPORTS_ROOT = BENCH_ROOT / "reports"
MAIN_PDF_PATH = PAPER_ROOT / "main.pdf"
CLAIM_LEDGER_PATH = REPORTS_ROOT / "paper-claim-evidence-ledger.json"
BASELINE_RUN_SCHEMA_PATH = BENCH_ROOT / "schema" / "baseline_run.schema.json"
VERIFIER_CONTRACTS_PATH = BENCH_ROOT / "verifiers" / "verifier-contracts.json"
REPRESENTATIVE_TASK_SET_PATH = BENCH_ROOT / "tasks" / "representative-v0.json"
V2_TASK_SET_PATHS = [
    BENCH_ROOT / "tasks" / "smoke-v2.json",
    BENCH_ROOT / "tasks" / "android-device-v2.json",
    BENCH_ROOT / "tasks" / "ios-simulator-v2.json",
]

REQUIRED_FIELDS = {
    "id",
    "category",
    "title",
    "user_goal",
    "input_fixture",
    "required_capabilities",
    "expected_artifacts",
    "verifiers",
    "evidence_requirements",
    "blocked_conditions",
}

SEED_CATEGORIES = {
    "file_intake",
    "code_edit",
    "preview_verification",
    "github_delivery",
    "harness_evidence",
}
V2_CATEGORIES = SEED_CATEGORIES | {"runtime_orchestration"}
V1_CATEGORY_COUNTS = {
    "file_intake": 40,
    "code_edit": 40,
    "preview_verification": 40,
    "github_delivery": 40,
    "harness_evidence": 40,
}
V2_CATEGORY_COUNTS = {
    "file_intake": 167,
    "code_edit": 167,
    "preview_verification": 167,
    "github_delivery": 167,
    "harness_evidence": 166,
    "runtime_orchestration": 166,
}

ID_RE = re.compile(r"^MH-[A-Z]{2}-[0-9]{3}$")
PUBLIC_BLOCKLIST = [
    re.compile(r"media_id", re.IGNORECASE),
    re.compile(r"access_token", re.IGNORECASE),
    re.compile(r"wechat_(appid|secret)", re.IGNORECASE),
    re.compile(r"\bopenid\b", re.IGNORECASE),
    re.compile(r"\b[a-zA-Z]:\\"),
    re.compile(r"sk-[A-Za-z0-9_-]{12,}"),
]
VALID_RESULT_STATUSES = {"passed", "warning", "failed", "blocked"}
BASELINE_IDS = {
    "chat_only_mobile_coding_flow",
    "desktop_remote_ide_flow",
    "mobile_harness_flow",
}
BASELINE_METRICS = {
    "task_success",
    "verified_success",
    "trace_completeness",
    "recovery_rate",
    "artifact_availability",
    "human_intervention_count",
    "steps_to_completion",
}
BASELINE_EVIDENCE_FIELDS = {
    "artifact_paths",
    "trace_paths",
    "screenshot_paths",
    "logs",
    "verifier_outputs",
    "transcript_paths",
    "human_intervention_notes",
}
BASELINE_PILOT_ROOT = BASELINES_ROOT / "2026-06-06-baseline-pilot-pack"
MODEL_LOCK_FIELDS = {
    "model_provider",
    "model_name",
    "model_version_or_snapshot",
    "temperature",
    "max_tokens",
    "system_prompt_hash",
    "task_prompt_hash",
    "operator_label",
    "run_started_at",
    "run_environment",
}
HUMAN_INTERVENTION_COLUMNS = [
    "baseline_id",
    "task_id",
    "intervention_index",
    "actor_role",
    "trigger",
    "action_taken",
    "duration_seconds",
    "counts_as_human_intervention",
    "notes",
]
REQUIRED_VERIFIER_CONTRACT_FIELDS = {
    "id",
    "category_scope",
    "description",
    "required_inputs",
    "required_evidence",
    "pass_conditions",
    "failure_kinds",
    "current_t0_support",
}


def _fs_path(path: Path) -> str:
    text = str(path)
    if not path.is_absolute():
        text = os.path.abspath(text)
    if os.name != "nt" or text.startswith("\\\\?\\"):
        return text
    if text.startswith("\\\\"):
        return "\\\\?\\UNC\\" + text[2:]
    return "\\\\?\\" + text


def _patch_pathlib_for_windows_long_paths() -> None:
    if os.name != "nt":
        return

    def exists(self: Path) -> bool:
        return os.path.exists(_fs_path(self))

    def is_file(self: Path) -> bool:
        return os.path.isfile(_fs_path(self))

    def is_dir(self: Path) -> bool:
        return os.path.isdir(_fs_path(self))

    def stat(self: Path, *, follow_symlinks: bool = True):
        return os.stat(_fs_path(self), follow_symlinks=follow_symlinks)

    def open_path(
        self: Path,
        mode: str = "r",
        buffering: int = -1,
        encoding: str | None = None,
        errors: str | None = None,
        newline: str | None = None,
    ):
        return open(_fs_path(self), mode, buffering=buffering, encoding=encoding, errors=errors, newline=newline)

    def read_text(self: Path, encoding: str | None = None, errors: str | None = None) -> str:
        with open_path(self, "r", encoding=encoding, errors=errors) as handle:
            return handle.read()

    def iterdir(self: Path):
        for name in os.listdir(_fs_path(self)):
            yield self / name

    def rglob(self: Path, pattern: str):
        base = _fs_path(self)
        for dirpath, dirnames, filenames in os.walk(base):
            for name in dirnames + filenames:
                full = os.path.join(dirpath, name)
                rel = os.path.relpath(full, base)
                if fnmatch.fnmatch(name, pattern) or fnmatch.fnmatch(rel.replace("\\", "/"), pattern):
                    yield self / Path(rel)

    Path.exists = exists  # type: ignore[method-assign]
    Path.is_file = is_file  # type: ignore[method-assign]
    Path.is_dir = is_dir  # type: ignore[method-assign]
    Path.stat = stat  # type: ignore[method-assign]
    Path.open = open_path  # type: ignore[method-assign]
    Path.read_text = read_text  # type: ignore[method-assign]
    Path.iterdir = iterdir  # type: ignore[method-assign]
    Path.rglob = rglob  # type: ignore[method-assign]


_patch_pathlib_for_windows_long_paths()


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def is_unzipped_anonymous_supplement() -> bool:
    return (ROOT / "README_SUPPLEMENT.md").exists() and (PAPER_ROOT / "main.tex").exists()


def validate_anonymous_supplement_readme() -> None:
    if not is_unzipped_anonymous_supplement():
        return
    readme_path = ROOT / "README_SUPPLEMENT.md"
    text = readme_path.read_text(encoding="utf-8")
    required_terms = [
        "Reviewer Checklist",
        "paper-claim-evidence-ledger.md",
        "evidence-maturity-matrix.md",
        "evaluation-protocol-readiness.md",
        "Claim Review Map",
        "System abstraction and design invariants",
        "Candidate task supply",
        "Non-counted readiness artifacts",
        "Submission blockers",
        "T0 fixture evidence only",
        "Evidence Label Quick Reference",
        "`candidate_supply`",
        "`t0_fixture_evidence`",
        "`capture_ready_no_results`",
        "`pilot_ready_no_results`",
        "`counts_as_experiment=false`",
        "`open_requirement`",
        "Do not report Android/iOS mobile-tier results",
    ]
    missing = [term for term in required_terms if term not in text]
    if missing:
        fail(f"README_SUPPLEMENT.md missing reviewer boundary terms: {missing}")


def ensure_list(task: dict, key: str) -> None:
    value = task.get(key)
    if not isinstance(value, list) or not value:
        fail(f"{task.get('id', '<missing id>')} field {key!r} must be a non-empty list")


def load_task_entries(path: Path) -> list[dict]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    tasks = payload.get("tasks") if isinstance(payload, dict) else payload
    if not isinstance(tasks, list):
        fail(f"{path.relative_to(ROOT)} must contain a task list")
    return tasks


def assert_public_safe(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    for pattern in PUBLIC_BLOCKLIST:
        match = pattern.search(text)
        if match:
            fail(f"{path.relative_to(ROOT)} contains public report sensitive marker: {match.group(0)!r}")


def validate_verifier_contract_catalog() -> tuple[int, int]:
    if not VERIFIER_CONTRACTS_PATH.exists():
        fail(f"missing verifier contract catalog: {VERIFIER_CONTRACTS_PATH.relative_to(ROOT)}")
    assert_public_safe(VERIFIER_CONTRACTS_PATH)
    catalog = json.loads(VERIFIER_CONTRACTS_PATH.read_text(encoding="utf-8"))
    if catalog.get("counts_as_experiment") is not False:
        fail(f"{VERIFIER_CONTRACTS_PATH.relative_to(ROOT)} must set counts_as_experiment=false")
    contracts = catalog.get("contracts")
    if not isinstance(contracts, list) or len(contracts) != 12:
        fail(f"{VERIFIER_CONTRACTS_PATH.relative_to(ROOT)} must contain twelve verifier contracts")
    contracts_by_id: dict[str, dict] = {}
    for contract in contracts:
        missing = REQUIRED_VERIFIER_CONTRACT_FIELDS - set(contract)
        if missing:
            fail(f"{VERIFIER_CONTRACTS_PATH.relative_to(ROOT)} {contract.get('id', '<missing id>')} missing fields: {sorted(missing)}")
        contract_id = contract["id"]
        if contract_id in contracts_by_id:
            fail(f"{VERIFIER_CONTRACTS_PATH.relative_to(ROOT)} duplicate contract id: {contract_id}")
        for key in REQUIRED_VERIFIER_CONTRACT_FIELDS - {"id", "description", "current_t0_support"}:
            if not isinstance(contract.get(key), list) or not contract[key]:
                fail(f"{VERIFIER_CONTRACTS_PATH.relative_to(ROOT)} {contract_id}.{key} must be a non-empty list")
        contracts_by_id[contract_id] = contract

    task_files = [
        ("v0 seed", TASKS_PATH, 25),
        ("v1 task bank", V1_TASK_BANK_PATH, 200),
        ("v2 task bank", V2_TASK_BANK_PATH, 1000),
    ]
    used_verifiers: Counter[str] = Counter()
    category_scope_violations: dict[str, list[str]] = defaultdict(list)
    task_count_checked = 0
    for label, path, expected_count in task_files:
        tasks = load_task_entries(path)
        if len(tasks) != expected_count:
            fail(f"{path.relative_to(ROOT)} {label} expected {expected_count} tasks; got {len(tasks)}")
        task_count_checked += len(tasks)
        for task in tasks:
            category = task.get("category")
            for verifier_id in task.get("verifiers", []):
                contract = contracts_by_id.get(verifier_id)
                if contract is None:
                    fail(f"{path.relative_to(ROOT)} {task.get('id')} references unknown verifier: {verifier_id}")
                used_verifiers[verifier_id] += 1
                if category not in contract["category_scope"]:
                    category_scope_violations[verifier_id].append(task.get("id"))
    if category_scope_violations:
        fail(f"verifier category scope violations: {dict(category_scope_violations)}")
    unused_contracts = sorted(set(contracts_by_id) - set(used_verifiers))
    if unused_contracts:
        fail(f"{VERIFIER_CONTRACTS_PATH.relative_to(ROOT)} has unused contracts: {unused_contracts}")
    return len(contracts_by_id), task_count_checked


def validate_run_dir(run_dir: Path, valid_task_ids: set[str]) -> None:
    run_json = run_dir / "run.json"
    summary_md = run_dir / "summary.md"
    traces_jsonl = run_dir / "traces.jsonl"
    for path in (run_json, summary_md, traces_jsonl):
        if not path.exists():
            fail(f"{run_dir.relative_to(ROOT)} missing required run file: {path.name}")
        assert_public_safe(path)

    payload = json.loads(run_json.read_text(encoding="utf-8"))
    results = payload.get("results")
    if not isinstance(results, list) or len(results) < 5:
        fail(f"{run_json.relative_to(ROOT)} must contain at least 5 verifier results")

    summary = payload.get("summary")
    if not isinstance(summary, dict):
        fail(f"{run_json.relative_to(ROOT)} missing summary object")
    if summary.get("total") != len(results):
        fail(f"{run_json.relative_to(ROOT)} summary.total does not match results length")

    status_counts: Counter[str] = Counter()
    for result in results:
        task_id = result.get("task_id")
        if task_id not in valid_task_ids:
            fail(f"{run_json.relative_to(ROOT)} has unknown task_id: {task_id}")
        status = result.get("status")
        if status not in VALID_RESULT_STATUSES:
            fail(f"{run_json.relative_to(ROOT)} has invalid status for {task_id}: {status}")
        status_counts[status] += 1
        checks = result.get("checks")
        if not isinstance(checks, list) or not checks:
            fail(f"{run_json.relative_to(ROOT)} {task_id} missing checks")
        evidence = result.get("evidence")
        if not isinstance(evidence, dict):
            fail(f"{run_json.relative_to(ROOT)} {task_id} missing evidence")
        for artifact in evidence.get("artifact_paths", []):
            if re.search(r"\b[a-zA-Z]:\\", artifact):
                fail(f"{run_json.relative_to(ROOT)} {task_id} contains absolute artifact path")
            artifact_path = ROOT / artifact
            if not artifact_path.exists():
                fail(f"{run_json.relative_to(ROOT)} {task_id} missing artifact path: {artifact}")

    for status in ("passed", "blocked", "failed", "warning"):
        if summary.get(status, 0) != status_counts[status]:
            fail(f"{run_json.relative_to(ROOT)} summary.{status} does not match result counts")

    trace_count = 0
    trace_task_ids: set[str] = set()
    for line_number, line in enumerate(traces_jsonl.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        trace_count += 1
        event = json.loads(line)
        task_id = event.get("task_id")
        if task_id not in valid_task_ids:
            fail(f"{traces_jsonl.relative_to(ROOT)} line {line_number} unknown task_id: {task_id}")
        trace_task_ids.add(task_id)
    result_task_ids = {result["task_id"] for result in results}
    if trace_task_ids != result_task_ids:
        fail(f"{traces_jsonl.relative_to(ROOT)} trace task ids do not match run results")
    if trace_count < len(results) * 3:
        fail(f"{traces_jsonl.relative_to(ROOT)} has too few trace events")


def validate_runs(valid_task_ids: set[str]) -> int:
    if not RUNS_ROOT.exists():
        return 0
    run_dirs = [path for path in RUNS_ROOT.iterdir() if path.is_dir()]
    for run_dir in sorted(run_dirs):
        validate_run_dir(run_dir, valid_task_ids)
    return len(run_dirs)


def validate_reports() -> int:
    if not REPORTS_ROOT.exists():
        return 0
    report_paths = sorted(
        path for path in REPORTS_ROOT.iterdir() if path.is_file() and path.suffix.lower() in {".json", ".md"}
    )
    for path in report_paths:
        assert_public_safe(path)
        if path.name == "mobile-tier-readiness.json":
            payload = json.loads(path.read_text(encoding="utf-8"))
            if payload.get("counts_as_experiment") is not False:
                fail(f"{path.relative_to(ROOT)} must set counts_as_experiment=false")
            for task_set in ("android-device-v2", "ios-simulator-v2"):
                if task_set not in payload.get("task_sets", {}):
                    fail(f"{path.relative_to(ROOT)} missing task set readiness entry: {task_set}")
            for platform in ("android", "ios"):
                status = payload.get(platform, {}).get("status")
                if status not in {
                    "blocked",
                    "ready_for_manual_t2_collection",
                    "ready_for_manual_t3_collection",
                }:
                    fail(f"{path.relative_to(ROOT)} invalid {platform} readiness status: {status}")
        if path.name == "mobile-evidence-pack-readiness.json":
            payload = json.loads(path.read_text(encoding="utf-8"))
            if payload.get("status") != "capture_ready_no_results":
                fail(f"{path.relative_to(ROOT)} must be capture_ready_no_results")
            if payload.get("counts_as_experiment") is not False:
                fail(f"{path.relative_to(ROOT)} must set counts_as_experiment=false")
            if payload.get("counts_as_mobile_experiment") is not False:
                fail(f"{path.relative_to(ROOT)} must set counts_as_mobile_experiment=false")
            if payload.get("ready_for_capture") is not True:
                fail(f"{path.relative_to(ROOT)} must be ready for capture")
            if payload.get("ready_for_counted_mobile_experiment") is not False:
                fail(f"{path.relative_to(ROOT)} must not be ready for counted mobile experiment")
            if payload.get("task_set_count") != 2:
                fail(f"{path.relative_to(ROOT)} must cover two mobile task sets")
            if payload.get("task_count") != 48:
                fail(f"{path.relative_to(ROOT)} must cover 48 mobile-tier tasks")
            if payload.get("template_count") != 53:
                fail(f"{path.relative_to(ROOT)} must cover 53 capture templates")
            expected_open = {
                "execute_android_t2_real_device_run",
                "execute_ios_t3_simulator_run",
                "fill_device_metadata_and_task_evidence",
                "attach_verifier_outputs_traces_screenshots_and_logs",
                "pass_public_output_safety_scan",
            }
            if set(payload.get("open_requirements", [])) != expected_open:
                fail(f"{path.relative_to(ROOT)} open requirements mismatch")
            task_sets = {entry.get("task_set"): entry for entry in payload.get("task_sets", [])}
            expected_task_sets = {
                "android-device-v2": ("T2-android-real-device", 30, 30),
                "ios-simulator-v2": ("T3-ios-simulator", 18, 0),
            }
            if set(task_sets) != set(expected_task_sets):
                fail(f"{path.relative_to(ROOT)} task sets mismatch")
            for task_set, (tier, task_count, real_device_count) in expected_task_sets.items():
                entry = task_sets[task_set]
                if entry.get("test_tier") != tier:
                    fail(f"{path.relative_to(ROOT)} {task_set} tier mismatch")
                if entry.get("task_count") != task_count:
                    fail(f"{path.relative_to(ROOT)} {task_set} task count mismatch")
                if entry.get("requires_real_device_count") != real_device_count:
                    fail(f"{path.relative_to(ROOT)} {task_set} real-device count mismatch")
                template_dir = entry.get("template_dir")
                if not template_dir or not (ROOT / template_dir).exists():
                    fail(f"{path.relative_to(ROOT)} {task_set} missing template_dir")
            for artifact in payload.get("evidence_artifacts", []):
                if not (ROOT / artifact).exists():
                    fail(f"{path.relative_to(ROOT)} missing evidence artifact: {artifact}")
            pack_manifest_path = ROOT / payload.get("evidence_artifacts", [""])[0]
            manifest = json.loads(pack_manifest_path.read_text(encoding="utf-8"))
            if manifest.get("status") != "capture_ready_no_results":
                fail(f"{pack_manifest_path.relative_to(ROOT)} must be capture_ready_no_results")
            if manifest.get("counts_as_mobile_experiment") is not False:
                fail(f"{pack_manifest_path.relative_to(ROOT)} must not count as mobile experiment")
            template_paths = manifest.get("template_paths")
            if not isinstance(template_paths, list) or len(template_paths) != 53:
                fail(f"{pack_manifest_path.relative_to(ROOT)} must contain 53 template paths")
            playbook_path = manifest.get("execution_playbook_path")
            if not playbook_path or not (ROOT / playbook_path).exists():
                fail(f"{pack_manifest_path.relative_to(ROOT)} missing execution_playbook_path")
            playbook_text = (ROOT / playbook_path).read_text(encoding="utf-8")
            for required_term in ("Execution Order", "Promotion Rule", "Non-Result Boundary", "Counts as result"):
                if required_term not in playbook_text:
                    fail(f"{Path(playbook_path).as_posix()} missing playbook term: {required_term}")
            for template in template_paths:
                template_path = ROOT / template
                if not template_path.exists():
                    fail(f"{pack_manifest_path.relative_to(ROOT)} missing template: {template}")
                if template_path.suffix == ".json":
                    template_payload = json.loads(template_path.read_text(encoding="utf-8"))
                    if template_payload.get("counts_as_mobile_experiment") is not False:
                        fail(f"{template_path.relative_to(ROOT)} must set counts_as_mobile_experiment=false")
        if path.name == "evidence-maturity-matrix.json":
            payload = json.loads(path.read_text(encoding="utf-8"))
            if payload.get("status") != "passed_with_open_requirements":
                fail(f"{path.relative_to(ROOT)} must be passed_with_open_requirements")
            if payload.get("stage_count") != 7:
                fail(f"{path.relative_to(ROOT)} must contain seven maturity stages")
            if payload.get("max_stage_level") != 6:
                fail(f"{path.relative_to(ROOT)} max stage level must be 6")
            if payload.get("current_max_counted_paper_evidence_level") != 1:
                fail(f"{path.relative_to(ROOT)} only T0 evidence may count as paper evidence")
            if payload.get("counted_mobile_stage_ids") != []:
                fail(f"{path.relative_to(ROOT)} must have zero counted mobile stages")
            if payload.get("counted_baseline_stage_ids") != []:
                fail(f"{path.relative_to(ROOT)} must have zero counted baseline stages")
            stages = payload.get("stages")
            if not isinstance(stages, list) or len(stages) != 7:
                fail(f"{path.relative_to(ROOT)} stages must contain seven entries")
            stage_by_id = {stage.get("id"): stage for stage in stages}
            required_stage_ids = {
                "M0_candidate_supply",
                "M1_t0_fixture_runs",
                "M2_frozen_subset_planning",
                "M3_mobile_tier_readiness",
                "M4_baseline_protocol_contract",
                "M5_baseline_pilot_ready",
                "M6_counted_mobile_or_baseline_results",
            }
            if set(stage_by_id) != required_stage_ids:
                fail(f"{path.relative_to(ROOT)} stage ids mismatch")
            if stage_by_id["M1_t0_fixture_runs"].get("counts_as_paper_evidence") is not True:
                fail(f"{path.relative_to(ROOT)} T0 fixture stage must count as paper evidence")
            for stage_id, stage in stage_by_id.items():
                if stage.get("counts_as_mobile_experiment") is not False:
                    fail(f"{path.relative_to(ROOT)} {stage_id} must not count as mobile experiment")
                if stage.get("counts_as_baseline_result") is not False:
                    fail(f"{path.relative_to(ROOT)} {stage_id} must not count as baseline result")
                artifacts = stage.get("evidence_artifacts")
                if not isinstance(artifacts, list) or not artifacts:
                    fail(f"{path.relative_to(ROOT)} {stage_id} missing evidence_artifacts")
                for artifact in artifacts:
                    if not (ROOT / artifact).exists():
                        fail(f"{path.relative_to(ROOT)} {stage_id} missing artifact: {artifact}")
            open_requirements = set(payload.get("open_requirements", []))
            if open_requirements != {"M6_counted_mobile_or_baseline_results"}:
                fail(f"{path.relative_to(ROOT)} open requirements mismatch")
        if path.name == "paper-claim-evidence-ledger.json":
            payload = json.loads(path.read_text(encoding="utf-8"))
            if payload.get("status") != "passed_with_open_requirements":
                fail(f"{path.relative_to(ROOT)} must be passed_with_open_requirements")
            claims = payload.get("claims")
            if not isinstance(claims, list) or len(claims) < 6:
                fail(f"{path.relative_to(ROOT)} must contain at least 6 claims")
            claims_by_id = {claim.get("id"): claim for claim in claims}
            required_claims = {
                "v2_candidate_bank",
                "representative_v0_t0_run",
                "smoke_v2_t0_run",
                "draft_frozen_paper_subset",
                "mobile_tier_readiness",
                "real_mobile_and_baseline_results",
            }
            missing_claims = required_claims - set(claims_by_id)
            if missing_claims:
                fail(f"{path.relative_to(ROOT)} missing claims: {sorted(missing_claims)}")
            if claims_by_id["v2_candidate_bank"]["validated_values"].get("task_count") != 1000:
                fail(f"{path.relative_to(ROOT)} v2 candidate claim must record 1000 tasks")
            if claims_by_id["smoke_v2_t0_run"]["validated_values"].get("total") != 60:
                fail(f"{path.relative_to(ROOT)} smoke-v2 claim must record 60 tasks")
            if claims_by_id["representative_v0_t0_run"].get("counts_as_paper_evidence") is not True:
                fail(f"{path.relative_to(ROOT)} representative-v0 T0 claim must count as paper evidence")
            if claims_by_id["smoke_v2_t0_run"].get("counts_as_paper_evidence") is not True:
                fail(f"{path.relative_to(ROOT)} smoke-v2 T0 claim must count as paper evidence")
            frozen_values = claims_by_id["draft_frozen_paper_subset"]["validated_values"]
            if frozen_values.get("task_count") != 60:
                fail(f"{path.relative_to(ROOT)} frozen subset claim must record 60 tasks")
            if frozen_values.get("counts_as_final_paper_subset") is not False:
                fail(f"{path.relative_to(ROOT)} frozen subset claim must not count as final")
            if claims_by_id["mobile_tier_readiness"]["validated_values"].get("counts_as_experiment") is not False:
                fail(f"{path.relative_to(ROOT)} mobile readiness claim must be non-experimental")
            if claims_by_id["real_mobile_and_baseline_results"].get("status") != "open_requirement":
                fail(f"{path.relative_to(ROOT)} real mobile/baseline claim must remain an open requirement")
            baseline_values = claims_by_id["real_mobile_and_baseline_results"]["validated_values"]
            if baseline_values.get("baseline_protocol_defined") is not True:
                fail(f"{path.relative_to(ROOT)} baseline protocol must be marked as defined")
            if baseline_values.get("baseline_protocol_status") != "protocol_defined_no_results":
                fail(f"{path.relative_to(ROOT)} baseline protocol must not report results")
            if baseline_values.get("baseline_count") != 3:
                fail(f"{path.relative_to(ROOT)} baseline protocol must define three baselines")
            if baseline_values.get("baseline_run_contract_defined") is not True:
                fail(f"{path.relative_to(ROOT)} baseline run contract must be marked as defined")
            if baseline_values.get("baseline_run_contract_status") != "contract_defined_no_results":
                fail(f"{path.relative_to(ROOT)} baseline run contract must not report results")
            if baseline_values.get("baseline_run_contract_result_count") != 0:
                fail(f"{path.relative_to(ROOT)} baseline run contract must have zero results")
            if baseline_values.get("baseline_dry_run_available") is not True:
                fail(f"{path.relative_to(ROOT)} baseline dry run must be marked as available")
            if baseline_values.get("baseline_dry_run_status") != "dry_run_not_counted":
                fail(f"{path.relative_to(ROOT)} baseline dry run must not count as a result")
            if baseline_values.get("baseline_dry_run_task_count_per_baseline") != 1:
                fail(f"{path.relative_to(ROOT)} baseline dry run must cover one task per baseline")
            if baseline_values.get("baseline_dry_run_counts_as_result") is not False:
                fail(f"{path.relative_to(ROOT)} baseline dry run counts_as_result must be false")
            if baseline_values.get("baseline_pilot_pack_available") is not True:
                fail(f"{path.relative_to(ROOT)} baseline pilot pack must be marked as available")
            if baseline_values.get("baseline_pilot_pack_status") != "pilot_ready_no_results":
                fail(f"{path.relative_to(ROOT)} baseline pilot pack must not count as a result")
            if baseline_values.get("baseline_pilot_pack_task_count_per_baseline") != 1:
                fail(f"{path.relative_to(ROOT)} baseline pilot pack must cover one task per baseline")
            if baseline_values.get("baseline_pilot_pack_counts_as_result") is not False:
                fail(f"{path.relative_to(ROOT)} baseline pilot pack counts_as_result must be false")
            if baseline_values.get("baseline_pilot_readiness_status") != "pilot_ready_no_results":
                fail(f"{path.relative_to(ROOT)} baseline pilot readiness must not count as a result")
            if baseline_values.get("baseline_pilot_ready_for_execution") is not True:
                fail(f"{path.relative_to(ROOT)} baseline pilot readiness must be ready for non-counted execution")
            if baseline_values.get("baseline_pilot_ready_for_counted_result") is not False:
                fail(f"{path.relative_to(ROOT)} baseline pilot readiness must not be ready for counted result")
            for claim in claims:
                if claim.get("counts_as_mobile_experiment") is not False:
                    fail(f"{path.relative_to(ROOT)} {claim.get('id')} must not count as a mobile experiment yet")
                artifacts = claim.get("evidence_artifacts")
                if not isinstance(artifacts, list) or not artifacts:
                    fail(f"{path.relative_to(ROOT)} {claim.get('id')} missing evidence_artifacts")
                for artifact in artifacts:
                    artifact_path = ROOT / artifact
                    if not artifact_path.exists():
                        fail(f"{path.relative_to(ROOT)} {claim.get('id')} missing evidence artifact: {artifact}")
        if path.name == "submission-readiness.json":
            payload = json.loads(path.read_text(encoding="utf-8"))
            if payload.get("status") != "passed_with_open_requirements":
                fail(f"{path.relative_to(ROOT)} must be passed_with_open_requirements")
            if payload.get("ready_for_submission_upload") is not False:
                fail(f"{path.relative_to(ROOT)} must not mark the draft as upload-ready")
            if payload.get("ready_for_counted_mobile_experiment") is not False:
                fail(f"{path.relative_to(ROOT)} must not mark mobile experiments as counted")
            if payload.get("ready_for_counted_baseline_result") is not False:
                fail(f"{path.relative_to(ROOT)} must not mark baseline results as counted")
            if payload.get("gate_count") != 16:
                fail(f"{path.relative_to(ROOT)} must contain sixteen submission-readiness gates")
            open_gate_ids = set(payload.get("open_gate_ids", []))
            expected_open_gate_ids = {
                "S2_mobile_experiment_boundary",
                "S4_baseline_result_boundary",
                "S6_submission_metadata",
            }
            if open_gate_ids != expected_open_gate_ids:
                fail(f"{path.relative_to(ROOT)} open gate ids mismatch")
            open_requirements = set(payload.get("open_requirements", []))
            expected_open_requirements = {
                "venue_template_author_confirmation",
                "real_android_or_ios_mobile_tier_evidence",
                "counted_baseline_comparison_results",
                "final_anonymous_supplement_after_new_evidence",
            }
            if open_requirements != expected_open_requirements:
                fail(f"{path.relative_to(ROOT)} open requirements mismatch")
            gates = payload.get("gates")
            if not isinstance(gates, list) or len(gates) != 16:
                fail(f"{path.relative_to(ROOT)} gates must contain sixteen entries")
            gate_ids = {gate.get("id") for gate in gates}
            expected_gate_ids = {
                "S0_manuscript_artifacts",
                "S1_claim_evidence_boundary",
                "S1a_core_claim_positioning",
                "S2_mobile_experiment_boundary",
                "S3_mobile_evidence_capture_pack",
                "S3a_verifier_contract_readiness",
                "S4_baseline_result_boundary",
                "S5_anonymous_supplement_boundary",
                "S5a_reviewer_manifest_gate",
                "S6_submission_metadata",
                "S7_bibliography_metadata",
                "S8_threats_to_validity",
                "S9_evaluation_protocol_readiness",
                "S9a_method_presentation_readiness",
                "S10_reproducibility_checklist",
                "S11_page_limit_readiness",
            }
            if gate_ids != expected_gate_ids:
                fail(f"{path.relative_to(ROOT)} gate ids mismatch")
            for gate_item in gates:
                artifacts = gate_item.get("evidence_artifacts")
                if not isinstance(artifacts, list) or not artifacts:
                    fail(f"{path.relative_to(ROOT)} {gate_item.get('id')} missing evidence_artifacts")
                for artifact in artifacts:
                    artifact_path = ROOT / artifact
                    if not artifact_path.exists():
                        fail(f"{path.relative_to(ROOT)} {gate_item.get('id')} missing evidence artifact: {artifact}")
        if path.name == "core-claim-readiness.json":
            payload = json.loads(path.read_text(encoding="utf-8"))
            if payload.get("status") != "passed_with_open_requirements":
                fail(f"{path.relative_to(ROOT)} must be passed_with_open_requirements")
            if payload.get("claim_count") != 4:
                fail(f"{path.relative_to(ROOT)} must contain four core claims")
            if payload.get("counts_as_experiment") is not False:
                fail(f"{path.relative_to(ROOT)} must not count as experiment")
            if payload.get("paper_positioning_checked") is not True:
                fail(f"{path.relative_to(ROOT)} must check paper positioning")
            expected_claim_ids = {
                "C1_not_full_mobile_ide",
                "C2_harness_is_research_object",
                "C3_not_general_phone_use_benchmark",
                "C4_evidence_first_counting",
            }
            claims = payload.get("claims")
            if not isinstance(claims, list) or len(claims) != 4:
                fail(f"{path.relative_to(ROOT)} claims must contain four entries")
            claims_by_id = {entry.get("id"): entry for entry in claims}
            if set(claims_by_id) != expected_claim_ids:
                fail(f"{path.relative_to(ROOT)} claim ids mismatch")
            for claim_id, claim_item in claims_by_id.items():
                if claim_item.get("status") != "supported_as_positioning_claim":
                    fail(f"{path.relative_to(ROOT)} {claim_id} status mismatch")
                if claim_item.get("counts_as_experiment") is not False:
                    fail(f"{path.relative_to(ROOT)} {claim_id} must not count as experiment")
                terms = claim_item.get("paper_terms")
                if not isinstance(terms, list) or not terms:
                    fail(f"{path.relative_to(ROOT)} {claim_id} missing paper terms")
                artifacts = claim_item.get("evidence_artifacts")
                if not isinstance(artifacts, list) or not artifacts:
                    fail(f"{path.relative_to(ROOT)} {claim_id} missing evidence artifacts")
                for artifact in artifacts:
                    if not (ROOT / artifact).exists():
                        fail(f"{path.relative_to(ROOT)} {claim_id} missing evidence artifact: {artifact}")
        if path.name == "evaluation-protocol-readiness.json":
            payload = json.loads(path.read_text(encoding="utf-8"))
            if payload.get("status") != "passed_with_open_requirements":
                fail(f"{path.relative_to(ROOT)} must be passed_with_open_requirements")
            if payload.get("protocol_count") != 5:
                fail(f"{path.relative_to(ROOT)} must cover E1-E5")
            if payload.get("evaluation_section_checked") is not True:
                fail(f"{path.relative_to(ROOT)} must check the paper evaluation section")
            if payload.get("metric_contract_checked") is not True:
                fail(f"{path.relative_to(ROOT)} must check the metric contract")
            if payload.get("metric_count") != 7:
                fail(f"{path.relative_to(ROOT)} must cover seven primary metrics")
            if set(payload.get("primary_metrics", [])) != BASELINE_METRICS:
                fail(f"{path.relative_to(ROOT)} primary metrics mismatch")
            if payload.get("counts_as_complete_evaluation") is not False:
                fail(f"{path.relative_to(ROOT)} must not mark the evaluation complete")
            if payload.get("ready_for_counted_mobile_experiment") is not False:
                fail(f"{path.relative_to(ROOT)} must not mark mobile experiments as counted")
            if payload.get("ready_for_counted_baseline_result") is not False:
                fail(f"{path.relative_to(ROOT)} must not mark baseline results as counted")
            expected_protocol_ids = {
                "E1_t0_smoke_v2",
                "E2_android_real_device_subset",
                "E3_ios_simulator_subset",
                "E4_github_sandbox_delivery",
                "E5_baseline_comparison",
            }
            if payload.get("counted_protocol_ids") != ["E1_t0_smoke_v2"]:
                fail(f"{path.relative_to(ROOT)} counted_protocol_ids mismatch")
            protocols = payload.get("protocols")
            if not isinstance(protocols, list) or len(protocols) != 5:
                fail(f"{path.relative_to(ROOT)} protocols must contain five entries")
            protocols_by_id = {entry.get("id"): entry for entry in protocols}
            if set(protocols_by_id) != expected_protocol_ids:
                fail(f"{path.relative_to(ROOT)} protocol ids mismatch")
            expected_statuses = {
                "E1_t0_smoke_v2": "counted_t0_fixture_evidence_available",
                "E2_android_real_device_subset": "capture_ready_no_results",
                "E3_ios_simulator_subset": "capture_ready_no_results",
                "E4_github_sandbox_delivery": "protocol_defined_t0_blocked_no_remote_write",
                "E5_baseline_comparison": "protocol_defined_pilot_ready_no_results",
            }
            for protocol_id, expected_status in expected_statuses.items():
                protocol = protocols_by_id[protocol_id]
                if protocol.get("status") != expected_status:
                    fail(f"{path.relative_to(ROOT)} {protocol_id} status mismatch")
                if protocol.get("counts_as_mobile_experiment") is not False:
                    fail(f"{path.relative_to(ROOT)} {protocol_id} must not count as mobile experiment")
                if protocol.get("counts_as_baseline_result") is not False:
                    fail(f"{path.relative_to(ROOT)} {protocol_id} must not count as baseline result")
                artifacts = protocol.get("evidence_artifacts")
                if not isinstance(artifacts, list) or not artifacts:
                    fail(f"{path.relative_to(ROOT)} {protocol_id} missing evidence_artifacts")
                for artifact in artifacts:
                    if not (ROOT / artifact).exists():
                        fail(f"{path.relative_to(ROOT)} {protocol_id} missing evidence artifact: {artifact}")
            smoke_summary = protocols_by_id["E1_t0_smoke_v2"].get("summary", {}).get("run", {}).get("summary", {})
            if smoke_summary.get("total") != 60 or smoke_summary.get("passed") != 50 or smoke_summary.get("blocked") != 10 or smoke_summary.get("failed") != 0:
                fail(f"{path.relative_to(ROOT)} E1 smoke summary mismatch")
        if path.name == "page-limit-readiness.json":
            payload = json.loads(path.read_text(encoding="utf-8"))
            if payload.get("status") != "passed":
                fail(f"{path.relative_to(ROOT)} must be passed")
            if payload.get("main_text_page_limit") != 9:
                fail(f"{path.relative_to(ROOT)} must use nine-page main text limit")
            if payload.get("within_main_text_limit") is not True:
                fail(f"{path.relative_to(ROOT)} must keep main text within the page limit")
            if payload.get("references_are_unlimited") is not True:
                fail(f"{path.relative_to(ROOT)} must record citations as unlimited")
            if payload.get("counts_as_experiment") is not False:
                fail(f"{path.relative_to(ROOT)} must not count as experiment")
            references_start_page = payload.get("references_start_page")
            if not isinstance(references_start_page, int) or references_start_page < 1:
                fail(f"{path.relative_to(ROOT)} missing valid references_start_page")
            if references_start_page > payload.get("main_text_page_limit"):
                fail(f"{path.relative_to(ROOT)} references start after the main text limit")
            if payload.get("main_text_with_ethics_pages_upper_bound") != references_start_page:
                fail(f"{path.relative_to(ROOT)} main text upper bound must match references start page")
            if payload.get("actual_pdf_file_bytes") != MAIN_PDF_PATH.stat().st_size:
                fail(f"{path.relative_to(ROOT)} actual PDF byte count mismatch")
            if payload.get("pdf_file_bytes") != MAIN_PDF_PATH.stat().st_size:
                fail(f"{path.relative_to(ROOT)} pdfinfo byte count mismatch")
            for artifact in payload.get("evidence_artifacts", []):
                if not (ROOT / artifact).exists():
                    fail(f"{path.relative_to(ROOT)} missing evidence artifact: {artifact}")
        if path.name == "reproducibility-checklist.json":
            payload = json.loads(path.read_text(encoding="utf-8"))
            if payload.get("status") != "passed_with_open_requirements":
                fail(f"{path.relative_to(ROOT)} must be passed_with_open_requirements")
            if payload.get("command_count") != 16:
                fail(f"{path.relative_to(ROOT)} must contain sixteen commands")
            if payload.get("counts_as_experiment") is not False:
                fail(f"{path.relative_to(ROOT)} must not count as experiment")
            if payload.get("ready_for_draft_reproduction") is not True:
                fail(f"{path.relative_to(ROOT)} must mark draft reproduction ready")
            if payload.get("ready_for_full_empirical_reproduction") is not False:
                fail(f"{path.relative_to(ROOT)} must not mark full empirical reproduction ready")
            expected_command_ids = {
                "R0_generate_task_bank",
                "R1_audit_task_bank",
                "R2_run_offline_smoke",
                "R3_generate_mobile_readiness",
                "R4_generate_mobile_capture_pack",
                "R5_generate_verifier_contract_readiness",
                "R6_generate_baseline_readiness",
                "R7_generate_claim_reports",
                "R8_generate_evidence_protocol_reports",
                "R9_generate_bibliography_and_threats",
                "R10_generate_method_presentation_readiness",
                "R11_compile_paper",
                "R12_generate_page_limit_readiness",
                "R13_generate_submission_readiness",
                "R14_stage_anonymous_supplement",
                "R15_validate_benchmark",
            }
            commands = payload.get("commands")
            if not isinstance(commands, list) or len(commands) != 16:
                fail(f"{path.relative_to(ROOT)} commands must contain sixteen entries")
            commands_by_id = {entry.get("id"): entry for entry in commands}
            if set(commands_by_id) != expected_command_ids:
                fail(f"{path.relative_to(ROOT)} command ids mismatch")
            for command_id, command_item in commands_by_id.items():
                if command_item.get("status") != "ready":
                    fail(f"{path.relative_to(ROOT)} {command_id} must be ready")
                if command_item.get("counts_as_experiment") is not False:
                    fail(f"{path.relative_to(ROOT)} {command_id} must not count as experiment")
                outputs = command_item.get("expected_outputs")
                if not isinstance(outputs, list) or not outputs:
                    fail(f"{path.relative_to(ROOT)} {command_id} missing expected_outputs")
                for output in outputs:
                    if not (ROOT / output).exists():
                        if (
                            command_id == "R14_stage_anonymous_supplement"
                            and output == "paper/iclr-mobile-harness/build/mobile-harness-anonymous-supplement.zip"
                            and is_unzipped_anonymous_supplement()
                        ):
                            continue
                        fail(f"{path.relative_to(ROOT)} {command_id} missing expected output: {output}")
        if path.name == "method-presentation-readiness.json":
            payload = json.loads(path.read_text(encoding="utf-8"))
            if payload.get("status") != "passed":
                fail(f"{path.relative_to(ROOT)} must be passed")
            if payload.get("ready_for_method_review") is not True:
                fail(f"{path.relative_to(ROOT)} must mark method review ready")
            if payload.get("counts_as_experiment") is not False:
                fail(f"{path.relative_to(ROOT)} must not count as experiment")
            if payload.get("check_count") != 5:
                fail(f"{path.relative_to(ROOT)} must contain five checks")
            counts = payload.get("method_surface_counts")
            if not isinstance(counts, dict):
                fail(f"{path.relative_to(ROOT)} missing method_surface_counts")
            if counts.get("figures", 0) < 2:
                fail(f"{path.relative_to(ROOT)} must detect at least two figures")
            if counts.get("tables", 0) < 4:
                fail(f"{path.relative_to(ROOT)} must detect at least four tables")
            if counts.get("algorithm_markers") != 4:
                fail(f"{path.relative_to(ROOT)} must detect four algorithm markers")
            if counts.get("display_math_blocks", 0) < 8:
                fail(f"{path.relative_to(ROOT)} must detect enough display math blocks")
            if counts.get("equation_symbols", 0) < 12:
                fail(f"{path.relative_to(ROOT)} must detect the formula contract terms")
            expected_check_ids = {
                "MP1_visual_scaffolding",
                "MP2_algorithmic_methods",
                "MP3_module_interfaces",
                "MP4_formula_contracts",
                "MP5_evidence_boundaries",
            }
            checks = payload.get("checks")
            if not isinstance(checks, list) or len(checks) != 5:
                fail(f"{path.relative_to(ROOT)} checks must contain five entries")
            checks_by_id = {entry.get("id"): entry for entry in checks}
            if set(checks_by_id) != expected_check_ids:
                fail(f"{path.relative_to(ROOT)} check ids mismatch")
            for check_id, check_item in checks_by_id.items():
                if check_item.get("status") != "passed":
                    fail(f"{path.relative_to(ROOT)} {check_id} must pass")
                if check_item.get("counts_as_experiment") is not False:
                    fail(f"{path.relative_to(ROOT)} {check_id} must not count as experiment")
                terms = check_item.get("required_terms")
                if not isinstance(terms, list) or not terms:
                    fail(f"{path.relative_to(ROOT)} {check_id} missing required_terms")
            expected_open = {
                "real_android_or_ios_mobile_tier_evidence",
                "counted_baseline_comparison_results",
                "venue_template_author_confirmation",
            }
            if set(payload.get("open_requirements", [])) != expected_open:
                fail(f"{path.relative_to(ROOT)} open requirements mismatch")
            for artifact in payload.get("evidence_artifacts", []):
                if not (ROOT / artifact).exists():
                    fail(f"{path.relative_to(ROOT)} missing evidence artifact: {artifact}")
        if path.name == "verifier-contract-readiness.json":
            payload = json.loads(path.read_text(encoding="utf-8"))
            if payload.get("status") != "passed":
                fail(f"{path.relative_to(ROOT)} must be passed")
            if payload.get("counts_as_experiment") is not False:
                fail(f"{path.relative_to(ROOT)} must not count as experiment")
            if payload.get("contract_count") != 12:
                fail(f"{path.relative_to(ROOT)} must cover twelve verifier contracts")
            if payload.get("covered_verifier_count") != 12:
                fail(f"{path.relative_to(ROOT)} must cover all twelve used verifiers")
            if payload.get("task_bank_count") != 3:
                fail(f"{path.relative_to(ROOT)} must check three task banks")
            if payload.get("task_count_checked") != 1225:
                fail(f"{path.relative_to(ROOT)} must check 1225 task definitions")
            if payload.get("unused_contracts") != []:
                fail(f"{path.relative_to(ROOT)} unused_contracts must be empty")
            expected_verifiers = {
                "artifact_exists_verifier",
                "diff_scope_verifier",
                "evidence_verifier",
                "external_file_verifier",
                "github_delivery_verifier",
                "html_preview_verifier",
                "json_verifier",
                "markdown_preview_verifier",
                "privacy_verifier",
                "runtime_verifier",
                "snapshot_verifier",
                "trace_verifier",
            }
            if set(payload.get("used_verifiers", [])) != expected_verifiers:
                fail(f"{path.relative_to(ROOT)} used verifiers mismatch")
            task_banks = payload.get("task_banks")
            if not isinstance(task_banks, list) or len(task_banks) != 3:
                fail(f"{path.relative_to(ROOT)} task_banks must contain three entries")
            for artifact in payload.get("evidence_artifacts", []):
                if not (ROOT / artifact).exists():
                    fail(f"{path.relative_to(ROOT)} missing evidence artifact: {artifact}")
        if path.name == "bibliography-readiness.json":
            payload = json.loads(path.read_text(encoding="utf-8"))
            if payload.get("status") != "passed":
                fail(f"{path.relative_to(ROOT)} must be passed")
            if payload.get("entry_count") != 9:
                fail(f"{path.relative_to(ROOT)} must cover nine bibliography entries")
            if payload.get("cited_key_count") != 9:
                fail(f"{path.relative_to(ROOT)} must cover nine cited keys")
            for key in ("missing_entries", "unexpected_entries", "missing_cited_keys", "uncited_reference_keys", "remaining_draft_entries", "open_requirements"):
                if payload.get(key) != []:
                    fail(f"{path.relative_to(ROOT)} {key} must be empty")
            entries = payload.get("entries")
            if not isinstance(entries, list) or len(entries) != 9:
                fail(f"{path.relative_to(ROOT)} entries must contain nine items")
            expected_eprints = {
                "aitw": "2307.10088",
                "androidworld": "2405.14573",
                "appworld": "2407.18901",
                "mind2web": "2306.06070",
                "mobileagentbench": "2406.08184",
                "osworld": "2404.07972",
                "phoneworld": "2605.29486",
                "swebench": "2310.06770",
                "webarena": "2307.13854",
            }
            entries_by_key = {entry.get("key"): entry for entry in entries}
            if set(entries_by_key) != set(expected_eprints):
                fail(f"{path.relative_to(ROOT)} bibliography keys mismatch")
            for key, eprint in expected_eprints.items():
                entry = entries_by_key[key]
                if entry.get("eprint") != eprint:
                    fail(f"{path.relative_to(ROOT)} {key} eprint mismatch")
                if entry.get("status") != "verified":
                    fail(f"{path.relative_to(ROOT)} {key} must be verified")
                if not entry.get("source_url"):
                    fail(f"{path.relative_to(ROOT)} {key} missing source_url")
            for artifact in payload.get("evidence_artifacts", []):
                if not (ROOT / artifact).exists():
                    fail(f"{path.relative_to(ROOT)} missing evidence artifact: {artifact}")
        if path.name == "threats-to-validity.json":
            payload = json.loads(path.read_text(encoding="utf-8"))
            if payload.get("status") != "passed_with_open_requirements":
                fail(f"{path.relative_to(ROOT)} must be passed_with_open_requirements")
            if payload.get("threat_count") != 6:
                fail(f"{path.relative_to(ROOT)} must cover six threats")
            if payload.get("counts_as_experiment") is not False:
                fail(f"{path.relative_to(ROOT)} must set counts_as_experiment=false")
            if payload.get("limitations_section_checked") is not True:
                fail(f"{path.relative_to(ROOT)} must check the limitations section")
            expected_threat_ids = {
                "TTV1_construct_candidate_bank",
                "TTV2_internal_t0_evidence",
                "TTV3_external_device_diversity",
                "TTV4_baseline_fairness",
                "TTV5_privacy_and_delivery",
                "TTV6_submission_metadata",
            }
            threats = payload.get("threats")
            if not isinstance(threats, list) or len(threats) != 6:
                fail(f"{path.relative_to(ROOT)} threats must contain six entries")
            threats_by_id = {entry.get("id"): entry for entry in threats}
            if set(threats_by_id) != expected_threat_ids:
                fail(f"{path.relative_to(ROOT)} threat ids mismatch")
            for threat_id, threat_item in threats_by_id.items():
                if threat_item.get("counts_as_experiment") is not False:
                    fail(f"{path.relative_to(ROOT)} {threat_id} must not count as experiment")
                artifacts = threat_item.get("evidence_artifacts")
                if not isinstance(artifacts, list) or not artifacts:
                    fail(f"{path.relative_to(ROOT)} {threat_id} missing evidence_artifacts")
                for artifact in artifacts:
                    if not (ROOT / artifact).exists():
                        fail(f"{path.relative_to(ROOT)} {threat_id} missing evidence artifact: {artifact}")
            expected_open = {
                "authorized_github_sandbox_runs",
                "counted_baseline_runs_with_locked_settings",
                "human_review_and_final_frozen_subset",
                "multi_device_mobile_collection",
                "real_mobile_tier_runs",
                "venue_template_author_confirmation",
            }
            if set(payload.get("open_requirements", [])) != expected_open:
                fail(f"{path.relative_to(ROOT)} open requirements mismatch")
        if path.name == "baseline-protocol-readiness.json":
            payload = json.loads(path.read_text(encoding="utf-8"))
            if payload.get("status") != "protocol_defined_no_results":
                fail(f"{path.relative_to(ROOT)} must be protocol_defined_no_results")
            if payload.get("counts_as_experiment") is not False:
                fail(f"{path.relative_to(ROOT)} must set counts_as_experiment=false")
            if payload.get("counts_as_baseline_result") is not False:
                fail(f"{path.relative_to(ROOT)} must set counts_as_baseline_result=false")
            task_subset = payload.get("task_subset")
            if not isinstance(task_subset, dict) or task_subset.get("task_count") != 60:
                fail(f"{path.relative_to(ROOT)} must bind to the 60-task draft frozen subset")
            if task_subset.get("counts_as_final_paper_subset") is not False:
                fail(f"{path.relative_to(ROOT)} task subset must not count as final paper evidence")
            baselines = payload.get("baselines")
            expected_baselines = {
                "chat_only_mobile_coding_flow",
                "desktop_remote_ide_flow",
                "mobile_harness_flow",
            }
            if not isinstance(baselines, list) or {item.get("id") for item in baselines} != expected_baselines:
                fail(f"{path.relative_to(ROOT)} must define the three required baselines")
            for baseline in baselines:
                for key in ("allowed_tools", "evidence_requirements"):
                    value = baseline.get(key)
                    if not isinstance(value, list) or not value:
                        fail(f"{path.relative_to(ROOT)} {baseline.get('id')} missing {key}")
            metrics = set(payload.get("metrics", []))
            required_metrics = {
                "task_success",
                "verified_success",
                "trace_completeness",
                "recovery_rate",
                "artifact_availability",
                "human_intervention_count",
                "steps_to_completion",
            }
            if not required_metrics.issubset(metrics):
                fail(f"{path.relative_to(ROOT)} missing metrics: {sorted(required_metrics - metrics)}")
            for key in ("fairness_controls", "blocked_conditions", "required_result_artifacts", "source_artifacts"):
                value = payload.get(key)
                if not isinstance(value, list) or not value:
                    fail(f"{path.relative_to(ROOT)} missing {key}")
            for artifact in payload["source_artifacts"]:
                if not (ROOT / artifact).exists():
                    fail(f"{path.relative_to(ROOT)} missing source artifact: {artifact}")
        if path.name == "baseline-pilot-readiness.json":
            payload = json.loads(path.read_text(encoding="utf-8"))
            if payload.get("status") != "pilot_ready_no_results":
                fail(f"{path.relative_to(ROOT)} must be pilot_ready_no_results")
            if payload.get("counts_as_experiment") is not False:
                fail(f"{path.relative_to(ROOT)} must set counts_as_experiment=false")
            if payload.get("counts_as_baseline_result") is not False:
                fail(f"{path.relative_to(ROOT)} must set counts_as_baseline_result=false")
            if payload.get("baseline_count") != 3:
                fail(f"{path.relative_to(ROOT)} must cover three baselines")
            if payload.get("task_count_per_baseline") != 1:
                fail(f"{path.relative_to(ROOT)} must use one task per baseline")
            if payload.get("ready_for_pilot_execution") is not True:
                fail(f"{path.relative_to(ROOT)} must be ready for non-counted pilot execution")
            if payload.get("ready_for_counted_baseline_result") is not False:
                fail(f"{path.relative_to(ROOT)} must not be ready for counted baseline result")
            checks = payload.get("readiness_checks")
            if not isinstance(checks, dict):
                fail(f"{path.relative_to(ROOT)} missing readiness_checks")
            if checks.get("prompt_template_count") != 3:
                fail(f"{path.relative_to(ROOT)} must include three prompt templates")
            if checks.get("evidence_template_count") != 3:
                fail(f"{path.relative_to(ROOT)} must include three evidence templates")
            if set(checks.get("baseline_ids", [])) != BASELINE_IDS:
                fail(f"{path.relative_to(ROOT)} baseline ids mismatch")
            blocked = set(payload.get("blocked_before_counting", []))
            required_blockers = {
                "model_lock_not_filled",
                "no_model_execution",
                "no_prompt_transcripts",
                "no_artifacts_or_blocked_outputs",
                "no_verifier_outputs",
                "no_baseline_result_runs",
            }
            if not required_blockers.issubset(blocked):
                fail(f"{path.relative_to(ROOT)} missing blocked-before-counting markers")
            for key in ("prompt_paths", "evidence_template_paths", "source_artifacts"):
                values = payload.get(key)
                if not isinstance(values, list) or not values:
                    fail(f"{path.relative_to(ROOT)} missing {key}")
                for artifact in values:
                    if not (ROOT / artifact).exists():
                        fail(f"{path.relative_to(ROOT)} missing artifact: {artifact}")
            for key in ("model_lock_template", "human_intervention_sheet"):
                artifact = payload.get(key)
                if not isinstance(artifact, str) or not (ROOT / artifact).exists():
                    fail(f"{path.relative_to(ROOT)} missing {key}")
        if path.name == "baseline-run-contract.json":
            payload = json.loads(path.read_text(encoding="utf-8"))
            if payload.get("status") != "contract_defined_no_results":
                fail(f"{path.relative_to(ROOT)} must be contract_defined_no_results")
            if payload.get("counts_as_experiment") is not False:
                fail(f"{path.relative_to(ROOT)} must set counts_as_experiment=false")
            if payload.get("counts_as_baseline_result") is not False:
                fail(f"{path.relative_to(ROOT)} must set counts_as_baseline_result=false")
            if payload.get("result_count") != 0:
                fail(f"{path.relative_to(ROOT)} must not contain baseline results")
            schema = payload.get("schema")
            if not isinstance(schema, dict):
                fail(f"{path.relative_to(ROOT)} missing schema object")
            schema_path = ROOT / schema.get("path", "")
            if schema_path != BASELINE_RUN_SCHEMA_PATH or not schema_path.exists():
                fail(f"{path.relative_to(ROOT)} must reference baseline_run.schema.json")
            required_top_level = set(schema.get("required_top_level", []))
            for key in (
                "benchmark",
                "schema_version",
                "run_id",
                "run_kind",
                "task_subset",
                "baseline_id",
                "environment",
                "counts_as_experiment",
                "counts_as_baseline_result",
                "summary",
                "results",
                "evidence_boundary",
            ):
                if key not in required_top_level:
                    fail(f"{path.relative_to(ROOT)} schema missing top-level field: {key}")
            baseline_ids = set(payload.get("baseline_ids", []))
            if baseline_ids != BASELINE_IDS:
                fail(f"{path.relative_to(ROOT)} must define the three baseline ids")
            required_metrics = set(schema.get("required_metrics", []))
            if required_metrics != BASELINE_METRICS:
                fail(f"{path.relative_to(ROOT)} required metrics do not match protocol metrics")
            required_evidence_fields = set(schema.get("required_evidence_fields", []))
            for key in BASELINE_EVIDENCE_FIELDS:
                if key not in required_evidence_fields:
                    fail(f"{path.relative_to(ROOT)} schema missing evidence field: {key}")
            task_subset = payload.get("task_subset")
            if not isinstance(task_subset, dict) or task_subset.get("task_count") != 60:
                fail(f"{path.relative_to(ROOT)} must bind to the 60-task draft frozen subset")
            if task_subset.get("counts_as_final_paper_subset") is not False:
                fail(f"{path.relative_to(ROOT)} task subset must not count as final paper evidence")
            for key in ("future_artifacts", "source_artifacts"):
                value = payload.get(key)
                if not isinstance(value, list) or not value:
                    fail(f"{path.relative_to(ROOT)} missing {key}")
            for artifact in payload["source_artifacts"]:
                if not (ROOT / artifact).exists():
                    fail(f"{path.relative_to(ROOT)} missing source artifact: {artifact}")
    return len(report_paths)


def validate_task_set(tasks_by_id: dict[str, dict], task_set_path: Path, valid_categories: set[str]) -> None:
    if not task_set_path.exists():
        fail(f"missing task set manifest: {task_set_path.relative_to(ROOT)}")
    payload = json.loads(task_set_path.read_text(encoding="utf-8"))
    task_set = payload.get("task_set")
    if not task_set:
        fail(f"{task_set_path.relative_to(ROOT)} missing task_set")
    entries = payload.get("tasks")
    if not isinstance(entries, list) or len(entries) < 5:
        fail(f"{task_set_path.relative_to(ROOT)} must contain at least 5 task entries")

    categories: Counter[str] = Counter()
    seen_ids: set[str] = set()
    for entry in entries:
        task_id = entry.get("id")
        if task_id not in tasks_by_id:
            fail(f"{task_set_path.relative_to(ROOT)} references unknown task id: {task_id}")
        if task_id in seen_ids:
            fail(f"{task_set_path.relative_to(ROOT)} duplicates task id: {task_id}")
        seen_ids.add(task_id)

        seed_task = tasks_by_id[task_id]
        if entry.get("category") != seed_task["category"]:
            fail(f"{task_set_path.relative_to(ROOT)} {task_id} category does not match seed task")
        if entry.get("fixture") != seed_task["input_fixture"]["path"]:
            fail(f"{task_set_path.relative_to(ROOT)} {task_id} fixture does not match seed task")
        verifiers = entry.get("offline_verifiers")
        if not isinstance(verifiers, list) or not verifiers:
            fail(f"{task_set_path.relative_to(ROOT)} {task_id} missing offline_verifiers")
        categories[seed_task["category"]] += 1

    missing_categories = valid_categories - set(categories)
    if missing_categories:
        fail(f"{task_set_path.relative_to(ROOT)} missing categories: {sorted(missing_categories)}")


def validate_candidate_task_set(tasks_by_id: dict[str, dict], task_set_path: Path, expected_count: int) -> None:
    if not task_set_path.exists():
        fail(f"missing v2 task set manifest: {task_set_path.relative_to(ROOT)}")
    payload = json.loads(task_set_path.read_text(encoding="utf-8"))
    if not payload.get("task_set"):
        fail(f"{task_set_path.relative_to(ROOT)} missing task_set")
    entries = payload.get("tasks")
    if not isinstance(entries, list) or len(entries) != expected_count:
        fail(f"{task_set_path.relative_to(ROOT)} must contain exactly {expected_count} tasks")
    seen_ids: set[str] = set()
    categories: Counter[str] = Counter()
    for entry in entries:
        task_id = entry.get("id")
        if task_id not in tasks_by_id:
            fail(f"{task_set_path.relative_to(ROOT)} references unknown task id: {task_id}")
        if task_id in seen_ids:
            fail(f"{task_set_path.relative_to(ROOT)} duplicates task id: {task_id}")
        seen_ids.add(task_id)
        task = tasks_by_id[task_id]
        if entry.get("category") != task["category"]:
            fail(f"{task_set_path.relative_to(ROOT)} {task_id} category does not match v2 bank")
        if entry.get("fixture") != task["input_fixture"]["path"]:
            fail(f"{task_set_path.relative_to(ROOT)} {task_id} fixture does not match v2 bank")
        if entry.get("mobile_profile") != task["scenario"]["mobile_profile"]:
            fail(f"{task_set_path.relative_to(ROOT)} {task_id} mobile_profile does not match v2 bank")
        if entry.get("quality_axis") != task["scenario"]["quality_axis"]:
            fail(f"{task_set_path.relative_to(ROOT)} {task_id} quality_axis does not match v2 bank")
        if not entry.get("test_tier"):
            fail(f"{task_set_path.relative_to(ROOT)} {task_id} missing test_tier")
        categories[task["category"]] += 1
    missing_categories = V2_CATEGORIES - set(categories)
    if missing_categories:
        fail(f"{task_set_path.relative_to(ROOT)} missing categories: {sorted(missing_categories)}")


def validate_frozen_subset(tasks_by_id: dict[str, dict]) -> bool:
    if not FROZEN_SUBSET_PATH.exists():
        return False
    payload = json.loads(FROZEN_SUBSET_PATH.read_text(encoding="utf-8"))
    if payload.get("status") != "draft_frozen_candidate":
        fail(f"{FROZEN_SUBSET_PATH.relative_to(ROOT)} must be draft_frozen_candidate until mobile-tier evidence exists")
    if payload.get("frozen") is not False:
        fail(f"{FROZEN_SUBSET_PATH.relative_to(ROOT)} must set frozen=false")
    if payload.get("counts_as_final_paper_subset") is not False:
        fail(f"{FROZEN_SUBSET_PATH.relative_to(ROOT)} must set counts_as_final_paper_subset=false")
    entries = payload.get("tasks")
    if not isinstance(entries, list) or len(entries) != 60:
        fail(f"{FROZEN_SUBSET_PATH.relative_to(ROOT)} must contain exactly 60 draft entries")
    seen_ids: set[str] = set()
    categories: Counter[str] = Counter()
    for entry in entries:
        task_id = entry.get("id")
        if task_id not in tasks_by_id:
            fail(f"{FROZEN_SUBSET_PATH.relative_to(ROOT)} references unknown task id: {task_id}")
        if task_id in seen_ids:
            fail(f"{FROZEN_SUBSET_PATH.relative_to(ROOT)} duplicates task id: {task_id}")
        seen_ids.add(task_id)
        task = tasks_by_id[task_id]
        if entry.get("category") != task["category"]:
            fail(f"{FROZEN_SUBSET_PATH.relative_to(ROOT)} {task_id} category does not match v2 bank")
        if entry.get("counts_as_final_paper_result") is not False:
            fail(f"{FROZEN_SUBSET_PATH.relative_to(ROOT)} {task_id} must set counts_as_final_paper_result=false")
        if entry.get("paper_counting_status") != "t0_only_not_mobile_counted":
            fail(f"{FROZEN_SUBSET_PATH.relative_to(ROOT)} {task_id} has invalid paper_counting_status")
        if not entry.get("required_next_tier"):
            fail(f"{FROZEN_SUBSET_PATH.relative_to(ROOT)} {task_id} missing required_next_tier")
        required_evidence = entry.get("required_next_evidence")
        if not isinstance(required_evidence, list) or not required_evidence:
            fail(f"{FROZEN_SUBSET_PATH.relative_to(ROOT)} {task_id} missing required_next_evidence")
        for artifact in entry.get("t0_artifacts", []):
            artifact_path = ROOT / artifact
            if not artifact_path.exists():
                fail(f"{FROZEN_SUBSET_PATH.relative_to(ROOT)} {task_id} missing T0 artifact: {artifact}")
        categories[task["category"]] += 1
    missing_categories = V2_CATEGORIES - set(categories)
    if missing_categories:
        fail(f"{FROZEN_SUBSET_PATH.relative_to(ROOT)} missing categories: {sorted(missing_categories)}")
    return True


def _ensure_baseline_metric_shape(metrics: object, context: str, *, expect_null: bool) -> None:
    if not isinstance(metrics, dict):
        fail(f"{context} metrics must be an object")
    missing = BASELINE_METRICS - set(metrics)
    if missing:
        fail(f"{context} metrics missing keys: {sorted(missing)}")
    if expect_null:
        not_null = {key: value for key, value in metrics.items() if key in BASELINE_METRICS and value is not None}
        if not_null:
            fail(f"{context} non-result metrics must be null; got {not_null}")


def _ensure_baseline_evidence_shape(evidence: object, context: str) -> None:
    if not isinstance(evidence, dict):
        fail(f"{context} evidence must be an object")
    missing = BASELINE_EVIDENCE_FIELDS - set(evidence)
    if missing:
        fail(f"{context} evidence missing keys: {sorted(missing)}")
    for key in BASELINE_EVIDENCE_FIELDS:
        if not isinstance(evidence.get(key), list):
            fail(f"{context} evidence.{key} must be a list")


def validate_baseline_run_dir(run_dir: Path, valid_task_ids: set[str]) -> None:
    run_json = run_dir / "baseline-run.json"
    summary_md = run_dir / "baseline-summary.md"
    traces_jsonl = run_dir / "baseline-traces.jsonl"
    for path in (run_json, summary_md, traces_jsonl):
        if not path.exists():
            fail(f"{run_dir.relative_to(ROOT)} missing required baseline file: {path.name}")
        assert_public_safe(path)

    payload = json.loads(run_json.read_text(encoding="utf-8"))
    if payload.get("benchmark") != "MobileHarnessBench":
        fail(f"{run_json.relative_to(ROOT)} invalid benchmark")
    baseline_id = payload.get("baseline_id")
    if baseline_id not in BASELINE_IDS:
        fail(f"{run_json.relative_to(ROOT)} invalid baseline_id: {baseline_id}")
    run_kind = payload.get("run_kind")
    if run_kind not in {"scaffold_not_run", "dry_run_not_counted", "baseline_result"}:
        fail(f"{run_json.relative_to(ROOT)} invalid run_kind: {run_kind}")

    summary = payload.get("summary")
    if not isinstance(summary, dict):
        fail(f"{run_json.relative_to(ROOT)} missing summary")
    results = payload.get("results")
    if not isinstance(results, list):
        fail(f"{run_json.relative_to(ROOT)} results must be a list")
    if summary.get("total") != len(results):
        fail(f"{run_json.relative_to(ROOT)} summary.total does not match result count")
    _ensure_baseline_metric_shape(summary.get("metrics"), f"{run_json.relative_to(ROOT)} summary", expect_null=run_kind != "baseline_result")

    if run_kind == "scaffold_not_run":
        if payload.get("counts_as_experiment") is not False:
            fail(f"{run_json.relative_to(ROOT)} scaffold must set counts_as_experiment=false")
        if payload.get("counts_as_baseline_result") is not False:
            fail(f"{run_json.relative_to(ROOT)} scaffold must set counts_as_baseline_result=false")
        if summary.get("not_run") != len(results):
            fail(f"{run_json.relative_to(ROOT)} scaffold summary.not_run must equal result count")
        for status in ("passed", "failed", "blocked", "warning"):
            if summary.get(status) != 0:
                fail(f"{run_json.relative_to(ROOT)} scaffold summary.{status} must be 0")
    elif run_kind == "dry_run_not_counted":
        if payload.get("counts_as_experiment") is not False:
            fail(f"{run_json.relative_to(ROOT)} dry run must set counts_as_experiment=false")
        if payload.get("counts_as_baseline_result") is not False:
            fail(f"{run_json.relative_to(ROOT)} dry run must set counts_as_baseline_result=false")
        if len(results) < 1:
            fail(f"{run_json.relative_to(ROOT)} dry run must contain at least one result")
        for status in ("passed", "failed", "warning"):
            if summary.get(status) != 0:
                fail(f"{run_json.relative_to(ROOT)} dry run summary.{status} must be 0")
        if summary.get("blocked", 0) + summary.get("not_run", 0) != len(results):
            fail(f"{run_json.relative_to(ROOT)} dry run must be fully blocked or not_run")
    elif run_kind == "baseline_result":
        if payload.get("counts_as_baseline_result") is not True:
            fail(f"{run_json.relative_to(ROOT)} baseline_result must set counts_as_baseline_result=true")

    result_task_ids: set[str] = set()
    for result in results:
        task_id = result.get("task_id")
        if task_id not in valid_task_ids:
            fail(f"{run_json.relative_to(ROOT)} unknown task_id: {task_id}")
        result_task_ids.add(task_id)
        status = result.get("status")
        if run_kind == "scaffold_not_run":
            if status != "not_run":
                fail(f"{run_json.relative_to(ROOT)} scaffold {task_id} must be not_run")
            if result.get("counts_as_mobile_experiment") is not False:
                fail(f"{run_json.relative_to(ROOT)} scaffold {task_id} must not count as mobile experiment")
            _ensure_baseline_metric_shape(result.get("metrics"), f"{run_json.relative_to(ROOT)} {task_id}", expect_null=True)
        elif run_kind == "dry_run_not_counted":
            if status not in {"blocked", "not_run"}:
                fail(f"{run_json.relative_to(ROOT)} dry run {task_id} must be blocked or not_run")
            if result.get("counts_as_mobile_experiment") is not False:
                fail(f"{run_json.relative_to(ROOT)} dry run {task_id} must not count as mobile experiment")
            _ensure_baseline_metric_shape(result.get("metrics"), f"{run_json.relative_to(ROOT)} {task_id}", expect_null=True)
        else:
            if status not in {"passed", "warning", "failed", "blocked", "not_run"}:
                fail(f"{run_json.relative_to(ROOT)} {task_id} invalid status: {status}")
            _ensure_baseline_metric_shape(result.get("metrics"), f"{run_json.relative_to(ROOT)} {task_id}", expect_null=False)
        _ensure_baseline_evidence_shape(result.get("evidence"), f"{run_json.relative_to(ROOT)} {task_id}")

    trace_task_ids: set[str] = set()
    trace_count = 0
    for line_number, line in enumerate(traces_jsonl.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        trace_count += 1
        event = json.loads(line)
        if event.get("baseline_id") != baseline_id:
            fail(f"{traces_jsonl.relative_to(ROOT)} line {line_number} baseline_id mismatch")
        task_id = event.get("task_id")
        if task_id not in result_task_ids:
            fail(f"{traces_jsonl.relative_to(ROOT)} line {line_number} unknown task_id: {task_id}")
        trace_task_ids.add(task_id)
        if run_kind != "baseline_result" and event.get("counts_as_baseline_result") is not False:
            fail(f"{traces_jsonl.relative_to(ROOT)} line {line_number} non-result run must not count as baseline result")
    if trace_task_ids != result_task_ids:
        fail(f"{traces_jsonl.relative_to(ROOT)} trace task ids do not match baseline results")
    if trace_count < len(results):
        fail(f"{traces_jsonl.relative_to(ROOT)} has too few baseline trace events")


def validate_baseline_artifacts(valid_task_ids: set[str]) -> tuple[int, int]:
    if not BASELINES_ROOT.exists():
        return 0, 0
    run_files = sorted(BASELINES_ROOT.rglob("baseline-run.json"))
    if not run_files:
        return 0, 0
    seen_scaffold_baselines: set[str] = set()
    seen_dry_run_baselines: set[str] = set()
    scaffold_count = 0
    dry_run_count = 0
    for run_file in run_files:
        run_dir = run_file.parent
        validate_baseline_run_dir(run_dir, valid_task_ids)
        payload = json.loads(run_file.read_text(encoding="utf-8"))
        if payload.get("run_kind") == "scaffold_not_run":
            scaffold_count += 1
            seen_scaffold_baselines.add(payload.get("baseline_id"))
        if payload.get("run_kind") == "dry_run_not_counted":
            dry_run_count += 1
            seen_dry_run_baselines.add(payload.get("baseline_id"))
    if seen_scaffold_baselines != BASELINE_IDS:
        fail(f"{BASELINES_ROOT.relative_to(ROOT)} scaffold must cover all baselines; got {sorted(seen_scaffold_baselines)}")
    if dry_run_count and seen_dry_run_baselines != BASELINE_IDS:
        fail(f"{BASELINES_ROOT.relative_to(ROOT)} dry run must cover all baselines; got {sorted(seen_dry_run_baselines)}")
    return scaffold_count, dry_run_count


def validate_baseline_pilot_pack(valid_task_ids: set[str]) -> int:
    if not BASELINE_PILOT_ROOT.exists():
        return 0

    manifest_path = BASELINE_PILOT_ROOT / "manifest.json"
    readme_path = BASELINE_PILOT_ROOT / "README.md"
    model_lock_path = BASELINE_PILOT_ROOT / "model-lock-template.json"
    intervention_path = BASELINE_PILOT_ROOT / "human-intervention-sheet.csv"
    for path in (manifest_path, readme_path, model_lock_path, intervention_path):
        if not path.exists():
            fail(f"{BASELINE_PILOT_ROOT.relative_to(ROOT)} missing pilot file: {path.name}")
        assert_public_safe(path)

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("status") != "pilot_ready_no_results":
        fail(f"{manifest_path.relative_to(ROOT)} must be pilot_ready_no_results")
    if manifest.get("counts_as_experiment") is not False:
        fail(f"{manifest_path.relative_to(ROOT)} must set counts_as_experiment=false")
    if manifest.get("counts_as_baseline_result") is not False:
        fail(f"{manifest_path.relative_to(ROOT)} must set counts_as_baseline_result=false")
    if manifest.get("baseline_count") != 3:
        fail(f"{manifest_path.relative_to(ROOT)} must cover three baselines")
    if manifest.get("task_count_per_baseline") != 1:
        fail(f"{manifest_path.relative_to(ROOT)} must use one pilot task per baseline")
    selected_task = manifest.get("selected_task", {})
    selected_task_id = selected_task.get("id")
    if selected_task_id not in valid_task_ids:
        fail(f"{manifest_path.relative_to(ROOT)} unknown selected task: {selected_task_id}")

    pilot_dirs = manifest.get("pilot_dirs")
    if not isinstance(pilot_dirs, list):
        fail(f"{manifest_path.relative_to(ROOT)} pilot_dirs must be a list")
    seen_baselines: set[str] = set()
    for pilot_dir_text in pilot_dirs:
        pilot_dir = ROOT / pilot_dir_text
        if not pilot_dir.exists() or not pilot_dir.is_dir():
            fail(f"{manifest_path.relative_to(ROOT)} missing pilot dir: {pilot_dir_text}")
        baseline_id = pilot_dir.name
        if baseline_id not in BASELINE_IDS:
            fail(f"{manifest_path.relative_to(ROOT)} invalid pilot baseline id: {baseline_id}")
        seen_baselines.add(baseline_id)

        prompt_path = pilot_dir / "prompt.md"
        evidence_path = pilot_dir / "evidence-template.json"
        baseline_readme_path = pilot_dir / "README.md"
        for path in (prompt_path, evidence_path, baseline_readme_path):
            if not path.exists():
                fail(f"{pilot_dir.relative_to(ROOT)} missing pilot file: {path.name}")
            assert_public_safe(path)

        prompt = prompt_path.read_text(encoding="utf-8")
        if baseline_id not in prompt or selected_task_id not in prompt:
            fail(f"{prompt_path.relative_to(ROOT)} must contain baseline id and selected task id")

        evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
        if evidence.get("status") != "template_not_filled":
            fail(f"{evidence_path.relative_to(ROOT)} must be template_not_filled")
        if evidence.get("baseline_id") != baseline_id:
            fail(f"{evidence_path.relative_to(ROOT)} baseline_id mismatch")
        if evidence.get("task_id") != selected_task_id:
            fail(f"{evidence_path.relative_to(ROOT)} task_id mismatch")
        if evidence.get("counts_as_baseline_result") is not False:
            fail(f"{evidence_path.relative_to(ROOT)} must set counts_as_baseline_result=false")
        required_before_counting = evidence.get("required_before_counting")
        if not isinstance(required_before_counting, list) or len(required_before_counting) < 6:
            fail(f"{evidence_path.relative_to(ROOT)} must define required evidence before counting")

    if seen_baselines != BASELINE_IDS:
        fail(f"{manifest_path.relative_to(ROOT)} pilot dirs must cover all baselines; got {sorted(seen_baselines)}")

    model_lock = json.loads(model_lock_path.read_text(encoding="utf-8"))
    if model_lock.get("status") != "template_not_filled":
        fail(f"{model_lock_path.relative_to(ROOT)} must be template_not_filled")
    if model_lock.get("counts_as_baseline_result") is not False:
        fail(f"{model_lock_path.relative_to(ROOT)} must set counts_as_baseline_result=false")
    required_fields = set(model_lock.get("required_fields", []))
    if required_fields != MODEL_LOCK_FIELDS:
        fail(f"{model_lock_path.relative_to(ROOT)} required_fields mismatch")
    placeholders = model_lock.get("placeholders")
    if not isinstance(placeholders, dict) or set(placeholders) != MODEL_LOCK_FIELDS:
        fail(f"{model_lock_path.relative_to(ROOT)} placeholders must cover model lock fields")
    if set(model_lock.get("baseline_ids", [])) != BASELINE_IDS:
        fail(f"{model_lock_path.relative_to(ROOT)} baseline_ids mismatch")
    if model_lock.get("task_id") != selected_task_id:
        fail(f"{model_lock_path.relative_to(ROOT)} task_id mismatch")

    with intervention_path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames != HUMAN_INTERVENTION_COLUMNS:
            fail(f"{intervention_path.relative_to(ROOT)} header mismatch")
        rows = list(reader)
    if len(rows) != len(BASELINE_IDS):
        fail(f"{intervention_path.relative_to(ROOT)} must contain one template row per baseline")
    if {row.get("baseline_id") for row in rows} != BASELINE_IDS:
        fail(f"{intervention_path.relative_to(ROOT)} rows must cover all baselines")
    if {row.get("task_id") for row in rows} != {selected_task_id}:
        fail(f"{intervention_path.relative_to(ROOT)} rows must use selected task id")

    return len(seen_baselines)


def validate_task_file(
    task_file: Path,
    label: str,
    *,
    expected_count: int | None = None,
    minimum_count: int = 1,
    valid_categories: set[str],
    require_quality_fields: bool = False,
) -> tuple[set[str], dict[str, dict], Counter[str]]:
    if not task_file.exists():
        fail(f"missing {label} task file: {task_file}")

    payload = json.loads(task_file.read_text(encoding="utf-8"))
    tasks = payload.get("tasks")
    if not isinstance(tasks, list) or len(tasks) < minimum_count:
        fail(f"{label} top-level tasks must contain at least {minimum_count} entries")
    if expected_count is not None and len(tasks) != expected_count:
        fail(f"{label} must contain exactly {expected_count} tasks; got {len(tasks)}")

    seen_ids: set[str] = set()
    seen_titles: set[str] = set()
    seen_goals: set[str] = set()
    tasks_by_id: dict[str, dict] = {}
    categories: Counter[str] = Counter()

    for index, task in enumerate(tasks):
        if not isinstance(task, dict):
            fail(f"task at index {index} is not an object")
        missing = REQUIRED_FIELDS - set(task)
        if missing:
            fail(f"{task.get('id', '<missing id>')} missing fields: {sorted(missing)}")

        task_id = task["id"]
        if not ID_RE.match(task_id):
            fail(f"{label} invalid task id: {task_id}")
        if task_id in seen_ids:
            fail(f"{label} duplicate task id: {task_id}")
        seen_ids.add(task_id)
        tasks_by_id[task_id] = task
        if require_quality_fields:
            title = task.get("title")
            user_goal = task.get("user_goal")
            if title in seen_titles:
                fail(f"{label} duplicate title: {title}")
            if user_goal in seen_goals:
                fail(f"{label} duplicate user_goal: {user_goal}")
            seen_titles.add(title)
            seen_goals.add(user_goal)

        category = task["category"]
        if category not in valid_categories:
            fail(f"{label} {task_id} invalid category: {category}")
        categories[category] += 1

        fixture = task["input_fixture"]
        if not isinstance(fixture, dict):
            fail(f"{task_id} input_fixture must be an object")
        for key in ("kind", "path", "description"):
            if not fixture.get(key):
                fail(f"{task_id} input_fixture.{key} is required")
        fixture_path = BENCH_ROOT / fixture["path"]
        if not fixture_path.exists():
            fail(f"{label} {task_id} missing fixture path: {fixture['path']}")

        for key in ("required_capabilities", "expected_artifacts", "verifiers", "evidence_requirements"):
            ensure_list(task, key)
        if not isinstance(task.get("blocked_conditions"), list):
            fail(f"{task_id} blocked_conditions must be a list")
        if require_quality_fields:
            scenario = task.get("scenario")
            if not isinstance(scenario, dict):
                fail(f"{label} {task_id} scenario must be an object")
            for key in (
                "context",
                "difficulty",
                "source",
                "fixture_family",
                "quality_axis",
                "bank_version",
                "mobile_profile",
                "os_target",
                "input_surface",
                "app_state",
                "network_profile",
                "viewport",
            ):
                if not scenario.get(key):
                    fail(f"{label} {task_id} scenario.{key} is required")
            for key in ("quality_gates", "sampling_tags"):
                ensure_list(task, key)
            mobile_requirements = task.get("mobile_requirements")
            if not isinstance(mobile_requirements, dict):
                fail(f"{label} {task_id} mobile_requirements must be an object")
            for key in ("os_target", "input_surface", "app_state", "network_profile", "viewport", "evidence_capture"):
                if not mobile_requirements.get(key):
                    fail(f"{label} {task_id} mobile_requirements.{key} is required")
            if not isinstance(mobile_requirements.get("requires_real_device"), bool):
                fail(f"{label} {task_id} mobile_requirements.requires_real_device must be boolean")
            test_oracle = task.get("test_oracle")
            if not isinstance(test_oracle, dict):
                fail(f"{label} {task_id} test_oracle must be an object")
            if not isinstance(test_oracle.get("must_satisfy"), list) or not test_oracle["must_satisfy"]:
                fail(f"{label} {task_id} test_oracle.must_satisfy must be a non-empty list")

    missing_categories = valid_categories - set(categories)
    if missing_categories:
        fail(f"{label} missing categories: {sorted(missing_categories)}")

    return seen_ids, tasks_by_id, categories


def main() -> None:
    validate_anonymous_supplement_readme()

    seed_ids, seed_tasks_by_id, seed_categories = validate_task_file(
        TASKS_PATH,
        "v0 seed",
        expected_count=25,
        valid_categories=SEED_CATEGORIES,
    )
    v1_ids, _, v1_categories = validate_task_file(
        V1_TASK_BANK_PATH,
        "v1 task bank",
        expected_count=200,
        valid_categories=SEED_CATEGORIES,
    )
    v2_ids, v2_tasks_by_id, v2_categories = validate_task_file(
        V2_TASK_BANK_PATH,
        "v2 task bank",
        expected_count=1000,
        valid_categories=V2_CATEGORIES,
        require_quality_fields=True,
    )
    overlap = (seed_ids & v1_ids) | (seed_ids & v2_ids) | (v1_ids & v2_ids)
    if overlap:
        fail(f"task files have overlapping ids: {sorted(overlap)}")

    for category, expected_count in V1_CATEGORY_COUNTS.items():
        if v1_categories[category] != expected_count:
            fail(f"v1 task bank category {category} must contain {expected_count} tasks; got {v1_categories[category]}")
    for category, expected_count in V2_CATEGORY_COUNTS.items():
        if v2_categories[category] != expected_count:
            fail(f"v2 task bank category {category} must contain {expected_count} tasks; got {v2_categories[category]}")

    verifier_contract_count, verifier_task_count = validate_verifier_contract_catalog()

    validate_task_set(seed_tasks_by_id, REPRESENTATIVE_TASK_SET_PATH, SEED_CATEGORIES)
    validate_candidate_task_set(v2_tasks_by_id, V2_TASK_SET_PATHS[0], 60)
    validate_candidate_task_set(v2_tasks_by_id, V2_TASK_SET_PATHS[1], 30)
    validate_candidate_task_set(v2_tasks_by_id, V2_TASK_SET_PATHS[2], 18)
    has_frozen_subset = validate_frozen_subset(v2_tasks_by_id)
    run_count = validate_runs(seed_ids | v1_ids | v2_ids)
    baseline_scaffold_count, baseline_dry_run_count = validate_baseline_artifacts(seed_ids | v1_ids | v2_ids)
    baseline_pilot_count = validate_baseline_pilot_pack(seed_ids | v1_ids | v2_ids)
    report_count = validate_reports()

    print("MobileHarnessBench validation passed")
    print(f"v0_tasks={len(seed_ids)} categories={dict(sorted(seed_categories.items()))}")
    print(f"v1_task_bank={len(v1_ids)} categories={dict(sorted(v1_categories.items()))}")
    print(f"v2_task_bank={len(v2_ids)} categories={dict(sorted(v2_categories.items()))}")
    print(f"verifier_contracts={verifier_contract_count} task_definitions_checked={verifier_task_count}")
    print(f"task_set=representative-v0 entries=5 validated")
    print("task_set=smoke-v2 entries=60 validated")
    print("task_set=android-device-v2 entries=30 validated")
    print("task_set=ios-simulator-v2 entries=18 validated")
    if has_frozen_subset:
        print("task_set=frozen-v2-paper-subset entries=60 draft validated")
    if run_count:
        print(f"runs={run_count} validated")
    if baseline_scaffold_count:
        print(f"baseline_scaffolds={baseline_scaffold_count} validated")
    if baseline_dry_run_count:
        print(f"baseline_dry_runs={baseline_dry_run_count} validated")
    if baseline_pilot_count:
        print(f"baseline_pilot_pack={baseline_pilot_count} validated")
    if report_count:
        print(f"reports={report_count} validated")


if __name__ == "__main__":
    main()
