# Mobile Harness 长期路线图

目标：把 MobileCode 从 phone-native AI coding app 推进为可论文发表、可复现评测、可产品交付的 Mobile Harness 系统。

## 使用规则

- `[x]` 只代表已有文件、命令、截图、CI、草稿或提交能证明完成。
- `[ ]` 代表未完成、未验证、被阻塞、暂缓或仍需用户输入。
- 主路线图只记录方向、阶段和验收标准；执行细节放入 `tasks/`。
- benchmark 的事实来源、任务定义、验证器结果和失败样例必须可复查。
- 任何论文结论不能只来自产品叙述，必须有 task、verifier、trace 或用户流程证据支撑。

## 安全规则

- 不把 PhoneWorld、AndroidWorld 或其他论文写成对 MobileCode 的直接背书。
- 不声称“已发布论文”“已完成 benchmark”，除非有公开稿件、任务集、运行结果和复现说明。
- 不把未公开密钥、公众号 token、本地绝对私密路径写入公开 README 或论文正文。
- 不新增绕过 `RuntimeProvider`、`ActionRunner`、GitHub API 和 WebView 安全边界的执行入口。

## 当前基线

- 日期：2026-06-06。
- 主工作树：`MobileCode-last-recover-v039-next`。
- 当前分支：`last-recover-v068-work`，跟踪 `origin/last-recover-from-v039`。
- 当前产品定位：Phone-native AI Coding Harness。
- 已有研究锚点：PhoneWorld arXiv 2605.29486，本地 PDF 与分析文档已入仓库。
- 已有产品能力：ActionRunner、ActionEvidence、HTML/Markdown preview、external file preview、GitHub Repo Hub、GitHub Actions surface、Pages publish、RuntimeProvider。
- 当前缺口：MobileHarnessBench v2 1000 条任务已生成且已完成机器质量审计、T0 smoke dry run、baseline scaffold、一任务 baseline T0 dry-run 合约样本、baseline pilot prompt/evidence pack、pilot readiness gate、core claim readiness、evidence maturity matrix、evaluation protocol readiness、verifier contract readiness、bibliography readiness、mobile evidence capture pack、threats-to-validity matrix、page-limit readiness、reproducibility checklist 和 submission readiness gate；MobileCode Skill Spec、Harness Task Registry 和 App 内 Benchmark Lab 原型已启动；mobile-tier readiness probe 已记录当前本机缺少 `adb`/Xcode 工具。尚未完成真实 Android/iOS mobile run、正式 baseline comparison、全量 verifier implementation、App 内 verifier 执行层、真实设备 trace export、论文实验表格和 frozen subset。
- 当前 frozen 状态：已有 draft frozen paper subset manifest，但 `counts_as_final_paper_subset=false`；真实 T2/T3/T5 证据缺失前不能作为最终论文实验子集。

## Key Decisions

- [x] 论文方向采用 `Mobile Harness for AI Coding on Phones`，不是通用手机 GUI benchmark。
  - Evidence: 2026-06-06 README 增加 `Research Signal: Mobile Harness Era`；`docs/mobile-harness/phoneworld-mobile-harness-era.md` 记录边界。
- [x] benchmark 采用 `MobileHarnessBench` 命名，聚焦 AI coding harness 工作流。
  - Evidence: 2026-06-06 本路线图与 `docs/mobile-harness-benchmark/` 初始规格已创建。
- [x] 第一版论文按 ICLR anonymous submission draft 起草。
  - Evidence: `paper/iclr-mobile-harness/main.tex` 使用 ICLR 2026 LaTeX 模板，包含 abstract、system、benchmark、experiment plan、limitations。
- [ ] 具体 OpenReview venue/year 仍需确认：当前本地使用 `iclr2026.zip`，但正式上传前必须确认目标会议周期和官方模板版本。
- [x] benchmark 数据规模提升到 v1 200 条 candidate tasks，后续再冻结实验 subset。
  - Evidence: `docs/mobile-harness-benchmark/tasks/v1-task-bank.json` 与 `scripts/generate_mobile_harness_task_bank.py`。
- [x] benchmark 数据规模提升到 v2 1000 条 candidate tasks，类别从 5 类提升到 6 类。
  - Evidence: `docs/mobile-harness-benchmark/tasks/v2-task-bank.json`；新增 `runtime_orchestration`。
