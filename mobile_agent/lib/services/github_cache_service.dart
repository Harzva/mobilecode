// lib/services/github_cache_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

// =============================================================================
// CACHE EXCEPTION
// =============================================================================

/// Exception thrown by cache operations.
class GitHubCacheException implements Exception {
  final String message;
  final String? operation;

  const GitHubCacheException({
    required this.message,
    this.operation,
  });

  @override
  String toString() => 'GitHubCacheException [$operation]: $message';
}

// =============================================================================
// INTERNAL: IN-MEMORY CACHE ENTRY
// =============================================================================

/// A single entry in the L1 in-memory cache.
///
/// Stores the cached value, the endpoint path (for TTL lookup),
/// and the timestamp when the entry was created.
class _CacheEntry {
  /// The cached response data (JSON-decoded).
  final dynamic value;

  /// The cache key (endpoint path + query params hash).
  final String key;

  /// The endpoint path used for TTL determination.
  final String endpoint;

  /// When this entry was stored.
  final DateTime cachedAt;

  /// Custom TTL override, or null to use endpoint-based TTL.
  final Duration? customTtl;

  /// How many times this entry was accessed.
  int accessCount;

  _CacheEntry({
    required this.value,
    required this.key,
    required this.endpoint,
    this.customTtl,
  })  : cachedAt = DateTime.now(),
        accessCount = 0;

  /// Whether this entry has expired based on its TTL.
  bool isExpired(Map<RegExp, Duration> ttlRules) {
    final ttl = customTtl ?? _resolveTtl(endpoint, ttlRules);
    return DateTime.now().difference(cachedAt) > ttl;
  }

  /// Resolve the TTL for a given endpoint based on pattern rules.
  static Duration _resolveTtl(
    String endpoint,
    Map<RegExp, Duration> ttlRules,
  ) {
    for (final entry in ttlRules.entries) {
      if (entry.key.hasMatch(endpoint)) {
        return entry.value;
      }
    }
    // Default TTL: 5 minutes
    return const Duration(minutes: 5);
  }

  Map<String, dynamic> toPersistMap() => {
        'value': value,
        'key': key,
        'endpoint': endpoint,
        'cachedAt': cachedAt.toIso8601String(),
        'accessCount': accessCount,
      };

  factory _CacheEntry.fromPersistMap(Map<String, dynamic> map) {
    final entry = _CacheEntry(
      value: map['value'],
      key: map['key'] as String,
      endpoint: map['endpoint'] as String,
    );
    entry.accessCount = (map['accessCount'] as int?) ?? 0;
    return entry;
  }
}

// =============================================================================
// CACHE STATISTICS
// =============================================================================

/// Statistics about cache performance and contents.
class CacheStats {
  /// Number of entries in the L1 in-memory cache.
  final int memoryEntries;

  /// Number of entries in the L2 persistent cache.
  final int persistentEntries;

  /// Total cache hits (reads that returned cached data).
  final int hits;

  /// Total cache misses (reads that found no valid cached data).
  final int misses;

  /// Number of writes to the cache.
  final int writes;

  /// Number of explicit invalidations.
  final int invalidations;

  /// When the stats were last reset.
  final DateTime lastReset;

  const CacheStats({
    this.memoryEntries = 0,
    this.persistentEntries = 0,
    this.hits = 0,
    this.misses = 0,
    this.writes = 0,
    this.invalidations = 0,
    required this.lastReset,
  });

  /// Cache hit rate as a percentage (0.0 to 1.0).
  double get hitRate {
    final total = hits + misses;
    if (total == 0) return 0.0;
    return hits / total;
  }

  /// Cache hit rate as a formatted percentage string.
  String get hitRatePercent => '${(hitRate * 100).toStringAsFixed(1)}%';

  /// Total number of requests (hits + misses).
  int get totalRequests => hits + misses;

  @override
  String toString() {
    return 'CacheStats(mem=$memoryEntries, persist=$persistentEntries, '
        'hitRate=$hitRatePercent, hits=$hits, misses=$misses, writes=$writes)';
  }
}

// =============================================================================
// RATE LIMIT INFO
// =============================================================================

/// GitHub API rate limit status.
class RateLimit {
  /// Maximum requests allowed per hour.
  final int limit;

  /// Remaining requests in the current window.
  final int remaining;

  /// Requests used in the current window.
  final int used;

  /// When the rate limit window resets.
  final DateTime resetAt;

  const RateLimit({
    required this.limit,
    required this.remaining,
    required this.used,
    required this.resetAt,
  });

