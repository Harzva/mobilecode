# MobileCode Harness Long-term Task Index

这个文件是 MobileCode Harness 长期路线图的任务索引。它参考 `roadmp.md` 的组织方式，把“长期计划”拆成可执行、可验收、可停止的任务卡，避免路线图变成一篇好看的长文。

## Recovery Baseline（2026-05-21）

本轮恢复以 `v0.1.39` 为 UI 产品真值：

```text
tag:    v0.1.39
commit: 460cb675aea0993a791e609412845becdc0f3768
branch: origin/v011-streaming-fix
```

原因：

- `v0.1.39` 对应用户确认的正确产品 UI（Chat / Tools / Skills / Roles）。
- `v0.1.40-last`、`v0.1.41-last`、`v0.1.42-last` 不作为产品验收基线。
- `last` 后续应恢复为“保留 v0.1.39 UI + 最小迁移 Harness 能力”的结果。

本轮允许迁移：

- `ActionEvidence` / `ActionEvidenceStore`。
- `ActionRunner`。
- Agent Trace 的 `evidenceId` 绑定。
- H05 最小版 `Activity / Logs` 入口，只读 `recent()` 与 `failures()`。

本轮不迁移：

- Chat 首屏能力边界大卡。
- 覆盖 `v0.1.39` Chat / Tools / Skills / Roles 主视觉的 H04 UI 改动。
- H05 搜索、分类、远程日志、持久化查询。

## Experiment Log（2026-05-21）

公开复盘口径：

- `v0.1.43-last` 当前是 `single-shot generation + ActionRunner + Evidence`，不是完整 provider-native tool-calling Agent。
- 当前真实闭环：模型输出内容 -> App 提取/保存产物 -> `ActionRunner.writeFile/readFile/previewHtml` -> `ActionEvidenceStore` -> `Activity / Logs` 复盘。
- 当前缺口：模型尚未通过 provider-native `tool_call/tool_use` 分步请求工具，工具执行结果也尚未回传给模型形成 observation loop。
- 下一阶段目标：从“保存模型完整输出”升级为 `model intent -> tool call -> ActionRunner -> evidence -> observation -> next action`。

任务关系：

- H07：给不支持原生 tool call 的 provider 提供 JSON action fallback。
- H08：接 OpenAI tools / Anthropic tool_use，输出统一 `ActionSchema`。
- H15：把失败 evidence/logs 反馈为修复建议、用户确认和重试循环。

GitHub Pages 公开实验日志入口：`/experiments`，主题为 `From Single-Shot Generation to Tool-Calling Harness`。

## DeepSeek-First Tool Calling Route（2026-05-21）

本轮技术路线更新：

- 以 `v0.1.43-last / last-recover-from-v039` 作为产品 UI 基线，不再用 H04/H05 的工程面板式首屏覆盖正确 UI。
- DeepSeek 作为 H08 `Provider ToolCall Adapter` 的第一条 provider-native 实现线，但 MobileCode 不绑定为 DeepSeek-only 产品。
- `DeepSeek-TUI` 作为架构参考：学习工具面收敛、结构化工具调用、日志句柄和失败 observation，不迁移它的 shell、task、subagent、runtime server 能力。
- Provider-native 主路径只开放 `write_file`、`read_file`、`preview_html`、`report_result`。
- 明确禁止：shell、Git push、发布、远程日志、任意命令、绕过 `ActionRunner` 的文件写入。
- `model_acess.txt` 只作为后续本地凭据输入来源，不读取、不打印、不提交、不进入日志。

当前 H08 增量实现：

- 新增 DeepSeek provider preset，默认 OpenAI-compatible Base URL：`https://api.deepseek.com/v1`，默认模型：`deepseek-chat`。
- 新增 `OpenAiCompatibleToolCallAdapter`，可生成安全工具 schema、解析 non-streaming `tool_calls`、拼接 streaming `delta.tool_calls`、生成 `role: tool` observation message。
- Agent 路径优先尝试 DeepSeek/OpenAI-compatible provider-native tool loop；若模型没有返回 `tool_calls`，明确走 generated-only fallback，不伪装为真实工具调用。
- Tool call 执行统一进入 `ActionRunner`，产出继续进入 `ActionEvidenceStore`。
- 第一阶段没有实现 H15 自动修复循环，也没有开放 shell/Git/publish。

当前先保持为单文件任务索引。后续如果任务继续膨胀，再单独开小任务拆成：

```text
docs/import_phase_summarize/harness_tasks/
```

## 为什么这样改

- 更清楚：每个方向都有任务编号、优先级、产出和验收标准。
- 更适合接力：Codex、ccmimo 或其他执行通道只需要处理一个任务。
- 更能防发散：每个任务都有 stop line 和 out of scope。
- 更容易收尾：不是“长期都要做”，而是知道 v1 到哪里可以停。
- 更诚实：把“伪 Agent / 真 Agent / Function Call / Wrapper / Runtime”的边界写清楚。

## 总体定位

MobileCode 的长期目标不是做一个缩小版桌面 IDE，也不是做一个只会生成代码的聊天壳，而是做一个真正运行在手机上的 AI Coding Harness。

核心链路：

```text
模型智能
  -> MobileCode Harness
  -> Action Wrapper / Runtime Adapter / Connector
  -> 手机文件、WebView、GitHub、Termux、Helper、Cloud
  -> Evidence / Logs / Recovery
```

一句话定义：

> MobileCode 要把模型意图变成手机环境中可执行、可观察、可恢复、可发布的动作。

