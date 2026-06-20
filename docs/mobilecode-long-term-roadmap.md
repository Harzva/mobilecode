# MobileCode 长期路线图

目标：把 MobileCode 从手机端 AI 编码 App 推进为多工作区、多运行时、多预览、多证据账本的安全移动编码容器系统，并保留 Mobile Harness 论文与产品化双线能力。

Last updated: 2026-06-19 PDT

## 使用规则

- `[x]` 只代表已有代码、文档、命令、截图、CI、发布记录或用户验收能证明完成。
- `[ ]` 代表未完成、未验证、被阻塞、暂缓或仍需用户输入。
- 主路线图记录方向、阶段、验收标准和关键决策；执行细节可以拆到专项文档。
- 每个用户可见能力都要有至少一种证据：测试、截图、模拟器记录、真机记录、CI artifact、release asset 或 verifier report。
- 不把计划中的能力写成已完成；不把本地 ADB 成功等同于真实第三方 App QA。

## 安全规则

- 正式发布 APK 默认不内置大模型权重；本地模型必须由用户显式下载或导入。
- 不把 provider key、GitHub token、cookie、`.env`、访问文件、本地私密路径或原始聊天日志写入公开文档、截图、manifest、release notes 或提交。
- MobileCode 的工具执行必须经过 RuntimeProvider、ActionEvidence、权限检查、路径限制和预览/验证边界。
- 自动路由不能伪造 provider 支持的模型名。Provider 端不支持 `model=auto` 时，MobileCode 应保存路由元数据，并向 provider 发送真实模型名。
- 任何“可发布”“已完成”“已跑通”声明必须有对应证据。

## 当前基线

- 当前工作树：`MobileCode-main-dev`。
- 产品主线：Flutter Android/iOS App，核心体验是手机端聊天、Agent、文件生成、WebView 预览、Runtime providers、GitHub/CI/Pages 辅助能力。
- Harness 主线：`docs/mobile-harness-roadmp/roadmp-mobile-harness.md` 是论文和 benchmark 专项路线图，本文件是 MobileCode 产品与架构总控路线图。
- 已有发布/QA 基线：`docs/mobilecode-release-qa.md` 记录 release CI gates、Android smoke、runtime CI 和历史 release evidence。
- 本地模型策略基线：`docs/mobilecode-local-model-distribution.md` 规定 release APK 不内置模型权重，使用远程 manifest 和用户显式安装。
- 生产硬化基线：`docs/mobilecode-production-hardening.md` 记录 provider 配置、WebView preview、Termux/Runtime 边界、日志与发布检查。

## Key Decisions

- [x] MobileCode 的长期形态不是“手机上复刻桌面 IDE”，而是移动端 AI coding harness/control plane。
  - Evidence: `docs/mobile-harness-roadmp/roadmp-mobile-harness.md` 记录 Mobile Harness 定位。
- [x] 正式发布默认不内置大模型权重，本地模型通过用户显式下载或导入启用。
  - Evidence: `docs/mobilecode-local-model-distribution.md` 与 `docs/mobilecode-production-hardening.md`。
- [x] Provider preset 作为一键配置层：保存 Base URL、model、UI label、识别逻辑和路由元数据，不直接保存用户 key。
  - Evidence: `mobile_agent/lib/services/model_provider_preset_service.dart`。
- [x] TierFlow Auto 采用 provider-side `model=auto`。
  - Evidence: 2026-06-19 `flutter test test/services/model_provider_preset_service_test.dart` passed；模拟器截图 `mobile_agent/qa-output/tierflow-deepseek-auto-20260619-201639/12-model-sheet-scroll-fixed.png`。
- [x] DeepSeek Auto 采用 MobileCode-side Flash/Pro 路由元数据，默认请求模型为 `deepseek-v4-flash`，候选包含 `deepseek-v4-pro`。
  - Evidence: 2026-06-19 `flutter test test/services/model_provider_preset_service_test.dart` passed；模拟器截图 `mobile_agent/qa-output/tierflow-deepseek-auto-20260619-201639/13-final-deepseek-auto-state-scroll-fixed.png`。
