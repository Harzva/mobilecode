# MobileCode Roadmap Index

这个文件是 MobileCode 长期路线图的总索引。详细执行内容已经拆到 `roadmap/tasks/` 下，每个子任务一个文件，便于 Agent 单次只读取当前任务上下文，减少长文扫描和误改范围。

保留文件名 `roadmp.md` 是为了兼容当前仓库里已经建立的引用习惯。后续如果要改成 `roadmap.md`，应单独开一个小任务处理重命名和链接迁移。

## 为什么这样拆

- 更省上下文：执行某个任务时，只需要读本索引、对应任务文件、任务文件列出的少量源文件。
- 边界更清楚：每个任务都有 `Can edit`、`Do not edit`、`Out of scope`。
- 更利于接力：任务文件自带 handoff prompt，适合 Codex、Claude Code 或本地 `cc*` 执行通道使用。
- 更容易验收：每个任务都有独立验收标准和验证命令，不会把大路线图当成完成证明。
- 更安全：涉及 Git、Lark、GitHub、push、commit、token、Helper 的任务都明确 stop line。

## 本次任务完成记录

- [x] 复查本地角色库规则，按 `project-inventory + Codex current model` 处理项目组织任务。
- [x] 复查并更新 MobileCode `AGENTS.md`：Mac 本地编译是完整支持的一等路径，应优先用于本地验证；GitHub Actions 保留为远端 CI/发布复核。
- [x] 将原长文 `roadmp.md` 改造成轻量总索引。
- [x] 新建 `roadmap/tasks/` 子任务目录。
- [x] 将 MobileAgent 可借鉴内容拆成独立任务文件，并在本索引建立链接。
- [x] 为每个任务补充目标、边界、输入、输出、验收和 handoff。
- [x] 完成 T00-T23 收尾验收，闭环报告见 `docs/mobilecode-t00-t23-closure.md`。
- [x] 2026-06-25 新增 T25/T26 未完成任务定义：无障碍与后台权限产品化、Subscription Login 与 Usage Hub。
- [x] 2026-06-25 T25 代码实现已落地，Helper service 正式接入 Android app，Termux daemon 作为外部强 runtime 排在 EmbeddedLite 之前；Mac 本地 focused tests、targeted analyze、debug APK build、emulator Helper smoke 已通过；远端 CI workflow 已补入 T25 focused tests 和 tokenized Helper smoke，T25 仍保持未完成，等待远端 emulator smoke 和真机 QA 证据。

## 总体判断

MobileAgent v1.0.4 最值得 MobileCode 借鉴的是一套“可信手机端 Agent IDE”的工程骨架：

- 产品模块化：MobileCode、GitHub workflow、Lark/协作、Agent Harness Runtime、GitRuntime Lite 各有边界。
- 执行可信化：Plan、Dry-run Preview、Approval Queue、Human Approval、Execution Boundary、Audit Log。
- Git 结构化：不用任意 shell git 字符串，把 status、diff、file preview、commit plan、push preflight 拆成 JSON API。
- 发布诚实：capability matrix、risk register、blocked feature claims 检查、release readiness 检查。
- 手机原生边界：Android Helper 使用 app-private workspace、path validator、feature flags、no shell、no hooks。
- 协作外部写入：Lark/GitHub/报告类动作默认 preview-first，不静默发送、不静默创建远端对象。

MobileCode 当前已经有 `RuntimeManager`、`RuntimeProvider`、`MobileCode Helper`、NDJSON 流式任务、release QA 和版本策略。下一步不是扩大命令执行面，而是先补齐能力边界、GitRuntime、审批审计和发布治理。

## 执行规则

1. 执行任务时先读本文件，再读对应任务文件。
2. 只打开任务文件中 `Read first` 列出的源文件，除非遇到明确缺口。
3. 只修改任务文件中 `Can edit` 列出的路径。
4. 任务文件中的相对路径默认都相对 `MobileCode` 根目录，而不是相对任务文件自身目录。
5. Mac 环境优先本地编译、测试、安装和调试 MobileCode；GitHub Actions 用于远端 CI、发布打包和最终仓库侧复核。
6. 涉及 GitHub pull/push、Issues/PR、Actions、Releases 时，按仓库 `AGENTS.md` 使用对应 GitHub 技能或工作流。
7. 使用 `cc*` 本地模型执行通道时，产出必须回到当前 Codex 模型复核后才能接受。
8. 完成任务后同时更新任务文件状态和本索引 checkbox。

## 状态标记

