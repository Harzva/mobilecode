# P6.0-P6.2 Runtime Benchmark Upgrade Contract

This contract upgrades MobileHarnessBench from a small strategy pilot into a
mobile runtime benchmark scaffold. It is a contract artifact only:
`counts_as_experiment=false` and `run_kind=strategy_pilot_not_counted` remain
mandatory until a later promotion gate verifies real model, tool, device,
runtime, and privacy evidence.

## P6.0 Task Taxonomy

| Task category | Purpose | Required runtime assertions | Evidence refs |
| --- | --- | --- | --- |
| `ui_artifact` | Generated HTML or Flutter UI artifact behaves on a phone viewport. | keyboard, tap, screenshot, error absence | screenshot, verifier JSON |
| `webview_artifact` | Artifact behaves inside MobileCode WebView. | keyboard, tap, set_text, localStorage, WebView state, screenshot | WebView state, screenshot |
| `phone_use_permission` | App-owned phone-use capability is permission gated. | Accessibility state, dry probe, blocked reason, action schema | UI XML, logcat, verifier JSON |
| `file_intake` | Open/share/import flow preserves source metadata and content. | content URI state, file hash, UI confirmation, recovery path | intake log, UI XML |
| `local_runtime` | Local helper/runtime can execute or report a clear blocker. | process state, stdout/stderr summary, timeout, exit code | runtime report, logcat |
| `network_boundary` | Network-dependent task respects offline, proxy, and secret boundaries. | request block/allow decision, redaction, retry state | network summary, verifier JSON |
| `recovery_task` | Strategy recovers from verifier failure or blocked tooling. | retry/replan, blocked reason, recovery action, final status | strategy trace, verifier JSON |
| `real_device_task` | Android/iOS device lane proves install, launch, and runtime evidence. | install, launch, focus, screenshot, UI XML, logcat/device logs | device evidence directory |

## Runtime Assertion Matrix

| Assertion | Contract | Applies to |
| --- | --- | --- |
| `keyboard` | Dispatch Arrow/WASD or shortcut keys and assert visible/state change. | UI artifact, WebView artifact, games, editors |
| `tap` | Tap coordinates or accessibility node and assert target state changed. | WebView, phone-use, device lane |
| `swipe` | Swipe from/to coordinates and assert scroll, drawer, or canvas state changed. | phone-use, UI screens |
| `set_text` | Input text through DOM, WebView, or accessibility path and assert value/state. | forms, Kanban, chat/task input |
| `localStorage` | Read/write/refresh persistence assertion without leaking raw user data. | Web artifacts, WebView artifacts |
| `ui_xml` | Capture sanitized UI hierarchy and assert stable labels or state markers. | Android emulator/real device |
| `screenshot` | Capture nonblank image and inspect for target UI, not launcher/error page. | all runtime lanes |
| `logcat` | Scan app-scoped logs for fatal, ANR, Flutter, and plugin errors. | Android emulator/real device |
| `webview_state` | Query app-owned WebView URL, JS state, DOM markers, and console errors. | MobileCode WebView |
| `focus_state` | Assert foreground package/activity or iOS process state. | real device lanes |

## Score Dimensions

Scores are dimension reports, not counted benchmark rankings, until the
promotion gate passes.

| Dimension | Weight | What it measures |
| --- | ---: | --- |
| `quality` | 25 | Functional completeness and requirement coverage. |
| `runtime_correctness` | 25 | Real interaction assertions and state changes. |
| `phone_use_ability` | 15 | Permission-gated observe/tap/swipe/set_text/back/home ability. |
| `recovery` | 15 | Retry, replan, blocked reason quality, and recovered verifier failures. |
| `latency_token` | 10 | Wall time, steps, model tokens, and tool I/O efficiency. |
| `safety_privacy` | 10 | Non-counted boundary, redaction, scope limits, and raw transcript avoidance. |

## P6.1 Communication Substrate

| Contract | Purpose | Required fields |
| --- | --- | --- |
| `MailboxMessage` | Role-to-role work packet with scoped context. | message_id, from_role, to_role, task_id, allowed_tools, budget, input_filter, expected_return, evidence_refs |
| `EvidenceLedgerEntry` | Shared blackboard entry for artifacts and verifier outputs. | evidence_id, kind, path, producer_role, redaction_state, created_at, summary |
| `RuntimeEvent` | EventBus record for device/WebView/runtime interactions. | event_id, source, target, action, status, timestamp, evidence_id, redaction_state |
| `MemoryCommitProposal` | Proposal-only memory write after verification. | proposal_id, source_trace, content_summary, ttl, redaction_state, approval_required |

Role contracts:

| Role | Allowlist | Budget | Input filter | Return contract |
| --- | --- | --- | --- | --- |
| `CodeAgent` | read_file, apply_patch, format, unit_test | max_steps 8 | code files and scoped task | patch summary, tests, blockers |
| `RuntimeAgent` | adb, devicectl, browser_cdp, webview_probe | max_steps 8 | runtime target and evidence policy | runtime events, screenshots/log refs |
| `PreviewAgent` | screenshot, ui_xml, webview_state | max_steps 6 | app-owned UI only | visual state, UI markers, blockers |
| `VerifierAgent` | validators, static checks, runtime assertions | max_steps 8 | artifacts and evidence refs | pass/fail, score dimensions, missing evidence |
| `MemoryAgent` | memory_packet, redaction, proposal | max_steps 4 | summaries only | proposal or no-op with reason |
| `ReporterAgent` | evidence_ledger, markdown_summary | max_steps 4 | verified evidence refs | public-safe summary |

## P6.2 Runtime Verifier Scaffold

The scaffold reuses P5.6 browser runtime verification and extends the contract
toward Android/WebView evidence. A verifier output must include:

- `schema_version`
- `run_kind`
- `counts_as_experiment=false`
- `task_id`
- `task_category`
- `assertion_results`
- `score_dimensions`
- `device_evidence_refs`
- `webview_evidence_refs`
- `privacy_boundary`
- `blocked_reason`

A non-counted run must include:

- `run_kind=strategy_pilot_not_counted`
- `counts_as_experiment=false`
- one result per strategy per contract task
- `evidence.boundary=pilot_not_counted`
- no model/provider claim unless real callbacks were used and redacted
- no raw transcript, raw UI text from third-party apps, secrets, or private paths

## P6.3 Android Real Device Lane Recommendation

The next execution lane should install the latest APK on a real Android device
or dedicated emulator, grant/verify Accessibility manually where needed, run the
Mobile Phone Use dry/action probe, capture screenshot/UI XML/logcat/focus state,
and attach WebView state assertions for generated artifacts. This should remain
non-counted until repeated task samples and promotion gates pass.

2026-06-21 execution note: the dedicated Android emulator phone-use lane now has
non-counted evidence at
`docs/mobile-harness-benchmark/strategy-ablation/runs/p63-android-real-device-lane/`.
It verifies APK install/launch, Accessibility state, Mobile Phone Use dry/action
probe, Back/Home focus state, screenshot/UI XML/logcat capture, and validator
compatibility. It is emulator evidence only; real Android hardware and
WebView/localStorage/generated artifact interaction assertions remain separate
P6.3/P6.4 gates.
