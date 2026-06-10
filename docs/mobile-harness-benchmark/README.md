# MobileHarnessBench

MobileHarnessBench 是 MobileCode 的最小可复现评测协议，用于衡量手机端 AI coding harness 是否能把任务从输入、编辑、预览、验证、发布和证据报告闭环。

它不是通用手机 App 操作 benchmark。它不评测模型是否能在真实 App 里点击按钮，也不复刻 PhoneWorld。它评测的是手机端 AI coding harness 的工程能力。

## v0 范围

v0 包含 25 个种子任务，分成 5 类。v1 candidate bank 已扩展到 200 条任务。v2 candidate bank 已扩展到 1000 条任务，并把类别从 5 类提升到 6 类，用于后续 frozen subset、verifier dry run 和论文实验设计。

- `file_intake`：微信/系统分享进入的 HTML、Markdown、TXT、JSON、异常后缀文件能否被识别和预览。
- `code_edit`：手机端能否生成、读取、修改和验证小型代码/文档 artifact。
- `preview_verification`：HTML、Markdown、WebView preview 和 snapshot 是否可验证。
- `github_delivery`：GitHub commit、Pages publish、Actions artifact 是否可追踪。
- `harness_evidence`：tool trace、runtime log、verifier report、failure recovery 是否完整。
- `runtime_orchestration`：RuntimeProvider、Helper、Termux fallback、WebViewOnly、runtime switch 和 task stop 是否可控。

## 指标

- `task_success_rate`：任务是否完成。
- `verified_success_rate`：是否通过 verifier。
- `trace_completeness`：工具调用、输入、输出、artifact、URL、失败类型是否完整。
- `recovery_rate`：失败后能否给出可执行恢复路径。
- `artifact_availability`：本地文件、预览 URL、Pages URL、Actions artifact 是否可访问。
- `human_intervention_count`：完成任务所需人工介入次数。
- `steps_to_completion`：完成任务的 action/tool step 数。

## Mobile 测试原则

MobileHarnessBench 不能只在桌面脚本里证明。测试分层详见：[mobile-test-strategy.md](mobile-test-strategy.md)。

- T0：offline fixture runner，用于快速校验 task、fixture、verifier 和 public report。
- T1：Android emulator，用于 UI/WebView 回归。
- T2：Android real device，用于真实分享入口、Open with、WebView、后台和低内存证据。
- T3：Mac 上的 iOS simulator，用于 iOS WebView、Document Picker 和 Xcode log 回归。
- T4：iOS real device，用于真实 Open In、Files app、权限和后台行为。
- T5：GitHub sandbox，用于 commit、Pages、Actions 和 artifact delivery。

论文实验不能把 1000 条 candidate tasks 当作 1000 条实验结果；只有 frozen subset 中有 verifier result、trace、summary 和对应 mobile tier 证据的任务才能计入实验表。

## 文件结构

```text
docs/mobile-harness-benchmark/
├─ README.md
├─ baselines/
│  ├─ 2026-06-06-baseline-dry-run-t0/
│  ├─ 2026-06-06-baseline-pilot-pack/
│  └─ 2026-06-06-baseline-scaffold/
├─ mobile-test-strategy.md
├─ harness-task-registry.md
├─ skill-spec.md
├─ mobile-evidence/
│  └─ 2026-06-06-mobile-evidence-pack/
├─ reports/
│  ├─ bibliography-readiness.json
│  ├─ bibliography-readiness.md
│  ├─ baseline-protocol-readiness.json
│  ├─ baseline-protocol-readiness.md
│  ├─ baseline-pilot-readiness.json
│  ├─ baseline-pilot-readiness.md
│  ├─ baseline-run-contract.json
│  ├─ baseline-run-contract.md
│  ├─ core-claim-readiness.json
│  ├─ core-claim-readiness.md
│  ├─ evidence-maturity-matrix.json
│  ├─ evidence-maturity-matrix.md
│  ├─ evaluation-protocol-readiness.json
│  ├─ evaluation-protocol-readiness.md
│  ├─ frozen-subset-readiness.json
│  ├─ frozen-subset-readiness.md
│  ├─ method-presentation-readiness.json
│  ├─ method-presentation-readiness.md
│  ├─ mobile-tier-readiness.json
│  ├─ mobile-tier-readiness.md
│  ├─ reproducibility-checklist.json
│  ├─ reproducibility-checklist.md
│  ├─ mobile-evidence-pack-readiness.json
│  ├─ mobile-evidence-pack-readiness.md
│  ├─ paper-claim-evidence-ledger.json
│  ├─ paper-claim-evidence-ledger.md
│  ├─ submission-readiness.json
│  ├─ submission-readiness.md
│  ├─ threats-to-validity.json
│  ├─ threats-to-validity.md
│  ├─ verifier-contract-readiness.json
│  ├─ verifier-contract-readiness.md
│  ├─ v2-quality-audit.json
│  └─ v2-quality-audit.md
├─ rubric.md
├─ runbook.md
├─ runs/
│  └─ 2026-06-06-v0-dry-run/
├─ schema/
│  ├─ baseline_run.schema.json
│  └─ mobile_harness_task.schema.json
├─ tasks/
│  ├─ representative-v0.json
│  ├─ android-device-v2.json
│  ├─ frozen-v2-paper-subset.json
│  ├─ ios-simulator-v2.json
│  ├─ smoke-v2.json
│  ├─ v1-task-bank.json
│  ├─ v2-task-bank.json
│  └─ v0-seed-tasks.json
└─ verifiers/
   ├─ verifier-contract.md
   └─ verifier-contracts.json
```

