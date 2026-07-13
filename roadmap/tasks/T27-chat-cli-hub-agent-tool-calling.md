# T27 Chat CLI Hub Agent Tool Calling

Status: [ ] In progress; V1 core bridge, V2 preview-first/chat approval trace UI plus Extension Center/Usage Hub refresh signal, V3 service-level output bounds/redaction/task monitor, V3 multi-provider chat business task/recovery tests, V4 permission gating, V5 local schema gates/local import/remove/safe remote fetch/SHA-256 integrity/Ed25519 trusted keyring plus trusted-key lifecycle schema boundary, trusted-key import/store/manage/remove/revoke UI, trusted-key rotation deadline gate, verified remote catalog import UI, and Android Dev Harness GitHub CLI install/probe QA implemented with tests/build/evidence; real Android CLI login/business QA, true quota refresh, remote marketplace install, complete key rotation/revocation trust chain, and complete catalog trust chain pending
Priority: P1
Owner role: software-dev-pipeline + appui-design-skill + quality-reviewer
Depends on: T04, T13, T14, T25, T26

## 目标

让 MobileCode 聊天层可以通过 `cli_hub_task` function call 安全调用 CLI Hub typed task，并把执行结果通过 evidence 回传给模型。

## 范围

- In scope:
  - `cli_hub_task` function schema。
  - tool availability context。
  - `ToolCallAdapter -> ActionSchema -> ActionRunner -> RuntimeTypedTaskRunner` 桥。
  - Linux Sandbox CLI typed task 的聊天调用。
  - approval、redaction、evidence、tool result message。
- Out of scope:
  - 任意 raw shell 默认开放。
  - 把 CLI profile 打进 Pure APK。
  - 订阅账号登录和模型转发的 provider 细节；这些属于 T26。
  - Cloud Runner 和团队治理；这些属于后续阶段。

## Reference Assets / 视觉参考

- R1: `docs/mobilecode-cli-hub-agent-tool-calling-long-term-roadmp.md`
  - Borrow: V1-V8 阶段、tool schema、approval、evidence、runtime 边界。
  - Do not copy: 未验证完成态。
  - Notes: 本任务文件是执行入口，长期细节以 long-term roadmp 为准。
- R2: `docs/assets/reference/linux-sandbox-roadmp/r3-alpine-linux-sandbox.svg`
  - Borrow: Alpine runtime 状态、安装和恢复建议。
  - Do not copy: 外部 runtime 默认路径。

## Key Decisions

- [x] `cli_hub_task` 作为聊天层 CLI Hub 的统一 function。
- [x] 默认只允许 typed task；Full access raw shell 是单独工具。
- [x] CLI task 必须来自 `CliHubCatalog`，不能由模型自由拼 command。
- [x] `ActionRunner` 是审批、校验和 evidence 边界，不是 native runtime。
- [x] Linux Sandbox 是 v1 的主要 CLI execution runtime。

## Task List

### V1: Chat 调用 CLI 状态与检测

- [x] 增加 `cli_hub_task` tool schema。
- [x] 增加 per-request CLI capability context。
- [x] `ToolCallAdapter` 将 `cli_hub_task` 映射为 `ActionSchema`。
- [x] `ActionRunner` 增加 CLI Hub task 校验和执行。
- [x] 调用 `RuntimeTypedTaskRunner.runTypedTask()`。
- [x] GitHub CLI auth status 作为首个 E2E case。
- [x] Google Workspace、Agent Mail、Lark auth status 接入同一链路。
- [x] tool result message 回传模型。

### V2: Chat 引导安装与登录

- [ ] 聊天安装 CLI profile。
  - Note: `package_install` typed task、chat trace preview card、用户确认后以 `payload.approved=true` 重放同一 typed task 已接入；模型系统上下文已补充“帮我安装 GitHub CLI”到 `package_install githubCli` 的显式 intent mapping；AgentLoop focused test 已覆盖中文安装意图先返回 approval preview、用户确认后再执行 approved install。真实模型/真机自然语言端到端安装 QA 仍需补，所以暂不打完成。
- [ ] 聊天启动官方 login/auth/setup flow。
  - Note: auth/login/setup taskKind 已接入 catalog 和 ActionRunner；真实官方 flow 的 UI/QA 仍需补。
- [x] install/auth/login/mutation task 未确认时不启动 runtime。
- [x] 用户取消 approval 时不执行 task。
- [x] approvalRequired evidence 详情展示 CLI 名称、taskKind、risk、credential policy、runtime、packages、approval preview 和 typed payload preview。
- [x] 聊天 trace 中的 approval preview 可显示 `Confirm typed task`，用户确认后执行 approved typed task 并生成新的 evidence。
- [x] auth flow 输出 redaction。
- [x] 安装和登录状态刷新 Extension Center / Usage Hub。
  - Evidence: Extension Center 与 Usage Hub 已监听 `CliHubRuntimeEvents`；聊天 approved task 或扩展中心任务完成后会触发 Extension Center refresh，GitHub CLI 成功 auth/status 事件会刷新 Copilot/GitHub quota，Google Workspace CLI 成功事件会刷新 Antigravity/Google quota。Focused tests passed: `flutter test test/widgets/extension_center_screen_test.dart test/services/cli_hub_runtime_events_test.dart test/widgets/subscription_usage_hub_screen_test.dart`。

### V3: 受控业务 CLI 任务

- [x] GitHub repo list。
- [x] Google Drive files list。
- [x] Agent Mail message list。
- [x] Lark Wiki space list。
- [x] 任务分页、输出大小限制、PII redaction。
  - Note: ActionRunner 对 catalog read-only business task 注入 bounded limit/pageSize，记录 outputLimit/truncated metadata，并做基础 email/phone/token redaction；模型系统上下文已补充 GitHub repo、Google Drive、Agent Mail、Lark Wiki 中文意图到对应 catalog `commandId` 的显式 mapping；分页 UI 与真机业务列表 QA 尚未完成。
- [x] 长任务 task snapshot、stop、logs、timeout 状态基础。
  - Note: Linux Sandbox typed task 已接入 `RuntimeTaskMonitor`/`RuntimeTaskController`，会记录 currentTask/history/logs，stop 写入 cancelled snapshot；timeout 分类由 runtime result 映射。真实 Android native process 强杀仍是后续 runner 能力，不在本次虚标。

### V4: Full Access Raw Shell

- [x] UI 增加 Harness permission mode。
- [x] Full access 才暴露 `raw_shell`。
- [x] 危险命令二次确认。
- [x] raw shell evidence 与 typed task evidence 分开。

