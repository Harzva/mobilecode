# MobileCode Version Policy

## Summary

MobileCode uses semantic versioning, but the project is still pre-1.0. The version number should communicate release intent clearly, not simply increase because work happened.

Current next release line: `0.1.10+29`.

## Version Lines

| Version line | Meaning | Examples |
| --- | --- | --- |
| `0.1.x` | v1 Runtime closure, bug fixes, QA hardening, release polish | provider settings, chat stop button, runtime diagnostics wording, APK smoke fixes |
| `0.2.0` | first larger runtime capability expansion after v1 closure | Helper APK foreground service maturity, task persistence, streaming logs recovery |
| `0.3.0` | new product workflow surface built on runtime abstraction | project import/clone flow, structured runtime actions in real UI |
| `1.0.0` | stable v1 product release | documented install path, repeatable APK release, passing CI, runtime state understandable to normal users |

## Build Number Rule

Flutter uses `version: MAJOR.MINOR.PATCH+BUILD`.

- Increment `PATCH` for user-visible fixes inside the same release scope.
- Increment `MINOR` for a new capability line or workflow that changes the product boundary.
- Increment `BUILD` for every APK artifact built for QA or release.

Examples:

- `0.1.0+19`: first v1 runtime closure baseline APK.
- `0.1.1+20`: provider settings, chat session, pause/streaming, and diagnostics fixes.
- `0.1.2+21`: follow-up QA fix for chat persistence, generated artifact actions, browser preview, and tool-call detail UX.
- `0.1.3+22`: real Skill/MCP/Memory/Agent management routes, read-only Hook Registry, default HTML/UI skills, and extension source hardening.
- `0.1.4+23`: HTML/UI skill prompt injection, account-free curated GitHub skill/MCP source adapters, and Node 24 GitHub Actions updates.
- `0.1.5+24`: GitHub Pages pre-publish checks, published work cards with live Pages thumbnail, and Lark CLI structured dry-run actions.
- `0.1.6+25`: agent process role avatar polish, Claude Yellow / Codex Blue theme options, and release artifact version alignment.
- `0.1.7+26`: browser open preference, MobileCode Projects workspace browser, project-folder actions, Git folder badge, and official GitHub icon polish.
- `0.1.8+27`: GitHub Repo Hub, repo watchlist, phone workspace mapping, and lightweight GitHub Actions status/dispatch entrypoint.
- `0.1.9+28`: GitHub Repo Hub Actions polling/artifact download and API-backed file tree/read/edit/commit workspace flow.
- `0.1.10+29`: Runtime UX polish for folded code viewing, bottom trace progress, respectful chat scrolling, and visual Role Recruit / RR mode roles.
- `0.2.0+30`: Helper APK/runtime capability expansion starts.

## Stop Rules

Stay on `0.1.x` until these are true:

- User can configure managed or custom provider with Base URL.
- Chat can create/select conversations reliably.
- Agent provider calls show progress and can be stopped.
- Runtime Diagnostics explains Helper, External Termux, planned Embedded Lite, Cloud, and WebViewOnly without false red failures.
- Android APK build and install smoke evidence exists for the exact release commit.

Move to `0.2.0` only when the release adds a real runtime capability, not just UI polish. The recommended `0.2.0` trigger is a usable MobileCode Helper APK foreground service with task recovery evidence.

Do not tag `1.0.0` until the app is installable, testable, documented, and understandable without developer guidance.

## Release Naming

Release tags should match the product version:

- Tag: `v0.1.10`
- APK asset: `mobilecode-v0.1.10.apk`
- iOS simulator asset: `mobilecode-ios-simulator-v0.1.10.zip`

If a release tag is supplied manually in GitHub Actions, artifact names should follow that tag.
