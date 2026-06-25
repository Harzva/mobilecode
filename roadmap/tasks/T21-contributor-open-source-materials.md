# T21 Contributor 与 Open-source Materials

Status: [x] Implemented
Priority: P2
Owner role: project-inventory + quality-reviewer
Depends on: T20

## Objective

补齐 MobileCode 的开源协作材料，让外部贡献者能理解项目边界、运行方式、good first issues 和问题模板。

## Read First

- `README.md`
- `docs/mobilecode-capability-matrix.md`
- `docs/mobilecode-release-process.md`
- `docs/mobilecode-security-model.md`
- `AGENTS.md`
- `.github/` existing templates and workflows

## Can Edit

- `docs/mobilecode-contributor-onboarding.md`
- `docs/mobilecode-good-first-issues.md`
- `.github/ISSUE_TEMPLATE/`
- `README.md` short links only
- `roadmp.md`
- this task file

## Do Not Edit

- App code.
- Runtime code.
- Release automation unless T20 requests it.

## Required Materials

- Contributor onboarding。
- Good first issues。
- Bug report template。
- Feature request template。
- Runtime bug template。
- GitRuntime bug template。
- Release blocker template。
- Docs feedback template。

## Acceptance Criteria

- New contributor can find setup limitations and no-local-build rule.
- Good first issues avoid high-risk Git write tasks.
- Issue templates ask for runtime provider, APK version, CI run, device/emulator and logs.
- README links to onboarding without becoming too long.

## Validation

```powershell
Test-Path .\docs\mobilecode-contributor-onboarding.md
Test-Path .\docs\mobilecode-good-first-issues.md
Get-ChildItem .\.github\ISSUE_TEMPLATE -ErrorAction SilentlyContinue
```

## Handoff Prompt

请实现 T21。重点是降低贡献门槛和减少错误 issue。不要把 high-risk Git write 任务列为 good first issue。

## Completion Notes

**Implemented**:
- `docs/mobilecode-contributor-onboarding.md` — project overview, key constraints (no local build, release honesty, security model), getting started, work organization, submission process, issue template guide.
- `docs/mobilecode-good-first-issues.md` — documentation, app UI, scripts/tooling tasks with risk levels; explicit "what NOT to pick" section excluding high-risk Git write and runtime tasks.
- `.github/ISSUE_TEMPLATE/bug_report.md` — general app bug with environment, device, provider fields.
- `.github/ISSUE_TEMPLATE/feature_request.md` — feature proposal with capability matrix reference check.
- `.github/ISSUE_TEMPLATE/runtime_bug.md` — runtime provider bug with provider selection, diagnostics output, CI run reference.
- `.github/ISSUE_TEMPLATE/gitruntime_bug.md` — GitRuntime bug with feature selection (file preview, status, diff, commit plan, secret scan, etc.).
- `.github/ISSUE_TEMPLATE/release_blocker.md` — release blocker with severity, release impact, CI evidence.
- `.github/ISSUE_TEMPLATE/docs_feedback.md` — documentation feedback with document selection, current/suggested text.
- `.github/ISSUE_TEMPLATE/config.yml` — disables blank issues, adds contact links to capability matrix and onboarding.
- `README.md` — added Contributing section with short links to onboarding, good first issues, and issue templates.

**Not done** (intentionally):
- No app code changes.
- No runtime code changes.
- No CI workflow changes.
