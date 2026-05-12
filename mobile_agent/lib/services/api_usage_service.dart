// lib/services/api_usage_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'api_service.dart';
import 'storage_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Usage Alert Model
// ═══════════════════════════════════════════════════════════════════════════

/// {@template usage_alert}
/// An alert triggered when API usage crosses a configured threshold.
/// {@endtemplate}
@immutable
class UsageAlert {
  /// Unique identifier for the alert.
  final String id;

  /// The usage percentage threshold that triggered this alert (e.g., 80).
  final int threshold;

  /// Alert type: 'percentage', 'fixed', or 'projected'.
  final String type;

  /// When the alert was triggered.
  final DateTime triggeredAt;

  /// Whether the alert has been dismissed by the user.
  final bool isDismissed;

  /// Human-readable message describing the alert.
  final String message;

  const UsageAlert({
    required this.id,
    required this.threshold,
    required this.type,
    required this.triggeredAt,
    this.isDismissed = false,
    required this.message,
  });

  factory UsageAlert.fromJson(Map<String, dynamic> json) {
    return UsageAlert(
      id: json['id'] as String,
      threshold: json['threshold'] as int,
      type: json['type'] as String,
      triggeredAt: DateTime.parse(json['triggeredAt'] as String),
      isDismissed: json['isDismissed'] as bool? ?? false,
      message: json['message'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'threshold': threshold,
      'type': type,
      'triggeredAt': triggeredAt.toIso8601String(),
      'isDismissed': isDismissed,
      'message': message,
    };
  }

  UsageAlert copyWith({
    String? id,
    int? threshold,
    String? type,
    DateTime? triggeredAt,
    bool? isDismissed,
    String? message,
  }) {
    return UsageAlert(
      id: id ?? this.id,
      threshold: threshold ?? this.threshold,
      type: type ?? this.type,
      triggeredAt: triggeredAt ?? this.triggeredAt,
      isDismissed: isDismissed ?? this.isDismissed,
      message: message ?? this.message,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UsageAlert &&
        other.id == id &&
        other.threshold == threshold &&
        other.type == type &&
        other.triggeredAt == triggeredAt &&
        other.isDismissed == isDismissed &&
        other.message == message;
  }

  @override
  int get hashCode => Object.hash(
        id,
        threshold,
        type,
        triggeredAt,
        isDismissed,
        message,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// Quota Status Model
// ═══════════════════════════════════════════════════════════════════════════

/// {@template quota_status}
/// Current quota usage and availability for the billing period.
/// {@endtemplate}
@immutable
class QuotaStatus {
  /// Maximum tokens allowed per month.
  final int monthlyQuota;

  /// Tokens consumed so far this month.
  final int usedThisMonth;

  /// Tokens remaining in the current billing period.
  final int remaining;

  /// Usage as a percentage of the monthly quota (0.0–100.0).
  final double usagePercent;

  /// When the quota resets (first day of next month).
  final DateTime quotaResetsAt;

  /// Whether usage has already exceeded the quota.
  final bool isExceeding;

  /// List of active warning messages.
  final List<String> warnings;

  const QuotaStatus({
    required this.monthlyQuota,
    required this.usedThisMonth,
    required this.remaining,
    required this.usagePercent,
    required this.quotaResetsAt,
    required this.isExceeding,
    required this.warnings,
  });

  factory QuotaStatus.fromJson(Map<String, dynamic> json) {
    return QuotaStatus(
      monthlyQuota: json['monthlyQuota'] as int,
      usedThisMonth: json['usedThisMonth'] as int,
      remaining: json['remaining'] as int,
      usagePercent: (json['usagePercent'] as num).toDouble(),
      quotaResetsAt: DateTime.parse(json['quotaResetsAt'] as String),
      isExceeding: json['isExceeding'] as bool? ?? false,
      warnings: (json['warnings'] as List<dynamic>?)?.cast<String>() ?? const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'monthlyQuota': monthlyQuota,
      'usedThisMonth': usedThisMonth,
      'remaining': remaining,
      'usagePercent': usagePercent,
      'quotaResetsAt': quotaResetsAt.toIso8601String(),
      'isExceeding': isExceeding,
      'warnings': warnings,
    };
  }

  QuotaStatus copyWith({
    int? monthlyQuota,
    int? usedThisMonth,
    int? remaining,
    double? usagePercent,
    DateTime? quotaResetsAt,
    bool? isExceeding,
    List<String>? warnings,
  }) {
    return QuotaStatus(
      monthlyQuota: monthlyQuota ?? this.monthlyQuota,
      usedThisMonth: usedThisMonth ?? this.usedThisMonth,
      remaining: remaining ?? this.remaining,
      usagePercent: usagePercent ?? this.usagePercent,
      quotaResetsAt: quotaResetsAt ?? this.quotaResetsAt,
      isExceeding: isExceeding ?? this.isExceeding,
      warnings: warnings ?? this.warnings,
    );
  }

  /// Color representing the current quota usage level.
  Color get statusColor {
    if (usagePercent >= 100) return AppTheme.error;
    if (usagePercent >= 80) return AppTheme.warning;
    if (usagePercent >= 50) return const Color(0xFFF59E0B);
    return AppTheme.success;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is QuotaStatus &&
        other.monthlyQuota == monthlyQuota &&
        other.usedThisMonth == usedThisMonth &&
        other.remaining == remaining &&
        other.usagePercent == usagePercent &&
        other.quotaResetsAt == quotaResetsAt &&
        other.isExceeding == isExceeding &&
        listEquals(other.warnings, warnings);
  }

  @override
  int get hashCode => Object.hash(
        monthlyQuota,
        usedThisMonth,
        remaining,
        usagePercent,
        quotaResetsAt,
        isExceeding,
        Object.hashAll(warnings),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// API Usage Statistics Model
// ═══════════════════════════════════════════════════════════════════════════

/// {@template api_usage_stats}
/// Aggregated statistics about API usage over a period.
/// {@endtemplate}
@immutable
class ApiUsageStats {
  /// Total tokens consumed.
  final int totalTokensUsed;

  /// Total number of API requests made.
  final int totalRequests;

  /// Average tokens per request.
  final double avgTokensPerRequest;

  /// Percentage of requests that succeeded (0.0–100.0).
  final double successRate;

  /// The most-used provider name.
  final String topProvider;

  /// The most-used model name.
  final String topModel;

  /// Estimated cost in US cents.
  final int estimatedCost;

  /// Current quota status.
  final QuotaStatus quotaStatus;

  const ApiUsageStats({
    required this.totalTokensUsed,
    required this.totalRequests,
    required this.avgTokensPerRequest,
    required this.successRate,
    required this.topProvider,
    required this.topModel,
    required this.estimatedCost,
    required this.quotaStatus,
  });

  factory ApiUsageStats.fromJson(Map<String, dynamic> json) {
    return ApiUsageStats(
      totalTokensUsed: json['totalTokensUsed'] as int,
      totalRequests: json['totalRequests'] as int,
      avgTokensPerRequest: (json['avgTokensPerRequest'] as num).toDouble(),
      successRate: (json['successRate'] as num).toDouble(),
      topProvider: json['topProvider'] as String,
      topModel: json['topModel'] as String,
      estimatedCost: json['estimatedCost'] as int,
      quotaStatus: QuotaStatus.fromJson(json['quotaStatus'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'totalTokensUsed': totalTokensUsed,
      'totalRequests': totalRequests,
      'avgTokensPerRequest': avgTokensPerRequest,
      'successRate': successRate,
      'topProvider': topProvider,
      'topModel': topModel,
      'estimatedCost': estimatedCost,
      'quotaStatus': quotaStatus.toJson(),
    };
  }

  ApiUsageStats copyWith({
    int? totalTokensUsed,
    int? totalRequests,
    double? avgTokensPerRequest,
    double? successRate,
    String? topProvider,
    String? topModel,
    int? estimatedCost,
    QuotaStatus? quotaStatus,
  }) {
    return ApiUsageStats(
      totalTokensUsed: totalTokensUsed ?? this.totalTokensUsed,
      totalRequests: totalRequests ?? this.totalRequests,
      avgTokensPerRequest: avgTokensPerRequest ?? this.avgTokensPerRequest,
      successRate: successRate ?? this.successRate,
      topProvider: topProvider ?? this.topProvider,
      topModel: topModel ?? this.topModel,
      estimatedCost: estimatedCost ?? this.estimatedCost,
      quotaStatus: quotaStatus ?? this.quotaStatus,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ApiUsageStats &&
        other.totalTokensUsed == totalTokensUsed &&
        other.totalRequests == totalRequests &&
        other.avgTokensPerRequest == avgTokensPerRequest &&
        other.successRate == successRate &&
        other.topProvider == topProvider &&
        other.topModel == topModel &&
        other.estimatedCost == estimatedCost &&
        other.quotaStatus == quotaStatus;
  }

  @override
  int get hashCode => Object.hash(
        totalTokensUsed,
        totalRequests,
        avgTokensPerRequest,
        successRate,
        topProvider,
        topModel,
        estimatedCost,
        quotaStatus,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// Daily Usage Model
// ═══════════════════════════════════════════════════════════════════════════

/// {@template daily_usage}
/// API usage aggregated for a single day.
/// {@endtemplate}
@immutable
class DailyUsage {
  /// The calendar date.
  final DateTime date;

  /// Tokens consumed on this day.
  final int tokensUsed;

  /// Number of API requests on this day.
  final int requestCount;

  /// Estimated cost for this day in US dollars.
  final double cost;

  const DailyUsage({
    required this.date,
    required this.tokensUsed,
    required this.requestCount,
    required this.cost,
  });

  factory DailyUsage.fromJson(Map<String, dynamic> json) {
    return DailyUsage(
      date: DateTime.parse(json['date'] as String),
      tokensUsed: json['tokensUsed'] as int,
      requestCount: json['requestCount'] as int,
      cost: (json['cost'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'tokensUsed': tokensUsed,
      'requestCount': requestCount,
      'cost': cost,
    };
  }

  DailyUsage copyWith({
    DateTime? date,
    int? tokensUsed,
    int? requestCount,
    double? cost,
  }) {
    return DailyUsage(
      date: date ?? this.date,
      tokensUsed: tokensUsed ?? this.tokensUsed,
      requestCount: requestCount ?? this.requestCount,
      cost: cost ?? this.cost,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DailyUsage &&
        other.date == date &&
        other.tokensUsed == tokensUsed &&
        other.requestCount == requestCount &&
        other.cost == cost;
  }

  @override
  int get hashCode => Object.hash(date, tokensUsed, requestCount, cost);
}

// ═══════════════════════════════════════════════════════════════════════════
// Provider Usage Model
// ═══════════════════════════════════════════════════════════════════════════

/// {@template provider_usage}
/// API usage broken down by a single provider.
/// {@endtemplate}
@immutable
class ProviderUsage {
  /// Name of the AI provider (e.g., 'openai', 'claude', 'gemini').
  final String provider;

  /// Tokens consumed via this provider.
  final int tokensUsed;

  /// Number of API requests to this provider.
  final int requestCount;

  /// Percentage of total usage (0.0–100.0).
  final double percentage;

  /// Color for chart visualization.
  final Color color;

  const ProviderUsage({
    required this.provider,
    required this.tokensUsed,
    required this.requestCount,
    required this.percentage,
    required this.color,
  });

  factory ProviderUsage.fromJson(Map<String, dynamic> json) {
    return ProviderUsage(
      provider: json['provider'] as String,
      tokensUsed: json['tokensUsed'] as int,
      requestCount: json['requestCount'] as int,
      percentage: (json['percentage'] as num).toDouble(),
      color: Color(json['color'] as int),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'provider': provider,
      'tokensUsed': tokensUsed,
      'requestCount': requestCount,
      'percentage': percentage,
      'color': color.value,
    };
  }

  ProviderUsage copyWith({
    String? provider,
    int? tokensUsed,
    int? requestCount,
    double? percentage,
    Color? color,
  }) {
    return ProviderUsage(
      provider: provider ?? this.provider,
      tokensUsed: tokensUsed ?? this.tokensUsed,
      requestCount: requestCount ?? this.requestCount,
      percentage: percentage ?? this.percentage,
      color: color ?? this.color,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProviderUsage &&
        other.provider == provider &&
        other.tokensUsed == tokensUsed &&
        other.requestCount == requestCount &&
        other.percentage == percentage &&
        other.color == color;
  }

  @override
  int get hashCode => Object.hash(
        provider,
        tokensUsed,
        requestCount,
        percentage,
        color,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// Endpoint Usage Model
// ═══════════════════════════════════════════════════════════════════════════

/// {@template endpoint_usage}
/// API usage broken down by endpoint type.
/// {@endtemplate}
class EndpointUsage {
  /// The endpoint name (e.g., 'chat', 'completion', 'embed').
  final String endpoint;

  /// Tokens consumed on this endpoint.
  final int tokensUsed;

  /// Number of requests to this endpoint.
  final int requestCount;

  /// Percentage of total usage (0.0–100.0).
  final double percentage;

  const EndpointUsage({
    required this.endpoint,
    required this.tokensUsed,
    required this.requestCount,
    required this.percentage,
  });

  factory EndpointUsage.fromJson(Map<String, dynamic> json) {
    return EndpointUsage(
      endpoint: json['endpoint'] as String,
      tokensUsed: json['tokensUsed'] as int,
      requestCount: json['requestCount'] as int,
      percentage: (json['percentage'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'endpoint': endpoint,
      'tokensUsed': tokensUsed,
      'requestCount': requestCount,
      'percentage': percentage,
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Hourly Usage Model
// ═══════════════════════════════════════════════════════════════════════════

/// {@template hourly_usage}
/// API usage pattern aggregated by hour of day.
/// {@endtemplate}
class HourlyUsage {
  /// Hour of day (0–23).
  final int hour;

  /// Average tokens used during this hour.
  final double avgTokens;

  /// Average request count during this hour.
  final double avgRequests;

  const HourlyUsage({
    required this.hour,
    required this.avgTokens,
    required this.avgRequests,
  });

  factory HourlyUsage.fromJson(Map<String, dynamic> json) {
    return HourlyUsage(
      hour: json['hour'] as int,
      avgTokens: (json['avgTokens'] as num).toDouble(),
      avgRequests: (json['avgRequests'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'hour': hour,
      'avgTokens': avgTokens,
      'avgRequests': avgRequests,
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Usage Projection Model
// ═══════════════════════════════════════════════════════════════════════════

/// {@template usage_projection}
/// Projection of whether monthly usage will exceed the quota.
/// {@endtemplate}
@immutable
class UsageProjection {
  /// Projected total monthly usage based on current rate.
  final double projectedMonthlyUsage;

  /// Whether the projection indicates quota will be exceeded.
  final bool willExceedQuota;

  /// Estimated days until quota is exceeded (null if won't exceed).
  final int? daysUntilExceed;

  /// Human-readable recommendation.
  final String recommendation;

  const UsageProjection({
    required this.projectedMonthlyUsage,
    required this.willExceedQuota,
    this.daysUntilExceed,
    required this.recommendation,
  });

  factory UsageProjection.fromJson(Map<String, dynamic> json) {
    return UsageProjection(
      projectedMonthlyUsage: (json['projectedMonthlyUsage'] as num).toDouble(),
      willExceedQuota: json['willExceedQuota'] as bool,
      daysUntilExceed: json['daysUntilExceed'] as int?,
      recommendation: json['recommendation'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'projectedMonthlyUsage': projectedMonthlyUsage,
      'willExceedQuota': willExceedQuota,
      if (daysUntilExceed != null) 'daysUntilExceed': daysUntilExceed,
      'recommendation': recommendation,
    };
  }

  UsageProjection copyWith({
    double? projectedMonthlyUsage,
    bool? willExceedQuota,
    int? daysUntilExceed,
    String? recommendation,
  }) {
    return UsageProjection(
      projectedMonthlyUsage: projectedMonthlyUsage ?? this.projectedMonthlyUsage,
      willExceedQuota: willExceedQuota ?? this.willExceedQuota,
      daysUntilExceed: daysUntilExceed ?? this.daysUntilExceed,
      recommendation: recommendation ?? this.recommendation,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UsageProjection &&
        other.projectedMonthlyUsage == projectedMonthlyUsage &&
        other.willExceedQuota == willExceedQuota &&
        other.daysUntilExceed == daysUntilExceed &&
        other.recommendation == recommendation;
  }

  @override
  int get hashCode => Object.hash(
        projectedMonthlyUsage,
        willExceedQuota,
        daysUntilExceed,
        recommendation,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// Optimization Tip Model
// ═══════════════════════════════════════════════════════════════════════════

/// {@template optimization_tip}
/// A recommendation for reducing API usage and saving costs.
/// {@endtemplate}
@immutable
class OptimizationTip {
  /// Short title of the tip.
  final String title;

  /// Detailed description of the recommendation.
  final String description;

  /// Suggested action to take.
  final String action;

  /// Estimated token savings per month if applied.
  final int potentialSavings;

  const OptimizationTip({
    required this.title,
    required this.description,
    required this.action,
    required this.potentialSavings,
  });

  factory OptimizationTip.fromJson(Map<String, dynamic> json) {
    return OptimizationTip(
      title: json['title'] as String,
      description: json['description'] as String,
      action: json['action'] as String,
      potentialSavings: json['potentialSavings'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'action': action,
      'potentialSavings': potentialSavings,
    };
  }

  OptimizationTip copyWith({
    String? title,
    String? description,
    String? action,
    int? potentialSavings,
  }) {
    return OptimizationTip(
      title: title ?? this.title,
      description: description ?? this.description,
      action: action ?? this.action,
      potentialSavings: potentialSavings ?? this.potentialSavings,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OptimizationTip &&
        other.title == title &&
        other.description == description &&
        other.action == action &&
        other.potentialSavings == potentialSavings;
  }

  @override
  int get hashCode => Object.hash(title, description, action, potentialSavings);
}

// ═══════════════════════════════════════════════════════════════════════════
// Exception
// ═══════════════════════════════════════════════════════════════════════════

/// Exception for API usage service operations.
class ApiUsageException implements Exception {
  final String message;
  final String? operation;
  final dynamic originalError;

  const ApiUsageException({
    required this.message,
    this.operation,
    this.originalError,
  });

  @override
  String toString() => 'ApiUsageException [$operation]: $message';
}

// ═══════════════════════════════════════════════════════════════════════════
// Service
// ═══════════════════════════════════════════════════════════════════════════

/// {@template api_usage_service}
/// Service for tracking API usage and managing quotas.
///
/// Tracks token consumption across AI providers, enforces monthly quotas,
/// and provides usage analytics, projections, and optimization tips.
///
/// ```dart
/// final usage = ApiUsageService(api: apiService, storage: storageService);
/// final quota = await usage.getQuotaStatus();
/// if (quota.remaining < 1000) {
///   // Show upgrade prompt
/// }
/// ```
/// {@endtemplate}
class ApiUsageService {
  /// The HTTP client for server communication.
  final ApiService _api;

  /// The local storage service for caching.
  final StorageService _storage;

  /// Whether the service has been initialized.
  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// In-memory cache of recent usage records (pending sync).
  final List<Map<String, dynamic>> _pendingRecords = [];

  /// Storage keys.
  static const String _keyQuotaStatus = 'api_quota_status';
  static const String _keyUsageStats = 'api_usage_stats';
  static const String _keyPendingRecords = 'api_pending_records';
  static const String _keyMonthlyQuota = 'api_monthly_quota';

  /// Provider colors for chart visualization.
  static const Map<String, Color> _providerColors = {
    'openai': AppTheme.success,
    'claude': Color(0xFFD97757),
    'gemini': Color(0xFF4285F4),
    'custom': AppTheme.textTertiary,
  };

  /// Creates an [ApiUsageService].
  ApiUsageService({
    required ApiService api,
    required StorageService storage,
  })  : _api = api,
        _storage = storage;

  /// Initialize the service.
  Future<void> init() async {
    if (_initialized) return;

    try {
      // Load any pending records from local storage.
      final pending = await _storage.getSetting<String>(_keyPendingRecords);
      if (pending != null && pending.isNotEmpty) {
        final decoded = jsonDecode(pending) as List<dynamic>;
        _pendingRecords.addAll(decoded.cast<Map<String, dynamic>>());
        debugPrint('[ApiUsageService] Loaded ${_pendingRecords.length} pending records');
      }

      _initialized = true;
      debugPrint('[ApiUsageService] Initialized');
    } catch (e) {
      debugPrint('[ApiUsageService] Init warning: $e');
      _initialized = true;
    }
  }

  // ── Usage Tracking ────────────────────────────────────────────────────

  /// Track a single API usage event.
  ///
  /// Records the usage details and immediately syncs to the server.
  /// If offline, the record is queued and will be synced later.
  Future<void> trackUsage({
    required String provider,
    required String endpoint,
    required int tokensUsed,
    required int requestCount,
    required String model,
    required bool success,
  }) async {
    _ensureInitialized();

    final record = {
      'provider': provider,
      'endpoint': endpoint,
      'tokensUsed': tokensUsed,
      'requestCount': requestCount,
      'model': model,
      'success': success,
      'timestamp': DateTime.now().toIso8601String(),
    };

    try {
      // Attempt immediate sync.
      await _api.post('/usage/track', data: record);
      debugPrint('[ApiUsageService] Tracked $tokensUsed tokens via $provider/$model');
    } on ApiException catch (e) {
      // Queue for later if offline or server error.
      _pendingRecords.add(record);
      await _persistPendingRecords();
      debugPrint('[ApiUsageService] Usage queued (server unavailable): $e');
    } catch (e) {
      throw ApiUsageException(
        message: 'Failed to track usage: $e',
        operation: 'trackUsage',
        originalError: e,
      );
    }
  }

  /// Sync any pending usage records to the server.
  ///
  /// Call this when connectivity is restored.
  Future<void> syncPendingRecords() async {
    if (_pendingRecords.isEmpty) return;

    final toSync = List<Map<String, dynamic>>.from(_pendingRecords);
    _pendingRecords.clear();

    try {
      await _api.post('/usage/batch', data: {'records': toSync});
      await _persistPendingRecords();
      debugPrint('[ApiUsageService] Synced ${toSync.length} pending records');
    } catch (e) {
      // Re-queue on failure.
      _pendingRecords.insertAll(0, toSync);
      debugPrint('[ApiUsageService] Sync failed, re-queued ${toSync.length} records');
    }
  }

  // ── Quota Management ──────────────────────────────────────────────────

  /// Get the current quota status.
  ///
  /// Returns the quota information including tokens used, remaining,
  /// and reset date. Falls back to cached data if offline.
  Future<QuotaStatus> getQuotaStatus() async {
    _ensureInitialized();
    try {
      final response = await _api.get('/usage/quota');
      final quota = QuotaStatus.fromJson(response.data as Map<String, dynamic>);

      // Cache locally.
      await _storage.setSetting(_keyQuotaStatus, jsonEncode(quota.toJson()));

      return quota;
    } on ApiException {
      // Return cached data if available.
      return _getCachedQuotaStatus();
    } catch (e) {
      throw ApiUsageException(
        message: 'Failed to get quota status: $e',
        operation: 'getQuotaStatus',
        originalError: e,
      );
    }
  }

  /// Check whether enough quota is available for an estimated usage.
  ///
  /// [estimatedTokens] is the number of tokens you expect to consume.
  /// Returns `true` if the call should be allowed.
  Future<bool> checkQuotaAvailable({int estimatedTokens = 0}) async {
    try {
      final quota = await getQuotaStatus();
      if (quota.isExceeding) return false;
      return quota.remaining >= estimatedTokens;
    } catch (e) {
      // Allow on error to prevent blocking the user.
      debugPrint('[ApiUsageService] Quota check failed, allowing: $e');
      return true;
    }
  }

  /// Set the monthly quota limit.
  ///
  /// Only owners can change the quota. Common values:
  /// - 5_000 for Pro tier
  /// - 50_000 for Team tier
  /// - 500_000 for Enterprise tier
  Future<void> setMonthlyQuota(int quota) async {
    _ensureInitialized();
    try {
      await _api.put('/usage/quota', data: {'monthlyQuota': quota});
      await _storage.setSetting(_keyMonthlyQuota, quota);
      debugPrint('[ApiUsageService] Set monthly quota to $quota');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiUsageException(
        message: 'Failed to set monthly quota: $e',
        operation: 'setMonthlyQuota',
        originalError: e,
      );
    }
  }

  // ── Usage Statistics ──────────────────────────────────────────────────

  /// Get aggregated usage statistics.
  ///
  /// [startDate] and [endDate] filter the time range. If null,
  /// returns statistics for the current billing period.
  Future<ApiUsageStats> getUsageStats({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    _ensureInitialized();
    try {
      final query = <String, dynamic>{};
      if (startDate != null) query['start'] = startDate.toIso8601String();
      if (endDate != null) query['end'] = endDate.toIso8601String();

      final response = await _api.get('/usage/stats', query: query);
      final stats = ApiUsageStats.fromJson(response.data as Map<String, dynamic>);

      await _storage.setSetting(_keyUsageStats, jsonEncode(stats.toJson()));

      return stats;
    } on ApiException {
      // Return cached stats if available.
      return _getCachedUsageStats();
    } catch (e) {
      throw ApiUsageException(
        message: 'Failed to get usage stats: $e',
        operation: 'getUsageStats',
        originalError: e,
      );
    }
  }

  /// Get daily usage breakdown.
  ///
  /// [days] controls how many days to include (default: 30).
  /// Returns a list sorted by date (oldest first).
  Future<List<DailyUsage>> getDailyUsage({int days = 30}) async {
    _ensureInitialized();
    try {
      final response = await _api.get(
        '/usage/daily',
        query: {'days': days},
      );
      final data = response.data as List<dynamic>;
      final usage = data
          .map((json) => DailyUsage.fromJson(json as Map<String, dynamic>))
          .toList();

      usage.sort((a, b) => a.date.compareTo(b.date));
      return usage;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiUsageException(
        message: 'Failed to get daily usage: $e',
        operation: 'getDailyUsage',
        originalError: e,
      );
    }
  }

  /// Get usage breakdown by AI provider.
  ///
  /// [days] controls the time window (default: 30).
  /// Returns providers sorted by usage (highest first).
  Future<List<ProviderUsage>> getUsageByProvider({int days = 30}) async {
    _ensureInitialized();
    try {
      final response = await _api.get(
        '/usage/by-provider',
        query: {'days': days},
      );
      final data = response.data as List<dynamic>;
      final usage = data.map((json) {
        final jsonMap = json as Map<String, dynamic>;
        return ProviderUsage(
          provider: jsonMap['provider'] as String,
          tokensUsed: jsonMap['tokensUsed'] as int,
          requestCount: jsonMap['requestCount'] as int,
          percentage: (jsonMap['percentage'] as num).toDouble(),
          color: _providerColors[jsonMap['provider'] as String] ?? AppTheme.textTertiary,
        );
      }).toList();

      usage.sort((a, b) => b.tokensUsed.compareTo(a.tokensUsed));
      return usage;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiUsageException(
        message: 'Failed to get provider usage: $e',
        operation: 'getUsageByProvider',
        originalError: e,
      );
    }
  }

  /// Get usage breakdown by endpoint type.
  ///
  /// [days] controls the time window (default: 30).
  Future<List<EndpointUsage>> getUsageByEndpoint({int days = 30}) async {
    _ensureInitialized();
    try {
      final response = await _api.get(
        '/usage/by-endpoint',
        query: {'days': days},
      );
      final data = response.data as List<dynamic>;
      return data
          .map((json) => EndpointUsage.fromJson(json as Map<String, dynamic>))
          .toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiUsageException(
        message: 'Failed to get endpoint usage: $e',
        operation: 'getUsageByEndpoint',
        originalError: e,
      );
    }
  }

  /// Get hourly usage pattern.
  ///
  /// [days] controls the time window for averaging (default: 7).
  /// Returns 24 entries (one per hour, 0–23).
  Future<List<HourlyUsage>> getHourlyPattern({int days = 7}) async {
    _ensureInitialized();
    try {
      final response = await _api.get(
        '/usage/hourly-pattern',
        query: {'days': days},
      );
      final data = response.data as List<dynamic>;
      final usage = data
          .map((json) => HourlyUsage.fromJson(json as Map<String, dynamic>))
          .toList();

      // Ensure all 24 hours are present.
      final byHour = {for (final u in usage) u.hour: u};
      final result = <HourlyUsage>[];
      for (var h = 0; h < 24; h++) {
        result.add(byHour[h] ?? HourlyUsage(hour: h, avgTokens: 0, avgRequests: 0));
      }
      return result;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiUsageException(
        message: 'Failed to get hourly pattern: $e',
        operation: 'getHourlyPattern',
        originalError: e,
      );
    }
  }

  // ── Projections & Alerts ──────────────────────────────────────────────

  /// Get a projection of whether monthly usage will exceed the quota.
  ///
  /// Uses the current daily usage rate to extrapolate the full month.
  Future<UsageProjection> getUsageProjection() async {
    _ensureInitialized();
    try {
      final response = await _api.get('/usage/projection');
      return UsageProjection.fromJson(response.data as Map<String, dynamic>);
    } on ApiException catch (e) {
      debugPrint('[ApiUsageService] Projection API failed, computing locally: $e');
      // Compute locally from available data.
      return _computeLocalProjection();
    } catch (e) {
      throw ApiUsageException(
        message: 'Failed to get usage projection: $e',
        operation: 'getUsageProjection',
        originalError: e,
      );
    }
  }

  /// Get active (non-dismissed) usage alerts.
  Future<List<UsageAlert>> getActiveAlerts() async {
    _ensureInitialized();
    try {
      final response = await _api.get('/usage/alerts');
      final data = response.data as List<dynamic>;
      return data
          .map((json) => UsageAlert.fromJson(json as Map<String, dynamic>))
          .where((alert) => !alert.isDismissed)
          .toList();
    } on ApiException {
      // Return empty list on error.
      return [];
    } catch (e) {
      throw ApiUsageException(
        message: 'Failed to get alerts: $e',
        operation: 'getActiveAlerts',
        originalError: e,
      );
    }
  }

  /// Create a new usage alert threshold.
  ///
  /// [threshold] is the percentage (0–100) at which to trigger.
  /// [type] is one of: 'percentage', 'fixed', 'projected'.
  Future<void> createAlert({
    required int threshold,
    required String type,
  }) async {
    _ensureInitialized();
    try {
      await _api.post('/usage/alerts', data: {
        'threshold': threshold,
        'type': type,
      });
      debugPrint('[ApiUsageService] Created alert: $type at $threshold%');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiUsageException(
        message: 'Failed to create alert: $e',
        operation: 'createAlert',
        originalError: e,
      );
    }
  }

  /// Dismiss an active alert by ID.
  Future<void> dismissAlert(String alertId) async {
    _ensureInitialized();
    try {
      await _api.patch('/usage/alerts/$alertId/dismiss');
      debugPrint('[ApiUsageService] Dismissed alert: $alertId');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiUsageException(
        message: 'Failed to dismiss alert: $e',
        operation: 'dismissAlert',
        originalError: e,
      );
    }
  }

  // ── Recommendations ───────────────────────────────────────────────────

  /// Get optimization tips for reducing API usage.
  ///
  /// Returns a list of actionable recommendations sorted by
  /// potential savings (highest first).
  Future<List<OptimizationTip>> getOptimizationTips() async {
    _ensureInitialized();
    try {
      final response = await _api.get('/usage/tips');
      final data = response.data as List<dynamic>;
      final tips = data
          .map((json) => OptimizationTip.fromJson(json as Map<String, dynamic>))
          .toList();

      tips.sort((a, b) => b.potentialSavings.compareTo(a.potentialSavings));
      return tips;
    } on ApiException {
      // Return default tips if API fails.
      return _getDefaultTips();
    } catch (e) {
      throw ApiUsageException(
        message: 'Failed to get optimization tips: $e',
        operation: 'getOptimizationTips',
        originalError: e,
      );
    }
  }

  // ── Private Helpers ───────────────────────────────────────────────────

  void _ensureInitialized() {
    if (!_initialized) {
      throw const ApiUsageException(
        message: 'ApiUsageService not initialized. Call init() first.',
        operation: '_ensureInitialized',
      );
    }
  }

  /// Persist pending records to local storage.
  Future<void> _persistPendingRecords() async {
    try {
      await _storage.setSetting(
        _keyPendingRecords,
        jsonEncode(_pendingRecords),
      );
    } catch (e) {
      debugPrint('[ApiUsageService] Failed to persist pending records: $e');
    }
  }

  /// Load cached quota status from local storage.
  Future<QuotaStatus> _getCachedQuotaStatus() async {
    try {
      final cached = await _storage.getSetting<String>(_keyQuotaStatus);
      if (cached != null && cached.isNotEmpty) {
        return QuotaStatus.fromJson(jsonDecode(cached) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('[ApiUsageService] Failed to load cached quota: $e');
    }
    // Return a default (empty) quota status.
    return QuotaStatus(
      monthlyQuota: 5000,
      usedThisMonth: 0,
      remaining: 5000,
      usagePercent: 0.0,
      quotaResetsAt: _nextMonthStart(),
      isExceeding: false,
      warnings: const [],
    );
  }

  /// Load cached usage stats from local storage.
  Future<ApiUsageStats> _getCachedUsageStats() async {
    try {
      final cached = await _storage.getSetting<String>(_keyUsageStats);
      if (cached != null && cached.isNotEmpty) {
        return ApiUsageStats.fromJson(jsonDecode(cached) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('[ApiUsageService] Failed to load cached stats: $e');
    }
    // Return empty stats.
    return ApiUsageStats(
      totalTokensUsed: 0,
      totalRequests: 0,
      avgTokensPerRequest: 0.0,
      successRate: 100.0,
      topProvider: 'none',
      topModel: 'none',
      estimatedCost: 0,
      quotaStatus: await _getCachedQuotaStatus(),
    );
  }

  /// Compute a local usage projection from cached data.
  Future<UsageProjection> _computeLocalProjection() async {
    try {
      final daily = await getDailyUsage(days: 7);
      final quota = await getQuotaStatus();

      if (daily.isEmpty) {
        return UsageProjection(
          projectedMonthlyUsage: 0,
          willExceedQuota: false,
          recommendation: "Not enough data to project usage.",
        );
      }

      final avgDaily = daily.map((d) => d.tokensUsed).reduce((a, b) => a + b) / daily.length;
      final daysInMonth = _daysInCurrentMonth();
      final today = DateTime.now().day;
      final projectedTotal = avgDaily * daysInMonth;
      final remainingDays = daysInMonth - today;
      final remainingBudget = quota.monthlyQuota - quota.usedThisMonth;

      final willExceed = projectedTotal > quota.monthlyQuota;
      int? daysUntilExceed;

      if (willExceed && avgDaily > 0) {
        daysUntilExceed = (remainingBudget / avgDaily).ceil();
      }

      String recommendation;
      if (willExceed) {
        final overagePercent = ((projectedTotal - quota.monthlyQuota) / quota.monthlyQuota * 100).round();
        recommendation = "Reduce usage by $overagePercent% or upgrade your plan to avoid quota exhaustion.";
      } else {
        final headroom = ((quota.monthlyQuota - projectedTotal) / quota.monthlyQuota * 100).round();
        recommendation = "You're on track. You have about $headroom% headroom remaining.";
      }

      return UsageProjection(
        projectedMonthlyUsage: projectedTotal,
        willExceedQuota: willExceed,
        daysUntilExceed: daysUntilExceed,
        recommendation: recommendation,
      );
    } catch (e) {
      return UsageProjection(
        projectedMonthlyUsage: 0,
        willExceedQuota: false,
        recommendation: "Unable to compute projection. Please try again later.",
      );
    }
  }

  /// Get default optimization tips when the API is unavailable.
  List<OptimizationTip> _getDefaultTips() {
    return const [
      OptimizationTip(
        title: 'Use smaller models for simple tasks',
        description: 'For tasks like summarization or simple Q&A, use gpt-4o-mini or claude-haiku instead of the largest models.',
        action: 'Switch to a smaller model in Settings > AI Configuration.',
        potentialSavings: 150000,
      ),
      OptimizationTip(
        title: 'Reduce max tokens for responses',
        description: 'Lowering the max_tokens parameter prevents the model from generating unnecessarily long responses.',
        action: 'Set max tokens to 1024 for most conversations in Settings.',
        potentialSavings: 80000,
      ),
      OptimizationTip(
        title: 'Enable response caching',
        description: 'Cache responses for frequently asked questions to avoid redundant API calls.',
        action: 'Enable caching in Settings > AI Settings.',
        potentialSavings: 50000,
      ),
      OptimizationTip(
        title: 'Batch multiple requests',
        description: 'Combine multiple small prompts into a single larger request to reduce overhead.',
        action: 'Use the batch mode for code reviews and refactoring.',
        potentialSavings: 30000,
      ),
      OptimizationTip(
        title: 'Use streaming responses judiciously',
        description: 'Streaming uses slightly more tokens due to connection overhead. Disable for non-interactive tasks.',
        action: 'Disable streaming in Settings > AI Settings.',
        potentialSavings: 20000,
      ),
    ];
  }

  /// Calculate the start of the next month.
  DateTime _nextMonthStart() {
    final now = DateTime.now();
    if (now.month == 12) {
      return DateTime(now.year + 1, 1, 1);
    }
    return DateTime(now.year, now.month + 1, 1);
  }

  /// Number of days in the current month.
  int _daysInCurrentMonth() {
    final now = DateTime.now();
    final nextMonth = now.month == 12
        ? DateTime(now.year + 1, 1, 1)
        : DateTime(now.year, now.month + 1, 1);
    return nextMonth.subtract(const Duration(days: 1)).day;
  }

  /// Dispose and release resources.
  void dispose() {
    _initialized = false;
    _pendingRecords.clear();
    debugPrint('[ApiUsageService] Disposed');
  }
}
