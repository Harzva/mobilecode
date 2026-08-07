import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/cli_hub_catalog_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('bundled CLI Hub catalog exposes supported and planned CLI entries',
      () async {
    const service = CliHubCatalogService();
    final catalog = await service.loadBundledCatalog();

    expect(catalog.schemaVersion, '1.0');
    expect(catalog.entries, hasLength(14));
    expect(catalog.entries.map((entry) => entry.id), contains('git'));
    expect(catalog.entries.map((entry) => entry.id), contains('node-npm'));
    expect(catalog.entries.map((entry) => entry.id), contains('lark-cli'));
    expect(
        catalog.entries.map((entry) => entry.id), contains('agent-mail-cli'));
    expect(
      catalog.entries.map((entry) => entry.id),
      contains('google-workspace-cli'),
    );
    expect(catalog.entries.map((entry) => entry.id), contains('github-cli'));
    expect(
      catalog.entries.map((entry) => entry.id),
      contains('hyperframes-cli'),
    );

    final lark = catalog.entries.singleWhere((entry) => entry.id == 'lark-cli');
    expect(lark.riskLevel, CliHubRiskLevel.high);
    expect(lark.credentialPolicy, CliHubCredentialPolicy.secureStorage);
    expect(lark.readOnlyTaskIds, containsAll(['lark-auth-status']));
    expect(lark.mutationTaskIds, contains('lark-auth-start'));
    expect(lark.install.profileId, 'larkCli');
    expect(lark.probe.taskKind, 'lark_cli_probe');
    expect(lark.auth.required, isTrue);
    expect(lark.canInstallInSandbox, isTrue);
    expect(
      lark.install.packages,
      contains('@larksuite/cli'),
    );
    expect(
      lark.tasks.map((task) => task.taskKind),
      containsAll([
        'lark_cli_auth_start',
        'lark_cli_auth_status',
        'lark_cli_execute',
      ]),
    );
    expect(
      lark.tasks
          .singleWhere((task) => task.taskKind == 'lark_cli_execute')
          .payload['commandId'],
      'wiki_space_list',
    );

    final node = catalog.entries.singleWhere((entry) => entry.id == 'node-npm');
    expect(node.probe.taskKind, 'node_version');
    expect(
        node.probe.safeArgs, containsAll(['node --version', 'npm --version']));

    final agentMail =
        catalog.entries.singleWhere((entry) => entry.id == 'agent-mail-cli');
    expect(agentMail.install.profileId, 'agentMailCli');
    expect(agentMail.riskLevel, CliHubRiskLevel.high);
    expect(agentMail.credentialPolicy, CliHubCredentialPolicy.secureStorage);
    expect(
      agentMail.readOnlyTaskIds,
      containsAll(['agent-mail-me', 'agent-mail-message-list']),
    );
    expect(agentMail.mutationTaskIds, contains('agent-mail-auth-start'));
    expect(agentMail.probe.taskKind, 'agently_cli_probe');
    expect(agentMail.auth.required, isTrue);
    expect(agentMail.auth.storage, 'secureStorage');
    expect(agentMail.canInstallInSandbox, isTrue);
    expect(
      agentMail.install.packages,
      contains('@tencent-qqmail/agently-cli'),
    );
    expect(
      agentMail.tasks.map((task) => task.taskKind),
      containsAll([
        'agently_cli_auth_start',
        'agently_cli_me',
        'agently_cli_execute',
      ]),
    );
    expect(
      agentMail.tasks
          .singleWhere((task) => task.taskKind == 'agently_cli_execute')
          .payload['commandId'],
      'message_list',
    );

    final googleWorkspace = catalog.entries
        .singleWhere((entry) => entry.id == 'google-workspace-cli');
    expect(googleWorkspace.riskLevel, CliHubRiskLevel.high);
    expect(
      googleWorkspace.credentialPolicy,
      CliHubCredentialPolicy.secureStorage,
    );
    expect(
      googleWorkspace.readOnlyTaskIds,
      containsAll([
        'google-workspace-auth-status',
        'google-workspace-drive-files-list',
      ]),
    );
    expect(
      googleWorkspace.mutationTaskIds,
      containsAll([
        'google-workspace-auth-setup',
        'google-workspace-auth-login',
      ]),
    );
    expect(googleWorkspace.install.profileId, 'googleWorkspaceCli');
    expect(googleWorkspace.probe.taskKind, 'gws_cli_probe');
    expect(googleWorkspace.auth.required, isTrue);
    expect(googleWorkspace.auth.storage, 'secureStorage');
    expect(googleWorkspace.canInstallInSandbox, isTrue);
    expect(
      googleWorkspace.install.packages,
      contains('@googleworkspace/cli'),
    );
    expect(
      googleWorkspace.tasks.map((task) => task.taskKind),
      containsAll([
        'gws_cli_auth_setup',
        'gws_cli_auth_login',
        'gws_cli_auth_status',
        'gws_cli_execute',
      ]),
    );
    expect(
      googleWorkspace.tasks
          .singleWhere((task) => task.taskKind == 'gws_cli_execute')
          .payload['commandId'],
      'drive_files_list',
    );

    final github =
        catalog.entries.singleWhere((entry) => entry.id == 'github-cli');
    expect(github.riskLevel, CliHubRiskLevel.high);
    expect(github.credentialPolicy, CliHubCredentialPolicy.secureStorage);
    expect(github.readOnlyTaskIds, containsAll(['github-auth-status']));
    expect(github.mutationTaskIds, contains('github-auth-login'));
    expect(github.install.profileId, 'githubCli');
    expect(github.probe.taskKind, 'github_cli_probe');
    expect(github.supportLevel, CliHubSupportLevel.preview);
    expect(github.auth.required, isTrue);
    expect(github.auth.storage, 'secureStorage');
    expect(github.canInstallInSandbox, isTrue);
    expect(github.install.packages, contains('github-cli'));
    expect(
      github.tasks.map((task) => task.taskKind),
      containsAll([
        'github_cli_auth_login',
        'github_cli_auth_status',
        'github_cli_execute',
      ]),
    );
    expect(
      github.tasks
          .singleWhere((task) => task.taskKind == 'github_cli_execute')
          .payload['commandId'],
      'repo_list',
    );

    for (final entry in catalog.entries) {
      final taskIds = entry.tasks.map((task) => task.id).toSet();
      for (final id in [...entry.readOnlyTaskIds, ...entry.mutationTaskIds]) {
        expect(taskIds, contains(id), reason: '${entry.id} task classifier');
      }
    }
  });

  test('rejects duplicate CLI ids', () async {
    const service = CliHubCatalogService();

    await expectLater(
      service.loadFromManifestJson('''
{
  "schemaVersion": "1.0",
  "updatedAt": "2026-06-26",
  "entries": [
    {
      "id": "git",
      "title": "Git",
      "command": "git",
      "category": "core",
      "supportLevel": "supported",
      "officialSources": ["https://git-scm.com/downloads"],
      "install": {"strategy": "packageProfile", "profileId": "devBasic", "packages": []},
      "probe": {"taskKind": "git_version", "safeArgs": []},
      "auth": {"required": false, "storage": "none", "notes": ""}
    },
    {
      "id": "git",
      "title": "Git duplicate",
      "command": "git",
      "category": "core",
      "supportLevel": "supported",
      "officialSources": ["https://git-scm.com/downloads"],
      "install": {"strategy": "packageProfile", "profileId": "devBasic", "packages": []},
      "probe": {"taskKind": "git_version", "safeArgs": []},
      "auth": {"required": false, "storage": "none", "notes": ""}
    }
  ]
}
'''),
      throwsFormatException,
    );
  });

  test('rejects plugin manifest tasks that declare raw shell or credentials',
      () async {
    const service = CliHubCatalogService();

    await expectLater(
      service.loadFromManifestJson('''
{
  "schemaVersion": "1.0",
  "updatedAt": "2026-06-26",
  "entries": [
    {
      "id": "unsafe-cli",
      "title": "Unsafe CLI",
      "command": "unsafe",
      "category": "plugin",
      "supportLevel": "preview",
      "officialSources": ["https://example.invalid/unsafe-cli"],
      "install": {"strategy": "packageProfile", "profileId": "unsafeCli", "packages": ["unsafe-cli"]},
      "probe": {"taskKind": "unsafe_cli_probe", "safeArgs": ["--version"]},
      "auth": {"required": true, "storage": "secureStorage", "notes": "No raw shell."},
      "tasks": [
        {
          "id": "unsafe-shell",
          "label": "Unsafe shell",
          "taskKind": "raw_shell",
          "payload": {},
          "requiresApproval": true
        }
      ],
      "mutationTasks": ["unsafe-shell"]
    }
  ]
}
'''),
      throwsFormatException,
    );

    await expectLater(
      service.loadFromManifestJson('''
{
  "schemaVersion": "1.0",
  "updatedAt": "2026-06-26",
  "entries": [
    {
      "id": "credential-cli",
      "title": "Credential CLI",
      "command": "credential",
      "category": "plugin",
      "supportLevel": "preview",
      "officialSources": ["https://example.invalid/credential-cli"],
      "install": {"strategy": "packageProfile", "profileId": "credentialCli", "packages": ["credential-cli"]},
      "probe": {"taskKind": "credential_cli_probe", "safeArgs": ["--version"]},
      "auth": {"required": true, "storage": "secureStorage", "notes": "No secrets in catalog."},
      "tasks": [
        {
          "id": "credential-probe",
          "label": "Credential probe",
          "taskKind": "credential_cli_auth_status",
          "payload": {"token": "must-not-enter-catalog"},
          "requiresApproval": false
        }
      ],
      "readOnlyTasks": ["credential-probe"]
    }
  ]
}
'''),
      throwsFormatException,
    );
  });

  test('rejects malformed plugin manifests before runtime exposure', () async {
    const service = CliHubCatalogService();

    await expectLater(
      service.loadFromManifestJson('''
{
  "schemaVersion": "1.0",
  "entries": []
}
'''),
      throwsFormatException,
    );

    await expectLater(
      service.loadFromManifestJson('''
{
  "schemaVersion": "1.0",
  "updatedAt": "2026-06-26",
  "entries": [
    {
      "id": "no-source-cli",
      "title": "No Source CLI",
      "command": "no-source",
      "category": "plugin",
      "supportLevel": "preview",
      "officialSources": [],
      "install": {"strategy": "packageProfile", "profileId": "noSourceCli", "packages": ["no-source-cli"]},
      "probe": {"taskKind": "no_source_cli_probe", "safeArgs": ["--version"]},
      "auth": {"required": false, "storage": "none", "notes": ""},
      "riskLevel": "medium",
      "credentialPolicy": "none"
    }
  ]
}
'''),
      throwsFormatException,
    );

    await expectLater(
      service.loadFromManifestJson('''
{
  "schemaVersion": "1.0",
  "updatedAt": "2026-06-26",
  "entries": [
    {
      "id": "bad-classifier-cli",
      "title": "Bad Classifier CLI",
      "command": "bad-classifier",
      "category": "plugin",
      "supportLevel": "preview",
      "officialSources": ["https://example.invalid/bad-classifier-cli"],
      "install": {"strategy": "packageProfile", "profileId": "badClassifierCli", "packages": ["bad-classifier-cli"]},
      "probe": {"taskKind": "bad_classifier_cli_probe", "safeArgs": ["--version"]},
      "auth": {"required": false, "storage": "none", "notes": ""},
      "riskLevel": "medium",
      "credentialPolicy": "none",
      "tasks": [
        {
          "id": "delete-item",
          "label": "Delete item",
          "taskKind": "bad_classifier_delete",
          "payload": {"itemId": "typed-id"},
          "requiresApproval": false
        }
      ],
      "mutationTasks": ["delete-item"]
    }
  ]
}
'''),
      throwsFormatException,
    );
  });

  test('loads remote CLI Hub catalog manifest schema without enabling download',
      () async {
    const service = CliHubCatalogService();

    final remote = await service.loadRemoteManifestJson('''
{
  "schemaVersion": "1.0",
  "catalogId": "community.github",
  "name": "Community GitHub CLI Extensions",
  "version": "2026.06.26",
  "updatedAt": "2026-06-26T10:00:00Z",
  "source": "https://example.invalid/mobilecode/cli-hub/community.json",
  "minAppVersion": "0.1.0",
  "signature": {
    "algorithm": "ed25519",
    "keyId": "mobilecode-dev-test",
    "value": "test-signature-declaration-only"
  },
  "catalog": {
    "schemaVersion": "1.0",
    "updatedAt": "2026-06-26",
    "entries": [
      {
        "id": "gh-safe",
        "title": "GitHub Safe",
        "command": "gh",
        "category": "developer",
        "supportLevel": "preview",
        "officialSources": ["https://cli.github.com/"],
        "install": {"strategy": "packageProfile", "profileId": "githubCli", "packages": ["github-cli"]},
        "probe": {"taskKind": "github_cli_probe", "safeArgs": ["--version"]},
        "auth": {"required": true, "storage": "secureStorage", "notes": "Use official gh auth."},
        "riskLevel": "high",
        "credentialPolicy": "secureStorage",
        "tasks": [
          {
            "id": "repo-list",
            "label": "List repositories",
            "taskKind": "github_cli_execute",
            "payload": {"commandId": "repo_list", "limit": 20},
            "requiresApproval": false
          },
          {
            "id": "auth-login",
            "label": "Login",
            "taskKind": "github_cli_auth_login",
            "payload": {},
            "requiresApproval": true
          }
        ],
        "readOnlyTasks": ["repo-list"],
        "mutationTasks": ["auth-login"]
      }
    ]
  }
}
''');

    expect(remote.schemaVersion, '1.0');
    expect(remote.catalogId, 'community.github');
    expect(remote.source.scheme, 'https');
    expect(remote.signature.algorithm, 'ed25519');
    expect(remote.catalog.entries.single.id, 'gh-safe');
    expect(remote.catalog.entries.single.readOnlyTaskIds, ['repo-list']);
  });

  test('fetches remote CLI Hub manifest through safe downloader boundary',
      () async {
    const service = CliHubCatalogService();
    final source =
        Uri.parse('https://example.invalid/mobilecode/cli-hub/community.json');
    final fetched = await service.fetchRemoteManifest(
      source,
      downloader: (uri, {required maxBytes, required timeout}) async {
        expect(uri, source);
        expect(maxBytes, greaterThan(100));
        expect(timeout.inSeconds, greaterThan(0));
        return _remoteCatalogManifestJson(source: source.toString());
      },
    );

    expect(fetched.requestedSource, source);
    expect(fetched.bytesRead, greaterThan(100));
    expect(fetched.manifest.catalogId, 'community.github');
    expect(fetched.manifest.signature.isDeclared, isTrue);
    expect(fetched.toMetadata(), containsPair('entryCount', 1));
  });

  test('verifies sha256 remote CLI Hub manifest integrity when required',
      () async {
    const service = CliHubCatalogService();
    final source = Uri.parse(
      'https://example.invalid/mobilecode/cli-hub/community-sha.json',
    );
    final fetched = await service.fetchRemoteManifest(
      source,
      requireVerifiedSignature: true,
      downloader: (uri, {required maxBytes, required timeout}) async =>
          _remoteSha256CatalogManifestJson(source: uri.toString()),
    );

    expect(fetched.manifest.signature.algorithm, 'sha256');
    expect(fetched.manifest.signatureVerified, isTrue);
    expect(fetched.toMetadata(), containsPair('signatureVerified', true));
    expect(fetched.manifest.catalog.entries.single.id, 'gh-safe');
  });

  test('rejects unverified remote CLI Hub manifest signatures', () async {
    const service = CliHubCatalogService();

    await expectLater(
      service.loadRemoteManifestJson(
        _remoteSha256CatalogManifestJson(
          source: 'https://example.invalid/bad-digest.json',
          digestOverride:
              '0000000000000000000000000000000000000000000000000000000000000000',
        ),
        requireVerifiedSignature: true,
      ),
      throwsFormatException,
    );

    await expectLater(
      service.loadRemoteManifestJson(
        _remoteCatalogManifestJson(
          source: 'https://example.invalid/ed25519-declaration-only.json',
        ),
        requireVerifiedSignature: true,
      ),
      throwsFormatException,
    );
  });

  test('verifies ed25519 remote CLI Hub manifests with trusted keyring',
      () async {
    const service = CliHubCatalogService();
    final signed = await _remoteEd25519CatalogManifestJson(
      source: 'https://example.invalid/signed-ed25519.json',
    );

    final remote = await service.loadRemoteManifestJson(
      signed.manifestJson,
      requireVerifiedSignature: true,
      trustedEd25519PublicKeys: {
        signed.keyId: signed.publicKeyBase64,
      },
    );

    expect(remote.signature.algorithm, 'ed25519');
    expect(remote.signatureVerified, isTrue);
    expect(remote.catalog.entries.single.id, 'gh-safe');
  });

  test('verifies ed25519 remote manifests through lifecycle keyring', () async {
    const service = CliHubCatalogService();
    final signed = await _remoteEd25519CatalogManifestJson(
      source: 'https://example.invalid/signed-ed25519.json',
    );

    final remote = await service.loadRemoteManifestJson(
      signed.manifestJson,
      requireVerifiedSignature: true,
      verificationTime: DateTime.utc(2026, 6, 26, 12),
      trustedKeyring: [
        CliHubTrustedKey(
          keyId: signed.keyId,
          algorithm: 'ed25519',
          publicKeyBase64: signed.publicKeyBase64,
          allowedCatalogIds: const ['community.github'],
          allowedHosts: const ['example.invalid'],
          validFrom: DateTime.parse('2026-01-01T00:00:00Z'),
          validUntil: DateTime.parse('2027-01-01T00:00:00Z'),
        ),
      ],
    );

    expect(remote.signatureVerified, isTrue);
    expect(remote.signature.keyId, signed.keyId);
  });

  test('rejects ed25519 remote manifests after key rotation deadline',
      () async {
    const service = CliHubCatalogService();
    final signed = await _remoteEd25519CatalogManifestJson(
      source: 'https://example.invalid/signed-ed25519.json',
    );
    final rotatingKey = CliHubTrustedKey(
      keyId: signed.keyId,
      algorithm: 'ed25519',
      publicKeyBase64: signed.publicKeyBase64,
      allowedCatalogIds: const ['community.github'],
      allowedHosts: const ['example.invalid'],
      replacementKeyId: 'community-key-2027',
      rotationRequiredAfter: DateTime.parse('2026-07-01T00:00:00Z'),
    );

    final beforeDeadline = await service.loadRemoteManifestJson(
      signed.manifestJson,
      requireVerifiedSignature: true,
      verificationTime: DateTime.utc(2026, 6, 30, 23, 59),
      trustedKeyring: [rotatingKey],
    );
    expect(beforeDeadline.signatureVerified, isTrue);

    await expectLater(
      service.loadRemoteManifestJson(
        signed.manifestJson,
        requireVerifiedSignature: true,
        verificationTime: DateTime.utc(2026, 7),
        trustedKeyring: [rotatingKey],
      ),
      throwsFormatException,
    );
  });

  test('rejects ed25519 remote manifests with invalid keyring lifecycle',
      () async {
    const service = CliHubCatalogService();
    final signed = await _remoteEd25519CatalogManifestJson(
      source: 'https://example.invalid/signed-ed25519.json',
    );

    Future<void> expectRejected(CliHubTrustedKey key) => expectLater(
          service.loadRemoteManifestJson(
            signed.manifestJson,
            requireVerifiedSignature: true,
            verificationTime: DateTime.utc(2026, 6, 26, 12),
            trustedKeyring: [key],
          ),
          throwsFormatException,
        );

    await expectRejected(
      CliHubTrustedKey(
        keyId: signed.keyId,
        algorithm: 'ed25519',
        publicKeyBase64: signed.publicKeyBase64,
        revoked: true,
      ),
    );
    await expectRejected(
      CliHubTrustedKey(
        keyId: signed.keyId,
        algorithm: 'ed25519',
        publicKeyBase64: signed.publicKeyBase64,
        validUntil: DateTime.parse('2026-01-01T00:00:00Z'),
      ),
    );
    await expectRejected(
      CliHubTrustedKey(
        keyId: signed.keyId,
        algorithm: 'ed25519',
        publicKeyBase64: signed.publicKeyBase64,
        allowedCatalogIds: const ['other.catalog'],
      ),
    );
    await expectRejected(
      CliHubTrustedKey(
        keyId: signed.keyId,
        algorithm: 'ed25519',
        publicKeyBase64: signed.publicKeyBase64,
        allowedHosts: const ['other.example.invalid'],
      ),
    );
  });

  test('rejects ed25519 remote manifests without a trusted matching key',
      () async {
    const service = CliHubCatalogService();
    final signed = await _remoteEd25519CatalogManifestJson(
      source: 'https://example.invalid/signed-ed25519.json',
    );

    await expectLater(
      service.loadRemoteManifestJson(
        signed.manifestJson,
        requireVerifiedSignature: true,
      ),
      throwsFormatException,
    );

    await expectLater(
      service.loadRemoteManifestJson(
        signed.manifestJson,
        requireVerifiedSignature: true,
        trustedEd25519PublicKeys: {
          signed.keyId: base64Encode(List<int>.filled(32, 1)),
        },
      ),
      throwsFormatException,
    );
  });

  test('rejects unsafe remote CLI Hub manifest downloads before install',
      () async {
    const service = CliHubCatalogService();
    var downloaderCalled = false;

    await expectLater(
      service.fetchRemoteManifest(
        Uri.parse('http://example.invalid/catalog.json'),
        downloader: (uri, {required maxBytes, required timeout}) async {
          downloaderCalled = true;
          return '{}';
        },
      ),
      throwsFormatException,
    );
    expect(downloaderCalled, isFalse);

    await expectLater(
      service.fetchRemoteManifest(
        Uri.parse('https://example.invalid/catalog.json'),
        downloader: (uri, {required maxBytes, required timeout}) async =>
            _remoteCatalogManifestJson(
          source: 'https://example.invalid/other.json',
        ),
      ),
      throwsFormatException,
    );

    await expectLater(
      service.fetchRemoteManifest(
        Uri.parse('https://example.invalid/catalog.json'),
        maxBytes: 24,
        downloader: (uri, {required maxBytes, required timeout}) async =>
            _remoteCatalogManifestJson(source: uri.toString()),
      ),
      throwsFormatException,
    );
  });

  test('merges a validated local CLI extension catalog without duplicates',
      () async {
    const service = CliHubCatalogService();
    final base = await service.loadBundledCatalog();
    final extension = await service.loadFromManifestJson('''
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
      "install": {"strategy": "packageProfile", "profileId": "safeNotesCli", "packages": ["safe-notes-cli"]},
      "probe": {"taskKind": "safe_notes_cli_probe", "safeArgs": ["--version"]},
      "auth": {"required": false, "storage": "none", "notes": "No account required."},
      "riskLevel": "medium",
      "credentialPolicy": "none",
      "tasks": [
        {
          "id": "note-list",
          "label": "List local notes",
          "taskKind": "safe_notes_cli_execute",
          "payload": {"commandId": "note_list", "limit": 20},
          "requiresApproval": false
        }
      ],
      "readOnlyTasks": ["note-list"],
      "mutationTasks": []
    }
  ]
}
''');

    final merged = await service.mergeCatalogs(base, [extension]);

    expect(merged.entries.length, base.entries.length + 1);
    expect(merged.entries.map((entry) => entry.id), contains('safe-notes-cli'));
    expect(merged.updatedAt, extension.updatedAt);
  });

  test('rejects local CLI extension catalog id collisions', () async {
    const service = CliHubCatalogService();
    final base = await service.loadBundledCatalog();
    final duplicate = await service.loadFromManifestJson('''
{
  "schemaVersion": "1.0",
  "updatedAt": "2026-06-26T12:00:00Z",
  "entries": [
    {
      "id": "github-cli",
      "title": "Duplicate GitHub CLI",
      "command": "gh",
      "category": "developer",
      "supportLevel": "preview",
      "officialSources": ["https://cli.github.com/"],
      "install": {"strategy": "packageProfile", "profileId": "githubCli", "packages": ["github-cli"]},
      "probe": {"taskKind": "github_cli_probe", "safeArgs": ["--version"]},
      "auth": {"required": true, "storage": "secureStorage", "notes": "Use official gh auth."},
      "riskLevel": "high",
      "credentialPolicy": "secureStorage",
      "tasks": [
        {
          "id": "repo-list",
          "label": "List repositories",
          "taskKind": "github_cli_execute",
          "payload": {"commandId": "repo_list", "limit": 20},
          "requiresApproval": false
        }
      ],
      "readOnlyTasks": ["repo-list"],
      "mutationTasks": []
    }
  ]
}
''');

    await expectLater(
      service.mergeCatalogs(base, [duplicate]),
      throwsFormatException,
    );
  });

  test('removes validated local CLI extension entries without touching bundled',
      () async {
    const service = CliHubCatalogService();
    final base = await service.loadBundledCatalog();
    final extension = await service.loadFromManifestJson('''
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
      "install": {"strategy": "packageProfile", "profileId": "safeNotesCli", "packages": ["safe-notes-cli"]},
      "probe": {"taskKind": "safe_notes_cli_probe", "safeArgs": ["--version"]},
      "auth": {"required": false, "storage": "none", "notes": "No account required."},
      "riskLevel": "medium",
      "credentialPolicy": "none",
      "tasks": [
        {
          "id": "note-list",
          "label": "List local notes",
          "taskKind": "safe_notes_cli_execute",
          "payload": {"commandId": "note_list", "limit": 20},
          "requiresApproval": false
        }
      ],
      "readOnlyTasks": ["note-list"],
      "mutationTasks": []
    }
  ]
}
''');

    final merged = await service.mergeCatalogs(base, [extension]);
    final removed = service.removeExtensionEntry(
      merged,
      bundledCatalog: base,
      extensionId: 'safe-notes-cli',
    );

    expect(merged.entries.map((entry) => entry.id), contains('safe-notes-cli'));
    expect(
      removed.entries.map((entry) => entry.id),
      isNot(contains('safe-notes-cli')),
    );
    expect(removed.entries.length, base.entries.length);
    expect(removed.entries.map((entry) => entry.id), contains('github-cli'));

    expect(
      () => service.removeExtensionEntry(
        merged,
        bundledCatalog: base,
        extensionId: 'github-cli',
      ),
      throwsFormatException,
    );
    expect(
      () => service.removeExtensionEntry(
        merged,
        bundledCatalog: base,
        extensionId: 'missing-cli',
      ),
      throwsFormatException,
    );
  });

  test('builds extension install preview with source and approval disclosure',
      () async {
    const service = CliHubCatalogService();
    final base = await service.loadBundledCatalog();
    final extension = await service.loadFromManifestJson('''
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
      "install": {"strategy": "packageProfile", "profileId": "safeNotesCli", "packages": ["safe-notes-cli", "ca-certificates"]},
      "probe": {"taskKind": "safe_notes_cli_probe", "safeArgs": ["--version"]},
      "auth": {"required": false, "storage": "none", "notes": "No account required."},
      "riskLevel": "medium",
      "credentialPolicy": "none",
      "tasks": [
        {
          "id": "note-list",
          "label": "List local notes",
          "taskKind": "safe_notes_cli_execute",
          "payload": {"commandId": "note_list", "limit": 20},
          "requiresApproval": false
        },
        {
          "id": "note-write",
          "label": "Write local note",
          "taskKind": "safe_notes_cli_execute",
          "payload": {"commandId": "note_write"},
          "requiresApproval": true
        }
      ],
      "readOnlyTasks": ["note-list"],
      "mutationTasks": ["note-write"]
    }
  ]
}
''');
    final merged = await service.mergeCatalogs(base, [extension]);

    final preview = service.buildExtensionInstallPreview(
      merged,
      bundledCatalog: base,
      extensionId: 'safe-notes-cli',
      source: 'local-import://safe-notes.json',
    );
    final metadata = preview.toMetadata();

    expect(preview.id, 'safe-notes-cli');
    expect(preview.source, 'local-import://safe-notes.json');
    expect(preview.officialSources, ['https://example.invalid/safe-notes-cli']);
    expect(preview.profileId, 'safeNotesCli');
    expect(preview.packages, ['safe-notes-cli', 'ca-certificates']);
    expect(preview.riskLevel, CliHubRiskLevel.medium);
    expect(preview.credentialPolicy, CliHubCredentialPolicy.none);
    expect(preview.supportLevel, CliHubSupportLevel.preview);
    expect(preview.readOnlyTaskCount, 1);
    expect(preview.mutationTaskCount, 1);
    expect(preview.requiresApproval, isTrue);
    expect(metadata['riskLevel'], 'medium');
    expect(metadata['credentialPolicy'], 'none');
    expect(metadata['requiresApproval'], isTrue);
    expect(metadata.toString(), isNot(contains('token')));
    expect(metadata.toString(), isNot(contains('cookie')));
    expect(metadata.toString(), isNot(contains('shell')));

    expect(
      () => service.buildExtensionInstallPreview(
        merged,
        bundledCatalog: base,
        extensionId: 'github-cli',
      ),
      throwsFormatException,
    );
    expect(
      () => service.buildExtensionInstallPreview(
        merged,
        bundledCatalog: base,
        extensionId: 'missing-cli',
      ),
      throwsFormatException,
    );
  });

  test('persists validated local CLI extension catalogs and supports removal',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const service = CliHubCatalogService();
    final store = CliHubLocalExtensionStore(
      preferences: prefs,
    );
    final base = await service.loadBundledCatalog();

    const safeNotesManifest = '''
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
      "install": {"strategy": "packageProfile", "profileId": "safeNotesCli", "packages": ["safe-notes-cli"]},
      "probe": {"taskKind": "safe_notes_cli_probe", "safeArgs": ["--version"]},
      "auth": {"required": false, "storage": "none", "notes": "No account required."},
      "riskLevel": "medium",
      "credentialPolicy": "none",
      "tasks": [
        {
          "id": "note-list",
          "label": "List local notes",
          "taskKind": "safe_notes_cli_execute",
          "payload": {"commandId": "note_list", "limit": 20},
          "requiresApproval": false
        }
      ],
      "readOnlyTasks": ["note-list"],
      "mutationTasks": []
    }
  ]
}
''';

    final added = await store.addCatalogJson(
      safeNotesManifest,
      bundledCatalog: base,
    );
    final merged = await store.mergedWithBundled(base);

    expect(added.entries.single.id, 'safe-notes-cli');
    expect(merged.entries.map((entry) => entry.id), contains('safe-notes-cli'));
    expect(prefs.getStringList(store.storageKey), hasLength(1));

    await expectLater(
      store.addCatalogJson(safeNotesManifest, bundledCatalog: base),
      throwsFormatException,
    );

    await store.removeCatalogContainingEntry('safe-notes-cli');
    final afterRemoval = await store.mergedWithBundled(base);

    expect(
      afterRemoval.entries.map((entry) => entry.id),
      isNot(contains('safe-notes-cli')),
    );
    expect(prefs.getStringList(store.storageKey), isEmpty);
  });

  test('refuses to persist local CLI extension manifests with secrets',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const service = CliHubCatalogService();
    final store = CliHubLocalExtensionStore(
      preferences: prefs,
    );
    final base = await service.loadBundledCatalog();

    await expectLater(
      store.addCatalogJson(
        '''
{
  "schemaVersion": "1.0",
  "updatedAt": "2026-06-26T12:00:00Z",
  "entries": [
    {
      "id": "unsafe-notes-cli",
      "title": "Unsafe Notes CLI",
      "command": "unsafe-notes",
      "category": "productivity",
      "supportLevel": "preview",
      "officialSources": ["https://example.invalid/unsafe-notes-cli"],
      "install": {"strategy": "packageProfile", "profileId": "unsafeNotesCli", "packages": ["unsafe-notes-cli"]},
      "probe": {"taskKind": "unsafe_notes_cli_probe", "safeArgs": ["--version"]},
      "auth": {"required": false, "storage": "none", "notes": "No account required."},
      "riskLevel": "medium",
      "credentialPolicy": "none",
      "tasks": [
        {
          "id": "note-list",
          "label": "List local notes",
          "taskKind": "unsafe_notes_cli_execute",
          "payload": {"commandId": "note_list", "limit": 20},
          "requiresApproval": false
        }
      ],
      "readOnlyTasks": ["note-list"],
      "mutationTasks": [],
      "safetyNotes": ["token: REDACTED_TEST_VALUE"]
    }
  ]
}
''',
        bundledCatalog: base,
      ),
      throwsFormatException,
    );

    expect(prefs.getStringList(store.storageKey), isNull);
  });

  test('persists trusted remote catalog keys and supports revoke/removal',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = CliHubTrustedKeyStore(preferences: prefs);
    const service = CliHubCatalogService();
    final signed = await _remoteEd25519CatalogManifestJson(
      source: 'https://example.invalid/signed-ed25519.json',
    );

    final key = await store.addKeyJson(jsonEncode({
      'keyId': signed.keyId,
      'algorithm': 'ed25519',
      'publicKeyBase64': signed.publicKeyBase64,
      'allowedCatalogIds': ['community.github'],
      'allowedHosts': ['example.invalid'],
      'validFrom': '2026-01-01T00:00:00Z',
      'validUntil': '2027-01-01T00:00:00Z',
      'replacementKeyId': 'community-key-2027',
      'rotationRequiredAfter': '2026-12-01T00:00:00Z',
    }));

    expect(key.keyId, signed.keyId);
    expect(key.toMetadata().containsKey('publicKeyBase64'), isFalse);
    expect(key.toMetadata()['replacementKeyId'], 'community-key-2027');
    expect(prefs.getStringList(store.storageKey), hasLength(1));

    final loaded = await store.loadKeys();
    expect(loaded.single.keyId, signed.keyId);
    expect(loaded.single.allowedHosts, ['example.invalid']);
    expect(loaded.single.replacementKeyId, 'community-key-2027');
    expect(
      loaded.single.rotationRequiredAfter,
      DateTime.parse('2026-12-01T00:00:00Z'),
    );

    await expectLater(
      store.addKeyJson(jsonEncode({
        'keyId': signed.keyId,
        'algorithm': 'ed25519',
        'publicKeyBase64': signed.publicKeyBase64,
      })),
      throwsFormatException,
    );

    final revoked = await store.revokeKey(signed.keyId);
    expect(revoked.revoked, isTrue);
    final revokedKeys = await store.loadKeys();
    expect(revokedKeys.single.revoked, isTrue);
    expect(revokedKeys.single.toMetadata().containsKey('publicKeyBase64'),
        isFalse);

    await expectLater(
      service.loadRemoteManifestJson(
        signed.manifestJson,
        requireVerifiedSignature: true,
        verificationTime: DateTime.utc(2026, 6, 26, 12),
        trustedKeyring: revokedKeys,
      ),
      throwsFormatException,
    );

    await store.removeKey(signed.keyId);
    expect(await store.loadKeys(), isEmpty);
  });

  test('refuses to persist trusted key entries with sensitive material',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = CliHubTrustedKeyStore(preferences: prefs);

    await expectLater(
      store.addKeyJson('''
{
  "keyId": "unsafe-key",
  "algorithm": "ed25519",
  "publicKeyBase64": "cHVibGlj",
  "notes": "token: REDACTED_TEST_VALUE"
}
'''),
      throwsFormatException,
    );

    expect(prefs.getStringList(store.storageKey), isNull);
  });

  test('rejects remote CLI Hub manifests without trusted schema boundaries',
      () async {
    const service = CliHubCatalogService();

    await expectLater(
      service.loadRemoteManifestJson('''
{
  "schemaVersion": "1.0",
  "catalogId": "bad.remote",
  "name": "Bad Remote",
  "version": "2026.06.26",
  "updatedAt": "2026-06-26T10:00:00Z",
  "source": "http://example.invalid/unsafe.json",
  "signature": {
    "algorithm": "ed25519",
    "keyId": "bad",
    "value": "declared"
  },
  "catalog": {"schemaVersion": "1.0", "updatedAt": "2026-06-26", "entries": []}
}
'''),
      throwsFormatException,
    );

    await expectLater(
      service.loadRemoteManifestJson('''
{
  "schemaVersion": "1.0",
  "catalogId": "missing.signature",
  "name": "Missing Signature",
  "version": "2026.06.26",
  "updatedAt": "2026-06-26T10:00:00Z",
  "source": "https://example.invalid/catalog.json",
  "catalog": {"schemaVersion": "1.0", "updatedAt": "2026-06-26", "entries": []}
}
'''),
      throwsFormatException,
    );

    await expectLater(
      service.loadRemoteManifestJson('''
{
  "schemaVersion": "1.0",
  "catalogId": "unsafe.payload",
  "name": "Unsafe Payload",
  "version": "2026.06.26",
  "updatedAt": "2026-06-26T10:00:00Z",
  "source": "https://example.invalid/catalog.json",
  "signature": {
    "algorithm": "sha256",
    "keyId": "declared",
    "value": "declared"
  },
  "catalog": {
    "schemaVersion": "1.0",
    "updatedAt": "2026-06-26",
    "entries": [
      {
        "id": "unsafe-remote",
        "title": "Unsafe Remote",
        "command": "unsafe",
        "category": "plugin",
        "supportLevel": "preview",
        "officialSources": ["https://example.invalid/unsafe"],
        "install": {"strategy": "packageProfile", "profileId": "unsafeRemote", "packages": ["unsafe"]},
        "probe": {"taskKind": "unsafe_probe", "safeArgs": ["--version"]},
        "auth": {"required": false, "storage": "none", "notes": ""},
        "riskLevel": "medium",
        "credentialPolicy": "none",
        "tasks": [
          {
            "id": "unsafe",
            "label": "Unsafe",
            "taskKind": "raw_shell",
            "payload": {"secret": "nope"},
            "requiresApproval": true
          }
        ],
        "mutationTasks": ["unsafe"]
      }
    ]
  }
}
'''),
      throwsFormatException,
    );
  });

  test('filters catalog for pure and dev harness APKs', () async {
    const service = CliHubCatalogService();
    final catalog = await service.loadBundledCatalog();

    final pure = service.catalogForBuildProfile(
      catalog,
      includePreviewAndPlanned: false,
    );
    final devHarness = service.catalogForBuildProfile(
      catalog,
      includePreviewAndPlanned: true,
    );

    expect(
      pure.entries.map((entry) => entry.id),
      ['git', 'node-npm', 'hyperframes-cli'],
    );
    expect(
      pure.entries
          .where((entry) => entry.id != 'hyperframes-cli')
          .every((entry) => entry.supportLevel == CliHubSupportLevel.supported),
      isTrue,
    );
    expect(
      pure.entries
          .singleWhere((entry) => entry.id == 'hyperframes-cli')
          .supportLevel,
      CliHubSupportLevel.preview,
    );
    expect(devHarness.entries, hasLength(14));
    expect(devHarness.entries.map((entry) => entry.id), contains('github-cli'));
    expect(
      devHarness.entries.map((entry) => entry.id),
      contains('google-workspace-cli'),
    );
  });
}

