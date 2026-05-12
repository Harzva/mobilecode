// lib/providers/api_usage_provider.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/quota_status.dart';
import '../models/api_usage_stats.dart';
import '../models/daily_usage.dart';
import '../models/provider_usage.dart';
import '../models/usage_projection.dart';
import '../models/optimization_tip.dart';
import '../models/usage_alert.dart';
import '../services/api_usage_service.dart';

// ─── Service DI ────────────────────────────────────────────────────────

/// Provider for the [ApiUsageService] singleton.
///
/// Injected into all API usage notifiers. Override for testing:
/// ```dart
/// final container = ProviderContainer(
///   overrides: [apiUsageServiceProvider.overrideWithValue(mockService)],
/// );
/// ```
final apiUsageServiceProvider = Provider<ApiUsageService>((ref) {
  return ApiUsageService();
});

// ─── Quota Status ──────────────────────────────────────────────────────

/// Manages the current API quota status.
///
/// Tracks total quota, consumed tokens, remaining allowance,
/// and percentage consumed. Automatically loads on creation.
///
/// ```dart
/// final quotaAsync = ref.watch(apiQuotaProvider);
/// quotaAsync.whenData((quota) {
///   final pct = (quota.consumed / quota.total * 100).toStringAsFixed(1);
/// });
/// ```
class ApiQuotaNotifier extends StateNotifier<AsyncValue<QuotaStatus>> {
  final ApiUsageService _service;

  ApiQuotaNotifier(this._service) : super(const AsyncValue.loading()) {
    loadQuota();
  }

  /// Load current quota status from the service.
  Future<void> loadQuota() async {
    state = const AsyncValue.loading();
    try {
      final quota = await _service.getQuotaStatus();
      state = AsyncValue.data(quota);
    } catch (e, stack) {
      debugPrint('[ApiQuotaNotifier] Failed to load quota: $e');
      state = AsyncValue.error(e, stack);
    }
  }

  /// Refresh quota without showing loading indicator.
  Future<void> refresh() async {
    try {
      final quota = await _service.getQuotaStatus();
      state = AsyncValue.data(quota);
    } catch (e) {
      debugPrint('[ApiQuotaNotifier] Failed to refresh quota: $e');
    }
  }

  /// Set or update the total quota limit.
  ///
  /// [quota] The new total token quota.
  Future<void> setQuota(int quota) async {
    try {
      await _service.setQuota(quota);
      final updated = await _service.getQuotaStatus();
      state = AsyncValue.data(updated);
    } catch (e, stack) {
      debugPrint('[ApiQuotaNotifier] Failed to set quota: $e');
      state = AsyncValue.error(e, stack);
    }
  }

  /// Manually increment consumed tokens (for optimistic updates).
  void incrementConsumed(int tokens) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(current.copyWith(
      consumed: current.consumed + tokens,
    ));
  }
}

/// Provider for API quota status.
///
/// ```dart
/// final quotaAsync = ref.watch(apiQuotaProvider);
/// ```
final apiQuotaProvider =
    StateNotifierProvider<ApiQuotaNotifier, AsyncValue<QuotaStatus>>((ref) {
  return ApiQuotaNotifier(ref.read(apiUsageServiceProvider));
});

// ─── Usage Stats ───────────────────────────────────────────────────────

/// Provider for aggregate API usage statistics.
///
/// Returns total tokens, requests, average latency, success rate,
/// and cost estimates for the current billing period.
///
/// ```dart
/// final statsAsync = ref.watch(apiUsageStatsProvider);
/// statsAsync.whenData((stats) => Text('${stats.totalTokens} tokens'));
/// ```
final apiUsageStatsProvider = FutureProvider<ApiUsageStats>((ref) async {
  return ref.read(apiUsageServiceProvider).getUsageStats();
});

// ─── Daily Usage (for chart) ───────────────────────────────────────────

/// Provider for daily API usage data over the last N days.
///
/// Family parameter: number of days to look back (default: 30).
///
/// ```dart
/// final dailyAsync = ref.watch(apiDailyUsageProvider(30));
/// dailyAsync.whenData((data) => BarChart(dailyData: data));
/// ```
final apiDailyUsageProvider =
    FutureProvider.family<List<DailyUsage>, int>((ref, days) async {
  return ref.read(apiUsageServiceProvider).getDailyUsage(days: days);
});

// ─── Provider Breakdown ────────────────────────────────────────────────

/// Provider for API usage broken down by LLM provider.
///
/// Shows tokens, requests, and cost per provider (OpenAI, Anthropic, etc.)
/// for comparison and rebalancing decisions.
///
/// ```dart
/// final breakdownAsync = ref.watch(apiProviderUsageProvider);
/// breakdownAsync.whenData((providers) => PieChart(data: providers));
/// ```
final apiProviderUsageProvider = FutureProvider<List<ProviderUsage>>((ref) async {
  return ref.read(apiUsageServiceProvider).getUsageByProvider();
});

