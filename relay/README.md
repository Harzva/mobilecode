# MobileCode Token Relay

Minimal backend relay for bundled MobileCode model presets. The Android app can call this relay without embedding provider API keys in the APK, while custom provider settings remain direct and user-owned.

## Endpoint

- `POST /v1/provider`
- `POST /v1/tools/web_search`
- `POST /v1/tools/fetch_url`

Request envelope:

```json
{
  "provider": "mimo",
  "flavor": "anthropic",
  "body": {
    "model": "mimo-v2.5-pro",
    "messages": []
  }
}
```

## Worker Secrets

- `MIMO_API_KEY`
- `DEEPSEEK_API_KEY`
- `TAVILY_API_KEY` optional, preferred web search backend
- `BING_SEARCH_API_KEY` optional, fallback web search backend
- `MOBILECODE_RELAY_TOKEN` optional bearer token for app-to-relay auth

## Worker Variables

- `MIMO_BASE_URL`, default `https://token-plan-cn.xiaomimimo.com/anthropic`
- `DEEPSEEK_BASE_URL`, default `https://api.deepseek.com/v1`
- `BING_SEARCH_ENDPOINT`, default `https://api.bing.microsoft.com/v7.0/search`

If no Tavily or Bing key is configured, `web_search` falls back to DuckDuckGo's public instant-answer API. That fallback is useful for smoke tests but may return fewer normal web results.

## Android Build Defines

- `MOBILECODE_MANAGED_RELAY_URL`
- `MOBILECODE_MANAGED_RELAY_TOKEN` optional

Do not commit provider keys or relay tokens.
