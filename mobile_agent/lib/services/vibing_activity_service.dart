// lib/services/vibing_activity_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Data Models
// ═══════════════════════════════════════════════════════════════════════════

/// A single coding activity event.
@immutable
class ActivityEvent {
  /// Event type: 'code_write', 'code_delete', 'file_create', 'file_modify',
  /// 'ai_chat', 'git_commit', 'project_open', etc.
  final String type;

  /// Associated project ID (if any).
  final String? projectId;

  /// Affected file path (if any).
  final String? filePath;

  /// Number of lines changed (for code events).
  final int? linesChanged;

  /// Programming language (for code events).
  final String? language;

  /// When the event occurred.
  final DateTime timestamp;

  const ActivityEvent({
    required this.type,
    this.projectId,
    this.filePath,
    this.linesChanged,
    this.language,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        if (projectId != null) 'projectId': projectId,
        if (filePath != null) 'filePath': filePath,
        if (linesChanged != null) 'linesChanged': linesChanged,
        if (language != null) 'language': language,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ActivityEvent.fromJson(Map<String, dynamic> json) {
    return ActivityEvent(
      type: json['type'] as String,
      projectId: json['projectId'] as String?,
      filePath: json['filePath'] as String?,
      linesChanged: json['linesChanged'] as int?,
      language: json['language'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

/// Aggregated activity for a single day.
@immutable
class DailyActivity {
  /// The calendar date (time components are zeroed).
  final DateTime date;

  /// Total coding time in minutes.
  final int codingMinutes;

  /// Lines of code written.
  final int linesWritten;

  /// Lines of code deleted.
  final int linesDeleted;

  /// Files created.
  final int filesCreated;

  /// Files modified.
  final int filesModified;

  /// AI chat interactions.
  final int aiInteractions;

  /// Git commits made.
  final int gitCommits;

  const DailyActivity({
    required this.date,
    this.codingMinutes = 0,
    this.linesWritten = 0,
    this.linesDeleted = 0,
    this.filesCreated = 0,
    this.filesModified = 0,
    this.aiInteractions = 0,
    this.gitCommits = 0,
  });

  /// Total activity count for heatmap level calculation.
  int get totalActivityCount =>
      filesCreated +
      filesModified +
      aiInteractions +
      gitCommits +
      (linesWritten ~/ 10);

  /// Intensity level for heatmap coloring (0–4).
  int get intensityLevel {
    final count = totalActivityCount;
    if (count == 0) return 0;
    if (count < 5) return 1;
    if (count < 15) return 2;
    if (count < 30) return 3;
    return 4;
  }

  DailyActivity merge(ActivityEvent event) {
    var cm = codingMinutes;
    var lw = linesWritten;
    var ld = linesDeleted;
    var fc = filesCreated;
    var fm = filesModified;
    var ai = aiInteractions;
    var gc = gitCommits;

    switch (event.type) {
      case 'code_write':
        lw += event.linesChanged ?? 1;
        cm += 1;
      case 'code_delete':
        ld += event.linesChanged ?? 1;
        cm += 1;
      case 'file_create':
        fc += 1;
        cm += 1;
      case 'file_modify':
        fm += 1;
        cm += 1;
      case 'ai_chat':
        ai += 1;
      case 'git_commit':
        gc += 1;
      case 'project_open':
        cm += 5;
      default:
        cm += 1;
    }

    return DailyActivity(
      date: date,
      codingMinutes: cm,
      linesWritten: lw,
      linesDeleted: ld,
      filesCreated: fc,
      filesModified: fm,
      aiInteractions: ai,
      gitCommits: gc,
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'codingMinutes': codingMinutes,
        'linesWritten': linesWritten,
        'linesDeleted': linesDeleted,
        'filesCreated': filesCreated,
        'filesModified': filesModified,
        'aiInteractions': aiInteractions,
        'gitCommits': gitCommits,
      };

  factory DailyActivity.fromJson(Map<String, dynamic> json) {
    return DailyActivity(
      date: DateTime.parse(json['date'] as String),
      codingMinutes: json['codingMinutes'] as int? ?? 0,
      linesWritten: json['linesWritten'] as int? ?? 0,
      linesDeleted: json['linesDeleted'] as int? ?? 0,
      filesCreated: json['filesCreated'] as int? ?? 0,
      filesModified: json['filesModified'] as int? ?? 0,
      aiInteractions: json['aiInteractions'] as int? ?? 0,
      gitCommits: json['gitCommits'] as int? ?? 0,
    );
  }
}

/// A single day in the contribution heatmap.
@immutable
class ContributionDay {
  /// The date.
  final DateTime date;

  /// Raw activity count.
  final int count;

  /// Color intensity level (0–4).
  final int level;

  const ContributionDay({
    required this.date,
    required this.count,
    required this.level,
  });
}

/// Coding statistics for a time period.
@immutable
class CodingStats {
  /// Total coding time in minutes.
  final int totalCodingMinutes;

  /// Total lines written.
  final int totalLinesWritten;

  /// Total lines deleted.
  final int totalLinesDeleted;

  /// Total files created.
  final int totalFilesCreated;

  /// Total AI interactions.
  final int totalAiInteractions;

  /// Total Git commits.
  final int totalGitCommits;

  /// Number of unique projects worked on.
  final int projectsWorkedOn;

  /// Number of active days.
  final int activeDays;

  /// Average daily coding minutes.
  final double averageDailyMinutes;

  const CodingStats({
    required this.totalCodingMinutes,
    required this.totalLinesWritten,
    required this.totalLinesDeleted,
    required this.totalFilesCreated,
    required this.totalAiInteractions,
    required this.totalGitCommits,
    required this.projectsWorkedOn,
    required this.activeDays,
    required this.averageDailyMinutes,
  });

  /// Total lines changed (written + deleted).
  int get totalLinesChanged => totalLinesWritten + totalLinesDeleted;

  /// Formatted total coding time (e.g. "12h 30m").
  String get formattedCodingTime {
    final hours = totalCodingMinutes ~/ 60;
    final mins = totalCodingMinutes % 60;
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }
}

/// Streak information (consecutive active days).
@immutable
class StreakInfo {
  /// Current consecutive active days.
  final int currentStreak;

  /// Longest streak ever recorded.
  final int longestStreak;

  /// When the current streak started.
  final DateTime streakStart;

  /// Last day with activity (null if never).
  final DateTime? lastActiveDay;

  const StreakInfo({
    required this.currentStreak,
    required this.longestStreak,
    required this.streakStart,
    this.lastActiveDay,
  });
}

/// Language usage statistics.
@immutable
class LanguageStat {
  /// Programming language name.
  final String language;

  /// Lines written in this language.
  final int lines;

  /// Percentage of total (0.0–100.0).
  final double percentage;

  const LanguageStat({
    required this.language,
    required this.lines,
    required this.percentage,
  });
}

/// AI usage statistics.
@immutable
class AiUsageStats {
  /// Total AI interactions.
  final int totalInteractions;

  /// Total tokens consumed (if tracked).
  final int totalTokens;

  /// Average interactions per day.
  final double avgDailyInteractions;

  /// Most active day.
  final DateTime? mostActiveDay;

  const AiUsageStats({
    required this.totalInteractions,
    required this.totalTokens,
    required this.avgDailyInteractions,
    this.mostActiveDay,
  });
}

/// Achievement / badge.
@immutable
class Achievement {
  /// Unique identifier.
  final String id;

  /// Display name in Chinese.
  final String name;

  /// Description text.
  final String description;

  /// Emoji icon.
  final String icon;

  /// Whether unlocked.
  final bool isUnlocked;

  /// When unlocked (null if locked).
  final DateTime? unlockedAt;

  /// Progress percentage (0–100).
  final int progress;

  const Achievement({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.isUnlocked,
    this.unlockedAt,
    required this.progress,
  });

  Achievement copyWith({
    bool? isUnlocked,
    DateTime? unlockedAt,
    int? progress,
  }) {
    return Achievement(
      id: id,
      name: name,
      description: description,
      icon: icon,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      unlockedAt: unlockedAt ?? this.unlockedAt,
      progress: progress ?? this.progress,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Service
// ═══════════════════════════════════════════════════════════════════════════

/// {@template vibing_activity_service}
/// Tracks coding activity and generates Vibing Coding statistics.
///
/// Features:
/// - Daily coding time, lines written/deleted, files created/modified
/// - AI interactions and Git commits tracking
/// - GitHub-style contribution heatmap data
/// - Streak tracking (current + longest)
/// - Hourly distribution for productivity insights
/// - Language usage statistics
/// - Achievement / badge system
/// {@endtemplate}
class VibingActivityService {
  static const String _storageKeyDaily = 'vibing_daily_activity';
  static const String _storageKeyEvents = 'vibing_events';
  static const String _storageKeyStreak = 'vibing_streak';
  static const String _storageKeyAchievements = 'vibing_achievements';
  static const int _maxEventCache = 500;

  final List<ActivityEvent> _eventBuffer = [];
  final Map<String, DailyActivity> _dailyCache = {};
  bool _initialized = false;

  /// Whether the service has been initialized.
  bool get isInitialized => _initialized;

  /// Singleton instance.
  static final VibingActivityService _instance = VibingActivityService._internal();
  factory VibingActivityService() => _instance;
  VibingActivityService._internal();

  // ── Initialization ─────────────────────────────────────────────────

  /// Initialize the service by loading cached data.
  Future<void> init() async {
    if (_initialized) return;
    await _loadDailyCache();
    _initialized = true;
    debugPrint('[VibingActivityService] Initialized, ${_dailyCache.length} days loaded');
  }

  // ── Activity Tracking ──────────────────────────────────────────────

  /// Record a coding activity event.
  Future<void> recordActivity(ActivityEvent event) async {
    _eventBuffer.add(event);
    if (_eventBuffer.length > _maxEventCache) {
      _eventBuffer.removeAt(0);
    }

    // Update daily aggregate.
    final dateKey = _dateKey(event.timestamp);
    final existing = _dailyCache[dateKey];
    if (existing != null) {
      _dailyCache[dateKey] = existing.merge(event);
    } else {
      _dailyCache[dateKey] = DailyActivity(
        date: DateTime(event.timestamp.year, event.timestamp.month, event.timestamp.day),
      ).merge(event);
    }

    await _persistDailyCache();
    await _persistEvents();
  }

  /// Get daily activity for a date range.
  Future<List<DailyActivity>> getDailyActivity(DateTime start, DateTime end) async {
    final results = <DailyActivity>[];
    var current = DateTime(start.year, start.month, start.day);
    final endDate = DateTime(end.year, end.month, end.day);

    while (!current.isAfter(endDate)) {
      final key = _dateKey(current);
      final activity = _dailyCache[key];
      if (activity != null) {
        results.add(activity);
      } else {
        results.add(DailyActivity(date: current));
      }
      current = current.add(const Duration(days: 1));
    }

    return results;
  }

  /// Get contribution data for heatmap (GitHub-style), defaulting to 52 weeks.
  Future<List<ContributionDay>> getContributionData({int weeks = 52}) async {
    final now = DateTime.now();
    final endDate = DateTime(now.year, now.month, now.day);
    final startDate = endDate.subtract(Duration(days: weeks * 7));

    final dailyActivities = await getDailyActivity(startDate, endDate);
    return dailyActivities.map((da) {
      return ContributionDay(
        date: da.date,
        count: da.totalActivityCount,
        level: da.intensityLevel,
      );
    }).toList();
  }

  // ── Statistics ─────────────────────────────────────────────────────

  /// Get coding stats for a period.
  Future<CodingStats> getStats({DateTime? start, DateTime? end}) async {
    final now = DateTime.now();
    final effectiveStart = start ?? now.subtract(const Duration(days: 30));
    final effectiveEnd = end ?? now;

    final activities = await getDailyActivity(effectiveStart, effectiveEnd);

    int totalCodingMinutes = 0;
    int totalLinesWritten = 0;
    int totalLinesDeleted = 0;
    int totalFilesCreated = 0;
    int totalAiInteractions = 0;
    int totalGitCommits = 0;
    int activeDays = 0;
    final projects = <String>{};

    for (final day in activities) {
      totalCodingMinutes += day.codingMinutes;
      totalLinesWritten += day.linesWritten;
      totalLinesDeleted += day.linesDeleted;
      totalFilesCreated += day.filesCreated + day.filesModified;
      totalAiInteractions += day.aiInteractions;
      totalGitCommits += day.gitCommits;
      if (day.totalActivityCount > 0) activeDays++;
    }

    final dayCount = math.max(1, effectiveEnd.difference(effectiveStart).inDays);

    return CodingStats(
      totalCodingMinutes: totalCodingMinutes,
      totalLinesWritten: totalLinesWritten,
      totalLinesDeleted: totalLinesDeleted,
      totalFilesCreated: totalFilesCreated,
      totalAiInteractions: totalAiInteractions,
      totalGitCommits: totalGitCommits,
      projectsWorkedOn: projects.length,
      activeDays: activeDays,
      averageDailyMinutes: totalCodingMinutes / dayCount,
    );
  }

  /// Get streak info (current + longest).
  Future<StreakInfo> getStreakInfo() async {
    final now = DateTime.now();
    final sortedDates = _dailyCache.keys.toList()..sort();

    if (sortedDates.isEmpty) {
      return StreakInfo(
        currentStreak: 0,
        longestStreak: 0,
        streakStart: now,
      );
    }

    int currentStreak = 0;
    int longestStreak = 0;
    DateTime streakStart = now;
    DateTime? lastActiveDay;

    // Calculate current streak (from today backwards).
    var checkDate = DateTime(now.year, now.month, now.day);
    while (true) {
      final key = _dateKey(checkDate);
      final activity = _dailyCache[key];
      if (activity != null && activity.totalActivityCount > 0) {
        currentStreak++;
        lastActiveDay = checkDate;
        checkDate = checkDate.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }

    // Calculate longest streak.
    int tempStreak = 0;
    DateTime? tempStart;
    DateTime? longestStart;

    for (var i = 0; i < sortedDates.length; i++) {
      final key = sortedDates[i];
      final activity = _dailyCache[key];
      if (activity != null && activity.totalActivityCount > 0) {
        if (tempStreak == 0) {
          tempStart = activity.date;
        }
        tempStreak++;
        if (tempStreak > longestStreak) {
          longestStreak = tempStreak;
          longestStart = tempStart;
        }
      } else {
        tempStreak = 0;
        tempStart = null;
      }
    }

    if (currentStreak > 0) {
      streakStart = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: currentStreak - 1));
    }

    return StreakInfo(
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      streakStart: streakStart,
      lastActiveDay: lastActiveDay,
    );
  }

  /// Get hourly activity distribution (hour -> count).
  Future<Map<int, int>> getHourlyDistribution() async {
    final distribution = <int, int>{};
    for (var h = 0; h < 24; h++) {
      distribution[h] = 0;
    }

    for (final event in _eventBuffer) {
      final hour = event.timestamp.hour;
      distribution[hour] = (distribution[hour] ?? 0) + 1;
    }

    return distribution;
  }

  /// Get most used languages sorted by lines written.
  Future<List<LanguageStat>> getLanguageStats() async {
    final langLines = <String, int>{};

    // Aggregate from cached daily data.
    for (final day in _dailyCache.values) {
      // Language info is embedded in events, not daily aggregates.
      // We approximate using event buffer for recent languages.
    }

    // Use event buffer for language data.
    for (final event in _eventBuffer) {
      if (event.language != null && event.linesChanged != null) {
        langLines[event.language!] =
            (langLines[event.language!] ?? 0) + event.linesChanged!;
      }
    }

    if (langLines.isEmpty) {
      // Return demo data if no real data.
      return [
        const LanguageStat(language: 'Dart', lines: 1250, percentage: 45.0),
        const LanguageStat(language: 'Python', lines: 680, percentage: 24.5),
        const LanguageStat(language: 'JavaScript', lines: 420, percentage: 15.1),
        const LanguageStat(language: 'HTML/CSS', lines: 200, percentage: 7.2),
        const LanguageStat(language: 'Go', lines: 115, percentage: 4.1),
        const LanguageStat(language: 'Rust', lines: 110, percentage: 4.1),
      ];
    }

    final total = langLines.values.fold<int>(0, (s, v) => s + v);
    final stats = langLines.entries.map((e) {
      return LanguageStat(
        language: e.key,
        lines: e.value,
        percentage: total > 0 ? (e.value / total) * 100 : 0,
      );
    }).toList();

    stats.sort((a, b) => b.lines.compareTo(a.lines));
    return stats;
  }

  /// Get AI usage statistics.
  Future<AiUsageStats> getAiUsageStats() async {
    int totalInteractions = 0;
    int totalTokens = 0;
    DateTime? mostActiveDay;
    int maxDayInteractions = 0;

    for (final entry in _dailyCache.entries) {
      final day = entry.value;
      totalInteractions += day.aiInteractions;
      if (day.aiInteractions > maxDayInteractions) {
        maxDayInteractions = day.aiInteractions;
        mostActiveDay = day.date;
      }
    }

    // Estimate tokens: ~500 tokens per interaction average.
    totalTokens = totalInteractions * 500;

    final dayCount = math.max(1, _dailyCache.length);
    final avgDaily = totalInteractions / dayCount;

    return AiUsageStats(
      totalInteractions: totalInteractions,
      totalTokens: totalTokens,
      avgDailyInteractions: avgDaily,
      mostActiveDay: mostActiveDay,
    );
  }

  // ── Achievements ───────────────────────────────────────────────────

  /// All possible achievements.
  List<Achievement> getAchievements() {
    final stats = _calculateStatsForAchievements();

    return [
      Achievement(
        id: 'first_code',
        name: '初出茅庐',
        description: '编写第一行代码',
        icon: '💻',
        isUnlocked: stats['totalLines']! > 0,
        progress: math.min(100, (stats['totalLines']! / 1 * 100).round()),
      ),
      Achievement(
        id: 'streak_3',
        name: '坚持不懈',
        description: '连续编码 3 天',
        icon: '🔥',
        isUnlocked: stats['currentStreak']! >= 3,
        progress: math.min(100, (stats['currentStreak']! / 3 * 100).round()),
      ),
      Achievement(
        id: 'streak_7',
        name: '代码狂人',
        description: '连续编码 7 天',
        icon: '⚡',
        isUnlocked: stats['currentStreak']! >= 7,
        progress: math.min(100, (stats['currentStreak']! / 7 * 100).round()),
      ),
      Achievement(
        id: 'streak_30',
        name: '月度达人',
        description: '连续编码 30 天',
        icon: '👑',
        isUnlocked: stats['currentStreak']! >= 30,
        progress: math.min(100, (stats['currentStreak']! / 30 * 100).round()),
      ),
      Achievement(
        id: 'lines_1k',
        name: '千行里程碑',
        description: '累计编写 1000 行代码',
        icon: '📝',
        isUnlocked: stats['totalLines']! >= 1000,
        progress: math.min(100, (stats['totalLines']! / 1000 * 100).round()),
      ),
      Achievement(
        id: 'lines_10k',
        name: '万行大神',
        description: '累计编写 10000 行代码',
        icon: '🚀',
        isUnlocked: stats['totalLines']! >= 10000,
        progress: math.min(100, (stats['totalLines']! / 10000 * 100).round()),
      ),
      Achievement(
        id: 'ai_100',
        name: 'AI 达人',
        description: '与 AI 对话 100 次',
        icon: '🤖',
        isUnlocked: stats['aiChats']! >= 100,
        progress: math.min(100, (stats['aiChats']! / 100 * 100).round()),
      ),
      Achievement(
        id: 'git_50',
        name: '提交能手',
        description: '完成 50 次 Git 提交',
        icon: '🌿',
        isUnlocked: stats['gitCommits']! >= 50,
        progress: math.min(100, (stats['gitCommits']! / 50 * 100).round()),
      ),
      Achievement(
        id: 'night_owl',
        name: '夜猫子',
        description: '在 23:00 后编码',
        icon: '🌙',
        isUnlocked: stats['nightCoding']! > 0,
        progress: math.min(100, stats['nightCoding']! * 100),
      ),
      Achievement(
        id: 'early_bird',
        name: '早起的鸟儿',
        description: '在 06:00 前编码',
        icon: '🌅',
        isUnlocked: stats['earlyCoding']! > 0,
        progress: math.min(100, stats['earlyCoding']! * 100),
      ),
      Achievement(
        id: 'multi_lang',
        name: '多面手',
        description: '使用 3 种以上编程语言',
        icon: '🎯',
        isUnlocked: (stats['languages'] ?? 0) >= 3,
        progress: math.min(100, ((stats['languages'] ?? 0) / 3 * 100).round()),
      ),
      Achievement(
        id: 'project_master',
        name: '项目大师',
        description: '参与 5 个以上项目',
        icon: '📁',
        isUnlocked: (stats['projects'] ?? 0) >= 5,
        progress: math.min(100, ((stats['projects'] ?? 0) / 5 * 100).round()),
      ),
    ];
  }

  /// Check and return newly unlocked achievements.
  List<Achievement> checkNewAchievements() {
    final all = getAchievements();
    final newlyUnlocked = <Achievement>[];

    for (final ach in all) {
      if (ach.isUnlocked && ach.unlockedAt == null) {
        newlyUnlocked.add(ach.copyWith(unlockedAt: DateTime.now()));
      }
    }

    return newlyUnlocked;
  }

  // ── Persistence ────────────────────────────────────────────────────

  Future<void> _loadDailyCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKeyDaily);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          _dailyCache[entry.key] =
              DailyActivity.fromJson(entry.value as Map<String, dynamic>);
        }
      }
    } catch (e) {
      debugPrint('[VibingActivityService] Load cache error: $e');
    }
  }

  Future<void> _persistDailyCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = <String, dynamic>{};
      for (final entry in _dailyCache.entries) {
        encoded[entry.key] = entry.value.toJson();
      }
      await prefs.setString(_storageKeyDaily, jsonEncode(encoded));
    } catch (e) {
      debugPrint('[VibingActivityService] Persist cache error: $e');
    }
  }

  Future<void> _persistEvents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final events = _eventBuffer.map((e) => e.toJson()).toList();
      await prefs.setString(_storageKeyEvents, jsonEncode(events));
    } catch (e) {
      debugPrint('[VibingActivityService] Persist events error: $e');
    }
  }

