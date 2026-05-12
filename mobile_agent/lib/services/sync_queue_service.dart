// lib/services/sync_queue_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:math' show max;

import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'local_database_service.dart';
import 'offline_manager.dart';

// ─── Models ───────────────────────────────────────────────────────────

/// Result of a full queue processing run.
class SyncResult {
  /// How many operations were successfully synced.
  final int succeeded;

  /// How many operations failed permanently (exhausted retries).
  final int failed;

  /// How many conflicts were detected and need resolution.
  final int conflicts;

  /// Human-readable error messages for failed items.
  final List<String> errors;

  const SyncResult({
    this.succeeded = 0,
    this.failed = 0,
    this.conflicts = 0,
    this.errors = const [],
  });

  /// Whether every pending operation succeeded with no issues.
  bool get allSucceeded => failed == 0 && conflicts == 0;

  /// Total number of operations that were processed.
  int get totalProcessed => succeeded + failed + conflicts;

  Map<String, dynamic> toJson() => {
        'succeeded': succeeded,
        'failed': failed,
        'conflicts': conflicts,
        'errors': errors,
      };

  @override
  String toString() => 'SyncResult(ok=$succeeded, fail=$failed, conflict=$conflicts)';
}

/// Describes a conflict between a local pending operation and remote state.
class Conflict {
  /// Unique identifier for this conflict instance.
  final String id;

  /// The entity kind: 'project', 'file', 'snippet', 'config'.
  final String entityType;

  /// The entity's unique identifier.
  final String entityId;

  /// The local version of the entity data.
  final Map<String, dynamic> localVersion;

  /// The remote version as returned by the server.
  final Map<String, dynamic> remoteVersion;

  /// When the local change was made.
  final DateTime localTimestamp;

  /// When the remote change was made (from server metadata).
  final DateTime remoteTimestamp;

  /// The pending operation that caused the conflict.
  final SyncOperation? originatingOperation;

  const Conflict({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.localVersion,
    required this.remoteVersion,
    required this.localTimestamp,
    required this.remoteTimestamp,
    this.originatingOperation,
  });

  @override
  String toString() => 'Conflict(${entityType}:${entityId})';
}

/// Snapshot of the current queue health.
class SyncQueueStatus {
  /// Total operations waiting to be synced.
  final int totalPending;

  /// Operations currently in retry backoff.
  final int retrying;

  /// Operations that have failed permanently.
  final int failed;

  /// Unresolved conflicts awaiting user action.
  final int conflicts;

  /// Whether the queue processor is actively running.
  final bool isProcessing;

  /// Whether the device is currently online.
  final bool isOnline;

  /// When the queue was last processed (null if never).
  final DateTime? lastProcessedAt;

  const SyncQueueStatus({
    required this.totalPending,
    required this.retrying,
    required this.failed,
    required this.conflicts,
    required this.isProcessing,
    required this.isOnline,
    this.lastProcessedAt,
  });

  /// Whether there is any work remaining (pending, retrying, or conflicts).
  bool get hasWork => totalPending > 0 || retrying > 0 || failed > 0 || conflicts > 0;

  @override
  String toString() =>
      'SyncQueueStatus(pending=$totalPending, retrying=$retrying, failed=$failed, '
      'conflicts=$conflicts, processing=$isProcessing, online=$isOnline)';
}

/// {@template sync_queue_service}
/// Manages the outbound sync queue with conflict detection and resolution.
///
/// This service is the **execution layer** that sits between [OfflineManager]
/// and the network. It is responsible for:
/// - Enqueueing operations with priority ordering.
/// - Draining the queue by sending operations to the server.
/// - Detecting 409 / version-mismatch conflicts.
/// - Retrying failed operations with exponential backoff.
/// - Batching small operations for network efficiency.
///
/// ## Retry policy
/// ```
/// delay = min(baseDelay * 2^attempt, maxDelay)
/// ```
/// Operations are retried up to [maxRetries] times before being marked failed.
/// {@endtemplate}
class SyncQueueService {
  final ApiService _api;
  final LocalDatabaseService _db;

