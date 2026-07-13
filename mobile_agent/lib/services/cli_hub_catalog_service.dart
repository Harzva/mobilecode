import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:shared_preferences/shared_preferences.dart';

typedef CliHubRemoteManifestDownloader = Future<String> Function(
  Uri uri, {
  required int maxBytes,
  required Duration timeout,
});

enum CliHubSupportLevel { supported, preview, planned }

enum CliHubRiskLevel { low, medium, high }

enum CliHubCredentialPolicy {
  none,
  secureStorage,
  officialBrowser,
  external,
  forbidden,
}

enum CliHubInstallStrategy {
  packageProfile,
  npmGlobal,
  nativeInstaller,
  manual,
}

// HyperFrames is preview-level because the full Alpine runtime still needs
// device verification, but it must remain discoverable in the pure APK so
// users can install and inspect the typed media tasks.
const _purePreviewCliIds = {'hyperframes-cli'};

class CliHubCatalog {
  const CliHubCatalog({
    required this.schemaVersion,
    required this.updatedAt,
    required this.entries,
  });

  final String schemaVersion;
  final DateTime updatedAt;
  final List<CliHubEntry> entries;

  CliHubCatalog copyWith({
    String? schemaVersion,
    DateTime? updatedAt,
    List<CliHubEntry>? entries,
  }) {
    return CliHubCatalog(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      updatedAt: updatedAt ?? this.updatedAt,
      entries: entries ?? this.entries,
    );
  }

  factory CliHubCatalog.fromJson(Map<String, Object?> json) {
    final entries = json['entries'];
    return CliHubCatalog(
      schemaVersion: json['schemaVersion']?.toString() ?? '1.0',
      updatedAt: DateTime.parse(json['updatedAt']?.toString() ?? '1970-01-01'),
      entries: entries is List
          ? entries
              .whereType<Map<Object?, Object?>>()
              .map((entry) => CliHubEntry.fromJson(
                    entry.cast<String, Object?>(),
                  ))
              .toList(growable: false)
          : const [],
    );
  }
}

class CliHubRemoteCatalogManifest {
  const CliHubRemoteCatalogManifest({
    required this.schemaVersion,
    required this.catalogId,
    required this.name,
    required this.version,
    required this.updatedAt,
    required this.source,
    required this.minAppVersion,
    required this.signature,
    required this.catalog,
    this.signatureVerified = false,
  });

  final String schemaVersion;
  final String catalogId;
  final String name;
  final String version;
  final DateTime updatedAt;
  final Uri source;
  final String minAppVersion;
  final CliHubRemoteCatalogSignature signature;
  final CliHubCatalog catalog;
  final bool signatureVerified;
}

class CliHubRemoteCatalogSignature {
  const CliHubRemoteCatalogSignature({
    required this.algorithm,
    required this.keyId,
    required this.value,
  });

  final String algorithm;
  final String keyId;
  final String value;

  bool get isDeclared =>
      algorithm.trim().isNotEmpty &&
      keyId.trim().isNotEmpty &&
      value.trim().isNotEmpty;
}

class CliHubTrustedKey {
  const CliHubTrustedKey({
    required this.keyId,
    required this.algorithm,
    required this.publicKeyBase64,
    this.allowedCatalogIds = const [],
    this.allowedHosts = const [],
    this.validFrom,
    this.validUntil,
    this.revoked = false,
    this.replacementKeyId,
    this.rotationRequiredAfter,
  });

  final String keyId;
  final String algorithm;
  final String publicKeyBase64;
  final List<String> allowedCatalogIds;
  final List<String> allowedHosts;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final bool revoked;
  final String? replacementKeyId;
  final DateTime? rotationRequiredAfter;

  factory CliHubTrustedKey.fromJson(Map<String, Object?> json) {
    final keyId = json['keyId']?.toString().trim() ?? '';
    final algorithm = json['algorithm']?.toString().trim().toLowerCase() ?? '';
    final publicKeyBase64 = json['publicKeyBase64']?.toString().trim() ?? '';
    if (!_isValidTrustedKeyId(keyId)) {
      throw FormatException('Invalid CLI Hub trusted key id: $keyId');
    }
    if (algorithm != 'ed25519') {
      throw FormatException(
        'Unsupported CLI Hub trusted key algorithm: $algorithm',
      );
    }
    if (publicKeyBase64.isEmpty) {
      throw const FormatException('CLI Hub trusted public key is required.');
    }
    try {
      final bytes = base64Decode(publicKeyBase64);
      if (bytes.isEmpty) {
        throw const FormatException('empty public key');
      }
    } on FormatException {
      throw const FormatException(
        'CLI Hub trusted public key must be valid base64.',
      );
    }
    DateTime? parseDate(String key) {
      final raw = json[key]?.toString().trim();
      if (raw == null || raw.isEmpty) return null;
      final parsed = DateTime.tryParse(raw);
      if (parsed == null) {
        throw FormatException('CLI Hub trusted key $key is invalid: $raw');
      }
      return parsed;
    }

    final replacementKeyId = json['replacementKeyId']?.toString().trim() ?? '';
    if (replacementKeyId.isNotEmpty) {
      if (!_isValidTrustedKeyId(replacementKeyId) ||
          replacementKeyId == keyId) {
        throw FormatException(
          'Invalid CLI Hub trusted key replacementKeyId: $replacementKeyId',
        );
      }
    }

    return CliHubTrustedKey(
      keyId: keyId,
      algorithm: algorithm,
      publicKeyBase64: publicKeyBase64,
      allowedCatalogIds: _trustedKeyStringList(json['allowedCatalogIds']),
      allowedHosts: _trustedKeyStringList(json['allowedHosts']),
      validFrom: parseDate('validFrom'),
      validUntil: parseDate('validUntil'),
      revoked: json['revoked'] == true,
      replacementKeyId: replacementKeyId.isEmpty ? null : replacementKeyId,
      rotationRequiredAfter: parseDate('rotationRequiredAfter'),
    );
  }

  Map<String, Object?> toJson() => {
        'keyId': keyId,
        'algorithm': algorithm,
        'publicKeyBase64': publicKeyBase64,
        'allowedCatalogIds': allowedCatalogIds,
        'allowedHosts': allowedHosts,
        'validFrom': validFrom?.toIso8601String(),
        'validUntil': validUntil?.toIso8601String(),
        'revoked': revoked,
        'replacementKeyId': replacementKeyId,
        'rotationRequiredAfter': rotationRequiredAfter?.toIso8601String(),
      };

  Map<String, Object?> toMetadata() => {
        'keyId': keyId,
        'algorithm': algorithm,
        'allowedCatalogIds': allowedCatalogIds,
        'allowedHosts': allowedHosts,
        'validFrom': validFrom?.toIso8601String(),
        'validUntil': validUntil?.toIso8601String(),
        'revoked': revoked,
        'replacementKeyId': replacementKeyId,
        'rotationRequiredAfter': rotationRequiredAfter?.toIso8601String(),
      };

  CliHubTrustedKey copyWith({
    List<String>? allowedCatalogIds,
    List<String>? allowedHosts,
    DateTime? validFrom,
    DateTime? validUntil,
    bool? revoked,
    String? replacementKeyId,
    DateTime? rotationRequiredAfter,
  }) =>
      CliHubTrustedKey(
        keyId: keyId,
        algorithm: algorithm,
        publicKeyBase64: publicKeyBase64,
        allowedCatalogIds: allowedCatalogIds ?? this.allowedCatalogIds,
        allowedHosts: allowedHosts ?? this.allowedHosts,
        validFrom: validFrom ?? this.validFrom,
        validUntil: validUntil ?? this.validUntil,
        revoked: revoked ?? this.revoked,
        replacementKeyId: replacementKeyId ?? this.replacementKeyId,
        rotationRequiredAfter:
            rotationRequiredAfter ?? this.rotationRequiredAfter,
      );
}

bool _isValidTrustedKeyId(String value) =>
    value.isNotEmpty && !value.contains(RegExp(r'[^A-Za-z0-9_.-]'));

List<String> _trustedKeyStringList(Object? value) {
  if (value is! List) return const [];
  return List.unmodifiable(
    value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty),
  );
}

class CliHubRemoteCatalogFetchResult {
  const CliHubRemoteCatalogFetchResult({
    required this.requestedSource,
    required this.bytesRead,
    required this.manifest,
  });

