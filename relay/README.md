# MobileCode Token Relay

Minimal backend relay for bundled MobileCode model presets. The Android app can call this relay without embedding provider API keys in the APK, while custom provider settings remain direct and user-owned.

## Endpoint

- `POST /v1/provider`

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
- `MOBILECODE_RELAY_TOKEN` optional bearer token for app-to-relay auth

## Worker Variables

- `MIMO_BASE_URL`, default `https://token-plan-cn.xiaomimimo.com/anthropic`
- `DEEPSEEK_BASE_URL`, default `https://api.deepseek.com/v1`

## Android Build Defines

- `MOBILECODE_MANAGED_RELAY_URL`
- `MOBILECODE_MANAGED_RELAY_TOKEN` optional

Do not commit provider keys or relay tokens.
