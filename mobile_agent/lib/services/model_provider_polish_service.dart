import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'token_usage_service.dart';

enum ProviderPolishSource { provider, fallback }

enum _ProviderFlavor { openAi, anthropic }

class SkillPolishDraft {
  const SkillPolishDraft({
    required this.name,
    required this.description,
    required this.tags,
    required this.actions,
    required this.prompts,
  });

  final String name;
  final String description;
  final List<String> tags;
  final List<String> actions;
  final List<String> prompts;

  SkillPolishDraft copyWith({
    String? name,
    String? description,
    List<String>? tags,
    List<String>? actions,
    List<String>? prompts,
  }) {
    return SkillPolishDraft(
      name: name ?? this.name,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      actions: actions ?? this.actions,
      prompts: prompts ?? this.prompts,
    );
  }
}

class SkillPolishResult {
  const SkillPolishResult({
    required this.draft,
    required this.source,
    this.fallbackReason,
  });

  final SkillPolishDraft draft;
  final ProviderPolishSource source;
  final String? fallbackReason;

  bool get usedProvider => source == ProviderPolishSource.provider;
}

class _ProviderConfig {
  const _ProviderConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  final String baseUrl;
  final String apiKey;
  final String model;

  bool get isUsable => baseUrl.trim().isNotEmpty && apiKey.trim().isNotEmpty;
}

class ModelProviderPolishService {
  ModelProviderPolishService._();

  static final instance = ModelProviderPolishService._();

  static const _defaultBaseUrl = 'https://token-plan-cn.xiaomimimo.com/anthropic';
  static const _defaultModel = 'mimo-v2.5-pro';
  static const _managedProviderEnabled = bool.fromEnvironment('MOBILECODE_MANAGED_PROVIDER');
  static const _managedBaseUrl = String.fromEnvironment(
    'MOBILECODE_MANAGED_BASE_URL',
    defaultValue: _defaultBaseUrl,
  );
  static const _managedModel = String.fromEnvironment(
    'MOBILECODE_MANAGED_MODEL',
    defaultValue: _defaultModel,
  );
  static const _managedApiKey = String.fromEnvironment('MOBILECODE_MANAGED_API_KEY');

  static const _baseUrlKey = 'mobilecode.baseUrl';
  static const _apiKeyKey = 'mobilecode.apiKey';
  static const _modelKey = 'mobilecode.model';
  static const _providerModeKey = 'mobilecode.providerMode';

  Future<SkillPolishResult> polishSkillDraft(SkillPolishDraft draft) async {
    final fallback = _fallbackSkillDraft(draft);
    final config = await _loadProviderConfig();
    if (!config.isUsable) {
      return SkillPolishResult(
        draft: fallback,
        source: ProviderPolishSource.fallback,
        fallbackReason: config.baseUrl.trim().isEmpty
            ? 'Provider Base URL is empty.'
            : 'Provider API key is empty.',
      );
    }

    final flavor = _detectFlavor(config.baseUrl, config.model);
    final started = DateTime.now();
    final systemPrompt = _skillPolishSystemPrompt;
    final userPrompt = _skillPolishUserPrompt(draft);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);

    try {
      final request = await client
          .postUrl(flavor == _ProviderFlavor.anthropic
              ? _anthropicMessagesUri(config.baseUrl)
              : _openAiChatUri(config.baseUrl))
          .timeout(const Duration(seconds: 12));
      request.headers.contentType = ContentType.json;
      if (flavor == _ProviderFlavor.anthropic) {
        request.headers.set('anthropic-version', '2023-06-01');
        request.headers.set('x-api-key', config.apiKey);
      }
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${config.apiKey}');
      request.write(jsonEncode(_requestBody(flavor, config.model, systemPrompt, userPrompt)));

      final response = await request.close().timeout(const Duration(seconds: 80));
      final body = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await _recordUsage(
          flavor: flavor,
          model: config.model,
          durationMs: DateTime.now().difference(started).inMilliseconds,
          success: false,
          inputChars: systemPrompt.length + userPrompt.length,
          outputChars: 0,
        );
        return SkillPolishResult(
          draft: fallback,
          source: ProviderPolishSource.fallback,
          fallbackReason: 'Provider HTTP ${response.statusCode}: ${_compact(body, limit: 180)}',
        );
      }