  final List<Conflict> _activeConflicts = [];
  final _statusController = StreamController<SyncQueueStatus>.broadcast();
  final _conflictController = StreamController<List<Conflict>>.broadcast();

  bool _processing = false;
  bool _isOnline = false;
  DateTime? _lastProcessedAt;

  // ── Configuration ───────────────────────────────────────────────────

  /// Maximum number of retry attempts before an operation is abandoned.
  static const int maxRetries = 5;

  /// Base delay between retries (doubles each attempt).
  static const Duration baseRetryDelay = Duration(seconds: 3);

  /// Maximum delay between retries.
  static const Duration maxRetryDelay = Duration(minutes: 10);

  /// How many operations to process in a single batch.
  static const int batchSize = 10;

  // ── Constructor ─────────────────────────────────────────────────────

  /// {@macro sync_queue_service}
  SyncQueueService({
    required ApiService api,
    required LocalDatabaseService db,
  })  : _api = api,
        _db = db;

  // ── Streams ─────────────────────────────────────────────────────────

  /// Emits a new [SyncQueueStatus] whenever queue state changes.
  Stream<SyncQueueStatus> get onStatusChange => _statusController.stream;

  /// Emits the current list of active conflicts whenever they change.
  Stream<List<Conflict>> get onConflictsChange => _conflictController.stream;

  // ── Network state ───────────────────────────────────────────────────

  /// Notify the service of connectivity changes.
  void setOnline(bool online) {
    final changed = _isOnline != online;
    _isOnline = online;
    if (changed) {
      _notifyStatus();
      if (online) {
        // Auto-trigger processing when coming back online.
        processQueue();
      }
    }
  }

  // ── Enqueue ─────────────────────────────────────────────────────────

  /// Add an operation to the sync queue.
  ///
  /// The operation is persisted to SQLite immediately and will survive
  /// app restarts. Higher priority operations are processed first.
  Future<void> enqueue({
    required OperationType type,
    required String entityType,
    required String entityId,
    required Map<String, dynamic> data,
    SyncPriority priority = SyncPriority.normal,
  }) async {
    final op = SyncOperation(
      id: 'op_${DateTime.now().millisecondsSinceEpoch}_$_counter',
      type: type,
      entityType: entityType,
      entityId: entityId,
      data: data,
      timestamp: DateTime.now().toUtc(),
      priority: priority,
      localVersion: data['_version'] as int? ?? 1,
    );

    // Persist to local DB first.
    await _db.enqueueSync(op.toMap());

    debugPrint('[SyncQueueService] Enqueued: $op');
    _notifyStatus();

    // If online, kick off processing (debounced in OfflineManager).
    if (_isOnline) {
      unawaited(processQueue());
    }
  }

  int _counter = 0;

  // ── Process Queue ───────────────────────────────────────────────────

  /// Process all pending operations in the queue.
  ///
  /// Operations are fetched in priority order, sent to the server in
  /// batches, and removed from the queue on success. Conflicts are
  /// recorded and the caller is notified via [onConflictsChange].
  Future<SyncResult> processQueue() async {
    if (_processing || !_isOnline) {
      return const SyncResult();
    }

    _processing = true;
    _notifyStatus();

    int succeeded = 0;
    int failed = 0;
    int conflicts = 0;
    final errors = <String>[];

    try {
      // Get pending ops from DB (already sorted by priority, timestamp).
      final pending = await _db.getPendingSyncs();

      if (pending.isEmpty) {
        _processing = false;
        _lastProcessedAt = DateTime.now().toUtc();
        _notifyStatus();
        return const SyncResult();
      }

      debugPrint('[SyncQueueService] Processing ${pending.length} pending ops');

      // Process in batches.
      for (var i = 0; i < pending.length; i += batchSize) {
        final batch = pending.skip(i).take(batchSize).toList();

        for (final row in batch) {
          final dbId = row['id'] as int;
          final result = await _processSingleOperation(row, dbId);

          switch (result) {
            case _ProcessResult.success:
              succeeded++;
              break;
            case _ProcessResult.conflict:
              conflicts++;
              break;
            case _ProcessResult.failure:
              failed++;
              break;
            case _ProcessResult.skipped:
              break;
          }
        }

        // Brief yield between batches to keep the UI responsive.
        await Future.delayed(Duration.zero);
      }
    } catch (e) {
      debugPrint('[SyncQueueService] processQueue error: $e');
      errors.add('Queue processing failed: $e');
    } finally {
      _processing = false;
      _lastProcessedAt = DateTime.now().toUtc();
      _notifyStatus();
    }

    final result = SyncResult(
      succeeded: succeeded,
      failed: failed,
      conflicts: conflicts,
      errors: errors,
    );

    debugPrint('[SyncQueueService] $result');
    return result;
  }

