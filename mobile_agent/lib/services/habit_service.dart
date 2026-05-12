// lib/services/habit_service.dart
// Habit Service — Tracks user's coding habits and patterns over time.
//
// Analyzes coding activity to produce insights:
// - Daily/weekly coding time distribution
// - Most productive hours and days
// - Programming language preferences
// - Project type preferences
// - Coding streaks
// - Weekly and monthly productivity reports
//
// Usage:
// ```dart
// final habit = HabitService();
// await habit.init();
// final weekly = await habit.generateWeeklyReport();
// final languages = await habit.getLanguageHabits();
// ```

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Data Models
// ═══════════════════════════════════════════════════════════════════════════

/// Summary of a single week's coding activity.
@immutable
class WeeklySummary {
  final String weekLabel;
  final int codingMinutes;
  final int filesEdited;
  final int commits;
  final int aiInteractions;
  final String primaryLanguage;

  const WeeklySummary({
    required this.weekLabel,
    required this.codingMinutes,
    required this.filesEdited,
    required this.commits,
    required this.aiInteractions,
    required this.primaryLanguage,
  });

  /// Formatted coding time (e.g., "12h 30m").
  String get formattedCodingTime {
    final hours = codingMinutes ~/ 60;
    final mins = codingMinutes % 60;
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }

  Map<String, dynamic> toJson() => {
        'weekLabel': weekLabel,
        'codingMinutes': codingMinutes,
        'filesEdited': filesEdited,
        'commits': commits,
        'aiInteractions': aiInteractions,
        'primaryLanguage': primaryLanguage,
      };
}

/// Language usage habit with statistics.
@immutable
class LanguageHabit {
  final String language;
  final int usagePercent;
  final int filesCount;
  final int linesOfCode;
  final String color;

  const LanguageHabit({
    required this.language,
    required this.usagePercent,
    required this.filesCount,
    required this.linesOfCode,
    required this.color,
  });

  Map<String, dynamic> toJson() => {
        'language': language,
        'usagePercent': usagePercent,
        'filesCount': filesCount,
        'linesOfCode': linesOfCode,
        'color': color,
      };
}

/// Project type preference statistics.
@immutable
class ProjectTypeHabit {
  final String projectType;
  final int projectCount;
  final int totalFiles;
  final int codingMinutes;
  final double percentage;

  const ProjectTypeHabit({
    required this.projectType,
    required this.projectCount,
    required this.totalFiles,
    required this.codingMinutes,
    required this.percentage,
  });

  Map<String, dynamic> toJson() => {
        'projectType': projectType,
        'projectCount': projectCount,
        'totalFiles': totalFiles,
        'codingMinutes': codingMinutes,
        'percentage': percentage,
      };
}

/// Productivity pattern analysis.
@immutable
class ProductivityPattern {
  final List<String> peakHours;
  final List<String> lowHours;
  final int averageSessionMinutes;
  final int longestSessionMinutes;
  final int mostProductiveDay;
  final double consistencyScore;

  const ProductivityPattern({
    required this.peakHours,
    required this.lowHours,
    required this.averageSessionMinutes,
    required this.longestSessionMinutes,
    required this.mostProductiveDay,
    required this.consistencyScore,
  });

  /// Most productive day name (Monday-Sunday).
  String get mostProductiveDayName {
    const days = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return days[mostProductiveDay.clamp(1, 7) - 1];
  }

  /// Consistency score as a grade (A-F).
  String get consistencyGrade {
    if (consistencyScore >= 90) return 'A';
    if (consistencyScore >= 80) return 'B';
    if (consistencyScore >= 70) return 'C';
    if (consistencyScore >= 60) return 'D';
    return 'F';
  }

  Map<String, dynamic> toJson() => {
        'peakHours': peakHours,
        'lowHours': lowHours,
        'averageSessionMinutes': averageSessionMinutes,
        'longestSessionMinutes': longestSessionMinutes,
        'mostProductiveDay': mostProductiveDay,
        'consistencyScore': consistencyScore,
      };
}

/// A complete weekly report.
@immutable
class WeeklyReport {
  final String weekLabel;
  final int totalCodingMinutes;
  final int totalFilesEdited;
  final int totalCommits;
  final int totalAiInteractions;
  final List<String> highlights;
  final String comparisonToLastWeek;

