# MobileCode Mobile Roles And Extension Management

## Purpose

MobileCode should use roles only when they change execution behavior, evidence requirements, or safety boundaries. Roles are not decorative personas; they route mobile work to the right checks.

## V1 Role Set

| Role | Trigger | Output Contract | Completion Gate |
| --- | --- | --- | --- |
| `mobile-ui-designer` | Chat/UI/navigation changes, generated app screens, screenshot-to-code | Mobile layout, responsive states, touch targets, empty/loading/error states | Screenshot or emulator evidence shows the UI is usable on phone width |
| `web-preview-engineer` | HTML/CSS/JS artifact generation and WebView/browser preview | Self-contained HTML, local WebView path, external browser path, failure fallback | User can open code, WebView preview, browser preview, and copy the phone file path |
| `android-runtime-engineer` | Helper, Termux fallback, permissions, APK install/build | RuntimeProvider-safe action, health state, recovery suggestion | Runtime status explains the active backend and does not expose arbitrary shell by default |
| `release-qa-reviewer` | Version bump, APK artifact, CI, smoke test, release docs | Version line, build number, CI links, artifact hash, manual QA checklist | Exact release commit has Mobile Runtime CI, Android APK build, and Android smoke evidence |
| `extension-manager` | Skills, MCP, agents, hooks, memory, marketplace/import | Management entry point, enable/disable state, provenance, permission summary | User can find and inspect extension state without leaving the mobile app |

## Future Role Progress Cards

This is a TODO, not a v1 implementation requirement. The current app still runs a single visible agent trace; do not add multi-agent orchestration just for decoration.

When MobileCode later supports role-routed or multi-agent execution, show progress as compact role cards under the task trace:

- Each role card shows avatar, role name, assigned step, status, and a short progress meter.
- Cards are evidence-backed: a role appears only when that role owns a real action or review gate.
- The first visible polish already reuses copied local avatar assets under `mobile_agent/assets/role_avatars/`, sourced from `D:\study\code\0ai\产品\14-personal_knowledgebase\svg`.
- SVG/animated avatars are visual identity only; execution state must still come from task IDs, step status, logs, and review results.
- Keep this deferred until the single-agent trace, result card, GitHub Pages publish flow, and release QA are stable.

## Routing Rules

- Use `mobile-ui-designer` before changing Home, chat, drawer, settings, generated app cards, or preview layout.
- Use `web-preview-engineer` before accepting generated web artifacts as complete.
- Use `android-runtime-engineer` before exposing anything that runs commands, reads app-private files, opens Termux, or depends on Helper.
- Use `release-qa-reviewer` every time `pubspec.yaml` version changes.
- Use `extension-manager` for Skill, MCP, Agent, Hook, and Memory surfaces.

## Extension Management Stop Line

V1 should expose management surfaces, not build a full plugin marketplace.

Required for V1:

- Skill Manager entry.
- MCP Manager entry.
- Agent Manager entry.
- Memory Manager entry.
- Hook Registry read-only entry with hook point, owner, enabled state, and safety level.
- GitHub repository import for skill packages, with manifest preview before installation.
- MCP server registration from reviewed configuration only; registry discovery must not auto-run commands.
- Default installed HTML/UI skills can be disabled or uninstalled by the user; their built-in state must persist across restarts.

## Built-In HTML Skill Line

MobileCode's current primary artifact is HTML, so the most useful public skill ideas should become product-native defaults instead of only optional external packages.

Default installed built-ins:

| Skill | Internalized Advantage | Provenance |
| --- | --- | --- |
| `frontend_design` | Strong visual direction, typography, color, layout, and non-generic UI review | `https://github.com/anthropics/skills` |
| `ui_ux_pro_max` | Mobile UX flow, information hierarchy, and complete UI states | `https://github.com/nextlevelbuilder/ui-ux-pro-max-skill` |
| `shadcn_ui` | Owned component patterns, variants, dialogs, forms, and registry thinking | `https://github.com/giuseppe-trisciuoglio/developer-kit` |
| `stitch_html_design` | Prompt-to-interface structure and high-fidelity HTML screen generation | `https://github.com/google-labs-code/stitch-skills` |
| `web_accessibility` | Semantic HTML, focus order, contrast, labels, and reduced-motion defaults | `https://github.com/supercent-io/skills-template` |
| `web_design_guidelines` | Responsive composition, deployable web quality, and performance-aware UI | `https://github.com/vercel-labs/agent-skills` |
| `ui_animation` | CSS-first motion, micro-interactions, and reduced-motion fallback | `https://github.com/mblode/agent-skills` |
| `figma_implement_design` | Design-context extraction, token translation, visual parity discipline | `https://github.com/figma/mcp-server-guide` |
| `tailwind_design_system` | Tokenized spacing, typography, color, and reusable design-system rules | `https://github.com/wshobson/agents` |

## External Registry Direction

SkillHub and MCPHub can be useful discovery sources, but MobileCode should treat them as source adapters, not trusted execution backends.

V1 integration contract:

- SkillHub adapter: search/discover skills, resolve the selected item to a GitHub repository URL, then reuse the existing GitHub import and preview flow.
- MCPHub adapter: discover MCP server metadata, show command/transport/env requirements, then register the server disabled by default until the user explicitly enables it.
- GitHub repository import remains the common install path because it gives MobileCode a stable provenance URL, reviewable manifest, and update source.
- No marketplace result may install dependencies, start a server, write hooks, or run scripts without a separate runtime permission gate.

The Tools control center should expose the real Agent, Skill, MCP, Memory, and Hook surfaces directly. Placeholder sheets are allowed only when the target surface cannot compile or is intentionally deferred.

## Hook Registry V1

The Hook Registry is intentionally read-only in v1. It shows lifecycle hook points such as `chat.before_model_call`, `runtime.before_execute`, `files.before_write`, and `release.before_publish` with enabled state and safety level.

Not included in v1:

- Arbitrary script execution.
- Remote hook packages.
- Background hook automation.
- User-editable hook chains.

Deferred beyond V1:

- Remote marketplace ranking.
- Third-party code execution without review.
- Full hook scripting runtime.
- Multi-agent background marketplace automation.