- [x] benchmark 测试分层采用 T0 offline、T1 Android emulator、T2 Android real device、T3 iOS simulator、T4 iOS real device、T5 GitHub sandbox。
  - Evidence: `docs/mobile-harness-benchmark/mobile-test-strategy.md`。
- [x] baseline 对照协议已定义为 `chat-only mobile coding flow`、`desktop remote IDE flow`、`MobileCode harness flow`；结果尚未完成。
  - Evidence: `docs/mobile-harness-benchmark/reports/baseline-protocol-readiness.md`。

## 总体验收标准

- [ ] 有公开可读的论文草稿，包含 abstract、method、benchmark、experiment、limitation。
- [x] 有本地 ICLR-style anonymous 初稿，包含 abstract、method、benchmark、experiment plan、limitation。
  - Evidence: `paper/iclr-mobile-harness/main.tex`。
- [x] 有 `MobileHarnessBench` v1 candidate task bank，至少 200 个任务，覆盖 5 类 mobile coding harness 场景。
  - Evidence: `python scripts/validate_mobile_harness_bench.py` 输出 `v1_task_bank=200`，五类各 40 条。
- [x] 有 `MobileHarnessBench` v2 candidate task bank，至少 1000 个任务，覆盖 6 类 mobile coding harness 场景。
  - Evidence: `python scripts/validate_mobile_harness_bench.py` 输出 `v2_task_bank=1000`。
- [ ] 有质量抽检报告，覆盖去重、可验证性、fixture 可信度、失败边界和论文价值。
- [x] 有 v2 machine quality audit report，覆盖结构、覆盖率、唯一性、task-set manifest 和 public-output safety。
  - Evidence: 2026-06-06 `python scripts/audit_mobile_harness_task_bank.py` 输出 `failed_gates=0`，报告见 `docs/mobile-harness-benchmark/reports/v2-quality-audit.md`。
- [x] 有 paper claim-to-evidence ledger，核心论文声明可追踪到具体 artifact，并保留真实 mobile/baseline open requirements。
  - Evidence: `docs/mobile-harness-benchmark/reports/paper-claim-evidence-ledger.md`。
- [x] 有 core claim readiness report，检查 control-plane positioning、非 full mobile IDE、非 general phone-use benchmark 和 evidence-first counting。
  - Evidence: `docs/mobile-harness-benchmark/reports/core-claim-readiness.md`。
- [x] 有 baseline-comparison protocol，定义三组对照、七个指标、公平性控制和当前阻塞项，但不计为实验结果。
  - Evidence: `docs/mobile-harness-benchmark/reports/baseline-protocol-readiness.md`，`counts_as_experiment=false`。
- [x] 有 baseline run contract，定义 future `baseline-run.json`、summary、metrics 和 evidence 字段，但结果数为 0。
  - Evidence: `docs/mobile-harness-benchmark/reports/baseline-run-contract.md`，`counts_as_baseline_result=false`。
- [x] 有 baseline scaffold，三组 baseline 均生成 `baseline-run.json` / summary / traces，但全部为 `scaffold_not_run`。
  - Evidence: `docs/mobile-harness-benchmark/baselines/2026-06-06-baseline-scaffold/`。
- [x] 有 baseline T0 dry-run 合约样本，三组 baseline 均生成 1 条 `dry_run_not_counted` blocked 结果，指标为空且不计为 baseline result。
  - Evidence: `docs/mobile-harness-benchmark/baselines/2026-06-06-baseline-dry-run-t0/`。
- [x] 有 baseline pilot prompt/evidence pack，三组 baseline 均有 prompt、model lock、人类介入记录表和 evidence template，但状态仍为 `pilot_ready_no_results`。
  - Evidence: `docs/mobile-harness-benchmark/baselines/2026-06-06-baseline-pilot-pack/`。
- [x] 有 baseline pilot readiness gate，声明可执行 non-counted pilot，但不能计入 baseline result。
  - Evidence: `docs/mobile-harness-benchmark/reports/baseline-pilot-readiness.md`。
- [x] 有 evidence maturity matrix，将当前证据分为 7 个成熟度阶段，并明确 counted mobile/baseline result 阶段仍为空。
  - Evidence: `docs/mobile-harness-benchmark/reports/evidence-maturity-matrix.md`。
- [x] 有 bibliography readiness report，当前 related-work 条目元数据已验证并纳入 validator。
  - Evidence: `docs/mobile-harness-benchmark/reports/bibliography-readiness.md`。
