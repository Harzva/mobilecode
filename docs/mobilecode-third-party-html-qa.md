# MobileCode Third-Party HTML Open QA

目标：验证 Android 文件管理器、Chrome 下载页、微信/聊天工具打开或分享 `.html` 到 MobileCode 的真实行为，并保存截图、UI XML、logcat 和通过/失败结论。

Last updated: 2026-06-20 UTC

## 范围

本 QA 覆盖：

- `.html` 文件没有 MIME 或 MIME 不可靠时，Android 是否能把它交给 MobileCode。
- 第三方 App 通过 `ACTION_VIEW`、系统分享、`EXTRA_TEXT` 或 content URI 进入 MobileCode。
- 读取失败时是否能显示明确错误。
- Chrome 下载页和微信/聊天工具是否存在 App 自己接管文件的限制。

本 QA 不覆盖：

- Provider 模型调用质量。
- WebView 页面视觉设计评审。
- APK release signing。

## 准备

需要一台真实 Android 手机，或一台已安装目标第三方 App 的 emulator。

必需 App：

- MobileCode 最新 APK。
- Android Files / DocumentsUI。
- Chrome。
- 微信或目标聊天工具，且已登录，可以把文件发送给自己或文件传输助手。

连接设备：

```bash
adb devices -l
```

初始化证据目录并下发样例 HTML：

```bash
QA_DIR=mobile_agent/qa-output/html-open-real-device-$(date +%Y%m%d-%H%M%S) \
  scripts/qa_mobilecode_html_real_device.sh init
```

如果有多台设备：

```bash
ANDROID_SERIAL=<device-serial> QA_DIR=<same-dir> \
  scripts/qa_mobilecode_html_real_device.sh init
```

样例文件会写入手机：

```text
/sdcard/Download/mobilecode-real-device-html-open.html
```

每做完一个手动步骤，采集证据：

```bash
QA_DIR=<same-dir> scripts/qa_mobilecode_html_real_device.sh capture 01-label
```

## 判定标准

通过：

- 系统或第三方 App 明确出现 MobileCode 入口，或已打开 MobileCode。
- MobileCode 显示 `HTML Preview` 或等价预览界面。
- 页面中可以看到 marker：`mobilecode-real-device-html-open`，或 UI XML / logcat 能证明该 HTML 已进入 MobileCode。

未通过：

- 第三方 App 自己打开 HTML，且没有提供 MobileCode 分享/打开入口。
- Android resolver 不出现 MobileCode。
- MobileCode 打开但显示读取失败，且错误不明确。
- 只能通过 ADB 人工构造 intent 成功，无法通过真实第三方 App 操作成功。

限制：

- Chrome 下载列表 direct tap 和 Chrome share 要分开记录。Chrome 自己打开下载内容不等于 MobileCode 失败，但不能宣传为 direct-tap 支持。
- 微信 QA 必须使用真实微信或已登录微信环境。未安装、未登录或只用 ADB 模拟 intent，都不能算通过。

## 测试路径

### 1. Android Files / DocumentsUI

步骤：

1. 打开 Android Files。
2. 进入 Downloads。
3. 点击 `mobilecode-real-device-html-open.html`。
4. 如果出现 resolver，选择 MobileCode。
5. 在 MobileCode 中确认 HTML 预览出现。

采集：

```bash
QA_DIR=<same-dir> scripts/qa_mobilecode_html_real_device.sh capture 01-files-downloads
QA_DIR=<same-dir> scripts/qa_mobilecode_html_real_device.sh capture 02-files-resolver
QA_DIR=<same-dir> scripts/qa_mobilecode_html_real_device.sh capture 03-files-mobilecode-preview
```

通过证据：

- `02-files-resolver.png` 显示 MobileCode。
- `03-files-mobilecode-preview.png` 显示 MobileCode 预览。

### 2. Chrome 下载页 Direct Tap

步骤：