## 当前阶段判断

MobileCode 不是纯伪 Agent，但也还不是成熟的全工具 Agent。

当前状态更准确地说是：

```text
半工具化的移动端 Coding Harness 过渡态
```

已经具备：

- 文件写入、代码查看、编辑器入口。
- WebView 预览、浏览器打开、GitHub Pages 发布。
- RuntimeProvider / RuntimeManager。
- Helper / Termux / WebViewOnly / GitHub API 降级路线。
- Repo Hub、Release、Actions、Artifact、Skill/MCP 发现。
- Role、Memory、Token Usage、Device Telemetry、minimap 等控制台能力。

主要缺口：

- 工具步骤还没有全部绑定真实 evidence。
- 模型不总是通过结构化 action 调用工具。
- 失败日志没有稳定回传给模型形成修复循环。
- Runtime、GitHub、Storage、Provider 的连接状态还不够统一。
- 首页仍容易暴露太多工程状态，影响手机端产品感。

## 执行规则

1. 每次只执行一个任务编号，避免顺手扩大范围。
2. 执行前先读本文件，再读相关源码或文档。
3. 涉及代码改动时，必须写清楚 `Can edit` 和 `Do not edit`。
4. 涉及 runtime、GitHub、文件系统、token、MCP 时，默认按安全边界处理。
5. 不新增绕过 `RuntimeManager` / `ActionRunner` 的长期执行入口。
6. 不把普通模型文本生成伪装成真实工具调用。
7. 使用 cc* 执行通道时，结果必须回到 Codex 当前模型复核后接受。
8. 完成后更新任务状态、证据、验证结果和剩余风险。

## 状态标记

- `TODO`：尚未开始。
- `IN_PROGRESS`：正在执行。
- `REVIEW_NEEDED`：已完成改动，等待 Codex 审核。
- `ACCEPTED`：已审核通过。
- `BLOCKED`：被依赖、环境或设计问题阻塞。
- `DEFERRED`：不属于当前版本。

## 优先级定义

- `P0`：决定产品可信度和 v1 收尾，必须优先做。
- `P1`：核心能力，做完后产品明显更完整。
- `P2`：增强项，可后置。
- `P3`：高风险实验或 1.0 后能力。

## First Principles

1. 手机端先解决环境事实，再谈智能。
2. 每个能力都要可检测、可解释、可恢复。
3. UI 步骤必须逐步变成工具证据。
4. 本地做轻任务，GitHub/Termux/Helper/Cloud 做重任务。
5. 不把无障碍自动化作为 v1 核心依赖。
6. 用户必须知道文件在哪、日志在哪、权限为什么需要。
7. 不为了“看起来像 Agent”增加假步骤。
8. 角色、Memory、Rules、Skill、MCP 必须有清晰边界。

## Function Call 与 Wrapper 决策

Function Call 要做，但不能作为唯一核心。

MobileCode 应先做自己的 `Action Wrapper`，再适配不同 provider 的 function call。

原因：

- OpenAI、Anthropic、自定义 provider 的工具调用格式不同。
- 一些模型只支持普通文本或 JSON，不稳定支持 tool call。
- MobileCode 的核心执行边界在手机端，不应该被某个 provider 的格式绑死。

推荐结构：

```text
ModelProvider
  -> ToolCallAdapter
      -> OpenAI tools adapter
      -> Anthropic tool_use adapter
      -> JSON action adapter
      -> plain text fallback adapter
  -> MobileCode ActionRunner
  -> Runtime / GitHub / File / WebView / Skill / MCP
  -> ActionEvidence
```

降级规则：

- Provider 支持 function call：走原生 tool call adapter。
- Provider 不支持 function call：走 JSON action plan。
- JSON action plan 失败：降级普通生成，但 UI 标记为 `generated-only`。
- 不能把普通生成伪装成真实工具调用。

## KimiClaw 借鉴边界

KimiClaw 最值得借鉴的是手机端产品组织方式，不是照搬无障碍自动化。

可借鉴：

- 权限 checklist。
- 连接器 bottom sheet。
- 网关/daemon 状态卡。
- 日志面板。
- 用户可见文件夹授权。
- 清晰的“去授权 / 重启 / 连接 / 查看日志”路径。

不照搬：

- 不把无障碍作为 v1 核心执行路径。
- 不默认控制微信、Kimi、飞书等第三方 App。
- 不后台静默点击敏感权限。

## 任务索引