## 当前状态

- [x] v0 task schema 已创建。
- [x] v0 25 个 seed tasks 已创建。
- [x] v0 fixture 已创建。
- [x] `representative-v0` 任务集合已创建。
- [x] v1 200 条 candidate task bank 已创建。
- [x] v2 1000 条 candidate task bank 已创建。
- [x] 第 6 类 `runtime_orchestration` 已创建。
- [x] mobile 测试分层策略已创建。
- [x] 本地结构校验脚本已创建。
- [x] v2 machine quality audit 已创建。
- [x] baseline protocol readiness report 已创建。
- [x] baseline run contract schema/report 已创建。
- [x] baseline scaffold 已创建，三组 baseline 均为 `scaffold_not_run`。
- [x] baseline T0 dry-run 已创建，三组 baseline 均为 `dry_run_not_counted`，每组 1 个 blocked 合约样本。
- [x] baseline pilot pack 已创建，三组 baseline 均有 prompt、model lock、human intervention 和 evidence template。
- [x] baseline pilot readiness report 已创建，声明可执行 non-counted pilot，但不能计为 baseline result。
- [x] core claim readiness report 已创建，声明核心定位 claim 已有论文用语和 evidence boundary。
- [x] evidence maturity matrix 已创建，声明当前只有 T0 fixture run 可计为 paper evidence，mobile/baseline result 仍为 open requirement。
- [x] evaluation protocol readiness report 已创建，声明 E1-E5 均绑定 task set、证据等级、7 个 primary metrics 和 open requirements。
- [x] method presentation readiness report 已创建，声明论文图、算法、模块接口、公式和 evidence boundary 已有机器检查。
- [x] MobileCode Skill Spec 已创建，定义 `SKILL.md`、`scripts/index.html`、permission 和 verifier 合约。
- [x] Harness Task Registry 已创建，将 Tools、bottom sheets、pushed routes、skills 和 benchmark evidence 映射到 task metadata。
- [x] bibliography readiness report 已创建，声明当前 related-work metadata 已验证且无作者占位。
- [x] threats-to-validity matrix 已创建，声明当前审稿风险和 open requirements。
- [x] page-limit readiness report 已创建，声明当前编译 PDF 页数边界和 References 起始页。
- [x] reproducibility checklist 已创建，声明当前草稿可复现命令和 full empirical reproduction 缺口。
- [x] submission readiness gate 已创建，声明当前草稿可审阅但不能标记为正式 upload-ready。
- [x] paper claim-to-evidence ledger 已创建。
- [x] mobile-tier readiness probe 已创建。
- [x] mobile evidence capture pack 已创建，48 个 T2/T3 任务有 evidence template 和 execution playbook，但不计为 mobile experiment。
- [x] draft frozen paper subset manifest 已创建。
- [x] machine-readable verifier contract catalog 已创建，12 个 verifier 覆盖 v0/v1/v2 当前 1225 条任务定义引用。
- [x] 5 个代表任务的离线 verifier implementation 已创建。
- [x] v0 代表任务 dry run 已完成。
- [x] `smoke-v2` T0 离线 dry run 已完成。
- [ ] 全部 25 个 seed tasks 的 verifier implementation 尚未完成。
- [ ] v1 200 条 candidate tasks 尚未全部完成人工抽检和 dry run。
- [ ] v2 1000 条 candidate tasks 尚未全部完成人工抽检、分层和 dry run。
- [ ] 真实 Android/iOS mobile run 尚未完成。

