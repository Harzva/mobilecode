# T23 Post-1.0 Git 与 Cloud Runtime

Status: [x] Implemented (planning doc only, no code)
Priority: P3
Owner role: quality-reviewer + software-dev-pipeline
Depends on: T16, T17, T20

## Objective

定义 MobileCode 1.0 后的高风险能力边界：private clone、pull/fetch、push beta、merge/rebase、LFS/submodule、cloud/off-device runtime。

## Read First

- `docs/mobilecode-capability-matrix.md`
- `docs/mobilecode-risk-register.md`
- `docs/mobilecode-security-model.md`
- `roadmap/tasks/T16-local-commit-beta.md`
- `roadmap/tasks/T17-push-preflight-export.md`

## Can Edit

- `docs/mobilecode-post-1-git-cloud-runtime.md`
- `docs/mobilecode-capability-matrix.md`
- `docs/mobilecode-risk-register.md`
- `roadmp.md`
- this task file

## Do Not Edit

- Any implementation of private clone/push/pull/merge/rebase unless separate approved task exists.
- Token storage.
- Cloud credentials.

## High-risk Capabilities

- Private clone beta。
- Pull/fetch preflight。
- Push beta。
- Merge/rebase。
- LFS/submodule。
- Cloud/off-device runtime。
- Workspace retention and deletion。

## Required Gates Before Implementation

- Secure token storage.
- Scope-minimized auth.
- Approval queue.
- Audit log.
- Recovery advice.
- Kill switch.
- Manual QA evidence.
- Release note limitations.

## Acceptance Criteria

- Post-1.0 abilities are documented as future gates, not current promises.
- Capability matrix remains honest.
- Risk register includes each high-risk ability.
- No implementation is added by this planning task.

## Validation

```powershell
Test-Path .\docs\mobilecode-post-1-git-cloud-runtime.md
Select-String -Path .\docs\mobilecode-post-1-git-cloud-runtime.md -Pattern "private clone|push beta|pull|merge|cloud|kill switch"
```

## Handoff Prompt

请实现 T23 作为规划文档，不要写功能代码。所有高风险能力必须保持 gate-first，而不是 roadmap 写了就等同于承诺。

## Completion Notes

**Implemented**:
- `docs/mobilecode-post-1-git-cloud-runtime.md` — planning document covering 7 future-gated capabilities:
  - Private clone beta (Critical)
  - Pull/fetch preflight (High)
  - Push beta (Critical)
  - Merge/rebase (High)
  - LFS/submodule (Medium)
  - Cloud/off-device runtime (Critical)
  - Workspace retention and deletion (Medium)
- Each capability has: description, risk level, required gates, current state, dependencies.
- Global gate requirements defined: secure token storage, scope-minimized auth, approval queue, audit log, recovery advice, kill switch, manual QA evidence, release note limitations.
- Capability matrix updated with post-1.0 gate references for Push/Pull/Clone and Cloud Runtime.
- Risk register R-010 and R-011 updated with post-1.0 gate cross-references.

**Not done** (intentionally):
- No implementation code for any capability.
- No token storage or cloud credentials.
- No user-facing claims.
