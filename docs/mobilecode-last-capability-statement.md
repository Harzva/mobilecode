# last 口径能力声明（对外）

版本：`last`
生效基线：`2026-05-20-mobilecode-harness-next-plan.md`（H01/H04/H05 收口版本）

## 能力边界与对外可宣称项

### 已实现（可直接承诺的核心行为）

- 直接在手机端进行 AI 对话，执行“读取/写入/预览”核心 action 的闭环；
- `writeFile` / `readFile` / `previewHtml` 通过统一 `ActionRunner` 执行，且每次执行都会产出本地 `ActionEvidence`；
- 对话面板、工具入口、运行与文件路径在手机端以轻量交互展示，保留“首屏可读性”；
- `Tools` 页可打开 `Activity / Logs`，读取最近 evidence 与失败 evidence；
- 失败记录可一键复制摘要，并可跳转到 evidence 详情；
- 支持 `release` 观测与基础发布流程检查（CI、APK 构建、Release 产物）。

### 降级（在特定前提下可用）

- 部分能力在 Termux / Helper 未就绪时会进入降级分支：例如部分命令执行、外部发布、文件环境依赖动作会被提示并回退到受限模式；
- 运行状态、权限、路径等会在 `Tools` 中留存可见入口，避免错误吞没；
- 未满足全部环境条件时，仍可继续完成“对话与基本产物预览”任务。

### 阻断（本版本不做或不对外承诺）

- 不承诺完整的远端长期日志平台能力（本版本不做远端日志上传）；
- 不承诺在无本地/内嵌 runtime 的条件下稳定执行任意 shell 或跨设备长时任务；
- 不承诺对未完成 provider 能力（未就绪 Runtime 模块、未接入云端重型发布链路）进行完整可复现承诺；
- 不承诺 `ActionEvidence` 跨进程、跨重启的持久保存（当前为内存优先）。

## 与 H01/H04/H05 对外表达闭环说明

- H01 基线口径来源：用“已实现 / 降级 / 阻断”三色边界统一解释能力，不把 UI 流程误报为可执行工具；
- H04 首屏策略：`MobileCode` 以聊天入口为主；首屏显式展示能力边界，仅保留轻量操作入口，不放大 `runtime` 调试面板信息；
- H05 复盘入口：`Tools → Activity / Logs` 仅读取 `ActionEvidenceStore.shared.recent(count)` 与 `ActionEvidenceStore.shared.failures()`，不引入检索、分类、远程日志链路；失败可定位、可复制、可跳到详情。

## 不可承诺项（对外避免承诺）

- “支持全部模型函数调用都等价于真实执行”
- “支持任意系统级脚本或任意 shell 命令长期后台执行”
- “支持完整远端日志追踪、集中检索、审计归档”
- “在本版本保证所有异常都可自动修复或自动恢复”

## 验收建议（发布治理附注）

- 对外文案与页面文案优先对齐该声明；
- 若新增功能涉及边界变更，先更新本声明并更新
  `docs/import_phase_summarize/2026-05-20-mobilecode-harness-next-plan.md`；
- 仅当新版本在 CI（Mobile Runtime CI + Build Android APK）通过并完成小范围 APK 验收后再对外放大宣发。
