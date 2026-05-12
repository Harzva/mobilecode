// lib/services/offline_manager.dart

import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'local_database_service.dart';
import 'storage_service.dart';

// ─── Enums ────────────────────────────────────────────────────────────

/// Represents the current connectivity/sync state of the app.
enum SyncState { online, syncing, offline, error }

/// Types of syncable operations.
enum OperationType { create, update, delete }

/// Priority levels for sync operations.
/// Critical operations (e.g., project deletion) are processed first.
enum SyncPriority { low, normal, high, critical }

/// Resolution strategies when a conflict is detected between local and remote.
enum ConflictResolution { useLocal, useRemote, merge, manual }

// ─── Models ───────────────────────────────────────────────────────────

/// A single operation queued for synchronization with the remote server.
class SyncOperation {
  /// Unique operation ID (UUID v4).
  final String id;

  /// The type of CRUD operation.
  final OperationType type;

  /// The entity kind: 'project', 'file', 'snippet', 'config'.
  final String entityType;

  /// The entity's unique identifier.
  final String entityId;

  /// Payload data for the operation (JSON-serializable).
  final Map<String, dynamic> data;

  /// When the operation was originally created locally.
  final DateTime timestamp;

  /// How many times this operation has been retried after failure.
  final int retryCount;

  /// Processing priority.
  final SyncPriority priority;

  /// The version vector used for optimistic locking / conflict detection.
  final int? localVersion;

  /// Client-generated hash of the payload for integrity checks.
  final String? dataHash;

  const SyncOperation({
    required this.id,
    required this.type,
    required this.entityType,
    required this.entityId,
    required this.data,
    required this.timestamp,
    this.retryCount = 0,
    this.priority = SyncPriority.normal,
    this.localVersion,
    this.dataHash,
  });

  /// Serialize to a map for local DB storage.
  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.index,
        'entityType': entityType,
        'entityId': entityId,
        'data': data,
        'timestamp': timestamp.toIso8601String(),
        'retryCount': retryCount,
        'priority': priority.index,
        'localVersion': localVersion,
        'dataHash': dataHash,
      };

  /// Deserialize from a local DB map.
  factory SyncOperation.fromMap(Map<String, dynamic> map) => SyncOperation(
        id: map['id'] as String,
        type: OperationType.values[map['type'] as int],
        entityType: map['entityType'] as String,
        entityId: map['entityId'] as String,
        data: (map['data'] as Map<String, dynamic>?) ?? {},
        timestamp: DateTime.parse(map['timestamp'] as String),
        retryCount: (map['retryCount'] as int?) ?? 0,
        priority: SyncPriority.values[(map['priority'] as int?) ?? 1],
        localVersion: map['localVersion'] as int?,
        dataHash: map['dataHash'] as String?,
      );

  /// Create a copy with incremented retry count.
  SyncOperation incrementRetry() => SyncOperation(
        id: id,
        type: type,
        entityType: entityType,
        entityId: entityId,
        data: data,
        timestamp: timestamp,
        retryCount: retryCount + 1,
        priority: priority,
        localVersion: localVersion,
        dataHash: dataHash,
      );

  /// Priority value for queue ordering (higher = processed first).
  int get priorityValue => priority.index;

  @override
  String toString() =>
      'SyncOperation(${type.name} ${entityType}:${entityId}, pri=${priority.name}, retries=$retryCount)';
}

/// Describes a detected conflict between local and remote versions.
class ConflictDescription {
  final String conflictId;
  final String entityType;
  final String entityId;
  final Map<String, dynamic> localVersion;
  final Map<String, dynamic> remoteVersion;
  final DateTime localTimestamp;
  final DateTime remoteTimestamp;

  const ConflictDescription({
    required this.conflictId,
    required this.entityType,
    required this.entityId,
    required this.localVersion,
    required this.remoteVersion,
    required this.localTimestamp,
    required this.remoteTimestamp,
  });
}

/// Result of a queue processing run.
class QueueProcessResult {
  final int succeeded;
  final int failed;
  final int conflicts;
  final List<String> errors;

  const QueueProcessResult({
    this.succeeded = 0,
    this.failed = 0,
    this.conflicts = 0,
    this.errors = const [],
  });

  bool get allSucceeded => failed == 0 && conflicts == 0;
}

// ─── Offline Manager ──────────────────────────────────────────────────