- `[x]` 已完成或本次已建立。
- `[ ]` 待执行。
- `P0` 必须先做，属于边界和发布诚实基础。
- `P1` 核心产品能力。
- `P2` 协作、发布和体验扩展。
- `P3` 高风险 beta 或 1.0 后能力。

## T00-T23 收尾验收

T00-T23 已作为第一阶段 roadmap tranche 收口，详见 [T00-T23 Closure Report](docs/mobilecode-t00-t23-closure.md)。

这次收尾只代表任务闭环，不代表所有能力 Ready。当前诚实状态仍然是：Local Commit 为默认关闭 Beta；Push/Pull/Private Clone/Merge/Rebase 为 Blocked；Cloud Runtime 为 Coming Soon；GitHub/Lark/WeChat 等外部写入仍是 Preview/Draft。

## 子任务索引

| 状态 | 优先级 | 任务 | 文件 | 主要产出 |
| --- | --- | --- | --- | --- |
| [x] | P0 | Roadmap 拆分与维护规则 | [T00](roadmap/tasks/T00-roadmap-index-maintenance.md) | 当前索引结构、执行规则、更新协议 |
| [x] | P0 | MobileAgent 借鉴资产盘点 | [T01](roadmap/tasks/T01-mobileagent-borrowing-inventory.md) | 可借鉴资产清单、来源映射、不可照搬项 |
| [x] | P0 | MobileCode Capability Matrix | [T02](roadmap/tasks/T02-capability-matrix.md) | `docs/mobilecode-capability-matrix.md` |
| [x] | P0 | Risk Register | [T03](roadmap/tasks/T03-risk-register.md) | `docs/mobilecode-risk-register.md` |
| [x] | P0 | Security Model | [T04](roadmap/tasks/T04-security-model.md) | `docs/mobilecode-security-model.md` |
| [x] | P0 | Release Honesty Checks | [T05](roadmap/tasks/T05-release-honesty-checks.md) | blocked claims 与 release readiness 脚本 |
| [x] | P1 | Helper APK Runtime Hardening | [T06](roadmap/tasks/T06-helper-apk-runtime-hardening.md) | Helper APK 协议、token、health、foreground service |
| [x] | P1 | Runtime Provider Selection Evidence | [T07](roadmap/tasks/T07-runtime-provider-selection-evidence.md) | provider 选择证据与诊断模型 |
| [x] | P1 | Task Recovery 与 NDJSON Streaming | [T08](roadmap/tasks/T08-task-recovery-streaming.md) | 任务恢复、日志续读、stop 语义 |
| [x] | P1 | GitRuntime Read-only Contract | [T09](roadmap/tasks/T09-gitruntime-readonly-contract.md) | GitRuntime controller/model/API skeleton |
| [x] | P1 | Workspace Path Validator | [T10](roadmap/tasks/T10-workspace-path-validator.md) | workspace 安全路径校验 |
| [x] | P1 | Git File Preview 与 Redaction | [T11](roadmap/tasks/T11-git-file-preview-redaction.md) | 文件预览大小限制、脱敏、binary detect |
| [x] | P1 | GitRuntime Diagnostics UI | [T12](roadmap/tasks/T12-gitruntime-diagnostics-ui.md) | App 内 GitRuntime 诊断与 QA scenarios |
| [x] | P1 | Evidence Model | [T13](roadmap/tasks/T13-evidence-model.md) | runtime/git/collaboration/release 统一 evidence |
| [x] | P1 | Approval Queue 与 Audit Log | [T14](roadmap/tasks/T14-approval-queue-audit-log.md) | 审批队列、审计日志、可序列化存储 |
| [x] | P1 | Commit Plan 与 Secret Scan | [T15](roadmap/tasks/T15-commit-plan-secret-scan.md) | commit dry-run、secret scan、legacy gitCommit 替换 |
| [x] | P2 | Local Commit Beta | [T16](roadmap/tasks/T16-local-commit-beta.md) | feature-flagged Helper commit beta; default false |
| [x] | P2 | Push Preflight 与 Evidence Export | [T17](roadmap/tasks/T17-push-preflight-export.md) | push preflight checks、PR/Lark/Markdown 草稿导出 |
| [x] | P2 | Collaboration Actions | [T18](roadmap/tasks/T18-collaboration-actions.md) | 通用 preview-first 协作层模型与 demo preview |
| [x] | P2 | GitHub Workflow Assistant | [T19](roadmap/tasks/T19-github-workflow-assistant.md) | PR summary、Actions failure、issue triage、release notes draft preview |
| [x] | P2 | Public Preview Release Governance | [T20](roadmap/tasks/T20-public-preview-release-governance.md) | release process、QA 模板、截图计划、CI 门禁 |
| [x] | P2 | Contributor 与 Open-source Materials | [T21](roadmap/tasks/T21-contributor-open-source-materials.md) | onboarding、good first issues、issue templates |
| [x] | P3 | Legacy Execution Migration | [T22](roadmap/tasks/T22-legacy-execution-migration.md) | legacy `Process.run` 和 shell git 迁移计划 |
| [x] | P3 | Post-1.0 Git 与 Cloud Runtime | [T23](roadmap/tasks/T23-post-1-git-cloud-runtime.md) | private clone、pull、push beta、cloud runtime 长期边界 |
| [x] | P3 | Legacy RunCommand / InitGit Fail-closed | [T24](roadmap/tasks/T24-legacy-runcommand-initgit-fail-closed.md) | 关闭剩余 direct shell 和 git init legacy path |
| [ ] | P1 | Accessibility 与后台权限产品化 | [T25](roadmap/tasks/T25-accessibility-background-permissions.md) | 设置页无障碍服务、后台运行权限、状态检测和 QA 证据 |
| [ ] | P2 | Subscription Login 与 Usage Hub | [T26](roadmap/tasks/T26-subscription-login-usage-hub.md) | Claude、Copilot/GitHub、Antigravity/Google、Codex/ChatGPT 订阅登录和用量入口 |

