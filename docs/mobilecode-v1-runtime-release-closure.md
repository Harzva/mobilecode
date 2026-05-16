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
- **Android APK build/install/launch/helper protocol baseline** 已通过 Android App Smoke Test: https://github.com/Harzva/mobilecode/actions/runs/25958141674
- **Remote head**: `bd9373d7d26c12e57622b05d065a83735f7678f2`

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
| V1-CM-02 | P0 | 补小 Web 项目端到端 smoke 文档 | ACCEPTED | QA 文档有 smoke 章节 | 新增 `mobile_agent/tooling/runtime_web_smoke.py` 脚本；CI `helper-daemon-smoke` job 新增 web smoke 步骤并上传 `artifacts/runtime-web-smoke.json`；`docs/mobilecode-release-qa.md` 新增 "Small Web Project Runtime Smoke" 章节（本地/CI 验证、7 步协议调用、预期结果、失败恢复）。**Windows 9009 fix**: `_helper_python_command()` 封装跨平台 Python 可执行名选择（Windows→`python`，POSIX→`python3`），替换所有硬编码 `python3` 引用，修复 Helper /v1/execute 在 Windows 下 exitCode 9009 问题。 | Codex accepted after `python -m py_compile mobile_agent/tooling/runtime_web_smoke.py`, local `python mobile_agent/tooling/runtime_web_smoke.py --output qa/runtime-web-smoke-local.json` passed 7/7 steps, and `git diff --check` passed. |
| V1-CM-03 | P0 | 收束绕过 RuntimeManager 的执行入口 | TODO | 无绕过执行路径或已记录 | — | — |
| V1-CM-04 | P1 | Runtime Diagnostics 页面收尾 | TODO | 测试通过，页面可渲染 | — | — |
| V1-CM-05 | P1 | 失败恢复建议标准化 | TODO | 错误消息有恢复建议 | — | — |
| V1-CM-06 | P1 | Release QA 文档补齐 artifact/run id | TODO | QA 文档有完整章节 | — | — |
| V1-CM-07 | P2 | 收尾清单状态维护 | TODO | 状态列准确 | — | — |

### Baseline Evidence (已通过，独立于任务)

| 基线项 | 状态 | CI Run |
|--------|------|--------|
| Helper taskId/queue/protocol baseline (Mobile Runtime CI) | PASSED | https://github.com/Harzva/mobilecode/actions/runs/25958141678 |
| Android APK build/install/launch/helper protocol baseline (Android App Smoke Test) | PASSED | https://github.com/Harzva/mobilecode/actions/runs/25958141674 |
| Remote head | `bd9373d7d26c12e57622b05d065a83735f7678f2` | — |

---

## Deferred / Not V1

以下不在 v1 范围内：

- 完整 Termux 集成
- Embedded Lite
- 复杂并发调度
- 完整 PTY 支持
- 目录/模块改名

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

---

## Final Release Gate

v1 发布前必须满足：

1. 所有 P0 任务状态为 `ACCEPTED`。
2. 所有 P1 任务状态为 `ACCEPTED` 或 `DEFERRED`（需 Codex 明确批准）。
3. Mobile Runtime CI 绿灯。
4. Android App Smoke Test 绿灯。
5. Release QA 文档可独立指导手动验证。
6. Codex 在 Review Log 中签署最终发布批准。
