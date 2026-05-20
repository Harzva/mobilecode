import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'token_pricing_service.dart';

class TokenUsageSnapshot {
  const TokenUsageSnapshot({
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
    required this.cacheReadTokens,
    required this.cacheWriteTokens,
    required this.cacheMissTokens,
    required this.estimated,
  });

  final int inputTokens;
  final int outputTokens;
  final int totalTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final int cacheMissTokens;
  final bool estimated;

  bool get hasProviderUsage => !estimated && totalTokens > 0;

  TokenUsageSnapshot merge(TokenUsageSnapshot other) {
    return TokenUsageSnapshot(
      inputTokens: math.max(inputTokens, other.inputTokens),
      outputTokens: math.max(outputTokens, other.outputTokens),
      totalTokens: math.max(totalTokens, other.totalTokens),
      cacheReadTokens: math.max(cacheReadTokens, other.cacheReadTokens),
      cacheWriteTokens: math.max(cacheWriteTokens, other.cacheWriteTokens),
      cacheMissTokens: math.max(cacheMissTokens, other.cacheMissTokens),
      estimated: estimated && other.estimated,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'inputTokens': inputTokens,
      'outputTokens': outputTokens,
      'totalTokens': totalTokens,
      'cacheReadTokens': cacheReadTokens,
      'cacheWriteTokens': cacheWriteTokens,
      'cacheMissTokens': cacheMissTokens,
      'estimated': estimated,
    };
  }

  factory TokenUsageSnapshot.fromJson(Map<String, dynamic> json) {
    return TokenUsageSnapshot(
      inputTokens: json['inputTokens'] as int? ?? 0,
      outputTokens: json['outputTokens'] as int? ?? 0,
      totalTokens: json['totalTokens'] as int? ?? 0,
      cacheReadTokens: json['cacheReadTokens'] as int? ?? 0,
      cacheWriteTokens: json['cacheWriteTokens'] as int? ?? 0,
      cacheMissTokens: json['cacheMissTokens'] as int? ?? 0,
      estimated: json['estimated'] as bool? ?? true,
    );
  }

  static const empty = TokenUsageSnapshot(
    inputTokens: 0,
    outputTokens: 0,
    totalTokens: 0,
    cacheReadTokens: 0,
    cacheWriteTokens: 0,
    cacheMissTokens: 0,
    estimated: true,
  );
}

class TokenUsageEvent {
  const TokenUsageEvent({
    required this.id,
    required this.provider,
    required this.model,
    required this.endpoint,
    required this.sessionId,
    required this.runId,
    required this.roleId,
    required this.durationMs,
    required this.success,
    required this.cancelled,
    required this.usage,
    required this.costEstimate,
    required this.pricingSource,
    required this.pricingUpdatedAt,
    required this.createdAt,
  });

