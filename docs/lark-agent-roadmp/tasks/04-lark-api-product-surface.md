# 04 Lark API 产品化能力面

## 目标

让 Lark API Lab 从单点执行工具升级为可扫描的产品面，覆盖 Docs、Drive、Sheets、Bitable、Wiki + Agent Chat readiness 的能力可见性。

## 范围

- In scope: 当前就绪判断、缺失 scope 指引、最小成功/失败样例；Agent Chat readiness 证据回填与提示文本。
- Out of scope: 每个 API 的完整编辑器、真实数据批量写入、权限自动申请。

## Key Decisions

- [ ] 能力检测优先解释“为什么不可用”，再暴露“如何修复”。
- [ ] 样例 token 和日志字段必须脱敏或使用占位符。

## Task List

- [x] Docs 能力项（创建/追加）。
- [x] Drive 能力项（上传协议/预览）。
- [x] Sheets 能力项（值追加）。
- [x] Bitable 能力项（批量写入）。
- [x] Wiki 能力项（可达性探测 + 列表）。
- [x] Agent Chat readiness 项（IM event 运行面）。

## Evidence / 已完成证据

- [x] 更新 `docs/lark-agent-roadmp/tasks/03-lark-agent-failure-taxonomy.md`，定义 `event_consumer_not_running` 与 evidence 字段。
- [x] Lark API Lab UI 已显示 Docs/Drive/Sheets/Bitable/Wiki 与 Agent Chat readiness 的状态、missing-scope / missing-config 指引。
- [x] 失败样例与成功样例支持 `tool`/`tokenMode`/`httpStatus`/`requestId`/`logId`/`errorCode`/`dryRunTrace` 字段展示（占位符化）。

## Open Questions

- [x] Bitable 与 Sheets 在当前面板并列展示，分别独立失败恢复路径。

## Test Plan

- [x] Flutter analyze（建议在本地稳定环境再次复跑，当前环境 analyzer 有服务端异常）。
- [ ] Android debug build 或 GitHub Actions smoke。

## Assumptions

- [ ] 首版样例可以 dry-run，不需要真实写入飞书文档。
