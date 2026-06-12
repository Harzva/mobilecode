# Termux 参考映射（MobileCode）

## 参考仓与提交
- termux-app：`401bbe54b8f4e68302b1ff70678015a24628fb1d`（`401bbe5`），提交时间 `2026-06-05 04:15:42 +0500`
- ZeroTermux：`be1fd3b987866a1238e40dd2fa5b39389ca24e83`（`be1fd3b`），提交时间 `2026-06-07 22:10:28 +0800`
- Termux-X：`ca88eb735143a1ecbb4cacb7ccaaed90ca2fc530`（`ca88eb7`），提交时间 `2026-06-08 18:27:26 +0800`

## termux-app
### runtime
- 生命周期核心仍是 `TermuxApplication -> TermuxService`。`TermuxApplication` 负责全局初始化（崩溃处理、日志、共享配置、shell 环境、`TermuxAmSocketServer`）。
- `TermuxService` 采用前台服务托管 session 与 command，保证会话可在 Activity 生命周期外存活。
- 额外命令入口 `RunCommandService` 负责解析 `RUN_COMMAND` intent 并转发给 `TermuxService` 执行。
- 启动资产使用 JNI `TermuxInstaller.getZip()` 直接返回内嵌 bootstrap zip，外部启动包通过 gradle 下载校验。

### interaction entry
- 主入口：`app.TermuxActivity`（含 `MAIN/LAUNCHER` 与 `LEANBACK_LAUNCHER`）。
- 辅助入口：`HomeActivity` alias（IOT launcher）、文件接收 `FileReceiverActivity`（`SEND/VIEW` alias）。
- 内部桥接：`TermuxDocumentsProvider` 与 `TermuxOpenReceiver$ContentProvider`。
- 可观察策略：设置、帮助、报告页分离，不与终端主流程绑死。

### permissions / packaging
- 权限偏向终端运行时：网络、存储（含兼容旧路径策略）、前台服务、电量优化豁免、`READ_LOGS/DUMP/WRITE_SECURE_SETTINGS` 等。
- 关键构建点：
  - `packageVariant` + `TERMUX_PACKAGE_VARIANT`。
  - `downloadBootstraps()` 按 ABI 拉取 bootstrap，带 SHA-256 校验后入 `src/main/cpp`。
  - `split abi` 可按 debug/release 配置；`validateVersionName()` 强制 semver。
  - ndkBuild + legacy native libs packaging。

### reusable ideas
- 可复用：
  - `Application -> Service -> API intent` 的分层运行时模型，便于保持前台任务 + 低内聚 UI。
  - 文件接入策略（文件 provider + share/view intent alias）。
  - bootstrap 按 ABI 下载与校验机制（用于外部运行时资源管理）。

### do-not-copy points
- 不应完整迁移：终端/会话语义与 `Termux` 生态运行模型（对系统权限与安全假设差异大）。
- 不建议直接复制 `sharedUserId` 方案。
- 不应内置 `READ_LOGS`、`DUMP`、高危系统权限作为默认。

## ZeroTermux
### runtime
- 在 termux-app 基础上叠加大量功能模块（定时、scrcpy、socket/FTP、开发者工具、AI 设置等），`TermuxActivity` 仍是核心 shell 承载。
- 引入 Kotlin/协程、Root、OTG、HTTP 服务器、ADB/webview 扩展，明显偏“功能壳 + 终端内核”。

### interaction entry
- 入口不再单一：部分分支将 `TermuxGuideActivity` 作为 Launcher，原主 terminal activity 的 launcher intent 可见被移除/注释化。
- 设置类入口大幅增加（多类 Activity 和定制工具页），与核心终端交互更重 UI 承载。
- 文件接收/查看链路与官方大体一致（多图像选择器/接收 activity 替代）。

### permissions / packaging
- `minSdk` 与官方提升到 23。
- 额外权限显著增多：`POST_NOTIFICATIONS`、`READ_SMS`、`READ_CONTACTS`、`REQUEST_DELETE_PACKAGES` 等。
- 构建引入大量第三方 aar/jar、本地库、签名配置外置环境变量，签名文件指向 `phone.jks`（应避免敏感信息落盘）。
- ABI split 与 `minify` 仍保留；同时加入 `dataBinding/buildConfig` 与 compose 的兼容性改动。

### reusable ideas
- 可复用：
  - 多 activity / task 聚合前端（功能页与终端分层）。
  - 将扩展点做成独立服务模块，按需启停（如 scrcpy/FTP/socket）。
- 可借鉴但需审查：权限分层策略和运行时策略参数化。

### do-not-copy points
- 不建议直接吸收：AI/短信/联系人/安装卸载/联系人扫描相关能力，超出 MobileCode 当前边界。
- 不建议照搬：过重的第三方依赖树（尤其未治理的本地 AAR/JAR）与高权限默认策略。

## Termux-X
### runtime
- 与 ZeroTermux 非常接近，保留主服务链路（`TermuxService` + `RunCommandService`），并加入 scrcpy、socket、FTP、tile/service 模块。
- 增加更多 UI 依赖（Compose 相关）与兼容性组件，偏“多能力入口叠加”的包装。

### interaction entry
- `TermuxActivity` 仍是 launcher。
- 文件系统可扩展入口更多（`ImagePicker` 系列、`FileProvider` authority `${applicationId}.provider`）。
- 保留通用报表/分享/文件查看入口。

### permissions / packaging
- 同样将 `minSdk` 提升到 23；`ndkVersion` 指向 22.1.7171670（可观测兼容偏好变化）。
- 在构建中混入 Compose 生态（activity-compose/nav-compose/material3）与加密、网络、工具链相关依赖。
- ABI 仅启用 `arm64-v8a` universalApk false，明显是产物策略偏定制化渠道。

### reusable ideas
- 可复用：
  - 统一入口 + 扩展服务插件化思路可作为 MobileCode 的“能力扩展模板”。
  - ContentProvider 与外部文件路径分享链路兼容多文件类型。
- 可借鉴：依赖升级与 compose 逐步迁移节奏可供版本策略参考。

### do-not-copy points
- 不建议复制：将多个实验性功能压进同一 APK 的“胖应用”策略。
- 不建议沿用：单一仓库里混入过度权限和高度耦合的外部能力（FTP/ADB/scrcpy 全量集成）。

## MobileCode 决策总结
- 吸收：
  - 采用 termux-app 的三层运行时骨架（Application/Service/RunCommand intent）。
  - 借鉴 provider + file receiver 的文件交互约定。
  - 借鉴 bootstrap 按 ABI 下载与校验流程用于可外部化运行资源。
- 外部保留（不内嵌）：
  - ZeroTermux/Termux-X 的高级功能套件（AI、scrcpy、FTP、联系人/短信相关能力、复杂 root/OTG 工具链）。
  - 历史敏感权限的“开箱即用”集合。
- 延后：
  - 是否引入 Compose 与大规模本地 AAR/JAR 生态。
  - 对 `${TERMUX_PACKAGE_NAME}` 体系权限模型的完全兼容。
  - 对外暴露 `RUN_COMMAND` 的完整安全协议（先做最小受控 API）。
