// lib/providers/api_config_provider.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_config.dart';
import '../services/storage_service.dart';
import 'storage_provider.dart';

// ─── API Configs List ──────────────────────────────────────────────

/// Manages the list of LLM API configurations.
///
/// Provides CRUD operations for API configs with automatic
/// persistence to local storage via Hive.
class ApiConfigNotifier extends StateNotifier<List<ApiConfig>> {
  final StorageService _storage;

  ApiConfigNotifier(this._storage) : super([]) {
    _loadConfigs();
  }

  /// Load configs from local storage.
  Future<void> _loadConfigs() async {
    try {
      final configs = await _storage.getApiConfigs();
      state = configs;
    } catch (e) {
      debugPrint('[ApiConfigNotifier] Failed to load configs: $e');
      state = [];
    }
  }

  /// Refresh configs from storage.
  Future<void> refresh() async {
    await _loadConfigs();
  }

  /// Add a new API configuration.
  ///
  /// If [setAsActive] is true, deactivates all other configs.
  Future<void> addConfig(ApiConfig config, {bool setAsActive = false}) async {
    await _storage.saveApiConfig(config, setAsActive: setAsActive);

    if (setAsActive) {
      // Update all existing configs to inactive.
      state = state.map((c) => c.copyWith(isActive: false)).toList();
    }

    state = [...state, config];
  }

  /// Update an existing configuration.
  Future<void> updateConfig(ApiConfig updated) async {
    await _storage.saveApiConfig(updated);

    state = state.map((c) => c.id == updated.id ? updated : c).toList();
  }

  /// Delete a configuration by ID.
  ///
  /// If the deleted config was active, activates the first remaining config.
  Future<void> deleteConfig(String id) async {
    await _storage.deleteApiConfig(id);

    final newState = state.where((c) => c.id != id).toList();

    // If we removed the active config, activate the first one.
    if (newState.isNotEmpty && !newState.any((c) => c.isActive)) {
      final first = newState.first.copyWith(isActive: true);
      await _storage.saveApiConfig(first);
      state = newState
          .map((c) => c.id == first.id ? first : c)
          .toList();
      return;
    }

    state = newState;
  }

  /// Set a config as the active one.
  ///
  /// Only one config can be active at a time.
  Future<void> setActive(String id) async {
    await _storage.setActiveApiConfig(id);

    state = state.map((c) {
      return c.copyWith(isActive: c.id == id);
    }).toList();
  }

  /// Set a config as the default provider.
  ///
  /// The default config is used for new conversations.
  Future<void> setDefault(String id) async {
    state = state.map((c) {
      return c.copyWith(isDefault: c.id == id);
    }).toList();

    // Persist changes.
    for (final config in state) {
      await _storage.saveApiConfig(config);
    }
  }

  /// Create a default OpenAI config (for first-run setup).
  Future<void> createDefaultConfig() async {
    final defaultConfig = ApiConfig(
      id: 'default_openai',
      name: 'OpenAI GPT-4o',
      provider: 'openai',
      baseUrl: 'https://api.openai.com',
      apiKey: '',
      model: 'gpt-4o',
      isActive: true,
      isDefault: true,
      maxTokens: 4096,
      temperature: 0.7,
      createdAt: DateTime.now().toIso8601String(),
    );

    await addConfig(defaultConfig, setAsActive: true);
  }

  /// Check if any configs exist.
  bool get hasConfigs => state.isNotEmpty;

  /// Get the active config (from current state).
  ApiConfig? get activeConfig {
    try {
      return state.firstWhere((c) => c.isActive);
    } catch (_) {
      return state.isNotEmpty ? state.first : null;
    }
  }

  /// Get the default config (from current state).
  ApiConfig? get defaultConfig {
    try {
      return state.firstWhere((c) => c.isDefault);
    } catch (_) {
      return activeConfig;
    }
  }
}

/// Provider for all API configurations.
///
/// Returns the current list of API configs. Use the notifier
/// for CRUD operations.
///
/// ```dart
/// final configs = ref.watch(apiConfigsProvider);
/// ref.read(apiConfigsProvider.notifier).addConfig(newConfig);
/// ```
final apiConfigsProvider =
    StateNotifierProvider<ApiConfigNotifier, List<ApiConfig>>(
  (ref) => ApiConfigNotifier(ref.watch(storageServiceProvider)),
);

// ─── Derived Providers ─────────────────────────────────────────────

/// The currently active API configuration.
///
/// Returns the config marked as active, or the first config if
/// none are explicitly active. Returns null if no configs exist.
///
/// ```dart
/// final activeConfig = ref.watch(activeApiConfigProvider);
/// if (activeConfig != null) { ... }
/// ```
final activeApiConfigProvider = Provider<ApiConfig?>((ref) {
  final configs = ref.watch(apiConfigsProvider);
  if (configs.isEmpty) return null;

  try {
    return configs.firstWhere((c) => c.isActive);
  } catch (_) {
    return configs.first;
  }
});

/// The default API configuration.
///
/// Returns the config marked as default, or the active config,
/// or null if no configs exist.
final defaultApiConfigProvider = Provider<ApiConfig?>((ref) {
  final configs = ref.watch(apiConfigsProvider);
  if (configs.isEmpty) return null;

  try {
    return configs.firstWhere((c) => c.isDefault);
  } catch (_) {
    return ref.read(activeApiConfigProvider);
  }
});

/// Whether any API config has a non-empty API key.
///
/// Used to determine if the user can make API calls.
final hasValidApiKeyProvider = Provider<bool>((ref) {
  final activeConfig = ref.watch(activeApiConfigProvider);
  return activeConfig != null && activeConfig.apiKey.isNotEmpty;
});

/// The active provider name (e.g., 'openai', 'claude').
///
/// Returns null if no config is active.
final activeProviderNameProvider = Provider<String?>((ref) {
  return ref.watch(activeApiConfigProvider)?.provider;
});

/// The active model name (e.g., 'gpt-4o', 'claude-3-opus').
///
/// Returns null if no config is active.
final activeModelNameProvider = Provider<String?>((ref) {
  return ref.watch(activeApiConfigProvider)?.model;
});
