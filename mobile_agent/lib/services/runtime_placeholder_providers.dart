// lib/services/runtime_placeholder_providers.dart
// Placeholder runtime providers for future MobileCode runtime phases.

import 'dart:async';
import 'dart:io';

import 'runtime_actions.dart';
import 'runtime_provider.dart';
import 'termux_service.dart';

abstract class UnavailableRuntimeProvider implements RuntimeProvider {
  final StreamController<String> _logController =
      StreamController<String>.broadcast();

  @override
  Stream<String> get logStream => _logController.stream;

  @override
  Future<void> initialize() async {}

  RuntimeCapabilities get plannedCapabilities;
  String get unavailableStatus;
  List<String> get plannedActions;

  @override
  Future<RuntimeCapabilities> capabilities() async => plannedCapabilities;

  @override
  Future<RuntimeHealth> healthCheck() async {
    return RuntimeHealth(
      type: type,
      name: name,
      available: false,
      ready: false,
      status: unavailableStatus,
      capabilities: plannedCapabilities,
      missingDependencies: const ['Runtime implementation'],
      recoveryActions: plannedActions,
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
      stderr: '$name is not available in this build.',
      exitCode: 127,
      duration: Duration.zero,
      providerType: type,
    );
  }

  @override
  Stream<String> executeStream(
    String command, {
    String? workingDir,
    Map<String, String>? environment,
  }) async* {
    yield '[runtime] $name is not available in this build.';
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
      error: '$name is not available in this build.',
    );
  }

  @override
  Future<BuildResult> buildWeb(String projectPath) async {
    return BuildResult(
      success: false,
      error: '$name cannot build Flutter Web yet.',
      buildTime: Duration.zero,
    );
  }

  @override
  Future<BuildResult> buildApk(String projectPath,
      {BuildMode mode = BuildMode.debug}) async {
    return BuildResult(
      success: false,
      error:
          '$name cannot build APKs yet. Use External Termux or Cloud Runtime.',
      buildTime: Duration.zero,
    );
  }

  @override
  Future<InstallResult> installApk(String apkPath) async {
    return const InstallResult(
      success: false,
      packageName: '',
      error: 'APK install is not available for this runtime.',
    );
  }

  @override
  Future<void> launchApp(String packageName) async {}

  @override
  Future<void> uninstallApp(String packageName) async {}

  @override
  Future<void> stopCurrentTask() async {}
}

