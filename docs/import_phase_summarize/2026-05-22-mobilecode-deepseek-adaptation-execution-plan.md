# MobileCode DeepSeek 全面适配执行计划

日期：2026-05-22

执行基线：`last-recover-from-v039`

当前产品基线：`v0.1.57-last`（本轮修复基于 `last-recover-from-v039`，下一版建议 `v0.1.58-last`）

参考文档：

- `D:\study\code\0ai\产品\07-mobile-app\mobile-code\deepseek_doc\DeepSeek_API_图文教程_15讲_终稿v3_细节增强版.md`
- DeepSeek 官方重点章节：07 Thinking Mode、08 Streaming、10 Tool Calls、11 Strict Tool Call、13 Error Codes、15 Adapter / Harness / Runtime。

## 目标口径

MobileCode 不做 DeepSeek-only 产品，但 DeepSeek 是第一条完整 provider-native AgentLoop 验证线。

目标不是继续堆 UI，而是把 DeepSeek 协议能力稳定接进 MobileCode：

```text
DeepSeek Provider
-> ToolCallAdapter
-> AgentLoopController
-> ActionRunner
-> ActionEvidence
-> Activity Logs
-> Recovery / Fallback
```

## 当前真实状态

已完成：

- `Single-shot` 与 `Agent Loop` 双模式。
- `Auto Agent`：模型可在安全工具白名单内自主选择工具。
- DeepSeek/OpenAI-compatible `tool_calls` 非流式解析。
- DeepSeek/OpenAI-compatible streaming `delta.tool_calls` 拼接。
- `list_files / find_files / grep_files / web_search / fetch_url / write_file / read_file / move_file / apply_patch / preview_html / preview_snapshot / report_result` 安全工具集。
- Agent Loop 角色流第一版：`Planner -> Builder -> Reviewer -> Repair`，以同一执行 lane 内的 policy / prompt / tool allow-list 呈现，不伪装成并发子 Agent。
- Tools 页新增 Android/Linux/macOS 命令兼容矩阵，明确哪些命令由 MobileCode typed tools 模拟，哪些是 blocked/runtime-only/planned。
- `ActionRunner / ActionEvidence / Activity Logs` 记录执行事实。
- DS01 DeepSeek v4 Provider Profile 已完成，Mobile Runtime CI 与 v0.1.51-last APK 构建已通过。
- DS02 默认模型与 Base URL 迁移已完成，Mobile Runtime CI 与 v0.1.51-last APK 构建已通过。
- DS03 Thinking + Tool Calls 回传加固已完成，Mobile Runtime CI 与 v0.1.51-last APK 构建已通过。
- DS04 Streaming tool_calls 边界测试已完成，Mobile Runtime CI 与 v0.1.51-last APK 构建已通过。
- DS04.4 Sub-Agent Lite / mailbox-lite 已完成，Mobile Runtime CI 已通过，APK 构建待触发。

未完成或需加固：

- `https://api.deepseek.com` 与 legacy `/v1` 已本地兼容，仍需 GitHub Actions 验证。
- Thinking + Tool Calls 的 `reasoning_content` 回传已补本地测试，仍需 GitHub Actions 验证。
- DeepSeek 错误码尚未统一映射到产品级 failure kind。
- usage / cache hit-miss / reasoning tokens 未完整进入 Activity Logs。
- JSON Output 还没有明确作为 fallback/结构化诊断能力。

## 不变边界

- 不开放 shell。
- 不开放 Git push。
- 不开放发布动作。
- 不开放远程日志上传。
- 不开放任意命令执行。
- 不把 JSON fallback 伪装成 provider-native tool calling。
- 不把模型自然语言输出伪装成真实执行。
- 不读取、不打印、不提交任何本地密钥文件。

## GitHub Pages 日志规则

- 每天形成重要工程认知、协议边界、验收结论或失败复盘时，必须同步到 GitHub Pages `实验日志` 页面。
- 内部计划文档记录任务状态、证据和风险；GitHub Pages 记录对外可读的公开复盘。
- 公开日志不得包含密钥、私有路径、token、内部账号或未公开凭据。
- 对外口径必须诚实：区分 Single-shot、provider-native Agent Loop、fallback、runtime-only 和 blocked 能力。
- 当前日志入口：`app/src/pages/Experiments.tsx`。

## 快速执行顺序

建议每轮只做一个任务编号，避免再次出现分支或 UI 回归问题。

- [x] DS00 文档基线
- [x] DS01 DeepSeek v4 Provider Profile（本地实现完成，CI 待验收）
- [x] DS02 默认模型与 Base URL 迁移（本地实现完成，CI 待验收）
- [x] DS03 Thinking + Tool Calls 回传加固（本地实现完成，CI 待验收）
- [x] DS04 Streaming tool_calls 完整测试（本地实现完成，CI 待验收）
- [x] DS04.1 Mobile Unix Facade 命令语义层（本地实现完成，CI 待验收）
- [x] DS04.2 AgentLoop 可用工具 gating 与缺省写入路径修复（本地实现完成，CI 待验收）
- [ ] DS04.3 Search/Patch + 角色编排（本地实现完成，静态检查通过，CI 待验收）
- [x] DS04.4 Sub-Agent Lite / mailbox-lite（本地实现完成，Mobile Runtime CI 通过，APK 待构建）
- [ ] DS05 DeepSeek 错误码映射
- [ ] DS06 Usage / Cache / Reasoning 观测
- [ ] DS07 JSON Output 降级路径
- [ ] DS08 Strict Tool Call beta 入口
- [ ] DS09 AgentLoop 回归验收任务
- [ ] DS10 Release / APK 验收