| 状态 | 优先级 | ID | 任务 | 主要产出 | Stop Line |
| --- | --- | --- | --- | --- | --- |
| ACCEPTED | P0 | H00 | Harness 任务索引维护 | 本文件保持最新 | 只维护路线，不写代码 |
| ACCEPTED | P0 | H01 | 当前能力基线盘点 | capability baseline 与伪 Agent 边界 | 不夸大已实现能力 |
| ACCEPTED | P0 | H02 | Action Schema 与 ActionEvidence | 统一 action/evidence 数据模型 | 不接具体 provider function call |
| ACCEPTED | P0 | H03 | Agent Trace 读取 Evidence | 步骤详情从文案升级为证据卡 | 不改执行策略 |
| ACCEPTED | P0 | H04 | 首页减负与手机聊天化 | 隐藏内部状态，优化输入区 | 不删 Diagnostics 能力 |
| ACCEPTED | P0 | H05 | Logs / Activity 中心 | 模型、runtime、GitHub、文件日志统一查看 | 不做远程日志上传 |
| ACCEPTED | P1 | H06 | ActionRunner 最小实现 | write/read/preview 三个基础动作 | 不开放任意 shell |
| TODO | P1 | H07 | JSON Action Fallback | 不支持 tool call 的模型也能行动 | JSON 失败必须标记 generated-only |
| REVIEW_NEEDED | P1 | H08 | Provider ToolCall Adapter | DeepSeek/OpenAI-compatible first pass | Anthropic adapter 与 live provider CI 仍待补 |
| TODO | P1 | H09 | Connector Readiness 模型 | GitHub/Termux/Helper/Cloud/Lark/Storage 状态统一 | 不把状态散落到 UI |
| TODO | P1 | H10 | GitHub-first 轻量工作区 | API workspace、Actions、Pages、Release 补强 | 无 git 时不报死错误 |
| TODO | P1 | H11 | 用户可见共享目录 | Documents/MobileCode 授权与同步 | 不替代 App 私有工作区 |
| TODO | P1 | H12 | Runtime / Termux / Helper 诊断 | daemon、git、权限、workspace 检测 | 不做完整内置 Termux |
| TODO | P1 | H13 | Rules / Memory / Role / Skill 分层 | 上下文来源可管理、可解释 | 不自动写长期记忆 |
| TODO | P1 | H14 | Role Recruit 可视化与 AgentView | 角色卡、阶段、证据绑定 | 不伪装多 Agent 并发 |
| TODO | P2 | H15 | 自动修复循环 | failureKind -> 日志 -> 修复建议 -> 重试 | 写操作需确认 |
| TODO | P2 | H16 | 审批与审计 | Approval queue、audit log、action replay | 不静默 push/发布/发消息 |
| TODO | P2 | H17 | Release Honesty 与 README 证据 | 能力矩阵、风险、截图、APK 链接 | 不宣传未 ready 能力 |
| DEFERRED | P3 | H18 | UI Automation Connector | 实验性打开设置/浏览器/文件夹 | 不做默认第三方 App 自动控制 |
| DEFERRED | P3 | H19 | 完整 GitRuntime / Cloud Runtime | clone/pull/push/cloud heavy build | 不进入 v1 收尾范围 |

## 任务卡

### H00：Harness 任务索引维护

Priority：P0
Status：ACCEPTED

目标：

- 让本文件成为 Harness 长期计划的唯一入口。
- 后续任务变化先更新这里，再执行代码。

产出：

- 任务状态更新。
- 新增/移除任务的理由。
- 当前 P0 推荐任务。

Out of scope：

- 不写功能代码。
- 不改 runtime/provider。

验收：

- 任务索引能解释“下一步为什么做这个，而不是做别的”。

### H01：当前能力基线盘点

Priority：P0
Status：ACCEPTED

目标：

- 明确 MobileCode 当前哪些是真工具，哪些只是 UI 流程，哪些是降级能力。

Read first：

- `docs/import_phase_summarize/MobileCode 仅 “看起来调用工具” 的根源.md`
- `docs/import_phase_summarize/Agent与Harness工程、工具泛化与移动端适配技术复盘总结.md`

产出：

- 能力矩阵。
- 伪 Agent 风险说明。
- 用户可见表述建议。

Implementation evidence (2026-05-20, Codex):

- `docs/import_phase_summarize/2026-05-20-mobilecode-h01-capability-baseline.md`（本轮基线盘点与对外边界同步）
- `docs/mobilecode-capability-matrix.md`
- `docs/mobilecode-last-capability-statement.md`（本轮 last 口径的对外能力声明与不可承诺项）
- `docs/import_phase_summarize/Agent与Harness工程、工具泛化与移动端适配技术复盘总结.md`
- `docs/import_phase_summarize/MobileCode 仅 “看起来调用工具” 的根源.md`
- `docs/import_phase_summarize/2026-05-20-kimiclaw-mobile-harness-worklog.md`
- `mobile_agent/lib/services/runtime_manager.dart`
- `mobile_agent/lib/services/runtime_actions.dart`
- `mobile_agent/lib/services/runtime_placeholder_providers.dart`
- `mobile_agent/lib/services/mobile_code_helper_provider.dart`
- `mobile_agent/lib/services/external_termux_provider.dart`
- `mobile_agent/lib/services/agent_action_system.dart`
- `mobile_agent/lib/core/evidence/evidence_model.dart`
- `mobile_agent/lib/core/evidence/action_evidence_store.dart`
- `mobile_agent/lib/core/evidence/action_runner.dart`
- `mobile_agent/lib/core/git_runtime/git_runtime_controller.dart`
- `mobile_agent/lib/core/git_runtime/git_runtime_models.dart`

Remaining risks:

- `agent_action_system.dart` 与实际执行链路仍有 blocked 动作名共存，需持续与 UI 文案核对，避免“看起来可执行”误导。
- `runtime_actions.dart` 与 RuntimeManager 路径里存在 preview / fallback / blocked 混排，需要在用户对外说明中保持“已实现/降级/阻断”三色分级。
- `runtime_placeholder_providers.dart` 的 Cloud / Embedded Lite 仍为占位，不可对外标记 ready。

Codex review (2026-05-20):

- 已完成 H01 文档化交付，不改业务执行逻辑。
- 输出覆盖“已实现、降级、阻断、对外表述”四象限，且对外描述约束与风险边界已明确。
- 对外表述审核签字通过：`docs/import_phase_summarize/2026-05-20-mobilecode-h01-capability-baseline.md` 的可对外/不可对外条目与本体任务边界一致，可直接对外统一落地。
- `status` 已更新为 `ACCEPTED`，准许作为 v1 收尾前的基线决策输入。

