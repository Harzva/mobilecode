# P6 Mobile Agent Co-Evolution Roadmp

目标：将 Mobile Harness 从单次策略对比推进到 mobile-first 智能体共进化系统，让 benchmark、推理策略、多智能体协同、phone-use/runtime verifier 和 MobileCode framework 一起升级。

## 范围

- 本文件是 P6 规划，不是已完成证据。
- P6 结果在具备真实模型、真实工具、真实设备或 emulator、runtime verifier、截图/UI XML/logcat、token/model logs 前，仍必须保持 non-counted。
- P6 可以参考 `https://github.com/Just-Agent/Oh-Reflective-loop-skills` 的 reflective loop 思想，但不得把外部仓库内容直接当成本项目已实现能力。

## 三个主方向

P6 需要同时推进三个正交方向。它们可以单独 ablation，也可以组合成完整策略。

| 方向 | 目标 | 当前基线 | P6 要补齐 |
| --- | --- | --- | --- |
| Single-agent 推理，纵向 | 提升单个 agent 的计划、行动、验证、恢复能力。 | ReAct、Plan-Execute-Verify、ReAct + FinalVerifier 已有 runner 和 dry trace。 | 接入真实 model/tool callback、runtime verifier、token/time 记录、失败恢复评分。 |
| Multi-agent 协同，横向 | 提升多个角色之间的分工、交接、互检能力。 | Supervisor/Handoff、SwarmRouter、HierarchicalSwarm 已有发布级 scaffold；Swarm 仍 feature-gated。 | 统一 mailbox、blackboard、event bus、judge/verifier、role budget 和协同评分。 |
| Loop engineering，闭环 | 让 benchmark、策略、framework 根据失败样本共同进化。 | P5.5/P5.6/P5.7/P5.8 已形成 non-counted pilot 和 phone-use gate。 | 建立 failure bank、strategy tournament、holdout eval、regression gate 和策略晋升规则。 |

## 组合关系

P6 策略不再只用一个 strategy id 表达，而应拆成可组合配置：

```text
MobileStrategy =
  reasoning_mode
  + coordination_topology
  + loop_policy
  + memory_policy
  + tool_policy
  + device_policy
```

示例组合：

- `ReAct + no_handoff + simple_retry + redacted_memory + browser_tool + emulator_gate`
- `PEV + supervisor_mailbox + verifier_retry + proposal_memory + phone_use_tool + emulator_gate`
- `PEV/ReAct hybrid + hierarchical_swarm + reflective_failure_loop + evidence_ledger + phone_use/WebView tools + real_device_gate`

P6 ablation 必须先控制变量，再测试组合策略：

- [ ] 固定模型、任务、预算，只比较 single-agent 推理模式。
- [ ] 固定推理模式，只比较 multi-agent 协同拓扑。
- [ ] 固定推理和协同，只比较 loop policy。
- [ ] 最后测试组合策略是否在 holdout tasks 上稳定胜出。

## 多智能体通信策略

P6 推荐使用混合通信层，不只采用 shared blackboard 或 mailbox。

| 通信方案 | 用途 | P6 规则 |
| --- | --- | --- |
| Mailbox / HandoffPacket | Supervisor 给 CodeAgent、RuntimeAgent、PreviewAgent、VerifierAgent、MemoryAgent、ReporterAgent 派发原子任务。 | 每次 handoff 必须有 typed packet、input filter、allowed tools、budget、return contract。 |
| Shared Blackboard / EvidenceLedger | 共享 artifact、screenshot、UI XML、logcat、verifier output、runtime state。 | 只放摘要和 evidence refs，不放 raw transcript、secret、private path。 |
| Runtime EventBus | 记录 device/emulator、Accessibility、adb、WebView、artifact verifier 的事件流。 | 每个事件必须有 schema、timestamp、source、status、evidence id。 |
| MemoryCommitProposal | 将失败模式、项目事实、用户偏好写入可审查提案。 | 默认 proposal-only；不得自动持久化 raw memory。 |
| Judge / Debate | 对多个候选 artifact 或修复方案做质量裁决。 | Judge 只读取 filtered trace summary 和 evidence refs。 |

推荐默认拓扑：

```text
Supervisor
  -> mailbox handoff to specialist agents
  -> blackboard/evidence ledger for shared proof
  -> runtime event bus for phone-use/device state
  -> verifier/judge for gate
  -> memory proposal for durable learning
```

## Benchmark 与策略共进化

P6 采用 benchmark-adversarial co-evolution 思路：

```text
Benchmark 生成更难的 mobile tasks
  -> strategies 在相同模型/预算下执行
  -> runtime verifier 捕获真实失败
  -> failure bank 归类失败模式
  -> strategy designer 提出 mobile-first 改进
  -> MobileCode framework 补工具、权限、证据链和 UI
  -> regression/holdout gate 验证是否真提升
```

必须防止 benchmark overfitting：

