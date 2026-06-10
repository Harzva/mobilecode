# Verifier Contract

Verifier 是 Mobile Harness 的验收层。它不替代用户判断，但必须把“看起来完成”变成可复查的结构化结果。

## 输入

```json
{
  "task_id": "MH-FI-001",
  "workspace_root": "mobilecode_projects/...",
  "artifacts": [],
  "preview_urls": [],
  "action_trace": [],
  "environment": {
    "app_version": "0.1.30+49",
    "runtime_backend": "webview_only"
  }
}
```

## 输出

```json
{
  "task_id": "MH-FI-001",
  "status": "passed",
  "score": 92,
  "failure_kind": "none",
  "checks": [
    {
      "name": "artifact_exists",
      "status": "passed",
      "message": "index.html exists"
    }
  ],
  "evidence": {
    "artifact_paths": [],
    "preview_urls": [],
    "screenshots": [],
    "logs": []
  }
}
```

## 状态

- `passed`
- `warning`
- `failed`
- `blocked`

## v0 离线实现

`scripts/run_mobile_harness_bench.py` 已实现 `representative-v0` 的 stdlib verifier，用于先证明协议闭环。任务集合来源：[tasks/representative-v0.json](../tasks/representative-v0.json)。

- `MH-FI-001`：`external_file_verifier` + `html_preview_verifier`。
- `MH-CE-004`：`json_verifier` + `trace_verifier`。
- `MH-PV-001`：`html_preview_verifier` + `snapshot_verifier`。
- `MH-GD-001`：`github_delivery_verifier`，离线环境记录为 `blocked`。
- `MH-HE-001`：`trace_verifier`。

输出位置：[runs/2026-06-06-v0-dry-run/](../runs/2026-06-06-v0-dry-run/)。

离线实现不读取凭据、不访问远程 GitHub、不产出真实设备截图。它只验证 fixture、artifact、preview route、trace 和 public-safe report 结构。

v1 200 条任务库位于 [tasks/v1-task-bank.json](../tasks/v1-task-bank.json)。v2 1000 条任务库位于 [tasks/v2-task-bank.json](../tasks/v2-task-bank.json)，并新增 `runtime_orchestration` 类。

candidate task bank 不是实验结果。任务只有在产出 verifier result、trace 和 summary 后，才能计入实验结果。v2 task 还必须声明 `quality_gates` 和 `sampling_tags`，用于后续抽检、分层和 frozen subset。

## 必备检查

### HTML preview verifier

- artifact exists。
- file extension is `.html` or content type is HTML。
- DOM/text length is above task threshold。
- no obvious mobile overflow in bounded viewport。
- preview URL or WebView route exists。

### Markdown preview verifier

- artifact exists。
- Markdown can be parsed into headings/paragraphs/images。
- local image references are resolvable or clearly marked missing。
- first screen is not empty。

### External file verifier

- incoming file URI/path is recorded.
- detected type is recorded.
- fallback preview mode is recorded.
- unsupported type returns user-readable blocked result.

### GitHub delivery verifier

- target repo and branch are recorded.
- commit SHA exists for file changes.
- Pages URL or Actions run URL exists when requested.
- artifact is listed when build task requires it.

### Evidence verifier

- action trace has at least one user input, one action, one result.
- failure kind is stable when failed or blocked.
- report includes recovery suggestion.

### Runtime orchestration verifier

- selected runtime provider is recorded.
- runtime health, fallback reason or stop action is recorded.
- blocked shell/runtime actions are explicit.
- all runtime actions preserve `RuntimeProvider` and `ActionRunner` boundaries.

## 隐私规则

- Verifier output must not include raw tokens.
- Local absolute paths may appear in private run reports, but public reports must rewrite them to repo-relative paths.
- Account IDs and OpenIDs must be omitted unless explicitly approved for internal evidence.
