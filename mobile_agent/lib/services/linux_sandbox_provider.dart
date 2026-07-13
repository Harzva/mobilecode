import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/evidence/evidence_model.dart';
import 'runtime_provider.dart';
import 'termux_service.dart';

typedef LinuxSandboxRootfsDownloader = Future<List<int>> Function(
  LinuxSandboxRootfsManifest manifest,
  void Function(int receivedBytes, int? totalBytes) onProgress,
);

typedef LinuxSandboxRootfsExtractor = Future<void> Function(
  List<int> archiveBytes,
  Directory rootfsDirectory,
);

typedef LinuxSandboxBaseDirectoryResolver = Future<Directory> Function();

abstract class LinuxSandboxNativeBridge {
  Future<Map<String, dynamic>> status();
  Future<Map<String, dynamic>> setup(LinuxSandboxRootfsManifest manifest);
  Future<Map<String, dynamic>> reset();
  Future<Map<String, dynamic>> runTypedTask({
    required String taskKind,
    required Map<String, dynamic> payload,
  });
}

class MethodChannelLinuxSandboxNativeBridge
    implements LinuxSandboxNativeBridge {
  const MethodChannelLinuxSandboxNativeBridge();

  static const MethodChannel _channel =
      MethodChannel('mobilecode/system_tools');

  @override
  Future<Map<String, dynamic>> status() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'linuxSandboxStatus',
    );
    return _stringKeyMap(raw);
  }

  @override
  Future<Map<String, dynamic>> setup(
      LinuxSandboxRootfsManifest manifest) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'linuxSandboxSetup',
      {'manifest': manifest.toJson()},
    );
    return _stringKeyMap(raw);
  }

  @override
  Future<Map<String, dynamic>> reset() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'linuxSandboxReset',
    );
    return _stringKeyMap(raw);
  }

  @override
  Future<Map<String, dynamic>> runTypedTask({
    required String taskKind,
    required Map<String, dynamic> payload,
  }) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'linuxSandboxRunTypedTask',
      {'taskKind': taskKind, 'payload': payload},
    );
    return _stringKeyMap(raw);
  }
}

enum LinuxSandboxInstallStatus {
  idle,
  downloading,
  verifying,
  extracting,
  installed,
  failed,
  cancelled,
}

enum LinuxSandboxPackageProfileStatus {
  available,
  installing,
  installed,
  needsUpdate,
  failed,
}

class LinuxSandboxRootfsManifest {
  const LinuxSandboxRootfsManifest({
    required this.id,
    required this.version,
    required this.arch,
    required this.url,
    required this.sha256,
    required this.compressedSizeBytes,
    required this.extractedSizeBytes,
    required this.license,
    required this.source,
    required this.publishedAt,
  });

  final String id;
  final String version;
  final String arch;
  final String url;
  final String sha256;
  final int compressedSizeBytes;
  final int extractedSizeBytes;
  final String license;
  final String source;
  final DateTime publishedAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'version': version,
        'arch': arch,
        'url': url,
        'sha256': sha256,
        'compressedSizeBytes': compressedSizeBytes,
        'extractedSizeBytes': extractedSizeBytes,
        'license': license,
        'source': source,
        'publishedAt': publishedAt.toIso8601String(),
      };

  factory LinuxSandboxRootfsManifest.fromJson(Map<String, Object?> json) {
    return LinuxSandboxRootfsManifest(
      id: _string(json['id']),
      version: _string(json['version']),
      arch: _string(json['arch']),
      url: _string(json['url']),
      sha256: _string(json['sha256']),
      compressedSizeBytes: _int(json['compressedSizeBytes']),
      extractedSizeBytes: _int(json['extractedSizeBytes']),
      license: _string(json['license']),
      source: _string(json['source']),
      publishedAt: DateTime.parse(_string(json['publishedAt'])),
    );
  }
}

class LinuxSandboxPackageProfile {
  const LinuxSandboxPackageProfile({
    required this.id,
    required this.label,
    required this.packages,
    required this.capabilityDeltas,
    required this.estimatedDownloadBytes,
    required this.estimatedInstalledBytes,
    this.status = LinuxSandboxPackageProfileStatus.available,
    this.failureKind,
    this.recoveryHint,
  });

  final String id;
  final String label;
  final List<String> packages;
  final List<String> capabilityDeltas;
  final int estimatedDownloadBytes;
  final int estimatedInstalledBytes;
  final LinuxSandboxPackageProfileStatus status;
  final String? failureKind;
  final String? recoveryHint;

  bool get installed => status == LinuxSandboxPackageProfileStatus.installed;

  LinuxSandboxPackageProfile copyWith({
    LinuxSandboxPackageProfileStatus? status,
    String? failureKind,
    String? recoveryHint,
    bool clearFailure = false,
  }) {
    return LinuxSandboxPackageProfile(
      id: id,
      label: label,
      packages: packages,
      capabilityDeltas: capabilityDeltas,
      estimatedDownloadBytes: estimatedDownloadBytes,
      estimatedInstalledBytes: estimatedInstalledBytes,
      status: status ?? this.status,
      failureKind: clearFailure ? null : failureKind ?? this.failureKind,
      recoveryHint: clearFailure ? null : recoveryHint ?? this.recoveryHint,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'label': label,
        'packages': packages,
        'capabilityDeltas': capabilityDeltas,
        'estimatedDownloadBytes': estimatedDownloadBytes,
        'estimatedInstalledBytes': estimatedInstalledBytes,
        'status': status.name,
        'failureKind': failureKind,
        'recoveryHint': recoveryHint,
      };
}

class LinuxSandboxState {
  const LinuxSandboxState({
    required this.manifest,
    required this.status,
    required this.rootfsPath,
    required this.rootfsVerified,
    required this.packageProfiles,
    this.progress = 0,
    this.failureKind,
    this.recoveryHint,
    this.lastCheckedAt,
  });

  factory LinuxSandboxState.uninstalled({
    LinuxSandboxRootfsManifest? manifest,
    DateTime? checkedAt,
  }) {
    return LinuxSandboxState(
      manifest: manifest ?? LinuxSandboxManifests.alpineMiniRootfsAarch64,
      status: LinuxSandboxInstallStatus.idle,
      rootfsPath: '',
      rootfsVerified: false,
      packageProfiles: LinuxSandboxPackageProfiles.defaults,
      failureKind: 'rootfs_missing',
      recoveryHint:
          'Install and verify the Alpine minirootfs before running Linux Sandbox tasks.',
      lastCheckedAt: checkedAt,
    );
  }

  final LinuxSandboxRootfsManifest manifest;
  final LinuxSandboxInstallStatus status;
  final String rootfsPath;
  final bool rootfsVerified;
  final List<LinuxSandboxPackageProfile> packageProfiles;
  final double progress;
  final String? failureKind;
  final String? recoveryHint;
  final DateTime? lastCheckedAt;

  bool get installed =>
      status == LinuxSandboxInstallStatus.installed && rootfsVerified;