  final Uri requestedSource;
  final int bytesRead;
  final CliHubRemoteCatalogManifest manifest;

  Map<String, Object?> toMetadata() => {
        'requestedSource': requestedSource.toString(),
        'bytesRead': bytesRead,
        'catalogId': manifest.catalogId,
        'version': manifest.version,
        'signatureAlgorithm': manifest.signature.algorithm,
        'signatureKeyId': manifest.signature.keyId,
        'signatureVerified': manifest.signatureVerified,
        'entryCount': manifest.catalog.entries.length,
      };
}

class CliHubExtensionInstallPreview {
  const CliHubExtensionInstallPreview({
    required this.id,
    required this.title,
    required this.source,
    required this.officialSources,
    required this.profileId,
    required this.packages,
    required this.riskLevel,
    required this.credentialPolicy,
    required this.supportLevel,
    required this.readOnlyTaskCount,
    required this.mutationTaskCount,
    required this.requiresApproval,
  });

  final String id;
  final String title;
  final String source;
  final List<String> officialSources;
  final String? profileId;
  final List<String> packages;
  final CliHubRiskLevel riskLevel;
  final CliHubCredentialPolicy credentialPolicy;
  final CliHubSupportLevel supportLevel;
  final int readOnlyTaskCount;
  final int mutationTaskCount;
  final bool requiresApproval;

  Map<String, Object?> toMetadata() => {
        'id': id,
        'title': title,
        'source': source,
        'officialSources': officialSources,
        'profileId': profileId,
        'packages': packages,
        'riskLevel': riskLevel.name,
        'credentialPolicy': credentialPolicy.name,
        'supportLevel': supportLevel.name,
        'readOnlyTaskCount': readOnlyTaskCount,
        'mutationTaskCount': mutationTaskCount,
        'requiresApproval': requiresApproval,
      };
}

class CliHubLocalExtensionStore {
  const CliHubLocalExtensionStore({
    required this.preferences,
    this.catalogService = const CliHubCatalogService(),
    this.storageKey = _defaultStorageKey,
  });

  static const _defaultStorageKey = 'mobilecode.cliHub.localCatalogJson.v1';

  final SharedPreferences preferences;
  final CliHubCatalogService catalogService;
  final String storageKey;

  Future<List<CliHubCatalog>> loadCatalogs() async {
    final rawCatalogs = preferences.getStringList(storageKey) ?? const [];
    final catalogs = <CliHubCatalog>[];
    for (final raw in rawCatalogs) {
      catalogs.add(await catalogService.loadFromManifestJson(raw));
    }
    return List.unmodifiable(catalogs);
  }

  Future<CliHubCatalog> mergedWithBundled(CliHubCatalog bundledCatalog) async {
    return catalogService.mergeCatalogs(
      bundledCatalog,
      await loadCatalogs(),
    );
  }

  Future<CliHubCatalog> addCatalogJson(
    String manifestJson, {
    CliHubCatalog? bundledCatalog,
  }) async {
    _rejectStoredSensitiveMaterial(manifestJson);
    final catalog = await catalogService.loadFromManifestJson(manifestJson);
    final existingRaw = preferences.getStringList(storageKey) ?? const [];
    final existingCatalogs = <CliHubCatalog>[];
    for (final raw in existingRaw) {
      existingCatalogs.add(await catalogService.loadFromManifestJson(raw));
    }

    final existingIds = {
      if (bundledCatalog != null)
        for (final entry in bundledCatalog.entries) entry.id,
      for (final existing in existingCatalogs)
        for (final entry in existing.entries) entry.id,
    };
    for (final entry in catalog.entries) {
      if (!existingIds.add(entry.id)) {
        throw FormatException('Duplicate CLI Hub extension id: ${entry.id}');
      }
    }

    await preferences.setStringList(
      storageKey,
      List.unmodifiable([...existingRaw, manifestJson]),
    );
    return catalog;
  }

  Future<void> removeCatalogContainingEntry(String extensionId) async {
    final id = extensionId.trim();
    if (id.isEmpty) {
      throw const FormatException('CLI Hub extension id is required.');
    }
    final existingRaw = preferences.getStringList(storageKey) ?? const [];
    var found = false;
    final keptRaw = <String>[];
    for (final raw in existingRaw) {
      final catalog = await catalogService.loadFromManifestJson(raw);
      if (catalog.entries.any((entry) => entry.id == id)) {
        found = true;
        continue;
      }
      keptRaw.add(raw);
    }
    if (!found) {
      throw FormatException('CLI Hub extension is not installed: $id');
    }
    await preferences.setStringList(storageKey, List.unmodifiable(keptRaw));
  }
}

class CliHubTrustedKeyStore {
  const CliHubTrustedKeyStore({
    required this.preferences,
    this.storageKey = _defaultStorageKey,
  });

  static const _defaultStorageKey = 'mobilecode.cliHub.trustedKeys.v1';

  final SharedPreferences preferences;
  final String storageKey;

  Future<List<CliHubTrustedKey>> loadKeys() async {
    final rawKeys = preferences.getStringList(storageKey) ?? const [];
    final keys = <CliHubTrustedKey>[];
    for (final raw in rawKeys) {
      _rejectStoredSensitiveMaterial(raw);
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException(
          'CLI Hub trusted key entry must be a JSON object.',
        );
      }
      keys.add(CliHubTrustedKey.fromJson(decoded));
    }
    return List.unmodifiable(keys);
  }

  Future<CliHubTrustedKey> addKeyJson(String keyJson) async {
    _rejectStoredSensitiveMaterial(keyJson);
    final decoded = jsonDecode(keyJson);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException(
        'CLI Hub trusted key entry must be a JSON object.',
      );
    }
    final key = CliHubTrustedKey.fromJson(decoded);
    final existing = await loadKeys();
    if (existing.any((candidate) => candidate.keyId == key.keyId)) {
      throw FormatException('Duplicate CLI Hub trusted key id: ${key.keyId}');
    }
    final existingRaw = preferences.getStringList(storageKey) ?? const [];
    await preferences.setStringList(
      storageKey,
      List.unmodifiable([...existingRaw, jsonEncode(key.toJson())]),
    );
    return key;
  }

  Future<void> removeKey(String keyId) async {
    final id = keyId.trim();
    if (id.isEmpty) {
      throw const FormatException('CLI Hub trusted key id is required.');
    }
    final rawKeys = preferences.getStringList(storageKey) ?? const [];
    var found = false;
    final kept = <String>[];
    for (final raw in rawKeys) {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException(
          'CLI Hub trusted key entry must be a JSON object.',
        );
      }
      final key = CliHubTrustedKey.fromJson(decoded);
      if (key.keyId == id) {
        found = true;
        continue;
      }
      kept.add(raw);
    }
    if (!found) {
      throw FormatException('CLI Hub trusted key is not installed: $id');
    }
    await preferences.setStringList(storageKey, List.unmodifiable(kept));
  }

  Future<CliHubTrustedKey> revokeKey(String keyId) async {
    final id = keyId.trim();
    if (id.isEmpty) {
      throw const FormatException('CLI Hub trusted key id is required.');
    }
    final rawKeys = preferences.getStringList(storageKey) ?? const [];
    var found = false;
    CliHubTrustedKey? revokedKey;
    final updated = <String>[];
    for (final raw in rawKeys) {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException(
          'CLI Hub trusted key entry must be a JSON object.',
        );
      }
      final key = CliHubTrustedKey.fromJson(decoded);
      if (key.keyId == id) {
        found = true;
        revokedKey = key.copyWith(revoked: true);
        updated.add(jsonEncode(revokedKey.toJson()));
        continue;
      }
      updated.add(raw);
    }
    if (!found || revokedKey == null) {
      throw FormatException('CLI Hub trusted key is not installed: $id');
    }
    await preferences.setStringList(storageKey, List.unmodifiable(updated));
    return revokedKey;
  }
}

class CliHubEntry {
  const CliHubEntry({
    required this.id,
    required this.title,
    required this.command,
    required this.category,
    required this.supportLevel,
    required this.riskLevel,
    required this.credentialPolicy,
    required this.officialSources,
    required this.install,
    required this.probe,
    required this.auth,
    required this.tasks,
    required this.readOnlyTaskIds,
    required this.mutationTaskIds,
    required this.safetyNotes,
  });