验收：

- 对外宣传不夸大。
- 对内执行知道优先补哪里。

### H02：Action Schema 与 ActionEvidence

Priority：P0
Status：ACCEPTED

目标：

- 定义 MobileCode 内部 action 协议，让工具调用有统一输入/输出。

建议 action：

- `writeFile`
- `readFile`
- `openFile`
- `previewHtml`
- `publishPages`
- `runCommand`
- `cloneRepo`
- `linkRemoteRepo`
- `commitFiles`
- `triggerGitHubAction`
- `inspectRelease`
- `installSkill`
- `registerMcp`
- `openFolder`

Evidence 字段：

- `evidenceId`
- `actionName`
- `paramsSummary`
- `startedAt`
- `endedAt`
- `durationMs`
- `success`
- `artifactPaths`
- `urls`
- `logs`
- `exitCode`
- `failureKind`
- `recoveryActions`

Stop line：

- 本任务只定义模型和最小存储，不接 provider function call。

验收：

- 任何 UI 步骤都能引用一个 evidenceId。
- 失败 action 能表达原因和恢复动作。

Implementation evidence (2026-05-20, ccmimo):

- `mobile_agent/lib/core/evidence/evidence_model.dart` — added `MobileCodeAction` enum (initial 14 first-class action names; H03 later adds 5 trace-specific action names), `ActionRisk` enum, `ActionSchema` model, `ActionEvidence` model, `ActionFailureKind` constants, `toEvidence()` bridge.
- `mobile_agent/lib/core/evidence/action_evidence_store.dart` — in-memory `ActionEvidenceStore` with add, getById, recent, byAction, failures, clear, toJson/loadFromJson.
- `mobile_agent/test/core/evidence/action_evidence_model_test.dart` — added focused JSON, duration, failure, conversion, and store roundtrip tests.

Codex review (2026-05-20):

- Fixed a Dart compile risk by making `ActionSchema` non-const because it defaults `createdAt` with `DateTime.now()`.
- Added `paramsSummary` to `ActionSchema` so planned actions have a safe display string and do not require UI to inspect raw params.
- Ran `git diff --check`; only existing CRLF normalization warnings were reported.
- Local `flutter`/`dart` binaries were unavailable, so the focused Flutter test could not be executed locally.
- `cxspark` review was attempted but blocked because `gpt-5.3-codex-spark` is not supported by the current ChatGPT-backed Codex CLI account; no cxspark edits were made.
- `mobile_agent/test/core/evidence/action_evidence_model_test.dart` — 22 tests covering JSON roundtrip, duration computation, failure kind, factory helpers, store operations.
- `failureKind` uses stable strings (not `RuntimeTaskFailureKind` enum) to avoid core->services import cycle.
- Not wired: provider calls, UI, RuntimeManager, HomeScreen.

### H03：Agent Trace 读取 Evidence

Priority：P0
Status：ACCEPTED

目标：

- 把现有 Parse / Select tool / Call provider / Write artifact / Report in chat 从文案卡升级为证据卡。

产出：

- 步骤详情 bottom sheet 展示真实 evidence。
- 最终结果显示在步骤下方。
- 代码默认折叠，可打开编辑器。

验收：

- 用户点击任意步骤都能看到它真实做了什么。
- 没有 evidence 的步骤必须标记为 `generated-only` 或 `ui-only`。

Implementation evidence (2026-05-20, ccmimo):

- `mobile_agent/lib/core/evidence/evidence_model.dart` — added 5 trace-specific `MobileCodeAction` values: `traceParseInstruction`, `traceSelectTool`, `traceCallProvider`, `traceWriteArtifact`, `traceReportChat`. Total enum count: 19.
- `mobile_agent/lib/screens/home_screen.dart` — `_AgentTraceStep` now holds `evidenceId` (generated at creation), `startedAt`, `traceAction` (maps to `MobileCodeAction`), and cached `ActionEvidence?`. Each of the 5 trace steps gets a unique evidenceId at template creation time.
- `_setAgentRunStep` calls `_withStepEvidence` which creates/updates `ActionEvidence` on state transitions: running → in-progress evidence, done → successful evidence, failed → failed evidence.
- `_AgentTraceRow` now renders `_EvidenceChip` below the detail text when `step.evidence != null`. The chip shows `evidenceId`, `actionName`, duration, `success`/`failureKind`, artifact paths, and recovery actions.
- `_agentRunTraceTemplate` passes `traceAction` to each step, mapping parse→traceParseInstruction, select→traceSelectTool, call→traceCallProvider, write→traceWriteArtifact, report→traceReportChat.
- No changes to `_runAgentWithTrace` execution flow, `_completeAgentRunStep`, or `_cancelAgentRun` logic — evidence binding is additive via `_syncStepEvidence`.
- `mobile_agent/test/core/evidence/action_evidence_model_test.dart` — updated action count from 14 to 19; added `Trace-specific actions` group with 3 tests: factory helpers, JSON roundtrip, unknown action fallback.
- `.github/workflows/mobile-runtime-ci.yml` — added `lib/core/evidence/evidence_model.dart` to analyze step; added `test/core/evidence/action_evidence_model_test.dart` to both analyze and test steps.
- CI 证据（2026-05-20）：`Mobile Runtime CI`（`https://github.com/Harzva/mobilecode/actions/runs/26155688380`）通过；H03 证据读写链路已落地。

