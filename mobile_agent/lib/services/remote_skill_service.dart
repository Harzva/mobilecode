// lib/services/remote_skill_service.dart
// Remote Skill Service — Package SSH hosts as deployable Skills.
//
// Enables exporting/importing remote host configurations as shareable
// skill files, testing connections, and managing skill metadata.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'ssh_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Remote Skill Service
// ═══════════════════════════════════════════════════════════════════════════

/// Packages a remote SSH host as a deployable "Skill".
///
/// Skills can be:
/// - Exported as a JSON config file for sharing
/// - Imported from a config file
/// - Tested for connectivity before deployment
/// - Used as deployment targets for CI/CD workflows
///
/// ```dart
/// final service = RemoteSkillService(sshService);
/// final skill = await service.exportAsSkill(hostConfig);
/// final exported = await service.exportToFile(skill, '/path/to/save');
/// ```
class RemoteSkillService {
  final SshService _sshService;

  // Skill file version for forward compatibility.
  static const int _currentVersion = 1;

  /// Skill file extension.
  static const String skillFileExtension = '.mcskill';

  /// MIME type for skill files.
  static const String skillMimeType = 'application/json';

  RemoteSkillService(this._sshService);

  // ═════════════════════════════════════════════════════════════════
  // Export
  // ═════════════════════════════════════════════════════════════════

  /// Export a host configuration as a [SkillConfig].
  ///
  /// Creates a portable skill representation that can be shared
  /// with team members or imported on other devices.
  Future<SkillConfig> exportAsSkill(SshHostConfig host) async {
    final skill = SkillConfig(
      id: _generateSkillId(),
      name: host.name,
      description: 'SSH remote host: ${host.displayAddress}',
      version: '1.0.0',
      createdAt: DateTime.now(),
      hostConfig: host,
      metadata: {
        'exportedFrom': 'MobileCode',
        'exportVersion': _currentVersion.toString(),
        'hostType': _detectHostType(host),
      },
    );

    debugPrint(
        '[RemoteSkillService] Exported skill: ${skill.name} (${skill.id})');
    return skill;
  }

  /// Export a skill to a JSON file.
  ///
  /// Returns the absolute path to the exported file.
  Future<String> exportToFile(SkillConfig skill, String directory) async {
    final filename =
        '${_sanitizeFilename(skill.name)}_$skillFileExtension';
    final filePath = p.join(directory, filename);

    final jsonData = jsonEncode(skill.toJson());
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonData);

