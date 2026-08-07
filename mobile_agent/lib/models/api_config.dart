import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/constants.dart';

/// {@template api_config}
/// Configuration for a LLM (Large Language Model) API provider.
///
/// Stores connection details for AI providers like OpenAI, Claude,
/// Gemini, or custom endpoints. Only one config can be [isActive]
/// at a time.
///
/// ## Usage
/// ```dart
/// final config = ApiConfig.create(
///   provider: 'openai',
///   apiKey: 'sk-...',
///   model: 'gpt-4o',
/// );
/// ```
/// {@endtemplate}
@immutable
class ApiConfig {
  /// Unique identifier for this configuration
  final String id;

  /// Provider name: 'openai', 'claude', 'gemini', 'custom'
  final String provider;

  /// Display name for legacy settings surfaces.
  final String? name;

  /// API authentication key (encrypted in production)
  final String apiKey;

  /// Base URL for API requests
  final String baseUrl;

  /// Model identifier to use (e.g., 'gpt-4o', 'claude-3-sonnet')
  final String model;

  /// Whether this is the currently active configuration
  final bool isActive;

  /// Whether this is the default configuration for new chats.
  final bool isDefault;

  /// Optional generation token limit.
  final int? maxTokens;

  /// Optional generation temperature.
  final double? temperature;

  /// Creation timestamp for legacy settings surfaces.
  final DateTime? createdAt;

  /// Creates an [ApiConfig] with all fields specified.
  const ApiConfig({
    required this.id,
    required this.provider,
    required this.apiKey,
    required this.baseUrl,
    required this.model,
    required this.isActive,
    this.name,
    this.isDefault = false,
    this.maxTokens,
    this.temperature,
    this.createdAt,
  });

  /// Factory for creating a new config with sensible defaults.
  ///
  /// [provider] and [apiKey] are required. Base URL and model
  /// are derived from provider defaults if not specified.
  factory ApiConfig.create({
    required String provider,
    required String apiKey,
    String? baseUrl,
    String? model,
    bool isActive = true,
  }) {
    final resolvedBaseUrl =
        baseUrl ?? AiModels.defaultBaseUrls[provider] ?? '';
    final resolvedModel = model ??
        AiModels.modelsByProvider[provider]?.firstOrNull ??
        '';

    return ApiConfig(
      id: const Uuid().v4(),
      provider: provider,
      apiKey: apiKey,
      baseUrl: resolvedBaseUrl,
      model: resolvedModel,
      isActive: isActive,
      createdAt: DateTime.now(),
    );
  }

  /// Creates an [ApiConfig] from a JSON map.
  factory ApiConfig.fromJson(Map<String, dynamic> json) {
    return ApiConfig(
      id: json['id'] as String,
      provider: json['provider'] as String,
      apiKey: json['apiKey'] as String,
      baseUrl: json['baseUrl'] as String,
      model: json['model'] as String,
      isActive: json['isActive'] as bool? ?? false,
      name: json['name'] as String?,
      isDefault: json['isDefault'] as bool? ?? false,
      maxTokens: json['maxTokens'] as int?,
      temperature: (json['temperature'] as num?)?.toDouble(),
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.tryParse(json['createdAt'] as String),
    );
  }

  /// Converts this config to a JSON map.
  ///
  /// ⚠️ In production, encrypt [apiKey] before persisting.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'provider': provider,
      'apiKey': apiKey,
      'baseUrl': baseUrl,
      'model': model,
      'isActive': isActive,
      'name': name,
      'isDefault': isDefault,
      'maxTokens': maxTokens,
      'temperature': temperature,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  /// Creates a copy with specified fields replaced.
  ApiConfig copyWith({
    String? id,
    String? provider,
    String? apiKey,
    String? baseUrl,
    String? model,
    bool? isActive,
    String? name,
    bool? isDefault,
    int? maxTokens,
    double? temperature,
    DateTime? createdAt,
  }) {
    return ApiConfig(
      id: id ?? this.id,
      provider: provider ?? this.provider,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      isActive: isActive ?? this.isActive,
      name: name ?? this.name,
      isDefault: isDefault ?? this.isDefault,
      maxTokens: maxTokens ?? this.maxTokens,
      temperature: temperature ?? this.temperature,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Returns a copy with [isActive] set to true.
  ApiConfig activate() => copyWith(isActive: true);

  /// Returns a copy with [isActive] set to false.
  ApiConfig deactivate() => copyWith(isActive: false);

  /// Returns true if this is a custom provider configuration.
  bool get isCustom => provider == 'custom';

  /// Returns true for Gemini-compatible providers.
  bool get isGemini => provider == 'gemini' || provider == 'google';

  /// Returns true for Claude-compatible providers.
  bool get isClaude => provider == 'claude' || provider == 'anthropic';

  /// Returns the display-friendly provider name.
  String get providerDisplayName {
    switch (provider) {
      case 'openai':
        return 'OpenAI';
      case 'claude':
        return 'Anthropic Claude';
      case 'gemini':
        return 'Google Gemini';
      case 'custom':
        return 'Custom Provider';
      default:
        return provider;
    }
  }

  /// Returns available models for this provider.
  List<String> get availableModels {
    return AiModels.modelsByProvider[provider] ?? [];
  }

  /// Returns the full API chat completions URL.
  ///
  /// Each provider has a different endpoint path. This method
  /// constructs the appropriate URL for the configured provider.
  String get chatEndpoint {
    switch (provider) {
      case 'openai':
        return '$baseUrl${ApiEndpoints.openAiChat}';
      case 'claude':
        return '$baseUrl${ApiEndpoints.claudeMessages}';
      case 'gemini':
        return '$baseUrl/models/$model:generateContent';
      case 'custom':
        return '$baseUrl/chat/completions';
      default:
        return '$baseUrl/chat/completions';
    }
  }

  /// Returns a masked version of the API key for display.
  ///
  /// Shows only the last 4 characters, e.g., `sk-...abcd`
  String get maskedApiKey {
    if (apiKey.length <= 8) return '****';
    return '${apiKey.substring(0, 3)}...${apiKey.substring(apiKey.length - 4)}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ApiConfig &&
        other.id == id &&
        other.provider == provider &&
        other.apiKey == apiKey &&
        other.baseUrl == baseUrl &&
        other.model == model &&
        other.isActive == isActive;
  }

  @override
  int get hashCode => Object.hash(
        id,
        provider,
        apiKey,
        baseUrl,
        model,
        isActive,
      );

  @override
  String toString() {
    return 'ApiConfig(id: $id, provider: $provider, model: $model, '
        'active: $isActive)';
  }
}