- [x] 有 mobile evidence capture pack，准备 T2 Android real-device 和 T3 iOS simulator 采集模板与 execution playbook，但不计为实验结果。
  - Evidence: `docs/mobile-harness-benchmark/reports/mobile-evidence-pack-readiness.md`，`ready_for_counted_mobile_experiment=false`。
- [x] 有 threats-to-validity matrix，将 construct/internal/external/baseline/privacy/submission risks 映射到 open requirements。
  - Evidence: `docs/mobile-harness-benchmark/reports/threats-to-validity.md`。
- [x] 有 evaluation protocol readiness report，将 E1-E5 绑定到 task sets、证据等级、7 个 primary metrics 和 open requirements。
  - Evidence: `docs/mobile-harness-benchmark/reports/evaluation-protocol-readiness.md`。
- [x] 有 verifier contract readiness report，将 v0/v1/v2 当前任务引用的 12 个 verifier id 映射到 machine-readable contract。
  - Evidence: `docs/mobile-harness-benchmark/reports/verifier-contract-readiness.md`。
- [x] 有 MobileCode Skill Spec，将 skill package 定义为 `SKILL.md`、`scripts/index.html`、permission token 和 verifier contract。
  - Evidence: `docs/mobile-harness-benchmark/skill-spec.md`。
- [x] 有 Harness Task Registry，将 Tools、bottom sheets、pushed routes、skills 和 benchmark evidence 映射到统一 task metadata。
  - Evidence: `docs/mobile-harness-benchmark/harness-task-registry.md`。
- [x] 有 reproducibility checklist，将当前草稿复现命令映射到 expected artifacts，并明确 full empirical reproduction 仍未完成。
  - Evidence: `docs/mobile-harness-benchmark/reports/reproducibility-checklist.md`。
- [x] 有 page-limit readiness report，将当前编译 PDF 页数、Ethics 页和 References 起始页纳入机器检查。
  - Evidence: `docs/mobile-harness-benchmark/reports/page-limit-readiness.md`。
- [x] 有 submission readiness gate，将论文草稿、证据边界、核心定位、匿名 supplement、reviewer manifest evidence labels、bibliography readiness、mobile evidence pack、verifier contract readiness、threats matrix、evaluation protocol readiness、reproducibility checklist、page-limit readiness 和 open submission requirements 串成一个本地自检报告。
  - Evidence: `docs/mobile-harness-benchmark/reports/submission-readiness.md`，`ready_for_submission_upload=false`。
- [ ] 有 frozen benchmark release subset，任务数量、抽样规则、verifier 和运行证据已锁定。
- [x] 有 draft frozen paper subset manifest，固定 60 条计划任务并记录下一层证据要求。
  - Evidence: `docs/mobile-harness-benchmark/tasks/frozen-v2-paper-subset.json`，`counts_as_final_paper_subset=false`。
- [ ] 有真实 Android device 和 Mac iOS simulator 的 smoke run evidence。
- [x] 每个 benchmark 任务都有 machine-readable task definition 和 verifier contract。
  - Evidence: `docs/mobile-harness-benchmark/verifiers/verifier-contracts.json` 与 `docs/mobile-harness-benchmark/reports/verifier-contract-readiness.md` 覆盖 1225 条当前任务定义。
- [ ] 至少跑通 3 组 baseline，并产出 task success、verified success、trace completeness、recovery rate、artifact availability 等指标。
- [ ] App 内至少接入一条 verifier report 流程，能从任务执行进入 evidence/preview/report。
- [ ] 有可公开 demo：论文页、README、GitHub Pages、benchmark package、复现实验说明。

## Phase 0：论文定位与边界

详见：[01-paper-positioning.md](tasks/01-paper-positioning.md)

- [x] 提炼 PhoneWorld 对 Mobile Harness 的启发。
  - Evidence: `docs/mobile-harness/phoneworld-mobile-harness-era.md`。
- [x] 写出论文核心 claim：手机端 AI coding 的关键不是完整本地 IDE，而是 harness control plane。
  - Evidence: `docs/mobile-harness-benchmark/reports/core-claim-readiness.md`。
- [ ] 明确不做通用 App 操作 benchmark，不复刻 PhoneWorld。
- [ ] 完成 related work 表：PhoneWorld、AndroidWorld、AndroidControl、GUI agent、coding agent、mobile IDE。

## Phase 1：MobileHarnessBench v0