  LinuxSandboxState copyWith({
    LinuxSandboxInstallStatus? status,
    String? rootfsPath,
    bool? rootfsVerified,
    List<LinuxSandboxPackageProfile>? packageProfiles,
    double? progress,
    String? failureKind,
    String? recoveryHint,
    DateTime? lastCheckedAt,
    bool clearFailure = false,
  }) {
    return LinuxSandboxState(
      manifest: manifest,
      status: status ?? this.status,
      rootfsPath: rootfsPath ?? this.rootfsPath,
      rootfsVerified: rootfsVerified ?? this.rootfsVerified,
      packageProfiles: packageProfiles ?? this.packageProfiles,
      progress: progress ?? this.progress,
      failureKind: clearFailure ? null : failureKind ?? this.failureKind,
      recoveryHint: clearFailure ? null : recoveryHint ?? this.recoveryHint,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    );
  }
}

class LinuxSandboxManifests {
  const LinuxSandboxManifests._();

  static final alpineMiniRootfsAarch64 = LinuxSandboxRootfsManifest(
    id: 'alpine-minirootfs-aarch64-3.24.1',
    version: '3.24.1',
    arch: 'aarch64',
    url:
        'https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/aarch64/alpine-minirootfs-3.24.1-aarch64.tar.gz',
    sha256: 'f55a90f69052c5bd6f92cb09a8f47065970830b194c917a006fb94028e721259',
    compressedSizeBytes: 4023732,
    extractedSizeBytes: 8949760,
    license: 'Alpine Linux distribution licenses',
    source:
        'https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/aarch64/latest-releases.yaml',
    publishedAt: DateTime.utc(2026, 6, 13, 16, 39, 19),
  );

  static final alpineMiniRootfsX8664 = LinuxSandboxRootfsManifest(
    id: 'alpine-minirootfs-x86_64-3.24.1',
    version: '3.24.1',
    arch: 'x86_64',
    url:
        'https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/alpine-minirootfs-3.24.1-x86_64.tar.gz',
    sha256: '41f73e3cf5fa919b8aa5ca6b30dc48f0da2720776d7423e2a7748211456fe081',
    compressedSizeBytes: 3698422,
    extractedSizeBytes: 8704000,
    license: 'Alpine Linux distribution licenses',
    source:
        'https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/latest-releases.yaml',
    publishedAt: DateTime.utc(2026, 6, 13, 16, 38, 57),
  );
}

class LinuxSandboxPackageProfiles {
  const LinuxSandboxPackageProfiles._();

  static const base = LinuxSandboxPackageProfile(
    id: 'base',
    label: 'Base',
    packages: ['busybox', 'apk-tools'],
    capabilityDeltas: ['packageManager'],
    estimatedDownloadBytes: 0,
    estimatedInstalledBytes: 0,
    status: LinuxSandboxPackageProfileStatus.installed,
  );

  static const devBasic = LinuxSandboxPackageProfile(
    id: 'devBasic',
    label: 'Dev Basic',
    packages: ['git', 'curl', 'ca-certificates'],
    capabilityDeltas: ['git', 'networkTools'],
    estimatedDownloadBytes: 9000000,
    estimatedInstalledBytes: 32000000,
  );

  static const pythonPack = LinuxSandboxPackageProfile(
    id: 'pythonPack',
    label: 'Python Pack',
    packages: ['python3', 'py3-pip'],
    capabilityDeltas: ['python'],
    estimatedDownloadBytes: 24000000,
    estimatedInstalledBytes: 90000000,
  );

  static const nodePack = LinuxSandboxPackageProfile(
    id: 'nodePack',
    label: 'Node Pack',
    packages: ['nodejs', 'npm'],
    capabilityDeltas: ['node', 'npm'],
    estimatedDownloadBytes: 18000000,
    estimatedInstalledBytes: 76000000,
  );

  static const hyperframesCli = LinuxSandboxPackageProfile(
    id: 'hyperframesCli',
    label: 'HyperFrames CLI',
    packages: [
      'nodejs',
      'npm',
      'chromium',
      'ffmpeg',
      'ca-certificates',
      'hyperframes',
    ],
    capabilityDeltas: [
      'hyperframesCli',
      'htmlLint',
      'htmlCheck',
      'htmlRender',
      'node',
      'browserRuntime',
      'ffmpeg',
    ],
    estimatedDownloadBytes: 185000000,
    estimatedInstalledBytes: 520000000,
  );

  static const larkCli = LinuxSandboxPackageProfile(
    id: 'larkCli',
    label: 'Lark CLI',
    packages: ['nodejs', 'npm', 'curl', 'ca-certificates', '@larksuite/cli'],
    capabilityDeltas: ['larkCli', 'larkOpenApiProbe', 'node', 'networkTools'],
    estimatedDownloadBytes: 42000000,
    estimatedInstalledBytes: 142000000,
  );

  static const agentMailCli = LinuxSandboxPackageProfile(
    id: 'agentMailCli',
    label: 'Agent Mail CLI',
    packages: [
      'nodejs',
      'npm',
      'curl',
      'ca-certificates',
      '@tencent-qqmail/agently-cli',
    ],
    capabilityDeltas: ['agentMailCli', 'mailProbe', 'node', 'networkTools'],
    estimatedDownloadBytes: 36000000,
    estimatedInstalledBytes: 128000000,
  );

  static const googleWorkspaceCli = LinuxSandboxPackageProfile(
    id: 'googleWorkspaceCli',
    label: 'Google Workspace CLI',
    packages: [
      'nodejs',
      'npm',
      'curl',
      'ca-certificates',
      '@googleworkspace/cli',
    ],
    capabilityDeltas: [
      'googleWorkspaceCli',
      'googleWorkspaceProbe',
      'googleDriveRead',
      'node',
      'networkTools',
    ],
    estimatedDownloadBytes: 52000000,
    estimatedInstalledBytes: 190000000,
  );

  static const githubCli = LinuxSandboxPackageProfile(
    id: 'githubCli',
    label: 'GitHub CLI',
    packages: ['github-cli', 'git', 'curl', 'ca-certificates'],
    capabilityDeltas: [
      'githubCli',
      'githubAuthProbe',
      'githubRepoRead',
      'git',
      'networkTools',
    ],
    estimatedDownloadBytes: 22000000,
    estimatedInstalledBytes: 84000000,
  );

