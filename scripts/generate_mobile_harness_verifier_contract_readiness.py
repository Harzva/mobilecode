#!/usr/bin/env python3
"""Generate verifier-contract readiness for MobileHarnessBench."""

from __future__ import annotations

import json
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
BENCH_ROOT = ROOT / "docs" / "mobile-harness-benchmark"
TASKS_ROOT = BENCH_ROOT / "tasks"
REPORTS_ROOT = BENCH_ROOT / "reports"
CONTRACTS_PATH = BENCH_ROOT / "verifiers" / "verifier-contracts.json"
REPORT_JSON_PATH = REPORTS_ROOT / "verifier-contract-readiness.json"
REPORT_MD_PATH = REPORTS_ROOT / "verifier-contract-readiness.md"

TASK_BANKS = [
    ("v0-seed-tasks", TASKS_ROOT / "v0-seed-tasks.json", 25),
    ("v1-task-bank", TASKS_ROOT / "v1-task-bank.json", 200),
    ("v2-task-bank", TASKS_ROOT / "v2-task-bank.json", 1000),
]

REQUIRED_CONTRACT_FIELDS = {
    "id",
    "category_scope",
    "description",
    "required_inputs",
    "required_evidence",
    "pass_conditions",
    "failure_kinds",
    "current_t0_support",
}


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"verifier contract readiness generation failed: {message}")


def load_json(path: Path) -> Any:
    if not path.exists():
        raise SystemExit(f"missing required artifact: {rel(path)}")
    return json.loads(path.read_text(encoding="utf-8"))


def load_tasks(path: Path) -> list[dict[str, Any]]:
    payload = load_json(path)
    tasks = payload.get("tasks") if isinstance(payload, dict) else payload
    require(isinstance(tasks, list), f"{rel(path)} must contain a task list")
    return tasks


def validate_contracts(catalog: dict[str, Any]) -> dict[str, dict[str, Any]]:
    require(catalog.get("counts_as_experiment") is False, "catalog must not count as experiment")
    contracts = catalog.get("contracts")
    require(isinstance(contracts, list) and contracts, "catalog must contain contracts")
    by_id: dict[str, dict[str, Any]] = {}
    for contract in contracts:
        missing = REQUIRED_CONTRACT_FIELDS - set(contract)
        require(not missing, f"{contract.get('id', '<missing id>')} missing fields: {sorted(missing)}")
        contract_id = contract["id"]
        require(contract_id not in by_id, f"duplicate verifier contract: {contract_id}")
        for key in REQUIRED_CONTRACT_FIELDS - {"id", "description", "current_t0_support"}:
            require(isinstance(contract.get(key), list) and contract[key], f"{contract_id}.{key} must be a non-empty list")
        by_id[contract_id] = contract
    return by_id


def task_bank_summary(label: str, path: Path, expected_count: int, contracts: dict[str, dict[str, Any]]) -> dict[str, Any]:
    tasks = load_tasks(path)
    require(len(tasks) == expected_count, f"{label} expected {expected_count} tasks, got {len(tasks)}")
    verifier_counts: Counter[str] = Counter()
    category_counts: dict[str, Counter[str]] = defaultdict(Counter)
    unknown_verifiers: dict[str, list[str]] = defaultdict(list)
    category_scope_violations: dict[str, list[str]] = defaultdict(list)

    for task in tasks:
        task_id = task.get("id")
        category = task.get("category")
        verifiers = task.get("verifiers")
        require(isinstance(verifiers, list) and verifiers, f"{label} {task_id} missing verifiers")
        for verifier_id in verifiers:
            verifier_counts[verifier_id] += 1
            category_counts[category][verifier_id] += 1
            contract = contracts.get(verifier_id)
            if contract is None:
                unknown_verifiers[verifier_id].append(task_id)
                continue
            if category not in contract["category_scope"]:
                category_scope_violations[verifier_id].append(task_id)

    require(not unknown_verifiers, f"{label} unknown verifiers: {dict(unknown_verifiers)}")
    require(not category_scope_violations, f"{label} category scope violations: {dict(category_scope_violations)}")
    return {
        "label": label,
        "path": rel(path),
        "task_count": len(tasks),
        "unique_verifier_count": len(verifier_counts),
        "verifier_counts": dict(sorted(verifier_counts.items())),
        "category_verifier_counts": {
            category: dict(sorted(counts.items())) for category, counts in sorted(category_counts.items())
        },
    }