  final String id;
  final String title;
  final String command;
  final String category;
  final CliHubSupportLevel supportLevel;
  final CliHubRiskLevel riskLevel;
  final CliHubCredentialPolicy credentialPolicy;
  final List<String> officialSources;
  final CliHubInstall install;
  final CliHubProbe probe;
  final CliHubAuth auth;
  final List<CliHubTask> tasks;
  final List<String> readOnlyTaskIds;
  final List<String> mutationTaskIds;
  final List<String> safetyNotes;

  bool get canInstallInSandbox =>
      install.strategy == CliHubInstallStrategy.packageProfile &&
      install.profileId != null;

  factory CliHubEntry.fromJson(Map<String, Object?> json) {
    final auth = CliHubAuth.fromJson(
      (json['auth'] as Map?)?.cast<String, Object?>() ?? const {},
    );
    final tasks = _taskList(json['tasks']);
    return CliHubEntry(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      command: json['command']?.toString() ?? '',
      category: json['category']?.toString() ?? 'core',
      supportLevel: _supportLevel(json['supportLevel']?.toString()),
      riskLevel: _riskLevel(json['riskLevel']?.toString(), auth.required),
      credentialPolicy: _credentialPolicy(
        json['credentialPolicy']?.toString(),
        auth.storage,
      ),
      officialSources: _stringList(json['officialSources']),
      install: CliHubInstall.fromJson(
        (json['install'] as Map?)?.cast<String, Object?>() ?? const {},
      ),
      probe: CliHubProbe.fromJson(
        (json['probe'] as Map?)?.cast<String, Object?>() ?? const {},
      ),
      auth: auth,
      tasks: tasks,
      readOnlyTaskIds: _classifiedTaskIds(
        explicit: _stringList(json['readOnlyTasks']),
        tasks: tasks,
        mutation: false,
      ),
      mutationTaskIds: _classifiedTaskIds(
        explicit: _stringList(json['mutationTasks']),
        tasks: tasks,
        mutation: true,
      ),
      safetyNotes: _stringList(json['safetyNotes']),
    );
  }
}

class CliHubInstall {
  const CliHubInstall({
    required this.strategy,
    required this.profileId,
    required this.packages,
  });

  final CliHubInstallStrategy strategy;
  final String? profileId;
  final List<String> packages;

  factory CliHubInstall.fromJson(Map<String, Object?> json) {
    return CliHubInstall(
      strategy: _installStrategy(json['strategy']?.toString()),
      profileId: json['profileId']?.toString(),
      packages: _stringList(json['packages']),
    );
  }
}

class CliHubProbe {
  const CliHubProbe({
    required this.taskKind,
    required this.safeArgs,
  });

  final String? taskKind;
  final List<String> safeArgs;

  factory CliHubProbe.fromJson(Map<String, Object?> json) {
    final rawTaskKind = json['taskKind']?.toString();
    return CliHubProbe(
      taskKind: rawTaskKind == null || rawTaskKind.isEmpty ? null : rawTaskKind,
      safeArgs: _stringList(json['safeArgs']),
    );
  }
}

class CliHubAuth {
  const CliHubAuth({
    required this.required,
    required this.storage,
    required this.notes,
  });

  final bool required;
  final String storage;
  final String notes;

  factory CliHubAuth.fromJson(Map<String, Object?> json) {
    return CliHubAuth(
      required: json['required'] == true,
      storage: json['storage']?.toString() ?? 'none',
      notes: json['notes']?.toString() ?? '',
    );
  }
}

class CliHubTask {
  const CliHubTask({
    required this.id,
    required this.label,
    required this.taskKind,
    required this.payload,
    required this.requiresApproval,
  });

  final String id;
  final String label;
  final String taskKind;
  final Map<String, dynamic> payload;
  final bool requiresApproval;

  factory CliHubTask.fromJson(Map<String, Object?> json) {
    return CliHubTask(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      taskKind: json['taskKind']?.toString() ?? '',
      payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
      requiresApproval: json['requiresApproval'] == true,
    );
  }
}

class CliHubCatalogService {
  const CliHubCatalogService();

  Future<CliHubCatalog> loadBundledCatalog() async {
    return loadFromManifestJson(_bundledCliHubManifestJson);
  }