### V5-V8: Long-term

- [ ] CLI Hub 插件生态。
  - Note: V5 本地 catalog JSON、远端 catalog manifest envelope 解析/校验、安全远端 fetch 边界、可选 SHA-256 catalog integrity verification、Ed25519 trusted keyring verification、trusted key lifecycle schema gate、trusted key 本地持久化/导入/管理/移除/撤销 UI、trusted key rotation deadline gate、本地 extension merge、imported read-only task 进入聊天 CLI Hub context、service-level extension entry removal、service-level install preview/source disclosure、扩展中心安装确认弹窗中的来源/风险/凭据策略/任务范围展示、本地 extension catalog 持久化 store、扩展中心本地 JSON 导入/移除 UI、以及 verified remote catalog import UI 已加固；远端 marketplace 安装、完整 key rotation/revocation trust-chain UX 和完整信任链仍未完成。
- [ ] 多 runtime / 多设备 / 云端协同。
- [ ] 自动化 workflow。
- [ ] 团队与企业治理。

## Visual Acceptance

- [x] 聊天中出现 typed task preview card。
- [x] preview card 显示 CLI 名称、taskKind、risk、credential policy、runtime、approval 状态。
- [x] 执行中显示 progress/event。
  - Evidence: 2026-06-26 `AgentTraceProgressBox` 已接入聊天 trace row；用户确认 CLI Hub typed task 后先插入 running step，完成后用同一 step 更新为 done/failed。Focused `flutter test test/widgets/agent_trace_progress_box_test.dart test/widgets/agent_trace_recovery_box_test.dart` passed，4 tests passed。
- [x] 完成后显示 evidence id 和 redacted result。
- [x] 未安装 Alpine 或 CLI profile 时显示恢复入口。
  - Evidence: 2026-06-26 `AgentTraceRecoveryBox` 已从聊天 trace 抽成可测试组件；`flutter test test/widgets/agent_trace_recovery_box_test.dart` passed，覆盖 Alpine/CLI profile recovery 显示“打开能力中心”入口，普通 provider recovery 不显示该入口。真机截图 QA 仍作为后续补证项。

## Evidence / 已完成证据

