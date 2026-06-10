#!/usr/bin/env python3
"""Generate a page-limit readiness report for the Mobile Harness paper draft."""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
PAPER_ROOT = ROOT / "paper" / "iclr-mobile-harness"
REPORTS_ROOT = ROOT / "docs" / "mobile-harness-benchmark" / "reports"

MAIN_TEX_PATH = PAPER_ROOT / "main.tex"
MAIN_PDF_PATH = PAPER_ROOT / "main.pdf"
REPORT_JSON_PATH = REPORTS_ROOT / "page-limit-readiness.json"
REPORT_MD_PATH = REPORTS_ROOT / "page-limit-readiness.md"

MAIN_TEXT_PAGE_LIMIT = 9


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"page-limit readiness generation failed: {message}")


def run_text_command(args: list[str]) -> str:
    try:
        completed = subprocess.run(
            args,
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except FileNotFoundError as exc:
        raise SystemExit(f"page-limit readiness generation failed: missing tool {args[0]!r}") from exc
    except subprocess.CalledProcessError as exc:
        stderr = exc.stderr.strip()
        raise SystemExit(f"page-limit readiness generation failed: {' '.join(args)}: {stderr}") from exc
    return completed.stdout


def pdfinfo_summary(pdf_path: Path) -> dict[str, int]:
    output = run_text_command(["pdfinfo", str(pdf_path)])
    values: dict[str, int] = {}
    for line in output.splitlines():
        if ":" not in line:
            continue
        key, raw_value = line.split(":", 1)
        key = key.strip().lower().replace(" ", "_")
        raw_value = raw_value.strip().split()[0] if raw_value.strip() else ""
        if key in {"pages", "file_size"} and raw_value.isdigit():
            values[key] = int(raw_value)
    require("pages" in values, "pdfinfo did not return page count")
    require("file_size" in values, "pdfinfo did not return file size")
    return values


def page_text(pdf_path: Path, page_number: int) -> str:
    return run_text_command(["pdftotext", "-f", str(page_number), "-l", str(page_number), str(pdf_path), "-"])


def normalized_heading(line: str) -> str:
    return "".join(character for character in line.upper() if character.isalpha())


def find_heading_page(pdf_path: Path, page_count: int, expected_heading: str) -> int | None:
    for page_number in range(1, page_count + 1):
        for line in page_text(pdf_path, page_number).splitlines():
            if normalized_heading(line) == expected_heading:
                return page_number
    return None


def with_ascii_pdf_copy() -> Path:
    """Copy the PDF to an ASCII temp path for Windows Poppler tools."""
    temp_dir = Path(tempfile.mkdtemp(prefix="mobile_harness_pdf_"))
    temp_pdf_path = temp_dir / "main.pdf"
    shutil.copy2(MAIN_PDF_PATH, temp_pdf_path)
    return temp_pdf_path


def assert_main_tex_terms() -> list[str]:
    text = MAIN_TEX_PATH.read_text(encoding="utf-8")
    required_terms = [
        "\\section{Reproducibility Statement}",
        "\\section{Ethics Statement}",
        "\\bibliography{references}",
    ]
    missing = [term for term in required_terms if term not in text]
    require(not missing, f"main.tex missing page-limit terms: {missing}")
    return required_terms


def build_report() -> dict[str, Any]:
    require(MAIN_PDF_PATH.exists(), f"missing compiled PDF: {rel(MAIN_PDF_PATH)}")
    checked_terms = assert_main_tex_terms()
    temp_pdf_path = with_ascii_pdf_copy()
    try:
        pdfinfo = pdfinfo_summary(temp_pdf_path)
        pdf_pages = pdfinfo["pages"]
        reference_start_page = find_heading_page(temp_pdf_path, pdf_pages, "REFERENCES")
        ethics_statement_page = find_heading_page(temp_pdf_path, pdf_pages, "ETHICSSTATEMENT")
    finally:
        shutil.rmtree(temp_pdf_path.parent, ignore_errors=True)
    require(reference_start_page is not None, "could not locate References heading in compiled PDF")
    require(ethics_statement_page is not None, "could not locate Ethics Statement heading in compiled PDF")

    main_text_upper_bound = reference_start_page
    within_main_text_limit = main_text_upper_bound <= MAIN_TEXT_PAGE_LIMIT
    require(within_main_text_limit, "main text appears to exceed the current page limit")

    return {
        "report": "page-limit-readiness",
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "status": "passed",
        "main_text_page_limit": MAIN_TEXT_PAGE_LIMIT,
        "pdf_pages": pdf_pages,
        "pdf_file_bytes": pdfinfo["file_size"],
        "actual_pdf_file_bytes": MAIN_PDF_PATH.stat().st_size,
        "ethics_statement_page": ethics_statement_page,
        "references_start_page": reference_start_page,
        "main_text_with_ethics_pages_upper_bound": main_text_upper_bound,
        "within_main_text_limit": within_main_text_limit,
        "references_are_unlimited": True,
        "counts_as_experiment": False,
        "checked_main_tex_terms": checked_terms,
        "evidence_artifacts": [rel(MAIN_TEX_PATH), rel(MAIN_PDF_PATH)],
        "caveat": (
            "This report verifies the compiled draft page boundary, not venue upload readiness. "
            "It must be regenerated after paper text, bibliography, style-file or template changes."
        ),
    }


def write_markdown(report: dict[str, Any]) -> None:
    lines = [
        "# Page-Limit Readiness",
        "",
        f"Generated at: `{report['generated_at']}`",
        f"Status: `{report['status']}`",
        f"Within main-text limit: `{str(report['within_main_text_limit']).lower()}`",
        "",
        "## Current Compile",
        "",
        f"- PDF pages: `{report['pdf_pages']}`",
        f"- PDF bytes: `{report['pdf_file_bytes']}`",
        f"- Main-text page limit: `{report['main_text_page_limit']}`",
        f"- Ethics statement page: `{report['ethics_statement_page']}`",
        f"- References start page: `{report['references_start_page']}`",
        f"- Main text plus ethics upper-bound pages: `{report['main_text_with_ethics_pages_upper_bound']}`",
        "",
        "## Boundary",
        "",
        report["caveat"],
        "",
    ]
    REPORT_MD_PATH.write_text("\n".join(lines), encoding="utf-8", newline="")


def main() -> int:
    REPORTS_ROOT.mkdir(parents=True, exist_ok=True)
    report = build_report()
    REPORT_JSON_PATH.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_markdown(report)
    print("MobileHarnessBench page-limit readiness generated")
    print(f"report_json={rel(REPORT_JSON_PATH)}")
    print(f"report_md={rel(REPORT_MD_PATH)}")
    print(f"status={report['status']}")
    print(f"pdf_pages={report['pdf_pages']}")
    print(f"references_start_page={report['references_start_page']}")
    print(f"within_main_text_limit={report['within_main_text_limit']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
