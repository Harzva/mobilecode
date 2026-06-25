# T26 Subscription Login 与 Usage Hub

Status: [ ] Planned
Priority: P2
Owner role: software-dev-pipeline + appui-design-skill + quality-reviewer
Depends on: T04, T13, T14, T18, T25

## Objective

建立 MobileCode 的订阅账户与用量中心，支持 Claude、Copilot/GitHub、Antigravity/Google、Codex/ChatGPT 等不同登录方式，并以本地优先、隐私优先的方式展示额度、用量、刷新和错误状态。

## References

- `https://github.com/sylearn/AIUsage`
- `https://aiusage.jtanx.com/`
- `https://github.com/juliantanx/aiusage`

这些参考只用于信息架构：multi-provider、multi-account、本地优先、隐私优先、额度/用量卡片、订阅账户切换。不得复制 UI、品牌资产、私有接口、credential 处理或未授权 cookie 流程。

## Read First

- `roadmp.md`
- `roadmap/tasks/T04-security-model.md`
- `roadmap/tasks/T13-evidence-model.md`
- `roadmap/tasks/T14-approval-queue-audit-log.md`
- `roadmap/tasks/T18-collaboration-actions.md`
- `mobile_agent/lib/screens/settings_screen.dart`
- `mobile_agent/lib/screens/api_config_screen.dart`
- `mobile_agent/lib/services/secure_storage_service.dart`
- `mobile_agent/lib/services/llm_service.dart`
- `mobile_agent/android/app/src/main/AndroidManifest.xml`

## Can Edit

- new subscription/account modules under `mobile_agent/lib/modules/` or `mobile_agent/lib/services/`
- new Usage Hub screen and settings entry
- routing/navigation for the Usage Hub
- secure storage wrappers for provider credentials
- provider-specific login adapters
- tests for subscription models, login state, secure storage boundaries, and UI states
- docs or QA templates for subscription login evidence
- `roadmp.md`
- this task file

## Do Not Edit

- Do not store credentials in `SharedPreferences`, logs, screenshots, roadmap files, or plain evidence.
- Do not scrape browser cookies or import session files without explicit user action and a documented provider boundary.
- Do not silently switch active providers or mutate Codex/Claude/GitHub configs without preview and user confirmation.
- Do not claim real quota accuracy until provider-specific refresh has verified evidence.
- Do not copy AIUsage implementation details or assets.

## Scope

- Build a unified Usage Hub for provider login state and quota cards.
- Support at least four provider groups: `Claude`, `Copilot/GitHub`, `Antigravity/Google`, `Codex/ChatGPT`.
- Define common interfaces: `SubscriptionProvider`, `SubscriptionAccount`, `UsageQuota`, `ProviderLoginMethod`.
- Phase 1 provides UI, local state model, secure storage boundary, and mock usage.
- Phase 2 provides real login adapters and provider-specific refresh behavior.

## Out of Scope

- Paid billing, purchasing, subscription management, or plan upgrades.
- Background scraping of private dashboards.
- Enterprise SSO policy bypass.
- Cloud sync of credentials.
- Global proxy rewriting unless a separate task approves it.

## Implementation Tasks

### Phase 1: Usage Hub UI and Local Model

- [ ] Add Settings entry for `订阅账户` or `Usage Hub`.
- [ ] Add Usage Hub top-level screen with provider tabs/cards.
- [ ] Add local models: `SubscriptionProvider`, `SubscriptionAccount`, `UsageQuota`, `ProviderLoginMethod`.
- [ ] Support mock quota cards with usage percent, reset time, refresh status, and error state.
- [ ] Store provider account metadata separately from credentials.
- [ ] Keep credentials in secure storage only.
- [ ] Add tests for model serialization, redaction, and UI empty/error/loading states.

### Phase 2: Real Login and Refresh

- [ ] Implement ChatGPT/Codex login using official browser/OAuth-style flow when available; otherwise document manual token/API-key mode behind explicit consent.
- [ ] Implement GitHub/Copilot login via existing GitHub auth surface or a shared GitHub token boundary.
- [ ] Implement Google/Antigravity login using system browser account flow where available.
- [ ] Implement Claude login using official supported flow or manual API key mode; no cookie scraping by default.
- [ ] Add provider-specific failure kinds and recovery copy.
- [ ] Add refresh throttling, user-visible last refresh time, and no-silent-failure behavior.
- [ ] Ensure logout clears secure storage credentials and leaves redacted evidence.

## Acceptance Criteria

- Usage Hub shows login status, quota cards, refresh status, and error state per provider.
- At least four provider groups are represented: ChatGPT/Codex, GitHub/Copilot, Google/Antigravity, Claude.
- Credentials are stored only through secure storage.
- SharedPreferences, logs, roadmp, screenshots, and evidence do not contain raw credentials.
- Login failure produces provider-specific recovery guidance.
- Mock usage and real refresh states are visibly distinct.
- AIUsage references are documented as product references only, not as copied implementation.

## Validation

Roadmap-only update does not run these. Implementation should run:

```bash
cd mobile_agent
flutter analyze
flutter test
```

Additional implementation checks:

```bash
rg -n "apiKey|accessToken|refreshToken|cookie|secret" mobile_agent/lib mobile_agent/test docs qa
rg -n "SharedPreferences.*(token|key|secret|cookie)" mobile_agent/lib mobile_agent/test
git diff --check
```

Manual QA should cover mock state, successful login state, login failure state, refresh failure, logout, and credential redaction in screenshots/logs/evidence.

## Handoff Prompt

请实现 T26。先做 Usage Hub 的 provider/account/quota 模型和 UI，再接真实登录。所有凭据必须走 secure storage，禁止 cookie 抓取和明文日志。参考 AIUsage 的 multi-provider 和 usage-card 信息架构，但不要复制实现、接口或视觉资产。真实 provider 能力在接入前必须重新确认官方支持边界。