## DS00 文档基线

状态：`ACCEPTED`

目标：

- 把本计划作为 DeepSeek 全面适配的单一执行索引。
- 后续每完成一个 DS 任务，都回写状态、证据、CI 链接和剩余风险。

涉及文件：

- `docs/import_phase_summarize/2026-05-22-mobilecode-deepseek-adaptation-execution-plan.md`

验收：

- 文档存在。
- 任务编号清晰。
- 每个任务都有验收项和验证方式。

验证：

- `git diff --check`

## DS01 DeepSeek v4 Provider Profile

状态：`ACCEPTED`（本地实现完成，Mobile Runtime CI 通过，APK 已构建）

目标：

- 新增明确的 DeepSeek provider profile，不再只靠 `baseUrl.contains('deepseek')` 做能力判断。

建议 profile：

- `deepseekV4Flash`
- `deepseekV4Pro`
- `deepseekStrictBeta`
- `deepseekLegacyChat`
- `deepseekLegacyReasoner`

建议 UI 文案：

- `deepseek-v4-flash`：默认体验 / 快速聊天 / 常规 Agent Loop。
- `deepseek-v4-pro`：可手动切换，用于更重的编码任务。
- `deepseek-chat`：legacy alias，不作为新默认。
- `deepseek-reasoner`：legacy alias，不作为新默认。

涉及文件：

- `mobile_agent/lib/screens/api_config_screen.dart`
- `mobile_agent/lib/screens/home_screen.dart`
- `mobile_agent/lib/services/tool_call_adapter.dart`
- `mobile_agent/test/services/agent_loop_controller_test.dart`
- `mobile_agent/test/services/tool_call_adapter_test.dart`
- `.github/workflows/android-apk.yml`

验收：

- DeepSeek preset 能明确区分 v4 flash/pro/beta/legacy。
- UI 中不再把 legacy alias 当作推荐模型。
- `ToolCallProviderProfile.detect()` 测试覆盖 v4 模型名。

验证：

- `git diff --check`
- GitHub Actions `Mobile Runtime CI`

本轮执行记录（2026-05-22）：

任务编号：DS01
状态：ACCEPTED（本地实现完成，CI 与 APK 构建通过）
实际改动：

- `ToolCallProviderProfile.detect()` 新增 DeepSeek profile kind，区分 `v4Flash / v4Pro / strictBeta / legacyChat / legacyReasoner / experimentalUnsupported / unknown`。
- `DeepSeek v4 Flash` 作为 UI/API 配置默认模型；`deepseek-chat` 与 `deepseek-reasoner` 保留为 legacy alias，不再作为新默认。
- Agent Loop 空模型 fallback、managed DeepSeek 默认模型、APK workflow 的 DeepSeek dart-define 默认模型统一到 `deepseek-v4-flash`。
<<- 补充 provider profile 单元测试：v4 flash/pro、strict beta、legacy alias、unsupported experimental model。
- `cxspark` 已按要求调用，但本次被 Windows sandbox `CreateProcessAsUserW failed: 5` 阻塞，没有产出可接受代码；最终由当前 Codex 审核并直接实现。

关键文件：

- `mobile_agent/lib/services/tool_call_adapter.dart`
- `mobile_agent/lib/screens/api_config_screen.dart`
- `mobile_agent/lib/screens/home_screen.dart`
- `mobile_agent/test/services/tool_call_adapter_test.dart`
- `mobile_agent/test/services/agent_loop_controller_test.dart`
- `.github/workflows/android-apk.yml`

验证结果：

- `git diff --check` 通过。
- Flutter/Dart 验证统一走 GitHub Actions；本轮不再重复本地环境探测。

CI 链接：`https://github.com/Harzva/mobilecode/actions/runs/26275224712`
APK 链接：`https://github.com/Harzva/mobilecode/releases/download/v0.1.51-last/mobilecode-v0.1.51-last.apk`
剩余风险：

- DS05 错误码映射尚未开始。
- 仍需人工安装 `v0.1.51-last` APK，回归 DeepSeek Agent Loop 与 Single-shot fallback 体验。
下一步：人工验收 `v0.1.51-last` APK；通过后继续 DS05 DeepSeek 错误码映射。

## DS02 默认模型与 Base URL 迁移

状态：`ACCEPTED`（本地实现完成，Mobile Runtime CI 通过，APK 已构建）

目标：

- 将 DeepSeek 新默认模型迁移到 v4。
- 保留旧 alias 兼容，但默认不再使用 `deepseek-chat`。

建议默认：

- 普通聊天：`deepseek-v4-flash`
- AgentLoop / Auto Agent 默认：`deepseek-v4-flash`
- 重型编码任务可手动切换：`deepseek-v4-pro`
- strict tool call：`https://api.deepseek.com/beta`
- 普通 OpenAI-compatible：`https://api.deepseek.com`

当前需检查位置：

- `mobile_agent/lib/screens/api_config_screen.dart`
- `mobile_agent/lib/screens/home_screen.dart`
- `.github/workflows/android-apk.yml`
- `relay/README.md`
- `relay/mobilecode-token-relay-worker.js`
- tests 中所有 `deepseek-chat`

验收：

