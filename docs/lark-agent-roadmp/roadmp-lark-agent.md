# MobileCode Lark Agent Roadmp

目标：把 Lark/飞书能力从本地 CLI 采样推进为 MobileCode 内可诊断、可回话、可验收的 agent-native 产品闭环。

## 使用规则

- `[x]` 只代表已有文件、命令、代码、设备记录、CI 或 evidence 能证明完成。
- `[ ]` 代表未完成、未验证、被阻塞、暂缓或仍需用户输入。
- 主路线图只记录阶段、边界和验收标准；执行细节放入 `tasks/`。
- `lark-cli` 是开发期行为对齐源，不内置进移动端 App。
- `codex-spark-playbook` 可用于小范围、文本型、可审计任务；最终验收由主 Codex 会话完成。

## 安全规则

- 不提交 token、app secret、cookie、`.env`、原始授权日志或本地私密路径。
- 不把 Node/lark-cli 作为 MobileCode 移动端运行时前提。
- 不把 Spark 输出直接标记为完成；必须由主会话检查 diff、证据和风险。
- 不把模拟器截图、实机画面或飞书私聊截图交给 Spark 做判断。
- 不破坏 Mobile Harness benchmark、verifier、task bank 和论文证据链。

## 当前基线

- 日期：2026-06-12。
- 工作树：`MobileCode-main-dev`。
- 公开主线：`main`。
- Lark 基线：`lark-cli` 已可在 Mac mini 作为开发期采样工具使用；Mobile App 采用 Dart 原生 Lark OpenAPI。
- 已完成能力：Lark API Lab 有基础执行、能力检测、failure taxonomy 和 evidence 字段。
- 参考仓库：`Termux-X`、`ZeroTermux`、`termux-app` 已浅克隆到项目外部 `reference-repos/termux/`。
- 当前缺口：Relay 最小闭环、IM 事件消费、bot 回复链路、事件消费者缺失检测、发布前设备验收尚未完成。

## Key Decisions

- [x] MobileCode 不内置 Node/lark-cli；`lark-cli` 只作为 Mac/CI/Relay 的行为对齐源。
  - Evidence: `docs/lark-native-api-upgrade-plan.md` 已记录 CLI 采样模板与移动端映射。
- [x] Lark API Lab 使用 failure taxonomy 表达失败归因。
  - Evidence: `mobile_agent/lib/services/lark_api_service.dart` 与 `mobile_agent/lib/screens/home_screen.dart` 已加入 diagnosis/failure taxonomy。
- [ ] Lark bot 自动回话采用 Relay/callback/event consumer，而不是手机 App 长期监听公网 webhook。
- [ ] Termux 能力采用参考式吸收：runtime、PTY、文件系统和包管理经验可借鉴，但不直接把 Termux App 嵌进 MobileCode。

## 总体验收标准

- [ ] 有一页 Termux 参考映射，明确 `termux-app`、`ZeroTermux`、`Termux-X` 的可借鉴点和禁止照抄点。
- [ ] 有 Relay 最小闭环：`event -> queue -> agent -> IM reply/send`。
- [ ] Lark API Lab 能独立显示 `event_consumer_not_running`，并给出下一步动作。
- [ ] Lark API Lab 至少覆盖 Docs、Drive、Sheets、Bitable、Wiki 的能力可见性、缺失 scope 和成功/失败样例。
- [ ] 本地模拟器或实机完成一次 `bot 收消息 -> 触发 -> 回消息 -> 写 evidence` 验收。
- [ ] GitHub Actions 关注 Lark Lab 关键步骤、Mobile Runtime CI、Deploy Pages、Android Smoke。

## Phase 1：Termux 参考映射

详见：[01-termux-reference-mapping.md](tasks/01-termux-reference-mapping.md)

- [ ] 阅读 `termux-app`、`ZeroTermux`、`Termux-X` 的 runtime、交互入口、权限/打包、可复用模块。
- [ ] 输出 `docs/termux-reference-mapping.md`。
- [ ] 明确 MobileCode 应吸收的能力和只作为参考的能力。

## Phase 2：Relay 最小闭环

详见：[02-lark-relay-minimum-loop.md](tasks/02-lark-relay-minimum-loop.md)

- [ ] 实现最小 Relay 服务骨架。
- [ ] 支持 mock event 进入队列。
- [ ] 支持 agent stub 生成回复。
- [ ] 支持 IM reply/send adapter 的 dry-run evidence。
- [ ] 输出可复现场景：私聊触发关键词 -> 机器人回复。

## Phase 3：Agent 回话失败归因

详见：[03-lark-agent-failure-taxonomy.md](tasks/03-lark-agent-failure-taxonomy.md)

- [ ] 将 `event_consumer_not_running` 作为独立能力检测项加入 Lark API Lab。
- [ ] 将 CLI 采样结果和移动端调用结果统一写入 evidence。
- [ ] 给出可操作建议文案：事件消费、IM scope、callback/relay 配置。

## Phase 4：Lark API 产品化能力面

详见：[04-lark-api-product-surface.md](tasks/04-lark-api-product-surface.md)

- [ ] Docs、Drive、Sheets、Bitable、Wiki 至少 5 类能力有就绪判断。
- [ ] 每类能力有缺失 scope 指引。
- [ ] 每类能力有最小成功/失败样例字段。

## Phase 5：发布前验收

详见：[05-release-readiness-qa.md](tasks/05-release-readiness-qa.md)

- [ ] 本地模拟器或实机完成 Lark bot 回话链路。
- [ ] evidence 包含 request id、log id、failure kind、scope、next action。
- [ ] 同步 GitHub Actions 关注点。

## Spark Delegation Queue

- [ ] Spark Task A：生成 `docs/termux-reference-mapping.md` 草稿。
- [ ] Spark Task B：生成 Relay 最小骨架草稿，限定新增独立目录，不触碰移动端核心文件。
- [ ] Spark Task C：补 Lark API Lab 的 `event_consumer_not_running` 可见项，限定 `mobile_agent/lib/services/lark_api_service.dart` 和 `mobile_agent/lib/screens/home_screen.dart`。
- [ ] Spark Task D：补 Lark API Lab Docs/Drive/Sheets/Bitable/Wiki 的能力展示样例，限定同一组 Lark 文件。

## Test Plan

- [ ] `npm run build` in `app/`。
- [ ] `python3 scripts/validate_mobile_harness_bench.py` in repo root。
- [ ] 如修改 Flutter：尝试 `flutter analyze`；若本机 analyzer 不可用，记录限制。
- [ ] 如修改 Flutter：至少尝试 Android debug build 或由 GitHub Actions 验证。
- [ ] 如修改 Relay：运行 relay mock smoke 或记录 dry-run 命令。

## Open Questions

- [ ] Relay 首版放在仓库内哪个目录：`relay/`、`tools/lark_relay/` 还是 `scripts/lark_relay/`。
- [ ] 首版 IM reply adapter 使用 Lark OpenAPI 直连，还是只输出 dry-run evidence。
- [ ] 是否需要把 Relay 部署说明接入 GitHub Actions 或 Pages 开发者页。
