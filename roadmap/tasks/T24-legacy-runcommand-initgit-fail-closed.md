# T24 Legacy RunCommand / InitGit Fail-closed

Status: ACCEPTED
Priority: P3

## Goal

Close the two remaining deferred legacy execution paths from T22 before starting the new Harness ActionEvidence work:

- `agent_action_system.dart` `RunCommandAction`
- `project_manager.dart` `initGit()`

This task does not implement Cloud Runtime, push/pull/private clone/merge/rebase, or real external writes.

## Why

T00-T23 were already accepted as a roadmap tranche, but these two paths still existed as executable code. Leaving them active would weaken the next Harness phase because ActionEvidence/ActionRunner could accidentally coexist with old direct execution paths.

## Changes

- `RunCommandAction.execute()` now fails closed after validation and points callers to `RuntimeManager/ActionRunner`.
- `project_manager.initGit()` no longer calls `git init`; it logs a blocked legacy message and returns.
- Legacy/risk/release closure docs were updated so these paths are no longer described as active deferred execution paths.

## Out of scope

- No Cloud Runtime implementation.
- No push/pull/private clone/merge/rebase.
- No full GitRuntime write workflow.
- No UI changes.
- No new shell execution path.

## Verification

- `git diff --check`
- Source scan for the old direct execution patterns:
  - `Process.run('sh', ['-c', command])`
  - `Process.run('git', ['init']`
- Documentation scan for stale active legacy claims.

## Acceptance

- The two legacy paths fail closed.
- Remaining high-risk future features stay documented as not Ready.
- MobileCode can start the Harness ActionEvidence task without known active legacy command/git-init bypasses.
