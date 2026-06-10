# MobileHarnessBench Mobile Test Strategy

MobileHarnessBench 必须符合 mobile harness 的真实使用条件。离线 fixture 只能证明数据和 verifier 协议有效，不能替代真实移动环境测试。

## 测试分层

| Tier | 环境 | 用途 | 能证明什么 | 不能证明什么 |
| --- | --- | --- | --- | --- |
| T0 | Offline fixture runner | 快速校验 task schema、fixture、verifier contract、report export | 数据结构、离线 verifier、公开报告安全 | 分享入口、真实 WebView、权限、设备状态 |
| T1 | Android emulator | 回归 UI、WebView、文件选择、基础 preview | Android 可重复自动化、截图、logcat | 真实分享入口、低内存、厂商系统差异 |
| T2 | Android real device | 主 mobile benchmark 环境 | 微信/系统分享、Open with、真实 WebView、后台恢复、低内存、网络变化 | iOS 行为 |
| T3 | iOS simulator on Mac | iOS 回归和 Flutter/iOS WebView smoke | iOS 布局、Document Picker、WebView、Xcode logs | 真实 iPhone 分享链路、文件关联、后台限制、系统权限细节 |
| T4 | iOS real device | iOS 真实性能和入口验证 | Open In、Files app、真实 WebView、后台恢复、权限 | 大规模自动化成本较高 |
| T5 | GitHub authorized sandbox | GitHub delivery 类任务 | commit SHA、Pages、Actions、artifact metadata | 未授权或私有账号行为 |

## 是否必须上真实手机

必须。原因：

- MobileCode 的核心价值是 phone-native harness，不是桌面脚本。
- `file_intake` 依赖真实系统分享、文件入口和 Open with 行为。
- `preview_verification` 依赖真实 WebView、viewport、字体缩放和触控返回。
- `runtime_orchestration` 依赖真实 RuntimeProvider 状态、后台恢复、低内存和 stop task。
- `github_delivery` 需要真实网络和授权边界，但只能在 sandbox repo 中测。

T0/T1 可以做日常回归；论文实验不能只用 T0/T1。

## 是否需要 Mac 上的 iOS 模拟器

需要，但它不是最终证明。

iOS simulator 适合：

- Flutter iOS smoke。
- iOS WebView preview。
- Document Picker 和 Files app 基础流。
- 截图、Xcode log、快速回归。

iOS simulator 不能替代：

- 真实 iPhone 的 Open In / 分享链路。
- 真实后台、权限、低内存和蜂窝网络。
- 与微信等外部 App 的真实交互。

结论：Mac iOS simulator 应作为 T3 必备回归层；iOS real device 作为 T4 论文证据层。

## 可选外部工具参考：simutil

[simutil](https://github.com/dungngminh/simutil) 可以作为 MobileHarnessBench 的模拟器启动参考工具。它不是 MobileCode 的内置依赖，也不是 benchmark verifier，但它适合放在测试工具链参考中。

适合参考的点：

- 终端 TUI 管理 iOS Simulator、Android Emulator 和已连接设备。
- 快速启动不同 Android/iOS 模拟器，减少从 IDE 中手动切换设备的成本。
- Android emulator 支持 normal、cold boot、no audio 等启动模式。
- Android 真机无线连接和配对流程可以作为 T2 real-device 测试准备流程的参考。
- Dart + Nocterm 的 TUI 实现路径适合 Flutter/mobile 开发者理解和二次扩展。

不应混淆的边界：

- simutil 只负责设备启动和连接，不负责 MobileHarnessBench 的任务执行、verifier、trace、summary 或论文计数。
- 使用 simutil 启动的模拟器仍然必须产出 `run.json`、`summary.md`、`traces.jsonl` 和 `device-metadata.json`。
- iOS simulator 即使由 simutil 启动，也仍属于 T3 回归层，不能替代 T4 iOS real device。
- Android emulator 即使由 simutil 启动，也仍属于 T1 回归层，不能替代 T2 Android real device。

## Benchmark 计数规则

- Candidate task：只代表任务定义存在。
- Offline-verified task：有 T0 verifier result、trace 和 summary。
- Emulator-verified task：有 T1/T3 截图或日志证据。
- Device-verified task：有 T2/T4 真实设备证据。
- Paper-counted task：必须来自 frozen subset，并且至少有 verifier result、trace、summary 和对应 tier 证据。

论文实验表不能把 1000 条 candidate tasks 当作 1000 条实验结果。

## 推荐执行顺序

1. `representative-v0`：保持 T0 离线 dry run 作为 smoke。
2. `smoke-v2`：从 v2 每类抽 10 条，先跑 T0。
3. `android-device-v2`：从 smoke 中抽每类 5 条，跑 T2。
4. `ios-simulator-v2`：从 smoke 中抽每类 3 条，跑 T3。
5. `github-sandbox-v2`：只测 GitHub delivery 类，使用公开 sandbox repo。
6. `frozen-paper-subset`：冻结可复现实验子集，记录版本、设备、证据和失败样例。

## 证据格式

每个 mobile run 至少输出：

```text
runs/<date>-<tier>-<run-id>/
├─ run.json
├─ summary.md
├─ traces.jsonl
├─ screenshots/
├─ device-metadata.json
└─ logs/
```

`device-metadata.json` 必须包含：

- platform：android / ios。
- environment：emulator / simulator / real_device。
- device model。
- OS version。
- app version。
- viewport。
- network profile。
- input surface。
- evidence capture method。

## 当前结论

- T0 已有：`representative-v0` 离线 dry run 和 `smoke-v2` 60-task dry run。
- v2 已有：1000 条 candidate tasks 和 mobile profile/test oracle 字段。
- Mobile-tier readiness probe 已有：`reports/mobile-tier-readiness.md`。
- 当前本机 readiness：Android blocked by `adb_missing`，iOS blocked by `xcrun_missing`。
- 下一步：在具备 Android SDK/真实 Android 设备或 Mac/Xcode 的环境中运行 T2/T3，产出 `device-metadata.json`、截图/log 和 task-specific verifier results。
