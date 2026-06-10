# MobileHarnessBench Runbook

## 运行前检查

- [ ] 确认任务 JSON 通过结构校验。
- [ ] 确认测试 workspace 不包含私密 token。
- [ ] 确认 GitHub 授权、Pages、Actions 权限可用；不可用时记录为 `blocked`。
- [ ] 确认设备或模拟器支持目标预览能力。

## v0 离线代表任务 dry run

本地先跑一组不依赖账号和设备状态的 deterministic dry run，每类 1 个任务。

```powershell
python scripts/run_mobile_harness_bench.py --task-set representative-v0 --run-id 2026-06-06-v0-dry-run
python scripts/validate_mobile_harness_bench.py
```

当前代表任务：

- `MH-FI-001`：外部 HTML 文件入口。
- `MH-CE-004`：invalid JSON 修复。
- `MH-PV-001`：HTML preview snapshot。
- `MH-GD-001`：GitHub commit 交付；离线环境必须标记 `blocked`，不能伪造远程写入。
- `MH-HE-001`：完整 action trace。

任务集合来源：[tasks/representative-v0.json](tasks/representative-v0.json)。本地校验会检查该 manifest 与 `v0-seed-tasks.json` 的 task id、category 和 fixture 是否一致。

## v0 手动 / 设备 dry run

1. 选择 5 个任务，每类 1 个。
2. 在 MobileCode 中执行任务。
3. 保存输入、action trace、产物路径、预览 URL、截图或 DOM summary。
4. 按 `rubric.md` 评分。
5. 把失败写入 run report，不删除失败样例。

离线代表任务通过后，再进入真实设备或真实 GitHub 权限 dry run。外部权限不可用时只允许记录为 `blocked`。

## Mobile 环境测试

完整测试分层见：[mobile-test-strategy.md](mobile-test-strategy.md)。

- 必须有真实手机测试。MobileCode 是 phone-native harness，文件分享、Open with、WebView、后台恢复、低内存和真实网络不能只靠桌面脚本证明。
- Android real device 是当前最重要的移动证据层，优先验证 `file_intake`、`preview_verification` 和 `runtime_orchestration`。
- Android emulator 可做自动化回归，但不能替代真实分享入口和设备状态。
- Mac 上的 iOS simulator 需要纳入回归，用于 iOS WebView、Document Picker、Files app 基础流和 Xcode log。
- iOS simulator 不能替代真实 iPhone；Open In、真实分享链路、后台限制、权限和蜂窝网络仍需要 iOS real device。
- GitHub delivery 类必须使用 sandbox repo，不使用私有账号或私有仓库作为公开 benchmark 依赖。

可选工具参考：[simutil](https://github.com/dungngminh/simutil)。它可以用于在终端里启动 iOS Simulator、Android Emulator 或准备 Android 真机无线连接。它只属于测试环境准备工具，不属于 verifier；benchmark 仍必须输出 `run.json`、`summary.md`、`traces.jsonl` 和 `device-metadata.json`。

## candidate task banks

v1 当前是 200 条 candidate tasks，每类 40 条。v2 当前是 1000 条 candidate tasks，覆盖 6 类，并新增 `runtime_orchestration`。它们用于扩大论文和 benchmark 的任务覆盖面，但未经过 dry run 的任务不能计入实验结果。

```powershell
python scripts/generate_mobile_harness_task_bank.py
python scripts/validate_mobile_harness_bench.py
```

v1 后续执行顺序：

1. 从 200 条 candidate tasks 中抽取每类至少 5 条做 offline verifier dry run。
2. 按 smoke、offline、device、github-auth、release-artifact 分层。
3. 再冻结一组可复现实验 subset。
4. 只把有 `run.json`、`summary.md`、`traces.jsonl` 的任务计入论文实验表。

v2 后续执行顺序：

1. 从 1000 条 candidate tasks 中按 6 类抽取 smoke subset，每类 10 条：[tasks/smoke-v2.json](tasks/smoke-v2.json)。
2. Android 真机子集每类 5 条：[tasks/android-device-v2.json](tasks/android-device-v2.json)。
3. Mac iOS simulator 子集每类 3 条：[tasks/ios-simulator-v2.json](tasks/ios-simulator-v2.json)。
4. 对每条候选任务执行质量门槛检查：去重、可验证性、fixture 可信度、失败边界、论文价值。
5. 将任务分为 `smoke`、`offline`、`device`、`github-auth`、`release-artifact` 和 `runtime` 层。
6. 形成 frozen paper subset；论文只引用 frozen subset 和对应 run evidence。

## 运行产物

每次 run 应产出：

```text
runs/<date>-<run-id>/
├─ run.json
├─ summary.md
├─ traces.jsonl
├─ artifacts/
└─ screenshots/
```

`summary.md` 面向公开阅读，必须使用 repo-relative path 或 synthetic preview route。内部绝对路径、账号标识和密钥不得写入公开报告。

## 报告字段

- task_id
- model_provider
- model_name
- runtime_backend
- app_version
- started_at
- finished_at
- verifier_status
- failure_kind
- artifact_paths
- preview_urls
- human_intervention_count
- notes