- [ ] Public eval 用于复现和回归。
- [ ] Private holdout 用于策略晋升，不得被策略调参直接看到。
- [ ] Pilot run 保持 `counts_as_experiment=false`。
- [ ] Counted benchmark 只允许在 promotion gate 通过后生成。
- [ ] 每次策略改动都要跑旧任务 regression，确认没有能力退化。

## P6 阶段计划

### P6.0 Benchmark Taxonomy Upgrade

- [x] 增加 mobile task taxonomy：UI artifact、WebView artifact、phone-use permission、file intake、local runtime、network boundary、recovery task、real device task。
  - Evidence: `docs/mobile-harness-benchmark/strategy-ablation/p60-p62-runtime-benchmark-contract.md` and `docs/mobile-harness-benchmark/strategy-ablation/runs/p60-p62-runtime-benchmark-upgrade/runtime_benchmark_upgrade_contract.json`。
- [x] 为每类任务定义 runtime assertions：keyboard、tap、swipe、set_text、localStorage、UI XML、screenshot、logcat、WebView state。
  - Evidence: `runtime_benchmark_upgrade_contract.json` assertion catalog contains keyboard、tap、swipe、set_text、localStorage、UI XML、screenshot、logcat、WebView state、focus_state。
- [x] 增加评分维度：quality、runtime correctness、phone-use ability、recovery、latency/token、safety/privacy。
  - Evidence: score dimensions weights sum to 100 in `runtime_benchmark_upgrade_contract.json`。

### P6.1 Communication Substrate

- [x] 将 HandoffPacket 升级为 mailbox contract。
  - Evidence: `MailboxMessage` contract in `runtime_benchmark_upgrade_contract.json`。
- [x] 增加 EvidenceLedger blackboard contract。
  - Evidence: `EvidenceLedgerEntry` contract in `runtime_benchmark_upgrade_contract.json`。
- [x] 增加 RuntimeEventBus contract。
  - Evidence: `RuntimeEvent` contract in `runtime_benchmark_upgrade_contract.json`。
- [x] 增加 MemoryCommitProposal contract。
  - Evidence: `MemoryCommitProposal` contract in `runtime_benchmark_upgrade_contract.json`。
- [x] 为每个 role 固定 tool allowlist、budget、input filter、return contract。
  - Evidence: CodeAgent、RuntimeAgent、PreviewAgent、VerifierAgent、MemoryAgent、ReporterAgent role contracts in `runtime_benchmark_upgrade_contract.json`。

### P6.2 Runtime Interaction Verifier

- [x] 定义 P6.2 runtime verifier scaffold，复用 P5.6 artifact verifier 并补齐 Android/WebView runtime assertion contract。
  - Evidence: `docs/mobile-harness-benchmark/strategy-ablation/runs/p60-p62-runtime-benchmark-upgrade/runtime_benchmark_upgrade_verifier.json`。
- [x] 输出 verifier JSON contract 和 non-counted run contract。
  - Evidence: `docs/mobile-harness-benchmark/strategy-ablation/runs/p60-p62-runtime-benchmark-upgrade/run.json` validator passed，6 strategies、18 results、`run_kind=strategy_pilot_not_counted`、`counts_as_experiment=false`。
- [x] 输出 Android phone-use runtime screenshots、UI XML、logcat、focus state 和 runtime score。
  - Evidence: `docs/mobile-harness-benchmark/strategy-ablation/runs/p63-android-real-device-lane/phone_use_runtime_verifier.json` status passed，runtime score 100.0，action acceptance 4/4。
  - Boundary: emulator phone-use runtime QA only，non-counted，不证明 strategy quality 差异。
- [ ] 对 Snake 验证 Arrow/WASD、移动、得分、暂停、重启。
- [ ] 对 Kanban 验证输入任务、快捷键、timer、刷新后 localStorage。
- [ ] 对 Maze 验证点击设墙、起点终点、Solve、路径长度变化。
- [ ] 输出真实 WebView state / localStorage / generated artifact interaction runtime score。
  - Note: P6.0-P6.2 已完成 contract/scaffold；P6.3 已完成 Android emulator phone-use runtime gate；WebView/localStorage/generated artifact 交互证据进入 P6.4 gate。

### P6.3 Real Mac / Real Android Device Lane

- [x] 建立 emulator device registry evidence：serial、device tier、Android screen size、permission status。
  - Evidence: `evidence/adb-devices.txt`、`evidence/accessibility-settings.txt`、APK metadata in `apk.json`。
- [x] 支持 APK install、launch、Accessibility 授权检查、screenshot、UI dump、logcat、focus state。
  - Evidence: `install.txt`、`launch.txt`、`01-launch.png`、`02-tools-phone-use.png`、`03-dry-probe.png`、`04-action-probe.png`、`05-home-after-action.png`、`05-focus-after-back.txt`、`05-focus-after-home.txt`。
- [x] 明确 emulator evidence 和 real-device evidence 的区别，不得互相替代。
  - P6.3 当前证据是 emulator lane；外接 Android 真机 lane 仍需单独跑并保存授权状态。
- [ ] 真机授权可先采用人工步骤，但必须保存授权状态和复测证据。

### P6.4 Strategy Tournament

