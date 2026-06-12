# 03 Lark Agent 回话失败归因

## 目标

把 bot 私聊无响应这类问题从静默失败变成 Lark API Lab 中可见、可审计、可修复的 evidence。

## 范围

- In scope: `event_consumer_not_running` 检测项、CLI 采样映射、mobile evidence 字段、下一步动作文案；Agent Chat readiness 作为独立可见项。
- Out of scope: 真实公网 callback 部署、飞书后台权限自动申请。

### Live Relay Evidence Plan

- In scope extension: 让 Lark API Lab 可读取本地 `tools/lark_relay/evidence/*.json` 并展示事件到回复到 evidence 的链路。
- 最小展示字段（示例）：
  - `event`：`event_id`、`tool`、`text`、`received_at`，以及可选的 `chat_id`、`message_id`、`open_id`。
  - `reply`：`send_mode`、`text`、`status`、可选的回复 `message_id`。
  - `evidence`：`failure_kind`、`next_action`、`request_id`、`event_id`、`log_id`、`token_mode`、`tool`、`raw_json_path`。
- `tools/lark_relay/evidence/*.json` 可能包含 `chat_id`、`message_id`、`open_id`；本地解析应先进行脱敏过滤，未脱敏字段默认不渲染到 UI。
- Lark API Lab 应按三栏显示：事件摘要、回复动作、证据明细，并提供 `raw JSON` 的只读预览入口。

## Key Decisions

- [x] `event_consumer_not_running` 是独立 failure kind。
- [x] UI 保留并展示证据字段：`tokenMode`、`tool`、`HTTP`、`requestId`/`logId`、`errorCode`、`nextAction` 与 `dryRun`。
- [x] 将该故障挂接为 Agent Chat readiness 而非单一产品 API 读写项。

## Task List

- [x] 在 Lark API Lab 加入 `event_consumer_not_running` diagnosis 与 readiness 视图。
- [x] 将事件消费 CLI 采样写入 failure taxonomy sample（含 `tool`、`tokenMode`、`errorCode`、`requestId`、`logId`、`dryRunTrace`）。
- [x] 将移动端运行结果写入统一 evidence 结构（`failureKind`/`missingScopes`/`nextAction`/`logId`）。
- [x] 添加建议文案：先启动 relay/event consumer 或回调服务，再补 IM event scopes 与配置。
- [x] 为 live relay evidence 增加最小 `event -> reply -> evidence` 样例展示（纯占位字段），字段包含 `send_mode`、`failure_kind`、`next_action`、`event_id/request_id`、`reply message id`、`raw JSON` 预览状态。真实本地 evidence 文件 import 仍待后续实现。
- [ ] 为 live relay evidence 增加真实 `tools/lark_relay/evidence/*.json` import 与时间降序展示（后续迭代）。

## Evidence / 已完成证据

- [x] 已在 `mobile_agent/lib/services/lark_api_service.dart` 新增事件消费 failure kind 与 diagnosis 规则。
- [x] 已在 `mobile_agent/lib/screens/home_screen.dart` 增加 Agent Chat readiness 卡片并显示 evidence 导向详情。
- [x] 已在 `docs/lark-agent-roadmp/tasks/04-lark-api-product-surface.md` 补齐能力项与 readiness 说明。
- [x] 记录本地 `dart format` 与静态分析建议（analyzer 输出受环境限制，见建议）。

## Open Questions

- [x] 已统一归类到「Agent Chat readiness」而非某单一产品 API 能力。

## Test Plan

- [x] Flutter analyze（如同环境支持）；当前环境出现 analyzer JSON 解析异常，故建议在本机再跑一遍。
- [ ] Android debug build 或 GitHub Actions smoke（待确认）。
- [ ] 读取并展示至少 1 条 `tools/lark_relay/evidence/*.json`，检验 event/reply/evidence 三段链路可视化。

## Assumptions

- [x] 当前飞书私聊无响应的首要原因之一为「事件消费者未运行」；文档中的 guidance 也保留 scope 与配置缺失双路径。
- [ ] 本任务执行不依赖真实私有 ID；本地 evidence 文件中的 `chat_id`、`message_id`、`open_id` 仅在 sanitizer 后可见并保留最小上下文。