  // ── Private Helpers ────────────────────────────────────────────────

  String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Map<String, int> _calculateStatsForAchievements() {
    int totalLines = 0;
    int aiChats = 0;
    int gitCommits = 0;
    int currentStreak = 0;
    int nightCoding = 0;
    int earlyCoding = 0;
    final languages = <String>{};
    final projects = <String>{};

    for (final day in _dailyCache.values) {
      totalLines += day.linesWritten;
      aiChats += day.aiInteractions;
      gitCommits += day.gitCommits;
    }

    for (final event in _eventBuffer) {
      if (event.language != null) languages.add(event.language!);
      if (event.projectId != null) projects.add(event.projectId!);
      final hour = event.timestamp.hour;
      if (hour >= 23 || hour < 2) nightCoding = 1;
      if (hour >= 4 && hour < 6) earlyCoding = 1;
    }

    // Calculate current streak.
    final now = DateTime.now();
    var checkDate = DateTime(now.year, now.month, now.day);
    while (true) {
      final key = _dateKey(checkDate);
      final activity = _dailyCache[key];
      if (activity != null && activity.totalActivityCount > 0) {
        currentStreak++;
        checkDate = checkDate.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }

    return {
      'totalLines': totalLines,
      'aiChats': aiChats,
      'gitCommits': gitCommits,
      'currentStreak': currentStreak,
      'nightCoding': nightCoding,
      'earlyCoding': earlyCoding,
      'languages': languages.length,
      'projects': projects.length,
    };
  }

  /// Generate demo data for preview/testing.
  Future<void> generateDemoData() async {
    final random = math.Random(42);
    final now = DateTime.now();
    final languages = ['Dart', 'Python', 'JavaScript', 'HTML', 'Go', 'Rust'];
    final eventTypes = [
      'code_write',
      'code_delete',
      'file_create',
      'file_modify',
      'ai_chat',
      'git_commit',
    ];

    for (var dayOffset = 90; dayOffset >= 0; dayOffset--) {
      final date = now.subtract(Duration(days: dayOffset));
      // 70% chance of activity on any given day.
      if (random.nextDouble() < 0.7) {
        final eventCount = random.nextInt(8) + 2;
        for (var e = 0; e < eventCount; e++) {
          final event = ActivityEvent(
            type: eventTypes[random.nextInt(eventTypes.length)],
            projectId: 'project_${random.nextInt(3)}',
            filePath: '/src/file_${random.nextInt(10)}.dart',
            linesChanged: random.nextInt(50) + 1,
            language: languages[random.nextInt(languages.length)],
            timestamp: date.add(Duration(hours: random.nextInt(14) + 8)),
          );
          await recordActivity(event);
        }
      }
    }

    debugPrint('[VibingActivityService] Demo data generated');
  }

  /// Clear all activity data.
  Future<void> clearAllData() async {
    _dailyCache.clear();
    _eventBuffer.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKeyDaily);
    await prefs.remove(_storageKeyEvents);
    await prefs.remove(_storageKeyStreak);
    await prefs.remove(_storageKeyAchievements);
    debugPrint('[VibingActivityService] All data cleared');
  }
}
