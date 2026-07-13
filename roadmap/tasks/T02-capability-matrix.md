# T02 MobileCode Capability Matrix

Status: [x] Completed
Priority: P0
Owner role: project-inventory + quality-reviewer
Depends on: T01

## Objective

建立 MobileCode 自己的能力矩阵，让 README、App 诊断页、release note 和用户预期保持一致。

## Read First

- `README.md`
- `docs/mobilecode-v1-runtime-release-closure.md`
- `docs/mobilecode-version-policy.md`
- `docs/mobilecode-release-qa.md`
- `docs/mobilecode-helper-runtime-protocol.md`
- `mobile_agent/lib/services/runtime_provider.dart`
- `mobile_agent/lib/services/runtime_manager.dart`
- `roadmap/tasks/T01-mobileagent-borrowing-inventory.md`

## Can Edit

- `docs/mobilecode-capability-matrix.md`
- `README.md` only to add a short link to the new matrix
- `roadmp.md`
- this task file

## Do Not Edit

- Runtime code.
- GitRuntime code.
- CI workflows.

## Required Matrix Categories

- Mobile app shell。
- Runtime providers。
- MobileCode Helper。
- Embedded/WebView preview。
- External Termux。
- Cloud runtime。
- Local file workspace。
- Git read-only。
- Git commit planning。
- Local commit beta。
- Push/pull/private clone/merge/rebase。
- GitHub workflow assistant。
- Collaboration actions。
- Release QA and APK evidence。

## Required Status Labels

- Ready：当前代码和验证证据都支持。
- Preview：可演示或 dry-run，但不应宣称生产可用。
- Beta：feature flag 或限定环境可用。
- Blocked：明确不支持，且不应出现隐式入口。
- Coming Soon：规划中，没有可执行入口。

## Implementation Tasks

- [x] 新建 `docs/mobilecode-capability-matrix.md`。
- [x] 为每项能力写 `Status`、`User-visible behavior`、`Evidence`、`Stop line`、`Next step`。
- [x] 把 MobileAgent GitRuntime 的 status label 方法迁移成 MobileCode 文档语言。
- [x] 在 README 增加一行链接，不展开长表。
- [x] 在本索引中保持 T02 未完成直到文档落地并被引用。

## Acceptance Criteria

- [x] 文档能回答”现在到底能做什么，不能做什么”。
- [x] 每个 Beta/Blocked 项都有 stop line。
- [x] README 不再孤立描述能力，能链接到矩阵。
- [x] 没有把 push、private clone、pull、merge、rebase 写成 Ready。

## Completion Notes

- `docs/mobilecode-capability-matrix.md` created with 14 capability items.
- Every item has Status, User-visible behavior, Evidence, Stop line, and Next step.
- Push/pull/private clone/merge/rebase correctly marked as Blocked with evidence from `agent_action_system.dart`.
- Later T09-T17/T22 passes updated the matrix: GitRuntime remains Preview where helper-backed or mock-backed, local commit is feature-flagged Beta by default, and push/pull/private clone/merge/rebase remain Blocked.
- README updated with Governance section linking to roadmap, capability matrix, and risk register.
- README opening claim was tightened so cloud execution and GitHub workflow automation are described as planned capabilities, not current Ready features.
- Evidence sources: `runtime_provider.dart`, `runtime_manager.dart`, `runtime_actions.dart`, `agent_action_system.dart`, `project_manager.dart`, `mobilecode-helper-runtime-protocol.md`, CI run evidence from `mobilecode-release-qa.md`.

## Validation

不本地构建。只做文档检查：

```powershell
Test-Path .\docs\mobilecode-capability-matrix.md
Select-String -Path .\docs\mobilecode-capability-matrix.md -Pattern "Ready|Preview|Beta|Blocked|Coming Soon"
```

## Handoff Prompt

请实现 T02。先读取本文件列出的 Read First。只创建能力矩阵文档和 README 短链接，不改功能代码。完成后更新本文件和 `roadmp.md` 的 checkbox。
