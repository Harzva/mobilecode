// lib/providers/api_manager_provider.dart
// Riverpod Providers for API Management and Feature Flags
// API管理和功能开关的 Riverpod 状态管理

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_manager_service.dart';
import '../services/api_service.dart';
import '../services/feature_flags_service.dart';
import '../services/secure_storage_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Core Service Providers
// ═══════════════════════════════════════════════════════════════════════════

/// Provider for the [ApiService] instance.
///
/// This is typically overridden in the ProviderScope at app startup:
/// ```dart
/// ProviderScope(
///   overrides: [
///     apiServiceProvider.overrideWithValue(myApiService),
///   ],
///   child: MyApp(),
/// )
/// ```
final apiServiceProvider = Provider<ApiService>((ref) {
  final api = ApiService.create();
  ref.onDispose(() => api.dispose());
  return api;
});

/// Provider for the [SecureStorageService] instance.
final secureStorageProvider = Provider<SecureStorageService>((ref) {
  final storage = SecureStorageService();
  ref.onDispose(() => storage.dispose());
  return storage;
});

// ═══════════════════════════════════════════════════════════════════════════
// API Manager Provider
// ═══════════════════════════════════════════════════════════════════════════

/// State class for the API Manager.
///
/// Holds the current state of all API connections for reactive UI updates.
@immutable
class ApiManagerState {
  final bool isInitialized;
  final bool isLoading;
  final bool chatGPTConnected;
  final bool geminiConnected;
  final List<CustomApiConfig> customApis;
  final List<ApiProvider> availableProviders;
  final List<String> providerPriority;
  final bool autoFailoverEnabled;
  final Map<String, ApiHealthStatus> healthStatuses;
  final Map<String, RateLimit> rateLimits;
  final String? error;

  const ApiManagerState({
    this.isInitialized = false,
    this.isLoading = false,
    this.chatGPTConnected = false,
    this.geminiConnected = false,
    this.customApis = const [],
    this.availableProviders = const [],
    this.providerPriority = const [],
    this.autoFailoverEnabled = true,
    this.healthStatuses = const {},
    this.rateLimits = const {},
    this.error,
  });

  ApiManagerState copyWith({
    bool? isInitialized,
    bool? isLoading,
    bool? chatGPTConnected,
    bool? geminiConnected,
    List<CustomApiConfig>? customApis,
    List<ApiProvider>? availableProviders,
    List<String>? providerPriority,
    bool? autoFailoverEnabled,
    Map<String, ApiHealthStatus>? healthStatuses,
    Map<String, RateLimit>? rateLimits,
    String? error,
  }) {
    return ApiManagerState(
      isInitialized: isInitialized ?? this.isInitialized,
      isLoading: isLoading ?? this.isLoading,
      chatGPTConnected: chatGPTConnected ?? this.chatGPTConnected,
      geminiConnected: geminiConnected ?? this.geminiConnected,
      customApis: customApis ?? this.customApis,
      availableProviders: availableProviders ?? this.availableProviders,
      providerPriority: providerPriority ?? this.providerPriority,
      autoFailoverEnabled: autoFailoverEnabled ?? this.autoFailoverEnabled,
      healthStatuses: healthStatuses ?? this.healthStatuses,
      rateLimits: rateLimits ?? this.rateLimits,
      error: error ?? this.error,
    );
  }

  /// Whether any provider is available for use.
  bool get hasAnyProvider =>
      chatGPTConnected || geminiConnected || customApis.isNotEmpty;

  @override
  String toString() =>
      'ApiManagerState(chatGPT: $chatGPTConnected, gemini: $geminiConnected, '
      'custom: ${customApis.length}, providers: ${availableProviders.length})';
}

/// Notifier for managing API manager state.
///
/// Wraps [ApiManagerService] and exposes reactive state for Riverpod consumers.
class ApiManagerNotifier extends StateNotifier<ApiManagerState> {
  final ApiManagerService _service;

  ApiManagerNotifier(this._service) : super(const ApiManagerState()) {
    // Listen to the service's internal ChangeNotifier
    _service.addListener(_syncState);
  }

