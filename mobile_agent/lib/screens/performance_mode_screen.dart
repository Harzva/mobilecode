// lib/screens/performance_mode_screen.dart
// Performance Mode Screen — UI for configuring performance/fluency tradeoff.
//
// Layout:
// - Mode selector (3 cards): Fluent / Performance / Custom
// - Mode description card
// - Feature list with toggles (when custom mode)
// - Performance indicator at bottom
// - Reset button
//
// Design: Mode cards with selection, feature toggles grouped by category.

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/performance_mode_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Performance Mode Screen
// ═══════════════════════════════════════════════════════════════════════════

/// Performance Mode Screen — Configure performance/fluency tradeoff.
///
/// Features:
/// - Three mode cards: Fluent (default), Performance (full features), Custom
/// - Per-feature toggles when in custom mode
/// - Grouped by category: Visual, AI, Statistics
/// - Live performance estimation (memory, FPS)
/// - Reset to defaults button
class PerformanceModeScreen extends StatefulWidget {
  const PerformanceModeScreen({super.key});

  @override
  State<PerformanceModeScreen> createState() => _PerformanceModeScreenState();
}

class _PerformanceModeScreenState extends State<PerformanceModeScreen> {
  final PerformanceModeService _perf = PerformanceModeService();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _perf.init();
    _perf.addListener(_onPerfChanged);
    setState(() => _isLoading = false);
  }

  void _onPerfChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _perf.removeListener(_onPerfChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background.withOpacity(0.8),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          '性能模式',
          style: TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Mode Selector
                  _buildModeSelector(),
                  const SizedBox(height: 20),
                  // Mode Description
                  _buildModeDescription(),
                  const SizedBox(height: 24),
                  // Feature Toggles (custom mode only, or always visible)
                  _buildFeatureSection(),
                  const SizedBox(height: 24),
                  // Performance Indicator
                  _buildPerformanceIndicator(),
                  const SizedBox(height: 24),
                  // Reset Button
                  _buildResetButton(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  // ── Mode Selector ──────────────────────────────────────────────────

  Widget _buildModeSelector() {
    return Row(
      children: [
        Expanded(
          child: _ModeCard(
            mode: PerformanceMode.fluent,
            currentMode: _perf.currentMode,
            icon: Icons.speed,
            title: '流畅模式',
            subtitle: '默认',
            color: AppTheme.success,
            onTap: () => _perf.setMode(PerformanceMode.fluent),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ModeCard(
            mode: PerformanceMode.performance,
            currentMode: _perf.currentMode,
            icon: Icons.bolt,
            title: '性能模式',
            subtitle: '全功能',
            color: AppTheme.primary,
            onTap: () => _perf.setMode(PerformanceMode.performance),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ModeCard(
            mode: PerformanceMode.custom,
            currentMode: _perf.currentMode,
            icon: Icons.tune,
            title: '自定义',
            subtitle: '自定义',
            color: AppTheme.accent,
            onTap: () => _perf.setMode(PerformanceMode.custom),
          ),
        ),
      ],
    );
  }

  // ── Mode Description ───────────────────────────────────────────────

  Widget _buildModeDescription() {
    final descriptions = {
      PerformanceMode.fluent: {
        'title': '流畅模式（默认）',
        'description': '适合日常编码，低内存占用，保证60fps流畅体验。'
            '关闭粒子效果和波形动画，使用基础语法高亮，单Agent模式。',
        'memory': '< 150MB',
        'fps': '60',
        'features': '基础功能',
      },
      PerformanceMode.performance: {
        'title': '性能模式（全功能）',
        'description': '适合高性能设备，开启所有视觉效果和AI功能。'
            '启用粒子效果、波形动画、多Agent协作和自动预览。',
        'memory': '< 400MB',
        'fps': '55-60',
        'features': '全部功能',
      },
      PerformanceMode.custom: {
        'title': '自定义模式',
        'description': '根据你的需求自由开关各项功能。'
            '下方列表中可单独控制每个功能的启用状态。',
        'memory': '取决于配置',
        'fps': '视功能而定',
        'features': '自定义',
      },
    };

    final desc = descriptions[_perf.currentMode]!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            desc['title']!,
            style: const TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            desc['description']!,
            style: const TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _DescBadge(label: '内存: ${desc['memory']}', color: AppTheme.info),
              const SizedBox(width: 8),
              _DescBadge(label: 'FPS: ${desc['fps']}', color: AppTheme.success),
              const SizedBox(width: 8),
              _DescBadge(label: desc['features']!, color: AppTheme.primary),
            ],
          ),
        ],
      ),
    );
  }

  // ── Feature Section ────────────────────────────────────────────────

  Widget _buildFeatureSection() {
    final features = _perf.featuresByCategory;
    final categoryNames = {
      'visual': '视觉效果',
      'ai': 'AI 功能',
      'stats': '统计功能',
    };
    final categoryIcons = {
      'visual': Icons.palette,
      'ai': Icons.smart_toy,
      'stats': Icons.bar_chart,
    };
    final categoryColors = {
      'visual': AppTheme.primary,
      'ai': AppTheme.accent,
      'stats': AppTheme.warning,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: features.entries.map((entry) {
        final catId = entry.key;
        final catFeatures = entry.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10, top: 8),
              child: Row(
                children: [
                  Icon(
                    categoryIcons[catId] ?? Icons.settings,
                    color: categoryColors[catId] ?? AppTheme.textSecondary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    categoryNames[catId] ?? catId,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            ...catFeatures.map((feature) {
              return _FeatureToggle(
                id: feature['id'] as String,
                name: feature['name'] as String,
                description: feature['description'] as String,
                icon: feature['icon'] as String,
                enabled: feature['enabled'] as bool,
                onToggle: (enabled) => _perf.setFeatureEnabled(
                  feature['id'] as String,
                  enabled,
                ),
              );
            }),
          ],
        );
      }).toList(),
    );
  }

  // ── Performance Indicator ──────────────────────────────────────────

  Widget _buildPerformanceIndicator() {
    return FutureBuilder<PerformanceSnapshot>(
      future: _perf.getCurrentPerformance(),
      builder: (context, snapshot) {
        final estimatedMemory = snapshot.hasData ? '${snapshot.data!.memoryUsageMB}' : '--';
        final estimatedFps = snapshot.hasData ? '${snapshot.data!.fps.toStringAsFixed(0)}' : '--';
        final agents = snapshot.hasData ? '${snapshot.data!.activeAgentCount}' : '--';

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              const Text(
                '预估性能',
                style: TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _PerfIndicator(value: '$estimatedMemory MB', label: '内存占用', icon: Icons.memory),
                  Container(width: 1, height: 40, color: Colors.white24),
                  _PerfIndicator(value: '$estimatedFps FPS', label: '帧率', icon: Icons.speed),
                  Container(width: 1, height: 40, color: Colors.white24),
                  _PerfIndicator(value: agents, label: 'Agent数', icon: Icons.smart_toy),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Reset Button ───────────────────────────────────────────────────

  Widget _buildResetButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () async {
          await _perf.resetToDefaults();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已恢复默认设置')),
            );
          }
        },
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('恢复默认'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.textSecondary,
          side: const BorderSide(color: AppTheme.border),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Mode Card Widget
// ═══════════════════════════════════════════════════════════════════════════

class _ModeCard extends StatelessWidget {
  final PerformanceMode mode;
  final PerformanceMode currentMode;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ModeCard({
    required this.mode,
    required this.currentMode,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = mode == currentMode;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.15) : AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : AppTheme.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? color : AppTheme.textTertiary,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? color : AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 10,
                color: isSelected ? color.withOpacity(0.7) : AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Feature Toggle Widget
// ═══════════════════════════════════════════════════════════════════════════

class _FeatureToggle extends StatelessWidget {
  final String id;
  final String name;
  final String description;
  final String icon;
  final bool enabled;
  final ValueChanged<bool> onToggle;

  const _FeatureToggle({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.enabled,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Row(
        children: [
          // Feature icon (text emoji)
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: enabled ? AppTheme.primaryMuted : AppTheme.backgroundElevated,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                icon,
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Name and description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: enabled ? AppTheme.textPrimary : AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 12,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          // Toggle
          Switch(
            value: enabled,
            onChanged: onToggle,
            activeColor: AppTheme.primary,
            activeTrackColor: AppTheme.primary.withOpacity(0.4),
            inactiveThumbColor: AppTheme.textTertiary,
            inactiveTrackColor: AppTheme.border,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Description Badge
// ═══════════════════════════════════════════════════════════════════════════

class _DescBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _DescBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppTheme.fontBody,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Performance Indicator Item
// ═══════════════════════════════════════════════════════════════════════════

class _PerfIndicator extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;

  const _PerfIndicator({
    required this.value,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 11,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }
}
