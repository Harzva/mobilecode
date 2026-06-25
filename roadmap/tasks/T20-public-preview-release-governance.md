# T20 Public Preview Release Governance

Status: [x] Implemented (templates and readiness checker updated)
Priority: P2
Owner role: quality-reviewer + software-dev-pipeline
Depends on: T02, T03, T05

## Objective

补齐 MobileCode 面向公开预览发布的治理材料：release process、QA 模板、截图计划、native validation、accessibility、CI 门禁。

## Read First

- `docs/mobilecode-release-qa.md`
- `docs/mobilecode-version-policy.md`
- `docs/mobilecode-v1-runtime-release-closure.md`
- `roadmap/tasks/T02-capability-matrix.md`
- `roadmap/tasks/T05-release-honesty-checks.md`
- `.github/workflows/` if changing CI docs or checks

## Can Edit

- `docs/mobilecode-release-process.md`
- `docs/mobilecode-manual-qa-template.md`
- `docs/mobilecode-native-validation-result-template.md`
- `docs/mobilecode-accessibility-qa-result-template.md`
- `docs/mobilecode-screenshot-plan.md`
- `scripts/check_mobilecode_release_readiness.py`
- `.github/workflows/*` only for docs/release readiness checks
- `roadmp.md`
- this task file

## Do Not Edit

- App feature code.
- Runtime behavior.
- Local build artifacts.

## Required Docs

- Release process。
- Manual QA template。
- Native validation template。
- Accessibility QA template。
- Screenshot plan。
- Screenshot asset conventions。
- Release verification record。

## Acceptance Criteria

- Release notes can cite CI run, APK artifact, manual QA state and known limitations.
- Screenshot and native validation are planned before public release.
- Accessibility checks have a repeatable template.
- Release readiness checker knows which docs must exist.

## Validation

```powershell
Test-Path .\docs\mobilecode-release-process.md
Test-Path .\docs\mobilecode-manual-qa-template.md
Test-Path .\docs\mobilecode-native-validation-result-template.md
Test-Path .\docs\mobilecode-accessibility-qa-result-template.md
Test-Path .\docs\mobilecode-screenshot-plan.md
```

## Handoff Prompt

请实现 T20。只做发布治理材料和轻量检查，不本地构建。所有 release claim 必须回连 capability matrix。

## Completion Notes

**Implemented**:
- `docs/mobilecode-manual-qa-template.md` — 6 test scenario categories, evidence collection commands, sign-off section.
- `docs/mobilecode-native-validation-result-template.md` — multi-device install/launch/crash validation, permissions check.
- `docs/mobilecode-accessibility-qa-result-template.md` — touch targets, contrast, content descriptions, screen reader, text scaling, motion.
- `docs/mobilecode-screenshot-plan.md` — 7 required screenshots, naming convention, capture commands, quality checklist.
- `scripts/check_mobilecode_release_readiness.py` updated — now requires 11 governance docs (was 6).
- `docs/mobilecode-release-process.md` updated — references all 4 new templates.

**Not done** (intentionally):
- No local build artifacts.
- No automated UI testing.
- No app store metadata.