  final String id;
  final String provider;
  final String model;
  final String endpoint;
  final String? sessionId;
  final String? runId;
  final String? roleId;
  final int durationMs;
  final bool success;
  final bool cancelled;
  final TokenUsageSnapshot usage;
  final double costEstimate;
  final String pricingSource;
  final DateTime pricingUpdatedAt;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'provider': provider,
      'model': model,
      'endpoint': endpoint,
      'sessionId': sessionId,
      'runId': runId,
      'roleId': roleId,
      'durationMs': durationMs,
      'success': success,
      'cancelled': cancelled,
      'usage': usage.toJson(),
      'costEstimate': costEstimate,
      'pricingSource': pricingSource,
      'pricingUpdatedAt': pricingUpdatedAt.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory TokenUsageEvent.fromJson(Map<String, dynamic> json) {
    return TokenUsageEvent(
      id: json['id'] as String? ?? 'usage_${DateTime.now().microsecondsSinceEpoch}',
      provider: json['provider'] as String? ?? 'unknown',
      model: json['model'] as String? ?? 'unknown',
      endpoint: json['endpoint'] as String? ?? 'unknown',
      sessionId: json['sessionId'] as String?,
      runId: json['runId'] as String?,
      roleId: json['roleId'] as String?,
      durationMs: json['durationMs'] as int? ?? 0,
      success: json['success'] as bool? ?? false,
      cancelled: json['cancelled'] as bool? ?? false,
      usage: TokenUsageSnapshot.fromJson(Map<String, dynamic>.from(json['usage'] as Map? ?? const {})),
      costEstimate: (json['costEstimate'] as num?)?.toDouble() ?? 0,
      pricingSource: json['pricingSource'] as String? ?? 'Legacy estimate',
      pricingUpdatedAt: DateTime.tryParse(json['pricingUpdatedAt'] as String? ?? '') ?? DateTime(2026, 5, 18),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class TokenUsageSummary {
  const TokenUsageSummary({
    required this.totalTokens,
    required this.inputTokens,
    required this.outputTokens,
    required this.cacheReadTokens,
    required this.cacheWriteTokens,
    required this.cacheMissTokens,
    required this.requestCount,
    required this.successCount,
    required this.estimatedCount,
    required this.costEstimate,
    required this.byProvider,
  });

  final int totalTokens;
  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final int cacheMissTokens;
  final int requestCount;
  final int successCount;
  final int estimatedCount;
  final double costEstimate;
  final Map<String, int> byProvider;

  double get cacheHitRate {
    final denominator = cacheReadTokens + cacheWriteTokens + cacheMissTokens;
    if (denominator <= 0) return 0;
    return cacheReadTokens / denominator;
  }

  static const empty = TokenUsageSummary(
    totalTokens: 0,
    inputTokens: 0,
    outputTokens: 0,
    cacheReadTokens: 0,
    cacheWriteTokens: 0,
    cacheMissTokens: 0,
    requestCount: 0,
    successCount: 0,
    estimatedCount: 0,
    costEstimate: 0,
    byProvider: {},
  );
}

class TokenUsageAccumulator {
  TokenUsageAccumulator({required this.providerKind});

  final String providerKind;
  TokenUsageSnapshot _snapshot = TokenUsageSnapshot.empty;

  void addChunk(Map<String, dynamic> chunk) {
    final parsed = providerKind == 'anthropic'
        ? TokenUsageService.parseAnthropicUsage(chunk)
        : TokenUsageService.parseOpenAiUsage(chunk);
    if (parsed.totalTokens > 0 || parsed.inputTokens > 0 || parsed.outputTokens > 0) {
      _snapshot = _snapshot.merge(parsed);
    }
  }

  TokenUsageSnapshot snapshot({required int inputChars, required int outputChars}) {
    if (_snapshot.hasProviderUsage) return _snapshot;
    return TokenUsageService.estimateUsage(inputChars: inputChars, outputChars: outputChars);
  }
}

class TokenUsageService extends ChangeNotifier {
  TokenUsageService._();

  static final TokenUsageService instance = TokenUsageService._();
  static const _eventsKey = 'mobilecode.token_usage.events.v1';

  final _summaryController = StreamController<TokenUsageSummary>.broadcast();
  final List<TokenUsageEvent> _events = [];
  SharedPreferences? _prefs;
  bool _initialized = false;

  List<TokenUsageEvent> get recentEvents => List.unmodifiable(_events);

  TokenUsageSummary get summary => _summarize(_events);

  Future<void> initialize() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs?.getString(_eventsKey);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _events
            ..clear()
            ..addAll(decoded.whereType<Map>().map((item) => TokenUsageEvent.fromJson(Map<String, dynamic>.from(item))));
        }
      } catch (error) {
        debugPrint('[TokenUsageService] Failed to load usage events: $error');
      }
    }
    _initialized = true;
    _publish();
  }

  Stream<TokenUsageSummary> watchSummary() async* {
    await initialize();
    yield summary;
    yield* _summaryController.stream;
  }

  String recordStarted({
    required String provider,
    required String model,
    required String endpoint,
    String? sessionId,
    String? runId,
    String? roleId,
  }) {
    return 'usage_${DateTime.now().microsecondsSinceEpoch}';
  }

  Future<TokenUsageEvent> recordCompleted({
    required String provider,
    required String model,
    required String endpoint,
    required int durationMs,
    required bool success,
    bool cancelled = false,
    String? sessionId,
    String? runId,
    String? roleId,
    TokenUsageSnapshot? usage,
    int inputChars = 0,
    int outputChars = 0,
  }) async {
    await initialize();
    final snapshot = usage?.hasProviderUsage == true
        ? usage!
        : estimateUsage(inputChars: inputChars, outputChars: outputChars);
    final resolvedModel = model.isEmpty ? 'default' : model;
    final costEstimate = await TokenPricingService.instance.estimateCost(
      provider: provider,
      model: resolvedModel,
      inputTokens: snapshot.inputTokens,
      outputTokens: snapshot.outputTokens,
      cacheReadTokens: snapshot.cacheReadTokens,
      cacheWriteTokens: snapshot.cacheWriteTokens,
    );
    final event = TokenUsageEvent(
      id: 'usage_${DateTime.now().microsecondsSinceEpoch}',
      provider: provider,
      model: resolvedModel,
      endpoint: endpoint,
      sessionId: sessionId,
      runId: runId,
      roleId: roleId,
      durationMs: durationMs,
      success: success,
      cancelled: cancelled,
      usage: snapshot,
      costEstimate: costEstimate.costUsd,
      pricingSource: costEstimate.price.sourceName,
      pricingUpdatedAt: costEstimate.price.updatedAt,
      createdAt: DateTime.now(),
    );
    _events.insert(0, event);
    if (_events.length > 300) _events.removeRange(300, _events.length);
    await _persist();
    _publish();
    return event;
  }

  Future<TokenUsageEvent> recordCancelled({
    required String provider,
    required String model,
    required String endpoint,
    required int durationMs,
    String? sessionId,
    String? runId,
    String? roleId,
    int inputChars = 0,
    int outputChars = 0,
  }) {
    return recordCompleted(
      provider: provider,
      model: model,
      endpoint: endpoint,
      durationMs: durationMs,
      success: false,
      cancelled: true,
      sessionId: sessionId,
      runId: runId,
      roleId: roleId,
      inputChars: inputChars,
      outputChars: outputChars,
    );
  }

  static TokenUsageSnapshot parseOpenAiUsage(Map<String, dynamic> data) {
    final usage = _usageMap(data);
    if (usage == null) return TokenUsageSnapshot.empty;
    final input = _intValue(usage['prompt_tokens']);
    final output = _intValue(usage['completion_tokens']);
    final total = _intValue(usage['total_tokens'], fallback: input + output);
    final details = usage['prompt_tokens_details'];
    final cached = details is Map ? _intValue(details['cached_tokens']) : 0;
    final miss = math.max(0, input - cached);
    return TokenUsageSnapshot(
      inputTokens: input,
      outputTokens: output,
      totalTokens: total,
      cacheReadTokens: cached,
      cacheWriteTokens: 0,
      cacheMissTokens: miss,
      estimated: total == 0,
    );
  }

  static TokenUsageSnapshot parseAnthropicUsage(Map<String, dynamic> data) {
    final usage = _usageMap(data);
    if (usage == null) return TokenUsageSnapshot.empty;
    final input = _intValue(usage['input_tokens']);
    final output = _intValue(usage['output_tokens']);
    final cacheWrite = _intValue(usage['cache_creation_input_tokens']);
    final cacheRead = _intValue(usage['cache_read_input_tokens']);
    final total = input + output;
    return TokenUsageSnapshot(
      inputTokens: input,
      outputTokens: output,
      totalTokens: total,
      cacheReadTokens: cacheRead,
      cacheWriteTokens: cacheWrite,
      cacheMissTokens: math.max(0, input - cacheRead - cacheWrite),
      estimated: total == 0,
    );
  }

  static TokenUsageSnapshot estimateUsage({required int inputChars, required int outputChars}) {
    final input = math.max(1, (inputChars / 4).ceil());
    final output = math.max(1, (outputChars / 4).ceil());
    return TokenUsageSnapshot(
      inputTokens: input,
      outputTokens: output,
      totalTokens: input + output,
      cacheReadTokens: 0,
      cacheWriteTokens: 0,
      cacheMissTokens: input,
      estimated: true,
    );
  }

  static double estimateCost(TokenUsageSnapshot usage) {
    return (usage.inputTokens * 0.000003) + (usage.outputTokens * 0.000015);
  }

  Future<void> _persist() async {
    await _prefs?.setString(_eventsKey, jsonEncode(_events.map((event) => event.toJson()).toList()));
  }

  void _publish() {
    notifyListeners();
    if (!_summaryController.isClosed) _summaryController.add(summary);
  }

  TokenUsageSummary _summarize(List<TokenUsageEvent> events) {
    final byProvider = <String, int>{};
    var input = 0;
    var output = 0;
    var total = 0;
    var cacheRead = 0;
    var cacheWrite = 0;
    var cacheMiss = 0;
    var success = 0;
    var estimated = 0;
    var cost = 0.0;
    for (final event in events) {
      input += event.usage.inputTokens;
      output += event.usage.outputTokens;
      total += event.usage.totalTokens;
      cacheRead += event.usage.cacheReadTokens;
      cacheWrite += event.usage.cacheWriteTokens;
      cacheMiss += event.usage.cacheMissTokens;
      if (event.success) success++;
      if (event.usage.estimated) estimated++;
      cost += event.costEstimate;
      byProvider[event.provider] = (byProvider[event.provider] ?? 0) + event.usage.totalTokens;
    }
    return TokenUsageSummary(
      totalTokens: total,
      inputTokens: input,
      outputTokens: output,
      cacheReadTokens: cacheRead,
      cacheWriteTokens: cacheWrite,
      cacheMissTokens: cacheMiss,
      requestCount: events.length,
      successCount: success,
      estimatedCount: estimated,
      costEstimate: cost,
      byProvider: byProvider,
    );
  }

  static Map<String, dynamic>? _usageMap(Map<String, dynamic> data) {
    final usage = data['usage'];
    if (usage is Map) return Map<String, dynamic>.from(usage);
    final message = data['message'];
    if (message is Map && message['usage'] is Map) {
      return Map<String, dynamic>.from(message['usage'] as Map);
    }
    final delta = data['delta'];
    if (delta is Map && delta['usage'] is Map) {
      return Map<String, dynamic>.from(delta['usage'] as Map);
    }
    if (data.containsKey('input_tokens') ||
        data.containsKey('prompt_tokens') ||
        data.containsKey('output_tokens') ||
        data.containsKey('completion_tokens')) {
      return data;
    }
    return null;
  }

  static int _intValue(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }
}