// ─── Usage Projection ──────────────────────────────────────────────────

/// Provider for usage projection / forecast.
///
/// Predicts whether current usage patterns will exceed the quota
/// before the end of the billing period. Includes confidence interval.
///
/// ```dart
/// final projectionAsync = ref.watch(apiUsageProjectionProvider);
/// projectionAsync.whenData((proj) {
///   if (proj.willExceedQuota) { /* show warning */ }
/// });
/// ```
final apiUsageProjectionProvider = FutureProvider<UsageProjection>((ref) async {
  return ref.read(apiUsageServiceProvider).getUsageProjection();
});

// ─── Optimization Tips ─────────────────────────────────────────────────

/// Provider for API usage optimization suggestions.
///
/// Returns actionable tips for reducing token consumption,
/// such as using cheaper models for simple tasks or enabling caching.
///
/// ```dart
/// final tipsAsync = ref.watch(apiOptimizationTipsProvider);
/// tipsAsync.whenData((tips) => TipsList(tips: tips));
/// ```
final apiOptimizationTipsProvider = FutureProvider<List<OptimizationTip>>((ref) async {
  return ref.read(apiUsageServiceProvider).getOptimizationTips();
});

// ─── Usage Alerts ──────────────────────────────────────────────────────

/// Manages API usage alerts and notifications.
///
/// Tracks threshold-based alerts (e.g., 50%, 80%, 100% of quota)
/// and anomalous usage patterns.
class AlertsNotifier extends StateNotifier<AsyncValue<List<UsageAlert>>> {
  final ApiUsageService _service;

  AlertsNotifier(this._service) : super(const AsyncValue.loading()) {
    loadAlerts();
  }

  /// Load all active usage alerts.
  Future<void> loadAlerts() async {
    state = const AsyncValue.loading();
    try {
      final alerts = await _service.getUsageAlerts();
      state = AsyncValue.data(alerts);
    } catch (e, stack) {
      debugPrint('[AlertsNotifier] Failed to load alerts: $e');
      state = AsyncValue.error(e, stack);
    }
  }

  /// Dismiss a specific alert.
  Future<void> dismissAlert(String alertId) async {
    final previous = state.valueOrNull ?? [];
    final updated = previous.where((a) => a.id != alertId).toList();
    state = AsyncValue.data(updated);

    try {
      await _service.dismissAlert(alertId);
    } catch (e) {
      debugPrint('[AlertsNotifier] Failed to dismiss alert: $e');
      state = AsyncValue.data(previous);
    }
  }

  /// Acknowledge all current alerts.
  Future<void> acknowledgeAll() async {
    final previous = state.valueOrNull ?? [];
    state = const AsyncValue.data([]);

    try {
      final ids = previous.map((a) => a.id).toList();
      await _service.acknowledgeAlerts(ids);
    } catch (e) {
      debugPrint('[AlertsNotifier] Failed to acknowledge alerts: $e');
      state = AsyncValue.data(previous);
    }
  }

  /// Refresh alerts silently.
  Future<void> refresh() async {
    try {
      final alerts = await _service.getUsageAlerts();
      state = AsyncValue.data(alerts);
    } catch (e) {
      debugPrint('[AlertsNotifier] Failed to refresh alerts: $e');
    }
  }
}

/// Provider for API usage alerts.
///
/// ```dart
/// final alertsAsync = ref.watch(apiUsageAlertsProvider);
/// ```
final apiUsageAlertsProvider =
    StateNotifierProvider<AlertsNotifier, AsyncValue<List<UsageAlert>>>((ref) {
  return AlertsNotifier(ref.read(apiUsageServiceProvider));
});

// ─── Selected Month ────────────────────────────────────────────────────

/// Currently selected month for usage data display.
///
/// Defaults to the current month. Used to filter daily usage
/// charts and stats to a specific billing period.
///
/// ```dart
/// final month = ref.watch(apiUsageMonthProvider);
/// ref.read(apiUsageMonthProvider.notifier).state = DateTime(2025, 1);
/// ```
final apiUsageMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});

// ─── Usage Time Range ──────────────────────────────────────────────────

/// Selected time range for usage analytics.
///
/// Values: '7d', '30d', '90d', '1y'
final apiUsageTimeRangeProvider = StateProvider<String>((ref) => '30d');

// ─── Combined Dashboard Data ───────────────────────────────────────────

