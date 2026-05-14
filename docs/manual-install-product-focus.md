# Manual Install Product Focus

MobileCode is distributed from GitHub Releases for now. The product target is a clean side-load experience, not App Store submission.

## Product Priorities

- The Release page must contain the latest Android APK and iOS Simulator artifact.
- The app home screen should immediately show build confidence: Android smoke, iOS simulator, provider mode, and release version.
- The first usable path is mini agent -> generated 2048 project -> WebView preview -> GitHub test.
- API configuration must stay near the top, with health visible and actionable.
- Heavy backend capability maps should stay collapsed until the user asks for detail.
- Tooling surfaces should favor short action labels, clear status, and saved local artifacts over marketing copy.

## Smoothness Targets

- Keep the top screen dense and task-focused.
- Avoid loading long capability lists by default.
- Keep modal sheets scrollable with keyboard-dismiss-on-drag.
- Show progress and tool output as incremental events, not as a final static summary.
- Prefer GitHub Actions for APK/iOS verification when local SDKs are unavailable.

## Current Release Confidence

- Android release APK builds in GitHub Actions.
- Android emulator smoke test installs and launches the debug APK, captures screenshot, and scans logcat.
- iOS Simulator build installs and launches on a macOS runner, captures screenshot, and uploads the simulator app zip.