Remaining risks:

- `flutter analyze` and `flutter test` could not run locally (no Flutter SDK on Windows host); CI must verify.
- Evidence lifecycle is synchronous within `_setAgentRunStep`; if the step detail text changes between running→done, the `paramsSummary` in evidence reflects the final text, not the original.
- `_EvidenceChip` uses monospace font which may look different on iOS vs Android.

Codex review patch (2026-05-20):

- Fixed failed-step evidence binding: `_failAgentRunStep()` now writes `ActionEvidence.failed` through the same evidence helper as normal step transitions.
- Fixed running-state UI semantics: evidence chips now use the step state (`queued/running/success/failed`) instead of rendering every non-success evidence as red failed.
- Added step evidence bottom sheet: tapping any Agent Trace row shows evidenceId, action, state, duration, timestamps, artifact paths, URLs, logs, failureKind, and recovery suggestions.
- Added artifact extraction for the Write Artifact step so `Saved generated artifact to ...` becomes `ActionEvidence.artifactPaths`.
- Attempted cxspark read-only review, but the local Codex CLI account rejected `gpt-5.3-codex-spark`; no cxspark edits were made.
- Ran `git diff --check` on the H03 touched files; only existing CRLF normalization warnings were reported.

Codex patch (2026-05-20):

- `mobile_agent/lib/screens/home_screen.dart` — Agent Trace now writes every created/updated `ActionEvidence` into `ActionEvidenceStore` through `_withStepEvidence`, so future Logs / Activity surfaces can read the same evidence records instead of scraping UI text.
- Scope kept intentionally local: the store is in-memory for this pass; H05 can decide persistence, search, and cross-session retention.

### H04：首页减负与手机聊天化

Priority：P0
Status：ACCEPTED（principle only；2026-05-21 recovery branch does not carry the Chat first-screen boundary-card UI）

目标：

- 让首页更像手机聊天产品，而不是工程 IDE。

任务：

- 隐藏默认 Runtime 详细卡。
- 隐藏 Prompt/context 状态卡。
- 去掉无意义 Managed 状态。
- 输入框减少占位文字和高度问题。
- CPU 小状态可放顶部轻量胶囊，点击进入详情。

当前证据（2026-05-20，Codex）：

- `mobile_agent/lib/screens/home_screen.dart`
  - 已在 Chat 首屏替换为能力边界条：`已实现 / 降级 / 阻断` 及示例能力摘要，去掉原始 runtime 详细状态大卡。
  - 已在 Tools Tab 复用同一边界卡，收敛 Debug 感与可见状态噪音。

Recovery override（2026-05-21，Codex）：

- `v0.1.39` 已被确认为正确 UI 产品基线。
- `last-recover-from-v039` 不迁移 Chat 首屏能力边界大卡，也不覆盖 `v0.1.39` 的 Chat / Tools / Skills / Roles 主视觉。
- H04 在本恢复分支只保留原则：不夸大能力、不放大伪执行感；能力边界说明转移到文档与 `Tools -> Activity / Logs` 的观测入口。

验收：

- 小屏首屏不拥挤。
- Diagnostics 仍能查看详细状态。

Codex review（2026-05-20）：

- 已确认首屏已去掉高噪音 runtime 调试牌，改为 `已实现 / 降级 / 阻断` 边界条（Chat + Tools 共用）：
  - `mobile_agent/lib/screens/home_screen.dart`：`_buildCapabilityBoundaryStrip()` + `buildChatTab()` + `buildToolsTab()`。
- 已添加 `Tools` 一致性入口（并移除 ToolLab 的“能力边界”重复文本），减少聊天流首屏工程化感。
- 该验收不新增 runtime 执行路径，仍保留 `Runtime`/`Diagnostics` 通道。

Regression fix（2026-05-21，Codex）：

- 修复 `v0.1.41-last` APK 中 Chat 首屏能力边界灰色大块问题。
- 根因：`_BoundaryChip` 内部使用 `Expanded`，但父级为 `Wrap`，release 构建中触发 Flutter `ParentDataWidget` 错误并渲染为灰色错误区域。
- 修复：将 `Expanded` 移到 `Row` 布局层；窄屏时切换为垂直堆叠，保持首屏轻量、可读。

Remaining risks:

- 该任务仍依赖 `CapabilityLayer` 的静态状态定义，当前边界口径可能与实际运行时动态能力有偏差；需在 H09 统一 Connector Readiness 后精化映射。

### H05：Logs / Activity 中心

Priority：P0
Status：ACCEPTED

目标：

- 失败不是 toast，而是可搜索、可复制、可定位的日志。

日志来源：

- Model provider。
- RuntimeProvider。
- Helper daemon。
- Termux daemon。
- GitHub Pages。
- GitHub Actions。
- Repo Hub。
- Skill/MCP 装载。
- File / Preview / Publish。

验收：

- 失败步骤能跳到相关日志。
- 用户能复制失败摘要给开发者。

启动记录（2026-05-20，Codex）：

- 已新增 `H05` 启动性入口：`_ModuleAction.activityCenter`。
  - 入口挂在 `Tools` 页：`Activity / Logs`（无检索、无远程日志上传）。
  - 对接源：`ActionEvidenceStore.shared.recent(count)` 与 `ActionEvidenceStore.shared.failures()`。
  - 失败行支持一键复制 failure summary。
