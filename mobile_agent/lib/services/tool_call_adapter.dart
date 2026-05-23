import 'dart:convert';

import '../core/evidence/action_runner.dart';
import '../core/evidence/evidence_model.dart';

enum ToolChoiceMode {
  auto,
  required,
  none,
}

enum DeepSeekProviderProfileKind {
  none,
  v4Flash,
  v4Pro,
  strictBeta,
  legacyChat,
  legacyReasoner,
  experimentalUnsupported,
  unknown,
}

class ToolCallProviderProfile {
  const ToolCallProviderProfile({
    required this.label,
    required this.deepSeekProfile,
    required this.isDeepSeek,
    required this.isOpenAiCompatible,
    required this.strictTools,
    required this.supportsNativeToolCalls,
  });

  final String label;
  final DeepSeekProviderProfileKind deepSeekProfile;
  final bool isDeepSeek;
  final bool isOpenAiCompatible;
  final bool strictTools;
  final bool supportsNativeToolCalls;

  bool get isDeepSeekV4 =>
      deepSeekProfile == DeepSeekProviderProfileKind.v4Flash ||
      deepSeekProfile == DeepSeekProviderProfileKind.v4Pro;

  bool get isDeepSeekLegacy =>
      deepSeekProfile == DeepSeekProviderProfileKind.legacyChat ||
      deepSeekProfile == DeepSeekProviderProfileKind.legacyReasoner;

  bool get isDeepSeekStrictBeta =>
      deepSeekProfile == DeepSeekProviderProfileKind.strictBeta;

  static ToolCallProviderProfile detect(String baseUrl, String model) {
    final probe = '$baseUrl $model'.toLowerCase();
    final isDeepSeek = probe.contains('deepseek');
    final isOpenAi = probe.contains('openai') || probe.contains('gpt-');
    final betaStrict = isDeepSeek && baseUrl.toLowerCase().contains('/beta');
    final deepSeekProfile = _detectDeepSeekProfile(
      baseUrl: baseUrl,
      model: model,
      isDeepSeek: isDeepSeek,
      betaStrict: betaStrict,
    );
    final unsupportedDeepSeekExperiment =
        deepSeekProfile == DeepSeekProviderProfileKind.experimentalUnsupported;
    return ToolCallProviderProfile(
      label: isDeepSeek
          ? _deepSeekProfileLabel(deepSeekProfile)
          : isOpenAi
              ? 'OpenAI-compatible'
              : 'Generated-only',
      deepSeekProfile: deepSeekProfile,
      isDeepSeek: isDeepSeek,
      isOpenAiCompatible: isDeepSeek || isOpenAi,
      strictTools: betaStrict,
      supportsNativeToolCalls: (isDeepSeek || isOpenAi) && !unsupportedDeepSeekExperiment,
    );
  }

  static DeepSeekProviderProfileKind _detectDeepSeekProfile({
    required String baseUrl,
    required String model,
    required bool isDeepSeek,
    required bool betaStrict,
  }) {
    if (!isDeepSeek) return DeepSeekProviderProfileKind.none;
    final probe = '$baseUrl $model'.toLowerCase();
    if (probe.contains('v3.2-exp') || probe.contains('v3-2-exp')) {
      return DeepSeekProviderProfileKind.experimentalUnsupported;
    }
    if (betaStrict) return DeepSeekProviderProfileKind.strictBeta;
    if (probe.contains('deepseek-v4-flash')) return DeepSeekProviderProfileKind.v4Flash;
    if (probe.contains('deepseek-v4-pro')) return DeepSeekProviderProfileKind.v4Pro;
    if (probe.contains('deepseek-chat')) return DeepSeekProviderProfileKind.legacyChat;
    if (probe.contains('deepseek-reasoner')) return DeepSeekProviderProfileKind.legacyReasoner;
    return DeepSeekProviderProfileKind.unknown;
  }

  static String _deepSeekProfileLabel(DeepSeekProviderProfileKind profile) {
    return switch (profile) {
      DeepSeekProviderProfileKind.v4Flash => 'DeepSeek v4 Flash',
      DeepSeekProviderProfileKind.v4Pro => 'DeepSeek v4 Pro',
      DeepSeekProviderProfileKind.strictBeta => 'DeepSeek Strict Beta',
      DeepSeekProviderProfileKind.legacyChat => 'DeepSeek Legacy Chat',
      DeepSeekProviderProfileKind.legacyReasoner => 'DeepSeek Legacy Reasoner',
      DeepSeekProviderProfileKind.experimentalUnsupported => 'DeepSeek Unsupported Experiment',
      DeepSeekProviderProfileKind.unknown => 'DeepSeek OpenAI-compatible',
      DeepSeekProviderProfileKind.none => 'Generated-only',
    };
  }
}

class ProviderToolCall {
  const ProviderToolCall({
    required this.id,
    required this.name,
    required this.arguments,
    this.index,
  });

  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  final int? index;

  bool get isReportResult => name == 'report_result';
  bool get isSubAgentLiteTool => name == 'agent_open' || name == 'agent_eval' || name == 'agent_close';

  Map<String, dynamic> toProviderJson() {
    return {
      'id': id,
      'type': 'function',
      'function': {
        'name': name,
        'arguments': jsonEncode(arguments),
      },
    };
  }
}

class ProviderToolCallResponse {
  const ProviderToolCallResponse({
    required this.content,
    required this.toolCalls,
    this.finishReason,
    this.reasoningContent,
  });

  final String content;
  final List<ProviderToolCall> toolCalls;
  final String? finishReason;
  final String? reasoningContent;

  bool get hasToolCalls => toolCalls.isNotEmpty;
}

class OpenAiToolCallStreamAssembler {
  final Map<int, _StreamingToolCallBuilder> _builders = {};
  final StringBuffer _contentBuffer = StringBuffer();
  final StringBuffer _reasoningBuffer = StringBuffer();

  String get content => _contentBuffer.toString();

  String get reasoningContent => _reasoningBuffer.toString();

  List<OpenAiStreamingToolCallProgress> get progress {
    final builders = _builders.values.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return builders
        .map((builder) {
          final arguments = builder.arguments.toString();
          return OpenAiStreamingToolCallProgress(
              index: builder.index,
              name: builder.name,
              argumentChars: arguments.length,
              argumentLines: _estimateDraftLineCount(arguments),
              targetPath: _extractDraftTargetPath(arguments),
            );
        })
        .toList();
  }

  void _appendChunkText(
    StringBuffer buffer,
    dynamic value,
  ) {
    if (value is String && value.isNotEmpty) {
      buffer.write(value);
    }
  }

