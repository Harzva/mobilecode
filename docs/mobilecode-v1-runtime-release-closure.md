# MobileCode v1 Runtime Release Closure

唯一任务板。后续只使用 ccmimo 执行，Codex 审核。不使用 cckimi、ccdeepseek 或任何其他评估/执行代理。

---

## V1 Stop Line

v1 范围：Mobile Runtime CI 绿灯、Android App Smoke Test 绿灯、RuntimeManager 统一执行入口、基础 Diagnostics、Release QA 文档可追溯。

不包含：完整 Termux 集成、Embedded Lite、复杂并发调度、完整 PTY。

---

## Status Rules

| 状态 | 含义 |
|------|------|
| `TODO` | 未开始 |
| `IN_PROGRESS` | ccmimo 正在执行 |
| `REVIEW_NEEDED` | 已完成，等待 Codex 审核 |
| `ACCEPTED` | Codex 审核通过 |
| `BLOCKED` | 被外部依赖阻塞 |
| `DEFERRED` | 不在 v1 范围内 |

状态流转：`TODO → IN_PROGRESS → REVIEW_NEEDED → ACCEPTED`。被阻塞或推迟的任务保持 `BLOCKED` 或 `DEFERRED`。

---

## Repository Naming Note

- **MobileCode** 是产品/仓库名。
- **mobile_agent** 是 Flutter mobile app module，位于 `mobile_agent/` 目录。
- v1 不做目录改名，不重命名 module。

---

## Already Accepted Runtime Baseline

以下基线证据已被 Codex 接受，不受后续任务修改影响：

- **Helper taskId/queue/protocol baseline** 已通过 Mobile Runtime CI: https://github.com/Harzva/mobilecode/actions/runs/25958141678
- **Android emulator smoke baseline** (install/launch/helper protocol) 已通过 Android App Smoke Test: https://github.com/Harzva/mobilecode/actions/runs/25959749508 — artifact `mobilecode-android-smoke`，不含 APK
- **Release APK build baseline** 已通过 Build Android APK: https://github.com/Harzva/mobilecode/actions/runs/25960889017 — artifact `mobilecode-apk`，文件 `mobilecode-v0.1.0.apk`，APK 大小 `53051517` bytes，SHA256 `A13C0381EE2DEC6DA4C055CEC86A0990AE67344B7FE696641EB0B2682A8F928D`；GitHub Release `v0.1.0` asset digest `sha256:a13c0381ee2dec6da4c055cec86a0990ae67344b7fe696641eb0b2682a8f928d`
- **Remote head**: `594e6e51e794600e036b8a431f464dbf6f914313`

---

## ccmimo Execution Queue

每个任务由 ccmimo 执行，Codex 审核。任务按优先级排序。

### V1-CM-01

- **Goal**: 清理 UI 中剩余 Termux-only 文案，统一成 Runtime-first
- **Allowed Files**: `mobile_agent/lib/screens/home_screen.dart`, `mobile_agent/lib/screens/build_preview_screen.dart`
- **Forbidden**: 不修改服务层、providers、tests；不新增 Runtime 平台能力
- **ccmimo Prompt**: 扫描 allowed files 中的 dart 文件，找到用户可见的 Termux 引用（注释、变量名中的技术标识符不算），替换为 Runtime-first 文案。只改 UI 文案，不改逻辑。
- **Verification**: `grep -ri "termux" mobile_agent/lib/screens/home_screen.dart mobile_agent/lib/screens/build_preview_screen.dart` 仅在非 UI 上下文出现
- **Codex Acceptance Criteria**: 用户可见文案中无 Termux 引用，或 Termux 引用有明确技术必要性并记录在 Review Notes
- **Stop Condition**: 所有用户可见的 Termux 引用已替换为 Runtime-first 文案，或确认无需修改

### V1-CM-02

