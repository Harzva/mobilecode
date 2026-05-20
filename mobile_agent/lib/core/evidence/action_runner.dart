import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import 'action_evidence_store.dart';
import 'evidence_model.dart';

/// Result returned by [ActionRunner].
///
/// The evidence is always recorded in [ActionEvidenceStore]. Optional output
/// fields carry the small, direct result needed by follow-up actions.
class ActionRunnerResult {
  const ActionRunnerResult({
    required this.evidence,
    this.text,
    this.path,
    this.url,
  });

  final ActionEvidence evidence;
  final String? text;
  final String? path;
  final String? url;

  bool get success => evidence.success;
}

class _ActionRunnerFailure implements Exception {
  const _ActionRunnerFailure(
    this.message, {
    this.failureKind = ActionFailureKind.unknown,
    this.recoveryActions = const [],
  });

  final String message;
  final String failureKind;
  final List<String> recoveryActions;

  @override
  String toString() => message;
}

/// Minimal H06 action runner.
///
/// This runner intentionally starts with local, bounded actions only:
/// writeFile, readFile, and previewHtml. It does not run shell commands and it
/// rejects paths outside [workspaceRootPath].
class ActionRunner {
  ActionRunner({
    required String workspaceRootPath,
    ActionEvidenceStore? evidenceStore,
  })  : workspaceRootPath = p.normalize(p.absolute(workspaceRootPath)),
        evidenceStore = evidenceStore ?? ActionEvidenceStore();

  final String workspaceRootPath;
  final ActionEvidenceStore evidenceStore;

  Future<ActionRunnerResult> run(ActionSchema schema) async {
    final startedAt = DateTime.now();
    try {
      if (schema.approvalRequired) {
        throw const _ActionRunnerFailure(
          'Action requires approval before execution.',
          failureKind: ActionFailureKind.commandBlocked,
          recoveryActions: ['Approve the action before running it.'],
        );
      }

      return switch (schema.actionName) {
        MobileCodeAction.writeFile => await _writeFile(schema, startedAt),
        MobileCodeAction.readFile => await _readFile(schema, startedAt),
        MobileCodeAction.previewHtml => await _previewHtml(schema, startedAt),
        _ => _unsupported(schema, startedAt),
      };
    } on _ActionRunnerFailure catch (error) {
      return _recordFailure(
        schema,
        startedAt,
        error.message,
        failureKind: error.failureKind,
        recoveryActions: error.recoveryActions,
      );
    } on Object catch (error) {
      return _recordFailure(
        schema,
        startedAt,
        error.toString(),
        failureKind: ActionFailureKind.unknown,
        recoveryActions: const ['Open action details and inspect the captured error.'],
      );
    }
  }

  Future<ActionRunnerResult> _writeFile(ActionSchema schema, DateTime startedAt) async {
    final target = _resolveWorkspacePath(_requiredString(schema, 'path'));
    final content = _requiredString(schema, 'content');
    final overwrite = schema.params['overwrite'] as bool? ?? true;
    final file = File(target);
    if (await file.exists() && !overwrite) {
      throw _ActionRunnerFailure(
        'File already exists and overwrite=false: ${_relative(target)}',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: const ['Enable overwrite or choose a different file path.'],
      );
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true);

    final evidence = ActionEvidence(
      evidenceId: schema.requestId ?? generateEvidenceId(),
      actionName: MobileCodeAction.writeFile,
      paramsSummary: schema.paramsSummary.isEmpty ? 'write ${_relative(target)}' : schema.paramsSummary,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      success: true,
      artifactPaths: [target],
      logs: ['Wrote ${utf8.encode(content).length} bytes to ${_relative(target)}.'],
      metadata: {
        'relativePath': _relative(target),
        'byteLength': utf8.encode(content).length,
      },
    );
    evidenceStore.add(evidence);
    return ActionRunnerResult(evidence: evidence, path: target);
  }

  Future<ActionRunnerResult> _readFile(ActionSchema schema, DateTime startedAt) async {
    final target = _resolveWorkspacePath(_requiredString(schema, 'path'));
    final file = File(target);
    if (!await file.exists()) {
      throw _ActionRunnerFailure(
        'File does not exist: ${_relative(target)}',
        failureKind: ActionFailureKind.processFailed,
        recoveryActions: const ['Check the path or create the file before reading it.'],
      );
    }

    final maxBytes = _intParam(schema, 'maxBytes', defaultValue: 200 * 1024);
    final bytes = await file.readAsBytes();
    final readLength = math.min(bytes.length, maxBytes).toInt();
    final text = utf8.decode(bytes.take(readLength).toList(), allowMalformed: true);
    final truncated = bytes.length > readLength;

    final evidence = ActionEvidence(
      evidenceId: schema.requestId ?? generateEvidenceId(),
      actionName: MobileCodeAction.readFile,
      paramsSummary: schema.paramsSummary.isEmpty ? 'read ${_relative(target)}' : schema.paramsSummary,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      success: true,
      artifactPaths: [target],
      logs: [
        'Read ${_relative(target)} (${bytes.length} bytes${truncated ? ', truncated to $readLength bytes' : ''}).',
      ],
      metadata: {
        'relativePath': _relative(target),
        'byteLength': bytes.length,
        'truncated': truncated,
        'contentPreview': _compact(text, 2000),
      },
    );
    evidenceStore.add(evidence);
    return ActionRunnerResult(evidence: evidence, text: text, path: target);
  }

