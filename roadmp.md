# MobileCode Roadmap Index

这个文件是 MobileCode 长期路线图的总索引。详细执行内容已经拆到 `roadmap/tasks/` 下，每个子任务一个文件，便于 Agent 单次只读取当前任务上下文，减少长文扫描和误改范围。

保留文件名 `roadmp.md` 是为了兼容当前仓库里已经建立的引用习惯。后续如果要改成 `roadmap.md`，应单独开一个小任务处理重命名和链接迁移。

## 为什么这样拆

- 更省上下文：执行某个任务时，只需要读本索引、对应任务文件、任务文件列出的少量源文件。
- 边界更清楚：每个任务都有 `Can edit`、`Do not edit`、`Out of scope`。
- 更利于接力：任务文件自带 handoff prompt，适合 Codex、Claude Code 或本地 `cc*` 执行通道使用。
- 更容易验收：每个任务都有独立验收标准和验证命令，不会把大路线图当成完成证明。
- 更安全：涉及 Git、Lark、GitHub、push、commit、token、Helper 的任务都明确 stop line。

## 本次任务完成记录

- [x] 复查本地角色库规则，按 `project-inventory + Codex current model` 处理项目组织任务。
- [x] 复查并更新 MobileCode `AGENTS.md`：Mac 本地编译是完整支持的一等路径，应优先用于本地验证；GitHub Actions 保留为远端 CI/发布复核。
- [x] 将原长文 `roadmp.md` 改造成轻量总索引。
- [x] 新建 `roadmap/tasks/` 子任务目录。
- [x] 将 MobileAgent 可借鉴内容拆成独立任务文件，并在本索引建立链接。
- [x] 为每个任务补充目标、边界、输入、输出、验收和 handoff。
- [x] 完成 T00-T23 收尾验收，闭环报告见 `docs/mobilecode-t00-t23-closure.md`。
- [x] 2026-06-25 新增 T25/T26 未完成任务定义：无障碍与后台权限产品化、Subscription Login 与 Usage Hub。
- [x] 2026-06-25 T25 代码实现已落地，Helper service 正式接入 Android app，Termux daemon 作为外部强 runtime 排在 EmbeddedLite 之前；Mac 本地 focused tests、targeted analyze、debug APK build、emulator Helper smoke 已通过；远端 CI workflow 已补入 T25 focused tests 和 tokenized Helper smoke，远端 emulator smoke 和真机 QA 证据保留为 release evidence。
- [x] 2026-06-25 按 Mac 优先策略本地收口 T25，并完成 T26 Usage Hub 本地 Phase 1：设置页 `订阅账户` 入口、四类 provider、mock quota、secure storage 凭据边界、provider-specific recovery、logout redaction、focused tests、targeted analyze、debug APK build、emulator install/launch。
- [x] 2026-06-25 EmbeddedLite Runtime 本地受控版落地：只支持 project preflight 与 WebView preview metadata，不暴露 shell/git/node/python/flutter/androidBuild，不实现 apt/pkg 生态；重型执行仍优先 Helper、External Termux 或 Mac 本地编译。
- [x] 2026-06-25 T26 Phase 2 小步推进：Copilot/GitHub manual token mode 接入 GitHub `/user` 验证，验证成功后才写 secure storage；验证失败不保存凭据。T26 仍保持未完成，等待官方 browser/OAuth 登录和真实 quota refresh。
- [x] 2026-06-25 T26 Copilot/GitHub auth surface 已统一：Usage Hub 复用现有 GitHub OAuth/PAT 登录与 `GitHubDeepService` secure session，不在 Usage Hub vault 中重复保存 token；OpenAI/Google/Claude 官方账号登录继续按 provider 官方能力边界推进。
- [x] 2026-06-25 T26 model forwarding chain 已设计并落地首段：新增 `ProviderLogin -> CredentialVault -> ModelRouter -> ProviderAdapter` 服务边界；登录不依赖 Termux 或任何外部 runtime，正式转发路径应以内置 Android Helper APK / provider-native SDK adapter 为主。GitHub/Copilot 通过 `copilot_chat` helper task 接官方 Copilot SDK bridge；未配置 bridge 时返回 `dependencyMissing`，不降级为 mock 转发。Google/OpenAI/Claude 保持按官方能力逐个接入。
- [x] 2026-06-26 新增 T27 长期任务定义：Chat CLI Hub Agent Tool Calling，覆盖 `cli_hub_task`、ActionRunner 桥、Linux Sandbox typed task、Full access raw shell、多 runtime、workflow 和团队治理路线。
- [x] 2026-06-26 T27 V1 core bridge 与 V4 permission gating 已推进：`cli_hub_task` schema、ToolCallAdapter mapping、AgentLoop tool exposure、ActionRunner catalog gating、Linux Sandbox typed task bridge、Settings/Agent 面板 Harness permission mode 均有 focused tests；`flutter test` 436 passed，Dev Harness APK 构建通过并输出 `mobile_agent/build/app/outputs/flutter-apk/app-devharness-debug.apk`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因全仓 5201 个既有 analyzer issues 返回 exit 1；真机 Dev Harness CLI login/business QA、交互式聊天 approval card 和完整安装登录状态刷新仍未完成，T27 总任务保持 `[ ]`。
- [x] 2026-06-26 T27 V2 service-level preview-first 与 evidence 展示已补齐：ActionRunner 对 install/auth/login/mutation 类 `cli_hub_task` 未 approval 时只返回 `approvalRequired` preview evidence，不启动 runtime；`payload.approved=true` 后才调用 Linux Sandbox typed task route；`payload.cancelled=true` 时返回 cancelled evidence；`ActionEvidence` 详情可显示 CLI、taskKind、runtime、risk、credential policy、packages、approval preview 和 typed payload preview；focused tests 通过。真实 GitHub CLI 安装/登录 QA 和 Extension Center/Usage Hub 状态刷新仍未完成。
- [x] 2026-06-26 T27 V2 chat approval trace UI 已补齐：`AgentLoopEvent.evidenceMetadata` 会把 CLI Hub approval preview metadata 带到聊天 trace；Home trace 显示 `Confirm typed task`，用户确认后以 `payload.approved=true` 重放 `cli_hub_task` 并生成新的 evidence；`flutter test` 437 passed，Dev Harness APK 构建通过并输出 `mobile_agent/build/app/outputs/flutter-apk/app-devharness-debug.apk`。真实 Android CLI profile 安装、官方登录 flow、业务 CLI QA 和状态刷新仍未完成。
- [x] 2026-06-26 T27 V2/V3 状态刷新与输出边界继续推进：新增 `CliHubRuntimeEvents`，聊天 approved task 与扩展中心任务完成后可通知 Extension Center 刷新 Linux Sandbox status；ActionRunner 对 read-only business task 增加 bounded `limit/pageSize`、output truncation metadata、email/phone/token redaction；focused tests 与 `flutter test` 440 passed，Dev Harness APK 重新构建通过，SHA-256 `83a609adb8de18ddeea672d38f3bf4b41c4ef5725dc51867824d9cce3d839312`。Usage Hub 状态联动、真实 Android CLI 登录/业务 QA 仍未完成。
- [x] 2026-06-26 T27 V2/V3 再收口：Usage Hub 已监听 `CliHubRuntimeEvents` 并刷新 GitHub/Copilot、Google/Antigravity quota 状态；Linux Sandbox typed task 已接 `RuntimeTaskMonitor`/`RuntimeTaskController`，支持 currentTask、taskLogs、history snapshot、best-effort stop 和 timeout/status 映射；focused tests 与 `flutter test` 443 passed；Dev Harness APK 重新构建通过，SHA-256 `c6be6720f098b8057a01e7b0e5466c1d7238ccc8291e07728027d232c33ae7e7`。真实 Android CLI 登录/业务 QA 与真实 quota refresh 仍未完成。
- [x] 2026-06-26 T27 V5 schema 基础已推进：本地 CLI Hub catalog manifest 解析/校验增加 duplicate id、缺字段、`raw_shell` taskKind、token/credential-like payload 字段拒绝；planned 占位项允许缺少未实现 probe 但仍受安全 gate 约束；远端下载、签名、自定义 extension 安装/卸载未完成。
- [x] 2026-06-26 T27 聊天意图与 V5 schema gate 继续加固：ToolCallAdapter 系统上下文已加入 GitHub CLI 安装和 GitHub/Google Drive/Agent Mail/Lark Wiki 业务 task 的中文 intent mapping；CLI Hub catalog schema 继续校验 `updatedAt`/entries、官方来源、显式 risk/credential policy、task label/taskKind、read-only/mutation classifier 与 approval 标记一致性；focused tests 与 `flutter test` 444 passed；Dev Harness APK SHA-256 `9307548f12be49e1a3eb6a889eb9d9d2631240cc044dda186c5c56251235dd45`。真实 Android CLI 安装、官方登录、业务列表 QA 仍未完成。
- [x] 2026-06-26 T27 Android Dev Harness emulator QA 已补证：`app-devharness-debug.apk` 安装并启动 `com.mobilecode.app.dev` 于 `emulator-5554`，证据目录 `mobile_agent/qa-output/android-devharness-local-20260626-183321/`，`summary.json` 为 `ok=true`；这只证明 APK 安装启动和 UI 可见，不代表 CLI profile 真机安装、官方登录或业务 task 已完成。
- [x] 2026-06-26 T27 Android GitHub CLI profile QA 继续补证：Dev Harness emulator 进入 `能力中心 -> 扩展中心 -> CLI Hub`，确认 Alpine `installed`；GitHub CLI 安装 preview、确认执行、card 内进度、`gh version 2.93.0` probe、auth status 未登录恢复提示、login approval preview 均有截图/XML 证据，位于 `mobile_agent/qa-output/android-devharness-local-20260626-183321/`。这证明扩展中心路径的 GitHub CLI 增量安装与检测可用；聊天自然语言端到端安装、官方登录完成、业务列表 QA 仍未完成。安装日志保留 `failed to write database: Permission denied` warning，需后续修复 apk database 写权限。
- [x] 2026-06-26 T27 Android GitHub CLI install warning follow-up：`LinuxSandboxRunner.kt` 已补 package mutation 前 rootfs 写权限准备；focused tests `flutter test test/services/agent_loop_controller_test.dart test/core/evidence/action_runner_test.dart test/services/linux_sandbox_provider_test.dart` 通过，74 tests passed；Dev Harness APK 重新构建通过，SHA-256 `ee718a2b3dc5d5697d45d01bc609294cd1d0a1a3aa4716f19e85eb021299c3a9`；新 Android QA 证据位于 `mobile_agent/qa-output/android-devharness-local-20260626-185034-github-cli-permission/`。这轮确认 GitHub CLI 仍可安装并 postcondition verified，但 `failed to write database: Permission denied` warning 仍可复现，不能标为 clean fix。
- [x] 2026-06-26 T27 AgentLoop approved install/read-only follow-up：`cli_hub_task` approved GitHub CLI install 已验证会以 `payload.approved=true` 进入 runtime 并记录 success evidence；“列出我的 GitHub repo”已验证映射到 catalog read-only `github_cli_execute` + `commandId=repo_list`，payload 不含 raw `command`/`shell`；`ActionRunner` 顶层 evidence metadata 增加 runtime status、commandId、limit/pageSize。Focused tests 61 passed，full `flutter test` 446 passed；Dev Harness APK 构建通过，SHA-256 `1e6a535f9fe2843831380962424ef2911a98a4dc443564e1f480ebeefc33de14`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5214 个 analyzer issues 返回 exit 1。真实官方登录完成、真机业务列表 QA、真实 quota refresh 和 apk database warning 仍未完成。
- [x] 2026-06-26 T27 V3 multi-provider chat task follow-up：聊天层已验证 Google Drive files、Agent Mail messages、Lark Wiki spaces 三类业务意图均映射到 catalog read-only typed task，payload 不含 raw `command`/`shell`，stdout/stderr email/phone redaction 生效；Google Workspace CLI 未登录业务 task 会返回 provider-specific official login recovery。Focused tests 63 passed，full `flutter test` 448 passed；Dev Harness APK build rerun passed，SHA-256 `1e6a535f9fe2843831380962424ef2911a98a4dc443564e1f480ebeefc33de14`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5214 个 analyzer issues 返回 exit 1。真实官方登录完成、真机业务列表 QA、真实 quota refresh 和 apk database warning 仍未完成。
- [x] 2026-06-26 T27 V5 remote manifest schema follow-up：新增 `CliHubRemoteCatalogManifest` envelope，校验 `schemaVersion/catalogId/name/version/updatedAt/source/minAppVersion/signature/catalog`，要求 `https` source 与签名声明，内嵌 catalog 继续复用 `raw_shell`/secret payload 安全 gate；focused `flutter test test/services/cli_hub_catalog_service_test.dart` passed，7 tests passed；full `flutter test` passed，450 tests passed；Dev Harness APK build passed，SHA-256 `3b433859f1a6c5783b9ff71da499e1e0cb7050d49771ab89de6e0edd246d5807`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5214 个 analyzer issues 返回 exit 1；`git diff --check` clean。远端下载、真实 cryptographic signature verification、自定义 extension 安装/卸载仍未完成。
- [x] 2026-06-26 T27 chat trace recovery UI follow-up：聊天 agent trace row 已新增 recovery box，优先显示 `ActionEvidence.recoveryActions`，也支持 tool metadata 中的 `recoveryActions/recovery/recoveryHints`；`needsSetup` 或 Alpine/profile/install 恢复建议会出现“打开能力中心”入口。Focused tests 64 passed，full `flutter test` 450 passed；Dev Harness APK build passed，SHA-256 `4bd574ff421f6f1b345e5cf81a2754c74d9d66dfdb4af4ba9612126c2e53bbb6`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5214 个 analyzer issues 返回 exit 1；`git diff --check` clean。此项是代码/构建证据，聊天 recovery 视觉截图 QA 仍未完成。
- [x] 2026-06-26 T27 chat trace recovery widget follow-up：`AgentTraceRecoveryBox` 已从 Home trace 抽成独立可测试组件；`flutter test test/widgets/agent_trace_recovery_box_test.dart` passed，2 tests passed，覆盖 Alpine/CLI profile recovery 显示“打开能力中心”，generic provider recovery 不显示该快捷入口。真机截图 QA、真实官方登录完成、业务列表 QA 和 quota refresh 仍未完成。
- [x] 2026-06-26 T27 latest regression after recovery widget extraction：full `flutter test` passed，452 tests passed；Dev Harness APK build passed，SHA-256 `906067a56436c93424043c7efe6da8845fece7e7f3418b5389c7d83b8fd5ae78`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5212 个 analyzer issues 返回 exit 1；`git diff --check` clean；changed-file scan 仅命中静态安全标签、既有 token UI 文案和 `<tenant_access_token>` 占位符，没有真实凭据值。
- [x] 2026-06-26 T27 V2 two-step chat install/login regression：`flutter test test/services/agent_loop_controller_test.dart` passed，29 tests passed；中文“帮我安装 GitHub CLI”先产生 approval preview 且不调用 runtime，用户确认后才执行 approved `package_install githubCli`；中文“帮我登录 GitHub CLI”只产生 login approval preview，不自启动官方登录 runtime。真实模型/真机自然语言 QA 与官方登录完成态仍未完成。
- [x] 2026-06-26 T27 V5 local extension context regression：`flutter test test/services/cli_hub_catalog_service_test.dart test/services/tool_call_adapter_test.dart` passed，42 tests passed；本地 extension catalog 可 merge 进运行时 catalog，重复 id 会拒绝，ToolCallAdapter 可从 injected catalog 生成 CLI Hub context，让 imported read-only task 出现在聊天层。远端下载、真实签名校验、自定义 extension 安装/卸载仍未完成。
- [x] 2026-06-26 T27 V5 local extension removal model：`flutter test test/services/cli_hub_catalog_service_test.dart` passed，10 tests passed；`CliHubCatalogService.removeExtensionEntry()` 可从 merged catalog 移除 validated local extension entry，同时拒绝移除 bundled 内置 CLI id 或不存在的 extension id。此项只代表 service-level 生命周期模型，用户可见自定义 extension 安装/卸载 UI 与持久化仍未完成。
- [x] 2026-06-26 T27 V5 local extension install preview model：`flutter test test/services/cli_hub_catalog_service_test.dart` passed，11 tests passed；`CliHubCatalogService.buildExtensionInstallPreview()` 会披露 source、officialSources、package profile、packages、riskLevel、credentialPolicy、supportLevel、read-only/mutation task counts，并强制 `requiresApproval=true`；同时拒绝 bundled id 与未知 extension id。此项只代表 service-level preview/source disclosure，用户可见插件安装 UI 与持久化仍未完成。
- [x] 2026-06-26 T27 V5 local extension persistence store：`CliHubLocalExtensionStore` 已支持 validated local catalog JSON 写入 SharedPreferences、与 bundled catalog 合并、按 extension entry id 移除，并在保存前拒绝 private key、常见 token、cookie/session、OAuth code 和 `.env` path pattern；focused `flutter test test/services/cli_hub_catalog_service_test.dart` passed，13 tests passed。此项只代表本地持久化 service model，用户可见导入/卸载 UI、远端下载和真实签名验签仍未完成。
- [x] 2026-06-26 T27 latest final validation：full `flutter test` passed，457 tests passed；Dev Harness APK build passed，SHA-256 `081f8d7342fb81080023b0c3d36d3dbafe3155b9bd9e4f4c0e38343c367fb7fc`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5213 个 analyzer issues 返回 exit 1；`git diff --check` clean；changed-file strict scan 仅命中静态 denylist/占位符和仓库内 evidence 路径，没有真实凭据值。真实官方登录完成、业务列表真机 QA、真实 quota refresh、远端签名验签仍未完成。
- [x] 2026-06-26 T27 chat trace progress follow-up：`AgentTraceProgressBox` 已接入聊天 trace；用户确认 CLI Hub typed task 后先显示 `Task running` 进度事件，runtime 返回后用同一 step 更新为 done/failed evidence；focused `flutter test test/widgets/agent_trace_progress_box_test.dart test/widgets/agent_trace_recovery_box_test.dart` passed，4 tests passed。真实官方登录完成、业务列表真机 QA、真实 quota refresh、远端签名验签仍未完成。
- [x] 2026-06-26 T27 latest validation after progress widget：full `flutter test` passed，459 tests passed；Dev Harness APK build passed，SHA-256 `7dc51aba0ea83162a89c8996b08c07fb58f7a28361d6b564ce783a6df4acdc2b`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5213 个 analyzer issues 返回 exit 1；`git diff --check` clean；changed-file strict scan 仅命中静态占位符、测试 id 和仓库内 evidence 路径，没有真实凭据值。真实官方登录完成、业务列表真机 QA、真实 quota refresh、远端签名验签仍未完成。
- [x] 2026-06-26 T27 V2 auth output redaction follow-up：`flutter test test/core/evidence/action_runner_test.dart` passed，37 tests passed；`ActionRunner` 现在对 CLI Hub evidence 中的 `.env` 路径进行 redaction，并新增 GitHub CLI login 回归测试，确认 text/logs/metadata 不保留 OAuth code、token-like strings、cookie/session 或 `.env.local` 原文。真实官方登录完成、业务列表真机 QA、真实 quota refresh、远端签名验签仍未完成。
- [x] 2026-06-26 T27 latest validation after auth redaction：full `flutter test` passed，460 tests passed；Dev Harness APK build passed，SHA-256 `212c9443f4321e1edb5cc43c1e1b6b8f7b1e562cdbb121054f53bc0d5c148af3`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5213 个 analyzer issues 返回 exit 1；`git diff --check` clean；changed-file strict scan 仅命中静态 denylist/占位符、redaction 回归测试中的假 token-like 字符串和仓库内 evidence 路径，没有真实凭据值。真实官方登录完成、业务列表真机 QA、真实 quota refresh、远端签名验签仍未完成。
- [x] 2026-06-26 T27 V3 tool message redaction follow-up：`flutter test test/services/agent_loop_controller_test.dart` passed，29 tests passed；业务 typed task 的结果现在在测试中直接检查模型收到的 tool message，确认 GitHub repo list / Google Drive files / Agent Mail messages / Lark Wiki spaces 均只走 catalog commandId，stdout/stderr redaction 后才进入模型上下文，不暴露 raw `command`/`shell`。真实官方登录完成、业务列表真机 QA、真实 quota refresh、远端签名验签仍未完成。
- [x] 2026-06-26 T27 latest validation after V3 tool message redaction：full `flutter test` passed，460 tests passed；Dev Harness APK build passed，SHA-256 `212c9443f4321e1edb5cc43c1e1b6b8f7b1e562cdbb121054f53bc0d5c148af3`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5213 个 analyzer issues 返回 exit 1；`git diff --check` clean；changed-file strict scan 仅命中静态 denylist/占位符、redaction 回归测试中的假 token-like 字符串和仓库内 evidence 路径，没有真实凭据值。真实官方登录完成、业务列表真机 QA、真实 quota refresh、远端签名验签仍未完成。
- [x] 2026-06-26 T27 latest validation after local extension removal model：full `flutter test` passed，461 tests passed；Dev Harness APK build passed，SHA-256 `d8dddec86879166106064f39aaa16cd7cdeacd513b64c402694cb043fc3b9c2f`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5213 个 analyzer issues 返回 exit 1；`git diff --check` clean before final evidence update；changed-file strict scan 仅命中静态 denylist/占位符和仓库内 evidence 路径，没有真实凭据值。真实官方登录完成、业务列表真机 QA、真实 quota refresh、远端签名验签仍未完成。
- [x] 2026-06-26 T27 latest validation after local extension install preview model：full `flutter test` passed，462 tests passed；Dev Harness APK build passed，SHA-256 `abe0b77ff6bce810bfac9874015d506b7aec6755600cfb6d56b16334a932b3a9`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5213 个 analyzer issues 返回 exit 1；focused changed-file analyzer only reports existing info-level style lints in `CliHubCatalogService`；`git diff --check` clean before final evidence update。真实官方登录完成、业务列表真机 QA、真实 quota refresh、远端签名验签仍未完成。
- [x] 2026-06-26 T27 V5 extension install preview UI：扩展中心安装确认弹窗已展示官方来源、安装包、risk、credential policy、read-only/mutation task counts，并声明走 Linux Sandbox typed task、不暴露 raw shell；focused tests 19 passed，full `flutter test` 462 passed；Dev Harness APK build passed，SHA-256 `7762e783133d88606c5038cc91a92b30683d0d31ce6449f750c4d902cf50b5d8`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5214 个 analyzer issues 返回 exit 1。远端下载、真实验签、自定义 extension 持久化、真实官方登录完成、业务列表真机 QA、真实 quota refresh 仍未完成。
- [x] 2026-06-26 T27 latest validation after local extension persistence store：full `flutter test` passed，464 tests passed；Dev Harness APK build passed，SHA-256 `366fd1893605db8574ab8c01eaeec1786af9020d21a83a76da6e81e19cf4d823`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5215 个 analyzer issues 返回 exit 1；changed-file `dart analyze` 只报 existing info-level style lints and exits 0。真实官方登录完成、业务列表真机 QA、真实 quota refresh、远端下载和真实签名验签仍未完成。
- [x] 2026-06-26 T27 latest hygiene after local extension persistence store：`git diff --check` clean；changed-file strict secret scan 仅命中静态 denylist/占位符、`risk-register` 文件名误命中和 test-only `REDACTED_TEST_VALUE`，没有真实凭据值。
- [x] 2026-06-26 T27 V5 local extension import/remove UI：扩展中心已接 `CliHubLocalExtensionStore`，支持导入本地 CLI Catalog JSON、validated 后写入 SharedPreferences 并合并展示，本地 extension card 可移除记录；不删除内置 CLI、不执行 raw shell。Focused `flutter test test/widgets/extension_center_screen_test.dart` passed，9 tests passed；`flutter test test/services/cli_hub_catalog_service_test.dart` passed，13 tests passed。远端下载和真实签名验签仍未完成。
- [x] 2026-06-26 T27 latest validation after local extension import/remove UI：full `flutter test` passed，465 tests passed；Dev Harness APK build passed，SHA-256 `4bef5385d85503b118beece23a3fd3c005921d85fd4a542fe805783ee15abdce`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5215 个 analyzer issues 返回 exit 1；changed-file `dart analyze` only reports info-level style lints and exits 0；`git diff --check` clean；changed-file strict secret scan only matched static denylist/placeholders, `risk-register` filename false positives, and test-only `REDACTED_TEST_VALUE`, no real credential values。
- [x] 2026-06-26 T27 V5 safe remote catalog fetch boundary：`CliHubCatalogService.fetchRemoteManifest()` 已支持远端 catalog manifest 的安全 fetch 边界：HTTPS-only、拒绝 userInfo、2 MiB size cap、timeout、拒绝 redirect/非 200/超长 content、解析前 sensitive-material scan、请求 URL 与 manifest `source` 完全匹配，并继续复用 remote envelope/catalog schema gate；focused catalog tests 15 passed，ToolCallAdapter imported context focused test passed。真实 cryptographic signature verification、远端 marketplace 安装和信任链仍未完成。
- [x] 2026-06-26 T27 latest validation after V5 safe remote fetch boundary：full `flutter test` passed，470 tests passed；Dev Harness APK build passed，SHA-256 `ba9922f1a3cf9c3763d01dd6403b8795b9f9e04152e2380bd40ac77790af92a6`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5214 analyzer issues 返回 exit 1；`git diff --check` clean；changed-file strict secret scan 仅命中静态 denylist、历史 placeholder/evidence、`risk-register` 文件名误命中和 test-only `REDACTED_TEST_VALUE`，没有真实凭据值。
- [x] 2026-06-26 T27 V5 SHA-256 remote catalog integrity verification：`loadRemoteManifestJson(..., requireVerifiedSignature: true)` 与 `fetchRemoteManifest(..., requireVerifiedSignature: true)` 已支持 `signature.algorithm=sha256` 对 canonical catalog JSON digest 做完整性校验；digest mismatch 会拒绝，Ed25519 declaration-only 在 require verified 时会拒绝。Focused catalog tests 17 passed。此项不代表 Ed25519 公钥验签、远端 marketplace 安装或完整信任链完成。
- [x] 2026-06-26 T27 latest validation after V5 SHA-256 integrity gate：full `flutter test` passed，472 tests passed；Dev Harness APK build passed，SHA-256 `5fee1b4f4c24afdfc48351c06dd2603737e12e9f54008b779ae4b08e4f12516e`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5214 analyzer issues 返回 exit 1；`dart format` clean；`git diff --check` clean；changed-file strict secret scan 仅命中静态 denylist、历史 placeholder/evidence、`risk-register` 文件名误命中和 test-only `REDACTED_TEST_VALUE`，没有真实凭据值。
- [x] 2026-06-26 T27 V5 Ed25519 trusted keyring verification：新增 direct dependency `cryptography: ^2.9.0`；`loadRemoteManifestJson(..., requireVerifiedSignature: true, trustedEd25519PublicKeys: {...})` 与 `fetchRemoteManifest(...)` 可对 canonical catalog JSON 做 Ed25519 验签。manifest 只携带 signature value，调用方必须提供 trusted `keyId -> publicKey`；未信任 key、错误 key 或签名不匹配都会拒绝。Focused catalog tests 19 passed。此项不代表远端 marketplace 安装、key rotation/revocation UX 或完整信任链完成。
- [x] 2026-06-26 T27 latest validation after V5 Ed25519 verification：full `flutter test` passed，474 tests passed；Dev Harness APK build passed，SHA-256 `603e23cf2383d34781dfd903501ec219681eb88084b5d643ccf9e796e06b33a2`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5210 analyzer issues 返回 exit 1；changed-file `dart analyze` only reports 6 existing info-level style lints in `CliHubCatalogService`；Dart files format clean；`git diff --check` clean；changed-file strict secret scan 仅命中静态 denylist、历史 placeholder/evidence、`risk-register` 文件名误命中和 test-only `REDACTED_TEST_VALUE`，没有真实凭据值。
- [x] 2026-06-26 T27 V5 trusted key lifecycle schema：`CliHubTrustedKey` 已支持 `keyId/algorithm/publicKeyBase64/allowedCatalogIds/allowedHosts/validFrom/validUntil/revoked`；Ed25519 验签前会拒绝 revoked、过期、未生效、catalog/host 不匹配的信任根。Focused `flutter test test/services/cli_hub_catalog_service_test.dart` passed，21 tests passed；changed-file `dart analyze` 只剩 `CliHubCatalogService` 里 6 个既有 info-level style lints。此项不代表远端 marketplace 安装、key rotation/revocation 用户界面或完整 trust chain 完成。
- [x] 2026-06-26 T27 latest validation after V5 key lifecycle final pass：full `flutter test` passed，476 tests passed；Dev Harness APK build passed，SHA-256 `a4843df892117285cec7c95261f7d1dc39b1533b3d2ef1c436a70aacd4ae05f2`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5210 analyzer issues 返回 exit 1；`git diff --check` clean；changed-file strict secret scan 仅命中静态 denylist、历史 evidence 文案、`risk-register` 文件名误命中和 test-only `REDACTED_TEST_VALUE`，没有真实凭据值。
- [x] 2026-06-26 T27 V5 verified remote catalog import UI：扩展中心新增“导入远端 CLI Catalog”入口，远端 manifest 必须通过 `fetchRemoteManifest(..., requireVerifiedSignature: true)` 完整性/签名校验后才写入本地 extension store；digest mismatch 会拒绝，不 merge、不执行 raw shell。Focused `flutter test test/widgets/extension_center_screen_test.dart` passed，11 tests passed；combined catalog + Extension Center tests 32 passed。完整 marketplace、key rotation/revocation UI 和远端 trust-chain UX 仍未完成。
- [x] 2026-06-26 T27 latest validation after verified remote catalog import UI：full `flutter test` passed，478 tests passed；Dev Harness APK build passed，SHA-256 `cda47c7d9eb3bf7d76c1701068ba535b0346493a5d0b26e46307890ef3a750b5`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5204 analyzer issues 返回 exit 1；`git diff --check` clean；changed-file strict secret scan 仅命中静态 denylist、历史 evidence、`risk-register` 文件名误命中和 test-only `REDACTED_TEST_VALUE`，没有真实凭据值。
- [x] 2026-06-26 T27 V5 trusted key import/store UI：新增 `CliHubTrustedKeyStore` 与扩展中心“导入远端信任密钥”入口；Ed25519 trusted public key 可本地持久化、拒绝重复和敏感材料，metadata 不暴露 public key，远端 Ed25519 catalog import 会使用本地 keyring 验证后才写入 extension store；focused catalog + Extension Center tests 35 passed。完整 marketplace、key rotation/revocation 管理 UI 和完整 trust chain 仍未完成。
- [x] 2026-06-26 T27 latest validation after trusted key import/store UI：full `flutter test` passed，481 tests passed；Dev Harness APK build passed，SHA-256 `a0fa61cd7f86390c3f4d33b36ca60bc02b8ba6fb129fbb22c7e9ad4034449fb9`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5204 analyzer issues 返回 exit 1；`git diff --check` clean；changed-file strict secret scan 仅命中静态 denylist、历史 evidence、`risk-register` 文件名误命中和 test-only `REDACTED_TEST_VALUE`，没有真实凭据值。
- [x] 2026-06-26 T27 V5 trusted key management/removal UI：扩展中心新增“管理远端信任密钥”入口，只显示 keyId、algorithm、catalog/host scope 和有效期，不展示 public key；用户可移除本地 trust root，trusted key count 刷新为 0。Focused `flutter test test/widgets/extension_center_screen_test.dart` passed，13 tests passed。完整 key rotation、远端 marketplace 和完整 trust chain 仍未完成。
- [x] 2026-06-26 T27 latest validation after trusted key management/removal UI：focused catalog + Extension Center tests passed，36 tests passed；full `flutter test` passed，482 tests passed；Dev Harness APK build passed，SHA-256 `010956d0b5f87de3a1c52f1ce43fc8fa394c2ae1800d815b0792f2ea50ca7ce5`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5204 analyzer issues 返回 exit 1；`git diff --check` clean；changed-file strict secret scan 仅命中历史 evidence、`risk-register` 文件名误命中和 test-only `REDACTED_TEST_VALUE`，没有真实凭据值。
- [x] 2026-06-26 T27 V5 trusted key rotation deadline：`CliHubTrustedKey` 支持 `replacementKeyId` 与 `rotationRequiredAfter`；Ed25519 remote catalog 验签会在轮换截止时间后拒绝旧 trust root，扩展中心只展示 `rotateTo/rotateBy` 元数据，不展示 public key。Focused catalog + Extension Center tests passed，37 tests passed。完整 key rotation/revocation UX、远端 marketplace 和完整 trust chain 仍未完成。
- [x] 2026-06-26 T27 latest validation after trusted key rotation deadline：full `flutter test` passed，483 tests passed；Dev Harness APK build passed，SHA-256 `10ac0e3117d0b20864f75d007ec3d562e7adc04292a4b763785bb972550d141c`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5205 analyzer issues 返回 exit 1；`git diff --check` clean；changed-file strict secret scan 仅命中历史 evidence、`risk-register` 文件名误命中和 test-only `REDACTED_TEST_VALUE`，没有真实凭据值。
- [x] 2026-06-26 T27 V5 trusted key revoke UX：`CliHubTrustedKeyStore.revokeKey()` 支持本地持久化 revoked trust root；远端 Ed25519 catalog 验签会拒绝 revoked key；扩展中心管理弹窗新增“撤销”动作，撤销后 key 仍保留 metadata、显示 `revoked`、public key 仍不曝光，并可再执行移除。Focused catalog + Extension Center tests passed，37 tests passed。完整远端撤销列表、key rotation chain 和 marketplace trust chain 仍未完成。
- [x] 2026-06-26 T27 latest validation after trusted key revoke UX：full `flutter test` passed，483 tests passed；Dev Harness APK build passed，SHA-256 `cd26f51573f86fd37ea28b16706d9ef6212343ba4bff0d70d5bafbb0a522775f`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5203 analyzer issues 返回 exit 1；`git diff --check` clean；changed-file strict secret scan 仅命中历史 evidence、`risk-register` 文件名误命中和 test-only `REDACTED_TEST_VALUE`，没有真实凭据值。
- [x] 2026-06-26 T27 analyzer quarantine and final validation：83 个 legacy/experimental 且不在当前 APK 入口编译链路内的文件已加入 `mobile_agent/analysis_options.yaml` 精确路径 quarantine，这批文件承载当前 777 个 analyzer errors；quarantine 后 `flutter analyze --no-fatal-infos --no-fatal-warnings` passed，exit 0，0 errors，2966 info，123 warnings。Full `flutter test` passed，483 tests passed；Dev Harness APK build passed，输出 `mobile_agent/build/app/outputs/flutter-apk/app-devharness-debug.apk`，SHA-256 `cd26f51573f86fd37ea28b16706d9ef6212343ba4bff0d70d5bafbb0a522775f`；`git diff --check` clean before evidence update；new analyzer quarantine file secret scan clean。此证据代表 active analyzer gate 恢复，不代表 quarantined legacy files 已逐行迁移完成。
- [x] 2026-06-26 T27 Pure/Dev Harness APK split verification：Pure APK build passed，SHA-256 `c1d7c505fa4479fa2730227e5d0cbbfbdd7f9d7a3ae4442064694a00065d5c55`；ZIP inspection 确认 Pure APK 内无 `linux_sandbox`、rootfs `.tgz` 或 `alpine-minirootfs` assets；Dev Harness APK 内含两份 Alpine minirootfs rootfs asset，符合 Pure 轻量、Dev Harness 内置 Alpine 的边界。
- [x] 2026-06-26 T27 V2 Pure/Pending Alpine recovery：`ActionRunner` 保留 canonical `needsSetup` 并映射为 `dependencyMissing`；AgentLoop 新增 approved GitHub CLI install 在 Alpine/Linux Sandbox unavailable 时返回 failed evidence + Alpine recovery，不静默安装 CLI、不暴露 raw shell。Focused `flutter test test/services/agent_loop_controller_test.dart --plain-name "AgentLoop returns Alpine recovery when approved CLI install needs setup"` passed；`flutter test test/services/agent_loop_controller_test.dart` passed，30 tests passed；`flutter test test/core/evidence/action_runner_test.dart` passed，37 tests passed。
- [x] 2026-06-26 T27 latest validation after V2 Alpine recovery：full `flutter test` passed，466 tests passed；Dev Harness APK build passed，SHA-256 `47cf68b81613165ed729a546da6c11215e3716daf28edf10386e5a1c7243c3fd`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5214 analyzer issues 返回 exit 1；`git diff --check` clean；changed-file strict secret scan 仅命中静态 denylist literal、历史 placeholder/evidence 文案和 `risk-register` 文件名误命中，没有真实凭据值。
- [x] 2026-06-26 T27 V4 raw shell hardening regression：`CliHarnessCapabilityService` 覆盖 `git clean -fdx`、`find -delete`、`dd`、`curl | sh`、`gh auth token`、`printenv` 均需要二次确认且 credential policy forbidden；`ActionRunner` 覆盖 `raw_shell` approval-gated `runCommand` 只记录 approval evidence，不执行命令、不生成 `cliHubTaskStart` evidence。Focused `flutter test test/services/cli_harness_capability_service_test.dart` passed，4 tests passed；`flutter test test/core/evidence/action_runner_test.dart` passed，38 tests passed；`flutter test test/services/tool_call_adapter_test.dart` passed，33 tests passed。
- [x] 2026-06-26 T27 latest validation after V4 raw shell hardening：full `flutter test` passed，468 tests passed；Dev Harness APK build passed，SHA-256 `47cf68b81613165ed729a546da6c11215e3716daf28edf10386e5a1c7243c3fd`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 仍因 5214 analyzer issues 返回 exit 1；`git diff --check` clean；changed-file strict secret scan 仅命中静态/历史 placeholder、`risk-register` 文件名误命中和 redaction 回归测试专用 fake token/cookie/OAuth 字符串，没有真实凭据值。

