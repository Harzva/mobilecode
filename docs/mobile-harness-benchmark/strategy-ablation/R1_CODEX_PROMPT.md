# MobileCode Agent Reasoning Strategy Ablation Benchmark R1 — Codex 提示词

> 用途：把 ReAct、Plan-Execute-Verify、Supervisor/Handoff、SwarmRouter/HierarchicalSwarm 等推理方法和协同算法作为 MobileHarnessBench 的消融实验策略，比较时间、token 消耗和效果三类指标。

---

你现在在工程：

```text
<repo-root>
```

本轮任务：为 MobileCode / MobileHarnessBench 新增一个“Agent Reasoning Strategy Ablation Benchmark”设计与脚手架。注意：我们最终要做的是 benchmark，不是单纯做一个 agent 产品。ReAct、Plan-Execute-Verify、Supervisor/Handoff、SwarmRouter/HierarchicalSwarm 等推理方法和多智能体协同算法，都是不同的消融实验策略。我们要在同一任务集、同一模型、同一环境下比较它们的三类指标：

1. 时间消耗：wall-clock time、planning time、execution time、verification time、平均每任务耗时。
2. Token 消耗：prompt tokens、completion tokens、total tokens、每成功任务 token、工具调用输入输出字符数或近似 token。
3. 效果指标：task_success、verified_success、trace_completeness、artifact_availability、recovery_rate、human_intervention_count、steps_to_completion。

本轮不要伪造真实实验结果。没有真实模型/API/设备执行的结果必须标记为 `scaffold_not_run`、`dry_run_not_counted` 或 `pilot_not_counted`，不能写成正式实验结论。

## 0. 先读取当前 benchmark 结构

请先读取这些文件，理解当前工程已有 benchmark 结构：

- `MOBILECODE_RULES.md`
- `docs/mobile-harness-benchmark/README.md`
- `docs/mobile-harness-benchmark/runbook.md`
- `docs/mobile-harness-benchmark/rubric.md`
- `docs/mobile-harness-benchmark/schema/baseline_run.schema.json`
- `docs/mobile-harness-benchmark/tasks/smoke-v2.json`
- `docs/mobile-harness-benchmark/tasks/frozen-v2-paper-subset.json`
- `scripts/run_mobile_harness_bench.py`
- `scripts/validate_mobile_harness_bench.py`

再读取外部 agent 推理知识库索引，不要全文塞入上下文：

- `<local-agent-reasoning-index>/framework_matrix.md`
- `<local-agent-reasoning-index>/repo_manifest.md`
- `<local-agent-reasoning-index>/readme_heading_index.md`

然后用这个脚本检索相关方法，只读取最相关的少量命中文件：

```bash
cd <local-agent-reasoning-index>
python3 scripts/search_agent_zoo.py react planning execute verify --top 20
python3 scripts/search_agent_zoo.py swarm handoff supervisor router --snippets --top 20
python3 scripts/search_agent_zoo.py guardrails tracing session workflow --snippets --top 20
```

本轮要完成的是 R1 脚手架，不要大规模重构，不要污染现有 benchmark，不要覆盖已有文件。优先新增文件。

## 一、建立 strategy ablation 的实验定义

新增目录：

```text
docs/mobile-harness-benchmark/strategy-ablation/
```

在里面创建：

### 1. `README.md`

说明本 benchmark 的定位：比较不同 agent reasoning strategy / collaboration strategy 在 MobileHarnessBench 任务上的表现。必须明确：

- Independent variable：agent strategy。
- Controlled variables：task subset、model、device tier、runtime、tool access、prompt budget、max steps。
- Dependent metrics：time、token、effectiveness。
- Evidence boundary：未真实执行的结果不能算正式实验。
- Threats：模型波动、任务难度差异、工具权限差异、缓存影响、人工介入影响。

### 2. `strategy-taxonomy.md`

定义至少这些策略：

#### `react_single_agent`

- 单智能体 ReAct：observe → reason → act → observe。
- 优点：实现简单、工具闭环强。
- 风险：长任务容易局部循环，缺少全局规划。

#### `plan_execute_verify_single_agent`

- 单智能体 Plan-Execute-Verify：先规划，再执行，再验证。
- 优点：适合复杂任务、便于记录计划与回滚。
- 风险：前期规划 token 高，计划可能过时。