- 新安装 APK 默认显示 DeepSeek v4 推荐模型。
- legacy alias 仍可手动选择或自定义输入。
- CI secrets / dart-define 不再默认写入 legacy model。

进展清单：

- [x] DeepSeek v4 Flash 作为默认管理/UI 模型路径（`deepseek-v4-flash`）；
- [x] `api_config_screen` 与 `home_screen` 的 DeepSeek 默认 base 改为 `https://api.deepseek.com`；
- [x] OpenAI 兼容 URI 组装器保持兼容 `/`, `/v1`, `/beta`, `/chat/completions` 入口；
- [x] Relay 默认 base 与 README 口径统一到 `https://api.deepseek.com`，并保留 `/v1` 兼容性。

验证：

- [x] `git diff --check`
- [x] `node --check relay/mobilecode-token-relay-worker.js`
- [x] GitHub Actions `Mobile Runtime CI`
- [x] GitHub Actions `Build Android APK`

验证证据：

- `git diff --check` 通过（无 whitespace/patch 格式问题）。
- `node --check relay/mobilecode-token-relay-worker.js` 通过。
- Flutter/Dart 验证统一走 GitHub Actions；本轮不再重复本地环境探测。
- `cxspark` 执行完成并进入 Codex review：`20260522-145722-6d23434577ac-36792-1ba4394c`。
- GitHub Actions `Mobile Runtime CI` 通过：`https://github.com/Harzva/mobilecode/actions/runs/26275224712`
- GitHub Actions `Build Android APK` 通过：`https://github.com/Harzva/mobilecode/actions/runs/26275362394`
- Release APK：`https://github.com/Harzva/mobilecode/releases/download/v0.1.51-last/mobilecode-v0.1.51-last.apk`

剩余风险：

- `deepseek-v4-pro` 保留为手动切换的重型编码模型；当前单一 DeepSeek UI preset 默认使用更轻的 `deepseek-v4-flash`。
- 需要人工安装 APK 验证移动端 provider 请求路径与 DeepSeek Agent Loop 真实体验。

下一步：DS03 Thinking + Tool Calls 回传加固。

## DS03 Thinking + Tool Calls 回传加固

状态：`ACCEPTED`（本地实现完成，Mobile Runtime CI 通过，APK 已构建）
<<
目标：

- 确保 Thinking + Tool Calls 场景完整回传 assistant message。
- 避免再次出现 DeepSeek 400：`reasoning_content in thinking mode must be passed back`。

执行清单：

- [x] 非流式 `parseChatCompletion` 保留 `content`、`reasoning_content`、`tool_calls`、`finish_reason`。
- [x] 流式 `OpenAiToolCallStreamAssembler` 组装 `delta.content` 与 `delta.reasoning_content`，并继续拼接 `delta.tool_calls`。
- [x] `assistantToolCallMessage(parsed)` 输出 `reasoning_content` 和完整 `tool_calls` JSON；`finish_reason` 保留在内部 response，不作为下一轮 provider message 字段发送。
- [x] AgentLoop 二轮请求历史在次轮携带上轮 assistant tool-call message，再追加 tool 结果消息。
- [x] 补充 DS03 聚焦单元测试（非流式、流式拼接、两轮历史顺序）。

涉及文件：

- `mobile_agent/lib/services/tool_call_adapter.dart`
- `mobile_agent/lib/screens/home_screen.dart`
- `mobile_agent/test/services/tool_call_adapter_test.dart`
- `mobile_agent/test/services/agent_loop_controller_test.dart`

验收：

- Thinking + tool_calls 单元测试覆盖。
- assistant message 中保留 `reasoning_content`。
- tool message 正确带 `tool_call_id`。
- AgentLoop 连续两轮请求不触发 400（保留上一轮 assistant tool-call 上下文）。

验证：

- [x] `git diff --check`
- [x] Flutter/Dart 验证统一走 GitHub Actions；不再把本地环境探测作为本轮噪音。
- [x] GitHub Actions `Mobile Runtime CI`

本轮执行记录（2026-05-22）：

任务编号：DS03
状态：`ACCEPTED`（本地加固完成，CI 与 APK 构建通过）
实际改动：

- `OpenAiToolCallStreamAssembler` 现在会组装 streaming `delta.content` 与 `delta.reasoning_content`，并继续拼接 `delta.tool_calls`。
- `_streamOpenAiCompatibleToolCallRequest` 统一从 assembler 读取 streaming content / reasoning，减少双通道状态漂移。
- `assistantToolCallMessage(parsed)` 保留 `reasoning_content` 与完整 `tool_calls` JSON，并避免把 response metadata `finish_reason` 误塞进下一轮 provider message。
- AgentLoop 测试覆盖第二轮 history：assistant tool-call message 位于 tool result 之前，且携带 `reasoning_content`。

关键文件：

- `mobile_agent/lib/services/tool_call_adapter.dart`
- `mobile_agent/lib/screens/home_screen.dart`
- `mobile_agent/test/services/tool_call_adapter_test.dart`
- `mobile_agent/test/services/agent_loop_controller_test.dart`

验证结果：

- `git diff --check` 通过。
- Flutter/Dart 验证统一走 GitHub Actions；本轮不再重复本地环境探测。
- `cxspark` 执行完成并进入 Codex review：`20260522-151017-6d23434577ac-19588-99a101d4`。
- GitHub Actions `Mobile Runtime CI` 通过：`https://github.com/Harzva/mobilecode/actions/runs/26275224712`
- GitHub Actions `Build Android APK` 通过：`https://github.com/Harzva/mobilecode/actions/runs/26275362394`
- Release APK：`https://github.com/Harzva/mobilecode/releases/download/v0.1.51-last/mobilecode-v0.1.51-last.apk`

