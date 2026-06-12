// lib/screens/feature_flags_screen.dart
// Feature Flags Screen - Organized by category with toggle switches
// 功能开关设置界面

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/feature_flags_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Feature Flags Screen
// ═══════════════════════════════════════════════════════════════════════════

/// Feature Flags Settings Screen
///
/// Organized by category:
/// - 🧪 实验功能 (Experimental)
/// - ⚙️ 高级功能 (Advanced)
/// - 👥 团队功能 (Team)
/// - 🎨 显示设置 (Display)
/// - 🔒 核心功能 (Core - not toggleable)
///
/// Each feature: icon + name + description + toggle switch
/// Experimental features show ⚠️ badge
class FeatureFlagsScreen extends StatefulWidget {
  final FeatureFlagsService featureFlags;

  const FeatureFlagsScreen({super.key, required this.featureFlags});

  @override
  State<FeatureFlagsScreen> createState() => _FeatureFlagsScreenState();
}

class _FeatureFlagsScreenState extends State<FeatureFlagsScreen> {
  bool _isLoading = false;

  void _setLoading(bool v) => setState(() => _isLoading = v);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background.withOpacity(0.8),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          '功能开关',
          style: TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 20, color: AppTheme.textSecondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          // Reset button
          TextButton(
            onPressed: _showResetDialog,
            child: const Text(
              '重置',
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: widget.featureFlags,
        builder: (context, _) {
          final featuresByCategory = widget.featureFlags.featuresByCategory;

          if (featuresByCategory.isEmpty) {
            return _buildEmptyState();
          }

          return Stack(
            children: [
              ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: featuresByCategory.length,
                itemBuilder: (context, categoryIndex) {
                  final entry =
                      featuresByCategory.entries.elementAt(categoryIndex);
                  return _buildCategorySection(
                    category: entry.key,
                    features: entry.value,
                    isLast: categoryIndex == featuresByCategory.length - 1,
                  );
                },
              ),
              if (_isLoading)
                Container(
                  color: Colors.black.withOpacity(0.3),
                  child: const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Category Section
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildCategorySection({
    required FeatureCategory category,
    required List<FeatureFlag> features,
    required bool isLast,
  }) {
    final categoryColor = _getCategoryColor(category);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category header
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: categoryColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    category.emoji,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.displayName,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      category.displayNameEn,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 11,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              // Feature count badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: categoryColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${features.length}',
                  style: TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: categoryColor,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Features list
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < features.length; i++) ...[
                _buildFeatureTile(
                  feature: features[i],
                  categoryColor: categoryColor,
                ),
                if (i < features.length - 1)
                  const Divider(
                    height: 1,
                    indent: 56,
                    endIndent: 16,
                    color: AppTheme.divider,
                  ),
              ],
            ],
          ),
        ),

        if (!isLast) const SizedBox(height: 8),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Feature Tile
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildFeatureTile({
    required FeatureFlag feature,
    required Color categoryColor,
  }) {
    final isExperimental = feature.isExperimental;
    final isCore = feature.isCore;
    final requiresPermission = feature.requiresPermission;
    final permissionType = feature.permissionType;

    return InkWell(
      onTap: isCore ? null : () => _toggleFeature(feature),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isCore
                    ? categoryColor.withOpacity(0.1)
                    : (feature.value
                        ? categoryColor.withOpacity(0.2)
                        : AppTheme.surfaceHover),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Center(
                child: Icon(
                  _getFeatureIcon(feature.id),
                  size: 18,
                  color: isCore
                      ? categoryColor.withOpacity(0.6)
                      : (feature.value ? categoryColor : AppTheme.textDisabled),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name row with badges
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          feature.name,
                          style: TextStyle(
                            fontFamily: AppTheme.fontBody,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isCore
                                ? AppTheme.textSecondary
                                : AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      if (isExperimental && !isCore) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.warning.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.warning_amber,
                                size: 10,
                                color: AppTheme.warning,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '实验',
                                style: TextStyle(
                                  fontFamily: AppTheme.fontBody,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.warning,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (isCore) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.textDisabled.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            '核心',
                            style: TextStyle(
                              fontFamily: AppTheme.fontBody,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textDisabled,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),

                  // Description
                  Text(
                    feature.description,
                    style: TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 12,
                      color: isCore
                          ? AppTheme.textTertiary.withOpacity(0.6)
                          : AppTheme.textTertiary,
                    ),
                  ),

                  // Permission hint
                  if (requiresPermission && !isCore) ...[
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 11,
                          color: AppTheme.info.withOpacity(0.7),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '需要${_getPermissionLabel(permissionType)}权限',
                          style: TextStyle(
                            fontFamily: AppTheme.fontBody,
                            fontSize: 10,
                            color: AppTheme.info.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Toggle switch (or lock icon for core features)
            if (isCore)
              Container(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.lock_outline,
                  size: 16,
                  color: AppTheme.textDisabled.withOpacity(0.5),
                ),
              )
            else
              SizedBox(
                height: 32,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Switch.adaptive(
                    value: feature.value,
                    onChanged: (_) => _toggleFeature(feature),
                    activeColor: categoryColor,
                    activeTrackColor: categoryColor.withOpacity(0.3),
                    inactiveThumbColor: AppTheme.textDisabled,
                    inactiveTrackColor: AppTheme.textDisabled.withOpacity(0.2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Actions
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _toggleFeature(FeatureFlag feature) async {
    if (feature.isCore) return;

    _setLoading(true);
    try {
      await widget.featureFlags.toggle(feature.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('切换失败: $e'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      _setLoading(false);
    }
  }

  void _showResetDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: const Text(
          '重置功能开关',
          style: TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        content: Text(
          '确定要将所有功能开关恢复为默认值吗？',
          style: TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              '取消',
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              _setLoading(true);
              await widget.featureFlags.resetToDefaults();
              _setLoading(false);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已恢复默认值'),
                    backgroundColor: AppTheme.success,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text(
              '重置',
              style: TextStyle(fontFamily: AppTheme.fontBody),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.toggle_off_outlined,
            size: 64,
            color: AppTheme.textDisabled.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无功能开关',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textTertiary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '功能开关将在后续版本中添加',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 13,
              color: AppTheme.textTertiary.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Color _getCategoryColor(FeatureCategory category) {
    switch (category) {
      case FeatureCategory.experimental:
        return AppTheme.warning;
      case FeatureCategory.advanced:
        return AppTheme.accent;
      case FeatureCategory.team:
        return AppTheme.info;
      case FeatureCategory.display:
        return AppTheme.primary;
      case FeatureCategory.core:
        return AppTheme.textSecondary;
    }
  }

  IconData _getFeatureIcon(String featureId) {
    switch (featureId) {
      case 'voice_to_code':
        return Icons.mic;
      case 'screenshot_to_code':
        return Icons.camera_alt;
      case 'terminal':
        return Icons.terminal;
      case 'github_pages_deploy':
        return Icons.rocket_launch;
      case 'lark_native_api':
        return Icons.account_tree;
      case 'lark_cli':
        return Icons.terminal;
      case 'team_collaboration':
        return Icons.groups;
      case 'offline_ai':
        return Icons.cloud_off;
      case 'agent_multi_step':
        return Icons.psychology;
      case 'code_minimap':
        return Icons.map;
      case 'live_collaboration':
        return Icons.group;
      case 'wechat_publish':
        return Icons.wechat;
      case 'advanced_ai_settings':
        return Icons.tune;
      case 'breadcrumbs':
        return Icons.account_tree;
      case 'zen_mode':
        return Icons.spa;
      case 'ai_chat':
        return Icons.chat_bubble;
      case 'code_editor':
        return Icons.code;
      case 'file_manager':
        return Icons.folder;
      case 'github_integration':
        return Icons.code;
      default:
        return Icons.toggle_on;
    }
  }

  String _getPermissionLabel(String? permissionType) {
    switch (permissionType) {
      case 'microphone':
        return '麦克风';
      case 'camera':
        return '相机';
      case 'storage':
        return '存储';
      default:
        return '';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Feature Flag Quick Toggle Widget (for embedding in other screens)
// ═══════════════════════════════════════════════════════════════════════════

/// A compact widget that shows a single feature flag toggle.
/// Can be embedded in settings or tool panels.
class FeatureQuickToggle extends StatelessWidget {
  final FeatureFlag feature;
  final ValueChanged<bool>? onChanged;

  const FeatureQuickToggle({
    super.key,
    required this.feature,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(
        _getIcon(feature.id),
        size: 20,
        color: feature.value ? AppTheme.primary : AppTheme.textTertiary,
      ),
      title: Text(
        feature.name,
        style: TextStyle(
          fontFamily: AppTheme.fontBody,
          fontSize: 14,
          color: AppTheme.textPrimary,
        ),
      ),
      trailing: Switch.adaptive(
        value: feature.value,
        onChanged: feature.isCore ? null : onChanged,
        activeColor: AppTheme.primary,
      ),
    );
  }

  IconData _getIcon(String featureId) {
    switch (featureId) {
      case 'voice_to_code':
        return Icons.mic;
      case 'screenshot_to_code':
        return Icons.camera_alt;
      case 'terminal':
        return Icons.terminal;
      case 'github_pages_deploy':
        return Icons.rocket_launch;
      case 'lark_native_api':
        return Icons.account_tree;
      case 'lark_cli':
        return Icons.terminal;
      case 'team_collaboration':
        return Icons.groups;
      case 'offline_ai':
        return Icons.cloud_off;
      case 'agent_multi_step':
        return Icons.psychology;
      case 'code_minimap':
        return Icons.map;
      case 'live_collaboration':
        return Icons.group;
      case 'wechat_publish':
        return Icons.wechat;
      case 'advanced_ai_settings':
        return Icons.tune;
      case 'breadcrumbs':
        return Icons.account_tree;
      case 'zen_mode':
        return Icons.spa;
      default:
        return Icons.toggle_on;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Feature Badge Widget (for showing feature status indicators)
// ═══════════════════════════════════════════════════════════════════════════

/// A small badge that indicates a feature's experimental status.
class ExperimentalBadge extends StatelessWidget {
  final double fontSize;

  const ExperimentalBadge({super.key, this.fontSize = 9});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.warning.withOpacity(0.15),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber,
              size: fontSize + 1, color: AppTheme.warning),
          const SizedBox(width: 2),
          Text(
            '实验功能',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: AppTheme.warning,
            ),
          ),
        ],
      ),
    );
  }
}
