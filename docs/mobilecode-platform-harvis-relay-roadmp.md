# MobileCode Platform + Harvis Relay Roadmp

目标：把 MobileCode 定位为手机端 Agent Harness / 移动版 AgentWorkOS 控制台，并把 Harvis Relay 定义为可选外部桥接能力，而不是内置 runtime。

保留文件名中的 `roadmp` 拼写，兼容当前仓库引用习惯。

## 使用规则

- `[x]` 只表示有代码、测试、构建、截图、真机 QA、用户验收或其他明确证据。
- `[ ]` 表示未完成、未验证、被阻塞、仍需设计确认，或只完成了部分。
- 参考图、UI 参考、文字计划不能作为功能完成证据。
- 每个阶段完成后，必须把证据写入本文件的 `Evidence / 已完成证据`。
- 不把凭据、token、cookie、`.env`、OAuth code、本机私有路径、原始聊天日志写入 roadmp、截图或 evidence 原文。
- 本 roadmp 只定义 MobileCode 平台定位和 Harvis Relay 长期路线，不替代 T26 的订阅登录、T27 的 CLI Hub tool calling 或 Linux Sandbox roadmp。

## 产品定位

MobileCode 不是单纯的 MobileClaw。

MobileCode 是平台：

```text
MobileCode
├─ MobileClaw：手机操作执行器
├─ CLI Hub：增量 CLI 工具中心
├─ Linux Sandbox：内置 Alpine 运行层
├─ Usage Hub：订阅与账号用量
├─ Native Helper：本机 Git/文件/构建能力
└─ Harvis Relay：连接 Mac mini / AgentWorkOS
```

模块边界：

- MobileCode：对话、权限、工具编排、证据、设置入口、用户确认。
- MobileClaw：无障碍、屏幕理解、点击、输入、手机 UI 自动化。
- CLI Hub：CLI catalog、profile 安装、probe、typed task。
- Linux Sandbox：Alpine rootfs、包安装、受控命令执行。
- Usage Hub：账号登录、订阅状态、quota refresh、Credential Vault。
- Native Helper：本机文件、Git、构建、安装、日志、证据。
- Harvis Relay：把 MobileCode 事件转发到外部 Harvis / AgentWorkOS。

## Key Decisions

- [ ] MobileCode 默认不依赖 Harvis；Harvis Relay 是高级外部集成。
- [ ] Harvis Relay 不作为内置 runtime，不和 Native Helper / Alpine 混在一起。
- [ ] Lark Relay 只作为外部桥接路径：`MobileCode -> Lark -> lark-relay -> Harvis -> ack`。
- [ ] MobileCode 不保存 Lark bot token、Harvis secret、cookie、OAuth code。
- [ ] 所有跨设备事件必须有 evidence payload、trace id、redaction、replay 防护。
- [ ] 只有真实测试通过后，checkbox 才能改为 `[x]`。

## Current Baseline

- 已有 MobileCode 平台模块：MobileClaw、CLI Hub、Linux Sandbox、Usage Hub、Native Helper。
- 已有 CLI Hub / Linux Sandbox 方向的长期 roadmp，覆盖 typed task、Full access raw shell、Pure/Dev Harness APK 分层。
- 已有外部 `lark-relay` 方向的实现思路：把 MobileCode evidence payload 经 Lark 转发到 Harvis localhost endpoint。
- 缺口：MobileCode evidence payload schema 尚未固定。
- 缺口：Harvis localhost endpoint contract 尚未在 MobileCode 侧固化。
- 缺口：真实 Lark bot / chat_id / Harvis ack 全链路尚未完成 evidence。
- 缺口：MobileCode 设置页尚未提供 `External Harvis Relay` 入口。

## Scope / 范围

In scope:

- MobileCode 平台定位和模块边界。
- MobileCode evidence payload schema。
- Harvis localhost endpoint contract。
- Lark Relay dry-run / live smoke 验证。
- `MobileCode/fixture -> Lark -> lark-relay -> Harvis -> ack` 全链路证据。
- MobileCode 中的 `External Harvis Relay` 设置入口。

Out of scope:

- 把 Harvis Relay 打进 Pure APK。
- 把 Lark token、Harvis secret 或 bot 凭据写进 MobileCode。
- 把 `lark-relay` 伪装成 MobileCode 内置 runtime。
- 让模型绕过 typed task 直接拼接任意 relay 命令。
- 把 mock 截图当作完成证据。

## Phase P0: Evidence Payload Schema

目标：固定 MobileCode 对外发送的最小事件协议。

- [ ] 定义 `MobileCodeEvidencePayload`。
- [ ] 字段包含：
  - `schemaVersion`
  - `eventId`
  - `traceId`
  - `source`
  - `deviceIdHash`
  - `capability`
  - `taskKind`
  - `summary`
  - `createdAt`
  - `redactedEvidence`
  - `requiresAck`
- [ ] 禁止字段：
  - `token`
  - `cookie`
  - `.env`
  - `oauthCode`
  - raw chat log
  - private local path
  - credential-like string
- [ ] 增加 JSON schema 或 Dart model 测试。
- [ ] 增加 redaction 单测。

### P0 Acceptance

- [ ] fixture payload 可通过 schema 校验。
- [ ] 敏感字段会被拒绝或脱敏。
- [ ] payload 可被 `lark-relay` 独立消费。

## Phase P1: Harvis Localhost Endpoint

目标：先用 mock，再接真实 Harvis localhost API。

- [ ] 定义 Harvis endpoint contract：
  - `POST /mobilecode/evidence`
  - request: `MobileCodeEvidencePayload`
  - response: `ackId`、`status`、`message`、`receivedAt`
- [ ] 增加 mock Harvis server。
- [ ] 增加 timeout、retry、idempotency 规则。
- [ ] 真实 Harvis API 未可用时，不阻塞 MobileCode 主流程。

### P1 Acceptance

- [ ] mock endpoint 可收到 fixture event。
- [ ] relay 收到 ack 后能返回稳定结果。
- [ ] endpoint 失败时有 recovery，不静默失败。

## Phase P2: Lark Relay 真实配置

目标：让外部 `lark-relay` 能用真实 Lark bot / chat_id 跑通。

- [ ] 配置真实 Lark bot 或 Lark CLI profile。
- [ ] 配置目标 `chat_id`。
- [ ] relay config 只保存在用户本机私有配置，不进入 MobileCode repo。
- [ ] relay 支持 dry-run 与 live 两种模式。
- [ ] relay 输出日志必须 redaction。

### P2 Acceptance

- [ ] dry-run 模式能解析 MobileCode fixture。
- [ ] live 模式能向 Lark 发送测试事件。
- [ ] 日志不包含 token、cookie、私有路径、原始凭据。

## Phase P3: End-to-End Relay Chain

目标：验证 `MobileCode/fixture -> Lark -> lark-relay -> Harvis -> ack`。

- [ ] 从 fixture 发送一条 MobileCode evidence event。
- [ ] `lark-relay` 接收并转发。
- [ ] Harvis mock 或真实 endpoint 返回 ack。
- [ ] ack 回写到 relay evidence。
- [ ] 记录 trace id、耗时、失败原因。

### P3 Acceptance

- [ ] E2E 测试通过。
- [ ] evidence 中能看到完整 trace。
- [ ] 重复 `eventId` 不会重复执行。
- [ ] 网络失败、Harvis 失败、Lark 失败都有 recovery。

## Phase P4: MobileCode Settings Entry

目标：在 MobileCode 中增加 `External Harvis Relay` 设置入口，但不把它当内置 runtime。