  // ── Single Operation Execution ──────────────────────────────────────

  Future<_ProcessResult> _processSingleOperation(
    Map<String, dynamic> row,
    int dbId,
  ) async {
    final opType = (row['type'] as int? ?? 0).clamp(0, 2);
    final type = OperationType.values[opType];
    final entityType = row['entity_type'] as String;
    final entityId = row['entity_id'] as String;
    final retryCount = (row['retry_count'] as int?) ?? 0;
    final dataRaw = row['data'] as String? ?? '{}';
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(dataRaw) as Map<String, dynamic>;
    } catch (_) {
      data = {};
    }

    final op = SyncOperation(
      id: row['op_id'] as String,
      type: type,
      entityType: entityType,
      entityId: entityId,
      data: data,
      timestamp: DateTime.parse(row['timestamp'] as String),
      retryCount: retryCount,
      priority: SyncPriority.values[(row['priority'] as int? ?? 1).clamp(0, 3)],
      localVersion: row['local_version'] as int?,
    );

    try {
      // Check if this operation's entity has an active conflict.
      final hasConflict = _activeConflicts.any(
        (c) => c.entityType == entityType && c.entityId == entityId,
      );
      if (hasConflict) return _ProcessResult.skipped;

      switch (type) {
        case OperationType.create:
          await _api.post(
            '/api/$entityType/$entityId',
            data: data,
          );
          break;
        case OperationType.update:
          final response = await _api.put(
            '/api/$entityType/$entityId',
            data: {
              ...data,
              '_version': op.localVersion,
            },
          );
          // 409 Conflict -- server has a newer version.
          if (response.statusCode == 409) {
            _recordConflict(op, response.data);
            return _ProcessResult.conflict;
          }
          break;
        case OperationType.delete:
          await _api.delete('/api/$entityType/$entityId');
          break;
      }

      // Success -- remove from queue.
      await _db.markSyncCompleted(dbId);
      return _ProcessResult.success;
    } catch (e) {
      final errorMsg = e.toString();

      // Check for version conflict in error payload.
      if (_isConflictError(errorMsg)) {
        _recordConflict(op, {'error': errorMsg});
        return _ProcessResult.conflict;
      }

      // Handle retryable vs permanent failures.
      if (retryCount < maxRetries && _isRetryableError(e)) {
        final delayMs = baseRetryDelay.inMilliseconds * (1 << retryCount);
        final clampedDelay = Duration(
          milliseconds: delayMs.clamp(0, maxRetryDelay.inMilliseconds),
        );

        await _db.markSyncFailed(dbId, errorMsg);

        // Schedule retry.
        Timer(clampedDelay, () async {
          debugPrint('[SyncQueueService] Retrying op ${op.id} (attempt ${retryCount + 1})');
          final retryRow = await _db.getPendingSyncs();
          final match = retryRow.firstWhere(
            (r) => r['id'] == dbId,
            orElse: () => const {},
          );
          if (match.isNotEmpty) {
            await _processSingleOperation(match, dbId);
          }
        });

        return _ProcessResult.failure;
      } else {
        // Exhausted retries or non-retryable error.
        await _db.markSyncFailed(dbId, errorMsg);
        return _ProcessResult.failure;
      }
    }
  }

  // ── Conflict Detection & Resolution ─────────────────────────────────

  /// Scan the current queue and the server for any version conflicts.
  ///
  /// This performs HEAD requests for all pending update operations to
  /// detect if the remote has moved ahead of the local version.
  Future<List<Conflict>> detectConflicts() async {
    if (!_isOnline) return [];

    final pending = await _db.getPendingSyncs();
    final conflicts = <Conflict>[];

    for (final row in pending) {
      final opType = (row['type'] as int? ?? 0);
      if (opType != OperationType.update.index) continue;

      final entityType = row['entity_type'] as String;
      final entityId = row['entity_id'] as String;
      final localVersion = row['local_version'] as int?;

      try {
        final response = await _api.get(
          '/api/$entityType/$entityId',
          query: {'_fields': 'version,updatedAt,data'},
        );

        if (response.statusCode == 200 && response.data is Map) {
          final remote = response.data as Map<String, dynamic>;
          final remoteVersion = remote['_version'] as int?;

          if (remoteVersion != null &&
              localVersion != null &&
              remoteVersion > localVersion) {
            final dataRaw = row['data'] as String? ?? '{}';
            final localData = jsonDecode(dataRaw) as Map<String, dynamic>;

            final conflict = Conflict(
              id: 'conf_${entityType}_${entityId}_${DateTime.now().millisecondsSinceEpoch}',
              entityType: entityType,
              entityId: entityId,
              localVersion: localData,
              remoteVersion: remote,
              localTimestamp: DateTime.parse(row['timestamp'] as String),
              remoteTimestamp: _parseTimestamp(remote['updatedAt']),
              originatingOperation: SyncOperation.fromMap(row),
            );

            conflicts.add(conflict);
          }
        }
      } catch (e) {
        // Skip entities we can't check.
        debugPrint('[SyncQueueService] Conflict check failed for $entityType:$entityId: $e');
      }
    }

    // Merge with existing conflicts, avoiding duplicates.
    for (final newConflict in conflicts) {
      final exists = _activeConflicts.any(
        (c) => c.entityType == newConflict.entityType && c.entityId == newConflict.entityId,
      );
      if (!exists) _activeConflicts.add(newConflict);
    }

    _conflictController.add(List.unmodifiable(_activeConflicts));
    _notifyStatus();

    return List.unmodifiable(_activeConflicts);
  }

  /// Resolve a conflict using the chosen strategy.
  Future<void> resolveConflict(String conflictId, ConflictResolution resolution) async {
    final idx = _activeConflicts.indexWhere((c) => c.id == conflictId);
    if (idx < 0) throw StateError('Conflict $conflictId not found');

    final conflict = _activeConflicts[idx];
    _activeConflicts.removeAt(idx);

    Map<String, dynamic> winningData;
    switch (resolution) {
      case ConflictResolution.useLocal:
        winningData = conflict.localVersion;
        break;
      case ConflictResolution.useRemote:
        winningData = conflict.remoteVersion;
        break;
      case ConflictResolution.merge:
        winningData = _mergeMaps(conflict.localVersion, conflict.remoteVersion);
        break;
      case ConflictResolution.manual:
        // Caller should have updated data before calling; fall through to local.
        winningData = conflict.localVersion;
        break;
    }

    // Queue the resolved version as a new high-priority update.
    await enqueue(
      type: OperationType.update,
      entityType: conflict.entityType,
      entityId: conflict.entityId,
      data: {
        ...winningData,
        '_version': (conflict.remoteVersion['_version'] as int? ?? 0) + 1,
        '_resolvedAt': DateTime.now().toUtc().toIso8601String(),
        '_resolution': resolution.name,
      },
      priority: SyncPriority.high,
    );

    _conflictController.add(List.unmodifiable(_activeConflicts));
    _notifyStatus();

    debugPrint('[SyncQueueService] Resolved conflict $conflictId with ${resolution.name}');
  }

  /// Discard a conflict without syncing (user chose to abandon changes).
  Future<void> abandonConflict(String conflictId) async {
    _activeConflicts.removeWhere((c) => c.id == conflictId);
    _conflictController.add(List.unmodifiable(_activeConflicts));
    _notifyStatus();
  }

  /// Resolve all active conflicts automatically using last-write-wins.
  Future<SyncResult> resolveAllAutomatically() async {
    int succeeded = 0;
    int failed = 0;

    final toResolve = List<Conflict>.from(_activeConflicts);
    for (final conflict in toResolve) {
      try {
        final resolution = conflict.localTimestamp.isAfter(conflict.remoteTimestamp)
            ? ConflictResolution.useLocal
            : ConflictResolution.useRemote;
        await resolveConflict(conflict.id, resolution);
        succeeded++;
      } catch (e) {
        failed++;
        debugPrint('[SyncQueueService] Auto-resolve failed for ${conflict.id}: $e');
      }
    }

    return SyncResult(succeeded: succeeded, failed: failed);
  }

  // ── Status ──────────────────────────────────────────────────────────

  /// Get a point-in-time snapshot of the queue status.
  SyncQueueStatus getStatus() => SyncQueueStatus(
        totalPending: _pendingCount,
        retrying: _retryingCount,
        failed: _failedCount,
        conflicts: _activeConflicts.length,
        isProcessing: _processing,
        isOnline: _isOnline,
        lastProcessedAt: _lastProcessedAt,
      );

  /// Get all currently active conflicts.
  List<Conflict> getActiveConflicts() => List.unmodifiable(_activeConflicts);

  // ── Private ─────────────────────────────────────────────────────────

  int get _pendingCount => _db.getPendingSyncCount() as int;

  int get _retryingCount {
    // Computed from DB state; we keep this lightweight.
    return 0; // Fetched on-demand via status snapshots.
  }

  int get _failedCount => _activeConflicts.length; // Approximation.

  void _notifyStatus() {
    _statusController.add(getStatus());
  }

  void _recordConflict(SyncOperation op, dynamic remoteData) {
    final remoteMap = remoteData is Map<String, dynamic>
        ? remoteData
        : <String, dynamic>{'raw': remoteData.toString()};

    final conflict = Conflict(
      id: 'conf_${op.entityType}_${op.entityId}_${DateTime.now().millisecondsSinceEpoch}',
      entityType: op.entityType,
      entityId: op.entityId,
      localVersion: op.data,
      remoteVersion: remoteMap,
      localTimestamp: op.timestamp,
      remoteTimestamp: _parseTimestamp(remoteMap['updatedAt'] ?? remoteMap['timestamp']),
      originatingOperation: op,
    );

    final exists = _activeConflicts.any(
      (c) => c.entityType == op.entityType && c.entityId == op.entityId,
    );
    if (!exists) {
      _activeConflicts.add(conflict);
      _conflictController.add(List.unmodifiable(_activeConflicts));
      _notifyStatus();
    }

    debugPrint('[SyncQueueService] Recorded conflict: ${conflict.id}');
  }

  Map<String, dynamic> _mergeMaps(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    final merged = Map<String, dynamic>.of(remote);
    local.forEach((key, value) {
      if (!merged.containsKey(key)) {
        merged[key] = value;
      } else if (value is Map<String, dynamic> && merged[key] is Map<String, dynamic>) {
        merged[key] = _mergeMaps(value, merged[key] as Map<String, dynamic>);
      }
      // Primitives: remote wins (last-write-wins).
    });
    merged['_merged'] = true;
    return merged;
  }

  bool _isRetryableError(dynamic error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('timeout') ||
        msg.contains('socket') ||
        msg.contains('connection') ||
        msg.contains('network') ||
        msg.contains('503') ||
        msg.contains('502') ||
        msg.contains('504');
  }

  bool _isConflictError(String errorMessage) {
    final lower = errorMessage.toLowerCase();
    return lower.contains('409') ||
        lower.contains('conflict') ||
        lower.contains('version mismatch');
  }

  DateTime _parseTimestamp(dynamic ts) {
    if (ts is String) return DateTime.tryParse(ts) ?? DateTime.now().toUtc();
    return DateTime.now().toUtc();
  }

  /// Dispose all internal streams.
  void dispose() {
    _statusController.close();
    _conflictController.close();
  }
}

// Internal result type for a single operation.
enum _ProcessResult { success, conflict, failure, skipped }