  void addChunk(Map<String, dynamic> decoded) {
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return;
    for (final choice in choices) {
      if (choice is! Map<String, dynamic>) continue;
      final delta = choice['delta'];
      if (delta is Map<String, dynamic>) {
        _appendChunkText(_contentBuffer, delta['content']);
        _appendChunkText(_reasoningBuffer, delta['reasoning_content']);
      }
      final message = choice['message'];
      if (message is Map<String, dynamic>) {
        _appendChunkText(_contentBuffer, message['content']);
        _appendChunkText(_reasoningBuffer, message['reasoning_content']);
      }
      if (delta is! Map<String, dynamic>) continue;
      final toolCalls = delta['tool_calls'];
      if (toolCalls is! List) continue;
      for (final raw in toolCalls) {
        if (raw is! Map<String, dynamic>) continue;
        final index = _intValue(raw['index']) ?? _builders.length;
        final builder = _builders.putIfAbsent(index, () => _StreamingToolCallBuilder(index));
        builder.add(raw);
      }
    }
  }

  List<ProviderToolCall> finish() {
    final calls = _builders.values.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return calls.map((builder) => builder.finish()).whereType<ProviderToolCall>().toList();
  }
}

class OpenAiStreamingToolCallProgress {
  const OpenAiStreamingToolCallProgress({
    required this.index,
    required this.argumentChars,
    required this.argumentLines,
    this.name,
    this.targetPath,
  });

  final int index;
  final String? name;
  final int argumentChars;
  final int argumentLines;
  final String? targetPath;

  String get key => '$index:${name ?? ''}';
}

class _StreamingToolCallBuilder {
  _StreamingToolCallBuilder(this.index);

  final int index;
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();

  void add(Map<String, dynamic> raw) {
    final rawId = raw['id'];
    if (rawId is String && rawId.isNotEmpty) id = rawId;
    final function = raw['function'];
    if (function is Map<String, dynamic>) {
      final rawName = function['name'];
      if (rawName is String && rawName.isNotEmpty) name = rawName;
      final rawArguments = function['arguments'];
      if (rawArguments is String && rawArguments.isNotEmpty) {
        arguments.write(rawArguments);
      }
    }
  }

  ProviderToolCall? finish() {
    final callName = name;
    if (callName == null || callName.isEmpty) return null;
    return ProviderToolCall(
      id: id ?? 'tool_call_$index',
      name: callName,
      arguments: _parseArguments(arguments.toString()),
      index: index,
    );
  }
}

int _estimateDraftLineCount(String arguments) {
  if (arguments.isEmpty) return 0;
  final escapedNewlines = RegExp(r'\\n').allMatches(arguments).length;
  final rawNewlines = arguments.split('\n').length - 1;
  return escapedNewlines + rawNewlines + 1;
}

String? _extractDraftTargetPath(String arguments) {
  if (arguments.isEmpty) return null;
  final directPath = RegExp(r'"(?:path|file_path|filepath|filename|fileName|name)"\s*:\s*"([^"\\]+)"').firstMatch(arguments)?.group(1);
  if (directPath != null && directPath.trim().isNotEmpty) return directPath.trim();
  final patchPath = RegExp(r'\+\+\+\s+(?:b/)?([^\\n"\r]+)').firstMatch(arguments)?.group(1);
  if (patchPath != null && patchPath.trim().isNotEmpty && patchPath.trim() != '/dev/null') {
    return patchPath.trim();
  }
  return null;
}

class OpenAiCompatibleToolCallAdapter {
  OpenAiCompatibleToolCallAdapter({required this.profile});

  final ToolCallProviderProfile profile;

  String get systemInstruction => [
        'When a mobile coding request needs a file or preview, use the provided tools instead of only describing the result.',
        'MobileCode tools may include list_files, find_files, grep_files, project_summary, detect_project_type, change_history, virtual_status, agent_open, agent_eval, agent_close, web_search, fetch_url, write_file, read_file, copy_file, mkdir, delete_file, move_file, save_snapshot, virtual_diff, restore_snapshot, validate_html, validate_json, validate_markdown, apply_patch, preview_html, preview_snapshot, termux_task_start, and report_result; only call tools exposed in the current request.',
        'Use web_search/fetch_url only for public reference gathering. Use preview_snapshot after preview_html when the user asks for a visible product check.',
        'Use project_summary/detect_project_type/list_files/find_files instead of shell pwd/tree/ls/find, grep_files instead of shell grep/rg, change_history/virtual_status/save_snapshot/virtual_diff/restore_snapshot instead of shell git status/git log/diff/restore, copy_file instead of shell cp, mkdir instead of shell mkdir, move_file instead of shell mv, delete_file instead of shell rm, validate_html/validate_json/validate_markdown instead of ad-hoc validators, and apply_patch instead of shell patch/git apply. termux_task_start is a typed helper route only when exposed; never ask for raw Android or Termux shell commands.',
        'Never request shell, Git push, publishing, remote logging, or arbitrary commands.',
        'Use paths relative to the MobileCode workspace. If writing one web artifact and no path is obvious, use index.html. Do not include secrets in arguments.',
        'For complex work, choose the smallest safe next tool yourself. You may open read-only Sub-Agent Lite explorer/reviewer sessions for isolated inspection, then agent_eval/agent_close them. You may summarize, list, find, grep, search, fetch, write, read, copy, mkdir, delete a confirmed workspace file, move, save/restore snapshots, inspect virtual diffs, validate HTML, patch, preview, snapshot, or report depending on the current observation.',
        'After tool observations, call report_result or answer with a concise final summary.',
      ].join('\n');

  Map<String, dynamic> buildChatCompletionRequest({
    required String model,
    required String systemPrompt,
    required List<Map<String, dynamic>> messages,
    int maxTokens = 4096,
    bool stream = false,
    ToolChoiceMode toolChoice = ToolChoiceMode.auto,
    List<String>? allowedToolNames,
  }) {
    final tools = toolDefinitions(strict: profile.strictTools, allowedToolNames: allowedToolNames);
    final exposedToolNames = tools
        .map((tool) => (tool['function'] as Map<String, dynamic>)['name'])
        .whereType<String>()
        .join(', ');
    return {
      'model': model,
      'messages': [
        {'role': 'system', 'content': '$systemPrompt\n\n$systemInstruction\n\nCurrently exposed tools: $exposedToolNames.'},
        ...messages,
      ],
      'max_tokens': maxTokens,
      'stream': stream,
      if (stream) 'stream_options': {'include_usage': true},
      'tools': tools,
      // DeepSeek defaults to auto when tools are present. Omitting tool_choice
      // keeps reasoning/tool-call models on the widest compatible request path.
      if (!profile.isDeepSeek) 'tool_choice': toolChoice.name,
    };
  }

