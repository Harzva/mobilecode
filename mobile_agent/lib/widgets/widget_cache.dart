import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// WIDGET CACHE
// ═══════════════════════════════════════════════════════════════════════════════

/// An LRU (Least Recently Used) cache for expensive widgets.
///
/// Prevents rebuilding widgets when the same key is requested multiple times.
/// This is particularly effective for:
///
/// - List items that are scrolled off and back on screen
/// - Expensive-to-build widgets (charts, rich text, etc.)
/// - Widgets with heavy child subtrees
///
/// ## Usage
/// ```dart
/// // Cache a widget
/// final widget = WidgetCache.getOrCreate(
///   'user_card_$userId',
///   () => UserCard(user: user),
/// );
///
/// // Later, same key returns cached widget (instant)
/// final sameWidget = WidgetCache.getOrCreate(
///   'user_card_$userId',
///   () => UserCard(user: user), // This builder is NOT called
/// );
///
/// // Clear cache when data changes
/// WidgetCache.invalidate('user_card_$userId');
/// ```
class WidgetCache {
  WidgetCache._();

  // ── Internal State ─────────────────────────────────────────────────

  /// Maximum number of entries in the cache.
  static const int _maxSize = 100;

  /// The actual cache storage.
  static final Map<String, Widget> _cache = {};

  /// Access order tracking for LRU eviction.
  /// Most recently accessed keys are at the END of the list.
  static final List<String> _accessOrder = [];

  /// Hit/miss statistics for debugging.
  static int _hits = 0;
  static int _misses = 0;

  // ── Public API ─────────────────────────────────────────────────────

  /// Get a cached widget or create and cache a new one.
  ///
  /// If [key] exists in the cache, returns the cached widget and
  /// updates its access time (LRU tracking).
  ///
  /// If [key] doesn't exist, calls [builder] to create the widget,
  /// stores it in the cache, and returns it.
  ///
  /// If the cache is at capacity, the least recently used entry
  /// is evicted before adding the new one.
  static Widget getOrCreate(String key, Widget Function() builder) {
    if (_cache.containsKey(key)) {
      // Hit: Move to front (most recently used)
      _accessOrder.remove(key);
      _accessOrder.add(key);
      _hits++;
      return _cache[key]!;
    }

    // Miss: Build new widget
    _misses++;

    // Evict oldest if at capacity
    if (_cache.length >= _maxSize) {
      _evictOldest();
    }

    final widget = builder();
    _cache[key] = widget;
    _accessOrder.add(key);
    return widget;
  }

  /// Get a cached widget without updating LRU order.
  ///
  /// Returns null if the key is not in the cache.
  static Widget? peek(String key) {
    return _cache[key];
  }

  /// Check if a key exists in the cache.
  static bool contains(String key) {
    return _cache.containsKey(key);
  }

  /// Invalidate (remove) a specific cached widget.
  ///
  /// Call this when the underlying data has changed and the cached
  /// widget is stale.
  static void invalidate(String key) {
    _cache.remove(key);
    _accessOrder.remove(key);
  }

  /// Invalidate multiple keys matching a prefix.
  static void invalidatePrefix(String prefix) {
    final keysToRemove = _cache.keys
        .where((key) => key.startsWith(prefix))
        .toList();

    for (final key in keysToRemove) {
      _cache.remove(key);
      _accessOrder.remove(key);
    }

    if (keysToRemove.isNotEmpty) {
      debugPrint(
        '[WidgetCache] Invalidated ${keysToRemove.length} entries '
        'with prefix "$prefix"',
      );
    }
  }

  /// Invalidate all cached widgets.
  static void invalidateAll() {
    final count = _cache.length;
    _cache.clear();
    _accessOrder.clear();
    debugPrint('[WidgetCache] Invalidated all $count entries');
  }

  /// Clear the entire cache (alias for [invalidateAll]).
  static void clear() => invalidateAll();

  // ── Statistics ─────────────────────────────────────────────────────

  /// Get cache statistics.
  ///
  /// Returns a map with:
  /// - `size`: Current number of cached widgets
  /// - `maxSize`: Maximum cache capacity
  /// - `hits`: Number of cache hits
  /// - `misses`: Number of cache misses
  /// - `hitRate`: Cache hit rate (0.0-1.0)
  /// - `evictions`: Number of evictions performed
  static Map<String, dynamic> getStats() {
    final total = _hits + _misses;
    return {
      'size': _cache.length,
      'maxSize': _maxSize,
      'hits': _hits,
      'misses': _misses,
      'hitRate': total > 0 ? _hits / total : 0.0,
      'evictions': _evictionCount,
    };
  }

  /// Print cache statistics to the console.
  static void printStats() {
    final stats = getStats();
    final buffer = StringBuffer();
    buffer.writeln('╔══════════════════════════════════════════╗');
    buffer.writeln('║         WIDGET CACHE STATS                ║');
    buffer.writeln('╠══════════════════════════════════════════╣');
    stats.forEach((key, value) {
      final line = '  ${key.padRight(12)}: ${value.toString()}';
      buffer.writeln('║${line.padRight(42)}║');
    });
    buffer.writeln('╚══════════════════════════════════════════╝');
    debugPrint(buffer.toString());
  }

