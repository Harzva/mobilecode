import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

const _defaultBaseUrl = 'https://token-plan-cn.xiaomimimo.com/anthropic';
const _defaultModel = 'mimo-v2.5-pro';
const _managedProviderEnabled = bool.fromEnvironment('MOBILECODE_MANAGED_PROVIDER');
const _managedBaseUrl = String.fromEnvironment(
  'MOBILECODE_MANAGED_BASE_URL',
  defaultValue: _defaultBaseUrl,
);
const _managedModel = String.fromEnvironment(
  'MOBILECODE_MANAGED_MODEL',
  defaultValue: _defaultModel,
);
const _managedApiKey = String.fromEnvironment('MOBILECODE_MANAGED_API_KEY');

const _baseUrlKey = 'mobilecode.baseUrl';
const _apiKeyKey = 'mobilecode.apiKey';
const _modelKey = 'mobilecode.model';
const _providerModeKey = 'mobilecode.providerMode';

const _allowedLanguages = {'Dart', 'Python', 'JavaScript', 'TypeScript', 'Go'};

const repoIntentPolishSystemPrompt = '''
You polish a short repository creation intent into a GitHub repository draft.

Return only valid JSON with this exact shape:
{
  "name": "kebab-case-repo-name",
  "description": "one concise GitHub repository description",
  "language": "Dart|Python|JavaScript|TypeScript|Go",
  "private": false,
  "addReadme": true
}

Rules:
- name must be lowercase kebab-case, GitHub-safe, max 64 chars.
- description must be one sentence, max 140 chars.
- choose the closest language from the allowed list only.
- infer private=true only if the user says private/internal/team-only.
- addReadme should normally be true for initialized mobile projects.
- do not include markdown fences, explanations, or extra keys.
''';

enum _RepoProviderFlavor { openAi, anthropic }

class RepoIntentDraft {
  const RepoIntentDraft({
    required this.name,
    required this.description,
    required this.language,
    required this.isPrivate,
    required this.addReadme,
    required this.source,
    this.fallbackReason,
  });

  final String name;
  final String description;
  final String language;
  final bool isPrivate;
  final bool addReadme;
  final String source;
  final String? fallbackReason;

  bool get usedProvider => source == 'provider';

  RepoIntentDraft copyWith({
    String? name,
    String? description,
    String? language,
    bool? isPrivate,
    bool? addReadme,
    String? source,
    String? fallbackReason,
  }) {
    return RepoIntentDraft(
      name: name ?? this.name,
      description: description ?? this.description,
      language: language ?? this.language,
      isPrivate: isPrivate ?? this.isPrivate,
      addReadme: addReadme ?? this.addReadme,
      source: source ?? this.source,
      fallbackReason: fallbackReason ?? this.fallbackReason,
    );
  }
}

class RepoIntentPolishService {
  Future<RepoIntentDraft> polish(String intent) async {
    final fallback = fallbackDraft(intent);
    final config = await _loadProviderConfig();
    if (config == null) {
      return fallback.copyWith(fallbackReason: 'Provider is not configured.');
    }

    final flavor = _detectFlavor(config.baseUrl, config.model);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .postUrl(flavor == _RepoProviderFlavor.anthropic ? _anthropicMessagesUri(config.baseUrl) : _openAiChatUri(config.baseUrl))
          .timeout(const Duration(seconds: 10));
      request.headers.contentType = ContentType.json;
      if (flavor == _RepoProviderFlavor.anthropic) {
        request.headers.set('anthropic-version', '2023-06-01');
        request.headers.set('x-api-key', config.apiKey);
      }
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${config.apiKey}');
      request.write(jsonEncode(_requestBody(flavor, config.model, intent)));

      final response = await request.close().timeout(const Duration(seconds: 45));
      final body = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return fallback.copyWith(fallbackReason: 'Provider HTTP ${response.statusCode}.');
      }
      final text = _extractProviderText(body);
      final draft = _parseDraft(text, fallback);
      return draft.copyWith(source: 'provider', fallbackReason: null);
    } on TimeoutException {
      return fallback.copyWith(fallbackReason: 'Provider timed out.');
    } on SocketException catch (error) {
      return fallback.copyWith(fallbackReason: _friendlySocketError(error));
    } on Object catch (error) {
      return fallback.copyWith(fallbackReason: _compact(error.toString(), 120));
    } finally {
      client.close(force: true);
    }
  }

  RepoIntentDraft fallbackDraft(String rawIntent) {
    final intent = rawIntent.trim();
    final normalized = intent.toLowerCase();
    final language = _detectLanguage(normalized);
    final isPrivate = normalized.contains('private') ||
        intent.contains('私有') ||
        intent.contains('内部') ||
        intent.contains('团队');
    return RepoIntentDraft(
      name: _repoNameFromIntent(intent, language),
      description: _repoDescriptionFromIntent(intent, language),
      language: language,
      isPrivate: isPrivate,
      addReadme: true,
      source: 'fallback',
    );
  }

  Future<_RepoProviderConfig?> _loadProviderConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final useManaged = _managedProviderEnabled && prefs.getString(_providerModeKey) != 'custom';
    final baseUrl = useManaged ? _managedBaseUrl : _savedOrDefault(prefs.getString(_baseUrlKey), _defaultBaseUrl);
    final apiKey = useManaged ? _managedApiKey : (prefs.getString(_apiKeyKey) ?? '');
    final model = useManaged ? _managedModel : _savedOrDefault(prefs.getString(_modelKey), _defaultModel);
    if (baseUrl.trim().isEmpty || apiKey.trim().isEmpty) return null;
    return _RepoProviderConfig(
      baseUrl: baseUrl.trim(),
      apiKey: apiKey.trim(),
      model: model.trim(),
    );
  }

  Map<String, dynamic> _requestBody(_RepoProviderFlavor flavor, String model, String intent) {
    final resolvedModel = model.isEmpty ? (flavor == _RepoProviderFlavor.anthropic ? _defaultModel : 'gpt-4o-mini') : model;
    if (flavor == _RepoProviderFlavor.anthropic) {
      return {
        'model': resolvedModel,
        'system': repoIntentPolishSystemPrompt,
        'max_tokens': 500,
        'temperature': 0.2,
        'messages': [
          {'role': 'user', 'content': intent},
        ],
      };
    }
    return {
      'model': resolvedModel,
      'temperature': 0.2,
      'response_format': {'type': 'json_object'},
      'messages': [
        {'role': 'system', 'content': repoIntentPolishSystemPrompt},
        {'role': 'user', 'content': intent},
      ],
    };
  }
}