  ProviderToolCallResponse parseChatCompletion(Map<String, dynamic> decoded) {
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      return const ProviderToolCallResponse(content: '', toolCalls: []);
    }
    final first = choices.first;
    if (first is! Map<String, dynamic>) {
      return const ProviderToolCallResponse(content: '', toolCalls: []);
    }
    final message = first['message'];
    final finishReason = first['finish_reason'] as String?;
    if (message is! Map<String, dynamic>) {
      return ProviderToolCallResponse(content: '', toolCalls: const [], finishReason: finishReason);
    }

    final content = _messageContent(message['content']);
    final reasoningContent = _messageContent(message['reasoning_content']);
    final rawToolCalls = message['tool_calls'];
    if (rawToolCalls is! List) {
      return ProviderToolCallResponse(
        content: content,
        toolCalls: const [],
        finishReason: finishReason,
        reasoningContent: reasoningContent.isEmpty ? null : reasoningContent,
      );
    }

    final calls = <ProviderToolCall>[];
    for (var i = 0; i < rawToolCalls.length; i++) {
      final raw = rawToolCalls[i];
      if (raw is! Map<String, dynamic>) continue;
      final function = raw['function'];
      if (function is! Map<String, dynamic>) continue;
      final name = function['name'];
      if (name is! String || name.trim().isEmpty) continue;
      calls.add(ProviderToolCall(
        id: raw['id'] as String? ?? 'tool_call_$i',
        name: name.trim(),
        arguments: _parseArguments(function['arguments']),
        index: _intValue(raw['index']) ?? i,
      ));
    }

