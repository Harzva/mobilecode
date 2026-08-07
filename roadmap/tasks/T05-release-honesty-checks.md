# T05 Release Honesty Checks

Status: [x] Completed
Priority: P0
Owner role: quality-reviewer + software-dev-pipeline
Depends on: T02, T03, T04

## Objective

建立发布诚实检查，防止 README、docs、release note、商店文案宣称 MobileCode 尚未真正支持的功能。

## Read First

- `README.md`
- `docs/mobilecode-release-qa.md`
- `docs/mobilecode-version-policy.md`
- `docs/mobilecode-v1-runtime-release-closure.md`
- `roadmap/tasks/T02-capability-matrix.md`
- `roadmap/tasks/T03-risk-register.md`

## Can Edit

- `scripts/check_mobilecode_blocked_feature_claims.py`
- `scripts/check_mobilecode_release_readiness.py`
- `.github/workflows/*` only if adding a docs-only check workflow is explicitly in scope
- `docs/mobilecode-release-process.md` if needed as a stub
- `roadmp.md`
- this task file

## Do Not Edit

- App code.
- Helper code.
- Build scripts that compile or package locally.

## Blocked Claim Examples

The checker should flag unqualified claims like:

- full git client
- real git push
- private clone supported
- pull/merge/rebase supported
- creates PR automatically
- sends Lark/WeChat/GitHub messages
- production Termux runtime
- secure token storage ready

Allowed wording should require qualifiers:

- dry-run
- preview
- preflight
- demo
- blocked
- coming soon
- feature-flagged beta

## Implementation Tasks

- [x] Create blocked feature claims checker.
- [x] Create release readiness checker that verifies required docs exist.
- [x] Add docs explaining how to run the checks locally without building.
- [ ] Optionally add GitHub Actions docs-check job. (Out of scope — no workflow changes in this pass)

## Acceptance Criteria

- [x] Running the blocked claims checker scans README and release-facing docs.
- [x] The checker avoids internal roadmap/code false positives and explains how to resolve findings.
- [x] Release readiness checker fails when capability matrix/security/risk docs are missing.
- [x] No local build or compile required.

## Completion Notes

- `scripts/check_mobilecode_blocked_feature_claims.py` scans README and release-facing docs while skipping internal roadmap, scripts, code, and governance docs that intentionally enumerate blocked terms.
- `scripts/check_mobilecode_release_readiness.py` verifies governance docs and invokes the blocked-claims checker.
- `docs/mobilecode-release-process.md` documents the local no-build release governance checks.
- Codex review corrected the initial overly broad scanner after it produced false positives against roadmap tasks, code, and the scanner's own regex definitions.

## Validation

```powershell
python .\scripts\check_mobilecode_blocked_feature_claims.py
python .\scripts\check_mobilecode_release_readiness.py
```

If Python is unavailable, document that validation was not run and rely on CI.

## Handoff Prompt

请实现 T05。目标是脚本和轻量文档检查，不触碰 App 功能。脚本要保守，宁可提示人工复核，也不要静默放过高风险夸大声明。