- [ ] 固定同一模型、同一任务集、同一预算。
- [ ] 跑 ReAct、PEV、ReAct + FinalVerifier、Supervisor/Handoff、SwarmRouter、HierarchicalSwarm。
- [ ] 同时报告质量分、runtime 分、phone-use 分、恢复分、效率分。
- [ ] 输出 strategy matrix、efficiency scoreboard、failure taxonomy、evidence package。

### P6.5 Mobile-First Strategy Proposal

- [ ] 基于失败样本提出 Mobile Evidence-Gated Reflective Swarm。
- [ ] 默认结构：PEV outer loop、ReAct inner loop、Supervisor mailbox、EvidenceLedger blackboard、runtime verifier gate、Memory proposal。
- [ ] 针对 mobile 优化：权限先验、UI tree grounding、tap/text/swipe recovery、WebView/localStorage verifier、real-device drift handling。
- [ ] 只有 holdout 胜出且安全边界完整，才允许作为候选默认策略。

### P6.6 Promotion Gate

- [ ] 检查 `counts_as_experiment=false` 是否只用于 pilot。
- [ ] 检查 counted result 是否具备 model logs、token records、tool evidence、device evidence、verifier outputs、screenshots。
- [ ] secret/path/raw transcript scan 必须通过。
- [ ] Swarm 相关策略在未通过 gate 前继续 feature-gated。

## Evidence / 已完成证据

- 2026-06-20 P5.8 已完成 Android phone-use runtime gate；它只证明 phone-use runtime gate 和证据链，不证明六个推理框架质量差异。
- 2026-06-20 P5.8 `phone_use_runtime_verifier.json` 为 non-counted runtime score。
- 2026-06-21 P6.0-P6.2 runtime benchmark upgrade contract 已生成：
  - Contract doc: `docs/mobile-harness-benchmark/strategy-ablation/p60-p62-runtime-benchmark-contract.md`。
  - Contract JSON: `docs/mobile-harness-benchmark/strategy-ablation/runs/p60-p62-runtime-benchmark-upgrade/runtime_benchmark_upgrade_contract.json`。
  - Verifier JSON: `docs/mobile-harness-benchmark/strategy-ablation/runs/p60-p62-runtime-benchmark-upgrade/runtime_benchmark_upgrade_verifier.json`。
  - Run JSON: `docs/mobile-harness-benchmark/strategy-ablation/runs/p60-p62-runtime-benchmark-upgrade/run.json`。
  - Summary: `docs/mobile-harness-benchmark/strategy-ablation/runs/p60-p62-runtime-benchmark-upgrade/summary.md`。
  - 2026-06-21 strategy validator passed：6 strategies、18 results、`run_kind=strategy_pilot_not_counted`。
  - Boundary: `counts_as_experiment=false`、`counts_as_strategy_ablation_result=false`；这是 contract/scaffold proof，不是正式 benchmark。
- 2026-06-21 P6.3 Android emulator phone-use runtime lane 已完成：
  - Run package: `docs/mobile-harness-benchmark/strategy-ablation/runs/p63-android-real-device-lane/`。
  - Verifier JSON: `docs/mobile-harness-benchmark/strategy-ablation/runs/p63-android-real-device-lane/phone_use_runtime_verifier.json`。
  - Run JSON: `docs/mobile-harness-benchmark/strategy-ablation/runs/p63-android-real-device-lane/run.json`。
  - Summary: `docs/mobile-harness-benchmark/strategy-ablation/runs/p63-android-real-device-lane/summary.md`。
  - Result: `status=passed`、`runtime_score=100.0`、`action_acceptance=4/4`。
  - 2026-06-21 strategy validator passed：6 strategies、6 results、`run_kind=strategy_pilot_not_counted`。
  - Boundary: `counts_as_experiment=false`、`counts_as_strategy_ablation_result=false`；这是 emulator phone-use runtime QA，不是正式 benchmark。

## Open Questions

- [ ] P6 是否先以 emulator 作为 primary lane，真机作为 release gate。
- [ ] P6 strategy tournament 使用哪个固定模型和预算。
- [ ] Private holdout tasks 放在公开仓库还是本地受控目录。
- [ ] Real-device Accessibility 授权是否允许半自动化，还是必须人工确认。

## Test Plan

- `flutter test test/services/ test/widgets/strategy_mode_card_test.dart test/widgets/phone_use_mode_card_test.dart`
- `flutter analyze` 针对 P6 新增 Dart 文件。
- `python3 -m py_compile` 针对 P6 新增 verifier/runner scripts。
- Strategy validator 覆盖 P5.8、P6 pilot、promotion gate。
- Android emulator QA 覆盖 install、launch、Tools 页、phone-use dry/action probe。
- Real Android device QA 覆盖 install、launch、Accessibility、runtime verifier、evidence package。

## Assumptions

- P6 继续遵守 non-counted 边界。
- 真机和 emulator 都由外部 harness 通过 adb 或等价 device channel 控制。
- App 内部 phone-use 必须受 Accessibility 权限门控。
- MobileCode 不提交 secret、private path、raw transcript、credential dump。
