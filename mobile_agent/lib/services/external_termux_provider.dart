// lib/services/external_termux_provider.dart
// RuntimeProvider adapter around the existing TermuxService.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'runtime_provider.dart';
import 'termux_service.dart';

class ExternalTermuxProvider implements RuntimeProvider {
  static const MethodChannel _systemToolsChannel =
      MethodChannel('mobilecode/system_tools');

  final TermuxService _termux;

  ExternalTermuxProvider(this._termux);

  @override
  RuntimeProviderType get type => RuntimeProviderType.externalTermux;

  @override
  String get name => 'External Termux';

  @override
  Stream<String> get logStream => _termux.buildLogStream;

  @override
  Future<void> initialize() async {
    if (_isAndroidAppRuntime) return;
    await _termux.initialize();
  }

  @override
  Future<RuntimeCapabilities> capabilities() async {
    if (_isAndroidAppRuntime) {
      return const RuntimeCapabilities(webViewPreview: true);
    }
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
    if (_isAndroidAppRuntime) {
      return _androidBridgeHealth();
    }

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
      actions.add(
          'Optional: install Termux:API for notifications, clipboard, and richer Android integration.');
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
          ? (caps.flutter
              ? 'Termux ready for Flutter builds.'
              : 'Termux available; Flutter SDK missing.')
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
    if (_isAndroidAppRuntime) {
      return _androidBridgeBlocked(command);
    }

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
  }) async* {
    if (_isAndroidAppRuntime) {
      yield '[runtime] External Termux requires the MobileCode bridge protocol on Android. Use MobileCode Helper or a future Termux bridge.';
      return;
    }
    yield* _termux.executeStream(command, workingDir: workingDir);
  }

  @override
  Future<RuntimeSyncResult> syncWorkspace({
    required String sourcePath,
    required String targetPath,
  }) async {
    if (_isAndroidAppRuntime) {
      return RuntimeSyncResult(
        success: false,
        sourcePath: sourcePath,
        targetPath: targetPath,
        error:
            'External Termux sync requires the MobileCode bridge protocol on Android.',
      );
    }

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
  Future<BuildResult> buildWeb(String projectPath) {
    if (_isAndroidAppRuntime) {
      return Future.value(_androidBridgeBuildBlocked('Flutter Web'));
    }
    return _termux.buildWeb(projectPath);
  }

  @override
  Future<BuildResult> buildApk(String projectPath,
      {BuildMode mode = BuildMode.debug}) {
    if (_isAndroidAppRuntime) {
      return Future.value(_androidBridgeBuildBlocked('APK'));
    }
    return _termux.buildApk(projectPath, mode: mode);
  }

  @override
  Future<InstallResult> installApk(String apkPath) {
    if (_isAndroidAppRuntime) {
      return Future.value(const InstallResult(
        success: false,
        packageName: '',
        error:
            'External Termux APK install requires the MobileCode bridge protocol on Android.',
      ));
    }
    return _termux.installApk(apkPath);
  }

  @override
  Future<void> launchApp(String packageName) async {
    if (_isAndroidAppRuntime) return;
    await _termux.launchApp(packageName);
  }

  @override
  Future<void> uninstallApp(String packageName) async {
    if (_isAndroidAppRuntime) return;
    await _termux.uninstallApp(packageName);
  }

  @override
  Future<void> stopCurrentTask() async {
    if (_isAndroidAppRuntime) return;
    await _termux.stopCurrentBuild();
  }

  Future<bool> _hasCommand(String command) async {
    try {
      final result = await _termux.execute('which $command');
      return result.success && result.stdout.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  bool get _isAndroidAppRuntime =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<RuntimeHealth> _androidBridgeHealth() async {
    final installed = await _isAndroidPackageInstalled('com.termux');
    final apiInstalled = await _isAndroidPackageInstalled('com.termux.api');
    return RuntimeHealth(
      type: type,
      name: name,
      available: installed,
      ready: false,
      status: installed
          ? 'Termux is installed, but the MobileCode bridge protocol is not connected yet.'
          : 'Termux is not installed.',
      capabilities: const RuntimeCapabilities(webViewPreview: true),
      missingDependencies: installed
          ? const ['MobileCode Termux bridge protocol']
          : const ['Termux app', 'MobileCode Termux bridge protocol'],
      recoveryActions: [
        if (!installed)
          'Install Termux from F-Droid before enabling bridge mode.',
        if (installed && !apiInstalled)
          'Optional: install Termux:API for richer Android integration.',
        'Use MobileCode Helper for current shell execution, or connect the future Termux bridge provider.',
      ],
    );
  }

  Future<bool> _isAndroidPackageInstalled(String packageName) async {
    try {
      return await _systemToolsChannel.invokeMethod<bool>(
            'isPackageInstalled',
            {'packageName': packageName},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  RuntimeCommandResult _androidBridgeBlocked(String command) {
    return RuntimeCommandResult(
      command: command,
      stdout: '',
      stderr:
          'External Termux requires the MobileCode bridge protocol on Android. Use MobileCode Helper for shell execution.',
      exitCode: 127,
      duration: Duration.zero,
      providerType: type,
      failureKind: RuntimeTaskFailureKind.dependencyMissing,
    );
  }

  BuildResult _androidBridgeBuildBlocked(String target) {
    return BuildResult(
      success: false,
      error:
          'External Termux $target build requires the MobileCode bridge protocol on Android.',
      buildTime: Duration.zero,
    );
  }
}
