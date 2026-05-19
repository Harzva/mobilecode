# MobileCode Rules and Memory

## Purpose

MobileCode should keep two durable knowledge layers:

- `Rules`: explicit, user-approved operating instructions, similar to `CLAUDE.md` or `AGENTS.md`.
- `Memory`: accumulated preferences, repo insights, habits, and reusable observations that can propose future rules.

They are related, but not the same thing.

## Rules

Rules are the source of truth for how MobileCode should behave.

Good examples:

- Always prefer GitHub Pages for simple HTML publishing.
- Use GitHub Actions for heavy APK builds when local runtime has no Android SDK.
- Never run arbitrary MCP or Hook scripts without review.
- Keep generated web pages mobile-first and touch-friendly.

Rules should be short, explicit, stable, and user-approved.

In the app, accepted Rules can be exported as `MOBILECODE_RULES.md`. This is the MobileCode equivalent of a lightweight `CLAUDE.md` / `AGENTS.md`: a portable, user-approved instruction file that can be copied into a project or injected into future planning prompts.

## Memory

Memory is evidence and preference history. It can be learned from chats, repo READMEs, accepted role proposals, failed builds, and repeated user corrections.

Good examples:

- The user often publishes demos under `Harzva/*.github.io`.
- The user's Flutter projects usually use GitHub Actions for release builds.
- The user prefers Role Recruit mode as single-lane role personality orchestration, not parallel agents.

Memory can suggest new Rules, but should not silently become a Rule.

## Approval Flow

1. MobileCode analyzes repos, chat, or task outcomes.
2. It creates `MemoryRuleProposal` or `RuleProposal`.
3. The user can save, edit then save, or ignore.
4. Accepted Rules are injected into future planning prompts.
5. Accepted Memory remains searchable context and can later produce more precise Rule proposals.

## V1 Boundary

For v1, Rules are a product model and release checklist item. They should not execute code. Hooks and MCP servers must remain reviewed and disabled by default unless the user explicitly enables them.