  static const defaults = [
    base,
    devBasic,
    pythonPack,
    nodePack,
    hyperframesCli,
    larkCli,
    agentMailCli,
    googleWorkspaceCli,
    githubCli,
  ];
}

class LinuxSandboxRuntimeProvider
    implements
        RuntimeProvider,
        RuntimeTypedTaskRunner,
        RuntimeTaskMonitor,
        RuntimeTaskController {
  LinuxSandboxRuntimeProvider({
    LinuxSandboxState? initialState,
    LinuxSandboxRootfsDownloader? downloader,
    LinuxSandboxRootfsExtractor? extractor,
    LinuxSandboxBaseDirectoryResolver? baseDirectoryResolver,
    LinuxSandboxNativeBridge? nativeBridge,
    bool? useNativeRunner,
  })  : _state = initialState ?? LinuxSandboxState.uninstalled(),
        _downloader = downloader ?? _defaultDownloader,
        _extractor = extractor ?? _extractTarGz,
        _baseDirectoryResolver =
            baseDirectoryResolver ?? _defaultBaseDirectoryResolver,
        _nativeBridge =
            nativeBridge ?? const MethodChannelLinuxSandboxNativeBridge(),
        _useNativeRunner = useNativeRunner ?? Platform.isAndroid;

  final StreamController<String> _logs = StreamController<String>.broadcast();
  final LinuxSandboxRootfsDownloader _downloader;
  final LinuxSandboxRootfsExtractor _extractor;
  final LinuxSandboxBaseDirectoryResolver _baseDirectoryResolver;
  final LinuxSandboxNativeBridge _nativeBridge;
  final bool _useNativeRunner;
  LinuxSandboxState _state;
  bool _cancelInstall = false;
  RuntimeTaskSnapshot? _currentTask;
  final List<RuntimeTaskSnapshot> _taskHistory = [];
  final Map<String, List<String>> _taskLogs = {};
  final Set<String> _stopRequestedTaskIds = {};

  LinuxSandboxState get state => _state;

  set state(LinuxSandboxState value) {
    _state = value;
  }

  List<ActionEvidence> get evidence => List.unmodifiable(_evidence);
  final List<ActionEvidence> _evidence = [];

  @override
  RuntimeProviderType get type => RuntimeProviderType.linuxSandbox;

  @override
  String get name => 'Linux Sandbox';

  @override
  Stream<String> get logStream => _logs.stream;

  @override
  Future<void> initialize() async {
    if (!_useNativeRunner) return;
    final status = await _nativeBridge.status();
    _applyNativeStatus(status);
  }

  Future<LinuxSandboxState> installRootfs() async {
    if (_useNativeRunner) {
      return _installRootfsNative();
    }
    final startedAt = DateTime.now();
    _cancelInstall = false;
    _setState(_state.copyWith(
      status: LinuxSandboxInstallStatus.downloading,
      progress: 0.02,
      rootfsVerified: false,
      clearFailure: true,
      lastCheckedAt: startedAt,
    ));
    _logs.add('[linux-sandbox] rootfs download started: ${_state.manifest.id}');

    try {
      final archiveBytes = await _downloader(
        _state.manifest,
        (received, total) {
          if (total != null && total > 0) {
            final ratio = received / total;
            _setState(_state.copyWith(
              progress: math.min(0.65, math.max(0.02, ratio * 0.65)),
              clearFailure: true,
            ));
          }
        },
      );
      if (_cancelInstall) return _cancelledRootfsInstall(startedAt);

      _setState(_state.copyWith(
        status: LinuxSandboxInstallStatus.verifying,
        progress: 0.7,
        clearFailure: true,
      ));
      final digest = sha256.convert(archiveBytes).toString();
      if (digest.toLowerCase() != _state.manifest.sha256.toLowerCase()) {
        return _failRootfsInstall(
          startedAt: startedAt,
          failureKind: 'checksum_mismatch',
          recoveryHint: '删除暂存文件后重试；如果仍失败，更新 manifest SHA-256 后再安装。',
          log:
              'sha256 mismatch: expected ${_state.manifest.sha256}, got $digest',
        );
      }
      if (_cancelInstall) return _cancelledRootfsInstall(startedAt);

      _setState(_state.copyWith(
        status: LinuxSandboxInstallStatus.extracting,
        progress: 0.78,
        clearFailure: true,
      ));
      final baseDir = await _sandboxBaseDirectory();
      final rootfsDir = Directory(p.join(baseDir.path, 'rootfs'));
      if (!p.isWithin(baseDir.path, rootfsDir.path)) {
        return _failRootfsInstall(
          startedAt: startedAt,
          failureKind: 'rootfs_path_outside_app_storage',
          recoveryHint: 'Linux Sandbox rootfs 只能安装到 app-owned storage。',
          log: 'blocked rootfs path outside app storage: ${rootfsDir.path}',
        );
      }
      if (rootfsDir.existsSync()) {
        await rootfsDir.delete(recursive: true);
      }
      await rootfsDir.create(recursive: true);
      await _extractor(archiveBytes, rootfsDir);
      if (_cancelInstall) return _cancelledRootfsInstall(startedAt);

      await File(p.join(baseDir.path, 'manifest.json'))
          .writeAsString(jsonEncode(_state.manifest.toJson()));
      _setState(_state.copyWith(
        status: LinuxSandboxInstallStatus.installed,
        rootfsPath: rootfsDir.path,
        rootfsVerified: true,
        progress: 1,
        clearFailure: true,
        lastCheckedAt: DateTime.now(),
      ));
      _recordEvidence(ActionEvidence(
        evidenceId: generateEvidenceId(),
        actionName: MobileCodeAction.termuxTaskStart,
        paramsSummary: 'linux_sandbox_rootfs_install ${_state.manifest.id}',
        startedAt: startedAt,
        success: true,
        artifactPaths: [rootfsDir.path],
        logs: const ['downloaded', 'verified', 'extracted'],
        metadata: {
          'runtime': 'linuxSandbox',
          'operation': 'rootfs_install',
          'manifestId': _state.manifest.id,
          'sha256': _state.manifest.sha256,
        },
      ));
      _logs.add('[linux-sandbox] rootfs installed: ${rootfsDir.path}');
      return _state;
    } catch (error) {
      return _failRootfsInstall(
        startedAt: startedAt,
        failureKind: 'rootfs_install_failed',
        recoveryHint: '检查网络、存储空间和 rootfs manifest 后重试。',
        log: error.toString(),
      );
    }
  }

  Future<LinuxSandboxState> deleteRootfs() async {
    if (_useNativeRunner) {
      final startedAt = DateTime.now();
      final result = _redactLinuxSandboxNativeResult(
        await _nativeBridge.reset(),
      );
      _setState(LinuxSandboxState.uninstalled(
        manifest: _state.manifest,
        checkedAt: DateTime.now(),
      ));
      _recordEvidence(_evidenceFromNativeResult(
        result,
        startedAt: startedAt,
        paramsSummary: 'linux_sandbox_rootfs_delete ${_state.manifest.id}',
      ));
      return _state;
    }
    final startedAt = DateTime.now();
    final baseDir = await _sandboxBaseDirectory();
    if (baseDir.existsSync()) {
      await baseDir.delete(recursive: true);
    }
    _setState(LinuxSandboxState.uninstalled(
      manifest: _state.manifest,
      checkedAt: DateTime.now(),
    ));
    _recordEvidence(ActionEvidence(
      evidenceId: generateEvidenceId(),
      actionName: MobileCodeAction.termuxTaskStart,
      paramsSummary: 'linux_sandbox_rootfs_delete ${_state.manifest.id}',
      startedAt: startedAt,
      success: true,
      logs: const ['deleted app-owned linux-sandbox directory'],
      metadata: {
        'runtime': 'linuxSandbox',
        'operation': 'rootfs_delete',
        'manifestId': _state.manifest.id,
      },
    ));
    return _state;
  }

  Future<LinuxSandboxState> resetRootfs() => deleteRootfs();

  void cancelRootfsInstall() {
    _cancelInstall = true;
    _logs.add('[linux-sandbox] rootfs install cancellation requested');
  }

  ActionEvidence previewPackageProfileInstall(String profileId) {
    final profile = _profileById(profileId);
    final startedAt = DateTime.now();
    if (profile == null) {
      return ActionEvidence(
        evidenceId: generateEvidenceId(),
        actionName: MobileCodeAction.termuxTaskStart,
        paramsSummary: 'linux_sandbox_package_install unknown',
        startedAt: startedAt,
        success: false,
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: const ['选择内置 Package Profile，不能让模型请求任意包名。'],
        metadata: const {
          'runtime': 'linuxSandbox',
          'operation': 'package_profile_install',
          'approved': false,
        },
      );
    }
    return ActionEvidence(
      evidenceId: generateEvidenceId(),
      actionName: MobileCodeAction.termuxTaskStart,
      paramsSummary: 'linux_sandbox_package_install ${profile.id}',
      startedAt: startedAt,
      success: false,
      failureKind: _state.installed
          ? ActionFailureKind.dependencyMissing
          : 'approvalRequired',
      recoveryActions: [
        if (!_state.installed) '先安装并校验 Alpine rootfs。',
        '用户确认后才能安装 ${profile.label}。',
        'runner proof 接通前不会执行 apk add。',
      ],
      metadata: {
        'runtime': 'linuxSandbox',
        'operation': 'package_profile_install',
        'profileId': profile.id,
        'profileName': profile.label,
        'packages': profile.packages,
        'estimatedDownloadBytes': profile.estimatedDownloadBytes,
        'estimatedInstalledBytes': profile.estimatedInstalledBytes,
        'approved': false,
      },
    );
  }

  @override
  Future<RuntimeCapabilities> capabilities() async {
    if (!_state.installed) {
      return RuntimeCapabilities(
        rootfsInstalled: false,
        rootfsVerified: _state.rootfsVerified,
        packageProfiles: _state.packageProfiles
            .where((profile) => profile.installed)
            .map((profile) => profile.id)
            .toList(growable: false),
        networkPolicy: 'disabled',
        rawShellAllowed: false,
      );
    }
    return RuntimeCapabilities(
      git: _profileInstalled('devBasic'),
      node: _profileInstalled('nodePack'),
      python: _profileInstalled('pythonPack'),
      packageManager: _profileInstalled('base'),
      rootfsInstalled: true,
      rootfsVerified: true,
      packageProfiles: _state.packageProfiles
          .where((profile) => profile.installed)
          .map((profile) => profile.id)
          .toList(growable: false),
      networkPolicy: 'package-sources-only',
      rawShellAllowed: false,
      writableMounts: const ['workspace'],
    );
  }

  @override
  Future<RuntimeHealth> healthCheck() async {
    final caps = await capabilities();
    if (!_state.installed) {
      return RuntimeHealth(
        type: type,
        name: name,
        available: false,
        ready: false,
        status:
            'Linux Sandbox rootfs is not installed. Alpine ${_state.manifest.version} ${_state.manifest.arch} is available for install.',
        capabilities: caps,
        missingDependencies: const ['Alpine rootfs'],
        recoveryActions: [
          _state.recoveryHint ??
              'Install and verify the Alpine minirootfs before running Linux Sandbox tasks.',
        ],
      );
    }

    return RuntimeHealth(
      type: type,
      name: name,
      available: true,
      ready: true,
      status:
          'Linux Sandbox rootfs is installed and verified. Agent raw shell remains disabled.',
      capabilities: caps,
      recoveryActions: const [
        'Install package profiles before running Git, Node, or Python tasks.',
      ],
    );
  }

  @override
  Future<RuntimeCommandResult> execute(
    String command, {
    String? workingDir,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    return RuntimeCommandResult(
      command: command,
      stdout: '',
      stderr:
          'Linux Sandbox blocks raw shell execution for agents. Use typed tasks instead.',
      exitCode: 126,
      duration: Duration.zero,
      providerType: type,
      failureKind: RuntimeTaskFailureKind.commandBlocked,
    );
  }

  @override
  Stream<String> executeStream(
    String command, {
    String? workingDir,
    Map<String, String>? environment,
  }) async* {
    yield '[runtime] Linux Sandbox blocks raw shell execution for agents. Use typed tasks instead.';
  }

  @override
  Future<Map<String, dynamic>> runTypedTask({
    required String taskKind,
    required Map<String, dynamic> payload,
  }) async {
    final safeKind = taskKind.trim();
    const allowedKinds = {
      'apk_version',
      'project_check',
      'package_install',
      'git_version',
      'node_version',
      'npm_version',
      'lark_cli_probe',
      'lark_cli_auth_start',
      'lark_cli_auth_status',
      'lark_cli_execute',
      'agently_cli_probe',
      'agently_cli_auth_start',
      'agently_cli_me',
      'agently_cli_execute',
      'gws_cli_probe',
      'gws_cli_auth_setup',
      'gws_cli_auth_login',
      'gws_cli_auth_status',
      'gws_cli_execute',
      'github_cli_probe',
      'github_cli_auth_login',
      'github_cli_auth_status',
      'github_cli_execute',
      'npm_build',
      'hyperframes_cli_probe',
      'hyperframes_lint',
      'hyperframes_check',
      'hyperframes_compositions',
      'hyperframes_render',
    };
    if (!allowedKinds.contains(safeKind)) {
      return _typedFailure(
        taskKind: safeKind,
        failureKind: 'commandBlocked',
        stderr:
            'Linux Sandbox only accepts typed tasks: ${allowedKinds.join(', ')}.',
      );
    }
    final task = _startRuntimeTypedTask(safeKind, payload);
    Map<String, dynamic> finish(Map<String, dynamic> result) =>
        _finishRuntimeTypedTask(task, result);
    if (safeKind == 'package_install') {
      final profileId = payload['profileId']?.toString() ??
          payload['profile_id']?.toString() ??
          '';
      final approved = payload['approved'] == true;
      final profile = _profileById(profileId);
      if (profile == null) {
        return finish(_typedFailure(
          taskKind: safeKind,
          failureKind: 'commandBlocked',
          stderr:
              'Linux Sandbox package_install only accepts built-in package profile ids.',
          metadata: {'profileId': profileId},
        ));
      }
      if (!approved) {
        return finish(_typedFailure(
          taskKind: safeKind,
          failureKind: 'approvalRequired',
          stderr:
              'Linux Sandbox package_install requires explicit user approval.',
          metadata: {'profileId': profile.id, 'profileName': profile.label},
        ));
      }
    }
    if (safeKind == 'hyperframes_render' && payload['approved'] != true) {
      return finish(_typedFailure(
        taskKind: safeKind,
        failureKind: 'approvalRequired',
        stderr:
            'HyperFrames render requires explicit user approval because it writes an MP4 artifact.',
      ));
    }
    if (safeKind == 'lark_cli_auth_start' && payload['approved'] != true) {
      return finish(_typedFailure(
        taskKind: safeKind,
        failureKind: 'approvalRequired',
        stderr:
            'Starting Lark CLI login requires explicit user approval because it opens an official browser flow.',
      ));
    }
    if (safeKind == 'lark_cli_execute') {
      final commandId = payload['commandId']?.toString() ?? '';
      const allowedCommandIds = {'auth_status', 'wiki_space_list'};
      if (!allowedCommandIds.contains(commandId)) {
        return finish(_typedFailure(
          taskKind: safeKind,
          failureKind: 'commandBlocked',
          stderr:
              'Lark CLI execute only accepts built-in read-only command ids: ${allowedCommandIds.join(', ')}.',
          metadata: {'commandId': commandId},
        ));
      }
      if (payload['approved'] != true) {
        return finish(_typedFailure(
          taskKind: safeKind,
          failureKind: 'approvalRequired',
          stderr: 'Running a Lark CLI command requires explicit user approval.',
          metadata: {'commandId': commandId},
        ));
      }
    }
    if (safeKind == 'agently_cli_auth_start' && payload['approved'] != true) {
      return finish(_typedFailure(
        taskKind: safeKind,
        failureKind: 'approvalRequired',
        stderr:
            'Starting Agent Mail CLI login requires explicit user approval because it opens an official browser flow.',
      ));
    }
    if (safeKind == 'agently_cli_execute') {
      final commandId = payload['commandId']?.toString() ?? '';
      const allowedCommandIds = {'message_list'};
      if (!allowedCommandIds.contains(commandId)) {
        return finish(_typedFailure(
          taskKind: safeKind,
          failureKind: 'commandBlocked',
          stderr:
              'Agent Mail CLI execute only accepts built-in read-only command ids: ${allowedCommandIds.join(', ')}.',
          metadata: {'commandId': commandId},
        ));
      }
      if (payload['approved'] != true) {
        return finish(_typedFailure(
          taskKind: safeKind,
          failureKind: 'approvalRequired',
          stderr: 'Reading Agent Mail data requires explicit user approval.',
          metadata: {'commandId': commandId},
        ));
      }
    }
    if ((safeKind == 'gws_cli_auth_setup' ||
            safeKind == 'gws_cli_auth_login') &&
        payload['approved'] != true) {
      return finish(_typedFailure(
        taskKind: safeKind,
        failureKind: 'approvalRequired',
        stderr:
            'Starting Google Workspace CLI auth requires explicit user approval because it opens an official browser or Google Cloud setup flow.',
      ));
    }
    if (safeKind == 'gws_cli_execute') {
      final commandId = payload['commandId']?.toString() ?? '';
      const allowedCommandIds = {'drive_files_list'};
      if (!allowedCommandIds.contains(commandId)) {
        return finish(_typedFailure(
          taskKind: safeKind,
          failureKind: 'commandBlocked',
          stderr:
              'Google Workspace CLI execute only accepts built-in read-only command ids: ${allowedCommandIds.join(', ')}.',
          metadata: {'commandId': commandId},
        ));
      }
      if (payload['approved'] != true) {
        return finish(_typedFailure(
          taskKind: safeKind,
          failureKind: 'approvalRequired',
          stderr:
              'Reading Google Workspace data requires explicit user approval.',
          metadata: {'commandId': commandId},
        ));
      }
    }
    if (safeKind == 'github_cli_auth_login' && payload['approved'] != true) {
      return finish(_typedFailure(
        taskKind: safeKind,
        failureKind: 'approvalRequired',
        stderr:
            'Starting GitHub CLI login requires explicit user approval because it opens an official browser flow.',
      ));
    }
    if (safeKind == 'github_cli_execute') {
      final commandId = payload['commandId']?.toString() ?? '';
      const allowedCommandIds = {'repo_list'};
      if (!allowedCommandIds.contains(commandId)) {
        return finish(_typedFailure(
          taskKind: safeKind,
          failureKind: 'commandBlocked',
          stderr:
              'GitHub CLI execute only accepts built-in read-only command ids: ${allowedCommandIds.join(', ')}.',
          metadata: {'commandId': commandId},
        ));
      }
      if (payload['approved'] != true) {
        return finish(_typedFailure(
          taskKind: safeKind,
          failureKind: 'approvalRequired',
          stderr: 'Reading GitHub data requires explicit user approval.',
          metadata: {'commandId': commandId},
        ));
      }
    }
    if (!_state.installed) {
      return finish(_typedFailure(
        taskKind: safeKind,
        failureKind: 'dependencyMissing',
        stderr: 'Linux Sandbox rootfs is not installed.',
      ));
    }
    if (_useNativeRunner) {
      final startedAt = DateTime.now();
      final timeoutMs = _typedTaskTimeoutMs(payload);
      final result = _normalizeNativeTypedTaskResult(
        safeKind,
        _redactLinuxSandboxNativeResult(
          await _nativeBridge
              .runTypedTask(
                taskKind: safeKind,
                payload: payload,
              )
              .timeout(
                Duration(milliseconds: timeoutMs),
                onTimeout: () => {
                  'success': false,
                  'taskKind': safeKind,
                  'status': 'timeout',
                  'stdout': '',
                  'stderr':
                      'Linux Sandbox typed task timed out after ${timeoutMs}ms.',
                  'exitCode': 124,
                  'durationMs': timeoutMs,
                  'failureKind': 'timeout',
                },
              ),
        ),
      );
      if (safeKind == 'package_install' && result['success'] == true) {
        final profileId = payload['profileId']?.toString() ??
            payload['profile_id']?.toString() ??
            '';
        _markPackageProfileInstalled(profileId);
      }
      _recordEvidence(_evidenceFromNativeResult(
        _evidenceSafeLinuxSandboxNativeResult(safeKind, result),
        startedAt: startedAt,
        paramsSummary: 'linux_sandbox_typed_task $safeKind',
      ));
      return finish(result);
    }
    return finish(_typedFailure(
      taskKind: safeKind,
      failureKind: 'dependencyMissing',
      stderr:
          'Linux Sandbox runner proof is not connected yet; typed task execution is blocked.',
    ));
  }

  int _typedTaskTimeoutMs(Map<String, dynamic> payload) {
    final raw = payload['timeoutMs'] ?? payload['timeout_ms'];
    final parsed = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
    return (parsed ?? 60000).clamp(1000, 600000);
  }

  Map<String, dynamic> _normalizeNativeTypedTaskResult(
    String taskKind,
    Map<String, dynamic> rawResult,
  ) {
    final result = Map<String, dynamic>.from(rawResult);
    final output = [
      result['stdout']?.toString() ?? '',
      result['stderr']?.toString() ?? '',
    ].join('\n').toLowerCase();
    final warnings = <String>[
      ...((result['warnings'] as List?) ?? const [])
          .map((warning) => warning.toString()),
    ];
    if (taskKind == 'package_install' &&
        result['success'] == true &&
        _hasPackageDatabaseWarning(output)) {
      warnings.add(
        'Alpine apk reported a package database write warning; postconditions passed, but the profile should be re-verified.',
      );
      result['status'] = 'succeeded_with_warnings';
      result['warning'] = true;
      result['warnings'] = warnings.toSet().toList(growable: false);
    }
    return result;
  }

  bool _hasPackageDatabaseWarning(String output) {
    return output.contains('failed to write database') ||
        output.contains('system state may be inconsistent') ||
        output.contains('permission denied') && output.contains('database') ||
        RegExp(r'(^|\n)error:', caseSensitive: false).hasMatch(output);
  }

  @override
  Future<Map<String, dynamic>> runTermuxTask({
    required String taskKind,
    required Map<String, dynamic> payload,
  }) {
    return runTypedTask(taskKind: taskKind, payload: payload);
  }

  @override
  Future<RuntimeSyncResult> syncWorkspace({
    required String sourcePath,
    required String targetPath,
  }) async {
    return RuntimeSyncResult(
      success: false,
      sourcePath: sourcePath,
      targetPath: targetPath,
      error: 'Linux Sandbox workspace sync requires runner proof first.',
    );
  }

  @override
  Future<BuildResult> buildWeb(String projectPath) async {
    return BuildResult(
      success: false,
      error:
          'Linux Sandbox cannot build Web until Node Pack and runner proof are connected.',
      buildTime: Duration.zero,
    );
  }

  @override
  Future<BuildResult> buildApk(String projectPath,
      {BuildMode mode = BuildMode.debug}) async {
    return BuildResult(
      success: false,
      error:
          'Linux Sandbox Android builds are out of scope for the first proof.',
      buildTime: Duration.zero,
    );
  }

  @override
  Future<InstallResult> installApk(String apkPath) async {
    return const InstallResult(
      success: false,
      packageName: '',
      error: 'Linux Sandbox cannot install APKs.',
    );
  }

  @override
  Future<void> launchApp(String packageName) async {}

  @override
  Future<void> uninstallApp(String packageName) async {}

  @override
  Future<void> stopCurrentTask() async {
    final task = _currentTask;
    if (task != null) await stopTask(task.taskId);
  }

  @override
  Future<RuntimeTaskSnapshot?> currentTask() async => _currentTask;

  @override
  Future<List<RuntimeTaskSnapshot>> listTasks({int limit = 20}) async {
    final safeLimit = limit.clamp(1, 100);
    return _taskHistory.take(safeLimit).toList(growable: false);
  }

  @override
  Future<List<String>> taskLogs(String taskId, {int limit = 200}) async {
    final safeLimit = limit.clamp(1, 1000);
    return (_taskLogs[taskId] ?? const [])
        .take(safeLimit)
        .toList(growable: false);
  }

  @override
  Future<void> stopTask(String taskId) async {
    _stopRequestedTaskIds.add(taskId);
    final current = _currentTask;
    if (current != null && current.taskId == taskId) {
      final logs = [
        ...current.logs,
        'Stop requested by user; native runner cancellation is best-effort.',
      ];
      _taskLogs[taskId] = logs;
      _currentTask = current.copyWith(
        status: RuntimeTaskStatus.cancelled,
        finishedAt: DateTime.now(),
        logs: logs,
        error: 'Stop requested by user.',
        failureKind: RuntimeTaskFailureKind.cancelled,
      );
      _rememberTask(_currentTask!);
    }
  }

  RuntimeTaskSnapshot _startRuntimeTypedTask(
    String taskKind,
    Map<String, dynamic> payload,
  ) {
    final startedAt = DateTime.now();
    final taskId = 'linux-sandbox-${startedAt.microsecondsSinceEpoch}';
    final safePayloadKeys = payload.keys
        .map((key) => _redactLinuxSandboxEvidenceText(key.toString()))
        .toList(growable: false)
      ..sort();
    final logs = [
      'Started Linux Sandbox typed task: $taskKind.',
      if (safePayloadKeys.isNotEmpty)
        'Payload keys: ${safePayloadKeys.join(', ')}.',
    ];
    final snapshot = RuntimeTaskSnapshot(
      taskId: taskId,
      status: RuntimeTaskStatus.running,
      command: 'typed:$taskKind',
      startedAt: startedAt,
      logs: logs,
      providerType: RuntimeProviderType.linuxSandbox,
    );
    _taskLogs[taskId] = logs;
    _currentTask = snapshot;
    _logs.add('[linux-sandbox] typed task started: $taskKind');
    return snapshot;
  }

  Map<String, dynamic> _finishRuntimeTypedTask(
    RuntimeTaskSnapshot task,
    Map<String, dynamic> rawResult,
  ) {
    final result = Map<String, dynamic>.from(rawResult);
    result.putIfAbsent('taskId', () => task.taskId);
    final stopRequested = _stopRequestedTaskIds.remove(task.taskId);
    if (stopRequested) {
      result['success'] = false;
      result['status'] = 'cancelled';
      result['failureKind'] = 'cancelled';
      result['exitCode'] ??= 130;
      final stderr = result['stderr']?.toString() ?? '';
      result['stderr'] = stderr.isEmpty
          ? 'Stop requested by user.'
          : '$stderr\nStop requested by user.';
    }
    final finishedAt = DateTime.now();
    final stdout = result['stdout']?.toString() ?? '';
    final stderr = result['stderr']?.toString() ?? '';
    final logs = [
      ...(_taskLogs[task.taskId] ?? task.logs),
      if (stdout.isNotEmpty) _compactRuntimeLog(stdout),
      if (stderr.isNotEmpty) _compactRuntimeLog(stderr),
      'Finished with status: ${result['status'] ?? 'unknown'}.',
    ];
    final snapshot = task.copyWith(
      status: _runtimeStatusFromTypedResult(result),
      finishedAt: finishedAt,
      exitCode: _nullableInt(result['exitCode']),
      duration: finishedAt.difference(task.startedAt ?? finishedAt),
      logs: logs,
      error: stderr.isEmpty ? null : _compactRuntimeLog(stderr),
      failureKind: _runtimeFailureFromTypedResult(result),
    );
    _taskLogs[task.taskId] = logs;
    if (_currentTask?.taskId == task.taskId) {
      _currentTask = null;
    }
    _rememberTask(snapshot);
    return result;
  }

  void _rememberTask(RuntimeTaskSnapshot snapshot) {
    _taskHistory.removeWhere((task) => task.taskId == snapshot.taskId);
    _taskHistory.insert(0, snapshot);
    if (_taskHistory.length > 50) {
      _taskHistory.removeRange(50, _taskHistory.length);
    }
  }

  RuntimeTaskStatus _runtimeStatusFromTypedResult(Map<String, dynamic> result) {
    final status = result['status']?.toString().toLowerCase();
    if (status == 'cancelled' || result['failureKind'] == 'cancelled') {
      return RuntimeTaskStatus.cancelled;
    }
    if (status == 'timeout' || status == 'timedout') {
      return RuntimeTaskStatus.timedOut;
    }
    if (result['success'] == true || status == 'succeeded') {
      return RuntimeTaskStatus.succeeded;
    }
    return RuntimeTaskStatus.failed;
  }

  RuntimeTaskFailureKind _runtimeFailureFromTypedResult(
    Map<String, dynamic> result,
  ) {
    final failure = result['failureKind']?.toString().toLowerCase() ?? '';
    if (failure.contains('timeout')) return RuntimeTaskFailureKind.timeout;
    if (failure.contains('cancel')) return RuntimeTaskFailureKind.cancelled;
    if (failure.contains('dependency')) {
      return RuntimeTaskFailureKind.dependencyMissing;
    }
    if (failure.contains('blocked'))
      return RuntimeTaskFailureKind.commandBlocked;
    if (failure.contains('auth')) return RuntimeTaskFailureKind.authFailed;
    if (result['success'] == true) return RuntimeTaskFailureKind.none;
    return RuntimeTaskFailureKind.processFailed;
  }

  String _compactRuntimeLog(String value) {
    final safe = _redactLinuxSandboxEvidenceText(value).trim();
    if (safe.length <= 500) return safe;
    return '${safe.substring(0, 500)}... [truncated]';
  }

  bool _profileInstalled(String id) {
    return _state.packageProfiles
        .any((profile) => profile.id == id && profile.installed);
  }

  LinuxSandboxPackageProfile? _profileById(String id) {
    for (final profile in _state.packageProfiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  void _markPackageProfileInstalled(String id) {
    if (id.isEmpty) return;
    _setState(_state.copyWith(
      packageProfiles: [
        for (final profile in _state.packageProfiles)
          if (profile.id == id)
            profile.copyWith(
              status: LinuxSandboxPackageProfileStatus.installed,
              clearFailure: true,
            )
          else
            profile,
      ],
      clearFailure: true,
    ));
  }

  Future<LinuxSandboxState> _installRootfsNative() async {
    final startedAt = DateTime.now();
    try {
      final status = await _nativeBridge.status();
      final manifest = _manifestForNativeStatus(status);
      _state = LinuxSandboxState.uninstalled(manifest: manifest).copyWith(
        status: LinuxSandboxInstallStatus.downloading,
        progress: 0.05,
        clearFailure: true,
      );
      final result = _redactLinuxSandboxNativeResult(
        await _nativeBridge.setup(manifest),
      );
      _recordEvidence(_evidenceFromNativeResult(
        result,
        startedAt: startedAt,
        paramsSummary: 'linux_sandbox_native_setup ${manifest.id}',
      ));
      if (result['success'] == true) {
        final latest = await _nativeBridge.status();
        _applyNativeStatus(latest);
      } else {
        _setState(_state.copyWith(
          status: LinuxSandboxInstallStatus.failed,
          rootfsVerified: false,
          failureKind: result['failureKind']?.toString() ?? 'processFailed',
          recoveryHint: result['stderr']?.toString() ??
              'Android native Linux Sandbox setup failed.',
        ));
      }
      return _state;
    } catch (error) {
      return _failRootfsInstall(
        startedAt: startedAt,
        failureKind: 'native_runner_failed',
        recoveryHint: 'Android native Linux Sandbox runner failed.',
        log: error.toString(),
      );
    }
  }

  LinuxSandboxRootfsManifest _manifestForNativeStatus(
    Map<String, dynamic> status,
  ) {
    final arch = status['arch']?.toString();
    if (arch == 'x86_64') return LinuxSandboxManifests.alpineMiniRootfsX8664;
    return LinuxSandboxManifests.alpineMiniRootfsAarch64;
  }

  void _applyNativeStatus(Map<String, dynamic> status) {
    final packages = _stringKeyMap(status['packages']);
    final ready = status['ready'] == true;
    final installed = status['installed'] == true;
    final rootfsPath = status['rootfsPath']?.toString() ?? _state.rootfsPath;
    _setState(_state.copyWith(
      status: ready
          ? LinuxSandboxInstallStatus.installed
          : LinuxSandboxInstallStatus.idle,
      rootfsPath: installed ? rootfsPath : '',
      rootfsVerified: ready,
      progress: ready ? 1 : 0,
      packageProfiles: [
        for (final profile in _state.packageProfiles)
          profile.copyWith(
            status: packages[profile.id] == true
                ? LinuxSandboxPackageProfileStatus.installed
                : profile.status,
            clearFailure: true,
          ),
      ],
      clearFailure: true,
      lastCheckedAt: DateTime.now(),
    ));
  }

  ActionEvidence _evidenceFromNativeResult(
    Map<String, dynamic> result, {
    required DateTime startedAt,
    required String paramsSummary,
  }) {
    final success = result['success'] == true;
    return ActionEvidence(
      evidenceId: generateEvidenceId(),
      actionName: MobileCodeAction.termuxTaskStart,
      paramsSummary: paramsSummary,
      startedAt: startedAt,
      success: success,
      logs: [
        if ((result['stdout']?.toString() ?? '').isNotEmpty)
          _redactLinuxSandboxEvidenceText(result['stdout'].toString()),
        if ((result['stderr']?.toString() ?? '').isNotEmpty)
          _redactLinuxSandboxEvidenceText(result['stderr'].toString()),
      ],
      exitCode: _nullableInt(result['exitCode']),
      failureKind:
          success ? null : result['failureKind']?.toString() ?? 'processFailed',
      recoveryActions: success
          ? const []
          : const ['检查 rootfs、PRoot native libs、Android ABI 和网络连接后重试。'],
      metadata: {
        'runtime': 'linuxSandbox',
        'native': true,
        if (result['taskKind'] != null) 'taskKind': result['taskKind'],
        if (result['metadata'] != null)
          'nativeMetadata':
              _redactLinuxSandboxEvidenceValue(result['metadata']),
      },
    );
  }

  Map<String, dynamic> _typedFailure({
    required String taskKind,
    required String failureKind,
    required String stderr,
    Map<String, dynamic> metadata = const {},
  }) {
    return {
      'success': false,
      'taskId': 'linux-sandbox-${DateTime.now().millisecondsSinceEpoch}',
      'taskKind': taskKind,
      'status': 'failed',
      'stdout': '',
      'stderr': stderr,
      'exitCode': failureKind == 'commandBlocked' ? 126 : 127,
      'durationMs': 0,
      'failureKind': failureKind,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }

  void _setState(LinuxSandboxState state) {
    _state = state;
  }

  void _recordEvidence(ActionEvidence evidence) {
    _evidence.add(evidence);
  }

  Future<Directory> _sandboxBaseDirectory() async {
    final appDir = await _baseDirectoryResolver();
    final baseDir = Directory(p.join(appDir.path, 'linux-sandbox'));
    await baseDir.create(recursive: true);
    return baseDir;
  }

  LinuxSandboxState _cancelledRootfsInstall(DateTime startedAt) {
    _setState(_state.copyWith(
      status: LinuxSandboxInstallStatus.cancelled,
      rootfsVerified: false,
      failureKind: 'cancelled',
      recoveryHint: '已取消安装；可稍后重试或删除暂存目录。',
      lastCheckedAt: DateTime.now(),
    ));
    _recordEvidence(ActionEvidence.failed(
      actionName: MobileCodeAction.termuxTaskStart,
      startedAt: startedAt,
      paramsSummary: 'linux_sandbox_rootfs_install ${_state.manifest.id}',
      failureKind: ActionFailureKind.cancelled,
      recoveryActions: const ['重试 rootfs 安装。'],
      logs: const ['cancelled'],
    ));
    return _state;
  }

  LinuxSandboxState _failRootfsInstall({
    required DateTime startedAt,
    required String failureKind,
    required String recoveryHint,
    required String log,
  }) {
    _setState(_state.copyWith(
      status: LinuxSandboxInstallStatus.failed,
      rootfsVerified: false,
      failureKind: failureKind,
      recoveryHint: recoveryHint,
      lastCheckedAt: DateTime.now(),
    ));
    final safeLog = _redactLinuxSandboxEvidenceText(log);
    _logs.add('[linux-sandbox] $failureKind: $safeLog');
    _recordEvidence(ActionEvidence.failed(
      actionName: MobileCodeAction.termuxTaskStart,
      startedAt: startedAt,
      paramsSummary: 'linux_sandbox_rootfs_install ${_state.manifest.id}',
      failureKind: failureKind,
      recoveryActions: [recoveryHint],
      logs: [safeLog],
    ));
    return _state;
  }
}

Map<String, dynamic> _redactLinuxSandboxNativeResult(
  Map<String, dynamic> result,
) {
  return {
    for (final entry in result.entries)
      entry.key: _redactLinuxSandboxEvidenceValue(entry.value),
  };
}

Map<String, dynamic> _evidenceSafeLinuxSandboxNativeResult(
  String taskKind,
  Map<String, dynamic> result,
) {
  if (!_redactsOfficialAuthFlowOutput(taskKind)) return result;
  final safe = Map<String, dynamic>.from(result);
  if ((safe['stdout']?.toString() ?? '').isNotEmpty) {
    safe['stdout'] = '[redacted official auth flow output]';
  }
  if ((safe['stderr']?.toString() ?? '').isNotEmpty) {
    safe['stderr'] = '[redacted official auth flow output]';
  }
  if (safe['metadata'] != null) {
    safe['metadata'] = _redactAuthFlowMetadata(safe['metadata']);
  }
  return safe;
}

bool _redactsOfficialAuthFlowOutput(String taskKind) {
  return taskKind.endsWith('_auth_start') ||
      taskKind.endsWith('_auth_login') ||
      taskKind.endsWith('_auth_setup');
}

dynamic _redactAuthFlowMetadata(dynamic value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): entry.key
                .toString()
                .contains(RegExp('url|code|oauth', caseSensitive: false))
            ? '<redacted_auth_flow>'
            : _redactAuthFlowMetadata(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map(_redactAuthFlowMetadata).toList(growable: false);
  }
  if (value is String && value.contains(RegExp(r'https?://'))) {
    return '<redacted_auth_flow>';
  }
  return value;
}

dynamic _redactLinuxSandboxEvidenceValue(dynamic value) {
  if (value is String) return _redactLinuxSandboxEvidenceText(value);
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): _redactLinuxSandboxEvidenceValue(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map(_redactLinuxSandboxEvidenceValue).toList(growable: false);
  }
  return value;
}

String _redactLinuxSandboxEvidenceText(String value) {
  var redacted = value.replaceAllMapped(
    RegExp(
      "\\b(access[_-]?token|refresh[_-]?token|id[_-]?token|token|cookie|secret|app[_-]?secret|password)\\b\\s*[:=]\\s*[\"']?[^\"'\\s,;]+",
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}=<redacted>',
  );
  redacted = redacted.replaceAllMapped(
    RegExp(r'(bearer\s+)[A-Za-z0-9._\-]+', caseSensitive: false),
    (match) => '${match.group(1)}<redacted>',
  );
  redacted = redacted.replaceAll(
    RegExp("/(Users|Volumes)/[^\\s,\"']+"),
    '/<redacted_local_path>',
  );
  return redacted;
}

Future<Directory> _defaultBaseDirectoryResolver() {
  return getApplicationSupportDirectory();
}

Future<List<int>> _defaultDownloader(
  LinuxSandboxRootfsManifest manifest,
  void Function(int receivedBytes, int? totalBytes) onProgress,
) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(manifest.url));
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'HTTP ${response.statusCode} while downloading ${manifest.id}',
        uri: Uri.parse(manifest.url),
      );
    }
    final bytes = <int>[];
    var received = 0;
    final total = response.contentLength > 0 ? response.contentLength : null;
    await for (final chunk in response) {
      bytes.addAll(chunk);
      received += chunk.length;
      onProgress(received, total);
    }
    return bytes;
  } finally {
    client.close(force: true);
  }
}

