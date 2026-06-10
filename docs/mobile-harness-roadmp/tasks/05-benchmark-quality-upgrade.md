# 05 Benchmark Quality Upgrade

## 目标

把 MobileHarnessBench 从“任务数量扩容”推进到“高质量、可验证、可论文复现”的 benchmark 数据工程。

## 范围

- In scope:
  - v2 1000 条 candidate tasks。
  - 任务类别从 5 类提升到 6 类。
  - 新增 `runtime_orchestration` 类，覆盖 RuntimeProvider、Helper、Termux fallback、WebViewOnly、runtime switch 和 task stop。
  - 每条 v2 task 必须包含 `quality_gates`、`sampling_tags` 和 `scenario.quality_axis`。
  - 每条 v2 task 必须包含 mobile profile、mobile requirements 和 test oracle。
  - 建立质量分层、人工抽检、verifier 覆盖率、设备证据和 frozen subset 规则。
- Out of scope:
  - 声称 1000 条任务都已经实验完成。
  - 用生成数量替代真实 verifier result。
  - 在公开任务库中加入私有账号、私有仓库、token、media id 或本地绝对路径。

## Quality Gates

- [x] 结构质量：每条任务都有 id、category、fixture、capability、artifact、verifier、evidence 和 blocked condition。
  - Evidence: `python scripts/validate_mobile_harness_bench.py`。
- [x] 类别质量：v2 覆盖 6 类，包含新增 `runtime_orchestration`。
  - Evidence: `docs/mobile-harness-benchmark/tasks/v2-task-bank.json`。
- [x] 任务质量标签：v2 每条任务都有 `quality_gates` 和 `sampling_tags`。
  - Evidence: validator 对 v2 开启 `require_quality_fields=True`。
- [x] 差异化质量：v2 每条任务都有唯一 `title` 和 `user_goal`，并声明 mobile profile、test oracle 和 mobile requirements。
  - Evidence: `scripts/validate_mobile_harness_bench.py` 对 v2 执行重复检测和 mobile 字段校验。
- [x] Mobile 测试策略：T0/T1/T2/T3/T4/T5 分层已定义。
  - Evidence: `docs/mobile-harness-benchmark/mobile-test-strategy.md`。
- [x] 机器质量审计：v2 覆盖结构、唯一性、类别平衡、quality axis、mobile profile、task-set manifests 和 public-output safety。
  - Evidence: 2026-06-06 `python scripts/audit_mobile_harness_task_bank.py` 输出 `failed_gates=0`，报告见 `docs/mobile-harness-benchmark/reports/v2-quality-audit.md`。
- [x] 证据可追踪性：论文核心 claim 已映射到具体 task bank、run、readiness 和 frozen subset artifacts。
  - Evidence: `docs/mobile-harness-benchmark/reports/paper-claim-evidence-ledger.md`。
- [x] Baseline 协议质量：三组对照、指标、公平性控制和证据要求已机器可读化，但不计为实验结果。
  - Evidence: `docs/mobile-harness-benchmark/reports/baseline-protocol-readiness.md`。
- [x] Baseline run contract 质量：future baseline result 的 JSON schema、summary、metrics 和 evidence 字段已定义，但结果数为 0。
  - Evidence: `docs/mobile-harness-benchmark/schema/baseline_run.schema.json` 与 `docs/mobile-harness-benchmark/reports/baseline-run-contract.md`。
- [x] Baseline scaffold 质量：三组 baseline 均有 `not_run` scaffold，验证 run shape 但不产生 baseline result。
  - Evidence: `docs/mobile-harness-benchmark/baselines/2026-06-06-baseline-scaffold/`。
- [x] Baseline dry-run 质量：三组 baseline 均有一任务 `dry_run_not_counted` blocked 样本，验证非结果 dry-run 形状和证据边界。
  - Evidence: `docs/mobile-harness-benchmark/baselines/2026-06-06-baseline-dry-run-t0/`。
- [x] Baseline pilot pack 质量：三组 baseline 均有 prompt、model lock、人类介入记录表和 evidence template，准备下一步真实 pilot。
  - Evidence: `docs/mobile-harness-benchmark/baselines/2026-06-06-baseline-pilot-pack/`。
- [x] Baseline pilot readiness 质量：机器检查 pilot pack 已具备 non-counted pilot 输入，但明确 counted result 未就绪。
  - Evidence: `docs/mobile-harness-benchmark/reports/baseline-pilot-readiness.md`。
