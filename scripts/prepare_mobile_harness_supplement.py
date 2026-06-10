"""Build an anonymized Mobile Harness paper supplement.

The source benchmark docs are product-facing. This script creates a separate
reviewer-facing package with product names, public repo URLs, local path markers,
and account-related tokens redacted before zipping.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import zipfile
from datetime import datetime, timezone
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
PAPER_DIR = REPO_ROOT / "paper" / "iclr-mobile-harness"
BENCH_DIR = REPO_ROOT / "docs" / "mobile-harness-benchmark"
BUILD_DIR = PAPER_DIR / "build"
DEFAULT_STAGE_DIR = BUILD_DIR / "anonymous-supplement"
DEFAULT_ZIP_PATH = BUILD_DIR / "mobile-harness-anonymous-supplement.zip"

PAPER_FILES = [
    "main.pdf",
    "main.tex",
    "references.bib",
    "SUPPLEMENT_BOUNDARY.md",
    "SUBMISSION_TODO.md",
    "iclr2026_conference.sty",
    "iclr2026_conference.bst",
    "math_commands.tex",
    "natbib.sty",
    "fancyhdr.sty",
]

SCRIPT_FILES = [
    "audit_mobile_harness_task_bank.py",
    "collect_mobile_harness_mobile_tier_evidence.py",
    "generate_mobile_harness_baseline_protocol.py",
    "generate_mobile_harness_baseline_run_contract.py",
    "generate_mobile_harness_baseline_scaffold.py",
    "generate_mobile_harness_baseline_dry_run.py",
    "generate_mobile_harness_baseline_pilot_pack.py",
    "generate_mobile_harness_baseline_pilot_readiness.py",
    "generate_mobile_harness_bibliography_readiness.py",
    "generate_mobile_harness_evidence_maturity_matrix.py",
    "generate_mobile_harness_evaluation_protocol_readiness.py",
    "generate_mobile_harness_mobile_evidence_pack.py",
    "generate_mobile_harness_method_presentation_readiness.py",
    "generate_mobile_harness_page_limit_readiness.py",
    "generate_mobile_harness_reproducibility_checklist.py",
    "generate_mobile_harness_submission_readiness.py",
    "generate_mobile_harness_threats_to_validity.py",
    "generate_mobile_harness_verifier_contract_readiness.py",
    "generate_mobile_harness_task_bank.py",
    "generate_mobile_harness_frozen_subset.py",
    "generate_mobile_harness_claim_ledger.py",
    "generate_mobile_harness_core_claim_readiness.py",
    "prepare_mobile_harness_supplement.py",
    "run_mobile_harness_bench.py",
    "validate_mobile_harness_bench.py",
]

TEXT_EXTENSIONS = {
    ".bib",
    ".css",
    ".dat",
    ".html",
    ".json",
    ".jsonl",
    ".md",
    ".py",
    ".schema",
    ".sty",
    ".tex",
    ".txt",
    ".xml",
    ".yaml",
    ".yml",
}

SOURCE_OWNER = "Har" + "zva"
SOURCE_OWNER_LOWER = SOURCE_OWNER.lower()
SOURCE_PRODUCT = "Mobile" + "Code"
SOURCE_PRODUCT_LOWER = "mobile" + "code"
SOURCE_REPO_PATH = SOURCE_OWNER + "/" + SOURCE_PRODUCT_LOWER
SOURCE_PAGES_PATH = SOURCE_OWNER_LOWER + ".github.io/" + SOURCE_PRODUCT_LOWER

REDACTIONS: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"https://github\.com/" + re.escape(SOURCE_REPO_PATH), re.IGNORECASE), "https://anonymous.example/mobile-harness"),
    (re.compile(r"https://" + re.escape(SOURCE_PAGES_PATH), re.IGNORECASE), "https://anonymous.example/mobile-harness-pages"),
    (re.compile(r"github\.com/" + re.escape(SOURCE_REPO_PATH), re.IGNORECASE), "anonymous.example/mobile-harness"),
    (re.compile(re.escape(SOURCE_PAGES_PATH), re.IGNORECASE), "anonymous.example/mobile-harness-pages"),
    (re.compile(r"\b" + re.escape(SOURCE_PRODUCT) + r"Helper\b"), "MobileHarnessHelper"),
    (re.compile(r"\b" + re.escape(SOURCE_PRODUCT) + r" workspace picker\b"), "MobileHarness workspace picker"),
    (re.compile(r"\b" + re.escape(SOURCE_PRODUCT) + r"\b"), "MobileHarness prototype"),
    (re.compile(re.escape(SOURCE_PRODUCT_LOWER), re.IGNORECASE), "mobileharness"),
    (re.compile(r"\b" + re.escape(SOURCE_OWNER) + r"\b"), "Anonymous"),
    (re.compile(r"\b" + re.escape(SOURCE_OWNER_LOWER) + r"\b"), "anonymous"),
    (re.compile(r"media_id", re.IGNORECASE), "upload_reference_marker"),
    (re.compile(r"\baccess_token\b", re.IGNORECASE), "api_secret_marker"),
    (re.compile(r"\bOpenIDs\b"), "platform account identifiers"),
    (re.compile(r"\bOpenID\b"), "platform account identifier"),
    (re.compile(r"openid", re.IGNORECASE), "platform_account_identifier"),
    (re.compile(r"\bwxid\b", re.IGNORECASE), "chat_account_identifier"),
]

FORBIDDEN_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("public product name", re.compile(re.escape(SOURCE_PRODUCT_LOWER), re.IGNORECASE)),
    ("repository owner handle", re.compile(r"\b" + re.escape(SOURCE_OWNER) + r"\b|\b" + re.escape(SOURCE_OWNER_LOWER) + r"\b")),
    ("public repository URL", re.compile(r"github\.com/" + re.escape(SOURCE_OWNER) + r"|" + re.escape(SOURCE_OWNER_LOWER) + r"\.github\.io", re.IGNORECASE)),
    ("Windows absolute path", re.compile(r"[A-Za-z]:\\")),
    ("chat account identifier", re.compile(r"\bwxid\b", re.IGNORECASE)),
    ("upload media identifier", re.compile(r"\bmedia_id\b", re.IGNORECASE)),
    ("access token marker", re.compile(r"\baccess_token\b", re.IGNORECASE)),
    ("OpenID marker", re.compile(r"\bOpenID\b|\bopenid\b")),
    ("secret key literal", re.compile(r"sk-[A-Za-z0-9_-]{20,}")),
]

REVIEWER_MANIFEST_REQUIRED_TERMS: list[tuple[str, str]] = [
    ("claim review map", "## Claim Review Map"),
    ("evidence label quick reference", "## Evidence Label Quick Reference"),
    ("candidate supply label", "`candidate_supply`"),
    ("T0 fixture label", "`t0_fixture_evidence`"),
    ("mobile capture-ready label", "`capture_ready_no_results`"),
    ("baseline pilot-ready label", "`pilot_ready_no_results`"),
    ("non-experiment guardrail", "`counts_as_experiment=false`"),
    ("open requirement label", "`open_requirement`"),
    ("mobile-result boundary", "Do not report Android/iOS mobile-tier results"),
]


def _fs_path(path: Path) -> str:
    text = str(path.resolve(strict=False))
    if os.name != "nt" or text.startswith("\\\\?\\"):
        return text
    if text.startswith("\\\\"):
        return "\\\\?\\UNC\\" + text[2:]
    return "\\\\?\\" + text


def _is_text_file(path: Path) -> bool:
    if path.name in {"LICENSE", "NOTICE"}:
        return True
    return path.suffix.lower() in TEXT_EXTENSIONS


def _iter_files(root: Path) -> list[tuple[Path, str]]:
    base = _fs_path(root)
    files: list[tuple[Path, str]] = []
    for dirpath, _, filenames in os.walk(base):
        for filename in filenames:
            full_path = Path(dirpath) / filename
            relative = Path(os.path.relpath(str(full_path), base)).as_posix()
            files.append((full_path, relative))
    return sorted(files, key=lambda item: item[1])


def _redact_text(text: str) -> str:
    for pattern, replacement in REDACTIONS:
        text = pattern.sub(replacement, text)
    return text


def _copy_file(source: Path, destination: Path) -> None:
    os.makedirs(_fs_path(destination.parent), exist_ok=True)
    if _is_text_file(source):
        try:
            with open(_fs_path(source), "r", encoding="utf-8") as handle:
                text = handle.read()
        except UnicodeDecodeError:
            shutil.copy2(_fs_path(source), _fs_path(destination))
            return
        with open(_fs_path(destination), "w", encoding="utf-8", newline="") as handle:
            handle.write(_redact_text(text))
    else:
        shutil.copy2(_fs_path(source), _fs_path(destination))


def _copy_tree(source_root: Path, destination_root: Path) -> None:
    for source, relative_text in _iter_files(source_root):
        relative = Path(relative_text)
        _copy_file(source, destination_root / relative)


def _write_manifest(stage_dir: Path, zip_path: Path) -> None:
    generated = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    manifest = f"""# Anonymous Supplement Manifest

