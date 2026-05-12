# Mobile-Coding Agent 能力演进路线图

---

## 一、什么是 Coding Agent？

### 三层进化模型

```
Level 1: AI Copilot（副驾驶）        ← 我们现在的能力
         用户写代码，AI提建议
         "帮我补全这行代码"
         
Level 2: AI Agent（智能体）          ← 近期目标
         用户说需求，AI动手做
         "给我做一个待办事项App"
         → AI自己创建文件、写代码、运行、修复
         
Level 3: AI Developer（开发者）      ← 远景目标
         用户说想法，AI全搞定
         "我想做一个记账App，要有图表和云同步"
         → AI自主设计架构、写代码、测bug、发布
```

### AppAgent 是通用 Agent（操作手机UI）
### Mobile-Coding Agent 是专业 Coding Agent（编写代码）

两者技术同源，但 Agent 的动作空间完全不同：

| 维度 | AppAgent | Mobile-Coding Agent |
|------|----------|---------------------|
| 动作空间 | tap / text / long_press / swipe | writeFile / editCode / runCommand / gitCommit / fixBug |
| 观察空间 | 屏幕截图 | 代码文件 + 终端输出 + 错误信息 |
| 决策输入 | "在Twitter上关注某人" | "实现用户登录功能" |
| 决策输出 | UI操作序列 | 代码编辑序列 |
| 知识积累 | UI元素文档库 | 项目代码向量库 |

---

## 二、Mobile-Coding Agent 的核心能力

### 能力1: 需求→代码（自然语言编程）

```
用户说: "创建一个带有本地存储的待办事项App"

AI Agent 的自主执行流程:
┌──────────────────────────────────────────┐
│ Step 1: 任务分解                          │
│  - 创建项目结构                            │
│  - 设计数据模型 (TodoItem)                 │
│  - 实现UI界面 (列表+输入框)                 │
│  - 添加本地存储 (Hive/SQLite)              │
│  - 添加增删改查功能                         │
├──────────────────────────────────────────┤
│ Step 2: 创建项目                           │
│  Action: createProject("todo_app", "flutter")│
├──────────────────────────────────────────┤
│ Step 3: 编写数据模型                        │
│  Action: writeFile("lib/models/todo.dart", modelCode)│
├──────────────────────────────────────────┤
│ Step 4: 编写UI                             │
│  Action: writeFile("lib/screens/home.dart", uiCode)  │
├──────────────────────────────────────────┤
│ Step 5: 编写存储服务                        │
│  Action: writeFile("lib/services/storage.dart", storageCode)│
├──────────────────────────────────────────┤
│ Step 6: 编写主入口                          │
│  Action: editFile("lib/main.dart", importAndRoute)    │
├──────────────────────────────────────────┤
│ Step 7: 运行测试                           │
│  Action: runCommand("flutter run")          │
│  Observation: 编译错误！                    │
├──────────────────────────────────────────┤
│ Step 8: 修复错误                           │
│  Action: fixCode("lib/screens/home.dart", errorInfo)  │
├──────────────────────────────────────────┤
│ Step 9: 再次运行                           │
│  Action: runCommand("flutter run")          │
│  Observation: 运行成功！                    │
├──────────────────────────────────────────┤
│ Step 10: 提交Git                           │
│  Action: gitCommit("Initial todo app implementation") │
└──────────────────────────────────────────┘
```

### 能力2: 代码自我进化（Self-Evolution）

```
AI Agent 发现代码有问题:
  运行测试 → 发现bug → 定位问题 → 自主修复 → 验证修复

循环直到所有测试通过:
  ┌──────────┐
  │ 运行测试  │
  └────┬─────┘
       │ 有错误?
       ▼
  ┌──────────┐     否     ┌──────────┐
  │ 定位错误  │──────────→│ 全部通过  │
  └────┬─────┘           └──────────┘
       ▼
  ┌──────────┐
  │ 分析原因  │
  └────┬─────┘
       ▼
  ┌──────────┐
  │ 生成修复  │
  └────┬─────┘
       ▼
  ┌──────────┐
  │ 应用修复  │
  └────┬─────┘
       ▼
  ┌──────────┐
  │ 重新测试  │
  └──────────┘
```

### 能力3: 多文件协同编辑