- [x] Evidence maturity 质量：用 7 阶段矩阵区分 candidate、T0、readiness、pilot-ready 和 counted result，防止论文过度声明。
  - Evidence: `docs/mobile-harness-benchmark/reports/evidence-maturity-matrix.md`。
- [x] Core claim readiness 质量：检查 control-plane positioning、非 full mobile IDE、非 general phone-use benchmark 和 evidence-first counting。
  - Evidence: `docs/mobile-harness-benchmark/reports/core-claim-readiness.md`。
- [x] Evaluation protocol readiness 质量：将论文 E1-E5 绑定到 task sets、证据等级、7 个 primary metrics、当前状态和 open requirements。
  - Evidence: `docs/mobile-harness-benchmark/reports/evaluation-protocol-readiness.md`。
- [x] Reproducibility checklist 质量：将当前草稿复现命令映射到 expected artifacts，并明确 full empirical reproduction 仍为 open requirement。
  - Evidence: `docs/mobile-harness-benchmark/reports/reproducibility-checklist.md`。
- [x] Bibliography readiness 质量：当前 related-work 条目有 source URL、eprint metadata、正文引用覆盖和零作者占位。
  - Evidence: `docs/mobile-harness-benchmark/reports/bibliography-readiness.md`。
- [x] Mobile evidence capture 质量：为 48 个 T2/T3 任务生成采集模板、device metadata 模板、run manifest 模板和 checklist，但不计为 mobile experiment。
  - Evidence: `docs/mobile-harness-benchmark/reports/mobile-evidence-pack-readiness.md`。
- [x] Mobile execution playbook 质量：固定 Android T2 / iOS T3 执行顺序、必需产物和 non-result promotion boundary。
  - Evidence: `docs/mobile-harness-benchmark/mobile-evidence/2026-06-06-mobile-evidence-pack/execution-playbook.md`。
- [x] Verifier contract 质量：12 个 verifier id 均有 machine-readable contract，覆盖当前 v0/v1/v2 共 1225 条任务定义引用。
  - Evidence: `docs/mobile-harness-benchmark/reports/verifier-contract-readiness.md`。
- [x] Threats-to-validity 质量：6 类审稿风险映射到 evidence artifacts 和 open requirements，不计为实验结果。
  - Evidence: `docs/mobile-harness-benchmark/reports/threats-to-validity.md`。
- [x] Page-limit readiness 质量：用编译后的 PDF 记录总页数、Ethics 页和 References 起始页，证明当前 main-text boundary 未越过 9 页限制。
  - Evidence: `docs/mobile-harness-benchmark/reports/page-limit-readiness.md`。
- [x] Submission readiness 质量：用 16 个 gate 汇总 manuscript、claim boundary、core claim positioning、mobile boundary、mobile evidence pack、verifier contract readiness、baseline boundary、anonymous supplement boundary、reviewer manifest gate、submission metadata、bibliography metadata、threats matrix、evaluation protocol readiness、method presentation readiness、reproducibility checklist 和 page-limit readiness，不把草稿标记为 upload-ready。
  - Evidence: `docs/mobile-harness-benchmark/reports/submission-readiness.md`。
- [ ] 内容质量：1000 条任务完成去重、人工抽检和可验证性评分。
- [x] 执行质量：至少 60 条 v2 任务有 T0 dry run 结果，每类至少 10 条。
  - Evidence: 2026-06-06 `smoke-v2` T0 dry run 输出 60 条结果，50 passed，10 blocked，0 failed。
- [ ] 设备质量：至少 30 条 v2 任务有真实设备或模拟器证据。
- [x] 论文质量：draft frozen subset 有固定版本、抽样规则、T0 结果和下一层证据要求。
  - Evidence: `docs/mobile-harness-benchmark/tasks/frozen-v2-paper-subset.json`。
- [ ] 论文质量：final frozen subset 有真实 T2/T3/T5 证据、失败样例和复现说明。

## Task List

- [x] 将 v2 task bank 扩展到 1000 条。
- [x] 新增第 6 类 `runtime_orchestration`。
- [x] 为 runtime 类创建 fixture。
- [x] 将 schema 和 validator 升级到 6 类。
- [x] 为 v2 candidate tasks 增加差异化 mobile profile 和 test oracle。
- [x] 写出 mobile environment test strategy。
- [x] 生成 `v2-quality-audit.md`，记录机器质量审计结果。
  - Evidence: `docs/mobile-harness-benchmark/reports/v2-quality-audit.md`，状态 `passed_with_limits`。