- 已新建最小 `Logs / Activity Center` 底部面板：
  - `mobile_agent/lib/screens/home_screen.dart`：`_ActionEvidenceCenterSheet`。
  - 支持“Recent Action Evidence”+“Failed Action Evidence”两段展示。
  - 每条失败记录可直接复制摘要并跳转到 `_showActionEvidenceSheet` 详情。
- 对外口径统一页：`docs/mobilecode-last-capability-statement.md`（已声明对外能力、降级、阻断与不可承诺项边界）。

Recovery migration（2026-05-21，Codex）：

- `last-recover-from-v039` 已将 H05 入口接入 `v0.1.39` 的 Tools 列表，不覆盖 Tools 主视觉。
- 数据源保持最小：`ActionEvidenceStore.shared.recent(count)` 与 `ActionEvidenceStore.shared.failures()`。
- 失败项支持复制摘要与跳转 evidence 详情；仍不做搜索、分类、远程日志上传或持久化查询。

简版读数评估（2026-05-20，Codex）：

- 读数体量：`_ActionEvidenceCenterSheet` 维持双列表上限各 12 条（`_maxItems = 12`）。
  - 只从内存 store 拉取，不做分页，不做远程拉取。
  - `recent` 使用 `ActionEvidenceStore.shared.recent(count)`，按 `startedAt` 倒序。
  - `failures` 使用 `ActionEvidenceStore.shared.failures()`，再过滤 `!success` 并截断 12 条。
- 可读性：
  - 每条仅保留 `actionName`、`status/failureKind`、`duration`、`Artifacts`、`URLs`，并通过 `maxLines: 1 + ellipsis` 收口超长字段，适合首屏快速扫描。
  - 失败可复制摘要（`_buildEvidenceFailureSummary`）和点击详情形成“轻量但可用”。
  - 目前不做分类、关键词检索、跨页筛选，减少上下文噪音。
- 跳转成本：
  - 失败步骤（行内按钮/行点击）到证据详情为单跳：1 次点击打开 `ActionEvidenceSheet`，保留 `Evidence ID / Action / Duration / URLs / Logs`。
  - 对应失败条目可在一屏内完成“定位 -> 复制 -> 粘贴”闭环，适合调试节奏；
  - 风险点：无搜索与分类时，用户需手动滚动以定位历史上下文。
- 下一步落地建议：
  - 若评估显示体量>30条/5分钟后仍需高频查看，下一步再拆分 `H05.1`（失败分类）与 `H05.2`（轻量筛选/时间窗）。

Codex Review（2026-05-20，ACCEPTED）：

- H05 最小版验收范围已对齐 `H05` 起始约束（仅 consume `ActionEvidenceStore` 最近记录）：
  - 入口验收：Tools 主流程新增 `Activity / Logs`，只为日志入口，不引入新执行路径。
  - 面板结构验收：`_ActionEvidenceCenterSheet` 同时展示 `Recent Action Evidence` 与 `Failed Action Evidence`，各自限定 12 条。
  - 数据源验收：Recent 使用 `ActionEvidenceStore.shared.recent(count)`，Failed 使用 `ActionEvidenceStore.shared.failures()`，不做检索或远程日志上传。
  - 失败可读性验收：每条失败记录展示 `actionName`、`status/failureKind`、`duration`、`artifact`、`urls`，行内失败摘要复制按钮已接入 `_buildEvidenceFailureSummary`。
  - 跳转验收：失败行点击行/复制按钮为同一入口，可跳到 `_showActionEvidenceSheet` 获取 evidence 详情（Evidence ID / Action / Duration / URLs / Logs）。
  - 交付边界：保持“体量受限 + 单页快速扫描”，无关键词检索、分类筛选、持久化查询链路。
- 依据本轮简版读数评估：该入口满足“列表体量 12x2 段 + 一键复制 + 一跳到详情”闭环，可作为 v1 最小日志面板验收通过点。
- 仍留风险：ActionEvidenceStore 为内存态，跨进程/跨启动时效不可见；不在本任务范围。

### H06：ActionRunner 最小实现

Priority：P1
Status：ACCEPTED

目标：

- 让内部 action 可以被统一执行。

第一批动作：

- `writeFile`
- `readFile`
- `previewHtml`

Stop line：

- 不开放任意 shell。
- `runCommand` 只走 RuntimeProvider 安全边界。

验收：

- action 执行后必有 ActionEvidence。

Implementation evidence (2026-05-20, Codex):

- `mobile_agent/lib/core/evidence/action_runner.dart` — added a minimal structured `ActionRunner` with `ActionRunnerResult`.
- Supported actions:
  - `writeFile` writes only inside the configured workspace and records artifact path/bytes.
  - `readFile` reads only inside the configured workspace, returns text, and stores a bounded metadata preview.
  - `previewHtml` accepts either an existing workspace HTML path or inline HTML, prepares a file URL, and records artifact path/preview URL.
- Safety:
  - rejects paths outside the workspace with `cwdOutsideWorkspace`.
  - fails closed for unsupported actions, including `runCommand`, with `commandBlocked`.
  - does not execute shell commands or talk to external services.
- `mobile_agent/test/core/evidence/action_runner_test.dart` — added focused tests for write/read/preview, outside-workspace rejection, and unsupported-action blocking.
- `.github/workflows/mobile-runtime-ci.yml` — added `action_evidence_store.dart`, `action_runner.dart`, and `action_runner_test.dart` to the scoped analyze/test gate.
- CI 证据（2026-05-20）：`Mobile Runtime CI`（`https://github.com/Harzva/mobilecode/actions/runs/26155688380`）通过；H06 运行最小 ActionRunner 能被 CI 覆盖（包含失败路径回归）。