## 数据规模

| Dataset | Count | Status | Evidence |
| --- | ---: | --- | --- |
| v0 seed tasks | 25 | schema + fixture validated | [v0-seed-tasks.json](tasks/v0-seed-tasks.json) |
| representative-v0 | 5 | dry run completed | [summary.md](runs/2026-06-06-v0-dry-run/summary.md) |
| v1 candidate task bank | 200 | generated + locally validated | [v1-task-bank.json](tasks/v1-task-bank.json) |
| v2 candidate task bank | 1000 | generated + locally validated + machine audited; 6 categories | [v2-task-bank.json](tasks/v2-task-bank.json) · [quality audit](reports/v2-quality-audit.md) |
| baseline protocol | 3 baselines | protocol defined; no baseline results counted | [baseline-protocol-readiness.md](reports/baseline-protocol-readiness.md) |
| baseline run contract | 0 results | schema/contract defined; no baseline results counted | [baseline-run-contract.md](reports/baseline-run-contract.md) |
| baseline scaffold | 3 baselines x 60 tasks | `not_run` scaffold only; no baseline results counted | [manifest](baselines/2026-06-06-baseline-scaffold/README.md) |
| baseline T0 dry run | 3 baselines x 1 task | `dry_run_not_counted`; blocked before model/device/sandbox execution | [manifest](baselines/2026-06-06-baseline-dry-run-t0/README.md) |
| baseline pilot pack | 3 baselines x 1 task | prompt/evidence templates locked; no baseline results counted | [manifest](baselines/2026-06-06-baseline-pilot-pack/README.md) |
| baseline pilot readiness | 3 baselines x 1 task | ready for non-counted pilot; not ready for counted baseline result | [baseline-pilot-readiness.md](reports/baseline-pilot-readiness.md) |
| core claim readiness | 4 claims | control-plane positioning checked; no experiment counted | [core-claim-readiness.md](reports/core-claim-readiness.md) |
| evidence maturity matrix | 7 stages | T0 fixture evidence only; 0 counted mobile/baseline result stages | [evidence-maturity-matrix.md](reports/evidence-maturity-matrix.md) |
| evaluation protocol readiness | 5 protocols / 7 metrics | E1-E5 and metric contract machine-checkable; only E1 has counted T0 fixture evidence | [evaluation-protocol-readiness.md](reports/evaluation-protocol-readiness.md) |
| method presentation readiness | 5 checks | visuals, algorithms, modules, formulas and evidence boundaries machine-checkable | [method-presentation-readiness.md](reports/method-presentation-readiness.md) |
| MobileCode Skill Spec | 5 initial skills | package contract for `SKILL.md`, WebView script, permissions and verifier boundary | [skill-spec.md](skill-spec.md) |
| Harness Task Registry | 8 initial product tasks | maps Tools, sheets and routes to category, surface, skill, permission, runtime and verifier metadata | [harness-task-registry.md](harness-task-registry.md) |
| verifier contract readiness | 12 contracts / 1225 task definitions | all current v0/v1/v2 verifier references are covered by machine-readable contracts; not full implementation evidence | [verifier-contract-readiness.md](reports/verifier-contract-readiness.md) |
| bibliography readiness | 9 entries | current related-work metadata verified; no author placeholders | [bibliography-readiness.md](reports/bibliography-readiness.md) |
| threats-to-validity matrix | 6 threats | review risks tracked; open requirements preserved | [threats-to-validity.md](reports/threats-to-validity.md) |
| page-limit readiness | 10 PDF pages | References start on page 9; main text boundary is within current limit | [page-limit-readiness.md](reports/page-limit-readiness.md) |
| reproducibility checklist | 16 commands | draft command-to-artifact matrix ready; full empirical reproduction open | [reproducibility-checklist.md](reports/reproducibility-checklist.md) |
| submission readiness gate | 16 gates | draft reviewable; reviewer manifest labels and method presentation gated; not upload-ready until mobile/baseline/submission metadata close | [submission-readiness.md](reports/submission-readiness.md) |
| paper claim ledger | 6 claims | supported claims mapped to artifacts; open mobile/baseline requirements preserved | [paper-claim-evidence-ledger.md](reports/paper-claim-evidence-ledger.md) |
| smoke-v2 | 60 | T0 run completed: 50 passed, 10 blocked | [smoke-v2.json](tasks/smoke-v2.json) · [summary.md](runs/2026-06-06-smoke-v2-t0/summary.md) |
| frozen-v2-paper-subset | 60 | draft planning manifest; not final paper evidence | [frozen-v2-paper-subset.json](tasks/frozen-v2-paper-subset.json) · [readiness](reports/frozen-subset-readiness.md) |
| android-device-v2 | 30 | T2 Android real-device subset; readiness currently blocked | [android-device-v2.json](tasks/android-device-v2.json) · [readiness](reports/mobile-tier-readiness.md) |
| ios-simulator-v2 | 18 | T3 Mac iOS simulator subset; readiness currently blocked | [ios-simulator-v2.json](tasks/ios-simulator-v2.json) · [readiness](reports/mobile-tier-readiness.md) |
| mobile evidence pack | 48 tasks / 53 templates | capture-ready templates plus execution playbook; no mobile results counted | [mobile-evidence-pack-readiness.md](reports/mobile-evidence-pack-readiness.md) · [pack](mobile-evidence/2026-06-06-mobile-evidence-pack/README.md) |

