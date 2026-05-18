# MobileCode Principle Video Script

This script matches `docs/assets/mobilecode-principle-remotion.mp4`. The video is rendered with Remotion and hosted by the HTML player at `docs/mobilecode-principle-video.html`.

## Voiceover

### 1. Why MobileCode Exists

AI coding is moving to the phone, but a phone should not pretend to be a desktop workstation. MobileCode is built as a phone-native coding harness: the model can be remote, but the loop, files, preview, runtime state, and publishing controls stay close to the user.

Subtitle: MobileCode 不是云端 IDE 外壳，而是把 AI coding harness 真正放到手机上。

### 2. The Pain

Mobile coding breaks when execution is unclear. Users should not need to guess whether an action belongs to the app, Termux, a cloud shell, GitHub, or a hidden preview. The real problem is not just screen size; it is an undefined execution layer.

Subtitle: 手机写代码的核心痛点不是屏幕小，而是执行层不清楚、失败不可恢复。

### 3. The Answer

MobileCode keeps the harness on the phone and moves heavy work outward. The app owns chat state, tool trace, local files, WebView preview, runtime diagnostics, repo context, and final result cards. Heavy builds can run through external runtimes or GitHub.

Subtitle: 手机保留对话、文件、预览、诊断和发布控制，把重构建交给外部平台。

### 4. Runtime Principle

RuntimeProvider turns execution into a replaceable contract. The UI should not care whether work runs through MobileCode Helper, external Termux, WebViewOnly, Embedded Lite, or Cloud Runtime. Interface first, backend second.

Subtitle: RuntimeProvider 让 Helper、Termux、WebViewOnly、Cloud 都成为可替换后端。

### 5. GitHub-First Loop

The phone edits and explains. GitHub stores, builds, and ships. Repo Hub, Contents API commits, Pages publishing, Actions runs, and release artifacts keep MobileCode lightweight but real.

Subtitle: GitHub 负责仓库、Pages、Actions 和产物，MobileCode 负责手机端闭环体验。

### 6. Outcome

A phone can become the AI coding control room. Not because it compiles everything locally, but because it keeps the user-facing harness, state, explanations, previews, and shipping decisions close to the user.

Subtitle: 最终目标：在手机上生成、预览、解释、发布，而不是伪装成桌面环境。
