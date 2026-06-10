# MobileHarnessBench Rubric

## 评分等级

每个任务输出一个 `VerifierResult`：

- `passed`：任务目标完成，所有 required verifier 通过。
- `warning`：核心目标完成，但存在非阻断问题，例如预览密度、缺少可选截图、报告不完整。
- `failed`：任务目标未完成，或关键 artifact 不存在。
- `blocked`：外部权限、网络、账号、平台 API 或设备能力阻断，不能计入模型/产品失败。

## 评分维度

| 维度 | 说明 | v0 权重 |
| --- | --- | --- |
| Task Success | 是否完成用户目标 | 30 |
| Verified Success | 是否通过 verifier | 30 |
| Trace Completeness | 是否记录 prompt、tool call、result、artifact、URL、failure kind | 15 |
| Recovery | 失败时是否提供恢复路径 | 10 |
| Artifact Availability | 产物是否可访问或可下载 | 10 |
| Human Intervention | 人工介入是否少于任务阈值 | 5 |

## 失败类型

- `missing_artifact`
- `invalid_preview`
- `invalid_markdown`
- `invalid_html`
- `github_auth_blocked`
- `github_pages_unavailable`
- `actions_artifact_missing`
- `runtime_unavailable`
- `trace_incomplete`
- `manual_review_required`

## v0 规则

- 没有 verifier 的任务不能标记 `passed`。
- 外部权限失败必须标记 `blocked`，不能伪装成产品失败。
- 只要本地路径、token 或私密账号泄漏到公开报告，任务必须标记 `failed`。

## v2 candidate bank 质量规则

- 1000 条 candidate tasks 不等于 1000 条实验结果。
- v2 任务必须包含 `quality_gates`、`sampling_tags` 和 `scenario.quality_axis`。
- v2 至少覆盖 6 类：`file_intake`、`code_edit`、`preview_verification`、`github_delivery`、`harness_evidence`、`runtime_orchestration`。
- frozen subset 必须有抽样规则、人工抽检记录、verifier result、trace 和 summary。
- runtime orchestration 任务必须保持 `RuntimeProvider` 和 `ActionRunner` 边界，不能新增绕过边界的执行入口。
