from pathlib import Path


def main() -> None:
    manifest = Path('android/app/src/main/AndroidManifest.xml')
    text = manifest.read_text()
    text = text.replace('android:label="mobile_agent"', 'android:label="MobileCode"')
    if '<queries>' not in text:
        text = text.replace(
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <uses-permission android:name="android.permission.INTERNET" />\n'
            '    <queries>\n'
            '        <package android:name="com.termux" />\n'
            '        <package android:name="com.termux.api" />\n'
            '        <intent>\n'
            '            <action android:name="android.intent.action.MAIN" />\n'
            '        </intent>\n'
            '    </queries>',
            1,
        )
    if 'android:hardwareAccelerated="true"' not in text:
        text = text.replace(
            '<application',
            '<application\n        android:hardwareAccelerated="true"\n        android:usesCleartextTraffic="true"',
            1,
        )
    manifest.write_text(text)

    gradle = Path('android/app/build.gradle.kts')
    if gradle.exists():
        gradle_text = gradle.read_text()
        gradle_text = gradle_text.replace('minSdk = flutter.minSdkVersion', 'minSdk = 24')
        gradle.write_text(gradle_text)

    launch_background = '''<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@android:color/black" />
</layer-list>
'''
    for launch in (
        Path('android/app/src/main/res/drawable/launch_background.xml'),
        Path('android/app/src/main/res/drawable-v21/launch_background.xml'),
    ):
        launch.parent.mkdir(parents=True, exist_ok=True)
        launch.write_text(launch_background)

    activity = Path('android/app/src/main/kotlin/com/mobilecode/mobile_agent/MainActivity.kt')
    activity.parent.mkdir(parents=True, exist_ok=True)
    activity.write_text(Path('tooling/MainActivity.kt').read_text())


if __name__ == '__main__':
    main()
