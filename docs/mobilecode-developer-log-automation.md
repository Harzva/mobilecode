# MobileCode Developer Log Automation

MobileCode developer logs are updated by a local Git hook, then deployed by GitHub Pages. This hook is intentionally scoped to this MobileCode repository only.

## One-time setup

Run this once in each clone:

```bash
scripts/setup_git_hooks.sh
```

That sets `core.hooksPath=.githooks` in this repository's local Git config. It does not use `--global` and does not affect other repositories on the machine.

## Commit-time behavior

After each normal commit, `.githooks/post-commit`:

- generates an important-change log for the commit that just landed;
- refreshes the daily log and JSON/HTML indexes;
- tries to capture a Pages-ready screenshot into `docs/devlog/screenshots/`;
- creates a follow-up `Update developer logs` commit.

The hook skips recursive developer-log commits automatically.

## Screenshot controls

Screenshots are attempted by default when Chrome/Chromium, npm dependencies, and the Pages build are available locally. The hook never blocks a commit just because screenshot capture is unavailable.

- Disable screenshots: `MOBILECODE_DEVLOG_SCREENSHOT=0 git commit ...`
- Install missing npm dependencies automatically: `MOBILECODE_DEVLOG_INSTALL_DEPS=1 git commit ...`
- Require screenshot success: `MOBILECODE_DEVLOG_SCREENSHOT_STRICT=1 git commit ...`

## CI behavior

`.github/workflows/devlog.yml` does not commit generated files anymore. On push to `main`, it builds the Pages site, verifies the committed devlog screenshot exists, attaches the committed devlog files, and deploys GitHub Pages.