```
用户说: "把用户认证系统添加到项目中"

AI Agent 同时操作多个文件:
  1. 新建 lib/models/user.dart
  2. 新建 lib/services/auth_service.dart
  3. 新建 lib/screens/login_screen.dart
  4. 编辑 lib/main.dart（添加路由）
  5. 编辑 pubspec.yaml（添加依赖）
  6. 编辑 lib/screens/home.dart（添加登录入口）

所有操作作为一个原子任务提交
```

### 能力4: 终端命令执行（借鉴 AppAgent 的动作空间）

```dart
/// Agent 可执行的终端命令
enum AgentCommand {
  flutterRun,        // flutter run
  flutterBuild,     // flutter build apk/ios
  flutterTest,      // flutter test
  flutterPubGet,    // flutter pub get
  flutterClean,     // flutter clean
  npmInstall,       // npm install
  npmRunBuild,      // npm run build
  npmRunDev,        // npm run dev
  gitInit,          // git init
  gitCommit,        // git commit
  gitPush,          // git push
  gitPull,          // git pull
  dartFormat,       // dart format
  dartAnalyze,      // dart analyze
  custom,           // 自定义命令
}
```

### 能力5: 自主学习能力（借鉴 AppAgent 的探索阶段）

```
用户说: "我想在这个项目中使用 Riverpod 状态管理"

AI Agent 的学习流程:
  1. 搜索 Riverpod 官方文档
  2. 阅读 pub.dev 上的使用示例
  3. 分析项目中现有的状态管理方式
  4. 制定迁移计划
  5. 先在一个小文件上尝试
  6. 验证可行性
  7. 全面迁移
  8. 运行测试确认
  
学习成果持久化到项目知识库:
  "本项目使用 Riverpod 进行状态管理"
  "推荐在 screens 层使用 ConsumerWidget"
  "推荐使用 StateNotifierProvider"
```

---

## 三、Agent 架构设计（借鉴 AppAgent）

```
┌─────────────────────────────────────────────────────────────┐
│                   Mobile-Coding Agent                       │
│                                                             │
│  ┌─────────────┐     ┌──────────────┐     ┌─────────────┐ │
│  │  输入层      │     │   决策引擎    │     │  执行层      │ │
│  │ Input Layer │────→│ Decision Core│────→│Action Layer │ │
│  └──────┬──────┘     └──────┬───────┘     └──────┬──────┘ │
│         │                    │                     │        │
│  语音输入 │              LLM 推理              文件操作     │
│  文本输入 │               (GPT-4/Claude)       终端命令     │
│  截图输入 │                    │               Git操作     │
│  代码上下文│                    │               API调用     │
│         │                    │                     │        │
│  ┌──────▼──────┐     ┌──────▼───────┐     ┌──────▼──────┐ │
│  │ 多模态理解   │     │  任务规划器   │     │  执行验证器   │ │
│  │Multimodal   │     │ Task Planner │     │Validator    │ │
│  │Understanding│     │              │     │             │ │
│  └─────────────┘     └──────────────┘     └─────────────┘ │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                  记忆层 (Memory)                        │  │
│  │  短期记忆: 当前会话上下文                                │  │
│  │  长期记忆: 项目知识库 + 用户偏好                          │  │
│  │  向量记忆: 代码语义索引                                  │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 四、三阶段实现路线图

### Phase 1: AI Copilot（已完成 ✅）

| 功能 | 状态 |
|------|------|
| AI 代码补全 | ✅ |
| AI 代码解释 | ✅ |
| AI 错误修复 | ✅ |
| AI 代码生成 | ✅ |
| AI 聊天问答 | ✅ |

### Phase 2: AI Agent（2025 Q3-Q4）

| 功能 | 说明 | 优先级 |
|------|------|--------|
| 需求→多文件生成 | 一句话生成完整功能模块 | 🔴 P0 |
| 终端命令执行 | 在App内运行 flutter build/test | 🔴 P0 |
| 错误自修复循环 | 编译错误→AI自动修复→重试 | 🔴 P0 |
| 项目知识库索引 | AI先学习项目再编码 | 🟠 P1 |
| 截图→UI代码 | 看到UI→生成代码 | 🟠 P1 |
| 自主任务分解 | 复杂需求自动拆分子任务 | 🟠 P1 |
| 多模态输入 | 截图+语音+文本融合 | 🟡 P2 |

### Phase 3: AI Developer（2026）

| 功能 | 说明 | 优先级 |
|------|------|--------|
| 全App自主开发 | "做一个记账App"→AI全搞定 | 🔴 P0 |
| 自主技术选型 | AI分析需求选择最佳技术栈 | 🔴 P0 |
| 自主测试覆盖 | AI写单元测试+集成测试 | 🟠 P1 |
| 自主代码审查 | AI审查代码质量+性能 | 🟠 P1 |
| 持续进化 | AI根据用户反馈持续优化 | 🟡 P2 |

---

## 五、核心代码：Agent Action 系统

```dart
/// lib/services/agent_action_system.dart