详见：[02-mobile-harness-benchmark.md](tasks/02-mobile-harness-benchmark.md)

- [x] 建立 benchmark 目录、任务 schema、25 个种子任务和本地校验脚本。
  - Evidence: `docs/mobile-harness-benchmark/` 与 `scripts/validate_mobile_harness_bench.py`。
- [x] 为每个种子任务补充初始 fixture。
  - Evidence: 2026-06-06 `docs/mobile-harness-benchmark/fixtures/` 包含 26 个 fixture 文件。
- [ ] 为每个种子任务补充 expected artifact 和 verifier implementation。
- [x] 形成 v0 runbook：如何运行、如何记录失败、如何导出报告。
  - Evidence: `docs/mobile-harness-benchmark/runbook.md` 已包含离线代表任务 dry run 和设备 dry run 流程。
- [x] 选定 5 个代表性任务做离线 dry run。
  - Evidence: `docs/mobile-harness-benchmark/tasks/representative-v0.json` 与 `docs/mobile-harness-benchmark/runs/2026-06-06-v0-dry-run/summary.md`，5 个任务覆盖 5 类，4 passed，1 blocked。

## Phase 1.5：Task Bank Scale-up

详见：[04-task-bank-scaleup.md](tasks/04-task-bank-scaleup.md)

- [x] 生成 200 条 v1 candidate tasks。
  - Evidence: `docs/mobile-harness-benchmark/tasks/v1-task-bank.json`。
- [x] 将 v1 task bank 纳入本地 validator。
  - Evidence: 2026-06-06 `python scripts/validate_mobile_harness_bench.py` 输出 `v1_task_bank=200`。
- [ ] 为 v1 每类至少选择 5 条做 verifier dry run。
- [ ] 形成 frozen benchmark release subset。

## Phase 1.6：Benchmark Quality Upgrade

详见：[05-benchmark-quality-upgrade.md](tasks/05-benchmark-quality-upgrade.md)

- [x] 生成 1000 条 v2 candidate tasks。
  - Evidence: `docs/mobile-harness-benchmark/tasks/v2-task-bank.json`。
- [x] 类别从 5 类提升到 6 类。
  - Evidence: `runtime_orchestration` 已加入 schema、validator 和 v2 task bank。
- [x] v2 每条任务加入质量字段。
  - Evidence: validator 对 v2 校验 `quality_gates`、`sampling_tags`、`scenario.quality_axis`、mobile profile 和 test oracle。
- [x] 形成 v2 machine quality audit。
  - Evidence: `docs/mobile-harness-benchmark/reports/v2-quality-audit.md`，状态 `passed_with_limits`，`failed_gates=0`。
- [x] 形成 v2 smoke、Android device、iOS simulator 初始分层 task set。
  - Evidence: `tasks/smoke-v2.json`、`tasks/android-device-v2.json`、`tasks/ios-simulator-v2.json`。
- [x] 形成 mobile-tier readiness probe。
  - Evidence: `docs/mobile-harness-benchmark/reports/mobile-tier-readiness.md`，当前 Android `adb_missing`、iOS `xcrun_missing`，`counts_as_experiment=false`。
- [x] 形成 draft frozen paper subset manifest。
  - Evidence: `docs/mobile-harness-benchmark/tasks/frozen-v2-paper-subset.json`，60 tasks，6 类各 10 条。
- [ ] 形成 v2 offline/github-auth/runtime 完整分层 task set。
- [ ] 形成 frozen paper subset。
- [ ] 将 draft frozen subset 升级为 final frozen paper subset，必须附带 T2/T3/T5 证据。

## Phase 1.7：Mobile Test Strategy

详见：[mobile-test-strategy.md](../mobile-harness-benchmark/mobile-test-strategy.md)

- [x] 定义 T0-T5 测试分层。
  - Evidence: `docs/mobile-harness-benchmark/mobile-test-strategy.md`。
- [x] 明确真实手机测试是论文证据层。
  - Evidence: T2 Android real device 与 T4 iOS real device 规则。
- [x] 明确 Mac iOS simulator 是必要回归层，但不能替代真实 iPhone。
  - Evidence: T3/T4 边界说明。
- [x] 生成 `smoke-v2.json`，每类 10 条。
  - Evidence: `docs/mobile-harness-benchmark/tasks/smoke-v2.json`。