- [ ] DeepSeek Auto 的真实任务路由器尚未完成。当前完成的是 UI、配置、持久化和路由元数据。
- [ ] TierFlow Auto 的真实端到端 provider 调用成功率、费用、失败回退和 token 账本尚未形成 release evidence。
- [ ] 本地模型下载、校验、加载和删除流程尚未接入 App。

## 总体验收标准

- [ ] App 支持稳定的多工作区：每个项目有独立文件、预览、运行记录、证据账本和导出入口。
- [ ] App 支持多运行时：WebView-only、MobileCode Helper、Termux fallback、Cloud/CI provider、本地模型 provider。
- [ ] App 支持多预览：HTML、Markdown、图片、日志、GitHub Pages、runtime report，并能记录打开失败原因。
- [ ] App 支持多 provider preset：Mimo、DeepSeek、DeepSeek Auto、TierFlow Auto、OpenAI、Anthropic、Custom，并有测试覆盖。
- [ ] App 支持证据账本：每次模型调用、文件写入、预览、发布、CI、截图、错误恢复都能记录为可导出的 evidence。
- [ ] Android 发布链路稳定：debug/release build、emulator smoke、runtime CI、HTML open-with QA、GitHub release asset。
- [ ] iOS 发布链路有可验证路径：simulator smoke、unsigned archive、签名发布策略、iOS WebView/文件导入边界。
- [ ] 本地模型作为可选能力上线：manifest、下载、checksum、runtime load、内存提示、删除、fallback provider。
- [ ] MobileHarnessBench 与 App 内 Benchmark Lab 打通：任务选择、执行、verifier、trace export、报告导出。
- [ ] 对外展示资产稳定：截图、短视频、README、GitHub Pages、架构图、产品说明不含私密信息。

## Phase 0：当前分支收尾与发布卫生

目标：把当前 Provider Auto 与 HTML open-with 工作收成可提交、可 CI、可 QA 的小闭环。

- [x] DeepSeek Auto / TierFlow Auto 模型弹层在 Android 模拟器中可见。
  - Evidence: `mobile_agent/qa-output/tierflow-deepseek-auto-20260619-201639/12-model-sheet-scroll-fixed.png`。
- [x] DeepSeek Auto 选中后能保持为当前 provider preset，重启后仍保持。
  - Evidence: `mobile_agent/qa-output/tierflow-deepseek-auto-20260619-201639/09-deepseek-auto-persists-after-restart.xml` 与 `13-final-deepseek-auto-state-scroll-fixed.xml`。
- [x] 模型选择弹层底部 overflow 已修复。
  - Evidence: `12-model-sheet-scroll-fixed.png` 不再出现 Flutter overflow 条纹。
- [x] 将 Provider Auto 相关代码拆成单独 commit 并 push。
  - Evidence: 2026-06-19 commit `57eef01` pushed to `origin/main`；docs follow-up commit `ba4e244` pushed separately。
- [x] GitHub CI 完成，Android App Smoke Test 和 Mobile Runtime CI 通过。
  - Evidence: 2026-06-20 UTC Android App Smoke Test run `27859042736` success；Mobile Runtime CI run `27859042737` success。
- [x] 真实第三方 App QA：Android 文件管理器 / DocumentsUI 打开 `.html` 到 MobileCode。
  - Evidence: `mobile_agent/qa-output/html-open-real-app-20260619-204552/01-documentsui-downloads.png`、`02-documentsui-after-file-tap.png`、`03-documentsui-opened-in-mobilecode.png`。
- [ ] 浏览器下载页打开 `.html` 到 MobileCode 仍需产品决策或真实设备复测。
  - Evidence: `mobile_agent/qa-output/html-open-real-app-20260619-204552/10-chrome-download-open-attempt.png` 显示 Chrome 在模拟器中自己打开 `content://media/external/downloads/64`。
