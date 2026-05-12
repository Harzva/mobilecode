// lib/services/api_manager_service.dart
// API Manager Service - Complete API management with official + custom providers
// Inspired by CCSwitch - clean card-based UI model

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import 'api_service.dart';
import 'secure_storage_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Data Models
// ═══════════════════════════════════════════════════════════════════════════

/// Configuration for a custom API endpoint (OpenAI-compatible).
///
/// Stores all details needed to connect to a third-party API provider
/// such as OpenRouter, Together AI, or a local LLM server.
@immutable
class CustomApiConfig {
  /// Unique identifier (UUID v4)
  final String id;

  /// Display name, e.g. "My OpenRouter"
  final String name;

  /// Base URL, e.g. "https://openrouter.ai/api/v1"
  final String baseUrl;

  /// Encrypted API key
  final String apiKey;

  /// Default model identifier
  final String model;

  /// Optional organization ID
  final String? organization;

  /// Custom headers for requests
  final Map<String, String>? headers;

  /// Creation timestamp
  final DateTime createdAt;

  /// Whether this config is currently active
  bool isActive;

  CustomApiConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.organization,
    this.headers,
    required this.createdAt,
    this.isActive = true,
  });

  /// Create from JSON map (apiKey is expected to be encrypted)
  factory CustomApiConfig.fromJson(Map<String, dynamic> json) {
    return CustomApiConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      baseUrl: json['baseUrl'] as String,
      apiKey: json['apiKey'] as String,
      model: json['model'] as String,
      organization: json['organization'] as String?,
      headers: (json['headers'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, v as String),
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      isActive: json['isActive'] as bool? ?? true,
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'baseUrl': baseUrl,
      'apiKey': apiKey,
      'model': model,
      'organization': organization,
      'headers': headers,
      'createdAt': createdAt.toIso8601String(),
      'isActive': isActive,
    };
  }

  /// Create a copy with specified fields replaced
  CustomApiConfig copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    String? model,
    String? organization,
    Map<String, String>? headers,
    DateTime? createdAt,
    bool? isActive,
  }) {
    return CustomApiConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      organization: organization ?? this.organization,
      headers: headers ?? this.headers,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
    );
  }

  /// Returns a masked API key for display (e.g., "sk-or...9a2b")
  String get maskedApiKey {
    if (apiKey.isEmpty) return '';
    if (apiKey.length <= 8) return '****';
    return '${apiKey.substring(0, min(4, apiKey.length))}...${apiKey.substring(apiKey.length - 4)}';
  }

  /// Returns a masked base URL (hides API keys in URL)
  String get displayUrl {
    try {
      final uri = Uri.parse(baseUrl);
      return '${uri.scheme}://${uri.host}';
    } catch (_) {
      return baseUrl;
    }
  }

  @override
  String toString() => 'CustomApiConfig(id: $id, name: $name, model: $model, active: $isActive)';
}

/// Health status from an API connection test.
@immutable
class ApiHealthStatus {
  final bool isHealthy;
  final int latencyMs;
  final String? error;
  final DateTime checkedAt;

  const ApiHealthStatus({
    required this.isHealthy,
    required this.latencyMs,
    this.error,
    required this.checkedAt,
  });

  factory ApiHealthStatus.healthy(int latencyMs) =>
      ApiHealthStatus(isHealthy: true, latencyMs: latencyMs, checkedAt: DateTime.now());

  factory ApiHealthStatus.unhealthy(String error) =>
      ApiHealthStatus(isHealthy: false, latencyMs: -1, error: error, checkedAt: DateTime.now());

  @override
  String toString() => 'ApiHealthStatus(healthy: $isHealthy, latency: ${latencyMs}ms)';
}

/// Unified API provider descriptor.
@immutable
class ApiProvider {
  final String id;
  final String name;
  final String type; // "official_chatgpt" / "official_gemini" / "custom"
  final String baseUrl;
  final String defaultModel;
  final bool supportsVision;
  final bool supportsStreaming;

  const ApiProvider({
    required this.id,
    required this.name,
    required this.type,
    required this.baseUrl,
    required this.defaultModel,
    this.supportsVision = true,
    this.supportsStreaming = true,
  });

  @override
  String toString() => 'ApiProvider($id, $name, $type)';
}

/// Rate limit tracking for a provider.
@immutable
class RateLimit {
  final int remaining;
  final int limit;
  final DateTime resetAt;

