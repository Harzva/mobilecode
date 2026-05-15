import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/runtime_actions.dart';
import 'package:mobile_agent/services/runtime_manager.dart';
import 'package:mobile_agent/services/runtime_provider.dart';
import 'package:mobile_agent/services/termux_service.dart';

void main() {
  group('RuntimeManager', () {
    test('selects the first ready provider in priority order', () async {
      final embedded = _FakeRuntimeProvider(
        type: RuntimeProviderType.embeddedLite,
        name: 'Embedded',
        health: const RuntimeHealth(
          type: RuntimeProviderType.embeddedLite,
          name: 'Embedded',
          available: false,
          ready: false,
          status: 'missing',
          capabilities: RuntimeCapabilities.none,
        ),
      );
      final termux = _FakeRuntimeProvider(
        type: RuntimeProviderType.externalTermux,
        name: 'Termux',
        health: const RuntimeHealth(
          type: RuntimeProviderType.externalTermux,
          name: 'Termux',
          available: true,
          ready: true,
          status: 'ready',
          capabilities: RuntimeCapabilities(shell: true, git: true),
        ),
      );
      final webOnly = _FakeRuntimeProvider(
        type: RuntimeProviderType.webViewOnly,
        name: 'WebView',
        health: const RuntimeHealth(
          type: RuntimeProviderType.webViewOnly,
          name: 'WebView',
          available: true,
          ready: true,
          status: 'ready',
          capabilities: RuntimeCapabilities(webViewPreview: true),
        ),
      );

      final manager = RuntimeManager(providers: [embedded, termux, webOnly]);
      await manager.initialize();

      expect(manager.activeProvider?.type, RuntimeProviderType.externalTermux);
      expect((await manager.capabilities()).git, isTrue);

      await manager.dispose();
    });

    test('falls back to WebViewOnly when shell runtimes are unavailable', () async {
      final manager = RuntimeManager(providers: [
        _FakeRuntimeProvider(
          type: RuntimeProviderType.embeddedLite,
          name: 'Embedded',
          health: const RuntimeHealth(
            type: RuntimeProviderType.embeddedLite,
            name: 'Embedded',
            available: false,
            ready: false,
            status: 'missing',
            capabilities: RuntimeCapabilities.none,
          ),
        ),
        _FakeRuntimeProvider(
          type: RuntimeProviderType.webViewOnly,
          name: 'WebView',
          health: const RuntimeHealth(
            type: RuntimeProviderType.webViewOnly,
            name: 'WebView',
            available: true,
            ready: true,
            status: 'ready',
            capabilities: RuntimeCapabilities(webViewPreview: true),
          ),
        ),
      ]);

      await manager.initialize();

      expect(manager.activeProvider?.type, RuntimeProviderType.webViewOnly);
      expect((await manager.capabilities()).webViewPreview, isTrue);

      await manager.dispose();
    });

    test('runs structured git commit action through the active runtime', () async {
      final provider = _FakeRuntimeProvider(
        type: RuntimeProviderType.mobileCodeHelper,
        name: 'Helper',
        health: const RuntimeHealth(
          type: RuntimeProviderType.mobileCodeHelper,
          name: 'Helper',
          available: true,
          ready: true,
          status: 'ready',
          capabilities: RuntimeCapabilities(shell: true, git: true),
        ),
      );
      final manager = RuntimeManager(providers: [provider]);

      final result = await manager.runAction(const RuntimeActionRequest(
        type: RuntimeActionType.gitCommit,
        projectPath: '/workspace/app',
        message: 'runtime action commit',
      ));

      expect(result.success, isTrue);
      expect(provider.commands, ['git add .', 'git commit -m "runtime action commit"']);

      await manager.dispose();
    });
  });
}

class _FakeRuntimeProvider implements RuntimeProvider {
  final RuntimeProviderType _type;
  final String _name;
  final RuntimeHealth _health;
  final StreamController<String> _logs = StreamController<String>.broadcast();
  final List<String> commands = [];

  _FakeRuntimeProvider({
    required RuntimeProviderType type,
    required String name,
    required RuntimeHealth health,
  })  : _type = type,
        _name = name,
        _health = health;

  @override
  RuntimeProviderType get type => _type;

  @override
  String get name => _name;

  @override
  Stream<String> get logStream => _logs.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<RuntimeCapabilities> capabilities() async => _health.capabilities;

  @override
  Future<RuntimeHealth> healthCheck() async => _health;

  @override
  Future<RuntimeCommandResult> execute(
    String command, {
    String? workingDir,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    commands.add(command);
    return RuntimeCommandResult(
      command: command,
      stdout: '',
      stderr: '',
      exitCode: 0,
      duration: Duration.zero,
      providerType: type,
    );
  }

  @override
  Stream<String> executeStream(
    String command, {
    String? workingDir,
    Map<String, String>? environment,
  }) async* {}

  @override
  Future<RuntimeSyncResult> syncWorkspace({
    required String sourcePath,
    required String targetPath,
  }) async {
    return RuntimeSyncResult(
      success: true,
      sourcePath: sourcePath,
      targetPath: targetPath,
    );
  }

  @override
  Future<BuildResult> buildWeb(String projectPath) async {
    return const BuildResult(success: true, buildTime: Duration.zero);
  }

  @override
  Future<BuildResult> buildApk(String projectPath, {BuildMode mode = BuildMode.debug}) async {
    return const BuildResult(success: true, buildTime: Duration.zero);
  }

  @override
  Future<InstallResult> installApk(String apkPath) async {
    return const InstallResult(success: true, packageName: 'test.app');
  }

  @override
  Future<void> launchApp(String packageName) async {}

  @override
  Future<void> uninstallApp(String packageName) async {}

  @override
  Future<void> stopCurrentTask() async {}
}