- [ ] 微信 / 聊天工具 QA 仍需真实 App 环境。
  - Evidence: 2026-06-19 emulator package list did not include WeChat。
- [ ] 决定哪些 QA 截图进入公开素材目录，哪些只留在本地 `qa-output`。

## Phase 1：Provider Preset 与自动路由

目标：把 provider 选择从“手填配置”升级为可观测、可回退、可控成本的路由层。

- [x] 建立 `ModelProviderPresetService`，把 preset 从 Home UI 中抽出。
  - Evidence: `mobile_agent/lib/services/model_provider_preset_service.dart`。
- [x] 增加 Provider preset 单元测试。
  - Evidence: `mobile_agent/test/services/model_provider_preset_service_test.dart`。
- [ ] 为 DeepSeek Auto 增加真实路由策略：
  - 简单聊天、短改代码、低风险生成默认走 Flash。
  - 长上下文、多文件修改、失败重试、verifier 失败、复杂编码任务升级到 Pro。
  - Pro 失败后记录原因，不静默降级。
- [ ] 为 TierFlow Auto 增加 provider health 与兼容性测试：
  - health check；
  - chat completions；
  - tool call / non-tool-call 兼容；
  - token usage；
  - rate limit 和错误提示。
- [ ] 在证据账本中记录 provider preset、实际 model、路由原因、token、延迟、失败回退。
- [ ] 增加 provider preset UI 防截断策略，窄屏按钮可查看完整名称。

## Phase 2：多工作区安全容器

目标：让每个用户任务进入独立工作区，减少文件污染、预览混乱和证据丢失。

- [ ] 定义 `Workspace` 数据模型：id、title、rootPath、createdAt、updatedAt、providerPreset、runtimeProfile、previewRegistry、evidenceLedger。
- [ ] 每次 Agent 生成 artifact 时自动绑定 workspace。
- [ ] 支持 workspace 列表、搜索、归档、删除、导出。
- [ ] 支持从外部 `.html`、分享文本、GitHub repo、模板图库创建 workspace。
- [ ] 每个 workspace 有独立预览历史、运行历史和发布目标。
- [ ] 增加 workspace 安全边界：禁止跨 workspace 写文件，除非用户显式复制或导入。

## Phase 3：多运行时与任务执行闭环

目标：根据任务需要选择最小可用运行时，避免把所有能力都塞进单一路径。

- [ ] WebView-only runtime：用于 HTML、Markdown、轻量交互 demo。
- [ ] MobileCode Helper runtime：用于受控文件、shell-like task、project preflight、任务日志。
- [ ] Termux fallback runtime：用于 Linux-like 命令、包管理器和重型本地工具。
- [ ] Cloud/CI runtime：用于 Android/iOS build、release signing、长任务和受保护仓库操作。
- [ ] Local model runtime：用于离线聊天、小模型改写、隐私敏感草稿。
- [ ] RuntimeManager 根据 capability、权限、成本、网络、设备状态选择默认 runtime。
- [ ] 用户可以在每个 workspace 中查看 runtime 选择原因和失败恢复建议。

## Phase 4：多预览与外部文件入口

目标：把 MobileCode 变成手机上的生成物查看器、修复器和发布前检查器。

- [x] `.html` 无 MIME、`EXTRA_TEXT` HTML 分享、读取失败提示已完成本地能力链路验证。
  - Evidence: 用户已验收该能力链路；2026-06-19 DocumentsUI 真实入口 QA 已保存截图；Chrome download direct tap 与 WeChat 仍单独跟踪。
- [ ] 建立 Preview Registry：`html`、`markdown`、`image`、`text`、`json`、`log`、`runtime-report`、`github-pages`。
- [ ] 每个 preview 记录：来源、文件路径、打开方式、渲染状态、错误、截图、最后验证时间。
- [ ] HTML preview verifier：DOM 非空、移动端无明显 overflow、按钮可点击、JS 错误可见。
- [ ] Markdown preview verifier：标题结构、图片引用、链接、移动端段落密度。
- [ ] GitHub Pages preview verifier：Pages URL 可访问、artifact 与 commit SHA 可追踪。

