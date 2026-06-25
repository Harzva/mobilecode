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


def ensure_application_attribute(text: str, attribute: str, value: str) -> str:
    if f'{attribute}=' in text:
        return text
    return text.replace('<application', f'<application\n        {attribute}="{value}"', 1)


def main() -> None:
    manifest = Path('android/app/src/main/AndroidManifest.xml')
    text = manifest.read_text()
    text = text.replace('android:label="mobile_agent"', 'android:label="MobileCode"')
    text = text.replace('android:icon="@mipmap/ic_launcher"', 'android:icon="@drawable/mobilecode_launcher"')
    if 'android:roundIcon=' not in text:
        text = text.replace(
            'android:icon="@drawable/mobilecode_launcher"',
            'android:icon="@drawable/mobilecode_launcher"\n        android:roundIcon="@drawable/mobilecode_launcher"',
            1,
        )
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
    text = ensure_application_attribute(text, 'android:usesCleartextTraffic', 'false')
    text = ensure_application_attribute(text, 'android:networkSecurityConfig', '@xml/network_security_config')
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
    phone_use_service = (
        '        <service\n'
        '            android:name=".PhoneUseAccessibilityService"\n'
        '            android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE"\n'
        '            android:exported="true">\n'
        '            <intent-filter>\n'
        '                <action android:name="android.accessibilityservice.AccessibilityService" />\n'
        '            </intent-filter>\n'
        '            <meta-data\n'
        '                android:name="android.accessibilityservice"\n'
        '                android:resource="@xml/mobilecode_phone_use_accessibility_service" />\n'
        '        </service>'
    )
    text = ensure_application_child(text, phone_use_service, 'android:name=".PhoneUseAccessibilityService"')
    if 'android:scheme="mobilecode"' not in text:
        oauth_filter = (
            '            <intent-filter>\n'
            '                <action android:name="android.intent.action.VIEW"/>\n'
            '                <category android:name="android.intent.category.DEFAULT"/>\n'
            '                <category android:name="android.intent.category.BROWSABLE"/>\n'
            '                <data\n'
            '                    android:scheme="mobilecode"\n'
            '                    android:host="github"\n'
            '                    android:pathPrefix="/oauth" />\n'
            '            </intent-filter>'
        )
        text = text.replace('            </intent-filter>\n        </activity>', '            </intent-filter>\n' + oauth_filter + '\n        </activity>', 1)
    if 'application/octet-stream' not in text:
        shared_file_filters = (
            '            <intent-filter>\n'
            '                <action android:name="android.intent.action.VIEW"/>\n'
            '                <category android:name="android.intent.category.DEFAULT"/>\n'
            '                <data android:scheme="content"/>\n'
            '                <data android:scheme="file"/>\n'
            '                <data android:mimeType="text/*"/>\n'
            '                <data android:mimeType="application/xhtml+xml"/>\n'
            '                <data android:mimeType="application/xml"/>\n'
            '                <data android:mimeType="application/json"/>\n'
            '                <data android:mimeType="application/octet-stream"/>\n'
            '            </intent-filter>\n'
            '            <intent-filter>\n'
            '                <action android:name="android.intent.action.SEND"/>\n'
            '                <category android:name="android.intent.category.DEFAULT"/>\n'
            '                <data android:mimeType="text/*"/>\n'
            '                <data android:mimeType="application/xhtml+xml"/>\n'
            '                <data android:mimeType="application/xml"/>\n'
            '                <data android:mimeType="application/json"/>\n'
            '                <data android:mimeType="application/octet-stream"/>\n'
            '            </intent-filter>'
        )
        text = text.replace('            </intent-filter>\n        </activity>', '            </intent-filter>\n' + shared_file_filters + '\n        </activity>', 1)
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

    launcher_icon = '''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path
        android:fillColor="#061022"
        android:pathData="M0,0h108v108h-108z" />
    <path
        android:fillColor="#0B1B35"
        android:pathData="M23,18H85V90H23Z" />
    <path
        android:fillColor="#2DE2C5"
        android:pathData="M45,37L28,54l17,17l8,-8l-9,-9l9,-9z" />
    <path
        android:fillColor="#6C7CFF"
        android:pathData="M63,37l17,17l-17,17l-8,-8l9,-9l-9,-9z" />
    <path
        android:fillColor="#B7C4FF"
        android:pathData="M61,26a4,4 0,0 1,3 5l-14,51a4,4 0,0 1,-8 -2l14,-51a4,4 0,0 1,5 -3z" />
    <path
        android:fillColor="#2DE2C5"
        android:pathData="M17,50H25V58H17Z" />
    <path
        android:fillColor="#6C7CFF"
        android:pathData="M83,56H91V64H83Z" />
</vector>
'''
    launcher = Path('android/app/src/main/res/drawable/mobilecode_launcher.xml')
    launcher.parent.mkdir(parents=True, exist_ok=True)
    launcher.write_text(launcher_icon)

    strings = '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="mobilecode_phone_use_accessibility_summary">MobileCode phone-use probe</string>
    <string name="mobilecode_phone_use_accessibility_description">Allows MobileCode to observe UI structure and perform explicit test actions for local non-counted phone-use evaluation.</string>