Future<void> _extractTarGz(
  List<int> archiveBytes,
  Directory rootfsDirectory,
) async {
  final tarBytes = gzip.decode(archiveBytes);
  var offset = 0;
  while (offset + 512 <= tarBytes.length) {
    final header = tarBytes.sublist(offset, offset + 512);
    offset += 512;
    if (header.every((byte) => byte == 0)) break;

    final name = _tarString(header, 0, 100);
    final prefix = _tarString(header, 345, 155);
    final entryName = prefix.isEmpty ? name : '$prefix/$name';
    final size = _tarOctal(header, 124, 12);
    final typeFlag = header[156];
    final outputPath = _safeRootfsPath(rootfsDirectory, entryName);

    if (typeFlag == 53) {
      await Directory(outputPath).create(recursive: true);
    } else if (typeFlag == 50) {
      final linkTarget = _tarString(header, 157, 100);
      if (linkTarget.isNotEmpty &&
          !p.isAbsolute(linkTarget) &&
          !p.split(linkTarget).contains('..')) {
        await Directory(p.dirname(outputPath)).create(recursive: true);
        final link = Link(outputPath);
        if (!await link.exists()) {
          await link.create(linkTarget, recursive: true);
        }
      }
    } else if (typeFlag == 0 || typeFlag == 48) {
      await Directory(p.dirname(outputPath)).create(recursive: true);
      final fileBytes = tarBytes.sublist(offset, offset + size);
      await File(outputPath).writeAsBytes(fileBytes, flush: false);
    }

    offset += _tarPaddedSize(size);
  }
}