## Phase 5：本地模型与手机端部署

目标：正式发布不内置模型，但提供清晰下载、校验、配置和 fallback 体验。

- [x] 写出本地模型分发策略：release APK 不内置权重，模型通过 manifest 下载或导入。
  - Evidence: `docs/mobilecode-local-model-distribution.md`。
- [ ] 建立模型 manifest JSON，并放到 GitHub Pages 或其他静态地址。
- [ ] App 接入模型 manifest：展示模型名、大小、runtime、license、最低内存、下载状态。
- [ ] 下载管理：Wi-Fi-only、暂停/取消、临时文件、checksum、失败清理。
- [ ] 模型存储：app-owned `models/<model-id>/`，支持删除和重新校验。
- [ ] Android ExecuTorch runtime proof：从 demo 模型进入真实可配置 runtime。
- [ ] 评估 VibeThinker-3B、Qwen3 0.6B/1.7B 等模型的手机可部署性、内存、速度和 license。
- [ ] 本地模型 provider 只能在模型 ready 后显示为可选；远程 provider 始终保留 fallback。

## Phase 6：Mobile Harness 与 Benchmark 产品化

目标：把论文/benchmark 证据能力反哺 App，让每次手机端 AI 编码都有可复查报告。

- [x] 已有 Mobile Harness 专项路线图。
  - Evidence: `docs/mobile-harness-roadmp/roadmp-mobile-harness.md`。
- [ ] App 内 Benchmark Lab 支持选择任务、运行任务、展示 verifier report。
- [ ] Trace export JSONL：prompt、provider、runtime、tool call、file diff、preview、verifier、recovery。
- [ ] 形成公开 trace 与脱敏 trace 两种导出模式。
- [ ] 支持把 benchmark evidence 附到 GitHub issue、release 或 Pages。
- [ ] 至少形成 Android emulator、Android real device、iOS simulator 三类 evidence pack。

## Phase 7：模板图库、技能与内容生产

目标：让用户不需要记路径，只通过关键字调用风格参考、模板和生成技能。

- [ ] 建立模板图库索引：style id、用途、参考图路径、关键词、生成提示、适用尺寸、公开/私有标记。
- [ ] 将常用参考图迁入稳定素材目录，避免依赖难找的本地散落路径。
- [ ] 增加“风格参考 resolver”：用户说关键字时自动找到参考图和提示模板。
- [ ] 模板类型覆盖：App UI、架构图、产品宣传图、小红书卡片、论文/报告图、教程步骤图。
- [ ] 每个模板有预览图、适用场景、禁止用途和版权/隐私备注。
- [ ] 与 image generation 技能衔接：生成前先解析模板，再写入可复用 prompt。

## Phase 8：自动更新与发布运营

目标：App 内能读取远程更新 JSON，GitHub Pages 能成为轻量发布公告面。

- [x] App 内远程更新 feed 方向已进入代码和 docs。
  - Evidence: `docs/mobilecode-update.json` 与 Home 里的 update service 接入。
- [ ] GitHub Pages 地址在 MobileCode App 内有稳定入口。
- [ ] 更新 feed 支持 latestVersion、buildNumber、releaseNotes、downloadUrl、minimumSupportedVersion、发布时间。
- [ ] App 展示更新消息时区分公告、可选更新、强提醒、兼容性警告。
- [ ] Release notes 自动收集：commit、CI run、APK SHA256、截图证据、已知限制。
- [ ] 发布前检查 public-safe：不含密钥、本地私密路径、原始聊天日志。

## Phase 9：安全、隐私与合规

目标：把“手机端 AI 编码容器”做成可长期信任的产品，而不是临时 demo。