## 最新 dry run

2026-06-06 已完成 `representative-v0` 离线 dry run，每类 1 个任务：

- `MH-FI-001`：外部 HTML 文件入口，`passed`。
- `MH-CE-004`：invalid JSON 修复，`passed`。
- `MH-PV-001`：HTML preview snapshot，`passed`。
- `MH-GD-001`：GitHub commit 交付，离线环境按规则 `blocked`。
- `MH-HE-001`：完整 action trace，`passed`。

输出：

- [representative-v0.json](tasks/representative-v0.json)
- [run.json](runs/2026-06-06-v0-dry-run/run.json)
- [summary.md](runs/2026-06-06-v0-dry-run/summary.md)
- [traces.jsonl](runs/2026-06-06-v0-dry-run/traces.jsonl)

2026-06-06 也已完成 `smoke-v2` T0 离线 dry run，60 条任务覆盖 6 类：

- `code_edit`、`file_intake`、`preview_verification`、`harness_evidence`、`runtime_orchestration` 共 50 条 fixture-level `passed`。
- `github_delivery` 10 条按规则 `blocked`，因为 T0 不使用授权 GitHub sandbox。
- 每条结果都带 `counts_as_mobile_experiment=false`，不能当作 Android/iOS 真实设备证据。

输出：

- [smoke-v2.json](tasks/smoke-v2.json)
- [run.json](runs/2026-06-06-smoke-v2-t0/run.json)
- [summary.md](runs/2026-06-06-smoke-v2-t0/summary.md)
- [traces.jsonl](runs/2026-06-06-smoke-v2-t0/traces.jsonl)

2026-06-06 已生成 baseline T0 dry-run 合约样本：

- 三组 baseline 各 1 条 `MH-CE-209` 结果。
- 每条结果为 `blocked`，`counts_as_baseline_result=false`，所有指标为 `null`。
- 这只验证 baseline-run 结果形状和证据边界，不是 baseline comparison。

输出：

- [manifest](baselines/2026-06-06-baseline-dry-run-t0/README.md)
- [chat-only baseline-run.json](baselines/2026-06-06-baseline-dry-run-t0/chat_only_mobile_coding_flow/baseline-run.json)
- [desktop baseline-run.json](baselines/2026-06-06-baseline-dry-run-t0/desktop_remote_ide_flow/baseline-run.json)
- [harness baseline-run.json](baselines/2026-06-06-baseline-dry-run-t0/mobile_harness_flow/baseline-run.json)

2026-06-06 已生成 baseline pilot pack：

- 三组 baseline 各有一份 `prompt.md`，使用同一个 `MH-CE-209` 任务。
- `model-lock-template.json` 固定下一次真实 pilot 前必须填写的模型、版本、温度、prompt hash 和运行环境字段。
- `human-intervention-sheet.csv` 固定人工介入记录列。
- `evidence-template.json` 固定从 pilot 升级到 `baseline_result` 前必须提交的证据。
- 该包状态为 `pilot_ready_no_results`，仍然不计为 baseline comparison。