    debugPrint('[RemoteSkillService] Exported skill to: $filePath');
    return filePath;
  }

  /// Export a skill to a JSON string for clipboard sharing.
  String exportToString(SkillConfig skill) {
    return jsonEncode(skill.toJson());
  }

  // ═════════════════════════════════════════════════════════════════
  // Import
  // ═════════════════════════════════════════════════════════════════

  /// Import a [SkillConfig] and convert it to an [SshHostConfig].
  ///
  /// [skill] The skill configuration to import.
  /// [newName] Optional new display name for the imported host.
  /// [newTag] Optional tag to assign to the imported host.
  Future<SshHostConfig> importFromSkill(
    SkillConfig skill, {
    String? newName,
    String? newTag,
  }) async {
    // Validate skill version.
    if (skill.exportVersion > _currentVersion) {
      throw RemoteSkillException(
          'Skill version ${skill.exportVersion} is newer than '
          'supported version $_currentVersion. Please update MobileCode.');
    }

    // Create a new host config from the skill.
    final hostConfig = SshHostConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: newName ?? skill.name,
      host: skill.hostConfig.host,
      port: skill.hostConfig.port,
      username: skill.hostConfig.username,
      password: skill.hostConfig.password,
      privateKey: skill.hostConfig.privateKey,
      passphrase: skill.hostConfig.passphrase,
      workingDirectory: skill.hostConfig.workingDirectory,
      tag: newTag ?? skill.metadata['suggestedTag'],
    );

    debugPrint(
        '[RemoteSkillService] Imported skill: ${skill.name} -> ${hostConfig.name}');
    return hostConfig;
  }

  /// Import a skill from a JSON file.
  Future<SkillConfig> importFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw RemoteSkillException('Skill file not found: $filePath');
    }

    try {
      final content = await file.readAsString();
      return importFromString(content);
    } catch (e) {
      throw RemoteSkillException('Failed to read skill file: $e');
    }
  }

  /// Import a skill from a JSON string (e.g., from clipboard).
  SkillConfig importFromString(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return SkillConfig.fromJson(json);
    } on FormatException catch (e) {
      throw RemoteSkillException('Invalid skill JSON: $e');
    } catch (e) {
      throw RemoteSkillException('Failed to parse skill: $e');
    }
  }

  // ═════════════════════════════════════════════════════════════════
  // Connection Testing
  // ═════════════════════════════════════════════════════════════════

  /// Test if a skill's host can be connected to.
  ///
  /// Attempts to connect, run a basic command, and disconnect.
  /// Returns a [SkillTestResult] with detailed status.
  Future<SkillTestResult> testSkillConnection(SkillConfig skill) async {
    final stopwatch = Stopwatch()..start();
    final logs = <String>[];

    void log(String message) {
      logs.add('[${DateTime.now().toIso8601String()}] $message');
      debugPrint('[RemoteSkillService] Test: $message');
    }

    try {
      log('Starting connection test for ${skill.name}');

      // Step 1: Create temporary host config.
      final testHost = SshHostConfig(
        id: '_test_${skill.id}',
        name: 'Test: ${skill.name}',
        host: skill.hostConfig.host,
        port: skill.hostConfig.port,
        username: skill.hostConfig.username,
        password: skill.hostConfig.password,
        privateKey: skill.hostConfig.privateKey,
        passphrase: skill.hostConfig.passphrase,
      );

      // Step 2: Connect.
      log('Connecting to ${testHost.displayAddress}...');
      final client = await _sshService.connect(testHost);
      log('Connected successfully');

      // Step 3: Run diagnostic commands.
      final commands = [
        'whoami',
        'uname -a',
        'pwd',
        'echo "MobileCode skill test passed"',
      ];

      final commandOutputs = <String, String>{};
      for (final cmd in commands) {
        try {
          final result = await _sshService.execute(testHost.id, cmd,
              timeout: const Duration(seconds: 10));
          commandOutputs[cmd] = result.stdout.trim();
          log('$cmd: ${result.stdout.trim().split('\n').first}');
        } catch (e) {
          commandOutputs[cmd] = 'ERROR: $e';
          log('$cmd failed: $e');
        }
      }

      // Step 4: Test SFTP.
      log('Testing SFTP...');
      bool sftpWorks = false;
      try {
        await _sshService.listDirectory(testHost.id, '.');
        sftpWorks = true;
        log('SFTP test passed');
      } catch (e) {
        log('SFTP test failed: $e');
      }

      // Step 5: Disconnect.
      await _sshService.disconnect(testHost.id);
      log('Disconnected');

      stopwatch.stop();

      return SkillTestResult(
        success: true,
        duration: stopwatch.elapsed,
        logs: logs,
        commandOutputs: commandOutputs,
        sftpWorks: sftpWorks,
        hostInfo: {
          'username': commandOutputs['whoami'] ?? 'unknown',
          'system': commandOutputs['uname -a'] ?? 'unknown',
          'homeDirectory': commandOutputs['pwd'] ?? 'unknown',
        },
      );
    } on SocketException catch (e) {
      stopwatch.stop();
      log('Connection failed (network): $e');
      return SkillTestResult(
        success: false,
        duration: stopwatch.elapsed,
        logs: logs,
        error: 'Network error: ${e.message}',
        errorType: SkillErrorType.network,
      );
    } on SshServiceException catch (e) {
      stopwatch.stop();
      log('Connection failed (SSH): $e');
      return SkillTestResult(
        success: false,
        duration: stopwatch.elapsed,
        logs: logs,
        error: e.toString(),
        errorType: _classifyError(e.toString()),
      );
    } catch (e) {
      stopwatch.stop();
      log('Connection failed (unexpected): $e');
      return SkillTestResult(
        success: false,
        duration: stopwatch.elapsed,
        logs: logs,
        error: 'Unexpected error: $e',
        errorType: SkillErrorType.unknown,
      );
    }
  }

  /// Quick connectivity check ( lighter than full test ).
  Future<bool> quickTestConnection(SkillConfig skill) async {
    try {
      final testHost = SshHostConfig(
        id: '_quicktest_${DateTime.now().millisecondsSinceEpoch}',
        name: 'QuickTest',
        host: skill.hostConfig.host,
        port: skill.hostConfig.port,
        username: skill.hostConfig.username,
        password: skill.hostConfig.password,
        privateKey: skill.hostConfig.privateKey,
        passphrase: skill.hostConfig.passphrase,
      );

      await _sshService.connect(testHost);
      await _sshService.execute(testHost.id, 'echo ok',
          timeout: const Duration(seconds: 10));
      await _sshService.disconnect(testHost.id);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ═════════════════════════════════════════════════════════════════
  // Skill Management
  // ═════════════════════════════════════════════════════════════════

  /// Create a skill from an existing host config with additional metadata.
  Future<SkillConfig> createSkill({
    required SshHostConfig host,
    required String name,
    String? description,
    String version = '1.0.0',
    Map<String, String>? metadata,
  }) async {
    final mergedMetadata = <String, String>{
      'hostType': _detectHostType(host),
      'authType': host.usesKeyAuth ? 'key' : 'password',
      'exportedFrom': 'MobileCode',
      ...?metadata,
    };

    return SkillConfig(
      id: _generateSkillId(),
      name: name,
      description: description ?? 'SSH remote host: ${host.displayAddress}',
      version: version,
      createdAt: DateTime.now(),
      hostConfig: host,
      metadata: mergedMetadata,
    );
  }

  /// Update skill metadata without changing the host config.
  SkillConfig updateSkillMetadata(
    SkillConfig skill, {
    String? name,
    String? description,
    String? version,
    Map<String, String>? metadata,
  }) {
    return skill.copyWith(
      name: name,
      description: description,
      version: version,
      metadata: metadata != null ? {...skill.metadata, ...metadata} : null,
      updatedAt: DateTime.now(),
    );
  }

  /// Duplicate a skill with a new ID.
  SkillConfig duplicateSkill(SkillConfig skill, {String? newName}) {
    return skill.copyWith(
      id: _generateSkillId(),
      name: newName ?? '${skill.name} (Copy)',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // Batch Operations
  // ═════════════════════════════════════════════════════════════════

  /// Test multiple skills in parallel.
  Future<Map<String, SkillTestResult>> testMultipleSkills(
    List<SkillConfig> skills, {
    void Function(String skillName, SkillTestResult result)? onResult,
  }) async {
    final results = <String, SkillTestResult>{};

    await Future.wait(
      skills.map((skill) async {
        final result = await testSkillConnection(skill);
        results[skill.id] = result;
        onResult?.call(skill.name, result);
      }),
    );

    return results;
  }

  /// Export multiple skills to a directory.
  Future<List<String>> exportMultipleSkills(
    List<SkillConfig> skills,
    String directory,
  ) async {
    final paths = <String>[];

    for (final skill in skills) {
      try {
        final path = await exportToFile(skill, directory);
        paths.add(path);
      } catch (e) {
        debugPrint('[RemoteSkillService] Failed to export ${skill.name}: $e');
      }
    }

    return paths;
  }

  // ═════════════════════════════════════════════════════════════════
  // Utility
  // ═════════════════════════════════════════════════════════════════

  /// Generate a unique skill ID.
  String _generateSkillId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = (DateTime.now().microsecond * 997) % 10000;
    return 'skill_${timestamp}_$random';
  }

  /// Sanitize a string for use as a filename.
  String _sanitizeFilename(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
  }

  /// Detect the likely host type based on configuration.
  String _detectHostType(SshHostConfig host) {
    final lowerHost = host.host.toLowerCase();

    if (lowerHost.contains('aws') || lowerHost.contains('amazon')) {
      return 'aws_ec2';
    }
    if (lowerHost.contains('gcp') || lowerHost.contains('google')) {
      return 'gcp_compute';
    }
    if (lowerHost.contains('azure') || lowerHost.contains('cloudapp')) {
      return 'azure_vm';
    }
    if (lowerHost.contains('digitalocean') || lowerHost.contains('do-')) {
      return 'digitalocean_droplet';
    }
    if (lowerHost.contains('linode') || lowerHost.contains('li-')) {
      return 'linode_instance';
    }
    if (lowerHost.contains('hetzner') || lowerHost.contains('your-')) {
      return 'hetzner_cloud';
    }
    if (RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(host.host)) {
      return 'bare_metal_ip';
    }
    if (lowerHost.contains('local') || lowerHost.contains('127.0.0.1')) {
      return 'local';
    }

    return 'generic_ssh';
  }

  /// Classify an error message into a [SkillErrorType].
  SkillErrorType _classifyError(String error) {
    final lower = error.toLowerCase();
    if (lower.contains('auth')) return SkillErrorType.authentication;
    if (lower.contains('connect') || lower.contains('network')) {
      return SkillErrorType.network;
    }
    if (lower.contains('timeout')) return SkillErrorType.timeout;
    if (lower.contains('permission')) return SkillErrorType.permission;
    if (lower.contains('dns') || lower.contains('resolve')) {
      return SkillErrorType.dns;
    }
    return SkillErrorType.unknown;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Skill Config
// ═══════════════════════════════════════════════════════════════════════════

/// A deployable skill configuration for a remote SSH host.
///
/// Encapsulates everything needed to connect to and use a remote
/// server as a development environment.
class SkillConfig {
  /// Unique skill identifier.
  final String id;

  /// Display name for the skill.
  final String name;

  /// Description of what this skill provides.
  final String description;

  /// Semantic version string.
  final String version;

  /// When the skill was created.
  final DateTime createdAt;

  /// When the skill was last updated.
  final DateTime? updatedAt;

  /// The underlying SSH host configuration.
  final SshHostConfig hostConfig;

  /// Arbitrary metadata key-value pairs.
  final Map<String, String> metadata;

  /// Export format version for forward compatibility.
  final int exportVersion;

  SkillConfig({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.createdAt,
    this.updatedAt,
    required this.hostConfig,
    this.metadata = const {},
    this.exportVersion = RemoteSkillService._currentVersion,
  });

  /// Create from JSON map.
  factory SkillConfig.fromJson(Map<String, dynamic> json) {
    return SkillConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      version: json['version'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
      hostConfig: SshHostConfig.fromJson(
        json['hostConfig'] as Map<String, dynamic>,
      ),
      metadata: (json['metadata'] as Map<String, dynamic>?)
              ?.cast<String, String>() ??
          const {},
      exportVersion: json['exportVersion'] as int? ?? 1,
    );
  }

  /// Convert to JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'version': version,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'hostConfig': hostConfig.toJson(),
      'metadata': metadata,
      'exportVersion': exportVersion,
    };
  }

  /// Create a copy with modified fields.
  SkillConfig copyWith({
    String? id,
    String? name,
    String? description,
    String? version,
    DateTime? createdAt,
    DateTime? updatedAt,
    SshHostConfig? hostConfig,
    Map<String, String>? metadata,
    int? exportVersion,
  }) {
    return SkillConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      version: version ?? this.version,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      hostConfig: hostConfig ?? this.hostConfig,
      metadata: metadata ?? this.metadata,
      exportVersion: exportVersion ?? this.exportVersion,
    );
  }

  /// Whether credentials are included in this skill.
  bool get hasCredentials =>
      hostConfig.password != null || hostConfig.privateKey != null;

  @override
  String toString() => 'SkillConfig[$name] v$version (${hostConfig.host})';
}

// ═══════════════════════════════════════════════════════════════════════════
// Skill Test Result
// ═══════════════════════════════════════════════════════════════════════════

/// Result of testing a skill's connection.
class SkillTestResult {
  /// Whether the test succeeded.
  final bool success;

  /// Time taken to run the test.
  final Duration duration;

  /// Log messages from the test.
  final List<String> logs;

  /// Output from diagnostic commands (cmd -> output).
  final Map<String, String>? commandOutputs;

  /// Whether SFTP is working.
  final bool sftpWorks;

  /// Extracted host information.
  final Map<String, String>? hostInfo;

  /// Error message if the test failed.
  final String? error;

  /// Type of error if the test failed.
  final SkillErrorType? errorType;

  SkillTestResult({
    required this.success,
    required this.duration,
    required this.logs,
    this.commandOutputs,
    this.sftpWorks = false,
    this.hostInfo,
    this.error,
    this.errorType,
  });

  /// Whether SFTP file transfer is available.
  bool get canTransferFiles => success && sftpWorks;

  /// Whether this skill is ready for deployment.
  bool get isDeployable => success;

  /// Get a summary string of the test result.
  String get summary {
    if (success) {
      final info = hostInfo;
      if (info != null) {
        return 'Connected as ${info['username']} on ${info['system']?.split(' ').first} '
            '(${duration.inMilliseconds}ms)';
      }
      return 'Connected (${duration.inMilliseconds}ms)';
    }
    return 'Failed: $error (${duration.inMilliseconds}ms)';
  }

  @override
  String toString() => 'SkillTestResult(success=$success, ${duration.inMilliseconds}ms)';
}

// ═══════════════════════════════════════════════════════════════════════════
// Skill Error Type
// ═══════════════════════════════════════════════════════════════════════════

/// Classification of skill connection errors.
enum SkillErrorType {
  /// Network unreachable or connection refused.
  network,

  /// Authentication failed (wrong password/key).
  authentication,

  /// Connection timed out.
  timeout,

  /// DNS resolution failed.
  dns,

  /// Permission denied after connection.
  permission,

  /// Unknown or unclassified error.
  unknown,
}

// ═══════════════════════════════════════════════════════════════════════════
// Exceptions
// ═══════════════════════════════════════════════════════════════════════════

/// Exception thrown by the Remote Skill Service.
class RemoteSkillException implements Exception {
  final String message;

  const RemoteSkillException(this.message);

  @override
  String toString() => 'RemoteSkillException: $message';
}