  const WeeklyReport({
    required this.weekLabel,
    required this.totalCodingMinutes,
    required this.totalFilesEdited,
    required this.totalCommits,
    required this.totalAiInteractions,
    required this.highlights,
    required this.comparisonToLastWeek,
  });

  String get formattedCodingTime {
    final hours = totalCodingMinutes ~/ 60;
    final mins = totalCodingMinutes % 60;
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }
}

/// A complete monthly report.
@immutable
class MonthlyReport {
  final String monthLabel;
  final int totalCodingMinutes;
  final int totalFilesEdited;
  final int totalCommits;
  final int totalAiInteractions;
  final int activeDays;
  final int longestStreak;
  final List<String> topLanguages;
  final List<WeeklySummary> weeklyBreakdown;

  const MonthlyReport({
    required this.monthLabel,
    required this.totalCodingMinutes,
    required this.totalFilesEdited,
    required this.totalCommits,
    required this.totalAiInteractions,
    required this.activeDays,
    required this.longestStreak,
    required this.topLanguages,
    required this.weeklyBreakdown,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Habit Service
// ═══════════════════════════════════════════════════════════════════════════

/// Tracks user's coding habits and generates productivity insights.
///
/// This service analyzes raw activity data to produce meaningful patterns
/// and reports. It works closely with [VibingActivityService] to get
/// raw activity events and aggregates them into actionable insights.
class HabitService extends ChangeNotifier {
  SharedPreferences? _prefs;
  bool _initialized = false;

  // Raw data storage — daily activity records.
  final Map<String, _DailyRecord> _dailyRecords = {};

  // Storage key
  static const String _storageKey = 'habit_daily_records';

  // Singleton
  static HabitService? _instance;
  factory HabitService() {
    _instance ??= HabitService._internal();
    return _instance!;
  }
  HabitService._internal();

  // ── Initialization ─────────────────────────────────────────────────

  /// Initialize the service and load persisted data.
  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    await _loadRecords();
    _initialized = true;
    debugPrint('[HabitService] Initialized with ${_dailyRecords.length} daily records');
  }

  void _ensureInit() {
    if (!_initialized) throw StateError('HabitService not initialized. Call init() first.');
  }

  // ── Time Tracking ──────────────────────────────────────────────────

  /// Record a coding activity event for habit tracking.
  Future<void> recordActivity({
    required DateTime timestamp,
    int minutes = 1,
    String? language,
    String? projectType,
    int filesEdited = 0,
    int commits = 0,
    int aiInteractions = 0,
  }) async {
    _ensureInit();
    final key = _dateKey(timestamp);
    final existing = _dailyRecords[key];

    if (existing != null) {
      existing.codingMinutes += minutes;
      existing.filesEdited += filesEdited;
      existing.commits += commits;
      existing.aiInteractions += aiInteractions;
      if (language != null) {
        existing.languageMinutes[language] =
            (existing.languageMinutes[language] ?? 0) + minutes;
      }
      existing.hourlyActivity[timestamp.hour] =
          (existing.hourlyActivity[timestamp.hour] ?? 0) + minutes;
    } else {
      final record = _DailyRecord(
        date: DateTime(timestamp.year, timestamp.month, timestamp.day),
        codingMinutes: minutes,
        filesEdited: filesEdited,
        commits: commits,
        aiInteractions: aiInteractions,
      );
      if (language != null) {
        record.languageMinutes[language] = minutes;
      }
      record.hourlyActivity[timestamp.hour] = minutes;
      _dailyRecords[key] = record;
    }

    await _persistRecords();
  }

  /// Get hourly activity distribution for the last N days.
  Future<Map<int, int>> getHourlyDistribution({int days = 30}) async {
    _ensureInit();
    final distribution = <int, int>{};
    for (var h = 0; h < 24; h++) distribution[h] = 0;

    final cutoff = DateTime.now().subtract(Duration(days: days));
    for (final entry in _dailyRecords.entries) {
      if (entry.value.date.isBefore(cutoff)) continue;
      for (final hourEntry in entry.value.hourlyActivity.entries) {
        distribution[hourEntry.key] = (distribution[hourEntry.key] ?? 0) + hourEntry.value;
      }
    }

    return distribution;
  }

  /// Get daily activity distribution for the last N days.
  Future<Map<String, int>> getDailyDistribution({int days = 30}) async {
    _ensureInit();
    final distribution = <String, int>{};
    final now = DateTime.now();

    for (var i = days - 1; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final key = _dateKey(date);
      final record = _dailyRecords[key];
      distribution[key] = record?.codingMinutes ?? 0;
    }

    return distribution;
  }

  /// Get weekly summaries for the last N weeks.
  Future<List<WeeklySummary>> getWeeklySummaries({int weeks = 12}) async {
    _ensureInit();
    final summaries = <WeeklySummary>[];
    final now = DateTime.now();

    for (var w = weeks - 1; w >= 0; w--) {
      final weekEnd = now.subtract(Duration(days: w * 7));
      final weekStart = weekEnd.subtract(const Duration(days: 6));
      final weekLabel = '${weekStart.month}/${weekStart.day}-${weekEnd.month}/${weekEnd.day}';

      var codingMinutes = 0;
      var filesEdited = 0;
      var commits = 0;
      var aiInteractions = 0;
      final langMinutes = <String, int>{};

      for (var d = 0; d < 7; d++) {
        final date = weekStart.add(Duration(days: d));
        final key = _dateKey(date);
        final record = _dailyRecords[key];
        if (record != null) {
          codingMinutes += record.codingMinutes;
          filesEdited += record.filesEdited;
          commits += record.commits;
          aiInteractions += record.aiInteractions;
          for (final le in record.languageMinutes.entries) {
            langMinutes[le.key] = (langMinutes[le.key] ?? 0) + le.value;
          }
        }
      }

      // Determine primary language for the week.
      String primaryLanguage = 'Unknown';
      if (langMinutes.isNotEmpty) {
        primaryLanguage = langMinutes.entries
            .reduce((a, b) => a.value > b.value ? a : b)
            .key;
      }

      summaries.add(WeeklySummary(
        weekLabel: weekLabel,
        codingMinutes: codingMinutes,
        filesEdited: filesEdited,
        commits: commits,
        aiInteractions: aiInteractions,
        primaryLanguage: primaryLanguage,
      ));
    }

    return summaries;
  }

  // ── Language Preferences ───────────────────────────────────────────

  /// Get language usage habits.
  Future<List<LanguageHabit>> getLanguageHabits() async {
    _ensureInit();
    final langMinutes = <String, int>{};
    final langFiles = <String, int>{};

    for (final record in _dailyRecords.values) {
      for (final entry in record.languageMinutes.entries) {
        langMinutes[entry.key] = (langMinutes[entry.key] ?? 0) + entry.value;
        langFiles[entry.key] = (langFiles[entry.key] ?? 0) + record.filesEdited;
      }
    }

    if (langMinutes.isEmpty) {
      // Return demo data.
      return const [
        LanguageHabit(language: 'Dart', usagePercent: 45, filesCount: 24, linesOfCode: 3200, color: '#00B4AB'),
        LanguageHabit(language: 'Python', usagePercent: 25, filesCount: 12, linesOfCode: 1800, color: '#3776AB'),
        LanguageHabit(language: 'JavaScript', usagePercent: 15, filesCount: 8, linesOfCode: 1100, color: '#F7DF1E'),
        LanguageHabit(language: 'Go', usagePercent: 10, filesCount: 5, linesOfCode: 720, color: '#00ADD8'),
        LanguageHabit(language: 'Rust', usagePercent: 5, filesCount: 3, linesOfCode: 380, color: '#DEA584'),
      ];
    }

    final totalMinutes = langMinutes.values.fold<int>(0, (s, v) => s + v);
    final colors = <String, String>{
      'Dart': '#00B4AB',
      'Python': '#3776AB',
      'JavaScript': '#F7DF1E',
      'TypeScript': '#3178C6',
      'Go': '#00ADD8',
      'Rust': '#DEA584',
      'Java': '#E76F00',
      'Kotlin': '#7F52FF',
      'Swift': '#F05138',
      'C++': '#00599C',
      'HTML': '#E34F26',
      'CSS': '#1572B6',
    };

    final habits = langMinutes.entries.map((e) {
      final pct = totalMinutes > 0 ? (e.value / totalMinutes * 100).round() : 0;
      return LanguageHabit(
        language: e.key,
        usagePercent: pct,
        filesCount: langFiles[e.key] ?? 0,
        linesOfCode: e.value * 15, // Rough estimate: ~15 LOC per minute
        color: colors[e.key] ?? '#9CA3AF',
      );
    }).toList();

    habits.sort((a, b) => b.usagePercent.compareTo(a.usagePercent));
    return habits;
  }

  /// Get the most used programming language.
  Future<String> getPrimaryLanguage() async {
    final habits = await getLanguageHabits();
    if (habits.isEmpty) return 'Unknown';
    return habits.first.language;
  }

  /// Get the second most used programming language.
  Future<String> getSecondaryLanguage() async {
    final habits = await getLanguageHabits();
    if (habits.length < 2) return 'None';
    return habits[1].language;
  }

  // ── Project Preferences ────────────────────────────────────────────

  /// Get project type usage habits.
  Future<List<ProjectTypeHabit>> getProjectTypeHabits() async {
    _ensureInit();
    // In production, this would aggregate from actual project data.
    // For now, return demo data.
    return const [
      ProjectTypeHabit(projectType: 'Flutter 应用', projectCount: 5, totalFiles: 142, codingMinutes: 3420, percentage: 45.0),
      ProjectTypeHabit(projectType: 'Python 脚本', projectCount: 8, totalFiles: 64, codingMinutes: 1890, percentage: 25.0),
      ProjectTypeHabit(projectType: 'Web 前端', projectCount: 3, totalFiles: 48, codingMinutes: 1080, percentage: 14.0),
      ProjectTypeHabit(projectType: 'Go 服务', projectCount: 2, totalFiles: 28, codingMinutes: 720, percentage: 9.5),
      ProjectTypeHabit(projectType: '工具脚本', projectCount: 4, totalFiles: 20, codingMinutes: 510, percentage: 6.5),
    ];
  }

  // ── Productivity Patterns ──────────────────────────────────────────

  /// Analyze overall productivity patterns.
  Future<ProductivityPattern> getProductivityPattern() async {
    _ensureInit();
    final hourlyDist = await getHourlyDistribution(days: 30);

    // Find peak hours (top 3).
    final sortedHours = hourlyDist.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final peakHours = sortedHours.take(3).map((e) {
      return '${e.key.toString().padLeft(2, '0')}:00';
    }).toList();

    // Find low hours (bottom 3 among non-zero).
    final nonZero = sortedHours.where((e) => e.value > 0).toList();
    final lowHours = nonZero.isNotEmpty
        ? nonZero.reversed.take(3).map((e) => '${e.key.toString().padLeft(2, '0')}:00').toList()
        : <String>['02:00', '03:00', '04:00'];

    // Calculate average session.
    var totalMinutes = 0;
    var activeDays = 0;
    for (final record in _dailyRecords.values) {
      totalMinutes += record.codingMinutes;
      if (record.codingMinutes > 0) activeDays++;
    }
    final avgSession = activeDays > 0 ? totalMinutes ~/ activeDays : 0;

    // Find most productive day.
    final dayTotals = List<int>.filled(7, 0);
    for (final record in _dailyRecords.values) {
      dayTotals[record.date.weekday - 1] += record.codingMinutes;
    }
    var mostProductiveDay = 1;
    var maxDayMinutes = 0;
    for (var i = 0; i < 7; i++) {
      if (dayTotals[i] > maxDayMinutes) {
        maxDayMinutes = dayTotals[i];
        mostProductiveDay = i + 1;
      }
    }

    // Consistency score: days coded / total days * 100.
    final totalDays = _dailyRecords.length;
    final consistency = totalDays > 0 ? (activeDays / totalDays * 100) : 0.0;

    return ProductivityPattern(
      peakHours: peakHours.isNotEmpty ? peakHours : ['20:00', '21:00', '22:00'],
      lowHours: lowHours.isNotEmpty ? lowHours : ['02:00', '03:00', '04:00'],
      averageSessionMinutes: avgSession,
      longestSessionMinutes: avgSession * 3, // Estimated
      mostProductiveDay: mostProductiveDay,
      consistencyScore: consistency.clamp(0, 100),
    );
  }

  /// Get the most productive hours.
  Future<List<String>> getPeakHours() async {
    final pattern = await getProductivityPattern();
    return pattern.peakHours;
  }

  /// Get the least productive hours.
  Future<List<String>> getLowHours() async {
    final pattern = await getProductivityPattern();
    return pattern.lowHours;
  }

  // ── Weekly Report ──────────────────────────────────────────────────

  /// Generate a comprehensive weekly report.
  Future<WeeklyReport> generateWeeklyReport() async {
    _ensureInit();
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));
    final weekLabel = '${weekStart.month}月第${_weekOfMonth(weekStart)}周';

    var totalCodingMinutes = 0;
    var totalFilesEdited = 0;
    var totalCommits = 0;
    var totalAiInteractions = 0;
    final highlights = <String>[];

    for (var d = 0; d < 7; d++) {
      final date = weekStart.add(Duration(days: d));
      final key = _dateKey(date);
      final record = _dailyRecords[key];
      if (record != null) {
        totalCodingMinutes += record.codingMinutes;
        totalFilesEdited += record.filesEdited;
        totalCommits += record.commits;
        totalAiInteractions += record.aiInteractions;
      }
    }

    // Generate highlights.
    if (totalFilesEdited > 10) {
      highlights.add('本周编辑了 $totalFilesEdited 个文件');
    }
    if (totalCommits > 5) {
      highlights.add('提交了 $totalCommits 次代码');
    }
    if (totalAiInteractions > 10) {
      highlights.add('与 AI 协作了 $totalAiInteractions 次');
    }
    if (totalCodingMinutes > 300) {
      final hours = totalCodingMinutes ~/ 60;
      highlights.add('累计编码 ${hours}h ${totalCodingMinutes % 60}m');
    }
    if (highlights.isEmpty) {
      highlights.add('本周暂无显著活动');
    }

    // Compare to last week.
    var lastWeekMinutes = 0;
    for (var d = 0; d < 7; d++) {
      final date = weekStart.subtract(Duration(days: 7 - d));
      final key = _dateKey(date);
      final record = _dailyRecords[key];
      if (record != null) lastWeekMinutes += record.codingMinutes;
    }

    String comparison;
    if (lastWeekMinutes == 0) {
      comparison = '上周无数据';
    } else {
      final diff = totalCodingMinutes - lastWeekMinutes;
      final pct = (diff / lastWeekMinutes * 100).abs().round();
      if (diff > 0) {
        comparison = '+$pct% 较上周';
      } else if (diff < 0) {
        comparison = '-$pct% 较上周';
      } else {
        comparison = '与上周持平';
      }
    }

    return WeeklyReport(
      weekLabel: weekLabel,
      totalCodingMinutes: totalCodingMinutes,
      totalFilesEdited: totalFilesEdited,
      totalCommits: totalCommits,
      totalAiInteractions: totalAiInteractions,
      highlights: highlights,
      comparisonToLastWeek: comparison,
    );
  }