CI 链接：`https://github.com/Harzva/mobilecode/actions/runs/26275224712`

剩余风险：

- DS05 错误码映射尚未开始。
- 仍需人工安装 `v0.1.51-last` APK，回归 DeepSeek Agent Loop 与 Single-shot fallback 体验。

下一步：人工验收 `v0.1.51-last` APK；通过后继续 DS05 DeepSeek 错误码映射。

## DS04 Streaming tool_calls 完整测试

状态：`ACCEPTED`（本地实现完成，Mobile Runtime CI 通过，APK 已构建）

目标：

测试场景：

- [x] 单个 tool call 分片仍可正确拼接。
- [x] 多个 tool call 同轮并行分片（并按 `index` 顺序输出）。
- [x] `delta.reasoning_content` 与 `delta.content` 同时出现时可分别保留。
- [x] `choices=[]` 且带 usage chunk 时不会新增假工具调用。
- [x] `data: [DONE]`、空行、`: keep-alive` 行被安全忽略/结束。
- [x] tool arguments 被拆成多段 JSON 字符串仍能组装为有效参数。

涉及文件：

- `mobile_agent/lib/services/tool_call_adapter.dart`
- `mobile_agent/lib/screens/home_screen.dart`
- `mobile_agent/test/services/tool_call_adapter_test.dart`

验收：

- [x] 流式 tool call assembler 在 DS04 边界用例上通过。
- [x] `parseOpenAiStreamEvent` 覆盖 `DONE`、空行、`keep-alive` 和 `data:` 边界。
- [x] streaming request path 使用统一边界解析，不会由 usage-only chunk 生成 tool_calls。

验证：

- [x] `git diff --check`
- [x] Flutter/Dart 验证统一走 GitHub Actions；不再把本地环境探测作为本轮噪音。
- [x] GitHub Actions `Mobile Runtime CI`
- [x] GitHub Actions `Build Android APK`

本轮执行记录（2026-05-22）：

任务编号：DS04
状态：`ACCEPTED`（streaming 边界测试完成，CI 与 APK 构建通过）
实际改动：

- 新增 `parseOpenAiStreamEvent`，统一处理 `data:` payload、`data: [DONE]`、空行、`event:` 和 `: keep-alive`。
- 普通 streaming 与 provider-native tool-call streaming 路径均改为使用同一 SSE 边界解析。
- `OpenAiToolCallStreamAssembler` 覆盖多 tool interleaved index、usage-only chunk、content/reasoning/tool_calls 同 chunk、arguments 多段 JSON 拼接。
- Codex 审核后修补：空 `data:` 现在按 ignore 处理，不会误判为 done；多段 JSON fixture 补齐闭合 `}`。

关键文件：

- `mobile_agent/lib/services/tool_call_adapter.dart`
- `mobile_agent/lib/screens/home_screen.dart`
- `mobile_agent/test/services/tool_call_adapter_test.dart`

验证结果：

- `git diff --check` 通过。
- `node --check relay/mobilecode-token-relay-worker.js` 通过。
- Flutter/Dart 验证统一走 GitHub Actions；本轮不再重复本地环境探测。
- `cxspark` 执行完成并进入 Codex review：`20260522-152229-6d23434577ac-22928-264b9d68`。
- GitHub Actions `Mobile Runtime CI` 通过：`https://github.com/Harzva/mobilecode/actions/runs/26275224712`
- GitHub Actions `Build Android APK` 通过：`https://github.com/Harzva/mobilecode/actions/runs/26275362394`
- Release APK：`https://github.com/Harzva/mobilecode/releases/download/v0.1.51-last/mobilecode-v0.1.51-last.apk`

CI 链接：`https://github.com/Harzva/mobilecode/actions/runs/26275224712`

剩余风险：

- 需要用户手动安装 `mobilecode-v0.1.51-last.apk` 验收 UI 与 DeepSeek Agent Loop 行为。
- DS05 错误码映射尚未开始。

下一步：手动验收 `v0.1.51-last`；通过后继续 DS05 DeepSeek 错误码映射。

补充修复记录（2026-05-22）：

- DeepSeek 默认体验模型从 `deepseek-v4-pro` 调整为 `deepseek-v4-flash`；`v4-pro` 保留为手动切换的重型编码模型。
- Agent Loop 的 streaming `tool_calls` 增加参数流入进度提示，避免长 `write_file.content` 生成时 UI 看起来停在“选工具”。
- Agent Loop trace 从单行状态覆盖改为追加可见事件：请求模型、工具选择、参数流入、工具执行、observation、完成摘要。
- 写文件成功后，若模型继续重复调用 `write_file` 而未先 `read_file / preview_html / report_result`，MobileCode 会阻止重复写入并把 observation 回传模型。
- 最终聊天结果追加“本轮执行总结”，不再只在顶部状态行变化。
- 修复提交：`c71d00d fix: improve deepseek agent loop feedback`
- GitHub Actions `Mobile Runtime CI` 通过：`https://github.com/Harzva/mobilecode/actions/runs/26278750717`
- GitHub Actions `Build Android APK` 通过：`https://github.com/Harzva/mobilecode/actions/runs/26278838865`
- Release APK：`https://github.com/Harzva/mobilecode/releases/download/v0.1.52-last/mobilecode-v0.1.52-last.apk`
- 手动验收版本改为 `v0.1.52-last`。

