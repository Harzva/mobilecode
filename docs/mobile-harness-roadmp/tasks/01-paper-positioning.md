# 01 论文定位与边界

## 目标

把 Mobile Harness 论文从产品介绍提升为可验证的系统论文：提出概念、定义系统边界、给出 benchmark 和实验证据。

## 范围

- In scope:
  - Mobile Harness 概念定义。
  - MobileCode 作为 phone-native AI coding harness 的系统实现。
  - MobileHarnessBench 作为评测协议。
  - PhoneWorld、AndroidWorld、AndroidControl 等相关工作对比。
- Out of scope:
  - 复刻 PhoneWorld 的通用 phone-use environments。
  - 声称训练新模型。
  - 声称完整替代桌面 IDE。

## Key Decisions

- [x] 论文题目方向采用 `Mobile Harness`，不采用 `Mobile IDE`。
  - Evidence: 2026-06-06 README 项目副标题为 `Phone-native AI Coding Harness`。
- [ ] 论文 claim 需要压缩为一句话。
- [ ] 需要明确 `harness` 与 `app shell`、`remote IDE`、`mobile GUI benchmark` 的区别。

## Task List

- [ ] 写 300 字中文论文摘要草稿。
- [ ] 写英文 abstract v0。
- [ ] 建立 related work 表格。
- [ ] 定义 3 个核心贡献点。
- [ ] 写 limitations 初版。

## Evidence / 已完成证据

- [x] PhoneWorld PDF 已保存到 `docs/research/phoneworld-scaling-phone-use-agent-environments-2605.29486.pdf`。
- [x] PhoneWorld 分析文档已保存到 `docs/mobile-harness/phoneworld-mobile-harness-era.md`。
- [x] 公众号深度文章已创建草稿，说明 public narrative 已开始验证。

## Open Questions

- [ ] 论文是否要把公众号文章作为 public outreach，而不是学术 evidence？
- [ ] 是否需要联系其他 mobile agent benchmark 的作者或公开仓库做对照？

## Test Plan

- [ ] 论文 claim 交给至少一个 reviewer 角色做反驳审查。
- [ ] related work 引用必须能定位到论文、代码或官方项目页。

## Assumptions

- [ ] 第一篇论文可以是 technical report，不必一次达到顶会完整实验规模。