#### `react_with_final_verifier`

- ReAct 执行 + 最终 verifier。
- 作用：比较“边做边观察”和“最终统一校验”的组合收益。

#### `supervisor_handoff_multi_agent`

- Supervisor/Router 分配任务给 Planner、Executor、Verifier、Reporter。
- 优点：角色清晰，利于复杂任务。
- 风险：handoff token 和等待时间增加。

#### `swarm_router_multi_agent`

- SwarmRouter / 多智能体路由策略。
- 优点：可根据任务类型调度不同 agent。
- 风险：编排开销大，token 成本可能更高。

#### `hierarchical_swarm_multi_agent`

- 层级 swarm：manager → specialized agents。
- 优点：适合复杂长任务和多阶段任务。
- 风险：实现复杂、延迟和 token 消耗可能最大。

### 3. `metrics-contract.md`

定义三大维度指标：

时间类：

- `wall_time_ms`
- `planning_time_ms`
- `execution_time_ms`
- `verification_time_ms`
- `reporting_time_ms`
- `mean_time_per_successful_task_ms`

Token 类：

- `prompt_tokens`
- `completion_tokens`
- `total_tokens`
- `tool_input_chars`
- `tool_output_chars`
- `estimated_tool_tokens`
- `tokens_per_successful_task`
- `tokens_per_verified_success`

效果类：

- 沿用已有：`task_success`、`verified_success`、`trace_completeness`、`recovery_rate`、`artifact_availability`、`human_intervention_count`、`steps_to_completion`
- 新增建议：`strategy_overhead_steps`、`handoff_count`、`planning_revisions`、`verification_failures_recovered`

综合指标不要强行替代原始指标，但可以新增：

- `efficiency_score`
- `quality_score`
- `cost_quality_ratio`

公式可以先写在文档里，不必强行用于正式结果：

```text
quality_score =
  0.35 * task_success
+ 0.35 * verified_success
+ 0.15 * trace_completeness
+ 0.10 * artifact_availability
+ 0.05 * recovery_rate

efficiency_score =
  quality_score / log(1 + wall_time_ms + estimated_total_tokens)
```

## 二、建立机器可读 schema

新增：

```text
docs/mobile-harness-benchmark/schema/strategy_ablation_run.schema.json
```

要求 schema 至少包含：

- `benchmark`: const `MobileHarnessBench`
- `schema_version`
- `run_id`
- `run_kind`: enum
  - `strategy_scaffold_not_run`
  - `strategy_dry_run_not_counted`
  - `strategy_pilot_not_counted`
  - `strategy_ablation_result`
- `strategy_id`
- `strategy_family`: enum
  - `single_agent_reasoning`
  - `single_agent_with_verifier`
  - `multi_agent_handoff`
  - `multi_agent_swarm`
- `task_subset`
- `environment`
- `model_lock`
- `tool_access_policy`
- `prompt_budget`
- `max_steps`
- `counts_as_experiment`
- `summary`
- `results`
- `evidence_boundary`

每个 result 至少包含：

- `task_id`
- `status`
- `strategy_trace`
- `time_metrics`
- `token_metrics`
- `effect_metrics`
- `evidence`
- `counts_as_strategy_ablation_result`

## 三、建立策略配置文件

新增：

```text
docs/mobile-harness-benchmark/strategy-ablation/strategy_registry.json
```

里面列出 6 个策略，每个策略包含：

- `strategy_id`
- `strategy_family`
- `description`
- `agent_roles`
- `reasoning_loop`
- `allowed_tools`
- `max_steps`
- `max_handoffs`
- `verification_policy`
- `expected_overhead`
- `primary_comparison_targets`

注意：这只是 registry，不是结果。

## 四、建立 benchmark runner 脚手架

新增脚本：

```text
scripts/run_mobile_harness_strategy_ablation.py
```

要求：

- stdlib-only，不要引入额外依赖。
- 默认不调用 LLM，不联网，不读任何 API key。
- 支持参数：

```bash
python3 scripts/run_mobile_harness_strategy_ablation.py \
  --task-set smoke-v2 \
  --strategies react_single_agent,plan_execute_verify_single_agent \
  --run-kind strategy_scaffold_not_run \
  --output docs/mobile-harness-benchmark/strategy-ablation/runs/r1-scaffold
```

