#!/usr/bin/env python3
"""Generate a bibliography-readiness report for the Mobile Harness paper."""

from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PAPER_ROOT = ROOT / "paper" / "iclr-mobile-harness"
BENCH_ROOT = ROOT / "docs" / "mobile-harness-benchmark"
REPORTS_ROOT = BENCH_ROOT / "reports"

MAIN_TEX_PATH = PAPER_ROOT / "main.tex"
REFERENCES_PATH = PAPER_ROOT / "references.bib"
REPORT_JSON_PATH = REPORTS_ROOT / "bibliography-readiness.json"
REPORT_MD_PATH = REPORTS_ROOT / "bibliography-readiness.md"

EXPECTED_REFERENCES = {
    "swebench": {
        "year": "2024",
        "eprint": "2310.06770",
        "source": "OpenReview ICLR 2024 and arXiv",
        "source_url": "https://openreview.net/forum?id=VTF8yNQM66",
    },
    "webarena": {
        "year": "2024",
        "eprint": "2307.13854",
        "source": "ICLR 2024 and arXiv",
        "source_url": "https://arxiv.org/abs/2307.13854",
    },
    "mind2web": {
        "year": "2023",
        "eprint": "2306.06070",
        "source": "NeurIPS 2023 and arXiv",
        "source_url": "https://arxiv.org/abs/2306.06070",
    },
    "osworld": {
        "year": "2024",
        "eprint": "2404.07972",
        "source": "NeurIPS 2024 and arXiv",
        "source_url": "https://arxiv.org/abs/2404.07972",
    },
    "aitw": {
        "year": "2023",
        "eprint": "2307.10088",
        "source": "NeurIPS 2023 and arXiv",
        "source_url": "https://arxiv.org/abs/2307.10088",
    },
    "androidworld": {
        "year": "2025",
        "eprint": "2405.14573",
        "source": "OpenReview ICLR 2025 and arXiv",
        "source_url": "https://openreview.net/forum?id=il5yUQsrjC",
    },
    "mobileagentbench": {
        "year": "2024",
        "eprint": "2406.08184",
        "source": "arXiv",
        "source_url": "https://arxiv.org/abs/2406.08184",
    },
    "phoneworld": {
        "year": "2026",
        "eprint": "2605.29486",
        "source": "arXiv",
        "source_url": "https://arxiv.org/abs/2605.29486",
    },
    "appworld": {
        "year": "2024",
        "eprint": "2407.18901",
        "source": "ACL Anthology and arXiv",
        "source_url": "https://aclanthology.org/2024.acl-long.850/",
    },
}


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"bibliography readiness generation failed: {message}")


def parse_bibtex(text: str) -> dict[str, dict[str, str]]:
    entries: dict[str, dict[str, str]] = {}
    entry_pattern = re.compile(r"@(?P<type>\w+)\s*\{\s*(?P<key>[^,]+),(?P<body>.*?)(?=^@\w+\s*\{|\Z)", re.S | re.M)
    field_pattern = re.compile(r"^\s*(?P<field>[A-Za-z]+)\s*=\s*\{(?P<value>.*?)\},?\s*$", re.M)
    for match in entry_pattern.finditer(text):
        key = match.group("key").strip()
        body = match.group("body")
        fields = {"entry_type": match.group("type").lower()}
        for field_match in field_pattern.finditer(body):
            fields[field_match.group("field").lower()] = re.sub(r"\s+", " ", field_match.group("value").strip())
        entries[key] = fields
    return entries


def parse_cited_keys(text: str) -> set[str]:
    keys: set[str] = set()
    for match in re.finditer(r"\\cite[tp]?\{([^}]+)\}", text):
        keys.update(key.strip() for key in match.group(1).split(",") if key.strip())
    return keys


