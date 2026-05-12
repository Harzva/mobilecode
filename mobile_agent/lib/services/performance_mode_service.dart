// lib/services/performance_mode_service.dart
// Performance Mode Service — Manages the performance/fluency tradeoff.
//
// FLUENT MODE (default): <150MB RAM, 60fps, reduced features.
// PERFORMANCE MODE: <400MB RAM, all features ON, multi-agent active.
// CUSTOM MODE: User can toggle each feature independently.
//
// Usage:
// ```dart
// final perf = PerformanceModeService();
// await perf.init();
// await perf.setMode(PerformanceMode.fluent);
// final isEnabled = await perf.isFeatureEnabled('particles');
// ```

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Performance Mode Enum
// ═══════════════════════════════════════════════════════════════════════════

/// Available performance modes.
enum PerformanceMode { fluent, performance, custom }

extension PerformanceModeExt on PerformanceMode {
  String get displayName {
    switch (this) {
      case PerformanceMode.fluent:
        return '流畅模式';
      case PerformanceMode.performance:
        return '性能模式';
      case PerformanceMode.custom:
        return '自定义';
    }
  }

  String get description {
    switch (this) {
      case PerformanceMode.fluent:
        return '低内存占用，适合日常编码';
      case PerformanceMode.performance:
        return '全功能开启，适合高性能设备';
      case PerformanceMode.custom:
        return '自定义各项功能的开关';
    }
  }