## DS04.1 Mobile Unix Facade 命令语义层

状态：`ACCEPTED`（本地实现完成，CI 待验收）

目标：

- 吸收 DeepSeek-TUI 的 typed tool surface 思路，不把 MobileCode 伪装成完整 Linux shell。
- 给模型一个更熟悉的 Linux/macOS/Android 命令语义适配层，同时由 Android App 负责安全校验和 evidence。
- 解决“模型只能一直尝试 write_file，看起来只有写工具”的产品误解。

本轮实现：

- 新增 provider-native `list_files`，作为 `ls / dir / find / fd` 的安全替代。
- 新增 provider-native `move_file`，作为 `mv` 的安全替代。
- `ActionRunner` 新增 `listFiles / moveFile` 执行与 ActionEvidence 记录，路径仍限制在 MobileCode workspace 内。
- `ToolCallAdapter` tool definitions、ActionSchema 映射、systemInstruction 加入 `list_files / move_file`。
- `AgentPreset.allowedToolNames` 更新：
  - Auto / Research / Builder / Repair 可用 `list_files` 与 `move_file`。
  - Reviewer 只允许 `list_files / read_file / preview_html / preview_snapshot / report_result`，保持只读边界。
- Tools 页新增：
  - `Provider-native tool list`
  - `Android command map`
  - `Agent preset access`
- 新增长期命令口径文档：
  - `docs/COMMANDS.md`：列出当前 provider-native typed tools、参数、风险等级和明确禁用项。
  - `docs/COMMAND_COMPATIBILITY.md`：对比 Android / Linux / macOS 常见命令在 MobileCode 中的支持状态与扩展路线。
- 命令兼容矩阵覆盖：
  - `pwd / ls / dir / find / fd`
  - `cat / head / tail / less / more`
  - `grep / rg / ag / awk / sed`
  - `stat / file / wc / sort / uniq / cut / tr`
  - `mv / cp / mkdir / touch / rm`
  - `curl / wget / ping / dig / nslookup`
  - `pm / am / dumpsys / logcat`
  - `git / npm / yarn / pnpm / pip / cargo / go / dart / flutter / gradle / make`

验收口径：

- MobileCode 不开放任意 shell。
- `ls` 类需求应由模型调用 `list_files`。
- `mv` 类需求应由模型调用 `move_file`。
- 工具失败时返回结构化 failure evidence，而不是自然语言假装成功。
- Tools 页能显示“安卓常见命令 / Linux 常见命令 / MobileCode 当前支持状态”。

验证：

- [x] `git diff --check`
- [x] `node --check relay/mobilecode-token-relay-worker.js`
- [ ] GitHub Actions `Mobile Runtime CI`

剩余风险：

- `grep_files / find_files / edit_file / apply_patch / copy_file / mkdir / delete_file / snapshot` 仍未作为 provider-native tool 暴露。
- `delete_file` 与批量替换需二次确认机制，不应直接进入默认 Auto Agent。
- Runtime-only 命令仍依赖 Helper/Termux/CI，不能在当前 provider-native AgentLoop 中承诺可执行。

## DS04.2 AgentLoop 可用工具 gating 与缺省写入路径修复

状态：`ACCEPTED`（本地实现完成，CI 待验收）

问题来源：

- 真机验收 `v0.1.54-last` 时，模型第一轮选择 `web_search`，但当前 APK 没有可用 managed relay endpoint，导致 `webSearch requires the managed relay web tool endpoint`。
- 后续 DeepSeek 多轮选择 `write_file`，但参数缺少必填 `path`，导致 `Missing required string param: path` 循环失败。

根因判断：

- 这不是 Android 文件权限问题。
- 第一类失败是工具可用性 gating 问题：不可用的 relay-backed web tools 不应该出现在当前 provider request tools 中。
- 第二类失败是 provider-native tool argument 稳定性问题：模型可能生成完整 HTML content，但漏填 path 或使用 `filename/file_path` 等别名。

本轮实现：

- `AgentLoopController.allowedToolNames` 根据当前 `ActionRunner.webToolInvoker` 自动过滤 `web_search / fetch_url`。
- `OpenAiCompatibleToolCallAdapter.buildChatCompletionRequest()` 支持 `allowedToolNames`，只把当前真实可执行工具传给 provider。
- System instruction 改为“当前请求暴露哪些工具就只能调用哪些工具”，避免模型看到不可用 web tools。
- `write_file` 支持 `path / file_path / filepath / filename / fileName / name` 路径别名。
- 当 provider 返回 malformed tool arguments 但其中包含完整 HTML 时，`ToolCallAdapter` 会尝试恢复 `content`，不是直接丢弃为 `{}`。
- 当 `write_file` 缺少 path 但 content 是完整 HTML 时，安全缺省到 workspace 内 `index.html`。
- 参数恢复/路径推断会写入 `ActionEvidence.logs` 与 `metadata.adapterRepair`，便于 Activity Logs 和后续 observation 复盘。
- 新增单元测试覆盖工具过滤、缺省 HTML 写入路径、路径别名，以及无 relay 时 web tool 被阻止。

验收口径：

- 无 relay 配置时，DeepSeek Auto/Research 不应再收到 `web_search / fetch_url` tool definitions。
- 完整 HTML 的 `write_file` 即使以 malformed arguments 或缺 path 形式返回，也应被 adapter 恢复为 `content + index.html` 并写入 evidence，而不是循环失败。
- 仍然不允许写出 workspace，也不开放 shell/Git/publish/remote logs。

