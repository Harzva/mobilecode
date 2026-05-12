# Mobile-Coding Phase 2 执行计划

## 目标：Agent 核心能力（4个模块）

### 模块1: 语音输入系统（Voice→Code）
- `speech_to_text` 包集成
- 语音波形动画UI
- 语音→自然语言→代码生成链路
- 借鉴 easyVoice 的语音流式处理架构

### 模块2: 截图→代码（Screenshot→Code）🔥核心差异化
- 相机/相册选取图片
- 多模态LLM分析（GPT-4V/Claude 3）
- UI截图→Flutter/React代码生成
- 报错截图→自动定位修复

### 模块3: Agent Action 系统
- 定义Agent可执行的动作空间
- Action执行引擎+回滚机制
- 任务规划器（Task Planner）
- 执行验证器

### 模块4: Coding Prompt 模板库
- 借鉴AppAgent的prompts.py思想
- 代码解释/修复/生成/优化标准化Prompt
- 项目风格学习Prompt

## 执行分组
- Group-Voice: 语音输入系统
- Group-Vision: 截图→代码系统
- Group-Agent: Agent Action + Prompt模板
