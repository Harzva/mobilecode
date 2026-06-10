#!/usr/bin/env python3
"""Generate the baseline run contract report.

This is a schema/readiness artifact only. It defines how future baseline
results must be recorded, but it does not create or count any baseline result.
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
BENCH_ROOT = ROOT / "docs" / "mobile-harness-benchmark"
REPORTS_ROOT = BENCH_ROOT / "reports"
SCHEMA_PATH = BENCH_ROOT / "schema" / "baseline_run.schema.json"
BASELINE_PROTOCOL_PATH = REPORTS_ROOT / "baseline-protocol-readiness.json"
FROZEN_SUBSET_PATH = BENCH_ROOT / "tasks" / "frozen-v2-paper-subset.json"

CONTRACT_JSON_PATH = REPORTS_ROOT / "baseline-run-contract.json"
CONTRACT_MD_PATH = REPORTS_ROOT / "baseline-run-contract.md"


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def load_json(path: Path) -> Any:
    if not path.exists():
        raise SystemExit(f"missing required artifact: {rel(path)}")
    return json.loads(path.read_text(encoding="utf-8"))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"baseline run contract generation failed: {message}")


def main() -> int:
    REPORTS_ROOT.mkdir(parents=True, exist_ok=True)
    schema = load_json(SCHEMA_PATH)
    protocol = load_json(BASELINE_PROTOCOL_PATH)
    frozen_subset = load_json(FROZEN_SUBSET_PATH)

    require(protocol.get("status") == "protocol_defined_no_results", "baseline protocol must define no results")
    require(protocol.get("counts_as_baseline_result") is False, "baseline protocol must not count as result")
    require(frozen_subset.get("counts_as_final_paper_subset") is False, "draft frozen subset must remain non-final")
    require(len(frozen_subset.get("tasks", [])) == 60, "draft frozen subset must contain 60 tasks")

    required_top_level = schema.get("required", [])
    result_required = schema.get("properties", {}).get("results", {}).get("items", {}).get("required", [])
    summary_required = schema.get("properties", {}).get("summary", {}).get("required", [])
    metric_required = schema.get("$defs", {}).get("metrics", {}).get("required", [])
    evidence_required = schema.get("$defs", {}).get("evidence", {}).get("required", [])

    required_baselines = {item.get("id") for item in protocol.get("baselines", [])}
    require(
        required_baselines == {
            "chat_only_mobile_coding_flow",
            "desktop_remote_ide_flow",
            "mobile_harness_flow",
        },
        "baseline protocol must define the three required baselines",
    )
    require(set(protocol.get("metrics", [])) == set(metric_required), "protocol metrics must match schema metrics")

    report = {
        "report": "baseline-run-contract",
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "status": "contract_defined_no_results",
        "counts_as_experiment": False,
        "counts_as_baseline_result": False,
        "schema": {
            "path": rel(SCHEMA_PATH),
            "schema_id": schema.get("$id"),
            "title": schema.get("title"),
            "required_top_level": required_top_level,
            "required_summary_fields": summary_required,
            "required_result_fields": result_required,
            "required_metrics": metric_required,
            "required_evidence_fields": evidence_required,
        },
        "baseline_ids": sorted(required_baselines),
        "task_subset": {
            "name": "frozen-v2-paper-subset",
            "path": rel(FROZEN_SUBSET_PATH),
            "task_count": len(frozen_subset.get("tasks", [])),
            "counts_as_final_paper_subset": frozen_subset.get("counts_as_final_paper_subset"),
        },
        "future_artifacts": [
            "docs/mobile-harness-benchmark/baselines/<run-id>/baseline-run.json",
            "docs/mobile-harness-benchmark/baselines/<run-id>/baseline-summary.md",
            "docs/mobile-harness-benchmark/baselines/<run-id>/baseline-traces.jsonl",
            "docs/mobile-harness-benchmark/baselines/<run-id>/artifacts/",
        ],
        "result_count": 0,
        "evidence_boundary": (
            "This contract defines future baseline result shape only. It has zero results and must not be "
            "reported as a baseline comparison until valid baseline-run artifacts exist for all three flows."
        ),
        "source_artifacts": [
            rel(SCHEMA_PATH),
            rel(BASELINE_PROTOCOL_PATH),
            rel(FROZEN_SUBSET_PATH),
        ],
    }

    CONTRACT_JSON_PATH.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    lines = [
        "# Baseline Run Contract",
        "",
        f"Generated at: `{report['generated_at']}`",
        f"Status: `{report['status']}`",
        "",
        "## Evidence Boundary",
        "",
        report["evidence_boundary"],
        "",
        "## Required Top-Level Fields",
        "",
        *[f"- `{field}`" for field in required_top_level],
        "",
        "## Required Metrics",
        "",
        *[f"- `{field}`" for field in metric_required],
        "",
        "## Required Evidence Fields",
        "",
        *[f"- `{field}`" for field in evidence_required],
        "",
        "## Future Artifacts",
        "",
        *[f"- `{artifact}`" for artifact in report["future_artifacts"]],
        "",
    ]
    CONTRACT_MD_PATH.write_text("\n".join(lines), encoding="utf-8", newline="")

    print("MobileHarnessBench baseline run contract generated")
    print(f"report_json={rel(CONTRACT_JSON_PATH)}")
    print(f"report_md={rel(CONTRACT_MD_PATH)}")
    print(f"status={report['status']}")
    print(f"baseline_count={len(report['baseline_ids'])}")
    print(f"metric_count={len(metric_required)}")
    print("counts_as_baseline_result=False")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