String _safeRootfsPath(Directory rootfsDirectory, String entryName) {
  final normalizedName = p.normalize(entryName);
  if (normalizedName.isEmpty ||
      p.isAbsolute(normalizedName) ||
      p.split(normalizedName).contains('..')) {
    throw FormatException('Unsafe rootfs entry path: $entryName');
  }
  final outputPath = p.normalize(p.join(rootfsDirectory.path, normalizedName));
  if (!p.isWithin(rootfsDirectory.path, outputPath) &&
      p.normalize(rootfsDirectory.path) != outputPath) {
    throw FormatException('Rootfs entry escapes app-owned storage: $entryName');
  }
  return outputPath;
}

String _tarString(List<int> bytes, int start, int length) {
  final slice = bytes.sublist(start, start + length);
  final end = slice.indexOf(0);
  final value = end >= 0 ? slice.sublist(0, end) : slice;
  return utf8.decode(value, allowMalformed: true).trim();
}

int _tarOctal(List<int> bytes, int start, int length) {
  final value = _tarString(bytes, start, length).trim();
  if (value.isEmpty) return 0;
  return int.parse(value, radix: 8);
}

int _tarPaddedSize(int size) {
  final remainder = size % 512;
  return remainder == 0 ? size : size + 512 - remainder;
}

String _string(Object? value) {
  final result = value?.toString() ?? '';
  if (result.isEmpty) {
    throw const FormatException('Expected non-empty string');
  }
  return result;
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.parse(value?.toString() ?? '');
}

int? _nullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

Map<String, dynamic> _stringKeyMap(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, dynamic>{};
}