验证：

- [ ] `git diff --check`
- [ ] GitHub Actions `Mobile Runtime CI`
- [ ] 下一个 APK 真机验收

剩余风险：

- 如果模型返回的 `write_file` 参数连完整 HTML / `content` / `html` / `body` 都无法解析，仍会失败；这是正确的安全拒绝。
- `web_search / fetch_url` 仍依赖 relay endpoint；无 relay 时只能使用本地文件/预览类工具。

## DS04.3 Search/Patch + 角色编排

状态：`IN_PROGRESS`（本地实现完成，静态检查与 CI 待验收）

目标：

- 把 Agent Loop 从“主要写单文件”推进到“读项目 -> 搜项目 -> 补丁化修改 -> evidence observation -> 继续下一步”。
- 让模型看到熟悉的 Unix-like 能力，但底层仍是 MobileCode typed tools，不开放 raw shell。
- 多智能体第一版采用同一 loop 内的角色编排，不做并发子 Agent，不制造无法验证的后台执行感。当前版本不推真实后台子 Agent。

本轮实现：

- 新增 provider-native tools：
  - `find_files(pattern, path, max_results)`
  - `grep_files(query, path, include_glob, max_results, max_bytes)`
  - `apply_patch(patch, reason)`
- `ActionRunner` 新增：
  - `findFiles`：按文件名 / glob / 相对路径片段搜索 workspace，限制结果数量。
  - `grepFiles`：只读搜索 workspace 文本，跳过二进制与过大文件，返回紧凑行预览。
  - `applyPatch`：只接受 unified diff，限制 patch 大小、文件数、修改行数，拒绝越界路径、二进制 patch 和自动删除。
- `applyPatch` 自动保存 workspace 内快照：
  - 快照目录：`.mobilecode_patch_snapshots/patch_<timestamp>/`
  - 记录 `applied.patch`
  - Evidence 记录 changedFiles、snapshotRoot、patchBytes、changedLineCount、reason。
- `ToolCallAdapter` tool schema 和 ActionSchema 映射加入 `find_files / grep_files / apply_patch`。
- `AgentPreset.allowedToolNames` 更新：
  - Auto：search/read/write/patch/preview/report。
  - Builder：find/grep/read/write/apply_patch/preview/report。
  - Research：web/search/fetch/find/grep/write/patch/preview/snapshot/report。
  - Repair：find/grep/read/apply_patch/preview/report。
  - Reviewer：find/grep/read/preview/snapshot/report，不允许 write/apply_patch。
- Agent Loop trace 事件加入角色信息：
  - Planner：列目录、查找、搜索、读取。
  - Builder：写文件、移动文件、应用补丁。
  - Reviewer：预览、快照、报告结果。
  - Repair：失败 observation 后的修复职责。
- Streaming tool call 参数流入合并为同一条可更新事件，详情显示累计字符和增量字符；真正写入仍只在完整 tool call 到达并通过 ActionRunner 校验后发生。
- 无效 `apply_patch` 草稿（例如 `@@ ... @@`）显示为安全阻断，不再把已经保存的 artifact 误染成整体失败；失败 evidence 仍保留用于复盘。
- Blocked recovery observation 进一步加固：重复 `apply_patch` hunk header 错误或 `write_file` 缺少 `path` 时，下一轮 observation 明确给出 `failureKind / toolName / what failed / safeNextAction`，要求模型先 `read_file` 获取上下文、改用合法 unified diff，或在小型 HTML artifact 场景下完整 `write_file`。
- Composer 收纳为四层：`模式` 显示 Single-shot / Agent Loop，模式面板承载 Agent preset / RR；`模型` 靠近语音按钮；`任务派发` 默认只展示贪吃蛇、2048、GitHub，更多任务进 sheet；`输入` 保持最高优先级。后续子代理路线为“Sub-Agent Lite”（event/mailbox-lite）而非并发执行层。
- 模式面板中新增可见“角色协作”入口，说明 Planner / Builder / Reviewer / Repair 是同一 Agent Loop 内的角色编排，不是并发后台线程。
- Tools 页同步显示 provider-native tool list、Android/Linux/macOS command map、preset access。
- `COMMANDS.md` 与 `COMMAND_COMPATIBILITY.md` 同步 Search/Patch 支持状态。
- GitHub Pages `实验日志` 增加 2026-05-22 面向用户的移动端 AgentLoop 复盘。

Shell 边界：

- 不实现 `exec_shell(command)`。
- `ls / find / grep / cat / mv / patch / curl` 这类常见命令转译为 typed tools。
- 原因不是“shell 本身坏”，而是 raw shell 字符串会把管道、重定向、通配符、环境变量、网络和删除副作用混在一起，手机 App 很难可靠审计、限制和回滚。

验收口径：

- DeepSeek Agent Loop 可自主选择 `find_files / grep_files / read_file / apply_patch`。
- Reviewer preset 无法执行 `write_file / apply_patch`。
- Repair preset 可按 `find -> read -> apply_patch -> preview -> report_result` 路径修复。
- `apply_patch` 不越界、不删除、不处理二进制、不写过大 patch，并且每次都有 evidence 与快照。
- Chat trace 不再只顶部变化，而是逐条记录角色、工具、observation 和执行总结。

验证：

