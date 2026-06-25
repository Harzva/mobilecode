# T19 GitHub Workflow Assistant

Status: [x] Implemented (structured preview builders; no real GitHub API writes)
Priority: P2
Owner role: software-dev-pipeline + quality-reviewer
Depends on: T13, T14, T18

## Objective

建立 MobileCode 的 GitHub workflow assistant，用于 PR summary、Actions failure report、issue triage、release notes draft，默认 preview-first。

## Read First

- `roadmap/tasks/T18-collaboration-actions.md`
- `roadmap/tasks/T13-evidence-model.md`
- `roadmap/tasks/T14-approval-queue-audit-log.md`
- `docs/mobilecode-release-qa.md`
- `README.md`

## Can Edit

- `mobile_agent/lib/modules/github_workflows/`
- `mobile_agent/lib/modules/collaboration/`
- `docs/mobilecode-capability-matrix.md`
- `roadmp.md`
- this task file

## Do Not Edit

- GitHub token storage.
- Real issue/PR/release creation.
- Git push.

## Required Workflows

- PR summary preview。
- GitHub Actions failure report preview。
- Issue triage preview。
- Release notes draft preview。
- Runtime/GitRuntime evidence attachment。

## Required Safety

- No unauthenticated real write。
- No automatic PR creation。
- No automatic issue comments。
- Drafts can be copied/exported but must say they are drafts。

## Acceptance Criteria

- At least one workflow can produce a structured preview.
- Preview can be converted to collaboration action.
- No real GitHub write occurs.
- README/capability matrix wording remains preview-first.

## Validation

```powershell
Test-Path .\mobile_agent\lib\modules\github_workflows
Select-String -Path .\mobile_agent\lib\modules\github_workflows\*.dart -Pattern "preview|Actions|triage|release"
```

## Handoff Prompt

请实现 T19。不要使用真实 GitHub API 写入。若需要 GitHub 全流程管理，遵守仓库 AGENTS.md 中的 GitHub 技能路由。

## Completion Notes

**Implemented**:
- `GitHubWorkflowAssistant` class with 4 preview builders:
  - `buildPRSummary()` — structured PR summary from diff metadata.
  - `buildActionsFailureReport()` — CI failure report with workflow, run ID, error, logs.
  - `buildIssueTriage()` — triage preview with suggested labels, priority, assignee.
  - `buildReleaseNotesDraft()` — release notes with changes, limitations, build evidence, governance link.
- `GitHubWorkflowPreview` model with type, title, summary, body, labels, assignees, metadata, recommendation.
- `toCollaborationAction()` — converts any preview into a `CollaborationAction` for the approval flow.
- All previews marked as `previewOnly: true` in metadata.
- Capability matrix updated: GitHub Workflow Assistant changed from Coming Soon to Preview.

**Not done** (intentionally):
- No real GitHub API calls.
- No PR/issue/release creation.
- No GitHub token storage.
