// lib/services/runtime_manager.dart
// Selects and routes commands to the best available MobileCode runtime.

import 'dart:async';

import 'external_termux_provider.dart';
import 'mobile_code_helper_provider.dart';
import 'runtime_actions.dart';
import 'runtime_placeholder_providers.dart';
import 'runtime_provider.dart';
import 'termux_service.dart';

class RuntimeManager {
  final List<RuntimeProvider> _providers;
  final StreamController<String> _logController = StreamController<String>.broadcast();
  final List<StreamSubscription<String>> _logSubscriptions = [];

  RuntimeProvider? _activeProvider;
  RuntimeHealth? _activeHealth;
  bool _initialized = false;

  RuntimeManager({required List<RuntimeProvider> providers}) : _providers = providers;

  factory RuntimeManager.withExternalTermux(
    TermuxService termux, {
    Uri? helperBaseUri,
  }) {
    return RuntimeManager(
      providers: [
        EmbeddedLiteRuntimeProvider(),
        MobileCodeHelperProvider(baseUri: helperBaseUri),
        ExternalTermuxProvider(termux),
        CloudRuntimeProvider(),
        WebViewOnlyRuntimeProvider(),
      ],
    );
  }

  Stream<String> get logStream => _logController.stream;
  RuntimeProvider? get activeProvider => _activeProvider;
  RuntimeHealth? get activeHealth => _activeHealth;
  List<RuntimeProvider> get providers => List.unmodifiable(_providers);

  Future<void> initialize() async {
    if (_initialized) return;

    for (final provider in _providers) {
      try {
        await provider.initialize();
      } catch (e) {
        _logController.add('[runtime] ${provider.name} initialization failed: $e');
      }
      _logSubscriptions.add(provider.logStream.listen(_logController.add));
    }

    await refresh();
    _initialized = true;
  }

  Future<List<RuntimeHealth>> refresh() async {
    final health = <RuntimeHealth>[];

    for (final provider in _providers) {
      try {
        health.add(await provider.healthCheck());
      } catch (e) {
        health.add(RuntimeHealth(
          type: provider.type,
          name: provider.name,
          available: false,
          ready: false,
          status: 'Runtime health check failed: $e',
          capabilities: RuntimeCapabilities.none,
          missingDependencies: const ['Health check'],
          recoveryActions: const ['Open runtime diagnostics and retry.'],
        ));
      }
    }

    _activeHealth = health.firstWhere(
      (item) => item.available && item.ready,
      orElse: () => health.last,
    );

    _activeProvider = _providers.firstWhere(
      (provider) => provider.type == _activeHealth!.type,
      orElse: () => _providers.last,
    );

    return health;
  }

  Future<RuntimeCapabilities> capabilities() async {
    await _ensureReady();
    return _activeProvider!.capabilities();
  }