  const RateLimit({
    required this.remaining,
    required this.limit,
    required this.resetAt,
  });

  bool get isExceeded => remaining <= 0;

  Duration get timeUntilReset => resetAt.difference(DateTime.now()).isNegative
      ? Duration.zero
      : resetAt.difference(DateTime.now());

  @override
  String toString() => 'RateLimit($remaining/$limit, reset: $resetAt)';
}

/// Types of AI tasks that can be performed.
enum TaskType {
  codeCompletion,
  codeGeneration,
  imageAnalysis,
  chat,
  embedding,
}

/// Exception thrown when no provider is available for a task.
class NoProviderAvailableException implements Exception {
  final TaskType taskType;
  const NoProviderAvailableException(this.taskType);
  @override
  String toString() => 'NoProviderAvailableException: No provider available for $taskType';
}

/// Exception thrown when all providers fail during failover.
class FailoverExhaustedException implements Exception {
  final TaskType taskType;
  final List<String> attemptedProviders;
  const FailoverExhaustedException(this.taskType, this.attemptedProviders);
  @override
  String toString() => 'FailoverExhaustedException: Tried ${attemptedProviders.length} providers for $taskType';
}

// ═══════════════════════════════════════════════════════════════════════════
// API Manager Service
// ═══════════════════════════════════════════════════════════════════════════

/// API Manager Service
///
/// Manages all API configurations:
/// - Official subscriptions (ChatGPT via OpenAI Auth, Gemini via Google Auth)
/// - Custom API endpoints with user-provided keys
/// - API health checking
/// - Rate limit tracking
/// - Auto-failover between providers
///
/// Inspired by CCSwitch -- clean card-based UI for managing APIs.
///
/// ## Usage
/// ```dart
/// final apiManager = ref.read(apiManagerServiceProvider);
/// await apiManager.initialize();
///
/// // Connect official providers
/// await apiManager.connectChatGPTOfficial(sessionToken: 'sess_...');
///
/// // Add custom API
/// await apiManager.addCustomApi(
///   name: 'OpenRouter',
///   baseUrl: 'https://openrouter.ai/api/v1',
///   apiKey: 'sk-or-...',
///   model: 'gpt-4o',
/// );
///
/// // Use with failover
/// final result = await apiManager.withFailover(
///   TaskType.codeGeneration,
///   (provider) => generateCode(provider),
/// );
/// ```
class ApiManagerService extends ChangeNotifier {
  // ── Dependencies ─────────────────────────────────

  final ApiService _apiService;
  final SecureStorageService _secureStorage;

  // ── Internal State ──────────────────────────────

  bool _initialized = false;

  // Official provider states
  bool _chatGPTOfficialConnected = false;
  String? _chatGPTSessionToken;
  String? _chatGPTAccountHint; // Masked email or username

  bool _geminiOfficialConnected = false;
  String? _geminiApiKey;
  String? _geminiAccountHint;

  // Custom APIs storage
  final Map<String, CustomApiConfig> _customApis = {};

  // Provider priority ordering (IDs from highest to lowest priority)
  final List<String> _providerPriority = [];

  // Rate limit cache: providerId -> RateLimit
  final Map<String, RateLimit> _rateLimits = {};

  // Health status cache: apiId -> ApiHealthStatus
  final Map<String, ApiHealthStatus> _healthCache = {};

  // Auto-failover enabled
  bool _autoFailoverEnabled = true;

  // ── Storage Keys ────────────────────────────────

  static const String _storagePrefix = 'api_mgr_';
  static const String _keyChatGPTConnected = '${_storagePrefix}chatgpt_connected';
  static const String _keyChatGPTToken = '${_storagePrefix}chatgpt_token';
  static const String _keyChatGPTAccount = '${_storagePrefix}chatgpt_account';
  static const String _keyGeminiConnected = '${_storagePrefix}gemini_connected';
  static const String _keyGeminiKey = '${_storagePrefix}gemini_key';
  static const String _keyGeminiAccount = '${_storagePrefix}gemini_account';
  static const String _keyCustomApis = '${_storagePrefix}custom_apis';
  static const String _keyProviderPriority = '${_storagePrefix}provider_priority';
  static const String _keyAutoFailover = '${_storagePrefix}auto_failover';

  // ── Singleton ───────────────────────────────────

  static ApiManagerService? _instance;

