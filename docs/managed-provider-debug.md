# MobileCode Managed Provider Debug Mode

Managed provider mode lets an internal debug build call a preconfigured provider without showing Base URL, model, or API key in the app UI.

Do not commit provider keys to source code and do not ship managed keys in public GitHub Releases. A key compiled into an APK can still be extracted from the package, even when the UI hides it.

## Build

Use private/local builds only:

```bash
flutter build apk --release \
  --target lib/main.dart \
  --dart-define=MOBILECODE_MANAGED_PROVIDER=true \
  --dart-define=MOBILECODE_MANAGED_BASE_URL=https://token-plan-cn.xiaomimimo.com/anthropic \
  --dart-define=MOBILECODE_MANAGED_MODEL=mimo-v2.5-pro \
  --dart-define=MOBILECODE_MANAGED_API_KEY=REPLACE_WITH_PRIVATE_DEBUG_KEY
```

When `MOBILECODE_MANAGED_PROVIDER=true` and `MOBILECODE_MANAGED_API_KEY` is non-empty, the APK uses the managed provider internally. The API configuration panel shows only a managed-provider status and a health-check button.

The GitHub Actions APK workflow can inject this mode from repository secret `MOBILECODE_MANAGED_API_KEY`. This keeps the key out of source control and build logs, but the resulting APK should still be treated as a private/debug artifact because compiled client secrets are extractable.

## Production Direction

For a public APK, prefer a server-side proxy:

- Store provider keys only on the server.
- Add app/device authorization, rate limits, usage logs, and revocation.
- Return short-lived tokens or proxy requests directly.
- Keep the public APK free of provider secrets.