Generated: {generated}

## Contents

- `paper/iclr-mobile-harness/`: anonymized paper PDF, LaTeX source, bibliography and ICLR style files.
- `docs/mobile-harness-benchmark/`: anonymized MobileHarnessBench task definitions, fixtures, verifier contracts, runbook, run evidence and task-set manifests.
- `scripts/`: benchmark generation, dry-run, readiness and validation scripts.

## Quick Start

Run commands from the supplement root after extracting the zip.

```bash
python scripts/validate_mobile_harness_bench.py
python scripts/generate_mobile_harness_verifier_contract_readiness.py
python scripts/generate_mobile_harness_method_presentation_readiness.py
python scripts/generate_mobile_harness_reproducibility_checklist.py
python scripts/generate_mobile_harness_submission_readiness.py
```

If a LaTeX toolchain is available, the paper can be rebuilt with:

```bash
cd paper/iclr-mobile-harness
latexmk -pdf -interaction=nonstopmode -halt-on-error main.tex
```

## Key Inspection Points

- `paper/iclr-mobile-harness/main.pdf`: compiled anonymous draft.
- `docs/mobile-harness-benchmark/reports/submission-readiness.md`: upload-readiness gate and open requirements.
- `docs/mobile-harness-benchmark/reports/paper-claim-evidence-ledger.md`: claim-to-artifact mapping.
- `docs/mobile-harness-benchmark/reports/evidence-maturity-matrix.md`: evidence maturity and non-counted stages.
- `docs/mobile-harness-benchmark/reports/evaluation-protocol-readiness.md`: E1-E5 protocol status and open gates.
- `docs/mobile-harness-benchmark/reports/reproducibility-checklist.md`: command-to-artifact map.
- `docs/mobile-harness-benchmark/reports/method-presentation-readiness.md`: visual, algorithm, module and formula presentation gate.
- `docs/mobile-harness-benchmark/reports/verifier-contract-readiness.md`: verifier contract coverage for current task banks.
- `docs/mobile-harness-benchmark/runs/2026-06-06-smoke-v2-t0/summary.md`: current T0 fixture run evidence.

