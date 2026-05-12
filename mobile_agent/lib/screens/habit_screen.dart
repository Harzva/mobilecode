// lib/screens/habit_screen.dart
// Habit Screen — Shows user's coding habits and productivity patterns.
//
// Features:
// - Active hours: Horizontal bar chart (24-hour distribution)
// - Language preferences: Colored horizontal bars
// - Weekly trend: Line chart (coding time over weeks)
// - Coding streak: Current + longest streak display
// - Weekly report: Summary stats card
// - Productivity analysis: Peak hours, consistency score
// - Habit achievements: Badges for consistent coding
//
// Design: Data visualization, charts, dark theme with accent colors.

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/habit_service.dart';
import '../widgets/hourly_distribution_chart.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Habit Screen
// ═══════════════════════════════════════════════════════════════════════════

/// Habit Screen — Comprehensive view of user's coding habits.
///
/// Displays active hours, language preferences, weekly trends,
/// coding streaks, productivity analysis, and habit achievements.
class HabitScreen extends StatefulWidget {
  const HabitScreen({super.key});

  @override
  State<HabitScreen> createState() => _HabitScreenState();
}

class _HabitScreenState extends State<HabitScreen> {
  final HabitService _habit = HabitService();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _habit.init();
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : CustomScrollView(
              slivers: [
                // Header
                SliverAppBar(
                  floating: true,
                  pinned: true,
                  backgroundColor: AppTheme.background.withOpacity(0.9),
                  elevation: 0,
                  expandedHeight: 120,
                  flexibleSpace: FlexibleSpaceBar(
                    title: const Text(
                      '我的编码习惯',
                      style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    background: Container(
                      decoration: const BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                      ),
                    ),
                  ),
                ),
                // Content
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      // Active Hours Chart
                      _ActiveHoursCard(habit: _habit),
                      // Language Preferences
                      _LanguagePreferencesCard(habit: _habit),
                      // Weekly Trend
                      _WeeklyTrendCard(habit: _habit),
                      // Coding Streak
                      _CodingStreakCard(habit: _habit),
                      // Weekly Report
                      _WeeklyReportCard(habit: _habit),
                      // Productivity Analysis
                      _ProductivityAnalysisCard(habit: _habit),
                      // Habit Achievements
                      _HabitAchievementsCard(),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Card Wrapper
// ═══════════════════════════════════════════════════════════════════════════

class _HabitCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget child;

  const _HabitCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: iconColor, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    title,
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
            Padding(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Active Hours Card
// ═══════════════════════════════════════════════════════════════════════════

class _ActiveHoursCard extends StatelessWidget {
  final HabitService habit;

  const _ActiveHoursCard({required this.habit});

  @override
  Widget build(BuildContext context) {
    return _HabitCard(
      title: '活跃时段',
      icon: Icons.access_time,
      iconColor: AppTheme.primary,
      child: FutureBuilder<Map<int, int>>(
        future: habit.getHourlyDistribution(),
        builder: (context, snapshot) {
          final distribution = snapshot.data ?? {};
          if (distribution.isEmpty) {
            return const SizedBox(
              height: 80,
              child: Center(
                child: Text(
                  '暂无数据',
                  style: TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 13,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ),
            );
          }
          return HourlyDistributionChart(distribution: distribution);
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Language Preferences Card
// ═══════════════════════════════════════════════════════════════════════════

class _LanguagePreferencesCard extends StatelessWidget {
  final HabitService habit;

  const _LanguagePreferencesCard({required this.habit});

  @override
  Widget build(BuildContext context) {
    return _HabitCard(
      title: '语言偏好',
      icon: Icons.language,
      iconColor: AppTheme.accent,
      child: FutureBuilder<List<LanguageHabit>>(
        future: habit.getLanguageHabits(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SizedBox(
              height: 60,
              child: Center(child: CircularProgressIndicator(color: AppTheme.accent)),
            );
          }
          final languages = snapshot.data!;
          if (languages.isEmpty) {
            return const _EmptyCard(text: '暂无语言数据');
          }
          return Column(
            children: languages.map((lang) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _parseColor(lang.color),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 80,
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
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: lang.usagePercent / 100,
                          backgroundColor: AppTheme.border,
                          valueColor: AlwaysStoppedAnimation<Color>(_parseColor(lang.color)),
                          minHeight: 8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 40,
                      child: Text(
                        '${lang.usagePercent}%',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontBody,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return AppTheme.primary;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Weekly Trend Card
// ═══════════════════════════════════════════════════════════════════════════

class _WeeklyTrendCard extends StatelessWidget {
  final HabitService habit;

  const _WeeklyTrendCard({required this.habit});

  @override
  Widget build(BuildContext context) {
    return _HabitCard(
      title: '周趋势',
      icon: Icons.trending_up,
      iconColor: AppTheme.info,
      child: FutureBuilder<List<WeeklySummary>>(
        future: habit.getWeeklySummaries(weeks: 12),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator(color: AppTheme.info)),
            );
          }
          final weeks = snapshot.data!;
          if (weeks.isEmpty) {
            return const _EmptyCard(text: '暂无周趋势数据');
          }

          // Find max for normalization.
          final maxMinutes = weeks
                  .map((w) => w.codingMinutes)
                  .reduce((a, b) => a > b ? a : b)
                  .toDouble() *
              1.2;

          return SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: weeks.map((week) {
                final height = maxMinutes > 0 ? week.codingMinutes / maxMinutes : 0.0;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Tooltip value
                        Text(
                          week.codingMinutes > 60
                              ? '${week.codingMinutes ~/ 60}h'
                              : '${week.codingMinutes}m',
                          style: const TextStyle(
                            fontFamily: AppTheme.fontBody,
                            fontSize: 9,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Bar
                        Container(
                          height: height * 80,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [AppTheme.primary, AppTheme.accent],
                            ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Week label
                        Text(
                          week.weekLabel.split('-').first,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontBody,
                            fontSize: 8,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Coding Streak Card
// ═══════════════════════════════════════════════════════════════════════════

class _CodingStreakCard extends StatelessWidget {
  final HabitService habit;

  const _CodingStreakCard({required this.habit});

  @override
  Widget build(BuildContext context) {
    return _HabitCard(
      title: '连续编码',
      icon: Icons.local_fire_department,
      iconColor: Colors.orange,
      child: Row(
        children: [
          Expanded(
            child: _StreakItem(
              label: '当前连续',
              value: '3',
              subtitle: '天',
              color: Colors.orange,
              icon: Icons.local_fire_department,
            ),
          ),
          Container(width: 1, height: 60, color: AppTheme.border),
          Expanded(
            child: _StreakItem(
              label: '最长连续',
              value: '7',
              subtitle: '天',
              color: AppTheme.primary,
              icon: Icons.emoji_events,
            ),
          ),
          Container(width: 1, height: 60, color: AppTheme.border),
          Expanded(
            child: _StreakItem(
              label: '本周编码',
              value: '12h',
              subtitle: '30m',
              color: AppTheme.accent,
              icon: Icons.timer,
            ),
          ),
        ],
      ),
    );
  }
}

class _StreakItem extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final Color color;
  final IconData icon;

  const _StreakItem({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 6),
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
          children: [
            Text(
              value,
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              subtitle,
              style: const TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Weekly Report Card
// ═══════════════════════════════════════════════════════════════════════════

class _WeeklyReportCard extends StatelessWidget {
  final HabitService habit;

  const _WeeklyReportCard({required this.habit});

  @override
  Widget build(BuildContext context) {
    return _HabitCard(
      title: '本周报告',
      icon: Icons.summarize,
      iconColor: AppTheme.warning,
      child: FutureBuilder<WeeklyReport>(
        future: habit.generateWeeklyReport(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.warning));
          }
          final report = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Week label + comparison
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    report.weekLabel,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: report.comparisonToLastWeek.startsWith('+')
                          ? AppTheme.success.withOpacity(0.15)
                          : report.comparisonToLastWeek.startsWith('-')
                              ? AppTheme.error.withOpacity(0.15)
                              : AppTheme.border,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      report.comparisonToLastWeek,
                      style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: report.comparisonToLastWeek.startsWith('+')
                            ? AppTheme.success
                            : report.comparisonToLastWeek.startsWith('-')
                                ? AppTheme.error
                                : AppTheme.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Stats grid
              Row(
                children: [
                  _ReportStat(
                    icon: Icons.timer_outlined,
                    label: '编码时间',
                    value: report.formattedCodingTime,
                  ),
                  _ReportStat(
                    icon: Icons.edit_note,
                    label: '编辑文件',
                    value: '${report.totalFilesEdited}',
                  ),
                  _ReportStat(
                    icon: Icons.commit,
                    label: '提交',
                    value: '${report.totalCommits}',
                  ),
                  _ReportStat(
                    icon: Icons.smart_toy_outlined,
                    label: 'AI 协作',
                    value: '${report.totalAiInteractions}',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Highlights
              ...report.highlights.map((h) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.star, color: AppTheme.warning, size: 12),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          h,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontBody,
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _ReportStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ReportStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: AppTheme.textTertiary, size: 18),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 10,
              color: AppTheme.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Productivity Analysis Card
// ═══════════════════════════════════════════════════════════════════════════

class _ProductivityAnalysisCard extends StatelessWidget {
  final HabitService habit;

  const _ProductivityAnalysisCard({required this.habit});

  @override
  Widget build(BuildContext context) {
    return _HabitCard(
      title: '生产力分析',
      icon: Icons.analytics,
      iconColor: Colors.purple,
      child: FutureBuilder<ProductivityPattern>(
        future: habit.getProductivityPattern(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: Colors.purple));
          }
          final pattern = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Peak hours
              Row(
                children: [
                  const Icon(Icons.trending_up, color: AppTheme.success, size: 16),
                  const SizedBox(width: 8),
                  const Text(
                    '高效时段:',
                    style: TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ...pattern.peakHours.map((h) {
                    return Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        h,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontBody,
                          fontSize: 11,
                          color: AppTheme.success,
                        ),
                      ),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 10),
              // Low hours
              Row(
                children: [
                  const Icon(Icons.trending_down, color: AppTheme.error, size: 16),
                  const SizedBox(width: 8),
                  const Text(
                    '低效时段:',
                    style: TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ...pattern.lowHours.map((h) {
                    return Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        h,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontBody,
                          fontSize: 11,
                          color: AppTheme.error,
                        ),
                      ),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 14),
              // Stats row
              Row(
                children: [
                  _ProductivityStat(
                    label: '平均时长',
                    value: '${pattern.averageSessionMinutes}m',
                  ),
                  _ProductivityStat(
                    label: '最长时长',
                    value: '${pattern.longestSessionMinutes}m',
                  ),
                  _ProductivityStat(
                    label: '最佳日期',
                    value: pattern.mostProductiveDayName,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Consistency score
              Row(
                children: [
                  const Text(
                    '稳定度评分:',
                    style: TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pattern.consistencyScore / 100,
                        backgroundColor: AppTheme.border,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          pattern.consistencyScore >= 80
                              ? AppTheme.success
                              : pattern.consistencyScore >= 60
                                  ? AppTheme.warning
                                  : AppTheme.error,
                        ),
                        minHeight: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${pattern.consistencyScore.toStringAsFixed(0)} (${pattern.consistencyGrade})',
                    style: TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: pattern.consistencyScore >= 80
                          ? AppTheme.success
                          : pattern.consistencyScore >= 60
                              ? AppTheme.warning
                              : AppTheme.error,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProductivityStat extends StatelessWidget {
  final String label;
  final String value;

  const _ProductivityStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.backgroundElevated,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 10,
                color: AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Habit Achievements Card
// ═══════════════════════════════════════════════════════════════════════════

class _HabitAchievementsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final achievements = [
      _AchievementData(name: '初出茅庐', desc: '编码第1天', icon: Icons.computer, unlocked: true, color: AppTheme.info),
      _AchievementData(name: '坚持不懈', desc: '连续3天编码', icon: Icons.local_fire_department, unlocked: true, color: Colors.orange),
      _AchievementData(name: '代码狂人', desc: '连续7天编码', icon: Icons.bolt, unlocked: false, color: AppTheme.primary),
      _AchievementData(name: '多面手', desc: '使用3种语言', icon: Icons.language, unlocked: true, color: AppTheme.accent),
      _AchievementData(name: '夜猫子', desc: '23:00后编码', icon: Icons.nights_stay, unlocked: false, color: Colors.indigo),
      _AchievementData(name: '早起的鸟儿', desc: '06:00前编码', icon: Icons.wb_sunny, unlocked: false, color: AppTheme.warning),
    ];

    return _HabitCard(
      title: '习惯成就',
      icon: Icons.emoji_events,
      iconColor: AppTheme.warning,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: achievements.map((a) {
          return SizedBox(
            width: (MediaQuery.of(context).size.width - 80) / 3,
            child: Opacity(
              opacity: a.unlocked ? 1.0 : 0.4,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: a.unlocked ? a.color.withOpacity(0.1) : AppTheme.backgroundElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: a.unlocked
                      ? Border.all(color: a.color.withOpacity(0.3), width: 1)
                      : null,
                ),
                child: Column(
                  children: [
                    Icon(a.icon, color: a.unlocked ? a.color : AppTheme.textTertiary, size: 24),
                    const SizedBox(height: 6),
                    Text(
                      a.name,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: a.unlocked ? AppTheme.textPrimary : AppTheme.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      a.desc,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 9,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _AchievementData {
  final String name;
  final String desc;
  final IconData icon;
  final bool unlocked;
  final Color color;

  _AchievementData({
    required this.name,
    required this.desc,
    required this.icon,
    required this.unlocked,
    required this.color,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Empty Card Helper
// ═══════════════════════════════════════════════════════════════════════════

class _EmptyCard extends StatelessWidget {
  final String text;

  const _EmptyCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 13,
            color: AppTheme.textTertiary,
          ),
        ),
      ),
    );
  }
}