String _remoteCatalogManifestJson({required String source}) => '''
{
  "schemaVersion": "1.0",
  "catalogId": "community.github",
  "name": "Community GitHub CLI Extensions",
  "version": "2026.06.26",
  "updatedAt": "2026-06-26T10:00:00Z",
  "source": "$source",
  "minAppVersion": "0.1.0",
  "signature": {
    "algorithm": "ed25519",
    "keyId": "mobilecode-dev-test",
    "value": "test-signature-declaration-only"
  },
  "catalog": {
    "schemaVersion": "1.0",
    "updatedAt": "2026-06-26",
    "entries": [
      {
        "id": "gh-safe",
        "title": "GitHub Safe",
        "command": "gh",
        "category": "developer",
        "supportLevel": "preview",
        "officialSources": ["https://cli.github.com/"],
        "install": {"strategy": "packageProfile", "profileId": "githubCli", "packages": ["github-cli"]},
        "probe": {"taskKind": "github_cli_probe", "safeArgs": ["--version"]},
        "auth": {"required": true, "storage": "secureStorage", "notes": "Use official gh auth."},
        "riskLevel": "high",
        "credentialPolicy": "secureStorage",
        "tasks": [
          {
            "id": "repo-list",
            "label": "List repositories",
            "taskKind": "github_cli_execute",
            "payload": {"commandId": "repo_list", "limit": 20},
            "requiresApproval": false
          },
          {
            "id": "auth-login",
            "label": "Login",
            "taskKind": "github_cli_auth_login",
            "payload": {},
            "requiresApproval": true
          }
        ],
        "readOnlyTasks": ["repo-list"],
        "mutationTasks": ["auth-login"]
      }
    ]
  }
}
''';

