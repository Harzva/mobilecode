# MobileCode / MobileHarnessBench — Long-Term Goal (Strategy Ablation Program)

## 1. 当前已经完成的 P 层级（真实状态）

当前系统已经逐步构建出完整的 strategy ablation 研究栈：

- **P1**：Harness Memory Contract（MemoryPacket / Handoff / Trace / Verification）
- **P2**：Fake Reasoning Strategy Runner（ReAct / Plan-Execute-Verify mock loop）
- **P3**：Controller Adapter Layer（MobileCode 应用层接入 fake runner）
- **P4a**：Runner Contract + Instrumentation（time / token / effect metrics）
- **P4b**：Real Runner Adapter Skeleton（可注入 callbacks，但默认 blocked）
- **P4c**：Callback Test Harness（生成 validator-compatible pilot artifact）
- **P4d-pre**：App-side StrategyDispatcher 与六类 non-counted runner 已落地：
  ReAct、Plan-Execute-Verify、ReAct+FinalVerifier、Supervisor/Handoff、
  SwarmRouter、HierarchicalSwarm。
- **P4d-pre**：HarnessMemoryPacketService 已把 MemoryService 接入 TTL /
  compaction / redaction / proposal-only memory commit。

👉 当前阶段：**P4d 前置能力正在形成“App 内可发 trace 的非计数闭环”**

仍未完成的发布级要求：

- App 内 strategy mode selector 与 trace/evidence UI。
- Android emulator 安装最新 APK 后的 strategy trace QA 截图。
- 真实 provider/tool/device/verifier callback 证据。
- P6 counted benchmark 所需 model logs、token logs、tool logs、device logs、
  verifier outputs。

---

## 2. 总体目标（Ultimate Goal）

构建一个统一的 **Agent Reasoning Strategy Benchmark System**，实现：

> 在完全可控条件下，对不同 agent 推理策略进行严格消融实验（ablation study）

比较维度：

- ReAct
- Plan-Execute-Verify
- Supervisor / Handoff
- Swarm / Hierarchical Swarm
- Memory-Augmented Strategies

### 三大核心指标：

1. **Time Cost**
2. **Token Cost**
3. **Effectiveness / Quality**

---

## 3. 长期演化路线图（P0 → P7）

### P0 — Problem Definition Layer
- 定义 benchmark schema
- 定义 task bank
- 定义 evaluation rubric

---

### P1 — Memory & Evidence Layer
- MemoryPacket
- HandoffPacket
- StrategyTrace
- StepVerification

---

### P2 — Fake Reasoning Loop Layer
- ReAct fake loop
- Plan-Execute-Verify fake loop
- deterministic simulation runner

---

### P3 — Application Adapter Layer
- MobileCode controller integration
- fake runner embedding

---

### P4 — Benchmark Infrastructure Layer

#### P4a
- Runner contract
- instrumentation system
- promotion gate

#### P4b
- real runner adapter skeleton
- injected callbacks (model/tool/verifier)
- default blocked execution

#### P4c
- callback-based pilot harness
- deterministic artifact generator
- validator-compatible run output

#### P4d
- review-only phase
- audit all fake vs real boundaries
- enforce evidence strictness
- app-side dispatcher/runner safety audit
- strategy UI and Android emulator non-counted trace QA

---

### P5 — Non-Counted Real Pilot Layer
- real model callbacks (gated)
- real tool execution (sandboxed)
- real device/emulator (optional)
- still non-counted by default

---

### P6 — Full Benchmark Execution Layer
- enable counted experiments
- full time/token logging
- reproducible comparisons

---

### P7 — Scaling & Multi-Agent Optimization
- multi-device evaluation
- distributed swarm benchmark
- continuous evaluation pipeline

---

## 4. Execution Model（关键设计）

### 4.1 单一执行原则

所有 agent execution 都必须满足：

```
Strategy Input
   ↓
Controlled Runner
   ↓
Trace + Evidence
   ↓
Metrics Collector
   ↓
Promotion Gate
```

---

### 4.2 非计数原则（Hard Constraint）

在 P1–P4c 阶段：

- ❌ 不允许 counted result
- ❌ 不允许 benchmark ranking
- ❌ 不允许 performance conclusion
- ❌ 不允许 real model assumption

---

### 4.3 Evidence Gate（核心控制）

只有满足以下条件才允许进入 P6 counted phase：

- model_logs
- token_logs
- tool_logs
- device_logs
- verifier_outputs

否则必须标记：

```
strategy_pilot_not_counted
```

---

## 5. Long-Term Goal Execution Loop（核心机制）

### Loop Definition

```
while (system_not_complete):
    1. pick next P-phase task
    2. generate implementation via local agent
    3. run validator
    4. run review protocol
    5. classify output:
        - valid
        - needs patch
        - downgrade to non-counted
        - reject
    6. update strategy registry
```

---

## 6. Local Model Usage Policy

当前系统原则：

- 不直接调用真实模型 API
- 不依赖外部网络
- 所有“模型调用”必须通过：
  - fake callback
  - injected callback
  - sandbox runner

未来 P5 才允许：
- local model runtime (optional)
- still gated by promotion system

---

## 7. Review System（强制机制）

所有子 agent 输出必须通过：

```
subagent-review-protocol.md
```

检查项：

- scope boundary
- evidence boundary
- metric integrity
- safety/privacy
- testability
- strategy contamination risk

---

## 8. Final Objective Statement

最终目标不是构建一个 agent，而是构建：

> A reproducible scientific benchmark system for reasoning strategy comparison in mobile agent systems.

---

## 9. Completion Condition

系统被认为“完成”的条件：

- P6 benchmark fully executable
- P6 produces reproducible results
- P7 scaling stable
- no fake-counted leakage exists
- review gate passes all phases

---

## 10. Key Insight

所有 P 阶段本质是：

> 从 “fake reasoning” → “controlled reasoning” → “measured reasoning” → “scientific benchmarking”