  Future<ActionRunnerResult> _previewHtml(ActionSchema schema, DateTime startedAt) async {
    final path = schema.params['path'];
    final html = schema.params['html'];
    late final String target;

    if (path is String && path.trim().isNotEmpty) {
      target = _resolveWorkspacePath(path);
      if (!await File(target).exists()) {
        throw _ActionRunnerFailure(
          'HTML file does not exist: ${_relative(target)}',
          failureKind: ActionFailureKind.processFailed,
          recoveryActions: const ['Create the HTML file before opening preview.'],
        );
      }
    } else if (html is String && html.trim().isNotEmpty) {
      target = _resolveWorkspacePath('.mobilecode_preview/index.html');
      final file = File(target);
      await file.parent.create(recursive: true);
      await file.writeAsString(html, flush: true);
    } else {
      throw const _ActionRunnerFailure(
        'previewHtml requires either params.path or params.html.',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: ['Provide an HTML file path or inline HTML content.'],
      );
    }

    final url = File(target).uri.toString();
    final evidence = ActionEvidence(
      evidenceId: schema.requestId ?? generateEvidenceId(),
      actionName: MobileCodeAction.previewHtml,
      paramsSummary: schema.paramsSummary.isEmpty ? 'preview ${_relative(target)}' : schema.paramsSummary,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      success: true,
      artifactPaths: [target],
      urls: [url],
      logs: ['Prepared HTML preview for ${_relative(target)}.'],
      metadata: {
        'relativePath': _relative(target),
        'previewUrl': url,
      },
    );
    evidenceStore.add(evidence);
    return ActionRunnerResult(evidence: evidence, path: target, url: url);
  }

  ActionRunnerResult _unsupported(ActionSchema schema, DateTime startedAt) {
    return _recordFailure(
      schema,
      startedAt,
      'ActionRunner does not support ${schema.actionName.name} yet.',
      failureKind: ActionFailureKind.commandBlocked,
      recoveryActions: const [
        'Use RuntimeManager or add this action to the structured runner before exposing it in UI.',
      ],
    );
  }

  ActionRunnerResult _recordFailure(
    ActionSchema schema,
    DateTime startedAt,
    String message, {
    required String failureKind,
    List<String> recoveryActions = const [],
  }) {
    final evidence = ActionEvidence.failed(
      evidenceId: schema.requestId ?? generateEvidenceId(),
      actionName: schema.actionName,
      paramsSummary: schema.paramsSummary,
      startedAt: startedAt,
      failureKind: failureKind,
      recoveryActions: recoveryActions,
      logs: [message],
    );
    evidenceStore.add(evidence);
    return ActionRunnerResult(evidence: evidence);
  }

  String _requiredString(ActionSchema schema, String key) {
    final value = schema.params[key];
    if (value is String && value.trim().isNotEmpty) return value;
    throw _ActionRunnerFailure(
      'Missing required string param: $key',
      failureKind: ActionFailureKind.commandBlocked,
      recoveryActions: ['Provide params.$key before running ${schema.actionName.name}.'],
    );
  }

  int _intParam(ActionSchema schema, String key, {required int defaultValue}) {
    final value = schema.params[key];
    if (value is int && value > 0) return value;
    if (value is num && value > 0) return value.toInt();
    return defaultValue;
  }

  String _resolveWorkspacePath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) {
      throw const _ActionRunnerFailure(
        'Path cannot be empty.',
        failureKind: ActionFailureKind.commandBlocked,
      );
    }

    final candidate = p.normalize(
      p.isAbsolute(trimmed) ? trimmed : p.join(workspaceRootPath, trimmed),
    );
    if (!(p.equals(candidate, workspaceRootPath) || p.isWithin(workspaceRootPath, candidate))) {
      throw _ActionRunnerFailure(
        'Path is outside workspace: $trimmed',
        failureKind: ActionFailureKind.cwdOutsideWorkspace,
        recoveryActions: const ['Choose a path inside the active MobileCode workspace.'],
      );
    }
    return candidate;
  }

  String _relative(String absolutePath) {
    if (p.equals(absolutePath, workspaceRootPath)) return '.';
    if (p.isWithin(workspaceRootPath, absolutePath)) {
      return p.relative(absolutePath, from: workspaceRootPath);
    }
    return absolutePath;
  }

  String _compact(String value, int limit) {
    final singleLine = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (singleLine.length <= limit) return singleLine;
    return '${singleLine.substring(0, limit - 1)}...';
  }
}
