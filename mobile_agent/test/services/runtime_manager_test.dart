import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/runtime_actions.dart';
import 'package:mobile_agent/services/runtime_manager.dart';
import 'package:mobile_agent/services/runtime_provider.dart';
import 'package:mobile_agent/services/termux_service.dart';

void main() {
  group('RuntimeManager', () {
    test('default Android provider order prefers Helper and Termux daemon', () {
      final manager = RuntimeManager.withExternalTermux(
        TermuxService(),
        helperBaseUri: Uri.parse('http://127.0.0.1:8765'),
      );

      expect(manager.providers.map((provider) => provider.name), [
        'MobileCode Helper',
        'External Termux daemon',
        'External Termux',
        'Embedded Lite Runtime',
        'Cloud Runtime',
        'WebView Only',
      ]);
    });

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

    test('falls back to WebViewOnly when shell runtimes are unavailable',
        () async {
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

    test('runs structured git commit action through the active runtime',
        () async {
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
      expect(provider.commands,
          ['git add .', 'git commit -m "runtime action commit"']);

      await manager.dispose();
    });

    test('restores current task snapshot from monitor-capable provider',
        () async {
      final provider = _FakeRuntimeProviderWithTask(
        type: RuntimeProviderType.mobileCodeHelper,
        name: 'Helper',
        health: const RuntimeHealth(
          type: RuntimeProviderType.mobileCodeHelper,
          name: 'Helper',
          available: true,
          ready: true,
          status: 'ready',
          capabilities: RuntimeCapabilities(shell: true),
        ),
        task: const RuntimeTaskSnapshot(
          taskId: 'task-1',
          status: RuntimeTaskStatus.running,
          command: 'npm run build',
          providerType: RuntimeProviderType.mobileCodeHelper,
          logs: ['stdout: building'],
        ),
      );
      final manager = RuntimeManager(providers: [provider]);

      final task = await manager.currentTaskSnapshot();

      expect(task?.taskId, 'task-1');
      expect(task?.running, isTrue);
      expect(task?.logs, ['stdout: building']);

      await manager.dispose();
    });

    test('routes task history and logs through monitor-capable provider',
        () async {
      const snapshot = RuntimeTaskSnapshot(
        taskId: 'task-2',
        status: RuntimeTaskStatus.failed,
        command: 'npm test',
        providerType: RuntimeProviderType.mobileCodeHelper,
        logs: ['stderr: failed'],
        failureKind: RuntimeTaskFailureKind.processFailed,
      );
      final provider = _FakeRuntimeProviderWithTask(
        type: RuntimeProviderType.mobileCodeHelper,
        name: 'Helper',
        health: const RuntimeHealth(
          type: RuntimeProviderType.mobileCodeHelper,
          name: 'Helper',
          available: true,
          ready: true,
          status: 'ready',
          capabilities: RuntimeCapabilities(shell: true),
        ),
        task: snapshot,
      );
      final manager = RuntimeManager(providers: [provider]);

      final history = await manager.taskHistory(limit: 5);
      final logs = await manager.taskLogs('task-2', limit: 20);

      expect(history, [snapshot]);
      expect(logs, ['stderr: failed']);

      await manager.dispose();
    });

    test('stops task by id through controller-capable provider', () async {
      const snapshot = RuntimeTaskSnapshot(
        taskId: 'task-3',
        status: RuntimeTaskStatus.running,
        command: 'npm run build',
        providerType: RuntimeProviderType.mobileCodeHelper,
      );
      final provider = _FakeRuntimeProviderWithTask(
        type: RuntimeProviderType.mobileCodeHelper,
        name: 'Helper',
        health: const RuntimeHealth(
          type: RuntimeProviderType.mobileCodeHelper,
          name: 'Helper',
          available: true,
          ready: true,
          status: 'ready',
          capabilities: RuntimeCapabilities(shell: true),
        ),
        task: snapshot,
      );
      final manager = RuntimeManager(providers: [provider]);

      await manager.stopTask('task-3');

      expect(provider.stoppedTaskIds, ['task-3']);

      await manager.dispose();
    });

    test(
        'runs validation pipeline and stops at first failed action with recovery hint',
        () async {
      final provider = _FakeRuntimeProvider(
        type: RuntimeProviderType.mobileCodeHelper,
        name: 'Helper',
        health: const RuntimeHealth(
          type: RuntimeProviderType.mobileCodeHelper,
          name: 'Helper',
          available: true,
          ready: true,
          status: 'ready',
          capabilities: RuntimeCapabilities(shell: true, node: true),
        ),
        exitCodes: const {
          'npm test': 1,
        },
      );
      final manager = RuntimeManager(providers: [provider]);

      final result = await manager.runActionPipeline(const [
        RuntimeActionRequest(
          type: RuntimeActionType.installDependencies,
          projectPath: '/workspace/app',
          packageManager: 'npm',
        ),
        RuntimeActionRequest(
          type: RuntimeActionType.runTests,
          projectPath: '/workspace/app',
          packageManager: 'npm',
        ),
        RuntimeActionRequest(
          type: RuntimeActionType.buildPreview,
          projectPath: '/workspace/app',
          packageManager: 'npm',
        ),
      ]);

      expect(result.success, isFalse);
      expect(result.failedStep?.action, RuntimeActionType.runTests);
      expect(result.recoveryHint, contains('Tests failed'));
      expect(provider.commands, ['npm install', 'npm test']);

      await manager.dispose();
    });

    test('preflights node project before auto validation', () async {
      final provider = _FakeRuntimeProvider(
        type: RuntimeProviderType.mobileCodeHelper,
        name: 'Helper',
        health: const RuntimeHealth(
          type: RuntimeProviderType.mobileCodeHelper,
          name: 'Helper',
          available: true,
          ready: true,
          status: 'ready',
          capabilities: RuntimeCapabilities(shell: true, node: true),
        ),
        stdoutByCommand: const {
          runtimeProjectProbeCommand: './package.json\n./.git\n',
        },
      );
      final manager = RuntimeManager(providers: [provider]);

      final result =
          await manager.validateProject(projectPath: '/workspace/app');

      expect(result.success, isTrue);
      expect(result.profile?.packageManager, 'npm');
      expect(provider.commands, [
        runtimeProjectProbeCommand,
        'npm install',
        'npm test',
        'npm run build',
      ]);

      await manager.dispose();
    });

    test('preflight avoids preview for python project', () async {
      final provider = _FakeRuntimeProvider(
        type: RuntimeProviderType.mobileCodeHelper,
        name: 'Helper',
        health: const RuntimeHealth(
          type: RuntimeProviderType.mobileCodeHelper,
          name: 'Helper',
          available: true,
          ready: true,
          status: 'ready',
          capabilities: RuntimeCapabilities(shell: true, python: true),
        ),
        stdoutByCommand: const {
          runtimeProjectProbeCommand: './requirements.txt\n',
        },
      );
      final manager = RuntimeManager(providers: [provider]);

      final result =
          await manager.validateProject(projectPath: '/workspace/app');

      expect(result.success, isTrue);
      expect(result.profile?.packageManager, 'python');
      expect(provider.commands, [
        runtimeProjectProbeCommand,
        'python3 -m pip install -r requirements.txt',
        'python3 -m pytest',
      ]);

      await manager.dispose();
    });

    test('auto action skips when preflight cannot identify project', () async {
      final provider = _FakeRuntimeProvider(
        type: RuntimeProviderType.mobileCodeHelper,
        name: 'Helper',
        health: const RuntimeHealth(
          type: RuntimeProviderType.mobileCodeHelper,
          name: 'Helper',
          available: true,
          ready: true,
          status: 'ready',
          capabilities:
              RuntimeCapabilities(shell: true, node: true, flutter: true),
        ),
        stdoutByCommand: const {
          runtimeProjectProbeCommand: '',
        },
      );
      final manager = RuntimeManager(providers: [provider]);

      final result = await manager.runAction(const RuntimeActionRequest(
        type: RuntimeActionType.installDependencies,
        projectPath: '/workspace/empty',
      ));

      expect(result.success, isFalse);
      expect(result.skippedReason, contains('preflight'));
      expect(result.recoveryHint, contains('package.json'));
      expect(provider.commands, [runtimeProjectProbeCommand]);

      await manager.dispose();
    });
  });
}

class _FakeRuntimeProvider implements RuntimeProvider {
  final RuntimeProviderType _type;
  final String _name;
  final RuntimeHealth _health;
  final Map<String, int> _exitCodes;
  final Map<String, String> _stdoutByCommand;
  final StreamController<String> _logs = StreamController<String>.broadcast();
  final List<String> commands = [];

  _FakeRuntimeProvider({
    required RuntimeProviderType type,
    required String name,
    required RuntimeHealth health,
    Map<String, int> exitCodes = const {},
    Map<String, String> stdoutByCommand = const {},
  })  : _type = type,
        _name = name,
        _health = health,
        _exitCodes = exitCodes,
        _stdoutByCommand = stdoutByCommand;

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
    final exitCode = _exitCodes[command] ?? 0;
    return RuntimeCommandResult(
      command: command,
      stdout: _stdoutByCommand[command] ??
          (exitCode == 0 ? '' : 'ok before failure'),
      stderr: exitCode == 0 ? '' : 'test failed',
      exitCode: exitCode,
      duration: Duration.zero,
      providerType: type,
      failureKind: exitCode == 0
          ? RuntimeTaskFailureKind.none
          : RuntimeTaskFailureKind.processFailed,
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
  Future<BuildResult> buildApk(String projectPath,
      {BuildMode mode = BuildMode.debug}) async {
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

class _FakeRuntimeProviderWithTask extends _FakeRuntimeProvider
    implements RuntimeTaskMonitor, RuntimeTaskController {
  final RuntimeTaskSnapshot task;
  final List<String> stoppedTaskIds = [];

  _FakeRuntimeProviderWithTask({
    required RuntimeProviderType type,
    required String name,
    required RuntimeHealth health,
    required this.task,
  }) : super(type: type, name: name, health: health);

  @override
  Future<RuntimeTaskSnapshot?> currentTask() async => task;

  @override
  Future<List<RuntimeTaskSnapshot>> listTasks({int limit = 20}) async => [task];

  @override
  Future<List<String>> taskLogs(String taskId, {int limit = 200}) async =>
      task.logs;

  @override
  Future<void> stopTask(String taskId) async {
    stoppedTaskIds.add(taskId);
  }
}