class _RepoProviderConfig {
  const _RepoProviderConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
}

RepoIntentDraft _parseDraft(String text, RepoIntentDraft fallback) {
  final jsonText = _extractJsonObject(text);
  if (jsonText == null) {
    throw const FormatException('Provider did not return JSON.');
  }
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Provider JSON is not an object.');
  }
  final language = decoded['language']?.toString().trim();
  final safeLanguage = _allowedLanguages.contains(language) ? language! : fallback.language;
  final name = _sanitizeRepoName(decoded['name']?.toString() ?? fallback.name);
  final description = _compact(
    (decoded['description']?.toString().trim().isEmpty ?? true) ? fallback.description : decoded['description'].toString(),
    140,
  );
  return RepoIntentDraft(
    name: name.isEmpty ? fallback.name : name,
    description: description.isEmpty ? fallback.description : description,
    language: safeLanguage,
    isPrivate: decoded['private'] is bool ? decoded['private'] as bool : fallback.isPrivate,
    addReadme: decoded['addReadme'] is bool ? decoded['addReadme'] as bool : fallback.addReadme,
    source: 'provider',
  );
}

String? _extractJsonObject(String text) {
  final trimmed = text.trim();
  final withoutFence = trimmed
      .replaceFirst(RegExp(r'^```(?:json)?', multiLine: true), '')
      .replaceFirst(RegExp(r'```$', multiLine: true), '')
      .trim();
  final start = withoutFence.indexOf('{');
  final end = withoutFence.lastIndexOf('}');
  if (start == -1 || end == -1 || end <= start) return null;
  return withoutFence.substring(start, end + 1);
}

String _extractProviderText(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) return '';
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
  if (content is List) {
    final parts = <String>[];
    for (final item in content) {
      if (item is Map<String, dynamic>) {
        final text = item['text'];
        if (text is String && text.trim().isNotEmpty) parts.add(text.trim());
      }
    }
    return parts.join('\n');
  }
  return '';
}

String _detectLanguage(String normalizedIntent) {
  if (normalizedIntent.contains('flutter') || normalizedIntent.contains('dart')) return 'Dart';
  if (normalizedIntent.contains('typescript') || normalizedIntent.contains('next') || normalizedIntent.contains('react')) {
    return 'TypeScript';
  }
  if (normalizedIntent.contains('python') || normalizedIntent.contains('fastapi') || normalizedIntent.contains('data')) {
    return 'Python';
  }
  if (normalizedIntent.contains('golang') || normalizedIntent.contains(' go ') || normalizedIntent.contains('gin')) return 'Go';
  return 'JavaScript';
}

String _repoNameFromIntent(String intent, String language) {
  final source = intent.isEmpty ? 'mobilecode ${language.toLowerCase()} project' : intent.toLowerCase();
  final matches = RegExp(r'[a-z0-9]+').allMatches(source).map((match) => match.group(0)!).where((part) {
    return !const {'a', 'an', 'the', 'for', 'with', 'and', 'to', 'of', 'app', 'project', 'repo', 'repository'}.contains(part);
  }).take(5).toList();
  final slug = matches.isEmpty ? 'mobilecode-${language.toLowerCase()}-${DateTime.now().millisecondsSinceEpoch % 100000}' : matches.join('-');
  return _sanitizeRepoName(slug);
}

String _repoDescriptionFromIntent(String intent, String language) {
  final trimmed = intent.trim();
  if (trimmed.isEmpty) return 'A $language project initialized from a MobileCode intent.';
  return _compact(trimmed.replaceAll(RegExp(r'\s+'), ' '), 140);
}

String _sanitizeRepoName(String value) {
  final slug = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
  if (slug.length <= 64) return slug;
  return slug.substring(0, 64).replaceAll(RegExp(r'[-.]+$'), '');
}

_RepoProviderFlavor _detectFlavor(String baseUrl, String model) {
  final probe = '$baseUrl $model'.toLowerCase();
  if (probe.contains('anthropic') || probe.contains('claude') || probe.contains('mimo-')) {
    return _RepoProviderFlavor.anthropic;
  }
  return _RepoProviderFlavor.openAi;
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
    throw const FormatException('Invalid URL');
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

String _friendlySocketError(SocketException error) {
  final raw = error.message.trim().isEmpty ? error.toString() : error.message.trim();
  final lower = raw.toLowerCase();
  if (lower.contains('failed host lookup') ||
      lower.contains('no address associated') ||
      lower.contains('temporary failure in name resolution')) {
    return 'Network/DNS issue: the device cannot resolve the provider host.';
  }
  return raw;
}

String _compact(String value, int limit) {
  final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (trimmed.length <= limit) return trimmed;
  return '${trimmed.substring(0, limit - 1)}...';
}
