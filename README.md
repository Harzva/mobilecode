<p align="center">
  <img src="app/public/showcase/mobilecode-icon-v2.svg" alt="MobileCode app icon" width="160" />
</p>

<h1 align="center">MobileCode</h1>

<p align="center">
  <strong>手机端 AI 编程工作台 / Mobile-first AI coding workspace.</strong>
</p>

<p align="center">
  <a href="https://harzva.github.io/mobilecode/">GitHub Pages</a>
  ·
  <a href="https://github.com/Harzva/mobilecode/releases/tag/v0.1.0">Release v0.1.0</a>
  ·
  <a href="roadmp.md">Roadmap</a>
  ·
  <a href="docs/mobilecode-capability-matrix.md">Capability Matrix</a>
</p>

MobileCode is an AI coding workspace designed for mobile devices. The current repository includes a promotional site, a Flutter mobile app preview, a RuntimeManager/Helper runtime baseline, and release QA evidence; cloud execution and GitHub workflow automation are planned capabilities tracked in the governance docs.

## Visual Preview

The public visual assets are curated from `reference_ui/local_dialog_all_images_svgs_final_pack/` into `app/public/showcase/`. They are used as brand and promotional design references, not as a substitute for runtime APK screenshots.

<p align="center">
  <img src="app/public/showcase/mobilecode-code-with-your-buddy.png" alt="MobileCode CodeLoong promotional poster" width="860" />
</p>

| Brand system | Wordmark |
|---|---|
| <img src="app/public/showcase/mobilecode-brand-identity-sheet.png" alt="MobileCode CodeLoong brand identity sheet" width="420" /> | <img src="app/public/showcase/mobilecode-mascot-wordmark.png" alt="MobileCode CodeLoong mascot wordmark" width="420" /> |

## Repository Structure

- `app/` - React/Vite promotional site for the product.
- `mobile_agent/` - Flutter source modules for the mobile app preview.
- `*.md` - planning, security, roadmap, and product analysis notes.

## Current Completeness

The promotional site is ready to build and publish. The Flutter app has a broad set of Dart screens, services, providers, and tests, but it is not yet a complete packaged mobile product in this checkout because the local machine has no Flutter SDK, the `ios/` project is missing, and the Android folder does not include the full Gradle wrapper/root project files.

## Build

```bash
cd app
npm install
npm run build
```

Android/iOS packages should be generated after restoring the Flutter platform scaffolding:

```bash
cd mobile_agent
flutter pub get
flutter create --platforms=android,ios .
flutter build apk --release
flutter build appbundle --release
flutter build ipa --release
```

The iOS build requires macOS, Xcode, and valid signing credentials.

## Release Notes

Version `v0.1.0` publishes the product site, source preview, and a real Android APK built from `mobile_agent/lib/main.dart` through GitHub Actions.

The iOS build still requires macOS, Xcode, and signing credentials.

## Governance

- [Roadmap](roadmp.md) — task index and execution order.
- [Capability Matrix](docs/mobilecode-capability-matrix.md) — what works today, what is blocked, what is coming.
- [Risk Register](docs/mobilecode-risk-register.md) — known risks, mitigations, and stop lines.
- [Security Model](docs/mobilecode-security-model.md) — trust boundaries, token policy, workspace policy, command policy.
- [Release QA](docs/mobilecode-release-qa.md) — CI gates, manual verification, artifact download paths.
- [Version Policy](docs/mobilecode-version-policy.md) — version numbering and stop rules.
- [UI Showcase Assets](docs/mobilecode-ui-showcase-assets.md) — curated README/GitHub Pages visual asset index.
- [T00-T23 Closure](docs/mobilecode-t00-t23-closure.md) — first roadmap tranche closure evidence and residual risks.

## Contributing

- [Contributor Onboarding](docs/mobilecode-contributor-onboarding.md) — setup, constraints, and how to get started.
- [Good First Issues](docs/mobilecode-good-first-issues.md) — starter tasks for new contributors.
- [Issue Templates](.github/ISSUE_TEMPLATE/) — bug, feature, runtime bug, GitRuntime bug, release blocker, docs feedback.