    return ProviderToolCallResponse(
      content: content,
      toolCalls: calls,
      finishReason: finishReason,
      reasoningContent: reasoningContent.isEmpty ? null : reasoningContent,
    );
  }

  Map<String, dynamic> assistantToolCallMessage(ProviderToolCallResponse response) {
    return {
      'role': 'assistant',
      'content': response.content,
      if (response.reasoningContent != null && response.reasoningContent!.isNotEmpty)
        'reasoning_content': response.reasoningContent,
      'tool_calls': response.toolCalls.map((call) => call.toProviderJson()).toList(),
    };
  }

  ActionSchema? toActionSchema(ProviderToolCall call) {
    final args = call.arguments;
    switch (call.name) {
      case 'list_files':
        return ActionSchema(
          actionName: MobileCodeAction.listFiles,
          requestId: call.id,
          paramsSummary: 'provider-native list_files',
          params: {
            'path': _stringArg(args, 'path'),
            'recursive': _boolArg(args, 'recursive', defaultValue: false),
            'maxEntries': _intArg(args, 'max_entries', defaultValue: 80),
          },
        );
      case 'find_files':
        return ActionSchema(
          actionName: MobileCodeAction.findFiles,
          requestId: call.id,
          paramsSummary: 'provider-native find_files',
          params: {
            'pattern': _stringArg(args, 'pattern'),
            'path': _stringArg(args, 'path'),
            'maxResults': _intArg(args, 'max_results', defaultValue: 80),
          },
        );
      case 'grep_files':
        return ActionSchema(
          actionName: MobileCodeAction.grepFiles,
          requestId: call.id,
          paramsSummary: 'provider-native grep_files',
          params: {
            'query': _stringArg(args, 'query'),
            'path': _stringArg(args, 'path'),
            'includeGlob': _stringArg(args, 'include_glob'),
            'maxResults': _intArg(args, 'max_results', defaultValue: 40),
            'maxBytes': _intArg(args, 'max_bytes', defaultValue: 256 * 1024),
          },
        );
      case 'project_summary':
        return ActionSchema(
          actionName: MobileCodeAction.projectSummary,
          requestId: call.id,
          paramsSummary: 'provider-native project_summary',
          params: {
            'path': _stringArg(args, 'path'),
            'maxDepth': _intArg(args, 'max_depth', defaultValue: 3),
            'maxFiles': _intArg(args, 'max_files', defaultValue: 80),
          },
        );
      case 'detect_project_type':
        return ActionSchema(
          actionName: MobileCodeAction.detectProjectType,
          requestId: call.id,
          paramsSummary: 'provider-native detect_project_type',
          params: {
            'path': _stringArg(args, 'path'),
            'maxDepth': _intArg(args, 'max_depth', defaultValue: 4),
            'maxFiles': _intArg(args, 'max_files', defaultValue: 120),
          },
        );
      case 'change_history':
        return ActionSchema(
          actionName: MobileCodeAction.changeHistory,
          requestId: call.id,
          paramsSummary: 'provider-native change_history',
          params: {
            'count': _intArg(args, 'count', defaultValue: 20),
            'includeReadOnly': _boolArg(args, 'include_read_only', defaultValue: false),
            'actionFilter': _stringArg(args, 'action_filter'),
          },
        );
      case 'virtual_status':
        return ActionSchema(
          actionName: MobileCodeAction.virtualStatus,
          requestId: call.id,
          paramsSummary: 'provider-native virtual_status',
          params: {
            'path': _stringArg(args, 'path'),
            'maxFiles': _intArg(args, 'max_files', defaultValue: 80),
            'maxRecent': _intArg(args, 'max_recent', defaultValue: 12),
          },
        );
      case 'write_file':
        final content = _stringArgAny(args, const ['content', 'html', 'body']);
        final path = _safeWritePath(args, content);
        final repairNotes = [
          _stringArg(args, '_adapterArgumentRepair'),
          _writePathRepairNote(args, path),
        ].where((note) => note.isNotEmpty).toList();
        return ActionSchema(
          actionName: MobileCodeAction.writeFile,
          requestId: call.id,
          paramsSummary: repairNotes.isEmpty
              ? 'provider-native write_file'
              : 'provider-native write_file; adapter repaired ${repairNotes.join('; ')}',
          params: {
            'path': path,
            'content': content,
            'overwrite': _boolArg(args, 'overwrite', defaultValue: true),
            if (repairNotes.isNotEmpty) 'adapterRepair': repairNotes.join('; '),
          },
        );
      case 'read_file':
        return ActionSchema(
          actionName: MobileCodeAction.readFile,
          requestId: call.id,
          paramsSummary: 'provider-native read_file',
          params: {
            'path': _stringArg(args, 'path'),
            'maxBytes': _intArg(args, 'max_bytes', defaultValue: 200 * 1024),
          },
        );
      case 'copy_file':
        return ActionSchema(
          actionName: MobileCodeAction.copyFile,
          requestId: call.id,
          paramsSummary: 'provider-native copy_file',
          params: {
            'sourcePath': _stringArg(args, 'source_path'),
            'destinationPath': _stringArg(args, 'destination_path'),
            'overwrite': _boolArg(args, 'overwrite', defaultValue: false),
          },
        );
      case 'mkdir':
        return ActionSchema(
          actionName: MobileCodeAction.makeDirectory,
          requestId: call.id,
          paramsSummary: 'provider-native mkdir',
          params: {
            'path': _stringArg(args, 'path'),
            'recursive': _boolArg(args, 'recursive', defaultValue: true),
          },
        );
      case 'delete_file':
        return ActionSchema(
          actionName: MobileCodeAction.deleteFile,
          requestId: call.id,
          paramsSummary: 'provider-native delete_file',
          params: {
            'path': _stringArg(args, 'path'),
            'confirm': _boolArg(args, 'confirm', defaultValue: false),
          },
        );
      case 'move_file':
        return ActionSchema(
          actionName: MobileCodeAction.moveFile,
          requestId: call.id,
          paramsSummary: 'provider-native move_file',
          params: {
            'sourcePath': _stringArg(args, 'source_path'),
            'destinationPath': _stringArg(args, 'destination_path'),
            'overwrite': _boolArg(args, 'overwrite', defaultValue: false),
          },
        );
      case 'save_snapshot':
        return ActionSchema(
          actionName: MobileCodeAction.saveSnapshot,
          requestId: call.id,
          paramsSummary: 'provider-native save_snapshot',
          params: {
            'path': _stringArg(args, 'path'),
            'label': _stringArg(args, 'label'),
            'maxFiles': _intArg(args, 'max_files', defaultValue: 80),
            'maxBytes': _intArg(args, 'max_bytes', defaultValue: 1024 * 1024),
          },
        );
      case 'virtual_diff':
        return ActionSchema(
          actionName: MobileCodeAction.virtualDiff,
          requestId: call.id,
          paramsSummary: 'provider-native virtual_diff',
          params: {
            'path': _stringArg(args, 'path'),
            'snapshotId': _stringArg(args, 'snapshot_id'),
            'snapshotPath': _stringArg(args, 'snapshot_path'),
            'maxBytes': _intArg(args, 'max_bytes', defaultValue: 256 * 1024),
          },
        );
      case 'restore_snapshot':
        return ActionSchema(
          actionName: MobileCodeAction.restoreSnapshot,
          requestId: call.id,
          paramsSummary: 'provider-native restore_snapshot',
          params: {
            'path': _stringArg(args, 'path'),
            'snapshotId': _stringArg(args, 'snapshot_id'),
            'snapshotPath': _stringArg(args, 'snapshot_path'),
            'confirm': _boolArg(args, 'confirm', defaultValue: false),
            'maxFiles': _intArg(args, 'max_files', defaultValue: 40),
            'maxBytes': _intArg(args, 'max_bytes', defaultValue: 1024 * 1024),
          },
        );
      case 'validate_html':
        return ActionSchema(
          actionName: MobileCodeAction.validateHtml,
          requestId: call.id,
          paramsSummary: 'provider-native validate_html',
          params: {
            'path': _stringArg(args, 'path'),
            'html': _stringArg(args, 'html'),
            'maxBytes': _intArg(args, 'max_bytes', defaultValue: 256 * 1024),
          },
        );
      case 'validate_json':
        return ActionSchema(
          actionName: MobileCodeAction.validateJson,
          requestId: call.id,
          paramsSummary: 'provider-native validate_json',
          params: {
            'path': _stringArg(args, 'path'),
            'json': _stringArg(args, 'json'),
            'maxBytes': _intArg(args, 'max_bytes', defaultValue: 256 * 1024),
          },
        );
      case 'validate_markdown':
        return ActionSchema(
          actionName: MobileCodeAction.validateMarkdown,
          requestId: call.id,
          paramsSummary: 'provider-native validate_markdown',
          params: {
            'path': _stringArg(args, 'path'),
            'markdown': _stringArg(args, 'markdown'),
            'maxBytes': _intArg(args, 'max_bytes', defaultValue: 256 * 1024),
          },
        );
      case 'apply_patch':
        return ActionSchema(
          actionName: MobileCodeAction.applyPatch,
          requestId: call.id,
          paramsSummary: 'provider-native apply_patch',
          params: {
            'patch': _stringArg(args, 'patch'),
            'reason': _stringArg(args, 'reason'),
          },
        );
      case 'preview_html':
        return ActionSchema(
          actionName: MobileCodeAction.previewHtml,
          requestId: call.id,
          paramsSummary: 'provider-native preview_html',
          params: {
            'path': _stringArg(args, 'path'),
            'html': _stringArg(args, 'html'),
          },
        );
      case 'web_search':
        return ActionSchema(
          actionName: MobileCodeAction.webSearch,
          requestId: call.id,
          paramsSummary: 'provider-native web_search',
          params: {
            'query': _stringArg(args, 'query'),
            'count': _intArg(args, 'count', defaultValue: 5),
          },
        );
      case 'fetch_url':
        return ActionSchema(
          actionName: MobileCodeAction.fetchUrl,
          requestId: call.id,
          paramsSummary: 'provider-native fetch_url',
          params: {
            'url': _stringArg(args, 'url'),
            'maxBytes': _intArg(args, 'max_bytes', defaultValue: 80 * 1024),
          },
        );
      case 'preview_snapshot':
        return ActionSchema(
          actionName: MobileCodeAction.previewSnapshot,
          requestId: call.id,
          paramsSummary: 'provider-native preview_snapshot',
          params: {
            'path': _stringArg(args, 'path'),
            'url': _stringArg(args, 'url'),
            'html': _stringArg(args, 'html'),
            'viewportWidth': _intArg(args, 'viewport_width', defaultValue: 390),
            'viewportHeight': _intArg(args, 'viewport_height', defaultValue: 844),
          },
        );
      case 'termux_task_start':
        return ActionSchema(
          actionName: MobileCodeAction.termuxTaskStart,
          requestId: call.id,
          paramsSummary: 'provider-native termux_task_start',
          params: {
            'taskKind': _stringArg(args, 'task_kind'),
            'path': _stringArg(args, 'path'),
            'argsJson': _stringArg(args, 'args_json'),
            'timeoutMs': _intArg(args, 'timeout_ms', defaultValue: 30000),
            'maxOutputBytes': _intArg(args, 'max_output_bytes', defaultValue: 32 * 1024),
            'reason': _stringArg(args, 'reason'),
          },
        );
      default:
        return null;
    }
  }

  Map<String, dynamic> buildToolResultMessage(
    ProviderToolCall call,
    ActionRunnerResult result,
    {String? observationHint}
  ) {
    final payload = _actionResultPayload(result);
    if (observationHint != null && observationHint.trim().isNotEmpty) {
      payload['observationHint'] = observationHint.trim();
    }
    return {
      'role': 'tool',
      'tool_call_id': call.id,
      'content': jsonEncode(payload),
    };
  }

  Map<String, dynamic> buildReportResultToolMessage(ProviderToolCall call) {
    return {
      'role': 'tool',
      'tool_call_id': call.id,
      'content': jsonEncode({
        'success': true,
        'message': 'Final report accepted by MobileCode.',
      }),
    };
  }

  String reportResultText(ProviderToolCall call) {
    final status = _stringArg(call.arguments, 'status');
    final summary = _stringArg(call.arguments, 'summary');
    final detail = _stringArg(call.arguments, 'detail');
    return [
      if (status.isNotEmpty) 'Status: $status',
      if (summary.isNotEmpty) summary,
      if (detail.isNotEmpty) detail,
    ].join('\n\n').trim();
  }

  static List<Map<String, dynamic>> toolDefinitions({
    bool strict = false,
    List<String>? allowedToolNames,
  }) {
    Map<String, dynamic> functionTool({
      required String name,
      required String description,
      required Map<String, dynamic> properties,
      required List<String> required,
    }) {
      return {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          if (strict) 'strict': true,
          'parameters': {
            'type': 'object',
            'properties': properties,
            'required': required,
            'additionalProperties': false,
          },
        },
      };
    }

    final tools = [
      functionTool(
        name: 'list_files',
        description: 'List files inside the MobileCode workspace. Safe replacement for ls; cannot read outside the workspace.',
        properties: const {
          'path': {'type': 'string', 'description': 'Relative workspace directory or file path. Use "." for workspace root.'},
          'recursive': {'type': 'boolean', 'description': 'Whether to list nested files.'},
          'max_entries': {'type': 'integer', 'description': 'Maximum entries to return, 1 to 200.'},
        },
        required: const ['path', 'recursive', 'max_entries'],
      ),
      functionTool(
        name: 'find_files',
        description: 'Find workspace files by name or glob. Safe replacement for find/fd; bounded to the MobileCode workspace.',
        properties: const {
          'pattern': {'type': 'string', 'description': 'Filename, glob, or path fragment such as "*.html" or "index".'},
          'path': {'type': 'string', 'description': 'Relative workspace directory or file path. Use "." for workspace root.'},
          'max_results': {'type': 'integer', 'description': 'Maximum matching entries to return, 1 to 200.'},
        },
        required: const ['pattern', 'path', 'max_results'],
      ),
      functionTool(
        name: 'grep_files',
        description: 'Search text inside workspace files. Safe replacement for grep/rg; bounded results and file sizes.',
        properties: const {
          'query': {'type': 'string', 'description': 'Plain text query to search for.'},
          'path': {'type': 'string', 'description': 'Relative workspace directory or file path. Use "." for workspace root.'},
          'include_glob': {'type': 'string', 'description': 'Optional filename glob such as "*.html"; use "*" for all text files.'},
          'max_results': {'type': 'integer', 'description': 'Maximum match rows to return, 1 to 120.'},
          'max_bytes': {'type': 'integer', 'description': 'Maximum bytes per file to inspect.'},
        },
        required: const ['query', 'path', 'include_glob', 'max_results', 'max_bytes'],
      ),
      functionTool(
        name: 'project_summary',
        description: 'Summarize workspace structure, likely entrypoints, directories, extensions, and file sizes. Safe replacement for pwd/tree/stat before planning.',
        properties: const {
          'path': {'type': 'string', 'description': 'Relative workspace path to summarize. Use "." for workspace root.'},
          'max_depth': {'type': 'integer', 'description': 'Maximum directory depth to inspect, 1 to 6.'},
          'max_files': {'type': 'integer', 'description': 'Maximum files to include in the compact summary.'},
        },
        required: const ['path', 'max_depth', 'max_files'],
      ),
      functionTool(
        name: 'detect_project_type',
        description: 'Detect likely project type and entrypoints from workspace files. Safe replacement for package/project sniffing before planning.',
        properties: const {
          'path': {'type': 'string', 'description': 'Relative workspace path to inspect. Use "." for workspace root.'},
          'max_depth': {'type': 'integer', 'description': 'Maximum directory depth to inspect, 1 to 8.'},
          'max_files': {'type': 'integer', 'description': 'Maximum files to inspect.'},
        },
        required: const ['path', 'max_depth', 'max_files'],
      ),
      functionTool(
        name: 'change_history',
        description: 'Return recent MobileCode action history, including writes, patches, snapshots, restores, failures, and evidence IDs. Safe replacement for git log/status history.',
        properties: const {
          'count': {'type': 'integer', 'description': 'Maximum history records to return, 1 to 80.'},
          'include_read_only': {'type': 'boolean', 'description': 'Whether to include read-only inspection tools as well as writes/failures.'},
          'action_filter': {'type': 'string', 'description': 'Optional MobileCode action enum name to filter, or empty string.'},
        },
        required: const ['count', 'include_read_only', 'action_filter'],
      ),
      functionTool(
        name: 'virtual_status',
        description: 'Summarize workspace status, recent changes, restore points, files, extensions, and evidence IDs without shell or Git.',
        properties: const {
          'path': {'type': 'string', 'description': 'Relative workspace path to summarize. Use "." for workspace root.'},
          'max_files': {'type': 'integer', 'description': 'Maximum files to inspect.'},
          'max_recent': {'type': 'integer', 'description': 'Maximum recent evidence records to summarize.'},
        },
        required: const ['path', 'max_files', 'max_recent'],
      ),
      functionTool(
        name: 'agent_open',
        description: 'Open a read-only background Sub-Agent Lite v2 worker for isolated Explorer or Reviewer inspection. It is not a shell and cannot mutate files.',
        properties: const {
          'role': {'type': 'string', 'description': 'Read-only role: explorer or reviewer.'},
          'task': {'type': 'string', 'description': 'Compact inspection task for the sub-agent.'},
          'path': {'type': 'string', 'description': 'Workspace-relative path to inspect. Use "." for workspace root.'},
          'focus': {'type': 'string', 'description': 'Optional search/focus phrase. Use an empty string when not needed.'},
          'timeout_ms': {'type': 'integer', 'description': 'Worker timeout in milliseconds, 1000 to 30000.'},
          'token_budget': {'type': 'integer', 'description': 'Approximate mailbox token budget, 200 to 4000.'},
        },
        required: const ['role', 'task', 'path', 'focus', 'timeout_ms', 'token_budget'],
      ),
      functionTool(
        name: 'agent_eval',
        description: 'Read mailbox and result summary for an opened Sub-Agent Lite session.',
        properties: const {
          'agent_id': {'type': 'string', 'description': 'Sub-Agent Lite session id returned by agent_open.'},
        },
        required: const ['agent_id'],
      ),
      functionTool(
        name: 'agent_close',
        description: 'Close a Sub-Agent Lite session and keep its mailbox/evidence for the parent AgentLoop.',
        properties: const {
          'agent_id': {'type': 'string', 'description': 'Sub-Agent Lite session id returned by agent_open.'},
          'reason': {'type': 'string', 'description': 'Short close/cancel reason.'},
        },
        required: const ['agent_id', 'reason'],
      ),
      functionTool(
        name: 'web_search',
        description: 'Search public web references through the MobileCode managed relay. Read-only; returns compact results with ref IDs.',
        properties: const {
          'query': {'type': 'string', 'description': 'Search query for public reference material.'},
          'count': {'type': 'integer', 'description': 'Maximum number of compact results to return, 1 to 5.'},
        },
        required: const ['query', 'count'],
      ),
      functionTool(
        name: 'fetch_url',
        description: 'Fetch and summarize a public https URL through the MobileCode managed relay. Blocks local/private URLs.',
        properties: const {
          'url': {'type': 'string', 'description': 'Public https URL to read.'},
          'max_bytes': {'type': 'integer', 'description': 'Maximum response bytes to keep, capped by MobileCode.'},
        },
        required: const ['url', 'max_bytes'],
      ),
      functionTool(
        name: 'write_file',
        description: 'Write a file inside the MobileCode workspace. This cannot write outside the app workspace.',
        properties: const {
          'path': {'type': 'string', 'description': 'Relative file path inside the MobileCode workspace.'},
          'content': {'type': 'string', 'description': 'Complete file content to write.'},
          'overwrite': {'type': 'boolean', 'description': 'Whether an existing file may be replaced.'},
        },
        required: const ['path', 'content', 'overwrite'],
      ),
      functionTool(
        name: 'read_file',
        description: 'Read a file inside the MobileCode workspace and return a bounded text preview.',
        properties: const {
          'path': {'type': 'string', 'description': 'Relative file path inside the MobileCode workspace.'},
          'max_bytes': {'type': 'integer', 'description': 'Maximum bytes to read.'},
        },
        required: const ['path', 'max_bytes'],
      ),
      functionTool(
        name: 'copy_file',
        description: 'Copy one regular file inside the MobileCode workspace. Safe replacement for cp; directories and outside-workspace paths are blocked.',
        properties: const {
          'source_path': {'type': 'string', 'description': 'Existing relative file path inside the MobileCode workspace.'},
          'destination_path': {'type': 'string', 'description': 'Target relative file path inside the MobileCode workspace, including filename.'},
          'overwrite': {'type': 'boolean', 'description': 'Whether an existing destination file may be replaced.'},
        },
        required: const ['source_path', 'destination_path', 'overwrite'],
      ),
      functionTool(
        name: 'mkdir',
        description: 'Create a directory inside the MobileCode workspace. Safe replacement for mkdir -p; outside-workspace paths are blocked.',
        properties: const {
          'path': {'type': 'string', 'description': 'Relative directory path inside the MobileCode workspace.'},
          'recursive': {'type': 'boolean', 'description': 'Whether to create missing parent directories.'},
        },
        required: const ['path', 'recursive'],
      ),
      functionTool(
        name: 'delete_file',
        description: 'Delete one regular workspace file after explicit confirmation. Guarded replacement for rm; saves a pre-delete snapshot.',
        properties: const {
          'path': {'type': 'string', 'description': 'Relative regular file path inside the MobileCode workspace.'},
          'confirm': {'type': 'boolean', 'description': 'Must be true when the user explicitly requested deletion.'},
        },
        required: const ['path', 'confirm'],
      ),
      functionTool(
        name: 'move_file',
        description: 'Move or rename one file inside the MobileCode workspace. Safe replacement for mv; directories and outside-workspace paths are blocked.',
        properties: const {
          'source_path': {'type': 'string', 'description': 'Existing relative file path inside the MobileCode workspace.'},
          'destination_path': {'type': 'string', 'description': 'Target relative file path inside the MobileCode workspace, including filename.'},
          'overwrite': {'type': 'boolean', 'description': 'Whether an existing destination file may be replaced.'},
        },
        required: const ['source_path', 'destination_path', 'overwrite'],
      ),
      functionTool(
        name: 'save_snapshot',
        description: 'Save a bounded read-only snapshot of a workspace file or directory before risky changes. This does not run git or shell.',
        properties: const {
          'path': {'type': 'string', 'description': 'Relative workspace path to snapshot. Use "." for workspace root.'},
          'label': {'type': 'string', 'description': 'Short user-facing snapshot label.'},
          'max_files': {'type': 'integer', 'description': 'Maximum files to copy into the snapshot, 1 to 200.'},
          'max_bytes': {'type': 'integer', 'description': 'Maximum total bytes to snapshot.'},
        },
        required: const ['path', 'label', 'max_files', 'max_bytes'],
      ),
      functionTool(
        name: 'virtual_diff',
        description: 'Compare current workspace files against a MobileCode snapshot. Safe replacement for diff/git diff; read-only.',
        properties: const {
          'path': {'type': 'string', 'description': 'Relative workspace path to compare. Use "." for workspace root.'},
          'snapshot_id': {'type': 'string', 'description': 'Snapshot ID returned by save_snapshot, or empty when snapshot_path is used.'},
          'snapshot_path': {'type': 'string', 'description': 'Workspace-relative snapshot directory path, or empty when snapshot_id is used.'},
          'max_bytes': {'type': 'integer', 'description': 'Maximum bytes to inspect while producing the virtual diff.'},
        },
        required: const ['path', 'snapshot_id', 'snapshot_path', 'max_bytes'],
      ),
      functionTool(
        name: 'restore_snapshot',
        description: 'Restore files from a MobileCode snapshot back into the workspace after explicit confirmation. Does not delete files absent from the snapshot.',
        properties: const {
          'path': {'type': 'string', 'description': 'Relative workspace path to restore. Use "." for the whole snapshot root.'},
          'snapshot_id': {'type': 'string', 'description': 'Snapshot ID returned by save_snapshot, or empty when snapshot_path is used.'},
          'snapshot_path': {'type': 'string', 'description': 'Workspace-relative snapshot directory path, or empty when snapshot_id is used.'},
          'confirm': {'type': 'boolean', 'description': 'Must be true only when the user explicitly asked to restore files.'},
          'max_files': {'type': 'integer', 'description': 'Maximum files to restore, 1 to 120.'},
          'max_bytes': {'type': 'integer', 'description': 'Maximum bytes to restore.'},
        },
        required: const ['path', 'snapshot_id', 'snapshot_path', 'confirm', 'max_files', 'max_bytes'],
      ),
      functionTool(
        name: 'validate_html',
        description: 'Validate an HTML file or inline HTML for mobile WebView readiness. Returns compact structural warnings; does not run browser scripts.',
        properties: const {
          'path': {'type': 'string', 'description': 'Relative HTML file path, or empty when html is provided.'},
          'html': {'type': 'string', 'description': 'Inline HTML, or empty when path is provided.'},
          'max_bytes': {'type': 'integer', 'description': 'Maximum bytes to validate.'},
        },
        required: const ['path', 'html', 'max_bytes'],
      ),
      functionTool(
        name: 'validate_json',
        description: 'Validate a workspace JSON file or inline JSON string. Safe replacement for jq/python -m json.tool; returns syntax status and root type.',
        properties: const {
          'path': {'type': 'string', 'description': 'Relative JSON file path, or empty when json is provided.'},
          'json': {'type': 'string', 'description': 'Inline JSON, or empty when path is provided.'},
          'max_bytes': {'type': 'integer', 'description': 'Maximum bytes to validate.'},
        },
        required: const ['path', 'json', 'max_bytes'],
      ),
      functionTool(
        name: 'validate_markdown',
        description: 'Validate a workspace Markdown file or inline Markdown for basic structure and mobile readability. Does not run external markdownlint.',
        properties: const {
          'path': {'type': 'string', 'description': 'Relative Markdown file path, or empty when markdown is provided.'},
          'markdown': {'type': 'string', 'description': 'Inline Markdown, or empty when path is provided.'},
          'max_bytes': {'type': 'integer', 'description': 'Maximum bytes to validate.'},
        },
        required: const ['path', 'markdown', 'max_bytes'],
      ),
      functionTool(
        name: 'apply_patch',
        description: 'Apply a small unified diff patch inside the MobileCode workspace. Safe replacement for patch/git apply; deletion, binary patches, and outside paths are blocked.',
        properties: const {
          'patch': {'type': 'string', 'description': 'Unified diff patch with ---/+++ headers and @@ hunks.'},
          'reason': {'type': 'string', 'description': 'Short reason for applying this patch.'},
        },
        required: const ['patch', 'reason'],
      ),
      functionTool(
        name: 'preview_html',
        description: 'Prepare an HTML preview from an existing workspace path or inline HTML. Use an empty string for the unused field.',
        properties: const {
          'path': {'type': 'string', 'description': 'Relative HTML file path, or an empty string when html is provided.'},
          'html': {'type': 'string', 'description': 'Inline HTML, or an empty string when path is provided.'},
        },
        required: const ['path', 'html'],
      ),
      functionTool(
        name: 'preview_snapshot',
        description: 'Create a lightweight evidence snapshot for a prepared WebView preview. This is metadata/DOM evidence, not a native bitmap screenshot.',
        properties: const {
          'path': {'type': 'string', 'description': 'Relative HTML file path, or an empty string when url/html is provided.'},
          'url': {'type': 'string', 'description': 'Preview URL, or an empty string when path/html is provided.'},
          'html': {'type': 'string', 'description': 'Inline HTML to snapshot, or an empty string when path/url is provided.'},
          'viewport_width': {'type': 'integer', 'description': 'Expected viewport width for the evidence snapshot.'},
          'viewport_height': {'type': 'integer', 'description': 'Expected viewport height for the evidence snapshot.'},
        },
        required: const ['path', 'url', 'html', 'viewport_width', 'viewport_height'],
      ),
      functionTool(
        name: 'termux_task_start',
        description: 'Start a typed Termux/MobileCode Helper task when the helper route is configured. This is not raw shell; only named task kinds are accepted and stdout/stderr are evidence-backed.',
        properties: const {
          'task_kind': {'type': 'string', 'description': 'Typed task kind such as project_check, validate, build_preview, flutter_analyze, flutter_test, or npm_build.'},
          'path': {'type': 'string', 'description': 'Relative workspace path for the task, or "." for workspace root.'},
          'args_json': {'type': 'string', 'description': 'Small JSON object string for typed task options, or "{}". Never pass raw shell.'},
          'timeout_ms': {'type': 'integer', 'description': 'Timeout in milliseconds, 1000 to 120000.'},
          'max_output_bytes': {'type': 'integer', 'description': 'Maximum stdout/stderr bytes to keep in evidence.'},
          'reason': {'type': 'string', 'description': 'Short reason for starting this typed task.'},
        },
        required: const ['task_kind', 'path', 'args_json', 'timeout_ms', 'max_output_bytes', 'reason'],
      ),
      functionTool(
        name: 'report_result',
        description: 'Report the final result after tool observations. This does not execute device, shell, Git, or network actions.',
        properties: const {
          'status': {'type': 'string', 'description': 'One of success, blocked, failed, or partial.'},
          'summary': {'type': 'string', 'description': 'Short user-facing result summary.'},
          'detail': {'type': 'string', 'description': 'Useful details, evidence IDs, file paths, or recovery notes.'},
        },
        required: const ['status', 'summary', 'detail'],
      ),
    ];
    if (allowedToolNames == null) return tools;
    final allowed = allowedToolNames.toSet();
    return tools.where((tool) {
      final function = tool['function'];
      if (function is! Map<String, dynamic>) return false;
      return allowed.contains(function['name']);
    }).toList();
  }

  Map<String, dynamic> _actionResultPayload(ActionRunnerResult result) {
    final evidence = result.evidence;
    return {
      'success': result.success,
      'evidenceId': evidence.evidenceId,
      'actionName': evidence.actionName.name,
      'durationMs': evidence.durationMs,
      'artifactPaths': evidence.artifactPaths,
      'urls': evidence.urls,
      'logs': evidence.logs,
      if (evidence.metadata.isNotEmpty) 'metadata': evidence.metadata,
      if (result.text != null) 'text': _compact(result.text!, 6000),
      if (result.path != null) 'path': result.path,
      if (result.url != null) 'url': result.url,
      if (evidence.failureKind != null) 'failureKind': evidence.failureKind,
      if (evidence.recoveryActions.isNotEmpty) 'recoveryActions': evidence.recoveryActions,
    };
  }
}