String _remoteSha256CatalogManifestJson({
  required String source,
  String? digestOverride,
}) {
  final catalog = <String, Object?>{
    'schemaVersion': '1.0',
    'updatedAt': '2026-06-26',
    'entries': [
      {
        'id': 'gh-safe',
        'title': 'GitHub Safe',
        'command': 'gh',
        'category': 'developer',
        'supportLevel': 'preview',
        'officialSources': ['https://cli.github.com/'],
        'install': {
          'strategy': 'packageProfile',
          'profileId': 'githubCli',
          'packages': ['github-cli'],
        },
        'probe': {
          'taskKind': 'github_cli_probe',
          'safeArgs': ['--version'],
        },
        'auth': {
          'required': true,
          'storage': 'secureStorage',
          'notes': 'Use official gh auth.',
        },
        'riskLevel': 'high',
        'credentialPolicy': 'secureStorage',
        'tasks': [
          {
            'id': 'repo-list',
            'label': 'List repositories',
            'taskKind': 'github_cli_execute',
            'payload': {'commandId': 'repo_list', 'limit': 20},
            'requiresApproval': false,
          },
          {
            'id': 'auth-login',
            'label': 'Login',
            'taskKind': 'github_cli_auth_login',
            'payload': <String, Object?>{},
            'requiresApproval': true,
          },
        ],
        'readOnlyTasks': ['repo-list'],
        'mutationTasks': ['auth-login'],
      },
    ],
  };
  final digest = digestOverride ?? _testSha256HexOfCanonicalJson(catalog);
  return jsonEncode({
    'schemaVersion': '1.0',
    'catalogId': 'community.github',
    'name': 'Community GitHub CLI Extensions',
    'version': '2026.06.26',
    'updatedAt': '2026-06-26T10:00:00Z',
    'source': source,
    'minAppVersion': '0.1.0',
    'signature': {
      'algorithm': 'sha256',
      'keyId': 'mobilecode-dev-test-sha256',
      'value': digest,
    },
    'catalog': catalog,
  });
}

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

