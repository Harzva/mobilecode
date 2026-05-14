# MobileCode Mobile Platform Testing

This project is tested through GitHub Actions because the local Windows workstation does not have Flutter, Android SDK tools, or Xcode simulators installed.

## Android

Workflow: `.github/workflows/android-app-test.yml`

Checks:

- Recreates the Android Flutter platform project from source.
- Applies MobileCode Android bridge customizations from `mobile_agent/tooling/prepare_android_project.py`.
- Runs `flutter analyze` on the app entry surfaces.
- Builds a debug APK.
- Installs the APK on an Android emulator.
- Launches `com.mobilecode.mobile_agent`.
- Captures a smoke-test screenshot and logcat.
- Fails on common runtime crash signatures such as `FATAL EXCEPTION`, `AndroidRuntime`, `NoSuchMethodError`, or `MissingPluginException`.

Release APK workflow: `.github/workflows/android-apk.yml`

- Builds the release APK.
- Injects the managed debug provider only from GitHub Secret `MOBILECODE_MANAGED_API_KEY`.
- Uploads `mobilecode-v0.1.0.apk` to the GitHub Release.

## iOS

Workflow: `.github/workflows/ios-simulator.yml`

Checks:

- Runs on a macOS GitHub runner with Xcode.
- Recreates the iOS Flutter platform project from source.
- Runs `flutter analyze` on the app entry surfaces.
- Builds a debug iOS Simulator `.app`.
- Installs and launches the app on an available iPhone simulator.
- Captures a simulator screenshot and Runner logs.
- Uploads `mobilecode-ios-simulator-v0.1.0.zip` to the GitHub Release.

This is an iOS Simulator build, not a signed App Store IPA. A physical-device IPA requires an Apple Developer team, signing certificate, provisioning profile, and an export options plist.

## Local Plugin Findings

- Build iOS Apps / XcodeBuildMCP was available, but the local machine had no Xcode defaults configured.
- `xcrun` was missing locally, so iOS simulator testing must run on macOS CI.
- Android SDK tools such as `adb` were missing locally, so Android device testing must run on emulator CI.
