// lib/services/feature_flags_service.dart
// Feature Flags Service - Toggle features on/off
// 功能开关系统

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Data Models
// ═══════════════════════════════════════════════════════════════════════════

/// Categories for organizing feature flags.
enum FeatureCategory {
  /// 实验功能 - Experimental features that may be unstable
  experimental,

  /// 高级功能 - Advanced features for power users
  advanced,

  /// 团队功能 - Team collaboration features
  team,

  /// 显示设置 - Display/UI preferences
  display,

  /// 核心功能 - Core app features (not toggleable)
  core,
}

/// Extension for display names and icons.
extension FeatureCategoryExt on FeatureCategory {
  /// Chinese display name.
  String get displayName {
    switch (this) {
      case FeatureCategory.experimental:
        return '实验功能';
      case FeatureCategory.advanced:
        return '高级功能';
      case FeatureCategory.team:
        return '团队功能';
      case FeatureCategory.display:
        return '显示设置';
      case FeatureCategory.core:
        return '核心功能';
    }
  }

  /// English display name.
  String get displayNameEn {
    switch (this) {
      case FeatureCategory.experimental:
        return 'Experimental';
      case FeatureCategory.advanced:
        return 'Advanced';
      case FeatureCategory.team:
        return 'Team';
      case FeatureCategory.display:
        return 'Display';
      case FeatureCategory.core:
        return 'Core';
    }
  }

  /// Emoji icon for the category.
  String get emoji {
    switch (this) {
      case FeatureCategory.experimental:
        return '🧪';
      case FeatureCategory.advanced:
        return '⚙️';
      case FeatureCategory.team:
        return '👥';
      case FeatureCategory.display:
        return '🎨';
      case FeatureCategory.core:
        return '🔒';
    }
  }

  /// Icon data name for Flutter.
  String get iconName {
    switch (this) {
      case FeatureCategory.experimental:
        return 'science';
      case FeatureCategory.advanced:
        return 'settings';
      case FeatureCategory.team:
        return 'people';
      case FeatureCategory.display:
        return 'palette';
      case FeatureCategory.core:
        return 'lock';
    }
  }

  /// Sort order for display.
  int get sortOrder {
    switch (this) {
      case FeatureCategory.core:
        return 0;
      case FeatureCategory.experimental:
        return 1;
      case FeatureCategory.advanced:
        return 2;
      case FeatureCategory.team:
        return 3;
      case FeatureCategory.display:
        return 4;
    }
  }
}

/// A single feature flag with metadata.
///
/// Features are organized by category and can be toggled on/off.
/// Some features require additional permissions (e.g., microphone, camera).
class FeatureFlag {
  final String id;
  final String name;
  final String description;
  final FeatureCategory category;
  final bool defaultValue;
  final bool requiresPermission;

  /// Current runtime value.
  bool _currentValue;

  /// Permission name required (e.g., 'microphone', 'camera', 'storage').
  final String? permissionType;

  /// Whether this feature is only available in certain platforms.
  final List<String>? supportedPlatforms;

  FeatureFlag({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.defaultValue,
    this.requiresPermission = false,
    this.permissionType,
    this.supportedPlatforms,
  }) : _currentValue = defaultValue;

  /// Current value of the feature flag.
  bool get value => _currentValue;

  /// Set the current value (internal use only).
  set value(bool v) => _currentValue = v;

  /// Whether this feature is experimental.
  bool get isExperimental => category == FeatureCategory.experimental;

  /// Whether this feature is a core feature (not toggleable).
  bool get isCore => category == FeatureCategory.core;

  /// Whether this feature requires a permission.
  bool get needsPermission => requiresPermission;

  FeatureFlag copyWith({bool? currentValue}) {
    final copy = FeatureFlag(
      id: id,
      name: name,
      description: description,
      category: category,
      defaultValue: defaultValue,
      requiresPermission: requiresPermission,
      permissionType: permissionType,
      supportedPlatforms: supportedPlatforms,
    );
    copy._currentValue = currentValue ?? _currentValue;
    return copy;
  }

  @override
  String toString() => 'FeatureFlag($id: $name = $value)';
}

// ═══════════════════════════════════════════════════════════════════════════
// Feature Flags Service
// ═══════════════════════════════════════════════════════════════════════════

