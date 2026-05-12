// lib/providers/sync_provider.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_database_service.dart';
import '../services/offline_manager.dart';
import '../services/sync_queue_service.dart';

// ─── Provider Declarations ────────────────────────────────────────────

/// Provider for the [OfflineManager] singleton.
///
/// Must be overridden with an initialized instance in `ProviderScope`:
/// ```dart
/// ProviderScope(
///   overrides: [
///     offlineManagerProvider.overrideWithValue(myInitializedManager),
///   ],
///   child: MyApp(),
/// )
/// ```
final offlineManagerProvider = Provider<OfflineManager>((ref) {
  return OfflineManager();
});

/// Provider for the [SyncQueueService].
final syncQueueServiceProvider = Provider<SyncQueueService>((ref) {
  // This will be overridden after initialization.
  throw UnimplementedError('SyncQueueService must be overridden after initialization');
});

/// Provider for the [LocalDatabaseService].
final localDatabaseProvider = Provider<LocalDatabaseService>((ref) {
  return LocalDatabaseService();
});

// ─── Sync State Notifier ──────────────────────────────────────────────

/// Comprehensive sync state exposed to the UI layer.
///
/// This is an immutable snapshot that widgets can observe via
/// [syncStateProvider] to show connectivity badges, pending counts,
/// sync progress, and last-sync timestamps.
@immutable
class SyncStateData {
  /// Whether the device is currently connected to the internet.
  final bool isOnline;

  /// The current sync lifecycle phase.
  final SyncState syncState;

  /// Number of operations waiting to be synced.
  final int pendingCount;

  /// Number of operations currently retrying.
  final int retryingCount;

  /// Number of operations that failed permanently.
  final int failedCount;

  /// Number of unresolved conflicts.
  final int conflictCount;

  /// Whether the sync queue processor is actively running.
  final bool isProcessing;

  /// When the last successful sync completed (null if never).
  final DateTime? lastSyncAt;

  /// Current download progress for model downloads (0.0 to 1.0, -1 if not downloading).
  final double modelDownloadProgress;

  const SyncStateData({
    this.isOnline = false,
    this.syncState = SyncState.offline,
    this.pendingCount = 0,
    this.retryingCount = 0,
    this.failedCount = 0,
    this.conflictCount = 0,
    this.isProcessing = false,
    this.lastSyncAt,
    this.modelDownloadProgress = -1,
  });

  /// Whether there is any sync-related activity that the user should know about.
  bool get hasActivity => pendingCount > 0 || isProcessing || failedCount > 0 || conflictCount > 0;

  /// Whether the current state represents an error condition.
  bool get hasError => failedCount > 0 || conflictCount > 0;

  /// Human-readable status label for UI display.
  String get statusLabel {
    switch (syncState) {
      case SyncState.online:
        return pendingCount > 0 ? 'Sync pending' : 'Online';
      case SyncState.syncing:
        return 'Syncing...';
      case SyncState.offline:
        return 'Offline';
      case SyncState.error:
        return failedCount > 0 ? '$failedCount failed' : 'Sync error';
    }
  }

  /// Creates a copy with specified fields replaced.
  SyncStateData copyWith({
    bool? isOnline,
    SyncState? syncState,
    int? pendingCount,
    int? retryingCount,
    int? failedCount,
    int? conflictCount,
    bool? isProcessing,
    DateTime? lastSyncAt,
    double? modelDownloadProgress,
  }) {
    return SyncStateData(
      isOnline: isOnline ?? this.isOnline,
      syncState: syncState ?? this.syncState,
      pendingCount: pendingCount ?? this.pendingCount,
      retryingCount: retryingCount ?? this.retryingCount,
      failedCount: failedCount ?? this.failedCount,
      conflictCount: conflictCount ?? this.conflictCount,
      isProcessing: isProcessing ?? this.isProcessing,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      modelDownloadProgress: modelDownloadProgress ?? this.modelDownloadProgress,
    );
  }

  @override
  String toString() {
    return 'SyncStateData(online=$isOnline, state=${syncState.name}, '
        'pending=$pendingCount, failed=$failedCount, conflicts=$conflictCount, '
        'processing=$isProcessing, lastSync=${lastSyncAt?.toIso8601String() ?? 'never'})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SyncStateData &&
        other.isOnline == isOnline &&
        other.syncState == syncState &&
        other.pendingCount == pendingCount &&
        other.retryingCount == retryingCount &&
        other.failedCount == failedCount &&
        other.conflictCount == conflictCount &&
        other.isProcessing == isProcessing &&
        other.lastSyncAt == lastSyncAt &&
        other.modelDownloadProgress == modelDownloadProgress;
  }

  @override
  int get hashCode => Object.hash(
        isOnline,
        syncState,
        pendingCount,
        retryingCount,
        failedCount,
        conflictCount,
        isProcessing,
        lastSyncAt,
        modelDownloadProgress,
      );
}

