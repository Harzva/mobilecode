// lib/services/runtime_provider.dart
// Runtime provider contracts for MobileCode execution backends.

import 'dart:async';

import 'termux_service.dart';

/// Ordered runtime backend types.
enum RuntimeProviderType {
  embeddedLite,
  mobileCodeHelper,
  externalTermux,
  cloud,
  webViewOnly,
}

/// Capabilities exposed by an execution backend.
class RuntimeCapabilities {
  final bool shell;
  final bool git;
  final bool node;
  final bool python;
  final bool flutter;
  final bool androidBuild;
  final bool pty;
  final bool backgroundService;
  final bool webViewPreview;
  final bool cloudBuild;

  const RuntimeCapabilities({
    this.shell = false,
    this.git = false,
    this.node = false,
    this.python = false,
    this.flutter = false,
    this.androidBuild = false,
    this.pty = false,
    this.backgroundService = false,
    this.webViewPreview = false,
    this.cloudBuild = false,
  });

  static const none = RuntimeCapabilities();

  RuntimeCapabilities merge(RuntimeCapabilities other) {
    return RuntimeCapabilities(
      shell: shell || other.shell,
      git: git || other.git,
      node: node || other.node,
      python: python || other.python,
      flutter: flutter || other.flutter,
      androidBuild: androidBuild || other.androidBuild,
      pty: pty || other.pty,
      backgroundService: backgroundService || other.backgroundService,
      webViewPreview: webViewPreview || other.webViewPreview,
      cloudBuild: cloudBuild || other.cloudBuild,
    );
  }
}

/// User-facing runtime health result.
class RuntimeHealth {
  final RuntimeProviderType type;
  final String name;
  final bool available;
  final bool ready;
  final String status;
  final RuntimeCapabilities capabilities;
  final List<String> missingDependencies;
  final List<String> recoveryActions;

  const RuntimeHealth({
    required this.type,
    required this.name,
    required this.available,
    required this.ready,
    required this.status,
    required this.capabilities,
    this.missingDependencies = const [],
    this.recoveryActions = const [],
  });
}

/// Result of a runtime command.
class RuntimeCommandResult {
  final String command;
  final String stdout;
  final String stderr;
  final int exitCode;
  final Duration duration;
  final RuntimeProviderType providerType;
  final String? taskId;
  final RuntimeTaskFailureKind failureKind;

  const RuntimeCommandResult({
    required this.command,
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.duration,
    required this.providerType,
    this.taskId,
    this.failureKind = RuntimeTaskFailureKind.none,
  });

  bool get success => exitCode == 0;
}

/// Recoverable task state exposed by runtimes that support background work.
enum RuntimeTaskStatus {
  queued,
  running,
  succeeded,
  failed,
  cancelled,
  timedOut,
  lost,
  unknown,
}

/// Coarse failure categories that can drive user recovery suggestions.
enum RuntimeTaskFailureKind {
  none,
  timeout,
  cancelled,
  dependencyMissing,
  commandBlocked,
  cwdOutsideWorkspace,
  authFailed,
  processFailed,
  runtimeLost,
  unknown,
}

/// A task snapshot is intentionally compact so the UI can restore context after
/// reconnecting without needing to understand each runtime's internal process model.
class RuntimeTaskSnapshot {
  final String taskId;
  final RuntimeTaskStatus status;
  final String command;
  final String? workingDir;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final int? exitCode;
  final Duration? duration;
  final List<String> logs;
  final RuntimeProviderType providerType;
  final String? error;
  final RuntimeTaskFailureKind failureKind;

  const RuntimeTaskSnapshot({
    required this.taskId,
    required this.status,
    required this.command,
    required this.providerType,
    this.workingDir,
    this.startedAt,
    this.finishedAt,
    this.exitCode,
    this.duration,
    this.logs = const [],
    this.error,
    this.failureKind = RuntimeTaskFailureKind.none,
  });

  bool get running => status == RuntimeTaskStatus.running || status == RuntimeTaskStatus.queued;
  bool get canCancel => running;

  RuntimeTaskSnapshot copyWith({
    String? taskId,
    RuntimeTaskStatus? status,
    String? command,
    String? workingDir,
    DateTime? startedAt,
    DateTime? finishedAt,
    int? exitCode,
    Duration? duration,
    List<String>? logs,
    RuntimeProviderType? providerType,
    String? error,
    RuntimeTaskFailureKind? failureKind,
  }) {
    return RuntimeTaskSnapshot(
      taskId: taskId ?? this.taskId,
      status: status ?? this.status,
      command: command ?? this.command,
      providerType: providerType ?? this.providerType,
      workingDir: workingDir ?? this.workingDir,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      exitCode: exitCode ?? this.exitCode,
      duration: duration ?? this.duration,
      logs: logs ?? this.logs,
      error: error ?? this.error,
      failureKind: failureKind ?? this.failureKind,
    );
  }
}

/// Result of syncing workspaces between the app and a runtime backend.
class RuntimeSyncResult {
  final bool success;
  final String sourcePath;
  final String targetPath;
  final String? error;

  const RuntimeSyncResult({
    required this.success,
    required this.sourcePath,
    required this.targetPath,
    this.error,
  });
}

/// Contract implemented by all MobileCode runtime backends.
abstract class RuntimeProvider {
  RuntimeProviderType get type;
  String get name;
  Stream<String> get logStream;

  Future<void> initialize();
  Future<RuntimeCapabilities> capabilities();
  Future<RuntimeHealth> healthCheck();

  Future<RuntimeCommandResult> execute(
    String command, {
    String? workingDir,
    Map<String, String>? environment,
    Duration? timeout,
  });

  Stream<String> executeStream(
    String command, {
    String? workingDir,
    Map<String, String>? environment,
  });

  Future<RuntimeSyncResult> syncWorkspace({
    required String sourcePath,
    required String targetPath,
  });

  Future<BuildResult> buildWeb(String projectPath);
  Future<BuildResult> buildApk(String projectPath, {BuildMode mode = BuildMode.debug});
  Future<InstallResult> installApk(String apkPath);
  Future<void> launchApp(String packageName);
  Future<void> uninstallApp(String packageName);
  Future<void> stopCurrentTask();
}

/// Optional extension implemented by providers that can recover task state.
abstract class RuntimeTaskMonitor {
  Future<RuntimeTaskSnapshot?> currentTask();
  Future<List<RuntimeTaskSnapshot>> listTasks({int limit = 20});
  Future<List<String>> taskLogs(String taskId, {int limit = 200});
}

/// Optional extension implemented by runtimes that can control individual
/// tasks instead of only stopping the current foreground process.
abstract class RuntimeTaskController {
  Future<void> stopTask(String taskId);
}

/// Optional extension for runtimes that expose a typed Termux-like task endpoint
/// used by `termux_task_start`.
abstract class RuntimeTypedTaskRunner {
  Future<Map<String, dynamic>> runTermuxTask({
    required String taskKind,
    required Map<String, dynamic> payload,
  });
}
