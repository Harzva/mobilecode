# MobileCode V11 — 4大需求执行计划

## 1. Solo模式改名 — 静默运行

候选名字：
| 名字 | 风格 | 评分 |
|------|------|------|
| **暗影模式** | 酷炫科技感 | ★★★★★ |
| 潜行模式 | 隐秘行动感 | ★★★★☆ |
|  Daemon模式 | 极客技术感 | ★★★★☆ |
| 无感运行 | 简洁直白 | ★★★☆☆ |
| 后台Agent | 功能描述型 | ★★★☆☆ |
| **深潜模式** | 探索感 | ★★★★★ |

**最终选择：深潜模式 (DeepDive Mode)**
- 英文：DeepDive
- 中文：深潜模式
- 含义：AI像潜水员一样深入代码海洋，静默工作，不打扰用户
- Slogan: "AI深潜，代码浮现"

## 2. 宣传标语
新增标语：
- "让手机发烫的除了游戏，还有你写的每一行代码"
- "让手机发烧的又何止是游戏，程序也可以"

## 3. 终端方案

### Termux vs Termius 对比

| 维度 | Termux | Termius |
|------|--------|---------|
| 类型 | 本地Linux环境 | SSH远程客户端 |
| 功能 | 本地运行python/node/git | 连接远程服务器 |
| 权限 | 需要存储权限 | 需要网络权限 |
| 适用场景 | 本地build/test | 远程部署/CI/CD |

### 推荐方案：双终端架构

```
MobileCode 终端系统:
├── 本地终端 (Termux-style)
│   └── 本地执行 flutter build / npm install / python
│   └── 需要集成 Termux API 或类似方案
│
└── 远程终端 (Termius-style) ← 先做这部分，更容易实现
    └── SSH 连接到远程开发服务器
    └── 在远程服务器上执行所有命令
    └── 远程自动发布任务
    └── 远程主机打包为 Skill
```

**先做远程终端 (SSH)** — 更容易实现，价值更大
- 用户配置远程服务器 (IP/端口/用户名/密钥)
- MobileCode 通过 SSH 连接
- 所有命令在远程执行
- 远程主机可以打包为 Skill，一键导入

## 4. MCP + Skill管理

### Skill 架构

```
Skill = 可复用的Agent能力包
├── skill.yaml (元数据)
├── actions/ (动作定义)
├── prompts/ (Prompt模板)
└── config/ (配置)

Skill 来源:
├── 内置 (Built-in)
├── GitHub 一键导入
├── 本地导入 (ZIP)
└── 用户自定义

MCP (Model Context Protocol):
├── 标准化AI工具调用协议
├── Skill 通过 MCP 注册为可用工具
└── MCP Server 管理
```

### Skill管理页面
- 已安装 Skills 列表
- Skill 市场 (GitHub导入)
- MCP Server 管理
- 一键启用/禁用
