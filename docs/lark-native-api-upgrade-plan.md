# MobileCode Lark Native API Upgrade Plan

Objective: replace the Node-dependent Lark CLI path with a native, typed Lark OpenAPI provider that fits MobileCode's phone-native AI coding harness model.

## Source Baseline

Official Lark / Feishu documents used for this plan:

- [larksuite/cli](https://github.com/larksuite/cli)
- [larksuite/lark-openapi-mcp](https://github.com/larksuite/lark-openapi-mcp)
- [Lark MCP configuration guide](https://github.com/larksuite/lark-openapi-mcp/blob/main/docs/usage/configuration/configuration.md)
- [Lark MCP command line reference](https://github.com/larksuite/lark-openapi-mcp/blob/main/docs/reference/cli/cli.md)
- [Server API getting started](https://open.larksuite.com/document/server-docs/getting-started/getting-started.md)
- [H5 JSAPI overview](https://open.larksuite.com/document/client-docs/h5/.md)
- [Access credentials overview](https://open.larksuite.com/document/home/introduction-to-scope-and-authorization/access-credentials.md)
- [Get access token](https://open.larksuite.com/document/ukTMukTMukTM/uMTNz4yM1MjLzUzM.md)
- [Create Docx document](https://open.larksuite.com/document/server-docs/docs/docs/docx-v1/document/create.md)
- [Create Docx block](https://open.larksuite.com/document/server-docs/docs/docs/docx-v1/document-block/create.md)
- [Drive file upload](https://open.larksuite.com/document/server-docs/docs/drive-v1/upload/upload_all.md)
- [Sheets append data](https://open.larksuite.com/document/ukTMukTMukTM/uMjMzUjLzIzM14yMyMTN.md)
- [Bitable batch create records](https://open.larksuite.com/document/uAjLw4CM/ukTMukTMukTM/reference/bitable-v1/app-table-record/batch_create.md)
- [Wiki space list](https://open.larksuite.com/document/ukTMukTMukTM/uUDN04SN0QjL1QDN/wiki-v2/space/list.md)

Key facts from the docs:

- `larksuite/cli` is a Lark organization repository described as the official Lark/Feishu CLI, built for humans and AI Agents. Its README says it covers Messenger, Docs, Base, Sheets, Slides, Calendar, Mail, Tasks, Meetings, Markdown, and more with 200+ commands and 26 AI Agent skills. GitHub API checked on 2026-06-12 shows it is a Go repository with recent activity (`pushed_at=2026-06-11T20:34:54Z`).
- `larksuite/lark-openapi-mcp` is a Lark organization repository and its README describes it as the official Feishu/Lark OpenAPI MCP tool. It wraps Open Platform APIs as MCP tools and supports the international `https://open.larksuite.com` domain through `--domain`.
- The MCP package is Node-based (`@larksuiteoapi/lark-mcp`, Node.js required, package engine `>=20.0.0`). It supports stdio, streamable, and SSE modes, plus explicit `--tools`, `--token-mode`, `--oauth`, `--scope`, and `--domain` configuration. GitHub API checked on 2026-06-12 shows its latest push was `2025-08-14T05:39:18Z`, so MobileCode should treat it as useful but not as the only live integration source.
- The MCP README marks the project as Beta and notes current limitations: file upload/download operations are not yet supported, and direct Feishu cloud document editing is not supported.
- Lark server APIs follow a RESTful OpenAPI flow: create an app, get access credentials, apply API permissions, optionally configure data permissions and IP allowlists, then call APIs.
- Lark OpenAPI calls use `Authorization: Bearer <access_token>`.
- `tenant_access_token` is for app identity; `user_access_token` is for user identity; `app_access_token` is mainly an app identity credential and is increasingly unified with tenant token in some paths.
- Access tokens are short lived. Token refresh must be handled by trusted code.
- Official guidance says access credentials should not be used directly in the app frontend. MobileCode must therefore avoid shipping `app_secret` or long-lived Lark credentials in public mobile builds.
- Docx, Drive, Sheets, Bitable, and Wiki all expose direct HTTP APIs. A Node runtime is not required for the core product path.
- H5 JSAPI is useful when MobileCode is opened inside Lark or renders a Lark companion page. It covers client-side actions such as `authorize`, `docsPicker`, `filePicker`, `openDocument`, `chooseChat`, clipboard, media, and device APIs. It is a client interaction layer, not a replacement for server OpenAPI writes.

## Product Decision

MobileCode should treat Lark as a first-class structured API provider, not as a shell command.

Prefer official or semi-official tools for development, verification, and schema discovery where they fit:

- Use `larksuite/cli` on Mac during development as the most active official behavior probe, command reference, auth/scope debugger, and quick API experiment tool.
- Use `larksuite/lark-openapi-mcp` as an optional structured MCP adapter for desktop agents, CI experiments, or a managed relay when its coverage is sufficient.
- Use native Dart OpenAPI calls inside the phone app for the product runtime and for the minimal evidence loop.
- Keep both CLI and MCP outside APK/IPA runtime boundaries.

```text
AI tool intent
-> Lark structured tool router
-> dev-time official CLI or MCP probe on Mac/CI when useful
-> native Dart OpenAPI adapter inside phone runtime
-> token broker / user OAuth / secure storage
-> Lark OpenAPI / H5 JSAPI
-> redacted ActionEvidence
-> phone-side preview, publish, benchmark, or verifier result
```

The existing Lark CLI connector can remain as an opt-in development and compatibility tool for Mac, desktop agents, CI, or Termux users, but it must not be the default product path. The default path should be Node-free and safe to run inside the Flutter app.

### Local CLI Borrowing Pattern

- `larksuite/cli` is a good reference adapter for API shape and behavior parity, but it is built to run in Node environments.
- We should treat it as a local "behavior oracle": clone it into an external dev workspace, run the same commands we need, and then mirror successful payloads into Dart native request schemas.
- Typical borrowing cycle:
  1. Download/clone in a separate dev dir and install dependencies.
  2. Log in via `lark-cli auth login --recommend`.
  3. Run paired commands against Docs/Drive/Sheets/Bitable/Wiki to capture stable request examples.
  4. Paste only the relevant examples into `LarkApiService` tests and action schemas.
  5. Mark parity notes in this plan and convert each one to redacted `ActionEvidence` with confirm-before-write.

This keeps MobileCode mobile path lightweight while preserving protocol compatibility to official semantics.

### Local CLI Sampling Template (for parity + validation)

采样目标：在独立开发目录里执行官方 CLI 命令，拿到稳定可复现的行为快照，再映射到手机原生请求。

#### 统一采样字段

| 字段 | 说明 |
| --- | --- |
| CLI command | 可复现命令（包含 `--format json`） |
| CLI param 关键位 | 与 OpenAPI path/body 的对应变量 |
| token source | 访问令牌从 CLI 配置哪个字段透出 |
| expected headers | `Authorization`/`Content-Type` 等 |
|常见错误码| 失效或失败时的最小参考码 |
| mobile-native action | 当前应用内映射 `LarkApiActionKind` |

#### 最小样例（建议持续追加）

| 场景 | CLI command | CLI 关键参数 | token source | 预期 token 位置 | 常见错误码 | Mobile action 映射 |
| --- | --- | --- | --- | --- | --- | --- |
| Docx create | `lark-cli docs +create --api-version v2 --doc-format markdown --title "<title>" --content "<markdown>" --folder-token "<folder_token>" --dry-run --format json` | `title` `content` `folder_token` | `lark config` 用户登录上下文 | `Authorization: Bearer <token>` | `0=成功`, `1001=permission deny`, `9999=invalid param` | `lark_docx_create` -> `POST /docx/v1/documents` |
| Docx append blocks | `lark-cli docs +create --api-version v2 --doc-format raw --document-id "<doc_token>" --parent-id "<parent_block>" --content "<markdown>" --dry-run --format json`（或对应 raw block 命令） | `document-id` `parent-id` `content` | CLI auth context | `Authorization: Bearer <token>` | `0=成功`, `9999=invalid revision` | `lark_docx_append_blocks` -> `POST /docx/v1/documents/{document_id}/blocks/{block_id}/children` |
| Sheets append | `lark-cli sheets +append-values --spreadsheet-token "<token>" --range "<Sheet1!A1:D4>" --values "[[\"...\" ...]]" --raw --format json` | `spreadsheet-token` `range` `values` | CLI auth context | `Authorization: Bearer <token>` + query `insertDataOption=INSERT_ROWS` | `0=成功`, `1001=permission denied`, `9999=param error` | `lark_sheets_append` -> `POST /sheets/v2/spreadsheets/{spreadsheetToken}/values_append` |
| Drive upload preview | `lark-cli drive +upload --file "<path>" --parent-node "<node>" --file-name "<name>" --dry-run --format json` | `file-name` `parent_node` `path` | CLI auth context | `Authorization: Bearer <token>` + `multipart/form-data` | `0=成功`, `404=not found`, `1001=permission denied` | `lark_drive_upload_preview` -> `POST /drive/v1/files/upload_all` |
| Wiki list | `lark-cli wiki +space list --page-size 10 --format json` | `page_size` | CLI auth context | `Authorization: Bearer <token>` | `0=成功`, `1001=permission denied` | `lark_wiki_list_spaces` -> `GET /wiki/v2/spaces?page_size=10` |

#### 采样到移动端验证映射表（持续维护）

| 校验项 | CLI 产物字段 | Mobile-native 断言 | 结果落地 |
| --- | --- | --- | --- |
| Method / Path | CLI 请求 method 与 endpoint | `LarkApiRequestSpec.method` / `path` | `LarkApiService` 校验清单 |
| 认证载体 | CLI token 类型和 header 风格 | `LarkApiConnection.tokenMode` + `Authorization` redact preview | `ActionEvidence.metadata["connection"]` |
| 体/查询参数 | CLI 输入体转 JSON 参数 | `LarkApiRequestSpec.body` / `query` | `ActionEvidence.metadata["preview"]` |
| 响应错误码 | CLI `code`、HTTP 状态 | `LarkApiCallResult.statusCode` / `larkCode` | `ActionEvidence.metadata["result"]` |
| 失败归因 | CLI 错误信息 | `failureKind` + `failure` 显示 | `ActionEvidence.failureKind` 与日志 |

更新节奏：每完成一个新 CLI 样本，立即在此表新增一行，并在 `LarkApiService.cliParityCatalog()` / `ActionEvidence` 中写入对应 `cliReference` 与 `requiredScopes`，确保 CLI 参照可追踪。

#### CLI 采样失败归因映射（2026-06-12）

| CLI probe | Token mode | 观测结果 | Mobile failureKind | Agent recovery |
| --- | --- | --- | --- | --- |
| `lark-cli wiki +space-list --as user --page-size 1 --format json`（授权前） | `user_access_token` | `missing required scope(s): wiki:space:retrieve` | `missing_scope` | 触发 user OAuth，追加 `wiki:space:retrieve`，不要误判为 token 无效 |
| `lark-cli auth login --scope "wiki:space:retrieve"` 后重跑 user list | `user_access_token` | `ok=true`, `spaces=[]` | `empty_result` | API 已通；提示当前账号无可见 Wiki space，尝试 `my_library`、加入/创建测试 Wiki |
| `lark-cli wiki +space-list --as bot --page-size 1 --format json` | `tenant_access_token` | `code=99991672`, `app_scope_not_applied`, `log_id` 和 `console_url` | `app_scope_not_applied` | 打开开发者后台为 app 申请 `wiki:wiki` / `wiki:wiki:readonly` / `wiki:space:retrieve` |
| 飞书里直接私聊 CLI bot | bot/event | Bot identity ready 但无事件消费者或回调服务 | `event_consumer_not_running` | 运行 `lark-cli event consume im.message.receive_v1 --as bot` 或配置 callback/relay，再接模型回复链路 |

当前移动端追踪点：

- `LarkApiService.cliParityCatalog()` 是 CLI 参照的代码内清单。
- `LarkApiService.failureTaxonomySamples()` 是 CLI 失败归因的代码内清单。
- `LarkApiService.cliParityFor(actionKind)` 是单个 mobile-native action 的最低追溯项。
- `ActionEvidence.metadata["cliReference"]` 记录 dry-run 参照。
- `ActionEvidence.metadata["requestAttribution"]` 记录真实执行的 token mode、tool、HTTP status、request id、Lark error code、dry-run/confirm 痕迹与 required scopes。

## Scope

In scope:

- Official CLI and OpenAPI MCP evaluation for development, schema discovery, and integration tests.
- Native Dart HTTP client for Lark OpenAPI.
- Token-mode abstraction for `tenant_access_token` and `user_access_token`.
- Managed token broker for app-secret flows.
- User OAuth flow for user-owned document actions.
- Typed actions for Docs, Wiki, Drive, Sheets, Bitable, and message/task drafts.
- Dry-run and confirm-before-write governance.
- Evidence capture for every Lark action.
- Benchmark tasks that prove Lark actions work on mobile without Node.

Out of scope for the first production cut:

- Bundling `app_secret` or permanent access tokens inside APK/IPA.
- Arbitrary Lark shell execution.
- Requiring Node, npm, or `lark-cli` for default mobile use.
- Requiring `lark-openapi-mcp` to run inside the APK/IPA.
- Treating MCP or CLI behavior as product readiness without native mobile evidence.
- Silent writes to user workspaces, chats, docs, sheets, or bases.
- Marketplace app distribution before internal app and token-broker flows are proven.

## Architecture

### Runtime Lanes

| Lane | Role | Lark Usage |
| --- | --- | --- |
| Model API | Remote model reasoning and tool selection | Chooses typed Lark actions, never sees raw secrets |
| GitHub API Runtime | Repository, release, Pages, Actions | Publishes code and evidence artifacts |
| Native Mobile Runtime | Files, preview, evidence, secure storage | Runs Lark API client and stores redacted results |
| Lark H5 Companion | Optional WebView / in-Lark client surface | Picks docs/files/chats, opens Lark resources, requests client-side authorization |
| Official CLI Dev Probe | Mac development and CI exploration | Runs `lark-cli` to verify scopes, payloads, and Lark behavior outside the app |
| Official MCP Adapter | Mac, CI, desktop agent, or managed relay | Runs `@larksuiteoapi/lark-mcp` when Node is available and coverage is sufficient |
| Helper / Termux Runtime | Optional local command tasks | Compatibility only, not required for Lark Native API |
| Managed Relay / Token Broker | Secret-bearing server side | Exchanges app credentials, refreshes tokens, enforces tenant policy |

### Proposed Modules

| Module | Responsibility |
| --- | --- |
| `LarkAuthService` | Selects token mode, requests user OAuth, refreshes via broker, reports missing scopes |
| `LarkStructuredToolRouter` | Routes a Lark action to native API, official MCP adapter, or compatibility runtime |
| `LarkApiClient` | Shared HTTP client, retries, rate-limit handling, error normalization |
| `LarkCliDevProbe` | Optional Mac/CI probe that runs `lark-cli` commands to compare native payloads with official behavior |
| `LarkOpenApiMcpBridge` | Optional bridge to `@larksuiteoapi/lark-mcp` in stdio, streamable, or SSE mode |
| `LarkDocsService` | Create documents, create blocks, read metadata, convert MobileCode evidence into Docx blocks |
| `LarkWikiService` | List spaces, resolve wiki nodes, publish or link docs into a wiki space |
| `LarkDriveService` | Upload evidence files, screenshots, reports, and exported artifacts |
| `LarkSheetsService` | Append benchmark rows and release QA rows |
| `LarkBitableService` | Create structured records for tasks, issues, verifier results, and evidence index |
| `LarkMessageService` | Prepare interactive message or task drafts; send only after explicit confirmation |
| `LarkH5Bridge` | Optional JSAPI bridge for in-Lark H5 surfaces such as `docsPicker`, `openDocument`, `chooseChat`, and `authorize` |
| `LarkEvidenceStore` | Stores redacted request/response metadata, tokens omitted, `log_id` retained when available |
| `LarkActionVerifier` | Converts Lark results into benchmark/verifier assertions |

## API Capability Map

| Capability | Native API Target | Token Mode | First MobileCode Use |
| --- | --- | --- | --- |
| Connectivity check | Access-token broker health + a low-risk metadata call | broker / user | Show Lark readiness in Tools |
| Create report document | `POST /open-apis/docx/v1/documents` | tenant or user | Publish mobile evidence report |
| Write report blocks | `POST /open-apis/docx/v1/documents/:document_id/blocks/:block_id/children` | tenant or user | Convert verifier output into structured Docx |
| Upload artifacts | `POST /open-apis/drive/v1/files/upload_all` | tenant or user | Upload screenshots, logs, benchmark JSON |
| Append metrics | `POST /open-apis/sheets/v2/spreadsheets/:spreadsheetToken/values_append` | tenant or user | Append benchmark run summary |
| Create Base records | `POST /open-apis/bitable/v1/apps/:app_token/tables/:table_id/records/batch_create` | tenant or user | Track tasks, runs, releases, failures |
| List wiki spaces | `GET /open-apis/wiki/v2/spaces` | tenant or user | Select publish destination |
| Pick or open resources in Lark client | H5 JSAPI such as `docsPicker`, `filePicker`, `openDocument`, `chooseChat`, `authorize` | Lark client context | Select targets and return user intent to native API flow |
| Development-time CLI probes | `lark-cli` auth, shortcut commands, API commands, raw API calls | Mac/CI user or app identity | Compare native implementation, inspect scopes, generate payload examples |
| Agent-facing structured Lark tools | `@larksuiteoapi/lark-mcp` with whitelisted `--tools` and `--domain https://open.larksuite.com` | tenant or user | Desktop/CI/relay automation, schema reference, integration tests |

## Security Model

Rules:

- Public mobile builds must not contain Lark `app_secret`, raw tenant tokens, user refresh tokens, cookies, or exported credential files.
- `tenant_access_token` should be obtained through a managed token broker or another trusted runtime, not directly from the Flutter client with app credentials.
- `user_access_token` may be stored only through platform secure storage, with clear disconnect and revoke UX.
- All logs and evidence must redact `Authorization`, `app_secret`, refresh tokens, cookies, and document content marked private.
- Write actions must be dry-run first unless the user explicitly confirms the exact target and payload summary.
- Permission scope requests should be minimal and staged. Do not request broad Drive, Wiki, Bitable, or contact scopes until a feature needs them.

Recommended token modes:

| Mode | Use Case | Product Status |
| --- | --- | --- |
| `managedTenant` | App-owned folders, team benchmark sink, release evidence space | Preferred for shared team workflows |
| `userOAuth` | User-owned docs, sheets, wiki spaces, personal task flows | Preferred for personal workflows |
| `runtimeProvidedToken` | Local dev, CI, or enterprise managed devices | Dev / enterprise only |
| `h5ClientContext` | MobileCode page opened inside Lark client and using JSAPI for selection/opening | Companion UX only, not secret-bearing OpenAPI writes |
| `officialCliDevProbe` | Mac/CI runtime running `lark-cli` for validation and payload comparison | Development and QA only |
| `officialMcpRelay` | Managed server or Mac/CI runtime running `@larksuiteoapi/lark-mcp` | Optional structured adapter when Node is acceptable |
| `larkCliCompat` | Existing CLI diagnostics in Termux or desktop helper | Compatibility fallback |

## Product Surfaces

### Tools / Settings

- [x] Add `Lark Native API` card next to GitHub, RuntimeProvider, and managed model provider readiness.
- [x] Show token mode: `Not connected`, `Managed tenant`, `User OAuth`, or `Runtime provided`.
- [x] Show capability checks: Docs, Drive, Wiki, Sheets, Bitable.
- [x] Show missing scope and required input guidance without exposing internal token details.
- [ ] Add Messages after confirm-safe draft sender and scope model are ready.
- [ ] Keep the existing CLI connector under `Advanced / Compatibility`.

### Agent Tooling

- [x] Add typed actions: `lark_readiness`, `lark_docx_create`, `lark_docx_append_blocks`, `lark_drive_upload_preview`, `lark_sheets_append`, `lark_bitable_create_records`, `lark_wiki_list_spaces`.
- [x] Use JSON schemas with required target tokens and preview payloads.
- [x] Map the first MobileCode Lark typed actions to the native Dart OpenAPI adapter.
- [x] Treat `lark-cli` as the Mac development behavior-alignment source and record CLI samples before mobile-native parity claims.
- [ ] Run authenticated `lark-cli` samples in a development tenant and paste observed response/error payloads back into the parity table.
- [ ] Prefer MCP tool names and official schemas where `@larksuiteoapi/lark-mcp` already supports the needed API.
- [ ] Use explicit MCP `--tools` whitelists instead of exposing all APIs to the model.
- [x] Reject free-form shell-like Lark commands in the native path.
- [x] Attach ActionEvidence to every result: endpoint family, token mode, status code, Lark error code, request id, latency, redacted target, and dry-run/confirm trace.

### Evidence And Preview

- [x] Render a mobile evidence preview before writing to Lark.
- [ ] Save the generated Lark payload locally as redacted JSON.
- [ ] Link resulting Docx, Drive file, Sheet row, or Bitable record back into the MobileCode run.
- [ ] Make verifier outputs exportable to Lark Docs and Bitable.

### Live Relay Evidence Ingestion (MVP)

- [ ] Define a shared relay evidence shape for local packs in `tools/lark_relay/evidence/*.json`:
  - `event`: `event_id`, `tool`, `text`, `received_at`, optional `chat_id`/`message_id`/`open_id`
  - `reply`: `send_mode`, `status`, `text`, optional reply `message_id`
  - `evidence`: `failure_kind`, `next_action`, `request_id`, `event_id`, `log_id`, `token_mode`, `tool`, `error_code`, `raw_json_path`
- [ ] Lark API Lab renders each item as Event -> Reply -> Evidence timeline blocks.
- [ ] Include read-only raw JSON preview block for each entry.
- [ ] `tools/lark_relay/evidence/*.json` may contain `chat_id`、`message_id`、`open_id`; keep these fields out of public UI unless sanitized.

### H5 Companion Surface

- [ ] Add a small Lark H5 companion mode for target selection when MobileCode is opened from Lark.
- [ ] Use `docsPicker` and `filePicker` to choose user-visible resources, then pass resource identifiers back to native API actions.
- [ ] Use `openDocument` to open produced evidence reports after confirmed writes.
- [ ] Use `chooseChat` only to select a target; sending messages remains confirm-before-write through typed actions.
- [ ] Treat H5 `authorize` as client interaction evidence, not as permission to expose server credentials in WebView JavaScript.

## Implementation Phases

### P0: Plan And Compatibility Boundary

- [x] Add this plan as the Lark Native API source of truth.
- [x] Treat `larksuite/cli` as the preferred Mac development probe and reference implementation.
- [x] Treat `larksuite/lark-openapi-mcp` as an optional structured non-mobile adapter, not as the sole source of truth.
- [x] Rename public product wording from "Lark CLI connector" to "Lark Native API connector" where the default mobile product path is described.
- [x] Keep CLI wording only where it clearly means compatibility or diagnostics.
- [ ] Add a feature flag proposal: `lark_native_api`.
- [ ] Add a feature flag proposal: `lark_openapi_mcp_bridge`.

Acceptance:

- Public docs explain Node-free Lark mode.
- Public docs also explain that official CLI and MCP can be used on Mac/CI/relay as development and verification aids.
- No public surface implies Node, MCP, or `lark-cli` is mandatory for phone-side Lark support.
- No branch-internal wording or local paths are introduced.

### P1: Official CLI And MCP Evaluation

- [ ] Download/clone `larksuite/cli` to a dedicated local workspace and verify toolchain + auth flow.
- [ ] Use `lark-cli auth login --recommend` and `lark-cli auth status` to validate scopes in a development tenant.
- [ ] Use `lark-cli` shortcut/API/raw calls to create payload examples for Docs, Drive, Sheets, Base, and Wiki.
- [ ] Record and normalize payload differences (method/path/body/header) into Flutter-native action schemas.
- [ ] Record which CLI commands can serve as golden behavior for native Dart tests.
- [ ] Verify `@larksuiteoapi/lark-mcp` on Mac with `--domain https://open.larksuite.com`.
- [ ] Test stdio mode for local agents and streamable mode for a relay prototype.
- [ ] Run with explicit `--tools` whitelist for Docs, Wiki, Sheets, Bitable, IM, and Calendar candidates.
- [ ] Test `--token-mode user_access_token` for personal resource access.
- [ ] Record unsupported required product operations, especially file upload/download and Docx direct editing.

Acceptance:

- MobileCode has a known-good config template for international Lark.
- Tool coverage matrix says which actions use CLI probes, MCP, and native OpenAPI.
- `app_secret` stays outside tracked files and mobile builds.

### P2: Native Client Skeleton

- [ ] Add `LarkApiClient` with base URL `https://open.larksuite.com/open-apis`.
- [ ] Add request middleware for `Authorization: Bearer`, JSON content type, multipart upload, timeout, and retry/backoff.
- [ ] Normalize errors into `LarkApiError`.
- [ ] Add redaction tests for auth headers and token-like fields.

Acceptance:

- Unit tests can hit fake Lark responses without network.
- Logs never contain access tokens.
- Rate-limit responses produce actionable recovery hints.

### P3: Auth And Readiness

- [ ] Add `LarkAuthService` with token mode enum.
- [ ] Add managed relay configuration for tenant token broker.
- [ ] Add user OAuth preparation path and disconnect UX.
- [ ] Add optional H5 client-context detection for MobileCode pages opened inside Lark.
- [ ] Add readiness checks in Tools / Settings.

Acceptance:

- User can see whether Docs, Drive, Wiki, Sheets, and Bitable are available.
- Missing scopes are shown as user-actionable guidance.
- App can run without Lark configured.

### P4: Read-Only And Preview

- [ ] Parse Lark Docx, Wiki, Drive, Sheet, and Bitable URLs into typed resource identifiers.
- [ ] Fetch safe metadata for supported resources.
- [ ] Add local preview cards for selected Lark targets.
- [ ] Add H5 target-picking bridge for docs/files/chats when available.
- [ ] Add evidence preview before any write.
- [ ] Add relay evidence reader for `tools/lark_relay/evidence/*.json` and show event/reply/evidence timeline in Lark API Lab.

Acceptance:

- MobileCode can inspect a Lark target and show what will be written.
- Failed access is represented as `needs_permission`, `not_found`, `rate_limited`, or `unsupported`.
- Relay evidence view presents `send_mode`, `failure_kind`, `next_action`, `event_id/request_id`, reply `message_id`, and raw JSON preview.

### P5: Confirmed Writes

- [ ] Create Docx report documents.
- [ ] Append Docx blocks from MobileCode evidence and Markdown summaries.
- [ ] Upload artifact files to Drive.
- [ ] Append benchmark rows to Sheets.
- [ ] Create Bitable records for task/run/release evidence.
- [ ] Require explicit confirmation for every write.

Acceptance:

- Each write produces a local evidence record with redacted request and response metadata.
- User can open the created Lark resource from MobileCode.
- Repeated writes use idempotency where supported.

### P6: Benchmark Lab Integration

- [ ] Add Lark tasks to `docs/mobile-harness-benchmark/`.
- [ ] Add verifier cases for Docx report creation, Drive upload, Sheet append, and Bitable record creation.
- [ ] Add mobile evidence capture: screenshots, local payload, redacted API result, and final Lark resource link.
- [ ] Add Benchmark Lab UI rows for Lark readiness and latest verifier result.

Acceptance:

- Benchmark Lab proves Lark Native API works from the phone-native harness.
- Verifier does not require Node or `lark-cli`.
- Evidence chain remains compatible with the existing MobileHarnessBench reports.

### P7: CLI Compatibility Freeze

- [ ] Mark the existing CLI connector as advanced compatibility.
- [ ] Stop adding new product features to CLI-only flows.
- [ ] Reuse the same typed action schema between native API and CLI dry-run compatibility where practical.
- [ ] Keep CLI tests limited to diagnostics and backward compatibility.

Acceptance:

- New Lark product demos use native API mode.
- CLI absence is no longer a blocker for Lark product features.

## Minimal Product Increment

First shippable increment:

1. `Lark Native API` card in Tools.
2. Official CLI dev-probe commands for Mac, plus optional MCP bridge config template for Mac/CI/relay with `--domain https://open.larksuite.com`.
3. Managed relay URL configured through existing provider settings pattern.
4. Readiness check for token broker, native API client, and Docs scope.
5. Create a Docx evidence report from a local Benchmark Lab run.
6. Store redacted evidence locally and show the created document link.

This is the smallest useful loop because it connects the product story:

```text
phone-native benchmark run
-> local evidence pack
-> native Lark API write, validated against official CLI/MCP probes
-> shareable Lark Docx report
-> verifier-visible evidence link
```

## Testing Plan

- [ ] `dart test` for `LarkApiClient`, auth redaction, URL parsing, and fake response handling.
- [ ] Mac/CI smoke for selected `lark-cli` auth, Docs, Drive, Sheets, Base, and Wiki commands.
- [ ] Mac/CI smoke for `npx -y @larksuiteoapi/lark-mcp mcp --domain https://open.larksuite.com --tools <whitelist>`.
- [ ] `flutter analyze` after mobile code changes, or document local Flutter analyzer limitations.
- [ ] `python3 scripts/validate_mobile_harness_bench.py` after benchmark task changes.
- [ ] `npm run build` in `app/` if public Pages or Developer copy changes.
- [ ] Android emulator smoke: connect mode, readiness, create report dry-run, confirmed write.
- [ ] iOS simulator smoke: same flow, with secure storage and URL launch verification.

## Open Questions

- Which tenant should host the managed evidence workspace: Lark global or Feishu China tenant?
- Should MobileCode use an internal self-built app first, then later a marketplace app?
- Where will the managed token broker live, and how will it bind invite/developer access without leaking secrets?
- Which first sink matters more for product proof: Docx report, Sheet benchmark row, or Bitable run registry?
- Should Lark message sending be included in the first write phase, or stay deferred until Docs/Drive evidence is stable?

## Public Copy Direction

Use this wording:

- "Lark Native API connector"
- "Node-free Lark OpenAPI mode"
- "Docs, Drive, Sheets, Bitable, and Wiki actions with mobile evidence"
- "CLI compatibility is optional for advanced runtimes"

Avoid this wording in default product surfaces:

- "requires lark-cli"
- "requires Node"
- "paste app_secret into the app"
- "silent send"
- "raw shell command"