- [ ] Provider key 本地加密存储，导出和截图时默认隐藏。
- [ ] 证据账本支持脱敏导出。
- [ ] 外部 HTML 预览有清晰权限边界，不自动访问危险能力。
- [ ] 本地模型 manifest 只包含公开下载和 checksum，不包含私密地址。
- [ ] Runtime tool schema 做最小权限设计，禁止未声明的文件、网络和系统操作。
- [ ] 发布前运行 secrets scan、路径泄漏检查、截图隐私检查。
- [ ] 明确第三方 provider、模型 license、企业证书、iOS 限制和账号风控边界。

## 基于本路线图的近期执行队列

### R0：当前 Provider Auto 收尾

- [x] 只提交 Provider Auto 相关 3 个文件：`home_screen.dart`、`model_provider_preset_service.dart`、`model_provider_preset_service_test.dart`。
  - Evidence: commit `57eef01`。
- [x] 本路线图、本地模型策略、生产硬化说明作为独立 docs commit 提交。
  - Evidence: commit `ba4e244`。
- [x] Push 后等待 Android App Smoke Test 和 Mobile Runtime CI。
  - Evidence: 2026-06-20 UTC Android App Smoke Test run `27859042736` success；Mobile Runtime CI run `27859042737` success。
- [x] 将 `12-model-sheet-scroll-fixed.png` 与 `13-final-deepseek-auto-state-scroll-fixed.png` 保留为本地 QA 证据。
  - Evidence: `mobile_agent/qa-output/tierflow-deepseek-auto-20260619-201639/`。

### R1：HTML 外部打开真实 QA

- [x] Android 文件管理器打开 `.html` 到 MobileCode，保存截图和 XML。
  - Evidence: `mobile_agent/qa-output/html-open-real-app-20260619-204552/03-documentsui-opened-in-mobilecode.png` 与 `.xml`。
- [ ] 微信/聊天工具分享 HTML 文本或文件到 MobileCode，保存截图和失败原因。
- [ ] 浏览器下载页打开 `.html` 到 MobileCode，保存截图和 content URI 授权证据。
  - Evidence: 当前模拟器 Chrome direct tap 未路由到 MobileCode，需真实设备或分享入口复测。
- [ ] 将真实第三方 App QA 结果写入 `docs/mobilecode-release-qa.md` 或专项 QA 文档。

### R2：Provider Auto 产品化

- [ ] DeepSeek Auto 增加真实 router：Flash 默认，Pro 用于复杂编码、失败重试和长上下文。
- [ ] TierFlow Auto 增加 health check、真实请求 smoke 和错误文案。
- [ ] 在 evidence ledger 记录实际模型和切换原因。
- [ ] 增加 Provider preset 设置页说明，避免用户误以为 preset 等于内置 key。

### R3：本地模型下载入口

- [ ] 先发布模型 manifest JSON 草案，不直接接下载。
- [ ] App 只展示下载链接和说明，默认不下载。
- [ ] 选择一个小模型做 Android runtime proof，不承诺 VibeThinker-3B 已可量产。
- [ ] 记录每个模型的内存、速度、license、文件大小和失败边界。

### R4：架构图与对外表达

- [ ] 画 MobileCode 总架构图：App Shell、Provider Layer、Runtime Layer、Workspace Layer、Preview Layer、Evidence Ledger。
- [ ] 画 Provider Auto 路由图：用户请求、preset、router、Flash/Pro、TierFlow `auto`、账本记录。
- [ ] 画本地模型分发图：manifest、下载、checksum、runtime load、fallback provider。
- [ ] 画 Mobile Harness 闭环图：task、agent、runtime、artifact、preview、verifier、report。

## Open Questions

- DeepSeek Flash/Pro 的正式模型 ID、价格和 API 兼容性是否需要从 provider 官方文档重新确认。
- TierFlow Auto 是否要求特殊 header、账户配置或 model id 白名单。
- 本地模型首发应优先 Android ExecuTorch，还是先做“下载/导入/校验 UI”再接 runtime。
- 公开截图应放入 `docs/assets/`、README showcase，还是单独建立 `docs/assets/qa/`。
- MobileCode 长期路线图是否需要拆成 `roadmpxx.md` 风格的主文件与 `roadmpxx-tasks/` 任务目录。