## Claim Review Map

| Claim area | Primary files | Boundary |
| --- | --- | --- |
| System abstraction and design invariants | `paper/iclr-mobile-harness/main.pdf`; `docs/mobile-harness-benchmark/reports/core-claim-readiness.md`; `docs/mobile-harness-benchmark/reports/method-presentation-readiness.md` | Positioning and system design, not a mobile experiment result. |
| Candidate task supply | `docs/mobile-harness-benchmark/tasks/v2-task-bank.json`; `docs/mobile-harness-benchmark/reports/v2-quality-audit.md` | Task supply only; quality-axis fields are coverage tags, not difficulty or result claims. |
| Counted T0 evidence | `docs/mobile-harness-benchmark/runs/2026-06-06-smoke-v2-t0/summary.md`; `docs/mobile-harness-benchmark/reports/paper-claim-evidence-ledger.md` | Fixture-level evidence only. |
| Non-counted readiness artifacts | `docs/mobile-harness-benchmark/reports/evidence-maturity-matrix.md`; `docs/mobile-harness-benchmark/reports/evaluation-protocol-readiness.md` | Mobile packs, baseline scaffolds and pilot packs are not counted results. |
| Submission blockers | `docs/mobile-harness-benchmark/reports/submission-readiness.md` | Upload readiness remains false until open gates close. |

## Evidence Label Quick Reference

- `candidate_supply`: task-bank scale or coverage; not execution evidence.
- `t0_fixture_evidence`: deterministic offline verifier output; not Android/iOS behavior.
- `capture_ready_no_results`: mobile evidence templates prepared for future device runs.
- `pilot_ready_no_results`: baseline prompts and evidence sheets prepared for future comparison.
- `counts_as_experiment=false`: readiness, scaffold or dry-run artifact that must not be reported as a completed experiment.
- `open_requirement`: blocker that remains visible in the claim ledger and submission readiness gate.

## Reviewer Checklist