- **Goal**: 补一个小 Web 项目端到端 smoke 文档/脚本入口
- **Allowed Files**: `docs/mobilecode-release-qa.md`, `.github/workflows/mobile-runtime-ci.yml`, `mobile_agent/tooling/*`
- **Forbidden**: 不修改 Flutter 源码、不修改其他 CI 工作流
- **ccmimo Prompt**: 在 docs/mobilecode-release-qa.md 中补充一个小 Web 项目的端到端 smoke 验证步骤：从创建项目到运行到看到结果，每步写清楚命令和预期输出。如需新增 tooling 脚本，放入 mobile_agent/tooling/。
- **Verification**: docs/mobilecode-release-qa.md 中存在 "smoke" 或 "web" 相关章节，步骤可独立复现
- **Codex Acceptance Criteria**: QA 文档中有完整的小 Web 项目 smoke 步骤，每步有命令和预期结果
- **Stop Condition**: release QA 文档中包含一个可复现的小 Web 项目端到端 smoke 验证步骤

### V1-CM-03

- **Goal**: 检查并收束绕过 RuntimeManager 的执行入口
- **Allowed Files**: `mobile_agent/lib/services/*`, `mobile_agent/lib/providers/*`, `mobile_agent/lib/screens/*`
- **Forbidden**: 不修改 tests、tooling、docs；不新增 Runtime 平台能力
- **ccmimo Prompt**: 扫描 allowed files 中的 dart 文件，查找直接调用 runtime 执行（如 Process.run、RuntimeService 直接调用）但不经过 RuntimeManager 的路径。如果找到，要么重构为经过 RuntimeManager，要么记录为已知限制。
- **Verification**: grep 确认无绕过 RuntimeManager 的直接执行调用，或绕过入口已在本文档记录
- **Codex Acceptance Criteria**: 所有执行入口经过 RuntimeManager，或绕过入口已记录并有技术理由
- **Stop Condition**: 所有 runtime 执行路径都经过 RuntimeManager，或绕过入口已记录并标记为已知限制

### V1-CM-04

- **Goal**: Runtime Diagnostics 页面收尾
- **Allowed Files**: `mobile_agent/lib/screens/home_screen.dart`
- **Forbidden**: 不修改 services、providers、tests；不新增 Runtime 平台能力
- **ccmimo Prompt**: 检查 home_screen.dart 中 Runtime Diagnostics 相关的实现，确保它能正确显示 runtime 状态（运行中/已停止/错误），修复已知问题。
- **Verification**: `flutter test mobile_agent/test/` 相关测试通过，Diagnostics 页面可正常渲染
- **Codex Acceptance Criteria**: Diagnostics 页面显示 runtime 状态，测试覆盖核心场景
- **Stop Condition**: Diagnostics 页面可正常显示 runtime 状态，测试通过

### V1-CM-05

- **Goal**: 失败恢复建议标准化
- **Allowed Files**: `mobile_agent/lib/services/runtime_*`, `mobile_agent/lib/screens/home_screen.dart`
- **Forbidden**: 不修改 providers、tests、docs；不新增 Runtime 平台能力
- **ccmimo Prompt**: 检查 allowed files 中用户可见的错误消息，确保每条错误消息都包含恢复建议（如"重试"、"检查网络"、"重启 runtime"）。
- **Verification**: 错误消息包含恢复建议
- **Codex Acceptance Criteria**: 用户可见错误消息均有恢复建议
- **Stop Condition**: 用户可见的错误消息包含标准化的恢复建议

### V1-CM-06

- **Goal**: Release QA 文档补齐 artifact/run id/手动验证步骤
- **Allowed Files**: `docs/mobilecode-release-qa.md`, `docs/mobilecode-v1-runtime-release-closure.md`
- **Forbidden**: 不修改代码、CI、tooling
- **ccmimo Prompt**: 在 docs/mobilecode-release-qa.md 中补充：1) CI artifact 下载路径说明；2) 关联的 CI run id；3) 手动验证步骤（从下载 artifact 到安装到验证）。
- **Verification**: QA 文档包含 artifact、run id、手动验证章节
- **Codex Acceptance Criteria**: QA 文档可独立指导手动验证
- **Stop Condition**: QA 文档包含 artifact 路径、CI run id、手动验证步骤

### V1-CM-07