- [ ] 设置页增加 `External Harvis Relay`。
- [ ] 展示状态：
  - `notConfigured`
  - `configured`
  - `reachable`
  - `relayError`
  - `harvisError`
- [ ] 支持发送测试事件。
- [ ] 支持查看最近 ack。
- [ ] 明确文案：这是外部桥接，不是默认内置运行环境。

### P4 Acceptance

- [ ] 未配置时显示 setup guidance。
- [ ] 配置后可发送 test event。
- [ ] 成功后显示 ack id。
- [ ] 失败后显示 provider-specific recovery。

## Phase P5: Capability Center Alignment

目标：把 Harvis Relay 放到正确入口，避免 UI 定位混乱。

信息架构：

- 能力中心
  - 运行环境：Native Helper、Alpine Linux Sandbox、Embedded Lite、Termux fallback。
  - 扩展中心：Git、Node/npm、Lark CLI、GitHub CLI、Google Workspace CLI。
  - 账号订阅：ChatGPT/Codex、Claude、GitHub/Copilot、Google/Antigravity、Usage Hub。
  - 安全权限：MobileClaw、无障碍、后台运行、Credential Vault、Evidence Redaction。
  - 外部集成：Harvis Relay、Lark Relay、AgentWorkOS bridge。

- [ ] Harvis Relay 只出现在“外部集成”。
- [ ] 不出现在 CLI Hub 完整列表中。
- [ ] 不出现在 Native Helper / Linux Sandbox runtime 里。
- [ ] UI 文案不暗示 APK 内置 Harvis。

### P5 Acceptance

- [ ] 能力中心入口不重复。
- [ ] Harvis Relay 页面只做外部桥接配置和状态。
- [ ] Pure APK 不包含 Harvis Relay daemon 或私有配置。

## Recommended Execution Order

1. P0：先固定 evidence payload schema。
2. P1：实现 mock Harvis endpoint contract。
3. P2：配置真实 Lark relay 并完成 dry-run。
4. P3：跑通 E2E relay chain。
5. P4：再给 MobileCode 增加 `External Harvis Relay` 设置入口。
6. P5：最后收拢能力中心信息架构。

## Test Plan

必须验证：

- [ ] schema unit tests
- [ ] redaction tests
- [ ] mock Harvis endpoint tests
- [ ] `lark-relay` fixture tests
- [ ] E2E dry-run
- [ ] E2E live smoke
- [ ] MobileCode widget test：`External Harvis Relay` 设置入口
- [ ] `flutter test`
- [ ] `flutter analyze --no-fatal-infos --no-fatal-warnings`
- [ ] Dev Harness APK build
- [ ] secret scan

## Evidence / 已完成证据

只有真实命令、截图、日志、测试或 APK 验证通过后才能填写。

- [ ] P0 evidence:
- [ ] P1 evidence:
- [ ] P2 evidence:
- [ ] P3 evidence:
- [ ] P4 evidence:
- [ ] P5 evidence:

## Open Questions

- [ ] Harvis localhost API 是否已有稳定 endpoint，还是先使用 mock server。
- [ ] Lark Relay 使用 bot webhook、Lark CLI profile，还是事件订阅模式。
- [ ] MobileCode test event 是否只在 Dev Harness 暴露，还是 Pure APK 也显示配置入口。
- [ ] ack 是否需要回传到 MobileCode 聊天 trace，还是仅进入 relay evidence。
- [ ] 是否需要 HMAC / signature 保护跨设备 payload 来源。

## Assumptions

- Harvis Relay 是可选外部集成，不是 MobileCode 默认依赖。
- Pure APK 继续保持轻量，不打包 Harvis Relay daemon、rootfs 或 CLI 大资产。
- Dev Harness APK 可以展示更多集成入口，但仍不保存凭据。
- Lark bot、chat_id、Harvis endpoint 等真实配置只存在用户本机私有配置中。
- MobileCode 侧只保存安全状态、redacted evidence 和用户可见 recovery。