1. 用 Chrome 下载同一个 HTML 文件，或打开本地/Pages 上的测试 HTML 下载链接。
2. 打开 Chrome Downloads。
3. 直接点击下载项。
4. 观察是否出现 MobileCode 或 Android resolver。

采集：

```bash
QA_DIR=<same-dir> scripts/qa_mobilecode_html_real_device.sh capture 04-chrome-downloads
QA_DIR=<same-dir> scripts/qa_mobilecode_html_real_device.sh capture 05-chrome-direct-tap-result
```

通过证据：

- `05-chrome-direct-tap-result.png` 显示 MobileCode 或 resolver。

未通过但可接受的记录：

- Chrome 自己打开 `content://media/...` 或内置 WebView 页面。
- 记录为 Chrome direct-tap limitation，不要宣传为 MobileCode direct-tap 通过。

### 3. Chrome 分享替代路径

步骤：

1. 在 Chrome 打开的下载 HTML 页面点击 Share。
2. 选择 MobileCode。
3. 确认 MobileCode 能接收并预览 HTML 或 HTML 文本。

采集：

```bash
QA_DIR=<same-dir> scripts/qa_mobilecode_html_real_device.sh capture 06-chrome-share-sheet
QA_DIR=<same-dir> scripts/qa_mobilecode_html_real_device.sh capture 07-chrome-share-mobilecode-preview
```

通过证据：

- share sheet 中出现 MobileCode。
- MobileCode 预览页面或 HTML 分享预览出现。

### 4. 微信 / 聊天工具文件打开

步骤：

1. 把 `mobilecode-real-device-html-open.html` 发送到微信文件传输助手或一个测试聊天。
2. 在微信中点击该文件。
3. 如果微信提供“用其他应用打开”或系统分享入口，选择 MobileCode。
4. 确认 MobileCode 能预览 HTML。

采集：

```bash
QA_DIR=<same-dir> scripts/qa_mobilecode_html_real_device.sh capture 08-wechat-file-message
QA_DIR=<same-dir> scripts/qa_mobilecode_html_real_device.sh capture 09-wechat-open-with
QA_DIR=<same-dir> scripts/qa_mobilecode_html_real_device.sh capture 10-wechat-mobilecode-preview
```

通过证据：

- 微信文件消息可见。
- 微信或系统 open-with/share UI 出现 MobileCode。
- MobileCode 预览 HTML。

未通过记录：

- 微信只内置预览 HTML，未提供 MobileCode。
- 微信要求登录、文件安全检查、权限授权或下载原文件。
- 设备未安装微信或未登录。

### 5. 微信 / 聊天工具 HTML 文本分享

步骤：

1. 在微信中发送或复制一段 HTML 文本。
2. 使用系统分享或转发入口选择 MobileCode。
3. 确认 MobileCode 以 `EXTRA_TEXT` 路径接收并预览 HTML。

采集：

```bash
QA_DIR=<same-dir> scripts/qa_mobilecode_html_real_device.sh capture 11-wechat-html-text-share
QA_DIR=<same-dir> scripts/qa_mobilecode_html_real_device.sh capture 12-wechat-extra-text-preview
```

通过证据：

- MobileCode 显示 HTML 分享预览。
- UI XML 或日志可见 HTML text/share 入口。

## 输出要求

每次真实设备 QA 完成后，在 QA 目录写一个 `summary.md`：

```markdown
# MobileCode HTML Third-Party QA

Date:
Device:
APK SHA256:

| Entry | Result | Evidence |
| --- | --- | --- |
| Files / DocumentsUI | Passed/Failed | screenshot path |
| Chrome direct tap | Passed/Failed/Limitation | screenshot path |
| Chrome share | Passed/Failed | screenshot path |
| WeChat file | Passed/Failed/Blocked | screenshot path |
| WeChat EXTRA_TEXT | Passed/Failed/Blocked | screenshot path |

## Notes

- ...
```

只在真实第三方 App 证据齐全时，才把对应项从 release QA 的未完成列表移到通过列表。
