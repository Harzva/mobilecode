// lib/screens/performance_screen.dart

import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/device_perf_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Performance Screen
// ═══════════════════════════════════════════════════════════════════════════

/// {@template performance_screen}
/// Device performance analyzer UI.
///
/// Shows device info, RAM/storage gauges, CPU info, device rating,
/// Flutter capability assessment, project recommendations, language
/// capabilities table, and optimization suggestions.
///
/// Design: Dark theme with gauge charts and color-coded ratings.
/// {@endtemplate}
class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  final DevicePerfService _perfService = DevicePerfService();
  DeviceProfile? _profile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDeviceProfile();
  }

  Future<void> _loadDeviceProfile() async {
    final profile = await _perfService.analyzeDevice();
    setState(() {
      _profile = profile;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background.withOpacity(0.8),
        title: const Text('设备性能分析'),
        centerTitle: true,
        elevation: 0,
      ),
      body: _isLoading || _profile == null
          ? const _LoadingView()
          : RefreshIndicator(
              onRefresh: _loadDeviceProfile,
              color: AppTheme.accent,
              backgroundColor: AppTheme.surface,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DeviceInfoCard(profile: _profile!),
                    const SizedBox(height: 16),
                    _UsageGaugesSection(profile: _profile!),
                    const SizedBox(height: 16),
                    _CpuInfoCard(profile: _profile!),
                    const SizedBox(height: 16),
                    _DeviceRatingCard(profile: _profile!),
                    const SizedBox(height: 16),
                    _CapabilityCard(profile: _profile!),
                    const SizedBox(height: 16),
                    _RecommendationsCard(profile: _profile!),
                    const SizedBox(height: 16),
                    _LanguageCapabilitiesCard(profile: _profile!),
                    const SizedBox(height: 16),
                    _OptimizationCard(profile: _profile!),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }
}

// ── Loading View ─────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppTheme.accent),
          SizedBox(height: 16),
          Text(
            '正在分析设备性能...',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Device Info Card ─────────────────────────────────────────────────

class _DeviceInfoCard extends StatelessWidget {
  final DeviceProfile profile;

  const _DeviceInfoCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.smartphone_outlined,
                  color: AppTheme.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profile.osVersion,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _InfoRow(label: '型号', value: profile.model),
          _InfoRow(label: '处理器', value: profile.processorType),
          _InfoRow(label: '架构', value: profile.is64Bit ? '64 位' : '32 位'),
        ],
      ),
    );
  }
}

// ── RAM & Storage Gauges ─────────────────────────────────────────────

class _UsageGaugesSection extends StatelessWidget {
  final DeviceProfile profile;

  const _UsageGaugesSection({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _GaugeCard(
            title: '内存',
            used: profile.totalRamMB - profile.availableRamMB,
            total: profile.totalRamMB,
            usedLabel: profile.ramInfo.totalFormatted,
            availableLabel: profile.ramInfo.availableFormatted,
            color: AppTheme.accent,
            icon: Icons.memory_outlined,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _GaugeCard(
            title: '存储',
            used: profile.totalStorageMB - profile.availableStorageMB,
            total: profile.totalStorageMB,
            usedLabel: profile.storageInfo.totalFormatted,
            availableLabel: profile.storageInfo.availableFormatted,
            color: AppTheme.primary,
            icon: Icons.storage_outlined,
          ),
        ),
      ],
    );
  }
}

class _GaugeCard extends StatelessWidget {
  final String title;
  final int used;
  final int total;
  final String usedLabel;
  final String availableLabel;
  final Color color;
  final IconData icon;

