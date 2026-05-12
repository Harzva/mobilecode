// lib/providers/memory_habit_provider.dart
// Riverpod providers for Memory, Habit, and Performance Mode services.
//
// Provides:
// - memoryServiceProvider: Singleton MemoryService
// - habitServiceProvider: Singleton HabitService
// - performanceModeServiceProvider: Singleton PerformanceModeService
// - Derived state notifiers for reactive UI updates
//
// Usage:
// ```dart
// final memory = ref.watch(memoryServiceProvider);
// final projects = ref.watch(projectMemoriesProvider);
// final perfMode = ref.watch(performanceModeProvider);
// ```

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/habit_service.dart';
import '../services/memory_service.dart';
import '../services/performance_mode_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Service Providers (Singletons)
// ═══════════════════════════════════════════════════════════════════════════

/// Provider for the MemoryService singleton.
///
/// Use this to access memory management functionality throughout the app.
/// The service is initialized lazily on first read.
final memoryServiceProvider = Provider<MemoryService>((ref) {
  final service = MemoryService();
  // Initialize on first use.
  service.init().then((_) {
    debugPrint('[memoryServiceProvider] MemoryService initialized');
  });
  ref.onDispose(() {
    debugPrint('[memoryServiceProvider] MemoryService disposed');
  });
  return service;
});

/// Provider for the HabitService singleton.
///
/// Use this to access habit tracking and productivity analysis.
final habitServiceProvider = Provider<HabitService>((ref) {
  final service = HabitService();
  service.init().then((_) {
    debugPrint('[habitServiceProvider] HabitService initialized');
  });
  ref.onDispose(() {
    debugPrint('[habitServiceProvider] HabitService disposed');
  });
  return service;
});

/// Provider for the PerformanceModeService singleton.
///
/// Use this to access performance mode configuration.
final performanceModeServiceProvider = Provider<PerformanceModeService>((ref) {
  final service = PerformanceModeService();
  service.init().then((_) {
    debugPrint('[performanceModeServiceProvider] PerformanceModeService initialized');
  });
  ref.onDispose(() {
    debugPrint('[performanceModeServiceProvider] PerformanceModeService disposed');
  });
  return service;
});

// ═══════════════════════════════════════════════════════════════════════════
// Async Data Providers
// ═══════════════════════════════════════════════════════════════════════════

/// Async provider for project memories list.
///
/// Automatically refreshes when memory state changes.
final projectMemoriesProvider = FutureProvider<List<ProjectMemory>>((ref) async {
  final service = ref.watch(memoryServiceProvider);
  return service.getProjectMemories();
});

/// Async provider for code preferences.
final codePreferencesProvider = FutureProvider<CodePreferences>((ref) async {
  final service = ref.watch(memoryServiceProvider);
  return service.getCodePreferences();
});

/// Async provider for conversation history.
final conversationHistoryProvider = FutureProvider.family<List<ConversationRecord>, int>(
  (ref, limit) async {
    final service = ref.watch(memoryServiceProvider);
    return service.getConversationHistory(limit: limit);
  },
);

/// Async provider for error patterns.
final errorPatternsProvider = FutureProvider<List<ErrorPattern>>((ref) async {
  final service = ref.watch(memoryServiceProvider);
  return service.getErrorPatterns();
});

/// Async provider for frequent snippets.
final frequentSnippetsProvider = FutureProvider<List<FrequentSnippet>>((ref) async {
  final service = ref.watch(memoryServiceProvider);
  return service.getFrequentSnippets();
});

/// Async provider for user corrections.
final userCorrectionsProvider = FutureProvider<List<UserCorrection>>((ref) async {
  final service = ref.watch(memoryServiceProvider);
  return service.getUserCorrections();
});

/// Async provider for memory statistics.
final memoryStatsProvider = FutureProvider<MemoryStats>((ref) async {
  final service = ref.watch(memoryServiceProvider);
  return service.getMemoryStats();
});

// ═══════════════════════════════════════════════════════════════════════════
// Habit Data Providers
// ═══════════════════════════════════════════════════════════════════════════

/// Async provider for hourly activity distribution.
final hourlyDistributionProvider = FutureProvider.family<Map<int, int>, int>(
  (ref, days) async {
    final service = ref.watch(habitServiceProvider);
    return service.getHourlyDistribution(days: days);
  },
);

/// Async provider for language habits.
final languageHabitsProvider = FutureProvider<List<LanguageHabit>>((ref) async {
  final service = ref.watch(habitServiceProvider);
  return service.getLanguageHabits();
});

/// Async provider for weekly summaries.
final weeklySummariesProvider = FutureProvider.family<List<WeeklySummary>, int>(
  (ref, weeks) async {
    final service = ref.watch(habitServiceProvider);
    return service.getWeeklySummaries(weeks: weeks);
  },
);