  /// Usage percentage (0.0 to 1.0).
  double get usagePercent => used / limit;

  /// Whether remaining requests are critically low (< 100).
  bool get isCritical => remaining < 100;

  /// Whether the rate limit has been exceeded.
  bool get isExceeded => remaining <= 0;

  /// Time until the rate limit window resets.
  Duration get timeUntilReset {
    final diff = resetAt.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Whether the rate limit window has reset.
  bool get hasReset => DateTime.now().isAfter(resetAt);

  @override
  String toString() {
    return 'RateLimit(used=$used/$limit, remaining=$remaining, '
        'resets in ${timeUntilReset.inMinutes}m)';
  }
}

// =============================================================================
// MAIN CACHE SERVICE
// =============================================================================

/// Two-level caching service for GitHub API responses.
///
/// Provides efficient caching with:
/// - **L1 Cache**: In-memory (fastest, cleared on app restart)
/// - **L2 Cache**: Persistent Hive storage (survives app restarts)
///
/// ## Cache Strategies per Endpoint
///
/// | Endpoint Pattern | TTL |
/// |------------------|-----|
/// | `/user/repos` | 5 minutes |
/// | `/repos/{owner}/{repo}` | 10 minutes |
/// | `/repos/{owner}/{repo}/contents` | 2 minutes |
/// | `/repos/{owner}/{repo}/issues` | 1 minute |
/// | `/repos/{owner}/{repo}/pulls` | 1 minute |
/// | `/notifications` | 30 seconds |
/// | `/search/*` | 10 minutes |
///
/// ## Usage
/// ```dart
/// final cache = GitHubCacheService();
/// await cache.initialize();
///
/// // Read from cache
/// final cached = cache.get('/user/repos');
/// if (cached != null) return cached;
///
/// // Fetch from API and store
/// final data = await api.get('/user/repos');
/// cache.set('/user/repos', data);
/// ```
class GitHubCacheService {
  // ---------------------------------------------------------------------------
  // CACHE DURATIONS PER ENDPOINT PATTERN
  // ---------------------------------------------------------------------------

  /// TTL rules mapped to endpoint path patterns.
  ///
  /// These are checked in order; the first matching pattern wins.
  static final Map<RegExp, Duration> _cacheDurations = {
    // User repos list
    RegExp(r'^/user/repos'): const Duration(minutes: 5),
    // Notifications (very short - they change frequently)
    RegExp(r'^/notifications'): const Duration(seconds: 30),
    // Search results
    RegExp(r'^/search/'): const Duration(minutes: 10),
    // Repo contents (can change frequently)
    RegExp(r'^/repos/[^/]+/[^/]+/contents'): const Duration(minutes: 2),
    // Issues (frequently changing)
    RegExp(r'^/repos/[^/]+/[^/]+/issues'): const Duration(minutes: 1),
    // Pull requests (frequently changing)
    RegExp(r'^/repos/[^/]+/[^/]+/pulls'): const Duration(minutes: 1),
    // Branches list
    RegExp(r'^/repos/[^/]+/[^/]+/branches'): const Duration(minutes: 3),
    // Commits list
    RegExp(r'^/repos/[^/]+/[^/]+/commits'): const Duration(minutes: 2),
    // Single repo details (stable)
    RegExp(r'^/repos/[^/]+/[^/]+$'): const Duration(minutes: 10),
    // Single repo details with trailing segment
    RegExp(r'^/repos/[^/]+/[^/]+/'): const Duration(minutes: 5),
    // User profile
    RegExp(r'^/user$'): const Duration(minutes: 10),
    // Other users
    RegExp(r'^/users/'): const Duration(minutes: 15),
  };

  // ---------------------------------------------------------------------------
  // INTERNAL STATE
  // ---------------------------------------------------------------------------

  /// L1: In-memory cache map (key -> entry).
  final Map<String, _CacheEntry> _memoryCache = {};

  /// L2: Persistent cache box name.
  static const String _persistentBoxName = 'github_api_cache';

  /// Hive box for persistent cache.
  Box<String>? _persistentBox;

  /// Whether the service has been initialized.
  bool _initialized = false;

  /// Internal hit counter.
  int _hitCount = 0;

  /// Internal miss counter.
  int _missCount = 0;

  /// Internal write counter.
  int _writeCount = 0;

  /// Internal invalidation counter.
  int _invalidateCount = 0;

  /// Background cleanup timer.
  Timer? _cleanupTimer;

  /// Stats reset timestamp.
  DateTime _statsResetAt = DateTime.now();

