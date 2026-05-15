// lib/services/runtime_actions.dart
// Structured runtime actions for agent-safe command orchestration.

import 'runtime_provider.dart';

enum RuntimeActionType {
  installDependencies,
  runTests,
  buildPreview,
  gitCommit,
  publishPages,
}

class RuntimeActionRequest {
  const RuntimeActionRequest({
    required this.type,
    required this.projectPath,
    this.message,
    this.packageManager,
    this.timeout = const Duration(minutes: 10),
  });

  final RuntimeActionType type;
  final String projectPath;
  final String? message;
  final String? packageManager;
  final Duration timeout;
}

class RuntimeActionPlan {
  const RuntimeActionPlan({
    required this.action,
    required this.commands,
    required this.summary,
  });

  final RuntimeActionType action;
  final List<String> commands;
  final String summary;
}

class RuntimeActionResult {
  const RuntimeActionResult({
    required this.action,
    required this.success,
    required this.summary,
    required this.results,
    this.skippedReason,
    this.recoveryHint,
  });

  final RuntimeActionType action;
  final bool success;
  final String summary;
  final List<RuntimeCommandResult> results;
  final String? skippedReason;
  final String? recoveryHint;

  RuntimeCommandResult? get lastResult => results.isEmpty ? null : results.last;
}

class RuntimeActionPipelineResult {
  const RuntimeActionPipelineResult({
    required this.success,
    required this.summary,
    required this.steps,
    this.recoveryHint,
  });

  final bool success;
  final String summary;
  final List<RuntimeActionResult> steps;
  final String? recoveryHint;

  RuntimeActionResult? get failedStep {
    for (final step in steps) {
      if (!step.success) return step;
    }
    return null;
  }
}

RuntimeActionPlan? planRuntimeAction(
  RuntimeActionRequest request,
  RuntimeCapabilities capabilities,
) {
  final packageManager = request.packageManager?.trim().toLowerCase();

  switch (request.type) {
    case RuntimeActionType.installDependencies:
      if (packageManager == 'flutter' || capabilities.flutter) {
        return const RuntimeActionPlan(
          action: RuntimeActionType.installDependencies,
          commands: ['flutter pub get'],
          summary: 'Install Flutter/Dart dependencies.',
        );
      }
      if (packageManager == 'npm' || capabilities.node) {
        return const RuntimeActionPlan(
          action: RuntimeActionType.installDependencies,
          commands: ['npm install'],
          summary: 'Install Node dependencies.',
        );
      }
      if (packageManager == 'python' || capabilities.python) {
        return const RuntimeActionPlan(
          action: RuntimeActionType.installDependencies,
          commands: ['python3 -m pip install -r requirements.txt'],
          summary: 'Install Python dependencies from requirements.txt.',
        );
      }
      return null;

    case RuntimeActionType.runTests:
      if (packageManager == 'flutter' || capabilities.flutter) {
        return const RuntimeActionPlan(
          action: RuntimeActionType.runTests,
          commands: ['flutter test'],
          summary: 'Run Flutter tests.',
        );
      }
      if (packageManager == 'npm' || capabilities.node) {
        return const RuntimeActionPlan(
          action: RuntimeActionType.runTests,
          commands: ['npm test'],
          summary: 'Run Node test script.',
        );
      }
      if (packageManager == 'python' || capabilities.python) {
        return const RuntimeActionPlan(
          action: RuntimeActionType.runTests,
          commands: ['python3 -m pytest'],
          summary: 'Run Python pytest suite.',
        );
      }
      return null;

    case RuntimeActionType.buildPreview:
      if (packageManager == 'flutter' || capabilities.flutter) {
        return const RuntimeActionPlan(
          action: RuntimeActionType.buildPreview,
          commands: ['flutter build web'],
          summary: 'Build Flutter Web preview.',
        );
      }
      if (packageManager == 'npm' || capabilities.node) {
        return const RuntimeActionPlan(
          action: RuntimeActionType.buildPreview,
          commands: ['npm run build'],
          summary: 'Build Node web preview.',
        );
      }
      return null;

    case RuntimeActionType.gitCommit:
      if (!capabilities.git) return null;
      final message = request.message?.trim();
      if (message == null || message.isEmpty) return null;
      return RuntimeActionPlan(
        action: RuntimeActionType.gitCommit,
        commands: ['git add .', 'git commit -m ${quoteRuntimeArg(message)}'],
        summary: 'Commit workspace changes.',
      );

    case RuntimeActionType.publishPages:
      if (!capabilities.git) return null;
      return const RuntimeActionPlan(
        action: RuntimeActionType.publishPages,
        commands: ['git push origin HEAD'],
        summary: 'Push current branch for GitHub Pages or release automation.',
      );
  }
}

