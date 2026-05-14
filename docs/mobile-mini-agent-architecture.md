# MobileCode Android Mini Agent

MobileCode is moving from a chat-only assistant to a phone-first coding agent. The immediate goal is not to clone a desktop IDE, but to make the Android APK show a real agent loop that can create, inspect, save, preview, and publish small mobile-friendly projects.

## Reference Ideas

The local reference projects under `D:\study\code\0ai\产品\07-mobile-app\agent_refs` are used as design references only.

- `mini-harness`: clear model -> tool call -> tool result -> model loop, with a small registry of `read_file`, `write_file`, `bash`, `list_files`, and `search_text`.
- `mini-codex`: workspace-scoped execution, shell/tool output capture, bounded loop limits, and approval-aware command execution.
- `mini-claude-code`: persistent sessions, visible tool-use transcript, context compression, TODO reminders, and project memory.
- `MiniClaude`: rich CLI surfaces for in-progress tool calls, permission requests, file diffs, and grouped tool-use output.

## Android Adaptation

The APK cannot assume the same privileges as a desktop agent. The safe baseline is an app-owned workspace plus Android-native preview and explicit bridges to external apps.

Current phone-safe tool registry:

- `list_files`: inspect app-owned project folders.
- `write_file`: write generated code through a temp-file rename.
- `read_file`: read generated files back for preview and copy.
- `preview_webview`: render generated HTML/CSS/JS in Android WebView.
- `termux_probe`: check whether Termux is installed/exposed before offering shell workflows.
- `github_connect`: open the GitHub token/repo tester before publishing.

## Run Lifecycle

1. Boot the mini harness and show the active tool registry.
2. Think through the target artifact and workspace.
3. Call `list_files` to inspect current app-owned projects.
4. Call `write_file` to create `mobilecode_projects/agent_2048/index.html`.
5. Stream code-writing chunks to the UI as the file is generated.
6. Save atomically through `index.html.tmp` -> `index.html`.
7. Show a generated diff summary.
8. Call `read_file` to verify the saved artifact.
9. Arm WebView preview and persist `agent_run.json`.

## Production Path

- Replace deterministic demo generation with provider tool-call parsing when the model returns structured tool calls.
- Keep direct Android tools permissionless and workspace-scoped.
- Route shell/build operations through Termux only after package detection and explicit user consent.
- Store every agent run as JSONL or compact JSON for crash recovery, debugging, and replay.
- Add tool result size limits, timeout handling, and cancellation.
- Add GitHub publishing as a first-class tool after the GitHub connectivity tester passes.
