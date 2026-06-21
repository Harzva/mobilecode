目标：将 MobileCode Mobile Harness Reasoning Strategy 从 scaffold 推进到发布级可用状态，完整实现 ReAct、Plan-Execute-Verify、Supervisor/Handoff、SwarmRouter、HierarchicalSwarm 的可运行策略框架，并完成测试、验证、文档、发布门禁。

工程路径：
MobileCode 仓库根目录（本机路径由开发者环境决定，不写入公开交付文档）。

当前背景：
MobileCode 已有：
- P0 strategy-ablation docs/schema/registry/runner/validator
- P1 reasoning strategy Dart models
- P2 fake_reasoning_strategy_runner，但 retry/finalStatus 测试未绿
- P3-lite reasoning_strategy_controller
- P4a runner contract / promotion gate
- P4b real runner adapter skeleton
- P4c fake callback pilot artifact

核心要求：
不要只做 scaffold。要做到 app 内可发布、可测试、可回滚、可观测、默认安全的真实策略框架。
但不得伪造 benchmark 结果。没有真实模型、真实工具、真实设备、真实 verifier 证据的结果必须保持 non-counted。

必须实现：

1. 修复 P2
- 修复 fake runner 的 retry/finalStatus 聚合逻辑。
- `fail -> retry -> pass` 最终必须是 `passed`。
- `fail -> retry -> failAccepted` 最终必须是 `failAccepted`。
- Flutter reasoning strategy tests 必须全绿。

2. StrategyDispatcher
新增统一策略分发器：
- 输入：strategyId、userGoal、memoryPacket、runKind、tool/model/verifier adapters、budget。
- 输出：ReasoningStrategyRunOutput。
- 支持：
  - `react_single_agent`
  - `plan_execute_verify_single_agent`
  - `react_with_final_verifier`
  - `supervisor_handoff_multi_agent`
  - `swarm_router_multi_agent`
  - `hierarchical_swarm_multi_agent`
- 未启用或风险较高策略必须有 feature flag / capability gate。

3. ReActRunner
实现真实 ReAct 框架：
- `think -> act -> observe -> repeat -> report`
- max iterations
- tool allowlist
- structured ActionEvidence
- StrategyTrace events
- timeout / cancellation
- blocked recovery
- no raw secret echo
- 支持 fake adapter 和 real callback adapter 两种模式。

4. PlanExecuteVerifyRunner
实现真实 PEV 框架：
- plan 生成 3-7 个 step
- execute step
- verify step
- retry / replan
- failAccepted / blocked 明确落账
- StepVerification 必须成为每步 gate
- 每步都要写 StrategyTrace 和 ActionEvidence。

5. ReactWithFinalVerifierRunner
实现：
- ReAct actor 完成任务
- final verifier 独立检查 artifact/evidence/trace
- verifier 只能收到 filtered trace summary，不能收到 raw transcript。

6. SupervisorHandoffRunner
实现最小可发布多智能体协同：
- Supervisor 负责任务拆解、预算、路由、停止条件
- Specialist roles：
  - CodeAgent
  - RuntimeAgent
  - PreviewAgent
  - VerifierAgent
  - MemoryAgent
  - ReporterAgent
- 每次交接必须用 HandoffPacket
- HandoffPacket 必须应用 inputFilter：
  - summary_only
  - remove_tool_calls
  - evidence_refs_only
- 不允许把 raw transcript 直接交给下游 agent。
- 每个 role 必须有 tool allowlist。

7. SwarmRouterRunner
实现发布级但默认 experimental 的 Router：
- 根据 task category / runtime profile / device tier / tool availability 选择 worker group
- 支持 load / budget / risk routing
- 输出 judge/verifier evidence
- 默认不参与正式 benchmark，除非显式开启。

8. HierarchicalSwarmRunner
实现发布级但默认 experimental 的层级 manager-worker：
- manager plan
- worker subtasks
- judge
- manager reconcile
- report
- 必须有最大 worker 数、最大 handoff 数、最大 token/step budget。