- [x] 为 v2 创建 `smoke-v2.json`，每类 10 条。
- [ ] 为 v2 创建 `offline-v2.json`，只包含不依赖账号和设备授权的任务。
- [x] 为 v2 创建 `android-device-v2.json`，每类 5 条。
- [x] 为 v2 创建 `ios-simulator-v2.json`，每类 3 条。
- [x] 生成 mobile-tier readiness report。
  - Evidence: `docs/mobile-harness-benchmark/reports/mobile-tier-readiness.md`，当前本机缺少 `adb` 和 `xcrun`。
- [ ] 为 v2 创建 `device-v2.json`，合并需要 WebView、文件分享、runtime 状态或截图证据的任务。
- [ ] 为 v2 创建 `github-auth-v2.json`，明确需要 GitHub 授权的任务。
- [x] 形成 draft `frozen-v2-paper-subset.json`。
  - Evidence: `counts_as_final_paper_subset=false`，只用于论文子集规划。
- [ ] 将 `frozen-v2-paper-subset.json` 升级为 final，论文实验只引用有 mobile-tier/GitHub sandbox evidence 的任务。

## Evidence / 已完成证据

- [x] 2026-06-06 `docs/mobile-harness-benchmark/tasks/v2-task-bank.json` 已生成 1000 条任务。
- [x] 2026-06-06 v2 类别分布：`file_intake=167`、`code_edit=167`、`preview_verification=167`、`github_delivery=167`、`harness_evidence=166`、`runtime_orchestration=166`。
- [x] 2026-06-06 `docs/mobile-harness-benchmark/fixtures/runtime/` 已加入 5 个 runtime fixtures。
- [x] 2026-06-06 `docs/mobile-harness-benchmark/schema/mobile_harness_task.schema.json` 已加入 `runtime_orchestration`。
- [x] 2026-06-06 `scripts/validate_mobile_harness_bench.py` 已校验 v2 的 1000 条、6 类分布和质量字段。
- [x] 2026-06-06 `scripts/validate_mobile_harness_bench.py` 已校验 v2 的唯一 title、唯一 user_goal、mobile requirements 和 test oracle。
- [x] 2026-06-06 `scripts/audit_mobile_harness_task_bank.py` 已生成 v2 machine quality audit。
  - Evidence: `docs/mobile-harness-benchmark/reports/v2-quality-audit.md` 与 `docs/mobile-harness-benchmark/reports/v2-quality-audit.json`。
- [x] 2026-06-06 `docs/mobile-harness-benchmark/mobile-test-strategy.md` 已定义真实手机、Android emulator、iOS simulator、iOS real device 和 GitHub sandbox 分层。
- [x] 2026-06-06 `docs/mobile-harness-benchmark/tasks/smoke-v2.json` 已创建，60 条任务，每类 10 条。
- [x] 2026-06-06 `docs/mobile-harness-benchmark/tasks/android-device-v2.json` 已创建，30 条任务，每类 5 条。
- [x] 2026-06-06 `docs/mobile-harness-benchmark/tasks/ios-simulator-v2.json` 已创建，18 条任务，每类 3 条。
- [x] 2026-06-06 `scripts/collect_mobile_harness_mobile_tier_evidence.py` 已生成 mobile-tier readiness report。
  - Evidence: Android `adb_missing`，iOS `xcrun_missing`，不计入实验。
- [x] 2026-06-06 `scripts/generate_mobile_harness_frozen_subset.py` 已生成 draft frozen subset manifest。
  - Evidence: `docs/mobile-harness-benchmark/tasks/frozen-v2-paper-subset.json` 与 `docs/mobile-harness-benchmark/reports/frozen-subset-readiness.md`。
- [x] 2026-06-06 `scripts/generate_mobile_harness_claim_ledger.py` 已生成 paper claim-to-evidence ledger。
  - Evidence: `docs/mobile-harness-benchmark/reports/paper-claim-evidence-ledger.md`，6 claims，1 个 open requirement。
- [x] 2026-06-06 `scripts/generate_mobile_harness_baseline_protocol.py` 已生成 baseline protocol readiness report。
  - Evidence: `docs/mobile-harness-benchmark/reports/baseline-protocol-readiness.md`，3 baselines，7 metrics，`counts_as_experiment=false`。
