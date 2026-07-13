# T26 Subscription Login 与 Usage Hub

Status: [ ] Local Phase 1 implemented; manual credential validation added for GitHub, OpenAI, Anthropic, and Gemini; Copilot/GitHub now reuses existing GitHub auth and has the first ModelRouter forwarding adapter; provider-supported official login and real quota refresh still pending where available
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
- Do not bind provider login to Termux or any external runtime. Login belongs to the built-in app/provider auth surface and secure storage.
- Do not make Termux the product default for model forwarding. The product path is built-in Android Helper APK or provider-native SDK adapters; external daemons are development or advanced fallback only.
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
- [x] Reuse or converge with the existing GitHub auth surface so GitHub app login and Usage Hub account state share one explicit token boundary.
- [x] Add `ProviderLogin -> CredentialVault -> ModelRouter -> ProviderAdapter` chain and route GitHub/Copilot chat requests through a helper-side `copilot_chat` bridge task.
- [x] Make missing Copilot SDK bridge a visible `dependencyMissing` failure instead of silently using mock forwarding.
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
- Copilot/GitHub official login now reuses the existing MobileCode GitHub auth surface: Usage Hub opens/syncs `GitHubScreen` and links the active `GitHubDeepService` secure session as `github_deep_service_secure_storage` instead of duplicating the token in `SubscriptionCredentialVault`.
- `mobile_agent/lib/services/model_provider_adapter_service.dart` defines the forwarding chain:
  `ProviderCredentialResolver` reads provider credentials, `ModelRouter` selects a provider adapter, and `CopilotBridgeModelProviderAdapter` sends chat requests to the helper-side `copilot_chat` task with redacted result metadata.
- The forwarding chain is intentionally split from login: provider login and credential storage do not require Termux or any external runtime. Adapter execution should default to the built-in Android Helper APK or provider-native SDK bindings.
- `mobile_agent/tooling/mobilecode_helper_daemon.py` accepts `copilot_chat` typed tasks as a development bridge while the built-in Helper/provider-native path is being finalized. It requires `MOBILECODE_COPILOT_BRIDGE_CMD` to point at a bridge built on the official GitHub Copilot SDK; this is a model-forwarding runtime boundary, not a login requirement. The GitHub token is passed only as process environment for the bridge process, not written to task payload stdout/stderr or persisted logs by MobileCode.
- ChatGPT/Codex manual API key mode calls OpenAI `/v1/models` with an explicit bearer token and stores the key only after validation succeeds.
- Claude manual API key mode calls Anthropic `/v1/models` with `x-api-key` and `anthropic-version: 2023-06-01`, then stores the key only after validation succeeds.
- Google/Antigravity manual API key mode calls Gemini `models.list` with an explicit key query parameter and stores the key only after validation succeeds.
- `SecureSubscriptionCredentialVault` writes manual credentials through `flutter_secure_storage`; UI and redacted snapshots only expose `stored_in_secure_storage`.
- Non-GitHub official login buttons currently create provider-specific recovery states instead of pretending real provider login is complete.
- `test/services/subscription_usage_service_test.dart` covers provider groups, mock quota, secure credential boundary, redaction, provider-specific recovery, GitHub/OpenAI/Anthropic/Gemini validation success/failure, direct local-server adapter validation, no vault write on failed validation, GitHub existing-session linking without duplicate credential storage, and logout clearing.
- `test/widgets/subscription_usage_hub_screen_test.dart` covers provider tabs/cards, privacy copy, and official-login recovery state.
- Local Mac validation on 2026-06-25 passed focused T25/T26 tests, targeted analyzer gate, debug APK build, APK install, MainActivity launch, and logcat crash-keyword scan.
- Real quota refresh remains pending for all providers; current quota cards still use mock usage until official provider-supported quota sources are confirmed.
- 2026-06-25 GitHub/Copilot validation follow-up passed focused T25/T26/Helper/Runtime tests, targeted analyzer gate, debug APK build, APK install, MainActivity launch, and logcat crash-keyword scan; evidence directory: `mobile_agent/qa-output/android-local-20260625-224116`.
- 2026-06-25 manual API key validation follow-up uses official endpoint boundaries documented by OpenAI, Anthropic, and Google Gemini API docs; browser/OAuth flows and real quota refresh remain pending.
- 2026-06-25 manual credential validation follow-up passed focused T25/T26/Helper/Runtime tests, targeted analyzer gate, debug APK build, APK install, MainActivity launch, and logcat crash-keyword scan; evidence directory: `mobile_agent/qa-output/android-local-20260625-224757`.
- 2026-06-25 official capability review:
  - OpenAI Codex documentation supports ChatGPT sign-in for Codex app/CLI/IDE and API-key sign-in for usage-based access. MobileCode must not claim general third-party ChatGPT subscription OAuth until OpenAI exposes a supported third-party app flow or an explicit token handoff boundary.
  - GitHub Copilot SDK documentation supports GitHub OAuth for users to use Copilot through an application, so MobileCode can reuse its existing GitHub OAuth/PAT auth surface for Usage Hub account state.
  - Google Gemini API documentation supports OAuth when stricter access controls are needed, but a production mobile flow requires Google OAuth client configuration and consent-screen setup before real account login can ship.
  - Anthropic Claude API documentation supports API keys and Workload Identity Federation for API access. Claude consumer account login must remain pending unless Anthropic provides an official third-party app login boundary; cookie/session import is not allowed.
- 2026-06-25 ModelRouter forwarding follow-up passed:
  - `python3 -m py_compile mobile_agent/tooling/mobilecode_helper_daemon.py`
  - `cd mobile_agent && flutter test test/services/model_provider_adapter_service_test.dart test/services/subscription_usage_service_test.dart`
  - `test/services/model_provider_adapter_service_test.dart` covers Copilot helper payload shape, redacted credential metadata, missing bridge failure, and missing credential failure.

## Deferred Provider Adapter Work

- GitHub/Copilot: promote the official Copilot SDK bridge into the built-in Helper APK or provider-native adapter path, then capture real signed-in end-to-end QA evidence. `MOBILECODE_COPILOT_BRIDGE_CMD` remains a development bridge hook, not the product dependency.
- OpenAI/Codex: keep API-key forwarding separate from ChatGPT subscription login. Do not claim ChatGPT subscription model forwarding until OpenAI exposes a supported third-party app handoff for that account surface.
- Google/Antigravity: add OAuth client and consent-screen configuration before replacing manual Gemini API-key mode with account login.
- Claude: support official API-key or Workload Identity Federation boundaries first; do not add consumer cookie/session import.

## Handoff Prompt

请实现 T26。先做 Usage Hub 的 provider/account/quota 模型和 UI，再接真实登录。所有凭据必须走 secure storage，禁止 cookie 抓取和明文日志。参考 AIUsage 的 multi-provider 和 usage-card 信息架构，但不要复制实现、接口或视觉资产。真实 provider 能力在接入前必须重新确认官方支持边界。
