# 02 MobileHarnessBench

## 目标

建立 MobileHarnessBench：一个专门评测手机端 AI coding harness 的任务集、指标和验证协议。

## 范围

- In scope:
  - 文件入口、代码编辑、预览验证、GitHub 交付、harness evidence、runtime orchestration 六类任务。
  - 任务 JSON schema。
  - verifier contract。
  - v0 25 个种子任务。
  - v1 200 条 candidate task bank。
  - v2 1000 条 candidate task bank。
- Out of scope:
  - 大规模真实 App GUI 操作。
  - 需要训练模型的 RL 环境。
  - 私有账号或私有仓库依赖任务。

## Key Decisions

- [x] v0 采用 5 类任务，每类 5 个任务。
  - Evidence: `docs/mobile-harness-benchmark/tasks/v0-seed-tasks.json`。
- [x] 每个任务必须声明 verifier、expected artifact 和 evidence requirements。
  - Evidence: `docs/mobile-harness-benchmark/schema/mobile_harness_task.schema.json`。
- [x] v1 candidate bank 先扩展到 200 条任务，再从中冻结实验 subset。
  - Evidence: `docs/mobile-harness-benchmark/tasks/v1-task-bank.json`。
- [x] v2 candidate bank 扩展到 1000 条任务，并新增 runtime orchestration 类。
  - Evidence: `docs/mobile-harness-benchmark/tasks/v2-task-bank.json`。

## Task List

- [x] 创建 benchmark README。
- [x] 创建 JSON schema。
- [x] 创建 25 个种子任务。
- [x] 创建本地结构校验脚本。
- [x] 为 25 个种子任务补初始 fixture。
- [x] 创建 `representative-v0` 任务集合 manifest。
- [x] 创建 v1 200 条 candidate task bank。
- [x] 创建 v2 1000 条 candidate task bank。
- [x] 新增第 6 类 `runtime_orchestration`。
- [x] 为 5 个代表任务补 verifier implementation。
- [x] 跑一次离线代表任务 dry run，并记录 blocked 样例。
- [ ] 跑一次真实设备 dry run，并记录截图或 WebView evidence。
- [ ] 将全部 25 个 seed tasks 扩展到可执行 verifier。
- [ ] 从 200 条 candidate tasks 中抽取 frozen subset 并跑 verifier dry run。
- [ ] 从 1000 条 v2 candidate tasks 中抽取 smoke/offline/device/frozen subsets 并跑 verifier dry run。

## Evidence / 已完成证据

- [x] 2026-06-06 `scripts/validate_mobile_harness_bench.py` 已创建。
- [x] 2026-06-06 本地校验通过：`tasks=25`，5 个 category 各 5 个任务。
- [x] 2026-06-06 fixture 文件已补齐：`docs/mobile-harness-benchmark/fixtures/` 包含 26 个文件。
- [x] 2026-06-06 `docs/mobile-harness-benchmark/tasks/representative-v0.json` 已创建，本地校验会检查 task id、category、fixture 与 seed task 一致。
- [x] 2026-06-06 `docs/mobile-harness-benchmark/tasks/v1-task-bank.json` 已创建，包含 200 条 candidate tasks。
- [x] 2026-06-06 `docs/mobile-harness-benchmark/tasks/v2-task-bank.json` 已创建，包含 1000 条 candidate tasks。
- [x] 2026-06-06 `docs/mobile-harness-benchmark/fixtures/runtime/` 已创建，支撑 runtime orchestration 类。
- [x] 2026-06-06 `scripts/run_mobile_harness_bench.py` 已创建，覆盖 `MH-FI-001`、`MH-CE-004`、`MH-PV-001`、`MH-GD-001`、`MH-HE-001`。
- [x] 2026-06-06 `docs/mobile-harness-benchmark/runs/2026-06-06-v0-dry-run/` 已生成 `run.json`、`summary.md`、`traces.jsonl` 和 5 个 artifact。
- [x] 2026-06-06 本地 run 校验通过：`runs=1 validated`。

## Open Questions

- [ ] v0 是否要包含 iOS artifact 检查，还是先只验证 Android/GitHub artifact？
- [ ] benchmark 是否需要区分 on-device run 和 desktop simulation run？

## Test Plan

- [x] `python scripts/validate_mobile_harness_bench.py`。
- [x] `python scripts/generate_mobile_harness_task_bank.py`。
- [x] `python scripts/run_mobile_harness_bench.py --task-set representative-v0 --run-id 2026-06-06-v0-dry-run`。
- [x] 抽取 5 个代表任务，每类 1 个，核查 task 描述、fixture、verifier 和 run evidence 是否一致。
- [ ] 真实设备 dry run 后核查截图、WebView URL、GitHub permission blocked/available 分支。

## Assumptions

- [ ] v0 benchmark 先验证 harness 流程，不评估模型智能上限。