/// Feature Flags Service
///
/// Allows users to enable/disable features dynamically.
/// Feature states are persisted to SharedPreferences.
///
/// ## Feature Categories
/// - 🧪 实验功能 (Experimental)
/// - ⚙️ 高级功能 (Advanced)
/// - 👥 团队功能 (Team)
/// - 🎨 显示设置 (Display)
/// - 🔒 核心功能 (Core - not toggleable)
///
/// ## Usage
/// ```dart
/// final flags = ref.read(featureFlagsServiceProvider);
/// await flags.initialize();
///
/// if (await flags.isEnabled('screenshot_to_code')) {
///   // Enable screenshot-to-code UI
/// }
///
/// await flags.setEnabled('terminal', true);
/// ```
class FeatureFlagsService extends ChangeNotifier {
  // ── Feature Definitions ─────────────────────────

  /// All available features with their metadata.
  static final Map<String, FeatureFlag> allFeatures = {
    // ── Experimental Features ─────────────────────
    'voice_to_code': FeatureFlag(
      id: 'voice_to_code',
      name: '语音转代码',
      description: '通过语音输入生成代码，说出你的想法即可生成代码',
      category: FeatureCategory.experimental,
      defaultValue: true,
      requiresPermission: true,
      permissionType: 'microphone',
    ),
    'screenshot_to_code': FeatureFlag(
      id: 'screenshot_to_code',
      name: '截图转代码',
      description: '通过截图识别UI并生成Flutter代码，支持识别布局和样式',
      category: FeatureCategory.experimental,
      defaultValue: true,
      requiresPermission: true,
      permissionType: 'camera',
    ),
    'offline_ai': FeatureFlag(
      id: 'offline_ai',
      name: '离线AI',
      description: '使用本地AI模型进行代码生成（需提前下载模型）',
      category: FeatureCategory.experimental,
      defaultValue: false,
      supportedPlatforms: ['android'],
    ),
    'agent_multi_step': FeatureFlag(
      id: 'agent_multi_step',
      name: '多步Agent',
      description: 'AI自动分解并执行多步骤任务，如创建完整项目结构',
      category: FeatureCategory.experimental,
      defaultValue: true,
    ),
    'wechat_publish': FeatureFlag(
      id: 'wechat_publish',
      name: '微信发布',
      description: '自动发布文章到微信公众号，支持Markdown转公众号格式',
      category: FeatureCategory.experimental,
      defaultValue: false,
    ),

    // ── Advanced Features ─────────────────────────
    'terminal': FeatureFlag(
      id: 'terminal',
      name: '终端执行',
      description: '在应用内执行终端命令，支持常用shell命令',
      category: FeatureCategory.advanced,
      defaultValue: false,
      requiresPermission: true,
      permissionType: 'storage',
    ),
    'github_pages_deploy': FeatureFlag(
      id: 'github_pages_deploy',
      name: 'GitHub Pages 部署',
      description: '一键部署静态网页到 GitHub Pages',
      category: FeatureCategory.advanced,
      defaultValue: true,
    ),
    'lark_cli': FeatureFlag(
      id: 'lark_cli',
      name: 'Lark CLI 连接器',
      description: '通过 RuntimeProvider 受控检测 lark-cli、授权状态和后续飞书/Lark结构化动作',
      category: FeatureCategory.advanced,
      defaultValue: false,
    ),
    'advanced_ai_settings': FeatureFlag(
      id: 'advanced_ai_settings',
      name: '高级AI设置',
      description: '自定义温度、最大令牌数、系统提示词等高级参数',
      category: FeatureCategory.advanced,
      defaultValue: false,
    ),

    // ── Team Features ─────────────────────────────
    'team_collaboration': FeatureFlag(
      id: 'team_collaboration',
      name: '团队协作',
      description: '团队成员协作功能，包括代码审查和任务分配',
      category: FeatureCategory.team,
      defaultValue: false,
    ),
    'live_collaboration': FeatureFlag(
      id: 'live_collaboration',
      name: '实时协作',
      description: '多人实时编辑同一文件，类似Google Docs',
      category: FeatureCategory.team,
      defaultValue: false,
    ),

    // ── Display Features ──────────────────────────
    'code_minimap': FeatureFlag(
      id: 'code_minimap',
      name: '代码迷你地图',
      description: '编辑器右侧显示代码缩略图，快速导航大文件',
      category: FeatureCategory.display,
      defaultValue: false,
    ),
    'breadcrumbs': FeatureFlag(
      id: 'breadcrumbs',
      name: '面包屑导航',
      description: '编辑器顶部显示文件路径导航',
      category: FeatureCategory.display,
      defaultValue: true,
    ),
    'zen_mode': FeatureFlag(
      id: 'zen_mode',
      name: '禅模式',
      description: '全屏专注编码模式，隐藏所有干扰元素',
      category: FeatureCategory.display,
      defaultValue: true,
    ),

    // ── Core Features (not toggleable) ────────────
    'ai_chat': FeatureFlag(
      id: 'ai_chat',
      name: 'AI 对话',
      description: '与AI助手对话获取编程帮助',
      category: FeatureCategory.core,
      defaultValue: true,
    ),
    'code_editor': FeatureFlag(
      id: 'code_editor',
      name: '代码编辑器',
      description: '核心代码编辑功能',
      category: FeatureCategory.core,
      defaultValue: true,
    ),
    'file_manager': FeatureFlag(
      id: 'file_manager',
      name: '文件管理',
      description: '项目文件浏览和管理',
      category: FeatureCategory.core,
      defaultValue: true,
    ),
    'github_integration': FeatureFlag(
      id: 'github_integration',
      name: 'GitHub 集成',
      description: 'GitHub仓库管理和代码同步',
      category: FeatureCategory.core,
      defaultValue: true,
    ),
  };