- 支持 `--dry-run`，生成结构化结果文件，但所有结果必须明确 `counts_as_experiment=false`。
- 从已有 task set 读取任务。
- 从 `strategy_registry.json` 读取策略。
- 输出：
  - `run.json`
  - `summary.md`
  - `strategy_comparison_table.md`
  - `task_strategy_matrix.csv`

R1 阶段不需要真实执行 agent，只需要生成可审查的 scaffold / dry-run not counted 结构。但字段必须完整，方便后续接入真实 agent 执行器。

## 五、建立验证脚本

新增：

```text
scripts/validate_mobile_harness_strategy_ablation.py
```

要求：

- stdlib-only。
- 验证：
  - `strategy_registry.json` 是否包含必要字段。
  - `run.json` 是否符合关键字段要求。
  - `run_kind` 如果不是 `strategy_ablation_result`，则 `counts_as_experiment` 必须为 false。
  - 没有真实执行 evidence 时，不允许写 `counts_as_strategy_ablation_result=true`。
  - 每个 strategy 的结果数量必须等于 task_count。
  - 每个 result 必须同时包含 time/token/effect 三类 metrics。
- 输出清晰的 pass/fail 信息。

## 六、建立报告文档

新增：

```text
docs/mobile-harness-benchmark/strategy-ablation/r1-design-report.md
```

内容包括：

1. 为什么把 ReAct、Plan-Execute-Verify、Swarm/Handoff 看作消融变量。
2. 实验设计：
   - Same tasks
   - Same model
   - Same tool budget
   - Same max steps
   - Same verifier
3. 三维指标：
   - Time
   - Tokens
   - Effectiveness
4. 对比表模板：
   - Strategy
   - Task success
   - Verified success
   - Wall time
   - Total tokens
   - Steps
   - Handoff count
   - Human intervention
   - Notes
5. 当前 R1 的证据边界：
   - 只是 benchmark design + scaffold。
   - 不声称任何策略更好。
   - 真正实验需要后续接入 LLM runtime、token logger、timer、verifier 和 task runner。

## 七、最小运行测试

完成后执行：

```bash
python3 scripts/run_mobile_harness_strategy_ablation.py \
  --task-set smoke-v2 \
  --strategies react_single_agent,plan_execute_verify_single_agent,supervisor_handoff_multi_agent,swarm_router_multi_agent \
  --run-kind strategy_scaffold_not_run \
  --output docs/mobile-harness-benchmark/strategy-ablation/runs/r1-scaffold

python3 scripts/validate_mobile_harness_strategy_ablation.py \
  --registry docs/mobile-harness-benchmark/strategy-ablation/strategy_registry.json \
  --run docs/mobile-harness-benchmark/strategy-ablation/runs/r1-scaffold/run.json
```

## 八、生成 review 包

最后生成一个压缩包，方便我发给 ChatGPT 检查：

```text
<repo-root>/MobileCode_agent_strategy_ablation_R1_review.zip
```

压缩包至少包含：

- `docs/mobile-harness-benchmark/strategy-ablation/`
- `docs/mobile-harness-benchmark/schema/strategy_ablation_run.schema.json`
- `scripts/run_mobile_harness_strategy_ablation.py`
- `scripts/validate_mobile_harness_strategy_ablation.py`
- `MOBILECODE_RULES.md`
- 本轮变更清单 `R1_CHANGELOG.md`

## 九、输出总结

命令完成后，请在终端输出：

1. 新增/修改文件列表。
2. 运行命令及结果。
3. `run.json` 里 strategy 数量、task 数量、result 数量。
4. 明确说明：R1 是否只是 scaffold，是否没有产生正式实验结论。
5. review zip 的完整路径。

## 重要约束

- 不要删除已有 benchmark 文件。
- 不要伪造真实实验结果。
- 不要调用外部 API。
- 不要读取任何 token/secret。
- 不要安装新依赖。
- 不要把 4 个外部 agent 仓库全文复制进 MobileCode。
- 只通过 `_knowledge_index` 读取必要信息。
- 当前重点是 benchmark 设计、schema、runner scaffold、validator、报告，而不是证明哪个策略最好。