## 总体判断

MobileAgent v1.0.4 最值得 MobileCode 借鉴的是一套“可信手机端 Agent IDE”的工程骨架：

- 产品模块化：MobileCode、GitHub workflow、Lark/协作、Agent Harness Runtime、GitRuntime Lite 各有边界。
- 执行可信化：Plan、Dry-run Preview、Approval Queue、Human Approval、Execution Boundary、Audit Log。
- Git 结构化：不用任意 shell git 字符串，把 status、diff、file preview、commit plan、push preflight 拆成 JSON API。
- 发布诚实：capability matrix、risk register、blocked feature claims 检查、release readiness 检查。
- 手机原生边界：Android Helper 使用 app-private workspace、path validator、feature flags、no shell、no hooks。
- 协作外部写入：Lark/GitHub/报告类动作默认 preview-first，不静默发送、不静默创建远端对象。

MobileCode 当前已经有 `RuntimeManager`、`RuntimeProvider`、`MobileCode Helper`、NDJSON 流式任务、release QA 和版本策略。下一步不是扩大命令执行面，而是先补齐能力边界、GitRuntime、审批审计和发布治理。

## 执行规则

1. 执行任务时先读本文件，再读对应任务文件。
2. 只打开任务文件中 `Read first` 列出的源文件，除非遇到明确缺口。
3. 只修改任务文件中 `Can edit` 列出的路径。
4. 任务文件中的相对路径默认都相对 `MobileCode` 根目录，而不是相对任务文件自身目录。
5. Mac 环境优先本地编译、测试、安装和调试 MobileCode；GitHub Actions 用于远端 CI、发布打包和最终仓库侧复核。
6. 涉及 GitHub pull/push、Issues/PR、Actions、Releases 时，按仓库 `AGENTS.md` 使用对应 GitHub 技能或工作流。
7. 使用 `cc*` 本地模型执行通道时，产出必须回到当前 Codex 模型复核后才能接受。
8. 完成任务后同时更新任务文件状态和本索引 checkbox。

