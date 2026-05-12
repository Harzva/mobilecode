// lib/core/memory_manager.dart
// Memory Management System for Mobile Agent
//
// Monitors and optimizes app memory usage:
// - Real-time memory tracking with estimated heuristics
// - Automatic cache eviction under memory pressure
// - Object pooling for frequently created objects (StringBuffer, List, Map)
// - Image cache size limits with Flutter's PaintingBinding
// - String buffer pooling for repeated string operations
// - Widget caching with WeakReference to avoid leaks
// - Timely disposal of unused resources on app lifecycle changes
// - Periodic memory pressure monitoring

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// Memory Manager — Singleton
// ---------------------------------------------------------------------------

/// Central memory management coordinator for the Mobile Agent app.
///
/// Tracks memory usage through estimation heuristics, manages object pools,
/// controls image cache size, caches widgets weakly, and responds to memory
/// pressure by evicting caches and suggesting garbage collection.
///
/// ## Usage
///
/// ```dart
/// // Access singleton
/// final mm = MemoryManager();
///
/// // Check memory status
/// if (mm.isUnderPressure) { mm.handleMemoryPressure(); }
///
/// // Use pooled string builder
/// final sb = PooledStringBuilder();
/// sb.write('content');
/// final result = sb.toString();
/// sb.release(); // MUST release back to pool
///
/// // Track image loads
/// mm.onImageLoaded(imageBytes);
///
/// // Cache widgets weakly
/// mm.cacheWidget('my_key', myWidget);
/// final cached = mm.getCachedWidget('my_key');
/// ```
class MemoryManager {
  static final MemoryManager _instance = MemoryManager._internal();
  factory MemoryManager() => _instance;
  MemoryManager._internal() {
    _startPressureMonitor();
  }

  // -- Configuration Constants --

  /// Maximum target memory usage in MB.
  static const int _maxMemoryMB = 200;

  /// Memory threshold at which pressure handling kicks in (80%).
  static const double _pressureThreshold = 0.80;

  /// Memory threshold considered critical (95%).
  static const double _criticalThreshold = 0.95;

  /// Maximum image cache size in MB.
  static const int _imageCacheMB = 50;

  /// Maximum number of widgets cached via WeakReference.
  static const int _widgetCacheSize = 100;

  /// Maximum string buffers to keep in the pool.
  static const int _stringPoolSize = 500;

  /// Maximum pooled lists per type.
  static const int _listPoolMaxPerType = 50;

  /// Maximum pooled maps per type.
  static const int _mapPoolMaxPerType = 30;

  /// Interval between memory pressure checks.
  static const Duration _monitorInterval = Duration(seconds: 30);

  /// Estimated memory per cached widget in MB (~100KB).
  static const double _widgetMemoryMB = 0.1;

  /// Estimated memory per pooled string in MB (~10KB).
  static const double _stringMemoryMB = 0.01;

  // -- Memory Tracking State --

  int _imageCacheSize = 0;
  int _manualWidgetCacheCount = 0;
  final Set<String> _loadedImageKeys = <String>{};

  /// Total bytes allocated through this manager's tracking.
  int _totalTrackedBytes = 0;

  /// Cumulative eviction count (for reporting).
  int _evictionCount = 0;

  /// Timestamp of last pressure handling.
  DateTime? _lastPressureHandle;

  /// Whether the pressure monitor timer is active.
  bool _monitorActive = false;

  Timer? _pressureTimer;

  // -- Pressure Monitoring --

  void _startPressureMonitor() {
    if (_monitorActive) return;
    _monitorActive = true;

    _pressureTimer = Timer.periodic(_monitorInterval, (_) {
      _checkMemoryPressure();
    });
  }

  void _checkMemoryPressure() {
    if (isCritical) {
      debugPrint('[MemoryManager] CRITICAL memory pressure detected: ${currentMemoryMB}MB');
      handleMemoryPressure();
    } else if (isUnderPressure) {
      debugPrint('[MemoryManager] Memory pressure detected: ${currentMemoryMB}MB');
      _softEviction();
    }
  }

  // -- Public Memory Metrics --

  /// Current estimated memory usage in MB.
  int get currentMemoryMB => _estimateMemoryUsage();

  /// Maximum allowed memory in MB.
  int get maxMemoryMB => _maxMemoryMB;

