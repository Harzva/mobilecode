import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/screens/extension_center_screen.dart';
import 'package:mobile_agent/services/cli_hub_catalog_service.dart';
import 'package:mobile_agent/services/cli_hub_runtime_events.dart';
import 'package:mobile_agent/services/linux_sandbox_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'shows runtime extensions for Git, Node, Lark, Agent Mail, and Google Workspace',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ExtensionCenterScreen(includePreviewCliCatalog: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('扩展中心'), findsOneWidget);
    expect(find.text('Alpine Linux Runtime'), findsOneWidget);
    expect(find.text('Git'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Node.js / npm'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Node.js / npm'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('extensionCenter.install.lark-cli')),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Lark CLI'), findsOneWidget);
    expect(find.text('先安装 Alpine'), findsWidgets);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('extensionCenter.install.agent-mail-cli')),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Agent Mail CLI'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(
          const ValueKey('extensionCenter.install.google-workspace-cli')),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Google Workspace CLI'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('GitHub CLI'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('GitHub CLI'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Firebase CLI'),
      360,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Firebase CLI'), findsOneWidget);
    expect(find.text('planned'), findsWidgets);
  });

  testWidgets('refreshes profile install state after one-click install',
      (tester) async {
    final bridge = _FakeLinuxSandboxNativeBridge();
    final provider = LinuxSandboxRuntimeProvider(
      nativeBridge: bridge,
      useNativeRunner: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ExtensionCenterScreen(
          provider: provider,
          includePreviewCliCatalog: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('extensionCenter.install.lark-cli')),
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final installButton =
        find.byKey(const ValueKey('extensionCenter.install.lark-cli'));
    expect(installButton, findsOneWidget);

    await tester.tap(installButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(bridge.installedProfiles, contains('larkCli'));
    expect(bridge.statusCalls, greaterThanOrEqualTo(2));
    expect(find.widgetWithText(FilledButton, '已安装'), findsWidgets);
    expect(
      find.byKey(
          const ValueKey('extensionCenter.task.lark-cli.lark-auth-start')),
      findsOneWidget,
    );
    expect(
      find.byKey(
          const ValueKey('extensionCenter.task.lark-cli.lark-auth-status')),
      findsOneWidget,
    );
    expect(
      find.byKey(
          const ValueKey('extensionCenter.task.lark-cli.lark-wiki-space-list')),
      findsOneWidget,
    );

    final authStatusButton = find.byKey(
      const ValueKey('extensionCenter.task.lark-cli.lark-auth-status'),
    );
    await tester.scrollUntilVisible(
      authStatusButton,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(authStatusButton);
    await tester.pumpAndSettle();

    expect(bridge.taskKinds, contains('lark_cli_auth_status'));
  });

  testWidgets('refreshes when chat CLI Hub task changes install state',
      (tester) async {
    final bridge = _FakeLinuxSandboxNativeBridge();
    final provider = LinuxSandboxRuntimeProvider(
      nativeBridge: bridge,
      useNativeRunner: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ExtensionCenterScreen(
          provider: provider,
          includePreviewCliCatalog: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final before = bridge.statusCalls;
    CliHubRuntimeEvents.publish(const CliHubRuntimeEvent(
      cliId: 'github-cli',
      taskKind: 'package_install',
      status: 'completed',
      success: true,
      profileId: 'githubCli',
    ));
    await tester.pumpAndSettle();

    expect(bridge.statusCalls, greaterThan(before));
  });

  testWidgets('installs Agent Mail CLI as an incremental profile',
      (tester) async {
    final bridge = _FakeLinuxSandboxNativeBridge();
    final provider = LinuxSandboxRuntimeProvider(
      nativeBridge: bridge,
      useNativeRunner: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ExtensionCenterScreen(
          provider: provider,
          includePreviewCliCatalog: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final installButton =
        find.byKey(const ValueKey('extensionCenter.install.agent-mail-cli'));
    await tester.scrollUntilVisible(
      installButton,
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(installButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(bridge.installedProfiles, contains('agentMailCli'));
    expect(bridge.installedProfiles, isNot(contains('larkCli')));
    expect(find.text('Agent Mail CLI'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '已安装'), findsWidgets);
    expect(find.text('最近邮件'), findsOneWidget);

    final meButton = find.byKey(
      const ValueKey('extensionCenter.task.agent-mail-cli.agent-mail-me'),
    );
    await tester.scrollUntilVisible(
      meButton,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(meButton);
    await tester.pumpAndSettle();

    expect(bridge.taskKinds, contains('agently_cli_me'));
  });

  testWidgets('installs Google Workspace CLI as an incremental profile',
      (tester) async {
    final bridge = _FakeLinuxSandboxNativeBridge();
    final provider = LinuxSandboxRuntimeProvider(
      nativeBridge: bridge,
      useNativeRunner: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ExtensionCenterScreen(
          provider: provider,
          includePreviewCliCatalog: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final installButton = find
        .byKey(const ValueKey('extensionCenter.install.google-workspace-cli'));
    await tester.scrollUntilVisible(
      installButton,
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(installButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(bridge.installedProfiles, contains('googleWorkspaceCli'));
    expect(bridge.installedProfiles, isNot(contains('larkCli')));
    expect(bridge.installedProfiles, isNot(contains('agentMailCli')));
    expect(find.text('Google Workspace CLI'), findsOneWidget);
    expect(find.text('Drive'), findsOneWidget);

    final statusButton = find.byKey(
      const ValueKey(
        'extensionCenter.task.google-workspace-cli.google-workspace-auth-status',
      ),
    );
    await tester.scrollUntilVisible(
      statusButton,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(statusButton);
    await tester.pumpAndSettle();

    expect(bridge.taskKinds, contains('gws_cli_auth_status'));
  });

  testWidgets('installs GitHub CLI as an incremental profile', (tester) async {
    final bridge = _FakeLinuxSandboxNativeBridge();
    final provider = LinuxSandboxRuntimeProvider(
      nativeBridge: bridge,
      useNativeRunner: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ExtensionCenterScreen(
          provider: provider,
          includePreviewCliCatalog: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final installButton =
        find.byKey(const ValueKey('extensionCenter.install.github-cli'));
    await tester.scrollUntilVisible(
      installButton,
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(installButton);
    await tester.pumpAndSettle();
    expect(find.textContaining('来源：https://cli.github.com/'), findsOneWidget);
    expect(find.text('风险等级：high'), findsOneWidget);
    expect(find.text('凭据策略：secureStorage'), findsOneWidget);
    expect(find.text('任务范围：read-only:2 · mutation:1'), findsOneWidget);
    expect(find.textContaining('不暴露 raw shell'), findsOneWidget);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(bridge.installedProfiles, contains('githubCli'));
    expect(bridge.installedProfiles, isNot(contains('larkCli')));
    expect(bridge.installedProfiles, isNot(contains('agentMailCli')));
    expect(bridge.installedProfiles, isNot(contains('googleWorkspaceCli')));
    expect(find.text('GitHub CLI'), findsOneWidget);
    expect(find.text('仓库'), findsOneWidget);

    final statusButton = find.byKey(
      const ValueKey('extensionCenter.task.github-cli.github-auth-status'),
    );
    await tester.scrollUntilVisible(
      statusButton,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(statusButton);
    await tester.pumpAndSettle();

    expect(bridge.taskKinds, contains('github_cli_auth_status'));
  });

  testWidgets('shows Dev Harness Alpine as available with uninstall action',
      (tester) async {
    final bridge = _FakeLinuxSandboxNativeBridge();
    final provider = LinuxSandboxRuntimeProvider(
      nativeBridge: bridge,
      useNativeRunner: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ExtensionCenterScreen(
          provider: provider,
          includePreviewCliCatalog: true,
          bundledAlpineRuntime: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Dev Harness · Alpine built-in · CLI 按需安装'),
      findsOneWidget,
    );
    expect(find.text('Alpine Linux Runtime'), findsOneWidget);
    expect(find.text('已安装'), findsWidgets);
    expect(find.byKey(const ValueKey('extensionCenter.uninstall.rootfs')),
        findsOneWidget);
  });

  testWidgets('shows Pure APK Alpine as on-demand install', (tester) async {
    final provider = LinuxSandboxRuntimeProvider(useNativeRunner: false);

    await tester.pumpWidget(
      MaterialApp(
        home: ExtensionCenterScreen(
          provider: provider,
          includePreviewCliCatalog: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Pure APK · Alpine 按需下载 · CLI 按需安装'),
      findsOneWidget,
    );
    expect(find.text('Alpine Linux Runtime'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '一键安装'), findsOneWidget);
    expect(find.text('需要 Alpine'), findsWidgets);
  });

  testWidgets('imports and removes a local CLI Hub extension catalog',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final bridge = _FakeLinuxSandboxNativeBridge();
    final provider = LinuxSandboxRuntimeProvider(
      nativeBridge: bridge,
      useNativeRunner: true,
    );
    final store = CliHubLocalExtensionStore(preferences: prefs);

    await tester.pumpWidget(
      MaterialApp(
        home: ExtensionCenterScreen(
          provider: provider,
          includePreviewCliCatalog: true,
          localExtensionStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('导入本地 CLI Catalog'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('extensionCenter.importCatalog.input')),
      _safeNotesCatalogJson,
    );
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Safe Notes CLI'),
      360,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Safe Notes CLI'), findsOneWidget);
    expect(find.textContaining('safe-notes'), findsWidgets);
    expect(
      prefs.getStringList(store.storageKey)?.single,
      contains('"safe-notes-cli"'),
    );

    await tester.tap(
      find.byKey(const ValueKey('extensionCenter.removeLocal.safe-notes-cli')),
    );
    await tester.pumpAndSettle();
    expect(find.text('这只会移除本地导入的 CLI catalog 记录，不会删除内置 CLI，也不会执行 raw shell。'),
        findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '移除'));
    await tester.pumpAndSettle();

    expect(find.text('Safe Notes CLI'), findsNothing);
    expect(prefs.getStringList(store.storageKey), isEmpty);
  });

  testWidgets('imports a verified remote CLI Hub extension catalog',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final bridge = _FakeLinuxSandboxNativeBridge();
    final provider = LinuxSandboxRuntimeProvider(
      nativeBridge: bridge,
      useNativeRunner: true,
    );
    final store = CliHubLocalExtensionStore(preferences: prefs);
    final source =
        Uri.parse('https://example.invalid/mobilecode/safe-notes.json');

    await tester.pumpWidget(
      MaterialApp(
        home: ExtensionCenterScreen(
          provider: provider,
          includePreviewCliCatalog: true,
          localExtensionStore: store,
          remoteManifestDownloader: (
            uri, {
            required maxBytes,
            required timeout,
          }) async {
            expect(uri, source);
            expect(maxBytes, greaterThan(100));
            expect(timeout.inSeconds, greaterThan(0));
            return _remoteSafeNotesCatalogManifestJson(source.toString());
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('导入远端 CLI Catalog'));
    await tester.pumpAndSettle();
    expect(find.text('导入远端 CLI Catalog'), findsOneWidget);
    expect(find.textContaining('签名或完整性校验'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('extensionCenter.importRemoteCatalog.url')),
      source.toString(),
    );
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Safe Notes CLI'),
      360,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Safe Notes CLI'), findsOneWidget);
    expect(
      prefs.getStringList(store.storageKey)?.single,
      contains('"safe-notes-cli"'),
    );
  });

  testWidgets('imports an ed25519 remote catalog through trusted keyring',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final bridge = _FakeLinuxSandboxNativeBridge();
    final provider = LinuxSandboxRuntimeProvider(
      nativeBridge: bridge,
      useNativeRunner: true,
    );
    final localStore = CliHubLocalExtensionStore(preferences: prefs);
    final keyStore = CliHubTrustedKeyStore(preferences: prefs);
    final source =
        Uri.parse('https://example.invalid/mobilecode/safe-notes-ed25519.json');
    final signed = await _remoteSafeNotesEd25519CatalogManifestJson(
      source: source.toString(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ExtensionCenterScreen(
          provider: provider,
          includePreviewCliCatalog: true,
          localExtensionStore: localStore,
          trustedKeyStore: keyStore,
          remoteManifestDownloader: (
            uri, {
            required maxBytes,
            required timeout,
          }) async {
            expect(uri, source);
            return signed.manifestJson;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('导入远端信任密钥'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('extensionCenter.importTrustedKey.input')),
      jsonEncode({
        'keyId': signed.keyId,
        'algorithm': 'ed25519',
        'publicKeyBase64': signed.publicKeyBase64,
        'allowedCatalogIds': ['community.safe-notes'],
        'allowedHosts': ['example.invalid'],
        'validFrom': '2026-01-01T00:00:00Z',
        'validUntil': '2027-01-01T00:00:00Z',
      }),
    );
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();

    expect(prefs.getStringList(keyStore.storageKey), hasLength(1));
    expect(find.textContaining('已导入远端信任密钥'), findsWidgets);

    await tester.tap(find.byTooltip('导入远端 CLI Catalog'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('extensionCenter.importRemoteCatalog.url')),
      source.toString(),
    );
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Safe Notes CLI'),
      360,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Safe Notes CLI'), findsOneWidget);
    expect(
      prefs.getStringList(localStore.storageKey)?.single,
      contains('"safe-notes-cli"'),
    );
  });

  testWidgets('manages trusted remote catalog keys without exposing public key',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final bridge = _FakeLinuxSandboxNativeBridge();
    final provider = LinuxSandboxRuntimeProvider(
      nativeBridge: bridge,
      useNativeRunner: true,
    );
    final keyStore = CliHubTrustedKeyStore(preferences: prefs);
    final signed = await _remoteSafeNotesEd25519CatalogManifestJson(
      source: 'https://example.invalid/mobilecode/safe-notes-ed25519.json',
    );
    await keyStore.addKeyJson(jsonEncode({
      'keyId': signed.keyId,
      'algorithm': 'ed25519',
      'publicKeyBase64': signed.publicKeyBase64,
      'allowedCatalogIds': ['community.safe-notes'],
      'allowedHosts': ['example.invalid'],
      'validFrom': '2026-01-01T00:00:00Z',
      'validUntil': '2027-01-01T00:00:00Z',
      'replacementKeyId': 'safe-notes-key-2027',
      'rotationRequiredAfter': '2026-12-01T00:00:00Z',
    }));

    await tester.pumpWidget(
      MaterialApp(
        home: ExtensionCenterScreen(
          provider: provider,
          includePreviewCliCatalog: true,
          trustedKeyStore: keyStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('trusted keys:1'), findsOneWidget);

    await tester.tap(find.byTooltip('管理远端信任密钥'));
    await tester.pumpAndSettle();

    expect(find.text('远端信任密钥'), findsOneWidget);
    expect(find.text(signed.keyId), findsOneWidget);
    expect(find.textContaining('catalog:community.safe-notes'), findsOneWidget);
    expect(find.textContaining('host:example.invalid'), findsOneWidget);
    expect(find.textContaining('rotateTo:safe-notes-key-2027'), findsOneWidget);
    expect(
      find.textContaining('rotateBy:2026-12-01T00:00:00.000Z'),
      findsOneWidget,
    );
    expect(find.textContaining(signed.publicKeyBase64), findsNothing);

    await tester.tap(
      find.byKey(ValueKey('extensionCenter.trustedKey.revoke.${signed.keyId}')),
    );
    await tester.pumpAndSettle();

    final revokedKeys = await keyStore.loadKeys();
    expect(revokedKeys.single.keyId, signed.keyId);
    expect(revokedKeys.single.revoked, isTrue);
    expect(find.textContaining('已撤销远端信任密钥'), findsWidgets);
    expect(find.textContaining('trusted keys:1'), findsOneWidget);

    await tester.tap(find.byTooltip('管理远端信任密钥'));
    await tester.pumpAndSettle();
    expect(find.textContaining('revoked'), findsOneWidget);
    expect(find.byTooltip('${signed.keyId} 已撤销'), findsOneWidget);
    expect(find.textContaining(signed.publicKeyBase64), findsNothing);

    await tester.tap(
      find.byKey(ValueKey('extensionCenter.trustedKey.remove.${signed.keyId}')),
    );
    await tester.pumpAndSettle();

    expect(await keyStore.loadKeys(), isEmpty);
    expect(find.textContaining('trusted keys:0'), findsOneWidget);

    await tester.tap(find.byTooltip('管理远端信任密钥'));
    await tester.pumpAndSettle();
    expect(find.text('还没有导入远端信任密钥。'), findsOneWidget);
  });

  testWidgets('rejects unverified remote CLI Hub extension catalog',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final bridge = _FakeLinuxSandboxNativeBridge();
    final provider = LinuxSandboxRuntimeProvider(
      nativeBridge: bridge,
      useNativeRunner: true,
    );
    final store = CliHubLocalExtensionStore(preferences: prefs);

    await tester.pumpWidget(
      MaterialApp(
        home: ExtensionCenterScreen(
          provider: provider,
          includePreviewCliCatalog: true,
          localExtensionStore: store,
          remoteManifestDownloader: (
            uri, {
            required maxBytes,
            required timeout,
          }) async =>
              _remoteSafeNotesCatalogManifestJson(
            uri.toString(),
            digestOverride:
                '0000000000000000000000000000000000000000000000000000000000000000',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('导入远端 CLI Catalog'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('extensionCenter.importRemoteCatalog.url')),
      'https://example.invalid/mobilecode/bad-digest.json',
    );
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();

    expect(find.text('Safe Notes CLI'), findsNothing);
    expect(prefs.getStringList(store.storageKey), isNull);
    expect(find.textContaining('远端导入失败'), findsWidgets);
  });
}

const _safeNotesCatalogJson = '''
{
  "schemaVersion": "1.0",
  "updatedAt": "2026-06-26T12:00:00Z",
  "entries": [
    {
      "id": "safe-notes-cli",
      "title": "Safe Notes CLI",
      "command": "safe-notes",
      "category": "productivity",
      "supportLevel": "preview",
      "officialSources": ["https://example.invalid/safe-notes-cli"],
      "install": {
        "strategy": "packageProfile",
        "profileId": "safeNotesCli",
        "packages": ["safe-notes-cli"]
      },
      "probe": {
        "taskKind": "safe_notes_cli_probe",
        "safeArgs": ["--version"]
      },
      "auth": {
        "required": false,
        "storage": "none",
        "notes": "No account required."
      },
      "riskLevel": "low",
      "credentialPolicy": "none",
      "tasks": [
        {
          "id": "note-list",
          "label": "List notes",
          "taskKind": "safe_notes_cli_execute",
          "payload": {"commandId": "note_list", "limit": 20},
          "requiresApproval": false
        }
      ],
      "readOnlyTasks": ["note-list"],
      "mutationTasks": [],
      "safetyNotes": ["Local read-only extension fixture."]
    }
  ]
}
''';

String _remoteSafeNotesCatalogManifestJson(
  String source, {
  String? digestOverride,
}) {
  final catalog = _safeNotesCatalogMap();
  final digest = digestOverride ?? _testSha256HexOfCanonicalJson(catalog);
  return jsonEncode({
    'schemaVersion': '1.0',
    'catalogId': 'community.safe-notes',
    'name': 'Safe Notes CLI Catalog',
    'version': '2026.06.26',
    'updatedAt': '2026-06-26T12:00:00Z',
    'source': source,
    'minAppVersion': '0.1.0',
    'signature': {
      'algorithm': 'sha256',
      'keyId': 'safe-notes-test-sha256',
      'value': digest,
    },
    'catalog': catalog,
  });
}

Future<_SignedRemoteCatalogFixture> _remoteSafeNotesEd25519CatalogManifestJson({
  required String source,
}) async {
  final catalog = _safeNotesCatalogMap();
  final keyId = 'mobilecode-widget-ed25519';
  final algorithm = cryptography.Ed25519();
  final keyPair = await algorithm.newKeyPair();
  final publicKey = await keyPair.extractPublicKey();
  final signature = await algorithm.sign(
    utf8.encode(jsonEncode(_testCanonicalJsonValue(catalog))),
    keyPair: keyPair,
  );
  return _SignedRemoteCatalogFixture(
    manifestJson: jsonEncode({
      'schemaVersion': '1.0',
      'catalogId': 'community.safe-notes',
      'name': 'Community Safe Notes',
      'version': '2026.06.26',
      'updatedAt': '2026-06-26T10:00:00Z',
      'source': source,
      'minAppVersion': '0.1.0',
      'signature': {
        'algorithm': 'ed25519',
        'keyId': keyId,
        'value': base64Encode(signature.bytes),
      },
      'catalog': catalog,
    }),
    keyId: keyId,
    publicKeyBase64: base64Encode(publicKey.bytes),
  );
}

Map<String, Object?> _safeNotesCatalogMap() => <String, Object?>{
      'schemaVersion': '1.0',
      'updatedAt': '2026-06-26T12:00:00Z',
      'entries': [
        {
          'id': 'safe-notes-cli',
          'title': 'Safe Notes CLI',
          'command': 'safe-notes',
          'category': 'productivity',
          'supportLevel': 'preview',
          'officialSources': ['https://example.invalid/safe-notes-cli'],
          'install': {
            'strategy': 'packageProfile',
            'profileId': 'safeNotesCli',
            'packages': ['safe-notes-cli'],
          },
          'probe': {
            'taskKind': 'safe_notes_cli_probe',
            'safeArgs': ['--version'],
          },
          'auth': {
            'required': false,
            'storage': 'none',
            'notes': 'No account required.',
          },
          'riskLevel': 'low',
          'credentialPolicy': 'none',
          'tasks': [
            {
              'id': 'note-list',
              'label': 'List notes',
              'taskKind': 'safe_notes_cli_execute',
              'payload': {'commandId': 'note_list', 'limit': 20},
              'requiresApproval': false,
            },
          ],
          'readOnlyTasks': ['note-list'],
          'mutationTasks': [],
          'safetyNotes': ['Remote read-only extension fixture.'],
        },
      ],
    };

String _testSha256HexOfCanonicalJson(Object? value) {
  final canonical = jsonEncode(_testCanonicalJsonValue(value));
  return crypto.sha256.convert(utf8.encode(canonical)).toString();
}

Object? _testCanonicalJsonValue(Object? value) {
  if (value is Map) {
    final sorted = <String, Object?>{};
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    for (final key in keys) {
      sorted[key] = _testCanonicalJsonValue(value[key]);
    }
    return sorted;
  }
  if (value is List) {
    return [for (final item in value) _testCanonicalJsonValue(item)];
  }
  return value;
}

class _SignedRemoteCatalogFixture {
  const _SignedRemoteCatalogFixture({
    required this.manifestJson,
    required this.keyId,
    required this.publicKeyBase64,
  });

  final String manifestJson;
  final String keyId;
  final String publicKeyBase64;
}

class _FakeLinuxSandboxNativeBridge implements LinuxSandboxNativeBridge {
  final installedProfiles = <String>{'base'};
  final taskKinds = <String>[];
  int statusCalls = 0;

  @override
  Future<Map<String, dynamic>> status() async {
    statusCalls += 1;
    return {
      'installed': true,
      'ready': true,
      'status': 'ready',
      'arch': 'aarch64',
      'rootfsPath': '/app-owned/linux-sandbox/rootfs',
      'packages': {
        for (final profile in installedProfiles) profile: true,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> setup(
    LinuxSandboxRootfsManifest manifest,
  ) async =>
      {
        'success': true,
        'taskKind': 'setup',
        'status': 'installed',
        'stdout': '',
        'stderr': '',
      };

  @override
  Future<Map<String, dynamic>> reset() async {
    installedProfiles
      ..clear()
      ..add('base');
    return {
      'success': true,
      'taskKind': 'reset',
      'status': 'idle',
      'stdout': '',
      'stderr': '',
    };
  }

  @override
  Future<Map<String, dynamic>> runTypedTask({
    required String taskKind,
    required Map<String, dynamic> payload,
  }) async {
    taskKinds.add(taskKind);
    if (taskKind == 'package_install' &&
        payload['approved'] == true &&
        payload['profileId'] == 'larkCli') {
      installedProfiles.add('larkCli');
      return {
        'success': true,
        'taskKind': taskKind,
        'status': 'installed',
        'stdout': 'Lark CLI prerequisites installed.',
        'stderr': '',
        'metadata': {'profileId': 'larkCli'},
      };
    }
    if (taskKind == 'package_install' &&
        payload['approved'] == true &&
        payload['profileId'] == 'agentMailCli') {
      installedProfiles.add('agentMailCli');
      return {
        'success': true,
        'taskKind': taskKind,
        'status': 'installed',
        'stdout': 'Agent Mail CLI prerequisites installed.',
        'stderr': '',
        'metadata': {'profileId': 'agentMailCli'},
      };
    }
    if (taskKind == 'package_install' &&
        payload['approved'] == true &&
        payload['profileId'] == 'googleWorkspaceCli') {
      installedProfiles.add('googleWorkspaceCli');
      return {
        'success': true,
        'taskKind': taskKind,
        'status': 'installed',
        'stdout': 'Google Workspace CLI prerequisites installed.',
        'stderr': '',
        'metadata': {'profileId': 'googleWorkspaceCli'},
      };
    }
    if (taskKind == 'package_install' &&
        payload['approved'] == true &&
        payload['profileId'] == 'githubCli') {
      installedProfiles.add('githubCli');
      return {
        'success': true,
        'taskKind': taskKind,
        'status': 'installed',
        'stdout': 'GitHub CLI prerequisites installed.',
        'stderr': '',
        'metadata': {'profileId': 'githubCli'},
      };
    }
    if (taskKind == 'lark_cli_auth_status') {
      return {
        'success': true,
        'taskKind': taskKind,
        'status': 'succeeded',
        'stdout': 'Lark CLI auth status: not logged in.',
        'stderr': '',
      };
    }
    if (taskKind == 'agently_cli_me') {
      return {
        'success': true,
        'taskKind': taskKind,
        'status': 'succeeded',
        'stdout': '邮箱地址 local@example.test 已授权成功，可以用它来收发邮件了',
        'stderr': '',
      };
    }
    if (taskKind == 'gws_cli_auth_status') {
      return {
        'success': true,
        'taskKind': taskKind,
        'status': 'succeeded',
        'stdout': 'Google Workspace CLI auth status: not logged in.',
        'stderr': '',
      };
    }
    if (taskKind == 'github_cli_auth_status') {
      return {
        'success': true,
        'taskKind': taskKind,
        'status': 'succeeded',
        'stdout': 'GitHub CLI auth status: not logged in.',
        'stderr': '',
      };
    }
    return {
      'success': false,
      'taskKind': taskKind,
      'failureKind': 'commandBlocked',
      'stderr': 'Unexpected fake task.',
    };
  }
}
