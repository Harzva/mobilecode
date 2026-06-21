# Mobile Agent iOS 部署指南

> 本指南记录了将 Mobile Agent  Flutter 项目编译并安装到 iOS 真机的完整流程，包含环境准备、常见问题及解决方案。

---

## 环境要求

- **macOS**（必需，iOS 开发只能在 Mac 上进行）
- **Xcode**（建议最新稳定版，本文使用 Xcode 26.5）
- **Flutter**（3.29.0+，本文使用 3.44.0）
- **CocoaPods**（`sudo gem install cocoapods` 或 `brew install cocoapods`）
- **一台 iPhone**（iOS 13.0+）
- **Apple ID**（免费个人开发者账号即可）

---

## 步骤一：创建 iOS 项目

如果项目中没有 `ios/` 目录，需要先创建：

```bash
cd mobile_agent
flutter create --platforms=ios .
```

> **注意**：本项目使用了 `flutter_secure_storage` 插件，该插件暂不支持 Swift Package Manager。建议先禁用 SPM 再创建项目：
> ```bash
> flutter config --no-enable-swift-package-manager
> rm -rf ios
> flutter create --platforms=ios .
> ```

---

## 步骤二：配置 iOS 权限

由于项目使用了语音输入（`speech_to_text`）和 WebView，需要在 `ios/Runner/Info.plist` 中添加以下权限声明：

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for speech-to-text functionality.</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>This app needs speech recognition access to convert your voice to text.</string>
```

---

## 步骤三：配置代码签名

### 3.1 在 Xcode 中登录 Apple ID

1. 打开 Xcode → **Settings (⌘,)** → **Accounts**
2. 点击左下角 **+** → 选择 **Apple ID** → 登录你的 Apple ID

### 3.2 选择开发团队

1. 在 Xcode 左侧导航栏点击 **Runner**（蓝色图标）
2. 中间区域选择 **TARGETS > Runner**
3. 点击 **Signing & Capabilities** 标签
4. 在 **Team** 下拉框中选择 **"你的姓名 (Personal Team)"**
5. 修改 **Bundle Identifier**（建议把默认的 `com.example.mobileAgent` 改为 `com.mobilecode.agent` 等非 example 前缀）

---

## 步骤四：开启 iPhone 开发者模式

**iOS 16+ 必须开启开发者模式才能安装开发版 App。**

1. iPhone 上打开 **设置 → 隐私与安全性**
2. 滑到最底部，点击 **开发者模式**
3. 打开开关 → 点击 **重新启动**
4. **重启后开机界面会弹出一个确认框**，点击 **"打开"（Turn On）**
5. 输入锁屏密码确认

> ⚠️ **关键**：必须在重启后的弹窗中二次确认，否则开发者模式不会真正生效。

---

## 步骤五：连接设备并信任

1. 用数据线将 iPhone 连接到 Mac
2. iPhone 上点击 **"信任此电脑"**，输入锁屏密码
3. 确保 iPhone **处于解锁状态**

---

## 步骤六：编译并安装

### 方式 A：命令行一键安装（推荐）

```bash
flutter run --release
```

Flutter 会自动：编译 → 签名 → 安装 → 启动 App。

### 方式 B：通过 Xcode 安装

1. Xcode 顶部工具栏确认已选择你的 iPhone 设备
2. 点击 **▶️ Run 按钮**（或按 Cmd+R）
3. 等待编译完成，App 会自动安装并启动

---

## 步骤七：信任开发者证书

首次打开 App 时，系统会提示 **"不受信任的开发者"**：

1. 点击 **取消**
2. 打开 iPhone **设置 → 通用 → VPN与设备管理**（或"描述文件与设备管理"）
3. 找到你的 **Apple ID**，点击进入
4. 点击 **信任"你的 Apple ID"** → 再次确认 **信任**
5. 返回桌面，重新点击 App 图标即可正常使用

---

## 常见问题排查

### Q1: Flutter 提示 "iOS 26.5 Platform Not Installed"

**原因**：Xcode 缺少 iOS 平台运行时。  
**解决**：
```bash
xcodebuild -downloadPlatform iOS
```

### Q2: Flutter 提示 "enable Developer Mode"

**原因**：iPhone 开发者模式未开启或未确认。  
**解决**：严格按照"步骤四"操作，确保重启后点击弹窗确认。

### Q3: Flutter 提示 "No valid code signing certificates"

**原因**：Xcode 项目中未选择 Team。  
**解决**：在 Xcode → Runner → Signing & Capabilities → Team 中选择 Personal Team。

### Q4: 安装成功但打开 App 白屏/闪退

**原因**：`flutter_secure_storage` 插件与 Swift Package Manager 冲突，导致构建产物损坏。  
**解决**：
```bash
flutter config --no-enable-swift-package-manager
rm -rf ios
flutter create --platforms=ios .
```
然后重新配置签名并编译。

### Q5: Xcode 报错 "Missing package product 'FlutterGeneratedPluginSwiftPackage'"

**原因**：Swift Package Manager 与部分插件不兼容。  
**解决**：同 Q4，禁用 SPM 后重新生成 iOS 项目。

---

## 免费开发者账号限制

- App 安装后 **7 天有效**，到期后需要重新连接 Mac 编译安装
- 同一时间最多安装 3 个使用个人证书签名的 App
- 无法发布到 App Store（需要付费 Developer Program，¥688/年）

---

## 参考

- [Flutter iOS 部署官方文档](https://docs.flutter.dev/deployment/ios)
- [Apple Developer - Distributing Your App](https://developer.apple.com/documentation/xcode/distributing-your-app)