9. Memory 管理
将现有 MemoryService 接入 HarnessMemoryPacket：
- TTL
- compaction
- redaction
- recent turns limit
- project facts
- error patterns
- user preferences
- 不写 raw transcript
- Memory commit 必须是 proposal，除非用户/设置明确允许持久化。

10. Evidence / Trace
完善 run-level evidence：
- StrategyTrace 必须串起 plan/think/act/observe/verify/handoff/replan/report/memory_commit。
- ActionEvidenceStore 继续记录 action-level evidence。
- 新增或复用 run-level strategy ledger。
- 所有 artifact path、screenshot path、logs、verifier output 都要可追踪。

11. Benchmark 安全边界
- scaffold / dry-run / pilot 不能 counted。
- strategy_ablation_result 只有在具备以下证据时允许：
  - model logs
  - token records
  - verifier outputs
  - tool evidence
  - device/emulator evidence
  - screenshots 或 preview evidence
- PromotionGate 必须强制执行。

12. UI / App 发布要求
- 在 app 内提供 strategy mode 选择：
  - Auto
  - ReAct
  - Plan-Execute-Verify
  - Supervisor/Handoff
  - Experimental Swarm
- 默认使用安全 Auto。
- Experimental 策略必须标注实验性。
- UI 必须展示：
  - 当前 strategy
  - run status
  - trace summary
  - evidence summary
  - blocked reason
  - retry/replan 状态
- 不泄露 API key、private path、raw transcript。

13. 测试要求
必须新增/修复 Flutter tests：
- reasoning_strategy_models_test
- fake_reasoning_strategy_runner_test
- reasoning_strategy_controller_test
- reasoning_strategy_runner_contract_test
- reasoning_strategy_pilot_runner_test
- reasoning_strategy_real_runner_adapter_test
- strategy_dispatcher_test
- react_runner_test
- plan_execute_verify_runner_test
- supervisor_handoff_runner_test
- swarm_router_runner_test
- hierarchical_swarm_runner_test
- memory_packet_service_test
- strategy_promotion_gate_test

必须跑通：
cd mobile_agent
flutter test test/services/

再跑：
python3 -m py_compile \
  scripts/run_mobile_harness_strategy_ablation.py \
  scripts/validate_mobile_harness_strategy_ablation.py \
  scripts/generate_mobile_harness_strategy_callback_pilot.py

python3 scripts/validate_mobile_harness_strategy_ablation.py \
  --registry docs/mobile-harness-benchmark/strategy-ablation/strategy_registry.json \
  --run docs/mobile-harness-benchmark/strategy-ablation/runs/r1-scaffold/run.json

python3 scripts/validate_mobile_harness_strategy_ablation.py \
  --registry docs/mobile-harness-benchmark/strategy-ablation/strategy_registry.json \
  --run docs/mobile-harness-benchmark/strategy-ablation/runs/p4c-callback-pilot/run.json

git diff --check

14. 真实 QA
完成后必须做 Android emulator QA：
- 安装最新 APK
- 打开 MobileCode
- 选择不同 strategy mode
- 跑一个 fake/dry-run strategy trace
- 验证 UI 不崩溃
- 验证 trace/evidence 能展示
- 截图保存到 docs/assets 或 docs/mobile-harness-benchmark/strategy-ablation/evidence/
- 不把 fake QA 写成真实 benchmark 结果。

15. 文档要求
更新：
- docs/mobile-harness-benchmark/strategy-ablation/README.md
- docs/mobile-harness-benchmark/strategy-ablation/mobile-harness-reasoning-strategy-v1.md
- docs/mobile-harness-benchmark/strategy-ablation/long_term_goal.md
- docs/mobile-harness-benchmark/strategy-ablation/subagent-review-protocol.md
- docs/mobilecode-long-term-roadmap.md

新增发布说明：
- 当前支持哪些策略
- 哪些默认启用
- 哪些 experimental
- 哪些结果可以 counted
- 哪些结果只能 non-counted
- 如何复现测试
- 如何开启/关闭策略

