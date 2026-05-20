import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TokenPrice {
  const TokenPrice({
    required this.provider,
    required this.model,
    required this.inputCostPerToken,
    required this.outputCostPerToken,
    required this.cacheReadCostPerToken,
    required this.cacheWriteCostPerToken,
    required this.sourceName,
    required this.sourceUrl,
    required this.updatedAt,
    required this.custom,
    this.notes = '',
  });

  final String provider;
  final String model;
  final double inputCostPerToken;
  final double outputCostPerToken;
  final double cacheReadCostPerToken;
  final double cacheWriteCostPerToken;
  final String sourceName;
  final String sourceUrl;
  final DateTime updatedAt;
  final bool custom;
  final String notes;

  double get inputPerMillion => inputCostPerToken * 1000000;
  double get outputPerMillion => outputCostPerToken * 1000000;
  double get cacheReadPerMillion => cacheReadCostPerToken * 1000000;
  double get cacheWritePerMillion => cacheWriteCostPerToken * 1000000;

  String get key => priceKey(provider, model);

  TokenPrice copyWith({
    String? provider,
    String? model,
    double? inputCostPerToken,
    double? outputCostPerToken,
    double? cacheReadCostPerToken,
    double? cacheWriteCostPerToken,
    String? sourceName,
    String? sourceUrl,
    DateTime? updatedAt,
    bool? custom,
    String? notes,
  }) {
    return TokenPrice(
      provider: provider ?? this.provider,
      model: model ?? this.model,
      inputCostPerToken: inputCostPerToken ?? this.inputCostPerToken,
      outputCostPerToken: outputCostPerToken ?? this.outputCostPerToken,
      cacheReadCostPerToken: cacheReadCostPerToken ?? this.cacheReadCostPerToken,
      cacheWriteCostPerToken: cacheWriteCostPerToken ?? this.cacheWriteCostPerToken,
      sourceName: sourceName ?? this.sourceName,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      updatedAt: updatedAt ?? this.updatedAt,
      custom: custom ?? this.custom,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'provider': provider,
      'model': model,
      'inputCostPerToken': inputCostPerToken,
      'outputCostPerToken': outputCostPerToken,
      'cacheReadCostPerToken': cacheReadCostPerToken,
      'cacheWriteCostPerToken': cacheWriteCostPerToken,
      'sourceName': sourceName,
      'sourceUrl': sourceUrl,
      'updatedAt': updatedAt.toIso8601String(),
      'custom': custom,
      'notes': notes,
    };
  }

  factory TokenPrice.fromJson(Map<String, dynamic> json) {
    return TokenPrice(
      provider: json['provider'] as String? ?? 'custom',
      model: json['model'] as String? ?? 'unknown',
      inputCostPerToken: _doubleValue(json['inputCostPerToken'] ?? json['input_cost_per_token']),
      outputCostPerToken: _doubleValue(json['outputCostPerToken'] ?? json['output_cost_per_token']),
      cacheReadCostPerToken: _doubleValue(
        json['cacheReadCostPerToken'] ?? json['cache_read_input_token_cost'] ?? json['cache_read_cost_per_token'],
      ),
      cacheWriteCostPerToken: _doubleValue(
        json['cacheWriteCostPerToken'] ?? json['cache_creation_input_token_cost'] ?? json['cache_write_cost_per_token'],
      ),
      sourceName: json['sourceName'] as String? ?? 'Custom override',
      sourceUrl: json['sourceUrl'] as String? ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      custom: json['custom'] as bool? ?? false,
      notes: json['notes'] as String? ?? '',
    );
  }

  factory TokenPrice.fromLiteLlmEntry(
    Map<String, dynamic> json, {
    required String snapshotSourceName,
    required String snapshotSourceUrl,
    required DateTime snapshotUpdatedAt,
  }) {
    return TokenPrice(
      provider: json['provider'] as String? ?? json['litellm_provider'] as String? ?? 'unknown',
      model: json['model'] as String? ?? 'unknown',
      inputCostPerToken: _doubleValue(json['input_cost_per_token']),
      outputCostPerToken: _doubleValue(json['output_cost_per_token']),
      cacheReadCostPerToken: _doubleValue(json['cache_read_input_token_cost'] ?? json['cache_read_cost_per_token']),
      cacheWriteCostPerToken: _doubleValue(json['cache_creation_input_token_cost'] ?? json['cache_write_cost_per_token']),
      sourceName: snapshotSourceName,
      sourceUrl: snapshotSourceUrl,
      updatedAt: snapshotUpdatedAt,
      custom: false,
      notes: json['notes'] as String? ?? '',
    );
  }
}