- [x] 生成 Android real device 测试子集，每类 5 条。
  - Evidence: `docs/mobile-harness-benchmark/tasks/android-device-v2.json`。
- [x] 生成 Mac iOS simulator 测试子集，每类 3 条。
  - Evidence: `docs/mobile-harness-benchmark/tasks/ios-simulator-v2.json`。
- [ ] Android real device 跑 smoke subset。
- [ ] Mac iOS simulator 跑 iOS smoke subset。

## Phase 2：Verifier Layer

详见：[03-verifier-layer.md](tasks/03-verifier-layer.md)

- [x] 写出 verifier contract 初版。
  - Evidence: `docs/mobile-harness-benchmark/verifiers/verifier-contract.md`。
- [x] 写出 machine-readable verifier contract catalog，并检查当前 task bank 引用覆盖。
  - Evidence: `docs/mobile-harness-benchmark/verifiers/verifier-contracts.json` 与 `docs/mobile-harness-benchmark/reports/verifier-contract-readiness.md`。
- [x] 为 5 个代表任务补充 stdlib verifier implementation。
  - Evidence: `scripts/run_mobile_harness_bench.py` 与 `docs/mobile-harness-benchmark/runs/2026-06-06-v0-dry-run/run.json`。
- [ ] 在 App 侧定义 `VerifierResult` 数据模型。
- [ ] 接入 HTML preview verifier：文件存在、WebView 可打开、DOM 有内容、无明显移动端溢出。
- [ ] 接入 Markdown preview verifier：可解析、标题密度、图片引用、移动端段落节奏。
- [ ] 接入 GitHub verifier：commit SHA、Pages URL、Actions artifact。

## Phase 3：Trace Dataset 与 Evidence Export

- [ ] 定义 trace export JSONL：prompt、tool call、result、artifact、verifier、recovery。
- [ ] 从现有 ActionEvidence 中导出最小 trace report。
- [ ] 区分公开 trace、脱敏 trace、内部 trace。
- [ ] 形成 20 条可公开 trace 样例，用于论文 appendix 或 benchmark package。

## Phase 4：App 产品接入

- [x] 在 MobileCode 中增加 Benchmark Lab / Harness Eval 原型入口。
  - Evidence: `mobile_agent/lib/screens/benchmark_lab_screen.dart` 与 Tools 页 `Benchmark Lab` pushed route。
- [ ] 支持选择任务、运行任务、显示 verifier report。
- [ ] 支持导出 task report 到本地 Markdown/JSON。
- [ ] 支持把 benchmark evidence 附到 GitHub issue/release/Pages。

## Phase 5：论文写作与实验

- [x] 写 abstract 和 introduction。
  - Evidence: `paper/iclr-mobile-harness/main.tex`。
- [x] 写 system design：MobileCode harness、runtime boundary、evidence model、verifier layer。
  - Evidence: `paper/iclr-mobile-harness/main.tex`。
- [x] 写 benchmark design：任务分类、指标、验证器、复现方式。
  - Evidence: `paper/iclr-mobile-harness/main.tex`。
- [x] 跑 v0 实验并生成第一版结果表。
  - Evidence: `paper/iclr-mobile-harness/main.tex` 与 `docs/mobile-harness-benchmark/runs/2026-06-06-v0-dry-run/summary.md`。
- [x] 写 limitations：不是通用 phone-use benchmark、样本规模小、真实设备差异、API 权限差异。
  - Evidence: `paper/iclr-mobile-harness/main.tex`。
- [x] 写匿名 supplement 边界：纳入范围、排除范围、脱敏规则和验证 gate。
  - Evidence: `paper/iclr-mobile-harness/SUPPLEMENT_BOUNDARY.md`。
- [x] 跑 T0 `smoke-v2` 并生成离线 fixture 结果表。
  - Evidence: 2026-06-06 `python scripts/run_mobile_harness_bench.py --task-set smoke-v2 --run-id 2026-06-06-smoke-v2-t0` 输出 `result_counts={'blocked': 10, 'passed': 50}`，`privacy_check.status=passed`。
- [ ] 将需要真实设备的 `smoke-v2` 任务补充 T2/T3/T4 mobile-tier evidence。
- [ ] 跑 Android real device / Mac iOS simulator subset 并补入论文。
- [ ] 完成 baseline comparison。
- [x] 生成当前草稿匿名 supplement zip，并通过身份、路径、token 和 repo URL 扫描。
  - Evidence: 2026-06-06 `python scripts\prepare_mobile_harness_supplement.py` 生成 `paper/iclr-mobile-harness/build/mobile-harness-anonymous-supplement.zip`，staged file count 由脚本输出，脚本报告 `Anonymous supplement staging passed`。
