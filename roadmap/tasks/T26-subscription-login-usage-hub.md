# T26 Subscription Login 与 Usage Hub

Status: [ ] Local Phase 1 implemented; manual credential validation added for GitHub, OpenAI, Anthropic, and Gemini; official browser login adapters and real quota refresh pending
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

- [x] Add Settings entry for `订阅账户` / `Usage Hub`.
- [x] Add Usage Hub top-level screen with provider tabs/cards.
- [x] Add local models: `SubscriptionProvider`, `SubscriptionAccount`, `UsageQuota`, `ProviderLoginMethod`.
- [x] Support mock quota cards with usage percent, reset time, refresh status, and error state.
- [x] Store provider account metadata separately from credentials.
- [x] Keep credentials in secure storage only through `SubscriptionCredentialVault`.
- [x] Add tests for model serialization, redaction, and UI empty/error/loading states.

### Phase 2: Real Login and Refresh

- [x] Implement ChatGPT/Codex manual API key validation through OpenAI `/v1/models` before writing to secure storage.
- [ ] Implement ChatGPT/Codex official browser/OAuth-style flow when available.
- [x] Implement GitHub/Copilot manual token validation through GitHub `/user` before writing to secure storage.
- [ ] Reuse or converge with the existing GitHub auth surface so GitHub app login and Usage Hub account state share one explicit token boundary.
- [ ] Implement real Copilot usage refresh after provider-supported quota source is confirmed.
- [x] Implement Google/Antigravity manual Gemini API key validation through Gemini `models.list` before writing to secure storage.
- [ ] Implement Google/Antigravity login using system browser account flow where available.
- [x] Implement Claude manual API key validation through Anthropic `/v1/models` before writing to secure storage.
- [ ] Implement Claude official supported browser/account flow when available; no cookie scraping by default.
- [x] Add provider-specific failure kinds and recovery copy for not-yet-connected official flows.
- [x] Add user-visible last refresh time for local mock refresh; real refresh throttling remains pending provider adapters.
- [x] Ensure logout clears secure storage credentials and leaves redacted evidence.

## Acceptance Criteria

- Usage Hub shows login status, quota cards, refresh status, and error state per provider.
- At least four provider groups are represented: ChatGPT/Codex, GitHub/Copilot, Google/Antigravity, Claude.
- Credentials are stored only through secure storage.
- SharedPreferences, logs, roadmp, screenshots, and evidence do not contain raw credentials.
- Login failure produces provider-specific recovery guidance.
- GitHub/Copilot, ChatGPT/Codex, Google/Antigravity, and Claude manual credential modes validate credentials before storage; failed validation does not write credentials.
- Mock usage and real refresh states are visibly distinct.
- AIUsage references are documented as product references only, not as copied implementation.

## Validation

Local implementation validation:

```bash
cd mobile_agent
flutter analyze lib/screens/settings_screen.dart lib/screens/subscription_usage_hub_screen.dart lib/services/subscription_usage_service.dart --no-fatal-infos --no-fatal-warnings
flutter test test/services/subscription_usage_service_test.dart test/widgets/subscription_usage_hub_screen_test.dart
flutter build apk --debug --target lib/main.dart
```

Additional implementation checks:

```bash
rg -n "apiKey|accessToken|refreshToken|cookie|secret" mobile_agent/lib mobile_agent/test docs qa
rg -n "SharedPreferences.*(token|key|secret|cookie)" mobile_agent/lib mobile_agent/test
git diff --check
```

Manual QA should cover mock state, successful login state, login failure state, refresh failure, logout, and credential redaction in screenshots/logs/evidence.

## Current Implementation Evidence

- `mobile_agent/lib/screens/settings_screen.dart` adds `订阅账户` under AI settings.
- `mobile_agent/lib/screens/subscription_usage_hub_screen.dart` provides provider tabs/cards for Claude, Copilot/GitHub, Antigravity/Google, and Codex/ChatGPT.
- `mobile_agent/lib/services/subscription_usage_service.dart` defines `SubscriptionProvider`, `SubscriptionAccount`, `UsageQuota`, `ProviderLoginMethod`, provider-specific recovery, mock refresh, redacted snapshots, and `SubscriptionCredentialVault`.
- `SubscriptionUsageService` accepts provider login adapters and uses `GitHubSubscriptionLoginAdapter` for `copilotGithub` manual access tokens.
- GitHub/Copilot manual token mode calls GitHub `/user` with an explicit bearer token and stores the token only after validation succeeds.
- ChatGPT/Codex manual API key mode calls OpenAI `/v1/models` with an explicit bearer token and stores the key only after validation succeeds.
- Claude manual API key mode calls Anthropic `/v1/models` with `x-api-key` and `anthropic-version: 2023-06-01`, then stores the key only after validation succeeds.
- Google/Antigravity manual API key mode calls Gemini `models.list` with an explicit key query parameter and stores the key only after validation succeeds.
- `SecureSubscriptionCredentialVault` writes manual credentials through `flutter_secure_storage`; UI and redacted snapshots only expose `stored_in_secure_storage`.
- Official login buttons currently create provider-specific recovery states instead of pretending real provider login is complete.
- `test/services/subscription_usage_service_test.dart` covers provider groups, mock quota, secure credential boundary, redaction, provider-specific recovery, GitHub/OpenAI/Anthropic/Gemini validation success/failure, direct local-server adapter validation, no vault write on failed validation, and logout clearing.
- `test/widgets/subscription_usage_hub_screen_test.dart` covers provider tabs/cards, privacy copy, and official-login recovery state.
- Local Mac validation on 2026-06-25 passed focused T25/T26 tests, targeted analyzer gate, debug APK build, APK install, MainActivity launch, and logcat crash-keyword scan.
- Real quota refresh remains pending for all providers; current quota cards still use mock usage until official provider-supported quota sources are confirmed.
- 2026-06-25 GitHub/Copilot validation follow-up passed focused T25/T26/Helper/Runtime tests, targeted analyzer gate, debug APK build, APK install, MainActivity launch, and logcat crash-keyword scan; evidence directory: `mobile_agent/qa-output/android-local-20260625-224116`.
- 2026-06-25 manual API key validation follow-up uses official endpoint boundaries documented by OpenAI, Anthropic, and Google Gemini API docs; browser/OAuth flows and real quota refresh remain pending.
- 2026-06-25 manual credential validation follow-up passed focused T25/T26/Helper/Runtime tests, targeted analyzer gate, debug APK build, APK install, MainActivity launch, and logcat crash-keyword scan; evidence directory: `mobile_agent/qa-output/android-local-20260625-224757`.

## Handoff Prompt

请实现 T26。先做 Usage Hub 的 provider/account/quota 模型和 UI，再接真实登录。所有凭据必须走 secure storage，禁止 cookie 抓取和明文日志。参考 AIUsage 的 multi-provider 和 usage-card 信息架构，但不要复制实现、接口或视觉资产。真实 provider 能力在接入前必须重新确认官方支持边界。
