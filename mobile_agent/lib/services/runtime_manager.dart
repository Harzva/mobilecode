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

  Future<void> stopTask(String taskId) async {
    await _ensureReady();
    final id = taskId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(taskId, 'taskId', 'Task ID is required.');
    }
    final provider = _activeProvider!;
    if (provider is RuntimeTaskController) {
      await (provider as RuntimeTaskController).stopTask(id);
      return;
    }
    if (provider is RuntimeTaskMonitor) {
      final task = await (provider as RuntimeTaskMonitor).currentTask();
      if (task?.taskId == id) {
        await provider.stopCurrentTask();
        return;
      }
    }
    throw UnsupportedError('${provider.name} cannot stop task $id by ID.');
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

  Future<RuntimeProjectProfile> preflightProject(
    String projectPath, {
    String? packageManager,
  }) async {
    await _ensureReady();
    final provider = _activeProvider!;
    final caps = await provider.capabilities();
    if (!caps.shell) {
      return runtimeProjectPreflightFailure(
        projectPath: projectPath,
        summary: 'Active runtime cannot inspect project files because shell execution is unavailable.',
        recoveryHint: 'Start MobileCode Helper, External Termux, or Cloud Runtime before running project actions.',
      );
    }

    try {
      if (provider is RuntimeProjectInspector) {
        return await (provider as RuntimeProjectInspector).preflightProject(
          projectPath,
          packageManager: packageManager,
        );
      }

      final probe = await provider.execute(
        runtimeProjectProbeCommand,
        workingDir: projectPath,
        timeout: const Duration(seconds: 8),
      );
      if (!probe.success) {
        return runtimeProjectPreflightFailure(
          projectPath: projectPath,
          summary: 'Project preflight failed: ${probe.stderr.trim().isEmpty ? probe.stdout.trim() : probe.stderr.trim()}',
          recoveryHint: runtimeActionRecoveryHint(
            action: RuntimeActionType.installDependencies,
            capabilities: caps,
            result: probe,
          ),
        );
      }

      return profileRuntimeProject(
        projectPath: projectPath,
        probeOutput: probe.stdout,
        capabilities: caps,
        packageManagerOverride: packageManager,
      );
    } on Object catch (error) {
      return runtimeProjectPreflightFailure(
        projectPath: projectPath,
        summary: 'Project preflight failed: $error',
      );
    }
  }

  Future<RuntimeActionResult> runAction(RuntimeActionRequest request) async {
    await _ensureReady();
    final provider = _activeProvider!;
    final caps = await provider.capabilities();
    RuntimeActionRequest effectiveRequest = request;
    RuntimeProjectProfile? profile;
    if (runtimeActionNeedsProjectProfile(request.type) &&
        normalizeRuntimePackageManager(request.packageManager) == null) {
      profile = await preflightProject(request.projectPath);
      if (!profile.recognized) {
        const skippedReason = 'Project preflight could not identify a supported project.';
        return RuntimeActionResult(
          action: request.type,
          success: false,
          summary: profile.summary,
          results: const [],
          skippedReason: skippedReason,
          recoveryHint: profile.recoveryHint,
        );
      }
      if (!runtimeProjectToolchainAvailable(profile, caps)) {
        const skippedReason = 'Project toolchain is not available in the active runtime.';
        return RuntimeActionResult(
          action: request.type,
          success: false,
          summary: profile.summary,
          results: const [],
          skippedReason: skippedReason,
          recoveryHint: profile.recoveryHint,
        );
      }
      effectiveRequest = RuntimeActionRequest(
        type: request.type,
        projectPath: request.projectPath,
        message: request.message,
        packageManager: profile.packageManager,
        timeout: request.timeout,
      );
    }

    final plan = planRuntimeAction(effectiveRequest, caps);
    if (plan == null) {
      const skippedReason = 'Missing capability or required action input.';
      return RuntimeActionResult(
        action: effectiveRequest.type,
        success: false,
        summary: 'Runtime cannot plan ${effectiveRequest.type.name} with current capabilities.',
        results: const [],
        skippedReason: skippedReason,
        recoveryHint: runtimeActionRecoveryHint(
          action: effectiveRequest.type,
          capabilities: caps,
          skippedReason: skippedReason,
        ),
      );
    }

    final results = <RuntimeCommandResult>[];
    for (final command in plan.commands) {
      final result = await provider.execute(
        command,
        workingDir: effectiveRequest.projectPath,
        timeout: effectiveRequest.timeout,
      );
      results.add(result);
      if (!result.success) {
        return RuntimeActionResult(
          action: effectiveRequest.type,
          success: false,
          summary: '${plan.summary} Failed at: $command',
          results: List.unmodifiable(results),
          recoveryHint: runtimeActionRecoveryHint(
            action: effectiveRequest.type,
            capabilities: caps,
            result: result,
          ),
        );
      }
    }

    return RuntimeActionResult(
      action: effectiveRequest.type,
      success: true,
      summary: profile == null ? plan.summary : '${plan.summary} ${profile.summary}',
      results: List.unmodifiable(results),
    );
  }

  Future<RuntimeActionPipelineResult> validateProject({
    required String projectPath,
    String? packageManager,
    String? message,
  }) async {
    await _ensureReady();
    final caps = await _activeProvider!.capabilities();
    final profile = await preflightProject(projectPath, packageManager: packageManager);
    if (!profile.recognized) {
      return RuntimeActionPipelineResult(
        success: false,
        summary: profile.summary,
        steps: const [],
        recoveryHint: profile.recoveryHint,
        profile: profile,
      );
    }
    if (!runtimeProjectToolchainAvailable(profile, caps)) {
      return RuntimeActionPipelineResult(
        success: false,
        summary: profile.summary,
        steps: const [],
        recoveryHint: profile.recoveryHint,
        profile: profile,
      );
    }

    final requests = profile.validationActions
        .map(
          (action) => RuntimeActionRequest(
            type: action,
            projectPath: projectPath,
            packageManager: profile.packageManager,
            message: message,
          ),
        )
        .toList();
    final result = await runActionPipeline(requests);
    return RuntimeActionPipelineResult(
      success: result.success,
      summary: '${profile.summary} ${result.summary}',
      steps: result.steps,
      recoveryHint: result.recoveryHint,
      profile: profile,
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