  Future<CliHubCatalog> loadFromManifestJson(String manifestJson) async {
    final decoded = jsonDecode(manifestJson);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('CLI Hub manifest must be a JSON object.');
    }
    if (decoded['updatedAt']?.toString().trim().isEmpty ?? true) {
      throw const FormatException('CLI Hub manifest updatedAt is required.');
    }
    final catalog = CliHubCatalog.fromJson(decoded);
    if (catalog.schemaVersion.trim().isEmpty) {
      throw const FormatException(
          'CLI Hub manifest schemaVersion is required.');
    }
    if (catalog.entries.isEmpty) {
      throw const FormatException('CLI Hub manifest entries are required.');
    }
    final ids = <String>{};
    for (final entry in catalog.entries) {
      if (entry.id.isEmpty || !ids.add(entry.id)) {
        throw FormatException('Invalid or duplicate CLI Hub id: ${entry.id}');
      }
      if (entry.title.trim().isEmpty) {
        throw FormatException('CLI Hub title is required for ${entry.id}.');
      }
      if (entry.supportLevel != CliHubSupportLevel.planned) {
        if (entry.officialSources.isEmpty ||
            entry.officialSources.any((source) => !_isHttpSource(source))) {
          throw FormatException(
            'Supported CLI Hub entry ${entry.id} requires official http(s) sources.',
          );
        }
        final rawRisk = _entryRawString(entry.id, decoded, 'riskLevel');
        if (rawRisk == null || rawRisk.trim().isEmpty) {
          throw FormatException(
            'Supported CLI Hub entry ${entry.id} requires explicit riskLevel.',
          );
        }
        final rawCredential =
            _entryRawString(entry.id, decoded, 'credentialPolicy');
        if (rawCredential == null || rawCredential.trim().isEmpty) {
          throw FormatException(
            'Supported CLI Hub entry ${entry.id} requires explicit credentialPolicy.',
          );
        }
      }
      if (entry.install.strategy == CliHubInstallStrategy.packageProfile &&
          (entry.install.profileId == null ||
              entry.install.profileId!.trim().isEmpty)) {
        throw FormatException(
          'Package profile install requires profileId for ${entry.id}.',
        );
      }
      if (entry.install.profileId != null &&
          entry.install.profileId!.contains(RegExp(r'[^A-Za-z0-9_-]'))) {
        throw FormatException(
          'Invalid package profile id for ${entry.id}: ${entry.install.profileId}',
        );
      }
      if (entry.install.strategy == CliHubInstallStrategy.packageProfile &&
          entry.supportLevel != CliHubSupportLevel.planned &&
          entry.install.packages.isEmpty) {
        throw FormatException(
          'Package profile install requires packages for ${entry.id}.',
        );
      }
      if (entry.supportLevel != CliHubSupportLevel.planned &&
          (entry.probe.taskKind == null || entry.probe.taskKind!.isEmpty)) {
        throw FormatException('Probe taskKind is required for ${entry.id}.');
      }
      final taskIds = <String>{};
      for (final task in entry.tasks) {
        if (task.id.isEmpty || !taskIds.add(task.id)) {
          throw FormatException(
            'Invalid or duplicate CLI Hub task id for ${entry.id}: ${task.id}',
          );
        }
        if (task.label.trim().isEmpty || task.taskKind.trim().isEmpty) {
          throw FormatException(
            'CLI Hub task ${entry.id}.${task.id} requires label and taskKind.',
          );
        }
        if (_forbiddenCliHubTaskKinds.contains(task.taskKind)) {
          throw FormatException(
            'CLI Hub task ${entry.id}.${task.id} must not declare ${task.taskKind}.',
          );
        }
        final unsafePayloadKey = _firstUnsafeManifestPayloadKey(task.payload);
        if (unsafePayloadKey != null) {
          throw FormatException(
            'CLI Hub task ${entry.id}.${task.id} payload contains unsafe field: $unsafePayloadKey.',
          );
        }
      }
      final classifiedTaskIds = [
        ...entry.readOnlyTaskIds,
        ...entry.mutationTaskIds,
      ];
      for (final id in classifiedTaskIds) {
        if (!taskIds.contains(id)) {
          throw FormatException(
            'CLI Hub task classifier for ${entry.id} references unknown task id: $id',
          );
        }
      }
      final taskById = {for (final task in entry.tasks) task.id: task};
      for (final id in entry.readOnlyTaskIds) {
        final task = taskById[id];
        if (task != null && task.requiresApproval) {
          throw FormatException(
            'Read-only CLI Hub task ${entry.id}.$id must not require approval.',
          );
        }
      }
      for (final id in entry.mutationTaskIds) {
        final task = taskById[id];
        if (task != null && !task.requiresApproval) {
          throw FormatException(
            'Mutation CLI Hub task ${entry.id}.$id must require approval.',
          );
        }
      }
    }
    return catalog;
  }

  Future<CliHubRemoteCatalogManifest> loadRemoteManifestJson(
    String manifestJson, {
    bool requireVerifiedSignature = false,
    Map<String, String> trustedEd25519PublicKeys = const {},
    List<CliHubTrustedKey> trustedKeyring = const [],
    DateTime? verificationTime,
  }) async {
    final decoded = jsonDecode(manifestJson);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException(
        'Remote CLI Hub manifest must be a JSON object.',
      );
    }

    final schemaVersion = decoded['schemaVersion']?.toString().trim() ?? '';
    final catalogId = decoded['catalogId']?.toString().trim() ?? '';
    final name = decoded['name']?.toString().trim() ?? '';
    final version = decoded['version']?.toString().trim() ?? '';
    final updatedAtRaw = decoded['updatedAt']?.toString().trim() ?? '';
    final sourceRaw = decoded['source']?.toString().trim() ?? '';
    final minAppVersion = decoded['minAppVersion']?.toString().trim() ?? '';

    if (schemaVersion.isEmpty) {
      throw const FormatException(
        'Remote CLI Hub manifest schemaVersion is required.',
      );
    }
    if (catalogId.isEmpty || catalogId.contains(RegExp(r'[^A-Za-z0-9_.-]'))) {
      throw FormatException('Invalid remote CLI Hub catalogId: $catalogId');
    }
    if (name.isEmpty || version.isEmpty || updatedAtRaw.isEmpty) {
      throw const FormatException(
        'Remote CLI Hub manifest name, version, and updatedAt are required.',
      );
    }
    final updatedAt = DateTime.tryParse(updatedAtRaw);
    if (updatedAt == null) {
      throw FormatException(
        'Remote CLI Hub manifest updatedAt is invalid: $updatedAtRaw',
      );
    }
    final source = Uri.tryParse(sourceRaw);
    if (source == null || source.scheme != 'https') {
      throw FormatException(
        'Remote CLI Hub manifest source must be https: $sourceRaw',
      );
    }

    final signatureJson =
        (decoded['signature'] as Map?)?.cast<String, Object?>() ?? const {};
    final signature = CliHubRemoteCatalogSignature(
      algorithm: signatureJson['algorithm']?.toString().trim() ?? '',
      keyId: signatureJson['keyId']?.toString().trim() ?? '',
      value: signatureJson['value']?.toString().trim() ?? '',
    );
    if (!signature.isDeclared) {
      throw const FormatException(
        'Remote CLI Hub manifest signature declaration is required.',
      );
    }
    if (signature.algorithm != 'ed25519' && signature.algorithm != 'sha256') {
      throw FormatException(
        'Unsupported remote CLI Hub signature algorithm: ${signature.algorithm}',
      );
    }

    final catalogJson =
        (decoded['catalog'] as Map?)?.cast<String, Object?>() ?? const {};
    if (catalogJson.isEmpty) {
      throw const FormatException(
        'Remote CLI Hub manifest catalog object is required.',
      );
    }
    if (requireVerifiedSignature) {
      await _verifyRemoteManifestSignature(
        signature,
        catalogJson,
        catalogId: catalogId,
        source: source,
        trustedEd25519PublicKeys: trustedEd25519PublicKeys,
        trustedKeyring: trustedKeyring,
        verificationTime: verificationTime,
      );
    }
    final catalog = await loadFromManifestJson(jsonEncode(catalogJson));

    return CliHubRemoteCatalogManifest(
      schemaVersion: schemaVersion,
      catalogId: catalogId,
      name: name,
      version: version,
      updatedAt: updatedAt,
      source: source,
      minAppVersion: minAppVersion,
      signature: signature,
      catalog: catalog,
      signatureVerified: requireVerifiedSignature,
    );
  }

  Future<CliHubRemoteCatalogFetchResult> fetchRemoteManifest(
    Uri source, {
    CliHubRemoteManifestDownloader? downloader,
    int maxBytes = 512 * 1024,
    Duration timeout = const Duration(seconds: 15),
    bool requireVerifiedSignature = false,
    Map<String, String> trustedEd25519PublicKeys = const {},
    List<CliHubTrustedKey> trustedKeyring = const [],
    DateTime? verificationTime,
  }) async {
    if (source.scheme != 'https' || source.host.trim().isEmpty) {
      throw FormatException(
        'Remote CLI Hub manifest download source must be https: $source',
      );
    }
    if (source.hasAuthority && source.userInfo.trim().isNotEmpty) {
      throw const FormatException(
        'Remote CLI Hub manifest source must not include user info.',
      );
    }
    if (maxBytes <= 0 || maxBytes > 2 * 1024 * 1024) {
      throw FormatException(
        'Remote CLI Hub manifest maxBytes is outside safe bounds: $maxBytes',
      );
    }

    final raw = await (downloader ?? _downloadRemoteManifestJson)(
      source,
      maxBytes: maxBytes,
      timeout: timeout,
    );
    if (raw.trim().isEmpty) {
      throw const FormatException(
        'Remote CLI Hub manifest download returned an empty response.',
      );
    }
    final bytesRead = utf8.encode(raw).length;
    if (bytesRead > maxBytes) {
      throw FormatException(
        'Remote CLI Hub manifest exceeded maxBytes: $bytesRead > $maxBytes',
      );
    }
    _rejectStoredSensitiveMaterial(raw);

    final manifest = await loadRemoteManifestJson(
      raw,
      requireVerifiedSignature: requireVerifiedSignature,
      trustedEd25519PublicKeys: trustedEd25519PublicKeys,
      trustedKeyring: trustedKeyring,
      verificationTime: verificationTime,
    );
    if (manifest.source.toString() != source.toString()) {
      throw FormatException(
        'Remote CLI Hub manifest source mismatch: ${manifest.source}',
      );
    }

    return CliHubRemoteCatalogFetchResult(
      requestedSource: source,
      bytesRead: bytesRead,
      manifest: manifest,
    );
  }

  CliHubCatalog catalogForBuildProfile(
    CliHubCatalog catalog, {
    required bool includePreviewAndPlanned,
  }) {
    if (includePreviewAndPlanned) return catalog;
    return catalog.copyWith(
      entries: [
        for (final entry in catalog.entries)
          if (entry.supportLevel == CliHubSupportLevel.supported ||
              _purePreviewCliIds.contains(entry.id))
            entry,
      ],
    );
  }

  Future<CliHubCatalog> mergeCatalogs(
    CliHubCatalog base,
    List<CliHubCatalog> extensions,
  ) async {
    final mergedEntries = <CliHubEntry>[];
    final ids = <String>{};

    void addEntry(CliHubEntry entry) {
      if (!ids.add(entry.id)) {
        throw FormatException('Duplicate CLI Hub extension id: ${entry.id}');
      }
      mergedEntries.add(entry);
    }

    for (final entry in base.entries) {
      addEntry(entry);
    }
    for (final catalog in extensions) {
      for (final entry in catalog.entries) {
        addEntry(entry);
      }
    }

    final latestUpdatedAt = [
      base.updatedAt,
      for (final catalog in extensions) catalog.updatedAt,
    ].reduce((a, b) => a.isAfter(b) ? a : b);

    return CliHubCatalog(
      schemaVersion: base.schemaVersion,
      updatedAt: latestUpdatedAt,
      entries: List.unmodifiable(mergedEntries),
    );
  }

  CliHubCatalog removeExtensionEntry(
    CliHubCatalog catalog, {
    required CliHubCatalog bundledCatalog,
    required String extensionId,
  }) {
    final id = extensionId.trim();
    if (id.isEmpty) {
      throw const FormatException('CLI Hub extension id is required.');
    }
    if (bundledCatalog.entries.any((entry) => entry.id == id)) {
      throw FormatException(
        'Bundled CLI Hub entry cannot be removed as an extension: $id',
      );
    }
    if (!catalog.entries.any((entry) => entry.id == id)) {
      throw FormatException('CLI Hub extension is not installed: $id');
    }
    return catalog.copyWith(
      entries: List.unmodifiable([
        for (final entry in catalog.entries)
          if (entry.id != id) entry,
      ]),
    );
  }

  CliHubExtensionInstallPreview buildExtensionInstallPreview(
    CliHubCatalog catalog, {
    required CliHubCatalog bundledCatalog,
    required String extensionId,
    String? source,
  }) {
    final id = extensionId.trim();
    if (id.isEmpty) {
      throw const FormatException('CLI Hub extension id is required.');
    }
    if (bundledCatalog.entries.any((entry) => entry.id == id)) {
      throw FormatException(
        'Bundled CLI Hub entry does not use extension install preview: $id',
      );
    }
    CliHubEntry? entry;
    for (final candidate in catalog.entries) {
      if (candidate.id == id) {
        entry = candidate;
        break;
      }
    }
    if (entry == null) {
      throw FormatException('CLI Hub extension is not available: $id');
    }
    if (entry.supportLevel == CliHubSupportLevel.planned) {
      throw FormatException(
        'Planned CLI Hub extension cannot be installed yet: $id',
      );
    }
    if (!entry.canInstallInSandbox) {
      throw FormatException(
        'CLI Hub extension requires a package profile before install preview: $id',
      );
    }
    return CliHubExtensionInstallPreview(
      id: entry.id,
      title: entry.title,
      source: source?.trim().isNotEmpty == true
          ? source!.trim()
          : entry.officialSources.first,
      officialSources: List.unmodifiable(entry.officialSources),
      profileId: entry.install.profileId,
      packages: List.unmodifiable(entry.install.packages),
      riskLevel: entry.riskLevel,
      credentialPolicy: entry.credentialPolicy,
      supportLevel: entry.supportLevel,
      readOnlyTaskCount: entry.readOnlyTaskIds.length,
      mutationTaskCount: entry.mutationTaskIds.length,
      requiresApproval: true,
    );
  }
}

