# Agent Notes

- Mac local development is a first-class supported path for MobileCode.
- Mac local compilation is fully supported, not limited support. Prefer it when the required Flutter, Android, Xcode, or emulator toolchain is available.
- Local build, test, install, launch, log, and screenshot workflows are allowed on Mac and should be used before relying on GitHub Actions when they can produce faster evidence.
- GitHub Actions remains required for remote CI, release packaging, public artifacts, and final repository-side verification.
- Do not commit generated build artifacts, `.dart_tool/`, `build/`, `Pods/`, raw logs with secrets, raw `.xcresult` bundles, local signing files, Android `local.properties`, credentials, tokens, cookies, or private local paths.
- For local code search, prefer `rg` for text search, `rg --files` or `fd` for file discovery, and `ast-grep`/`sg` for syntax-aware code pattern search. Use `semgrep` for security, policy, or cross-file rule scans. Use ad hoc Python `re` only for small one-off text extraction after the match set is understood.
- For Dart/Flutter work, prefer `dart analyze` and analyzer output for semantic errors before broad regex rewrites. Avoid regex-based edits for imports, widget trees, routes, and generated files unless the target files are first inspected.
- 涉及 GitHub 全流程管理（pull/push、Issues/PR、Actions、Releases、GitHub Pages、README 优化、推送失败排障）时，优先使用本地 Codex 技能 `$github-management-suite`；其中账号/远端/push 身份用 `$gh-account-router`，Actions/构建发布用 `$gh-actions-release-builder`，README 优化用 `$readme-design`，产品级发布质量门禁结合 `$software-dev-pipeline`。
- `@cxspark` and the common typo `@cxsaprk` mean: delegate a bounded non-multimodal coding/debugging/refactor/docs subtask through the locally installed `cxspark` skill, then have the parent Codex session inspect Spark output, inspect diffs, run targeted verification, and only then accept or report the result.
- On macOS/Linux, cxspark review closure must use the skill's `cxspark-mark-reviewed.sh` helper. Do not call or require `.ps1`/`pwsh` for the macOS/Linux cxspark path.