  /// Whether memory is under pressure (> 80% of max).
  bool get isUnderPressure => currentMemoryMB > (_maxMemoryMB * _pressureThreshold).toInt();

  /// Whether memory is in a critical state (> 95% of max).
  bool get isCritical => currentMemoryMB > (_maxMemoryMB * _criticalThreshold).toInt();

  /// The current memory pressure level.
  MemoryPressureLevel get pressureLevel {
    final usage = currentMemoryMB;
    final critical = (_maxMemoryMB * _criticalThreshold).toInt();
    final pressure = (_maxMemoryMB * _pressureThreshold).toInt();

    if (usage > critical) return MemoryPressureLevel.critical;
    if (usage > pressure) return MemoryPressureLevel.pressure;
    return MemoryPressureLevel.normal;
  }

  /// Number of times evictions have been performed.
  int get evictionCount => _evictionCount;

  /// Estimate current memory usage from tracked components.
  int _estimateMemoryUsage() {
    double total = 0.0;

    // Image cache contribution.
    total += _imageCacheSize;

    // Widget cache contribution (live references only).
    total += _liveWidgetCount * _widgetMemoryMB;

    // String pool contribution.
    total += _stringPool.length * _stringMemoryMB;

    // List pool estimate.
    for (final entry in _listPool.entries) {
      total += entry.value.length * 0.005; // ~5KB per list.
    }

    // Map pool estimate.
    for (final entry in _mapPool.entries) {
      total += entry.value.length * 0.008; // ~8KB per map.
    }

    // Pooled string builders.
    total += _activeStringBuilders * 0.02;

    return total.ceil();
  }

  // -- Object Pool: StringBuffer --

  final List<StringBuffer> _stringPool = [];
  int _activeStringBuilders = 0;

  /// Acquire a [StringBuffer] from the pool, or create a new one.
  ///
  /// The returned buffer is cleared and ready for use.
  /// **Must** call [releaseStringBuffer] when done.
  StringBuffer acquireStringBuffer() {
    if (_stringPool.isNotEmpty) {
      final buffer = _stringPool.removeLast()..clear();
      _activeStringBuilders++;
      return buffer;
    }
    _activeStringBuilders++;
    return StringBuffer();
  }

  /// Release a [StringBuffer] back to the pool for reuse.
  ///
  /// Silently drops the buffer if the pool is at capacity.
  void releaseStringBuffer(StringBuffer buffer) {
    _activeStringBuilders = math.max(0, _activeStringBuilders - 1);
    if (_stringPool.length < _stringPoolSize) {
      buffer.clear();
      _stringPool.add(buffer);
    }
  }

  // -- Object Pool: List --

  final Map<Type, List<List<Object?>>> _listPool = {};

  /// Acquire a [List<T>] from the pool, or create a new one.
  ///
  /// The returned list is cleared and ready for use.
  /// **Must** call [releaseList] when done.
  List<T> acquireList<T>() {
    final lists = _listPool[T];
    if (lists != null && lists.isNotEmpty) {
      final list = lists.removeLast();
      list.clear();
      return list.cast<T>();
    }
    return <T>[];
  }

  /// Release a [List<T>] back to the pool for reuse.
  ///
  /// Silently drops the list if the type pool is at capacity.
  void releaseList<T>(List<T> list) {
    _listPool.putIfAbsent(T, () => []);
    if (_listPool[T]!.length < _listPoolMaxPerType) {
      list.clear();
      _listPool[T]!.add(list.cast<Object?>());
    }
  }

  // -- Object Pool: Map --

  final Map<Type, List<Map<Object?, Object?>>> _mapPool = {};

  /// Acquire a [Map<K, V>] from the pool, or create a new one.
  ///
  /// The returned map is cleared and ready for use.
  /// **Must** call [releaseMap] when done.
  Map<K, V> acquireMap<K, V>() {
    final maps = _mapPool[Map<K, V>];
    if (maps != null && maps.isNotEmpty) {
      final map = maps.removeLast();
      map.clear();
      return map.cast<K, V>();
    }
    return <K, V>{};
  }

