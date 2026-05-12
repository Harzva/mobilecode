// lib/services/deep_dive_task_manager.dart
// Solo Task Manager — Task Queue, Scheduling & Persistence
//
// Manages the complete lifecycle of Solo Mode tasks:
//   - Priority-based scheduling (urgent > high > normal > low)
//   - Max concurrent execution limit (2 for mobile battery/thermal)
//   - Task persistence across app restarts via SharedPreferences
//   - Task history with retention policies
//   - Queue status monitoring and reporting
//
// This works alongside [DeepDiveModeService] which handles the actual
// isolate spawning. TaskManager focuses on WHEN to run tasks,
// DeepDiveModeService focuses on HOW to run them.

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/error_handler.dart';
import '../models/self_use_session.dart';
import 'deep_dive_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Solo Task Manager
// ═══════════════════════════════════════════════════════════════════════════════

/// Manages the queue, scheduling, and persistence of Solo Mode tasks.
///
/// The [DeepDiveTaskManager] sits above [DeepDiveModeService] and controls
/// which tasks run and when. It provides:
///
/// - **Priority scheduling**: Higher priority tasks run first.
/// - **Concurrency limiting**: Max 2 simultaneous tasks on mobile
///   to preserve battery life and avoid thermal throttling.
/// - **Persistence**: Tasks survive app restarts via SharedPreferences.
/// - **History**: Retains last 50 completed tasks for review.
///
/// ## Usage
///
/// ```dart
/// await DeepDiveTaskManager.initialize();
///
/// // Queue a task — it will run when capacity is available
/// await DeepDiveTaskManager().enqueue(task);
///
/// // Check queue status
/// final status = DeepDiveTaskManager().getStatus();
/// print('Running: ${status.running}, Queued: ${status.queued}');
/// ```
class DeepDiveTaskManager with ErrorLogging {
  DeepDiveTaskManager._internal();

  static final DeepDiveTaskManager _instance = DeepDiveTaskManager._internal();

  /// Get the singleton instance.
  factory DeepDiveTaskManager() => _instance;

  @override
  String get logTag => 'DeepDiveTaskManager';

  // ── Configuration ──────────────────────────────────────────────────────────

  /// Maximum number of concurrently running tasks.
  /// Set to 2 on mobile to balance performance with battery life.
  static const int _maxConcurrent = 2;

  /// Maximum number of completed tasks to retain in history.
  static const int _maxHistorySize = 50;

  /// SharedPreferences key for persisting the task queue.
  static const String _prefsKeyQueue = 'deep_dive_task_queue';

  /// SharedPreferences key for persisting task history.
  static const String _prefsKeyHistory = 'deep_dive_task_history';

  /// SharedPreferences key for persisting running tasks.
  static const String _prefsKeyRunning = 'deep_dive_running_tasks';

  // ── State ──────────────────────────────────────────────────────────────────

  /// Tasks waiting to be executed, ordered by priority.
  final List<DeepDiveTask> _queue = [];

  /// Tasks currently running.
  final List<DeepDiveTask> _running = [];

  /// Completed task history (newest first).
  final List<DeepDiveTask> _history = [];

  /// Whether the manager has been initialized.
  bool _initialized = false;

  /// SharedPreferences instance for persistence.
  SharedPreferences? _prefs;

  /// Timer for periodic queue processing.
  Timer? _queueProcessorTimer;

  /// Stream controller for queue status updates.
  final StreamController<QueueStatus> _statusController =
      StreamController<QueueStatus>.broadcast();

