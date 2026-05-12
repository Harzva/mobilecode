# MobileCode

MobileCode is an AI coding workspace designed for mobile devices. It combines voice input, screenshot-to-code, agentic development actions, cloud execution, previews, and GitHub workflows into a lightweight mobile-first product.

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