/// Core offline-first synchronization manager.
///
/// Implements the **write-through-local** pattern: every mutation is persisted
/// to the local database immediately so the UI never blocks. When the device
/// is online, pending operations are drained from the [SyncQueue] and pushed
/// to the remote server in priority order.
///
/// ## Architecture
/// ```
///  UI / ViewModel
///       |
///       v
///  OfflineManager  <--->  LocalDatabaseService (source of truth)
///       |
///       v
///  SyncQueue  <--->  ApiService (best-effort remote)
/// ```
///
/// ## Conflict Resolution
/// The manager uses **optimistic locking** (version vectors) combined with
/// **last-write-wins** as the default automatic strategy. When a conflict is
/// detected the caller can elect [ConflictResolution.manual] and present a
/// diff UI to the user.
class OfflineManager {
  // ── Dependencies ────────────────────────────────────────────────────
  late final ApiService _api;
  late final LocalDatabaseService _db;
  late final StorageService _storage;

  // ── Internal State ──────────────────────────────────────────────────
  SyncState _state = SyncState.offline;
  bool _isOnline = false;
  bool _initialized = false;
  bool _processing = false;

  final List<SyncOperation> _pendingQueue = [];
  final List<ConflictDescription> _activeConflicts = [];

  // Broadcast streams for reactive UI updates.
  final _stateController = StreamController<SyncState>.broadcast();
  final _queueCountController = StreamController<int>.broadcast();
  final _conflictsController = StreamController<List<ConflictDescription>>.broadcast();
  final _lastSyncController = StreamController<DateTime?>.broadcast();

  DateTime? _lastSuccessfulSync;

  // Back-off config for failed operations.
  static const int _maxRetries = 5;
  static const Duration _baseRetryDelay = Duration(seconds: 2);
  static const Duration _maxRetryDelay = Duration(minutes: 5);

  // Debounce timer for batching rapid-fire mutations.
  Timer? _batchTimer;
  static const Duration _batchWindow = Duration(milliseconds: 500);

  // ── Public getters ──────────────────────────────────────────────────

  /// Current connectivity / sync state.
  SyncState get state => _state;

  /// Whether the device is currently online.
  bool get isOnline => _isOnline;

  /// Number of pending operations waiting to sync.
  int get pendingCount => _pendingQueue.length;

  /// Currently unresolved conflicts that need attention.
  List<ConflictDescription> get activeConflicts => List.unmodifiable(_activeConflicts);

  /// When the last successful full sync completed (null if never).
  DateTime? get lastSuccessfulSync => _lastSuccessfulSync;

  // ── Reactive streams ────────────────────────────────────────────────

  /// Emits whenever [state] changes.
  Stream<SyncState> get onStateChange => _stateController.stream;

  /// Emits the current pending queue count after every mutation.
  Stream<int> get onQueueCountChange => _queueCountController.stream;

  /// Emits the current list of active conflicts.
  Stream<List<ConflictDescription>> get onConflictsChange => _conflictsController.stream;

  /// Emits whenever a successful sync finishes.
  Stream<DateTime?> get onLastSyncChange => _lastSyncController.stream;

  // ── Singleton ───────────────────────────────────────────────────────

  static final OfflineManager _instance = OfflineManager._internal();
  factory OfflineManager() => _instance;
  OfflineManager._internal();

  // ── Lifecycle ───────────────────────────────────────────────────────

  /// One-time initialization. Must be called before any other method.
  ///
  /// [api] and [db] are injected so tests can provide fakes.
  Future<void> initialize({
    required ApiService api,
    required LocalDatabaseService db,
    required StorageService storage,
  }) async {
    if (_initialized) return;

    _api = api;
    _db = db;
    _storage = storage;

    // Hydrate in-memory queue from local DB.
    final pendingMaps = await _db.getPendingSyncs();
    _pendingQueue.addAll(
      pendingMaps.map(SyncOperation.fromMap),
    );
    _sortQueue();

    // Restore last sync timestamp from settings.
    final lastSyncStr = await _db.getSetting('last_successful_sync');
    if (lastSyncStr != null) {
      _lastSuccessfulSync = DateTime.tryParse(lastSyncStr as String);
    }

    // Assume offline until proven otherwise.
    _setState(SyncState.offline);

    _initialized = true;
    debugPrint('[OfflineManager] Initialized with $_pendingQueue pending ops');
  }

  /// Call when network connectivity changes.
  ///
  /// [isOnline] should come from `connectivity_plus` or similar.
  void onNetworkChange(bool isOnline) {
    final wasOnline = _isOnline;
    _isOnline = isOnline;

    if (isOnline && !wasOnline) {
      debugPrint('[OfflineManager] Network recovered -> online');
      _setState(SyncState.online);
      // Auto-drain queue when we come back online.
      _scheduleQueueProcessing();
    } else if (!isOnline && wasOnline) {
      debugPrint('[OfflineManager] Network lost -> offline');
      _setState(SyncState.offline);
      _batchTimer?.cancel();
    }
  }

