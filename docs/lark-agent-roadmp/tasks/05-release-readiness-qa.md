# 05 发布前验收

## 目标

在发布前跑通一条可复现链路：`bot 收消息 -> 触发 -> 回消息 -> 写 evidence`。

## 范围

- In scope: 本地模拟器或实机、Lark Lab 关键步骤、Android Smoke、GitHub Actions 关注点。
- Out of scope: 正式生产 SLA、长期 relay 部署、安全审计结论。

## Key Decisions

- [ ] 设备/模拟器验收由主 Codex 会话执行，不交给 Spark。
- [ ] 失败也要留下 evidence，不能只记录“没反应”。

## Task List

- [x] Android 模拟器或实机安装测试。
- [ ] iOS simulator 如环境可用则测试。
- [ ] 飞书 bot 私聊触发。
- [ ] Relay/agent 生成回复。
- [x] Evidence 最小样例可在 Lark API Lab 查看。
- [ ] 关注 GitHub Actions：Mobile Runtime CI、Deploy Pages、Android Smoke。

## Evidence / 已完成证据

- [x] Android 本地 release APK 安装/启动通过：`mobile_agent/qa-output/android-local-20260612-052506/`。
- [x] Android QA 证据包含 `install.txt`、`launch.txt`、`screenshot-main.png`、`window-main.xml`、`window-focus.txt`、`logcat.txt`、`apk-sha256.txt`。
- [x] 本地结果：`install=Success`，`launch=Status: ok`，focus=`com.mobilecode.app/.MainActivity`，UI XML 命中 `MobileCode` / `Single-shot` / `任务派发`，logcat 未命中 `FATAL EXCEPTION` / `E/flutter` / `ANR` / `MissingPluginException` / `SIGSEGV`。
- [ ] 记录新的 GitHub Android Smoke run URL。

## Open Questions

- [ ] 当前机器是否具备稳定 Android emulator 和 iOS simulator 环境。

## Test Plan

- [x] `npm run build`。
- [x] `python3 scripts/validate_mobile_harness_bench.py`。
- [x] `flutter analyze` 记录限制：本机 `flutter analyze` analysis server LSP JSON 崩溃；`dart analyze --format machine ... | rg '^ERROR'` 无 ERROR。
- [x] Android 本地安装与启动记录。
- [ ] iOS simulator 本地安装与启动记录。

## Live Relay Evidence Import Acceptance（Flutter 后续集成）

- [ ] Flutter 侧可读取 `tools/lark_relay/evidence/*.json`（单文件/批量）并支持时间降序列表化。
- [x] Flutter 侧已接入最小样例面板（event -> reply -> evidence），展示 `send_mode`、`failure_kind`、`next_action`、`event_id`/`request_id`、`reply message id` 与 `raw JSON` 预览状态（占位样例，仅用于最小集成）。
- [ ] UI 必须显示 `send_mode`（dry-run / live）与 `failure_kind`（含 `event_consumer_not_running`/`missing_scope` 等）。
- [ ] UI 必须显示 `next_action` 与恢复建议（与 `failure_kind` 一致）。
- [ ] 每条记录必须展示 `event_id` 与 `request_id`（缺失其一时显示 `N/A`）。
- [ ] 回复成功时可展示 `reply` 的 `message_id`（需脱敏策略）。
- [ ] 显示可展开的 `raw JSON` 预览，默认仅读取本地文件不上传外网。
- [ ] `tools/lark_relay/evidence/*.json` 中的 `chat_id`、`message_id`、`open_id` 默认不在公开界面直显，需通过 sanitizer 显示占位符或隐藏。
- [ ] Lark API Lab 能按 `event -> reply -> evidence` 顺序显示本条链路并给出最小定位文案（如「事件已消费但未回复」「已发送且已记录 evidence」）。

## Assumptions

- [ ] 发布前验收可能依赖真实飞书权限、scope 和 callback 配置。