def build_report() -> dict[str, Any]:
    catalog = load_json(CONTRACTS_PATH)
    contracts = validate_contracts(catalog)
    summaries = [
        task_bank_summary(label, path, expected_count, contracts)
        for label, path, expected_count in TASK_BANKS
    ]
    used_verifiers = sorted({verifier for summary in summaries for verifier in summary["verifier_counts"]})
    unused_contracts = sorted(set(contracts) - set(used_verifiers))
    require(not unused_contracts, f"unused verifier contracts: {unused_contracts}")
    return {
        "report": "verifier-contract-readiness",
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "status": "passed",
        "counts_as_experiment": False,
        "contract_count": len(contracts),
        "covered_verifier_count": len(used_verifiers),
        "task_bank_count": len(summaries),
        "task_count_checked": sum(summary["task_count"] for summary in summaries),
        "used_verifiers": used_verifiers,
        "unused_contracts": unused_contracts,
        "task_banks": summaries,
        "evidence_artifacts": [
            rel(CONTRACTS_PATH),
            *[rel(path) for _, path, _ in TASK_BANKS],
        ],
        "evidence_boundary": (
            "This report checks machine-readable verifier contract coverage for task definitions. "
            "It does not claim full verifier implementation coverage or mobile-device execution."
        ),
        "open_requirements": [
            "complete_full_seed_task_verifier_implementation",
            "execute_mobile_tier_verifiers_on_real_or_simulated_devices",
            "attach_verifier_outputs_to_final_frozen_subset",
        ],
    }


def write_markdown(report: dict[str, Any]) -> None:
    lines = [
        "# Verifier Contract Readiness",
        "",
        f"Generated at: `{report['generated_at']}`",
        f"Status: `{report['status']}`",
        f"Counts as experiment: `{str(report['counts_as_experiment']).lower()}`",
        "",
        "## Evidence Boundary",
        "",
        report["evidence_boundary"],
        "",
        "## Coverage",
        "",
        f"- Contract count: `{report['contract_count']}`",
        f"- Covered verifier count: `{report['covered_verifier_count']}`",
        f"- Task banks checked: `{report['task_bank_count']}`",
        f"- Task definitions checked: `{report['task_count_checked']}`",
        "",
        "## Task Banks",
        "",
        "| Task bank | Tasks | Unique verifiers | Path |",
        "| --- | ---: | ---: | --- |",
    ]
    for summary in report["task_banks"]:
        lines.append(
            f"| {summary['label']} | {summary['task_count']} | {summary['unique_verifier_count']} | `{summary['path']}` |"
        )
    lines.extend(["", "## Verifiers", ""])
    for verifier_id in report["used_verifiers"]:
        lines.append(f"- `{verifier_id}`")
    lines.extend(["", "## Open Requirements", ""])
    for requirement in report["open_requirements"]:
        lines.append(f"- `{requirement}`")
    lines.append("")
    REPORT_MD_PATH.write_text("\n".join(lines), encoding="utf-8", newline="")


def main() -> int:
    REPORTS_ROOT.mkdir(parents=True, exist_ok=True)
    report = build_report()
    REPORT_JSON_PATH.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_markdown(report)
    print("MobileHarnessBench verifier contract readiness generated")
    print(f"report_json={rel(REPORT_JSON_PATH)}")
    print(f"report_md={rel(REPORT_MD_PATH)}")
    print(f"status={report['status']}")
    print(f"contracts={report['contract_count']}")
    print(f"task_definitions_checked={report['task_count_checked']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
