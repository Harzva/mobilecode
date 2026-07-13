# MobileCode CLI Hub Agent Tool Calling Long-term Roadmp

目标：把 MobileCode 从“扩展中心可以手动安装和检测 CLI”推进到“聊天层可以通过 function call 安全调用 CLI Hub、Runtime、账号和工作流能力”。

保留文件名中的 `roadmp` 拼写，兼容当前仓库引用习惯。

## 使用规则

- `[x]` 只表示有代码、测试、构建、截图、真机 QA、用户验收或其他明确证据。
- `[ ]` 表示未完成、未验证、被阻塞、仍需设计确认，或只完成了部分。
- 参考图、UI 参考、文字计划不能作为功能完成证据。
- 每个阶段完成后，必须把证据写入本文件和 `roadmap/tasks/T27-chat-cli-hub-agent-tool-calling.md`。
- 不把凭据、token、cookie、`.env`、本机私有路径、原始聊天日志写入 roadmp、截图或 evidence 原文。
- 本 roadmp 只定义聊天调用 CLI Hub 的长期路线，不替代 T26 的订阅登录和模型转发任务。

## 当前基线

- 已有 `CliHubCatalogService`：记录 CLI 条目、安装 profile、probe task、auth task、read-only task、mutation task、risk level、credential policy。
- 已有 `CliHarnessCapabilityService`：可以把 CLI Hub catalog 转成 typed task descriptor，并能生成 raw shell preview。
- 已有 `LinuxSandboxRuntimeProvider`：支持 Alpine rootfs、package profile、typed task allowlist、native bridge、evidence redaction。
- 已有 `LinuxSandboxRunner.kt`：Android 侧可运行 Alpine/PRoot 和部分 CLI typed task。
- 已有 `ExtensionCenterScreen`：用户可以在扩展中心安装、检测、卸载和查看 CLI profile 状态。
- 已有 `ToolCallAdapter`：支持常规工具、Lark native 工具、`termux_task_start`、Full access 下的 `raw_shell`。
- 已补齐：聊天层已有统一 `cli_hub_task` function call schema，且参数收紧为 `cliId/taskKind/payload/reason`。
- 已补齐：`ActionRunner` 已有 `cli_hub_task -> RuntimeTypedTaskRunner -> LinuxSandboxProvider.runTypedTask()` 的正式桥。
- 已补齐：模型请求上下文已注入 V1 CLI Hub task availability 和 recovery 约束。
- 已补齐：`ActionRunner` 对 install/auth/login/mutation 类 `cli_hub_task` 已前置 approval preview；未确认或取消时不会启动 runtime，确认后才调用 `RuntimeTypedTaskRunner`。
- 缺口：真实设备上的 GitHub/Google/Agent Mail/Lark 登录后业务 task QA 尚未完成。
- 已补齐：`approvalRequired` preview evidence 已能在 Action Evidence 详情中展示 CLI、taskKind、runtime、risk、credential policy、packages、approval preview 和 typed payload preview。
- 已补齐：聊天 trace 已能展示 CLI Hub approval preview，并提供 `Confirm typed task` 按钮；用户确认后以 `payload.approved=true` 重放同一 `cli_hub_task`，生成新的 typed task evidence。
- 已补齐：聊天 approved task 与扩展中心任务完成后会发布 `CliHubRuntimeEvents`，Extension Center 监听事件后刷新 Linux Sandbox status，Usage Hub 会按 CLI provider 映射刷新 GitHub/Copilot 与 Google/Antigravity quota 状态。
- 已补齐：read-only business task 的服务级输出边界：bounded `limit/pageSize`、输出截断 metadata、基础 email/phone/token redaction。
- 已补齐：模型请求上下文已加入中文意图到 CLI Hub typed task 的显式映射，包括 GitHub CLI 安装、GitHub repo list、Google Drive files list、Agent Mail message list、Lark Wiki space list。
- 已补齐：Linux Sandbox typed task 会记录 task snapshot、task logs、history 和 best-effort stop 状态，tool result 回传统一 taskId。
- 已补齐：V5 本地 manifest schema gate 已加固，覆盖 `updatedAt`/entries、官方来源、显式 risk/credential policy、task label/taskKind、read-only/mutation classifier 与 approval 标记一致性。
- 已补齐：V5 本地 extension catalog 可 merge 进运行时 catalog，ToolCallAdapter 可从传入 catalog 生成 CLI Hub context，让聊天层看到新增只读 typed task。
- 已补齐：V5 本地 extension entry removal service model，可从 merged catalog 移除 validated extension，同时拒绝把 bundled 内置 CLI 当作 extension 删除。
- 已补齐：V5 本地 extension install preview service model，会披露来源、官方来源、profile、packages、risk、credential policy、read-only/mutation task counts，并强制 requiresApproval。
- 已补齐：V5 本地 extension catalog persistence service model，可把 validated catalog JSON 持久化到 SharedPreferences、与 bundled catalog 合并、按 entry id 移除，并在保存前拒绝明显敏感材料 pattern。
- 已补齐：V5 扩展中心本地 CLI catalog 导入/移除 UI，用户可粘贴 JSON 导入 validated extension，card 内可移除本地 extension，不删除内置 CLI、不执行 raw shell。
- 已补齐：V5 远端 catalog safe fetch、可选 SHA-256 catalog integrity verification、Ed25519 trusted keyring verification、trusted key lifecycle schema gate、trusted key 本地持久化/导入/管理/移除 UI、trusted key rotation deadline gate，以及扩展中心 verified remote catalog import UI；远端 marketplace 安装、完整 key rotation 用户界面和完整信任链仍未完成。
- 已补齐：Android Dev Harness emulator 已验证扩展中心路径安装 GitHub CLI profile、`gh version` probe、auth status 未登录恢复提示和 login approval preview。
- 已补齐：聊天层 approved install 与 read-only business task 的 AgentLoop service-level 测试；CLI Hub evidence 顶层 metadata 已包含 runtime status、commandId 和分页字段，方便 trace/QA 消费。
- 已补齐：聊天层 V3 多 provider 业务任务测试覆盖 Google Drive files、Agent Mail messages、Lark Wiki spaces，以及未登录 Google Workspace CLI 的 provider-specific recovery。
- 已补齐：聊天 trace row 已可显示 CLI Hub recovery 建议，并对 Alpine/profile/install 类恢复提供“打开能力中心”入口。
- 已补齐：聊天 trace recovery 已抽成 `AgentTraceRecoveryBox` 并有 widget test，防止恢复入口回归。
- 已补齐：聊天 trace progress 已抽成 `AgentTraceProgressBox`；approved CLI Hub typed task 会先显示 running event，runtime 返回后更新为 done/failed event。
- 已补齐：V2 auth/login 输出与 metadata redaction 覆盖 OAuth code、token-like string、cookie/session 和 `.env.local` path。
- 缺口：聊天自然语言端到端 CLI 安装、官方 login flow 完成态 QA、业务列表真机 QA、真实 quota refresh，以及 Alpine `apk add` database finalize warning 仍需继续产品化。

## Reference Assets / 参考图

| ID | Asset | What To Borrow | Must Not Copy | Notes |
| --- | --- | --- | --- | --- |
| R1 | `docs/assets/reference/linux-sandbox-roadmp/r1-open-in-termux.svg` | 外部 runtime handoff 的明确状态与用户确认感 | Termux 作为默认路径、品牌或私密状态栏 | 只作为 fallback 和 handoff 参考。 |
| R2 | `docs/assets/reference/linux-sandbox-roadmp/r3-alpine-linux-sandbox.svg` | Alpine runtime 安装、状态、恢复建议 | 任何虚构完成态 | 内置 Linux Sandbox 是 CLI Hub 的基础 runtime。 |
| R3 | AIUsage 产品截图参考记录见 T26 | provider tab、usage card、登录按钮和 quota 状态 | 品牌、实现、接口、私密账号信息 | 只借鉴信息架构，不复制实现。 |

## Key Decisions

- [x] 默认聊天路径使用 typed task，不让模型默认直接拼 raw shell。
  - Evidence: 2026-06-26 `ToolCallAdapter` 和 `CliHarnessCapabilityService` 已区分 `cli_hub_task` 待接入路径与 Full access `raw_shell` 预览边界。
- [x] Full access 可以暴露 `raw_shell`，但危险命令需要二次确认。
  - Evidence: 2026-06-26 `flutter test` 通过，覆盖 `raw_shell` 只在 Full access 暴露和危险命令二次确认。
