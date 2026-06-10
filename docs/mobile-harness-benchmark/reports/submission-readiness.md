# Submission Readiness Gate

Generated at: `2026-06-09T12:15:23Z`
Status: `passed_with_open_requirements`
Ready for submission upload: `false`

## Evidence Boundary

The draft can be reviewed as a system-and-benchmark proposal with T0 fixture evidence, but it is not upload-ready as a final empirical paper until mobile-tier and baseline evidence are attached.

## Gates

| Gate | Status | Rationale |
| --- | --- | --- |
| Manuscript source and compiled PDF exist | passed | The anonymous ICLR-style draft has LaTeX source and a compiled PDF. |
| Claims are mapped to evidence boundaries | passed_with_open_requirements | T0 fixture evidence is separated from real mobile and baseline claims. |
| Core positioning claim is evidence-bounded | passed_with_open_requirements | The paper frames mobile AI coding as a harness control plane rather than a full mobile IDE or a general phone-use benchmark. |
| Mobile-tier results are not over-claimed | open_requirement | Android/iOS readiness is recorded, but no T2/T3/T4 result is claimed. |
| Mobile-tier evidence capture pack is ready | passed | Android T2 and iOS T3 task-level evidence templates are generated but not counted as results. |
| Verifier contracts cover current task banks | passed | All verifier ids referenced by the current v0/v1/v2 task banks are covered by machine-readable verifier contracts. |
| Baseline comparison remains protocol-only | open_requirement | The baseline pilot pack is ready for execution but not ready for counted results. |
| Anonymous supplement boundary is defined | passed | The boundary document defines included artifacts, repo-compatible supplement layout, excluded private materials, and scan rules. |
| Reviewer manifest evidence labels are machine-gated | passed | The supplement staging script fails if README_SUPPLEMENT.md loses its claim map, evidence labels, or mobile-result boundary. |
| Venue, template, and authorship remain draft | open_requirement | The draft still needs venue/year confirmation, official template confirmation, and author OpenReview checks. |
| Related-work bibliography metadata is verified | passed | The current cited related-work entries have source URLs, eprint metadata where available, and no author placeholders. |
| Threats to validity are tracked | passed_with_open_requirements | Construct, internal, external, baseline, privacy and submission threats are explicit and tied to open requirements. |
| Evaluation protocol is machine-checkable | passed_with_open_requirements | E1-E5 are tied to task sets, current evidence artifacts and non-counted open requirements. |
| Method presentation is reviewable | passed | The draft has machine-checked visuals, algorithms, module interfaces, formulas and evidence-boundary language. |
| Draft reproducibility checklist is available | passed_with_open_requirements | The draft command matrix maps reproducible commands to expected artifacts while keeping full empirical reproduction open. |
| Compiled PDF page boundary is checked | passed | The compiled draft records total PDF pages, the ethics page and the References start page, and keeps the main text within the current page limit. |

## Open Requirements

- `venue_template_author_confirmation`
- `real_android_or_ios_mobile_tier_evidence`
- `counted_baseline_comparison_results`
- `final_anonymous_supplement_after_new_evidence`