enum OpenAiStreamEventKind { ignore, done, payload }

class OpenAiStreamEvent {
  const OpenAiStreamEvent._({
    required this.kind,
    this.payload = '',
  });

  final OpenAiStreamEventKind kind;
  final String payload;

  bool get isIgnore => kind == OpenAiStreamEventKind.ignore;
  bool get isDone => kind == OpenAiStreamEventKind.done;
  bool get hasPayload => kind == OpenAiStreamEventKind.payload;
}

OpenAiStreamEvent parseOpenAiStreamEvent(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty || trimmed.startsWith('event:') || trimmed.startsWith(':')) {
    return const OpenAiStreamEvent._(kind: OpenAiStreamEventKind.ignore);
  }
  if (trimmed == 'data: [DONE]') {
    return const OpenAiStreamEvent._(kind: OpenAiStreamEventKind.done);
  }

  final payload = trimmed.startsWith('data:') ? trimmed.substring(5).trim() : trimmed;
  if (payload.isEmpty) {
    return const OpenAiStreamEvent._(kind: OpenAiStreamEventKind.ignore);
  }
  if (payload == '[DONE]') {
    return const OpenAiStreamEvent._(kind: OpenAiStreamEventKind.done);
  }
  if (payload.startsWith(':')) {
    return const OpenAiStreamEvent._(kind: OpenAiStreamEventKind.ignore);
  }
  return OpenAiStreamEvent._(kind: OpenAiStreamEventKind.payload, payload: payload);
}

