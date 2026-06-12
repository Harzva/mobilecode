# cxspark Agent Workflow

MobileCode uses `cxspark` as a bounded Codex Spark worker role for small, text-only development tasks. It is a workflow shortcut, not a separate product surface inside the app.

`cxspark` means "Codex Spark". Treat it as a fixed job role: a temporary Spark worker can draft a narrow patch, but the parent Codex session keeps planning, review, verification, commits, pushes, releases, and all risky operations.

## Default Use

Use `cxspark` by default for non-multimodal tasks that are small enough to inspect quickly:

- README, docs, prompt, checklist, and task-bank drafts.
- Single-file or few-file mechanical edits.
- Small code patches with exact allowed files.
- Text-only second-pass review of a small diff or decision.

Keep the task in the parent Codex session when it involves:

- Screenshots, images, videos, visual UI judgment, browser QA, emulator QA, simulator QA, or device acceptance.
- Secrets, tokens, cookies, private credential files, or raw auth logs.
- Publishing, pushing, deleting, migrations, resets, or irreversible actions.
- Broad architecture, product direction, release readiness, or final sign-off.

## Bounded Task Detail

Every handoff to `cxspark` should define the boundary before the worker starts:

```text
Task:
<one precise task>

Allowed scope:
- Files: <exact files or modules>
- Behavior limits: <allowed behavior changes>
- Tests or checks: <required checks>

Forbidden actions:
- Change unrelated files.
- Read or output secrets, tokens, cookies, private account data, or raw credentials.
- Publish, delete, push, migrate, reset, or perform irreversible actions.
- Perform image, screenshot, video, browser, emulator, simulator, device, or app-interaction QA.
- Mark work final.

Expected output:
1. Summary of changes.
2. Files touched.
3. Verification performed or recommended.
4. Risks, edge cases, and assumptions.
5. Spark Usage Report.
```

## Spark Usage Report

Each worker result must report:

```text
Spark Usage Report:
- model: gpt-5.3-codex-spark
- task: <short task summary>
- files_touched: <paths or none>
- verification: <performed or recommended>
- token_usage:
  - input_tokens: <number or token_usage_unavailable>
  - output_tokens: <number or token_usage_unavailable>
  - total_tokens: <number or token_usage_unavailable>
- token_saving_evidence: <what parent-session context/work was avoided>
```

If exact token usage is not exposed by the runtime, report `token_usage_unavailable`. Do not invent token counts.

## MobileCode Acceptance Rule

For this repo, Spark output is always a draft. The parent Codex session must inspect diffs, keep public README and Pages language product-safe, run required checks, and decide whether the result is accepted.

Baseline checks before MobileCode commits remain:

```bash
cd app
npm run build

cd ..
python3 scripts/validate_mobile_harness_bench.py
```

If Flutter code changes, also try `flutter analyze` from `mobile_agent/`; if local Flutter is unavailable, record the limitation and rely on GitHub Actions for device/build evidence.
