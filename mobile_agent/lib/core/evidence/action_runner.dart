import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import 'action_evidence_store.dart';
import 'evidence_model.dart';

typedef ActionRunnerWebToolInvoker = Future<Map<String, dynamic>> Function(
  String toolName,
  Map<String, dynamic> payload,
);

typedef ActionRunnerTermuxTaskInvoker = Future<Map<String, dynamic>> Function(
  String taskKind,
  Map<String, dynamic> payload,
);

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

/// Minimal H06/H08 action runner.
///
/// This runner intentionally stays bounded: local file/preview actions plus
/// read-only relay web tools. It does not run shell commands and it rejects
/// paths outside [workspaceRootPath].
class ActionRunner {
  ActionRunner({
    required String workspaceRootPath,
    ActionEvidenceStore? evidenceStore,
    ActionRunnerWebToolInvoker? webToolInvoker,
    ActionRunnerTermuxTaskInvoker? termuxTaskInvoker,
  })  : workspaceRootPath = p.normalize(p.absolute(workspaceRootPath)),
        evidenceStore = evidenceStore ?? ActionEvidenceStore.shared,
        webToolInvoker = webToolInvoker,
        termuxTaskInvoker = termuxTaskInvoker;

  final String workspaceRootPath;
  final ActionEvidenceStore evidenceStore;
  final ActionRunnerWebToolInvoker? webToolInvoker;
  final ActionRunnerTermuxTaskInvoker? termuxTaskInvoker;

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
        MobileCodeAction.listFiles => await _listFiles(schema, startedAt),
        MobileCodeAction.findFiles => await _findFiles(schema, startedAt),
        MobileCodeAction.grepFiles => await _grepFiles(schema, startedAt),
        MobileCodeAction.writeFile => await _writeFile(schema, startedAt),
        MobileCodeAction.readFile => await _readFile(schema, startedAt),
        MobileCodeAction.copyFile => await _copyFile(schema, startedAt),
        MobileCodeAction.makeDirectory => await _makeDirectory(schema, startedAt),
        MobileCodeAction.deleteFile => await _deleteFile(schema, startedAt),
        MobileCodeAction.moveFile => await _moveFile(schema, startedAt),
        MobileCodeAction.saveSnapshot => await _saveSnapshot(schema, startedAt),
        MobileCodeAction.virtualDiff => await _virtualDiff(schema, startedAt),
        MobileCodeAction.restoreSnapshot => await _restoreSnapshot(schema, startedAt),
        MobileCodeAction.changeHistory => await _changeHistory(schema, startedAt),
        MobileCodeAction.virtualStatus => await _virtualStatus(schema, startedAt),
        MobileCodeAction.projectSummary => await _projectSummary(schema, startedAt),
        MobileCodeAction.detectProjectType => await _detectProjectType(schema, startedAt),
        MobileCodeAction.validateHtml => await _validateHtml(schema, startedAt),
        MobileCodeAction.validateJson => await _validateJson(schema, startedAt),
        MobileCodeAction.validateMarkdown => await _validateMarkdown(schema, startedAt),
        MobileCodeAction.applyPatch => await _applyPatch(schema, startedAt),
        MobileCodeAction.termuxTaskStart => await _termuxTaskStart(schema, startedAt),
        MobileCodeAction.previewHtml => await _previewHtml(schema, startedAt),
        MobileCodeAction.webSearch => await _webSearch(schema, startedAt),
        MobileCodeAction.fetchUrl => await _fetchUrl(schema, startedAt),
        MobileCodeAction.previewSnapshot => await _previewSnapshot(schema, startedAt),
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

  Future<ActionRunnerResult> _listFiles(ActionSchema schema, DateTime startedAt) async {
    final rawPath = _stringParam(schema, 'path').isEmpty ? '.' : _stringParam(schema, 'path');
    final target = _resolveWorkspacePath(rawPath);
    final recursive = schema.params['recursive'] == true;
    final maxEntries = _boundedIntParam(schema, 'maxEntries', defaultValue: 80, min: 1, max: 200);
    final targetType = await FileSystemEntity.type(target, followLinks: false);
    if (targetType == FileSystemEntityType.notFound) {
      throw _ActionRunnerFailure(
        'Path does not exist: ${_relative(target)}',
        failureKind: ActionFailureKind.processFailed,
        recoveryActions: const ['List "." first or create the folder before listing it.'],
      );
    }

    final entries = <Map<String, dynamic>>[];
    if (targetType == FileSystemEntityType.file) {
      final file = File(target);
      final stat = await file.stat();
      entries.add(_fileListEntry(target, stat, 'file'));
    } else if (targetType == FileSystemEntityType.directory) {
      await for (final entity in Directory(target).list(recursive: recursive, followLinks: false)) {
        if (entries.length >= maxEntries) break;
        final type = await FileSystemEntity.type(entity.path, followLinks: false);
        final stat = await entity.stat();
        entries.add(_fileListEntry(entity.path, stat, type == FileSystemEntityType.directory ? 'directory' : 'file'));
      }
    } else {
      throw _ActionRunnerFailure(
        'Unsupported file system entity: ${_relative(target)}',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: const ['Choose a regular file or directory inside the workspace.'],
      );
    }

    entries.sort((a, b) => _stringValue(a['path']).compareTo(_stringValue(b['path'])));
    final lines = entries.isEmpty
        ? ['${_relative(target)} is empty.']
        : entries.map((entry) => '${entry['type']}\t${entry['path']}\t${entry['sizeBytes']} bytes').toList();
    final evidence = ActionEvidence(
      evidenceId: schema.requestId ?? generateEvidenceId(),
      actionName: MobileCodeAction.listFiles,
      paramsSummary: schema.paramsSummary.isEmpty ? 'list ${_relative(target)}' : schema.paramsSummary,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      success: true,
      artifactPaths: [target],
      logs: [
        'Listed ${entries.length} item(s) under ${_relative(target)}${recursive ? ' recursively' : ''}.',
      ],
      metadata: {
        'relativePath': _relative(target),
        'recursive': recursive,
        'maxEntries': maxEntries,
        'entries': entries,
      },
    );
    evidenceStore.add(evidence);
    return ActionRunnerResult(evidence: evidence, text: lines.join('\n'), path: target);
  }

  Future<ActionRunnerResult> _findFiles(ActionSchema schema, DateTime startedAt) async {
    final rawPath = _stringParam(schema, 'path').isEmpty ? '.' : _stringParam(schema, 'path');
    final pattern = _requiredString(schema, 'pattern');
    final target = _resolveWorkspacePath(rawPath);
    final maxResults = _boundedIntParam(schema, 'maxResults', defaultValue: 80, min: 1, max: 200);
    final targetType = await FileSystemEntity.type(target, followLinks: false);
    if (targetType == FileSystemEntityType.notFound) {
      throw _ActionRunnerFailure(
        'Path does not exist: ${_relative(target)}',
        failureKind: ActionFailureKind.processFailed,
        recoveryActions: const ['List "." first or choose an existing workspace folder.'],
      );
    }

    final matcher = _globToRegExp(pattern);
    final results = <Map<String, dynamic>>[];
    Future<void> addEntity(FileSystemEntity entity) async {
      if (results.length >= maxResults) return;
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.notFound) return;
      final relativePath = _relative(entity.path);
      final name = p.basename(entity.path);
      if (!matcher.hasMatch(name) && !matcher.hasMatch(relativePath.replaceAll('\\', '/'))) return;
      final stat = await entity.stat();
      results.add(_fileListEntry(entity.path, stat, type == FileSystemEntityType.directory ? 'directory' : 'file'));
    }

    if (targetType == FileSystemEntityType.file) {
      await addEntity(File(target));
    } else if (targetType == FileSystemEntityType.directory) {
      await for (final entity in Directory(target).list(recursive: true, followLinks: false)) {
        await addEntity(entity);
        if (results.length >= maxResults) break;
      }
    } else {
      throw _ActionRunnerFailure(
        'Unsupported file system entity: ${_relative(target)}',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: const ['Choose a regular file or directory inside the workspace.'],
      );
    }