const _forbiddenCliHubTaskKinds = {
  'raw_shell',
  'shell',
  'command',
  'cmd',
};

const _unsafeManifestPayloadKeys = {
  'command',
  'cmd',
  'shell',
  'token',
  'cookie',
  '.env',
  'env',
  'credential',
  'credentials',
  'secret',
  'password',
  'oauth_code',
  'oauthcode',
};

String? _firstUnsafeManifestPayloadKey(Map<String, dynamic> value) {
  for (final entry in value.entries) {
    final key = entry.key.toLowerCase();
    if (_unsafeManifestPayloadKeys.contains(key) ||
        key.contains('token') ||
        key.contains('cookie') ||
        key.contains('secret') ||
        key.contains('password') ||
        key.contains('credential')) {
      return entry.key;
    }
    final nested = entry.value;
    if (nested is Map) {
      final found =
          _firstUnsafeManifestPayloadKey(nested.cast<String, dynamic>());
      if (found != null) return '${entry.key}.$found';
    }
  }
  return null;
}

void _rejectStoredSensitiveMaterial(String manifestJson) {
  final checks = <RegExp>[
    RegExp(r'-----BEGIN [A-Z ]+PRIVATE KEY-----'),
    RegExp(r'\bgh[pousr]_[A-Za-z0-9_]{20,}\b'),
    RegExp(r'\bsk-[A-Za-z0-9_-]{20,}\b'),
    RegExp(r'\bxox[baprs]-[A-Za-z0-9-]{20,}\b'),
    RegExp(r'\bAKIA[0-9A-Z]{16}\b'),
    RegExp(r'\bAIza[0-9A-Za-z_-]{35}\b'),
    RegExp(r'\boauth[_-]?code\s*[:=]', caseSensitive: false),
    RegExp(r'\bcookie\s*[:=]', caseSensitive: false),
    RegExp(r'\bsession\s*[:=]', caseSensitive: false),
    RegExp(r'\btoken\s*[:=]', caseSensitive: false),
    RegExp(r'\.env(\b|[./_-])', caseSensitive: false),
  ];
  for (final pattern in checks) {
    if (pattern.hasMatch(manifestJson)) {
      throw const FormatException(
        'CLI Hub local extension manifest contains sensitive material.',
      );
    }
  }
}

Future<void> _verifyRemoteManifestSignature(
  CliHubRemoteCatalogSignature signature,
  Map<String, Object?> catalogJson, {
  required String catalogId,
  required Uri source,
  required Map<String, String> trustedEd25519PublicKeys,
  required List<CliHubTrustedKey> trustedKeyring,
  required DateTime? verificationTime,
}) async {
  final canonicalBytes = utf8.encode(_canonicalJsonEncode(catalogJson));
  if (signature.algorithm == 'sha256') {
    _verifySha256RemoteManifestSignature(signature, canonicalBytes);
    return;
  }
  if (signature.algorithm == 'ed25519') {
    final publicKeys = Map<String, String>.of(trustedEd25519PublicKeys);
    final key = _trustedKeyForSignature(
      signature,
      catalogId: catalogId,
      source: source,
      trustedKeyring: trustedKeyring,
      verificationTime: verificationTime,
    );
    if (key != null) {
      publicKeys[signature.keyId] = key.publicKeyBase64;
    }
    await _verifyEd25519RemoteManifestSignature(
      signature,
      canonicalBytes,
      trustedEd25519PublicKeys: publicKeys,
    );
    return;
  }
  throw FormatException(
    'Unsupported remote CLI Hub signature algorithm: ${signature.algorithm}',
  );
}

CliHubTrustedKey? _trustedKeyForSignature(
  CliHubRemoteCatalogSignature signature, {
  required String catalogId,
  required Uri source,
  required List<CliHubTrustedKey> trustedKeyring,
  required DateTime? verificationTime,
}) {
  if (trustedKeyring.isEmpty) return null;
  final candidates =
      trustedKeyring.where((key) => key.keyId == signature.keyId);
  if (candidates.isEmpty) {
    throw FormatException(
      'Remote CLI Hub trusted key is not in keyring: ${signature.keyId}',
    );
  }
  final key = candidates.first;
  final algorithm = key.algorithm.trim().toLowerCase();
  if (algorithm != signature.algorithm) {
    throw FormatException(
      'Remote CLI Hub trusted key algorithm mismatch for ${signature.keyId}.',
    );
  }
  if (key.revoked) {
    throw FormatException(
      'Remote CLI Hub trusted key is revoked: ${signature.keyId}',
    );
  }
  final now = (verificationTime ?? DateTime.now()).toUtc();
  if (key.validFrom != null && now.isBefore(key.validFrom!.toUtc())) {
    throw FormatException(
      'Remote CLI Hub trusted key is not valid yet: ${signature.keyId}',
    );
  }
  if (key.validUntil != null && !now.isBefore(key.validUntil!.toUtc())) {
    throw FormatException(
      'Remote CLI Hub trusted key is expired: ${signature.keyId}',
    );
  }
  if (key.rotationRequiredAfter != null &&
      !now.isBefore(key.rotationRequiredAfter!.toUtc())) {
    throw FormatException(
      'Remote CLI Hub trusted key requires rotation: ${signature.keyId}',
    );
  }
  if (key.allowedCatalogIds.isNotEmpty &&
      !key.allowedCatalogIds.contains(catalogId)) {
    throw FormatException(
      'Remote CLI Hub trusted key is not allowed for catalog: $catalogId',
    );
  }
  if (key.allowedHosts.isNotEmpty && !key.allowedHosts.contains(source.host)) {
    throw FormatException(
      'Remote CLI Hub trusted key is not allowed for host: ${source.host}',
    );
  }
  return key;
}