class TokenCostEstimate {
  const TokenCostEstimate({
    required this.costUsd,
    required this.price,
  });

  final double costUsd;
  final TokenPrice price;
}

class TokenPricingCatalog {
  const TokenPricingCatalog({
    required this.sourceName,
    required this.sourceUrl,
    required this.updatedAt,
    required this.snapshotCount,
    required this.overrideCount,
  });

  final String sourceName;
  final String sourceUrl;
  final DateTime updatedAt;
  final int snapshotCount;
  final int overrideCount;
}

class TokenPricingSnapshotUpdate {
  const TokenPricingSnapshotUpdate({
    required this.sourceName,
    required this.sourceUrl,
    required this.updatedAt,
    required this.prices,
    required this.newCount,
    required this.changedCount,
    required this.unchangedCount,
  });

  final String sourceName;
  final String sourceUrl;
  final DateTime updatedAt;
  final List<TokenPrice> prices;
  final int newCount;
  final int changedCount;
  final int unchangedCount;

  int get modelCount => prices.length;

  Map<String, dynamic> toCacheJson() {
    return {
      'sourceName': sourceName,
      'sourceUrl': sourceUrl,
      'updatedAt': updatedAt.toIso8601String(),
      'prices': prices.map((price) => price.toJson()).toList(),
    };
  }
}

class TokenPricingService extends ChangeNotifier {
  TokenPricingService._();

  static final TokenPricingService instance = TokenPricingService._();

  static const _snapshotAsset = 'assets/token_pricing/litellm_price_snapshot.json';
  static const officialLiteLlmRawUrl =
      'https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json';
  static const _overridesKey = 'mobilecode.token_pricing.overrides.v1';
  static const _snapshotCacheKey = 'mobilecode.token_pricing.snapshot_cache.v1';
  static final _fallbackUpdatedAt = DateTime(2026, 5, 18);

  final Map<String, TokenPrice> _snapshotPrices = {};
  final Map<String, TokenPrice> _overrides = {};
  SharedPreferences? _prefs;
  var _initialized = false;
  var _snapshotSourceName = 'MobileCode fallback prices';
  var _snapshotSourceUrl = 'https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json';
  var _snapshotUpdatedAt = _fallbackUpdatedAt;

  List<TokenPrice> get overrides => _overrides.values.toList(growable: false)
    ..sort((a, b) => a.key.compareTo(b.key));

  List<TokenPrice> get snapshotPrices => _snapshotPrices.values.toList(growable: false)
    ..sort((a, b) => a.key.compareTo(b.key));

  List<TokenPrice> get visiblePrices {
    final combined = <String, TokenPrice>{..._snapshotPrices, ..._overrides};
    final values = combined.values.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    return values;
  }

  TokenPricingCatalog get catalog => TokenPricingCatalog(
        sourceName: _snapshotSourceName,
        sourceUrl: _snapshotSourceUrl,
        updatedAt: _snapshotUpdatedAt,
        snapshotCount: _snapshotPrices.length,
        overrideCount: _overrides.length,
      );

