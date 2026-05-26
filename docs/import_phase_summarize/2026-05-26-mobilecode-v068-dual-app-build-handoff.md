# MobileCode v0.1.68 Dual App Build Handoff

Date: 2026-05-26

## Baseline

- Work branch: `last-recover-v068-work`
- Base: `origin/last-recover-from-v039`
- Base commit used for the continuation worktree: `32ffd83a0c01d29d0dcce8b71d042a207ae9ff24`
- Do not switch this workline to `last` or `main`.

## Product Changes

- Runtime task detail now has separate copy actions for task summary and failure summary.
- `preview_snapshot` evidence now explicitly reports metadata-only capture:
  - `status: metadata_captured`
  - `captureMode: metadata`
  - `artifactType: json`
  - `bitmapCaptured: false`
- A native bitmap screenshot must not be claimed unless a real image artifact and `bitmapPath` are produced.

## Build Changes

New unified workflow:

- `.github/workflows/mobile-app-release.yml`

Expected artifacts for `release_tag=v0.1.68-last`:

- `mobilecode-v0.1.68-last.apk`
- `mobilecode-ios-simulator-v0.1.68-last.zip`
- `mobilecode-ios-smoke.png`
- `ios-runner.log`
- `mobilecode-ios-archive-v0.1.68-last.xcarchive.zip`
- `ios-archive-summary.txt`

The iOS archive is unsigned by default. Producing a signed `.ipa` is a separate signing task that requires Apple certificate, provisioning profile, team ID, and GitHub Secrets.

## Local Validation

Completed locally:

- `git diff --check`
- `node --check relay/mobilecode-token-relay-worker.js`
- `python -c "import yaml ..."` against `.github/workflows/mobile-app-release.yml`

Known local limitation:

- `flutter` and `dart` are not available in local PATH. Flutter analyze/test/build must be verified by GitHub Actions.

## GitHub Validation Required

After pushing the branch/tag, verify:

- `Mobile Runtime CI` passes.
- `Build Mobile Apps` passes.
- The GitHub Release for `v0.1.68-last` contains both Android and iOS app artifacts.
- The iOS simulator artifact includes a smoke screenshot and runner log with no crash signature.
