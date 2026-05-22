# MobileCode Command Compatibility

Date: 2026-05-22

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
| Recursive find | `find`, `fd` | Safe only inside workspace | Partial | `list_files(recursive: true)` |
| Read text | `cat`, `head`, `tail`, `less` | App can read workspace text | Supported | `read_file` |
| Write text | `cat > file`, editor save | App can write workspace files | Supported | `write_file` |
| Move / rename | `mv` | Safe inside workspace | Supported | `move_file` |
| Copy | `cp` | Safe inside workspace | Planned | `copy_file` later |
| Make directory | `mkdir -p` | Safe inside workspace | Partial | parent dirs via `write_file`; typed `mkdir` later |
| Delete | `rm`, `rmdir` | Risky in agent loops | Blocked | Not exposed |
| Text search | `grep`, `rg`, `ag` | Safe with result limits | Planned | `grep_files` later |
| Name search | `find -name`, glob | Safe with result limits | Planned | `find_files` later |
| Replace text | `sed -i`, editor replace | Risky without diff preview | Planned | `edit_file` / `apply_patch` later |
| Diff | `diff`, `git diff` | Can be snapshot-based | Planned | `git_diff_virtual` later |
| Patch | `patch`, `git apply` | Safe with workspace validation | Planned | `apply_patch` later |
| Web fetch | `curl`, `wget` | App should not fetch private/local targets | Supported when relay configured | `fetch_url` relay |
| Web search | search CLI / browser | Requires managed relay | Supported when relay configured | `web_search` relay |
| Preview | browser open | App has WebView | Supported | `preview_html` |
| Preview evidence | screenshot | Native bitmap capture not implemented | Partial | `preview_snapshot` metadata |
| Package managers | `npm`, `pip`, `brew`, `apt` | Not guaranteed on Android app sandbox | Runtime only | Helper/Termux/CI later |
| Build tools | `flutter`, `dart`, `gradle`, `make` | Not guaranteed in APK | Runtime only | Helper/Termux/CI later |
| Git local | `git status`, `git diff` | Git binary not guaranteed | Planned virtual | snapshots later |
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
- `web_search` when managed relay is configured
- `fetch_url` when managed relay is configured
- `write_file`
- `read_file`
- `move_file`
- `preview_html`
- `preview_snapshot`
- `report_result`

Not supported today:

- arbitrary `ls` / `mv` / `cat` shell strings;
- `rm`, `cp`, `mkdir` as independent typed tools;
- `grep_files`, `find_files`, `apply_patch`;
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

Status: in progress.

- `list_files`
- `read_file`
- `write_file`
- `move_file`
- UI-visible command map
- evidence for each action

### P1: Search and patch

- `grep_files`
- `find_files`
- `edit_file`
- `apply_patch`
- bounded `read_many_files`

### P2: Snapshot safety

- `save_snapshot`
- `git_status_virtual`
- `git_diff_virtual`
- `restore_snapshot`
- change history

### P3: Project intelligence

- `project_summary`
- `detect_project_type`
- `validate_html`
- `validate_json`
- `validate_markdown`

### P4: Android-specific helpers

- `android_device_info`
- `share_project`
- `copy_to_downloads`
- `request_workspace_permission`
- optional Termux bridge, explicit user opt-in only