输出：

- [manifest](baselines/2026-06-06-baseline-pilot-pack/README.md)
- [model lock template](baselines/2026-06-06-baseline-pilot-pack/model-lock-template.json)
- [human intervention sheet](baselines/2026-06-06-baseline-pilot-pack/human-intervention-sheet.csv)
- [chat-only prompt](baselines/2026-06-06-baseline-pilot-pack/chat_only_mobile_coding_flow/prompt.md)
- [desktop prompt](baselines/2026-06-06-baseline-pilot-pack/desktop_remote_ide_flow/prompt.md)
- [harness prompt](baselines/2026-06-06-baseline-pilot-pack/mobile_harness_flow/prompt.md)

2026-06-06 已生成 baseline pilot readiness report：

- `ready_for_pilot_execution=true`，代表 prompt、model lock 模板、human intervention sheet 和 evidence templates 已齐。
- `ready_for_counted_baseline_result=false`，因为仍缺 filled model lock、transcripts、artifacts、verifier outputs 和 `baseline_result` runs。
- 该 report 是 gate，不是实验结果。

输出：

- [baseline-pilot-readiness.md](reports/baseline-pilot-readiness.md)
- [baseline-pilot-readiness.json](reports/baseline-pilot-readiness.json)

2026-06-06 已生成 evidence maturity matrix：

- 7 个成熟度阶段，从 candidate task supply 到 counted mobile/baseline results。
- 当前 `current_max_counted_paper_evidence_level=1`，也就是 T0 fixture run。
- `counted_mobile_stage_ids=[]`，`counted_baseline_stage_ids=[]`。
- `M6_counted_mobile_or_baseline_results` 仍是 open requirement。

输出：

- [evidence-maturity-matrix.md](reports/evidence-maturity-matrix.md)
- [evidence-maturity-matrix.json](reports/evidence-maturity-matrix.json)

2026-06-06 已生成 bibliography readiness report：

- 9 个当前正文引用的 related-work 条目均有 source URL 和 eprint metadata。
- 当前 `remaining_draft_entries=[]`。
- 正文引用 key 与 `references.bib` key 完全对应。
- 该 report 只证明当前 bibliography metadata 质量，不替代 venue/year/template 和 author profile 检查。

输出：

- [bibliography-readiness.md](reports/bibliography-readiness.md)
- [bibliography-readiness.json](reports/bibliography-readiness.json)

2026-06-06 已生成 submission readiness gate：

- 16 个 gate 覆盖 manuscript artifacts、claim/evidence boundary、core claim positioning、mobile experiment boundary、mobile evidence capture pack、verifier contract readiness、baseline boundary、anonymous supplement boundary、reviewer manifest evidence labels、submission metadata、bibliography metadata、threats-to-validity、evaluation protocol readiness、method presentation readiness、reproducibility checklist 和 page-limit readiness。
- 当前 `ready_for_submission_upload=false`。
- `S2_mobile_experiment_boundary`、`S4_baseline_result_boundary` 和 `S6_submission_metadata` 仍是 open gate。
- 该 gate 用于审稿前自检，不是实验结果。

输出：

- [submission-readiness.md](reports/submission-readiness.md)
- [submission-readiness.json](reports/submission-readiness.json)

2026-06-06 已生成 reproducibility checklist：

- 16 个命令步骤覆盖 task-bank generation、audit、T0 smoke、mobile readiness、mobile capture pack、verifier contract readiness、baseline protocol、claim reports、evidence reports、method presentation readiness、paper compile、page-limit readiness、supplement staging 和 validator。
- 当前 `ready_for_draft_reproduction=true`。
- 当前 `ready_for_full_empirical_reproduction=false`，因为真实 Android/iOS、GitHub sandbox 和 counted baseline 结果仍未完成。
- 该 report 是复现命令矩阵，不是实验结果。

输出：

- [reproducibility-checklist.md](reports/reproducibility-checklist.md)
- [reproducibility-checklist.json](reports/reproducibility-checklist.json)

2026-06-06 已生成 page-limit readiness report：

- 当前编译 PDF 为 10 页，包括参考文献。
- References 起始页为第 9 页，`within_main_text_limit=true`。
- 该 report 只证明当前编译稿页数边界，不证明 venue/year/template 和 OpenReview metadata 已准备完成。