void _verifySha256RemoteManifestSignature(
  CliHubRemoteCatalogSignature signature,
  List<int> canonicalBytes,
) {
  final expected = _normalizeSha256SignatureValue(signature.value);
  final actual = crypto.sha256.convert(canonicalBytes).toString();
  if (actual != expected) {
    throw const FormatException(
      'Remote CLI Hub catalog sha256 verification failed.',
    );
  }
}

String _normalizeSha256SignatureValue(String value) {
  final normalized = value.trim().toLowerCase().replaceFirst('sha256:', '');
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized)) {
    throw const FormatException(
      'Remote CLI Hub sha256 signature value must be a 64 character hex digest.',
    );
  }
  return normalized;
}

Future<void> _verifyEd25519RemoteManifestSignature(
  CliHubRemoteCatalogSignature signature,
  List<int> canonicalBytes, {
  required Map<String, String> trustedEd25519PublicKeys,
}) async {
  final publicKeyValue = trustedEd25519PublicKeys[signature.keyId]?.trim();
  if (publicKeyValue == null || publicKeyValue.isEmpty) {
    throw FormatException(
      'Remote CLI Hub Ed25519 public key is not trusted: ${signature.keyId}',
    );
  }
  final publicKeyBytes = _decodeBase64Field(
    publicKeyValue,
    fieldName: 'Remote CLI Hub Ed25519 public key',
  );
  if (publicKeyBytes.length != 32) {
    throw const FormatException(
      'Remote CLI Hub Ed25519 public key must be 32 bytes.',
    );
  }
  final signatureBytes = _decodeBase64Field(
    signature.value,
    fieldName: 'Remote CLI Hub Ed25519 signature',
  );
  if (signatureBytes.length != 64) {
    throw const FormatException(
      'Remote CLI Hub Ed25519 signature must be 64 bytes.',
    );
  }
  final algorithm = cryptography.Ed25519();
  final verified = await algorithm.verify(
    canonicalBytes,
    signature: cryptography.Signature(
      signatureBytes,
      publicKey: cryptography.SimplePublicKey(
        publicKeyBytes,
        type: cryptography.KeyPairType.ed25519,
      ),
    ),
  );
  if (!verified) {
    throw const FormatException(
      'Remote CLI Hub Ed25519 signature verification failed.',
    );
  }
}

List<int> _decodeBase64Field(String value, {required String fieldName}) {
  try {
    return base64Decode(value.trim());
  } on FormatException {
    throw FormatException('$fieldName must be base64 encoded.');
  }
}

String _canonicalJsonEncode(Object? value) =>
    jsonEncode(_canonicalJsonValue(value));

Object? _canonicalJsonValue(Object? value) {
  if (value is Map) {
    final sorted = <String, Object?>{};
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    for (final key in keys) {
      sorted[key] = _canonicalJsonValue(value[key]);
    }
    return sorted;
  }
  if (value is List) {
    return [for (final item in value) _canonicalJsonValue(item)];
  }
  return value;
}

Future<String> _downloadRemoteManifestJson(
  Uri uri, {
  required int maxBytes,
  required Duration timeout,
}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client.getUrl(uri).timeout(timeout);
    request.followRedirects = false;
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw FormatException(
        'Remote CLI Hub manifest download failed with HTTP ${response.statusCode}.',
      );
    }
    if (response.contentLength > maxBytes) {
      throw FormatException(
        'Remote CLI Hub manifest contentLength exceeds maxBytes: ${response.contentLength} > $maxBytes',
      );
    }

    final builder = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in response.timeout(timeout)) {
      received += chunk.length;
      if (received > maxBytes) {
        throw FormatException(
          'Remote CLI Hub manifest exceeded maxBytes: $received > $maxBytes',
        );
      }
      builder.add(chunk);
    }
    return utf8.decode(builder.takeBytes());
  } finally {
    client.close(force: true);
  }
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.map((item) => item.toString()).toList(growable: false);
}

List<CliHubTask> _taskList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map<Object?, Object?>>()
      .map((item) => CliHubTask.fromJson(item.cast<String, Object?>()))
      .toList(growable: false);
}

bool _isHttpSource(String source) {
  final uri = Uri.tryParse(source);
  return uri != null && (uri.scheme == 'https' || uri.scheme == 'http');
}

String? _entryRawString(
  String entryId,
  Map<String, Object?> manifest,
  String key,
) {
  final entries = manifest['entries'];
  if (entries is! List) return null;
  for (final raw in entries) {
    if (raw is! Map) continue;
    if (raw['id']?.toString() == entryId) return raw[key]?.toString();
  }
  return null;
}

List<String> _classifiedTaskIds({
  required List<String> explicit,
  required List<CliHubTask> tasks,
  required bool mutation,
}) {
  if (explicit.isNotEmpty) return explicit;
  return tasks
      .where(
          (task) => mutation ? task.requiresApproval : !task.requiresApproval)
      .map((task) => task.id)
      .toList(growable: false);
}

CliHubSupportLevel _supportLevel(String? value) => switch (value) {
      'supported' => CliHubSupportLevel.supported,
      'preview' => CliHubSupportLevel.preview,
      _ => CliHubSupportLevel.planned,
    };

CliHubRiskLevel _riskLevel(String? value, bool authRequired) => switch (value) {
      'low' => CliHubRiskLevel.low,
      'medium' => CliHubRiskLevel.medium,
      'high' => CliHubRiskLevel.high,
      _ => authRequired ? CliHubRiskLevel.high : CliHubRiskLevel.medium,
    };

CliHubCredentialPolicy _credentialPolicy(
  String? value,
  String authStorage,
) =>
    switch (value ?? authStorage) {
      'none' => CliHubCredentialPolicy.none,
      'secureStorage' => CliHubCredentialPolicy.secureStorage,
      'officialBrowser' => CliHubCredentialPolicy.officialBrowser,
      'external' => CliHubCredentialPolicy.external,
      'forbidden' => CliHubCredentialPolicy.forbidden,
      _ => CliHubCredentialPolicy.none,
    };

CliHubInstallStrategy _installStrategy(String? value) => switch (value) {
      'packageProfile' => CliHubInstallStrategy.packageProfile,
      'npmGlobal' => CliHubInstallStrategy.npmGlobal,
      'nativeInstaller' => CliHubInstallStrategy.nativeInstaller,
      _ => CliHubInstallStrategy.manual,
    };