  /// Release a [Map<K, V>] back to the pool for reuse.
  ///
  /// Silently drops the map if the type pool is at capacity.
  void releaseMap<K, V>(Map<K, V> map) {
    _mapPool.putIfAbsent(Map<K, V>, () => []);
    if (_mapPool[Map<K, V>]!.length < _mapPoolMaxPerType) {
      map.clear();
      _mapPool[Map<K, V>]!.add(map.cast<Object?, Object?>());
    }
  }

  // -- Image Cache Control --

  /// Call this when an image is loaded to track its memory impact.
  ///
  /// [bytes] is the decoded image size in bytes.
  /// [key] is an optional unique identifier for the image.
  void onImageLoaded(int bytes, {String? key}) {
    final mb = bytes ~/ (1024 * 1024);
    _imageCacheSize += mb;
    _totalTrackedBytes += bytes;

    if (key != null) {
      _loadedImageKeys.add(key);
    }

    if (_imageCacheSize > _imageCacheMB) {
      _evictImageCache();
    }
  }

  /// Call this when an image is explicitly disposed.
  ///
  /// [bytes] is the decoded image size in bytes.
  void onImageDisposed(int bytes, {String? key}) {
    final mb = bytes ~/ (1024 * 1024);
    _imageCacheSize = math.max(0, _imageCacheSize - mb);
    _totalTrackedBytes = math.max(0, _totalTrackedBytes - bytes);

    if (key != null) {
      _loadedImageKeys.remove(key);
    }
  }

  /// Evict oldest entries from the image cache.
  ///
  /// Clears Flutter's internal image cache and resets our tracking.
  void _evictImageCache() {
    debugPrint('[MemoryManager] Evicting image cache ($_imageCacheSize MB)');
    PaintingBinding.instance.imageCache.clear();
    _imageCacheSize = 0;
    _loadedImageKeys.clear();
    _evictionCount++;
  }

  /// Set a live maximum on Flutter's image cache.
  ///
  /// Call once during app initialization.
  void configureImageCache() {
    PaintingBinding.instance.imageCache.maximumSizeBytes =
        _imageCacheMB * 1024 * 1024;
    debugPrint('[MemoryManager] Image cache limited to $_imageCacheMB MB');
  }

  // -- Widget Cache (WeakReference) --

  final Map<String, WeakReference<Widget>> _widgetCache = {};

  /// Cache a widget using a weak reference.
  ///
  /// The widget can be garbage collected when no other references exist.
  /// Useful for expensive-to-build widgets that may be shown again.
  void cacheWidget(String key, Widget widget) {
    // Clean dead references if we're at capacity.
    if (_widgetCache.length >= _widgetCacheSize) {
      _pruneDeadWidgets();
    }

    // If still at capacity after pruning, remove oldest entries.
    if (_widgetCache.length >= _widgetCacheSize) {
      final toRemove = _widgetCache.keys.take(_widgetCacheSize ~/ 4).toList();
      for (final k in toRemove) {
        _widgetCache.remove(k);
      }
    }

    _widgetCache[key] = WeakReference(widget);
    _manualWidgetCacheCount++;
  }

  /// Retrieve a cached widget if it is still alive.
  Widget? getCachedWidget(String key) {
    return _widgetCache[key]?.target;
  }

  /// Remove a specific widget from the cache.
  void removeCachedWidget(String key) {
    _widgetCache.remove(key);
  }

  /// Number of live (non-garbage-collected) cached widgets.
  int get _liveWidgetCount {
    return _widgetCache.values.where((ref) => ref.target != null).length;
  }

  /// Remove dead weak references from the widget cache.
  void _pruneDeadWidgets() {
    _widgetCache.removeWhere((_, ref) => ref.target == null);
  }

  // -- Soft Eviction (lighter than full pressure handling) --

  /// Perform soft eviction: clear image cache and prune dead widgets.
  ///
  /// This is called when memory is elevated but not yet critical.
  void _softEviction() {
    debugPrint('[MemoryManager] Soft eviction triggered');
    _evictImageCache();
    _pruneDeadWidgets();
  }

  // -- Resource Disposal --

