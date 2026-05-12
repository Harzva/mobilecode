// lib/screens/vibing_stats_screen.dart

import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/vibing_activity_service.dart';
import '../widgets/contribution_graph.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Vibing Stats Screen
// ═══════════════════════════════════════════════════════════════════════════

/// {@template vibing_stats_screen}
/// Vibing Coding statistics screen with GitHub-style contribution graph.
///
/// Shows contribution heatmap, coding statistics, streak info, hourly
/// distribution chart, language stats, achievement badges, and period selector.
///
/// Design: Dark theme, glassmorphism stat cards, custom contribution painter.
/// {@endtemplate}
class VibingStatsScreen extends StatefulWidget {
  const VibingStatsScreen({super.key});

  @override
  State<VibingStatsScreen> createState() => _VibingStatsScreenState();
}

class _VibingStatsScreenState extends State<VibingStatsScreen>
    with SingleTickerProviderStateMixin {
  final VibingActivityService _activityService = VibingActivityService();
  late TabController _tabController;

  bool _isLoading = true;
  List<ContributionDay> _contributionData = [];
  CodingStats? _codingStats;
  StreakInfo? _streakInfo;
  Map<int, int> _hourlyDistribution = {};
  List<LanguageStat> _languageStats = [];
  List<Achievement> _achievements = [];
  int _selectedPeriodIndex = 1; // Default to month.

  final List<String> _periodLabels = ['本周', '本月', '本年', '全部'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadData();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    setState(() => _selectedPeriodIndex = _tabController.index);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await _activityService.init();

    final now = DateTime.now();
    DateTime? start;

    switch (_selectedPeriodIndex) {
      case 0: // Week.
        start = now.subtract(Duration(days: now.weekday - 1));
      case 1: // Month.
        start = DateTime(now.year, now.month, 1);
      case 2: // Year.
        start = DateTime(now.year, 1, 1);
      case 3: // All.
        start = null;
    }

    final results = await Future.wait([
      _activityService.getContributionData(weeks: 52),
      _activityService.getStats(start: start),
      _activityService.getStreakInfo(),
      _activityService.getHourlyDistribution(),
      _activityService.getLanguageStats(),
      Future.value(_activityService.getAchievements()),
    ]);

    setState(() {
      _contributionData = results[0] as List<ContributionDay>;
      _codingStats = results[1] as CodingStats;
      _streakInfo = results[2] as StreakInfo;
      _hourlyDistribution = results[3] as Map<int, int>;
      _languageStats = results[4] as List<LanguageStat>;
      _achievements = results[5] as List<Achievement>;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background.withOpacity(0.8),
        title: const Text('Vibing Coding 活动'),
        centerTitle: true,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _periodLabels.map((l) => Tab(text: l)).toList(),
          labelColor: AppTheme.accent,
          unselectedLabelColor: AppTheme.textTertiary,
          indicatorColor: AppTheme.accent,
          labelStyle: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _isLoading
          ? const _LoadingView()
          : RefreshIndicator(
              onRefresh: _loadData,
              color: AppTheme.accent,
              backgroundColor: AppTheme.surface,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ContributionGraphSection(data: _contributionData),
                    const SizedBox(height: 20),
                    _StatsGrid(stats: _codingStats!),
                    const SizedBox(height: 20),
                    _StreakCard(streakInfo: _streakInfo!),
                    const SizedBox(height: 20),
                    _HourlyDistributionChart(distribution: _hourlyDistribution),
                    const SizedBox(height: 20),
                    _LanguageStatsCard(languages: _languageStats),
                    const SizedBox(height: 20),
                    _AchievementsGrid(achievements: _achievements),
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
            '加载活动数据...',
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

// ── Contribution Graph Section ───────────────────────────────────────

class _ContributionGraphSection extends StatelessWidget {
  final List<ContributionDay> data;

  const _ContributionGraphSection({required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.local_fire_department, color: AppTheme.accent, size: 20),
            const SizedBox(width: 8),
            const Text(
              '编码贡献图',
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const Spacer(),
            Text(
              '${data.where((d) => d.count > 0).length} 天活跃',
              style: const TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 12,
                color: AppTheme.textTertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ContributionGraph(
          data: data,
          onCellTap: (day) {
            _showDayDetail(context, day);
          },
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Text(
              '少',
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 11,
                color: AppTheme.textTertiary,
              ),
            ),
            const SizedBox(width: 6),
            ...List.generate(5, (i) {
              return Container(
                margin: const EdgeInsets.only(right: 4),
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: ContributionGraph.levelColor(i),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
            const SizedBox(width: 6),
            const Text(
              '多',
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 11,
                color: AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showDayDetail(BuildContext context, ContributionDay day) {
    final dateStr =
        '${day.date.year}-${day.date.month.toString().padLeft(2, '0')}-${day.date.day.toString().padLeft(2, '0')}';
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dateStr,
                style: const TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _DetailBadge(
                    label: '活动数',
                    value: '${day.count}',
                    color: AppTheme.accent,
                  ),
                  const SizedBox(width: 10),
                  _DetailBadge(
                    label: '活跃度',
                    value: _levelLabel(day.level),
                    color: ContributionGraph.levelColor(day.level),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: AppTheme.textOnPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('关闭'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _levelLabel(int level) {
    switch (level) {
      case 0:
        return '无活动';
      case 1:
        return '轻度';
      case 2:
        return '中等';
      case 3:
        return '活跃';
      case 4:
        return '高产';
      default:
        return '未知';
    }
  }
}

class _DetailBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _DetailBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
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
          Text(
            value,
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stats Grid ───────────────────────────────────────────────────────

class _StatsGrid extends StatelessWidget {
  final CodingStats stats;

  const _StatsGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    final items = [
      _StatItem(
        label: '编码时间',
        value: stats.formattedCodingTime,
        icon: Icons.timer_outlined,
        color: AppTheme.accent,
      ),
      _StatItem(
        label: '代码行数',
        value: '${stats.totalLinesChanged}',
        sublabel: '+${stats.totalLinesWritten} / -${stats.totalLinesDeleted}',
        icon: Icons.code,
        color: AppTheme.primary,
      ),
      _StatItem(
        label: 'AI 交互',
        value: '${stats.totalAiInteractions}',
        icon: Icons.chat_bubble_outline,
        color: const Color(0xFFD97757),
      ),
      _StatItem(
        label: 'Git 提交',
        value: '${stats.totalGitCommits}',
        icon: Icons.commit,
        color: AppTheme.success,
      ),
      _StatItem(
        label: '活跃天数',
        value: '${stats.activeDays}',
        icon: Icons.calendar_today_outlined,
        color: AppTheme.info,
      ),
      _StatItem(
        label: '日均(分)',
        value: '${stats.averageDailyMinutes.toStringAsFixed(0)}',
        icon: Icons.trending_up,
        color: const Color(0xFF9333EA),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.1,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => _StatCard(item: items[index]),
    );
  }
}

class _StatItem {
  final String label;
  final String value;
  final String? sublabel;
  final IconData icon;
  final Color color;

  _StatItem({
    required this.label,
    required this.value,
    this.sublabel,
    required this.icon,
    required this.color,
  });
}

class _StatCard extends StatelessWidget {
  final _StatItem item;

  const _StatCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.surface,
            AppTheme.backgroundElevated,
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(item.icon, color: item.color, size: 22),
          const SizedBox(height: 8),
          Text(
            item.value,
            style: const TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          if (item.sublabel != null)
            Text(
              item.sublabel!,
              style: const TextStyle(
                fontFamily: AppTheme.fontCode,
                fontSize: 9,
                color: AppTheme.textTertiary,
              ),
            )
          else
            const SizedBox(height: 2),
          Text(
            item.label,
            style: const TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 11,
              color: AppTheme.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Streak Card ──────────────────────────────────────────────────────

class _StreakCard extends StatelessWidget {
  final StreakInfo streakInfo;

  const _StreakCard({required this.streakInfo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1520), Color(0xFF111827)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '当前连续',
                      style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      '🔥',
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${streakInfo.currentStreak}',
                      style: const TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accent,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Text(
                        ' 天',
                        style: TextStyle(
                          fontFamily: AppTheme.fontBody,
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                if (streakInfo.lastActiveDay != null)
                  Text(
                    '最后活跃: ${_formatDate(streakInfo.lastActiveDay!)}',
                    style: const TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 11,
                      color: AppTheme.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 60,
            color: AppTheme.divider,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '最长连续',
                  style: TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${streakInfo.longestStreak}',
                      style: const TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.warning,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Text(
                        ' 天',
                        style: TextStyle(
                          fontFamily: AppTheme.fontBody,
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  '始于 ${_formatDate(streakInfo.streakStart)}',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 11,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}';
  }
}

// ── Hourly Distribution Chart ────────────────────────────────────────

class _HourlyDistributionChart extends StatelessWidget {
  final Map<int, int> distribution;

  const _HourlyDistributionChart({required this.distribution});

  @override
  Widget build(BuildContext context) {
    final maxValue = distribution.values.isEmpty
        ? 1
        : distribution.values.reduce(math.max);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.access_time, color: AppTheme.primary, size: 18),
              SizedBox(width: 8),
              Text(
                '活跃时段分布',
                style: TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(24, (hour) {
                final value = distribution[hour] ?? 0;
                final heightFraction = maxValue > 0 ? value / maxValue : 0.0;
                final isPeak = value == maxValue && maxValue > 0;

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          width: double.infinity,
                          height: math.max(4, 90 * heightFraction),
                          decoration: BoxDecoration(
                            color: isPeak
                                ? AppTheme.accent
                                : AppTheme.accent.withOpacity(0.3 + heightFraction * 0.5),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3),
                            ),
                          ),
                        ),
                        if (hour % 4 == 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '$hour',
                              style: const TextStyle(
                                fontFamily: AppTheme.fontBody,
                                fontSize: 9,
                                color: AppTheme.textTertiary,
                              ),
                            ),
                          )
                        else
                          const SizedBox(height: 16),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Language Stats Card ──────────────────────────────────────────────

class _LanguageStatsCard extends StatelessWidget {
  final List<LanguageStat> languages;

  const _LanguageStatsCard({required this.languages});

  @override
  Widget build(BuildContext context) {
    final maxLines = languages.isEmpty ? 1 : languages.map((l) => l.lines).reduce(math.max);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.language, color: AppTheme.info, size: 18),
              SizedBox(width: 8),
              Text(
                '常用语言',
                style: TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...languages.asMap().entries.map((entry) {
            final lang = entry.value;
            final barFraction = maxLines > 0 ? lang.lines / maxLines : 0.0;
            final colors = [
              AppTheme.accent,
              AppTheme.primary,
              AppTheme.info,
              AppTheme.success,
              AppTheme.warning,
              const Color(0xFFEC4899),
            ];
            final barColor = colors[entry.key % colors.length];

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 70,
                    child: Text(
                      lang.language,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppTheme.backgroundElevated,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: barFraction.clamp(0.05, 1.0),
                          child: Container(
                            height: 8,
                            decoration: BoxDecoration(
                              color: barColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 50,
                    child: Text(
                      '${lang.percentage.toStringAsFixed(1)}%',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontCode,
                        fontSize: 11,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Achievements Grid ────────────────────────────────────────────────

class _AchievementsGrid extends StatelessWidget {
  final List<Achievement> achievements;

  const _AchievementsGrid({required this.achievements});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events_outlined, color: AppTheme.warning, size: 18),
              const SizedBox(width: 8),
              const Text(
                '成就徽章',
                style: TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '${achievements.where((a) => a.isUnlocked).length}/${achievements.length}',
                style: const TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 13,
                  color: AppTheme.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.85,
            ),
            itemCount: achievements.length,
            itemBuilder: (context, index) {
              final ach = achievements[index];
              return _AchievementBadge(achievement: ach);
            },
          ),
        ],
      ),
    );
  }
}

class _AchievementBadge extends StatelessWidget {
  final Achievement achievement;

  const _AchievementBadge({required this.achievement});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: achievement.isUnlocked ? 1.0 : 0.35,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: achievement.isUnlocked
                  ? LinearGradient(
                      colors: [
                        AppTheme.primary.withOpacity(0.3),
                        AppTheme.accent.withOpacity(0.2),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: achievement.isUnlocked ? null : AppTheme.backgroundElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: achievement.isUnlocked
                    ? AppTheme.primary.withOpacity(0.4)
                    : AppTheme.border,
              ),
            ),
            child: Center(
              child: Text(
                achievement.icon,
                style: const TextStyle(fontSize: 24),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            achievement.name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 10,
              fontWeight: achievement.isUnlocked ? FontWeight.w600 : FontWeight.normal,
              color: achievement.isUnlocked ? AppTheme.textPrimary : AppTheme.textTertiary,
            ),
          ),
          if (!achievement.isUnlocked)
            Container(
              margin: const EdgeInsets.only(top: 4),
              width: 36,
              height: 3,
              decoration: BoxDecoration(
                color: AppTheme.backgroundElevated,
                borderRadius: BorderRadius.circular(2),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: achievement.progress / 100,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