  IconData get icon {
    switch (this) {
      case PerformanceMode.fluent:
        return Icons.speed;
      case PerformanceMode.performance:
        return Icons.bolt;
      case PerformanceMode.custom:
        return Icons.tune;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Performance Snapshot
// ═══════════════════════════════════════════════════════════════════════════

/// A snapshot of current performance metrics.
@immutable
class PerformanceSnapshot {
  final int memoryUsageMB;
  final double fps;
  final int activeAgentCount;
  final bool isThrottling;
  final PerformanceMode currentMode;
  final Map<String, bool> featureStates;

  const PerformanceSnapshot({
    required this.memoryUsageMB,
    required this.fps,
    required this.activeAgentCount,
    required this.isThrottling,
    required this.currentMode,
    required this.featureStates,
  });

  /// Estimated memory impact string.
  String get memoryStatus {
    if (memoryUsageMB < 150) return '低 (${memoryUsageMB}MB)';
    if (memoryUsageMB < 250) return '中 (${memoryUsageMB}MB)';
    return '高 (${memoryUsageMB}MB)';
  }

  Map<String, dynamic> toJson() => {
        'memoryUsageMB': memoryUsageMB,
        'fps': fps,
        'activeAgentCount': activeAgentCount,
        'isThrottling': isThrottling,
        'currentMode': currentMode.index,
        'featureStates': featureStates,
      };
}

// ═══════════════════════════════════════════════════════════════════════════
// Performance Mode Service
// ═══════════════════════════════════════════════════════════════════════════

/// Manages the performance/fluency tradeoff for the app.
///
/// The service provides three modes:
/// - **Fluent**: Minimal RAM (<150MB), 60fps, reduced visual effects.
/// - **Performance**: Higher RAM (<400MB), all features enabled.
/// - **Custom**: User-defined feature toggles.
///
/// Features managed include particles, waveforms, animations, multi-agent
/// collaboration, auto-preview, and statistics displays.
class PerformanceModeService extends ChangeNotifier {
  // ── Default Configurations ─────────────────────────────────────────

  static const Map<String, bool> fluentModeDefaults = {
    'particles': false,
    'waveforms': false,
    'syntax_highlighting': true,
    'full_highlighting': false,
    'multi_agent': false,
    'auto_preview': false,
    'animations': false,
    'background_deep_dive': true,
    'realtime_sync': false,
    'contributions_graph': true,
    'achievements': true,
  };

  static const Map<String, bool> performanceModeDefaults = {
    'particles': true,
    'waveforms': true,
    'syntax_highlighting': true,
    'full_highlighting': true,
    'multi_agent': true,
    'auto_preview': true,
    'animations': true,
    'background_deep_dive': true,
    'realtime_sync': true,
    'contributions_graph': true,
    'achievements': true,
  };

  /// Feature metadata: id -> {name, description, category, icon}.
  static const Map<String, Map<String, String>> featureMetadata = {
    'particles': {
      'name': '粒子效果',
      'description': '编辑器背景中的动态粒子动画',
      'category': 'visual',
      'icon': '✨',
    },
    'waveforms': {
      'name': '波形动画',
      'description': '音频/代码可视化波形效果',
      'category': 'visual',
      'icon': '〰️',
    },
    'syntax_highlighting': {
      'name': '语法高亮',
      'description': '代码语法颜色高亮（基础）',
      'category': 'visual',
      'icon': '🎨',
    },
    'full_highlighting': {
      'name': '完整高亮',
      'description': '语义高亮、内联提示等高级高亮',
      'category': 'visual',
      'icon': '🔆',
    },
    'multi_agent': {
      'name': '多Agent协作',
      'description': '同时运行多个AI Agent处理任务',
      'category': 'ai',
      'icon': '🤖',
    },
    'auto_preview': {
      'name': '自动预览',
      'description': '代码修改后自动刷新预览',
      'category': 'ai',
      'icon': '👁️',
    },
    'animations': {
      'name': '完整动画',
      'description': '页面过渡和交互动画',
      'category': 'visual',
      'icon': '🎬',
    },
    'background_deep_dive': {
      'name': '后台深潜',
      'description': '后台运行AI代码分析',
      'category': 'ai',
      'icon': '🤿',
    },
    'realtime_sync': {
      'name': '实时同步',
      'description': '代码变更实时同步到云端',
      'category': 'ai',
      'icon': '☁️',
    },
    'contributions_graph': {
      'name': '贡献图',
      'description': 'GitHub风格贡献热力图',
      'category': 'stats',
      'icon': '📊',
    },
    'achievements': {
      'name': '成就系统',
      'description': '编码成就徽章和进度',
      'category': 'stats',
      'icon': '🏆',
    },
  };

  // ── Internal State ─────────────────────────────────────────────────

  SharedPreferences? _prefs;
  bool _initialized = false;
  PerformanceMode _currentMode = PerformanceMode.fluent;
  final Map<String, bool> _featureStates = {};
  final List<VoidCallback> _lowMemoryCallbacks = [];

  // Storage key
  static const String _storageKeyMode = 'perf_mode';
  static const String _storageKeyFeatures = 'perf_features';

  // Singleton
  static PerformanceModeService? _instance;
  factory PerformanceModeService() {
    _instance ??= PerformanceModeService._internal();
    return _instance!;
  }
  PerformanceModeService._internal();

  // ── Initialization ─────────────────────────────────────────────────

  /// Initialize the service and load persisted settings.
  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    await _loadSettings();
    _initialized = true;
    debugPrint('[PerformanceModeService] Initialized: $_currentMode');
  }

  void _ensureInit() {
    if (!_initialized) {
      throw StateError('PerformanceModeService not initialized. Call init() first.');
    }
  }

  // ── Mode Management ────────────────────────────────────────────────

  /// Get the current performance mode.
  PerformanceMode get currentMode {
    _ensureInit();
    return _currentMode;
  }

  /// Set the performance mode.
  ///
  /// This applies the appropriate default feature configuration
  /// for fluent or performance modes. Custom mode preserves
  /// the user's individual feature toggles.
  Future<void> setMode(PerformanceMode mode) async {
    _ensureInit();
    _currentMode = mode;

    // Apply mode-specific defaults.
    switch (mode) {
      case PerformanceMode.fluent:
        _applyDefaults(fluentModeDefaults);
      case PerformanceMode.performance:
        _applyDefaults(performanceModeDefaults);
      case PerformanceMode.custom:
        // In custom mode, keep current feature states.
        break;
    }

    await _persistSettings();
    notifyListeners();
    debugPrint('[PerformanceModeService] Switched to $mode');
  }

  // ── Feature Control ────────────────────────────────────────────────

  /// Check if a feature is currently enabled.
  Future<bool> isFeatureEnabled(String featureId) async {
    _ensureInit();
    return _featureStates[featureId] ??
        fluentModeDefaults[featureId] ??
        false;
  }

  /// Synchronous check (use cached value).
  bool isFeatureEnabledSync(String featureId) {
    if (!_initialized) return fluentModeDefaults[featureId] ?? false;
    return _featureStates[featureId] ?? fluentModeDefaults[featureId] ?? false;
  }

  /// Enable or disable a specific feature.
  Future<void> setFeatureEnabled(String featureId, bool enabled) async {
    _ensureInit();
    _featureStates[featureId] = enabled;

    // If in fluent/performance mode, switching a feature moves to custom.
    if (_currentMode != PerformanceMode.custom) {
      _currentMode = PerformanceMode.custom;
    }

    await _persistSettings();
    notifyListeners();
    debugPrint('[PerformanceModeService] Feature $featureId = $enabled');
  }

  /// Reset all features to the current mode's defaults.
  Future<void> resetToDefaults() async {
    _ensureInit();
    switch (_currentMode) {
      case PerformanceMode.fluent:
        _applyDefaults(fluentModeDefaults);
      case PerformanceMode.performance:
        _applyDefaults(performanceModeDefaults);
      case PerformanceMode.custom:
        _applyDefaults(fluentModeDefaults);
        _currentMode = PerformanceMode.fluent;
    }
    await _persistSettings();
    notifyListeners();
  }

  /// Get all features with their current states.
  Map<String, bool> get allFeatureStates {
    _ensureInit();
    final result = <String, bool>{};
    for (final id in featureMetadata.keys) {
      result[id] = _featureStates[id] ?? fluentModeDefaults[id] ?? false;
    }
    return result;
  }

  /// Get features grouped by category.
  Map<String, List<Map<String, dynamic>>> get featuresByCategory {
    _ensureInit();
    final result = <String, List<Map<String, dynamic>>>{};

    for (final entry in featureMetadata.entries) {
      final meta = entry.value;
      final category = meta['category']!;
      result.putIfAbsent(category, () => []).add({
        'id': entry.key,
        'name': meta['name'],
        'description': meta['description'],
        'icon': meta['icon'],
        'category': category,
        'enabled': _featureStates[entry.key] ??
            fluentModeDefaults[entry.key] ??
            false,
      });
    }

    return result;
  }

  // ── Performance Monitoring ─────────────────────────────────────────

  /// Get current performance snapshot.
  Future<PerformanceSnapshot> getCurrentPerformance() async {
    _ensureInit();

    // Estimate memory based on enabled features.
    final enabledCount = _featureStates.values.where((v) => v).length;
    final baseMemory = 80; // Base app memory in MB.
    final featureMemory = enabledCount * 25; // ~25MB per major feature.
    final estimatedMemory = baseMemory + featureMemory;

    // Estimate FPS.
    final fps = _currentMode == PerformanceMode.fluent ? 60.0 : 55.0;

    // Estimate active agents.
    final agentCount = await isFeatureEnabled('multi_agent') ? 3 : 1;

    return PerformanceSnapshot(
      memoryUsageMB: estimatedMemory,
      fps: fps,
      activeAgentCount: agentCount,
      isThrottling: estimatedMemory > 300,
      currentMode: _currentMode,
      featureStates: Map.unmodifiable(allFeatureStates),
    );
  }

  /// Check if animations should be throttled.
  bool shouldThrottleAnimations() {
    if (!_initialized) return true;
    return _currentMode == PerformanceMode.fluent;
  }

  /// Check if simple (basic) highlighting should be used.
  bool shouldUseSimpleHighlighting() {
    if (!_initialized) return true;
    if (_currentMode == PerformanceMode.performance) return false;
    return !(_featureStates['full_highlighting'] ?? false);
  }

  /// Get maximum concurrent agent count.
  int getMaxAgentConcurrency() {
    if (!_initialized) return 1;
    if (_currentMode == PerformanceMode.performance) return 4;
    if (_featureStates['multi_agent'] == true) return 3;
    return 1;
  }

  // ── Auto-Switch ────────────────────────────────────────────────────

  /// Check memory and auto-switch to fluent mode if low.
  Future<void> checkAutoSwitch() async {
    _ensureInit();
    final snapshot = await getCurrentPerformance();

    // If memory usage is high and not already in fluent mode, switch.
    if (snapshot.memoryUsageMB > 350 && _currentMode == PerformanceMode.performance) {
      debugPrint('[PerformanceModeService] Low memory detected (${snapshot.memoryUsageMB}MB), '
          'switching to fluent mode');
      await setMode(PerformanceMode.fluent);

      // Notify registered callbacks.
      for (final cb in _lowMemoryCallbacks) {
        cb();
      }
    }
  }

  /// Register a callback for low memory events.
  void onLowMemory(void Function() callback) {
    _lowMemoryCallbacks.add(callback);
  }

  /// Remove a low memory callback.
  void removeLowMemoryCallback(void Function() callback) {
    _lowMemoryCallbacks.remove(callback);
  }

  // ── Persistence ────────────────────────────────────────────────────

  Future<void> _loadSettings() async {
    try {
      // Load mode.
      final modeIndex = _prefs?.getInt(_storageKeyMode);
      if (modeIndex != null && modeIndex >= 0 && modeIndex < PerformanceMode.values.length) {
        _currentMode = PerformanceMode.values[modeIndex];
      }

      // Load feature states.
      final featuresJson = _prefs?.getString(_storageKeyFeatures);
      if (featuresJson != null && featuresJson.isNotEmpty) {
        final decoded = jsonDecode(featuresJson) as Map<String, dynamic>;
        _featureStates.clear();
        for (final entry in decoded.entries) {
          _featureStates[entry.key] = entry.value as bool;
        }
      }

      // If no feature states, apply current mode defaults.
      if (_featureStates.isEmpty) {
        switch (_currentMode) {
          case PerformanceMode.fluent:
            _applyDefaults(fluentModeDefaults);
          case PerformanceMode.performance:
            _applyDefaults(performanceModeDefaults);
          case PerformanceMode.custom:
            _applyDefaults(fluentModeDefaults);
        }
      }

      debugPrint('[PerformanceModeService] Loaded mode: $_currentMode, '
          '${_featureStates.length} feature states');
    } catch (e) {
      debugPrint('[PerformanceModeService] Failed to load settings: $e');
    }
  }

  Future<void> _persistSettings() async {
    try {
      await _prefs?.setInt(_storageKeyMode, _currentMode.index);
      await _prefs?.setString(_storageKeyFeatures, jsonEncode(_featureStates));
    } catch (e) {
      debugPrint('[PerformanceModeService] Failed to persist settings: $e');
    }
  }

  void _applyDefaults(Map<String, bool> defaults) {
    _featureStates.clear();
    _featureStates.addAll(defaults);
  }
}