  /// Handle memory pressure by aggressively evicting caches.
  ///
  /// Call this when [isUnderPressure] or [isCritical] is true.
  /// Safe to call multiple times — includes rate limiting.
  Future<void> handleMemoryPressure() async {
    if (!isUnderPressure) return;

    // Rate limit: don't handle more than once per 10 seconds.
    final now = DateTime.now();
    if (_lastPressureHandle != null &&
        now.difference(_lastPressureHandle!) < const Duration(seconds: 10)) {
      return;
    }
    _lastPressureHandle = now;

    debugPrint('[MemoryManager] Handling memory pressure at ${currentMemoryMB}MB');

    // Evict image cache.
    _evictImageCache();

    // Clear widget cache entirely.
    _widgetCache.clear();
    _manualWidgetCacheCount = 0;

    // Trim string pool to half capacity.
    if (_stringPool.length > _stringPoolSize ~/ 2) {
      _stringPool.removeRange(0, _stringPool.length ~/ 2);
    }

    // Trim list pools.
    for (final entry in _listPool.entries) {
      final target = _listPoolMaxPerType ~/ 2;
      if (entry.value.length > target) {
        entry.value.removeRange(0, entry.value.length - target);
      }
    }

    // Trim map pools.
    for (final entry in _mapPool.entries) {
      final target = _mapPoolMaxPerType ~/ 2;
      if (entry.value.length > target) {
        entry.value.removeRange(0, entry.value.length - target);
      }
    }

    // Hint at GC by allocating and discarding.
    _hintGC();

    debugPrint('[MemoryManager] Pressure handled. Now at ~${currentMemoryMB}MB');
  }

  /// Hint the garbage collector to run.
  ///
  /// Dart doesn't expose GC directly, but we can create
  /// temporary pressure to encourage collection.
  void _hintGC() {
    final List<int> dummy = List.filled(10000, 0);
    dummy.clear();
  }

  /// Dispose all managed resources.
  ///
  /// Call this when the app is backgrounded or the session ends.
  Future<void> disposeAll() async {
    debugPrint('[MemoryManager] Disposing all resources');

    PaintingBinding.instance.imageCache.clear();
    _imageCacheSize = 0;
    _loadedImageKeys.clear();

    _widgetCache.clear();
    _manualWidgetCacheCount = 0;

    _stringPool.clear();
    _activeStringBuilders = 0;

    _listPool.clear();
    _mapPool.clear();

    _pressureTimer?.cancel();
    _pressureTimer = null;
    _monitorActive = false;

    _totalTrackedBytes = 0;
    _evictionCount = 0;
  }

  /// Pause the pressure monitor timer.
  ///
  /// Call when the app is backgrounded.
  void pauseMonitor() {
    _pressureTimer?.cancel();
    _monitorActive = false;
    debugPrint('[MemoryManager] Pressure monitor paused');
  }

  /// Resume the pressure monitor timer.
  ///
  /// Call when the app is foregrounded.
  void resumeMonitor() {
    if (_monitorActive) return;
    _startPressureMonitor();
    debugPrint('[MemoryManager] Pressure monitor resumed');
  }

  // -- Memory Report --

  /// Generate a snapshot memory report.
  MemoryReport generateReport() {
    return MemoryReport(
      currentMB: currentMemoryMB,
      maxMB: _maxMemoryMB,
      imageCacheMB: _imageCacheSize,
      widgetCacheCount: _widgetCache.length,
      liveWidgetCount: _liveWidgetCount,
      stringPoolCount: _stringPool.length,
      activeStringBuilders: _activeStringBuilders,
      listPoolTypes: _listPool.length,
      listPoolTotalEntries: _listPool.values.fold(0, (s, v) => s + v.length),
      mapPoolTypes: _mapPool.length,
      mapPoolTotalEntries: _mapPool.values.fold(0, (s, v) => s + v.length),
      evictionCount: _evictionCount,
      pressureLevel: pressureLevel,
      timestamp: DateTime.now(),
    );
  }
}

// ---------------------------------------------------------------------------
// Memory Pressure Level
// ---------------------------------------------------------------------------

/// Memory pressure severity levels.
enum MemoryPressureLevel {
  /// Normal operation, no pressure.
  normal,

  /// Elevated memory usage, soft eviction recommended.
  pressure,

  /// Critical memory usage, aggressive eviction required.
  critical,
}

// ---------------------------------------------------------------------------
// Memory Report
// ---------------------------------------------------------------------------

/// A snapshot of memory usage at a point in time.
class MemoryReport {
  /// Current estimated memory in MB.
  final int currentMB;