  /// Stream controller for task list changes.
  final StreamController<void> _tasksChangedController =
      StreamController<void>.broadcast();

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Initialize the task manager.
  ///
  /// Must be called once during app startup. Loads persisted tasks
  /// and starts the queue processor.
  Future<void> initialize() async {
    if (_initialized) {
      logDebug('DeepDiveTaskManager already initialized');
      return;
    }

    try {
      _prefs = await SharedPreferences.getInstance();
      await restore();

      // Start periodic queue processor.
      _queueProcessorTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _processQueue(),
      );

      _initialized = true;
      logInfo('=== DeepDiveTaskManager initialized ===');
      logInfo('Queue: ${_queue.length}, Running: ${_running.length}, '
          'History: ${_history.length}');
    } catch (e, st) {
      logError('Failed to initialize DeepDiveTaskManager', e, st);
    }
  }

  /// Whether the manager has been initialized.
  bool get isInitialized => _initialized;

  // ── Task Enqueueing ────────────────────────────────────────────────────────

  /// Add a task to the queue.
  ///
  /// The task will be scheduled based on its priority and the
  /// current queue state. If there is capacity, it may start
  /// running immediately.
  ///
  /// Returns the enqueued task with any assigned queue metadata.
  Future<void> enqueue(DeepDiveTask task) async {
    if (!_initialized) {
      throw AppException.validationError(
        message: 'DeepDiveTaskManager not initialized. Call initialize() first.',
      );
    }

    // Insert into queue maintaining priority order.
    final insertIndex = _queue.indexWhere(
      (t) => t.priority.index < task.priority.index,
    );
    if (insertIndex == -1) {
      _queue.add(task);
    } else {
      _queue.insert(insertIndex, task);
    }

    logInfo(
      'Task enqueued: "${task.title}" (${task.priority.name}, '
      'queue position: $insertIndex)',
    );

    await persist();
    _notifyTasksChanged();

    // Try to start the task immediately if we have capacity.
    await _processQueue();
  }

  /// Create and enqueue a new task from raw parameters.
  ///
  /// This is a convenience method that creates a [DeepDiveTask] and
  /// immediately enqueues it.
  Future<DeepDiveTask> createAndEnqueue({
    required String title,
    required String description,
    required List<SelfAction> actions,
    SoloPriority priority = SoloPriority.normal,
  }) async {
    final task = DeepDiveTask(
      id: _generateTaskId(),
      title: title,
      description: description,
      actions: actions,
      priority: priority,
      status: DeepDiveTaskStatus.queued,
      submittedAt: DateTime.now(),
    );
    await enqueue(task);
    return task;
  }

  /// Create and enqueue a task from an existing [SelfUseSession].
  Future<DeepDiveTask> enqueueSession(SelfUseSession session,
      {SoloPriority priority = SoloPriority.normal}) async {
    return createAndEnqueue(
      title: session.userRequest,
      description: session.planDescription ??
          'Executing ${session.plannedActions.length} planned actions',
      actions: session.plannedActions,
      priority: priority,
    );
  }

  // ── Queue Processing ───────────────────────────────────────────────────────

  /// Process the queue — start the next available task if capacity allows.
  ///
  /// This is called automatically by the periodic timer, but can also
  /// be called manually to trigger immediate processing.
  Future<void> processQueue() async {
    if (!_initialized) return;
    await _processQueue();
  }

  void _processQueue() async {
    if (_queue.isEmpty) return;

    // Check if we have capacity to start more tasks.
    while (_running.length < _maxConcurrent && _queue.isNotEmpty) {
      final nextTask = _queue.removeAt(0);

      // Move from queue to running.
      _running.add(nextTask);

      logInfo(
        'Starting queued task: "${nextTask.title}" '
        '(running: ${_running.length}/$_maxConcurrent)',
      );

      // Delegate actual execution to DeepDiveModeService.
      try {
        final service = DeepDiveModeService();
        final task = await service.submitTask(
          title: nextTask.title,
          description: nextTask.description,
          actions: nextTask.actions,
          priority: nextTask.priority,
        );

        // Transfer the service-assigned ID back.
        nextTask.status = task.status;
        nextTask.startedAt = task.startedAt;

        // Listen for task completion to remove from running list.
        _watchTask(task);
      } catch (e, st) {
        logError('Failed to start queued task "${nextTask.title}"', e, st);
        nextTask.status = DeepDiveTaskStatus.failed;
        nextTask.errorMessage = 'Failed to start: $e';
        _running.remove(nextTask);
        _history.insert(0, nextTask);
      }

      await persist();
      _notifyTasksChanged();
    }

    // Emit updated status.
    _statusController.add(getStatus());
  }

  /// Watch a task running through DeepDiveModeService and update our
  /// running list when it completes.
  void _watchTask(DeepDiveTask serviceTask) {
    DeepDiveModeService().taskEvents.listen((event) {
      if (event.taskId != serviceTask.id) return;

      if (event.type == DeepDiveTaskEventType.completed ||
          event.type == DeepDiveTaskEventType.failed ||
          event.type == DeepDiveTaskEventType.cancelled) {
        // Remove from running and add to history.
        final ourTask = _running.firstWhere(
          (t) => t.title == serviceTask.title,
          orElse: () => null as DeepDiveTask,
        );
        if (ourTask != null) {
          _running.remove(ourTask);
          _addToHistory(ourTask);
          persist();
          _notifyTasksChanged();
          _statusController.add(getStatus());
        }
      }
    });
  }

  // ── Task Control ───────────────────────────────────────────────────────────

  /// Remove a task from the queue (before it starts running).
  ///
  /// Returns `true` if the task was found and removed.
  bool dequeue(String taskId) {
    final index = _queue.indexWhere((t) => t.id == taskId);
    if (index == -1) return false;

    final task = _queue.removeAt(index);
    logInfo('Task dequeued: "${task.title}"');

    persist();
    _notifyTasksChanged();
    return true;
  }

  /// Cancel a running task.
  ///
  /// Finds the task in the running list and cancels it through
  /// [DeepDiveModeService].
  void cancelRunning(String taskId) {
    final task = _running.firstWhere(
      (t) => t.id == taskId,
      orElse: () => null as DeepDiveTask,
    );
    if (task == null) return;

    DeepDiveModeService().cancelTask(taskId);
    _running.remove(task);
    _addToHistory(task);

    persist();
    _notifyTasksChanged();
    _statusController.add(getStatus());
  }

  /// Pause a running task.
  void pauseTask(String taskId) {
    DeepDiveModeService().pauseTask(taskId);
  }

  /// Resume a paused task.
  void resumeTask(String taskId) {
    DeepDiveModeService().resumeTask(taskId);
  }

  // ── Queries ────────────────────────────────────────────────────────────────

  /// Get the current queue status.
  QueueStatus getStatus() => QueueStatus(
        queued: _queue.length,
        running: _running.length,
        maxConcurrent: _maxConcurrent,
        totalPending: _queue.length + _running.length,
        hasCapacity: _running.length < _maxConcurrent,
      );

  /// Get all queued tasks.
  List<DeepDiveTask> get queuedTasks => List.unmodifiable(_queue);

  /// Get all currently running tasks.
  List<DeepDiveTask> get runningTasks => List.unmodifiable(_running);

  /// Get task history (completed, failed, cancelled — newest first).
  List<DeepDiveTask> get history => List.unmodifiable(_history);

  /// Get all tasks across all states.
  List<DeepDiveTask> get allTasks => [
        ..._running,
        ..._queue,
        ..._history,
      ];

  /// Find a task by ID across all states.
  DeepDiveTask? findTask(String taskId) {
    for (final task in _queue) {
      if (task.id == taskId) return task;
    }
    for (final task in _running) {
      if (task.id == taskId) return task;
    }
    for (final task in _history) {
      if (task.id == taskId) return task;
    }
    return null;
  }

  /// Whether the queue is empty (no queued or running tasks).
  bool get isIdle => _queue.isEmpty && _running.isEmpty;

  /// Whether there are tasks currently being processed.
  bool get isBusy => _running.isNotEmpty;

  /// Total number of tasks across all states.
  int get totalTaskCount => _queue.length + _running.length + _history.length;

  // ── Streams ────────────────────────────────────────────────────────────────

  /// Stream of queue status updates.
  Stream<QueueStatus> get statusUpdates => _statusController.stream;

  /// Stream that emits whenever the task list changes.
  Stream<void> get onTasksChanged => _tasksChangedController.stream;

  // ── Persistence ────────────────────────────────────────────────────────────

  /// Persist the current queue, running tasks, and history to disk.
  ///
  /// Uses SharedPreferences to store task data as JSON. This ensures
  /// tasks survive app restarts.
  Future<void> persist() async {
    if (_prefs == null) return;

    try {
      final queueJson = _queue.map((t) => _taskToJson(t)).toList();
      final runningJson = _running.map((t) => _taskToJson(t)).toList();
      final historyJson = _history.map((t) => _taskToJson(t)).toList();

      await _prefs!.setString(_prefsKeyQueue, jsonEncode(queueJson));
      await _prefs!.setString(_prefsKeyRunning, jsonEncode(runningJson));
      await _prefs!.setString(_prefsKeyHistory, jsonEncode(historyJson));

      logDebug(
        'Persisted: ${_queue.length} queued, ${_running.length} running, '
        '${_history.length} history',
      );
    } catch (e, st) {
      logError('Failed to persist tasks', e, st);
    }
  }

  /// Restore tasks from persistent storage.
  ///
  /// Called during initialization to recover tasks after an app restart.
  /// Tasks that were running are moved back to the queue since their
  /// isolates were killed when the app closed.
  Future<void> restore() async {
    if (_prefs == null) return;

    try {
      // Restore queue.
      final queueStr = _prefs!.getString(_prefsKeyQueue);
      if (queueStr != null) {
        final queueList = jsonDecode(queueStr) as List<dynamic>;
        _queue.clear();
        _queue.addAll(
          queueList.map((json) => _taskFromJson(json as Map<String, dynamic>)),
        );
      }

      // Restore running — move back to queue since isolates were killed.
      final runningStr = _prefs!.getString(_prefsKeyRunning);
      if (runningStr != null) {
        final runningList = jsonDecode(runningStr) as List<dynamic>;
        for (final json in runningList) {
          final task = _taskFromJson(json as Map<String, dynamic>);
          // Reset to queued since the isolate is gone.
          task.status = DeepDiveTaskStatus.queued;
          task.startedAt = null;
          _queue.add(task);
        }
        logInfo(
          'Restored ${runningList.length} previously running tasks to queue',
        );
      }

      // Restore history.
      final historyStr = _prefs!.getString(_prefsKeyHistory);
      if (historyStr != null) {
        final historyList = jsonDecode(historyStr) as List<dynamic>;
        _history.clear();
        _history.addAll(
          historyList.map((json) => _taskFromJson(json as Map<String, dynamic>)),
        );
      }

      logInfo(
        'Restored: ${_queue.length} queued, ${_history.length} history',
      );
    } catch (e, st) {
      logError('Failed to restore tasks', e, st);
      // Clear potentially corrupted data.
      _queue.clear();
      _running.clear();
      _history.clear();
    }
  }

  /// Clear all persisted task data.
  ///
  /// This permanently removes all queued, running, and historical
  /// tasks from persistent storage.
  Future<void> clearAll() async {
    _queue.clear();
    _running.clear();
    _history.clear();

    if (_prefs != null) {
      await _prefs!.remove(_prefsKeyQueue);
      await _prefs!.remove(_prefsKeyRunning);
      await _prefs!.remove(_prefsKeyHistory);
    }

    logInfo('All tasks cleared');
    _notifyTasksChanged();
    _statusController.add(getStatus());
  }

  // ── History Management ─────────────────────────────────────────────────────

  /// Clear only the task history (keep queue and running tasks).
  Future<void> clearHistory() async {
    final count = _history.length;
    _history.clear();
    await persist();
    _notifyTasksChanged();
    logInfo('History cleared ($count tasks removed)');
  }

  /// Add a task to history, respecting the max history size.
  void _addToHistory(DeepDiveTask task) {
    _history.insert(0, task);
    while (_history.length > _maxHistorySize) {
      _history.removeLast();
    }
  }

  // ── Private Helpers ────────────────────────────────────────────────────────

  void _notifyTasksChanged() {
    if (!_tasksChangedController.isClosed) {
      _tasksChangedController.add(null);
    }
  }

  String _generateTaskId() {
    return 'st_${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(10000)}';
  }

  final Random _random = Random();

  /// Serialize a task to JSON for persistence.
  Map<String, dynamic> _taskToJson(DeepDiveTask task) => {
        'id': task.id,
        'title': task.title,
        'description': task.description,
        'actions': task.actions.map((a) => a.toJson()).toList(),
        'priority': task.priority.index,
        'status': task.status.index,
        'submittedAt': task.submittedAt.toIso8601String(),
        'startedAt': task.startedAt?.toIso8601String(),
        'completedAt': task.completedAt?.toIso8601String(),
        'currentStep': task.currentStep,
        'currentActionDescription': task.currentActionDescription,
        'completedStepCount': task.completedStepCount,
        'failedStepCount': task.failedStepCount,
        'errorMessage': task.errorMessage,
      };

  /// Deserialize a task from JSON.
  DeepDiveTask _taskFromJson(Map<String, dynamic> json) {
    final actionsList = (json['actions'] as List<dynamic>? ?? [])
        .map((a) => SelfAction.fromJson(a as Map<String, dynamic>))
        .toList();

    return DeepDiveTask(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      actions: actionsList,
      priority: SoloPriority.values[(json['priority'] as int?) ?? 1],
      status: DeepDiveTaskStatus.values[(json['status'] as int?) ?? 0],
      submittedAt: DateTime.parse(json['submittedAt'] as String),
      startedAt: json['startedAt'] != null
          ? DateTime.parse(json['startedAt'] as String)
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
      currentStep: json['currentStep'] as int? ?? 0,
      currentActionDescription:
          json['currentActionDescription'] as String? ?? '',
      completedStepCount: json['completedStepCount'] as int? ?? 0,
      failedStepCount: json['failedStepCount'] as int? ?? 0,
      errorMessage: json['errorMessage'] as String?,
    );
  }

  // ── Diagnostics ────────────────────────────────────────────────────────────

  /// Get diagnostic information.
  Map<String, dynamic> getDiagnostics() {
    return {
      'initialized': _initialized,
      'queued': _queue.length,
      'running': _running.length,
      'history': _history.length,
      'maxConcurrent': _maxConcurrent,
      'hasCapacity': getStatus().hasCapacity,
      'isIdle': isIdle,
    };
  }

  /// Log diagnostics to the error handler.
  void logDiagnostics() {
    logInfo('=== DeepDiveTaskManager Diagnostics ===');
    getDiagnostics().forEach((key, value) {
      logInfo('  $key: $value');
    });
    for (final task in _queue) {
      logInfo('  [Q] ${task.id}: "${task.title}" (${task.priority.name})');
    }
    for (final task in _running) {
      logInfo('  [R] ${task.id}: "${task.title}" (${task.progressPercent}%)');
    }
    logInfo('=====================================');
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────

  /// Dispose all resources.
  void dispose() {
    logInfo('Disposing DeepDiveTaskManager...');
    _queueProcessorTimer?.cancel();
    _statusController.close();
    _tasksChangedController.close();
    _initialized = false;
    logInfo('DeepDiveTaskManager disposed');
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// QueueStatus — Immutable snapshot of queue state
// ═══════════════════════════════════════════════════════════════════════════════

/// Immutable snapshot of the Solo Task Manager's queue state.
///
/// Use this for UI binding — it provides a consistent, atomic view
/// of the queue at a point in time.
@immutable
class QueueStatus {
  /// Number of tasks waiting in the queue.
  final int queued;

  /// Number of tasks currently executing.
  final int running;

  /// Maximum number of concurrent tasks allowed.
  final int maxConcurrent;

  /// Total number of pending tasks (queued + running).
  final int totalPending;

  /// Whether there is capacity to start more tasks.
  final bool hasCapacity;

  const QueueStatus({
    required this.queued,
    required this.running,
    required this.maxConcurrent,
    required this.totalPending,
    required this.hasCapacity,
  });

  /// Whether all tasks are complete (nothing queued or running).
  bool get isIdle => queued == 0 && running == 0;

  /// Whether tasks are currently being processed.
  bool get isProcessing => running > 0;

  /// Whether the queue is at maximum capacity.
  bool get isAtCapacity => running >= maxConcurrent;

  /// Utilization as a fraction (0.0 - 1.0).
  double get utilization => maxConcurrent == 0 ? 0.0 : running / maxConcurrent;

  /// Utilization as a percentage (0 - 100).
  int get utilizationPercent => (utilization * 100).round();

  Map<String, dynamic> toJson() => {
        'queued': queued,
        'running': running,
        'maxConcurrent': maxConcurrent,
        'totalPending': totalPending,
        'hasCapacity': hasCapacity,
        'isIdle': isIdle,
        'utilizationPercent': utilizationPercent,
      };

  @override
  String toString() =>
      'QueueStatus(queued=$queued, running=$running/$maxConcurrent, '
      'utilization=${utilizationPercent}%)';
}