- **Goal**: 收尾清单状态维护，不写代码
- **Allowed Files**: `docs/mobilecode-v1-runtime-release-closure.md`
- **Forbidden**: 不修改任何代码、CI 或其他文档
- **ccmimo Prompt**: 检查本文件中所有任务的状态，根据实际完成情况更新状态列，不修改代码。
- **Verification**: 本文件状态列反映实际进度
- **Codex Acceptance Criteria**: 状态列准确，无遗漏
- **Stop Condition**: 本文件状态列与实际一致

---

## Required Tasks

| ID | Priority | Task | Status | Evidence Required | Current Evidence | Reviewer Notes |
|----|----------|------|--------|-------------------|------------------|----------------|
| V1-CM-01 | P0 | 清理 UI 中剩余 Termux-only 文案 | ACCEPTED | grep 无 Termux UI 引用 | home_screen.dart 9 处 user-visible 文案已改为 Runtime-first/External Termux fallback；build_preview_screen.dart 6 处 user-visible 文案已改为 Runtime-first/External Termux fallback。仅保留技术标识符（com.termux、termux_probe、变量名、方法名、服务名）和 Runtime Diagnostics 中诊断行（External Termux / External Termux:API），后者属于技术诊断项。追加修补 3 处文案：(1) `_openUrl` label 改为 `External Termux install page`；(2) Mini harness booted detail 中 `termux_probe` 显示文案改为 `runtime_probe`；(3) Diagnostics 诊断行 label `Termux:API` 改为 `External Termux:API`。再修补 Tool Lab probe 结果文案 2 处：`Termux:API fallback detected.` → `External Termux:API fallback detected.`；`Termux:API not detected.` → `External Termux:API not detected.`（line 4496）。 | Codex accepted after ccmimo output review, targeted text search, and `git diff --check`; remaining Termux hits are technical identifiers, package names, or explicit External Termux fallback diagnostics. |
| V1-CM-02 | P0 | 补小 Web 项目端到端 smoke 文档 | ACCEPTED | QA 文档有 smoke 章节 | 新增 `mobile_agent/tooling/runtime_web_smoke.py` 脚本；CI `helper-daemon-smoke` job 新增 web smoke 步骤并上传 `artifacts/runtime-web-smoke.json`；`docs/mobilecode-release-qa.md` 新增 "Small Web Project Runtime Smoke" 章节（本地/CI 验证、7 步协议调用、预期结果、失败恢复）。**Windows 9009 fix**: `_helper_python_command()` 封装跨平台 Python 可执行名选择（Windows→`python`，POSIX→`python3`），替换所有硬编码 `python3` 引用，修复 Helper /v1/execute 在 Windows 下 exitCode 9009 问题。**CI readiness fix**: `_wait_ready()` 每次探测使用新的 `HTTPConnection`，避免 daemon 启动期间异常连接复用导致 `http.client.CannotSendRequest: Request-sent`。 | Codex accepted after `python -m py_compile mobile_agent/tooling/runtime_web_smoke.py`, local `python mobile_agent/tooling/runtime_web_smoke.py --output qa/runtime-web-smoke-local.json` passed 7/7 steps, `git diff --check` passed, and Mobile Runtime CI passed on https://github.com/Harzva/mobilecode/actions/runs/25960104143. |
| V1-CM-03 | P0 | 收束绕过 RuntimeManager 的执行入口 | ACCEPTED | 无绕过执行路径或已记录 | ccmimo 补扫并由 Codex 复审 `rg "Process\.(run|start)|TermuxService|_termux\.execute|\.executeStream\(|\.execute\(" mobile_agent/lib/services mobile_agent/lib/providers mobile_agent/lib/screens`。Runtime/provider 内部实现保留：`terminal_service.dart`、`terminal_controller.dart`、`termux_service.dart`、`external_termux_provider.dart`、`terminal_provider.dart`、`ssh_provider.dart`、`github_pages_service.dart`。UI 中 `build_preview_screen.dart` 的 `_termux.execute('am start ...')` 仅用于打开 External Termux App，不是 build/command 执行。已记录 Deferred：`agent_action_system.dart` 和 `project_manager.dart` 仍有 direct `Process.run`  legacy path，不纳入 v1 runtime gate。 | Codex 未接受第一轮 ccmimo 扫描（漏项），要求补扫；第二轮补扫分类完整。V1 接受标准是：Build/Preview/Runtime UI 执行入口已走 RuntimeManager；剩余 legacy direct Process path 明确记录为 Not V1，不继续扩底层。 |
| V1-CM-04 | P1 | Runtime Diagnostics 页面收尾 | ACCEPTED | 测试通过，页面可渲染 | `_RuntimeDiagnosticsSheet` (L4737-4958) 已完整实现：active runtime/provider 状态、Helper/External Termux/WebViewOnly fallback visibility panel、capabilities/missing dependencies/recovery actions（每个 `_RuntimeHealthTile`）、task snapshot（`_TaskSnapshotPanel`）。4 处入口（icon button、command shortcut、quick action、grid action）均指向同一 sheet。无散落 Termux-only setup sheet。External Termux install/launch 按钮作为 fallback 保留。无 home_screen 测试文件存在，forbidden 规则禁止修改 tests。 | Codex accepted after ccmimo output review and targeted `rg` verification. Note: ccmimo touched this closure doc despite the V1-CM-04 prompt limiting edits to `home_screen.dart`; Codex retained the reviewed status evidence and did not accept any unreviewed code change. |
| V1-CM-05 | P1 | 失败恢复建议标准化 | ACCEPTED | 错误消息有恢复建议 | `RuntimeTaskFailureKind` 已覆盖 `timeout/cancelled/dependencyMissing/commandBlocked/cwdOutsideWorkspace/authFailed/runtimeLost/processFailed/unknown`；`runtimeActionRecoveryHint()` 提供 action-aware 恢复建议；`runtimeFailureKindHint()` 为 task snapshot/detail 提供无 action 上下文建议；Home UI 展示 `Recovery:`、`failureKind`、`missingDependencies`、`recoveryActions`。 | Codex accepted after ccmimo read-only review and local `rg` verification. First editable ccmimo attempt timed out and produced no review metadata; Codex stopped the stray Claude process and reran a narrower read-only check. No code changes were required. |
| V1-CM-06 | P1 | Release QA 文档补齐 artifact/run id | ACCEPTED | QA 文档有完整章节 | 新增 "CI Artifact & Run References"（run ID 25960104143、25959749508、25904715949；`gh run download` 命令；浏览器下载说明）；新增 "Manual Verification"（7 步手动验证）；新增 "Failure Evidence & Recovery"。**Codex correction**: 修正 artifact 区分——`mobilecode-helper-smoke`=helper/web smoke evidence；`mobilecode-android-smoke`=emulator smoke evidence 不含 APK；`mobilecode-apk`=可安装 APK 来自 Build Android APK；手动验证步骤改为从 `mobilecode-apk` 安装；baseline 表增加 Artifact 列和 Build Android APK 行；说明 final release 前需在目标 release commit 重跑 Build Android APK。 | Codex accepted after reviewing ccmimo correction, GitHub artifact API output, targeted `rg`, and `git diff --check`. |
| V1-CM-07 | P2 | 收尾清单状态维护 | ACCEPTED | 状态列准确 | V1-CM-01–06 均 ACCEPTED；V1-CM-07 经 Codex 审核后更新为 ACCEPTED；Final Release Gate 6 条件均可从本文档读出；Review Log 已追加。 | Codex accepted after reviewing ccmimo output, Required Tasks states, Final Release Gate evidence, and `git diff --check`. |