/// {@template sync_state_notifier}
/// Riverpod [StateNotifier] that exposes reactive sync state to the UI.
///
/// Listens to streams from [OfflineManager] and [SyncQueueService] and
/// consolidates them into a single [SyncStateData] snapshot that widgets
/// can watch efficiently.
///
/// ## Usage in widgets
/// ```dart
/// class SyncBadge extends ConsumerWidget {
///   @override
///   Widget build(BuildContext context, WidgetRef ref) {
///     final sync = ref.watch(syncStateProvider);
///     return Text('${sync.pendingCount} pending');
///   }
/// }
/// ```
/// {@endtemplate}
class SyncStateNotifier extends StateNotifier<SyncStateData> {
  final OfflineManager _offlineManager;
  final SyncQueueService _queueService;

  StreamSubscription<SyncState>? _stateSub;
  StreamSubscription<int>? _queueCountSub;
  StreamSubscription<DateTime?>? _lastSyncSub;
  StreamSubscription<SyncQueueStatus>? _queueStatusSub;

  Timer? _pollingTimer;

  /// {@macro sync_state_notifier}
  SyncStateNotifier({
    required OfflineManager offlineManager,
    required SyncQueueService queueService,
  })  : _offlineManager = offlineManager,
        _queueService = queueService,
        super(const SyncStateData()) {
    _initListeners();
  }

  void _initListeners() {
    // Listen to OfflineManager state changes.
    _stateSub = _offlineManager.onStateChange.listen((syncState) {
      state = state.copyWith(
        syncState: syncState,
        isOnline: syncState == SyncState.online || syncState == SyncState.syncing,
        isProcessing: syncState == SyncState.syncing,
      );
    });

    // Listen to queue count changes.
    _queueCountSub = _offlineManager.onQueueCountChange.listen((count) {
      state = state.copyWith(pendingCount: count);
    });

    // Listen to last successful sync changes.
    _lastSyncSub = _offlineManager.onLastSyncChange.listen((lastSync) {
      state = state.copyWith(lastSyncAt: lastSync);
    });

    // Listen to detailed queue status from SyncQueueService.
    _queueStatusSub = _queueService.onStatusChange.listen((status) {
      state = state.copyWith(
        isProcessing: status.isProcessing,
        pendingCount: status.totalPending,
        retryingCount: status.retrying,
        failedCount: status.failed,
        conflictCount: status.conflicts,
        isOnline: status.isOnline,
      );
    });

    // Poll for updates every 5 seconds as a fallback.
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  /// Force a refresh of the sync state from underlying services.
  void _refresh() {
    final status = _queueService.getStatus();
    state = state.copyWith(
      pendingCount: _offlineManager.pendingCount,
      isOnline: _offlineManager.isOnline,
      syncState: _offlineManager.state,
      isProcessing: status.isProcessing,
      conflictCount: status.conflicts,
      lastSyncAt: _offlineManager.lastSuccessfulSync,
    );
  }

  /// Trigger an immediate sync of the pending queue.
  Future<void> syncNow() async {
    state = state.copyWith(isProcessing: true, syncState: SyncState.syncing);
    try {
      final result = await _offlineManager.processQueue();
      state = state.copyWith(
        isProcessing: false,
        pendingCount: _offlineManager.pendingCount,
        failedCount: result.failed,
        conflictCount: result.conflicts,
        syncState: _offlineManager.state,
      );
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        syncState: SyncState.error,
      );
    }
  }

  /// Resolve a conflict using the specified strategy.
  Future<void> resolveConflict(String conflictId, ConflictResolution resolution) async {
    await _offlineManager.resolveConflict(conflictId, resolution);
    _refresh();
  }

  /// Retry all failed operations.
  Future<void> retryFailed() async {
    await _offlineManager.retryFailed();
    _refresh();
  }

  /// Update the model download progress (called from LocalAIService).
  void setModelDownloadProgress(double progress) {
    state = state.copyWith(modelDownloadProgress: progress);
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _queueCountSub?.cancel();
    _lastSyncSub?.cancel();
    _queueStatusSub?.cancel();
    _pollingTimer?.cancel();
    super.dispose();
  }
}

// ─── Global Provider Instances ────────────────────────────────────────

/// The main sync state provider that widgets should watch.
///
/// Provides a reactive [SyncStateData] snapshot that updates automatically
/// as network conditions, queue state, and conflicts change.
final syncStateProvider = StateNotifierProvider<SyncStateNotifier, SyncStateData>((ref) {
  final offlineManager = ref.watch(offlineManagerProvider);
  final queueService = ref.watch(syncQueueServiceProvider);

  return SyncStateNotifier(
    offlineManager: offlineManager,
    queueService: queueService,
  );
});

/// A lightweight provider for just the online/offline boolean.
///
/// Use this when you only need connectivity status (cheaper rebuilds).
final isOnlineProvider = Provider<bool>((ref) {
  return ref.watch(syncStateProvider.select((s) => s.isOnline));
});

/// Provider for just the pending sync count.
///
/// Use this for badge counters (minimal rebuilds).
final pendingSyncCountProvider = Provider<int>((ref) {
  return ref.watch(syncStateProvider.select((s) => s.pendingCount));
});

/// Provider for whether any sync errors exist.
///
/// Use this to show error indicators.
final hasSyncErrorsProvider = Provider<bool>((ref) {
  return ref.watch(syncStateProvider.select((s) => s.hasError));
});

/// Provider for the human-readable sync status label.
final syncStatusLabelProvider = Provider<String>((ref) {
  return ref.watch(syncStateProvider.select((s) => s.statusLabel));
});