class EmbeddedLiteRuntimeProvider
    implements RuntimeProvider, RuntimeProjectInspector {
  final StreamController<String> _logController =
      StreamController<String>.broadcast();

  @override
  RuntimeProviderType get type => RuntimeProviderType.embeddedLite;

  @override
  String get name => 'Embedded Lite Runtime';

  @override
  Stream<String> get logStream => _logController.stream;

  static const RuntimeCapabilities _capabilities = RuntimeCapabilities(
    webViewPreview: true,
  );

  @override
  Future<void> initialize() async {}

  @override
  Future<RuntimeCapabilities> capabilities() async => _capabilities;

  @override
  Future<RuntimeHealth> healthCheck() async {
    return const RuntimeHealth(
      type: RuntimeProviderType.embeddedLite,
      name: 'Embedded Lite Runtime',
      available: true,
      ready: true,
      status:
          'Embedded Lite is ready for controlled project preflight and WebView preview metadata.',
      capabilities: _capabilities,
      recoveryActions: [
        'Start MobileCode Helper or External Termux for shell, git, dependency installation, tests, and Android builds.',
      ],
    );
  }

  @override
  Future<RuntimeProjectProfile> preflightProject(
    String projectPath, {
    String? packageManager,
  }) async {
    final markers = await _findProjectMarkers(projectPath);
    return profileRuntimeProject(
      projectPath: projectPath,
      probeOutput: markers.join('\n'),
      capabilities: _capabilities,
      packageManagerOverride: packageManager,
    );
  }

  @override
  Future<RuntimeCommandResult> execute(
    String command, {
    String? workingDir,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    return _blockedCommand(command);
  }

  @override
  Stream<String> executeStream(
    String command, {
    String? workingDir,
    Map<String, String>? environment,
  }) async* {
    yield '[runtime] Embedded Lite blocks shell commands. Start Helper or External Termux for command execution.';
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
      error:
          'Embedded Lite does not sync workspaces. Start Helper or External Termux for file transfer.',
    );
  }

  @override
  Future<BuildResult> buildWeb(String projectPath) async {
    return BuildResult(
      success: false,
      error:
          'Embedded Lite cannot run build tools. Start Helper, External Termux, or Cloud Runtime for Flutter/Node builds.',
      buildTime: Duration.zero,
    );
  }

  @override
  Future<BuildResult> buildApk(String projectPath,
      {BuildMode mode = BuildMode.debug}) async {
    return BuildResult(
      success: false,
      error:
          'Embedded Lite cannot build APKs. Start MobileCode Helper, External Termux, or use local Mac build.',
      buildTime: Duration.zero,
    );
  }

  @override
  Future<InstallResult> installApk(String apkPath) async {
    return const InstallResult(
      success: false,
      packageName: '',
      error:
          'Embedded Lite cannot install APKs. Use Android platform install or Helper-backed runtime.',
    );
  }

  @override
  Future<void> launchApp(String packageName) async {}

  @override
  Future<void> uninstallApp(String packageName) async {}

  @override
  Future<void> stopCurrentTask() async {}

  RuntimeCommandResult _blockedCommand(String command) {
    return RuntimeCommandResult(
      command: command,
      stdout: '',
      stderr:
          'Embedded Lite blocked shell command execution. Use structured preflight here, or start Helper/External Termux for commands.',
      exitCode: 126,
      duration: Duration.zero,
      providerType: type,
      failureKind: RuntimeTaskFailureKind.commandBlocked,
    );
  }

  Future<List<String>> _findProjectMarkers(String projectPath) async {
    final root = Directory(projectPath);
    if (!await root.exists()) return const [];

    const markerNames = {
      'package.json',
      'pubspec.yaml',
      'requirements.txt',
      'pyproject.toml',
      '.git',
    };
    final markers = <String>{};

    Future<void> inspectDirectory(Directory directory, String prefix) async {
      await for (final entity
          in directory.list(followLinks: false).handleError((_) {})) {
        final name = _entityName(entity);
        if (name == null) continue;
        if (markerNames.contains(name)) {
          markers.add('$prefix$name');
        }
      }
    }

    await inspectDirectory(root, './');
    await for (final entity
        in root.list(followLinks: false).handleError((_) {})) {
      if (entity is! Directory) continue;
      final name = _entityName(entity);
      if (name == null || name.startsWith('.')) continue;
      await inspectDirectory(entity, './$name/');
    }

    return markers.toList()..sort();
  }

  String? _entityName(FileSystemEntity entity) {
    final segments =
        entity.uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
    if (segments.isEmpty) return null;
    return segments.last;
  }
}

class CloudRuntimeProvider extends UnavailableRuntimeProvider {
  @override
  RuntimeProviderType get type => RuntimeProviderType.cloud;

  @override
  String get name => 'Cloud Runtime';

  @override
  RuntimeCapabilities get plannedCapabilities => const RuntimeCapabilities(
        shell: true,
        git: true,
        node: true,
        python: true,
        flutter: true,
        androidBuild: true,
        cloudBuild: true,
      );

  @override
  String get unavailableStatus => 'Cloud Runtime is not configured.';

  @override
  List<String> get plannedActions => const [
        'Connect a cloud build provider before using remote heavy builds.',
      ];
}

class WebViewOnlyRuntimeProvider extends UnavailableRuntimeProvider {
  @override
  RuntimeProviderType get type => RuntimeProviderType.webViewOnly;

  @override
  String get name => 'WebView Only';

  @override
  RuntimeCapabilities get plannedCapabilities =>
      const RuntimeCapabilities(webViewPreview: true);

  @override
  Future<RuntimeHealth> healthCheck() async {
    return RuntimeHealth(
      type: type,
      name: name,
      available: true,
      ready: true,
      status: 'WebView preview is available without a shell runtime.',
      capabilities: plannedCapabilities,
    );
  }

  @override
  String get unavailableStatus => 'WebView preview is available.';

  @override
  List<String> get plannedActions => const [];
}