- [x] 2026-06-06 `scripts/generate_mobile_harness_baseline_run_contract.py` 已生成 baseline run contract。
  - Evidence: `docs/mobile-harness-benchmark/reports/baseline-run-contract.md`，3 baselines，7 metrics，0 results。
- [x] 2026-06-06 `scripts/generate_mobile_harness_baseline_scaffold.py` 已生成 baseline scaffold。
  - Evidence: 3 baseline dirs，每个 60 个 `not_run` 任务，`counts_as_baseline_result=false`。
- [x] 2026-06-06 `scripts/generate_mobile_harness_baseline_dry_run.py` 已生成 baseline T0 dry-run。
  - Evidence: 3 baseline dirs，每个 1 个 `blocked` dry-run 任务，`counts_as_baseline_result=false`。
- [x] 2026-06-06 `scripts/generate_mobile_harness_baseline_pilot_pack.py` 已生成 baseline pilot pack。
  - Evidence: 3 baseline dirs，每个 1 份 `prompt.md` 和 `evidence-template.json`，并生成 model lock / human intervention 模板。
- [x] 2026-06-06 `scripts/generate_mobile_harness_baseline_pilot_readiness.py` 已生成 baseline pilot readiness report。
  - Evidence: `ready_for_pilot_execution=true`，`ready_for_counted_baseline_result=false`。
- [x] 2026-06-06 `scripts/generate_mobile_harness_evidence_maturity_matrix.py` 已生成 evidence maturity matrix。
  - Evidence: 7 stages，0 counted mobile stages，0 counted baseline stages。
- [x] 2026-06-06 `scripts/generate_mobile_harness_core_claim_readiness.py` 已生成 core claim readiness report。
  - Evidence: 4 claims，`counts_as_experiment=false`。
- [x] 2026-06-06 `scripts/generate_mobile_harness_bibliography_readiness.py` 已生成 bibliography readiness report。
  - Evidence: 9 verified entries，0 draft entries。
- [x] 2026-06-06 `scripts/generate_mobile_harness_mobile_evidence_pack.py` 已生成 mobile evidence capture pack。
  - Evidence: 48 tasks，53 templates，execution playbook，`capture_ready_no_results`。
- [x] 2026-06-06 `scripts/generate_mobile_harness_threats_to_validity.py` 已生成 threats-to-validity matrix。
  - Evidence: 6 threats，`passed_with_open_requirements`。
- [x] 2026-06-06 `scripts/generate_mobile_harness_evaluation_protocol_readiness.py` 已生成 evaluation protocol readiness report。
  - Evidence: 5 protocols，7 metrics，`complete_evaluation=false`。
- [x] 2026-06-06 `scripts/generate_mobile_harness_method_presentation_readiness.py` 已生成 method presentation readiness report。
  - Evidence: 5 checks，`ready_for_method_review=true`。
- [x] 2026-06-06 `scripts/generate_mobile_harness_verifier_contract_readiness.py` 已生成 verifier contract readiness report。
  - Evidence: 12 contracts，1225 task definitions，`counts_as_experiment=false`。
- [x] 2026-06-06 `scripts/generate_mobile_harness_reproducibility_checklist.py` 已生成 reproducibility checklist。
  - Evidence: 16 commands，`full_empirical_reproduction=false`。
- [x] 2026-06-06 `scripts/generate_mobile_harness_page_limit_readiness.py` 已生成 page-limit readiness report。
  - Evidence: `pdf_pages=10`，`references_start_page=9`，`within_main_text_limit=true`。
- [x] 2026-06-06 `scripts/generate_mobile_harness_submission_readiness.py` 已生成 submission readiness gate。
  - Evidence: 16 gates，`ready_for_submission_upload=false`，3 open gates。
- [x] 2026-06-09 MobileCode Skill Spec 已创建，定义 `SKILL.md`、`scripts/index.html`、permission token 和 verifier contract。
  - Evidence: `docs/mobile-harness-benchmark/skill-spec.md`。
- [x] 2026-06-09 Harness Task Registry 已创建，将现有 Tools、bottom sheets、routes 和 benchmark evidence 统一为 task metadata。
  - Evidence: `docs/mobile-harness-benchmark/harness-task-registry.md`。

