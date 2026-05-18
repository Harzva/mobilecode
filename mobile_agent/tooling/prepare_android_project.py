from pathlib import Path


def ensure_manifest_line(text: str, line: str) -> str:
    if line in text:
        return text
    return text.replace(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n' + line,
        1,
    )


def ensure_application_child(text: str, block: str, marker: str) -> str:
    if marker in text:
        return text
    return text.replace('    </application>', block + '\n    </application>', 1)


def main() -> None:
    manifest = Path('android/app/src/main/AndroidManifest.xml')
    text = manifest.read_text()
    text = text.replace('android:label="mobile_agent"', 'android:label="MobileCode"')
    for permission in (
        '    <uses-permission android:name="android.permission.INTERNET" />',
        '    <uses-permission android:name="android.permission.RECORD_AUDIO" />',
        '    <uses-permission android:name="android.permission.VIBRATE" />',
        '    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />',
        '    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />',
        '    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />',
    ):
        text = ensure_manifest_line(text, permission)
    if '<queries>' not in text:
        text = text.replace(
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <queries>\n'
            '        <package android:name="com.termux" />\n'
            '        <package android:name="com.termux.api" />\n'
            '        <intent>\n'
            '            <action android:name="android.intent.action.MAIN" />\n'
            '        </intent>\n'
            '        <intent>\n'
            '            <action android:name="android.speech.RecognitionService" />\n'
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
    helper_service = (
        '        <service\n'
        '            android:name=".MobileCodeHelperService"\n'
        '            android:foregroundServiceType="dataSync"\n'
        '            android:exported="false" />'
    )
    text = ensure_application_child(text, helper_service, 'android:name=".MobileCodeHelperService"')
    helper_launcher = (
        '        <activity\n'
        '            android:name=".MobileCodeHelperLauncherActivity"\n'
        '            android:exported="true"\n'
        '            android:permission="android.permission.DUMP"\n'
        '            android:theme="@android:style/Theme.NoDisplay" />'
    )
    text = ensure_application_child(text, helper_launcher, 'android:name=".MobileCodeHelperLauncherActivity"')
    impeller_opt_out = (
        '        <meta-data\n'
        '            android:name="io.flutter.embedding.android.EnableImpeller"\n'
        '            android:value="false" />'
    )
    text = ensure_application_child(text, impeller_opt_out, 'io.flutter.embedding.android.EnableImpeller')
    manifest.write_text(text)

    gradle = Path('android/app/build.gradle.kts')
    if gradle.exists():
        gradle_text = gradle.read_text()
        gradle_text = gradle_text.replace('minSdk = flutter.minSdkVersion', 'minSdk = 24')
        if 'import java.util.Properties' not in gradle_text:
            gradle_text = (
                'import java.util.Properties\n\n'
                'val keystorePropertiesFile = rootProject.file("key.properties")\n'
                'val keystoreProperties = Properties().apply {\n'
                '    if (keystorePropertiesFile.exists()) {\n'
                '        keystorePropertiesFile.inputStream().use { load(it) }\n'
                '    }\n'
                '}\n\n'
                + gradle_text
            )
        if 'create("release")' not in gradle_text:
            signing_block = (
                '    signingConfigs {\n'
                '        create("release") {\n'
                '            if (keystorePropertiesFile.exists()) {\n'
                '                keyAlias = keystoreProperties["keyAlias"] as String\n'
                '                keyPassword = keystoreProperties["keyPassword"] as String\n'
                '                storeFile = file(keystoreProperties["storeFile"] as String)\n'
                '                storePassword = keystoreProperties["storePassword"] as String\n'
                '            }\n'
                '        }\n'
                '    }\n\n'
            )
            gradle_text = gradle_text.replace('    buildTypes {\n', signing_block + '    buildTypes {\n', 1)
            gradle_text = gradle_text.replace(
                'signingConfig = signingConfigs.getByName("debug")',
                'signingConfig = if (keystorePropertiesFile.exists()) {\n'
                '                signingConfigs.getByName("release")\n'
                '            } else {\n'
                '                signingConfigs.getByName("debug")\n'
                '            }',
                1,
            )
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
    helper_service = Path('android/app/src/main/kotlin/com/mobilecode/mobile_agent/MobileCodeHelperService.kt')
    helper_service.write_text(Path('tooling/MobileCodeHelperService.kt').read_text())
    helper_launcher = Path('android/app/src/main/kotlin/com/mobilecode/mobile_agent/MobileCodeHelperLauncherActivity.kt')
    helper_launcher.write_text(Path('tooling/MobileCodeHelperLauncherActivity.kt').read_text())


if __name__ == '__main__':
    main()