  /// Maximum allowed memory in MB.
  final int maxMB;

  /// Current image cache size in MB.
  final int imageCacheMB;

  /// Total widget cache entries.
  final int widgetCacheCount;

  /// Live (non-GC'd) widget cache entries.
  final int liveWidgetCount;

  /// Available string buffers in pool.
  final int stringPoolCount;

  /// Currently lent-out string builders.
  final int activeStringBuilders;

  /// Number of types in the list pool.
  final int listPoolTypes;

  /// Total pooled lists across all types.
  final int listPoolTotalEntries;

  /// Number of types in the map pool.
  final int mapPoolTypes;

  /// Total pooled maps across all types.
  final int mapPoolTotalEntries;

  /// Number of evictions performed.
  final int evictionCount;

  /// Current memory pressure level.
  final MemoryPressureLevel pressureLevel;

  /// When this report was generated.
  final DateTime timestamp;

  const MemoryReport({
    required this.currentMB,
    required this.maxMB,
    required this.imageCacheMB,
    required this.widgetCacheCount,
    required this.liveWidgetCount,
    required this.stringPoolCount,
    required this.activeStringBuilders,
    required this.listPoolTypes,
    required this.listPoolTotalEntries,
    required this.mapPoolTypes,
    required this.mapPoolTotalEntries,
    required this.evictionCount,
    required this.pressureLevel,
    required this.timestamp,
  });

  /// Memory usage as a percentage of the maximum.
  double get usagePercent => maxMB > 0 ? (currentMB / maxMB * 100) : 0.0;

  /// Formatted usage string for display.
  String get formattedUsage =>
      '$currentMB / $maxMB MB (${usagePercent.toStringAsFixed(1)}%)';

  /// Whether memory is under pressure.
  bool get isUnderPressure => pressureLevel.index >= MemoryPressureLevel.pressure.index;

  /// Whether memory is critical.
  bool get isCritical => pressureLevel == MemoryPressureLevel.critical;

  @override
  String toString() {
    return 'MemoryReport{${formattedUsage}, '
        'pressure: ${pressureLevel.name}, '
        'images: ${imageCacheMB}MB, '
        'widgets: $liveWidgetCount/$widgetCacheCount, '
        'strings: $stringPoolCount, '
        'evictions: $evictionCount}';
  }
}

// ---------------------------------------------------------------------------
// PooledStringBuilder — Object Pool Pattern
// ---------------------------------------------------------------------------

/// A [StringBuffer] wrapper that automatically participates in object pooling.
///
/// Acquire from the pool on creation, and **always** call [release] when done
/// to return the underlying buffer to the pool for reuse.
///
/// ```dart
/// final builder = PooledStringBuilder();
/// builder.write('Hello');
/// builder.writeln(' World');
/// final result = builder.toString();
/// builder.release(); // Critical: returns buffer to pool
/// ```
class PooledStringBuilder {
  late StringBuffer _buffer;
  bool _released = false;

  PooledStringBuilder() : _buffer = MemoryManager().acquireStringBuffer();

  /// Whether this builder has been released back to the pool.
  bool get isReleased => _released;

  /// Write a string to the buffer.
  ///
  /// Throws [StateError] if the builder has already been released.
  void write(String s) {
    if (_released) throw StateError('PooledStringBuilder already released');
    _buffer.write(s);
  }

  /// Write a string followed by a newline.
  ///
  /// Throws [StateError] if the builder has already been released.
  void writeln(String s) {
    if (_released) throw StateError('PooledStringBuilder already released');
    _buffer.writeln(s);
  }

  /// Write multiple objects to the buffer.
  ///
  /// Throws [StateError] if the builder has already been released.
  void writeAll(Iterable<dynamic> objects, [String separator = '']) {
    if (_released) throw StateError('PooledStringBuilder already released');
    _buffer.writeAll(objects, separator);
  }

  /// Get the length of the buffer contents.
  ///
  /// Throws [StateError] if the builder has already been released.
  int get length {
    if (_released) throw StateError('PooledStringBuilder already released');
    return _buffer.length;
  }

  /// Whether the buffer is empty.
  ///
  /// Throws [StateError] if the builder has already been released.
  bool get isEmpty {
    if (_released) throw StateError('PooledStringBuilder already released');
    return _buffer.isEmpty;
  }

