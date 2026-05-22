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
  })  : workspaceRootPath = p.normalize(p.absolute(workspaceRootPath)),
        evidenceStore = evidenceStore ?? ActionEvidenceStore.shared,
        webToolInvoker = webToolInvoker;

  final String workspaceRootPath;
  final ActionEvidenceStore evidenceStore;
  final ActionRunnerWebToolInvoker? webToolInvoker;

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
        MobileCodeAction.moveFile => await _moveFile(schema, startedAt),
        MobileCodeAction.applyPatch => await _applyPatch(schema, startedAt),
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
          recoveryActions: ['Ask the model to return a standard unified diff.'],
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
        recoveryActions: const ['Use @@ -oldStart,oldCount +newStart,newCount @@ hunk headers.'],
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