def build_report() -> dict[str, object]:
    references_text = REFERENCES_PATH.read_text(encoding="utf-8")
    paper_text = MAIN_TEX_PATH.read_text(encoding="utf-8")
    entries = parse_bibtex(references_text)
    cited_keys = parse_cited_keys(paper_text)

    expected_keys = set(EXPECTED_REFERENCES)
    actual_keys = set(entries)
    missing_entries = sorted(expected_keys - actual_keys)
    unexpected_entries = sorted(actual_keys - expected_keys)
    missing_cited_keys = sorted(cited_keys - actual_keys)
    uncited_reference_keys = sorted(actual_keys - cited_keys)
    require(not missing_entries, f"missing expected references: {missing_entries}")
    require(not unexpected_entries, f"unexpected references: {unexpected_entries}")
    require(not missing_cited_keys, f"paper cites keys missing from references.bib: {missing_cited_keys}")
    require(not uncited_reference_keys, f"references.bib contains uncited keys: {uncited_reference_keys}")

    checked_entries = []
    for key in sorted(EXPECTED_REFERENCES):
        expected = EXPECTED_REFERENCES[key]
        entry = entries[key]
        for field in ("title", "author", "year", "url"):
            require(field in entry and entry[field], f"{key} missing required field {field}")
        require("others" not in entry["author"].lower(), f"{key} still uses an author placeholder")
        require(entry["year"] == expected["year"], f"{key} year mismatch: {entry['year']} != {expected['year']}")
        require(entry.get("eprint") == expected["eprint"], f"{key} eprint mismatch")
        require(entry.get("archiveprefix") == "arXiv", f"{key} missing archivePrefix=arXiv")
        require(entry.get("primaryclass"), f"{key} missing arXiv primaryClass")
        checked_entries.append(
            {
                "key": key,
                "entry_type": entry["entry_type"],
                "year": entry["year"],
                "eprint": entry["eprint"],
                "url": entry["url"],
                "source": expected["source"],
                "source_url": expected["source_url"],
                "status": "verified",
            }
        )

    return {
        "report": "bibliography-readiness",
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "status": "passed",
        "entry_count": len(checked_entries),
        "cited_key_count": len(cited_keys),
        "missing_entries": missing_entries,
        "unexpected_entries": unexpected_entries,
        "missing_cited_keys": missing_cited_keys,
        "uncited_reference_keys": uncited_reference_keys,
        "remaining_draft_entries": [],
        "open_requirements": [],
        "source_policy": "Each cited related-work entry has stable metadata, an official source URL, arXiv eprint metadata where available, and no author placeholder.",
        "evidence_artifacts": [rel(REFERENCES_PATH), rel(MAIN_TEX_PATH)],
        "entries": checked_entries,
    }


def write_markdown(report: dict[str, object]) -> None:
    lines = [
        "# Bibliography Readiness",
        "",
        f"Generated at: `{report['generated_at']}`",
        f"Status: `{report['status']}`",
        "",
        "## Source Policy",
        "",
        str(report["source_policy"]),
        "",
        "## Entries",
        "",
        "| Key | Year | Eprint | Source | Status |",
        "| --- | --- | --- | --- | --- |",
    ]
    for entry in report["entries"]:
        lines.append(
            "| {key} | {year} | {eprint} | [{source}]({source_url}) | {status} |".format(
                key=entry["key"],
                year=entry["year"],
                eprint=entry["eprint"],
                source=entry["source"],
                source_url=entry["source_url"],
                status=entry["status"],
            )
        )
    lines.extend(["", "## Open Requirements", ""])
    if report["open_requirements"]:
        for requirement in report["open_requirements"]:
            lines.append(f"- `{requirement}`")
    else:
        lines.append("- None for the current related-work bibliography metadata.")
    lines.append("")
    REPORT_MD_PATH.write_text("\n".join(lines), encoding="utf-8", newline="")


def main() -> int:
    REPORTS_ROOT.mkdir(parents=True, exist_ok=True)
    report = build_report()
    REPORT_JSON_PATH.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_markdown(report)
    print("MobileHarnessBench bibliography readiness generated")
    print(f"report_json={rel(REPORT_JSON_PATH)}")
    print(f"report_md={rel(REPORT_MD_PATH)}")
    print(f"status={report['status']}")
    print(f"entries={report['entry_count']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