  /// Clear the buffer contents without releasing.
  ///
  /// Throws [StateError] if the builder has already been released.
  void clear() {
    if (_released) throw StateError('PooledStringBuilder already released');
    _buffer.clear();
  }

  /// Convert buffer contents to a string.
  ///
  /// Throws [StateError] if the builder has already been released.
  @override
  String toString() {
    if (_released) throw StateError('PooledStringBuilder already released');
    return _buffer.toString();
  }

  /// Release the underlying [StringBuffer] back to the pool.
  ///
  /// After calling this method, the builder is no longer usable.
  /// Safe to call multiple times (idempotent).
  void release() {
    if (!_released) {
      MemoryManager().releaseStringBuffer(_buffer);
      _released = true;
    }
  }
}

// ---------------------------------------------------------------------------
// PooledList — Object Pool Pattern
// ---------------------------------------------------------------------------

/// A [List<T>] wrapper that automatically participates in object pooling.
///
/// Acquire from the pool on creation, and **always** call [release] when done.
///
/// ```dart
/// final list = PooledList<String>();
/// list.add('item');
/// process(list);
/// list.release(); // Returns list to pool
/// ```
class PooledList<T> {
  late List<T> _list;
  bool _released = false;

  PooledList() : _list = MemoryManager().acquireList<T>();

  /// Whether this list has been released back to the pool.
  bool get isReleased => _released;

  /// Add an item to the list.
  void add(T item) {
    if (_released) throw StateError('PooledList already released');
    _list.add(item);
  }

  /// Add all items to the list.
  void addAll(Iterable<T> items) {
    if (_released) throw StateError('PooledList already released');
    _list.addAll(items);
  }

  /// Number of elements in the list.
  int get length {
    if (_released) throw StateError('PooledList already released');
    return _list.length;
  }

  /// Whether the list is empty.
  bool get isEmpty {
    if (_released) throw StateError('PooledList already released');
    return _list.isEmpty;
  }

  /// Access elements by index.
  T operator [](int index) {
    if (_released) throw StateError('PooledList already released');
    return _list[index];
  }

  /// Set elements by index.
  void operator []=(int index, T value) {
    if (_released) throw StateError('PooledList already released');
    _list[index] = value;
  }

  /// Iterate over the list.
  Iterable<T> get items {
    if (_released) throw StateError('PooledList already released');
    return _list;
  }

  /// Convert to a plain List (safe to use after release).
  List<T> toList() {
    if (_released) throw StateError('PooledList already released');
    return List<T>.from(_list);
  }

  /// Clear the list contents without releasing.
  void clear() {
    if (_released) throw StateError('PooledList already released');
    _list.clear();
  }

  /// Release the underlying list back to the pool.
  ///
  /// Safe to call multiple times (idempotent).
  void release() {
    if (!_released) {
      MemoryManager().releaseList<T>(_list);
      _released = true;
    }
  }
}

// ---------------------------------------------------------------------------
// Memory-Aware Provider Observer
// ---------------------------------------------------------------------------

/// A [ProviderObserver] that monitors provider lifecycle for memory awareness.
///
/// Logs provider creation/disposal in debug mode and can trigger
/// memory pressure handling when too many providers are active.
class MemoryAwareProviderObserver extends ProviderObserver {
  int _activeProviderCount = 0;
  final Set<ProviderBase<dynamic>> _activeProviders = {};

  /// Number of currently active (non-disposed) providers.
  int get activeProviderCount => _activeProviderCount;

  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    _activeProviders.add(provider);
    _activeProviderCount++;

    if (kDebugMode && _activeProviderCount % 100 == 0) {
      debugPrint(
          '[MemoryAwareProviderObserver] Active providers: $_activeProviderCount');
    }
  }

  @override
  void didDisposeProvider(
    ProviderBase<Object?> provider,
    ProviderContainer container,
  ) {
    if (_activeProviders.remove(provider)) {
      _activeProviderCount = math.max(0, _activeProviderCount - 1);
    }
  }

  @override
  void providerDidFail(
    ProviderBase<Object?> provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    debugPrint('[MemoryAwareProviderObserver] Provider failed: ${provider.name ?? provider.runtimeType}');
  }
}
