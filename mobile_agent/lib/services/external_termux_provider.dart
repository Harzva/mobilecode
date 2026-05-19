// lib/services/external_termux_provider.dart
// RuntimeProvider adapter around the existing TermuxService.

import 'dart:async';

import 'runtime_provider.dart';
import 'termux_service.dart';

class ExternalTermuxProvider implements RuntimeProvider {
  final TermuxService _termux;

  ExternalTermuxProvider(this._termux);

  @override
  RuntimeProviderType get type => RuntimeProviderType.externalTermux;

  @override
  String get name => 'External Termux';

  @override
  Stream<String> get logStream => _termux.buildLogStream;

  @override
  Future<void> initialize() => _termux.initialize();

  @override
  Future<RuntimeCapabilities> capabilities() async {
    await initialize();
    final installed = await _termux.isTermuxInstalled();
    if (!installed) {
      return const RuntimeCapabilities();
    }

    final flutterStatus = await _termux.checkFlutterSdk();
    final flutterReady = flutterStatus == FlutterSdkStatus.installed ||
        flutterStatus == FlutterSdkStatus.outdated;

    return RuntimeCapabilities(
      shell: true,
      git: await _hasCommand('git'),
      node: await _hasCommand('node'),
      python: await _hasCommand('python') || await _hasCommand('python3'),
      flutter: flutterReady,
      androidBuild: flutterReady,
      pty: false,
      backgroundService: false,
      webViewPreview: true,
    );
  }

  @override
  Future<RuntimeHealth> healthCheck() async {
    await initialize();

    final installed = await _termux.isTermuxInstalled();
    final apiInstalled = await _termux.isTermuxApiInstalled();
    final caps = await capabilities();
    final missing = <String>[];
    final actions = <String>[];

    if (!installed) {
      missing.add('Termux app');
      actions.add('Install Termux from F-Droid, then reopen MobileCode.');
    }
    if (installed && !apiInstalled) {
      actions.add('Optional: install Termux:API for notifications, clipboard, and richer Android integration.');
    }
    if (installed && !caps.flutter) {
      missing.add('Flutter SDK in Termux');
      actions.add('Run the MobileCode Termux setup wizard.');
    }

    return RuntimeHealth(
      type: type,
      name: name,
      available: installed,
      ready: installed && caps.shell,
      status: installed
          ? (caps.flutter ? 'Termux ready for Flutter builds.' : 'Termux available; Flutter SDK missing.')
          : 'Termux is not installed.',
      capabilities: caps,
      missingDependencies: missing,
      recoveryActions: actions,
    );
  }

  @override
  Future<RuntimeCommandResult> execute(
    String command, {
    String? workingDir,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    final result = await _termux.execute(
      command,
      workingDir: workingDir,
      timeoutSeconds: timeout?.inSeconds ?? 120,
    );
    return RuntimeCommandResult(
      command: result.command,
      stdout: result.stdout,
      stderr: result.stderr,
      exitCode: result.exitCode,
      duration: result.duration,
      providerType: type,
    );
  }

  @override
  Stream<String> executeStream(
    String command, {
    String? workingDir,
    Map<String, String>? environment,
  }) {
    return _termux.executeStream(command, workingDir: workingDir);
  }

  @override
  Future<RuntimeSyncResult> syncWorkspace({
    required String sourcePath,
    required String targetPath,
  }) async {
    try {
      await _termux.syncToTermux(sourcePath, targetPath);
      return RuntimeSyncResult(
        success: true,
        sourcePath: sourcePath,
        targetPath: targetPath,
      );
    } catch (e) {
      return RuntimeSyncResult(
        success: false,
        sourcePath: sourcePath,
        targetPath: targetPath,
        error: e.toString(),
      );
    }
  }

  @override
  Future<BuildResult> buildWeb(String projectPath) => _termux.buildWeb(projectPath);

  @override
  Future<BuildResult> buildApk(String projectPath, {BuildMode mode = BuildMode.debug}) {
    return _termux.buildApk(projectPath, mode: mode);
  }

  @override
  Future<InstallResult> installApk(String apkPath) => _termux.installApk(apkPath);

  @override
  Future<void> launchApp(String packageName) => _termux.launchApp(packageName);

  @override
  Future<void> uninstallApp(String packageName) => _termux.uninstallApp(packageName);

  @override
  Future<void> stopCurrentTask() => _termux.stopCurrentBuild();

  Future<bool> _hasCommand(String command) async {
    try {
      final result = await _termux.execute('which $command');
      return result.success && result.stdout.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