## Long-term Milestones

- [ ] Milestone A：1000 条 candidate task bank 稳定生成并通过 validator。
- [x] Milestone B：`smoke-v2.json` 有 T0 dry run report。
  - Evidence: `docs/mobile-harness-benchmark/runs/2026-06-06-smoke-v2-t0/summary.md`。
- [ ] Milestone C：`android-device-v2.json` 有 T2 real-device run report。
- [ ] Milestone D：每类至少 5 条有 Android real device 证据。
- [ ] Milestone E：iOS simulator smoke subset 在 Mac 上跑通。
- [x] Milestone F0：生成 60 条 draft paper subset planning manifest。
  - Evidence: `docs/mobile-harness-benchmark/tasks/frozen-v2-paper-subset.json`。
- [ ] Milestone F：冻结最终 paper subset，包含成功、失败、blocked 和 recovery 样例。
- [x] Milestone G0：App 内 Benchmark Lab 原型能展示 task registry、T0 evidence 和 open gates。
  - Evidence: `mobile_agent/lib/screens/benchmark_lab_screen.dart`。
- [ ] Milestone G：App 内 Benchmark Lab 能运行 frozen subset 并导出 report。
- [ ] Milestone H：论文实验表只引用 frozen subset 和可复查 run evidence。

## Open Questions

- [ ] 1000 条 candidate 是否需要外部标注者做二次质量审核？
- [ ] runtime 类是否需要拆成 `runtime_health` 和 `runtime_control` 两类？
- [ ] frozen subset 的目标规模是 60、120 还是 200？
- [ ] 真实设备证据是否接受 DOM summary，还是必须有截图/录屏？
- [ ] iOS simulator smoke 是否放在 GitHub Actions macOS runner，还是本地 Mac + Xcode？

## Test Plan

- [x] `python scripts/generate_mobile_harness_task_bank.py`。
- [x] `python scripts/validate_mobile_harness_bench.py`。
- [x] `python scripts/audit_mobile_harness_task_bank.py`。
- [x] `python scripts/collect_mobile_harness_mobile_tier_evidence.py`。
- [x] `python scripts/generate_mobile_harness_mobile_evidence_pack.py`。
- [x] `python scripts/generate_mobile_harness_frozen_subset.py`。
- [x] `python scripts/generate_mobile_harness_baseline_protocol.py`。
- [x] `python scripts/generate_mobile_harness_baseline_run_contract.py`。
- [x] `python scripts/generate_mobile_harness_baseline_scaffold.py`。
- [x] `python scripts/generate_mobile_harness_baseline_dry_run.py`。
- [x] `python scripts/generate_mobile_harness_baseline_pilot_pack.py`。
- [x] `python scripts/generate_mobile_harness_baseline_pilot_readiness.py`。
- [x] `python scripts/generate_mobile_harness_claim_ledger.py`。
- [x] `python scripts/generate_mobile_harness_core_claim_readiness.py`。
- [x] `python scripts/generate_mobile_harness_evidence_maturity_matrix.py`。
- [x] `python scripts/generate_mobile_harness_evaluation_protocol_readiness.py`。
- [x] `python scripts/generate_mobile_harness_method_presentation_readiness.py`。
- [x] `python scripts/generate_mobile_harness_bibliography_readiness.py`。
- [x] `python scripts/generate_mobile_harness_threats_to_validity.py`。
- [x] `python scripts/generate_mobile_harness_page_limit_readiness.py`。
- [x] `python scripts/generate_mobile_harness_reproducibility_checklist.py`。
- [x] `python scripts/generate_mobile_harness_submission_readiness.py`。
- [x] `smoke-v2.json` 生成后跑 T0 dry run。
  - Evidence: `python scripts/run_mobile_harness_bench.py --task-set smoke-v2 --run-id 2026-06-06-smoke-v2-t0`。
- [ ] Android real device run 输出 device metadata、screenshots/logcat 和 run summary。
- [ ] Mac iOS simulator run 输出 simulator screenshot、Xcode log 和 run summary。
- [ ] frozen subset 发布前做敏感信息扫描和人工抽检。

## Assumptions

- [ ] 1000 条是候选任务规模，不等同于 1000 条实验结果。
- [ ] 论文中只能使用有 run evidence 的任务。
- [ ] 新增 runtime 类必须保持 RuntimeProvider / ActionRunner 安全边界。
