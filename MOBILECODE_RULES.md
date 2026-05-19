# MobileCode Rules

This file is the product-level rules surface for MobileCode.

Rules are not the same as Memory:

- Rules are explicit, stable, user-approved operating instructions.
- Memory is evidence, preferences, repo insights, and proposal history.
- Memory can suggest a Rule, but it should not silently become a Rule.

## Active Product Rules

- Keep MobileCode as a phone-native coding harness. The product should make it clear that the harness runs on the mobile device, while GitHub, Termux, Helper, or cloud are optional execution backends.
- Prefer lightweight mobile loops: generate, preview, inspect, publish, and recover on the phone.
- Use GitHub Pages for simple HTML publishing and GitHub Actions for heavy APK or release builds when local runtime is not ready.
- Do not execute Hook or MCP scripts without explicit user review and confirmation.
- Treat Skill and MCP installs as reviewed imports: show provenance, manifest, permissions, and risk before installation.
- Keep Role Recruit as a single execution lane with role personalities unless true multi-agent execution is explicitly implemented.

## Prompt Injection Boundary

Future prompt builders may inject approved Rules as high-priority context. They should keep Memory as lower-priority supporting evidence and must keep user secrets, tokens, and private source code out of model prompts unless the user explicitly approves.
