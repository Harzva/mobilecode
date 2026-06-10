# 04 Task Bank Scale-up

## 目标

把 MobileHarnessBench 从 25 条 v0 seed tasks 扩展为可支撑论文实验设计的 candidate task bank。v1 已达到 200 条；v2 已继续扩展到 1000 条，质量治理详见 [05-benchmark-quality-upgrade.md](05-benchmark-quality-upgrade.md)。

## 范围

- In scope:
  - v1 200 条 machine-readable task definition。
  - v2 1000 条 machine-readable task definition。
  - v1 五类任务均衡覆盖：每类 40 条。
  - v2 六类任务覆盖，新增 `runtime_orchestration`。
  - 每条任务包含 fixture、capability、expected artifact、verifier、evidence requirement 和 blocked condition。
  - 生成脚本和校验脚本可复现。
- Out of scope:
  - 声称 200 条任务都已经跑过真实设备。
  - 声称 200 条任务都有完整 App 内 verifier。
  - 引入私有账号、私有仓库、公众号材料或本地绝对路径。

## Key Decisions

- [x] v1 任务规模目标从 50 条上调到 200 条候选任务。
  - Evidence: `docs/mobile-harness-benchmark/tasks/v1-task-bank.json`。
- [x] v1 先使用 capability matrix 扩容，不直接复制 v0 seed 文件。
  - Evidence: `scripts/generate_mobile_harness_task_bank.py`。
- [x] v1 candidate bank 与 v0 seed 分离。
  - Evidence: v0 保持 `tasks/v0-seed-tasks.json`，v1 使用 `tasks/v1-task-bank.json`。
- [x] v2 candidate bank 与 v1 分离。
  - Evidence: v2 使用 `tasks/v2-task-bank.json`。

## Task List

- [x] 创建 v1 task bank 生成脚本。
- [x] 生成 200 条 candidate tasks。
- [x] 每类任务达到 40 条。
- [x] 将 v1 task bank 纳入本地 validator。
- [x] 生成 1000 条 v2 candidate tasks。
- [x] 新增第 6 类 `runtime_orchestration`。
- [ ] 为 v1 每类至少选择 5 条做 verifier dry run。
- [ ] 将 v1 task bank 分层：smoke、offline、device、github-auth、release-artifact。
- [ ] 为 v1 增加人工质量抽检表，记录重复度、难度、可验证性和论文价值。

## Evidence / 已完成证据

- [x] 2026-06-06 `scripts/generate_mobile_harness_task_bank.py` 已创建。
- [x] 2026-06-06 `docs/mobile-harness-benchmark/tasks/v1-task-bank.json` 已生成 200 条任务。
- [x] 2026-06-06 本地校验通过：`v1_task_bank=200`，五类各 40 条。
- [x] 2026-06-06 `docs/mobile-harness-benchmark/tasks/v2-task-bank.json` 已生成 1000 条任务。
- [x] 2026-06-06 本地校验通过：`v2_task_bank=1000`，六类覆盖。

## Open Questions

- [ ] v2 是否需要从 1000 条 candidate 中抽取 120 条 frozen benchmark release？
- [ ] 真实设备 run 的最小证据是 DOM summary、截图还是录屏？
- [ ] GitHub delivery 类是否需要准备公开 sandbox repo，避免依赖私有授权？

## Test Plan

- [x] `python scripts/generate_mobile_harness_task_bank.py`。
- [x] `python scripts/validate_mobile_harness_bench.py`。
- [ ] 200 条任务做人工抽检，至少每类抽 5 条。
- [ ] v1 frozen subset 形成后跑 dry run 并输出 summary。

## Assumptions

- [ ] v1 candidate bank 是数据规模基础，不等同于实验完成。
- [ ] 论文中只能把已经有 run evidence 的任务计入实验结果。