  // ---------------------------------------------------------------------------
  // SINGLETON
  // ---------------------------------------------------------------------------

  static final GitHubCacheService _instance = GitHubCacheService._internal();
  factory GitHubCacheService() => _instance;
  GitHubCacheService._internal();

  // ---------------------------------------------------------------------------
  // INITIALIZATION
  // ---------------------------------------------------------------------------

  /// Initialize the cache service.
  ///
  /// Opens the persistent cache box and starts background cleanup.
  /// Safe to call multiple times.
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Open persistent cache box
      if (!Hive.isBoxOpen(_persistentBoxName)) {
        final dir = await getApplicationDocumentsDirectory();
        final cacheDir = '${dir.path}/mobile_agent/cache';
        await Directory(cacheDir).create(recursive: true);
        Hive.init(cacheDir);
      }

      _persistentBox = await Hive.openBox<String>(_persistentBoxName);

      // Hydrate L1 cache from persistent storage (last 50 entries)
      await _hydrateFromPersistent();

      // Start background cleanup every 2 minutes
      _cleanupTimer = Timer.periodic(
        const Duration(minutes: 2),
        (_) => _cleanupExpired(),
      );

      _initialized = true;
      debugPrint(
        '[GitHubCacheService] Initialized: '
        'L1=${_memoryCache.length}, L2=${_persistentBox?.length ?? 0}',
      );
    } catch (e) {
      debugPrint('[GitHubCacheService] Failed to initialize: $e');
      // Fall back to memory-only caching
      _initialized = true;
    }
  }

  /// Hydrate L1 cache from the most recently used persistent entries.
  Future<void> _hydrateFromPersistent() async {
    if (_persistentBox == null || _persistentBox!.isEmpty) return;

    try {
      final entries = _persistentBox!.values.toList();
      // Take last 50 entries (most recently added)
      final recentEntries = entries.length > 50
          ? entries.sublist(entries.length - 50)
          : entries;

      for (final jsonStr in recentEntries) {
        try {
          final map = jsonDecode(jsonStr) as Map<String, dynamic>;
          final entry = _CacheEntry.fromPersistMap(map);

          // Only hydrate if not expired
          if (!entry.isExpired(_cacheDurations)) {
            _memoryCache[entry.key] = entry;
          }
        } catch (_) {
          // Skip corrupted entries
        }
      }

      debugPrint(
        '[GitHubCacheService] Hydrated ${_memoryCache.length} entries '
        'from persistent cache',
      );
    } catch (e) {
      debugPrint('[GitHubCacheService] Hydration error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // CORE OPERATIONS
  // ---------------------------------------------------------------------------

  /// Get a cached response by key.
  ///
  /// Checks L1 (memory) first, then L2 (persistent).
  /// Returns null if no valid cached entry is found.
  ///
  /// [key] should be the full endpoint path including query parameters.
  dynamic get(String key) {
    _ensureInitialized();

    // Check L1 cache first
    final memoryEntry = _memoryCache[key];
    if (memoryEntry != null) {
      if (!memoryEntry.isExpired(_cacheDurations)) {
        memoryEntry.accessCount++;
        _hitCount++;
        debugPrint('[GitHubCacheService] L1 HIT: $key');
        return memoryEntry.value;
      } else {
        // Expired - remove from L1
        _memoryCache.remove(key);
      }
    }

    // Check L2 cache
    if (_persistentBox != null) {
      try {
        final jsonStr = _persistentBox!.get(key);
        if (jsonStr != null) {
          final map = jsonDecode(jsonStr) as Map<String, dynamic>;
          final entry = _CacheEntry.fromPersistMap(map);

          if (!entry.isExpired(_cacheDurations)) {
            // Promote to L1
            _memoryCache[key] = entry;
            entry.accessCount++;
            _hitCount++;
            debugPrint('[GitHubCacheService] L2 HIT -> L1: $key');
            return entry.value;
          } else {
            // Expired - remove from L2
            _persistentBox!.delete(key);
          }
        }
      } catch (e) {
        debugPrint('[GitHubCacheService] L2 read error: $e');
      }
    }

    _missCount++;
    debugPrint('[GitHubCacheService] MISS: $key');
    return null;
  }

  /// Store a response in the cache.
  ///
  /// Writes to both L1 (memory) and L2 (persistent) caches.
  ///
  /// [key] should be the full endpoint path.
  /// [value] is the JSON-decoded response data.
  /// [ttl] optionally overrides the default TTL for this endpoint.
  void set(
    String key,
    dynamic value, {
    Duration? ttl,
  }) {
    _ensureInitialized();

    if (value == null) return;

    // Extract endpoint path (without query params) for TTL lookup
    final endpoint = _extractEndpoint(key);

    final entry = _CacheEntry(
      value: value,
      key: key,
      endpoint: endpoint,
      customTtl: ttl,
    );

    // Write to L1
    _memoryCache[key] = entry;

    // Write to L2 (persistent)
    if (_persistentBox != null) {
      try {
        final jsonStr = jsonEncode(entry.toPersistMap());
        _persistentBox!.put(key, jsonStr);
      } catch (e) {
        debugPrint('[GitHubCacheService] L2 write error: $e');
      }
    }

    _writeCount++;
  }

  /// Check if a cached entry is still valid (not expired).
  ///
  /// Returns true only if the entry exists in either cache layer
  /// and has not exceeded its TTL.
  bool isValid(String key) {
    _ensureInitialized();

    final memoryEntry = _memoryCache[key];
    if (memoryEntry != null) {
      return !memoryEntry.isExpired(_cacheDurations);
    }

    if (_persistentBox != null) {
      try {
        final jsonStr = _persistentBox!.get(key);
        if (jsonStr != null) {
          final map = jsonDecode(jsonStr) as Map<String, dynamic>;
          final entry = _CacheEntry.fromPersistMap(map);
          return !entry.isExpired(_cacheDurations);
        }
      } catch (_) {
        return false;
      }
    }

    return false;
  }

  // ---------------------------------------------------------------------------
  // INVALIDATION
  // ---------------------------------------------------------------------------

  /// Invalidate a specific cache entry by key.
  void invalidate(String key) {
    _ensureInitialized();

    _memoryCache.remove(key);
    _persistentBox?.delete(key);
    _invalidateCount++;

    debugPrint('[GitHubCacheService] Invalidated: $key');
  }

  /// Invalidate all cache entries matching a regex pattern.
  ///
  /// This is useful for bulk invalidation, e.g., when you know
  /// that all data for a specific repository is now stale.
  ///
  /// ```dart
  /// // Invalidate all cache for repository 'my-org/my-app'
  /// cache.invalidatePattern(RegExp(r'/repos/my-org/my-app'));
  /// ```
  int invalidatePattern(RegExp pattern) {
    _ensureInitialized();

    var count = 0;

    // Invalidate L1 entries
    final l1KeysToRemove = _memoryCache.keys
        .where((key) => pattern.hasMatch(key))
        .toList();
    for (final key in l1KeysToRemove) {
      _memoryCache.remove(key);
      count++;
    }

    // Invalidate L2 entries
    if (_persistentBox != null) {
      final l2KeysToRemove = _persistentBox!.keys
          .where((key) => pattern.hasMatch(key as String))
          .toList();
      for (final key in l2KeysToRemove) {
        _persistentBox!.delete(key);
        count++;
      }
    }

    _invalidateCount += count;
    debugPrint('[GitHubCacheService] Invalidated $count entries for pattern: $pattern');
    return count;
  }

  /// Invalidate all cache entries for a specific repository.
  ///
  /// This removes all cached data related to the given owner/repo,
  /// including repo details, contents, issues, PRs, branches, etc.
  ///
  /// ```dart
  /// cache.invalidateRepo('flutter', 'flutter');
  /// ```
  int invalidateRepo(String owner, String repo) {
    return invalidatePattern(
      RegExp(r'/repos/' + RegExp.escape(owner) + r'/' + RegExp.escape(repo)),
    );
  }

  /// Invalidate all user-related cache entries.
  ///
  /// Call this when the authenticated user changes.
  int invalidateUserCache() {
    return invalidatePattern(RegExp(r'^/user'));
  }

  /// Invalidate all search cache entries.
  ///
  /// Call this when you want fresh search results.
  int invalidateSearchCache() {
    return invalidatePattern(RegExp(r'^/search/'));
  }

  // ---------------------------------------------------------------------------
  // BULK OPERATIONS
  // ---------------------------------------------------------------------------

  /// Clear all cache entries from both L1 and L2.
  void clear() {
    _ensureInitialized();

    _memoryCache.clear();
    _persistentBox?.clear();
    _invalidateCount++;

    debugPrint('[GitHubCacheService] All cache cleared');
  }

  /// Clear only the L1 (in-memory) cache.
  ///
  /// L2 (persistent) cache remains intact and will be used
  /// to re-hydrate L1 on next access.
  void clearMemoryCache() {
    _memoryCache.clear();
    debugPrint('[GitHubCacheService] L1 (memory) cache cleared');
  }

  /// Remove expired entries from both cache layers.
  ///
  /// Called automatically by a background timer every 2 minutes.
  void cleanupExpired() => _cleanupExpired();

  void _cleanupExpired() {
    _ensureInitialized();

    var l1Removed = 0;
    var l2Removed = 0;

    // Clean L1
    final expiredL1 = _memoryCache.entries
        .where((e) => e.value.isExpired(_cacheDurations))
        .map((e) => e.key)
        .toList();
    for (final key in expiredL1) {
      _memoryCache.remove(key);
      l1Removed++;
    }

    // Clean L2
    if (_persistentBox != null) {
      final expiredL2 = _persistentBox!.keys.where((key) {
        try {
          final jsonStr = _persistentBox!.get(key);
          if (jsonStr == null) return true;
          final map = jsonDecode(jsonStr) as Map<String, dynamic>;
          final entry = _CacheEntry.fromPersistMap(map);
          return entry.isExpired(_cacheDurations);
        } catch (_) {
          return true;
        }
      }).toList();

      for (final key in expiredL2) {
        _persistentBox!.delete(key);
        l2Removed++;
      }
    }

    if (l1Removed > 0 || l2Removed > 0) {
      debugPrint(
        '[GitHubCacheService] Cleanup: removed $l1Removed L1, $l2Removed L2 entries',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // STATISTICS
  // ---------------------------------------------------------------------------

  /// Get current cache statistics.
  CacheStats getStats() {
    return CacheStats(
      memoryEntries: _memoryCache.length,
      persistentEntries: _persistentBox?.length ?? 0,
      hits: _hitCount,
      misses: _missCount,
      writes: _writeCount,
      invalidations: _invalidateCount,
      lastReset: _statsResetAt,
    );
  }

  /// Reset hit/miss counters.
  void resetCounters() {
    _hitCount = 0;
    _missCount = 0;
    _writeCount = 0;
    _invalidateCount = 0;
    _statsResetAt = DateTime.now();
  }

  // ---------------------------------------------------------------------------
  // INFO / DEBUG
  // ---------------------------------------------------------------------------

  /// Get a list of all cached keys in L1.
  List<String> get memoryKeys => _memoryCache.keys.toList();

  /// Get a list of all cached keys in L2.
  List<String> get persistentKeys {
    if (_persistentBox == null) return [];
    return _persistentBox!.keys.map((k) => k.toString()).toList();
  }

  /// Get the current size of L1 cache.
  int get memoryEntryCount => _memoryCache.length;

  /// Get the current size of L2 cache.
  int get persistentEntryCount => _persistentBox?.length ?? 0;

  /// Print debug info about cache contents.
  void printDebugInfo() {
    debugPrint('=== GitHubCacheService Debug ===');
    debugPrint('L1 (Memory): ${_memoryCache.length} entries');
    debugPrint('L2 (Persistent): ${_persistentBox?.length ?? 0} entries');
    debugPrint('Stats: ${getStats()}');

    if (_memoryCache.isNotEmpty) {
      debugPrint('L1 Keys:');
      for (final key in _memoryCache.keys.take(20)) {
        final entry = _memoryCache[key]!;
        final age = DateTime.now().difference(entry.cachedAt);
        debugPrint('  $key (age: ${age.inSeconds}s, accesses: ${entry.accessCount})');
      }
    }
    debugPrint('================================');
  }

  // ---------------------------------------------------------------------------
  // LIFECYCLE
  // ---------------------------------------------------------------------------

  /// Dispose the cache service.
  ///
  /// Cancels the cleanup timer. Persistent data is preserved.
  Future<void> dispose() async {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _memoryCache.clear();
    await _persistentBox?.close();
    _persistentBox = null;
    _initialized = false;
    debugPrint('[GitHubCacheService] Disposed');
  }

  // ---------------------------------------------------------------------------
  // PRIVATE HELPERS
  // ---------------------------------------------------------------------------

  /// Extract the endpoint path from a potentially query-parameterized key.
  String _extractEndpoint(String key) {
    // Remove query parameters for endpoint extraction
    final queryIdx = key.indexOf('?');
    if (queryIdx >= 0) {
      return key.substring(0, queryIdx);
    }
    return key;
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw const GitHubCacheException(
        message: 'GitHubCacheService not initialized. Call initialize() first.',
        operation: '_ensureInitialized',
      );
    }
  }
}