- [x] 生成 submission readiness gate，明确当前草稿可审阅但不可标记为正式 upload-ready。
  - Evidence: 2026-06-06 `python scripts\generate_mobile_harness_submission_readiness.py` 输出 `ready_for_submission_upload=False`、`open_gates=3`。
- [x] 生成 bibliography readiness report，替换 draft BibTeX metadata 并验证正文引用覆盖。
  - Evidence: 2026-06-06 `python scripts\generate_mobile_harness_bibliography_readiness.py` 输出 `entries=9`、`status=passed`。
- [x] 生成 mobile evidence capture pack，准备 48 个 T2/T3 任务采集模板和 execution playbook。
  - Evidence: 2026-06-06 `python scripts\generate_mobile_harness_mobile_evidence_pack.py` 输出 `task_count=48`、`template_count=53`、`status=capture_ready_no_results`，并生成 `execution-playbook.md`。
- [x] 生成 threats-to-validity matrix，强化论文 limitations 与审稿风险边界。
  - Evidence: 2026-06-06 `python scripts\generate_mobile_harness_threats_to_validity.py` 输出 `threats=6`、`status=passed_with_open_requirements`。
- [x] 生成 evaluation protocol readiness report，强化 E1-E5 评测协议、7 个 primary metrics 与证据等级边界。
  - Evidence: 2026-06-06 `python scripts\generate_mobile_harness_evaluation_protocol_readiness.py` 输出 `protocols=5`、`metrics=7`、`complete_evaluation=False`。
- [x] 生成 method presentation readiness report，强化论文图、算法、模块接口、公式和证据边界的机器检查。
  - Evidence: 2026-06-06 `python scripts\generate_mobile_harness_method_presentation_readiness.py` 输出 `checks=5`、`ready_for_method_review=True`。
- [x] 生成 verifier contract readiness report，检查 12 个 verifier contract 覆盖当前 v0/v1/v2 任务定义引用。
  - Evidence: 2026-06-06 `python scripts\generate_mobile_harness_verifier_contract_readiness.py` 输出 `contracts=12`、`task_definitions_checked=1225`。
- [x] 生成 reproducibility checklist，强化论文复现命令和匿名 supplement 产物边界。
  - Evidence: 2026-06-06 `python scripts\generate_mobile_harness_reproducibility_checklist.py` 输出 `commands=16`、`full_empirical_reproduction=False`。
- [x] 生成 page-limit readiness report，强化页数风险和 References 起始页证据。
  - Evidence: 2026-06-06 `python scripts\generate_mobile_harness_page_limit_readiness.py` 输出 `pdf_pages=10`、`references_start_page=9`、`within_main_text_limit=True`。
- [ ] 真实 mobile runs、baseline 结果和最终 BibTeX 更新后，重新生成最终匿名 supplement zip。

## Phase 6：公开发布

- [x] README 增加 benchmark 和 paper draft 入口。
  - Evidence: `README.md` 的 `Research Signal: Mobile Harness Era` 增加 ICLR draft 链接。
- [x] README 和开发者页增加 On-device AI Gallery pattern 启发说明。
  - Evidence: README `Inspired by On-device AI Gallery Patterns` 与 GitHub Pages Developer 页。
- [x] 准备本地简历智能体 handoff，用 evidence-bound 口径包装 Mobile Harness 项目。
  - Evidence: [06-paper-resume-packaging.md](tasks/06-paper-resume-packaging.md)。
- [ ] GitHub Pages 增加 Mobile Harness / Benchmark 页面。
- [ ] 公众号文章系列继续输出：PhoneWorld 解读、MobileHarnessBench 设计、MobileCode 实验报告。
- [ ] 发布 arXiv 技术报告或 workshop draft。

## 测试计划

- [x] 2026-06-06 `python scripts/validate_mobile_harness_bench.py` 校验通过。
  - Evidence: `tasks=25 categories={'code_edit': 5, 'file_intake': 5, 'github_delivery': 5, 'harness_evidence': 5, 'preview_verification': 5}`。