</resources>
'''
    strings_path = Path('android/app/src/main/res/values/strings.xml')
    strings_path.parent.mkdir(parents=True, exist_ok=True)
    strings_path.write_text(strings)

    phone_use_accessibility = '''<?xml version="1.0" encoding="utf-8"?>
<accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"
    android:accessibilityEventTypes="typeAllMask"
    android:accessibilityFeedbackType="feedbackGeneric"
    android:accessibilityFlags="flagReportViewIds|flagRetrieveInteractiveWindows"
    android:canPerformGestures="true"
    android:canRetrieveWindowContent="true"
    android:description="@string/mobilecode_phone_use_accessibility_description"
    android:notificationTimeout="100"
    android:summary="@string/mobilecode_phone_use_accessibility_summary" />
'''
    phone_use_accessibility_path = Path('android/app/src/main/res/xml/mobilecode_phone_use_accessibility_service.xml')
    phone_use_accessibility_path.parent.mkdir(parents=True, exist_ok=True)
    phone_use_accessibility_path.write_text(phone_use_accessibility)

    network_security = '''<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <base-config cleartextTrafficPermitted="false">
        <trust-anchors>
            <certificates src="system" />
        </trust-anchors>
    </base-config>

    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="true">localhost</domain>
        <domain includeSubdomains="true">127.0.0.1</domain>
    </domain-config>
</network-security-config>
'''
    network_security_path = Path('android/app/src/main/res/xml/network_security_config.xml')
    network_security_path.parent.mkdir(parents=True, exist_ok=True)
    network_security_path.write_text(network_security)

    activity = Path('android/app/src/main/kotlin/com/mobilecode/app/MainActivity.kt')
    activity.parent.mkdir(parents=True, exist_ok=True)
    activity.write_text(Path('tooling/MainActivity.kt').read_text())
    helper_service = Path('android/app/src/main/kotlin/com/mobilecode/app/MobileCodeHelperService.kt')
    helper_service.write_text(Path('tooling/MobileCodeHelperService.kt').read_text())
    helper_launcher = Path('android/app/src/main/kotlin/com/mobilecode/app/MobileCodeHelperLauncherActivity.kt')
    helper_launcher.write_text(Path('tooling/MobileCodeHelperLauncherActivity.kt').read_text())
    phone_use_service = Path('android/app/src/main/kotlin/com/mobilecode/app/PhoneUseAccessibilityService.kt')
    phone_use_service.write_text(Path('tooling/PhoneUseAccessibilityService.kt').read_text())


if __name__ == '__main__':
    main()