  Future<RuntimeCommandResult> execute(
    String command, {
    String? workingDir,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    await _ensureReady();
    return _activeProvider!.execute(
      command,
      workingDir: workingDir,
      environment: environment,
      timeout: timeout,
    );
  }

  Stream<String> executeStream(
    String command, {
    String? workingDir,
    Map<String, String>? environment,
  }) async* {
    await _ensureReady();
    yield* _activeProvider!.executeStream(
      command,
      workingDir: workingDir,
      environment: environment,
    );
  }

  Future<RuntimeSyncResult> syncWorkspace({
    required String sourcePath,
    required String targetPath,
  }) async {
    await _ensureReady();
    return _activeProvider!.syncWorkspace(sourcePath: sourcePath, targetPath: targetPath);
  }

  Future<BuildResult> buildWeb(String projectPath) async {
    await _ensureReady();
    return _activeProvider!.buildWeb(projectPath);
  }

  Future<BuildResult> buildApk(String projectPath, {BuildMode mode = BuildMode.debug}) async {
    await _ensureReady();
    return _activeProvider!.buildApk(projectPath, mode: mode);
  }

  Future<InstallResult> installApk(String apkPath) async {
    await _ensureReady();
    return _activeProvider!.installApk(apkPath);
  }

  Future<void> launchApp(String packageName) async {
    await _ensureReady();
    await _activeProvider!.launchApp(packageName);
  }

  Future<void> uninstallApp(String packageName) async {
    await _ensureReady();
    await _activeProvider!.uninstallApp(packageName);
  }

  Future<void> stopCurrentTask() async {
    await _ensureReady();
    await _activeProvider!.stopCurrentTask();
  }

  Future<RuntimeTaskSnapshot?> currentTaskSnapshot() async {
    await _ensureReady();
    final provider = _activeProvider;
    if (provider == null || provider is! RuntimeTaskMonitor) return null;
    return (provider as RuntimeTaskMonitor).currentTask();
  }

  Future<List<RuntimeTaskSnapshot>> taskHistory({int limit = 20}) async {
    await _ensureReady();
    final provider = _activeProvider;
    if (provider == null || provider is! RuntimeTaskMonitor) return const [];
    return (provider as RuntimeTaskMonitor).listTasks(limit: limit);
  }

  Future<List<String>> taskLogs(String taskId, {int limit = 200}) async {
    await _ensureReady();
    final provider = _activeProvider;
    if (provider == null || provider is! RuntimeTaskMonitor) return const [];
    return (provider as RuntimeTaskMonitor).taskLogs(taskId, limit: limit);
  }

  Future<RuntimeActionResult> runAction(RuntimeActionRequest request) async {
    await _ensureReady();
    final provider = _activeProvider!;
    final caps = await provider.capabilities();
    final plan = planRuntimeAction(request, caps);
    if (plan == null) {
      const skippedReason = 'Missing capability or required action input.';
      return RuntimeActionResult(
        action: request.type,
        success: false,
        summary: 'Runtime cannot plan ${request.type.name} with current capabilities.',
        results: const [],
        skippedReason: skippedReason,
        recoveryHint: runtimeActionRecoveryHint(
          action: request.type,
          capabilities: caps,
          skippedReason: skippedReason,
        ),
      );
    }

    final results = <RuntimeCommandResult>[];
    for (final command in plan.commands) {
      final result = await provider.execute(
        command,
        workingDir: request.projectPath,
        timeout: request.timeout,
      );
      results.add(result);
      if (!result.success) {
        return RuntimeActionResult(
          action: request.type,
          success: false,
          summary: '${plan.summary} Failed at: $command',
          results: List.unmodifiable(results),
          recoveryHint: runtimeActionRecoveryHint(
            action: request.type,
            capabilities: caps,
            result: result,
          ),
        );
      }
    }

    return RuntimeActionResult(
      action: request.type,
      success: true,
      summary: plan.summary,
      results: List.unmodifiable(results),
    );
  }

  Future<RuntimeActionPipelineResult> runActionPipeline(
    List<RuntimeActionRequest> requests,
  ) async {
    final steps = <RuntimeActionResult>[];
    for (final request in requests) {
      final result = await runAction(request);
      steps.add(result);
      if (!result.success) {
        return RuntimeActionPipelineResult(
          success: false,
          summary: 'Stopped at ${request.type.name}: ${result.summary}',
          steps: List.unmodifiable(steps),
          recoveryHint: result.recoveryHint,
        );
      }
    }

    return RuntimeActionPipelineResult(
      success: true,
      summary: 'Runtime validation completed: ${steps.map((step) => step.action.name).join(' -> ')}.',
      steps: List.unmodifiable(steps),
    );
  }

  Future<void> _ensureReady() async {
    if (!_initialized) {
      await initialize();
    }
    _activeProvider ??= _providers.last;
  }

  Future<void> dispose() async {
    for (final subscription in _logSubscriptions) {
      await subscription.cancel();
    }
    _logSubscriptions.clear();
    if (!_logController.isClosed) {
      await _logController.close();
    }
    _initialized = false;
  }
}
