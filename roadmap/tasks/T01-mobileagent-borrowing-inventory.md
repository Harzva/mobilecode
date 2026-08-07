# T01 MobileAgent 借鉴资产盘点

Status: [x] Completed for initial inventory
Priority: P0
Owner role: project-inventory + Codex current model
Depends on: T00

## Objective

记录 MobileAgent v1.0.4 中值得 MobileCode 借鉴的资产，避免后续 Agent 每次都重新做全量扫描。这个文件是初始盘点摘要；如果后续需要更细证据，可扩展为 `docs/mobilecode-agent-borrowing-notes.md`。

## Read First

- `../MobileAgent-v1.0.4/README.md`
- `../MobileAgent-v1.0.4/docs/SECURITY_MODEL.md`
- `../MobileAgent-v1.0.4/docs/GIT_RUNTIME_LITE_PROTOCOL.md`
- `../MobileAgent-v1.0.4/docs/GIT_RUNTIME_LITE_SECURITY.md`
- `../MobileAgent-v1.0.4/docs/GIT_RUNTIME_CAPABILITY_MATRIX.md`
- `../MobileAgent-v1.0.4/docs/GIT_RUNTIME_RISK_REGISTER.md`
- `../MobileAgent-v1.0.4/docs/MobileAgent_GitRuntime_Next_Phase_roadmp.md`
- `../MobileAgent-v1.0.4/code/mobile_agent/lib/core/git_runtime/`
- `../MobileAgent-v1.0.4/code/mobile_agent/lib/modules/mobile_lark/`
- `../MobileAgent-v1.0.4/code/mobile_agent/lib/modules/mobile_github/`
- `../MobileAgent-v1.0.4/android-helper/`
- `../MobileAgent-v1.0.4/scripts/`

## Borrowable Assets

### Product Shell

- 模块注册：MobileCode、MobileGitHub、MobileLark 的 title、status、quick actions。
- App routes：home、compose、approvals、timeline、runner、git-runtime、workspace-files、settings。
- Status badge：Ready、Beta、Coming Soon、Blocked。

### Trust Runtime

- 安全链路：Prompt -> Plan -> Dry-run Preview -> Approval Queue -> Human Approval -> Execution Boundary -> Audit Log。
- 审批和审计 store。
- trust banner、approval sheet、runner health card、git runtime status card。

### GitRuntime Lite

- 结构化 controller，不接收任意 git command string。
- read-only API：health、clone dry-run、status、diff、diff-stat、file preview、private clone preflight。
- beta API：commit plan、secret scan、local commit beta、push preflight、push beta preflight、push evidence export。
- capability matrix 与 risk register。

### Lark / Collaboration

- action type、risk、dryRun、payload、preview、execute。
- demo mode 阻断真实外部动作。
- high-risk action 默认阻断。
- preview 失败时返回本地 dry-run fallback。

### GitHub Workflow

- PR summary、Actions failure report、issue triage、release notes draft。
- 默认 preview-only，不直接调用真实 GitHub 写入。

### Runner

- zod schema。
- idempotency key。
- audit log。
- redact secrets。
- truncate output。
- mock adapters。
- `MOBILEAGENT_ALLOW_EXECUTE` 这类执行开关。

### Android Helper

- JGit read-only/status/diff/file preview。
- app-private workspace。
- feature flags 默认关闭。
- path validator。
- no shell、no hooks、no Termux bundle。

### Release Governance

- release readiness scripts。
- blocked feature claims scripts。
- screenshot plan。
- native validation template。
- accessibility QA template。
- contributor onboarding。
- good first issues。
- issue templates。

## Must Not Copy Blindly

- 不复制 MobileAgent 品牌和营销口径。
- 不把 MobileLark 硬绑定成 MobileCode 的唯一协作层。
- 不复制任何“看起来能真实 push/send”的表述，除非 MobileCode 已实现完整审批、token、scope、audit。
- 不把 MobileAgent 的 mock Runner 当成 MobileCode production runtime。

## Acceptance Criteria

- [x] 可借鉴资产已按类别沉淀。
- [x] 已明确不应照搬的内容。
- [x] 后续任务能引用本文件作为来源摘要。

## Handoff Prompt

如需继续补充 MobileAgent 证据，请只追加“来源文件 -> 可借鉴点 -> MobileCode 落点”三列表，不要重写已有结论。若发现某项借鉴风险过高，移动到 Must Not Copy Blindly。