  const _GaugeCard({
    required this.title,
    required this.used,
    required this.total,
    required this.usedLabel,
    required this.availableLabel,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final percent = total > 0 ? used / total : 0.0;
    final percentText = '${(percent * 100).toStringAsFixed(1)}%';

    return _SectionCard(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 110,
            height: 110,
            child: CustomPaint(
              painter: _GaugePainter(
                percent: percent,
                color: color,
                bgColor: AppTheme.border,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      percentText,
                      style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    Text(
                      '已用',
                      style: const TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 10,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '总 $usedLabel',
            style: const TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── CPU Info Card ────────────────────────────────────────────────────

class _CpuInfoCard extends StatelessWidget {
  final DeviceProfile profile;

  const _CpuInfoCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: '处理器', icon: Icons.memory),
          const SizedBox(height: 12),
          Row(
            children: [
              _CpuMetricBox(
                label: '核心数',
                value: '${profile.cpuCores}',
                unit: '核',
                accentColor: AppTheme.accent,
              ),
              const SizedBox(width: 10),
              _CpuMetricBox(
                label: '主频',
                value: profile.cpuInfo.frequencyFormatted.split(' ')[0],
                unit: profile.cpuInfo.frequencyFormatted.split(' ').length > 1
                    ? profile.cpuInfo.frequencyFormatted.split(' ')[1]
                    : 'GHz',
                accentColor: AppTheme.primary,
              ),
              const SizedBox(width: 10),
              _CpuMetricBox(
                label: '架构',
                value: profile.is64Bit ? '64' : '32',
                unit: '位',
                accentColor: AppTheme.info,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            profile.cpuInfo.architecture,
            style: const TextStyle(
              fontFamily: AppTheme.fontCode,
              fontSize: 12,
              color: AppTheme.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CpuMetricBox extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color accentColor;

  const _CpuMetricBox({
    required this.label,
    required this.value,
    required this.unit,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: AppTheme.backgroundElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 11,
                color: AppTheme.textTertiary,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                  ),
                ),
                const SizedBox(width: 2),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    unit,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 11,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Device Rating Card ───────────────────────────────────────────────

class _DeviceRatingCard extends StatelessWidget {
  final DeviceProfile profile;

  const _DeviceRatingCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final rating = DevicePerfService().calculateDeviceRating(profile);
    final starColor = _ratingColor(rating);

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: '设备评分', icon: Icons.star_outline),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [starColor.withOpacity(0.3), starColor.withOpacity(0.1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: starColor.withOpacity(0.4)),
                ),
                child: Center(
                  child: Text(
                    '$rating',
                    style: TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: starColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: List.generate(10, (i) {
                        return Icon(
                          i < rating ? Icons.star : Icons.star_border,
                          color: i < rating ? starColor : AppTheme.border,
                          size: 18,
                        );
                      }),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _ratingDescription(rating),
                      style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 13,
                        color: starColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _ratingColor(int rating) {
    if (rating >= 8) return AppTheme.success;
    if (rating >= 5) return AppTheme.warning;
    return AppTheme.error;
  }

  String _ratingDescription(int rating) {
    if (rating >= 9) return '旗舰级设备，开发体验极佳';
    if (rating >= 8) return '性能优秀，适合各类开发';
    if (rating >= 7) return '性能良好，满足日常开发';
    if (rating >= 5) return '中等性能，中小型项目无压力';
    if (rating >= 3) return '性能一般，建议轻量级开发';
    return '入门级设备，开发体验有限';
  }
}

// ── Capability Card ──────────────────────────────────────────────────

class _CapabilityCard extends StatelessWidget {
  final DeviceProfile profile;

  const _CapabilityCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final capability = DevicePerfService().assessFlutterCapability(profile);

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: 'Flutter 开发能力', icon: Icons.flutter_dash),
          const SizedBox(height: 12),
          Text(
            capability.recommendation,
            style: const TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 14,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          _CapabilityRow(
            label: '小型项目 (<50 文件)',
            enabled: capability.canBuildSmall,
          ),
          _CapabilityRow(
            label: '中型项目 (50-200 文件)',
            enabled: capability.canBuildMedium,
          ),
          _CapabilityRow(
            label: '大型项目 (200-500 文件)',
            enabled: capability.canBuildLarge,
          ),
          _CapabilityRow(
            label: '超大型项目 (500+ 文件)',
            enabled: capability.canBuildVeryLarge,
          ),
          const Divider(color: AppTheme.divider, height: 20),
          _CapabilityRow(
            label: 'Hot Reload 流畅运行',
            enabled: capability.canUseHotReload,
          ),
          _CapabilityRow(
            label: '运行模拟器',
            enabled: capability.canRunEmulator,
          ),
        ],
      ),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  final String label;
  final bool enabled;

  const _CapabilityRow({required this.label, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            enabled ? Icons.check_circle : Icons.cancel,
            color: enabled ? AppTheme.success : AppTheme.error.withOpacity(0.6),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 13,
                color: enabled ? AppTheme.textSecondary : AppTheme.textTertiary,
              ),
            ),
          ),
          Text(
            enabled ? '支持' : '不支持',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: enabled ? AppTheme.success : AppTheme.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Recommendations Card ─────────────────────────────────────────────

class _RecommendationsCard extends StatelessWidget {
  final DeviceProfile profile;

  const _RecommendationsCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final recommendations = DevicePerfService().getRecommendedProjects(profile);

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: '推荐项目类型', icon: Icons.recommend),
          const SizedBox(height: 12),
          ...recommendations.map((rec) => _RecommendationItem(rec: rec)),
        ],
      ),
    );
  }
}

class _RecommendationItem extends StatelessWidget {
  final ProjectRecommendation rec;

  const _RecommendationItem({required this.rec});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: rec.isRecommended
            ? AppTheme.success.withOpacity(0.08)
            : AppTheme.warning.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: rec.isRecommended
              ? AppTheme.success.withOpacity(0.2)
              : AppTheme.warning.withOpacity(0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(
            rec.isRecommended ? Icons.check_circle_outline : Icons.error_outline,
            color: rec.isRecommended ? AppTheme.success : AppTheme.warning,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rec.type,
                  style: TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: rec.isRecommended ? AppTheme.textPrimary : AppTheme.textSecondary,
                  ),
                ),
                if (rec.warning != null)
                  Text(
                    rec.warning!,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 11,
                      color: AppTheme.warning,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.backgroundElevated,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              rec.complexity,
              style: const TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 11,
                color: AppTheme.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Language Capabilities Card ───────────────────────────────────────

class _LanguageCapabilitiesCard extends StatelessWidget {
  final DeviceProfile profile;

  const _LanguageCapabilitiesCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final languages = DevicePerfService().assessLanguageCapabilities(profile);

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: '语言支持', icon: Icons.code),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: const BoxDecoration(
                    color: AppTheme.backgroundElevated,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
                  ),
                  child: const Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          '语言',
                          style: TextStyle(
                            fontFamily: AppTheme.fontBody,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            '编辑',
                            style: TextStyle(
                              fontFamily: AppTheme.fontBody,
                              fontSize: 12,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            '运行',
                            style: TextStyle(
                              fontFamily: AppTheme.fontBody,
                              fontSize: 12,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            '调试',
                            style: TextStyle(
                              fontFamily: AppTheme.fontBody,
                              fontSize: 12,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: AppTheme.divider, height: 1),
                ...languages.asMap().entries.map((entry) {
                  final lang = entry.value;
                  final isLast = entry.key == languages.length - 1;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(
                                lang.language,
                                style: const TextStyle(
                                  fontFamily: AppTheme.fontBody,
                                  fontSize: 13,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: _BoolDot(value: lang.canEdit),
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: _BoolDot(value: lang.canRun),
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: _BoolDot(value: lang.canDebug),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isLast)
                        const Divider(color: AppTheme.divider, height: 1, indent: 12),
                    ],
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BoolDot extends StatelessWidget {
  final bool value;

  const _BoolDot({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: value ? AppTheme.success : AppTheme.error.withOpacity(0.5),
      ),
    );
  }
}

// ── Optimization Suggestions Card ────────────────────────────────────

class _OptimizationCard extends StatelessWidget {
  final DeviceProfile profile;

  const _OptimizationCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final suggestions = DevicePerfService().getOptimizationSuggestions(profile);

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: '优化建议', icon: Icons.tips_and_updates_outlined),
          const SizedBox(height: 12),
          ...suggestions.map((s) => _SuggestionItem(text: s)),
        ],
      ),
    );
  }
}

class _SuggestionItem extends StatelessWidget {
  final String text;

  const _SuggestionItem({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.arrow_right,
            color: AppTheme.accent,
            size: 18,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reusable Widgets ─────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final Widget child;

  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primary, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 13,
                color: AppTheme.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Gauge Painter ────────────────────────────────────────────────────

class _GaugePainter extends CustomPainter {
  final double percent;
  final Color color;
  final Color bgColor;

  _GaugePainter({
    required this.percent,
    required this.color,
    required this.bgColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 6;
    final strokeWidth = 10.0;

    // Background arc.
    final bgPaint = Paint()
      ..color = bgColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0.8 * math.pi,
      1.4 * math.pi,
      false,
      bgPaint,
    );

    // Foreground arc (clamped).
    final clampedPercent = percent.clamp(0.0, 1.0);
    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [color.withOpacity(0.6), color],
        startAngle: 0.8 * math.pi,
        endAngle: 0.8 * math.pi + 1.4 * math.pi,
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0.8 * math.pi,
      1.4 * math.pi * clampedPercent,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.percent != percent || oldDelegate.color != color;
  }
}

final math = const _Math();

class _Math {
  const _Math();
  double min(double a, double b) => a < b ? a : b;
}
