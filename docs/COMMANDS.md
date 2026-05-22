# MobileCode Commands

Date: 2026-05-22

Branch baseline: `last-recover-from-v039`

## Positioning

MobileCode does not expose a raw Linux shell to the model. It exposes a small, typed, Android-safe command layer:

```text
model tool call
-> ToolCallAdapter
-> ActionRunner
-> ActionEvidence
-> observation back to model
```

The model can use familiar Unix ideas like list, find, grep, read, patch, move, preview, and report, but every action is validated against the MobileCode workspace and recorded as evidence.

This is the current MobileCode Virtual Command Layer: it is not a full shell, but a provider-native typed tool facade that lets models translate common Linux/macOS development habits into Android-safe actions.

Streaming note: provider SSE deltas are buffered as in-memory tool-call drafts first. MobileCode does not write partial arguments to disk. A real workspace write happens only after the complete tool call is parsed, validated, permission-checked, executed by `ActionRunner`, and recorded as `ActionEvidence`.

## Current Provider-Native Tools

| Tool | Unix idea | Risk | Scope | Status |
|---|---|---:|---|---|
| `list_files` | `ls`, `dir`, limited `find` | Read | Workspace only | Supported |
| `find_files` | `find`, `fd` | Read | Workspace only | Supported |
| `grep_files` | `grep`, `rg`, `ag` | Read | Bounded text files | Supported |
| `web_search` | web search, not shell | Network read | Relay-backed public web | Supported when relay configured |
| `fetch_url` | safe `curl` / `wget` | Network read | Public HTTPS via relay | Supported when relay configured |
| `write_file` | `cat > file` | Write | Workspace only | Supported |
| `read_file` | `cat`, `head`, `tail` | Read | Workspace only | Supported |
| `copy_file` | `cp` | Guarded write | File-only, workspace only | Supported |
| `mkdir` | `mkdir -p` | Guarded write | Workspace directories only | Supported |
| `delete_file` | `rm` | Confirmed destructive | File-only, pre-delete snapshot | Supported |
| `move_file` | `mv` | Guarded write | File-only, workspace only | Supported |
| `save_snapshot` | checkpoint / local snapshot | Local evidence | Bounded workspace copy | Supported |
| `virtual_diff` | `diff`, limited `git diff` | Read | Snapshot-vs-workspace compare | Supported |
| `apply_patch` | `patch`, `git apply` | Bounded write | Unified diff, workspace only | Supported |
| `preview_html` | browser preview | Local preview | Workspace HTML / inline HTML | Supported |
| `preview_snapshot` | screenshot-like evidence | Local evidence | Metadata / DOM summary, not bitmap | Supported |
| `report_result` | final status | No execution | Conversation summary | Supported |

## Tool Contracts

### `list_files`

Purpose: inspect workspace files without arbitrary filesystem traversal.

Parameters:

- `path`: relative workspace path, use `.` for root.
- `recursive`: whether to include nested files.
- `max_entries`: bounded result count.

Notes:

- Safe replacement for `ls`.
- Returns path, type, size, and modified time.
- Does not read file contents.

### `find_files`

Purpose: find workspace files by name, glob, or path fragment.

Parameters:

- `pattern`: filename/glob/path fragment, for example `*.html` or `index`.
- `path`: relative workspace path, use `.` for root.
- `max_results`: bounded result count.

Notes:

- Safe replacement for `find` / `fd`.
- Searches only inside the active MobileCode workspace.
- Returns compact file metadata, not file content.

### `grep_files`

Purpose: search text inside bounded workspace files.

Parameters:

- `query`: plain text query.
- `path`: relative workspace path, use `.` for root.
- `include_glob`: optional filename glob such as `*.html`, or `*`.
- `max_results`: bounded match count.
- `max_bytes`: maximum bytes inspected per file.

Notes:

- Safe replacement for `grep` / `rg`.
- Skips binary-looking files and overly large files.
- Returns path, line number, and compact preview for each match.

### `read_file`

Purpose: read bounded text from a workspace file.

Parameters:

- `path`: relative workspace file path.
- `max_bytes`: maximum bytes to read.

Notes:

- Safe replacement for `cat/head/tail`.
- Binary files are not a target use case.
- Long content is compacted for model observation.

### `write_file`

Purpose: write one complete file into the workspace.

Parameters:

- `path`: relative workspace file path.
- `content`: complete content.
- `overwrite`: whether to replace an existing file.

Notes:

- Cannot write outside the app workspace.
- Writes are evidence-backed.
- The model should provide `path`; MobileCode also accepts common aliases such as `filename` and `file_path`.
- If a complete HTML artifact is provided without a path, MobileCode safely defaults to `index.html` inside the workspace.
- If the provider sends malformed tool arguments that still contain a complete HTML document, MobileCode attempts to recover the HTML content and records the repair in ActionEvidence.

### `copy_file`

Purpose: copy one regular file inside the workspace.

Parameters:

- `source_path`: existing relative file path.
- `destination_path`: target relative file path, including filename.
- `overwrite`: whether to replace an existing destination file.

Notes:

- Safe replacement for `cp`.
- Directories are blocked in the first version.
- Destination must not be just a directory.

### `mkdir`

Purpose: create a workspace directory.

Parameters:

- `path`: relative workspace directory path.
- `recursive`: whether to create missing parent directories.

Notes:

- Safe replacement for `mkdir -p`.
- Cannot create a directory over an existing file.
- `write_file` still creates parent folders automatically for generated artifacts.

### `delete_file`

Purpose: delete one confirmed regular file inside the workspace.

Parameters:

- `path`: relative workspace file path.
- `confirm`: must be `true` when the user explicitly requested deletion.

Notes:

- Guarded replacement for `rm`.
- Directory deletion is still blocked.
- MobileCode saves a pre-delete copy under `.mobilecode_delete_snapshots/` before removing the file.
- This is intentionally not raw recursive delete.

### `move_file`

Purpose: rename or move one file in the workspace.

Parameters:

- `source_path`: existing relative file path.
- `destination_path`: target relative file path including filename.
- `overwrite`: whether to replace an existing destination.

Notes:

- Safe replacement for `mv`.
- Directories are blocked in the first version.
- Destination must not be just a directory.

### `save_snapshot`

Purpose: save a bounded local snapshot before risky changes.

Parameters:

- `path`: relative file or directory path, use `.` for workspace root.
- `label`: short user-facing label.
- `max_files`: maximum files to include.
- `max_bytes`: maximum total bytes to copy.

Notes:

- This is a MobileCode snapshot, not a Git commit.
- Snapshot metadata is recorded as ActionEvidence.
- `.mobilecode_*` recovery directories are skipped to avoid recursive snapshots.

### `virtual_diff`

Purpose: compare current workspace files against a MobileCode snapshot.

Parameters:

- `path`: relative file or directory path to compare.
- `snapshot_id`: ID returned by `save_snapshot`, or empty when `snapshot_path` is used.
- `snapshot_path`: workspace-relative snapshot directory path, or empty when `snapshot_id` is used.
- `max_bytes`: maximum bytes to inspect.

Notes:

- Safe replacement for `diff` / a limited `git diff` workflow.
- Read-only: it does not write files.
- The first version is a compact line-level diff, not a complete Git diff engine.

### `apply_patch`

Purpose: apply a small unified diff inside the workspace.

Parameters:

- `patch`: unified diff with `---` / `+++` headers and `@@` hunks.
- `reason`: short reason for the patch.

Notes:

- Safe replacement for `patch` / `git apply`.
- Saves pre-patch snapshots and an `applied.patch` record.
- Rejects outside-workspace paths, deletion, binary patches, oversized patches, and context mismatches.
- This is bounded auto-apply, not raw shell execution.

### `web_search`

Purpose: obtain compact public references through managed relay.

Parameters:

- `query`: public web query.
- `count`: bounded result count.

Notes:

- Does not expose search provider secrets in the APK.
- Produces compact references for the model.
- If the managed relay endpoint is not configured, this tool is not exposed to the provider request.

### `fetch_url`

Purpose: fetch and compact a public HTTPS page.

Parameters:

- `url`: public HTTPS URL.
- `max_bytes`: bounded response size.

Notes:

- Local/private URLs are blocked.
- This is the safe equivalent of a constrained `curl`.
- If the managed relay endpoint is not configured, this tool is not exposed to the provider request.

### `preview_html`

Purpose: prepare in-app WebView preview from workspace HTML or inline HTML.

Parameters:

- `path`: relative HTML path, or empty string when using inline HTML.
- `html`: inline HTML, or empty string when using path.

### `preview_snapshot`

Purpose: record preview evidence.

Parameters:

- `path`: relative HTML path, or empty string.
- `url`: preview URL, or empty string.
- `html`: inline HTML, or empty string.
- `viewport_width`: expected viewport width.
- `viewport_height`: expected viewport height.

Notes:

- This is metadata/DOM evidence, not native bitmap screenshot yet.

### `report_result`

Purpose: finish the loop with concise status and evidence references.

Parameters:

- `status`: `success`, `blocked`, `failed`, or `partial`.
- `summary`: concise user-facing summary.
- `evidence_ids`: relevant evidence IDs.
- `recovery_actions`: next safe actions when blocked or failed.

## Explicitly Not Exposed

These are intentionally blocked in provider-native Agent Loop:

- raw `shell`, `bash`, `sh`, `cmd`;
- `sudo`, `chmod`, `chown`, system path writes;
- package installs such as `npm install`, `pip install`, `apt`, `brew`;
- Android system commands such as `pm`, `am`, `settings`, `dumpsys`, `logcat`;
- Git push, release publishing, remote log upload;
- arbitrary command strings such as `ls -la && rm -rf`.

## Near-Term Expansion

The next safe commands should remain typed tools, not raw shell:

- `restore_snapshot`: user-approved rollback to a prior MobileCode snapshot;
- `change_history`: readable history of recent evidence-backed changes;
- `project_summary`: compact project structure and entrypoint summary;
- `export_zip`: user-approved project export.

## Model Prompt Rule

The provider system prompt should say:

```text
You are running inside MobileCode, an Android app workspace.
This is not a full Linux environment.
Use provider-native typed tools instead of raw shell commands.
Translate ls/find/grep/cat/cp/mkdir/rm/mv/diff/patch/curl-style requests into list_files/find_files/grep_files/read_file/copy_file/mkdir/delete_file/move_file/save_snapshot/virtual_diff/apply_patch/fetch_url when possible.
Never attempt sudo, package installation, system Android commands, or writes outside the workspace.
```
