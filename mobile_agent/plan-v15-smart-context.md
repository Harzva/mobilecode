# V15 计划：AI 智能上下文注入（丝滑增强版）

## 原则
- **不做功能堆砌**：不增加用户可见的新功能、新按钮、新界面
- **不为分层而分层**：只有一个服务，不搞 6 层架构
- **不为记忆而记忆**：记忆自动沉淀，用户无感知
- **丝滑融入**：用户打开 AI Chat 对话，AI 自动知道项目上下文
- **流畅度优先**：检索延迟 < 50ms，不影响对话体验
- **部署零难度**：只用现有 SQLite，不引入 Milvus/MySQL/Redis 等外部依赖

## 核心目标
**一句话：让 AI 对话自动拥有项目代码上下文**

用户打开 AI Chat → 问"帮我修改登录页面" → AI 自动知道项目里 login.dart 的内容 → 给出精准回答

不需要：手动复制代码、手动@文件、手动选择上下文

## 技术方案

### 1. 代码索引服务（CodeIndexService）- 新增 1 个文件
- **纯 SQLite**，利用现有 `local_database_service.dart`
- 存储：文件路径 + 文件内容 + 简单关键词索引 + 文件类型 + 最后修改时间
- 不需要向量数据库，用 SQLite FTS5（全文搜索）做语义匹配
- 增量索引：只扫描修改过的文件

### 2. 上下文注入器（ContextInjector）- 新增 1 个文件
- 用户发送消息前，自动：
  1. 用关键词提取提取消息中的核心词（如"登录""网络请求"）
  2. 在代码索引中搜索相关文件
  3. 取前 3 个最相关的代码文件
  4. 自动注入到 LLM 的 system prompt 中
- 用户完全无感知

### 3. 项目结构缓存（ProjectStructureCache）- 新增 1 个文件
- 缓存项目的文件树结构
- 增量更新（监听文件变化）
- AI 回答时知道"项目里有哪些页面、哪些服务"

## 不做什么（明确排除）
- ❌ 不引入 Milvus / MySQL / Redis / MinIO
- ❌ 不增加新的 UI 界面或设置项
- ❌ 不搞 6 层记忆架构
- ❌ 不做手动@文件功能
- ❌ 不做代码 Wiki 自动生成
- ❌ 不做向量 Embedding（用 FTS5 关键词搜索足够）

## 影响范围
- 新增 3 个文件，约 400-600 行代码
- 修改 `llm_service.dart`（注入上下文到 prompt）
- 修改 `chat_provider.dart`（发送前自动检索）
- 完全兼容现有所有功能

## 用户体验
| 场景 | 之前 | 之后 |
|------|------|------|
| "帮我改登录页" | AI: "请提供 login.dart 的代码" | AI: "我看到你的 login.dart 使用了 Riverpod，建议这样改..." |
| "网络请求报错" | AI: "请提供相关代码" | AI: "你的 api_service.dart 第 45 行 validateStatus 设置为接受所有状态码，建议..." |
| "怎么添加深潜功能" | AI: "什么是深潜？" | AI: "你的 deep_dive_service.dart 已经实现了 Isolate 后台执行，可以在 editor_screen.dart 中添加入口..." |

## 实现步骤
1. 创建 `code_index_service.dart`（SQLite FTS5 全文索引）
2. 创建 `context_injector.dart`（检索 + 注入逻辑）
3. 修改 `llm_service.dart`（接收上下文）
4. 修改 `chat_provider.dart`（发送前调用注入）
5. 创建 `project_structure_cache.dart`（文件树缓存）