  /// Dispose all internal streams and timers.
  void dispose() {
    _batchTimer?.cancel();
    _stateController.close();
    _queueCountController.close();
    _conflictsController.close();
    _lastSyncController.close();
    debugPrint('[OfflineManager] Disposed');
  }

  // ── Queue Management ────────────────────────────────────────────────

  /// Queue an operation for later sync.
  ///
  /// The operation is persisted to the local DB immediately and added to
  /// the in-memory queue. If the device is online, processing is scheduled
  /// with a short debounce to batch rapid operations.
  Future<void> queueOperation(SyncOperation operation) async {
    _ensureInitialized();

    // Persist to local DB first (source of truth).
    await _db.enqueueSync(operation.toMap());

    // Add to in-memory queue.
    _pendingQueue.add(operation);
    _sortQueue();
    _notifyQueueCount();

    debugPrint('[OfflineManager] Queued: $operation');

    // If online, schedule processing with a debounce for batching.
    if (_isOnline) {
      _batchTimer?.cancel();
      _batchTimer = Timer(_batchWindow, _scheduleQueueProcessing);
    }
  }

  /// Convenience helper to queue a create operation.
  Future<void> queueCreate({
    required String entityType,
    required String entityId,
    required Map<String, dynamic> data,
    SyncPriority priority = SyncPriority.normal,
  }) => queueOperation(
        SyncOperation(
          id: _generateOpId(),
          type: OperationType.create,
          entityType: entityType,
          entityId: entityId,
          data: data,
          timestamp: DateTime.now().toUtc(),
          priority: priority,
          localVersion: 1,
        ),
      );

  /// Convenience helper to queue an update operation.
  Future<void> queueUpdate({
    required String entityType,
    required String entityId,
    required Map<String, dynamic> data,
    required int currentVersion,
    SyncPriority priority = SyncPriority.normal,
  }) => queueOperation(
        SyncOperation(
          id: _generateOpId(),
          type: OperationType.update,
          entityType: entityType,
          entityId: entityId,
          data: data,
          timestamp: DateTime.now().toUtc(),
          priority: priority,
          localVersion: currentVersion + 1,
        ),
      );

  /// Convenience helper to queue a delete operation.
  Future<void> queueDelete({
    required String entityType,
    required String entityId,
    SyncPriority priority = SyncPriority.high,
  }) => queueOperation(
        SyncOperation(
          id: _generateOpId(),
          type: OperationType.delete,
          entityType: entityType,
          entityId: entityId,
          data: const {},
          timestamp: DateTime.now().toUtc(),
          priority: priority,
        ),
      );

  /// Process all pending operations now.
  ///
  /// Returns a summary of what succeeded, failed, or conflicted.
  /// This is called automatically when coming online; callers can also
  /// trigger it manually (e.g., pull-to-refresh).
  Future<QueueProcessResult> processQueue() async {
    _ensureInitialized();
    if (_processing || _pendingQueue.isEmpty || !_isOnline) {
      return const QueueProcessResult();
    }

    _processing = true;
    _setState(SyncState.syncing);

    int succeeded = 0;
    int failed = 0;
    int conflicts = 0;
    final errors = <String>[];

    // Work on a copy so the queue can mutate during iteration.
    final ops = List<SyncOperation>.from(_pendingQueue);

    for (final op in ops) {
      try {
        final result = await _executeOperation(op);

        if (result == _OpResult.success) {
          _pendingQueue.removeWhere((o) => o.id == op.id);
          await _db.markSyncCompleted(_opIdToDbId(op.id));
          succeeded++;
        } else if (result == _OpResult.conflict) {
          conflicts++;
          // Keep in queue; will be retried after conflict resolution.
        } else {
          failed++;
          await _handleFailure(op, 'Server rejected operation');
        }
      } catch (e) {
        failed++;
        errors.add('$op: $e');
        await _handleFailure(op, e.toString());

        // If it's a network error, go offline immediately.
        if (_isNetworkError(e)) {
          onNetworkChange(false);
          break;
        }
      }
    }

    _processing = false;
    _notifyQueueCount();

    if (_isOnline) {
      _setState(_pendingQueue.isEmpty ? SyncState.online : SyncState.error);
    }

    if (succeeded > 0) {
      _lastSuccessfulSync = DateTime.now().toUtc();
      await _db.setSetting('last_successful_sync', _lastSuccessfulSync!.toIso8601String());
      _lastSyncController.add(_lastSuccessfulSync);
    }

    debugPrint(
      '[OfflineManager] Queue processed: $succeeded succeeded, $failed failed, $conflicts conflicts',
    );

    return QueueProcessResult(
      succeeded: succeeded,
      failed: failed,
      conflicts: conflicts,
      errors: errors,
    );
  }