/// Aggregated dashboard data combining all API usage providers.
///
/// Watches [apiQuotaProvider], [apiUsageStatsProvider],
/// [apiUsageProjectionProvider], and [apiOptimizationTipsProvider]
/// to produce a unified dashboard data map.
///
/// ```dart
/// final dashboardAsync = ref.watch(apiDashboardProvider);
/// dashboardAsync.whenData((data) {
///   final quota = data['quota'] as QuotaStatus;
///   final stats = data['stats'] as ApiUsageStats;
///   final projection = data['projection'] as UsageProjection;
///   final tips = data['tips'] as List<OptimizationTip>;
///   final hasAlerts = data['hasAlerts'] as bool;
/// });
/// ```
final apiDashboardProvider = Provider<AsyncValue<Map<String, dynamic>>>((ref) {
  final quota = ref.watch(apiQuotaProvider);
  final stats = ref.watch(apiUsageStatsProvider);
  final projection = ref.watch(apiUsageProjectionProvider);
  final tips = ref.watch(apiOptimizationTipsProvider);
  final alerts = ref.watch(apiUsageAlertsProvider);

  // If any critical data is loading, show loading
  if (quota is AsyncLoading) {
    return const AsyncValue.loading();
  }

  // If quota has an error, propagate it
  if (quota is AsyncError) {
    return AsyncValue.error(
      quota.error ?? 'Failed to load dashboard',
      quota.stackTrace ?? StackTrace.current,
    );
  }

  // Combine all available data
  final quotaData = quota.valueOrNull;
  final statsData = stats.valueOrNull;
  final projectionData = projection.valueOrNull;
  final tipsData = tips.valueOrNull ?? [];
  final alertsData = alerts.valueOrNull ?? [];

  // Compute summary metrics
  final totalTokens = statsData?.totalTokens ?? 0;
  final totalRequests = statsData?.totalRequests ?? 0;
  final quotaPercent = quotaData != null && quotaData.total > 0
      ? (quotaData.consumed / quotaData.total * 100).toStringAsFixed(1)
      : '0.0';

  // Determine status color indicator
  final double? quotaDouble = double.tryParse(quotaPercent);
  final quotaStatus = quotaDouble != null
      ? (quotaDouble >= 90
          ? 'critical'
          : quotaDouble >= 75
              ? 'warning'
              : quotaDouble >= 50
                  ? 'caution'
                  : 'healthy')
      : 'unknown';

  return AsyncValue.data({
    // Core data
    'quota': quotaData,
    'stats': statsData,
    'projection': projectionData,
    'tips': tipsData,
    'alerts': alertsData,

    // Summary metrics
    'totalTokens': totalTokens,
    'totalRequests': totalRequests,
    'quotaPercent': quotaPercent,
    'quotaStatus': quotaStatus,

    // Derived flags
    'hasAlerts': alertsData.isNotEmpty,
    'hasTips': tipsData.isNotEmpty,
    'willExceedQuota': projectionData?.willExceedQuota ?? false,

    // Loading states
    'isStatsLoading': stats is AsyncLoading,
    'isProjectionLoading': projection is AsyncLoading,
    'isTipsLoading': tips is AsyncLoading,

    // Errors
    'statsError': stats is AsyncError ? stats.error : null,
    'projectionError': projection is AsyncError ? projection.error : null,
    'tipsError': tips is AsyncError ? tips.error : null,
  });
});

// ─── Quota Warning ─────────────────────────────────────────────────────

/// Derived provider that emits a warning when quota is critical.
///
/// Returns a warning message string if quota > 90%, null otherwise.
/// Use for snackbar/banner notifications.
///
/// ```dart
/// final warning = ref.watch(quotaWarningProvider);
/// if (warning != null) { showWarningBanner(warning); }
/// ```
final quotaWarningProvider = Provider<String?>((ref) {
  final quotaAsync = ref.watch(apiQuotaProvider);

  return quotaAsync.when(
    data: (quota) {
      if (quota.total <= 0) return null;
      final pct = quota.consumed / quota.total * 100;
      if (pct >= 100) {
        return 'API quota fully consumed (${quota.consumed}/${quota.total} tokens). Upgrade your plan to continue.';
      }
      if (pct >= 90) {
        return 'API quota at ${pct.toStringAsFixed(0)}% (${quota.consumed}/${quota.total} tokens). Approaching limit.';
      }
      if (pct >= 75) {
        return 'API quota at ${pct.toStringAsFixed(0)}% (${quota.consumed}/${quota.total} tokens). Consider optimization.';
      }
      return null;
    },
    loading: () => null,
    error: (_, __) => null,
  );
});

// ─── Cost Estimate ─────────────────────────────────────────────────────

/// Provider for estimated API cost for the current period.
///
/// Derived from usage stats and provider-specific pricing.
///
/// ```dart
/// final costAsync = ref.watch(apiCostEstimateProvider);
/// costAsync.whenData((cost) => Text('\$${cost.toStringAsFixed(2)}'));
/// ```
final apiCostEstimateProvider = FutureProvider<double>((ref) async {
  return ref.read(apiUsageServiceProvider).getEstimatedCost();
});