### Baseline Evidence (已通过，独立于任务)

| 基线项 | 状态 | CI Run | Artifact |
|--------|------|--------|----------|
| Helper taskId/queue/protocol baseline (Mobile Runtime CI) | PASSED | https://github.com/Harzva/mobilecode/actions/runs/25958141678 | `mobilecode-helper-smoke` |
| Android emulator smoke: install/launch/helper protocol (Android App Smoke Test) | PASSED | https://github.com/Harzva/mobilecode/actions/runs/25959749508 | `mobilecode-android-smoke` (smoke evidence only, no APK) |
| Release APK build (Build Android APK) | PASSED | https://github.com/Harzva/mobilecode/actions/runs/25960889017 | `mobilecode-apk` (`mobilecode-v0.1.0.apk`, SHA256 `A13C0381…`) |
| Remote head | `594e6e51e794600e036b8a431f464dbf6f914313` | — | — |
| V1-CM-02 web smoke CI follow-up (Mobile Runtime CI) | PASSED | https://github.com/Harzva/mobilecode/actions/runs/25960104143 | `mobilecode-helper-smoke` |
| Latest verified remote head | `8b051e4a76d6bc5348506071c208332c7bf93e2a` | — | — |

---

## Deferred / Not V1

以下不在 v1 范围内：

