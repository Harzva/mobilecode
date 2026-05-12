# MobileCode Self-Use (自调用) 架构设计

## 核心洞察

MobileCode 不需要操作其他 App，它可以**操作自己**！

```
传统 App Agent (需要权限):
用户: "打开淘宝买奶茶"
AI → 需要无障碍服务权限 → 操作淘宝UI → 被系统拒绝 ❌

MobileCode Self-Use (无需权限):
用户: "帮我创建一个待办事项App"
AI → 操作自己的代码编辑器 → 自动写代码 → 运行 flutter run → ✅
```

## 为什么 Self-Use 可行？

| 维度 | 操作其他 App | 操作自己 (Self-Use) |
|------|-----------|-------------------|
| 无障碍服务 | ❌ 需要系统权限 | ✅ 不需要，在自己的沙盒内 |
| 开发者模式 | ❌ 需要开启 | ✅ 不需要 |
| Root | ❌ 需要Root | ✅ 不需要 |
| 系统限制 | ❌ 被Android/iOS限制 | ✅ 完全可控 |
| 流畅度 | ❌ 慢（跨进程） | ✅ 极快（同进程） |
| 安全性 | ❌ 高风险 | ✅ 零风险 |

## Self-Use 能力范围

MobileCode 可以操作自己的所有功能模块：

1. **代码编辑器** — 自动写代码、编辑文件、格式化
2. **终端** — 自动执行 flutter/git 命令
3. **项目管理器** — 自动创建项目、添加文件
4. **GitHub 集成** — 自动提交代码、推送
5. **AI 助手** — 自动对话、生成代码
6. **截图→代码** — 分析截图、生成代码
7. **语音→代码** — 听语音、生成代码
8. **设置面板** — 自动调整配置

## 架构：Self-Invocation Service

```
用户输入: "创建一个登录页面"
  ↓
SelfInvocationService.parseIntent()
  ↓
SelfActionPlan (任务分解):
  Step 1: editor.createFile("login_page.dart")
  Step 2: editor.writeCode(loginCode)
  Step 3: terminal.run("flutter run")
  Step 4: github.commit("Add login page")
  ↓
逐个执行 SelfAction
  ↓
每个动作通过 Flutter 的 Widget 控制器直接操作 UI
  ↓
实时反馈到 Agent Dashboard
```

## 技术实现

使用 Flutter 的 GlobalKey + Widget Controller 模式：
- 每个关键 Widget 注册一个 GlobalKey
- Self-Use Service 通过 Key 找到 Widget 并调用其方法
- 所有操作在 MobileCode 自己的进程中完成
- 不需要任何系统权限
