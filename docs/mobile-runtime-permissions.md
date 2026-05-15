# MobileCode runtime permissions

MobileCode is moving toward a real mobile mini-agent, not a static chat shell. On Android, that means the product must be honest about which layer is currently available.

## Permission model

| Layer | Works in a normal APK | Needs root / bridge |
| --- | --- | --- |
| LLM chat over HTTPS | Yes | No |
| Persistent chat history | Yes, app storage | No |
| WebView preview for generated HTML | Yes | No |
| App-owned project files | Yes | No |
| Microphone speech-to-text prompt input | Yes, `RECORD_AUDIO` permission | No |
| GitHub API test and Pages links | Yes | No |
| Broad filesystem access | Limited by SAF/app sandbox | Root, Shizuku, ADB, or explicit user grant |
| Local shell execution | No direct arbitrary shell | Termux bridge or root |
| Keep Termux backend alive | Not reliable from a normal APK | Root or privileged keepalive service |
| Auto-start local Codex/Claude-style backend | Not reliable from a normal APK | Root / Shizuku / Termux bootstrap |

## Product rule

The chat screen is the first screen. Runtime status must be visible before the user tries an agent task:

- Termux installed or missing
- Termux:API installed or missing
- root available, denied, or unknown
- backend listener ready or missing
- current provider health

When root is unavailable, MobileCode should still be useful: chat, voice prompt input, app-owned file generation, WebView preview, GitHub checks, and release links continue to work. The app should only block shell-backed tools and explain what permission is missing.

## Implementation notes

- `rootProbe` is exposed from Android `MainActivity` through `mobilecode/system_tools`.
- The Flutter UI treats root and Termux as runtime capabilities, not hidden errors.
- Generated preview demos should use app-owned files first, then WebView.
- Termux should be treated as an optional execution backend. If unavailable, show install/setup guidance instead of generic failure.

