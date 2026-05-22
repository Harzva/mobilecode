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
        MobileCodeAction.writeFile => await _writeFile(schema, startedAt),
        MobileCodeAction.readFile => await _readFile(schema, startedAt),
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