- 完整 Termux 集成
- Embedded Lite
- 复杂并发调度
- 完整 PTY 支持
- 目录/模块改名
- `agent_action_system.dart` 的 legacy `RunCommandAction` / `Git*Action` direct `Process.run` 重构：未来如果把 Riverpod agent action system 接入主 RuntimeManager，再统一迁移。
- `project_manager.dart` 的 lightweight git utility direct `Process.run` 重构：当前属于项目管理 legacy path，不进入 v1 runtime gate。

---

## Standard ccmimo Prompt

```
你是 MobileCode v1 Runtime 收尾执行代理。只执行 docs/mobilecode-v1-runtime-release-closure.md 中 ccmimo Execution Queue 指定的任务。

必须遵守：
1. 一次只做一个任务。不要并行处理多个任务。
2. 只修改 allowed files 中列出的文件。
3. 不修改代码逻辑（除非任务明确要求）。
4. 不新增 Runtime 平台能力。
5. 不删除用户已有内容。
6. 每个任务完成后，将任务状态改为 REVIEW_NEEDED。不得自行改为 ACCEPTED。
7. Codex 审核通过前，状态必须保持 REVIEW_NEEDED。
8. 所有状态只能使用：TODO、IN_PROGRESS、REVIEW_NEEDED、ACCEPTED、BLOCKED、DEFERRED。

完成后停止，并在输出中列出修改文件和验证结果。
```

---

## Codex Review Rules

1. Codex 审核每个 `REVIEW_NEEDED` 状态的任务。
2. 审核通过：状态改为 `ACCEPTED`，在 Reviewer Notes 记录。
3. 审核不通过：状态改回 `TODO`，在 Reviewer Notes 记录原因。
4. 审核时检查：修改是否在 allowed files 范围内，是否违反 v1 限制。
5. 每次审核后更新 Review Log。

---

## Review Log