    results.sort((a, b) => _stringValue(a['path']).compareTo(_stringValue(b['path'])));
    final text = results.isEmpty
        ? 'No files matched "$pattern" under ${_relative(target)}.'
        : results.map((entry) => '${entry['type']}\t${entry['path']}\t${entry['sizeBytes']} bytes').join('\n');
    final evidence = ActionEvidence(
      evidenceId: schema.requestId ?? generateEvidenceId(),
      actionName: MobileCodeAction.findFiles,
      paramsSummary: schema.paramsSummary.isEmpty ? 'find "$pattern" under ${_relative(target)}' : schema.paramsSummary,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      success: true,
      artifactPaths: [target],
      logs: ['Found ${results.length} item(s) matching "$pattern" under ${_relative(target)}.'],
      metadata: {
        'pattern': pattern,
        'relativePath': _relative(target),
        'maxResults': maxResults,
        'results': results,
      },
    );
    evidenceStore.add(evidence);
    return ActionRunnerResult(evidence: evidence, text: text, path: target);
  }

  Future<ActionRunnerResult> _grepFiles(ActionSchema schema, DateTime startedAt) async {
    final query = _requiredString(schema, 'query');
    final rawPath = _stringParam(schema, 'path').isEmpty ? '.' : _stringParam(schema, 'path');
    final includeGlob = _stringParam(schema, 'includeGlob').isEmpty ? '*' : _stringParam(schema, 'includeGlob');
    final target = _resolveWorkspacePath(rawPath);
    final maxResults = _boundedIntParam(schema, 'maxResults', defaultValue: 40, min: 1, max: 120);
    final maxBytes = _boundedIntParam(schema, 'maxBytes', defaultValue: 256 * 1024, min: 1024, max: 512 * 1024);
    final targetType = await FileSystemEntity.type(target, followLinks: false);
    if (targetType == FileSystemEntityType.notFound) {
      throw _ActionRunnerFailure(
        'Path does not exist: ${_relative(target)}',
        failureKind: ActionFailureKind.processFailed,
        recoveryActions: const ['List "." first or choose an existing workspace folder.'],
      );
    }

    final includeMatcher = _globToRegExp(includeGlob);
    final results = <Map<String, dynamic>>[];
    Future<void> searchFile(File file) async {
      if (results.length >= maxResults) return;
      final relativePath = _relative(file.path);
      if (!includeMatcher.hasMatch(p.basename(file.path)) && !includeMatcher.hasMatch(relativePath.replaceAll('\\', '/'))) {
        return;
      }
      final stat = await file.stat();
      if (stat.size > maxBytes) return;
      final bytes = await file.readAsBytes();
      if (_looksBinary(bytes)) return;
      final text = utf8.decode(bytes, allowMalformed: true);
      final queryLower = query.toLowerCase();
      final lines = const LineSplitter().convert(text);
      for (var i = 0; i < lines.length && results.length < maxResults; i++) {
        final line = lines[i];
        if (!line.toLowerCase().contains(queryLower)) continue;
        results.add({
          'path': relativePath,
          'lineNumber': i + 1,
          'preview': _compact(line, 240),
        });
      }
    }

    if (targetType == FileSystemEntityType.file) {
      await searchFile(File(target));
    } else if (targetType == FileSystemEntityType.directory) {
      await for (final entity in Directory(target).list(recursive: true, followLinks: false)) {
        if (results.length >= maxResults) break;
        final type = await FileSystemEntity.type(entity.path, followLinks: false);
        if (type == FileSystemEntityType.file) await searchFile(File(entity.path));
      }
    } else {
      throw _ActionRunnerFailure(
        'Unsupported file system entity: ${_relative(target)}',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: const ['Choose a text file or directory inside the workspace.'],
      );
    }

    final text = results.isEmpty
        ? 'No matches for "$query" under ${_relative(target)}.'
        : results.map((item) => '${item['path']}:${item['lineNumber']}: ${item['preview']}').join('\n');
    final evidence = ActionEvidence(
      evidenceId: schema.requestId ?? generateEvidenceId(),
      actionName: MobileCodeAction.grepFiles,
      paramsSummary: schema.paramsSummary.isEmpty ? 'grep "$query" under ${_relative(target)}' : schema.paramsSummary,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      success: true,
      artifactPaths: [target],
      logs: ['Found ${results.length} text match(es) for "$query" under ${_relative(target)}.'],
      metadata: {
        'query': query,
        'relativePath': _relative(target),
        'includeGlob': includeGlob,
        'maxResults': maxResults,
        'maxBytes': maxBytes,
        'results': results,
      },
    );
    evidenceStore.add(evidence);
    return ActionRunnerResult(evidence: evidence, text: text, path: target);
  }

  Future<ActionRunnerResult> _writeFile(ActionSchema schema, DateTime startedAt) async {
    if (_stringParam(schema, 'path').isEmpty) {
      throw _ActionRunnerFailure(
        'Missing required string param: path for write_file.',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: const [
          'Provide a workspace-safe path (path/pathname/file_path/filename/name/fileName).',
          'If this is a small HTML artifact and context is unclear, use write_file with a complete HTML payload.',
        ],
      );
    }
    final target = _resolveWorkspacePath(_requiredString(schema, 'path'));
    final content = _requiredString(schema, 'content');
    final overwrite = schema.params['overwrite'] as bool? ?? true;
    final adapterRepair = _stringParam(schema, 'adapterRepair');
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
      logs: [
        'Wrote ${utf8.encode(content).length} bytes to ${_relative(target)}.',
        if (adapterRepair.isNotEmpty) 'Adapter repaired tool arguments: $adapterRepair.',
      ],
      metadata: {
        'relativePath': _relative(target),
        'byteLength': utf8.encode(content).length,
        if (adapterRepair.isNotEmpty) 'adapterRepair': adapterRepair,
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

  Future<ActionRunnerResult> _copyFile(ActionSchema schema, DateTime startedAt) async {
    final source = _resolveWorkspacePath(_requiredString(schema, 'sourcePath'));
    final destination = _resolveWorkspacePath(_requiredString(schema, 'destinationPath'));
    final overwrite = schema.params['overwrite'] as bool? ?? false;
    final sourceType = await FileSystemEntity.type(source, followLinks: false);
    if (sourceType == FileSystemEntityType.notFound) {
      throw _ActionRunnerFailure(
        'Source file does not exist: ${_relative(source)}',
        failureKind: ActionFailureKind.processFailed,
        recoveryActions: const ['Call list_files or provide an existing source path before copying.'],
      );
    }
    if (sourceType != FileSystemEntityType.file) {
      throw _ActionRunnerFailure(
        'copy_file currently supports files only: ${_relative(source)}',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: const ['Copy a regular file, not a directory.'],
      );
    }
    final destinationType = await FileSystemEntity.type(destination, followLinks: false);
    if (destinationType == FileSystemEntityType.directory) {
      throw _ActionRunnerFailure(
        'Destination is a directory; provide the full destination file path: ${_relative(destination)}',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: const ['Include the target filename in destination_path.'],
      );
    }
    if (destinationType != FileSystemEntityType.notFound) {
      if (!overwrite) {
        throw _ActionRunnerFailure(
          'Destination already exists and overwrite=false: ${_relative(destination)}',
          failureKind: ActionFailureKind.commandBlocked,
          recoveryActions: const ['Set overwrite=true or choose a different destination path.'],
        );
      }
      await File(destination).delete();
    }
    await File(destination).parent.create(recursive: true);
    await File(source).copy(destination);

    final evidence = ActionEvidence(
      evidenceId: schema.requestId ?? generateEvidenceId(),
      actionName: MobileCodeAction.copyFile,
      paramsSummary: schema.paramsSummary.isEmpty ? 'copy ${_relative(source)} to ${_relative(destination)}' : schema.paramsSummary,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      success: true,
      artifactPaths: [source, destination],
      logs: ['Copied ${_relative(source)} to ${_relative(destination)}.'],
      metadata: {
        'sourcePath': _relative(source),
        'destinationPath': _relative(destination),
        'overwrite': overwrite,
      },
    );
    evidenceStore.add(evidence);
    return ActionRunnerResult(evidence: evidence, path: destination);
  }

  Future<ActionRunnerResult> _makeDirectory(ActionSchema schema, DateTime startedAt) async {
    final target = _resolveWorkspacePath(_requiredString(schema, 'path'));
    final recursive = schema.params['recursive'] as bool? ?? true;
    final targetType = await FileSystemEntity.type(target, followLinks: false);
    if (targetType == FileSystemEntityType.file) {
      throw _ActionRunnerFailure(
        'Cannot create directory over an existing file: ${_relative(target)}',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: const ['Choose a directory path that does not point at an existing file.'],
      );
    }
    await Directory(target).create(recursive: recursive);
    final evidence = ActionEvidence(
      evidenceId: schema.requestId ?? generateEvidenceId(),
      actionName: MobileCodeAction.makeDirectory,
      paramsSummary: schema.paramsSummary.isEmpty ? 'mkdir ${_relative(target)}' : schema.paramsSummary,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      success: true,
      artifactPaths: [target],
      logs: ['Created directory ${_relative(target)}${recursive ? ' recursively' : ''}.'],
      metadata: {
        'relativePath': _relative(target),
        'recursive': recursive,
      },
    );
    evidenceStore.add(evidence);
    return ActionRunnerResult(evidence: evidence, path: target);
  }

  Future<ActionRunnerResult> _deleteFile(ActionSchema schema, DateTime startedAt) async {
    final target = _resolveWorkspacePath(_requiredString(schema, 'path'));
    final confirm = schema.params['confirm'] == true;
    if (!confirm) {
      throw const _ActionRunnerFailure(
        'delete_file requires confirm=true because deletion is destructive.',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: ['Set confirm=true only when the user explicitly asked to delete a workspace file.'],
      );
    }
    final relativePath = _relative(target);
    if (relativePath.startsWith('.mobilecode_')) {
      throw _ActionRunnerFailure(
        'delete_file cannot remove MobileCode metadata or recovery artifacts: $relativePath',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: const ['Choose a regular user workspace file.'],
      );
    }
    final targetType = await FileSystemEntity.type(target, followLinks: false);
    if (targetType == FileSystemEntityType.notFound) {
      throw _ActionRunnerFailure(
        'File does not exist: $relativePath',
        failureKind: ActionFailureKind.processFailed,
        recoveryActions: const ['Call list_files or find_files before deleting.'],
      );
    }
    if (targetType != FileSystemEntityType.file) {
      throw _ActionRunnerFailure(
        'delete_file currently supports files only: $relativePath',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: const ['Delete a regular file, not a directory.'],
      );
    }

    final snapshotRoot = _resolveWorkspacePath(
      '.mobilecode_delete_snapshots/delete_${DateTime.now().millisecondsSinceEpoch}',
    );
    final snapshotPath = p.join(snapshotRoot, relativePath);
    final snapshotFile = File(snapshotPath);
    await snapshotFile.parent.create(recursive: true);
    await File(target).copy(snapshotPath);
    await File(target).delete();

    final evidence = ActionEvidence(
      evidenceId: schema.requestId ?? generateEvidenceId(),
      actionName: MobileCodeAction.deleteFile,
      paramsSummary: schema.paramsSummary.isEmpty ? 'delete $relativePath' : schema.paramsSummary,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      success: true,
      artifactPaths: [snapshotPath],
      logs: [
        'Deleted $relativePath.',
        'Saved pre-delete snapshot at ${_relative(snapshotPath)}.',
      ],
      metadata: {
        'deletedPath': relativePath,
        'snapshotPath': _relative(snapshotPath),
        'confirm': confirm,
      },
    );
    evidenceStore.add(evidence);
    return ActionRunnerResult(evidence: evidence, path: snapshotPath);
  }

  Future<ActionRunnerResult> _moveFile(ActionSchema schema, DateTime startedAt) async {
    final source = _resolveWorkspacePath(_requiredString(schema, 'sourcePath'));
    final destination = _resolveWorkspacePath(_requiredString(schema, 'destinationPath'));
    final overwrite = schema.params['overwrite'] as bool? ?? false;
    final sourceType = await FileSystemEntity.type(source, followLinks: false);
    if (sourceType == FileSystemEntityType.notFound) {
      throw _ActionRunnerFailure(
        'Source file does not exist: ${_relative(source)}',
        failureKind: ActionFailureKind.processFailed,
        recoveryActions: const ['Call list_files or provide an existing source path before moving.'],
      );
    }
    if (sourceType != FileSystemEntityType.file) {
      throw _ActionRunnerFailure(
        'move_file currently supports files only: ${_relative(source)}',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: const ['Move a regular file, not a directory.'],
      );
    }
    if (p.equals(source, destination)) {
      throw _ActionRunnerFailure(
        'Source and destination are the same file: ${_relative(source)}',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: const ['Choose a different destination path.'],
      );
    }
    final destinationType = await FileSystemEntity.type(destination, followLinks: false);
    if (destinationType == FileSystemEntityType.directory) {
      throw _ActionRunnerFailure(
        'Destination is a directory; provide the full destination file path: ${_relative(destination)}',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: const ['Include the target filename in destination_path.'],
      );
    }
    if (destinationType != FileSystemEntityType.notFound) {
      if (!overwrite) {
        throw _ActionRunnerFailure(
          'Destination already exists and overwrite=false: ${_relative(destination)}',
          failureKind: ActionFailureKind.commandBlocked,
          recoveryActions: const ['Set overwrite=true or choose a different destination path.'],
        );
      }
      await File(destination).delete();
    }
    await File(destination).parent.create(recursive: true);
    await File(source).rename(destination);

    final evidence = ActionEvidence(
      evidenceId: schema.requestId ?? generateEvidenceId(),
      actionName: MobileCodeAction.moveFile,
      paramsSummary: schema.paramsSummary.isEmpty ? 'move ${_relative(source)} to ${_relative(destination)}' : schema.paramsSummary,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      success: true,
      artifactPaths: [destination],
      logs: ['Moved ${_relative(source)} to ${_relative(destination)}.'],
      metadata: {
        'sourcePath': _relative(source),
        'destinationPath': _relative(destination),
        'overwrite': overwrite,
      },
    );
    evidenceStore.add(evidence);
    return ActionRunnerResult(evidence: evidence, path: destination);
  }

  Future<ActionRunnerResult> _saveSnapshot(ActionSchema schema, DateTime startedAt) async {
    final rawPath = _stringParam(schema, 'path').isEmpty ? '.' : _stringParam(schema, 'path');
    final target = _resolveWorkspacePath(rawPath);
    final label = _stringParam(schema, 'label');
    final maxFiles = _boundedIntParam(schema, 'maxFiles', defaultValue: 80, min: 1, max: 200);
    final maxBytes = _boundedIntParam(schema, 'maxBytes', defaultValue: 1024 * 1024, min: 1024, max: 5 * 1024 * 1024);
    final targetType = await FileSystemEntity.type(target, followLinks: false);
    if (targetType == FileSystemEntityType.notFound) {
      throw _ActionRunnerFailure(
        'Snapshot source does not exist: ${_relative(target)}',
        failureKind: ActionFailureKind.processFailed,
        recoveryActions: const ['Call list_files before saving a snapshot.'],
      );
    }
    final snapshotId = 'snapshot_${DateTime.now().millisecondsSinceEpoch}';
    final snapshotRoot = _resolveWorkspacePath('.mobilecode_snapshots/$snapshotId');
    final copiedFiles = <Map<String, dynamic>>[];
    var totalBytes = 0;

    Future<void> copyFile(File file) async {
      if (copiedFiles.length >= maxFiles) return;
      final relativePath = _relative(file.path);
      if (relativePath.startsWith('.mobilecode_snapshots${Platform.pathSeparator}') || relativePath == '.mobilecode_snapshots') {
        return;
      }
      if (relativePath.startsWith('.mobilecode_')) return;
      final stat = await file.stat();
      if (totalBytes + stat.size > maxBytes) return;
      final destination = p.join(snapshotRoot, relativePath);
      await File(destination).parent.create(recursive: true);
      await file.copy(destination);
      totalBytes += stat.size;
      copiedFiles.add({
        'path': relativePath,
        'sizeBytes': stat.size,
      });
    }

    if (targetType == FileSystemEntityType.file) {
      await copyFile(File(target));
    } else if (targetType == FileSystemEntityType.directory) {
      await for (final entity in Directory(target).list(recursive: true, followLinks: false)) {
        if (copiedFiles.length >= maxFiles || totalBytes >= maxBytes) break;
        final type = await FileSystemEntity.type(entity.path, followLinks: false);
        if (type == FileSystemEntityType.file) await copyFile(File(entity.path));
      }
    } else {
      throw _ActionRunnerFailure(
        'Unsupported snapshot source: ${_relative(target)}',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: const ['Choose a regular file or directory inside the workspace.'],
      );
    }

    final manifest = {
      'snapshotId': snapshotId,
      'label': label,
      'sourcePath': _relative(target),
      'createdAt': DateTime.now().toIso8601String(),
      'fileCount': copiedFiles.length,
      'totalBytes': totalBytes,
      'files': copiedFiles,
    };
    final manifestPath = p.join(snapshotRoot, 'manifest.json');
    final manifestFile = File(manifestPath);
    await manifestFile.parent.create(recursive: true);
    await manifestFile.writeAsString(const JsonEncoder.withIndent('  ').convert(manifest), flush: true);

    final evidence = ActionEvidence(
      evidenceId: schema.requestId ?? generateEvidenceId(),
      actionName: MobileCodeAction.saveSnapshot,
      paramsSummary: schema.paramsSummary.isEmpty ? 'save snapshot of ${_relative(target)}' : schema.paramsSummary,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      success: true,
      artifactPaths: [snapshotRoot, manifestPath],
      logs: [
        'Saved snapshot $snapshotId for ${_relative(target)} with ${copiedFiles.length} file(s), $totalBytes bytes.',
      ],
      metadata: manifest,
    );
    evidenceStore.add(evidence);
    return ActionRunnerResult(evidence: evidence, text: jsonEncode(manifest), path: snapshotRoot);
  }

  Future<ActionRunnerResult> _virtualDiff(ActionSchema schema, DateTime startedAt) async {
    final rawPath = _stringParam(schema, 'path').isEmpty ? '.' : _stringParam(schema, 'path');
    final snapshotId = _stringParam(schema, 'snapshotId');
    final snapshotPathParam = _stringParam(schema, 'snapshotPath');
    if (snapshotId.isEmpty && snapshotPathParam.isEmpty) {
      throw const _ActionRunnerFailure(
        'virtual_diff requires snapshot_id or snapshot_path.',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: ['Call save_snapshot first, then pass the returned snapshot_id to virtual_diff.'],
      );
    }
    if (snapshotId.isNotEmpty && !RegExp(r'^snapshot_\d+$').hasMatch(snapshotId)) {
      throw const _ActionRunnerFailure(
        'Invalid snapshot_id format for virtual_diff.',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: ['Use the snapshot_id returned by save_snapshot, for example snapshot_1234567890.'],
      );
    }
    final target = _resolveWorkspacePath(rawPath);
    final snapshotRoot = snapshotPathParam.isNotEmpty
        ? _resolveWorkspacePath(snapshotPathParam)
        : _resolveWorkspacePath('.mobilecode_snapshots/$snapshotId');
    final maxBytes = _boundedIntParam(schema, 'maxBytes', defaultValue: 256 * 1024, min: 1024, max: 1024 * 1024);
    if (!await Directory(snapshotRoot).exists()) {
      throw _ActionRunnerFailure(
        'Snapshot root does not exist: ${_relative(snapshotRoot)}',
        failureKind: ActionFailureKind.processFailed,
        recoveryActions: const ['Call save_snapshot and use the returned snapshot_id.'],
      );
    }

    final targetType = await FileSystemEntity.type(target, followLinks: false);
    final diffLines = <String>[];
    final changedFiles = <String>[];
    var inspectedBytes = 0;

    Future<void> diffFile(String currentPath) async {
      if (inspectedBytes >= maxBytes) return;
      final relativePath = _relative(currentPath);
      final snapshotFile = File(p.join(snapshotRoot, relativePath));
      final currentFile = File(currentPath);
      final currentExists = await currentFile.exists();
      final snapshotExists = await snapshotFile.exists();
      if (!currentExists && !snapshotExists) return;
      final currentBytes = currentExists ? await currentFile.readAsBytes() : <int>[];
      final snapshotBytes = snapshotExists ? await snapshotFile.readAsBytes() : <int>[];
      if (_looksBinary(currentBytes) || _looksBinary(snapshotBytes)) return;
      inspectedBytes += currentBytes.length + snapshotBytes.length;
      if (currentBytes.length + snapshotBytes.length > maxBytes) return;
      final currentText = utf8.decode(currentBytes, allowMalformed: true);
      final snapshotText = utf8.decode(snapshotBytes, allowMalformed: true);
      if (currentText == snapshotText) return;
      changedFiles.add(relativePath);
      diffLines.addAll(_lineDiff(relativePath, snapshotText, currentText, maxLines: 120));
    }

    if (targetType == FileSystemEntityType.file || targetType == FileSystemEntityType.notFound) {
      await diffFile(target);
    } else if (targetType == FileSystemEntityType.directory) {
      final paths = <String>{};
      await for (final entity in Directory(target).list(recursive: true, followLinks: false)) {
        if (paths.length >= 80) break;
        final type = await FileSystemEntity.type(entity.path, followLinks: false);
        if (type == FileSystemEntityType.file && !_relative(entity.path).startsWith('.mobilecode_')) {
          paths.add(entity.path);
        }
      }
      final snapshotTarget = Directory(p.join(snapshotRoot, _relative(target)));
      if (await snapshotTarget.exists()) {
        await for (final entity in snapshotTarget.list(recursive: true, followLinks: false)) {
          if (paths.length >= 120) break;
          final type = await FileSystemEntity.type(entity.path, followLinks: false);
          if (type == FileSystemEntityType.file) {
            final relativeToSnapshot = p.relative(entity.path, from: snapshotRoot);
            if (relativeToSnapshot == 'manifest.json' || relativeToSnapshot.startsWith('.mobilecode_')) {
              continue;
            }
            paths.add(_resolveWorkspacePath(relativeToSnapshot));
          }
        }
      }
      for (final path in paths.toList()..sort()) {
        await diffFile(path);
        if (diffLines.length > 300) break;
      }
    } else {
      throw _ActionRunnerFailure(
        'Unsupported diff target: ${_relative(target)}',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: const ['Choose a regular file or directory inside the workspace.'],
      );
    }

    final text = diffLines.isEmpty
        ? 'No virtual diff changes for ${_relative(target)}.'
        : diffLines.join('\n');
    final evidence = ActionEvidence(
      evidenceId: schema.requestId ?? generateEvidenceId(),
      actionName: MobileCodeAction.virtualDiff,
      paramsSummary: schema.paramsSummary.isEmpty ? 'virtual diff ${_relative(target)}' : schema.paramsSummary,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      success: true,
      artifactPaths: [snapshotRoot, target],
      logs: ['Virtual diff found ${changedFiles.length} changed file(s) for ${_relative(target)}.'],
      metadata: {
        if (snapshotId.isNotEmpty) 'snapshotId': snapshotId,
        'snapshotRoot': _relative(snapshotRoot),
        'targetPath': _relative(target),
        'changedFiles': changedFiles,
        'inspectedBytes': inspectedBytes,
      },
    );
    evidenceStore.add(evidence);
    return ActionRunnerResult(evidence: evidence, text: text, path: target);
  }

  Future<ActionRunnerResult> _restoreSnapshot(ActionSchema schema, DateTime startedAt) async {
    final confirm = schema.params['confirm'] == true;
    if (!confirm) {
      throw const _ActionRunnerFailure(
        'restore_snapshot requires confirm=true because it overwrites workspace files.',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: ['Set confirm=true only after the user asks to restore a MobileCode snapshot.'],
      );
    }
    final rawPath = _stringParam(schema, 'path').isEmpty ? '.' : _stringParam(schema, 'path');
    final target = _resolveWorkspacePath(rawPath);
    final snapshotId = _stringParam(schema, 'snapshotId');
    final snapshotPathParam = _stringParam(schema, 'snapshotPath');
    if (snapshotId.isEmpty && snapshotPathParam.isEmpty) {
      throw const _ActionRunnerFailure(
        'restore_snapshot requires snapshot_id or snapshot_path.',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: ['Call save_snapshot first, then pass the returned snapshot_id to restore_snapshot.'],
      );
    }
    if (snapshotId.isNotEmpty && !RegExp(r'^snapshot_\d+$').hasMatch(snapshotId)) {
      throw const _ActionRunnerFailure(
        'Invalid snapshot_id format for restore_snapshot.',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: ['Use the snapshot_id returned by save_snapshot, for example snapshot_1234567890.'],
      );
    }
    final snapshotRoot = snapshotPathParam.isNotEmpty
        ? _resolveWorkspacePath(snapshotPathParam)
        : _resolveWorkspacePath('.mobilecode_snapshots/$snapshotId');
    if (!await Directory(snapshotRoot).exists()) {
      throw _ActionRunnerFailure(
        'Snapshot root does not exist: ${_relative(snapshotRoot)}',
        failureKind: ActionFailureKind.processFailed,
        recoveryActions: const ['Call save_snapshot and use the returned snapshot_id.'],
      );
    }
    final maxFiles = _boundedIntParam(schema, 'maxFiles', defaultValue: 40, min: 1, max: 120);
    final maxBytes = _boundedIntParam(schema, 'maxBytes', defaultValue: 1024 * 1024, min: 1024, max: 5 * 1024 * 1024);
    final targetRelative = _relative(target);
    final source = targetRelative == '.' ? snapshotRoot : p.join(snapshotRoot, targetRelative);
    final sourceType = await FileSystemEntity.type(source, followLinks: false);
    if (sourceType == FileSystemEntityType.notFound) {
      throw _ActionRunnerFailure(
        'Snapshot does not contain ${targetRelative == '.' ? 'workspace root' : targetRelative}.',
        failureKind: ActionFailureKind.processFailed,
        recoveryActions: const ['Run virtual_diff or project_summary against the snapshot before restoring.'],
      );
    }

    final restoredFiles = <Map<String, dynamic>>[];
    final backupFiles = <Map<String, dynamic>>[];
    var totalBytes = 0;
    final backupRoot = _resolveWorkspacePath(
      '.mobilecode_restore_snapshots/restore_${DateTime.now().millisecondsSinceEpoch}',
    );

    Future<void> restoreFile(File snapshotFile) async {
      if (restoredFiles.length >= maxFiles) return;
      final relativeToSnapshot = p.relative(snapshotFile.path, from: snapshotRoot);
      if (relativeToSnapshot == 'manifest.json' || relativeToSnapshot.startsWith('.mobilecode_')) {
        return;
      }
      final stat = await snapshotFile.stat();
      if (totalBytes + stat.size > maxBytes) return;
      final destination = _resolveWorkspacePath(relativeToSnapshot);
      final existingType = await FileSystemEntity.type(destination, followLinks: false);
      if (existingType == FileSystemEntityType.directory) {
        throw _ActionRunnerFailure(
          'Cannot restore file over existing directory: ${_relative(destination)}',
          failureKind: ActionFailureKind.commandBlocked,
          recoveryActions: const ['Choose a file path restore target, not a directory with the same name.'],
        );
      }
      if (existingType == FileSystemEntityType.file) {
        final backupPath = p.join(backupRoot, relativeToSnapshot);
        await File(backupPath).parent.create(recursive: true);
        await File(destination).copy(backupPath);
        backupFiles.add({'path': _relative(backupPath), 'sizeBytes': await File(backupPath).length()});
      }
      await File(destination).parent.create(recursive: true);
      await snapshotFile.copy(destination);
      totalBytes += stat.size;
      restoredFiles.add({'path': _relative(destination), 'sizeBytes': stat.size});
    }

    if (sourceType == FileSystemEntityType.file) {
      await restoreFile(File(source));
    } else if (sourceType == FileSystemEntityType.directory) {
      await for (final entity in Directory(source).list(recursive: true, followLinks: false)) {
        if (restoredFiles.length >= maxFiles || totalBytes >= maxBytes) break;
        final type = await FileSystemEntity.type(entity.path, followLinks: false);
        if (type == FileSystemEntityType.file) await restoreFile(File(entity.path));
      }
    } else {
      throw _ActionRunnerFailure(
        'Unsupported snapshot restore source: ${_relative(source)}',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: const ['Restore regular files or directories saved by save_snapshot.'],
      );
    }
    if (restoredFiles.isEmpty) {
      throw _ActionRunnerFailure(
        'No files were restored from ${_relative(snapshotRoot)} within the current limits.',
        failureKind: ActionFailureKind.processFailed,
        recoveryActions: const ['Increase max_files/max_bytes or choose a narrower snapshot path.'],
      );
    }

    final text = [
      'Restored ${restoredFiles.length} file(s) from ${snapshotId.isEmpty ? _relative(snapshotRoot) : snapshotId}:',
      ...restoredFiles.map((file) => '- ${file['path']} (${file['sizeBytes']} bytes)'),
      if (backupFiles.isNotEmpty) 'Previous versions backed up under ${_relative(backupRoot)}.',
    ].join('\n');
    final evidence = ActionEvidence(
      evidenceId: schema.requestId ?? generateEvidenceId(),
      actionName: MobileCodeAction.restoreSnapshot,
      paramsSummary: schema.paramsSummary.isEmpty ? 'restore snapshot to $targetRelative' : schema.paramsSummary,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      success: true,
      artifactPaths: [
        snapshotRoot,
        target,
        if (backupFiles.isNotEmpty) backupRoot,
      ],
      logs: [
        'Restored ${restoredFiles.length} file(s) from ${_relative(snapshotRoot)} to workspace path $targetRelative.',
        if (backupFiles.isNotEmpty) 'Backed up ${backupFiles.length} previous file(s) under ${_relative(backupRoot)}.',
      ],
      metadata: {
        if (snapshotId.isNotEmpty) 'snapshotId': snapshotId,
        'snapshotRoot': _relative(snapshotRoot),
        'targetPath': targetRelative,
        'restoredFiles': restoredFiles,
        'backupFiles': backupFiles,
        'totalBytes': totalBytes,
        'confirm': confirm,
      },
    );
    evidenceStore.add(evidence);
    return ActionRunnerResult(evidence: evidence, text: text, path: target);
  }

  Future<ActionRunnerResult> _changeHistory(ActionSchema schema, DateTime startedAt) async {
    final count = _boundedIntParam(schema, 'count', defaultValue: 20, min: 1, max: 80);
    final includeReadOnly = schema.params['includeReadOnly'] == true;
    final actionFilter = _stringParam(schema, 'actionFilter');
    final records = evidenceStore.recent(count: math.min(count * 4, 240).toInt());
    final interestingActions = <MobileCodeAction>{
      MobileCodeAction.writeFile,
      MobileCodeAction.copyFile,
      MobileCodeAction.makeDirectory,
      MobileCodeAction.deleteFile,
      MobileCodeAction.moveFile,
      MobileCodeAction.saveSnapshot,
      MobileCodeAction.virtualDiff,
      MobileCodeAction.restoreSnapshot,
      MobileCodeAction.applyPatch,
      MobileCodeAction.previewHtml,
      MobileCodeAction.previewSnapshot,
      MobileCodeAction.termuxTaskStart,
    };
    final filtered = records.where((record) {
      if (record.actionName == MobileCodeAction.changeHistory) return false;
      if (actionFilter.isNotEmpty && record.actionName.name != actionFilter) return false;
      if (!record.success) return true;
      if (includeReadOnly) return true;
      return interestingActions.contains(record.actionName);
    }).take(count).toList();

    final entries = filtered.map((record) {
      final artifacts = record.artifactPaths.map(_relative).take(4).toList();
      final urls = record.urls.take(3).toList();
      return {
        'evidenceId': record.evidenceId,
        'actionName': record.actionName.name,
        'success': record.success,
        if (record.failureKind != null) 'failureKind': record.failureKind,
        'startedAt': record.startedAt.toIso8601String(),
        'durationMs': record.durationMs,
        'artifactPaths': artifacts,
        'urls': urls,
        'summary': _compact(record.paramsSummary.isEmpty ? record.logs.join(' ') : record.paramsSummary, 180),
      };
    }).toList();
    final text = entries.isEmpty
        ? 'No recent MobileCode action history matched the current filters.'
        : [
            'Recent MobileCode action history (${entries.length}):',
            ...entries.map((entry) {
              final status = entry['success'] == true ? 'ok' : 'failed';
              final artifacts = (entry['artifactPaths'] as List).isEmpty ? '' : ' paths=${(entry['artifactPaths'] as List).join(', ')}';
              final failure = entry['failureKind'] == null ? '' : ' failure=${entry['failureKind']}';
              return '- ${entry['startedAt']} ${entry['actionName']} $status${failure} evidence=${entry['evidenceId']}$artifacts';
            }),
          ].join('\n');
    final evidence = ActionEvidence(
      evidenceId: schema.requestId ?? generateEvidenceId(),
      actionName: MobileCodeAction.changeHistory,
      paramsSummary: schema.paramsSummary.isEmpty ? 'change history count=$count' : schema.paramsSummary,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      success: true,
      logs: ['Returned ${entries.length} history record(s).'],
      metadata: {
        'count': count,
        'includeReadOnly': includeReadOnly,
        if (actionFilter.isNotEmpty) 'actionFilter': actionFilter,
        'records': entries,
      },
    );
    evidenceStore.add(evidence);
    return ActionRunnerResult(evidence: evidence, text: text);
  }

  Future<ActionRunnerResult> _virtualStatus(ActionSchema schema, DateTime startedAt) async {
    final rawPath = _stringParam(schema, 'path').isEmpty ? '.' : _stringParam(schema, 'path');
    final target = _resolveWorkspacePath(rawPath);
    final maxFiles = _boundedIntParam(schema, 'maxFiles', defaultValue: 80, min: 10, max: 240);
    final maxRecent = _boundedIntParam(schema, 'maxRecent', defaultValue: 12, min: 1, max: 40);
    final targetType = await FileSystemEntity.type(target, followLinks: false);
    if (targetType == FileSystemEntityType.notFound) {
      throw _ActionRunnerFailure(
        'virtual_status path does not exist: ${_relative(target)}',
        failureKind: ActionFailureKind.processFailed,
        recoveryActions: const ['Call list_files first or choose an existing workspace path.'],
      );
    }

    final files = <Map<String, dynamic>>[];
    final extensionCounts = <String, int>{};
    var directoryCount = 0;
    var totalBytes = 0;
    var truncated = false;

    bool shouldSkip(String relativePath) {
      final normalized = relativePath.replaceAll('\\', '/');
      return normalized == '.mobilecode_snapshots' ||
          normalized.startsWith('.mobilecode_') ||
          normalized.contains('/.mobilecode_');
    }

    Future<void> addFile(File file) async {
      if (files.length >= maxFiles) {
        truncated = true;
        return;
      }
      final relativePath = _relative(file.path);
      if (shouldSkip(relativePath)) return;
      final stat = await file.stat();
      final ext = p.extension(file.path).toLowerCase();
      extensionCounts[ext.isEmpty ? '(none)' : ext] = (extensionCounts[ext.isEmpty ? '(none)' : ext] ?? 0) + 1;
      totalBytes += stat.size;
      files.add({
        'path': relativePath,
        'sizeBytes': stat.size,
        'modifiedAt': stat.modified.toIso8601String(),
      });
    }

    if (targetType == FileSystemEntityType.file) {
      await addFile(File(target));
    } else if (targetType == FileSystemEntityType.directory) {
      await for (final entity in Directory(target).list(recursive: true, followLinks: false)) {
        if (files.length >= maxFiles) {
          truncated = true;
          break;
        }
        final relativePath = _relative(entity.path);
        if (shouldSkip(relativePath)) continue;
        final type = await FileSystemEntity.type(entity.path, followLinks: false);
        if (type == FileSystemEntityType.directory) {
          directoryCount++;
        } else if (type == FileSystemEntityType.file) {
          await addFile(File(entity.path));
        }
      }
    } else {
      throw _ActionRunnerFailure(
        'Unsupported virtual_status target: ${_relative(target)}',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: const ['Choose a regular file or directory inside the workspace.'],
      );
    }

    final recent = evidenceStore.recent(count: maxRecent);
    final snapshots = recent
        .where((record) => record.actionName == MobileCodeAction.saveSnapshot)
        .map((record) => {
              'evidenceId': record.evidenceId,
              'snapshotId': record.metadata['snapshotId'],
              'label': record.metadata['label'],
              'sourcePath': record.metadata['sourcePath'],
              'createdAt': record.startedAt.toIso8601String(),
            })
        .take(6)
        .toList();
    final recentChanges = recent
        .where((record) =>
            record.actionName == MobileCodeAction.writeFile ||
            record.actionName == MobileCodeAction.applyPatch ||
            record.actionName == MobileCodeAction.copyFile ||
            record.actionName == MobileCodeAction.makeDirectory ||
            record.actionName == MobileCodeAction.deleteFile ||
            record.actionName == MobileCodeAction.moveFile ||
            record.actionName == MobileCodeAction.restoreSnapshot ||
            !record.success)
        .map((record) => {
              'evidenceId': record.evidenceId,
              'actionName': record.actionName.name,
              'success': record.success,
              if (record.failureKind != null) 'failureKind': record.failureKind,
              'startedAt': record.startedAt.toIso8601String(),
              'artifactPaths': record.artifactPaths.map(_relative).take(4).toList(),
            })
        .take(maxRecent)
        .toList();

    final extensionSummary = extensionCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final text = [
      'Virtual status for ${_relative(target)}',
      'Files: ${files.length}${truncated ? '+' : ''}, directories: $directoryCount, bytes: $totalBytes',
      if (extensionSummary.isNotEmpty) 'Extensions: ${extensionSummary.take(8).map((entry) => '${entry.key}:${entry.value}').join(', ')}',
      if (snapshots.isNotEmpty) 'Restore points: ${snapshots.map((entry) => entry['snapshotId']).join(', ')}',
      if (recentChanges.isNotEmpty)
        'Recent changes:\n${recentChanges.map((entry) => '- ${entry['actionName']} ${entry['success'] == true ? 'ok' : 'failed'} evidence=${entry['evidenceId']}').join('\n')}',
      if (files.isNotEmpty) 'Files:\n${files.take(20).map((file) => '- ${file['path']} (${file['sizeBytes']} bytes)').join('\n')}',
      if (truncated) 'Status truncated by max_files limit.',
    ].join('\n');
    final evidence = ActionEvidence(
      evidenceId: schema.requestId ?? generateEvidenceId(),
      actionName: MobileCodeAction.virtualStatus,
      paramsSummary: schema.paramsSummary.isEmpty ? 'virtual status ${_relative(target)}' : schema.paramsSummary,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      success: true,
      artifactPaths: [target],
      logs: ['Computed virtual status for ${_relative(target)} with ${files.length} file(s).'],
      metadata: {
        'relativePath': _relative(target),
        'fileCount': files.length,
        'directoryCount': directoryCount,
        'totalBytes': totalBytes,
        'truncated': truncated,
        'extensionCounts': extensionCounts,
        'files': files.take(80).toList(),
        'recentChanges': recentChanges,
        'restorePoints': snapshots,
      },
    );
    evidenceStore.add(evidence);
    return ActionRunnerResult(evidence: evidence, text: text, path: target);
  }

  Future<ActionRunnerResult> _projectSummary(ActionSchema schema, DateTime startedAt) async {
    final rawPath = _stringParam(schema, 'path').isEmpty ? '.' : _stringParam(schema, 'path');
    final target = _resolveWorkspacePath(rawPath);
    final maxDepth = _boundedIntParam(schema, 'maxDepth', defaultValue: 3, min: 1, max: 6);
    final maxFiles = _boundedIntParam(schema, 'maxFiles', defaultValue: 80, min: 10, max: 240);
    final targetType = await FileSystemEntity.type(target, followLinks: false);
    if (targetType == FileSystemEntityType.notFound) {
      throw _ActionRunnerFailure(
        'Project summary path does not exist: ${_relative(target)}',
        failureKind: ActionFailureKind.processFailed,
        recoveryActions: const ['Call list_files first or choose an existing workspace path.'],
      );
    }

    final files = <Map<String, dynamic>>[];
    final directories = <String>[];
    final extensionCounts = <String, int>{};
    final entrypoints = <String>[];
    var totalBytes = 0;
    var truncated = false;

    bool shouldSkip(String relativePath) {
      final normalized = relativePath.replaceAll('\\', '/');
      return normalized == '.mobilecode_snapshots' ||
          normalized.startsWith('.mobilecode_') ||
          normalized.contains('/.mobilecode_');
    }

    Future<void> addFile(File file) async {
      if (files.length >= maxFiles) {
        truncated = true;
        return;
      }
      final relativePath = _relative(file.path);
      if (shouldSkip(relativePath)) return;
      final stat = await file.stat();
      final ext = p.extension(file.path).toLowerCase();
      extensionCounts[ext.isEmpty ? '(none)' : ext] = (extensionCounts[ext.isEmpty ? '(none)' : ext] ?? 0) + 1;
      totalBytes += stat.size;
      final basename = p.basename(file.path).toLowerCase();
      if (basename == 'index.html' ||
          basename == 'package.json' ||
          basename == 'pubspec.yaml' ||
          basename == 'manifest.json' ||
          basename == 'readme.md') {
        entrypoints.add(relativePath);
      }
      files.add({
        'path': relativePath,
        'sizeBytes': stat.size,
        'modifiedAt': stat.modified.toIso8601String(),
      });
    }

    Future<void> walkDirectory(Directory directory, int depth) async {
      if (depth > maxDepth || files.length >= maxFiles) {
        truncated = true;
        return;
      }
      await for (final entity in directory.list(recursive: false, followLinks: false)) {
        if (files.length >= maxFiles) {
          truncated = true;
          break;
        }
        final relativePath = _relative(entity.path);
        if (shouldSkip(relativePath)) continue;
        final type = await FileSystemEntity.type(entity.path, followLinks: false);
        if (type == FileSystemEntityType.directory) {
          directories.add(relativePath);
          await walkDirectory(Directory(entity.path), depth + 1);
        } else if (type == FileSystemEntityType.file) {
          await addFile(File(entity.path));
        }
      }
    }

    if (targetType == FileSystemEntityType.file) {
      await addFile(File(target));
    } else if (targetType == FileSystemEntityType.directory) {
      await walkDirectory(Directory(target), 1);
    } else {
      throw _ActionRunnerFailure(
        'Unsupported project summary target: ${_relative(target)}',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: const ['Choose a regular file or directory inside the workspace.'],
      );
    }

    final sortedExtensions = extensionCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final text = [
      'Project summary for ${_relative(target)}',
      'Files: ${files.length}${truncated ? '+' : ''}, directories: ${directories.length}, bytes: $totalBytes',
      if (entrypoints.isNotEmpty) 'Likely entrypoints: ${entrypoints.take(8).join(', ')}',
      if (sortedExtensions.isNotEmpty) 'Extensions: ${sortedExtensions.take(8).map((entry) => '${entry.key}:${entry.value}').join(', ')}',
      if (directories.isNotEmpty) 'Directories: ${directories.take(12).join(', ')}',
      if (files.isNotEmpty) 'Files:\n${files.take(30).map((file) => '- ${file['path']} (${file['sizeBytes']} bytes)').join('\n')}',
      if (truncated) 'Summary truncated by max_files/max_depth limits.',
    ].join('\n');
    final evidence = ActionEvidence(
      evidenceId: schema.requestId ?? generateEvidenceId(),
      actionName: MobileCodeAction.projectSummary,
      paramsSummary: schema.paramsSummary.isEmpty ? 'project summary ${_relative(target)}' : schema.paramsSummary,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      success: true,
      artifactPaths: [target],
      logs: ['Summarized ${files.length} file(s) and ${directories.length} directorie(s) under ${_relative(target)}.'],
      metadata: {
        'relativePath': _relative(target),
        'maxDepth': maxDepth,
        'maxFiles': maxFiles,
        'truncated': truncated,
        'totalBytes': totalBytes,
        'entrypoints': entrypoints.take(20).toList(),
        'extensionCounts': extensionCounts,
        'files': files.take(80).toList(),
        'directories': directories.take(80).toList(),
      },
    );
    evidenceStore.add(evidence);
    return ActionRunnerResult(evidence: evidence, text: text, path: target);
  }

  Future<ActionRunnerResult> _detectProjectType(ActionSchema schema, DateTime startedAt) async {
    final rawPath = _stringParam(schema, 'path').isEmpty ? '.' : _stringParam(schema, 'path');
    final target = _resolveWorkspacePath(rawPath);
    final maxDepth = _boundedIntParam(schema, 'maxDepth', defaultValue: 4, min: 1, max: 8);
    final maxFiles = _boundedIntParam(schema, 'maxFiles', defaultValue: 120, min: 10, max: 300);
    final targetType = await FileSystemEntity.type(target, followLinks: false);
    if (targetType == FileSystemEntityType.notFound) {
      throw _ActionRunnerFailure(
        'detect_project_type path does not exist: ${_relative(target)}',
        failureKind: ActionFailureKind.processFailed,
        recoveryActions: const ['Call list_files first or choose an existing workspace path.'],
      );
    }

    final files = <String>[];
    final basenames = <String>{};
    var truncated = false;

    bool shouldSkip(String relativePath) {
      final normalized = relativePath.replaceAll('\\', '/');
      return normalized.startsWith('.mobilecode_') || normalized.contains('/.mobilecode_');
    }

    Future<void> addFile(File file) async {
      if (files.length >= maxFiles) {
        truncated = true;
        return;
      }
      final relativePath = _relative(file.path);
      if (shouldSkip(relativePath)) return;
      files.add(relativePath);
      basenames.add(p.basename(relativePath).toLowerCase());
    }

    Future<void> walk(Directory directory, int depth) async {
      if (depth > maxDepth || files.length >= maxFiles) {
        truncated = true;
        return;
      }
      await for (final entity in directory.list(recursive: false, followLinks: false)) {
        if (files.length >= maxFiles) {
          truncated = true;
          break;
        }
        final relativePath = _relative(entity.path);
        if (shouldSkip(relativePath)) continue;
        final type = await FileSystemEntity.type(entity.path, followLinks: false);
        if (type == FileSystemEntityType.file) {
          await addFile(File(entity.path));
        } else if (type == FileSystemEntityType.directory) {
          await walk(Directory(entity.path), depth + 1);
        }
      }
    }

    if (targetType == FileSystemEntityType.file) {
      await addFile(File(target));
    } else if (targetType == FileSystemEntityType.directory) {
      await walk(Directory(target), 1);
    } else {
      throw _ActionRunnerFailure(
        'Unsupported detect_project_type target: ${_relative(target)}',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: const ['Choose a regular file or directory inside the workspace.'],
      );
    }

    final signals = <String>[];
    final projectTypes = <String>[];
    void addType(String type, String signal) {
      if (!projectTypes.contains(type)) projectTypes.add(type);
      signals.add(signal);
    }

    if (basenames.contains('pubspec.yaml') || files.any((file) => file.replaceAll('\\', '/') == 'lib/main.dart')) {
      addType('flutter', 'pubspec.yaml or lib/main.dart');
    }
    if (basenames.contains('build.gradle') || basenames.contains('settings.gradle') || basenames.contains('gradlew')) {
      addType('android_gradle', 'Gradle build files');
    }
    if (basenames.contains('package.json')) {
      addType('node_or_web', 'package.json');
    }
    if (basenames.contains('vite.config.ts') || basenames.contains('vite.config.js')) {
      addType('vite', 'vite config');
    }
    if (basenames.contains('next.config.js') || basenames.contains('next.config.mjs') || basenames.contains('next.config.ts')) {
      addType('nextjs', 'next config');
    }
    if (basenames.contains('index.html')) {
      addType('static_web', 'index.html');
    }
    if (basenames.contains('manifest.json') && (basenames.contains('service-worker.js') || basenames.contains('sw.js'))) {
      addType('pwa', 'manifest + service worker');
    }
    if (basenames.contains('readme.md')) {
      signals.add('README present');
    }
    if (projectTypes.isEmpty) projectTypes.add('unknown');

    final entrypoints = files.where((file) {
      final base = p.basename(file).toLowerCase();
      return base == 'index.html' ||
          base == 'main.dart' ||
          base == 'package.json' ||
          base == 'pubspec.yaml' ||
          base == 'manifest.json' ||
          base == 'readme.md';
    }).take(20).toList();
    final text = [
      'Detected project type(s): ${projectTypes.join(', ')}',
      if (signals.isNotEmpty) 'Signals: ${signals.take(12).join('; ')}',
      if (entrypoints.isNotEmpty) 'Entrypoints: ${entrypoints.join(', ')}',
      'Files inspected: ${files.length}${truncated ? '+' : ''}',
      if (truncated) 'Detection truncated by max_files/max_depth limits.',
    ].join('\n');
    final evidence = ActionEvidence(
      evidenceId: schema.requestId ?? generateEvidenceId(),
      actionName: MobileCodeAction.detectProjectType,
      paramsSummary: schema.paramsSummary.isEmpty ? 'detect project type ${_relative(target)}' : schema.paramsSummary,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      success: true,
      artifactPaths: [target],
      logs: ['Detected ${projectTypes.join(', ')} from ${files.length} file(s).'],
      metadata: {
        'relativePath': _relative(target),
        'projectTypes': projectTypes,
        'signals': signals,
        'entrypoints': entrypoints,
        'filesInspected': files.length,
        'truncated': truncated,
      },
    );
    evidenceStore.add(evidence);
    return ActionRunnerResult(evidence: evidence, text: text, path: target);
  }

  Future<ActionRunnerResult> _validateHtml(ActionSchema schema, DateTime startedAt) async {
    final pathParam = _stringParam(schema, 'path');
    final htmlParam = _stringParam(schema, 'html');
    final maxBytes = _boundedIntParam(schema, 'maxBytes', defaultValue: 256 * 1024, min: 1024, max: 1024 * 1024);
    String html;
    String? target;
    if (pathParam.isNotEmpty) {
      target = _resolveWorkspacePath(pathParam);
      final file = File(target);
      if (!await file.exists()) {
        throw _ActionRunnerFailure(
          'HTML file does not exist: ${_relative(target)}',
          failureKind: ActionFailureKind.processFailed,
          recoveryActions: const ['Create or find the HTML file before validating it.'],
        );
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > maxBytes) {
        throw _ActionRunnerFailure(
          'HTML file is too large to validate on mobile (${bytes.length} bytes).',
          failureKind: ActionFailureKind.commandBlocked,
          recoveryActions: const ['Validate a smaller file or increase max_bytes within the supported cap.'],
        );
      }
      if (_looksBinary(bytes)) {
        throw const _ActionRunnerFailure(
          'validate_html only supports text HTML files.',
          failureKind: ActionFailureKind.commandBlocked,
          recoveryActions: ['Choose a UTF-8 text HTML file.'],
        );
      }
      html = utf8.decode(bytes, allowMalformed: true);
    } else if (htmlParam.isNotEmpty) {
      html = htmlParam;
      if (utf8.encode(html).length > maxBytes) {
        throw const _ActionRunnerFailure(
          'Inline HTML is too large to validate on mobile.',
          failureKind: ActionFailureKind.commandBlocked,
          recoveryActions: ['Validate a smaller HTML payload or write it to a file first.'],
        );
      }
    } else {
      throw const _ActionRunnerFailure(
        'validate_html requires path or html.',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: ['Pass a workspace HTML file path or inline HTML content.'],
      );
    }

    final issues = <Map<String, dynamic>>[];
    void addIssue(String severity, String code, String message) {
      issues.add({'severity': severity, 'code': code, 'message': message});
    }

    final lower = html.toLowerCase();
    if (!lower.contains('<!doctype html')) addIssue('warning', 'missing_doctype', 'Missing <!DOCTYPE html>.');
    if (!RegExp(r'<html[\s>]', caseSensitive: false).hasMatch(html)) addIssue('warning', 'missing_html_tag', 'Missing <html> tag.');
    if (!RegExp(r'<body[\s>]', caseSensitive: false).hasMatch(html)) addIssue('warning', 'missing_body_tag', 'Missing <body> tag.');
    if (_extractHtmlTitle(html).isEmpty) addIssue('warning', 'missing_title', 'Missing non-empty <title>.');
    if (!RegExp('<meta[^>]+name=["\\\']viewport["\\\']', caseSensitive: false).hasMatch(html)) {
      addIssue('warning', 'missing_viewport', 'Missing mobile viewport meta tag.');
    } else if (!lower.contains('width=device-width')) {
      addIssue('warning', 'viewport_not_mobile_width', 'Viewport exists but does not include width=device-width.');
    }
    if (RegExp(r'(http://|https://)', caseSensitive: false).hasMatch(html)) {
      addIssue('info', 'external_asset_reference', 'HTML references external network URLs; prefer inline assets for offline WebView demos.');
    }
    final voidTags = <String>{'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr'};
    final stack = <String>[];
    final tagExp = RegExp(r'<\s*(/)?\s*([a-zA-Z][a-zA-Z0-9-]*)\b([^>]*)>', caseSensitive: false);
    for (final match in tagExp.allMatches(html).take(400)) {
      final closing = match.group(1) == '/';
      final tag = (match.group(2) ?? '').toLowerCase();
      final tail = match.group(3) ?? '';
      if (tag.isEmpty || voidTags.contains(tag) || tail.trim().endsWith('/')) continue;
      if (!closing) {
        stack.add(tag);
      } else if (stack.isNotEmpty && stack.last == tag) {
        stack.removeLast();
      } else if (stack.contains(tag)) {
        while (stack.isNotEmpty && stack.last != tag) {
          addIssue('warning', 'tag_order_mismatch', 'Tag <${stack.removeLast()}> was not closed before </$tag>.');
          if (issues.length >= 20) break;
        }
        if (stack.isNotEmpty && stack.last == tag) stack.removeLast();
      } else {
        addIssue('warning', 'unexpected_closing_tag', 'Unexpected closing tag </$tag>.');
      }
      if (issues.length >= 24) break;
    }
    for (final tag in stack.reversed.take(8)) {
      addIssue('warning', 'unclosed_tag', 'Unclosed tag <$tag>.');
    }

    final text = issues.isEmpty
        ? 'HTML validation passed${target == null ? '' : ' for ${_relative(target)}'}: no obvious structural issues.'
        : [
            'HTML validation found ${issues.length} issue(s)${target == null ? '' : ' in ${_relative(target)}'}:',
            ...issues.take(20).map((issue) => '- ${issue['severity']} ${issue['code']}: ${issue['message']}'),
          ].join('\n');
    final evidence = ActionEvidence(
      evidenceId: schema.requestId ?? generateEvidenceId(),
      actionName: MobileCodeAction.validateHtml,
      paramsSummary: schema.paramsSummary.isEmpty ? 'validate html${target == null ? '' : ' ${_relative(target)}'}' : schema.paramsSummary,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      success: true,
      artifactPaths: [
        if (target != null) target,
      ],
      logs: ['Validated HTML with ${issues.length} issue(s).'],
      metadata: {
        if (target != null) 'relativePath': _relative(target),
        'htmlBytes': utf8.encode(html).length,
        'title': _extractHtmlTitle(html),
        'issueCount': issues.length,
        'issues': issues,
      },
    );
    evidenceStore.add(evidence);
    return ActionRunnerResult(evidence: evidence, text: text, path: target);
  }

  Future<ActionRunnerResult> _validateJson(ActionSchema schema, DateTime startedAt) async {
    final pathParam = _stringParam(schema, 'path');
    final jsonParam = _stringParam(schema, 'json');
    final maxBytes = _boundedIntParam(schema, 'maxBytes', defaultValue: 256 * 1024, min: 1024, max: 1024 * 1024);
    String content;
    String? target;
    if (pathParam.isNotEmpty) {
      target = _resolveWorkspacePath(pathParam);
      final file = File(target);
      if (!await file.exists()) {
        throw _ActionRunnerFailure(
          'JSON file does not exist: ${_relative(target)}',
          failureKind: ActionFailureKind.processFailed,
          recoveryActions: const ['Create or find the JSON file before validating it.'],
        );
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > maxBytes) {
        throw _ActionRunnerFailure(
          'JSON file is too large to validate on mobile (${bytes.length} bytes).',
          failureKind: ActionFailureKind.commandBlocked,
          recoveryActions: const ['Validate a smaller file or increase max_bytes within the supported cap.'],
        );
      }
      if (_looksBinary(bytes)) {
        throw const _ActionRunnerFailure(
          'validate_json only supports UTF-8 text JSON files.',
          failureKind: ActionFailureKind.commandBlocked,
          recoveryActions: ['Choose a text JSON file.'],
        );
      }
      content = utf8.decode(bytes, allowMalformed: true);
    } else if (jsonParam.isNotEmpty) {
      content = jsonParam;
      if (utf8.encode(content).length > maxBytes) {
        throw const _ActionRunnerFailure(
          'Inline JSON is too large to validate on mobile.',
          failureKind: ActionFailureKind.commandBlocked,
          recoveryActions: ['Validate a smaller JSON payload or write it to a file first.'],
        );
      }
    } else {
      throw const _ActionRunnerFailure(
        'validate_json requires path or json.',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: ['Pass a workspace JSON file path or inline JSON content.'],
      );
    }

    var valid = true;
    String? error;
    String rootType = 'unknown';
    int? itemCount;
    try {
      final parsed = jsonDecode(content);
      if (parsed is Map) {
        rootType = 'object';
        itemCount = parsed.length;
      } else if (parsed is List) {
        rootType = 'array';
        itemCount = parsed.length;
      } else {
        rootType = parsed.runtimeType.toString();
      }
    } on FormatException catch (e) {
      valid = false;
      error = _compact(e.message, 240);
    }

    final text = valid
        ? 'JSON validation passed${target == null ? '' : ' for ${_relative(target)}'}: root=$rootType${itemCount == null ? '' : ', items=$itemCount'}.'
        : 'JSON validation found syntax issue${target == null ? '' : ' in ${_relative(target)}'}: $error';
    final evidence = ActionEvidence(
      evidenceId: schema.requestId ?? generateEvidenceId(),
      actionName: MobileCodeAction.validateJson,
      paramsSummary: schema.paramsSummary.isEmpty ? 'validate json${target == null ? '' : ' ${_relative(target)}'}' : schema.paramsSummary,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      success: true,
      artifactPaths: [if (target != null) target],
      logs: ['Validated JSON: ${valid ? 'valid' : 'invalid'}.'],
      metadata: {
        if (target != null) 'relativePath': _relative(target),
        'jsonBytes': utf8.encode(content).length,
        'valid': valid,
        'rootType': rootType,
        if (itemCount != null) 'itemCount': itemCount,
        if (error != null) 'error': error,
      },
    );
    evidenceStore.add(evidence);
    return ActionRunnerResult(evidence: evidence, text: text, path: target);
  }

  Future<ActionRunnerResult> _validateMarkdown(ActionSchema schema, DateTime startedAt) async {
    final pathParam = _stringParam(schema, 'path');
    final markdownParam = _stringParam(schema, 'markdown');
    final maxBytes = _boundedIntParam(schema, 'maxBytes', defaultValue: 256 * 1024, min: 1024, max: 1024 * 1024);
    String content;
    String? target;
    if (pathParam.isNotEmpty) {
      target = _resolveWorkspacePath(pathParam);
      final file = File(target);
      if (!await file.exists()) {
        throw _ActionRunnerFailure(
          'Markdown file does not exist: ${_relative(target)}',
          failureKind: ActionFailureKind.processFailed,
          recoveryActions: const ['Create or find the Markdown file before validating it.'],
        );
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > maxBytes) {
        throw _ActionRunnerFailure(
          'Markdown file is too large to validate on mobile (${bytes.length} bytes).',
          failureKind: ActionFailureKind.commandBlocked,
          recoveryActions: const ['Validate a smaller file or increase max_bytes within the supported cap.'],
        );
      }
      if (_looksBinary(bytes)) {
        throw const _ActionRunnerFailure(
          'validate_markdown only supports UTF-8 text Markdown files.',
          failureKind: ActionFailureKind.commandBlocked,
          recoveryActions: ['Choose a text Markdown file.'],
        );
      }
      content = utf8.decode(bytes, allowMalformed: true);
    } else if (markdownParam.isNotEmpty) {
      content = markdownParam;
      if (utf8.encode(content).length > maxBytes) {
        throw const _ActionRunnerFailure(
          'Inline Markdown is too large to validate on mobile.',
          failureKind: ActionFailureKind.commandBlocked,
          recoveryActions: ['Validate a smaller Markdown payload or write it to a file first.'],
        );
      }
    } else {
      throw const _ActionRunnerFailure(
        'validate_markdown requires path or markdown.',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: ['Pass a workspace Markdown file path or inline Markdown content.'],
      );
    }

    final issues = <Map<String, dynamic>>[];
    void addIssue(String severity, String code, String message, int line) {
      issues.add({'severity': severity, 'code': code, 'message': message, 'line': line});
    }

    final lines = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    var hasH1 = false;
    var lastHeadingLevel = 0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineNo = i + 1;
      final heading = RegExp(r'^(#{1,6})\s+\S').firstMatch(line);
      if (heading != null) {
        final level = heading.group(1)!.length;
        if (level == 1) hasH1 = true;
        if (lastHeadingLevel > 0 && level > lastHeadingLevel + 1) {
          addIssue('warning', 'heading_jump', 'Heading jumps from H$lastHeadingLevel to H$level.', lineNo);
        }
        lastHeadingLevel = level;
      }
      if (line.length > 160) {
        addIssue('info', 'long_line', 'Line is longer than 160 characters; consider wrapping for mobile readability.', lineNo);
      }
      if (RegExp(r'https?://\S+').hasMatch(line) && !RegExp(r'\[[^\]]+\]\(https?://').hasMatch(line)) {
        addIssue('info', 'bare_url', 'Bare URL found; consider Markdown link text for readability.', lineNo);
      }
      if (line.endsWith(' ') || line.endsWith('\t')) {
        addIssue('info', 'trailing_whitespace', 'Trailing whitespace.', lineNo);
      }
      if (issues.length >= 30) break;
    }
    if (!hasH1 && content.trim().isNotEmpty) {
      addIssue('warning', 'missing_h1', 'No top-level # heading found.', 1);
    }

    final text = issues.isEmpty
        ? 'Markdown validation passed${target == null ? '' : ' for ${_relative(target)}'}: no basic structure issues.'
        : [
            'Markdown validation found ${issues.length} issue(s)${target == null ? '' : ' in ${_relative(target)}'}:',
            ...issues.take(20).map((issue) => '- line ${issue['line']} ${issue['severity']} ${issue['code']}: ${issue['message']}'),
          ].join('\n');
    final evidence = ActionEvidence(
      evidenceId: schema.requestId ?? generateEvidenceId(),
      actionName: MobileCodeAction.validateMarkdown,
      paramsSummary: schema.paramsSummary.isEmpty ? 'validate markdown${target == null ? '' : ' ${_relative(target)}'}' : schema.paramsSummary,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      success: true,
      artifactPaths: [if (target != null) target],
      logs: ['Validated Markdown with ${issues.length} issue(s).'],
      metadata: {
        if (target != null) 'relativePath': _relative(target),
        'markdownBytes': utf8.encode(content).length,
        'lineCount': lines.length,
        'issueCount': issues.length,
        'issues': issues,
      },
    );
    evidenceStore.add(evidence);
    return ActionRunnerResult(evidence: evidence, text: text, path: target);
  }

  Future<ActionRunnerResult> _applyPatch(ActionSchema schema, DateTime startedAt) async {
    final patch = _requiredString(schema, 'patch');
    final reason = _stringParam(schema, 'reason');
    final patchBytes = utf8.encode(patch).length;
    if (patchBytes > 80 * 1024) {
      throw _ActionRunnerFailure(
        'Patch is too large for mobile auto-apply (${patchBytes} bytes).',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: const ['Split the patch into smaller file-scoped patches.'],
      );
    }
    if (patch.contains('\u0000') || patch.contains('GIT binary patch')) {
      throw const _ActionRunnerFailure(
        'Binary patches are not supported by MobileCode apply_patch.',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: ['Use text files only.'],
      );
    }

    final files = _parseUnifiedPatch(patch);
    if (files.isEmpty) {
      throw const _ActionRunnerFailure(
        'apply_patch requires a unified diff with ---/+++ file headers and @@ hunks.',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: ['Ask the model to return a valid unified diff patch.'],
      );
    }
    if (files.length > 5) {
      throw _ActionRunnerFailure(
        'Patch touches too many files (${files.length}); mobile auto-apply is limited to 5 files.',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: const ['Split the change into smaller patches.'],
      );
    }
    final changedLineCount = files.fold<int>(
      0,
      (sum, file) => sum + file.hunks.fold<int>(0, (hunkSum, hunk) => hunkSum + hunk.lines.where((line) => line.startsWith('+') || line.startsWith('-')).length),
    );
    if (changedLineCount > 800) {
      throw _ActionRunnerFailure(
        'Patch changes too many lines ($changedLineCount); mobile auto-apply is limited to 800 changed lines.',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: const ['Split the patch or ask for a smaller targeted change.'],
      );
    }

    final snapshotRoot = _resolveWorkspacePath(
      '.mobilecode_patch_snapshots/patch_${DateTime.now().millisecondsSinceEpoch}',
    );
    final changedPaths = <String>[];
    final snapshots = <String>[];
    for (final filePatch in files) {
      if (filePatch.isDelete) {
        throw _ActionRunnerFailure(
          'Patch deletes ${filePatch.displayPath}; deletion is blocked in Agent Loop auto-apply.',
          failureKind: ActionFailureKind.commandBlocked,
          recoveryActions: const ['Use a non-deleting patch or ask the user for explicit deletion approval.'],
        );
      }
      final target = _resolveWorkspacePath(filePatch.targetPath);
      final existing = File(target);
      if (await existing.exists()) {
        final snapshotPath = p.join(snapshotRoot, filePatch.targetPath);
        final snapshotFile = File(snapshotPath);
        await snapshotFile.parent.create(recursive: true);
        await existing.copy(snapshotPath);
        snapshots.add(snapshotPath);
      }
      final originalText = await existing.exists() ? await existing.readAsString() : '';
      final nextText = _applyFilePatch(filePatch, originalText);
      await existing.parent.create(recursive: true);
      await existing.writeAsString(nextText, flush: true);
      changedPaths.add(target);
    }

    final patchRecordPath = p.join(snapshotRoot, 'applied.patch');
    final patchRecord = File(patchRecordPath);
    await patchRecord.parent.create(recursive: true);
    await patchRecord.writeAsString(patch, flush: true);

    final relativeChanged = changedPaths.map(_relative).toList();
    final evidence = ActionEvidence(
      evidenceId: schema.requestId ?? generateEvidenceId(),
      actionName: MobileCodeAction.applyPatch,
      paramsSummary: schema.paramsSummary.isEmpty ? 'apply patch${reason.isEmpty ? '' : ': $reason'}' : schema.paramsSummary,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      success: true,
      artifactPaths: [
        ...changedPaths,
        patchRecordPath,
        ...snapshots,
      ],
      logs: [
        'Applied patch to ${relativeChanged.length} file(s): ${relativeChanged.join(', ')}.',
        if (snapshots.isNotEmpty) 'Saved ${snapshots.length} pre-patch snapshot(s) under ${_relative(snapshotRoot)}.',
        'Patch record: ${_relative(patchRecordPath)}.',
      ],
      metadata: {
        'reason': reason,
        'changedFiles': relativeChanged,
        'snapshotRoot': _relative(snapshotRoot),
        'patchBytes': patchBytes,
        'changedLineCount': changedLineCount,
      },
    );
    evidenceStore.add(evidence);
    return ActionRunnerResult(
      evidence: evidence,
      text: 'Applied patch to ${relativeChanged.join(', ')}.',
      path: changedPaths.isEmpty ? null : changedPaths.first,
    );
  }

  Future<ActionRunnerResult> _termuxTaskStart(ActionSchema schema, DateTime startedAt) async {
    final taskKind = _requiredString(schema, 'taskKind');
    final pathParam = _stringParam(schema, 'path');
    final reason = _stringParam(schema, 'reason');
    final argsJson = _stringParam(schema, 'argsJson');
    final timeoutMs = _boundedIntParam(schema, 'timeoutMs', defaultValue: 30000, min: 1000, max: 120000);
    final maxOutputBytes = _boundedIntParam(schema, 'maxOutputBytes', defaultValue: 32 * 1024, min: 1024, max: 128 * 1024);
    const allowedKinds = {
      'project_check',
      'validate',
      'build_preview',
      'flutter_analyze',
      'flutter_test',
      'npm_build',
    };
    if (!allowedKinds.contains(taskKind)) {
      throw _ActionRunnerFailure(
        'termux_task_start only accepts typed task kinds, not raw shell: $taskKind',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: const ['Choose one of project_check, validate, build_preview, flutter_analyze, flutter_test, or npm_build.'],
      );
    }
    Map<String, dynamic> args = const {};
    if (argsJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(argsJson);
        if (decoded is Map<String, dynamic>) {
          args = decoded;
        } else {
          throw const FormatException('args_json must decode to an object');
        }
      } on Object catch (error) {
        throw _ActionRunnerFailure(
          'Invalid args_json for termux_task_start: $error',
          failureKind: ActionFailureKind.commandBlocked,
          recoveryActions: const ['Pass a small JSON object string, for example {"entry":"index.html"}, or "{}".'],
        );
      }
    }
    final cleanArgs = <String, dynamic>{};
    final blockedKeys = {'command', 'cmd', 'shell'};
    for (final entry in args.entries) {
      final key = entry.key.trim().toLowerCase();
      final value = entry.value;
      if (blockedKeys.contains(key) || key.contains('shell')) {
        throw _ActionRunnerFailure(
          'termux_task_start argsJson is typed payload only and must not include shell execution fields.',
          failureKind: ActionFailureKind.commandBlocked,
          recoveryActions: const [
            'Only pass typed task arguments (for example {"entry":"index.html"}).',
            'Do not pass command or shell-style fields.',
          ],
        );
      }
      if (value is Map || value is List) {
        throw _ActionRunnerFailure(
          'termux_task_start argsJson values must be simple scalars only.',
          failureKind: ActionFailureKind.commandBlocked,
          recoveryActions: const ['Flatten argsJson to simple key/value fields; avoid nested objects or arrays.'],
        );
      }
      cleanArgs[entry.key] = value;
    }
    final target = pathParam.isEmpty ? workspaceRootPath : _resolveWorkspacePath(pathParam);
    final generatedTaskId = 'termux_${DateTime.now().millisecondsSinceEpoch}';
    final payload = <String, dynamic>{
      'taskId': generatedTaskId,
      'taskKind': taskKind,
      'path': _relative(target),
      'absolutePath': target,
      'args': cleanArgs,
      'timeoutMs': timeoutMs,
      'maxOutputBytes': maxOutputBytes,
      if (reason.isNotEmpty) 'reason': reason,
    };

    final invoker = termuxTaskInvoker;
    if (invoker == null) {
      final text =
          'Termux typed task route is not connected. taskId=$generatedTaskId, taskKind=$taskKind. No raw shell was executed.';
      final evidence = ActionEvidence(
        evidenceId: schema.requestId ?? generateEvidenceId(),
        actionName: MobileCodeAction.termuxTaskStart,
        paramsSummary: schema.paramsSummary.isEmpty ? 'termux task $taskKind' : schema.paramsSummary,
        startedAt: startedAt,
        endedAt: DateTime.now(),
        success: false,
        artifactPaths: [target],
        logs: [
          text,
          'MobileCode requires a configured Termux daemon or MobileCode Helper before typed runtime tasks can run.',
        ],
        failureKind: ActionFailureKind.dependencyMissing,
        recoveryActions: const [
          'Configure the MobileCode Helper or Termux daemon bridge.',
          'Use MobileCode typed file tools or GitHub Actions for validation until the helper is connected.',
        ],
        metadata: {
          ...payload,
          'status': 'unavailable',
          'stdout': '',
          'stderr': 'Termux helper unavailable',
          'requestedTaskId': generatedTaskId,
        },
      );
      evidenceStore.add(evidence);
      return ActionRunnerResult(evidence: evidence, text: text, path: target);
    }

    final raw = await invoker(taskKind, payload);
    final rawStatus = raw['status']?.toString();
    final status = rawStatus != null && rawStatus.trim().isNotEmpty ? rawStatus.toLowerCase() : null;
    final normalizedStatus = status?.replaceAll(RegExp(r'[^a-z]'), '');
    final rawStdout = _compact(_stringValue(raw['stdout']), maxOutputBytes);
    final rawStderr = _compact(_stringValue(raw['stderr']), maxOutputBytes);
    final exitCodeRaw = raw['exitCode'];
    final exitCode = exitCodeRaw is num ? exitCodeRaw.toInt() : null;
    final success = normalizedStatus == 'succeeded' ||
        normalizedStatus == 'completed' ||
        normalizedStatus == 'success' ||
        (status == null && (raw['success'] == true || exitCode == 0));
    final returnedTaskId = _stringValue(raw['taskId']).isEmpty ? generatedTaskId : _stringValue(raw['taskId']);
    final resolvedStatus = status == null ? (success ? 'completed' : 'failed') : status;
    final String? failureKind;
    if (success) {
      failureKind = null;
    } else if (normalizedStatus == 'dependencymissing') {
      failureKind = ActionFailureKind.dependencyMissing;
    } else if (normalizedStatus == 'commandblocked') {
      failureKind = ActionFailureKind.commandBlocked;
    } else if (normalizedStatus == 'timeout' || normalizedStatus == 'timedout') {
      failureKind = ActionFailureKind.timeout;
    } else if (normalizedStatus == 'cancelled') {
      failureKind = ActionFailureKind.cancelled;
    } else {
      failureKind = ActionFailureKind.processFailed;
    }
    final text = [
      'Termux typed task $taskKind ${success ? 'completed' : 'failed'} with taskId=$returnedTaskId.',
      if (rawStdout.isNotEmpty) 'stdout: $rawStdout',
      if (rawStderr.isNotEmpty) 'stderr: $rawStderr',
    ].join('\n');
    final evidence = ActionEvidence(
      evidenceId: schema.requestId ?? generateEvidenceId(),
      actionName: MobileCodeAction.termuxTaskStart,
      paramsSummary: schema.paramsSummary.isEmpty ? 'termux task $taskKind' : schema.paramsSummary,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      success: success,
      artifactPaths: [target],
      logs: [
        'Termux typed task $taskKind returned taskId=$returnedTaskId.',
        if (rawStdout.isNotEmpty) 'stdout: $rawStdout',
        if (rawStderr.isNotEmpty) 'stderr: $rawStderr',
      ],
      exitCode: exitCode,
      failureKind: failureKind,
      recoveryActions: success
          ? const []
          : const ['Inspect stdout/stderr and rerun a narrower typed task, or fall back to GitHub Actions.'],
      metadata: {
        ...payload,
        ...raw,
        'status': resolvedStatus,
        'taskId': returnedTaskId,
        'requestedTaskId': generatedTaskId,
        'stdout': rawStdout,
        'stderr': rawStderr,
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

  Future<ActionRunnerResult> _webSearch(ActionSchema schema, DateTime startedAt) async {
    final invoker = webToolInvoker;
    if (invoker == null) {
      throw const _ActionRunnerFailure(
        'webSearch requires the managed relay web tool endpoint.',
        failureKind: ActionFailureKind.dependencyMissing,
        recoveryActions: ['Configure MOBILECODE_MANAGED_RELAY_URL before exposing web_search.'],
      );
    }
    final query = _requiredString(schema, 'query');
    final count = _boundedIntParam(schema, 'count', defaultValue: 5, min: 1, max: 5);
    final payload = await invoker('web_search', {
      'query': query,
      'count': count,
    });
    final results = _compactSearchResults(payload['results'], count);
    final source = _stringValue(payload['source']).isEmpty ? 'relay' : _stringValue(payload['source']);
    final text = _searchResultsText(query, results);

    final evidence = ActionEvidence(
      evidenceId: schema.requestId ?? generateEvidenceId(),
      actionName: MobileCodeAction.webSearch,
      paramsSummary: schema.paramsSummary.isEmpty ? 'web search "$query"' : schema.paramsSummary,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      success: true,
      urls: results.map((item) => _stringValue(item['url'])).where((url) => url.isNotEmpty).toList(),
      logs: ['Searched web for "$query" via $source and received ${results.length} result(s).'],
      metadata: {
        'query': query,
        'source': source,
        'results': results,
      },
    );
    evidenceStore.add(evidence);
    return ActionRunnerResult(evidence: evidence, text: text);
  }

  Future<ActionRunnerResult> _fetchUrl(ActionSchema schema, DateTime startedAt) async {
    final invoker = webToolInvoker;
    if (invoker == null) {
      throw const _ActionRunnerFailure(
        'fetchUrl requires the managed relay web tool endpoint.',
        failureKind: ActionFailureKind.dependencyMissing,
        recoveryActions: ['Configure MOBILECODE_MANAGED_RELAY_URL before exposing fetch_url.'],
      );
    }
    final uri = _safeHttpsUri(_requiredString(schema, 'url'));
    final maxBytes = _boundedIntParam(schema, 'maxBytes', defaultValue: 80 * 1024, min: 1024, max: 120 * 1024);
    final payload = await invoker('fetch_url', {
      'url': uri.toString(),
      'maxBytes': maxBytes,
    });
    final title = _stringValue(payload['title']);
    final finalUrl = _stringValue(payload['finalUrl']).isEmpty ? uri.toString() : _stringValue(payload['finalUrl']);
    final contentType = _stringValue(payload['contentType']);
    final text = _compact(_stringValue(payload['text']), 6000);
    final truncated = payload['truncated'] == true;

    final evidence = ActionEvidence(
      evidenceId: schema.requestId ?? generateEvidenceId(),
      actionName: MobileCodeAction.fetchUrl,
      paramsSummary: schema.paramsSummary.isEmpty ? 'fetch ${uri.host}' : schema.paramsSummary,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      success: true,
      urls: [finalUrl],
      logs: [
        'Fetched ${uri.toString()}${title.isEmpty ? '' : ' ($title)'}${truncated ? ', truncated' : ''}.',
      ],
      metadata: {
        'url': uri.toString(),
        'finalUrl': finalUrl,
        if (title.isNotEmpty) 'title': title,
        if (contentType.isNotEmpty) 'contentType': contentType,
        'truncated': truncated,
        'textPreview': _compact(text, 2000),
      },
    );
    evidenceStore.add(evidence);
    return ActionRunnerResult(evidence: evidence, text: text, url: finalUrl);
  }

  Future<ActionRunnerResult> _previewSnapshot(ActionSchema schema, DateTime startedAt) async {
    final path = schema.params['path'];
    final urlParam = schema.params['url'];
    final htmlParam = schema.params['html'];
    final viewportWidth = _boundedIntParam(schema, 'viewportWidth', defaultValue: 390, min: 240, max: 1440);
    final viewportHeight = _boundedIntParam(schema, 'viewportHeight', defaultValue: 844, min: 320, max: 2400);
    String? target;
    String? previewUrl;
    String html = '';

    if (path is String && path.trim().isNotEmpty) {
      target = _resolveWorkspacePath(path);
      final file = File(target);
      if (!await file.exists()) {
        throw _ActionRunnerFailure(
          'HTML file does not exist for preview snapshot: ${_relative(target)}',
          failureKind: ActionFailureKind.processFailed,
          recoveryActions: const ['Create or preview the HTML file before capturing a snapshot.'],
        );
      }
      html = await file.readAsString();
      previewUrl = file.uri.toString();
    } else if (htmlParam is String && htmlParam.trim().isNotEmpty) {
      html = htmlParam;
      target = _resolveWorkspacePath('.mobilecode_preview_snapshot/inline.html');
      final file = File(target);
      await file.parent.create(recursive: true);
      await file.writeAsString(html, flush: true);
      previewUrl = file.uri.toString();
    } else if (urlParam is String && urlParam.trim().isNotEmpty) {
      final uri = _safePreviewUri(urlParam);
      previewUrl = uri.toString();
    } else {
      throw const _ActionRunnerFailure(
        'previewSnapshot requires params.path, params.html, or params.url.',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: ['Pass the same path used by preview_html or a safe preview URL.'],
      );
    }

    final snapshot = {
      'snapshotType': 'evidence',
      'capturedAt': DateTime.now().toIso8601String(),
      'viewport': {
        'width': viewportWidth,
        'height': viewportHeight,
      },
      if (target != null) 'relativePath': _relative(target),
      if (previewUrl != null) 'previewUrl': previewUrl,
      if (html.isNotEmpty) ...{
        'htmlBytes': utf8.encode(html).length,
        'title': _extractHtmlTitle(html),
        'bodyTextPreview': _extractBodyTextPreview(html),
      },
    };
    final snapshotPath = _resolveWorkspacePath(
      '.mobilecode_preview_snapshots/snapshot_${DateTime.now().millisecondsSinceEpoch}.json',
    );
    final snapshotFile = File(snapshotPath);
    await snapshotFile.parent.create(recursive: true);
    await snapshotFile.writeAsString(const JsonEncoder.withIndent('  ').convert(snapshot), flush: true);

    final evidence = ActionEvidence(
      evidenceId: schema.requestId ?? generateEvidenceId(),
      actionName: MobileCodeAction.previewSnapshot,
      paramsSummary: schema.paramsSummary.isEmpty ? 'capture preview evidence snapshot' : schema.paramsSummary,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      success: true,
      artifactPaths: [
        if (target != null) target,
        snapshotPath,
      ],
      urls: [
        if (previewUrl != null) previewUrl,
      ],
      logs: [
        'Saved evidence snapshot for ${target == null ? previewUrl : _relative(target)}.',
        'Snapshot metadata file: ${_relative(snapshotPath)}.',
      ],
      metadata: snapshot,
    );
    evidenceStore.add(evidence);
    return ActionRunnerResult(evidence: evidence, path: snapshotPath, url: previewUrl);
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

  List<Map<String, dynamic>> _compactSearchResults(Object? raw, int limit) {
    if (raw is! List) return const [];
    final results = <Map<String, dynamic>>[];
    for (final item in raw.take(limit)) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final url = _stringValue(map['url']);
      if (url.isNotEmpty) {
        try {
          _safeHttpsUri(url);
        } on _ActionRunnerFailure {
          continue;
        }
      }
      results.add({
        'refId': _stringValue(map['refId']).isEmpty ? 'web_${results.length + 1}' : _stringValue(map['refId']),
        'title': _compact(_stringValue(map['title']), 160),
        'url': url,
        'snippet': _compact(_stringValue(map['snippet']), 360),
      });
    }
    return results;
  }

  String _searchResultsText(String query, List<Map<String, dynamic>> results) {
    if (results.isEmpty) return 'No web results returned for "$query".';
    final lines = <String>['Web search results for "$query":'];
    for (final item in results) {
      final refId = _stringValue(item['refId']);
      final title = _stringValue(item['title']);
      final url = _stringValue(item['url']);
      final snippet = _stringValue(item['snippet']);
      lines.add('- [$refId] ${title.isEmpty ? url : title}${url.isEmpty ? '' : ' - $url'}${snippet.isEmpty ? '' : ' :: $snippet'}');
    }
    return lines.join('\n');
  }

  Uri _safeHttpsUri(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'https' || uri.host.trim().isEmpty) {
      throw _ActionRunnerFailure(
        'Only https URLs are allowed for relay web tools: $rawUrl',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: const ['Use a public https URL. Local, file, content, and http URLs are blocked.'],
      );
    }
    if (_isBlockedHost(uri.host)) {
      throw _ActionRunnerFailure(
        'Blocked private or local URL host: ${uri.host}',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: const ['Use a public documentation or reference URL instead.'],
      );
    }
    return uri;
  }

  Uri _safePreviewUri(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || uri.scheme.trim().isEmpty) {
      throw _ActionRunnerFailure(
        'Invalid preview URL: $rawUrl',
        failureKind: ActionFailureKind.commandBlocked,
      );
    }
    if (uri.scheme == 'file') return uri;
    return _safeHttpsUri(rawUrl);
  }

  bool _isBlockedHost(String host) {
    final lower = host.toLowerCase();
    if (lower == 'localhost' || lower.endsWith('.localhost') || lower.endsWith('.local')) return true;
    final ip = InternetAddress.tryParse(lower);
    if (ip == null) return false;
    if (ip.isLoopback || ip.isLinkLocal || ip.isMulticast) return true;
    if (ip.type == InternetAddressType.IPv4) {
      final parts = lower.split('.').map(int.tryParse).toList();
      if (parts.length != 4 || parts.any((part) => part == null)) return true;
      final a = parts[0]!;
      final b = parts[1]!;
      return a == 10 ||
          a == 127 ||
          (a == 172 && b >= 16 && b <= 31) ||
          (a == 192 && b == 168) ||
          (a == 169 && b == 254) ||
          a == 0;
    }
    return lower == '::1' || lower.startsWith('fc') || lower.startsWith('fd') || lower.startsWith('fe80');
  }

  String _extractHtmlTitle(String html) {
    final match = RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false).firstMatch(html);
    return match == null ? '' : _compact(_stripHtml(match.group(1) ?? ''), 160);
  }

  String _extractBodyTextPreview(String html) {
    var text = html.replaceAll(RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false), ' ');
    text = text.replaceAll(RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false), ' ');
    return _compact(_stripHtml(text), 2000);
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _stringValue(Object? value) => value is String ? value.trim() : value?.toString().trim() ?? '';

  Map<String, dynamic> _fileListEntry(String absolutePath, FileStat stat, String type) {
    return {
      'path': _relative(absolutePath),
      'type': type,
      'sizeBytes': stat.size,
      'modifiedAt': stat.modified.toIso8601String(),
    };
  }

  String _stringParam(ActionSchema schema, String key) {
    final value = schema.params[key];
    return value is String ? value.trim() : '';
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

  int _boundedIntParam(
    ActionSchema schema,
    String key, {
    required int defaultValue,
    required int min,
    required int max,
  }) {
    final raw = _intParam(schema, key, defaultValue: defaultValue);
    return math.min(math.max(raw, min), max).toInt();
  }

  RegExp _globToRegExp(String glob) {
    final raw = glob.trim().isEmpty ? '*' : glob.trim().replaceAll('\\', '/');
    final normalized = raw.contains('*') || raw.contains('?') ? raw : '*$raw*';
    final buffer = StringBuffer('^');
    for (var i = 0; i < normalized.length; i++) {
      final char = normalized[i];
      if (char == '*') {
        buffer.write('.*');
      } else if (char == '?') {
        buffer.write('.');
      } else {
        buffer.write(RegExp.escape(char));
      }
    }
    buffer.write(r'$');
    return RegExp(buffer.toString(), caseSensitive: false);
  }

  bool _looksBinary(List<int> bytes) {
    final scanLength = math.min(bytes.length, 4096);
    for (var i = 0; i < scanLength; i++) {
      if (bytes[i] == 0) return true;
    }
    return false;
  }

  List<_UnifiedFilePatch> _parseUnifiedPatch(String patch) {
    final lines = patch.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final files = <_UnifiedFilePatch>[];
    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      if (!line.startsWith('--- ')) {
        i++;
        continue;
      }
      final oldPath = _normalizePatchPath(line.substring(4));
      i++;
      if (i >= lines.length || !lines[i].startsWith('+++ ')) {
        throw const _ActionRunnerFailure(
          'Invalid unified diff: expected +++ file header after ---.',
          failureKind: ActionFailureKind.commandBlocked,
          recoveryActions: [
            'Read_file first when context is missing, then send a valid unified diff with @@ line numbers.',
            'For small HTML artifacts, use write_file with complete HTML to overwrite the target.',
          ],
        );
      }
      final newPath = _normalizePatchPath(lines[i].substring(4));
      i++;
      final hunks = <_UnifiedHunk>[];
      while (i < lines.length && !lines[i].startsWith('--- ')) {
        if (!lines[i].startsWith('@@ ')) {
          i++;
          continue;
        }
        final hunk = _parseHunkHeader(lines[i]);
        i++;
        final hunkLines = <String>[];
        while (i < lines.length && !lines[i].startsWith('@@ ') && !lines[i].startsWith('--- ')) {
          final hunkLine = lines[i];
          if (hunkLine == r'\ No newline at end of file') {
            i++;
            continue;
          }
          if (hunkLine.isEmpty && i == lines.length - 1) {
            i++;
            continue;
          }
          if (hunkLine.startsWith(' ') || hunkLine.startsWith('+') || hunkLine.startsWith('-')) {
            hunkLines.add(hunkLine);
            i++;
            continue;
          }
          if (hunkLine.startsWith('diff --git ')) break;
          throw _ActionRunnerFailure(
            'Invalid unified diff hunk line: ${_compact(hunkLine, 80)}',
            failureKind: ActionFailureKind.commandBlocked,
            recoveryActions: const ['Use only context, addition, and removal lines inside hunks.'],
          );
        }
        hunks.add(hunk.copyWith(lines: hunkLines));
      }
      final targetPath = newPath.isNotEmpty ? newPath : oldPath;
      if (targetPath.isEmpty) {
        throw const _ActionRunnerFailure(
          'Patch file path is empty.',
          failureKind: ActionFailureKind.commandBlocked,
          recoveryActions: ['Use a workspace-relative file path in the patch headers.'],
        );
      }
      files.add(_UnifiedFilePatch(
        oldPath: oldPath,
        newPath: newPath,
        hunks: hunks,
      ));
    }
    return files;
  }

  String _normalizePatchPath(String raw) {
    final withoutTimestamp = raw.trim().split(RegExp(r'\s+')).first;
    if (withoutTimestamp == '/dev/null') return '';
    var path = withoutTimestamp.replaceAll('\\', '/');
    if ((path.startsWith('"') && path.endsWith('"')) || (path.startsWith("'") && path.endsWith("'"))) {
      path = path.substring(1, path.length - 1);
    }
    if (path.startsWith('a/')) path = path.substring(2);
    if (path.startsWith('b/')) path = path.substring(2);
    return path;
  }

  _UnifiedHunk _parseHunkHeader(String header) {
    final match = RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@').firstMatch(header);
    if (match == null) {
      throw _ActionRunnerFailure(
        'Invalid unified diff hunk header: $header',
        failureKind: ActionFailureKind.commandBlocked,
        recoveryActions: const [
          'Read_file first to confirm current context, then emit a valid @@ -oldStart,oldCount +newStart,newCount @@ header.',
          'For complete HTML artifacts, prefer write_file when practical.',
        ],
      );
    }
    return _UnifiedHunk(
      oldStart: int.parse(match.group(1)!),
      oldCount: int.tryParse(match.group(2) ?? '1') ?? 1,
      newStart: int.parse(match.group(3)!),
      newCount: int.tryParse(match.group(4) ?? '1') ?? 1,
      lines: const [],
    );
  }

  String _applyFilePatch(_UnifiedFilePatch filePatch, String originalText) {
    final originalLines = _splitPatchText(originalText);
    final output = <String>[];
    var cursor = 0;
    for (final hunk in filePatch.hunks) {
      final start = math.max(hunk.oldStart - 1, 0).toInt();
      if (start < cursor || start > originalLines.length) {
        throw _ActionRunnerFailure(
          'Patch hunk for ${filePatch.displayPath} does not match current file position.',
          failureKind: ActionFailureKind.processFailed,
          recoveryActions: const ['Read the current file and regenerate a smaller patch.'],
        );
      }
      output.addAll(originalLines.sublist(cursor, start));
      cursor = start;
      for (final line in hunk.lines) {
        final op = line[0];
        final text = line.substring(1);
        if (op == ' ') {
          _expectPatchLine(filePatch, originalLines, cursor, text);
          output.add(text);
          cursor++;
        } else if (op == '-') {
          _expectPatchLine(filePatch, originalLines, cursor, text);
          cursor++;
        } else if (op == '+') {
          output.add(text);
        }
      }
    }
    output.addAll(originalLines.sublist(cursor));
    return output.join('\n');
  }

  List<String> _splitPatchText(String text) {
    if (text.isEmpty) return const [];
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    return lines;
  }

  List<String> _lineDiff(
    String relativePath,
    String before,
    String after, {
    required int maxLines,
  }) {
    final beforeLines = _splitPatchText(before);
    final afterLines = _splitPatchText(after);
    final output = <String>[
      '--- snapshot/$relativePath',
      '+++ workspace/$relativePath',
    ];
    final maxLength = math.max(beforeLines.length, afterLines.length);
    for (var i = 0; i < maxLength && output.length < maxLines; i++) {
      final beforeLine = i < beforeLines.length ? beforeLines[i] : null;
      final afterLine = i < afterLines.length ? afterLines[i] : null;
      if (beforeLine == afterLine) continue;
      if (beforeLine != null) output.add('-$beforeLine');
      if (afterLine != null) output.add('+$afterLine');
    }
    if (output.length >= maxLines) output.add('... diff truncated ...');
    return output;
  }

  void _expectPatchLine(_UnifiedFilePatch filePatch, List<String> originalLines, int cursor, String expected) {
    if (cursor >= originalLines.length || originalLines[cursor] != expected) {
      throw _ActionRunnerFailure(
        'Patch context mismatch in ${filePatch.displayPath}.',
        failureKind: ActionFailureKind.processFailed,
        recoveryActions: const ['Read the current file and regenerate the patch from the latest content.'],
      );
    }
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

class _UnifiedFilePatch {
  const _UnifiedFilePatch({
    required this.oldPath,
    required this.newPath,
    required this.hunks,
  });

  final String oldPath;
  final String newPath;
  final List<_UnifiedHunk> hunks;

  String get targetPath => newPath.isNotEmpty ? newPath : oldPath;
  String get displayPath => targetPath.isEmpty ? oldPath : targetPath;
  bool get isDelete => newPath.isEmpty && oldPath.isNotEmpty;
}

class _UnifiedHunk {
  const _UnifiedHunk({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.lines,
  });

  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final List<String> lines;

  _UnifiedHunk copyWith({List<String>? lines}) {
    return _UnifiedHunk(
      oldStart: oldStart,
      oldCount: oldCount,
      newStart: newStart,
      newCount: newCount,
      lines: lines ?? this.lines,
    );
  }
}