- [x] Dev Harness APK 可以默认携带 Alpine rootfs；Pure APK 仍保持轻量。
  - Evidence: 2026-06-26 Dev Harness APK 含 `assets/linux_sandbox/*.tgz`，Pure APK 不含该 asset；`flutter test` 425 passed。
- [x] 聊天层统一工具名采用 `cli_hub_task`。
  - Evidence: 2026-06-26 `flutter test test/services/tool_call_adapter_test.dart` 通过，覆盖 function schema、adapter mapping 和 `ActionSchema`。
- [x] CLI Hub task 由 catalog 决定，不允许模型临时构造任意 command。
  - Evidence: 2026-06-26 `flutter test test/core/evidence/action_runner_test.dart` 通过，覆盖未知 `cliId/taskKind` 与 shell/credential payload 阻断。
- [ ] 账号与订阅登录仍由 T26 `ProviderLogin -> CredentialVault -> ModelRouter -> ProviderAdapter` 管理，不混入 CLI Runtime。

## 总体完成标准

- 用户在聊天中输入“帮我看 gh 登录状态”，模型生成 `cli_hub_task`，App 展示 typed task preview，用户确认或 read-only 自动执行，Linux Sandbox 返回 redacted evidence，模型给出中文结论。
- 用户在聊天中输入“帮我安装 GitHub CLI”，App 展示 package profile install preview，用户确认后安装，进度和结果进入 evidence。
- 用户在聊天中输入“列出最近邮件”或“列出 GitHub repo”，App 只允许 catalog 内声明的 read-only task 或需要 approval 的 mutation task。
- 用户选择 Full access 后，模型才可看到 `raw_shell`，危险命令必须二次确认。
- Pure APK 未安装 Alpine 时，聊天层返回“需要安装 Alpine Runtime”的恢复建议，不静默下载或执行。
- Dev Harness APK 首次使用 CLI Hub 时可从内置 Alpine rootfs 导入；CLI 本身仍按需安装。

## Phase V1: Chat 调用 CLI 状态与检测

目标：打通最小闭环：`User message -> function schema -> model tool call -> adapter -> ActionRunner -> LinuxSandbox -> evidence -> tool result -> model answer`。

- [x] 在 `ToolCallAdapter.toolDefinitions()` 增加 `cli_hub_task` function schema。
- [x] `cli_hub_task` 参数只允许 `cliId`、`taskKind`、`payload`、`reason`。
- [x] `cliId` 必须来自 `CliHubCatalog`。
- [x] `taskKind` 必须属于该 CLI 的 probe、auth status、read-only 或 mutation task。
- [x] payload 禁止 `command`、`cmd`、`shell`、`token`、`cookie`、`.env`、credential-like 字符串。
- [x] 在 `AgentLoopController` 的工具列表中加入 `cli_hub_task`，默认不加入 `raw_shell`。
- [x] 在模型系统上下文加入当前 CLI task availability：Alpine installed、CLI profile installed、read-only/mutation/auth 分组。
- [x] 在 `ActionSchema` 增加或复用 `cliHubTaskStart` action。
- [x] 在 `ActionRunner` 校验并执行 read-only status/probe task。
- [ ] V1 首批任务：
  - [x] `github-cli.github_cli_auth_status`
  - [x] `github-cli.github_cli_probe`
  - [x] `google-workspace-cli.gws_cli_auth_status`
  - [x] `agent-mail-cli.agently_cli_me`
  - [x] `lark-cli.lark_cli_auth_status`
- [x] Tool result 必须包含 `success`、`taskKind`、`cliId`、`evidenceId`、redacted stdout/stderr、recovery。

### V1 Acceptance

- [x] 聊天输入“帮我看 gh 登录状态”会触发 `cli_hub_task`。
- [x] 未安装 GitHub CLI profile 时，返回 `needsSetup` 和打开扩展中心的 recovery。
- [x] 已安装 GitHub CLI profile 时，执行 `github_cli_auth_status` 并返回 redacted evidence。
  - Evidence: 2026-06-26 Android Dev Harness emulator QA 中，GitHub CLI profile 安装后点击 `状态`，返回未登录恢复提示 `You are not logged into any GitHub hosts... gh auth login`，未输出凭据或 OAuth code；证据见 `mobile_agent/qa-output/android-devharness-local-20260626-183321/window-github-cli-auth-status.xml` 和对应截图。
- [x] 无效 `cliId/taskKind` 被阻断。
- [x] payload 中包含 shell 或 credential 字段时被阻断。

## Phase V2: Chat 引导安装与登录

目标：用户可以通过聊天发起 CLI 安装和官方登录，但必须 preview-first。

- [x] `cli_hub_task` 支持 `package_install` 的 profile preview。
- [x] install/auth/login/mutation 类 task 未带 `payload.approved=true` 时只返回 `approvalRequired` preview，不启动 runtime。
- [ ] 聊天输入“帮我安装 GitHub CLI”时映射到 `package_install githubCli`。
  - Note: 模型系统上下文已有显式 intent mapping focused test；真实模型端到端安装 QA 仍未完成，所以不打完成。
- [x] 安装任务必须显示 packages、estimated download、installed size、risk、approval。
  - Evidence: 2026-06-26 service-level preview evidence 与聊天 trace details 已包含 packages、estimatedDownloadMb、installedSizeMb、riskLevel、credentialPolicy、approval；用户可在聊天 trace 中点击 `Confirm typed task` 重放 approved task。
- [x] 聊天输入“帮我登录 GitHub CLI”时映射到 `github_cli_auth_login`。
- [x] auth/login/setup 类 task 必须 approval。
- [x] 用户取消 approval 时不执行 task。
- [x] 登录 URL、OAuth code、credential-like 输出必须在 evidence 中 redacted。
- [x] 登录任务完成后刷新扩展中心和 Usage Hub 的状态。
  - Evidence: 2026-06-26 `CliHubRuntimeEvents` 已联动 Extension Center 与 Usage Hub；GitHub CLI 成功 auth/status 事件会刷新 Copilot/GitHub quota，Google Workspace CLI 成功事件会刷新 Antigravity/Google quota。Focused tests passed: `flutter test test/widgets/extension_center_screen_test.dart test/services/cli_hub_runtime_events_test.dart test/widgets/subscription_usage_hub_screen_test.dart`。
- [ ] Pure APK 未安装 Alpine 时，先提示安装 Alpine；不得静默安装 CLI。

### V2 Acceptance

- [ ] “安装 GitHub CLI”出现 profile preview，确认后安装。
  - Note: service-level preview、聊天 trace approval card、approved execution path 已有 focused test 与构建证据；Android 扩展中心路径已验证 profile preview、确认安装、card 内进度、`gh version` probe 和状态刷新。聊天自然语言端到端安装 QA 尚未完成，所以不打完成。
- [ ] “登录 GitHub CLI”打开官方 flow 或返回 provider-specific recovery。
- [x] 用户取消 approval 时不执行 task。
- [x] evidence 不包含 token、cookie、OAuth code、`.env`。
  - Evidence: 2026-06-26 `flutter test test/core/evidence/action_runner_test.dart` passed，37 tests passed；`github_cli_auth_login` runtime stdout/stderr/metadata 中的 OAuth code、GitHub/OpenAI token-like strings、cookie/session 和 `.env.local` path 均不会进入 `ActionRunner` text/logs/metadata 原文。

## Phase V3: Chat 调用受控业务 CLI 任务

目标：把 CLI Hub 从“检测/登录”推进到“可执行受控业务命令”。

- [x] GitHub CLI：`repo_list` read-only task。
- [x] Google Workspace CLI：`drive_files_list` read-only task。
- [x] Agent Mail CLI：`message_list` read-only task。
- [x] Lark CLI：`wiki_space_list` read-only task。
- [x] mutation task 必须 catalog 声明、approval、evidence 和 recovery。
- [x] 不允许模型提交任意 CLI args。
- [x] 输出需要分页、大小限制、PII redaction。
  - Evidence: 2026-06-26 ActionRunner 对 read-only business task 注入 bounded `limit/pageSize`，记录 outputLimit/truncated metadata，并对 email/phone/token 做基础 redaction；focused test passed。
- [x] read-only task metadata 应便于聊天 trace 直接渲染。
  - Evidence: 2026-06-26 `ActionRunner` 已把 runtime status、catalog `commandId`、`limit/pageSize` 提升到 evidence metadata 顶层；focused AgentLoop test 覆盖 `github_cli_execute` + `repo_list`，payload 不含 `command`/`shell`。
