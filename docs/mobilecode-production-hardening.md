# MobileCode Production Hardening Notes

Last updated: 2026-05-13

## Deployable Target

MobileCode should ship as a real Android APK with the following first-run path:

1. Configure provider Base URL, API key, and model.
2. Run provider health check and show latency/status.
3. Ask AI Chat or Agent to build a small target such as `2048`.
4. Agent writes files into an app-owned project directory.
5. User taps Preview and sees the generated web app inside WebView.
6. User tests GitHub connectivity before publish/release actions.

Release builds must not bundle local LLM weight files in the APK. On-device
models are opt-in user-installed assets: MobileCode may show a model download
link or model manifest in the app, then enable local inference only after the
user downloads or imports a verified model and tokenizer. See
`docs/mobilecode-local-model-distribution.md`.

## Tool Capability Matrix

| Capability | Direct Flutter/Android | Termux Required | Remote/CI Preferred |
| --- | --- | --- | --- |
| Local storage, drafts, snippets | Yes | No | No |
| HTTP APIs, LLM calls, GitHub REST | Yes | No | Optional |
| WebView preview of generated HTML | Yes | No | No |
| Clipboard, share sheet, notifications | Yes | No | No |
| Camera, microphone, screenshot input | Yes | No | No |
| Git binary operations | Partial via APIs | Yes for CLI git | Yes for protected repos |
| SSH/SFTP | Possible via Dart libs | Optional | Optional |
| npm/python/package managers | No | Yes | Often preferred |
| Flutter/Android builds on device | No | Yes, heavy | Strongly preferred |
| Release signing and upload | Partial | Optional | Preferred |

Termux is not mandatory for every MobileCode tool. It is required when the user expects a Linux-like command environment, package managers, local build tools, and long-running shell sessions.

## Preview Architecture

The current APK preview path uses `webview_flutter`:

- generated HTML is saved to app documents;
- WebView loads the generated HTML string;
- JavaScript is enabled for local interactive demos;
- progress and WebView resource errors are surfaced in the UI.

Next production step: add a preview registry with `html`, `flutter`, `markdown`, and `terminal-output` preview types.

## Reliability Rules

- Never leave a spinner running after an exception.
- Persist user work before starting an external operation.
- Write generated files atomically with `*.tmp` then rename.
- Treat Termux URL schemes as a fallback only; package-manager checks are more reliable.
- Every tool should return one of: `ready`, `needs_permission`, `missing_dependency`, `failed`, or `unsupported`.

## Logging And Monitoring

Minimum local log fields:

- timestamp
- tool id
- input summary
- result status
- latency in milliseconds
- error code/message
- provider/model, when relevant

Recommended dashboards:

- provider health success rate and latency;
- WebView preview creation time;
- file generation failures;
- Termux package detection/launch results;
- crash-free sessions;
- APK version adoption.

## Performance Notes

- Keep UI probes short and cancellable.
- Avoid running heavy code generation or build commands on the main isolate.
- Use app-owned storage for drafts and generated files.
- Keep model weights out of the APK; download or import them into app-owned
  model storage after explicit user action.
- Prefer remote CI for release builds and signing.
- Cache provider health results briefly to avoid repeated network checks.
- Use bounded chat context windows to control token cost and latency.

## Versioning

Use semantic product tags such as `v0.1.0`, and Android build numbers such as `0.1.0+6`.

Release checklist:

1. `flutter pub get`
2. compile APK in GitHub Actions
3. upload APK to release
4. update release notes with build number, run id, and known limits
5. smoke test: API health, Agent 2048 generation, WebView preview, Tool Lab, Termux check