/// Agent 可执行的所有动作（借鉴 AppAgent 的动作空间思想）
abstract class AgentAction {
  String get name;
  String get description;
  Map<String, dynamic> get params;
  
  /// 执行动作
  Future<ActionResult> execute();
  
  /// 回滚动作（用于错误恢复）
  Future<void> rollback();
}

/// 文件操作
class WriteFileAction extends AgentAction {
  final String filePath;
  final String content;
  String? previousContent; // 用于回滚
  
  WriteFileAction({required this.filePath, required this.content});
  
  @override
  Future<ActionResult> execute() async {
    // 1. 保存旧内容（用于回滚）
    previousContent = await readFile(filePath);
    
    // 2. 写入新内容
    await writeFile(filePath, content);
    
    // 3. 验证写入成功
    final written = await readFile(filePath);
    if (written != content) {
      return ActionResult.failure('写入内容不匹配');
    }
    
    return ActionResult.success('文件写入成功: $filePath');
  }
  
  @override
  Future<void> rollback() async {
    if (previousContent != null) {
      await writeFile(filePath, previousContent!);
    }
  }
}

/// 终端命令执行
class RunCommandAction extends AgentAction {
  final String command;
  final String workingDirectory;
  
  RunCommandAction({required this.command, required this.workingDirectory});
  
  @override
  Future<ActionResult> execute() async {
    final result = await Process.run(
      command,
      [],
      workingDirectory: workingDirectory,
      runInShell: true,
    );
    
    if (result.exitCode == 0) {
      return ActionResult.success(result.stdout);
    } else {
      return ActionResult.failure(result.stderr);
    }
  }
  
  @override
  Future<void> rollback() async {
    // 命令类操作通常不可回滚
  }
}

/// 任务计划（借鉴 AppAgent 的任务分解）
class AgentTaskPlan {
  final String taskDescription;
  final List<AgentAction> actions;
  
  AgentTaskPlan({required this.taskDescription, required this.actions});
  
  /// 执行整个计划
  Future<PlanResult> execute() async {
    final completed = <AgentAction>[];
    
    for (final action in actions) {
      final result = await action.execute();
      
      if (result.isSuccess) {
        completed.add(action);
      } else {
        // 执行失败，回滚已完成的操作
        for (final completedAction in completed.reversed) {
          await completedAction.rollback();
        }
        return PlanResult.failure('步骤 ${action.name} 失败: ${result.message}');
      }
    }
    
    return PlanResult.success('所有步骤执行成功');
  }
}
```

---

## 六、借鉴 AppAgent 的关键设计

| AppAgent 设计 | Mobile-Coding Agent 对应设计 |
|--------------|---------------------------|
| `prompts.py` 提示词模板 | `coding_prompts.dart` 编码专用Prompt |
| `model.py` LLM抽象层 | `llm_service.dart` 多提供商LLM |
| `task_executor.py` 任务执行 | `agent_action_system.dart` Action系统 |
| `self_explorer.py` 自主探索 | `project_learning_service.dart` 项目学习 |
| `document_generation.py` 文档生成 | `code_knowledge_service.dart` 代码知识库 |
| `step_recorder.py` 步骤记录 | `agent_session_logger.dart` Agent会话记录 |
| 屏幕截图观察 | 代码文件+终端输出观察 |
| UI元素编号 | 代码行号+文件路径定位 |

---

## 七、一句话总结

> **现在：Mobile-Coding 是"口袋里的 VS Code + Copilot"**
> **未来：Mobile-Coding Agent 是"口袋里的全栈程序员"**
> 
> 用户说需求，Agent 动手做。这就是我们的终极目标。