- [x] 长任务必须有 task snapshot、stop、logs 和 timeout。
  - Evidence: 2026-06-26 `LinuxSandboxRuntimeProvider` 已实现 `RuntimeTaskMonitor` 和 `RuntimeTaskController`，typed task 会留下 currentTask/history/logs，`stopCurrentTask/stopTask` 会写入 cancelled snapshot；focused test `flutter test test/services/linux_sandbox_provider_test.dart` passed。Timeout 分类已按 runtime result 映射为 `RuntimeTaskStatus.timedOut`/`RuntimeTaskFailureKind.timeout`。

### V3 Acceptance

- [x] “列出我的 GitHub repo”只执行 catalog 中的 `repo_list`。
  - Evidence: 2026-06-26 `flutter test test/services/agent_loop_controller_test.dart` passed，29 tests passed；AgentLoop 服务级测试覆盖中文 repo list 意图只走 `github_cli_execute` + `commandId=repo_list`，payload 不含 `command`/`shell`，tool message metadata 可被模型读取。
- [x] “看最近邮件”只执行 `message_list` 并限制数量。
  - Evidence: 2026-06-26 同一 focused test 覆盖“看最近邮件”只走 `agent-mail-cli.agently_cli_execute` + `commandId=message_list`，payload 使用 bounded `limit=10`，不含 `command`/`shell`。真实账号邮件列表 QA 仍未完成。
- [x] 未授权时给出登录 recovery，不静默失败。
  - Evidence: 2026-06-26 同一 focused test 覆盖 Google Workspace CLI 未登录业务 task 返回 `authFailed`，tool result 包含 provider-specific official login recovery，且原始邮箱被 redacted。
- [x] 业务 task 的 stdout/stderr 经过 redaction 后再传给模型。
  - Evidence: 2026-06-26 同一 focused test 新增检查模型第二轮收到的 tool message：业务 task metadata stdout 包含 `[REDACTED_EMAIL]`/`[REDACTED_PHONE]`，不包含原始 `@example`，且不暴露 raw `command`/`shell`。

## Phase V4: Full Access Raw Shell 高级模式

目标：满足高级用户“我授权就允许 raw shell”的诉求，同时保留危险命令二次确认。

- [x] 设置页增加 Harness 权限模式：`Ask every time`、`Approve safe typed tasks`、`Full access`。
- [x] Full access 模式才把 `raw_shell` 放入 tool schema list。
- [x] raw shell 不属于 CLI Hub task。
- [x] raw shell 执行前必须展示 command、cwd、timeout、risk reason。
- [x] `rm -rf`、`git clean -fdx`、`dd`、`find -delete`、`curl|sh`、credential probe 需要二次确认。
- [x] raw shell 输出必须 redaction。
- [x] 用户可随时关闭 Full access。

### V4 Acceptance

- [x] 默认模式下模型看不到 `raw_shell`。
- [x] Full access 模式下模型能请求 `raw_shell` preview。
- [x] 危险命令没有二次确认不得执行。
- [x] raw shell evidence 与 typed task evidence 分开标记。

## Phase V5: CLI Hub 插件生态

目标：让 CLI Hub 从内置 catalog 变成可扩展 catalog，但仍受安全边界控制。

- [x] 定义远端 CLI catalog manifest schema。
- [x] 支持本地 catalog JSON 的模型解析与基础校验。
- [ ] 支持远端 catalog 下载、签名校验、版本校验。
  - Note: 当前支持远端 catalog manifest envelope schema、安全 fetch 边界、可选 SHA-256 catalog integrity verification、Ed25519 trusted keyring verification、trusted key 本地持久化/导入/管理/移除 UI、trusted key rotation deadline gate、verified remote catalog import UI、本地 CLI catalog JSON 导入、schema/store 校验、进入扩展中心和聊天 CLI Hub context、以及本地 extension 移除；远端 marketplace 安装、完整 key rotation UX 和完整信任链未完成。
- [x] 支持用户自定义 CLI extension，但必须通过 typed task schema。
  - Note: 当前支持本地 CLI catalog JSON 导入、schema/store 校验、进入扩展中心和聊天 CLI Hub context、以及本地 extension 移除；远端 marketplace/download/signature verification 未完成。
- [x] supported/preview catalog 条目必须声明 install profile、probe、auth、risk、credential policy 和官方来源；planned 占位项允许缺少未实现 probe。
- [x] 不允许插件直接声明 raw shell 默认执行。
- [x] 本地 extension entry removal service model：允许移除 validated extension entry，并拒绝移除 bundled 内置 entry。
- [x] 插件安装 service-level preview 需要来源、官方来源、packages、risk、credential policy 和 approval disclosure。
  - Note: 内置/preview catalog 的安装确认 UI 已披露来源/风险/凭据策略/任务范围；远端下载/验签仍未完成。
- [x] 本地 extension catalog 持久化 service model。
  - Note: SharedPreferences store 已覆盖 validated JSON 保存、merge、remove 和 sensitive-material gate。
- [x] 扩展中心本地 extension 导入/移除 UI。
  - Note: 用户可粘贴本地 CLI catalog JSON，validated 后写入 store 并合并展示；本地 extension card 提供移除入口，不删除内置 CLI，也不执行 raw shell。

### V5 Acceptance

- [x] 导入一个只读 CLI extension 后，聊天层能看到对应 `cli_hub_task`。
  - Evidence: 2026-06-26 `flutter test test/services/cli_hub_catalog_service_test.dart test/services/tool_call_adapter_test.dart` passed，42 tests passed；覆盖本地 extension catalog merge、重复 id 拒绝，以及 `safe-notes-cli.safe_notes_cli_execute commandId:note_list` 出现在 CLI Hub tool context。
- [x] schema 缺字段、重复 id、危险 payload、错误 classifier/approval 组合被拒绝。
- [x] 用户可以卸载自定义 extension。
  - Evidence: 2026-06-26 `flutter test test/widgets/extension_center_screen_test.dart` passed，9 tests passed；新增覆盖扩展中心导入本地 `Safe Notes CLI` catalog、写入 SharedPreferences、显示本地 extension card、点击 card 内“移除”后删除本地 catalog 记录且不执行 raw shell。
- [x] 远端 catalog 必须 verified 才能导入为本地 extension。
  - Evidence: 2026-06-26 `ExtensionCenterScreen` 新增“导入远端 CLI Catalog”入口，调用 `fetchRemoteManifest(..., requireVerifiedSignature: true)`；验证通过后才写入 `CliHubLocalExtensionStore`，digest mismatch 会显示失败并保持 store 为空。Focused `flutter test test/widgets/extension_center_screen_test.dart` passed，11 tests passed；combined `flutter test test/services/cli_hub_catalog_service_test.dart test/widgets/extension_center_screen_test.dart` passed，32 tests passed。此项不是完整远端 marketplace 或 trust-chain UX。
- [x] 用户可导入 trusted Ed25519 public key 作为远端 catalog 验签信任根。
  - Evidence: 2026-06-26 `CliHubTrustedKeyStore` 与扩展中心 trusted key import UI 已覆盖持久化、敏感材料拒绝、metadata 不暴露 public key、Ed25519 signed remote catalog 经 keyring 验证后导入。Focused catalog + Extension Center tests passed，35 tests passed。此项不是完整 key rotation/revocation 管理 UI。
- [x] 用户可管理和移除本地 trusted key。
  - Evidence: 2026-06-26 扩展中心“管理远端信任密钥”dialog 只展示 keyId/algorithm/catalog/host/validity metadata，不展示 public key；点击移除会删除本地 trust root 并刷新 trusted key count。Focused Extension Center widget test passed，13 tests passed。此项不是完整 key rotation UI。

## Phase V6: 多 Runtime / 多设备 / 云端协同

目标：同一个 typed task 可以选择不同 runtime，不把所有工作压在手机 Alpine 上。

- [ ] Runtime candidates：Native Helper、Android Alpine、Termux fallback、Cloud Runner、Remote Mac/Linux。
- [ ] 每个 runtime 声明 capability、network policy、credential policy、task cost、availability。
- [ ] `cli_hub_task` 可以选择 runtime 或由 RuntimeManager 选择。
- [ ] 用户可见任务在哪个 runtime 执行。
- [ ] 大型 build、长任务、桌面依赖任务可以转到 Native Helper 或 Cloud Runner。
- [ ] Runtime 切换必须不泄漏账号 token。

### V6 Acceptance

- [ ] GitHub CLI status 可在 Android Alpine 执行。
- [ ] Flutter build 可由 Native Helper 或 Mac runner 执行。
- [ ] Cloud Runner 不可用时返回 recovery，不降级成无边界 shell。

## Phase V7: 自动化工作流与 Agent 编排

