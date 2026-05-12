# MobileCode 预览系统技术方案

## 1. HTML 网页效果预览

### 方案对比

| 方案 | 实现难度 | 效果 | 热重载 | 推荐 |
|------|---------|------|--------|------|
| WebView 内嵌 | 低 | 中 | ✅ 自动 | ★★★★★ |
| 本地 HTTP 服务器 | 中 | 高 | ✅ 手动刷新 | ★★★★☆ |
| 外部浏览器打开 | 低 | 高 | ❌ 需切回 | ★★★☆☆ |

### 推荐方案：WebView 内嵌 + 本地服务器

```
用户编辑 HTML/CSS/JS
  ↓
自动保存触发
  ↓
启动本地 HTTP 服务器 (127.0.0.1:8080)
  ↓
WebView 加载 http://localhost:8080
  ↓
文件变更 → WebView 自动刷新
  ↓
用户实时看到效果
```

**技术栈：**
- `webview_flutter` — 内嵌浏览器
- `shelf` 或 `http_server` — 本地 HTTP 服务器
- `file_watcher` — 文件变更监听
- 支持热重载（文件保存后自动刷新 WebView）

---

## 2. App 效果预览

### 方案对比

| 方案 | 实现难度 | 效果 | 速度 | 推荐 |
|------|---------|------|------|------|
| Flutter Web 预览 | 低 | 接近原生 | 快 | ★★★★★ 先做 |
| Termux 构建 APK | 中 | 真机效果 | 慢(2-5分钟) | ★★★★☆ |
| 内置 Mini 渲染器 | 高 | 原生效果 | 快 | ★★★☆☆ 远期 |
| 远程仿真器 | 高 | 真机效果 | 依赖网络 | ★★☆☆☆ |

### 推荐方案：Flutter Web 预览 + Termux 构建

**阶段1：Web 预览（即时反馈）**
```
用户编辑 Dart 代码
  ↓
flutter build web --release
  ↓
WebView 加载 build/web/index.html
  ↓
看到接近原生的 UI 效果
  ↓
（不依赖 Android 仿真器，最快）
```

**阶段2：Termux 构建真机 APK**
```
用户代码完成 → 点击"构建 APK"
  ↓
MobileCode 调用 Termux
  ↓
Termux 执行: flutter build apk --release
  ↓
构建完成 → 自动安装
  ↓
真机运行查看效果
```

**Termux 权限说明：**
| 权限 | 是否可获得 | 说明 |
|------|-----------|------|
| 文件系统 | ✅ 完整 | 读写 /sdcard/ 和内部存储 |
| 网络 | ✅ 完整 | 完整网络访问 |
| 进程管理 | ✅ 完整 | 可运行子进程 |
| Java 环境 | ✅ 通过 proot | `pkg install openjdk-17` |
| Android SDK | ✅ 通过 proot | 手动安装或脚本安装 |
| Root | ❌ 不可获得 | 需要手机 Root |
| GPU 加速 | ⚠️ 有限 | 部分设备支持 |

---

## 3. Termux 集成深度方案

### MobileCode ↔ Termux 通信

```dart
/// Termux API 通信
/// 
/// 方式1: Intent 调用 (推荐)
///   am startservice -n com.termux/.app.TermuxService
///   am broadcast -a com.termux.app.ACTION_EXECUTE -e cmd "flutter build apk"
///
/// 方式2: Shared Storage
///   MobileCode 写命令到 /sdcard/.mobilecode/termux_cmd.sh
///   Termux 定时读取执行
///
/// 方式3: Termux:API 插件
///   termux-api 提供标准化接口
///
/// 方式4: Socket 通信 (最稳定)
///   MobileCode 启动 Socket 服务器
///   Termux 内的脚本连接 Socket
```

### 实现架构

```
MobileCode (主App)
  ├── 代码编辑器 ← 用户写代码
  ├── WebView 预览 ← HTML/Web 项目即时预览
  ├── Termux 控制器 ← 通过 Socket/Intent 控制 Termux
  │     ├── 发送命令: "flutter build apk"
  │     ├── 实时接收输出
  │     ├── 文件同步 (双向 SFTP)
  │     └── 构建结果获取 (APK 文件)
  └── 安装器 ← 安装构建好的 APK

Termux (辅助App)
  ├── Flutter SDK (通过 proot-distro 安装)
  ├── Android SDK (通过 proot-distro 安装)
  ├── Java (OpenJDK)
  ├── Python/Node 等运行时
  ├── 构建脚本 (自动化构建流程)
  └── Socket 客户端 (与 MobileCode 通信)
```

---

## 4. 完整的预览系统架构

```
┌─────────────────────────────────────────────┐
│         MobileCode 预览系统                  │
├─────────────────────────────────────────────┤
│                                              │
│  📄 HTML/CSS/JS 项目                         │
│     └── 🌐 WebView 预览 (即时)              │
│         ├── 本地 HTTP 服务器                 │
│         ├── 文件监听 + 热重载               │
│         └── 设备模拟 (手机/平板/桌面)       │
│                                              │
│  🎯 Flutter 项目                             │
│     ├── 🌐 Web 预览 (即时, 接近原生)        │
│     │   └── flutter build web              │
│     │                                      │
│     └── 📱 真机预览 (通过 Termux)           │
│         ├── flutter build apk              │
│         ├── 自动安装 APK                    │
│         └── 真机运行                       │
│                                              │
│  🐍 Python 项目                              │
│     └── 🖥️ 终端输出预览                     │
│                                              │
│  🌐 React/Vue 项目                           │
│     └── 🌐 WebView 预览                     │
│         └── npm run dev (通过 Termux)       │
│                                              │
└─────────────────────────────────────────────┘
```

---

## 5. 关键实现文件

需要新增:
1. `preview_service.dart` — 预览核心服务
2. `webview_preview_widget.dart` — WebView 预览组件
3. `http_preview_server.dart` — 本地 HTTP 服务器
4. `termux_integration_service.dart` — Termux 集成
5. `build_orchestrator.dart` — 构建编排器
6. `preview_screen.dart` — 预览界面