  Future<void> initialize() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    await _loadSnapshot();
    _loadCachedSnapshot();
    _loadOverrides();
    _initialized = true;
    notifyListeners();
  }

  Future<TokenCostEstimate> estimateCost({
    required String provider,
    required String model,
    required int inputTokens,
    required int outputTokens,
    required int cacheReadTokens,
    required int cacheWriteTokens,
  }) async {
    await initialize();
    final price = priceFor(provider: provider, model: model);
    return TokenCostEstimate(
      costUsd: estimateWithPrice(
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        cacheReadTokens: cacheReadTokens,
        cacheWriteTokens: cacheWriteTokens,
        price: price,
      ),
      price: price,
    );
  }

  TokenPrice priceFor({required String provider, required String model}) {
    final providerText = provider.trim();
    final modelText = model.trim().isEmpty ? 'default' : model.trim();
    final keys = <String>[
      priceKey(providerText, modelText),
      priceKey(_providerAlias(providerText), modelText),
      priceKey('', modelText),
      priceKey(providerText, _modelAlias(modelText)),
      priceKey(_providerAlias(providerText), _modelAlias(modelText)),
    ];
    for (final key in keys) {
      final override = _overrides[key];
      if (override != null) return override;
    }
    for (final key in keys) {
      final snapshot = _snapshotPrices[key];
      if (snapshot != null) return snapshot;
    }
    return _fallbackPrice(providerText, modelText);
  }

  Future<void> upsertOverride(TokenPrice price) async {
    await initialize();
    final normalized = price.copyWith(
      provider: price.provider.trim().isEmpty ? 'custom' : price.provider.trim(),
      model: price.model.trim().isEmpty ? 'default' : price.model.trim(),
      sourceName: 'User override',
      sourceUrl: '',
      updatedAt: DateTime.now(),
      custom: true,
    );
    _overrides[normalized.key] = normalized;
    await _persistOverrides();
    notifyListeners();
  }

  Future<void> removeOverride(String key) async {
    await initialize();
    _overrides.remove(key);
    await _persistOverrides();
    notifyListeners();
  }

  Future<TokenPricingSnapshotUpdate> checkLiteLlmUpdate({
    Uri? uri,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    await initialize();
    final sourceUri = uri ?? Uri.parse(officialLiteLlmRawUrl);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(sourceUri).timeout(const Duration(seconds: 10));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(timeout);
      final body = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('LiteLLM price update HTTP ${response.statusCode}');
      }
      final remoteUpdatedAt = response.headers.value(HttpHeaders.lastModifiedHeader);
      final parsed = parseLiteLlmSnapshot(
        body,
        sourceName: 'LiteLLM remote snapshot',
        sourceUrl: sourceUri.toString(),
        updatedAt: _parseHttpDate(remoteUpdatedAt) ?? DateTime.now(),
      );
      if (parsed.isEmpty) {
        throw StateError('LiteLLM price update returned no usable model prices.');
      }
      return _buildUpdate(parsed);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> applySnapshotUpdate(TokenPricingSnapshotUpdate update) async {
    await initialize();
    if (update.prices.isEmpty) {
      throw StateError('Cannot apply an empty pricing snapshot.');
    }
    _snapshotSourceName = update.sourceName;
    _snapshotSourceUrl = update.sourceUrl;
    _snapshotUpdatedAt = update.updatedAt;
    _snapshotPrices
      ..clear()
      ..addEntries(update.prices.map((price) => MapEntry(price.key, price)));
    await _prefs?.setString(_snapshotCacheKey, jsonEncode(update.toCacheJson()));
    notifyListeners();
  }

  @visibleForTesting
  TokenPricingSnapshotUpdate buildUpdateFromJson(
    String raw, {
    required String sourceName,
    required String sourceUrl,
    required DateTime updatedAt,
  }) {
    final prices = parseLiteLlmSnapshot(
      raw,
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      updatedAt: updatedAt,
    );
    return _buildUpdate(prices);
  }

  @visibleForTesting
  void resetForTesting() {
    _snapshotPrices.clear();
    _overrides.clear();
    _prefs = null;
    _initialized = false;
    _snapshotSourceName = 'MobileCode fallback prices';
    _snapshotSourceUrl = 'https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json';
    _snapshotUpdatedAt = _fallbackUpdatedAt;
  }

  Future<void> _loadSnapshot() async {
    try {
      final raw = await rootBundle.loadString(_snapshotAsset);
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      _snapshotSourceName = decoded['sourceName'] as String? ?? _snapshotSourceName;
      _snapshotSourceUrl = decoded['sourceUrl'] as String? ?? _snapshotSourceUrl;
      _snapshotUpdatedAt = DateTime.tryParse(decoded['updatedAt'] as String? ?? '') ?? _snapshotUpdatedAt;
      final prices = parseLiteLlmSnapshot(
        raw,
        sourceName: _snapshotSourceName,
        sourceUrl: _snapshotSourceUrl,
        updatedAt: _snapshotUpdatedAt,
      );
      _snapshotPrices
        ..clear()
        ..addEntries(prices.map((price) => MapEntry(price.key, price)));
    } on Object catch (error) {
      debugPrint('[TokenPricingService] Failed to load price snapshot: $error');
      final fallback = _fallbackPrice('anthropic', 'mimo-v2.5-pro');
      _snapshotPrices[fallback.key] = fallback;
    }
  }

  void _loadCachedSnapshot() {
    final raw = _prefs?.getString(_snapshotCacheKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      _snapshotSourceName = decoded['sourceName'] as String? ?? _snapshotSourceName;
      _snapshotSourceUrl = decoded['sourceUrl'] as String? ?? _snapshotSourceUrl;
      _snapshotUpdatedAt = DateTime.tryParse(decoded['updatedAt'] as String? ?? '') ?? _snapshotUpdatedAt;
      final prices = parseLiteLlmSnapshot(
        raw,
        sourceName: _snapshotSourceName,
        sourceUrl: _snapshotSourceUrl,
        updatedAt: _snapshotUpdatedAt,
      );
      if (prices.isEmpty) return;
      _snapshotPrices
        ..clear()
        ..addEntries(prices.map((price) => MapEntry(price.key, price)));
    } on Object catch (error) {
      debugPrint('[TokenPricingService] Failed to load cached price snapshot: $error');
    }
  }

  void _loadOverrides() {
    final raw = _prefs?.getString(_overridesKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _overrides
          ..clear()
          ..addEntries(decoded.whereType<Map>().map((entry) {
            final price = TokenPrice.fromJson(Map<String, dynamic>.from(entry)).copyWith(custom: true);
            return MapEntry(price.key, price);
          }));
      }
    } on Object catch (error) {
      debugPrint('[TokenPricingService] Failed to load price overrides: $error');
    }
  }

  Future<void> _persistOverrides() async {
    await _prefs?.setString(_overridesKey, jsonEncode(_overrides.values.map((price) => price.toJson()).toList()));
  }

  TokenPrice _fallbackPrice(String provider, String model) {
    return TokenPrice(
      provider: provider.trim().isEmpty ? 'unknown' : provider,
      model: model.trim().isEmpty ? 'default' : model,
      inputCostPerToken: 0.000003,
      outputCostPerToken: 0.000015,
      cacheReadCostPerToken: 0.0000003,
      cacheWriteCostPerToken: 0.00000375,
      sourceName: 'MobileCode fallback',
      sourceUrl: _snapshotSourceUrl,
      updatedAt: _fallbackUpdatedAt,
      custom: false,
      notes: 'Fallback Anthropic-class estimate. Add a user override for billing-grade accuracy.',
    );
  }

  TokenPricingSnapshotUpdate _buildUpdate(List<TokenPrice> prices) {
    var newCount = 0;
    var changedCount = 0;
    var unchangedCount = 0;
    for (final price in prices) {
      final existing = _snapshotPrices[price.key];
      if (existing == null) {
        newCount++;
      } else if (_priceChanged(existing, price)) {
        changedCount++;
      } else {
        unchangedCount++;
      }
    }
    final sourceName = prices.isEmpty ? 'LiteLLM remote snapshot' : prices.first.sourceName;
    final sourceUrl = prices.isEmpty ? officialLiteLlmRawUrl : prices.first.sourceUrl;
    final updatedAt = prices.isEmpty ? DateTime.now() : prices.first.updatedAt;
    return TokenPricingSnapshotUpdate(
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      updatedAt: updatedAt,
      prices: prices,
      newCount: newCount,
      changedCount: changedCount,
      unchangedCount: unchangedCount,
    );
  }
}

