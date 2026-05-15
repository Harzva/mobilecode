// lib/services/runtime_placeholder_providers.dart
// Placeholder runtime providers for future MobileCode runtime phases.

import 'dart:async';

import 'runtime_provider.dart';
import 'termux_service.dart';

abstract class UnavailableRuntimeProvider implements RuntimeProvider {
  final StreamController<String> _logController = StreamController<String>.broadcast();

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
  Future<BuildResult> buildApk(String projectPath, {BuildMode mode = BuildMode.debug}) async {
    return BuildResult(
      success: false,
      error: '$name cannot build APKs yet. Use External Termux or Cloud Runtime.',
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

class EmbeddedLiteRuntimeProvider extends UnavailableRuntimeProvider {
  @override
  RuntimeProviderType get type => RuntimeProviderType.embeddedLite;

  @override
  String get name => 'Embedded Lite Runtime';

  @override
  RuntimeCapabilities get plannedCapabilities => const RuntimeCapabilities(
        shell: true,
        git: true,
        node: true,
        python: true,
        webViewPreview: true,
      );

  @override
  String get unavailableStatus => 'Embedded Lite Runtime is planned but not bundled yet.';

  @override
  List<String> get plannedActions => const [
        'Bundle a minimal native toolchain before enabling this provider.',
      ];
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
  RuntimeCapabilities get plannedCapabilities => const RuntimeCapabilities(webViewPreview: true);

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