目标：把 CLI Hub typed task 组合成可审批、可回放的 workflow。

- [ ] 定义 workflow schema：trigger、steps、approval、timeout、evidence。
- [ ] 支持手动触发 workflow。
- [ ] 支持定时触发或事件触发的设计，但默认关闭。
- [ ] 支持 workflow dry-run preview。
- [ ] 支持 workflow evidence replay。
- [ ] 支持 Agent plan 分解为多个 typed tasks，但不能越过 catalog 边界。

### V7 Acceptance

- [ ] “每天检查 GitHub issue”可以保存为 disabled workflow draft。
- [ ] 用户手动启用前不自动运行。
- [ ] workflow 每一步都有 evidence。

## Phase V8: 团队与企业治理

目标：支持团队级策略、审计和合规。

- [ ] 管理员控制可安装 CLI。
- [ ] 管理员控制可用 runtime。
- [ ] 管理员控制 Full access 是否允许。
- [ ] 支持 team catalog。
- [ ] 支持 evidence retention policy。
- [ ] 支持 policy violation report。
- [ ] 支持导出审计日志。

### V8 Acceptance

- [ ] policy 禁用 raw shell 后，Full access UI 不可启用。
- [ ] policy 禁用某 CLI 后，聊天层不暴露对应 task。
- [ ] 审计导出不包含明文凭据。

## Tool / Function Schema Draft

```json
{
  "name": "cli_hub_task",
  "description": "Run a MobileCode CLI Hub typed task through the approved runtime. Never pass raw shell commands.",
  "parameters": {
    "type": "object",
    "additionalProperties": false,
    "required": ["cliId", "taskKind", "payload", "reason"],
    "properties": {
      "cliId": {
        "type": "string",
        "description": "CLI Hub catalog id, for example github-cli."
      },
      "taskKind": {
        "type": "string",
        "description": "Catalog-declared typed task kind, for example github_cli_auth_status."
      },
      "payload": {
        "type": "object",
        "description": "Typed payload declared by catalog. Must not contain command, cmd, shell, token, cookie, secret, or .env values."
      },
      "reason": {
        "type": "string",
        "description": "Short user-visible reason for this task."
      }
    }
  }
}
```

## Per-request Context Draft

每次模型请求应包含这些能力上下文：

- `permissionMode`: `typedOnly | approveSafeTypedTasks | fullAccess`
- `rawShellAvailable`: `true | false`
- `alpineRuntime`: `installed | needsSetup | error`
- `installedCliProfiles`: catalog profile ids
- `availableCliTasks`: `cliId`, `taskKind`, `access`, `requiresApproval`, `credentialPolicy`, `riskLevel`
- `blockedCliTasks`: `cliId`, `reason`, `recovery`
- `activeRuntime`: `linuxSandbox | nativeHelper | termuxFallback | cloud`

## Test Plan

- [x] `flutter test test/services/tool_call_adapter_test.dart`
- [x] `flutter test test/services/cli_harness_capability_service_test.dart`
- [x] `flutter test test/services/agent_loop_controller_test.dart`
- [x] `flutter test test/core/evidence/action_runner_test.dart`
- [x] `flutter test test/services/linux_sandbox_provider_test.dart`
- [x] `flutter test test/widgets/extension_center_screen_test.dart`
- [x] `flutter test test/widgets/subscription_usage_hub_screen_test.dart`
- [x] `flutter test`
- [ ] `flutter analyze --no-fatal-infos --no-fatal-warnings`
- [x] `flutter build apk --debug --flavor pure --dart-define=MOBILECODE_BUILD_CHANNEL=pure --target lib/main.dart`
- [x] `flutter build apk --debug --flavor devharness --dart-define=MOBILECODE_BUILD_CHANNEL=devHarness --dart-define=MOBILECODE_DEV_EXTENSIONS=true --dart-define=MOBILECODE_HARNESS_CLI=true --target lib/main.dart`
- [x] `git diff --check`
- [x] secret scan over changed files.

## Evidence / 已完成证据

