# T00 Roadmap 拆分与维护规则

Status: [x] Completed for initial split
Priority: P0
Owner role: project-inventory + Codex current model
Depends on: none

## Objective

把根目录 `roadmp.md` 从长篇路线图改成轻量索引，并把后续工作拆成可执行的独立任务文件。这个任务已经完成初始版本，后续只作为维护协议存在。

## Why This Helps Agents

- 单个 Agent 不需要读取整份长期规划，只打开当前任务文件。
- 每个任务文件给出可改路径，降低误改已有用户变更的风险。
- 每个任务都带有验收标准，方便 Codex 当前模型做最终复核。
- 可以让不同模型或不同会话处理不同任务，但最终接受权仍回到 Codex。

## Can Edit

- `roadmp.md`
- `roadmap/tasks/*.md`

## Do Not Edit

- 功能代码。
- CI 配置。
- README 或 docs 正文，除非某个具体任务要求。

## Maintenance Rules

- 新增任务时使用 `TNN-short-name.md` 命名。
- 任务 ID 一旦被引用，不要复用给其他语义。
- 任务文件中的相对路径默认都相对 `MobileCode` 根目录。
- 完成任务后同时更新任务文件 `Status` 和 `roadmp.md` 索引 checkbox。
- 任务文件里如果出现新的 deferred 项，应链接到下一任务或新建任务。
- 不要把任务文件写成泛泛计划；必须包含目标、边界、输入、输出、验收。

## Acceptance Criteria

- [x] `roadmp.md` 是任务索引，不再承载所有细节。
- [x] `roadmap/tasks/` 存在。
- [x] 每个任务文件都有状态、优先级、目标、边界和验收。
- [x] 本索引能直接链接到每个子任务。

## Handoff Prompt

继续维护 roadmap 时，请先读取 `roadmp.md` 和本文件。只调整任务索引、状态和任务描述，不要顺手实现功能代码。完成后同步更新 checkbox。