  /// Generate a comprehensive monthly report.
  Future<MonthlyReport> generateMonthlyReport() async {
    _ensureInit();
    final now = DateTime.now();
    final monthLabel = '${now.year}年${now.month}月';

    var totalCodingMinutes = 0;
    var totalFilesEdited = 0;
    var totalCommits = 0;
    var totalAiInteractions = 0;
    var activeDays = 0;
    var longestStreak = 0;
    var currentStreak = 0;
    final langSet = <String>{};

    final daysInMonth = _daysInMonth(now.year, now.month);
    final startOfMonth = DateTime(now.year, now.month, 1);

    for (var d = 1; d <= daysInMonth; d++) {
      final date = DateTime(now.year, now.month, d);
      final key = _dateKey(date);
      final record = _dailyRecords[key];
      if (record != null && record.codingMinutes > 0) {
        totalCodingMinutes += record.codingMinutes;
        totalFilesEdited += record.filesEdited;
        totalCommits += record.commits;
        totalAiInteractions += record.aiInteractions;
        activeDays++;
        currentStreak++;
        if (currentStreak > longestStreak) longestStreak = currentStreak;
        langSet.addAll(record.languageMinutes.keys);
      } else {
        currentStreak = 0;
      }
    }

    // Weekly breakdown.
    final weeklyBreakdown = <WeeklySummary>[];
    var weekStart = startOfMonth;
    while (weekStart.isBefore(now) || weekStart.isAtSameMomentAs(now)) {
      final weekEnd = weekStart.add(const Duration(days: 6));
      var weekMinutes = 0;
      var weekFiles = 0;
      var weekCommits = 0;
      var weekAi = 0;

      for (var d = 0; d < 7; d++) {
        final date = weekStart.add(Duration(days: d));
        if (date.month != now.month) continue;
        final key = _dateKey(date);
        final record = _dailyRecords[key];
        if (record != null) {
          weekMinutes += record.codingMinutes;
          weekFiles += record.filesEdited;
          weekCommits += record.commits;
          weekAi += record.aiInteractions;
        }
      }

      weeklyBreakdown.add(WeeklySummary(
        weekLabel: '${weekStart.month}/${weekStart.day}-${weekEnd.month}/${weekEnd.day}',
        codingMinutes: weekMinutes,
        filesEdited: weekFiles,
        commits: weekCommits,
        aiInteractions: weekAi,
        primaryLanguage: 'Mixed',
      ));

      weekStart = weekStart.add(const Duration(days: 7));
    }

    return MonthlyReport(
      monthLabel: monthLabel,
      totalCodingMinutes: totalCodingMinutes,
      totalFilesEdited: totalFilesEdited,
      totalCommits: totalCommits,
      totalAiInteractions: totalAiInteractions,
      activeDays: activeDays,
      longestStreak: longestStreak,
      topLanguages: langSet.toList()..sort(),
      weeklyBreakdown: weeklyBreakdown,
    );
  }