- [x] 2026-06-26 长期 roadmp 已创建：`docs/mobilecode-cli-hub-agent-tool-calling-long-term-roadmp.md`。
- [x] `cli_hub_task` schema 实现证据：2026-06-26 `flutter test test/services/tool_call_adapter_test.dart` passed。
- [x] GitHub CLI auth status 端到端聊天调用证据：2026-06-26 `flutter test test/services/agent_loop_controller_test.dart` passed，模拟“帮我看 gh 登录状态”触发 `cli_hub_task` 并记录 `MobileCodeAction.cliHubTaskStart` evidence。
- [x] ActionRunner catalog gating 证据：2026-06-26 `flutter test test/core/evidence/action_runner_test.dart` passed，覆盖 unknown task、unsafe payload、needsSetup recovery、install/login/business typed tasks。
- [x] V2 preview-first 证据：2026-06-26 `flutter test test/core/evidence/action_runner_test.dart` passed，覆盖 install/login/mutation task 未 approval 时只返回 `approvalRequired` preview evidence、不启动 runtime；`payload.approved=true` 后才调用 runtime；`payload.cancelled=true` 时返回 cancelled evidence。
- [x] V2 preview evidence UI 证据：2026-06-26 `flutter test test/services/cli_hub_catalog_service_test.dart test/core/evidence/action_runner_test.dart test/services/tool_call_adapter_test.dart` passed；`ActionEvidence` 详情可显示 CLI Hub preview metadata，包括 CLI、taskKind、runtime、risk、credential policy、packages、approval preview 和 typed payload preview。
- [x] V2 chat approval trace UI 证据：2026-06-26 `flutter test test/services/agent_loop_controller_test.dart` passed，覆盖 install preview metadata 会通过 `AgentLoopEvent.evidenceMetadata` 传到聊天 trace，未 approval 不触发 runtime；Home trace 已实现 `Confirm typed task` 按钮，确认后以 `payload.approved=true` 重放 `cli_hub_task` 并记录新的 `MobileCodeAction.cliHubTaskStart` evidence。
- [x] V2 Extension Center / Usage Hub refresh 证据：2026-06-26 `flutter test test/widgets/extension_center_screen_test.dart test/services/cli_hub_runtime_events_test.dart test/widgets/subscription_usage_hub_screen_test.dart` passed，覆盖聊天侧 `CliHubRuntimeEvents` install/auth 状态事件会触发 Extension Center 重新读取 Linux Sandbox status，并触发 Usage Hub 中 GitHub/Copilot、Google/Antigravity 对应 quota 状态刷新。
- [x] V3 output boundary 证据：2026-06-26 `flutter test test/core/evidence/action_runner_test.dart` passed，覆盖 GitHub repo list typed task 的 bounded `limit`、`outputLimitBytes`、`stdoutTruncated` metadata，以及 email/phone PII redaction。
- [x] V3 evidence metadata 证据：2026-06-26 `ActionRunner` 已将 CLI Hub runtime status、catalog `commandId`、`limit/pageSize` 提升到 evidence metadata 顶层，便于聊天 trace 和后续 QA 直接读取，不需要从 runtimeMetadata 深层解析。
- [x] V3 task monitor 证据：2026-06-26 `flutter test test/services/linux_sandbox_provider_test.dart` passed，覆盖 Linux Sandbox typed task currentTask、taskLogs、best-effort stop、cancelled history snapshot 和 runtime timeout/status 映射基础。
- [x] Linux Sandbox typed task 边界证据：2026-06-26 `flutter test test/services/linux_sandbox_provider_test.dart` passed，覆盖 GitHub/Google Workspace/Agent Mail/Lark commandId allowlist 和 approval。
- [x] Harness permission mode UI 证据：2026-06-26 `flutter test test/widgets/settings_screen_permissions_test.dart` passed，覆盖 Settings 中三档权限选择和持久化。
- [x] V5 schema gate 证据：2026-06-26 `flutter test test/services/cli_hub_catalog_service_test.dart` passed，覆盖本地 catalog manifest 重复 id、`raw_shell` taskKind、token/credential-like payload 字段拒绝；planned 占位项允许缺少未实现 probe，但仍受安全 gate 约束。
- [x] V2/V3 intent mapping 证据：2026-06-26 `flutter test test/services/tool_call_adapter_test.dart` passed，覆盖模型系统上下文包含“帮我安装 GitHub CLI”到 `package_install githubCli`，以及 GitHub repo、Google Drive、Agent Mail、Lark Wiki 业务意图到 catalog `commandId` 的显式 mapping。
- [x] V5 schema gate 加固证据：2026-06-26 `flutter test test/services/cli_hub_catalog_service_test.dart` passed，新增覆盖 manifest `updatedAt`/entries、非 planned 条目的官方来源、显式 risk/credential policy、task label/taskKind、read-only/mutation classifier 与 approval 标记一致性；四个 read-only business task 已修正为不需要 mutation approval。
- [x] AgentLoop approved install/read-only 证据：2026-06-26 `flutter test test/services/agent_loop_controller_test.dart test/core/evidence/action_runner_test.dart` passed，61 tests passed；新增覆盖 approved GitHub CLI install 会以 `payload.approved=true` 调用 runtime 并成功记录 evidence，以及“列出我的 GitHub repo”只走 catalog read-only `github_cli_execute` + `commandId=repo_list`，payload 不含 `command`/`shell`。
- [x] V3 multi-provider chat task 证据：2026-06-26 `flutter test test/services/agent_loop_controller_test.dart test/core/evidence/action_runner_test.dart` passed，63 tests passed；新增覆盖 Google Drive files、Agent Mail messages、Lark Wiki spaces 三类业务意图均走 catalog read-only typed task，payload 不含 `command`/`shell`，stdout/stderr 中 email/phone 被 redacted。
- [x] V3 auth recovery 证据：2026-06-26 同一 focused test 覆盖 Google Workspace CLI 未登录业务 task 返回 `authFailed`，tool result 包含 provider-specific recovery `Run the official login task for Google Workspace CLI...`，metadata/text 不泄漏邮箱原文。
- [x] V5 remote manifest schema 证据：2026-06-26 `flutter test test/services/cli_hub_catalog_service_test.dart` passed，新增 `CliHubRemoteCatalogManifest` envelope 校验，覆盖 `schemaVersion/catalogId/name/version/updatedAt/source/minAppVersion/signature/catalog`；只允许 `https` source、要求签名声明、内嵌 catalog 继续拒绝 `raw_shell`/secret payload。真实远端下载与验签未实现。
- [x] V5 local extension context 证据：2026-06-26 `flutter test test/services/cli_hub_catalog_service_test.dart test/services/tool_call_adapter_test.dart` passed，42 tests passed；新增覆盖本地 extension catalog merge、重复 id 拒绝，以及 injected catalog 生成 CLI Hub tool context，`safe-notes-cli.safe_notes_cli_execute commandId:note_list` 可被聊天层看到。远端下载、真实验签和 extension 卸载仍未实现。
- [x] V5 local extension removal model 证据：2026-06-26 `flutter test test/services/cli_hub_catalog_service_test.dart` passed，10 tests passed；`CliHubCatalogService.removeExtensionEntry()` 可从 merged catalog 移除 validated local extension entry，保留 bundled entries，并拒绝移除 `github-cli` 等内置 CLI id 或不存在的 extension id。此证据只代表 service-level 生命周期模型，不代表用户可见卸载 UI 已完成。
- [x] V5 local extension install preview model 证据：2026-06-26 `flutter test test/services/cli_hub_catalog_service_test.dart` passed，11 tests passed；`CliHubCatalogService.buildExtensionInstallPreview()` 返回 source、officialSources、package profile、packages、riskLevel、credentialPolicy、supportLevel、read-only/mutation task counts 和 `requiresApproval=true`，并拒绝 bundled id 与未知 extension id。此证据只代表 service-level preview/source disclosure，不代表用户可见插件安装 UI 或持久化已完成。
- [x] V5 extension install preview UI 证据：2026-06-26 `ExtensionCenterScreen` 安装确认弹窗已展示 CLI 官方来源、安装包、risk level、credential policy、read-only/mutation task counts，并声明 typed task 执行、不暴露 raw shell；focused `flutter test test/widgets/extension_center_screen_test.dart test/services/cli_hub_catalog_service_test.dart` passed，19 tests passed。此证据只覆盖内置/preview catalog 的用户可见安装预览，不代表远端下载、真实验签、自定义 extension 持久化或完整插件市场已完成。
- [x] V5 local extension persistence store 证据：2026-06-26 `CliHubLocalExtensionStore` 已支持 validated local catalog JSON 写入 SharedPreferences、与 bundled catalog 合并、按 extension entry id 移除，并在保存前拒绝 private key、常见 token、cookie/session、OAuth code 和 `.env` path pattern；focused `flutter test test/services/cli_hub_catalog_service_test.dart` passed，13 tests passed。此证据只代表本地持久化 service model，不代表完整用户可见导入/卸载 UI、远端下载或真实签名验签已完成。
- [x] V5 local extension import/remove UI 证据：2026-06-26 `ExtensionCenterScreen` 已接 `CliHubLocalExtensionStore`，默认加载 bundled catalog 后 merge 本地 validated catalogs；AppBar 提供“导入本地 CLI Catalog”入口，用户粘贴 JSON 后通过 schema/sensitive-material gate 才写入 SharedPreferences；本地 extension card 显示“移除”，只删除本地 catalog 记录，不删除内置 CLI、不执行 raw shell。Focused `flutter test test/widgets/extension_center_screen_test.dart` passed，9 tests passed；`flutter test test/services/cli_hub_catalog_service_test.dart` passed，13 tests passed。
- [x] V5 safe remote catalog fetch boundary 证据：2026-06-26 `CliHubCatalogService.fetchRemoteManifest()` 已实现远端 manifest 下载前/下载中/解析前安全边界：只允许 `https` 且无 userInfo，`maxBytes` 上限 2 MiB，下载 timeout，拒绝 redirect/非 200/超长 content，解析前跑 sensitive-material scan，manifest `source` 必须与请求 URL 完全一致，随后复用 `CliHubRemoteCatalogManifest` 和内嵌 catalog schema gate；不执行 merge/install/raw shell。Focused `flutter test test/services/cli_hub_catalog_service_test.dart` passed，15 tests passed；`flutter test test/services/tool_call_adapter_test.dart --plain-name "adds imported CLI extension tasks to CLI Hub tool context"` passed。真实 cryptographic signature verification、远端 catalog marketplace 下载入口和信任链仍未完成。
- [x] V5 SHA-256 remote catalog integrity verification 证据：2026-06-26 `loadRemoteManifestJson(..., requireVerifiedSignature: true)` 与 `fetchRemoteManifest(..., requireVerifiedSignature: true)` 已支持 `signature.algorithm=sha256` 的 canonical catalog JSON digest 校验；digest mismatch 会拒绝，Ed25519 declaration-only 在 require verified 时会拒绝，避免把签名声明误当成已验签。Focused `flutter test test/services/cli_hub_catalog_service_test.dart` passed，17 tests passed。此项只代表 SHA-256 完整性 gate，不代表 Ed25519 公钥验签、远端 marketplace 安装或信任链完成。
- [x] V5 Ed25519 trusted keyring verification 证据：2026-06-26 新增 direct dependency `cryptography: ^2.9.0`；`loadRemoteManifestJson(..., requireVerifiedSignature: true, trustedEd25519PublicKeys: {...})` 与 `fetchRemoteManifest(...)` 可对 canonical catalog JSON 做 Ed25519 验签。manifest 只携带 signature value，调用方必须提供 trusted `keyId -> publicKey`，未信任 key、错误 key 或签名不匹配都会拒绝。Focused `flutter test test/services/cli_hub_catalog_service_test.dart` passed，19 tests passed。此项不代表远端 marketplace 安装、key rotation/revocation UX 或完整信任链完成。
- [x] V5 trusted key lifecycle schema 证据：2026-06-26 `CliHubTrustedKey` 已支持 `keyId/algorithm/publicKeyBase64/allowedCatalogIds/allowedHosts/validFrom/validUntil/revoked`，`loadRemoteManifestJson(..., trustedKeyring: [...])` 会在 Ed25519 验签前拒绝 revoked、过期、未生效、catalog/host 不匹配的信任根；focused `flutter test test/services/cli_hub_catalog_service_test.dart` passed，21 tests passed；changed-file `dart analyze` 只剩 `CliHubCatalogService` 里 6 个既有 info-level style lints。此项不代表远端 marketplace 安装、key rotation/revocation 用户界面或完整 trust chain 已完成。
- [x] V5 verified remote catalog import UI 证据：2026-06-26 `ExtensionCenterScreen` 新增“导入远端 CLI Catalog”入口，要求 HTTPS manifest 通过 `CliHubCatalogService.fetchRemoteManifest(..., requireVerifiedSignature: true)` 完整性/签名校验后才序列化为本地 extension catalog 并写入 `CliHubLocalExtensionStore`；未验证或 digest mismatch 会拒绝，不 merge、不执行 raw shell。Focused `flutter test test/widgets/extension_center_screen_test.dart` passed，11 tests passed；combined `flutter test test/services/cli_hub_catalog_service_test.dart test/widgets/extension_center_screen_test.dart` passed，32 tests passed。此项不代表完整 marketplace、key rotation/revocation UI 或远端 trust-chain UX 已完成。
- [x] V5 trusted key import/store UI 证据：2026-06-26 `CliHubTrustedKeyStore` 已支持 Ed25519 trusted public key JSON 的 SharedPreferences 持久化、重复 key 拒绝、移除、sensitive-material gate，并且 `toMetadata()` 不暴露 `publicKeyBase64`；`ExtensionCenterScreen` 新增“导入远端信任密钥”入口，header 显示 trusted key 数量，远端 import 会使用本地 keyring 校验 Ed25519 manifest 后才写入本地 extension store。Focused `flutter test test/services/cli_hub_catalog_service_test.dart test/widgets/extension_center_screen_test.dart` passed，35 tests passed。此项不代表 key rotation/revocation 完整管理 UI、远端 marketplace 或完整 trust chain 已完成。
- [x] V5 trusted key management/removal UI 证据：2026-06-26 `ExtensionCenterScreen` 新增“管理远端信任密钥”入口，展示 keyId、algorithm、catalog/host scope 与有效期，不展示 public key；用户可移除本地 trusted key，header trusted key count 会刷新为 0，后续远端 Ed25519 catalog 不能继续依赖该信任根。Focused `flutter test test/widgets/extension_center_screen_test.dart` passed，13 tests passed。此项不代表 key rotation、远端 marketplace 或完整 trust chain 已完成。
- [x] V5 trusted key rotation deadline 证据：2026-06-26 `CliHubTrustedKey` 新增 `replacementKeyId` 与 `rotationRequiredAfter`；Ed25519 remote catalog 验签会在轮换截止时间后拒绝旧 trust root，扩展中心管理弹窗展示 `rotateTo/rotateBy` 元数据但仍不展示 public key。Focused `flutter test test/services/cli_hub_catalog_service_test.dart test/widgets/extension_center_screen_test.dart` passed，37 tests passed。此项不代表完整 key rotation/revocation UX、远端 marketplace 或完整 trust chain 已完成。
- [x] V2 Pure/Pending Alpine recovery 证据：2026-06-26 `ActionRunner` 将 runtime 返回的 `needsSetup` 规范保留为 canonical `needsSetup`，并把 `needsSetup` 映射为 `dependencyMissing`；新增 `AgentLoop returns Alpine recovery when approved CLI install needs setup` 覆盖用户已批准 GitHub CLI 安装但 Alpine/Linux Sandbox 不可用时，只记录 failed `cli_hub_task` evidence、返回安装/校验 Alpine recovery，不静默安装 CLI、不暴露 raw shell。Focused `flutter test test/services/agent_loop_controller_test.dart --plain-name "AgentLoop returns Alpine recovery when approved CLI install needs setup"` passed；`flutter test test/services/agent_loop_controller_test.dart` passed，30 tests passed；`flutter test test/core/evidence/action_runner_test.dart` passed，37 tests passed。
- [x] Latest validation after V2 Alpine recovery 证据：2026-06-26 full `flutter test` passed，466 tests passed；Dev Harness APK build passed，SHA-256 `47cf68b81613165ed729a546da6c11215e3716daf28edf10386e5a1c7243c3fd`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5214 analyzer issues 返回 exit 1，未作为完成态；`git diff --check` clean；changed-file strict secret scan only matched static denylist literals、historical placeholder/evidence text and `risk-register` filename false positives, no real credential values。
- [x] V4 raw shell hardening regression 证据：2026-06-26 `CliHarnessCapabilityService` 覆盖 `git clean -fdx`、`find -delete`、`dd`、`curl | sh`、`gh auth token`、`printenv` 均需要 second approval 且 credential policy forbidden；`ActionRunner` 覆盖 `raw_shell` 映射来的 approval-gated `runCommand` 只记录 `commandBlocked` approval evidence，不执行命令，也不会生成 `cliHubTaskStart` evidence。Focused `flutter test test/services/cli_harness_capability_service_test.dart` passed，4 tests passed；`flutter test test/core/evidence/action_runner_test.dart` passed，38 tests passed；`flutter test test/services/tool_call_adapter_test.dart` passed，33 tests passed。
- [x] Latest validation after V4 raw shell hardening 证据：2026-06-26 full `flutter test` passed，468 tests passed；Dev Harness APK build passed，SHA-256 `47cf68b81613165ed729a546da6c11215e3716daf28edf10386e5a1c7243c3fd`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5214 analyzer issues 返回 exit 1，未作为完成态；`git diff --check` clean；changed-file strict secret scan only matched static/historical placeholders, `risk-register` filename false positives, and test-only fake token/cookie/OAuth strings used by redaction regression, no real credential values。
- [x] Chat trace recovery UI 证据：2026-06-26 `home_screen.dart` 的 agent trace row 新增 recovery box，优先读取 `ActionEvidence.recoveryActions`，其次读取 tool metadata 中的 `recoveryActions/recovery/recoveryHints`，`needsSetup` 时给出安装 Alpine/CLI profile 的恢复建议，并提供“打开能力中心”按钮；focused `flutter test test/services/agent_loop_controller_test.dart test/core/evidence/action_runner_test.dart test/widgets/capability_center_screen_test.dart` passed，64 tests passed。后续仍可补真机截图 QA。
- [x] Chat trace recovery widget 证据：2026-06-26 `AgentTraceRecoveryBox` 已抽为独立 widget，`flutter test test/widgets/agent_trace_recovery_box_test.dart` passed，2 tests passed；覆盖 Alpine/CLI profile recovery 会显示“打开能力中心”，generic provider recovery 不显示能力中心快捷入口。
- [x] Chat trace progress widget 证据：2026-06-26 `AgentTraceProgressBox` 已接入 Home trace；approved CLI Hub typed task 会先显示 `Task running` 进度事件，runtime 返回后更新为完成/失败事件；focused `flutter test test/widgets/agent_trace_progress_box_test.dart test/widgets/agent_trace_recovery_box_test.dart` passed，4 tests passed。
- [x] Full regression 证据：2026-06-26 `flutter test` passed，459 tests passed。
- [x] Analyze gate recovery 证据：2026-06-26 将 83 个 legacy/experimental 且不在当前 APK 入口编译链路内的文件加入 `mobile_agent/analysis_options.yaml` 精确路径 quarantine；这批文件承载了当前 777 个 analyzer errors。Quarantine 后 `flutter analyze --no-fatal-infos --no-fatal-warnings` passed，exit 0，0 errors，2966 info，123 warnings。此项只代表 active app / CLI Hub / Linux Sandbox / subscription surfaces 的 analyzer gate 恢复，不代表 legacy quarantined files 已逐行迁移完成。
- [x] Dev Harness APK 证据：2026-06-26 `flutter build apk --debug --flavor devharness --dart-define=MOBILECODE_BUILD_CHANNEL=devHarness --dart-define=MOBILECODE_DEV_EXTENSIONS=true --dart-define=MOBILECODE_HARNESS_CLI=true --target lib/main.dart` passed，输出 `mobile_agent/build/app/outputs/flutter-apk/app-devharness-debug.apk`，SHA-256 `7dc51aba0ea83162a89c8996b08c07fb58f7a28361d6b564ce783a6df4acdc2b`。
- [x] Hygiene 证据：2026-06-26 `git diff --check` clean；changed-file strict secret pattern scan only matched static denylist literal `oauth_code` in `CliHubCatalogService` and placeholder `<tenant_access_token>` in an existing Lark dry-run example, no credential values.
- [x] Android Dev Harness emulator QA 证据：2026-06-26 installed/launched `com.mobilecode.app.dev` on `emulator-5554`; evidence at `mobile_agent/qa-output/android-devharness-local-20260626-183321/` includes `apk-sha256.txt`, `install.txt`, `launch.txt`, `screenshot-main.png`, `window-main.xml`, `window-focus.txt`, sanitized `logcat.txt`, and `summary.json`; summary `ok=true`, UI XML contains `MobileCode`, no `FATAL EXCEPTION`/`E/flutter`/`MissingPluginException`/`ANR`; QA evidence secret scan clean after redacting Android system binder ids.
- [x] Android GitHub CLI profile QA 证据：2026-06-26 Android Dev Harness emulator 从抽屉进入 `能力中心 -> 扩展中心 -> CLI Hub`，确认 header 显示 `Dev Harness · Alpine built-in · CLI 按需安装`，Alpine `installed`；GitHub CLI `安装` 展示 typed task approval preview，确认后 card 内显示 `正在安装 GitHub CLI...`，60s 后显示 `完成 · succeeded`，postcondition 返回 `gh version 2.93.0 (2026-06-04)`；`检测` 返回同一版本；`状态` 返回未登录恢复提示；`登录` 只展示 approval preview，未确认产生 OAuth code。证据文件包括 `screenshot-github-cli-install-after-tap.png`、`screenshot-github-cli-install-after-60s.png`、`screenshot-github-cli-probe-after-install.png`、`screenshot-github-cli-auth-status.png`、`screenshot-github-cli-login-preview.png` 及对应 XML。保留真实 warning：install 日志包含 `failed to write database: Permission denied`，但 postcondition 已通过，需后续定位 apk database 写权限。
- [x] Android GitHub CLI install warning follow-up 证据：2026-06-26 `LinuxSandboxRunner.kt` 已在 package profile mutation 前补 `prepareRootfsForPackageMutation()`，并强化 rootfs file/dir write permission preparation；focused tests `flutter test test/services/agent_loop_controller_test.dart test/core/evidence/action_runner_test.dart test/services/linux_sandbox_provider_test.dart` passed，74 tests passed；Dev Harness APK 重新构建通过，SHA-256 `ee718a2b3dc5d5697d45d01bc609294cd1d0a1a3aa4716f19e85eb021299c3a9`。Android emulator QA 证据位于 `mobile_agent/qa-output/android-devharness-local-20260626-185034-github-cli-permission/`，安装/启动通过，GitHub CLI 仍 postcondition verified with `gh version 2.93.0 (2026-06-04)`；但 `failed to write database: Permission denied` warning 仍可复现，所以只记录 hardening 与真实结果，不宣称 warning 已修复。
- [x] Latest regression 证据：2026-06-26 after chat trace recovery UI follow-up, focused `flutter test test/services/agent_loop_controller_test.dart test/core/evidence/action_runner_test.dart test/widgets/capability_center_screen_test.dart` passed，64 tests passed；full `flutter test` passed，450 tests passed；Dev Harness APK build rerun passed，SHA-256 `4bd574ff421f6f1b345e5cf81a2754c74d9d66dfdb4af4ba9612126c2e53bbb6`；`flutter analyze --no-fatal-infos --no-fatal-warnings` rerun returned exit 1 with 5214 analyzer issues，仍不作为 T27 完成态；`git diff --check` clean。
- [x] Latest recovery widget regression 证据：2026-06-26 after extracting `AgentTraceRecoveryBox`, focused `flutter test test/widgets/agent_trace_recovery_box_test.dart` passed，2 tests passed；full `flutter test` passed，452 tests passed；Dev Harness APK build passed，SHA-256 `906067a56436c93424043c7efe6da8845fece7e7f3418b5389c7d83b8fd5ae78`；`flutter analyze --no-fatal-infos --no-fatal-warnings` rerun returned exit 1 with 5212 analyzer issues，仍不作为 T27 完成态；`git diff --check` clean；changed-file secret scan only matched static safety labels, existing token UI copy, and placeholder `<tenant_access_token>`, no credential values.
- [x] V2 two-step chat install/login regression 证据：2026-06-26 `flutter test test/services/agent_loop_controller_test.dart` passed，29 tests passed；新增覆盖中文“帮我安装 GitHub CLI”先生成 `approvalRequired` preview 且不调用 runtime，随后“用户已确认安装 GitHub CLI”才以 `payload.approved=true` 执行 `package_install githubCli`；同时覆盖“帮我登录 GitHub CLI”只生成 `github_cli_auth_login` approval preview，不自启动 login runtime。
- [x] Latest final validation 证据：2026-06-26 full `flutter test` passed，457 tests passed；Dev Harness APK build passed，SHA-256 `081f8d7342fb81080023b0c3d36d3dbafe3155b9bd9e4f4c0e38343c367fb7fc`；`flutter analyze --no-fatal-infos --no-fatal-warnings` rerun returned exit 1 with 5213 analyzer issues，仍不作为 T27 完成态；`git diff --check` clean；changed-file strict scan only matched static denylist/placeholders and repo-local evidence paths, no credential values。
- [x] Latest validation after progress widget 证据：2026-06-26 focused `flutter test test/widgets/agent_trace_progress_box_test.dart test/widgets/agent_trace_recovery_box_test.dart` passed，4 tests passed；full `flutter test` passed，459 tests passed；Dev Harness APK build passed，SHA-256 `7dc51aba0ea83162a89c8996b08c07fb58f7a28361d6b564ce783a6df4acdc2b`；`flutter analyze --no-fatal-infos --no-fatal-warnings` rerun returned exit 1 with 5213 analyzer issues，仍不作为 T27 完成态；`git diff --check` clean；changed-file strict scan only matched static placeholders/test ids and repo-local evidence paths, no credential values。
- [x] V2 auth output redaction 证据：2026-06-26 `flutter test test/core/evidence/action_runner_test.dart` passed，37 tests passed；`ActionRunner` 已 redacts `github_cli_auth_login` 输出与 runtime metadata 中的 OAuth code、token-like strings、cookie/session 与 `.env.local` path，验证 `result.text`、evidence logs 和 metadata 不含原值。
- [x] Latest validation after auth redaction 证据：2026-06-26 full `flutter test` passed，460 tests passed；Dev Harness APK build passed，SHA-256 `212c9443f4321e1edb5cc43c1e1b6b8f7b1e562cdbb121054f53bc0d5c148af3`；`flutter analyze --no-fatal-infos --no-fatal-warnings` rerun returned exit 1 with 5213 analyzer issues，仍不作为 T27 完成态；`git diff --check` clean；changed-file strict scan only matched static denylist/placeholders, test-only fake token strings, and repo-local evidence paths, no real credential values。
- [x] V3 tool message redaction 证据：2026-06-26 `flutter test test/services/agent_loop_controller_test.dart` passed，29 tests passed；新增覆盖 GitHub repo list 和 Agent Mail/Google Drive/Lark Wiki 业务 task 的模型 tool message，确认 catalog `commandId` 进入 metadata、payload 不含 raw `command`/`shell`、stdout 中 email/phone 先 redacted 再传给模型。
- [x] Latest validation after V3 tool message redaction 证据：2026-06-26 full `flutter test` passed，460 tests passed；Dev Harness APK build passed，SHA-256 `212c9443f4321e1edb5cc43c1e1b6b8f7b1e562cdbb121054f53bc0d5c148af3`；`flutter analyze --no-fatal-infos --no-fatal-warnings` rerun returned exit 1 with 5213 analyzer issues，仍不作为 T27 完成态；`git diff --check` clean；changed-file strict scan only matched static denylist/placeholders, test-only fake token strings, and repo-local evidence paths, no real credential values。
- [x] Latest validation after local extension removal model 证据：2026-06-26 full `flutter test` passed，461 tests passed；Dev Harness APK build passed，SHA-256 `d8dddec86879166106064f39aaa16cd7cdeacd513b64c402694cb043fc3b9c2f`；`flutter analyze --no-fatal-infos --no-fatal-warnings` rerun returned exit 1 with 5213 analyzer issues，仍不作为 T27 完成态；`git diff --check` clean before final evidence update；changed-file strict scan only matched static denylist/placeholders and repo-local evidence paths, no real credential values。
- [x] Latest validation after local extension install preview model 证据：2026-06-26 full `flutter test` passed，462 tests passed；Dev Harness APK build passed，SHA-256 `abe0b77ff6bce810bfac9874015d506b7aec6755600cfb6d56b16334a932b3a9`；`flutter analyze --no-fatal-infos --no-fatal-warnings` rerun returned exit 1 with 5213 analyzer issues，仍不作为 T27 完成态；focused changed-file analyzer only reports existing info-level style lints in `CliHubCatalogService`；`git diff --check` clean before final evidence update。
- [x] Latest validation after extension install preview UI 证据：2026-06-26 full `flutter test` passed，462 tests passed；Dev Harness APK build passed，SHA-256 `7762e783133d88606c5038cc91a92b30683d0d31ce6449f750c4d902cf50b5d8`；`flutter analyze --no-fatal-infos --no-fatal-warnings` rerun returned exit 1 with 5214 analyzer issues，仍不作为 T27 完成态；`git diff --check` 和 changed-file strict secret scan 待本轮最终 hygiene。
- [x] Latest hygiene after extension install preview UI 证据：2026-06-26 `git diff --check` clean；changed-file strict secret scan 仅命中静态 denylist literal `oauth_code`、历史 `<tenant_access_token>` 占位符、以及 `risk-register` 文件名误命中，没有真实 token/cookie/.env/OAuth code/credential value。
- [x] Latest validation after local extension persistence store 证据：2026-06-26 full `flutter test` passed，464 tests passed；Dev Harness APK build passed，SHA-256 `366fd1893605db8574ab8c01eaeec1786af9020d21a83a76da6e81e19cf4d823`；`flutter analyze --no-fatal-infos --no-fatal-warnings` rerun returned exit 1 with 5215 analyzer issues，仍不作为 T27 完成态；changed-file `dart analyze` 只报 existing info-level style lints and exits 0；`git diff --check` clean；changed-file strict secret scan only matched static denylist/placeholders, `risk-register` filename false positives, and test-only `REDACTED_TEST_VALUE`, no real credential values。
- [x] Latest validation after local extension import/remove UI 证据：2026-06-26 full `flutter test` passed，465 tests passed；Dev Harness APK build passed，SHA-256 `4bef5385d85503b118beece23a3fd3c005921d85fd4a542fe805783ee15abdce`；`flutter analyze --no-fatal-infos --no-fatal-warnings` rerun returned exit 1 with 5215 analyzer issues，仍不作为 T27 完成态；changed-file `dart analyze` only reports info-level style lints and exits 0；`git diff --check` clean；changed-file strict secret scan only matched static denylist/placeholders, `risk-register` filename false positives, and test-only `REDACTED_TEST_VALUE`, no real credential values。
- [x] Latest validation after V5 safe remote fetch boundary 证据：2026-06-26 full `flutter test` passed，470 tests passed；Dev Harness APK build passed，SHA-256 `ba9922f1a3cf9c3763d01dd6403b8795b9f9e04152e2380bd40ac77790af92a6`；`flutter analyze --no-fatal-infos --no-fatal-warnings` rerun returned exit 1 with 5214 analyzer issues，仍不作为 T27 完成态；`git diff --check` clean；changed-file strict secret scan only matched static denylist literals, historical placeholder/evidence text, `risk-register` filename false positives, and test-only `REDACTED_TEST_VALUE`, no real credential values。
- [x] Latest validation after V5 SHA-256 integrity gate 证据：2026-06-26 full `flutter test` passed，472 tests passed；Dev Harness APK build passed，SHA-256 `5fee1b4f4c24afdfc48351c06dd2603737e12e9f54008b779ae4b08e4f12516e`；`flutter analyze --no-fatal-infos --no-fatal-warnings` rerun returned exit 1 with 5214 analyzer issues，仍不作为 T27 完成态；`dart format` clean；`git diff --check` clean；changed-file strict secret scan only matched static denylist literals, historical placeholder/evidence text, `risk-register` filename false positives, and test-only `REDACTED_TEST_VALUE`, no real credential values。
- [x] Latest validation after V5 Ed25519 verification 证据：2026-06-26 full `flutter test` passed，474 tests passed；Dev Harness APK build passed，SHA-256 `603e23cf2383d34781dfd903501ec219681eb88084b5d643ccf9e796e06b33a2`；`flutter analyze --no-fatal-infos --no-fatal-warnings` rerun returned exit 1 with 5210 analyzer issues，仍不作为 T27 完成态；changed-file `dart analyze` only reports 6 existing info-level style lints in `CliHubCatalogService`；`dart format` clean for Dart files；`git diff --check` clean；changed-file strict secret scan only matched static denylist literals, historical placeholder/evidence text, `risk-register` filename false positives, and test-only `REDACTED_TEST_VALUE`, no real credential values。
- [x] Latest validation after V5 trusted key lifecycle schema 证据：2026-06-26 focused `flutter test test/services/cli_hub_catalog_service_test.dart` passed，21 tests passed；changed-file `dart analyze mobile_agent/lib/services/cli_hub_catalog_service.dart mobile_agent/test/services/cli_hub_catalog_service_test.dart` exits 0 and only reports 6 existing info-level style lints in `CliHubCatalogService`。
- [x] Latest validation after V5 key lifecycle final pass 证据：2026-06-26 full `flutter test` passed，476 tests passed；Dev Harness APK build passed，SHA-256 `a4843df892117285cec7c95261f7d1dc39b1533b3d2ef1c436a70aacd4ae05f2`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5210 analyzer issues 返回 exit 1，未作为完成态；`git diff --check` clean；changed-file strict secret scan 仅命中静态 denylist literal、历史 evidence 文案、`risk-register` 文件名误命中和 test-only `REDACTED_TEST_VALUE`，没有真实凭据值。
- [x] Latest validation after verified remote catalog import UI 证据：2026-06-26 full `flutter test` passed，478 tests passed；Dev Harness APK build passed，SHA-256 `cda47c7d9eb3bf7d76c1701068ba535b0346493a5d0b26e46307890ef3a750b5`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5204 analyzer issues 返回 exit 1，未作为完成态；`git diff --check` clean；changed-file strict secret scan 仅命中静态 denylist literal、历史 evidence 文案、`risk-register` 文件名误命中和 test-only `REDACTED_TEST_VALUE`，没有真实凭据值。
- [x] Latest focused validation after trusted key import/store UI 证据：2026-06-26 `dart format` clean for changed Dart files；`flutter test test/services/cli_hub_catalog_service_test.dart test/widgets/extension_center_screen_test.dart` passed，35 tests passed。
- [x] Latest validation after trusted key import/store UI 证据：2026-06-26 full `flutter test` passed，481 tests passed；Dev Harness APK build passed，SHA-256 `a0fa61cd7f86390c3f4d33b36ca60bc02b8ba6fb129fbb22c7e9ad4034449fb9`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5204 analyzer issues 返回 exit 1，未作为完成态；`git diff --check` clean；changed-file strict secret scan 仅命中静态 denylist literal、历史 evidence 文案、`risk-register` 文件名误命中和 test-only `REDACTED_TEST_VALUE`，没有真实凭据值。
- [x] Latest focused validation after trusted key management/removal UI 证据：2026-06-26 `dart format` clean for changed Dart files；`flutter test test/widgets/extension_center_screen_test.dart` passed，13 tests passed。
- [x] Latest validation after trusted key management/removal UI 证据：2026-06-26 focused `flutter test test/services/cli_hub_catalog_service_test.dart test/widgets/extension_center_screen_test.dart` passed，36 tests passed；full `flutter test` passed，482 tests passed；Dev Harness APK build passed，SHA-256 `010956d0b5f87de3a1c52f1ce43fc8fa394c2ae1800d815b0792f2ea50ca7ce5`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5204 analyzer issues 返回 exit 1，未作为完成态；`git diff --check` clean；changed-file strict secret scan 仅命中历史 evidence 文案、`risk-register` 文件名误命中和 test-only `REDACTED_TEST_VALUE`，没有真实凭据值。
- [x] Latest validation after trusted key rotation deadline 证据：2026-06-26 full `flutter test` passed，483 tests passed；Dev Harness APK build passed，SHA-256 `10ac0e3117d0b20864f75d007ec3d562e7adc04292a4b763785bb972550d141c`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5205 analyzer issues 返回 exit 1，未作为完成态；`git diff --check` clean；changed-file strict secret scan 仅命中历史 evidence 文案、`risk-register` 文件名误命中和 test-only `REDACTED_TEST_VALUE`，没有真实凭据值。
- [x] V5 trusted key revoke UX 证据：2026-06-26 `CliHubTrustedKeyStore.revokeKey()` 已支持本地持久化 revoked trust root；远端 Ed25519 catalog 验签会拒绝 revoked key；扩展中心管理弹窗新增“撤销”动作，撤销后 key 仍保留 metadata、显示 `revoked`、public key 仍不曝光，并可再执行移除。Focused `flutter test test/services/cli_hub_catalog_service_test.dart test/widgets/extension_center_screen_test.dart` passed，37 tests passed。此项不代表完整远端撤销列表、key rotation chain 或 marketplace trust chain 完成。
- [x] Latest validation after trusted key revoke UX 证据：2026-06-26 full `flutter test` passed，483 tests passed；Dev Harness APK build passed，SHA-256 `cd26f51573f86fd37ea28b16706d9ef6212343ba4bff0d70d5bafbb0a522775f`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5203 analyzer issues 返回 exit 1，未作为完成态；`git diff --check` clean；changed-file strict secret scan 仅命中历史 evidence 文案、`risk-register` 文件名误命中和 test-only `REDACTED_TEST_VALUE`，没有真实凭据值。
- [x] Latest validation after analyzer quarantine 证据：2026-06-26 full `flutter test` passed，483 tests passed；`flutter analyze --no-fatal-infos --no-fatal-warnings` passed，exit 0，0 errors，2966 info，123 warnings；Dev Harness APK build passed，输出 `mobile_agent/build/app/outputs/flutter-apk/app-devharness-debug.apk`，SHA-256 `cd26f51573f86fd37ea28b16706d9ef6212343ba4bff0d70d5bafbb0a522775f`；`git diff --check` clean before evidence update；new analyzer quarantine file secret scan clean。Legacy quarantined files 仍需后续按模块迁移后再重新纳入 analyzer coverage。
- [x] Pure/Dev Harness APK split 证据：2026-06-26 `flutter build apk --debug --flavor pure --dart-define=MOBILECODE_BUILD_CHANNEL=pure --target lib/main.dart` passed，输出 `mobile_agent/build/app/outputs/flutter-apk/app-pure-debug.apk`，SHA-256 `c1d7c505fa4479fa2730227e5d0cbbfbdd7f9d7a3ae4442064694a00065d5c55`；Python ZIP inspection 确认 Pure APK 内无 `linux_sandbox`/rootfs `.tgz`/`alpine-minirootfs` assets，而 Dev Harness APK 内包含 `assets/linux_sandbox/alpine-minirootfs-aarch64-3.24.1.tgz` 与 `assets/linux_sandbox/alpine-minirootfs-x86_64-3.24.1.tgz`。
- [x] Analyzer quarantine reduction 证据：2026-06-26 module-by-module restored 21 files from quarantine into active analyzer coverage (`core` helpers, `CodeSnippet`, 9 widgets, and 9 services including logger/navigation/offline/performance/secure storage/sync queue). Quarantine count reduced from 83 to 62. `flutter analyze --no-fatal-infos --no-fatal-warnings` passed，exit 0；full `flutter test` passed，483 tests passed；Dev Harness APK build passed，SHA-256 `1c95f2ef43e5bccdc2e51f6c1ba34f5e9a0d073459ac9a911b61ca38732e46d8`；`git diff --check` clean. Remaining quarantined legacy files are still not marked complete and need focused migration before removing their excludes.
- [ ] 真机 Dev Harness CLI install/login/business QA 证据。