  // ── Internal State ─────────────────────────────

  final Map<String, bool> _featureStates = {};
  SharedPreferences? _prefs;
  bool _initialized = false;

  // ── Storage Key ────────────────────────────────

  static const String _storageKey = 'feature_flags_states';

  // ── Singleton ──────────────────────────────────

  static FeatureFlagsService? _instance;

  factory FeatureFlagsService() {
    _instance ??= FeatureFlagsService._internal();
    return _instance!;
  }

  FeatureFlagsService._internal();

  static void reset() => _instance = null;

  // ── Initialization ─────────────────────────────

  /// Initialize the service and load persisted feature states.
  Future<void> initialize() async {
    if (_initialized) return;

    debugPrint('[FeatureFlags] Initializing...');

    _prefs = await SharedPreferences.getInstance();

    // Load persisted states
    await _loadStates();

    // Initialize any missing features with defaults
    for (final entry in allFeatures.entries) {
      if (!_featureStates.containsKey(entry.key)) {
        _featureStates[entry.key] = entry.value.defaultValue;
      }
    }

    _initialized = true;
    debugPrint('[FeatureFlags] Initialized: ${allFeatures.length} features');
    notifyListeners();
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('FeatureFlagsService not initialized. Call initialize() first.');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Core Methods
  // ═══════════════════════════════════════════════════════════════════════

  /// Check if a feature is enabled.
  ///
  /// Returns [defaultValue] if the feature ID is unknown.
  Future<bool> isEnabled(String featureId) async {
    _ensureInitialized();

    // Check if feature exists
    final feature = allFeatures[featureId];
    if (feature == null) {
      debugPrint('[FeatureFlags] Unknown feature: $featureId');
      return false;
    }

    // Core features are always enabled
    if (feature.isCore) return true;

    return _featureStates[featureId] ?? feature.defaultValue;
  }

  /// Synchronous check (returns cached value).
  ///
  /// Use [isEnabled] for the most accurate result.
  bool isEnabledSync(String featureId) {
    if (!_initialized) return allFeatures[featureId]?.defaultValue ?? false;

    final feature = allFeatures[featureId];
    if (feature?.isCore ?? false) return true;

    return _featureStates[featureId] ?? feature?.defaultValue ?? false;
  }

  /// Enable or disable a feature.
  Future<void> setEnabled(String featureId, bool enabled) async {
    _ensureInitialized();

    final feature = allFeatures[featureId];
    if (feature == null) {
      throw ArgumentError('Unknown feature: $featureId');
    }

    // Core features cannot be disabled
    if (feature.isCore && !enabled) {
      debugPrint('[FeatureFlags] Cannot disable core feature: $featureId');
      return;
    }

    _featureStates[featureId] = enabled;
    await _persistStates();

    debugPrint('[FeatureFlags] $featureId = $enabled');
    notifyListeners();
  }

  /// Toggle a feature on/off.
  Future<bool> toggle(String featureId) async {
    _ensureInitialized();

    final current = await isEnabled(featureId);
    await setEnabled(featureId, !current);
    return !current;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Query Methods
  // ═══════════════════════════════════════════════════════════════════════

  /// Get all features organized by category.
  Map<FeatureCategory, List<FeatureFlag>> get featuresByCategory {
    _ensureInitialized();

    final result = <FeatureCategory, List<FeatureFlag>>{};
    for (final feature in allFeatures.values) {
      result.putIfAbsent(feature.category, () => []).add(
        feature.copyWith(
          currentValue: _featureStates[feature.id] ?? feature.defaultValue,
        ),
      );
    }

    // Sort categories and features within each category
    final sorted = Map.fromEntries(
      result.entries.toList()..sort((a, b) => a.key.sortOrder.compareTo(b.key.sortOrder)),
    );

    for (final list in sorted.values) {
      list.sort((a, b) => a.name.compareTo(b.name));
    }

    return sorted;
  }

  /// Get features filtered by category.
  List<FeatureFlag> getFeaturesByCategory(FeatureCategory category) {
    _ensureInitialized();

    return allFeatures.values
        .where((f) => f.category == category)
        .map((f) => f.copyWith(currentValue: _featureStates[f.id] ?? f.defaultValue))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Get all features with their current values.
  List<FeatureFlag> getAllFeatures() {
    _ensureInitialized();

    return allFeatures.values
        .map((f) => f.copyWith(currentValue: _featureStates[f.id] ?? f.defaultValue))
        .toList()
      ..sort((a, b) {
        final catCompare = a.category.sortOrder.compareTo(b.category.sortOrder);
        if (catCompare != 0) return catCompare;
        return a.name.compareTo(b.name);
      });
  }

  /// Get a single feature by ID.
  FeatureFlag? getFeature(String featureId) {
    final feature = allFeatures[featureId];
    if (feature == null) return null;
    return feature.copyWith(
      currentValue: _featureStates[featureId] ?? feature.defaultValue,
    );
  }

  /// Check if a feature requires a permission.
  bool requiresPermission(String featureId) {
    return allFeatures[featureId]?.requiresPermission ?? false;
  }

  /// Get the permission type required for a feature.
  String? getRequiredPermission(String featureId) {
    return allFeatures[featureId]?.permissionType;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Bulk Operations
  // ═══════════════════════════════════════════════════════════════════════

  /// Reset all features to their default values.
  Future<void> resetToDefaults() async {
    _ensureInitialized();

    _featureStates.clear();
    for (final entry in allFeatures.entries) {
      _featureStates[entry.key] = entry.value.defaultValue;
    }

    await _persistStates();
    debugPrint('[FeatureFlags] Reset to defaults');
    notifyListeners();
  }

  /// Reset only experimental features to their defaults.
  Future<void> resetExperimentalToDefaults() async {
    _ensureInitialized();

    for (final entry in allFeatures.entries) {
      if (entry.value.category == FeatureCategory.experimental) {
        _featureStates[entry.key] = entry.value.defaultValue;
      }
    }

    await _persistStates();
    debugPrint('[FeatureFlags] Experimental features reset');
    notifyListeners();
  }

  /// Enable all features in a category.
  Future<void> enableCategory(FeatureCategory category) async {
    _ensureInitialized();

    for (final entry in allFeatures.entries) {
      if (entry.value.category == category && !entry.value.isCore) {
        _featureStates[entry.key] = true;
      }
    }

    await _persistStates();
    notifyListeners();
  }

  /// Disable all non-core features in a category.
  Future<void> disableCategory(FeatureCategory category) async {
    _ensureInitialized();

    for (final entry in allFeatures.entries) {
      if (entry.value.category == category && !entry.value.isCore) {
        _featureStates[entry.key] = false;
      }
    }

    await _persistStates();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Import / Export
  // ═══════════════════════════════════════════════════════════════════════

  /// Export all feature states as JSON.
  Map<String, dynamic> exportStates() {
    _ensureInitialized();
    return Map<String, dynamic>.from(_featureStates);
  }

  /// Import feature states from JSON.
  Future<void> importStates(Map<String, dynamic> states) async {
    _ensureInitialized();

    for (final entry in states.entries) {
      if (allFeatures.containsKey(entry.key)) {
        final feature = allFeatures[entry.key]!;
        if (!feature.isCore) {
          _featureStates[entry.key] = entry.value as bool;
        }
      }
    }

    await _persistStates();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Private: Persistence
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _loadStates() async {
    try {
      final jsonStr = _prefs?.getString(_storageKey);
      if (jsonStr == null || jsonStr.isEmpty) return;

      final Map<String, dynamic> decoded = jsonDecode(jsonStr);
      _featureStates.clear();
      for (final entry in decoded.entries) {
        _featureStates[entry.key] = entry.value as bool;
      }
      debugPrint('[FeatureFlags] Loaded ${_featureStates.length} states');
    } catch (e) {
      debugPrint('[FeatureFlags] Failed to load states: $e');
    }
  }

  Future<void> _persistStates() async {
    try {
      final jsonStr = jsonEncode(_featureStates);
      await _prefs?.setString(_storageKey, jsonStr);
    } catch (e) {
      debugPrint('[FeatureFlags] Failed to persist states: $e');
    }
  }
}