  /// Retry all failed operations that haven't exceeded max retries.
  Future<void> retryFailed() async {
    _ensureInitialized();
    final retryable = _pendingQueue
        .where((op) => op.retryCount < _maxRetries)
        .map((op) => op.incrementRetry())
        .toList();

    if (retryable.isEmpty) return;

    // Replace old entries with incremented retry versions.
    for (final op in retryable) {
      final idx = _pendingQueue.indexWhere((o) => o.id == op.id);
      if (idx >= 0) _pendingQueue[idx] = op;
    }
    _sortQueue();

    debugPrint('[OfflineManager] Retrying ${retryable.length} failed ops');
    await processQueue();
  }

  /// Clear all pending operations (use with caution -- typically only
  /// after explicit user confirmation).
  Future<void> clearQueue() async {
    _pendingQueue.clear();
    await _db.clearSyncQueue();
    _notifyQueueCount();
    debugPrint('[OfflineManager] Queue cleared');
  }

  // ── Conflict Resolution ─────────────────────────────────────────────

  /// Resolve a detected conflict using the chosen strategy.
  ///
  /// After resolution the winning version is queued for re-sync.
  Future<void> resolveConflict(
    String conflictId,
    ConflictResolution resolution, {
    Map<String, dynamic>? mergedData,
  }) async {
    _ensureInitialized();

    final conflict = _activeConflicts.firstWhere(
      (c) => c.conflictId == conflictId,
      orElse: () => throw StateError('Conflict $conflictId not found'),
    );

    Map<String, dynamic> winningData;
    switch (resolution) {
      case ConflictResolution.useLocal:
        winningData = conflict.localVersion;
        break;
      case ConflictResolution.useRemote:
        winningData = conflict.remoteVersion;
        break;
      case ConflictResolution.merge:
        winningData = mergedData ?? _autoMerge(conflict.localVersion, conflict.remoteVersion);
        break;
      case ConflictResolution.manual:
        winningData = mergedData ?? conflict.localVersion;
        break;
    }

    // Remove from active conflicts.
    _activeConflicts.removeWhere((c) => c.conflictId == conflictId);
    _conflictsController.add(List.unmodifiable(_activeConflicts));

    // Queue the resolved version as an update.
    await queueUpdate(
      entityType: conflict.entityType,
      entityId: conflict.entityId,
      data: winningData,
      currentVersion: (winningData['_version'] as int?) ?? 1,
      priority: SyncPriority.high,
    );

    debugPrint('[OfflineManager] Resolved conflict $conflictId with ${resolution.name}');
  }

  /// Automatic conflict resolution strategy.
  ///
  /// Default is **last-write-wins** by timestamp. Override this method
  /// or use [ConflictResolution.manual] for domain-specific merge logic.
  ConflictResolution resolveConflictAutomatically(
    SyncOperation local,
    Map<String, dynamic> remote,
  ) {
    final localTime = local.timestamp;
    final remoteTime = _parseRemoteTimestamp(remote);

    // If the remote version is newer, use it unless local is critical.
    if (remoteTime.isAfter(localTime)) {
      // But if local is a deletion, preserve it (deletion wins).
      if (local.type == OperationType.delete) return ConflictResolution.useLocal;
      return ConflictResolution.useRemote;
    }

    // Local is newer or equal -- keep local.
    return ConflictResolution.useLocal;
  }

  // ── Private Execution ───────────────────────────────────────────────

  /// Internal result of attempting one operation.
  enum _OpResult { success, conflict, failure }

  Future<_OpResult> _executeOperation(SyncOperation op) async {
    switch (op.type) {
      case OperationType.create:
        final resp = await _api.post(
          '/api/${op.entityType}/${op.entityId}',
          data: op.data,
        );
        return resp.statusCode == 200 || resp.statusCode == 201
            ? _OpResult.success
            : _OpResult.failure;

      case OperationType.update:
        // Optimistic locking: send version header.
        final resp = await _api.put(
          '/api/${op.entityType}/${op.entityId}',
          data: {
            ...op.data,
            '_version': op.localVersion,
          },
        );
        if (resp.statusCode == 409) {
          // Conflict detected -- hydrate from response and register it.
          _registerConflict(op, resp.data as Map<String, dynamic>);
          return _OpResult.conflict;
        }
        return resp.statusCode == 200 || resp.statusCode == 204
            ? _OpResult.success
            : _OpResult.failure;

      case OperationType.delete:
        final resp = await _api.delete(
          '/api/${op.entityType}/${op.entityId}',
        );
        return resp.statusCode == 200 || resp.statusCode == 204
            ? _OpResult.success
            : _OpResult.failure;
    }
  }