String _messageContent(Object? content) {
  if (content is String) return content.trim();
  if (content is List) {
    final parts = <String>[];
    for (final item in content) {
      if (item is Map<String, dynamic>) {
        final text = item['text'];
        if (text is String && text.trim().isNotEmpty) parts.add(text.trim());
      }
    }
    return parts.join('\n\n');
  }
  return '';
}

Map<String, dynamic> _parseArguments(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is String && value.trim().isNotEmpty) {
    final trimmed = value.trim();
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      final repaired = _repairMalformedArguments(trimmed);
      if (repaired.isNotEmpty) return repaired;
      return const {};
    }
  }
  return const {};
}

Map<String, dynamic> _repairMalformedArguments(String raw) {
  final candidates = <String>[
    raw,
    if (!raw.startsWith('{')) '{$raw',
    if (!raw.endsWith('}')) '$raw}',
    if (!raw.startsWith('{') && !raw.endsWith('}')) '{$raw}',
  ];
  for (final candidate in candidates) {
    try {
      final decoded = jsonDecode(candidate);
      if (decoded is Map<String, dynamic>) {
        return {
          ...decoded,
          '_adapterArgumentRepair': 'recovered malformed JSON tool arguments',
        };
      }
      if (decoded is Map) {
        return {
          ...Map<String, dynamic>.from(decoded),
          '_adapterArgumentRepair': 'recovered malformed JSON tool arguments',
        };
      }
    } catch (_) {
      // Try the next repair shape, then fall back to HTML extraction.
    }
  }

  final html = _extractHtmlFromMalformedArguments(raw);
  if (html != null) {
    return {
      'content': html,
      'overwrite': true,
      '_adapterArgumentRepair': 'recovered complete HTML from malformed tool arguments',
    };
  }
  return const {};
}