String quoteRuntimeArg(String value) {
  final escaped = value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  return '"$escaped"';
}

String runtimeActionRecoveryHint({
  required RuntimeActionType action,
  required RuntimeCapabilities capabilities,
  RuntimeCommandResult? result,
  String? skippedReason,
}) {
  if (skippedReason != null && skippedReason.isNotEmpty) {
    return _capabilityRecoveryHint(action, capabilities);
  }

  final failureKind = result?.failureKind;
  switch (failureKind) {
    case RuntimeTaskFailureKind.timeout:
      return 'The task timed out. Retry with a longer timeout or move this build to Cloud Runtime.';
    case RuntimeTaskFailureKind.cancelled:
      return 'The task was cancelled. Retry the failed step when the runtime is idle.';
    case RuntimeTaskFailureKind.dependencyMissing:
      return 'A required tool or dependency is missing. Run Install first, then retry, or switch to Termux/Cloud with the toolchain installed.';
    case RuntimeTaskFailureKind.commandBlocked:
      return 'The runtime blocked this command. Prefer a structured Runtime Action or review the command policy before allowing it.';
    case RuntimeTaskFailureKind.cwdOutsideWorkspace:
      return 'The project path is outside the runtime workspace. Choose a workspace path exposed by Helper/Termux and retry.';
    case RuntimeTaskFailureKind.authFailed:
      return 'Helper auth failed. Restart the Helper and verify the app is using the same localhost token.';
    case RuntimeTaskFailureKind.runtimeLost:
      return 'The runtime lost the task after a restart. Open History, recover logs, then rerun the failed step.';
    case RuntimeTaskFailureKind.processFailed:
    case RuntimeTaskFailureKind.unknown:
      return _processFailureHint(action);
    case RuntimeTaskFailureKind.none:
    case null:
      if (result != null && !result.success) return _processFailureHint(action);
      return 'No recovery action is needed.';
  }
}

String _capabilityRecoveryHint(RuntimeActionType action, RuntimeCapabilities capabilities) {
  return switch (action) {
    RuntimeActionType.installDependencies || RuntimeActionType.runTests || RuntimeActionType.buildPreview =>
      'Current runtime cannot plan this action from its capabilities. Pick the correct action profile, start Helper/Termux, or move the task to Cloud Runtime.',
    RuntimeActionType.gitCommit || RuntimeActionType.publishPages =>
      capabilities.git
          ? 'Git is available, but this action is missing required input. Check the commit message or branch state.'
          : 'Git is not available in the active runtime. Start Helper/Termux with git installed or use GitHub API publishing.',
  };
}

String _processFailureHint(RuntimeActionType action) {
  return switch (action) {
    RuntimeActionType.installDependencies =>
      'Dependency installation failed. Open logs, fix the package manager error, then retry Install before running tests.',
    RuntimeActionType.runTests =>
      'Tests failed. Open logs, fix the first failing assertion or compile error, then retry Test.',
    RuntimeActionType.buildPreview =>
      'Preview build failed. Inspect the build log, fix the compile/bundle error, then retry Preview.',
    RuntimeActionType.gitCommit =>
      'Git commit failed. Check whether there are staged changes, identity config, or repository initialization issues.',
    RuntimeActionType.publishPages =>
      'Publish failed. Check git remote/auth/branch permissions, then retry or switch to GitHub API publishing.',
  };
}