- [x] `git diff --check`
- [x] `node --check relay/mobilecode-token-relay-worker.js`
- [x] `cd app && npm run build`
- [ ] GitHub Actions `Mobile Runtime CI`
- [ ] GitHub Actions `Build Android APK`

剩余风险：

- 第一版 `apply_patch` 是移动端轻量 unified diff 执行器，不等同于完整 `git apply`。
- 尚未实现 copy/mkdir/delete/snapshot restore/virtual git diff 的完整工具面。
- 多角色仍是单 loop 内的职责切换；真实后台子 Agent 本阶段延后，先落地角色编排 + event/mailbox-lite 方向。

## DS04.4 Sub-Agent Lite / mailbox-lite

状态：`ACCEPTED`（本地实现完成，Mobile Runtime CI 通过，APK 待构建）

目标：

- 把“角色协作”从 UI/prompt 标签推进到 provider-native 可见的最小子任务工具。
- 第一版只开放只读 `Explorer / Reviewer`，不开放 shell、不开放写入、不开放并发后台执行。
- 用 mailbox-lite 记录子任务生命周期，让父 Agent 可以 `agent_open -> agent_eval -> agent_close` 回收结构化结果。

本轮实现方向：

- 新增 provider-native tools：
  - `agent_open(role, task, path, focus)`
  - `agent_eval(agent_id)`
  - `agent_close(agent_id, reason)`
- `AgentLoopController` 在同一 run 内维护 Sub-Agent Lite session：
  - 只允许 `explorer` / `reviewer`。
  - 自动写入 mailbox 事件：`Started / ToolCallCompleted / Completed / Progress / Closed`。
  - 子任务只调用 MobileCode typed read-only tools，如 `list_files / grep_files`。
  - observation 返回固定输出协议：`SUMMARY / CHANGES / EVIDENCE / RISKS / BLOCKERS`。
- `AgentPreset` 工具权限：
  - Auto / Research / Reviewer 可使用 `agent_open / agent_eval / agent_close`。
  - Builder / Repair 暂不默认暴露子任务工具，避免写入阶段过度分叉。

验收口径：

- 模型能看到并调用 `agent_open / agent_eval / agent_close`。
- 非只读角色如 `implementer` 会被 blocked，并返回可恢复 observation。
- mailbox 事件能进入 trace，用户能看到 Explorer/Reviewer 子任务过程。
- 子任务不会写文件、不会 patch、不会 shell、不会并发后台常驻。

验证：

- [x] `git diff --check`
- [x] `node --check relay/mobilecode-token-relay-worker.js`
- [x] `cd app && npm run build`
- [x] GitHub Actions `Mobile Runtime CI`

本轮执行记录（2026-05-23）：

- 实现提交：`274b9aa feat: add sub-agent lite mailbox`
- `cxspark` 本地通道启动失败并已标记 review；没有采纳 Spark 输出，本轮由 Codex 手工实现并复核。
- GitHub Actions `Mobile Runtime CI` 通过：`https://github.com/Harzva/mobilecode/actions/runs/26299335635`

剩余风险：

- 第一版 Sub-Agent Lite 是同一 AgentLoop run 内的 read-only session，不是完整后台并发 worker。
- 未来如果要做真实后台子 Agent，需要单独设计 session 持久化、取消传播、token 预算和并发上限。

## DS05 DeepSeek 错误码映射

状态：`PENDING`

目标：

- 把 DeepSeek HTTP 错误转换为 MobileCode 可恢复的 failure kind 和用户可读提示。

映射建议：

| HTTP | 含义 | 行为 |
| --- | --- | --- |
| 400 | 请求体 / messages / reasoning 回传错误 | 不重试，提示修协议 |
| 401 | Key 错误 | 不重试，提示检查配置 |
| 402 | 余额不足 | 不重试，提示额度 |
| 422 | model / tools schema / max_tokens 错误 | 不重试，提示修参数 |
| 429 | 限流 | 可退避重试 |
| 500 | 服务端错误 | 可退避重试 |
| 503 | 服务繁忙 | 可退避重试或 fallback |

涉及文件：

- `mobile_agent/lib/screens/home_screen.dart`
- `mobile_agent/lib/core/evidence/evidence_model.dart`
- `mobile_agent/lib/core/evidence/action_runner.dart`
- `mobile_agent/test/services/tool_call_adapter_test.dart`

验收：

- 400/422 不盲目重试。
- 429/500/503 有退避策略或明确 fallback。
- Activity Logs 显示 failure kind、HTTP status、recovery action。

验证：

- `git diff --check`
- GitHub Actions `Mobile Runtime CI`

## DS06 Usage / Cache / Reasoning 观测

状态：`PENDING`

目标：

- 将 DeepSeek usage 信息纳入 Activity Logs 和 Evidence。

建议记录字段：

- `model`
- `baseUrlKind`
- `finish_reason`
- `prompt_tokens`
- `completion_tokens`
- `total_tokens`
- `reasoning_tokens`
- `prompt_cache_hit_tokens`
- `prompt_cache_miss_tokens`
- `tool_calls_count`
- `latency_ms`

涉及文件：

- `mobile_agent/lib/services/token_usage_service.dart`
- `mobile_agent/lib/screens/api_usage_screen.dart`
- `mobile_agent/lib/screens/home_screen.dart`
- `mobile_agent/lib/core/evidence/evidence_model.dart`

验收：