## Open Questions

- [ ] read-only task 是否默认可执行，还是每次都要用户确认。
- [ ] 是否为高频 CLI task 增加快捷 alias function。
- [ ] V6 Cloud Runner 是否拆独立 T28。

## Test Plan

- [x] `cd mobile_agent && flutter test test/services/tool_call_adapter_test.dart`
- [x] `cd mobile_agent && flutter test test/services/cli_hub_catalog_service_test.dart`
- [x] `cd mobile_agent && flutter test test/services/cli_harness_capability_service_test.dart`
- [x] `cd mobile_agent && flutter test test/services/agent_loop_controller_test.dart`
- [x] `cd mobile_agent && flutter test test/core/evidence/action_runner_test.dart`
- [x] `cd mobile_agent && flutter test test/services/linux_sandbox_provider_test.dart`
- [x] `cd mobile_agent && flutter test test/widgets/subscription_usage_hub_screen_test.dart`
- [x] `cd mobile_agent && flutter test`
- [x] `cd mobile_agent && flutter analyze --no-fatal-infos --no-fatal-warnings`
- [x] `cd mobile_agent && flutter build apk --debug --flavor pure --dart-define=MOBILECODE_BUILD_CHANNEL=pure --target lib/main.dart`
- [x] `cd mobile_agent && flutter build apk --debug --flavor devharness --dart-define=MOBILECODE_BUILD_CHANNEL=devHarness --dart-define=MOBILECODE_DEV_EXTENSIONS=true --dart-define=MOBILECODE_HARNESS_CLI=true --target lib/main.dart`
- [x] `cd mobile_agent && flutter test test/services/agent_loop_controller_test.dart test/core/evidence/action_runner_test.dart test/services/linux_sandbox_provider_test.dart`
- [x] `git diff --check`
- [x] changed-file secret scan。

## Assumptions

- [x] `cli_hub_task` 是统一入口。
- [x] Pure APK 不打包 CLI/rootfs。
- [x] Dev Harness 可以内置 Alpine rootfs。
- [x] CLI profile 仍然按需安装。
- [x] Termux 只作为 fallback。
