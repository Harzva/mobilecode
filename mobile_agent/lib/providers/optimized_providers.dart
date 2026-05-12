// lib/providers/optimized_providers.dart
// Optimized Riverpod Providers for Minimal Rebuilds
//
// This file provides Riverpod providers optimized for memory efficiency
// and minimal widget rebuilds. Key strategies:
//
// - select() for precise, field-level subscriptions
// - family providers for parameterized, scoped data
// - autoDispose for automatic memory cleanup
// - Debounced notifiers for high-frequency updates
// - Cached computation providers for expensive operations
// - Batch update notifiers for atomic multi-field changes
//
// Usage pattern: prefer select() over full state watches.
//
// BAD:  Rebuilds when ANY field changes
//       final user = ref.watch(userProvider);
//       return Text(user.name);
//
// GOOD: Only rebuilds when name changes
//       final name = ref.watch(userProvider.select((u) => u.name));
//       return Text(name);

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/memory_manager.dart';

// ---------------------------------------------------------------------------
// Extension: ProviderRef.cacheFor
// ---------------------------------------------------------------------------

extension ProviderRefX on Ref {
  /// Keep a provider alive for [duration] after the last listener is removed.
  ///
  /// Commonly used with autoDispose providers to prevent premature disposal
  /// during temporary listener drops (e.g., page transitions).
  ///
  /// ```dart
  /// final myProvider = FutureProvider.autoDispose((ref) async {
  ///   ref.cacheFor(const Duration(minutes: 2));
  ///   return await fetchData();
  /// });
  /// ```
  KeepAliveLink cacheFor(Duration duration) {
    final link = keepAlive();
    final timer = Timer(duration, link.close);
    onDispose(timer.cancel);
    return link;
  }

  /// Keep a provider alive while any of the given [links] are active.
  ///
  /// Combines multiple keep-alive links into a single managed lifecycle.
  void keepAliveWhile(List<KeepAliveLink> links) {
    onDispose(() {
      for (final link in links) {
        link.close();
      }
    });
  }
}

// ---------------------------------------------------------------------------
// Extension: AutoDispose Ref Cache
// ---------------------------------------------------------------------------

extension AutoDisposeRefCache on AutoDisposeRef {
  /// Cache provider result for a duration, refreshing on timer.
  ///
  /// The provider stays alive for [cacheDuration] and is automatically
  /// refreshed every [refreshInterval] if still active.
  void cacheWithRefresh({
    required Duration cacheDuration,
    Duration? refreshInterval,
  }) {
    final link = cacheFor(cacheDuration);

    if (refreshInterval != null) {
      final timer = Timer.periodic(refreshInterval, (_) {
        invalidateSelf();
      });
      onDispose(timer.cancel);
    }

    onDispose(link.close);
  }
}

// ---------------------------------------------------------------------------
// DebouncedSearchNotifier — High-Frequency Input Handling
// ---------------------------------------------------------------------------

/// Search state container.
///
/// Immutable value object used by [DebouncedSearchNotifier].
@immutable
class SearchState {
  /// Search result strings.
  final List<String> results;

  /// Whether a search is in progress.
  final bool isLoading;

  /// The query that produced these results (empty if none).
  final String query;

  /// Error message, if any.
  final String? error;

  const SearchState({
    this.results = const [],
    this.isLoading = false,
    this.query = '',
    this.error,
  });

  /// Empty state factory.
  factory SearchState.empty() => const SearchState();

  /// Loading state for a given query.
  factory SearchState.loading(String query) =>
      SearchState(query: query, isLoading: true);

  /// Create a modified copy.
  SearchState copyWith({
    List<String>? results,
    bool? isLoading,
    String? query,
    String? error,
    bool clearError = false,
  }) {
    return SearchState(
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      query: query ?? this.query,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchState &&
          runtimeType == other.runtimeType &&
          listEquals(results, other.results) &&
          isLoading == other.isLoading &&
          query == other.query &&
          error == other.error;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(results),
        isLoading,
        query,
        error,
      );
}

/// A [StateNotifier] that debounces search queries.
///
/// Prevents excessive search API calls by waiting for the user to
/// pause typing before executing the search.
///
/// ```dart
/// final search = ref.read(debouncedSearchProvider.notifier);
/// search.search('flutter widgets');
///
/// final state = ref.watch(debouncedSearchProvider);
/// if (state.isLoading) { showSpinner(); }
/// ```
class DebouncedSearchNotifier extends StateNotifier<SearchState> {
  Timer? _debounceTimer;

  /// The debounce delay. Default is 300ms.
  final Duration debounceDelay;

  DebouncedSearchNotifier({this.debounceDelay = const Duration(milliseconds: 300)})
      : super(SearchState.empty());