const _bundledCliHubManifestJson = r'''
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
      "officialSources": [
        "https://git-scm.com/downloads"
      ],
      "install": {
        "strategy": "packageProfile",
        "profileId": "devBasic",
        "packages": [
          "git",
          "curl",
          "ca-certificates"
        ]
      },
      "probe": {
        "taskKind": "git_version",
        "safeArgs": [
          "--version"
        ]
      },
      "auth": {
        "required": false,
        "storage": "none",
        "notes": "Repository credentials remain outside the CLI catalog and must use MobileCode credential boundaries."
      },
      "safetyNotes": [
        "No arbitrary git shell is exposed to Agent by default.",
        "Clone/push flows need separate workspace and credential approval."
      ],
      "riskLevel": "medium",
      "credentialPolicy": "none",
      "readOnlyTasks": [],
      "mutationTasks": []
    },
    {
      "id": "node-npm",
      "title": "Node.js / npm",
      "command": "node,npm",
      "category": "package",
      "supportLevel": "supported",
      "officialSources": [
        "https://nodejs.org/en/download",
        "https://docs.npmjs.com/downloading-and-installing-node-js-and-npm"
      ],
      "install": {
        "strategy": "packageProfile",
        "profileId": "nodePack",
        "packages": [
          "nodejs",
          "npm"
        ]
      },
      "probe": {
        "taskKind": "node_version",
        "safeArgs": [
          "node --version",
          "npm --version"
        ]
      },
      "auth": {
        "required": false,
        "storage": "none",
        "notes": "npm registry auth is not configured by this profile."
      },
      "safetyNotes": [
        "npm_build stays a typed task with cwd validation.",
        "Global package installs require explicit extension approval."
      ],
      "riskLevel": "medium",
      "credentialPolicy": "none",
      "readOnlyTasks": [],
      "mutationTasks": []
    },
    {
      "id": "lark-cli",
      "title": "Lark CLI",
      "command": "lark-cli",
      "category": "collaboration",
      "supportLevel": "preview",
      "officialSources": [
        "https://github.com/larksuite/cli",
        "https://www.npmjs.com/package/@larksuite/cli"
      ],
      "install": {
        "strategy": "packageProfile",
        "profileId": "larkCli",
        "packages": [
          "nodejs",
          "npm",
          "curl",
          "ca-certificates",
          "@larksuite/cli"
        ]
      },
      "probe": {
        "taskKind": "lark_cli_probe",
        "safeArgs": [
          "node --version",
          "npm --version",
          "lark-cli --version"
        ]
      },
      "auth": {
        "required": true,
        "storage": "secureStorage",
        "notes": "Real Lark auth must use MobileCode native Lark connection or secure storage; never catalog tokens."
      },
      "tasks": [
        {
          "id": "lark-auth-start",
          "label": "登录",
          "taskKind": "lark_cli_auth_start",
          "payload": {},
          "requiresApproval": true
        },
        {
          "id": "lark-auth-status",
          "label": "状态",
          "taskKind": "lark_cli_auth_status",
          "payload": {},
          "requiresApproval": false
        },
        {
          "id": "lark-wiki-space-list",
          "label": "执行",
          "taskKind": "lark_cli_execute",
          "payload": {
            "commandId": "wiki_space_list"
          },
          "requiresApproval": false
        }
      ],
      "safetyNotes": [
        "This profile installs prerequisites first; CLI auth/execution remains typed.",
        "No token, app_secret, cookie, or .env value may enter logs or evidence."
      ],
      "riskLevel": "high",
      "credentialPolicy": "secureStorage",
      "readOnlyTasks": [
        "lark-auth-status",
        "lark-wiki-space-list"
      ],
      "mutationTasks": [
        "lark-auth-start"
      ]
    },
    {
      "id": "hyperframes-cli",
      "title": "HyperFrames CLI",
      "command": "hyperframes",
      "category": "media",
      "supportLevel": "preview",
      "officialSources": [
        "https://hyperframes.heygen.com/packages/cli",
        "https://github.com/heygen-com/hyperframes"
      ],
      "install": {
        "strategy": "packageProfile",
        "profileId": "hyperframesCli",
        "packages": [
          "nodejs",
          "npm",
          "chromium",
          "ffmpeg",
          "ca-certificates",
          "hyperframes"
        ]
      },
      "probe": {
        "taskKind": "hyperframes_cli_probe",
        "safeArgs": [
          "hyperframes --version"
        ]
      },
      "auth": {
        "required": false,
        "storage": "none",
        "notes": "HyperFrames CLI itself does not require a MobileCode credential. External media providers and publish credentials remain outside this catalog."
      },
      "tasks": [
        {
          "id": "hyperframes-lint",
          "label": "Lint",
          "taskKind": "hyperframes_lint",
          "payload": {},
          "requiresApproval": false
        },
        {
          "id": "hyperframes-check",
          "label": "Check",
          "taskKind": "hyperframes_check",
          "payload": {},
          "requiresApproval": false
        },
        {
          "id": "hyperframes-compositions",
          "label": "Compositions",
          "taskKind": "hyperframes_compositions",
          "payload": {},
          "requiresApproval": false
        },
        {
          "id": "hyperframes-render",
          "label": "Render MP4",
          "taskKind": "hyperframes_render",
          "payload": {
            "output": "output.mp4"
          },
          "requiresApproval": true
        }
      ],
      "safetyNotes": [
        "Only fixed HyperFrames subcommands are exposed; raw shell and arbitrary CLI flags stay blocked.",
        "Render writes only to a workspace-relative output path and requires approval.",
        "HyperFrames render needs Node 22+, a browser runtime, and FFmpeg; Alpine package availability must be verified on the target ABI.",
        "Preview is intentionally not a bounded Agent task because it is a long-running server; use MobileCode's preview surface instead.",
        "Publish, add, transcribe, TTS, and background-removal flows remain outside this first compatibility slice."
      ],
      "riskLevel": "medium",
      "credentialPolicy": "none",
      "readOnlyTasks": [
        "hyperframes-lint",
        "hyperframes-check",
        "hyperframes-compositions"
      ],
      "mutationTasks": [
        "hyperframes-render"
      ]
    },
    {
      "id": "agent-mail-cli",
      "title": "Agent Mail CLI",
      "command": "agently-cli",
      "category": "collaboration",
      "supportLevel": "preview",
      "officialSources": [
        "https://agent.qq.com/doc/cli-setup.md",
        "https://www.npmjs.com/package/@tencent-qqmail/agently-cli"
      ],
      "install": {
        "strategy": "packageProfile",
        "profileId": "agentMailCli",
        "packages": [
          "nodejs",
          "npm",
          "curl",
          "ca-certificates",
          "@tencent-qqmail/agently-cli"
        ]
      },
      "probe": {
        "taskKind": "agently_cli_probe",
        "safeArgs": [
          "node --version",
          "npm --version",
          "agently-cli --version"
        ]
      },
      "auth": {
        "required": true,
        "storage": "secureStorage",
        "notes": "OAuth must use official agently-cli auth login. Credentials and opaque auth URLs must never enter catalog, logs, or evidence."
      },
      "tasks": [
        {
          "id": "agent-mail-auth-start",
          "label": "登录",
          "taskKind": "agently_cli_auth_start",
          "payload": {},
          "requiresApproval": true
        },
        {
          "id": "agent-mail-me",
          "label": "状态",
          "taskKind": "agently_cli_me",
          "payload": {},
          "requiresApproval": false
        },
        {
          "id": "agent-mail-message-list",
          "label": "最近邮件",
          "taskKind": "agently_cli_execute",
          "payload": {
            "commandId": "message_list",
            "limit": 10
          },
          "requiresApproval": false
        }
      ],
      "safetyNotes": [
        "No raw mail shell is exposed to Agent by default.",
        "Message read/send/reply/attachment commands require separate typed approvals.",
        "No token, cookie, .env, OAuth code, or credential-like value may enter logs or evidence."
      ],
      "riskLevel": "high",
      "credentialPolicy": "secureStorage",
      "readOnlyTasks": [
        "agent-mail-me",
        "agent-mail-message-list"
      ],
      "mutationTasks": [
        "agent-mail-auth-start"
      ]
    },
    {
      "id": "google-workspace-cli",
      "title": "Google Workspace CLI",
      "command": "gws",
      "category": "collaboration",
      "supportLevel": "preview",
      "officialSources": [
        "https://github.com/googleworkspace/cli",
        "https://www.npmjs.com/package/@googleworkspace/cli"
      ],
      "install": {
        "strategy": "packageProfile",
        "profileId": "googleWorkspaceCli",
        "packages": [
          "nodejs",
          "npm",
          "curl",
          "ca-certificates",
          "@googleworkspace/cli"
        ]
      },
      "probe": {
        "taskKind": "gws_cli_probe",
        "safeArgs": [
          "node --version",
          "npm --version",
          "gws --version"
        ]
      },
      "auth": {
        "required": true,
        "storage": "secureStorage",
        "notes": "Use official gws auth setup/login. OAuth setup may require gcloud and a Google Cloud project; never catalog tokens, exported credentials, or .env values."
      },
      "tasks": [
        {
          "id": "google-workspace-auth-setup",
          "label": "配置",
          "taskKind": "gws_cli_auth_setup",
          "payload": {},
          "requiresApproval": true
        },
        {
          "id": "google-workspace-auth-login",
          "label": "登录",
          "taskKind": "gws_cli_auth_login",
          "payload": {},
          "requiresApproval": true
        },
        {
          "id": "google-workspace-auth-status",
          "label": "状态",
          "taskKind": "gws_cli_auth_status",
          "payload": {},
          "requiresApproval": false
        },
        {
          "id": "google-workspace-drive-files-list",
          "label": "Drive",
          "taskKind": "gws_cli_execute",
          "payload": {
            "commandId": "drive_files_list",
            "pageSize": 5
          },
          "requiresApproval": false
        }
      ],
      "safetyNotes": [
        "This project is not an officially supported Google product and remains preview until real-device auth is verified.",
        "No raw Workspace shell is exposed to Agent by default.",
        "Drive, Gmail, Calendar, Sheets, Docs, Chat, and Admin commands require separate typed approvals.",
        "Do not expose gws auth export, plaintext credential files, service account keys, or GOOGLE_WORKSPACE_CLI_TOKEN through CLI Hub."
      ],
      "riskLevel": "high",
      "credentialPolicy": "secureStorage",
      "readOnlyTasks": [
        "google-workspace-auth-status",
        "google-workspace-drive-files-list"
      ],
      "mutationTasks": [
        "google-workspace-auth-setup",
        "google-workspace-auth-login"
      ]
    },
    {
      "id": "github-cli",
      "title": "GitHub CLI",
      "command": "gh",
      "category": "collaboration",
      "supportLevel": "preview",
      "officialSources": [
        "https://cli.github.com/",
        "https://cli.github.com/manual/installation"
      ],
      "install": {
        "strategy": "packageProfile",
        "profileId": "githubCli",
        "packages": [
          "github-cli",
          "git",
          "curl",
          "ca-certificates"
        ]
      },
      "probe": {
        "taskKind": "github_cli_probe",
        "safeArgs": [
          "gh --version"
        ]
      },
      "auth": {
        "required": true,
        "storage": "secureStorage",
        "notes": "Use official gh auth login browser flow and unify with MobileCode's existing GitHub auth surface. Do not use --with-token, --show-token, or --insecure-storage."
      },
      "tasks": [
        {
          "id": "github-auth-login",
          "label": "登录",
          "taskKind": "github_cli_auth_login",
          "payload": {},
          "requiresApproval": true
        },
        {
          "id": "github-auth-status",
          "label": "状态",
          "taskKind": "github_cli_auth_status",
          "payload": {},
          "requiresApproval": false
        },
        {
          "id": "github-repo-list",
          "label": "仓库",
          "taskKind": "github_cli_execute",
          "payload": {
            "commandId": "repo_list",
            "limit": 10
          },
          "requiresApproval": false
        }
      ],
      "safetyNotes": [
        "Do not ask users to paste GitHub tokens into raw CLI prompts.",
        "Do not expose gh auth token, --show-token, GH_TOKEN, or GITHUB_TOKEN through CLI Hub.",
        "Repo, issue, PR, workflow, release, and secret commands require separate typed approvals."
      ],
      "riskLevel": "high",
      "credentialPolicy": "secureStorage",
      "readOnlyTasks": [
        "github-auth-status",
        "github-repo-list"
      ],
      "mutationTasks": [
        "github-auth-login"
      ]
    },
    {
      "id": "firebase-cli",
      "title": "Firebase CLI",
      "command": "firebase",
      "category": "cloud",
      "supportLevel": "planned",
      "officialSources": [
        "https://firebase.google.com/docs/cli"
      ],
      "install": {
        "strategy": "npmGlobal",
        "profileId": null,
        "packages": [
          "firebase-tools"
        ]
      },
      "probe": {
        "taskKind": null,
        "safeArgs": [
          "firebase --version"
        ]
      },
      "auth": {
        "required": true,
        "storage": "officialBrowser",
        "notes": "Requires a Google/Firebase login flow before commands can mutate projects."
      },
      "safetyNotes": [
        "Deploy/delete commands require explicit approval and project binding."
      ],
      "riskLevel": "high",
      "credentialPolicy": "officialBrowser",
      "readOnlyTasks": [],
      "mutationTasks": []
    },
    {
      "id": "vercel-cli",
      "title": "Vercel CLI",
      "command": "vercel",
      "category": "deploy",
      "supportLevel": "planned",
      "officialSources": [
        "https://vercel.com/docs/cli"
      ],
      "install": {
        "strategy": "npmGlobal",
        "profileId": null,
        "packages": [
          "vercel"
        ]
      },
      "probe": {
        "taskKind": null,
        "safeArgs": [
          "vercel --version"
        ]
      },
      "auth": {
        "required": true,
        "storage": "officialBrowser",
        "notes": "Login/session storage must be explicit and redactable."
      },
      "safetyNotes": [
        "Production deploy commands need user confirmation and evidence."
      ],
      "riskLevel": "high",
      "credentialPolicy": "officialBrowser",
      "readOnlyTasks": [],
      "mutationTasks": []
    },
    {
      "id": "netlify-cli",
      "title": "Netlify CLI",
      "command": "netlify",
      "category": "deploy",
      "supportLevel": "planned",
      "officialSources": [
        "https://docs.netlify.com/cli/get-started/"
      ],
      "install": {
        "strategy": "npmGlobal",
        "profileId": null,
        "packages": [
          "netlify-cli"
        ]
      },
      "probe": {
        "taskKind": null,
        "safeArgs": [
          "netlify --version"
        ]
      },
      "auth": {
        "required": true,
        "storage": "officialBrowser",
        "notes": "Auth token handling must go through secure storage."
      },
      "safetyNotes": [
        "Deploy and site mutation commands need confirmation."
      ],
      "riskLevel": "high",
      "credentialPolicy": "officialBrowser",
      "readOnlyTasks": [],
      "mutationTasks": []
    },
    {
      "id": "cloudflare-wrangler",
      "title": "Cloudflare Wrangler",
      "command": "wrangler",
      "category": "deploy",
      "supportLevel": "planned",
      "officialSources": [
        "https://developers.cloudflare.com/workers/wrangler/install-and-update/"
      ],
      "install": {
        "strategy": "npmGlobal",
        "profileId": null,
        "packages": [
          "wrangler"
        ]
      },
      "probe": {
        "taskKind": null,
        "safeArgs": [
          "wrangler --version"
        ]
      },
      "auth": {
        "required": true,
        "storage": "officialBrowser",
        "notes": "Cloudflare account/API token storage must be explicit."
      },
      "safetyNotes": [
        "Publish/delete commands require approval."
      ],
      "riskLevel": "high",
      "credentialPolicy": "officialBrowser",
      "readOnlyTasks": [],
      "mutationTasks": []
    },
    {
      "id": "aws-cli",
      "title": "AWS CLI",
      "command": "aws",
      "category": "cloud",
      "supportLevel": "planned",
      "officialSources": [
        "https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
      ],
      "install": {
        "strategy": "nativeInstaller",
        "profileId": null,
        "packages": [
          "awscli"
        ]
      },
      "probe": {
        "taskKind": null,
        "safeArgs": [
          "aws --version"
        ]
      },
      "auth": {
        "required": true,
        "storage": "secureStorage",
        "notes": "AWS credentials must never be written to catalog, logs, screenshots, or evidence."
      },
      "safetyNotes": [
        "Resource mutation commands require explicit account/region confirmation."
      ],
      "riskLevel": "high",
      "credentialPolicy": "secureStorage",
      "readOnlyTasks": [],
      "mutationTasks": []
    },
    {
      "id": "google-cloud-cli",
      "title": "Google Cloud CLI",
      "command": "gcloud",
      "category": "cloud",
      "supportLevel": "planned",
      "officialSources": [
        "https://cloud.google.com/sdk/docs/install"
      ],
      "install": {
        "strategy": "nativeInstaller",
        "profileId": null,
        "packages": [
          "google-cloud-cli"
        ]
      },
      "probe": {
        "taskKind": null,
        "safeArgs": [
          "gcloud --version"
        ]
      },
      "auth": {
        "required": true,
        "storage": "officialBrowser",
        "notes": "Google auth should share the official account boundary used by provider login."
      },
      "safetyNotes": [
        "Project and billing-affecting commands require confirmation."
      ],
      "riskLevel": "high",
      "credentialPolicy": "officialBrowser",
      "readOnlyTasks": [],
      "mutationTasks": []
    },
    {
      "id": "azure-cli",
      "title": "Azure CLI",
      "command": "az",
      "category": "cloud",
      "supportLevel": "planned",
      "officialSources": [
        "https://learn.microsoft.com/cli/azure/install-azure-cli-linux"
      ],
      "install": {
        "strategy": "nativeInstaller",
        "profileId": null,
        "packages": [
          "azure-cli"
        ]
      },
      "probe": {
        "taskKind": null,
        "safeArgs": [
          "az --version"
        ]
      },
      "auth": {
        "required": true,
        "storage": "officialBrowser",
        "notes": "Azure login/session state needs explicit user authorization."
      },
      "safetyNotes": [
        "Subscription/resource-group mutations require confirmation."
      ],
      "riskLevel": "high",
      "credentialPolicy": "officialBrowser",
      "readOnlyTasks": [],
      "mutationTasks": []
    }
  ]
}
''';