  /// Reset statistics counters.
  static void resetStats() {
    _hits = 0;
    _misses = 0;
    _evictionCount = 0;
  }

  // ── Private ────────────────────────────────────────────────────────

  static int _evictionCount = 0;

  static void _evictOldest() {
    if (_accessOrder.isEmpty) return;
    final oldest = _accessOrder.removeAt(0);
    _cache.remove(oldest);
    _evictionCount++;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUTO-CACHE WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// A widget that automatically caches its child using [WidgetCache].
///
/// When this widget is rebuilt with the same [cacheKey], the cached
/// child is returned directly without calling the builder.
///
/// ## Important
/// The [child] parameter is evaluated eagerly when the widget is created,
/// NOT when the builder is called. For true lazy building, use
/// [AutoCache.builder] instead.
///
/// ## Example
/// ```dart
/// AutoCache(
///   cacheKey: 'repo_card_${repo.id}',
///   child: RepositoryCard(repository: repo), // Built immediately
/// )
///
/// // Lazy building alternative:
/// AutoCache.builder(
///   cacheKey: 'repo_card_${repo.id}',
///   builder: () => RepositoryCard(repository: repo), // Built on cache miss
/// )
/// ```
class AutoCache extends StatelessWidget {
  /// Unique key for this cached widget.
  final String cacheKey;

  /// The child widget (built eagerly).
  final Widget child;

  const AutoCache({
    required this.cacheKey,
    required this.child,
  });

  /// Create an AutoCache with a lazy builder.
  ///
  /// The [builder] is only called on cache misses.
  static Widget builder({
    required String cacheKey,
    required Widget Function() builder,
  }) {
    return WidgetCache.getOrCreate(cacheKey, builder);
  }

  @override
  Widget build(BuildContext context) {
    return WidgetCache.getOrCreate(cacheKey, () => child);
  }

  @override
  bool operator ==(Object other) {
    // Equality based only on cacheKey
    if (identical(this, other)) return true;
    return other is AutoCache && other.cacheKey == cacheKey;
  }

  @override
  int get hashCode => cacheKey.hashCode;
}

// ═══════════════════════════════════════════════════════════════════════════════
// CACHE INVALIDATION NOTIFIER
// ═══════════════════════════════════════════════════════════════════════════════

/// A notifier that triggers cache invalidation for specific keys.
///
/// Use this to invalidate cached widgets when data changes.
///
/// ## Example
/// ```dart
/// // In your state management
/// final cacheNotifier = CacheInvalidationNotifier();
///
/// // When data changes
/// cacheNotifier.invalidate('user_card_123');
///
/// // In your widget tree
/// CacheAwareWidget(
///   cacheKey: 'user_card_123',
///   notifier: cacheNotifier,
///   builder: (context) => UserCard(user: user),
/// )
/// ```
class CacheInvalidationNotifier extends ChangeNotifier {
  final Set<String> _invalidatedKeys = {};
  final Set<String> _invalidatedPrefixes = {};

  /// Invalidate a specific cache key.
  void invalidate(String key) {
    WidgetCache.invalidate(key);
    _invalidatedKeys.add(key);
    notifyListeners();
  }

  /// Invalidate all keys matching a prefix.
  void invalidatePrefix(String prefix) {
    WidgetCache.invalidatePrefix(prefix);
    _invalidatedPrefixes.add(prefix);
    notifyListeners();
  }

  /// Invalidate all cached widgets.
  void invalidateAll() {
    WidgetCache.invalidateAll();
    _invalidatedKeys.clear();
    _invalidatedPrefixes.clear();
    notifyListeners();
  }

  /// Check if a key was invalidated since the last check.
  bool wasInvalidated(String key) {
    if (_invalidatedKeys.contains(key)) return true;
    for (final prefix in _invalidatedPrefixes) {
      if (key.startsWith(prefix)) return true;
    }
    return false;
  }

  /// Clear the invalidation tracking (call after processing).
  void clearTracking() {
    _invalidatedKeys.clear();
    _invalidatedPrefixes.clear();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CACHE-AWARE WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// A widget that listens to cache invalidation and rebuilds when needed.
class CacheAwareWidget extends StatefulWidget {
  final String cacheKey;
  final CacheInvalidationNotifier? notifier;
  final Widget Function(BuildContext) builder;

  const CacheAwareWidget({
    required this.cacheKey,
    this.notifier,
    required this.builder,
  });

  @override
  State<CacheAwareWidget> createState() => _CacheAwareWidgetState();
}

class _CacheAwareWidgetState extends State<CacheAwareWidget> {
  int _buildKey = 0;

  @override
  void initState() {
    super.initState();
    widget.notifier?.addListener(_onInvalidation);
  }

  @override
  void didUpdateWidget(covariant CacheAwareWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notifier != widget.notifier) {
      oldWidget.notifier?.removeListener(_onInvalidation);
      widget.notifier?.addListener(_onInvalidation);
    }
  }

  void _onInvalidation() {
    if (widget.notifier?.wasInvalidated(widget.cacheKey) ?? false) {
      setState(() => _buildKey++);
    }
  }

  @override
  void dispose() {
    widget.notifier?.removeListener(_onInvalidation);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: ValueKey('${widget.cacheKey}_$_buildKey'),
      child: widget.builder(context),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CACHE-BOUND WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// A widget that binds its lifecycle to the cache.
///
/// When this widget is disposed, it optionally invalidates its cache entry.
/// This prevents stale widgets from persisting in the cache.
class CacheBoundWidget extends StatefulWidget {
  final String cacheKey;
  final Widget child;
  final bool invalidateOnDispose;

  const CacheBoundWidget({
    required this.cacheKey,
    required this.child,
    this.invalidateOnDispose = false,
  });

  @override
  State<CacheBoundWidget> createState() => _CacheBoundWidgetState();
}

class _CacheBoundWidgetState extends State<CacheBoundWidget> {
  @override
  void dispose() {
    if (widget.invalidateOnDispose) {
      WidgetCache.invalidate(widget.cacheKey);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WidgetCache.getOrCreate(
      widget.cacheKey,
      () => widget.child,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WARMED CACHE BUILDER
// ═══════════════════════════════════════════════════════════════════════════════

/// Pre-warms the cache with multiple widgets before they are needed.
///
/// Use this to pre-populate the cache during idle time or while
/// showing a loading screen.
class WarmedCacheBuilder extends StatefulWidget {
  final Map<String, Widget Function()> warmers;
  final Widget child;

  const WarmedCacheBuilder({
    required this.warmers,
    required this.child,
  });

  @override
  State<WarmedCacheBuilder> createState() => _WarmedCacheBuilderState();
}

class _WarmedCacheBuilderState extends State<WarmedCacheBuilder> {
  bool _isWarmed = false;

  @override
  void initState() {
    super.initState();
    _warmCache();
  }

  Future<void> _warmCache() async {
    // Warm cache entries in batches to avoid jank
    final entries = widget.warmers.entries.toList();
    const batchSize = 5;

    for (var i = 0; i < entries.length; i += batchSize) {
      final end = (i + batchSize < entries.length)
          ? i + batchSize
          : entries.length;

      for (var j = i; j < end; j++) {
        final entry = entries[j];
        WidgetCache.getOrCreate(entry.key, entry.value);
      }

      // Yield between batches
      await Future.delayed(Duration.zero);
    }

    if (mounted) {
      setState(() => _isWarmed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The child is rendered immediately; cache warming happens in background
    return widget.child;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TIMED CACHE ENTRY
// ═══════════════════════════════════════════════════════════════════════════════

/// A cache entry with an expiration time.
///
/// Entries are automatically invalidated after the specified duration.
class TimedCacheEntry<T> {
  final T value;
  final DateTime expiry;

  TimedCacheEntry(this.value, Duration ttl)
      : expiry = DateTime.now().add(ttl);

  bool get isExpired => DateTime.now().isAfter(expiry);
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXPIRING WIDGET CACHE
// ═══════════════════════════════════════════════════════════════════════════════

/// A widget cache with time-based expiration.
///
/// Useful for widgets that represent data that changes periodically.
class ExpiringWidgetCache {
  static final Map<String, _ExpiringEntry> _cache = {};
  static final List<String> _accessOrder = [];
  static const int _maxSize = 50;

  /// Get or create a cached widget with expiration.
  static Widget getOrCreate(
    String key,
    Widget Function() builder, {
    Duration ttl = const Duration(minutes: 5),
  }) {
    // Check if entry exists and is not expired
    final existing = _cache[key];
    if (existing != null && !existing.isExpired) {
      _accessOrder.remove(key);
      _accessOrder.add(key);
      return existing.widget;
    }

    // Remove expired entry
    if (existing != null) {
      _cache.remove(key);
      _accessOrder.remove(key);
    }

    // Evict oldest if at capacity
    if (_cache.length >= _maxSize) {
      final oldest = _accessOrder.removeAt(0);
      _cache.remove(oldest);
    }

    final widget = builder();
    _cache[key] = _ExpiringEntry(widget, ttl);
    _accessOrder.add(key);
    return widget;
  }

  /// Invalidate a specific entry.
  static void invalidate(String key) {
    _cache.remove(key);
    _accessOrder.remove(key);
  }

  /// Clear all entries.
  static void clear() {
    _cache.clear();
    _accessOrder.clear();
  }

  /// Remove all expired entries.
  static int purgeExpired() {
    final expiredKeys = _cache.entries
        .where((e) => e.value.isExpired)
        .map((e) => e.key)
        .toList();

    for (final key in expiredKeys) {
      _cache.remove(key);
      _accessOrder.remove(key);
    }

    return expiredKeys.length;
  }
}

class _ExpiringEntry {
  final Widget widget;
  final DateTime expiry;

  _ExpiringEntry(this.widget, Duration ttl)
      : expiry = DateTime.now().add(ttl);

  bool get isExpired => DateTime.now().isAfter(expiry);
}
