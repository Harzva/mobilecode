#!/usr/bin/env python3
"""Generate a baseline-comparison protocol readiness report.

This script defines the planned comparison protocol without reporting baseline
results. It keeps baseline design reviewable while preserving the evidence
boundary for the paper draft.
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
BENCH_ROOT = ROOT / "docs" / "mobile-harness-benchmark"
REPORTS_ROOT = BENCH_ROOT / "reports"

FROZEN_SUBSET_PATH = BENCH_ROOT / "tasks" / "frozen-v2-paper-subset.json"
MOBILE_READINESS_PATH = REPORTS_ROOT / "mobile-tier-readiness.json"
LEDGER_JSON_PATH = REPORTS_ROOT / "baseline-protocol-readiness.json"
LEDGER_MD_PATH = REPORTS_ROOT / "baseline-protocol-readiness.md"

BASELINES = [
    {
        "id": "chat_only_mobile_coding_flow",
        "name": "Chat-only mobile coding flow",
        "unit_under_test": "A mobile chat assistant without a harness evidence layer.",
        "allowed_tools": [
            "model chat",
            "manual copy/paste",
            "mobile browser or viewer",
        ],
        "evidence_requirements": [
            "prompt transcript",
            "generated artifact or explicit blocked output",
            "manual verification notes",
            "human intervention count",
        ],
        "expected_limit": "May produce plausible artifacts but lacks structured harness traces and verifier outputs.",
    },
    {
        "id": "desktop_remote_ide_flow",
        "name": "Desktop remote IDE flow",
        "unit_under_test": "A conventional desktop or remote IDE workflow used from outside the phone.",
        "allowed_tools": [
            "desktop IDE or remote editor",
            "terminal or CI logs",
            "repository commit tools",
        ],
        "evidence_requirements": [
            "diff or commit record",
            "test or preview output",
            "run logs",
            "human intervention count",
        ],
        "expected_limit": "Strong execution access, but not a phone-native control-plane baseline.",
    },
    {
        "id": "mobile_harness_flow",
        "name": "Phone-native mobile harness flow",
        "unit_under_test": "The proposed phone-native harness control loop.",
        "allowed_tools": [
            "harness action runner",
            "artifact store",
            "preview service",
            "runtime provider",
            "GitHub sandbox when authorized",
        ],
        "evidence_requirements": [
            "run.json",
            "summary.md",
            "traces.jsonl",
            "verifier outputs",
            "preview or delivery artifacts",
            "mobile-tier screenshots or logs when required",
        ],
        "expected_limit": "Cannot count as final mobile evidence until T2/T3/T5 artifacts are attached.",
    },
]

METRICS = [
    "task_success",
    "verified_success",
    "trace_completeness",
    "recovery_rate",
    "artifact_availability",
    "human_intervention_count",
    "steps_to_completion",
]

FAIRNESS_CONTROLS = [
    "Use the same frozen task subset for every baseline.",
    "Use the same input fixtures and task prompts.",
    "Record the exact model provider and model version for every run.",
    "Use the same authorization state for GitHub-delivery tasks; unavailable authorization is typed as blocked.",
    "Apply the same time budget and human-intervention logging.",
    "Do not compare T0 fixture evidence against T2/T3/T5 mobile-device evidence as if they were the same tier.",
]


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def load_json(path: Path) -> Any:
    if not path.exists():
        raise SystemExit(f"missing required artifact: {rel(path)}")
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> int:
    REPORTS_ROOT.mkdir(parents=True, exist_ok=True)
    frozen_subset = load_json(FROZEN_SUBSET_PATH)
    mobile_readiness = load_json(MOBILE_READINESS_PATH)

    task_count = len(frozen_subset.get("tasks", []))
    if frozen_subset.get("counts_as_final_paper_subset") is not False:
        raise SystemExit("baseline protocol requires the frozen subset to remain non-final")
    if task_count != 60:
        raise SystemExit(f"baseline protocol expects 60 draft frozen tasks; got {task_count}")
    if mobile_readiness.get("counts_as_experiment") is not False:
        raise SystemExit("mobile-tier readiness must remain non-experimental")

    blocked_conditions = [
        "No Android T2 run evidence is attached yet.",
        "No iOS T3/T4 run evidence is attached yet.",
        "No authorized GitHub T5 sandbox run evidence is attached yet.",
        "No model/provider lock file has been recorded for baseline runs yet.",
        "No human-intervention annotation sheet has been completed yet.",
    ]

    report = {
        "report": "baseline-protocol-readiness",
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "status": "protocol_defined_no_results",
        "counts_as_experiment": False,
        "counts_as_baseline_result": False,
        "task_subset": {
            "name": "frozen-v2-paper-subset",
            "path": rel(FROZEN_SUBSET_PATH),
            "task_count": task_count,
            "counts_as_final_paper_subset": frozen_subset.get("counts_as_final_paper_subset"),
        },
        "baselines": BASELINES,
        "metrics": METRICS,
        "fairness_controls": FAIRNESS_CONTROLS,
        "blocked_conditions": blocked_conditions,
        "required_result_artifacts": [
            "baseline-run.json",
            "baseline-summary.md",
            "baseline-traces.jsonl or equivalent transcript",
            "per-task artifact paths",
            "per-task verifier outputs",
            "mobile-tier screenshots/logs for tasks requiring mobile evidence",
            "human-intervention annotations",
        ],
        "evidence_boundary": (
            "This report defines the comparison protocol only. It contains no baseline result and must not be "
            "used as a performance table until run artifacts exist for all baselines."
        ),
        "source_artifacts": [
            rel(FROZEN_SUBSET_PATH),
            rel(MOBILE_READINESS_PATH),
        ],
    }

    LEDGER_JSON_PATH.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    lines = [
        "# Baseline Protocol Readiness",
        "",
        f"Generated at: `{report['generated_at']}`",
        f"Status: `{report['status']}`",
        "",
        "## Evidence Boundary",
        "",
        report["evidence_boundary"],
        "",
        "## Planned Baselines",
        "",
        "| Baseline | Unit under test | Expected limit |",
        "| --- | --- | --- |",
    ]
    for baseline in BASELINES:
        lines.append(
            f"| {baseline['id']} | {baseline['unit_under_test']} | {baseline['expected_limit']} |"
        )
    lines.extend([
        "",
        "## Metrics",
        "",
        *[f"- {metric}" for metric in METRICS],
        "",
        "## Fairness Controls",
        "",
        *[f"- {control}" for control in FAIRNESS_CONTROLS],
        "",
        "## Blocked Conditions",
        "",
        *[f"- {condition}" for condition in blocked_conditions],
        "",
    ])
    LEDGER_MD_PATH.write_text("\n".join(lines), encoding="utf-8", newline="")

    print("MobileHarnessBench baseline protocol generated")
    print(f"report_json={rel(LEDGER_JSON_PATH)}")
    print(f"report_md={rel(LEDGER_MD_PATH)}")
    print(f"status={report['status']}")
    print(f"baselines={len(BASELINES)}")
    print(f"metrics={len(METRICS)}")
    print("counts_as_experiment=False")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