  void _syncState() {
    state = state.copyWith(
      chatGPTConnected: _service.isChatGPTOfficialConnected,
      geminiConnected: _service.isGeminiOfficialConnected,
      customApis: _service.getCustomApis(),
      availableProviders: _service.availableProviders,
      providerPriority: _service.providerPriority.toList(),
      autoFailoverEnabled: _service.autoFailoverEnabled,
    );
  }

  /// Initialize the service.
  Future<void> initialize() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _service.initialize();
      _syncState();
      state = state.copyWith(isInitialized: true, isLoading: false);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  /// Connect ChatGPT Official.
  Future<bool> connectChatGPT({String? sessionToken}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _service.connectChatGPTOfficial(sessionToken: sessionToken);
      state = state.copyWith(isLoading: false);
      return result;
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
      return false;
    }
  }

  /// Disconnect ChatGPT Official.
  Future<void> disconnectChatGPT() async {
    state = state.copyWith(isLoading: true);
    await _service.disconnectChatGPTOfficial();
    state = state.copyWith(isLoading: false);
  }

  /// Connect Gemini Official.
  Future<bool> connectGemini({String? apiKey}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _service.connectGeminiOfficial(apiKey: apiKey);
      state = state.copyWith(isLoading: false);
      return result;
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
      return false;
    }
  }

  /// Disconnect Gemini Official.
  Future<void> disconnectGemini() async {
    state = state.copyWith(isLoading: true);
    await _service.disconnectGeminiOfficial();
    state = state.copyWith(isLoading: false);
  }

  /// Add a custom API.
  Future<void> addCustomApi({
    required String name,
    required String baseUrl,
    required String apiKey,
    required String model,
    String? organization,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _service.addCustomApi(
        name: name,
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        organization: organization,
      );
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  /// Update a custom API.
  Future<void> updateCustomApi(
    String id, {
    String? name,
    String? baseUrl,
    String? apiKey,
    String? model,
    String? organization,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _service.updateCustomApi(
        id,
        name: name,
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        organization: organization,
      );
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  /// Delete a custom API.
  Future<void> deleteCustomApi(String id) async {
    state = state.copyWith(isLoading: true);
    await _service.deleteCustomApi(id);
    state = state.copyWith(isLoading: false);
  }

  /// Toggle custom API active state.
  Future<void> toggleCustomApi(String id) async {
    await _service.toggleCustomApiActive(id);
  }

  /// Test a connection.
  Future<ApiHealthStatus> testConnection(String apiId) async {
    state = state.copyWith(isLoading: true);
    final status = await _service.testConnection(apiId);
    final newStatuses = Map<String, ApiHealthStatus>.from(state.healthStatuses)
      ..[apiId] = status;
    state = state.copyWith(healthStatuses: newStatuses, isLoading: false);
    return status;
  }

  /// Set provider priority.
  void setProviderPriority(List<String> priority) {
    _service.setProviderPriority(priority);
  }

  /// Set auto failover.
  Future<void> setAutoFailover(bool enabled) async {
    await _service.setAutoFailover(enabled);
  }

  /// Execute with failover.
  Future<T> withFailover<T>(TaskType task, Future<T> Function(ApiProvider) operation) async {
    return _service.withFailover(task, operation);
  }

  /// Get provider for a task.
  ApiProvider? getProviderForTask(TaskType task) {
    return _service.getProviderForTask(task);
  }

  /// Disconnect all providers.
  Future<void> disconnectAll() async {
    state = state.copyWith(isLoading: true);
    await _service.disconnectAll();
    state = state.copyWith(isLoading: false);
  }

  @override
  void dispose() {
    _service.removeListener(_syncState);
    super.dispose();
  }
}

/// Provider for the [ApiManagerService] instance.
final apiManagerServiceProvider = Provider<ApiManagerService>((ref) {
  final api = ref.watch(apiServiceProvider);
  final storage = ref.watch(secureStorageProvider);
  final service = ApiManagerService(
    apiService: api,
    secureStorage: storage,
  );
  ref.onDispose(() => service.dispose());
  return service;
});

/// StateNotifierProvider for reactive API manager state.
final apiManagerNotifierProvider =
    StateNotifierProvider<ApiManagerNotifier, ApiManagerState>((ref) {
  final service = ref.watch(apiManagerServiceProvider);
  return ApiManagerNotifier(service);
});

/// Computed provider: whether any API provider is available.
final hasAnyProviderProvider = Provider<bool>((ref) {
  return ref.watch(apiManagerNotifierProvider).hasAnyProvider;
});

/// Computed provider: list of available providers.
final availableProvidersProvider = Provider<List<ApiProvider>>((ref) {
  return ref.watch(apiManagerNotifierProvider).availableProviders;
});

/// Computed provider: current provider priority list.
final providerPriorityProvider = Provider<List<String>>((ref) {
  return ref.watch(apiManagerNotifierProvider).providerPriority;
});

// ═══════════════════════════════════════════════════════════════════════════
// Feature Flags Provider
// ═══════════════════════════════════════════════════════════════════════════

/// State class for Feature Flags.
@immutable
class FeatureFlagsState {
  final bool isInitialized;
  final bool isLoading;
  final Map<String, bool> featureValues;
  final String? error;

  const FeatureFlagsState({
    this.isInitialized = false,
    this.isLoading = false,
    this.featureValues = const {},
    this.error,
  });

  FeatureFlagsState copyWith({
    bool? isInitialized,
    bool? isLoading,
    Map<String, bool>? featureValues,
    String? error,
  }) {
    return FeatureFlagsState(
      isInitialized: isInitialized ?? this.isInitialized,
      isLoading: isLoading ?? this.isLoading,
      featureValues: featureValues ?? this.featureValues,
      error: error ?? this.error,
    );
  }

  /// Check if a feature is enabled.
  bool isEnabled(String featureId) {
    final feature = FeatureFlagsService.allFeatures[featureId];
    if (feature == null) return false;
    if (feature.isCore) return true;
    return featureValues[featureId] ?? feature.defaultValue;
  }

  /// Get features organized by category.
  Map<FeatureCategory, List<FeatureFlag>> get featuresByCategory {
    final result = <FeatureCategory, List<FeatureFlag>>{};
    for (final entry in FeatureFlagsService.allFeatures.entries) {
      final currentValue = isEnabled(entry.key);
      result.putIfAbsent(entry.value.category, () => []).add(
        entry.value.copyWith(currentValue: currentValue),
      );
    }
    // Sort by category order
    final sortedEntries = result.entries.toList()
      ..sort((a, b) => a.key.sortOrder.compareTo(b.key.sortOrder));
    return Map.fromEntries(sortedEntries);
  }

  @override
  String toString() => 'FeatureFlagsState(features: ${featureValues.length})';
}

/// Notifier for managing feature flags state.
class FeatureFlagsNotifier extends StateNotifier<FeatureFlagsState> {
  final FeatureFlagsService _service;

  FeatureFlagsNotifier(this._service) : super(const FeatureFlagsState()) {
    _service.addListener(_syncState);
  }

  void _syncState() {
    final values = <String, bool>{};
    for (final entry in FeatureFlagsService.allFeatures.entries) {
      values[entry.key] = _service.isEnabledSync(entry.key);
    }
    state = state.copyWith(featureValues: values);
  }

  /// Initialize the service.
  Future<void> initialize() async {
    state = state.copyWith(isLoading: true);
    try {
      await _service.initialize();
      _syncState();
      state = state.copyWith(isInitialized: true, isLoading: false);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  /// Toggle a feature.
  Future<void> toggle(String featureId) async {
    try {
      await _service.toggle(featureId);
      _syncState();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// Set a feature's enabled state.
  Future<void> setEnabled(String featureId, bool enabled) async {
    try {
      await _service.setEnabled(featureId, enabled);
      _syncState();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// Check if a feature is enabled (async).
  Future<bool> isEnabled(String featureId) async {
    return _service.isEnabled(featureId);
  }

  /// Check if a feature is enabled (sync).
  bool isEnabledSync(String featureId) {
    return state.isEnabled(featureId);
  }

  /// Reset all features to defaults.
  Future<void> resetToDefaults() async {
    state = state.copyWith(isLoading: true);
    await _service.resetToDefaults();
    _syncState();
    state = state.copyWith(isLoading: false);
  }

  @override
  void dispose() {
    _service.removeListener(_syncState);
    super.dispose();
  }
}

/// Provider for the [FeatureFlagsService] instance.
final featureFlagsServiceProvider = Provider<FeatureFlagsService>((ref) {
  final service = FeatureFlagsService();
  ref.onDispose(() {});
  return service;
});

/// StateNotifierProvider for reactive feature flags state.
final featureFlagsNotifierProvider =
    StateNotifierProvider<FeatureFlagsNotifier, FeatureFlagsState>((ref) {
  final service = ref.watch(featureFlagsServiceProvider);
  return FeatureFlagsNotifier(service);
});

/// Family provider: check if a specific feature is enabled.
final featureEnabledProvider = Provider.family<bool, String>((ref, featureId) {
  return ref.watch(featureFlagsNotifierProvider).isEnabled(featureId);
});

// ═══════════════════════════════════════════════════════════════════════════
// Convenience Combined Providers
// ═══════════════════════════════════════════════════════════════════════════

/// Provider that tracks the best available provider for code generation tasks.
final codeGenerationProviderProvider = Provider<ApiProvider?>((ref) {
  final apiManager = ref.watch(apiManagerNotifierProvider);
  if (!apiManager.isInitialized) return null;

  final service = ref.read(apiManagerServiceProvider);
  return service.getProviderForTask(TaskType.codeGeneration);
});

/// Provider that tracks the best available provider for chat tasks.
final chatProviderProvider = Provider<ApiProvider?>((ref) {
  final apiManager = ref.watch(apiManagerNotifierProvider);
  if (!apiManager.isInitialized) return null;

  final service = ref.read(apiManagerServiceProvider);
  return service.getProviderForTask(TaskType.chat);
});

/// Provider that checks if streaming chat is enabled.
final isStreamingChatEnabledProvider = Provider<bool>((ref) {
  return ref.watch(featureEnabledProvider('streaming_chat'));
});

/// Provider that checks if voice-to-code is enabled.
final isVoiceToCodeEnabledProvider = Provider<bool>((ref) {
  return ref.watch(featureEnabledProvider('voice_to_code'));
});

/// Provider that checks if screenshot-to-code is enabled.
final isScreenshotToCodeEnabledProvider = Provider<bool>((ref) {
  return ref.watch(featureEnabledProvider('screenshot_to_code'));
});

/// Provider that checks if terminal is enabled.
final isTerminalEnabledProvider = Provider<bool>((ref) {
  return ref.watch(featureEnabledProvider('terminal'));
});

/// Provider that checks if GitHub Pages deploy is enabled.
final isGitHubPagesDeployEnabledProvider = Provider<bool>((ref) {
  return ref.watch(featureEnabledProvider('github_pages_deploy'));
});

/// Provider that checks if multi-step agent is enabled.
final isMultiStepAgentEnabledProvider = Provider<bool>((ref) {
  return ref.watch(featureEnabledProvider('agent_multi_step'));
});

// ═══════════════════════════════════════════════════════════════════════════
// Initialization
// ═══════════════════════════════════════════════════════════════════════════

/// Initializes both API manager and feature flags services.
/// Call this during app startup before rendering UI.
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await initializeAppServices(container);
///   runApp(ProviderScope(parent: container, child: MyApp()));
/// }
/// ```
Future<void> initializeAppServices(ProviderContainer container) async {
  debugPrint('[AppServices] Initializing...');

  // Initialize secure storage first
  final storage = container.read(secureStorageProvider);
  await storage.initialize();

  // Initialize API manager
  final apiManagerNotifier = container.read(apiManagerNotifierProvider.notifier);
  await apiManagerNotifier.initialize();

  // Initialize feature flags
  final featureFlagsNotifier = container.read(featureFlagsNotifierProvider.notifier);
  await featureFlagsNotifier.initialize();

  debugPrint('[AppServices] All services initialized');
}