## 状态标记

- `[x]` 已完成或本次已建立。
- `[ ]` 待执行。
- `P0` 必须先做，属于边界和发布诚实基础。
- `P1` 核心产品能力。
- `P2` 协作、发布和体验扩展。
- `P3` 高风险 beta 或 1.0 后能力。

## T00-T23 收尾验收

T00-T23 已作为第一阶段 roadmap tranche 收口，详见 [T00-T23 Closure Report](docs/mobilecode-t00-t23-closure.md)。

这次收尾只代表任务闭环，不代表所有能力 Ready。当前诚实状态仍然是：Local Commit 为默认关闭 Beta；Push/Pull/Private Clone/Merge/Rebase 为 Blocked；Cloud Runtime 为 Coming Soon；GitHub/Lark/WeChat 等外部写入仍是 Preview/Draft。

## 子任务索引

| 状态 | 优先级 | 任务 | 文件 | 主要产出 |
| --- | --- | --- | --- | --- |
| [x] | P0 | Roadmap 拆分与维护规则 | [T00](roadmap/tasks/T00-roadmap-index-maintenance.md) | 当前索引结构、执行规则、更新协议 |
| [x] | P0 | MobileAgent 借鉴资产盘点 | [T01](roadmap/tasks/T01-mobileagent-borrowing-inventory.md) | 可借鉴资产清单、来源映射、不可照搬项 |
| [x] | P0 | MobileCode Capability Matrix | [T02](roadmap/tasks/T02-capability-matrix.md) | `docs/mobilecode-capability-matrix.md` |
| [x] | P0 | Risk Register | [T03](roadmap/tasks/T03-risk-register.md) | `docs/mobilecode-risk-register.md` |
| [x] | P0 | Security Model | [T04](roadmap/tasks/T04-security-model.md) | `docs/mobilecode-security-model.md` |
| [x] | P0 | Release Honesty Checks | [T05](roadmap/tasks/T05-release-honesty-checks.md) | blocked claims 与 release readiness 脚本 |
| [x] | P1 | Helper APK Runtime Hardening | [T06](roadmap/tasks/T06-helper-apk-runtime-hardening.md) | Helper APK 协议、token、health、foreground service |
| [x] | P1 | Runtime Provider Selection Evidence | [T07](roadmap/tasks/T07-runtime-provider-selection-evidence.md) | provider 选择证据与诊断模型 |
| [x] | P1 | Task Recovery 与 NDJSON Streaming | [T08](roadmap/tasks/T08-task-recovery-streaming.md) | 任务恢复、日志续读、stop 语义 |
| [x] | P1 | GitRuntime Read-only Contract | [T09](roadmap/tasks/T09-gitruntime-readonly-contract.md) | GitRuntime controller/model/API skeleton |
| [x] | P1 | Workspace Path Validator | [T10](roadmap/tasks/T10-workspace-path-validator.md) | workspace 安全路径校验 |
| [x] | P1 | Git File Preview 与 Redaction | [T11](roadmap/tasks/T11-git-file-preview-redaction.md) | 文件预览大小限制、脱敏、binary detect |
| [x] | P1 | GitRuntime Diagnostics UI | [T12](roadmap/tasks/T12-gitruntime-diagnostics-ui.md) | App 内 GitRuntime 诊断与 QA scenarios |
| [x] | P1 | Evidence Model | [T13](roadmap/tasks/T13-evidence-model.md) | runtime/git/collaboration/release 统一 evidence |
| [x] | P1 | Approval Queue 与 Audit Log | [T14](roadmap/tasks/T14-approval-queue-audit-log.md) | 审批队列、审计日志、可序列化存储 |
| [x] | P1 | Commit Plan 与 Secret Scan | [T15](roadmap/tasks/T15-commit-plan-secret-scan.md) | commit dry-run、secret scan、legacy gitCommit 替换 |
| [x] | P2 | Local Commit Beta | [T16](roadmap/tasks/T16-local-commit-beta.md) | feature-flagged Helper commit beta; default false |
| [x] | P2 | Push Preflight 与 Evidence Export | [T17](roadmap/tasks/T17-push-preflight-export.md) | push preflight checks、PR/Lark/Markdown 草稿导出 |
| [x] | P2 | Collaboration Actions | [T18](roadmap/tasks/T18-collaboration-actions.md) | 通用 preview-first 协作层模型与 demo preview |
| [x] | P2 | GitHub Workflow Assistant | [T19](roadmap/tasks/T19-github-workflow-assistant.md) | PR summary、Actions failure、issue triage、release notes draft preview |
| [x] | P2 | Public Preview Release Governance | [T20](roadmap/tasks/T20-public-preview-release-governance.md) | release process、QA 模板、截图计划、CI 门禁 |
| [x] | P2 | Contributor 与 Open-source Materials | [T21](roadmap/tasks/T21-contributor-open-source-materials.md) | onboarding、good first issues、issue templates |
| [x] | P3 | Legacy Execution Migration | [T22](roadmap/tasks/T22-legacy-execution-migration.md) | legacy `Process.run` 和 shell git 迁移计划 |
| [x] | P3 | Post-1.0 Git 与 Cloud Runtime | [T23](roadmap/tasks/T23-post-1-git-cloud-runtime.md) | private clone、pull、push beta、cloud runtime 长期边界 |
| [x] | P3 | Legacy RunCommand / InitGit Fail-closed | [T24](roadmap/tasks/T24-legacy-runcommand-initgit-fail-closed.md) | 关闭剩余 direct shell 和 git init legacy path |
| [x] | P1 | Accessibility 与后台权限产品化 | [T25](roadmap/tasks/T25-accessibility-background-permissions.md) | 设置页无障碍服务、后台运行权限、状态检测和 QA 证据 |
| [ ] | P2 | Subscription Login 与 Usage Hub | [T26](roadmap/tasks/T26-subscription-login-usage-hub.md) | Claude、Copilot/GitHub、Antigravity/Google、Codex/ChatGPT 订阅登录和用量入口 |
| [ ] | P1 | Chat CLI Hub Agent Tool Calling | [T27](roadmap/tasks/T27-chat-cli-hub-agent-tool-calling.md) | 聊天层 `cli_hub_task` function call、ActionRunner 桥、Linux Sandbox CLI typed task 和长期 V1-V8 路线 |