String? _extractHtmlFromMalformedArguments(String raw) {
  final lower = raw.toLowerCase();
  final doctypeStart = lower.indexOf('<!doctype html');
  final htmlStart = doctypeStart >= 0 ? doctypeStart : lower.indexOf('<html');
  if (htmlStart < 0) return null;
  final htmlEnd = lower.lastIndexOf('</html>');
  if (htmlEnd >= htmlStart) {
    return raw.substring(htmlStart, htmlEnd + '</html>'.length).trim();
  }
  return raw.substring(htmlStart).trim();
}

String _stringArg(Map<String, dynamic> args, String key) {
  final value = args[key];
  return value is String ? value.trim() : '';
}

String _stringArgAny(Map<String, dynamic> args, List<String> keys) {
  for (final key in keys) {
    final value = _stringArg(args, key);
    if (value.isNotEmpty) return value;
  }
  return '';
}

String _firstPresentKey(Map<String, dynamic> args, List<String> keys) {
  for (final key in keys) {
    final value = args[key];
    if (value is String && value.trim().isNotEmpty) return key;
  }
  return '';
}

String _safeWritePath(Map<String, dynamic> args, String content) {
  final explicit = _stringArgAny(args, const [
    'path',
    'file_path',
    'filepath',
    'filename',
    'fileName',
    'name',
  ]);
  if (explicit.isNotEmpty) return explicit;
  final lowerContent = content.toLowerCase();
  if (lowerContent.contains('<!doctype html') || lowerContent.contains('<html')) {
    return 'index.html';
  }
  return '';
}

String _writePathRepairNote(Map<String, dynamic> args, String resolvedPath) {
  if (_stringArg(args, 'path').isNotEmpty) return '';
  final aliasKey = _firstPresentKey(args, const [
    'file_path',
    'filepath',
    'filename',
    'fileName',
    'name',
  ]);
  if (aliasKey.isNotEmpty) return 'normalized path from `$aliasKey`';
  if (resolvedPath == 'index.html') return 'inferred safe workspace path `index.html` for complete HTML';
  return '';
}

bool _boolArg(Map<String, dynamic> args, String key, {required bool defaultValue}) {
  final value = args[key];
  return value is bool ? value : defaultValue;
}

int _intArg(Map<String, dynamic> args, String key, {required int defaultValue}) {
  final value = args[key];
  if (value is int && value > 0) return value;
  if (value is num && value > 0) return value.toInt();
  return defaultValue;
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

String _compact(String value, int limit) {
  final trimmed = value.trim();
  if (trimmed.length <= limit) return trimmed;
  return '${trimmed.substring(0, limit - 1)}...';
}
