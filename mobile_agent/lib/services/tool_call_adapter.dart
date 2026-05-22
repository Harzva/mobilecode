import 'dart:convert';

import '../core/evidence/action_runner.dart';
import '../core/evidence/evidence_model.dart';

enum ToolChoiceMode {
  auto,
  required,
  none,
}

class ToolCallProviderProfile {
  const ToolCallProviderProfile({
    required this.label,
    required this.isDeepSeek,
    required this.isOpenAiCompatible,
    required this.strictTools,
    required this.supportsNativeToolCalls,
  });

  final String label;
  final bool isDeepSeek;
  final bool isOpenAiCompatible;
  final bool strictTools;
  final bool supportsNativeToolCalls;

  static ToolCallProviderProfile detect(String baseUrl, String model) {
    final probe = '$baseUrl $model'.toLowerCase();
    final isDeepSeek = probe.contains('deepseek');
    final isOpenAi = probe.contains('openai') || probe.contains('gpt-');
    final betaStrict = isDeepSeek && baseUrl.toLowerCase().contains('/beta');
    final unsupportedDeepSeekExperiment = probe.contains('v3.2-exp') || probe.contains('v3-2-exp');
    return ToolCallProviderProfile(
      label: isDeepSeek
          ? 'DeepSeek'
          : isOpenAi
              ? 'OpenAI-compatible'
              : 'Generated-only',
      isDeepSeek: isDeepSeek,
      isOpenAiCompatible: isDeepSeek || isOpenAi,
      strictTools: betaStrict,
      supportsNativeToolCalls: (isDeepSeek || isOpenAi) && !unsupportedDeepSeekExperiment,
    );
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

  void addChunk(Map<String, dynamic> decoded) {
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return;
    for (final choice in choices) {
      if (choice is! Map<String, dynamic>) continue;
      final delta = choice['delta'];
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

class OpenAiCompatibleToolCallAdapter {
  OpenAiCompatibleToolCallAdapter({required this.profile});

  final ToolCallProviderProfile profile;

  String get systemInstruction => [
        'When a mobile coding request needs a file or preview, use the provided tools instead of only describing the result.',
        'Allowed tools are web_search, fetch_url, write_file, read_file, preview_html, preview_snapshot, and report_result.',
        'Use web_search/fetch_url only for public reference gathering. Use preview_snapshot after preview_html when the user asks for a visible product check.',
        'Never request shell, Git push, publishing, remote logging, or arbitrary commands.',
        'Use paths relative to the MobileCode workspace. Do not include secrets in arguments.',
        'For complex web demos, choose the smallest safe next tool yourself. You may search, fetch, write, read, preview, snapshot, or report depending on the current observation.',
        'After tool observations, call report_result or answer with a concise final summary.',
      ].join('\n');

  Map<String, dynamic> buildChatCompletionRequest({
    required String model,
    required String systemPrompt,
    required List<Map<String, dynamic>> messages,
    int maxTokens = 4096,
    bool stream = false,
    ToolChoiceMode toolChoice = ToolChoiceMode.auto,
  }) {
    return {
      'model': model,
      'messages': [
        {'role': 'system', 'content': '$systemPrompt\n\n$systemInstruction'},
        ...messages,
      ],
      'max_tokens': maxTokens,
      'stream': stream,
      if (stream) 'stream_options': {'include_usage': true},
      'tools': toolDefinitions(strict: profile.strictTools),
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
      case 'write_file':
        return ActionSchema(
          actionName: MobileCodeAction.writeFile,
          requestId: call.id,
          paramsSummary: 'provider-native write_file',
          params: {
            'path': _stringArg(args, 'path'),
            'content': _stringArg(args, 'content'),
            'overwrite': _boolArg(args, 'overwrite', defaultValue: true),
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
      default:
        return null;
    }
  }

  Map<String, dynamic> buildToolResultMessage(
    ProviderToolCall call,
    ActionRunnerResult result,
  ) {
    return {
      'role': 'tool',
      'tool_call_id': call.id,
      'content': jsonEncode(_actionResultPayload(result)),
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

  static List<Map<String, dynamic>> toolDefinitions({bool strict = false}) {
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

    return [
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
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return const {};
    }
  }
  return const {};
}

String _stringArg(Map<String, dynamic> args, String key) {
  final value = args[key];
  return value is String ? value.trim() : '';
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