  factory ApiManagerService({
    required ApiService apiService,
    required SecureStorageService secureStorage,
  }) {
    _instance ??= ApiManagerService._internal(
      apiService: apiService,
      secureStorage: secureStorage,
    );
    return _instance!;
  }

  ApiManagerService._internal({
    required ApiService apiService,
    required SecureStorageService secureStorage,
  })  : _apiService = apiService,
        _secureStorage = secureStorage;

  static void reset() => _instance = null;

  // ── Initialization ──────────────────────────────

  /// Initialize the service and load persisted state.
  Future<void> initialize() async {
    if (_initialized) return;

    debugPrint('[ApiManager] Initializing...');

    try {
      // Load official provider states
      final chatgptConnected = await _secureStorage.read(_keyChatGPTConnected);
      _chatGPTOfficialConnected = chatgptConnected == 'true';
      if (_chatGPTOfficialConnected) {
        _chatGPTSessionToken = await _secureStorage.read(_keyChatGPTToken);
        _chatGPTAccountHint = await _secureStorage.read(_keyChatGPTAccount);
      }

      final geminiConnected = await _secureStorage.read(_keyGeminiConnected);
      _geminiOfficialConnected = geminiConnected == 'true';
      if (_geminiOfficialConnected) {
        _geminiApiKey = await _secureStorage.read(_keyGeminiKey);
        _geminiAccountHint = await _secureStorage.read(_keyGeminiAccount);
      }

      // Load custom APIs
      await _loadCustomApis();

      // Load provider priority
      final priorityJson = await _secureStorage.read(_keyProviderPriority);
      if (priorityJson != null && priorityJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(priorityJson);
        _providerPriority.clear();
        _providerPriority.addAll(decoded.cast<String>());
      }

      // Build default priority if empty
      if (_providerPriority.isEmpty) {
        _buildDefaultPriority();
      }

      // Load failover setting
      final failoverStr = await _secureStorage.read(_keyAutoFailover);
      _autoFailoverEnabled = failoverStr != 'false';

      _initialized = true;
      debugPrint('[ApiManager] Initialized. Providers: ${availableProviders.length}');
      notifyListeners();
    } catch (e, st) {
      debugPrint('[ApiManager] Initialization error: $e');
      debugPrint(st.toString());
      // Continue with defaults even if loading fails
      _initialized = true;
    }
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('ApiManagerService not initialized. Call initialize() first.');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Official Providers - ChatGPT (OpenAI Auth)
  // ═══════════════════════════════════════════════════════════════════════

  /// Whether ChatGPT Official (OpenAI Auth) is connected.
  bool get isChatGPTOfficialConnected => _chatGPTOfficialConnected;

  /// Masked account info for ChatGPT.
  String? get chatGPTAccountHint => _chatGPTAccountHint;

  /// Connect ChatGPT Official using an OpenAI session token.
  ///
  /// [sessionToken] is the OpenAI session key from web auth flow.
  /// If null, attempts to use a previously stored token.
  Future<bool> connectChatGPTOfficial({String? sessionToken}) async {
    _ensureInitialized();

    try {
      final tokenToUse = sessionToken ?? _chatGPTSessionToken;
      if (tokenToUse == null || tokenToUse.isEmpty) {
        debugPrint('[ApiManager] No ChatGPT session token available');
        return false;
      }

      // Validate the token with a test request
      final isValid = await _validateOpenAIToken(tokenToUse);
      if (!isValid) {
        debugPrint('[ApiManager] ChatGPT session token validation failed');
        return false;
      }

      _chatGPTSessionToken = tokenToUse;
      _chatGPTOfficialConnected = true;

      // Persist state
      await _secureStorage.write(_keyChatGPTConnected, 'true');
      await _secureStorage.write(_keyChatGPTToken, tokenToUse);

      // Extract account hint from token (JWT payload)
      _chatGPTAccountHint = _extractAccountFromToken(tokenToUse);
      if (_chatGPTAccountHint != null) {
        await _secureStorage.write(_keyChatGPTAccount, _chatGPTAccountHint!);
      }

      // Add to priority if not present
      _ensureInPriority('official_chatgpt');

      debugPrint('[ApiManager] ChatGPT Official connected');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[ApiManager] ChatGPT connection error: $e');
      return false;
    }
  }

  /// Disconnect ChatGPT Official and clear stored credentials.
  Future<void> disconnectChatGPTOfficial() async {
    _ensureInitialized();

    _chatGPTOfficialConnected = false;
    _chatGPTSessionToken = null;
    _chatGPTAccountHint = null;

    await _secureStorage.delete(_keyChatGPTConnected);
    await _secureStorage.delete(_keyChatGPTToken);
    await _secureStorage.delete(_keyChatGPTAccount);

    _providerPriority.remove('official_chatgpt');
    await _persistPriority();

    debugPrint('[ApiManager] ChatGPT Official disconnected');
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Official Providers - Gemini (Google Auth)
  // ═══════════════════════════════════════════════════════════════════════

  /// Whether Gemini Official (Google Auth) is connected.
  bool get isGeminiOfficialConnected => _geminiOfficialConnected;

  /// Masked account info for Gemini.
  String? get geminiAccountHint => _geminiAccountHint;

  /// Connect Gemini Official using a Google API key.
  ///
  /// [apiKey] is the Gemini API key from Google AI Studio.
  Future<bool> connectGeminiOfficial({String? apiKey}) async {
    _ensureInitialized();

    try {
      final keyToUse = apiKey ?? _geminiApiKey;
      if (keyToUse == null || keyToUse.isEmpty) {
        debugPrint('[ApiManager] No Gemini API key available');
        return false;
      }

      // Validate with a test request
      final isValid = await _validateGeminiKey(keyToUse);
      if (!isValid) {
        debugPrint('[ApiManager] Gemini API key validation failed');
        return false;
      }

      _geminiApiKey = keyToUse;
      _geminiOfficialConnected = true;

      // Persist state
      await _secureStorage.write(_keyGeminiConnected, 'true');
      await _secureStorage.write(_keyGeminiKey, keyToUse);

      debugPrint('[ApiManager] Gemini Official connected');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[ApiManager] Gemini connection error: $e');
      return false;
    }
  }

  /// Disconnect Gemini Official and clear stored credentials.
  Future<void> disconnectGeminiOfficial() async {
    _ensureInitialized();

    _geminiOfficialConnected = false;
    _geminiApiKey = null;
    _geminiAccountHint = null;

    await _secureStorage.delete(_keyGeminiConnected);
    await _secureStorage.delete(_keyGeminiKey);
    await _secureStorage.delete(_keyGeminiAccount);

    _providerPriority.remove('official_gemini');
    await _persistPriority();

    debugPrint('[ApiManager] Gemini Official disconnected');
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Custom API Endpoints
  // ═══════════════════════════════════════════════════════════════════════

  /// Add a custom API endpoint (OpenAI-compatible).
  ///
  /// [name] - Display name, e.g. "My OpenRouter"
  /// [baseUrl] - API base URL, e.g. "https://openrouter.ai/api/v1"
  /// [apiKey] - The API key (will be encrypted)
  /// [model] - Default model, e.g. "gpt-4o" / "claude-3" / "gemini-pro"
  /// [organization] - Optional org ID
  /// [headers] - Optional custom headers
  Future<void> addCustomApi({
    required String name,
    required String baseUrl,
    required String apiKey,
    required String model,
    String? organization,
    Map<String, String>? headers,
  }) async {
    _ensureInitialized();

    final id = const Uuid().v4();
    final config = CustomApiConfig(
      id: id,
      name: name.trim(),
      baseUrl: baseUrl.trim().replaceAll(RegExp(r'/$'), ''), // Remove trailing slash
      apiKey: apiKey.trim(),
      model: model.trim(),
      organization: organization?.trim(),
      headers: headers,
      createdAt: DateTime.now(),
      isActive: true,
    );

    // Encrypt and store the API key separately for extra security
    final encryptedKey = await _encryptApiKey(apiKey);
    final secureConfig = config.copyWith(apiKey: encryptedKey);

    _customApis[id] = secureConfig;
    await _persistCustomApis();

    // Add to priority list
    _ensureInPriority(id);

    debugPrint('[ApiManager] Added custom API: $name ($id)');
    notifyListeners();
  }

  /// Edit an existing custom API configuration.
  Future<void> updateCustomApi(
    String id, {
    String? name,
    String? baseUrl,
    String? apiKey,
    String? model,
    String? organization,
    Map<String, String>? headers,
  }) async {
    _ensureInitialized();

    final existing = _customApis[id];
    if (existing == null) {
      throw ArgumentError('Custom API with id "$id" not found');
    }

    var newApiKey = existing.apiKey;
    if (apiKey != null && apiKey.isNotEmpty) {
      newApiKey = await _encryptApiKey(apiKey);
    }

    _customApis[id] = existing.copyWith(
      name: name,
      baseUrl: baseUrl?.trim().replaceAll(RegExp(r'/$'), ''),
      apiKey: newApiKey,
      model: model,
      organization: organization,
      headers: headers,
    );

    await _persistCustomApis();

    debugPrint('[ApiManager] Updated custom API: $id');
    notifyListeners();
  }

  /// Delete a custom API configuration.
  Future<void> deleteCustomApi(String id) async {
    _ensureInitialized();

    _customApis.remove(id);
    _rateLimits.remove(id);
    _healthCache.remove(id);
    _providerPriority.remove(id);

    await _persistCustomApis();
    await _persistPriority();

    debugPrint('[ApiManager] Deleted custom API: $id');
    notifyListeners();
  }

  /// Get a single custom API by ID.
  CustomApiConfig? getCustomApi(String id) => _customApis[id];

  /// List all custom API configurations.
  List<CustomApiConfig> getCustomApis() =>
      _customApis.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Toggle active state of a custom API.
  Future<void> toggleCustomApiActive(String id) async {
    final config = _customApis[id];
    if (config == null) return;

    config.isActive = !config.isActive;
    await _persistCustomApis();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Provider Selection & Failover
  // ═══════════════════════════════════════════════════════════════════════

  /// Get all available providers as [ApiProvider] descriptors.
  List<ApiProvider> get availableProviders {
    final providers = <ApiProvider>[];

    if (_chatGPTOfficialConnected) {
      providers.add(const ApiProvider(
        id: 'official_chatgpt',
        name: 'ChatGPT (OpenAI)',
        type: 'official_chatgpt',
        baseUrl: 'https://api.openai.com/v1',
        defaultModel: 'gpt-4o',
        supportsVision: true,
        supportsStreaming: true,
      ));
    }

    if (_geminiOfficialConnected) {
      providers.add(const ApiProvider(
        id: 'official_gemini',
        name: 'Gemini (Google)',
        type: 'official_gemini',
        baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
        defaultModel: 'gemini-2.0-flash',
        supportsVision: true,
        supportsStreaming: true,
      ));
    }

    for (final config in _customApis.values) {
      if (!config.isActive) continue;
      providers.add(ApiProvider(
        id: config.id,
        name: config.name,
        type: 'custom',
        baseUrl: config.baseUrl,
        defaultModel: config.model,
        supportsVision: true,
        supportsStreaming: true,
      ));
    }

    return providers;
  }

  /// Get the best provider for a specific task type.
  ///
  /// Iterates through the priority list and returns the first provider
  /// that supports the given task and is not rate-limited.
  ApiProvider? getProviderForTask(TaskType task) {
    _ensureInitialized();

    final providers = availableProviders;
    if (providers.isEmpty) return null;

    // Sort by priority order
    final sorted = _sortByPriority(providers);

    for (final provider in sorted) {
      if (_isProviderSuitable(provider, task) && !_isRateLimited(provider.id)) {
        return provider;
      }
    }

    // Fallback: return first available provider regardless of rate limit
    return sorted.firstOrNull;
  }

  /// Set the priority order for providers.
  ///
  /// [providerIds] is ordered from highest to lowest priority.
  void setProviderPriority(List<String> providerIds) {
    _ensureInitialized();
    _providerPriority
      ..clear()
      ..addAll(providerIds);
    _persistPriority();
    notifyListeners();
  }

  /// Get current priority ordering.
  List<String> get providerPriority => List.unmodifiable(_providerPriority);

  /// Whether auto-failover is enabled.
  bool get autoFailoverEnabled => _autoFailoverEnabled;

  /// Enable or disable auto-failover.
  Future<void> setAutoFailover(bool enabled) async {
    _autoFailoverEnabled = enabled;
    await _secureStorage.write(_keyAutoFailover, enabled.toString());
    notifyListeners();
  }

  /// Execute an operation with automatic failover between providers.
  ///
  /// If the primary provider fails, tries the next provider in priority order.
  /// Throws [FailoverExhaustedException] if all providers fail.
  Future<T> withFailover<T>(
    TaskType task,
    Future<T> Function(ApiProvider provider) operation,
  ) async {
    _ensureInitialized();

    final providers = _sortByPriority(availableProviders);
    if (providers.isEmpty) {
      throw NoProviderAvailableException(task);
    }

    // If failover disabled, only try the first provider
    final providersToTry = _autoFailoverEnabled
        ? providers.where((p) => _isProviderSuitable(p, task)).toList()
        : providers.where((p) => _isProviderSuitable(p, task)).take(1).toList();

    if (providersToTry.isEmpty) {
      throw NoProviderAvailableException(task);
    }

    final attemptedProviders = <String>[];
    Exception? lastError;

    for (final provider in providersToTry) {
      attemptedProviders.add(provider.id);
      try {
        final result = await operation(provider).timeout(
          const Duration(seconds: 60),
          onTimeout: () => throw TimeoutException('Operation timed out'),
        );
        return result;
      } on Exception catch (e) {
        lastError = e;
        debugPrint('[ApiManager] Provider ${provider.id} failed: $e');
        continue;
      }
    }

    throw FailoverExhaustedException(task, attemptedProviders);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Rate Limit Tracking
  // ═══════════════════════════════════════════════════════════════════════

  /// Update rate limit info for a provider.
  void updateRateLimit(String providerId, RateLimit limit) {
    _rateLimits[providerId] = limit;
    notifyListeners();
  }

  /// Parse and update rate limit from HTTP response headers.
  void updateRateLimitFromHeaders(String providerId, Map<String, dynamic> headers) {
    try {
      final remaining = int.tryParse(headers['x-ratelimit-remaining']?.toString() ?? '');
      final limit = int.tryParse(headers['x-ratelimit-limit']?.toString() ?? '');
      final resetUnix = int.tryParse(headers['x-ratelimit-reset']?.toString() ?? '');

      if (remaining != null && limit != null) {
        final resetAt = resetUnix != null
            ? DateTime.fromMillisecondsSinceEpoch(resetUnix * 1000)
            : DateTime.now().add(const Duration(minutes: 1));
        updateRateLimit(providerId, RateLimit(remaining: remaining, limit: limit, resetAt: resetAt));
      }
    } catch (_) {
      // Silently ignore malformed rate limit headers
    }
  }

  /// Get cached rate limit for a provider.
  RateLimit? getRateLimit(String providerId) => _rateLimits[providerId];

  /// Check if a provider is currently rate limited.
  bool isRateLimited(String providerId) {
    final limit = _rateLimits[providerId];
    if (limit == null) return false;
    if (!limit.isExceeded) return false;
    // Check if reset time has passed
    if (limit.timeUntilReset == Duration.zero) {
      _rateLimits.remove(providerId);
      return false;
    }
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Health Checking
  // ═══════════════════════════════════════════════════════════════════════

  /// Test connection to a specific API.
  ///
  /// [apiId] can be an official provider ID or a custom API ID.
  Future<ApiHealthStatus> testConnection(String apiId) async {
    _ensureInitialized();

    final stopwatch = Stopwatch()..start();

    try {
      if (apiId == 'official_chatgpt') {
        if (!_chatGPTOfficialConnected || _chatGPTSessionToken == null) {
          return ApiHealthStatus.unhealthy('Not connected');
        }
        final valid = await _validateOpenAIToken(_chatGPTSessionToken!);
        stopwatch.stop();
        if (valid) {
          final status = ApiHealthStatus.healthy(stopwatch.elapsedMilliseconds);
          _healthCache[apiId] = status;
          return status;
        }
        return ApiHealthStatus.unhealthy('Token validation failed');
      }

      if (apiId == 'official_gemini') {
        if (!_geminiOfficialConnected || _geminiApiKey == null) {
          return ApiHealthStatus.unhealthy('Not connected');
        }
        final valid = await _validateGeminiKey(_geminiApiKey!);
        stopwatch.stop();
        if (valid) {
          final status = ApiHealthStatus.healthy(stopwatch.elapsedMilliseconds);
          _healthCache[apiId] = status;
          return status;
        }
        return ApiHealthStatus.unhealthy('API key validation failed');
      }

      // Custom API
      final config = _customApis[apiId];
      if (config == null) {
        return ApiHealthStatus.unhealthy('API not found');
      }

      final decryptedKey = await _decryptApiKey(config.apiKey);
      final isHealthy = await _testCustomApi(config.baseUrl, decryptedKey, config.model);
      stopwatch.stop();

      final status = isHealthy
          ? ApiHealthStatus.healthy(stopwatch.elapsedMilliseconds)
          : ApiHealthStatus.unhealthy('Connection test failed');
      _healthCache[apiId] = status;
      return status;
    } catch (e) {
      stopwatch.stop();
      final status = ApiHealthStatus.unhealthy(e.toString());
      _healthCache[apiId] = status;
      return status;
    }
  }

  /// Get cached health status for an API.
  ApiHealthStatus? getCachedHealth(String apiId) => _healthCache[apiId];

  /// Clear all cached health statuses.
  void clearHealthCache() => _healthCache.clear();

  // ═══════════════════════════════════════════════════════════════════════
  // Credential Access (for LLM Service)
  // ═══════════════════════════════════════════════════════════════════════

  /// Get the active credential for a provider.
  ///
  /// Returns a map with 'apiKey', 'baseUrl', and 'model' for the given provider.
  /// Returns null if provider is not available.
  Future<Map<String, String>?> getCredentials(String providerId) async {
    _ensureInitialized();

    if (providerId == 'official_chatgpt') {
      if (!_chatGPTOfficialConnected || _chatGPTSessionToken == null) return null;
      return {
        'apiKey': _chatGPTSessionToken!,
        'baseUrl': 'https://api.openai.com/v1',
        'model': 'gpt-4o',
      };
    }

    if (providerId == 'official_gemini') {
      if (!_geminiOfficialConnected || _geminiApiKey == null) return null;
      return {
        'apiKey': _geminiApiKey!,
        'baseUrl': 'https://generativelanguage.googleapis.com/v1beta',
        'model': 'gemini-2.0-flash',
      };
    }

    final config = _customApis[providerId];
    if (config == null) return null;

    final decryptedKey = await _decryptApiKey(config.apiKey);
    return {
      'apiKey': decryptedKey,
      'baseUrl': config.baseUrl,
      'model': config.model,
      if (config.organization != null) 'organization': config.organization!,
    };
  }

  /// Get all active credentials as a map of providerId -> credentials.
  Future<Map<String, Map<String, String>>> getAllCredentials() async {
    final result = <String, Map<String, String>>{};
    for (final provider in availableProviders) {
      final creds = await getCredentials(provider.id);
      if (creds != null) {
        result[provider.id] = creds;
      }
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Cleanup
  // ═══════════════════════════════════════════════════════════════════════

  /// Disconnect all providers and clear all data.
  Future<void> disconnectAll() async {
    await disconnectChatGPTOfficial();
    await disconnectGeminiOfficial();

    for (final id in List<String>.from(_customApis.keys)) {
      await deleteCustomApi(id);
    }

    _providerPriority.clear();
    _rateLimits.clear();
    _healthCache.clear();

    await _persistPriority();
    notifyListeners();
  }

  @override
  void dispose() {
    _customApis.clear();
    _providerPriority.clear();
    _rateLimits.clear();
    _healthCache.clear();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Private Helpers
  // ═══════════════════════════════════════════════════════════════════════

  // ── Priority Management ─────────────────────────

  void _buildDefaultPriority() {
    _providerPriority.clear();
    if (_chatGPTOfficialConnected) _providerPriority.add('official_chatgpt');
    if (_geminiOfficialConnected) _providerPriority.add('official_gemini');
    _providerPriority.addAll(_customApis.keys.where((id) => _customApis[id]?.isActive ?? false));
  }

  void _ensureInPriority(String providerId) {
    if (!_providerPriority.contains(providerId)) {
      _providerPriority.add(providerId);
      _persistPriority();
    }
  }

  Future<void> _persistPriority() async {
    try {
      await _secureStorage.write(_keyProviderPriority, jsonEncode(_providerPriority));
    } catch (e) {
      debugPrint('[ApiManager] Failed to persist priority: $e');
    }
  }

  List<ApiProvider> _sortByPriority(List<ApiProvider> providers) {
    return providers.toList()..sort((a, b) {
      final aIndex = _providerPriority.indexOf(a.id);
      final bIndex = _providerPriority.indexOf(b.id);
      if (aIndex == -1 && bIndex == -1) return 0;
      if (aIndex == -1) return 1;
      if (bIndex == -1) return -1;
      return aIndex.compareTo(bIndex);
    });
  }

  // ── Provider Suitability ────────────────────────

  bool _isProviderSuitable(ApiProvider provider, TaskType task) {
    switch (task) {
      case TaskType.imageAnalysis:
        return provider.supportsVision;
      case TaskType.codeCompletion:
      case TaskType.codeGeneration:
      case TaskType.chat:
      case TaskType.embedding:
        return true;
    }
  }

  bool _isRateLimited(String providerId) => isRateLimited(providerId);

  // ── API Validation ──────────────────────────────

  Future<bool> _validateOpenAIToken(String token) async {
    try {
      _apiService.setBaseUrl('https://api.openai.com/v1');
      _apiService.setAuthHeader(token);
      final response = await _apiService.get(ApiEndpoints.openAiModels);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _validateGeminiKey(String apiKey) async {
    try {
      final url = '/models?key=$apiKey';
      _apiService.setBaseUrl(ApiEndpoints.geminiBase);
      final response = await _apiService.get(url);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _testCustomApi(String baseUrl, String apiKey, String model) async {
    try {
      _apiService.setBaseUrl(baseUrl);
      _apiService.setAuthHeader(apiKey);
      // Try to get model list or do a minimal completion
      final response = await _apiService.get('/models');
      if (response.statusCode == 200) return true;

      // Fallback: try a minimal chat completion
      final testBody = {
        'model': model,
        'messages': [
          {'role': 'user', 'content': 'Hi'}
        ],
        'max_tokens': 1,
      };
      final chatResponse = await _apiService.post('/chat/completions', data: testBody);
      return chatResponse.statusCode == 200;
    } catch (e) {
      debugPrint('[ApiManager] Custom API test failed: $e');
      return false;
    }
  }

  // ── Encryption ──────────────────────────────────

  Future<String> _encryptApiKey(String apiKey) async {
    // Store in secure storage with a derived key
    final storageKey = 'apikey_enc_${const Uuid().v4()}';
    await _secureStorage.write(storageKey, apiKey);
    return storageKey;
  }

  Future<String> _decryptApiKey(String storageKey) async {
    if (storageKey.startsWith('apikey_enc_')) {
      final decrypted = await _secureStorage.read(storageKey);
      return decrypted ?? '';
    }
    // Legacy: key was not encrypted, return as-is
    return storageKey;
  }

  // ── Persistence ─────────────────────────────────

  Future<void> _loadCustomApis() async {
    try {
      final jsonStr = await _secureStorage.read(_keyCustomApis);
      if (jsonStr == null || jsonStr.isEmpty) return;

      final List<dynamic> decoded = jsonDecode(jsonStr);
      _customApis.clear();
      for (final item in decoded) {
        final config = CustomApiConfig.fromJson(item as Map<String, dynamic>);
        _customApis[config.id] = config;
      }
      debugPrint('[ApiManager] Loaded ${_customApis.length} custom APIs');
    } catch (e) {
      debugPrint('[ApiManager] Failed to load custom APIs: $e');
    }
  }

  Future<void> _persistCustomApis() async {
    try {
      final List<Map<String, dynamic>> configs =
          _customApis.values.map((c) => c.toJson()).toList();
      await _secureStorage.write(_keyCustomApis, jsonEncode(configs));
    } catch (e) {
      debugPrint('[ApiManager] Failed to persist custom APIs: $e');
    }
  }

  // ── Token Parsing ───────────────────────────────

  String? _extractAccountFromToken(String token) {
    try {
      // Try to decode JWT payload
      final parts = token.split('.');
      if (parts.length == 3) {
        var payload = parts[1];
        // Add padding if needed
        while (payload.length % 4 != 0) payload += '=';
        final decoded = utf8.decode(base64Decode(payload));
        final json = jsonDecode(decoded) as Map<String, dynamic>;
        final email = json['email'] as String?;
        final sub = json['sub'] as String?;
        if (email != null) {
          // Mask email: a***@example.com
          final at = email.indexOf('@');
          if (at > 1) {
            return '${email[0]}${'*' * (at - 1)}${email.substring(at)}';
          }
          return email;
        }
        if (sub != null) {
          return '${sub.substring(0, min(4, sub.length))}...';
        }
      }
    } catch (_) {
      // Not a JWT or can't decode
    }
    return null;
  }
}

/// Simple timeout exception for failover operations.
class TimeoutException implements Exception {
  final String message;
  const TimeoutException(this.message);
  @override
  String toString() => 'TimeoutException: $message';
}