List<TokenPrice> parseLiteLlmSnapshot(
  String raw, {
  required String sourceName,
  required String sourceUrl,
  required DateTime updatedAt,
}) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) return const [];
  final pricesNode = decoded['prices'];
  if (pricesNode is List) {
    return pricesNode
        .whereType<Map>()
        .map((entry) {
          final map = Map<String, dynamic>.from(entry);
          return TokenPrice.fromJson({
            ...map,
            'sourceName': map['sourceName'] as String? ?? decoded['sourceName'] as String? ?? sourceName,
            'sourceUrl': map['sourceUrl'] as String? ?? decoded['sourceUrl'] as String? ?? sourceUrl,
            'updatedAt': map['updatedAt'] as String? ?? decoded['updatedAt'] as String? ?? updatedAt.toIso8601String(),
            'custom': map['custom'] as bool? ?? false,
          });
        })
        .where(_hasUsablePrice)
        .toList(growable: false);
  }

  final parsed = <TokenPrice>[];
  for (final entry in decoded.entries) {
    final value = entry.value;
    if (value is! Map) continue;
    final map = Map<String, dynamic>.from(value);
    if (!_hasLiteLlmCostFields(map)) continue;
    final price = TokenPrice.fromLiteLlmEntry(
      {
        ...map,
        'model': map['model'] ?? entry.key,
      },
      snapshotSourceName: sourceName,
      snapshotSourceUrl: sourceUrl,
      snapshotUpdatedAt: updatedAt,
    );
    if (_hasUsablePrice(price)) parsed.add(price);
  }
  return parsed;
}