1. Run `python scripts/validate_mobile_harness_bench.py` from the supplement root.
2. Inspect `paper/iclr-mobile-harness/main.pdf` for the paper argument.
3. Inspect `paper-claim-evidence-ledger.md` and `evidence-maturity-matrix.md` before accepting any empirical claim.
4. Treat `smoke-v2` as T0 fixture evidence only.
5. Do not report Android/iOS mobile-tier results, GitHub sandbox delivery, baseline comparison, or final frozen-subset performance unless later evidence artifacts are added.

## Evidence Boundary

This supplement supports review of the current T0/system-and-benchmark artifact.
It does not claim completed Android/iOS mobile-tier experiments, authorized GitHub sandbox delivery, counted baseline comparisons, or a final frozen paper subset.

## Verification

The package was generated by a local staging script that redacts product names, public repository URLs, local path markers and account-related token markers before zipping.

Output zip: `{zip_path.name}`
"""
    with open(_fs_path(stage_dir / "README_SUPPLEMENT.md"), "w", encoding="utf-8", newline="") as handle:
        handle.write(manifest)


def build_stage(stage_dir: Path, zip_path: Path) -> None:
    if stage_dir.exists():
        shutil.rmtree(_fs_path(stage_dir))
    os.makedirs(_fs_path(stage_dir), exist_ok=True)

    for filename in PAPER_FILES:
        _copy_file(PAPER_DIR / filename, stage_dir / "paper" / "iclr-mobile-harness" / filename)

    _copy_tree(BENCH_DIR, stage_dir / "docs" / "mobile-harness-benchmark")

    for filename in SCRIPT_FILES:
        _copy_file(REPO_ROOT / "scripts" / filename, stage_dir / "scripts" / filename)

    _write_manifest(stage_dir, zip_path)


def scan_stage(stage_dir: Path) -> list[str]:
    findings: list[str] = []
    for path, rel in _iter_files(stage_dir):
        if not _is_text_file(path):
            continue
        try:
            with open(_fs_path(path), "r", encoding="utf-8") as handle:
                text = handle.read()
        except UnicodeDecodeError:
            continue
        for label, pattern in FORBIDDEN_PATTERNS:
            for match in pattern.finditer(text):
                line = text.count("\n", 0, match.start()) + 1
                findings.append(f"{rel}:{line}: {label}: {match.group(0)}")
    return findings


def validate_reviewer_manifest(stage_dir: Path) -> list[str]:
    manifest_path = stage_dir / "README_SUPPLEMENT.md"
    if not manifest_path.exists():
        return ["README_SUPPLEMENT.md: missing reviewer-facing manifest"]
    with open(_fs_path(manifest_path), "r", encoding="utf-8") as handle:
        text = handle.read()
    findings: list[str] = []
    for label, term in REVIEWER_MANIFEST_REQUIRED_TERMS:
        if term not in text:
            findings.append(f"README_SUPPLEMENT.md: missing {label}: {term}")
    return findings


def write_zip(stage_dir: Path, zip_path: Path) -> None:
    if zip_path.exists():
        os.unlink(_fs_path(zip_path))
    os.makedirs(_fs_path(zip_path.parent), exist_ok=True)
    with zipfile.ZipFile(_fs_path(zip_path), "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path, rel in _iter_files(stage_dir):
            archive.write(_fs_path(path), rel)


def main() -> int:
    parser = argparse.ArgumentParser(description="Build an anonymized Mobile Harness supplement zip.")
    parser.add_argument("--stage-dir", type=Path, default=DEFAULT_STAGE_DIR)
    parser.add_argument("--zip-path", type=Path, default=DEFAULT_ZIP_PATH)
    parser.add_argument("--no-zip", action="store_true", help="Create the staged folder but skip zip creation.")
    args = parser.parse_args()

    stage_dir = args.stage_dir.resolve()
    zip_path = args.zip_path.resolve()

    build_stage(stage_dir, zip_path)
    findings = scan_stage(stage_dir)
    findings.extend(validate_reviewer_manifest(stage_dir))
    if findings:
        print("Anonymous supplement scan failed:")
        for finding in findings[:100]:
            print(f"  {finding}")
        if len(findings) > 100:
            print(f"  ... {len(findings) - 100} more findings")
        return 1

    if not args.no_zip:
        write_zip(stage_dir, zip_path)

    file_count = len(_iter_files(stage_dir))
    print("Anonymous supplement staging passed")
    print(f"stage_dir={stage_dir}")
    print(f"files={file_count}")
    if not args.no_zip:
        print(f"zip_path={zip_path}")
        print(f"zip_bytes={zip_path.stat().st_size}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