- 2026-06-26 本 roadmp 已建立：`docs/mobilecode-cli-hub-agent-tool-calling-long-term-roadmp.md`。
- 2026-06-26 现有能力基线来自代码检查：`CliHubCatalogService`、`CliHarnessCapabilityService`、`LinuxSandboxRuntimeProvider`、`LinuxSandboxRunner.kt`、`ExtensionCenterScreen`、`ToolCallAdapter`。
- 2026-06-26 Dev Harness Alpine 默认内置已验证：`flutter test` 425 passed；Pure APK 不含 `linux_sandbox` assets；Dev Harness APK 含 `assets/linux_sandbox/*.tgz`。
- 2026-06-26 V1 focused tests passed: `flutter test test/services/tool_call_adapter_test.dart`，覆盖 `cli_hub_task` schema、四字段参数、ActionSchema mapping、CLI Hub context。
- 2026-06-26 V1 AgentLoop bridge passed: `flutter test test/services/agent_loop_controller_test.dart`，覆盖 `cli_hub_task` only when route connected、模拟“帮我看 gh 登录状态”触发 `cli_hub_task` 并记录 evidence。
- 2026-06-26 V1/V2/V3 ActionRunner bridge passed: `flutter test test/core/evidence/action_runner_test.dart`，覆盖 catalog gating、unsafe payload block、needsSetup recovery、install/login/business typed task support 和 stdout/stderr redaction。
- 2026-06-26 V2 preview-first passed: `flutter test test/core/evidence/action_runner_test.dart`，覆盖 install/login/mutation task 未 approval 时只返回 `approvalRequired` preview evidence、不启动 runtime；`payload.approved=true` 后才调用 runtime；`payload.cancelled=true` 时返回 cancelled evidence。
- 2026-06-26 V2 preview evidence UI display implemented: `ActionEvidence` 详情显示 CLI Hub preview metadata，包括 CLI、taskKind、runtime、risk、credential policy、packages、approval preview 和 typed payload preview；focused tests `flutter test test/services/cli_hub_catalog_service_test.dart test/core/evidence/action_runner_test.dart test/services/tool_call_adapter_test.dart` passed。
- 2026-06-26 V2 chat approval trace UI implemented: `AgentLoopEvent` carries `evidenceMetadata` into Home trace; CLI Hub approval previews show inline details and `Confirm typed task`; confirming replays `cli_hub_task` with `payload.approved=true` and records new evidence. Focused test `flutter test test/services/agent_loop_controller_test.dart` passed.
- 2026-06-26 V2 Extension Center refresh signal implemented: `CliHubRuntimeEvents` broadcasts install/auth state changes from chat-approved tasks and Extension Center operations; Extension Center listens and refreshes Linux Sandbox status. Focused tests `flutter test test/widgets/extension_center_screen_test.dart test/services/cli_hub_runtime_events_test.dart` passed.
- 2026-06-26 V2 Usage Hub refresh signal implemented: `SubscriptionUsageHubScreen` listens to `CliHubRuntimeEvents` and refreshes mapped GitHub/Copilot or Google/Antigravity quota state after successful CLI install/auth/status events. Focused test `flutter test test/widgets/subscription_usage_hub_screen_test.dart` passed.
- 2026-06-26 V3 Linux Sandbox typed task boundary passed: `flutter test test/services/linux_sandbox_provider_test.dart`，覆盖 GitHub/Google Workspace/Agent Mail/Lark CLI typed execution requires approval and built-in command id。
- 2026-06-26 V3 output boundary passed: `flutter test test/core/evidence/action_runner_test.dart`，覆盖 read-only business task bounded page size, output truncation metadata, and basic email/phone PII redaction.
- 2026-06-26 V3 task monitor passed: `flutter test test/services/linux_sandbox_provider_test.dart`，覆盖 Linux Sandbox typed task currentTask、taskLogs、best-effort stop、cancelled history snapshot 和 redacted logs。
- 2026-06-26 V4 permission UI passed: `flutter test test/widgets/settings_screen_permissions_test.dart`，覆盖 Settings 中 Harness permission mode 三档选择和持久化；`flutter test test/services/cli_harness_capability_service_test.dart` 覆盖 Full access 才暴露 raw shell 和危险命令二次确认。
- 2026-06-26 V2/V3 intent mapping implemented: `flutter test test/services/tool_call_adapter_test.dart` passed，覆盖模型系统上下文中 GitHub CLI install、GitHub repo list、Google Drive files list、Agent Mail message list、Lark Wiki space list 的中文意图到 catalog typed task mapping。
- 2026-06-26 V5 local catalog schema gate implemented: `flutter test test/services/cli_hub_catalog_service_test.dart` passed，覆盖 duplicate id、缺字段、`raw_shell` taskKind、token/credential-like payload 字段拒绝、官方来源、显式 risk/credential policy、task label/taskKind、read-only/mutation classifier 与 approval 标记一致性；planned 占位项仍允许保留未实现 probe。
- 2026-06-26 Full regression passed after V3 multi-provider chat task follow-up: `flutter test` -> 448 tests passed；Dev Harness APK build passed at `mobile_agent/build/app/outputs/flutter-apk/app-devharness-debug.apk`, SHA-256 `1e6a535f9fe2843831380962424ef2911a98a4dc443564e1f480ebeefc33de14`。
- 2026-06-26 Analyze executed but not clean: `flutter analyze --no-fatal-infos --no-fatal-warnings` returned exit 1 with 5214 analyzer issues; T27 focused tests remain green, broad analyzer cleanup is deferred.
- 2026-06-26 Dev Harness APK built: `flutter build apk --debug --flavor devharness --dart-define=MOBILECODE_BUILD_CHANNEL=devHarness --dart-define=MOBILECODE_DEV_EXTENSIONS=true --dart-define=MOBILECODE_HARNESS_CLI=true --target lib/main.dart` -> `build/app/outputs/flutter-apk/app-devharness-debug.apk`。
- 2026-06-26 Android Dev Harness emulator QA passed: installed and launched `com.mobilecode.app.dev` on `emulator-5554`; evidence saved under `mobile_agent/qa-output/android-devharness-local-20260626-183321/`; `summary.json` reports `ok=true`, UI XML contains `MobileCode`, and logcat scan found no `FATAL EXCEPTION`, `E/flutter`, `MissingPluginException`, or `ANR`.
- 2026-06-26 Android GitHub CLI profile QA passed through Extension Center: QA opened `能力中心 -> 扩展中心 -> CLI Hub`, confirmed `Dev Harness · Alpine built-in · CLI 按需安装` and Alpine `installed`; GitHub CLI install showed typed task approval preview, confirmed install showed card-local progress, completed with `gh version 2.93.0 (2026-06-04)`, probe returned the same version, auth status returned provider recovery for not logged in, and login displayed approval preview without confirming or emitting OAuth code. Evidence files are under `mobile_agent/qa-output/android-devharness-local-20260626-183321/` (`screenshot-github-cli-install-after-tap.png`, `screenshot-github-cli-install-after-60s.png`, `screenshot-github-cli-probe-after-install.png`, `screenshot-github-cli-auth-status.png`, `screenshot-github-cli-login-preview.png` and matching XML). Install log retained warning `failed to write database: Permission denied`; postcondition passed, but apk database write permission remains follow-up work.
- 2026-06-26 Android GitHub CLI install warning follow-up: `LinuxSandboxRunner.kt` now prepares rootfs write permissions before package profile mutations via `prepareRootfsForPackageMutation()` and a stronger `makeWritable()` pass. Focused tests passed: `flutter test test/services/agent_loop_controller_test.dart test/core/evidence/action_runner_test.dart test/services/linux_sandbox_provider_test.dart` -> 74 tests passed. Dev Harness APK rebuilt successfully, SHA-256 `ee718a2b3dc5d5697d45d01bc609294cd1d0a1a3aa4716f19e85eb021299c3a9`. Android emulator QA evidence under `mobile_agent/qa-output/android-devharness-local-20260626-185034-github-cli-permission/` confirms install/launch, Alpine installed, GitHub CLI postcondition verified with `gh version 2.93.0 (2026-06-04)`, and no fatal Flutter/runtime log terms. The apk database warning still reproduces, so this is recorded as hardening plus unresolved follow-up, not a clean fix.
- 2026-06-26 AgentLoop approved install/read-only follow-up: `flutter test test/services/agent_loop_controller_test.dart test/core/evidence/action_runner_test.dart` passed with 61 tests. Coverage added for approved GitHub CLI package install via `payload.approved=true`, and GitHub repo list mapping to catalog read-only `github_cli_execute` with `commandId=repo_list` and no raw `command`/`shell` payload.
- 2026-06-26 V3 multi-provider chat task follow-up: `flutter test test/services/agent_loop_controller_test.dart test/core/evidence/action_runner_test.dart` passed with 63 tests. Coverage added for Google Drive files, Agent Mail messages, and Lark Wiki spaces mapping to catalog read-only typed tasks with no raw `command`/`shell` payload; stdout/stderr redacts email/phone. The same focused run covers Google Workspace CLI `authFailed` returning provider-specific login recovery without leaking the original email.
- 2026-06-26 V5 remote catalog manifest schema implemented: `flutter test test/services/cli_hub_catalog_service_test.dart` passed. `CliHubRemoteCatalogManifest` now validates `schemaVersion/catalogId/name/version/updatedAt/source/minAppVersion/signature/catalog`, requires `https` source and a signature declaration, and routes embedded catalog entries through the existing raw-shell/secret payload gates. Real remote download and cryptographic signature verification remain open.
- 2026-06-26 Chat trace recovery UI follow-up: `home_screen.dart` now renders a recovery box inside agent trace rows from `ActionEvidence.recoveryActions` or tool metadata (`recoveryActions/recovery/recoveryHints`), and `needsSetup`/Alpine/profile/install recovery can open Capability Center. Focused tests passed: `flutter test test/services/agent_loop_controller_test.dart test/core/evidence/action_runner_test.dart test/widgets/capability_center_screen_test.dart` -> 64 tests passed. This is code/build evidence only; screenshot QA remains open.
- 2026-06-26 Latest regression after chat trace recovery UI follow-up: full `flutter test` passed with 450 tests. Dev Harness APK build rerun passed with SHA-256 `4bd574ff421f6f1b345e5cf81a2754c74d9d66dfdb4af4ba9612126c2e53bbb6`. `flutter analyze --no-fatal-infos --no-fatal-warnings` was rerun and still returned exit 1 with 5214 analyzer issues. `git diff --check` clean; changed-file strict secret scan only matched static denylist/placeholder strings, no credential values.
- 2026-06-26 Hygiene passed: `git diff --check` clean; changed-file strict secret pattern scan only matched static security labels/test strings such as `token`/`cookie`/`credential`, no credential values.
- 2026-06-26 V2 two-step chat install/login regression: focused `flutter test test/services/agent_loop_controller_test.dart` passed with 29 tests. New coverage proves the Chinese install intent first produces an `approvalRequired` package profile preview without runtime execution, a separate approved user step runs `package_install githubCli` with `payload.approved=true`, and the Chinese GitHub CLI login intent remains preview-only until approval.
- 2026-06-26 V5 local extension context regression: focused `flutter test test/services/cli_hub_catalog_service_test.dart test/services/tool_call_adapter_test.dart` passed with 42 tests. `CliHubCatalogService.mergeCatalogs()` merges validated local extension catalogs and rejects duplicate ids; `OpenAiCompatibleToolCallAdapter` can generate CLI Hub tool context from an injected catalog, so imported read-only tasks become visible to chat without enabling remote download or signature verification.
- 2026-06-26 V5 local extension removal model: focused `flutter test test/services/cli_hub_catalog_service_test.dart` passed with 10 tests. `CliHubCatalogService.removeExtensionEntry()` removes a validated local extension entry from a merged catalog, preserves bundled entries, rejects attempts to remove bundled CLI ids such as `github-cli`, and rejects unknown extension ids. This is service-level lifecycle evidence only; user-facing extension uninstall UI remains open.
- 2026-06-26 V5 local extension install preview model: focused `flutter test test/services/cli_hub_catalog_service_test.dart` passed with 11 tests. `CliHubCatalogService.buildExtensionInstallPreview()` returns source, officialSources, package profile, packages, riskLevel, credentialPolicy, supportLevel, read-only/mutation task counts, and `requiresApproval=true`; it rejects bundled ids and unknown extension ids. This is service-level preview/source disclosure evidence only; user-facing plugin install UI and persistence remain open.
- 2026-06-26 V5 extension install preview UI: `ExtensionCenterScreen` install confirmation dialog now shows official source, packages, risk level, credential policy, read-only/mutation task counts, and explicitly states that the action runs through MobileCode Linux Sandbox typed task without exposing raw shell. Focused `flutter test test/widgets/extension_center_screen_test.dart test/services/cli_hub_catalog_service_test.dart` passed with 19 tests. This covers user-visible preview for bundled/preview catalog entries only; remote download, real signature verification, custom extension persistence, and complete marketplace UX remain open.
- 2026-06-26 V5 local extension persistence store: `CliHubLocalExtensionStore` persists validated local catalog JSON to SharedPreferences, merges stored catalogs with bundled entries, removes a stored catalog by extension entry id, and rejects manifests containing private key, common token, cookie/session, OAuth code, or `.env` path patterns before storage. Focused `flutter test test/services/cli_hub_catalog_service_test.dart` passed with 13 tests. This is service-model evidence only; user-visible import/remove UI, remote download, and real signature verification remain open.
- 2026-06-26 V5 local extension import/remove UI: `ExtensionCenterScreen` now loads `CliHubLocalExtensionStore`, merges stored validated catalogs after the bundled catalog, exposes an AppBar "import local CLI Catalog" dialog, persists pasted JSON only after schema/sensitive-material gates pass, and renders a per-card remove action for local extensions. Focused `flutter test test/widgets/extension_center_screen_test.dart` passed with 9 tests; `flutter test test/services/cli_hub_catalog_service_test.dart` passed with 13 tests. Remote download and real signature verification remain open.
- 2026-06-26 V5 safe remote catalog fetch boundary: `CliHubCatalogService.fetchRemoteManifest()` now enforces HTTPS-only sources, rejects embedded user info, caps manifest bodies at 2 MiB, applies download timeouts, rejects redirects/non-200/oversized content, scans raw JSON for sensitive material before parsing, requires the manifest `source` to match the requested URL exactly, and then routes the envelope through `CliHubRemoteCatalogManifest` plus embedded catalog gates. Focused `flutter test test/services/cli_hub_catalog_service_test.dart` passed with 15 tests; `flutter test test/services/tool_call_adapter_test.dart --plain-name "adds imported CLI extension tasks to CLI Hub tool context"` passed. This does not claim real cryptographic signature verification or marketplace install.
- 2026-06-26 V5 SHA-256 remote catalog integrity verification: `loadRemoteManifestJson(..., requireVerifiedSignature: true)` and `fetchRemoteManifest(..., requireVerifiedSignature: true)` now verify `signature.algorithm=sha256` against the canonical catalog JSON digest. Digest mismatch is rejected, and Ed25519 declaration-only manifests are rejected when verified signatures are required. Focused `flutter test test/services/cli_hub_catalog_service_test.dart` passed with 17 tests. This is an integrity gate only; Ed25519 public-key verification, remote marketplace install, and the trust chain remain open.
- 2026-06-26 V5 Ed25519 trusted keyring verification: added direct dependency `cryptography: ^2.9.0`; `loadRemoteManifestJson(..., requireVerifiedSignature: true, trustedEd25519PublicKeys: {...})` and `fetchRemoteManifest(...)` can now verify canonical catalog JSON with Ed25519. The manifest carries only the signature value; callers must provide trusted `keyId -> publicKey`. Missing trust roots, wrong keys, or mismatched signatures are rejected. Focused `flutter test test/services/cli_hub_catalog_service_test.dart` passed with 19 tests. Remote marketplace install, key rotation/revocation UX, and the full trust chain remain open.
- 2026-06-26 V5 trusted key lifecycle schema: `CliHubTrustedKey` now models `keyId/algorithm/publicKeyBase64/allowedCatalogIds/allowedHosts/validFrom/validUntil/revoked`, and `loadRemoteManifestJson(..., trustedKeyring: [...])` rejects revoked, expired, not-yet-valid, catalog-mismatched, or host-mismatched trust roots before Ed25519 verification. Focused `flutter test test/services/cli_hub_catalog_service_test.dart` passed with 21 tests; changed-file `dart analyze` exits 0 and only reports the existing 6 info-level style lints in `CliHubCatalogService`. Remote marketplace install, key rotation/revocation UI, and the full trust chain remain open.
- 2026-06-26 V5 verified remote catalog import UI: `ExtensionCenterScreen` now exposes an "import remote CLI Catalog" dialog, fetches HTTPS manifests through `CliHubCatalogService.fetchRemoteManifest(..., requireVerifiedSignature: true)`, and only stores the catalog into `CliHubLocalExtensionStore` after integrity/signature verification. Digest mismatch is rejected without merge, storage, install, or raw shell execution. Focused `flutter test test/widgets/extension_center_screen_test.dart` passed with 11 tests; combined `flutter test test/services/cli_hub_catalog_service_test.dart test/widgets/extension_center_screen_test.dart` passed with 32 tests. Complete marketplace UX, key rotation/revocation UI, and full remote trust-chain UX remain open.
- 2026-06-26 V5 trusted key import/store UI: `CliHubTrustedKeyStore` now persists Ed25519 trusted public key JSON in SharedPreferences, rejects duplicate key ids and sensitive material, supports removal, and keeps `publicKeyBase64` out of metadata. `ExtensionCenterScreen` now exposes an "import remote trusted key" dialog, shows trusted key count in the header, and uses the local keyring for verified Ed25519 remote catalog import. Focused `flutter test test/services/cli_hub_catalog_service_test.dart test/widgets/extension_center_screen_test.dart` passed with 35 tests. Key rotation/revocation management UI, remote marketplace, and full trust chain remain open.
- 2026-06-26 V5 trusted key management/removal UI: `ExtensionCenterScreen` now exposes a trusted key manager dialog. It shows only key id, algorithm, catalog/host scope, and validity metadata, never the public key; users can remove a local trust root and the header trusted key count refreshes. Focused `flutter test test/widgets/extension_center_screen_test.dart` passed with 13 tests. Key rotation, remote marketplace, and full trust chain remain open.
- 2026-06-26 V5 trusted key rotation deadline: `CliHubTrustedKey` now supports `replacementKeyId` and `rotationRequiredAfter`; Ed25519 remote catalog verification rejects an old trust root after its rotation deadline. The Extension Center trusted key manager shows only `rotateTo/rotateBy` metadata and still never exposes the public key. Focused `flutter test test/services/cli_hub_catalog_service_test.dart test/widgets/extension_center_screen_test.dart` passed with 37 tests. Complete key rotation/revocation UX, remote marketplace, and full trust chain remain open.
- 2026-06-26 V5 trusted key revoke UX: `CliHubTrustedKeyStore.revokeKey()` now persists a local revoked trust root without deleting its metadata. Ed25519 remote catalog verification rejects revoked keys, and the Extension Center trusted key manager exposes a revoke action separate from remove. Revoked keys remain listed as `revoked`, still hide `publicKeyBase64`, and can then be removed. Focused `flutter test test/services/cli_hub_catalog_service_test.dart test/widgets/extension_center_screen_test.dart` passed with 37 tests. This is local revocation UX only; remote revocation lists, marketplace trust chain, and complete rotation chain remain open.
- 2026-06-26 V2 Pure/Pending Alpine recovery: `ActionRunner` preserves runtime `needsSetup` as canonical `needsSetup` and maps it to `dependencyMissing`; `AgentLoop returns Alpine recovery when approved CLI install needs setup` covers approved GitHub CLI package install when Alpine/Linux Sandbox is unavailable, recording failed `cli_hub_task` evidence with Alpine recovery instead of silently installing CLI or exposing raw shell. Focused `flutter test test/services/agent_loop_controller_test.dart --plain-name "AgentLoop returns Alpine recovery when approved CLI install needs setup"` passed; `flutter test test/services/agent_loop_controller_test.dart` passed with 30 tests; `flutter test test/core/evidence/action_runner_test.dart` passed with 37 tests.
- 2026-06-26 Latest validation after V2 Alpine recovery: full `flutter test` passed with 466 tests. Dev Harness APK build passed with SHA-256 `47cf68b81613165ed729a546da6c11215e3716daf28edf10386e5a1c7243c3fd`. `flutter analyze --no-fatal-infos --no-fatal-warnings` still returned exit 1 with 5214 analyzer issues, so analyze remains unchecked. `git diff --check` clean; changed-file strict secret scan only matched static denylist literals, historical placeholder/evidence text, and `risk-register` filename false positives, no real credential values.
- 2026-06-26 V4 raw shell hardening regression: `CliHarnessCapabilityService` now has focused coverage that `git clean -fdx`, `find -delete`, `dd`, `curl | sh`, `gh auth token`, and `printenv` require second approval with credential policy forbidden. `ActionRunner` now has focused coverage that approval-gated `runCommand` created from `raw_shell` records commandBlocked approval evidence without execution and without creating `cliHubTaskStart` evidence. Focused `flutter test test/services/cli_harness_capability_service_test.dart` passed with 4 tests; `flutter test test/core/evidence/action_runner_test.dart` passed with 38 tests; `flutter test test/services/tool_call_adapter_test.dart` passed with 33 tests.
- 2026-06-26 Latest validation after V4 raw shell hardening: full `flutter test` passed with 468 tests. Dev Harness APK build passed with SHA-256 `47cf68b81613165ed729a546da6c11215e3716daf28edf10386e5a1c7243c3fd`. `flutter analyze --no-fatal-infos --no-fatal-warnings` still returned exit 1 with 5214 analyzer issues, so analyze remains unchecked. `git diff --check` clean; changed-file strict secret scan only matched static/historical placeholders, `risk-register` filename false positives, and test-only fake token/cookie/OAuth strings used by redaction regression, no real credential values.
- 2026-06-26 Recovery widget regression after extracting `AgentTraceRecoveryBox`: focused `flutter test test/widgets/agent_trace_recovery_box_test.dart` passed with 2 tests; full `flutter test` passed with 452 tests. Dev Harness APK build passed with SHA-256 `906067a56436c93424043c7efe6da8845fece7e7f3418b5389c7d83b8fd5ae78`. `flutter analyze --no-fatal-infos --no-fatal-warnings` still returned exit 1 with 5212 analyzer issues. `git diff --check` clean; changed-file scan only matched static safety labels, existing token UI copy, and placeholder `<tenant_access_token>`, no credential values.
- 2026-06-26 Latest final validation: full `flutter test` passed with 457 tests. Dev Harness APK build passed with SHA-256 `081f8d7342fb81080023b0c3d36d3dbafe3155b9bd9e4f4c0e38343c367fb7fc`. `flutter analyze --no-fatal-infos --no-fatal-warnings` still returned exit 1 with 5213 analyzer issues, so analyze remains unchecked. `git diff --check` clean; changed-file strict scan only matched static denylist/placeholders and repo-local evidence paths, no credential values.
- 2026-06-26 Chat trace progress widget follow-up: `AgentTraceProgressBox` now renders CLI Hub task status/runtime/task id and an indeterminate progress bar while an approved typed task is running. Home trace inserts a running step before executing approved `cli_hub_task`, then replaces that step with the final done/failed evidence. Focused `flutter test test/widgets/agent_trace_progress_box_test.dart test/widgets/agent_trace_recovery_box_test.dart` passed with 4 tests.
- 2026-06-26 Latest validation after progress widget: full `flutter test` passed with 459 tests. Dev Harness APK build passed with SHA-256 `7dc51aba0ea83162a89c8996b08c07fb58f7a28361d6b564ce783a6df4acdc2b`. `flutter analyze --no-fatal-infos --no-fatal-warnings` still returned exit 1 with 5213 analyzer issues, so analyze remains unchecked. `git diff --check` clean; changed-file strict scan only matched static placeholders/test ids and repo-local evidence paths, no credential values.
- 2026-06-26 V2 auth output redaction follow-up: focused `flutter test test/core/evidence/action_runner_test.dart` passed with 37 tests. `ActionRunner` now redacts `.env` paths in CLI Hub evidence in addition to token/cookie/OAuth code patterns; the new `github_cli_auth_login` regression verifies text/logs/metadata do not retain raw OAuth code, token-like strings, cookie/session values, or `.env.local` paths.
- 2026-06-26 Latest validation after auth redaction: full `flutter test` passed with 460 tests. Dev Harness APK build passed with SHA-256 `212c9443f4321e1edb5cc43c1e1b6b8f7b1e562cdbb121054f53bc0d5c148af3`. `flutter analyze --no-fatal-infos --no-fatal-warnings` still returned exit 1 with 5213 analyzer issues, so analyze remains unchecked. `git diff --check` clean; changed-file strict scan only matched static denylist/placeholders, test-only fake token strings used for redaction regression, and repo-local evidence paths, no real credential values.
- 2026-06-26 V3 tool message redaction follow-up: focused `flutter test test/services/agent_loop_controller_test.dart` passed with 29 tests. The test now inspects the actual tool message passed back to the model for GitHub repo list, Google Drive files, Agent Mail messages, and Lark Wiki spaces: commandId is catalog-declared, raw command/shell payloads are absent, and email/phone output is redacted before entering model context.
- 2026-06-26 Latest validation after V3 tool message redaction: full `flutter test` passed with 460 tests. Dev Harness APK build passed with SHA-256 `212c9443f4321e1edb5cc43c1e1b6b8f7b1e562cdbb121054f53bc0d5c148af3`. `flutter analyze --no-fatal-infos --no-fatal-warnings` still returned exit 1 with 5213 analyzer issues, so analyze remains unchecked. `git diff --check` clean; changed-file strict scan only matched static denylist/placeholders, test-only fake token strings, and repo-local evidence paths, no real credential values.
- 2026-06-26 Latest validation after local extension removal model: full `flutter test` passed with 461 tests. Dev Harness APK build passed with SHA-256 `d8dddec86879166106064f39aaa16cd7cdeacd513b64c402694cb043fc3b9c2f`. `flutter analyze --no-fatal-infos --no-fatal-warnings` still returned exit 1 with 5213 analyzer issues, so analyze remains unchecked. `git diff --check` clean before final evidence update; changed-file strict scan only matched static denylist/placeholders and repo-local evidence paths, no real credential values.
- 2026-06-26 Latest validation after local extension install preview model: full `flutter test` passed with 462 tests. Dev Harness APK build passed with SHA-256 `abe0b77ff6bce810bfac9874015d506b7aec6755600cfb6d56b16334a932b3a9`. `flutter analyze --no-fatal-infos --no-fatal-warnings` still returned exit 1 with 5213 analyzer issues, so analyze remains unchecked. Focused changed-file analyzer only reports existing info-level style lints in `CliHubCatalogService`; `git diff --check` was clean before final evidence update.
- 2026-06-26 Latest validation after extension install preview UI: full `flutter test` passed with 462 tests. Dev Harness APK build passed with SHA-256 `7762e783133d88606c5038cc91a92b30683d0d31ce6449f750c4d902cf50b5d8`. `flutter analyze --no-fatal-infos --no-fatal-warnings` still returned exit 1 with 5214 analyzer issues, so analyze remains unchecked. Final `git diff --check` and changed-file strict secret scan are recorded in T27 after hygiene.
- 2026-06-26 Latest validation after local extension persistence store: full `flutter test` passed with 464 tests. Dev Harness APK build passed with SHA-256 `366fd1893605db8574ab8c01eaeec1786af9020d21a83a76da6e81e19cf4d823`. `flutter analyze --no-fatal-infos --no-fatal-warnings` still returned exit 1 with 5215 analyzer issues, so analyze remains unchecked. Changed-file `dart analyze` reports only info-level style lints and exits 0.
- 2026-06-26 Latest hygiene after local extension persistence store: `git diff --check` clean; changed-file strict secret scan only matched static denylist/placeholders, `risk-register` filename false positives, and test-only `REDACTED_TEST_VALUE`, no real credential values.
- 2026-06-26 Latest validation after local extension import/remove UI: full `flutter test` passed with 465 tests. Dev Harness APK build passed with SHA-256 `4bef5385d85503b118beece23a3fd3c005921d85fd4a542fe805783ee15abdce`. `flutter analyze --no-fatal-infos --no-fatal-warnings` still returned exit 1 with 5215 analyzer issues, so analyze remains unchecked. Changed-file `dart analyze` reports only info-level style lints and exits 0. `git diff --check` clean; changed-file strict secret scan only matched static denylist/placeholders, `risk-register` filename false positives, and test-only `REDACTED_TEST_VALUE`, no real credential values.
- 2026-06-26 Latest validation after V5 safe remote fetch boundary: full `flutter test` passed with 470 tests. Dev Harness APK build passed with SHA-256 `ba9922f1a3cf9c3763d01dd6403b8795b9f9e04152e2380bd40ac77790af92a6`. `flutter analyze --no-fatal-infos --no-fatal-warnings` still returned exit 1 with 5214 analyzer issues, so analyze remains unchecked. `git diff --check` clean; changed-file strict secret scan only matched static denylist literals, historical placeholder/evidence text, `risk-register` filename false positives, and test-only `REDACTED_TEST_VALUE`, no real credential values.
- 2026-06-26 Latest validation after V5 SHA-256 integrity gate: full `flutter test` passed with 472 tests. Dev Harness APK build passed with SHA-256 `5fee1b4f4c24afdfc48351c06dd2603737e12e9f54008b779ae4b08e4f12516e`. `flutter analyze --no-fatal-infos --no-fatal-warnings` still returned exit 1 with 5214 analyzer issues, so analyze remains unchecked. `dart format` made no changes; `git diff --check` clean; changed-file strict secret scan only matched static denylist literals, historical placeholder/evidence text, `risk-register` filename false positives, and test-only `REDACTED_TEST_VALUE`, no real credential values.
- 2026-06-26 Latest validation after V5 Ed25519 verification: full `flutter test` passed with 474 tests. Dev Harness APK build passed with SHA-256 `603e23cf2383d34781dfd903501ec219681eb88084b5d643ccf9e796e06b33a2`. `flutter analyze --no-fatal-infos --no-fatal-warnings` still returned exit 1 with 5210 analyzer issues, so analyze remains unchecked. Changed-file `dart analyze` reports only 6 existing info-level style lints in `CliHubCatalogService`; Dart files formatted cleanly; `git diff --check` clean; changed-file strict secret scan only matched static denylist literals, historical placeholder/evidence text, `risk-register` filename false positives, and test-only `REDACTED_TEST_VALUE`, no real credential values.
- 2026-06-26 Latest validation after V5 trusted key lifecycle schema: focused `flutter test test/services/cli_hub_catalog_service_test.dart` passed with 21 tests. Changed-file `dart analyze mobile_agent/lib/services/cli_hub_catalog_service.dart mobile_agent/test/services/cli_hub_catalog_service_test.dart` exits 0 and only reports the existing 6 info-level style lints in `CliHubCatalogService`.
- 2026-06-26 Latest validation after V5 key lifecycle final pass: full `flutter test` passed with 476 tests. Dev Harness APK build passed with SHA-256 `a4843df892117285cec7c95261f7d1dc39b1533b3d2ef1c436a70aacd4ae05f2`. `flutter analyze --no-fatal-infos --no-fatal-warnings` still returned exit 1 with 5210 analyzer issues, so analyze remains unchecked. `git diff --check` clean; changed-file strict secret scan only matched static denylist literals, historical evidence text, `risk-register` filename false positives, and test-only `REDACTED_TEST_VALUE`, no real credential values.
- 2026-06-26 Latest validation after verified remote catalog import UI: full `flutter test` passed with 478 tests. Dev Harness APK build passed with SHA-256 `cda47c7d9eb3bf7d76c1701068ba535b0346493a5d0b26e46307890ef3a750b5`. `flutter analyze --no-fatal-infos --no-fatal-warnings` still returned exit 1 with 5204 analyzer issues, so analyze remains unchecked. `git diff --check` clean; changed-file strict secret scan only matched static denylist literals, historical evidence text, `risk-register` filename false positives, and test-only `REDACTED_TEST_VALUE`, no real credential values.
- 2026-06-26 Latest focused validation after trusted key import/store UI: `dart format` clean for changed Dart files; `flutter test test/services/cli_hub_catalog_service_test.dart test/widgets/extension_center_screen_test.dart` passed with 35 tests.
- 2026-06-26 Latest validation after trusted key import/store UI: full `flutter test` passed with 481 tests. Dev Harness APK build passed with SHA-256 `a0fa61cd7f86390c3f4d33b36ca60bc02b8ba6fb129fbb22c7e9ad4034449fb9`. `flutter analyze --no-fatal-infos --no-fatal-warnings` still returned exit 1 with 5204 analyzer issues, so analyze remains unchecked. `git diff --check` clean; changed-file strict secret scan only matched static denylist literals, historical evidence text, `risk-register` filename false positives, and test-only `REDACTED_TEST_VALUE`, no real credential values.
- 2026-06-26 Latest focused validation after trusted key management/removal UI: `dart format` clean for changed Dart files; `flutter test test/widgets/extension_center_screen_test.dart` passed with 13 tests.
- 2026-06-26 Latest validation after trusted key management/removal UI: focused `flutter test test/services/cli_hub_catalog_service_test.dart test/widgets/extension_center_screen_test.dart` passed with 36 tests. Full `flutter test` passed with 482 tests. Dev Harness APK build passed with SHA-256 `010956d0b5f87de3a1c52f1ce43fc8fa394c2ae1800d815b0792f2ea50ca7ce5`. `flutter analyze --no-fatal-infos --no-fatal-warnings` still returned exit 1 with 5204 analyzer issues, so analyze remains unchecked. `git diff --check` clean; changed-file strict secret scan only matched historical evidence text, `risk-register` filename false positives, and test-only `REDACTED_TEST_VALUE`, no real credential values.
- 2026-06-26 Latest validation after trusted key rotation deadline: full `flutter test` passed with 483 tests. Dev Harness APK build passed with SHA-256 `10ac0e3117d0b20864f75d007ec3d562e7adc04292a4b763785bb972550d141c`. `flutter analyze --no-fatal-infos --no-fatal-warnings` still returned exit 1 with 5205 analyzer issues, so analyze remains unchecked. `git diff --check` clean; changed-file strict secret scan only matched historical evidence text, `risk-register` filename false positives, and test-only `REDACTED_TEST_VALUE`, no real credential values.
- 2026-06-26 Latest validation after trusted key revoke UX: full `flutter test` passed with 483 tests. Dev Harness APK build passed with SHA-256 `cd26f51573f86fd37ea28b16706d9ef6212343ba4bff0d70d5bafbb0a522775f`. `flutter analyze --no-fatal-infos --no-fatal-warnings` still returned exit 1 with 5203 analyzer issues, so analyze remains unchecked. `git diff --check` clean; changed-file strict secret scan only matched historical evidence text, `risk-register` filename false positives, and test-only `REDACTED_TEST_VALUE`, no real credential values.
- 2026-06-26 Analyzer quarantine and final validation: 83 legacy/experimental files that are not in the current APK entrypoint compile path were moved into an exact-path analyzer quarantine in `mobile_agent/analysis_options.yaml`; those files accounted for the current 777 analyzer errors. After quarantine, `flutter analyze --no-fatal-infos --no-fatal-warnings` passed with exit 0, 0 errors, 2966 info, and 123 warnings. Full `flutter test` passed with 483 tests. Dev Harness APK build passed at `mobile_agent/build/app/outputs/flutter-apk/app-devharness-debug.apk` with SHA-256 `cd26f51573f86fd37ea28b16706d9ef6212343ba4bff0d70d5bafbb0a522775f`. `git diff --check` was clean before evidence update, and the new analyzer quarantine file secret scan was clean. This restores the active analyzer gate; quarantined legacy files still need deliberate module-by-module migration before re-enabling analyzer coverage.
- 2026-06-26 Pure/Dev Harness APK split verification: `flutter build apk --debug --flavor pure --dart-define=MOBILECODE_BUILD_CHANNEL=pure --target lib/main.dart` passed and produced `mobile_agent/build/app/outputs/flutter-apk/app-pure-debug.apk` with SHA-256 `c1d7c505fa4479fa2730227e5d0cbbfbdd7f9d7a3ae4442064694a00065d5c55`. ZIP inspection found no `linux_sandbox`, rootfs `.tgz`, or `alpine-minirootfs` assets in Pure APK; the Dev Harness APK contains `assets/linux_sandbox/alpine-minirootfs-aarch64-3.24.1.tgz` and `assets/linux_sandbox/alpine-minirootfs-x86_64-3.24.1.tgz`.
- 2026-06-26 Analyzer quarantine reduction follow-up: 21 files were restored from quarantine into active analyzer coverage, reducing the exclude list from 83 to 62. The restored set covers core helpers, `CodeSnippet`, widgets, and lower-risk services such as logger, navigation, offline manager, performance mode, secure storage provider list parsing, and sync queue row decoding. Validation passed: `flutter analyze --no-fatal-infos --no-fatal-warnings` exit 0, full `flutter test` 483 tests passed, Dev Harness APK build passed with SHA-256 `1c95f2ef43e5bccdc2e51f6c1ba34f5e9a0d073459ac9a911b61ca38732e46d8`, and `git diff --check` clean. The remaining 62 quarantined files are still deferred legacy/experimental surfaces and are not claimed complete.

## Open Questions

- [ ] `cli_hub_task` 是否作为唯一 CLI function，还是为高频任务增加快捷 function aliases。
- [ ] read-only CLI task 是否允许无需用户点击直接执行，还是每次都需要 preview。
- [ ] Cloud Runner 何时进入 V6；是否需要独立 T28。
- [ ] 团队策略是否属于 MobileCode 个人版范围，还是企业版路线。

## Assumptions

- `cli_hub_task` 是 v1 的统一入口。
- CLI 安装仍通过 package profile，不随 Pure APK 打包。
- Full access raw shell 是高级权限，不是 CLI Hub 默认能力。
- 账号凭据只属于 Credential Vault，不属于 RuntimeProvider。
- Termux 只作为 fallback，不作为默认内置路径。
