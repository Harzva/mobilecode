# 03 Verifier Layer

## 目标

把 MobileCode 的 preview、publish readiness、Actions artifact、runtime health 和 evidence report 收敛成统一 verifier layer。

## 范围

- In scope:
  - HTML verifier。
  - Markdown verifier。
  - External file preview verifier。
  - GitHub Pages verifier。
  - Actions artifact verifier。
  - Evidence trace completeness verifier。
- Out of scope:
  - 任意 shell 执行验证。
  - 绕过 GitHub API 的远程仓库写入。
  - 未授权账号或私有 token 检查。

## Key Decisions

- [x] verifier contract 先作为文档和 benchmark 协议定义。
  - Evidence: `docs/mobile-harness-benchmark/verifiers/verifier-contract.md`。
- [x] verifier contract 同时有 machine-readable catalog，用于检查 task bank 引用覆盖。
  - Evidence: `docs/mobile-harness-benchmark/verifiers/verifier-contracts.json` 与 `docs/mobile-harness-benchmark/reports/verifier-contract-readiness.md`。
- [x] v0 先用 stdlib 离线 verifier 证明协议，不把外部授权缺失伪装成成功。
  - Evidence: `scripts/run_mobile_harness_bench.py` 中 `MH-GD-001` 输出 `github_auth_blocked`。
- [ ] App 内模型待确定：`VerifierResult` 是独立模型，还是扩展 `ActionEvidence`。
- [ ] 失败类型需要稳定字符串，避免跨层 enum import cycle。

## Task List

- [x] 写 verifier contract 初版。
- [x] 写 machine-readable verifier contract catalog，并生成 coverage readiness。
- [x] 增加 5 个代表任务的 benchmark verifier runner。
- [ ] 在 Flutter core 层增加 `VerifierResult`。
- [ ] 增加 HTML verifier service。
- [ ] 增加 Markdown verifier service。
- [ ] 增加 GitHub artifact verifier。
- [ ] 将 verifier report 显示到任务结果卡。

## Evidence / 已完成证据

- [x] 2026-06-06 verifier contract 文档已创建。
- [x] 2026-06-06 verifier contract catalog 已创建，12 个 verifier 覆盖当前 v0/v1/v2 1225 条任务定义引用。
- [x] 2026-06-06 `scripts/run_mobile_harness_bench.py` 已实现 `external_file_verifier`、`html_preview_verifier`、`json_verifier`、`snapshot_verifier`、`github_delivery_verifier`、`trace_verifier` 的离线代表任务版本。
- [x] 2026-06-06 `docs/mobile-harness-benchmark/runs/2026-06-06-v0-dry-run/run.json` 包含 5 个 `VerifierResult`，4 passed，1 blocked。

## Open Questions

- [ ] verifier 是否需要直接产出截图，还是第一版只产出 metadata 和 DOM summary？
- [ ] verifier result 是否进入 ActionEvidenceStore，还是单独存储？

## Test Plan

- [x] `python scripts/run_mobile_harness_bench.py --task-set representative-v0 --run-id 2026-06-06-v0-dry-run`。
- [x] `python scripts/validate_mobile_harness_bench.py`，包含 run 产物结构、artifact 路径、trace task id 和 public-safe marker 校验。
- [ ] Dart unit tests 覆盖 success、warning、blocked、failed。
- [ ] Benchmark seed task dry run 至少覆盖 3 种 failure kind。

## Assumptions

- [ ] 第一版 verifier 不依赖原生 bitmap screenshot。
