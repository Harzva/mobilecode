# ICLR Draft: Mobile Harnesses for AI Coding on Phones

This folder contains an anonymous ICLR-style draft using the official ICLR 2026 LaTeX template.

## Files

- `main.tex`: paper draft.
- `main.pdf`: compiled anonymous PDF draft.
- `references.bib`: related-work bibliography with current metadata verified by the bibliography-readiness gate.
- `SUPPLEMENT_BOUNDARY.md`: anonymous supplement include/exclude rules and redaction gate.
- `iclr2026_conference.sty`, `iclr2026_conference.bst`, `math_commands.tex`, `natbib.sty`, `fancyhdr.sty`: copied from the official ICLR template zip.
- `iclr2026/`: unmodified downloaded template folder.

## Build

```powershell
pdflatex main.tex
bibtex main
pdflatex main.tex
pdflatex main.tex
```

or:

```powershell
latexmk -pdf main.tex
```

## Anonymous Supplement

Refresh bibliography metadata and then the local submission-readiness gate before staging the reviewer package:

```powershell
python scripts\generate_mobile_harness_bibliography_readiness.py
python scripts\generate_mobile_harness_mobile_evidence_pack.py
python scripts\generate_mobile_harness_core_claim_readiness.py
python scripts\generate_mobile_harness_evaluation_protocol_readiness.py
python scripts\generate_mobile_harness_threats_to_validity.py
python scripts\generate_mobile_harness_page_limit_readiness.py
python scripts\generate_mobile_harness_reproducibility_checklist.py
python scripts\generate_mobile_harness_submission_readiness.py
```

Generate the current draft supplement from the repository root:

```powershell
python scripts\prepare_mobile_harness_supplement.py
```

The script stages an anonymized package at `paper/iclr-mobile-harness/build/anonymous-supplement/`, scans for product names, public repository URLs, local paths and account/token markers, then writes `paper/iclr-mobile-harness/build/mobile-harness-anonymous-supplement.zip`. The generated `build/` folder is ignored and should be regenerated after any paper, benchmark, script or real-device-result change.

## Submission Notes

- ICLR 2026 Author Guide uses double-blind submission, 9 pages for main text at submission, and the official `iclr2026.zip` template. Its full paper deadline was 2025-09-24 AOE, so this folder should be treated as an ICLR-style draft until the actual target venue/year is confirmed.
- This draft is anonymous and does not include author names.
- The paper is a scoped system-and-benchmark contribution. It must not claim that the 1,000-task candidate bank is 1,000 completed experiments.
- Before actual submission, rerun bibliography readiness after any citation change, add real mobile run results, and prepare an anonymous supplementary package following `SUPPLEMENT_BOUNDARY.md`.
- As of 2026-06-06, the local compile produces a 10-page PDF including references; the page-limit readiness report records References starting on page 9, so the main text plus ethics upper-bound remains within the current 9-page main-text limit. The current anonymous supplement script produces a draft zip and passes its local identity/path/token scan. The submission-readiness gate remains `ready_for_submission_upload=false` until venue metadata, real mobile evidence, counted baselines and final supplement regeneration are complete.
