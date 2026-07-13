# MobileCode iOS Linux-like Runtime Research

Date: 2026-06-25

## Scope

This note records the current iOS Linux-like runtime research boundary for
MobileCode. It does not mark an iOS runtime as implemented.

## Sources Checked

- iSH official site: https://ish.app/
- iSH GitHub repository: https://github.com/ish-app/ish
- iSH App Store listing: https://apps.apple.com/us/app/ish-shell/id1436902243

## Findings

- iSH is a Linux-like shell for iOS. Its official description says it provides a
  local Linux shell environment on iOS using usermode x86 emulation and syscall
  translation.
- The App Store listing describes iSH as a Linux-like shell where users can edit
  and move files. It is a separate iPhone/iPad app, not a MobileCode embedded
  runtime.
- iSH is useful as an external research/fallback candidate, but it is not proof
  that MobileCode can execute an embedded Linux Sandbox on iOS.
- No product commitment should be made until MobileCode verifies launch/handoff
  behavior, file import/export, shortcut integration, clipboard behavior,
  performance, package installation, and user authorization boundaries on a real
  iOS device.

## Product Boundary

- Do not expose iSH as the default MobileCode runtime.
- Do not count iSH handoff as completing MobileCode Linux Sandbox.
- If an iSH bridge is later added, label it as an external fallback until a
  dedicated `IshRuntimeProvider` or iOS adapter passes QA.
- Do not pass secrets, raw chat logs, `.env` files, cookies, or tokens through
  clipboard, screenshots, public evidence, or handoff URLs.

## QA Required Before Any iOS Adapter

- Verify whether a supported URL scheme or Shortcuts action can launch iSH in a
  predictable way.
- Verify file import/export with a non-sensitive fixture project.
- Verify `apk --version`, `git --version`, `node --version`, and
  `npm --version` inside iSH.
- Record iOS version, device model, iSH version, install source, package list,
  elapsed time, and failures.
- Confirm that MobileCode can recover gracefully when iSH is not installed,
  unavailable, or returns no usable result.
