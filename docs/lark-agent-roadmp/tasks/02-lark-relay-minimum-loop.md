# 02 Lark Relay 最小闭环

## 目标

建立 `event -> queue -> agent -> IM reply/send` 的最小 Relay 骨架，让飞书私聊可以触发 agent 回复链路。

## 范围

- In scope: mock event、内存队列、agent stub、IM dry-run adapter、evidence JSON。
- Out of scope: 生产部署、真实 secret 管理、长期队列、发布和公网 webhook 配置。

目标外延: 支持 `--agent-mode mock|command` 的本地命令式 agent 适配开关，默认仍为 mock。

## Key Decisions

- [ ] Relay 是 Mac/CI/服务端适配层，不是移动端 App 内置 Node 环境。
- [ ] 首版优先 dry-run evidence，再接真实 Lark OpenAPI。

## Task List

- [x] 选择 Relay 目录。
- [x] 在 `tools/lark_relay/` 下实现 mock event 输入。
- [x] 实现事件内存队列（`InMemoryEventQueue`）。
- [x] 实现 agent stub。
- [x] 实现 IM reply/send dry-run adapter。
- [x] 实现私聊触发关键词到机器人回复的复现场景 CLI。
- [x] 为 live relay 增加本地命令 Agent 适配分支（默认 mock）。
- [x] 为命令模式新增 OpenAI-compatible 适配器脚本 `tools/lark_relay/agent_command_openai_compatible.py`，并接入 dry-run-first 使用说明。

## Evidence / 已完成证据

- [x] 记录 mock smoke 命令和输出。
- [x] 记录生成的 evidence 文件。

示例命令：

`python tools/lark_relay/mock_relay_runner.py --message "帮我回复一下这条私聊消息" --tool lark.relay.mock`

## Open Questions

- [ ] 首版是否需要 HTTP callback endpoint，还是先只做 CLI/mock runner。

## Notes

- 命令式 agent 依赖环境变量驱动：`MOBILECODE_AGENT_API_URL`、`MOBILECODE_AGENT_API_KEY`（必需）、`MOBILECODE_AGENT_MODEL`、`MOBILECODE_AGENT_SYSTEM_PROMPT`（可选）。
- 发送行为默认 dry-run；如需真实发送，必须同时使用 `--send-mode live --allow-live`。

## Test Plan

- [x] Relay mock smoke 命令通过。
- [x] dry-run evidence 包含 event id、tool、request id、dry_run_id、failure kind、next action、message text、reply text、timestamp。

## Assumptions

- [ ] 真实飞书 token 不写入仓库。