      final text = _extractProviderText(body);
      final providerDraft = _parseProviderDraft(text, fallback);
      await _recordUsage(
        flavor: flavor,
        model: config.model,
        durationMs: DateTime.now().difference(started).inMilliseconds,
        success: true,
        usage: _providerUsageFromBody(flavor, body),
        inputChars: systemPrompt.length + userPrompt.length,
        outputChars: text.length,
      );
      return SkillPolishResult(
        draft: providerDraft,
        source: ProviderPolishSource.provider,
      );
    } on TimeoutException {
      await _recordUsage(
        flavor: flavor,
        model: config.model,
        durationMs: DateTime.now().difference(started).inMilliseconds,
        success: false,
        inputChars: systemPrompt.length + userPrompt.length,
        outputChars: 0,
      );
      return SkillPolishResult(
        draft: fallback,
        source: ProviderPolishSource.fallback,
        fallbackReason: 'Provider timed out while polishing the skill draft.',
      );
    } on SocketException catch (error) {
      await _recordUsage(
        flavor: flavor,
        model: config.model,
        durationMs: DateTime.now().difference(started).inMilliseconds,
        success: false,
        inputChars: systemPrompt.length + userPrompt.length,
        outputChars: 0,
      );
      return SkillPolishResult(
        draft: fallback,
        source: ProviderPolishSource.fallback,
        fallbackReason: 'Network error: ${_friendlySocketError(error)}',
      );
    } on Object catch (error) {
      await _recordUsage(
        flavor: flavor,
        model: config.model,
        durationMs: DateTime.now().difference(started).inMilliseconds,
        success: false,
        inputChars: systemPrompt.length + userPrompt.length,
        outputChars: 0,
      );
      return SkillPolishResult(
        draft: fallback,
        source: ProviderPolishSource.fallback,
        fallbackReason: _compact(error.toString(), limit: 180),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<_ProviderConfig> _loadProviderConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final useManaged = _managedProviderEnabled && prefs.getString(_providerModeKey) != 'custom';
    if (useManaged) {
      return const _ProviderConfig(
        baseUrl: _managedBaseUrl,
        apiKey: _managedApiKey,
        model: _managedModel,
      );
    }
    return _ProviderConfig(
      baseUrl: _savedOrDefault(prefs.getString(_baseUrlKey), _defaultBaseUrl),
      apiKey: prefs.getString(_apiKeyKey) ?? '',
      model: _savedOrDefault(prefs.getString(_modelKey), _defaultModel),
    );
  }

  Map<String, dynamic> _requestBody(
    _ProviderFlavor flavor,
    String model,
    String systemPrompt,
    String userPrompt,
  ) {
    final resolvedModel = model.trim().isEmpty
        ? (flavor == _ProviderFlavor.anthropic ? _defaultModel : 'gpt-4o-mini')
        : model.trim();
    if (flavor == _ProviderFlavor.anthropic) {
      return {
        'model': resolvedModel,
        'system': systemPrompt,
        'max_tokens': 900,
        'temperature': 0.2,
        'messages': [
          {'role': 'user', 'content': userPrompt},
        ],
      };
    }
    return {
      'model': resolvedModel,
      'temperature': 0.2,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
    };
  }

  Future<void> _recordUsage({
    required _ProviderFlavor flavor,
    required String model,
    required int durationMs,
    required bool success,
    TokenUsageSnapshot? usage,
    int inputChars = 0,
    int outputChars = 0,
  }) async {
    try {
      await TokenUsageService.instance.recordCompleted(
        provider: flavor == _ProviderFlavor.anthropic ? 'anthropic' : 'openai',
        model: model,
        endpoint: 'skill_polish',
        durationMs: durationMs,
        success: success,
        usage: usage,
        inputChars: inputChars,
        outputChars: outputChars,
      );
    } catch (_) {
      // Usage telemetry should never block the user-facing polish result.
    }
  }

  SkillPolishDraft _parseProviderDraft(String text, SkillPolishDraft fallback) {
    final decoded = jsonDecode(_stripJsonFence(text));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Provider did not return a JSON object.');
    }
    return SkillPolishDraft(
      name: _nonEmpty(decoded['name'], fallback.name),
      description: _nonEmpty(decoded['description'], fallback.description),
      tags: _stringList(decoded['tags'], fallback.tags),
      actions: _stringList(decoded['actions'], fallback.actions),
      prompts: _stringList(decoded['prompts'], fallback.prompts),
    );
  }

  SkillPolishDraft _fallbackSkillDraft(SkillPolishDraft draft) {
    final rawName = draft.name.trim();
    final rawDescription = draft.description.trim();
    final inferredName = rawName.isNotEmpty
        ? rawName
        : rawDescription.isNotEmpty
            ? '${rawDescription.split(RegExp(r'\s+')).take(5).join(' ')} Skill'
            : 'MobileCode Custom Skill';

    final tags = <String>{...draft.tags, 'custom', 'user-created'};
    final slug = _slugify(inferredName);
    final prompts = draft.prompts.isNotEmpty
        ? draft.prompts
        : ['${slug.isEmpty ? 'custom_skill' : slug}.guidance'];
    final description = rawDescription.isEmpty
        ? 'A user-created MobileCode skill for reusable prompt guidance, guarded actions, and mobile-first coding workflow preferences.'
        : rawDescription.toLowerCase().contains('mobilecode')
            ? rawDescription
            : '$rawDescription\n\nStandardized: Use this skill as reviewed MobileCode guidance. It may add prompt context and structured action labels, but it must not execute code without user confirmation.';

    return SkillPolishDraft(
      name: inferredName,
      description: description,
      tags: tags.toList(),
      actions: draft.actions,
      prompts: prompts,
    );
  }
}

