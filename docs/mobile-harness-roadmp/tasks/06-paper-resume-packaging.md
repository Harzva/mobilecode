# 06 Paper And Resume Packaging

## 目标

把 Mobile Harness 论文工作包装成可公开展示、可简历表达、可面试讲清楚的研究型工程成果，同时保持证据边界。

## 范围

- 论文包装：method、algorithm、module、formula、figure/table、readiness gate。
- 简历包装：中英文 bullet、方法命名、面试讲述、证据路径。
- 公开边界：公开 README/论文只写 repo-safe 内容；本地简历智能体 handoff 可以放在 `docs/local/`。

## Key Decisions

- [x] 简历表达采用 evidence-bound 口径，不声称论文已录用、真实 mobile experiment 已完成或 baseline comparison 已完成。
  - Evidence: `docs/local/mobile-harness-resume-agent-handoff.md` 已写明禁止越界 claim。
- [x] 方法命名围绕 Mobile Harness，而不是普通 mobile IDE。
  - Evidence: handoff 文档将贡献整理为 Mobile Harness Control Plane、Evidence Ladder、Verifier Contract Catalog、Claim-to-Evidence Ledger 和 Submission Readiness Gate。
- [x] 本地绝对路径只放在 ignored local note，不进入公开 README、论文正文或匿名 supplement。
  - Evidence: `.gitignore` 增加 `docs/local/`。

## Task List

- [x] 生成本地简历智能体 handoff。
  - Evidence: `docs/local/mobile-harness-resume-agent-handoff.md`。
- [x] 给出中英文简历 bullet 草案。
  - Evidence: handoff 文档包含中文和英文 bullet。
- [x] 将方法总结为可命名算法/协议。
  - Evidence: handoff 文档包含 Evidence-Bound Harness Evaluation、Tiered Mobile Evidence Ladder、Verifier-Contract Task Scoring、Claim-to-Evidence Promotion Gate。
- [ ] 根据最终真实 Android/iOS 和 baseline evidence 更新简历数字。
- [ ] 将公开项目页补充为图文并茂的 Mobile Harness 页面。

## Evidence / 已完成证据

- 2026-06-09 已创建本地 handoff，供简历智能体读取论文、benchmark、readiness report 和 supplement 证据。
- 2026-06-09 已修正 benchmark README 中 reproducibility checklist 命令数为 16，避免包装材料与 validator 不一致。

## Open Questions

- 简历主版本需要偏研究员、移动端工程师、AI infra，还是创业项目负责人？
- 是否要把 Mobile Harness 作为单独项目条目，还是并入 MobileCode 项目条目？

## Test Plan

- `python scripts/validate_mobile_harness_bench.py` 必须通过。
- 匿名 supplement scan 必须不包含 `docs/local/` 中的本地路径。
- 公开 README、论文和 supplement 不得包含本地绝对路径、用户名、token、私有 repo URL。