Future<_SignedRemoteCatalogFixture> _remoteEd25519CatalogManifestJson({
  required String source,
}) async {
  final catalog = _remoteCatalogMap();
  final keyId = 'mobilecode-dev-test-ed25519';
  final algorithm = cryptography.Ed25519();
  final keyPair = await algorithm.newKeyPair();
  final publicKey = await keyPair.extractPublicKey();
  final signature = await algorithm.sign(
    utf8.encode(jsonEncode(_testCanonicalJsonValue(catalog))),
    keyPair: keyPair,
  );
  final manifest = {
    'schemaVersion': '1.0',
    'catalogId': 'community.github',
    'name': 'Community GitHub CLI Extensions',
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
  };
  return _SignedRemoteCatalogFixture(
    manifestJson: jsonEncode(manifest),
    keyId: keyId,
    publicKeyBase64: base64Encode(publicKey.bytes),
  );
}

Map<String, Object?> _remoteCatalogMap() => <String, Object?>{
      'schemaVersion': '1.0',
      'updatedAt': '2026-06-26',
      'entries': [
        {
          'id': 'gh-safe',
          'title': 'GitHub Safe',
          'command': 'gh',
          'category': 'developer',
          'supportLevel': 'preview',
          'officialSources': ['https://cli.github.com/'],
          'install': {
            'strategy': 'packageProfile',
            'profileId': 'githubCli',
            'packages': ['github-cli'],
          },
          'probe': {
            'taskKind': 'github_cli_probe',
            'safeArgs': ['--version'],
          },
          'auth': {
            'required': true,
            'storage': 'secureStorage',
            'notes': 'Use official gh auth.',
          },
          'riskLevel': 'high',
          'credentialPolicy': 'secureStorage',
          'tasks': [
            {
              'id': 'repo-list',
              'label': 'List repositories',
              'taskKind': 'github_cli_execute',
              'payload': {'commandId': 'repo_list', 'limit': 20},
              'requiresApproval': false,
            },
            {
              'id': 'auth-login',
              'label': 'Login',
              'taskKind': 'github_cli_auth_login',
              'payload': <String, Object?>{},
              'requiresApproval': true,
            },
          ],
          'readOnlyTasks': ['repo-list'],
          'mutationTasks': ['auth-login'],
        },
      ],
    };

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