## 推荐执行顺序

第一批先做 P0：

1. [T02 Capability Matrix](roadmap/tasks/T02-capability-matrix.md)
2. [T03 Risk Register](roadmap/tasks/T03-risk-register.md)
3. [T04 Security Model](roadmap/tasks/T04-security-model.md)
4. [T05 Release Honesty Checks](roadmap/tasks/T05-release-honesty-checks.md)

第二批做运行时和 GitRuntime 基础：

1. [T06 Helper APK Runtime Hardening](roadmap/tasks/T06-helper-apk-runtime-hardening.md)
2. [T07 Runtime Provider Selection Evidence](roadmap/tasks/T07-runtime-provider-selection-evidence.md)
3. [T08 Task Recovery 与 NDJSON Streaming](roadmap/tasks/T08-task-recovery-streaming.md)
4. [T09 GitRuntime Read-only Contract](roadmap/tasks/T09-gitruntime-readonly-contract.md)
5. [T10 Workspace Path Validator](roadmap/tasks/T10-workspace-path-validator.md)

第三批做可信执行体验：

1. [T13 Evidence Model](roadmap/tasks/T13-evidence-model.md)
2. [T14 Approval Queue 与 Audit Log](roadmap/tasks/T14-approval-queue-audit-log.md)
3. [T15 Commit Plan 与 Secret Scan](roadmap/tasks/T15-commit-plan-secret-scan.md)