验收标准：
- 所有 Dart reasoning strategy tests 通过。
- Python validator 通过。
- git diff --check 通过。
- Android emulator 可启动并完成至少一次 non-counted strategy run。
- UI 可查看 strategy trace/evidence。
- 默认不触网、不调用真实 provider、不执行危险工具。
- 真实 provider/tool/device callback 必须显式注入和授权。
- 没有伪造 benchmark 结果。
- 没有泄露 secrets、API key、raw transcript、private credentials。
- 产出可发布级代码、文档、截图证据和测试结果摘要。

最终交付：
1. 代码实现。
2. 测试通过结果。
3. Android emulator QA 截图路径。
4. 策略能力矩阵。
5. 发布风险清单。
6. 下一阶段真实 benchmark pilot 计划。

2026-06-20 当前交付登记：
- 最新 Android release APK 已构建：`mobile_agent/build/app/outputs/flutter-apk/app-release.apk`。
- APK SHA256：`7dcdfcd532981c05892017d40af3541c424b31e6f7f0682110540ff4ad416fb8`。
- Android emulator QA 已在 `Pixel_7_API_36` / `emulator-5554` 完成安装和启动；`install.txt` 为 `Success`，`launch.txt` 为 `Status: ok`。
- Strategy UI 已在 Tools 页验证五个模式：Auto、ReAct、Plan-Execute-Verify、Supervisor/Handoff、Experimental Swarm。
- 五个模式均为 non-counted dry trace，且 UI 展示 current strategy、run status、trace/evidence、blocked reason、retry/replan、handoff、memory packet。
- Experimental Swarm 仍按预期被 feature gate 阻断，blocked reason 为 `experimental_strategy_disabled`，`counts_as_experiment=false`。
- QA 证据目录：`mobile_agent/qa-output/android-strategy-qa-20260620-062617/`。
- 关键截图：
  - `screenshot-strategy-auto-details.png`
  - `screenshot-strategy-react-details.png`
  - `screenshot-strategy-pev-details.png`
  - `screenshot-strategy-supervisor-details.png`
  - `screenshot-strategy-swarm-details.png`
- 关键 UI XML：
  - `window-strategy-auto-details.xml`
  - `window-strategy-react-details.xml`
  - `window-strategy-pev-details.xml`
  - `window-strategy-supervisor-details.xml`
  - `window-strategy-swarm-details.xml`
- App-scoped logcat：`logcat-app-after-details.txt`，未发现 `FATAL EXCEPTION`、`E/flutter`、`ANR`、`MissingPluginException`。
- 该 QA 结果不是正式 benchmark，不得写入 counted strategy ablation result。

2026-06-21 P6.0-P6.2 runtime benchmark upgrade evidence:
- P6.0 taxonomy、P6.1 communication substrate、P6.2 verifier scaffold 已生成 contract/scaffold 证据。
- Contract doc：`docs/mobile-harness-benchmark/strategy-ablation/p60-p62-runtime-benchmark-contract.md`。
- Contract JSON：`docs/mobile-harness-benchmark/strategy-ablation/runs/p60-p62-runtime-benchmark-upgrade/runtime_benchmark_upgrade_contract.json`。
- Verifier JSON：`docs/mobile-harness-benchmark/strategy-ablation/runs/p60-p62-runtime-benchmark-upgrade/runtime_benchmark_upgrade_verifier.json`。
- Run JSON：`docs/mobile-harness-benchmark/strategy-ablation/runs/p60-p62-runtime-benchmark-upgrade/run.json`。
- Summary：`docs/mobile-harness-benchmark/strategy-ablation/runs/p60-p62-runtime-benchmark-upgrade/summary.md`。
- 2026-06-21 strategy validator passed：6 strategies、18 results、`run_kind=strategy_pilot_not_counted`。
- Boundary：`counts_as_experiment=false`、`counts_as_strategy_ablation_result=false`；本轮不是正式 benchmark。
- P6.3 Android real device lane 下一步：安装最新 APK 到独立 Android emulator 或真机，授权/核验 MobileCode Phone Use Accessibility service，跑 dry/action probe，并保存 screenshot、UI XML、logcat、focus state、WebView state assertions；promotion gate 前继续 non-counted。