/// Async provider for productivity pattern.
final productivityPatternProvider = FutureProvider<ProductivityPattern>((ref) async {
  final service = ref.watch(habitServiceProvider);
  return service.getProductivityPattern();
});

/// Async provider for weekly report.
final weeklyReportProvider = FutureProvider<WeeklyReport>((ref) async {
  final service = ref.watch(habitServiceProvider);
  return service.generateWeeklyReport();
});

/// Async provider for monthly report.
final monthlyReportProvider = FutureProvider<MonthlyReport>((ref) async {
  final service = ref.watch(habitServiceProvider);
  return service.generateMonthlyReport();
});

/// Async provider for project type habits.
final projectTypeHabitsProvider = FutureProvider<List<ProjectTypeHabit>>((ref) async {
  final service = ref.watch(habitServiceProvider);
  return service.getProjectTypeHabits();
});

// ═══════════════════════════════════════════════════════════════════════════
// Performance Mode Providers
// ═══════════════════════════════════════════════════════════════════════════

/// Provider that exposes the current performance mode reactively.
///
/// Listen to this for mode change notifications.
final performanceModeProvider = Provider<PerformanceMode>((ref) {
  final service = ref.watch(performanceModeServiceProvider);
  // Create a listener to rebuild when mode changes.
  final notifier = ValueNotifier<PerformanceMode>(service.currentMode);
  void listener() {
    notifier.value = service.currentMode;
  }

  service.addListener(listener);
  ref.onDispose(() {
    service.removeListener(listener);
    notifier.dispose();
  });
  return notifier.value;
});

/// Async provider for current performance snapshot.
final performanceSnapshotProvider = FutureProvider<PerformanceSnapshot>((ref) async {
  final service = ref.watch(performanceModeServiceProvider);
  return service.getCurrentPerformance();
});

/// Provider for a specific feature's enabled state.
final featureEnabledProvider = FutureProvider.family<bool, String>(
  (ref, featureId) async {
    final service = ref.watch(performanceModeServiceProvider);
    return service.isFeatureEnabled(featureId);
  },
);

/// Provider that exposes all feature states.
final allFeatureStatesProvider = Provider<Map<String, bool>>((ref) {
  final service = ref.watch(performanceModeServiceProvider);
  final notifier = ValueNotifier<Map<String, bool>>(service.allFeatureStates);
  void listener() {
    notifier.value = service.allFeatureStates;
  }

  service.addListener(listener);
  ref.onDispose(() {
    service.removeListener(listener);
    notifier.dispose();
  });
  return notifier.value;
});

// ═══════════════════════════════════════════════════════════════════════════
// StateNotifier Providers (for mutable state with UI updates)
// ═══════════════════════════════════════════════════════════════════════════

/// StateNotifier for managing the Memory Manager screen's selected tab.
class MemoryTabNotifier extends StateNotifier<int> {
  MemoryTabNotifier() : super(0);

  void selectTab(int index) => state = index;
}

final memoryTabProvider = StateNotifierProvider<MemoryTabNotifier, int>((ref) {
  return MemoryTabNotifier();
});

/// StateNotifier for managing conversation search query.
class ConversationSearchNotifier extends StateNotifier<String> {
  ConversationSearchNotifier() : super('');

  void setQuery(String query) => state = query;
  void clear() => state = '';
}

final conversationSearchProvider = StateNotifierProvider<ConversationSearchNotifier, String>((ref) {
  return ConversationSearchNotifier();
});

// ═══════════════════════════════════════════════════════════════════════════
// Combined/Utility Providers
// ═══════════════════════════════════════════════════════════════════════════

/// Provider that combines memory stats with habit stats for the dashboard.
final combinedStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final memoryService = ref.watch(memoryServiceProvider);
  final habitService = ref.watch(habitServiceProvider);

  final memoryStats = await memoryService.getMemoryStats();
  final weeklyReport = await habitService.generateWeeklyReport();
  final languageHabits = await habitService.getLanguageHabits();

  return {
    'memoryStats': memoryStats,
    'weeklyReport': weeklyReport,
    'primaryLanguage': languageHabits.isNotEmpty ? languageHabits.first.language : 'Unknown',
    'totalCodingMinutes': weeklyReport.totalCodingMinutes,
  };
});

/// Provider that determines if the app is in a resource-constrained state.
final isResourceConstrainedProvider = Provider<bool>((ref) {
  final perfService = ref.watch(performanceModeServiceProvider);
  return perfService.currentMode == PerformanceMode.fluent;
});

/// Provider for the maximum recommended agent concurrency.
final recommendedAgentConcurrencyProvider = Provider<int>((ref) {
  final perfService = ref.watch(performanceModeServiceProvider);
  return perfService.getMaxAgentConcurrency();
});

/// Provider that checks if animations should be throttled.
final shouldThrottleAnimationsProvider = Provider<bool>((ref) {
  final perfService = ref.watch(performanceModeServiceProvider);
  return perfService.shouldThrottleAnimations();
});