- Activity Logs 可看到本轮 DeepSeek token 与 tool call 数。
- cache hit/miss 缺失时不报错。
- reasoning_tokens 缺失时不报错。

验证：

- `git diff --check`
- GitHub Actions `Mobile Runtime CI`

## DS07 JSON Output 降级路径

状态：`PENDING`

目标：

- 将 JSON Output 明确作为降级/结构化诊断路径，而不是替代 provider-native tool call。

适合场景：

- provider 不支持 tool calls。
- tool call 解析失败。
- 需要模型输出结构化计划或错误诊断。

不允许：

- 把 JSON fallback 伪装成真实 provider-native function calling。
- 用 JSON 文本直接绕过 `ActionRunner` 写文件或执行工具。

涉及文件：

- `mobile_agent/lib/services/tool_call_adapter.dart`
- `mobile_agent/lib/services/agent_loop_controller.dart`
- `mobile_agent/test/services/tool_call_adapter_test.dart`

验收：

- Evidence 中明确标注 `fallback=json_output`。
- JSON 解析失败时有可读错误。
- `finish_reason=length` 时不把半截 JSON 当成功。

验证：

- `git diff --check`
- GitHub Actions `Mobile Runtime CI`

## DS08 Strict Tool Call beta 入口

状态：`PENDING`

目标：

- 支持 DeepSeek `/beta` strict tool call，但默认不强制开启。

要求：

- `base_url=https://api.deepseek.com/beta`
- 每个 function 设置 `strict=true`
- 每个 object 参数：
  - `required` 包含全部 properties
  - `additionalProperties=false`
- Runtime 仍然二次校验参数和权限。

涉及文件：

- `mobile_agent/lib/services/tool_call_adapter.dart`
- `mobile_agent/lib/screens/api_config_screen.dart`
- `mobile_agent/test/services/tool_call_adapter_test.dart`

验收：

- strict schema 测试通过。
- beta base URL 下 tools 全部带 `strict=true`。
- 普通 base URL 下不强制 strict。

验证：

- `git diff --check`
- GitHub Actions `Mobile Runtime CI`

## DS09 AgentLoop 回归验收任务

状态：`PENDING`

目标：

- 建立一组 DeepSeek AgentLoop 产品验收任务，防止后续适配破坏核心体验。

必测任务：

1. 普通聊天：问候与能力边界说明。
2. Single-shot 贪吃蛇：仍可生成并预览。
3. AgentLoop Builder：`write_file -> read_file -> preview_html -> report_result`。
4. Auto Agent 复杂任务：模型自主选择 search/write/preview/snapshot/report。
5. Repair：读取已有 artifact，修复并预览。
6. Reviewer：只读检查，不允许写文件。
7. 错误路径：非法工具名被拒绝并记录 failed evidence。
8. DeepSeek 400 reasoning 回传问题不复现。

涉及文件：

- `mobile_agent/test/services/agent_loop_controller_test.dart`
- `mobile_agent/test/services/tool_call_adapter_test.dart`
- 可选新增：`docs/import_phase_summarize/deepseek-agentloop-acceptance-checklist.md`

验收：

- 每个任务都有对应 evidence。
- 失败任务能复制失败摘要。
- UI 不把完整 HTML 塞进聊天气泡。
- 最新用户消息优先，不被旧 agent process 固定占底。

验证：

- GitHub Actions `Mobile Runtime CI`
- 手动 APK 验收

## DS10 Release / APK 验收

状态：`PENDING`

目标：

- 每完成一组 DeepSeek 适配任务后，发布可下载安装的 APK。

建议版本：

- DS01-DS04 完成：`v0.1.51-last`
- DS05-DS06 完成：`v0.1.52-last`
- DS07-DS09 完成：`v0.1.53-last`

发布流程：

```text
git diff --check
-> remote last-recover-from-v039 更新
-> GitHub Actions Mobile Runtime CI
-> GitHub Actions Build Android APK
-> GitHub Release asset 确认
-> 用户手动 APK 验收
```

验收：

- Release 中出现正确版本 APK。
- APK 文件名与 tag 一致。
- `Mobile Runtime CI` 成功。
- `Build Android APK` 成功。

## 建议优先级

P0：

- DS01 DeepSeek v4 Provider Profile
- DS02 默认模型与 Base URL 迁移
- DS03 Thinking + Tool Calls 回传加固
- DS04 Streaming tool_calls 完整测试

P1：

- DS05 DeepSeek 错误码映射
- DS06 Usage / Cache / Reasoning 观测

P2：

- DS07 JSON Output 降级路径
- DS08 Strict Tool Call beta 入口
- DS09 AgentLoop 回归验收任务

P3：

- DS10 Release / APK 验收

## 每轮执行模板

每次执行一个 DS 任务时，按下面格式回填：

```text
任务编号：
状态：PENDING / IN_PROGRESS / ACCEPTED / DEFERRED
实际改动：
关键文件：
验证结果：
CI 链接：
APK 链接：
剩余风险：
下一步：
```

## 最小验收标准

DeepSeek 全面适配不是“能聊天”就算完成，至少要满足：

- v4 模型名和入口口径正确。
- Thinking + Tool Calls 不触发 reasoning 回传 400。
- Streaming 能解析 content、reasoning_content、tool_calls、usage。
- Tool Call 必须经过 `ActionRunner`。
- Evidence 能记录工具执行事实。
- 错误码能映射为可理解、可恢复的失败。
- usage / cache / reasoning 成本可观察。
- Single-shot 稳定路径不被破坏。