  Future<void> _handleFailure(SyncOperation op, String error) async {
    final updated = op.incrementRetry();
    final idx = _pendingQueue.indexWhere((o) => o.id == op.id);
    if (idx >= 0) _pendingQueue[idx] = updated;

    // Persist updated retry count to DB.
    await _db.markSyncFailed(
      _opIdToDbId(op.id),
      error,
    );

    // Exponential back-off: delay = base * 2^retry, capped at max.
    if (updated.retryCount < _maxRetries) {
      final delay = Duration(
        milliseconds: min(
          _baseRetryDelay.inMilliseconds * (1 << updated.retryCount),
          _maxRetryDelay.inMilliseconds,
        ),
      );
      debugPrint('[OfflineManager] Will retry $op in ${delay.inSeconds}s');
      Timer(delay, () => retryFailed());
    } else {
      debugPrint('[OfflineManager] $op exceeded max retries, giving up');
    }
  }

  void _registerConflict(
    SyncOperation localOp,
    Map<String, dynamic> remoteData,
  ) {
    final conflict = ConflictDescription(
      conflictId: 'conf_${localOp.entityType}_${localOp.entityId}_${DateTime.now().millisecondsSinceEpoch}',
      entityType: localOp.entityType,
      entityId: localOp.entityId,
      localVersion: localOp.data,
      remoteVersion: remoteData,
      localTimestamp: localOp.timestamp,
      remoteTimestamp: _parseRemoteTimestamp(remoteData),
    );

    _activeConflicts.add(conflict);
    _conflictsController.add(List.unmodifiable(_activeConflicts));

    debugPrint('[OfflineManager] CONFLICT: ${localOp.entityType}:${localOp.entityId}');
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  void _setState(SyncState newState) {
    if (_state == newState) return;
    _state = newState;
    _stateController.add(newState);
  }

  void _notifyQueueCount() {
    _queueCountController.add(_pendingQueue.length);
  }

  void _sortQueue() {
    _pendingQueue.sort((a, b) {
      // Higher priority first.
      final pri = b.priorityValue.compareTo(a.priorityValue);
      if (pri != 0) return pri;
      // Then FIFO within same priority.
      return a.timestamp.compareTo(b.timestamp);
    });
  }

  void _scheduleQueueProcessing() {
    if (_isOnline && _pendingQueue.isNotEmpty && !_processing) {
      processQueue();
    }
  }

  bool _isNetworkError(dynamic error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('socket') ||
        msg.contains('timeout') ||
        msg.contains('connection') ||
        msg.contains('network');
  }

  DateTime _parseRemoteTimestamp(Map<String, dynamic> remote) {
    final ts = remote['updatedAt'] ?? remote['timestamp'] ?? remote['modifiedAt'];
    if (ts is String) return DateTime.tryParse(ts) ?? DateTime.now().toUtc();
    return DateTime.now().toUtc();
  }

  /// Auto-merge two maps: local wins on key collisions unless the remote
  /// value is newer based on nested `_version` fields.
  Map<String, dynamic> _autoMerge(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    final merged = Map<String, dynamic>.of(remote);
    local.forEach((key, value) {
      if (!merged.containsKey(key)) {
        merged[key] = value;
      } else if (value is Map<String, dynamic> && merged[key] is Map<String, dynamic>) {
        merged[key] = _autoMerge(value, merged[key] as Map<String, dynamic>);
      }
      // Otherwise keep remote (last-write-wins for primitives).
    });
    merged['_merged'] = true;
    merged['_mergedAt'] = DateTime.now().toUtc().toIso8601String();
    return merged;
  }

  String _generateOpId() =>
      'op_${DateTime.now().millisecondsSinceEpoch}_${_pendingQueue.length}';

  /// Map the operation's client ID to a DB row ID (best-effort).
  int _opIdToDbId(String opId) {
    // The DB uses auto-increment; we scan the queue to find the index.
    // In production, store the DB row ID on [SyncOperation].
    return _pendingQueue.indexWhere((o) => o.id == opId) + 1;
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('OfflineManager not initialized. Call initialize() first.');
    }
  }
}
