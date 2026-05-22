# MobileCode DeepSeek 全面适配执行计划

日期：2026-05-22

执行基线：`last-recover-from-v039`

当前产品基线：`v0.1.50-last`

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
- `write_file / read_file / preview_html / preview_snapshot / web_search / fetch_url / report_result` 安全工具集。
- `ActionRunner / ActionEvidence / Activity Logs` 记录执行事实。
- DS01 DeepSeek v4 Provider Profile 已完成，Mobile Runtime CI 与 v0.1.51-last APK 构建已通过。
- DS02 默认模型与 Base URL 迁移已完成，Mobile Runtime CI 与 v0.1.51-last APK 构建已通过。
- DS03 Thinking + Tool Calls 回传加固已完成，Mobile Runtime CI 与 v0.1.51-last APK 构建已通过。
- DS04 Streaming tool_calls 边界测试已完成，Mobile Runtime CI 与 v0.1.51-last APK 构建已通过。

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

## 快速执行顺序

建议每轮只做一个任务编号，避免再次出现分支或 UI 回归问题。

- [x] DS00 文档基线
- [x] DS01 DeepSeek v4 Provider Profile（本地实现完成，CI 待验收）
- [x] DS02 默认模型与 Base URL 迁移（本地实现完成，CI 待验收）
- [x] DS03 Thinking + Tool Calls 回传加固（本地实现完成，CI 待验收）
- [x] DS04 Streaming tool_calls 完整测试（本地实现完成，CI 待验收）
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
- 补充 provider profile 单元测试：v4 flash/pro、strict beta、legacy alias、unsupported experimental model。
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
- 本地 `flutter` / `dart` 不在 PATH，未运行 Flutter analyze/test。

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
- 本地 `flutter` / `dart` 不在 PATH，未运行 Flutter analyze/test。
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
- [x] 本地 `flutter`/`dart` 命令可用性确认（本地环境未检测到 `flutter`/`dart`）
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
- 本地 `flutter` / `dart` 不在 PATH，未运行 Flutter analyze/test。
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
- [x] 本地 `flutter` / `dart` 可用性确认（未检测到 `flutter` / `dart`）
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
- 本地 `flutter` / `dart` 不在 PATH，未运行 Flutter analyze/test。
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