### H07：JSON Action Fallback

Priority：P1
Status：TODO

目标：

- 对不支持 function call 的 provider，要求模型输出 JSON action plan。

验收：

- JSON 可解析时走 ActionRunner。
- JSON 不可解析时降级普通生成，并明确标记。

Experiment Log Note（2026-05-21）：

- H07 是 H08 的降级兄弟任务：provider 不支持原生 tool call 时，才使用 JSON action plan。
- JSON plan 仍必须经过 `ActionRunner`，不能把普通模型文本伪装成真实工具执行。

### H08：Provider ToolCall Adapter

Priority：P1
Status：REVIEW_NEEDED

目标：

- 支持 provider-native tool call，并输出统一 MobileCode action。
- 第一阶段先落 DeepSeek/OpenAI-compatible adapter；Anthropic tool_use 后续补齐。

Stop line：

- 不把任一 provider 格式写死到业务层。

验收：

- provider adapter 输出统一 MobileCode action。
- DeepSeek/OpenAI-compatible `tool_calls` 能解析为 `writeFile/readFile/previewHtml`，并统一交给 `ActionRunner`。
- `report_result` 只作为最终报告工具，不执行设备、shell、Git 或网络动作。
- provider 不返回 `tool_calls` 时必须标记为 generated-only fallback，不能伪装成真实工具调用。

Experiment Log Note（2026-05-21）：

- H08 是从 `single-shot generation with executable evidence` 进入 `multi-step tool-calling agent loop` 的关键门。
- 最小安全范围先只开放 `write_file`、`read_file`、`preview_html`、`report_result`，不开放 shell、Git push、发布、远程日志或任意命令。

Implementation Note（2026-05-21）：

- Added DeepSeek provider preset without making MobileCode DeepSeek-only.
- Added a provider-neutral OpenAI-compatible tool-call adapter and focused unit tests for tool schema, non-streaming tool calls, streaming fragments, unsupported DeepSeek experiment detection, and tool observation messages.
- Wired Agent runs to try provider-native tool calls first for DeepSeek/OpenAI-compatible providers, then fall back to existing generated-only artifact persistence when no `tool_calls` are returned.
- Remaining risks: no local Flutter/Dart on PATH in this workstation; Anthropic adapter and live DeepSeek API run are not included in this first pass.

### H09：Connector Readiness 模型

Priority：P1
Status：TODO

目标：

- 把 GitHub、Termux、Helper、Cloud、Lark、Storage 的状态统一。

字段：

- `connected`
- `authRequired`
- `missingPermission`
- `degraded`
- `offline`
- `capabilities`
- `lastCheckedAt`
- `recoveryActions`

验收：

- 用户知道为什么不能 clone、build、publish。

### H10：GitHub-first 轻量工作区

Priority：P1
Status：TODO

目标：

- 手机轻量，重任务交给 GitHub。

任务：

- Repo chat 显示绑定仓库、workspace mode、Pages、Actions。
- API-backed file read/write/commit。
- Release artifact 查看和下载。
- Actions trigger、logs、artifact。
- 本地无 git 时降级 Remote-linked。
- Termux/Helper 有 git 时走真实 clone/push。

验收：

- 不安装 Termux 也能进行 GitHub API 工作流。

### H11：用户可见共享目录

Priority：P1
Status：TODO

目标：

- 用户知道项目和产物在手机哪里。

建议目录：

```text
Documents/MobileCode/
  projects/
  exports/
  artifacts/
  logs/
```

验收：

- 用户可以用系统文件管理器找到工程。
- App 私有路径与共享路径区别明确。

### H12：Runtime / Termux / Helper 诊断

Priority：P1
Status：TODO

目标：

- 把 Termux:API、Termux daemon、Helper daemon、git、workspace 检测说清楚。

验收：

- 外部 Termux 有 git 时可以真实 clone。
- 无 git 时降级 Remote-linked，不报死错误。

### H13：Rules / Memory / Role / Skill 分层

Priority：P1
Status：TODO

定义：

- `Memory`：用户长期偏好和经验。
- `Rules`：当前 App 或项目必须遵守的硬规则，类似 `CLAUDE.md / AGENTS.md`。
- `Role`：任务人格、职责和审查标准。
- `Skill`：可复用能力包和提示词动作。
- `MCP`：外部工具服务器配置。

验收：

- 执行前上下文来源可解释。
- 用户确认后才写入 Memory / Rules。

### H14：Role Recruit 可视化与 AgentView

Priority：P1
Status：TODO

目标：

- 让角色招募不只是头像和名字，而是绑定阶段、职责和 action evidence。

Read first：

- `docs/import_phase_summarize/2026-05-20-agent-visualization-reference.md`
- `docs/import_phase_summarize/assets/agent_visualization/README.md`

任务：

- Role Recruit 使用 MobileCode 自有角色命名系统。
- 角色卡显示当前阶段、当前 action、状态和进度。
- AgentView 展示角色定义、职责、guardrails、当前 action、最近 evidence。
- 无 evidence 时显示 `待接手`，不要伪装正在执行。

建议内置角色：

- 澄野 / Planner。
- 绫构 / UI Designer。
- 铸岚 / Builder。
- 灯塔 / Runtime Reviewer。
- 星邮 / Publisher。
- 砚修 / Recovery Reviewer。
- 栈灵 / Repo Analyst。
- 织忆 / Memory Curator。