- [x] 2026-06-06 `python scripts/run_mobile_harness_bench.py --task-set representative-v0 --run-id 2026-06-06-v0-dry-run` 通过。
  - Evidence: `result_counts={'blocked': 1, 'passed': 4}`，`privacy_check.status=passed`。
- [x] 2026-06-06 `python scripts/validate_mobile_harness_bench.py` 已纳入 run 产物校验。
  - Evidence: `runs=2 validated`。
- [x] 2026-06-06 `python scripts/generate_mobile_harness_task_bank.py` 生成 v1 200 条 candidate tasks。
  - Evidence: `docs/mobile-harness-benchmark/tasks/v1-task-bank.json`。
- [x] 2026-06-06 `python scripts/validate_mobile_harness_bench.py` 已纳入 v1 task bank 校验。
  - Evidence: `v1_task_bank=200 categories={'code_edit': 40, 'file_intake': 40, 'github_delivery': 40, 'harness_evidence': 40, 'preview_verification': 40}`。
- [x] 2026-06-06 `python scripts/generate_mobile_harness_task_bank.py` 生成 v2 1000 条 candidate tasks。
  - Evidence: `docs/mobile-harness-benchmark/tasks/v2-task-bank.json`。
- [x] 2026-06-06 `python scripts/validate_mobile_harness_bench.py` 已纳入 v2 task bank 校验。
  - Evidence: `v2_task_bank=1000 categories={'code_edit': 167, 'file_intake': 167, 'github_delivery': 167, 'harness_evidence': 166, 'preview_verification': 167, 'runtime_orchestration': 166}`。
- [x] 2026-06-06 v2 task bank 已加入差异化 mobile profile、mobile requirements 和 test oracle。
  - Evidence: `python scripts/validate_mobile_harness_bench.py` 对 v2 开启唯一 title/user_goal 和 mobile 字段校验。
- [x] 2026-06-06 v2 task bank machine quality audit 已完成。
  - Evidence: `python scripts/audit_mobile_harness_task_bank.py` 输出 `passed_with_limits`、`task_count=1000`、`failed_gates=0`。
- [x] 2026-06-06 `smoke-v2` T0 离线 dry run 已完成。
  - Evidence: `docs/mobile-harness-benchmark/runs/2026-06-06-smoke-v2-t0/summary.md`，60 tasks，50 passed，10 blocked，0 failed。
- [x] 2026-06-06 mobile-tier readiness probe 已完成。
  - Evidence: `python scripts/collect_mobile_harness_mobile_tier_evidence.py` 输出 Android blocked、iOS blocked；报告声明 `counts_as_experiment=false`。
- [x] 2026-06-06 mobile evidence capture pack 已生成并纳入 validator。
  - Evidence: `python scripts/generate_mobile_harness_mobile_evidence_pack.py` 输出 `task_count=48`、`template_count=53`；validator 检查 `counts_as_mobile_experiment=false`、53 个 template paths 和 execution playbook。
- [x] 2026-06-06 draft frozen paper subset manifest 已生成。
  - Evidence: `python scripts/generate_mobile_harness_frozen_subset.py` 输出 `task_count=60`、`counts_as_final_paper_subset=False`。
- [x] 2026-06-06 mobile 测试策略已创建。
  - Evidence: `docs/mobile-harness-benchmark/mobile-test-strategy.md`。
- [x] 2026-06-06 当前草稿匿名 supplement staging/zip 生成并通过扫描。
  - Evidence: `python scripts/prepare_mobile_harness_supplement.py` 输出 `files=<script output>`、`zip_bytes=<script output>`、`Anonymous supplement staging passed`。
- [x] 2026-06-06 paper claim-to-evidence ledger 已生成并纳入 validator。
  - Evidence: `python scripts/generate_mobile_harness_claim_ledger.py` 输出 `claims=6`、`open_requirements=1`。
- [x] 2026-06-06 core claim readiness 已生成并纳入 validator。
  - Evidence: `python scripts/generate_mobile_harness_core_claim_readiness.py` 输出 `claims=4`、`counts_as_experiment=False`。
- [x] 2026-06-06 baseline protocol readiness report 已生成并纳入 validator。
  - Evidence: `python scripts/generate_mobile_harness_baseline_protocol.py` 输出 `baselines=3`、`metrics=7`、`counts_as_experiment=False`。
- [x] 2026-06-06 baseline run contract 已生成并纳入 validator。
  - Evidence: `python scripts/generate_mobile_harness_baseline_run_contract.py` 输出 `baseline_count=3`、`metric_count=7`、`counts_as_baseline_result=False`。
