# MobileCode V9 — 9大需求执行计划

## 需求3: Agent 范式分析（结合图片）

### 图片中的6大范式 vs MobileCode

| 范式类别 | 图中内容 | MobileCode 采用情况 |
|---------|---------|-------------------|
| 一、核心推理 | ReAct (Reason+Act) | ✅ **已采用** — 思考→写代码→编译→观察→修复 |
| 二、工作流编排 | Prompt Chaining / Routing / Parallelization / GraphFlow | ✅ **已部分采用** — Prompt链式生成 |
| 三、多Agent协作 | Supervisor-Worker / Swarm / Debate / Specialized Experts | ⚠️ **需增强** — 当前单Agent，需多专家Agent |
| 四、交互执行 | Function Calling / MCP / Computer Use | ✅ **已采用** — Function Calling操作文件/终端/Git |
| 五、可靠性增强 | Reflection / Self-Correction / Iterative Refinement / Guardrails | ✅ **已采用** — 代码反思+安全护栏 |
| 六、人机协同 | Human-in-the-Loop | ✅ **已采用** — 关键操作需用户确认 |

### MobileCode 轻量化Agent范式定位

```
MobileCode = 轻量级移动端 Coding Agent
           = ReAct (核心推理)
           + Function Calling (交互执行)
           + Reflection + Self-Correction (可靠性)
           + Human-in-the-Loop (人机协同)
           + Specialized Experts (多Agent — 需要新增)
           + Prompt Chaining + Routing (工作流 — 需要增强)
```

### 多Agent架构设计（Supervisor-Worker 模式）

```
                    ┌──────────────────┐
                    │   User (你)      │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │  Supervisor      │  ← 主Agent，理解需求、分配任务
                    │  Agent           │
                    └────────┬─────────┘
                             │ 任务分发
            ┌────────┬───────┼───────┬────────┐
            ▼        ▼       ▼       ▼        ▼
      ┌─────────┐ ┌──────┐ ┌─────┐ ┌──────┐ ┌─────────┐
      │ 代码专家 │ │ 调试 │ │ Git │ │ 终端 │ │ 项目管理 │
      │ Agent   │ │ Agent│ │Agent│ │ Agent│ │  Agent  │
      └─────────┘ └──────┘ └─────┘ └──────┘ └─────────┘
```

---

## 9大需求分组

### 组A: API管理系统 + 功能开关 + 自定义API (#2, #6, #7)
- API Key 管理系统（类似 CCSwitch）
- 官方订阅支持（ChatGPT Auth / Gemini Auth）
- 自定义 API 接入
- 功能开关（Feature Flags）

### 组B: 性能分析 + Token统计 + Vibing活动 (#4, #5)
- 手机性能分析器
- Token 使用统计（日/周/月）
- Vibing Coding 活动统计（GitHub风格贡献图）

### 组C: 侧边栏Plan + 多智能体监控 (#8)
- 任务Plan侧边栏（实时进度）
- 多Agent监控界面（观察每个Agent在干什么）

### 组D: 微信发文章 + Agent范式 (#1, #3)
- 微信文章自动发布（Apple ID + 密钥）
- Agent范式文档化

---

## 执行策略
- 4组并行开发
- 每组由1个子Agent负责
- 总共约 15-20 个新文件
