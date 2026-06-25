# Agent Notes

- Mac local development is a first-class supported path for MobileCode.
- Mac local compilation is fully supported, not limited support. Prefer it when the required Flutter, Android, Xcode, or emulator toolchain is available.
- Local build, test, install, launch, log, and screenshot workflows are allowed on Mac and should be used before relying on GitHub Actions when they can produce faster evidence.
- GitHub Actions remains required for remote CI, release packaging, public artifacts, and final repository-side verification.
- Do not commit generated build artifacts, `.dart_tool/`, `build/`, `Pods/`, raw logs with secrets, raw `.xcresult` bundles, local signing files, Android `local.properties`, credentials, tokens, cookies, or private local paths.
- 涉及 GitHub 全流程管理（pull/push、Issues/PR、Actions、Releases、GitHub Pages、README 优化、推送失败排障）时，优先使用本地 Codex 技能 `$github-management-suite`；其中账号/远端/push 身份用 `$gh-account-router`，Actions/构建发布用 `$gh-actions-release-builder`，README 优化用 `$readme-design`，产品级发布质量门禁结合 `$software-dev-pipeline`。
