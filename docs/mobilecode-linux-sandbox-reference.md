# MobileCode Linux Sandbox Reference

Date: 2026-06-25
Source: local product discussion and screenshots from Termux Toolbox / KAI-style Linux Sandbox UI.

## Why This Note Exists

This note preserves three product references that should inform the next MobileCode runtime direction:

1. A smooth `Open in Termux` action from a command card.
2. A first-run identity prompt that asks the user's name and adapts the assistant's form of address.
3. A one-tap Alpine Linux rootfs download flow that points toward a lightweight, extensible Linux Sandbox instead of full embedded Termux.

The key decision is that MobileCode should not bind its local runtime strategy to Termux. Termux can remain an Android external runtime, while MobileCode builds a cross-platform `LinuxSandboxProvider` abstraction that can use Alpine on Android and iSH-style Linux on iOS.

## Reference 1: Open In Termux

Observed behavior:

- A command card displays a shell command and tags.
- The user taps `Open in Termux`.
- The app jumps into Termux smoothly.

MobileCode implication:

- Add an `Open in Termux` action to command/task cards on Android.
- First version can copy the command to clipboard and open Termux.
- Advanced version can use Termux `RUN_COMMAND` intent when the user has explicitly enabled external command execution in Termux.
- If `RUN_COMMAND` is unavailable or blocked, fall back to `copy command + open Termux`.

This should be treated as a convenience bridge, not as MobileCode's primary runtime.

## Reference 2: Identity And Naming

Observed behavior:

- The assistant asks: "Please tell me your name."
- The user enters a name such as `harzva`.
- Conversation then feels more personal and stateful.

MobileCode implication:

- Add a settings surface for identity preferences:
  - user display name, for example `harzva`;
  - names the user may use to call MobileCode, for example `MobileCode` or `little dog`;
  - optional assistant self-name or persona label;
  - language and tone preference.
- Store the values locally.
- Inject a compact identity block into model context:
  - "The user prefers to be called harzva."
  - "If the user says little dog, they are referring to MobileCode."
  - "Use these names naturally, without overexplaining the setting."

This is a low-cost product improvement with high perceived polish.

## Reference 3: Alpine Linux Sandbox

Observed behavior:

- Settings includes a `Linux Sandbox` tab.
- It offers `Alpine Linux`.
- The app downloads a small rootfs first.
- The interface makes the Linux environment feel opt-in, lightweight, and reversible.

MobileCode implication:

- Replace the idea of "embedded Termux" with a more general `MobileCode Linux Sandbox`.
- Use a minimal rootfs as the first install step.
- Let users install optional package profiles:
  - `Base`: busybox, shell, apk;
  - `Dev Basic`: git, curl, python;
  - `Node Pack`: nodejs, npm;
  - future heavier packs only after explicit opt-in.
- Expose capability flags through `RuntimeProvider`:
  - shell;
  - git;
  - node;
  - python;
  - packageManager;
  - backgroundTask;
  - pty when supported.

The small initial download is not a blocker. It is a product advantage: start tiny, then let the user choose what to add.

## Android Runner Direction

Android has restrictions around executing downloaded app-private binaries on newer target SDKs. Treat this as a runner-design requirement, not a reason to abandon the Linux Sandbox direction.

Preferred architecture:

```text
MobileCode APK
-> bundled or approved native sandbox runner
-> downloaded Alpine rootfs in app-owned storage
-> controlled command/task API
-> RuntimeProvider capability report
-> ActionEvidence and logs
```

Rules:

- Do not expose arbitrary raw shell to the model.
- Use typed tasks first: package install, project check, node version, git version, npm build, etc.
- Keep downloads checksum-verified.
- Keep all state under app-owned storage.
- Make uninstall/reset obvious in Settings.

If KAI-style apps can offer this flow, MobileCode should be able to build a maintainable version, but it should be scoped as a product runtime instead of a copied terminal app.

## iOS Direction

iSH shows that iOS can have a Linux-like userland path, but it is not the same as native Linux. Treat iSH as the iOS reference runtime:

- first step: deep link / open external iSH where possible;
- second step: define an `IshRuntimeProvider` or `LinuxSandboxProvider` iOS adapter;
- later step: evaluate whether an embedded iSH-style engine is acceptable for App Store policy, performance, licensing, and maintenance.

The product goal is one runtime concept across platforms:

```text
Android: Alpine Linux Sandbox / Termux external bridge
iOS: iSH bridge or iSH-style sandbox
MobileCode UI: one Linux Sandbox settings surface
```

## Proposed Roadmap Slice

P0:

- Save this reference note.
- Add `Open in Termux` button with copy-and-open fallback.
- Add identity/naming settings and prompt-context injection.

P1:

- Add `RuntimeProviderType.linuxSandbox`.
- Add Linux Sandbox settings screen skeleton.
- Add Alpine rootfs manifest model: version, URL, sha256, installed size, status.
- Implement download/progress/reset UI.

P2:

- Implement Android runner proof:
  - boot Alpine rootfs;
  - run `apk --version`;
  - install or detect `git`;
  - install or detect `nodejs` and `npm`;
  - report capability evidence.

P3:

- Add iSH bridge proof on iOS.
- Decide whether embedded iSH-style runtime is feasible and policy-safe.

## Product Truth

MobileCode should become:

```text
WebViewOnly for instant previews
MobileCode Helper for controlled local tasks
Linux Sandbox for lightweight local development
Termux for Android external power-user workflows
iSH for iOS external or embedded Linux-like workflows
Cloud Runtime for heavy builds and release tasks
```

This is a stronger product direction than full embedded Termux.