Stop line：

- 不使用知名动漫 IP 角色名。
- 不复制第三方 UI 和头像。
- 不宣传为真实多 Agent 并发。

验收：

- 点击角色卡能看到角色定义和当前证据。
- 角色卡状态来自真实 action evidence。

### H15：自动修复循环

Priority：P2
Status：TODO

目标：

- 从一次性生成走向真正 agent loop。

流程：

```text
执行
  -> 失败
  -> 读取 evidence/logs
  -> failureKind 分类
  -> 生成修复 action
  -> 用户确认
  -> 重试
```

验收：

- 失败不是终点，而是进入可解释修复流程。

Experiment Log Note（2026-05-21）：

- H15 依赖 H05/H06/H08：必须先有 evidence、ActionRunner 和 tool-call/observation 入口，才谈得上自动修复循环。
- 第一版必须保留用户确认，不允许失败后静默写入、静默发布或静默执行高风险操作。

### H16：审批与审计

Priority：P2
Status：TODO

目标：

- 对敏感动作建立 human approval。

敏感动作：

- publish Pages。
- commit / push。
- create repo。
- install Skill。
- register MCP。
- run command。
- send Lark/GitHub message。

验收：

- 写操作有审批记录。
- 审计日志不保存 token 明文。

### H17：Release Honesty 与 README 证据

Priority：P2
Status：TODO

目标：

- 对外宣传和实际能力一致。

产出：

- Capability matrix。
- Risk register。
- README 首屏截图。
- APK/Release 链接。
- GitHub Pages demo。

验收：

- 不宣传未 ready 的能力。

### H18：UI Automation Connector

Priority：P3
Status：DEFERRED

目标：

- 有限借鉴 KimiClaw。

可做：

- 打开系统设置。
- 打开浏览器 URL。
- 打开文件夹。
- 辅助授权流程。

不做：

- 默认控制微信/Kimi/飞书聊天。
- 自动点击敏感权限。
- 后台静默操作第三方 App。

### H19：完整 GitRuntime / Cloud Runtime

Priority：P3
Status：DEFERRED

目标：

- 作为 1.0 后重能力探索。

暂缓原因：

- v1 当前更需要 evidence、日志、连接器和 GitHub-first 闭环。
- 完整 GitRuntime 或 Cloud Runtime 成本高，容易拖慢收尾。

## 推荐执行顺序

第一批 P0，解决可信度（v1 收尾）：

1. H04 首页减负与手机聊天化（先让首屏更像手机会话与最小信息承载）。
2. H05 Logs / Activity 中心（最小版）。

V1 收尾核心路径以 H04/H05 的最小版为准（已在本轮验收通过），后续如需再扩展可按 H05 增强子任务与 H09/H10 打散推进；H00 作为路线治理任务已完成。

第二批 P1，解决执行闭环：

1. H06 ActionRunner 最小实现（已验收）。
2. H07 JSON Action Fallback。
3. H08 Provider ToolCall Adapter。
4. H09 Connector Readiness 模型。
5. H10 GitHub-first 轻量工作区。

第三批 P1/P2，解决长期上下文和治理：

1. H11 用户可见共享目录。
2. H12 Runtime / Termux / Helper 诊断。
3. H13 Rules / Memory / Role / Skill 分层。
4. H14 Role Recruit 可视化与 AgentView。
5. H15 自动修复循环。
6. H16 审批与审计。
7. H17 Release Honesty 与 README 证据。

## 全局禁止线

- 不新增绕过 `RuntimeManager` 的执行路径。
- 不新增绕过 `ActionRunner` 的长期工具路径。
- 不用任意 shell git 字符串实现长期 Git 能力。
- 不静默执行 blocked `git push`、创建 PR、发送 Lark/WeChat/GitHub 消息。
- 不把 blocked private clone、blocked pull、blocked merge、blocked rebase、feature-flagged push beta 宣称为 ready。
- 不在日志、workspace、audit 中保存 token 或 secret 明文。
- 不把普通文本生成伪装成真实工具调用。
- 不把无障碍自动化作为 v1 核心依赖。

## v1 停止扩张线

满足以下条件，就停止继续扩底层能力，进入发布打磨：

- 网页生成 -> 代码文件 -> 编辑器打开 -> WebView 预览 -> 浏览器打开 -> GitHub Pages 发布闭环稳定。
- Repo Hub 可公开搜索、登录管理、Release/Skill/MCP 合理筛选。
- Runtime 不可用时能清楚降级到 GitHub API / WebViewOnly。
- 每个关键步骤都有 evidence。
- 失败时能看到 failureKind、日志和恢复建议。
- 首页不再像工程调试面板。
- README 清楚说明：Harness 运行在手机上，重任务交给 GitHub/Termux/Helper/Cloud。

## 全局完成标准

每个任务完成后，必须留下这些证据：

- 任务状态更新。
- 涉及文件路径。
- 真实改动说明。
- 验证方式。
- 未验证原因。
- 风险和 deferred 项。

## 当前最推荐下一步

P2：按本轮 H05 简版读数评估结果，决定是否拆分 H05 增强子任务（分类入口、时间窗/轻量筛选），并给出最小代价实施清单。

理由：

- H05 让现有证据链能转化为可定位、可复制、可复现的轻量日志入口。
- 这一步不引入新执行路径，仅消费既有 `ActionEvidenceStore` 最近记录。
- 失败步骤可跳转到详情，方便现场修复而不是堆积文案回放。