输出：

- [page-limit-readiness.md](reports/page-limit-readiness.md)
- [page-limit-readiness.json](reports/page-limit-readiness.json)

2026-06-06 已生成 core claim readiness report：

- 检查论文是否明确把 mobile AI coding 定位为 harness control plane，而不是 full mobile IDE。
- 检查论文是否明确不做 general phone-use benchmark。
- 检查 evidence-first counting 边界，不把定位 claim 当实验结果。
- 状态为 `passed_with_open_requirements`，仍保留真实 mobile/baseline evidence open requirements。

输出：

- [core-claim-readiness.md](reports/core-claim-readiness.md)
- [core-claim-readiness.json](reports/core-claim-readiness.json)

2026-06-06 已生成 evaluation protocol readiness report：

- 覆盖论文 E1-E5：T0 smoke、Android real-device subset、Mac iOS simulator subset、GitHub sandbox delivery 和 baseline comparison。
- 覆盖 7 个 primary metrics：task success、verified success、trace completeness、recovery rate、artifact availability、human intervention count 和 steps to completion。
- 当前只有 `E1_t0_smoke_v2` 有 counted T0 fixture evidence。
- E2/E3/E4/E5 仍是 capture-ready 或 protocol-only，不计为 mobile/baseline experiment。
- 该 report 用于证明 evaluation protocol 可执行且证据边界可机检。

输出：

- [evaluation-protocol-readiness.md](reports/evaluation-protocol-readiness.md)
- [evaluation-protocol-readiness.json](reports/evaluation-protocol-readiness.json)

2026-06-06 已生成 threats-to-validity matrix：

- 6 类风险：construct、internal、external、baseline、privacy/delivery、submission validity。
- 状态为 `passed_with_open_requirements`。
- 该 report 只跟踪审稿风险和缓解措施，不计为实验结果。

输出：

- [threats-to-validity.md](reports/threats-to-validity.md)
- [threats-to-validity.json](reports/threats-to-validity.json)

2026-06-06 已生成 mobile evidence capture pack：

- 覆盖 `android-device-v2` 的 30 条 T2 Android real-device 任务。
- 覆盖 `ios-simulator-v2` 的 18 条 T3 Mac iOS simulator 任务。
- 生成 48 个 task-level evidence templates、2 个 device metadata templates、2 个 run manifest templates 和 1 个 checklist。
- 生成 `execution-playbook.md`，固定 Android T2 / iOS T3 的操作顺序、必需产物和 non-result promotion boundary。
- 状态为 `capture_ready_no_results`，`counts_as_mobile_experiment=false`。

输出：

- [mobile-evidence-pack-readiness.md](reports/mobile-evidence-pack-readiness.md)
- [mobile-evidence-pack-readiness.json](reports/mobile-evidence-pack-readiness.json)
- [mobile evidence pack](mobile-evidence/2026-06-06-mobile-evidence-pack/README.md)
- [execution playbook](mobile-evidence/2026-06-06-mobile-evidence-pack/execution-playbook.md)

## 校验

```powershell
python scripts/generate_mobile_harness_task_bank.py
python scripts/run_mobile_harness_bench.py --task-set representative-v0 --run-id 2026-06-06-v0-dry-run
python scripts/run_mobile_harness_bench.py --task-set smoke-v2 --run-id 2026-06-06-smoke-v2-t0
python scripts/audit_mobile_harness_task_bank.py
python scripts/collect_mobile_harness_mobile_tier_evidence.py
python scripts/generate_mobile_harness_mobile_evidence_pack.py
python scripts/generate_mobile_harness_frozen_subset.py
python scripts/generate_mobile_harness_baseline_protocol.py
python scripts/generate_mobile_harness_baseline_run_contract.py
python scripts/generate_mobile_harness_baseline_scaffold.py
python scripts/generate_mobile_harness_baseline_dry_run.py
python scripts/generate_mobile_harness_baseline_pilot_pack.py
python scripts/generate_mobile_harness_baseline_pilot_readiness.py
python scripts/generate_mobile_harness_claim_ledger.py
python scripts/generate_mobile_harness_evidence_maturity_matrix.py
python scripts/generate_mobile_harness_bibliography_readiness.py
python scripts/generate_mobile_harness_threats_to_validity.py
python scripts/generate_mobile_harness_submission_readiness.py
python scripts/validate_mobile_harness_bench.py
```