const _skillPolishSystemPrompt = '''
You are MobileCode Skill Standardizer.

Turn a user's rough custom skill idea into a safe, production-ready MobileCode Skill draft.
Return JSON only. Do not include markdown fences.

Schema:
{
  "name": "2-6 words",
  "description": "one concise paragraph explaining what this skill contributes",
  "tags": ["custom", "html", "mobile"],
  "actions": ["optional.structured_action_id"],
  "prompts": ["optional.prompt_gate_id"]
}

Rules:
- This is a local MobileCode skill, not a script runtime.
- Do not invent shell commands, background services, or MCP execution.
- Prefer mobile-first HTML/UI, GitHub Pages, runtime diagnostics, testing, release QA, or repository workflows when relevant.
- Keep action and prompt IDs lowercase snake/dot style, such as html.mobile_review or github.pages_publish.
- If the user intent is vague, keep the skill safe and prompt-oriented.
''';

String _skillPolishUserPrompt(SkillPolishDraft draft) {
  return jsonEncode({
    'name': draft.name,
    'description': draft.description,
    'tags': draft.tags,
    'actions': draft.actions,
    'prompts': draft.prompts,
  });
}

_ProviderFlavor _detectFlavor(String baseUrl, String model) {
  final probe = '$baseUrl $model'.toLowerCase();
  if (probe.contains('anthropic') || probe.contains('claude') || probe.contains('mimo-')) {
    return _ProviderFlavor.anthropic;
  }
  return _ProviderFlavor.openAi;
}

String _normalizedBaseUrl(String baseUrl) {
  return baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
}

String _savedOrDefault(String? value, String fallback) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? fallback : trimmed;
}

Uri _parseBaseUrl(String baseUrl) {
  final uri = Uri.parse(_normalizedBaseUrl(baseUrl));
  if (!uri.hasScheme || uri.host.isEmpty) {
    throw const FormatException('Invalid provider URL');
  }
  return uri;
}

Uri _openAiChatUri(String baseUrl) {
  final normalized = _normalizedBaseUrl(baseUrl);
  final uri = _parseBaseUrl(normalized);
  if (normalized.endsWith('/chat/completions')) return uri;
  return Uri.parse('$normalized/chat/completions');
}

Uri _anthropicMessagesUri(String baseUrl) {
  final normalized = _normalizedBaseUrl(baseUrl);
  final uri = _parseBaseUrl(normalized);
  if (normalized.endsWith('/v1/messages') || normalized.endsWith('/messages')) {
    return uri;
  }
  if (normalized.endsWith('/v1')) {
    return Uri.parse('$normalized/messages');
  }
  return Uri.parse('$normalized/v1/messages');
}

String _extractProviderText(String body) {
  final decoded = jsonDecode(body);
  if (decoded is Map<String, dynamic>) {
    final choices = decoded['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map<String, dynamic>) {
        final message = first['message'];
        if (message is Map<String, dynamic>) {
          final content = message['content'];
          if (content is String && content.trim().isNotEmpty) return content.trim();
        }
        final text = first['text'];
        if (text is String && text.trim().isNotEmpty) return text.trim();
      }
    }
    final content = decoded['content'];
    if (content is List && content.isNotEmpty) {
      final parts = <String>[];
      for (final item in content) {
        if (item is Map<String, dynamic>) {
          final text = item['text'];
          if (text is String && text.trim().isNotEmpty) parts.add(text.trim());
        }
      }
      if (parts.isNotEmpty) return parts.join('\n\n');
    }
  }
  throw const FormatException('Provider returned no text content.');
}

TokenUsageSnapshot _providerUsageFromBody(_ProviderFlavor flavor, String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return flavor == _ProviderFlavor.anthropic
          ? TokenUsageService.parseAnthropicUsage(decoded)
          : TokenUsageService.parseOpenAiUsage(decoded);
    }
  } catch (_) {
    // Providers without usage metadata fall back to local estimation.
  }
  return TokenUsageSnapshot.empty;
}

String _stripJsonFence(String value) {
  var text = value.trim();
  if (text.startsWith('```')) {
    text = text.replaceFirst(RegExp(r'^```(?:json)?\s*', multiLine: true), '');
    text = text.replaceFirst(RegExp(r'\s*```$', multiLine: true), '');
  }
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start >= 0 && end > start) {
    return text.substring(start, end + 1);
  }
  return text;
}

String _nonEmpty(Object? value, String fallback) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? fallback : text;
}

List<String> _stringList(Object? value, List<String> fallback) {
  if (value is List) {
    final list = value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
    if (list.isNotEmpty) return list;
  }
  if (value is String) {
    final list = value
        .split(RegExp(r'[,，\n]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
    if (list.isNotEmpty) return list;
  }
  return fallback;
}

String _slugify(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

String _compact(String value, {int limit = 800}) {
  final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (trimmed.length <= limit) return trimmed;
  return '${trimmed.substring(0, limit)}...';
}

String _friendlySocketError(SocketException error) {
  final raw = error.message.trim().isEmpty ? error.toString() : error.message.trim();
  final lower = raw.toLowerCase();
  if (lower.contains('failed host lookup') ||
      lower.contains('no address associated') ||
      lower.contains('temporary failure in name resolution')) {
    return '$raw. Network/DNS/proxy issue: the device cannot resolve the provider host.';
  }
  return raw;
}