  /// Initiate a debounced search.
  ///
  /// Cancels any pending search and starts a new timer.
  void search(String query) {
    _debounceTimer?.cancel();

    if (query.isEmpty) {
      state = SearchState.empty();
      return;
    }

    if (state.query != query) {
      state = SearchState.loading(query);
    }

    _debounceTimer = Timer(debounceDelay, () async {
      try {
        final results = await SearchService().search(query);
        if (mounted) {
          state = SearchState(
            results: results,
            isLoading: false,
            query: query,
          );
        }
      } catch (e) {
        if (mounted) {
          state = state.copyWith(
            isLoading: false,
            error: 'Search failed: $e',
          );
        }
      }
    });
  }

  /// Clear search results and cancel any pending query.
  void clear() {
    _debounceTimer?.cancel();
    state = SearchState.empty();
  }

  /// Cancel pending search without clearing results.
  void cancelPending() {
    _debounceTimer?.cancel();
    if (state.isLoading) {
      state = state.copyWith(isLoading: false);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}

/// Provider for debounced search state.
///
/// Use with the [DebouncedSearchNotifier] for high-frequency search inputs.
final debouncedSearchProvider =
    StateNotifierProvider<DebouncedSearchNotifier, SearchState>(
  (ref) => DebouncedSearchNotifier(),
);

// ---------------------------------------------------------------------------
// BatchedStateNotifier — Atomic Multi-Field Updates
// ---------------------------------------------------------------------------

/// A [StateNotifier] that batches rapid updates to reduce rebuilds.
///
/// Collects state changes over a short window and applies them as a single
/// update, reducing widget rebuilds for high-frequency state changes.
///
/// ```dart
/// class MyNotifier extends BatchedStateNotifier<MyState> {
///   MyNotifier() : super(MyState.initial());
///
///   void rapidUpdate(String value) {
///     batch((s) => s.copyWith(field: value));
///   }
/// }
/// ```
abstract class BatchedStateNotifier<T> extends StateNotifier<T> {
  Timer? _batchTimer;
  T? _pendingState;

  /// The batch window duration. Default is 16ms (~1 frame at 60fps).
  final Duration batchDuration;

  BatchedStateNotifier(super.initialState, {this.batchDuration = const Duration(milliseconds: 16)});

  /// Queue a state change to be applied in the next batch.
  ///
  /// Multiple calls within [batchDuration] are collapsed into the last one.
  void batch(T Function(T current) updater) {
    _pendingState = updater(_pendingState ?? state);
    _batchTimer?.cancel();
    _batchTimer = Timer(batchDuration, _flushBatch);
  }

  /// Immediately flush any pending batched update.
  void flushBatch() => _flushBatch();

  void _flushBatch() {
    _batchTimer?.cancel();
    if (_pendingState != null) {
      state = _pendingState as T;
      _pendingState = null;
    }
  }

  /// Force an immediate state update (bypasses batching).
  void setImmediate(T newState) {
    _flushBatch();
    state = newState;
  }

  @override
  void dispose() {
    _batchTimer?.cancel();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// CachedAsyncNotifier — Async Computations with Caching
// ---------------------------------------------------------------------------

/// Base class for notifiers that perform expensive async operations with caching.
///
/// Results are cached by input parameter and optionally time-to-live (TTL).
///
/// ```dart
/// class AnalysisNotifier extends CachedAsyncNotifier<String, AnalysisResult> {
///   @override
///   Future<AnalysisResult> compute(String code) async {
///     return await performAnalysis(code);
///   }
/// }
///
/// final analysisProvider = StateNotifierProvider.family<
///   CachedAsyncNotifier<String, AnalysisResult>,
///   AsyncValue<AnalysisResult>,
///   String>((ref, code) => AnalysisNotifier(code));
/// ```
abstract class CachedAsyncNotifier<K, V> extends StateNotifier<AsyncValue<V>> {
  final Map<K, _CacheEntry<V>> _cache = {};

  /// Time-to-live for cached entries. Override for custom duration.
  Duration get cacheTtl => const Duration(minutes: 5);

  /// Maximum number of entries in the cache.
  int get maxCacheSize => 50;

  CachedAsyncNotifier() : super(const AsyncValue.loading());

  /// Perform the actual computation. Subclasses must override.
  Future<V> compute(K key);

  /// Get a cached result or compute a new one.
  Future<V> get(K key) async {
    // Check cache.
    final cached = _cache[key];
    if (cached != null && !cached.isExpired) {
      if (cached.value is V) {
        state = AsyncValue.data(cached.value as V);
        return cached.value as V;
      }
    }

    // Evict oldest if at capacity.
    if (_cache.length >= maxCacheSize) {
      _evictOldest();
    }

    // Compute.
    state = const AsyncValue.loading();
    try {
      final result = await compute(key);
      _cache[key] = _CacheEntry(result, DateTime.now().add(cacheTtl));
      state = AsyncValue.data(result);
      return result;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Invalidate a specific cached entry.
  void invalidate(K key) => _cache.remove(key);

  /// Clear the entire cache.
  void clearCache() => _cache.clear();

  /// Get current cache size.
  int get cacheSize => _cache.length;

  void _evictOldest() {
    if (_cache.isEmpty) return;
    final oldest = _cache.entries.reduce((a, b) =>
        a.value.createdAt.isBefore(b.value.createdAt) ? a : b);
    _cache.remove(oldest.key);
  }

  @override
  void dispose() {
    _cache.clear();
    super.dispose();
  }
}

class _CacheEntry<V> {
  final V value;
  final DateTime expiresAt;
  final DateTime createdAt;

  _CacheEntry(this.value, this.expiresAt) : createdAt = DateTime.now();

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

// ---------------------------------------------------------------------------
// Select-Optimized State — Fine-Grained Subscriptions
// ---------------------------------------------------------------------------

/// A base class for state objects that support fine-grained selection.
///
/// Wraps a value and allows providers to select specific fields,
/// minimizing rebuilds to only when the selected field changes.
///
/// ```dart
/// final name = ref.watch(userProvider.select((u) => u.name));
/// final email = ref.watch(userProvider.select((u) => u.email));
/// ```
@immutable
class SelectableState<T> {
  final T _value;

  const SelectableState(this._value);

  T get value => _value;

  /// Select a field from the underlying value using a selector function.
  ///
  /// This is primarily a documentation/utility helper — the actual
  /// optimization comes from using Riverpod's built-in `.select()`:
  ///
  /// ```dart
  /// final name = ref.watch(provider.select((s) => s.select((u) => u.name)));
  /// ```
  R select<R>(R Function(T value) selector) => selector(_value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectableState<T> &&
          runtimeType == other.runtimeType &&
          _value == other._value;

  @override
  int get hashCode => _value.hashCode;
}

// ---------------------------------------------------------------------------
// Optimized Stream Providers — Auto-Dispose with Caching
// ---------------------------------------------------------------------------

/// Provider for watching project files with auto-dispose.
///
/// Automatically disposed when no listeners are active.
/// Kept alive for 2 minutes to handle brief listener drops.
final projectFilesProvider =
    StreamProvider.autoDispose.family<List<FileItem>, String>(
  (ref, projectId) {
    ref.cacheFor(const Duration(minutes: 2));
    return ProjectService().watchFiles(projectId);
  },
);

/// Provider for reading file content with auto-dispose.
///
/// Cached for 1 minute after last listener is removed.
final fileContentProvider =
    FutureProvider.autoDispose.family<String, String>(
  (ref, filePath) async {
    ref.cacheFor(const Duration(minutes: 1));
    return await FileService().read(filePath);
  },
);

/// Provider for directory listing with auto-dispose.
///
/// Results are cached for 30 seconds.
final directoryListProvider =
    FutureProvider.autoDispose.family<List<FileItem>, String>(
  (ref, directoryPath) async {
    ref.cacheFor(const Duration(seconds: 30));
    return await FileService().listDirectory(directoryPath);
  },
);

// ---------------------------------------------------------------------------
// Memory-Efficient Providers
// ---------------------------------------------------------------------------

/// Provider that exposes memory report as a stream.
///
/// Updates every 30 seconds with current memory status.
/// Auto-disposes when not in use.
final memoryReportProvider = StreamProvider.autoDispose<MemoryReport>(
  (ref) {
    final manager = MemoryManager();
    final controller = StreamController<MemoryReport>.broadcast();

    // Emit initial report.
    controller.add(manager.generateReport());

    // Periodic updates.
    final timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!controller.isClosed) {
        controller.add(manager.generateReport());
      }
    });

    ref.onDispose(() {
      timer.cancel();
      controller.close();
    });

    return controller.stream;
  },
);

/// Provider for current memory pressure status.
///
/// Efficiently updates only when pressure level changes.
final memoryPressureProvider = Provider<MemoryPressureLevel>((ref) {
  final report = ref.watch(memoryReportProvider).when(
        data: (r) => r.pressureLevel,
        loading: () => MemoryPressureLevel.normal,
        error: (_, __) => MemoryPressureLevel.normal,
      );
  return report;
});

/// Provider for checking if memory is under pressure.
///
/// Optimized: only rebuilds when the boolean changes.
final isMemoryUnderPressureProvider = Provider<bool>((ref) {
  return ref.watch(memoryPressureProvider.select(
    (level) => level.index >= MemoryPressureLevel.pressure.index,
  ));
});

// ---------------------------------------------------------------------------
// Minimal-Rebuild Wrapper Utilities
// ---------------------------------------------------------------------------

/// Creates a provider that selects a single field from a source provider.
///
/// This is a convenience helper for the common select() pattern:
///
/// ```dart
/// final userNameProvider = selectProvider(userProvider, (u) => u.name);
/// ```
Provider<R> selectProvider<T, R>(
  ProviderListenable<T> source,
  R Function(T value) selector,
) {
  return Provider<R>((ref) {
    return ref.watch(source.select(selector));
  });
}

/// Creates a family provider with automatic caching and refresh.
///
/// The provider is kept alive for [cacheDuration] and optionally
/// auto-refreshed every [refreshInterval].
FutureProviderFamily<T, K> cachedFutureProvider<T, K>(
  Future<T> Function(Ref ref, K key) create, {
  required Duration cacheDuration,
  Duration? refreshInterval,
}) {
  return FutureProvider.family<T, K>((ref, key) async {
    if (refreshInterval != null) {
      ref.cacheWithRefresh(
        cacheDuration: cacheDuration,
        refreshInterval: refreshInterval,
      );
    } else {
      ref.cacheFor(cacheDuration);
    }
    return await create(ref, key);
  });
}

// ---------------------------------------------------------------------------
// Stub Service Classes (integrated with real services at runtime)
// ---------------------------------------------------------------------------

/// Search service stub — replaced with real implementation.
class SearchService {
  static SearchService? _instance;
  factory SearchService() => _instance ??= SearchService._internal();
  SearchService._internal();

  Future<List<String>> search(String query) async {
    // Real implementation provided by the app.
    return [];
  }
}

/// Code analysis service stub — replaced with real implementation.
class CodeAnalysisService {
  static CodeAnalysisService? _instance;
  factory CodeAnalysisService() => _instance ??= CodeAnalysisService._internal();
  CodeAnalysisService._internal();

  Future<AnalysisResult> analyze(String code) async {
    // Real implementation provided by the app.
    return AnalysisResult();
  }
}

/// Project service stub — replaced with real implementation.
class ProjectService {
  static ProjectService? _instance;
  factory ProjectService() => _instance ??= ProjectService._internal();
  ProjectService._internal();

  Stream<List<FileItem>> watchFiles(String projectId) {
    // Real implementation provided by the app.
    return const Stream.empty();
  }
}

/// File service stub — replaced with real implementation.
class FileService {
  static FileService? _instance;
  factory FileService() => _instance ??= FileService._internal();
  FileService._internal();

  Future<String> read(String filePath) async {
    // Real implementation provided by the app.
    return '';
  }

  Future<List<FileItem>> listDirectory(String directoryPath) async {
    // Real implementation provided by the app.
    return [];
  }
}

// ---------------------------------------------------------------------------
// Result Models
// ---------------------------------------------------------------------------

/// Result of a code analysis operation.
@immutable
class AnalysisResult {
  /// Summary of the analysis.
  final String summary;

  /// List of issues found.
  final List<String> issues;

  /// Overall score (0-100).
  final int? score;

  /// Lines of code analyzed.
  final int? linesAnalyzed;

  const AnalysisResult({
    this.summary = '',
    this.issues = const [],
    this.score,
    this.linesAnalyzed,
  });

  AnalysisResult copyWith({
    String? summary,
    List<String>? issues,
    int? score,
    int? linesAnalyzed,
  }) {
    return AnalysisResult(
      summary: summary ?? this.summary,
      issues: issues ?? this.issues,
      score: score ?? this.score,
      linesAnalyzed: linesAnalyzed ?? this.linesAnalyzed,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnalysisResult &&
          runtimeType == other.runtimeType &&
          summary == other.summary &&
          listEquals(issues, other.issues) &&
          score == other.score &&
          linesAnalyzed == other.linesAnalyzed;

  @override
  int get hashCode => Object.hash(summary, Object.hashAll(issues), score, linesAnalyzed);
}

/// Stub file item model — matches the real FileItem from models/.
@immutable
class FileItem {
  final String name;
  final String path;
  final bool isDirectory;
  final int? size;
  final DateTime? modifiedAt;

  const FileItem({
    required this.name,
    required this.path,
    this.isDirectory = false,
    this.size,
    this.modifiedAt,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileItem &&
          runtimeType == other.runtimeType &&
          path == other.path;

  @override
  int get hashCode => path.hashCode;
}
