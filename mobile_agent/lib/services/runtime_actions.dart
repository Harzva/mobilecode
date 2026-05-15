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
  });

  final RuntimeActionType action;
  final bool success;
  final String summary;
  final List<RuntimeCommandResult> results;
  final String? skippedReason;

  RuntimeCommandResult? get lastResult => results.isEmpty ? null : results.last;
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
