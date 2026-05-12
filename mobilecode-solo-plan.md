# MobileCode Solo 模式 — 后台静默执行

## 核心需求

类似 Trae AI 编辑器的 Solo 模式：
1. **后台执行**：Agent 任务在独立 Isolate 中运行
2. **不阻塞 UI**：用户可正常编辑、浏览、切到其他 App
3. **系统通知**：通知栏显示实时进度
4. **Solo 工作区**：独立页面查看后台任务
5. **切回查看**：随时回来检查进度和结果

## 技术方案

```
用户请求: "创建一个待办App"
  ↓
SoloModeService 接收任务
  ↓
创建 Isolate（独立线程）
  ↓
Isolate 中执行 Agent 任务（不阻塞主线程）
  ↓
通过 SendPort 发送进度到主线程
  ↓
主线程更新：
  - Solo 页面（如果用户在查看）
  - 系统通知栏（始终可见）
  - 迷你进度条（底部）
  ↓
用户同时可以：
  - 正常编辑代码 ✅
  - 浏览其他页面 ✅
  - 切到其他 App ✅
  - 随时切回 Solo 页面查看进度 ✅
```

## 实现模块

1. `solo_mode_service.dart` — 核心后台服务（Isolate + 通知）
2. `foreground_service.dart` — Android 前台服务保持存活
3. `solo_mode_screen.dart` — Solo 工作区页面
4. `solo_task_manager.dart` — 后台任务队列管理
5. `notification_manager.dart` — 系统通知管理
6. `solo_mode_provider.dart` — Riverpod 状态管理