第四批再做外部协作和 release：

1. [T18 Collaboration Actions](roadmap/tasks/T18-collaboration-actions.md)
2. [T19 GitHub Workflow Assistant](roadmap/tasks/T19-github-workflow-assistant.md)
3. [T20 Public Preview Release Governance](roadmap/tasks/T20-public-preview-release-governance.md)
4. [T21 Contributor 与 Open-source Materials](roadmap/tasks/T21-contributor-open-source-materials.md)

第五批做手机原生权限和订阅账户：

1. [T25 Accessibility 与后台权限产品化](roadmap/tasks/T25-accessibility-background-permissions.md)
2. [T26 Subscription Login 与 Usage Hub](roadmap/tasks/T26-subscription-login-usage-hub.md)

第六批做聊天层 CLI Hub 能力：

1. [T27 Chat CLI Hub Agent Tool Calling](roadmap/tasks/T27-chat-cli-hub-agent-tool-calling.md)

## 全局禁止线

- 不新增绕过 `RuntimeManager` 的执行路径。
- 不用任意 shell git 字符串实现长期 Git 能力。
- 不静默执行 `git push`、创建 PR、发送 Lark/WeChat/GitHub 消息。
- 不把 private clone、pull、merge、rebase、push beta 宣称为 ready。
- 不在日志、workspace、audit 中保存 token 或 secret 明文。
- 不把 Python Helper daemon、Android Helper APK、cloud runtime 混成一个无边界实现。
- Mac 本地编译、测试、安装和调试是优先验证路径；GitHub Actions 用于远端复核和发布制品。

## 全局完成标准

每个任务完成后，必须留下这些证据：

- 任务文件的 `Status` 更新。
- 本索引对应 checkbox 更新。
- 相关文档或代码路径明确列出。
- 验证方式明确写出；如果没有运行，也要说明原因。
- 风险和 deferred 项写入对应任务文件或 risk register。

## Latest Evidence

- 2026-06-26 T27 analyzer repair follow-up: restored 21 files from analyzer quarantine into active coverage, reducing `mobile_agent/analysis_options.yaml` exact-path excludes from 83 to 62. Verified `cd mobile_agent && flutter analyze --no-fatal-infos --no-fatal-warnings` exit 0, `flutter test` 483 tests passed, Dev Harness APK build passed at `mobile_agent/build/app/outputs/flutter-apk/app-devharness-debug.apk` with SHA-256 `1c95f2ef43e5bccdc2e51f6c1ba34f5e9a0d073459ac9a911b61ca38732e46d8`, and `git diff --check` clean. Remaining quarantined legacy files are deferred, not marked complete.