## 推荐执行顺序

第一批先做 P0：

1. [T02 Capability Matrix](roadmap/tasks/T02-capability-matrix.md)
2. [T03 Risk Register](roadmap/tasks/T03-risk-register.md)
3. [T04 Security Model](roadmap/tasks/T04-security-model.md)
4. [T05 Release Honesty Checks](roadmap/tasks/T05-release-honesty-checks.md)

第二批做运行时和 GitRuntime 基础：

1. [T06 Helper APK Runtime Hardening](roadmap/tasks/T06-helper-apk-runtime-hardening.md)
2. [T07 Runtime Provider Selection Evidence](roadmap/tasks/T07-runtime-provider-selection-evidence.md)
3. [T08 Task Recovery 与 NDJSON Streaming](roadmap/tasks/T08-task-recovery-streaming.md)
4. [T09 GitRuntime Read-only Contract](roadmap/tasks/T09-gitruntime-readonly-contract.md)
5. [T10 Workspace Path Validator](roadmap/tasks/T10-workspace-path-validator.md)

第三批做可信执行体验：

1. [T13 Evidence Model](roadmap/tasks/T13-evidence-model.md)
2. [T14 Approval Queue 与 Audit Log](roadmap/tasks/T14-approval-queue-audit-log.md)
3. [T15 Commit Plan 与 Secret Scan](roadmap/tasks/T15-commit-plan-secret-scan.md)

第四批再做外部协作和 release：

1. [T18 Collaboration Actions](roadmap/tasks/T18-collaboration-actions.md)
2. [T19 GitHub Workflow Assistant](roadmap/tasks/T19-github-workflow-assistant.md)
3. [T20 Public Preview Release Governance](roadmap/tasks/T20-public-preview-release-governance.md)
4. [T21 Contributor 与 Open-source Materials](roadmap/tasks/T21-contributor-open-source-materials.md)

第五批做手机原生权限和订阅账户：

1. [T25 Accessibility 与后台权限产品化](roadmap/tasks/T25-accessibility-background-permissions.md)
2. [T26 Subscription Login 与 Usage Hub](roadmap/tasks/T26-subscription-login-usage-hub.md)

## 全局禁止线

- 不新增绕过 `RuntimeManager` 的执行路径。
- 不用任意 shell git 字符串实现长期 Git 能力。
- 不静默执行 `git push`、创建 PR、发送 Lark/WeChat/GitHub 消息。
- 不把 private clone、pull、merge、rebase、push beta 宣称为 ready。
- 不在日志、workspace、audit 中保存 token 或 secret 明文。
- 不把 Python Helper daemon、Android Helper APK、cloud runtime 混成一个无边界实现。
- Mac 本地编译、测试、安装和调试是优先验证路径；GitHub Actions 用于远端复核和发布制品。

## 全局完成标准

每个任务完成后，必须留下这些证据：

- 任务文件的 `Status` 更新。
- 本索引对应 checkbox 更新。
- 相关文档或代码路径明确列出。
- 验证方式明确写出；如果没有运行，也要说明原因。
- 风险和 deferred 项写入对应任务文件或 risk register。