- [x] 2026-06-06 baseline scaffold 已生成并纳入 validator。
  - Evidence: `python scripts/generate_mobile_harness_baseline_scaffold.py` 输出 `baselines=3`、`task_count_per_baseline=60`、`counts_as_baseline_result=False`；validator 输出 `baseline_scaffolds=3 validated`。
- [x] 2026-06-06 baseline T0 dry-run 已生成并纳入 validator。
  - Evidence: `python scripts/generate_mobile_harness_baseline_dry_run.py` 输出 `selected_task=MH-CE-209`、`baselines=3`、`counts_as_baseline_result=False`；validator 输出 `baseline_dry_runs=3 validated`。
- [x] 2026-06-06 baseline pilot pack 已生成并纳入 validator。
  - Evidence: `python scripts/generate_mobile_harness_baseline_pilot_pack.py` 输出 `selected_task=MH-CE-209`、`baselines=3`、`counts_as_baseline_result=False`；validator 输出 `baseline_pilot_pack=3 validated`。
- [x] 2026-06-06 baseline pilot readiness 已生成并纳入 validator。
  - Evidence: `python scripts/generate_mobile_harness_baseline_pilot_readiness.py` 输出 `ready_for_counted_baseline_result=False`；validator 输出 `reports=14 validated`。
- [x] 2026-06-06 evidence maturity matrix 已生成并纳入 validator。
  - Evidence: `python scripts/generate_mobile_harness_evidence_maturity_matrix.py` 输出 `stage_count=7`、`counted_mobile_stages=0`、`counted_baseline_stages=0`；validator 纳入 reports 校验。
- [x] 2026-06-06 evaluation protocol readiness 已生成并纳入 validator。
  - Evidence: `python scripts/generate_mobile_harness_evaluation_protocol_readiness.py` 输出 `protocols=5`、`metrics=7`、`complete_evaluation=False`；validator 检查 E1-E5 protocol ids、status、evidence artifacts 和 7 个 primary metrics。
- [x] 2026-06-09 MobileCode Skill Spec 和 Harness Task Registry 已创建。
  - Evidence: `docs/mobile-harness-benchmark/skill-spec.md` 与 `docs/mobile-harness-benchmark/harness-task-registry.md`。
- [x] 2026-06-09 App 内 Benchmark Lab 原型入口已创建。
  - Evidence: `mobile_agent/lib/screens/benchmark_lab_screen.dart` 与 `mobile_agent/lib/screens/home_screen.dart` Tools 入口。
- [x] 2026-06-06 bibliography readiness 已生成并纳入 validator。
  - Evidence: `python scripts/generate_mobile_harness_bibliography_readiness.py` 输出 `entries=9`；validator 检查 9 个 eprint/source URL、正文引用覆盖和零 draft entries。
- [x] 2026-06-06 submission readiness gate 已生成并纳入 validator。
  - Evidence: `python scripts/generate_mobile_harness_submission_readiness.py` 输出 `ready_for_submission_upload=False`、`open_gates=3`；validator 检查 16 个 gate 和 4 个 open requirements。
- [x] 2026-06-06 threats-to-validity matrix 已生成并纳入 validator。
  - Evidence: `python scripts/generate_mobile_harness_threats_to_validity.py` 输出 `threats=6`；validator 检查 6 个 threat ids、open requirements 和 evidence artifacts。
- [ ] Flutter 层 verifier model 加入后运行 `flutter test`。
- [ ] README / Pages 更新后触发 GitHub Pages deploy。
- [ ] 每个 benchmark release 都保留 task JSON、run JSON、summary Markdown 和截图证据。

## Assumptions

- [ ] 第一篇论文以 scoped system-and-benchmark paper 为主，不承诺大规模训练。
- [ ] benchmark v0 先服务论文可信度和产品收敛，不追求覆盖所有手机 App。
- [ ] MobileCode 的论文价值来自“手机端 coding harness 工作流”，不是模型本身。

## Open Questions

- [ ] ICLR 正式上传使用哪个 venue/year、页面限制和模板版本？
- [ ] v1 benchmark 是否需要真实 Android 设备录屏证据？
- [ ] baseline 是否能稳定跑在同一模型和同一 prompt 条件下？
- [ ] 是否需要开放匿名 trace 数据集，还是只开放任务和 verifier？