double estimateWithPrice({
  required int inputTokens,
  required int outputTokens,
  required int cacheReadTokens,
  required int cacheWriteTokens,
  required TokenPrice price,
}) {
  final nonCachedInput = math.max(0, inputTokens - cacheReadTokens - cacheWriteTokens).toDouble();
  return (nonCachedInput * price.inputCostPerToken) +
      (outputTokens * price.outputCostPerToken) +
      (cacheReadTokens * price.cacheReadCostPerToken) +
      (cacheWriteTokens * price.cacheWriteCostPerToken);
}

bool _hasUsablePrice(TokenPrice price) {
  return price.model.trim().isNotEmpty &&
      (price.inputCostPerToken > 0 ||
          price.outputCostPerToken > 0 ||
          price.cacheReadCostPerToken > 0 ||
          price.cacheWriteCostPerToken > 0);
}

bool _priceChanged(TokenPrice a, TokenPrice b) {
  const epsilon = 0.000000000001;
  return (a.inputCostPerToken - b.inputCostPerToken).abs() > epsilon ||
      (a.outputCostPerToken - b.outputCostPerToken).abs() > epsilon ||
      (a.cacheReadCostPerToken - b.cacheReadCostPerToken).abs() > epsilon ||
      (a.cacheWriteCostPerToken - b.cacheWriteCostPerToken).abs() > epsilon;
}

bool _hasLiteLlmCostFields(Map<String, dynamic> map) {
  return map.containsKey('input_cost_per_token') ||
      map.containsKey('output_cost_per_token') ||
      map.containsKey('cache_read_input_token_cost') ||
      map.containsKey('cache_read_cost_per_token') ||
      map.containsKey('cache_creation_input_token_cost') ||
      map.containsKey('cache_write_cost_per_token');
}

DateTime? _parseHttpDate(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  try {
    return HttpDate.parse(value);
  } on Object {
    return null;
  }
}

String priceKey(String provider, String model) {
  final providerPart = _normalize(provider);
  final modelPart = _normalize(model);
  return '$providerPart/$modelPart';
}

String _providerAlias(String provider) {
  final normalized = _normalize(provider);
  if (normalized.contains('anthropic') || normalized.contains('claude') || normalized.contains('mimo')) {
    return 'anthropic';
  }
  if (normalized.contains('openai') || normalized.contains('gpt')) return 'openai';
  if (normalized.contains('google') || normalized.contains('gemini')) return 'google';
  return normalized;
}

String _modelAlias(String model) {
  final normalized = _normalize(model);
  if (normalized.contains('mimo-v2.5-pro')) return 'mimo-v2.5-pro';
  if (normalized.contains('gpt-4o-mini')) return 'gpt-4o-mini';
  if (normalized.contains('gpt-4o')) return 'gpt-4o';
  if (normalized.contains('claude-3-5-haiku')) return 'claude-3-5-haiku-latest';
  if (normalized.contains('claude-3-5-sonnet')) return 'claude-3-5-sonnet-latest';
  if (normalized.contains('claude-3-7-sonnet')) return 'claude-3-7-sonnet-latest';
  if (normalized.contains('sonnet-4') || normalized.contains('claude-sonnet-4')) return 'claude-sonnet-4-0';
  return normalized;
}

String _normalize(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_.:-]+'), '-');
}

double _doubleValue(Object? value, {double fallback = 0}) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}
