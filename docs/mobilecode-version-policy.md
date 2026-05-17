# MobileCode Version Policy

## Summary

MobileCode uses semantic versioning, but the project is still pre-1.0. The version number should communicate release intent clearly, not simply increase because work happened.

Current next release line: `0.1.2+21`.

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

- Tag: `v0.1.2`
- APK asset: `mobilecode-v0.1.2.apk`
- iOS simulator asset: `mobilecode-ios-simulator-v0.1.2.zip`

If a release tag is supplied manually in GitHub Actions, artifact names should follow that tag.
