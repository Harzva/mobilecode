# MobileCode Command Compatibility

Date: 2026-05-22

Last updated: 2026-05-23

Branch baseline: `last-recover-from-v039`

## Summary

MobileCode is an Android AI coding harness, not a Linux VM. The compatibility goal is a "Mobile Unix Facade":

```text
Unix-like command intent
-> provider-native typed tool
-> Android app workspace operation
-> ActionEvidence
```

This lets models reuse Linux/macOS development habits while MobileCode keeps Android app sandbox safety.

## Compatibility Matrix

| Area | Linux/macOS command idea | Android reality | MobileCode support | Tool / path |
|---|---|---|---|---|
| Current directory | `pwd` | App has private workspace roots | Partial | Runtime/workspace display |
| List files | `ls`, `dir` | App can list app-owned files | Supported | `list_files` |
| Recursive find | `find`, `fd` | Safe only inside workspace | Supported | `find_files` |
| Project summary | `pwd`, `tree`, `stat` overview | App can summarize bounded workspace files | Supported | `project_summary` |
| Read text | `cat`, `head`, `tail`, `less` | App can read workspace text | Supported | `read_file` |
| Write text | `cat > file`, editor save | App can write workspace files | Supported | `write_file` |
| Move / rename | `mv` | Safe inside workspace | Supported | `move_file` |
| Copy | `cp` | Safe inside workspace | Supported | `copy_file` |
| Make directory | `mkdir -p` | Safe inside workspace | Supported | `mkdir`; parent dirs also via `write_file` |
| Delete | `rm`, `rmdir` | Risky in agent loops | Guarded | `delete_file` for confirmed single files only |
| Text search | `grep`, `rg`, `ag` | Safe with result limits | Supported | `grep_files` |
| Name search | `find -name`, glob | Safe with result limits | Supported | `find_files` |
| Replace text | `sed -i`, editor replace | Risky without diff preview | Partial | `apply_patch` unified diff |
| Snapshot | checkpoint before changes | App can copy bounded workspace files | Supported | `save_snapshot` |
| Diff | `diff`, `git diff` | Can be snapshot-based | Supported | `virtual_diff` |
| Restore snapshot | `git restore`, rollback | Risky unless explicit and bounded | Guarded | `restore_snapshot` with `confirm=true` |
| Patch | `patch`, `git apply` | Safe with workspace validation | Supported | `apply_patch` bounded auto-apply |
| HTML sanity check | `tidy`, `htmlhint`, browser check | App can inspect text HTML safely | Supported | `validate_html` |
| Web fetch | `curl`, `wget` | App should not fetch private/local targets | Supported when relay configured | `fetch_url` relay |
| Web search | search CLI / browser | Requires managed relay | Supported when relay configured | `web_search` relay |
| Preview | browser open | App has WebView | Supported | `preview_html` |
| Preview evidence | screenshot | Native bitmap capture not implemented | Partial | `preview_snapshot` metadata |
| Package managers | `npm`, `pip`, `brew`, `apt` | Not guaranteed on Android app sandbox | Runtime only | Helper/Termux/CI later |
| Build tools | `flutter`, `dart`, `gradle`, `make` | Not guaranteed in APK | Runtime only | Helper/Termux/CI later |
| Git local | `git status`, `git diff` | Git binary not guaranteed | Partial virtual | `save_snapshot` / `virtual_diff`; status/restore later |
| Git remote | `git push`, release | High risk | Blocked | GitHub UI/CI only |
| Android shell | `pm`, `am`, `dumpsys`, `logcat` | Requires privileges / debug mode | Blocked | Not provider-native |
| Process control | `ps`, `top`, `kill` | Risky and limited | Blocked | Not exposed |
| Network diagnostics | `ping`, `dig`, `traceroute`, `nc` | Not core coding operation | Blocked | Not exposed |
| System permissions | `chmod`, `chown`, `sudo` | Not suitable for app sandbox | Blocked | Not exposed |

## Why macOS Works for Agents but Android Needs a Facade

Models work well on macOS because they have learned Unix-like workflows:

- inspect files;
- read relevant context;
- search text;
- edit files;
- run checks;
- inspect diffs;
- recover when a command fails.

macOS is not Linux, but it still offers a broad Unix command surface. Android apps do not get that same shell surface by default. MobileCode therefore should not pretend to be Linux. It should expose a compact typed command layer that gives the model the same workflow shape without unsafe shell access.

## Current Product Truth

Supported today in provider-native Agent Loop:

- `list_files`
- `find_files`
- `grep_files`
- `project_summary`
- `web_search` when managed relay is configured
- `fetch_url` when managed relay is configured
- `write_file`
- `read_file`
- `copy_file`
- `mkdir`
- `delete_file`
- `move_file`
- `save_snapshot`
- `virtual_diff`
- `restore_snapshot`
- `validate_html`
- `apply_patch`
- `preview_html`
- `preview_snapshot`
- `report_result`

Not supported today:

- arbitrary `ls` / `mv` / `cat` shell strings;
- recursive delete, directory delete, or `rm -rf` semantics;
- real package managers or shell builds;
- Android system command execution.

## Failure Interpretation

If the model repeatedly fails with:

```text
Missing required string param: path
```

that usually means:

- the provider selected a typed tool such as `write_file`;
- the tool arguments were incomplete;
- MobileCode correctly rejected the call before execution.

This is not an Android storage permission issue. It is a provider/tool schema adherence issue. MobileCode now accepts common path aliases, can safely default complete HTML writes to `index.html`, and can recover HTML content from some malformed tool argument strings; if the content itself is missing or cannot be recovered, the correct recovery path is still to feed back the failed evidence and ask the model for valid arguments.

## Expansion Roadmap

### P0: Read / inspect / move foundation

Status: accepted.

- `list_files`
- `read_file`
- `write_file`
- `move_file`
- UI-visible command map
- evidence for each action

### P1: Search and patch

Status: accepted.

- `grep_files`
- `find_files`
- `apply_patch`

### P2: Snapshot safety

Status: accepted for bounded snapshot / diff / restore.

- `save_snapshot`
- `virtual_diff`
- `restore_snapshot`
- `change_history` remains future work

### P3: Project intelligence

Status: partial.

- `project_summary`
- `detect_project_type`
- `validate_html`
- `validate_json` remains future work
- `validate_markdown` remains future work

### P4: Android-specific helpers

- `android_device_info`
- `share_project`
- `copy_to_downloads`
- `request_workspace_permission`
- optional Termux bridge, explicit user opt-in only