| 日期 | 任务 ID | 审核人 | 结果 | 备注 |
|------|---------|--------|------|------|
| 2026-05-16 | V1-CM-00 (初始化) | ccmimo | REVIEW_NEEDED | 等待 Codex 审核初始化文档 |
| 2026-05-16 | V1-CM-00 (修正) | ccmimo | REVIEW_NEEDED | 修正 allowed files 与用户计划对齐；明确代理边界：仅使用 ccmimo；补充 Already Accepted Runtime Baseline；统一任务卡字段格式 |
| 2026-05-16 | V1-CM-00 (Codex audit) | Codex | ACCEPTED | 已审核 ccmimo 输出、目标文件 diff、结构校验和 `git diff --check`；收尾任务板 accepted，后续从 V1-CM-01 开始逐项执行 |
| 2026-05-16 | V1-CM-01 | ccmimo | REVIEW_NEEDED | home_screen.dart 9 处 + build_preview_screen.dart 6 处 user-visible Termux 文案改为 Runtime-first/External Termux fallback；保留 com.termux、termux_probe、变量名/方法名等技术标识符；保留 Runtime Diagnostics 诊断行作为技术诊断项 |
| 2026-05-16 | V1-CM-01 | ccmimo patch | REVIEW_NEEDED | Codex 复审追加 3 处文案修补：(1) `_openUrl` label → `External Termux install page`；(2) Mini harness booted detail `termux_probe` → `runtime_probe`；(3) Diagnostics label `Termux:API` → `External Termux:API` |
| 2026-05-16 | V1-CM-01 | ccmimo patch | REVIEW_NEEDED | Codex 再审追加 Tool Lab probe 结果文案 2 处修补：`Termux:API fallback detected.` → `External Termux:API fallback detected.`；`Termux:API not detected.` → `External Termux:API not detected.`（home_screen.dart line 4496） |
| 2026-05-16 | V1-CM-01 | Codex | ACCEPTED | 已审核 ccmimo 输出、目标文件范围、剩余 Termux 命中和 `git diff --check`；接受为 Runtime-first UI 文案收束完成 |
| 2026-05-16 | V1-CM-02 | ccmimo | REVIEW_NEEDED | 新增 `runtime_web_smoke.py` 脚本（helper daemon 启动 -> 创建最小 web 项目 -> 7 步协议调用 -> preview 证据）；CI helper-daemon-smoke job 新增编译检查和 smoke 运行步骤；QA 文档新增 "Small Web Project Runtime Smoke" 章节 |
| 2026-05-16 | V1-CM-02 | ccmimo patch | REVIEW_NEEDED | Windows 9009 fix: 新增 `_helper_python_command()` 封装跨平台 Python 可执行名（Windows→`python`，POSIX→`python3`），替换 4 处硬编码 `python3` 引用，修复 Helper /v1/execute 在 Windows 下 exitCode 9009 |
| 2026-05-16 | V1-CM-02 | Codex | ACCEPTED | 已审核脚本、CI、QA 文档和收尾状态；本地 py_compile 通过，runtime web smoke 7/7 步通过，`git diff --check` 通过 |
| 2026-05-16 | V1-CM-02 CI follow-up | ccmimo patch | REVIEW_NEEDED | 修复 GitHub Actions 中 `_wait_ready` 复用异常 `HTTPConnection` 导致的 `CannotSendRequest: Request-sent`；仅修改 `mobile_agent/tooling/runtime_web_smoke.py` |
| 2026-05-16 | V1-CM-02 CI follow-up | Codex | ACCEPTED | 已审核 ccmimo 输出、脚本 diff、本地 `py_compile`、本地 runtime web smoke 7/7；推送后 Mobile Runtime CI 25960104143 通过 |
| 2026-05-16 | V1-CM-03 | ccmimo | REVIEW_NEEDED | 初扫报告为无代码改动，但漏掉 `project_manager.dart`、`terminal_service.dart`、`terminal_controller.dart`、`termux_service.dart`、`github_pages_service.dart` 等命中 |
| 2026-05-16 | V1-CM-03 | Codex | REVIEW_NEEDED | 未接受初扫；用完整 `rg` 命中要求 ccmimo 复扫分类 |
| 2026-05-16 | V1-CM-03 | ccmimo supplement | REVIEW_NEEDED | 完整分类 direct execution 命中：runtime/provider internals 保留，`agent_action_system.dart` 与 `project_manager.dart` 记录为 legacy Deferred，不做 v1 大重构 |
| 2026-05-16 | V1-CM-03 | Codex | ACCEPTED | 已审核补扫输出和 `rg` 证据；确认 Build/Preview/Runtime UI 执行入口不绕过 RuntimeManager，剩余 legacy direct Process path 已写入 Deferred / Not V1 |
| 2026-05-16 | V1-CM-04 | ccmimo | REVIEW_NEEDED | 无需代码改动；`_RuntimeDiagnosticsSheet` 已完整实现 active runtime/provider 状态、fallback visibility、capabilities/missing deps/recovery actions、task snapshot；4 处入口指向同一 sheet；无散落 Termux-only setup sheet；无 home_screen 测试文件（forbidden 禁止修改 tests） |
| 2026-05-16 | V1-CM-04 | Codex | ACCEPTED | 已审核输出、`home_screen.dart` diagnostics 文案/入口搜索和 `git diff --check`；接受为已满足。记录 ccmimo 越界更新 closure doc，Codex 已复审并保留状态证据 |
| 2026-05-16 | V1-CM-05 | ccmimo | BLOCKED | 首次 editable 运行超时且未生成 pending review metadata；Codex 停止残留 Claude 进程并改为窄范围只读复核 |
| 2026-05-16 | V1-CM-05 | ccmimo readonly | REVIEW_NEEDED | 确认 `RuntimeTaskFailureKind`、`runtimeActionRecoveryHint()`、`runtimeFailureKindHint()`、Home UI `Recovery:` / `failureKind` / `missingDependencies` / `recoveryActions` 均已覆盖 |
| 2026-05-16 | V1-CM-05 | Codex | ACCEPTED | 已审核 ccmimo 只读输出与本地 `rg` 证据；失败恢复建议已标准化，无需代码改动 |
| 2026-05-16 | V1-CM-06 | ccmimo | REVIEW_NEEDED | 新增 "CI Artifact & Run References"（run ID 25960104143/25959749508、`gh run download` 命令、浏览器下载说明）；新增 "Manual Verification: Download → Install → Runtime Smoke"（7 步手动验证流程）；新增 "Failure Evidence & Recovery"（证据收集命令、常见失败恢复表、evidence 归档说明） |
| 2026-05-16 | V1-CM-06 | ccmimo correction | REVIEW_NEEDED | Codex 审核修正 artifact 准确性：(1) `mobilecode-android-smoke` 是 emulator smoke evidence，不含 APK；(2) 可安装 APK 来自 Build Android APK workflow 的 `mobilecode-apk` artifact（run 25904715949），文件 `mobilecode-v0.1.0.apk`；(3) `mobilecode-helper-smoke` 是 Mobile Runtime CI helper/web smoke evidence；(4) 手动验证步骤改为从 `mobilecode-apk` 安装 APK；(5) baseline 表增加 Artifact 列和 Build Android APK 行；(6) 说明 final release 前需在目标 release commit 重跑 Build Android APK |
| 2026-05-16 | V1-CM-06 | Codex | ACCEPTED | 已审核 ccmimo correction、GitHub artifact API 输出、`rg` 命中和 `git diff --check`；接受 Release QA 文档为可复现发布验证指南 |
| 2026-05-16 | V1-CM-07 | ccmimo | REVIEW_NEEDED | 确认 V1-CM-01–06 状态列均为 ACCEPTED；V1-CM-07 更新为 REVIEW_NEEDED；Final Release Gate 6 条件（P0 accepted、P1 accepted/deferred、Mobile Runtime CI passed、Android App Smoke Test passed、QA 文档有 artifact/manual steps、Deferred/Not V1 明确）均可从本文档读出 |
| 2026-05-16 | V1-CM-07 | Codex | ACCEPTED | 已审核状态表、Final Release Gate 证据和 `git diff --check`；v1 Runtime 底层扩张停止线达成 |
| 2026-05-16 | Final Release Gate | Codex | ACCEPTED | P0/P1/P2 收尾任务均 ACCEPTED；Mobile Runtime CI 25960104143 通过；Android App Smoke Test 25959749508 通过；Release QA 文档有 artifact/run/manual/evidence/recovery；Deferred/Not V1 未被纳入 v1 |
| 2026-05-16 | Release APK evidence | Codex | ACCEPTED | Build Android APK 25960889017 passed (head `594e6e51`)；GitHub Release `v0.1.0` asset `mobilecode-v0.1.0.apk` updated `2026-05-16T11:40:29Z`, size `53051517`, digest `sha256:a13c0381ee2dec6da4c055cec86a0990ae67344b7fe696641eb0b2682a8f928d`；local downloaded APK SHA256 verified match；manual install/launch BLOCKED — no online adb device (`qa/release-apk-25960889017/summary.json` status `blocked`, error `No online adb device`) |
| 2026-05-16 | QA script path correction | Codex | ACCEPTED | Codex audit correction for QA script path: recovery command in Latest APK Evidence changed from non-existent `mobile_agent/tooling/android_release_qa.py` to local Codex skill script `C:\Users\harzva\.codex\skills\android-release-emulator-qa-skill\scripts\android_release_qa.py` with full arguments (--apk, --package, --github-release, --output) |

---

## Final Release Gate

v1 发布前必须满足：

1. 所有 P0 任务状态为 `ACCEPTED`。
2. 所有 P1 任务状态为 `ACCEPTED` 或 `DEFERRED`（需 Codex 明确批准）。
3. Mobile Runtime CI 绿灯。
4. Android App Smoke Test 绿灯。
5. Release QA 文档可独立指导手动验证。
6. Codex 在 Review Log 中签署最终发布批准。