  // ── Persistence ────────────────────────────────────────────────────

  Future<void> _loadRecords() async {
    try {
      final jsonStr = _prefs?.getString(_storageKey);
      if (jsonStr == null) return;
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      _dailyRecords.clear();
      for (final entry in map.entries) {
        _dailyRecords[entry.key] = _DailyRecord.fromJson(entry.value as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('[HabitService] Failed to load records: $e');
    }
  }

  Future<void> _persistRecords() async {
    try {
      final map = <String, dynamic>{};
      for (final entry in _dailyRecords.entries) {
        map[entry.key] = entry.value.toJson();
      }
      await _prefs?.setString(_storageKey, jsonEncode(map));
    } catch (e) {
      debugPrint('[HabitService] Failed to persist records: $e');
    }
  }

  // ── Private Helpers ────────────────────────────────────────────────

  String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  int _weekOfMonth(DateTime date) {
    return ((date.day - 1) / 7).ceil() + 1;
  }

  int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Internal: Daily Record
// ═══════════════════════════════════════════════════════════════════════════

/// Internal daily activity record for habit tracking.
class _DailyRecord {
  DateTime date;
  int codingMinutes;
  int filesEdited;
  int commits;
  int aiInteractions;
  final Map<String, int> languageMinutes;
  final Map<int, int> hourlyActivity;

  _DailyRecord({
    required this.date,
    this.codingMinutes = 0,
    this.filesEdited = 0,
    this.commits = 0,
    this.aiInteractions = 0,
  })  : languageMinutes = {},
        hourlyActivity = {};

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'codingMinutes': codingMinutes,
        'filesEdited': filesEdited,
        'commits': commits,
        'aiInteractions': aiInteractions,
        'languageMinutes': languageMinutes,
        'hourlyActivity': hourlyActivity.map((k, v) => MapEntry(k.toString(), v)),
      };

  factory _DailyRecord.fromJson(Map<String, dynamic> json) {
    final record = _DailyRecord(
      date: DateTime.parse(json['date'] as String),
      codingMinutes: json['codingMinutes'] as int? ?? 0,
      filesEdited: json['filesEdited'] as int? ?? 0,
      commits: json['commits'] as int? ?? 0,
      aiInteractions: json['aiInteractions'] as int? ?? 0,
    );

    final langMap = json['languageMinutes'] as Map<String, dynamic>?;
    if (langMap != null) {
      for (final entry in langMap.entries) {
        record.languageMinutes[entry.key] = entry.value as int;
      }
    }

    final hourMap = json['hourlyActivity'] as Map<String, dynamic>?;
    if (hourMap != null) {
      for (final entry in hourMap.entries) {
        record.hourlyActivity[int.parse(entry.key)] = entry.value as int;
      }
    }

    return record;
  }
}
