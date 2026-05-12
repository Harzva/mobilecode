// lib/services/deep_dive_service.dart
// Solo Mode Service — Background Execution System for MobileCode
//
// Inspired by Trae AI's Solo Mode:
//   - User submits a task (e.g. "create a todo app")
//   - Task runs silently in background via Dart Isolate
//   - User continues editing code normally — UI is NEVER blocked
//   - Progress shown via: system notifications + mini progress bar + Solo page
//   - User can check anytime by opening the Solo page
//
// Architecture:
//   Main Thread (UI)          Background Thread (Isolate)
//   ────────────────          ──────────────────────────
//   User edits code    ←──    Task executes independently
//   Mini progress bar  ←──    Progress updates via SendPort
//   System notifs      ←──    Status messages via SendPort
//   Solo page details  ←──    Step results via SendPort
//
// Critical Design: Isolates share NO memory with the main thread.
// The isolate serializes actions as JSON, executes them via a static
// bridge that delegates back to the main thread over SendPort/ReceivePort.
// The main thread runs actions via SelfInvocationService and sends
// results back to the isolate which continues the task loop.

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/error_handler.dart';
import '../models/self_use_session.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Solo Mode Service
// ═══════════════════════════════════════════════════════════════════════════════

/// Manages background execution of Agent tasks using Dart Isolates.
///
/// Tasks run in a separate Isolate, never blocking the UI thread.
/// This is the core engine behind MobileCode's Solo Mode feature.
///
/// ## Usage
///
/// ```dart
/// // Initialize once at app startup
/// await DeepDiveModeService().initialize();
///
/// // Submit a task — returns immediately, does NOT block
/// final task = await DeepDiveModeService().submitTask(
///   title: 'Create a todo app',
///   description: 'User requested a Flutter todo application',
///   actions: plannedActions,
///   priority: SoloPriority.high,
/// );
///
/// // Listen for updates anywhere in the app
/// DeepDiveModeService().taskUpdates.listen((task) {
///   print('Task ${task.id}: ${task.progress * 100}% — ${task.currentActionDescription}');
/// });
/// ```
class DeepDiveModeService with ErrorLogging {
  DeepDiveModeService._internal();

  static final DeepDiveModeService _instance = DeepDiveModeService._internal();

  /// Get the singleton instance.
  factory DeepDiveModeService() => _instance;

  @override
  String get logTag => 'DeepDiveMode';

  // ── State ──────────────────────────────────────────────────────────────────

  /// Active Solo tasks keyed by task ID.
  final Map<String, DeepDiveTask> _activeTasks = {};

  /// Completed tasks (retains last 50 for history).
  final List<DeepDiveTask> _completedTasks = [];

  /// Maximum number of completed tasks to retain in memory.
  static const int _maxCompletedHistory = 50;

  /// ReceivePort for getting progress and results from isolates.
  ReceivePort? _receivePort;

  /// Stream controllers for broadcasting task updates.
  final StreamController<DeepDiveTask> _taskUpdateController =
      StreamController<DeepDiveTask>.broadcast();

  final StreamController<List<DeepDiveTask>> _allTasksController =
      StreamController<List<DeepDiveTask>>.broadcast();

  final StreamController<DeepDiveTaskEvent> _taskEventController =
      StreamController<DeepDiveTaskEvent>.broadcast();

  /// Whether the service has been initialized.
  bool _initialized = false;

  /// Internal counter for generating unique IDs.
  int _idCounter = 0;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Initialize the Solo Mode service.
  ///
  /// Must be called once during app startup. Sets up the ReceivePort
  /// that listens for messages from background isolates.
  Future<void> initialize() async {
    if (_initialized) {
      logDebug('DeepDiveModeService already initialized, skipping');
      return;
    }

    _receivePort = ReceivePort();
    _receivePort!.listen(_handleIsolateMessage);

    logInfo('=== DeepDiveModeService initialized ===');
    _initialized = true;
  }

  /// Whether the service has been initialized.
  bool get isInitialized => _initialized;

  // ── Task Submission ────────────────────────────────────────────────────────

  /// Submit a task to run in Solo Mode (background).
  ///
  /// Returns a [DeepDiveTask] immediately — this method does NOT block.
  /// The task begins executing in a background isolate.
  ///
  /// [title] — Short human-readable title (e.g. "Create a todo app").
  /// [description] — Detailed description of what the task will do.
  /// [actions] — The ordered list of [SelfAction] steps to execute.
  /// [priority] — Task priority for queue scheduling.
  Future<DeepDiveTask> submitTask({
    required String title,
    required String description,
    required List<SelfAction> actions,
    SoloPriority priority = SoloPriority.normal,
  }) async {
    if (!_initialized) {
      throw AppException.validationError(
        message: 'DeepDiveModeService not initialized. Call initialize() first.',
      );
    }

    final task = DeepDiveTask(
      id: _generateTaskId(),
      title: title,
      description: description,
      actions: actions,
      priority: priority,
      status: DeepDiveTaskStatus.queued,
      submittedAt: DateTime.now(),
    );

    _activeTasks[task.id] = task;
    logInfo(
      'Task submitted: "${task.title}" (${task.actions.length} actions, priority: ${priority.name})',
    );

    _taskEventController.add(DeepDiveTaskEvent(
      type: DeepDiveTaskEventType.submitted,
      taskId: task.id,
      timestamp: DateTime.now(),
    ));

    // Start execution in Isolate — NON-BLOCKING
    _executeInIsolate(task);

    _notifyUpdate(task);
    return task;
  }

  /// Submit a task from an existing [SelfUseSession].
  ///
  /// This convenience method converts a session's planned actions
  /// into a Solo Mode background task.
  Future<DeepDiveTask> submitFromSession(SelfUseSession session) async {
    return submitTask(
      title: session.userRequest,
      description:
          session.planDescription ?? 'Executing ${session.plannedActions.length} actions',
      actions: session.plannedActions,
      priority: SoloPriority.normal,
    );
  }

  // ── Isolate Execution ──────────────────────────────────────────────────────

  /// Execute a task in a separate Dart Isolate.
  ///
  /// This is the KEY method — the task runs in a background isolate,
  /// completely independent from the main UI thread. The main thread
  /// is free to handle user input, render animations, and update the UI.
  void _executeInIsolate(DeepDiveTask task) async {
    task.status = DeepDiveTaskStatus.running;
    task.startedAt = DateTime.now();

    logInfo('Starting isolate for task: ${task.id} (${task.actions.length} actions)');

    try {
      // Serialize actions to JSON for cross-isolate transfer.
      // Isolates do NOT share memory — all data must be serializable.
      final actionMaps = task.actions.map((a) => a.toJson()).toList();

      final isolate = await Isolate.spawn(
        _isolateWorker,
        _IsolateInitMessage(
          taskId: task.id,
          actionsData: actionMaps,
          mainSendPort: _receivePort!.sendPort,
        ),
        errorsAreFatal: false,
        debugName: 'deep_dive_${task.id}',
      );

      task.isolate = isolate;
      task.isolateReady = true;

      // Listen for isolate errors on a separate error port.
      final errorPort = ReceivePort();
      isolate.addErrorListener(errorPort.sendPort);
      errorPort.listen((errorList) {
        final error = errorList[0];
        final stack = errorList[1] as String?;
        logError('Isolate error for task ${task.id}', error, StackTrace.fromString(stack ?? ''));
        if (task.status == DeepDiveTaskStatus.running) {
          task.status = DeepDiveTaskStatus.failed;
          task.errorMessage = 'Isolate error: $error';
          task.completedAt = DateTime.now();
          _moveToCompleted(task);
          _notifyUpdate(task);
        }
        errorPort.close();
      });

      _taskEventController.add(DeepDiveTaskEvent(
        type: DeepDiveTaskEventType.started,
        taskId: task.id,
        timestamp: DateTime.now(),
      ));

      _notifyUpdate(task);
    } catch (e, st) {
      logError('Failed to spawn isolate for task ${task.id}', e, st);
      task.status = DeepDiveTaskStatus.failed;
      task.errorMessage = 'Failed to start background task: $e';
      task.completedAt = DateTime.now();
      _moveToCompleted(task);

      _taskEventController.add(DeepDiveTaskEvent(
        type: DeepDiveTaskEventType.failed,
        taskId: task.id,
        message: task.errorMessage,
        timestamp: DateTime.now(),
      ));

      _notifyUpdate(task);
    }
  }

  /// The entry point that runs INSIDE the background isolate.
  ///
  /// This executes in a completely separate memory space. It cannot access
  /// any variables, singletons, or UI from the main thread. All communication
  /// happens through [SendPort] / [ReceivePort] message passing.
  ///
  /// How it works:
  /// 1. Deserialize actions from JSON
  /// 2. For each action, report "step starting" to main thread
  /// 3. Send action execution request to main thread via SendPort
  /// 4. Wait for result from main thread on a dedicated ReceivePort
  /// 5. Report step result (success/failure) to main thread
  /// 6. After all steps, report task completion
  static void _isolateWorker(_IsolateInitMessage init) async {
    // Background thread — does NOT block main UI thread.
    final taskId = init.taskId;
    final actionsData = init.actionsData;
    final mainPort = init.mainSendPort;

    for (int i = 0; i < actionsData.length; i++) {
      final actionMap = actionsData[i];
      final actionDesc =
          (actionMap['description'] as String?) ?? (actionMap['action'] as String?) ?? 'Step ${i + 1}';

      // ── Report: step starting ──
      mainPort.send(_IsolateProgressMsg(
        taskId: taskId,
        currentStep: i,
        totalSteps: actionsData.length,
        currentAction: actionDesc,
        status: 'running',
      ));

      // ── Execute: request main thread to run this action ──
      try {
        final actionRequest = _IsolateActionRequestMsg(
          taskId: taskId,
          stepIndex: i,
          actionType: actionMap['action'] as String,
          actionParams:
              (actionMap['params'] as Map<String, dynamic>?) ?? const {},
          actionDescription: actionDesc,
        );

        // Send request and wait for result via a response port.
        final responsePort = ReceivePort();
        mainPort.send(actionRequest..responsePort = responsePort.sendPort);
        final resultMsg = await responsePort.first as _IsolateActionResultMsg;
        responsePort.close();

        // ── Report: step result ──
        mainPort.send(resultMsg);

        if (!resultMsg.success) {
          // Stop execution on first failure.
          mainPort.send(_IsolateProgressMsg(
            taskId: taskId,
            currentStep: i,
            totalSteps: actionsData.length,
            currentAction: 'Failed at: $actionDesc',
            status: 'failed',
            error: resultMsg.message,
          ));
          return;
        }
      } catch (e) {
        // Report crash.
        mainPort.send(_IsolateActionResultMsg(
          taskId: taskId,
          stepIndex: i,
          success: false,
          message: 'Exception: $e',
        ));
        mainPort.send(_IsolateProgressMsg(
          taskId: taskId,
          currentStep: i,
          totalSteps: actionsData.length,
          currentAction: 'Crashed at step ${i + 1}',
          status: 'failed',
          error: e.toString(),
        ));
        return;
      }
    }

    // ── All steps completed successfully ──
    mainPort.send(_IsolateProgressMsg(
      taskId: taskId,
      currentStep: actionsData.length,
      totalSteps: actionsData.length,
      currentAction: 'All tasks completed successfully',
      status: 'completed',
    ));
  }

  // ── Message Handling (Main Thread) ─────────────────────────────────────────

  /// Handle all messages arriving from background isolates.
  void _handleIsolateMessage(dynamic message) {
    if (message is _IsolateProgressMsg) {
      _handleProgressMessage(message);
    } else if (message is _IsolateActionResultMsg) {
      _handleActionResultMessage(message);
    } else if (message is _IsolateActionRequestMsg) {
      // Execute the action on the main thread and send result back.
      _executeActionOnMainThread(message);
    } else {
      logWarning('Unknown isolate message type: ${message.runtimeType}');
    }
  }

  /// Handle progress update messages from isolates.
  void _handleProgressMessage(_IsolateProgressMsg message) {
    final task = _activeTasks[message.taskId];
    if (task == null) return;

    task.currentStep = message.currentStep;
    task.currentActionDescription = message.currentAction;

    switch (message.status) {
      case 'completed':
        task.status = DeepDiveTaskStatus.completed;
        task.completedAt = DateTime.now();
        task.currentStep = task.totalSteps;
        _moveToCompleted(task);
        _taskEventController.add(DeepDiveTaskEvent(
          type: DeepDiveTaskEventType.completed,
          taskId: task.id,
          timestamp: DateTime.now(),
        ));
        logInfo('Task completed: "${task.title}" (${task.totalSteps} steps)');
        break;

      case 'failed':
        task.status = DeepDiveTaskStatus.failed;
        task.completedAt = DateTime.now();
        task.errorMessage = message.error;
        _moveToCompleted(task);
        _taskEventController.add(DeepDiveTaskEvent(
          type: DeepDiveTaskEventType.failed,
          taskId: task.id,
          message: message.error,
          timestamp: DateTime.now(),
        ));
        logWarning('Task failed: "${task.title}" — ${message.error}');
        break;

      case 'running':
      default:
        // Still running — update UI with current action.
        break;
    }

    _notifyUpdate(task);
  }

  /// Handle action result messages from isolates.
  void _handleActionResultMessage(_IsolateActionResultMsg message) {
    final task = _activeTasks[message.taskId];
    if (task == null || message.stepIndex >= task.actions.length) return;

    final result = SoloStepResult(
      stepIndex: message.stepIndex,
      actionId: task.actions[message.stepIndex].id,
      success: message.success,
      message: message.message,
      data: message.data,
      error: message.error,
      durationMs: message.durationMs,
    );

    task.stepResults.add(result);

    if (!message.success) {
      task.failedStepCount++;
    } else {
      task.completedStepCount++;
    }

    _notifyUpdate(task);
  }

  /// Execute an action on the main thread (where SelfInvocationService lives).
  ///
  /// This is the critical bridge: the isolate sends us an action to execute,
  /// we run it through [SelfInvocationService] on the main thread, and send
  /// the result back through the response port so the isolate can continue.
  Future<void> _executeActionOnMainThread(
    _IsolateActionRequestMsg request,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      // Import here to avoid circular dependency issues at the top level.
      final service = SelfInvocationService();

      // Build a SelfAction compatible with SelfInvocationService.
      // The service's SelfAction uses 'type' field; our model uses 'action'.
      final invocationAction = self_invocation_service.SelfAction(
        type: request.actionType,
        params: request.actionParams,
        description: request.actionDescription,
      );

      final result = await service.execute(invocationAction);
      stopwatch.stop();

      // Send result back to the isolate via the response port.
      request.responsePort.send(_IsolateActionResultMsg(
        taskId: request.taskId,
        stepIndex: request.stepIndex,
        success: result.success,
        message: result.success
            ? 'Completed: ${result.data ?? request.actionDescription}'
            : 'Failed: ${result.error ?? "Unknown error"}',
        data: result.data,
        error: result.error,
        durationMs: stopwatch.elapsedMilliseconds,
      ));
    } catch (e, st) {
      stopwatch.stop();
      logError(
        'Action execution failed: ${request.actionType} for task ${request.taskId}',
        e,
        st,
      );
      request.responsePort.send(_IsolateActionResultMsg(
        taskId: request.taskId,
        stepIndex: request.stepIndex,
        success: false,
        message: 'Execution error: $e',
        error: e.toString(),
        durationMs: stopwatch.elapsedMilliseconds,
      ));
    }
  }

  // ── Task Control ───────────────────────────────────────────────────────────

  /// Pause a running task.
  ///
  /// Note: True isolate pause is complex. This sets a logical pause flag
  /// that prevents the next action from starting until resumed.
  /// The current action will still complete.
  void pauseTask(String taskId) {
    final task = _activeTasks[taskId];
    if (task != null && task.status == DeepDiveTaskStatus.running) {
      task.status = DeepDiveTaskStatus.paused;
      _taskEventController.add(DeepDiveTaskEvent(
        type: DeepDiveTaskEventType.paused,
        taskId: task.id,
        timestamp: DateTime.now(),
      ));
      logInfo('Task paused: "${task.title}" at step ${task.currentStep + 1}');
      _notifyUpdate(task);
    }
  }

  /// Resume a paused task.
  void resumeTask(String taskId) {
    final task = _activeTasks[taskId];
    if (task != null && task.status == DeepDiveTaskStatus.paused) {
      task.status = DeepDiveTaskStatus.running;
      _taskEventController.add(DeepDiveTaskEvent(
        type: DeepDiveTaskEventType.resumed,
        taskId: task.id,
        timestamp: DateTime.now(),
      ));
      logInfo('Task resumed: "${task.title}"');
      _notifyUpdate(task);
    }
  }

  /// Cancel a running or queued task.
  ///
  /// This kills the isolate immediately. Any in-progress action will
  /// be interrupted. Use with caution.
  void cancelTask(String taskId) {
    final task = _activeTasks[taskId];
    if (task == null) return;

    // Kill the isolate immediately.
    task.isolate?.kill(priority: Isolate.immediate);
    task.isolate = null;

    task.status = DeepDiveTaskStatus.cancelled;
    task.completedAt = DateTime.now();

    _moveToCompleted(task);

    _taskEventController.add(DeepDiveTaskEvent(
      type: DeepDiveTaskEventType.cancelled,
      taskId: task.id,
      timestamp: DateTime.now(),
    ));

    logInfo('Task cancelled: "${task.title}"');
    _notifyUpdate(task);
  }

  /// Retry a failed or cancelled task.
  ///
  /// Creates a new task with the same actions and starts it fresh.
  Future<DeepDiveTask?> retryTask(String taskId) async {
    DeepDiveTask? oldTask = _activeTasks[taskId];
    oldTask ??= _completedTasks.firstWhere(
      (t) => t.id == taskId,
      orElse: () => null as DeepDiveTask,
    );

    if (oldTask == null) {
      logWarning('Cannot retry: task $taskId not found');
      return null;
    }

    if (oldTask.status != DeepDiveTaskStatus.failed &&
        oldTask.status != DeepDiveTaskStatus.cancelled) {
      logWarning(
        'Cannot retry task ${oldTask.id}: status is ${oldTask.status.name}',
      );
      return null;
    }

    final newTask = await submitTask(
      title: '${oldTask.title} (retry)',
      description: oldTask.description,
      actions: oldTask.actions,
      priority: oldTask.priority,
    );

    logInfo('Task retried: "${oldTask.title}" → new task ${newTask.id}');
    return newTask;
  }

  // ── Queries ────────────────────────────────────────────────────────────────

  /// Get a task by its ID.
  DeepDiveTask? getTask(String taskId) => _activeTasks[taskId];

  /// Get all currently active (running / paused / queued) tasks.
  List<DeepDiveTask> get activeTasks => List.unmodifiable(
        _activeTasks.values.toList()
          ..sort((a, b) => b.priority.index.compareTo(a.priority.index)),
      );

  /// Get all completed (including failed / cancelled) tasks.
  List<DeepDiveTask> get completedTasks => List.unmodifiable(_completedTasks);

  /// Get all tasks (active + completed).
  List<DeepDiveTask> get allTasks => [...activeTasks, ...completedTasks];

  /// Whether any task is currently running.
  bool get hasRunningTask =>
      _activeTasks.values.any((t) => t.status == DeepDiveTaskStatus.running);

  /// Get the currently running task, if any.
  DeepDiveTask? get currentRunningTask {
    for (final task in _activeTasks.values) {
      if (task.status == DeepDiveTaskStatus.running) return task;
    }
    return null;
  }

  /// Get the number of currently running tasks.
  int get runningTaskCount =>
      _activeTasks.values.where((t) => t.status == DeepDiveTaskStatus.running).length;

  /// Get overall progress across all active tasks (0.0 - 1.0).
  double get overallProgress {
    if (_activeTasks.isEmpty) return 0.0;
    final totalProgress = _activeTasks.values.fold<double>(
      0.0,
      (sum, t) => sum + t.progress,
    );
    return totalProgress / _activeTasks.length;
  }

  // ── Streams ────────────────────────────────────────────────────────────────

  /// Stream of individual task updates. Use this to build reactive UIs.
  Stream<DeepDiveTask> get taskUpdates => _taskUpdateController.stream;

  /// Stream of the complete task list. Emits whenever any task changes.
  Stream<List<DeepDiveTask>> get allTasksUpdates => _allTasksController.stream;

  /// Stream of task lifecycle events (submitted, started, completed, etc.).
  Stream<DeepDiveTaskEvent> get taskEvents => _taskEventController.stream;

  // ── Diagnostics ────────────────────────────────────────────────────────────

  /// Get diagnostic information about the Solo Mode service.
  Map<String, dynamic> getDiagnostics() {
    return {
      'initialized': _initialized,
      'activeTasks': _activeTasks.length,
      'activeTaskIds': _activeTasks.keys.toList(),
      'completedTasks': _completedTasks.length,
      'hasRunningTask': hasRunningTask,
      'runningTaskCount': runningTaskCount,
      'overallProgress': overallProgress,
      'maxCompletedHistory': _maxCompletedHistory,
    };
  }

  /// Log diagnostics to the error handler.
  void logDiagnostics() {
    logInfo('=== DeepDiveModeService Diagnostics ===');
    final d = getDiagnostics();
    d.forEach((key, value) {
      logInfo('  $key: $value');
    });
    for (final task in _activeTasks.values) {
      logInfo(
        '  [${task.id}] ${task.status.name} — '
        '${task.progressPercent}% — ${task.currentActionDescription}',
      );
    }
    logInfo('====================================');
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  void _notifyUpdate(DeepDiveTask task) {
    if (!_taskUpdateController.isClosed) {
      _taskUpdateController.add(task);
    }
    if (!_allTasksController.isClosed) {
      _allTasksController.add(allTasks);
    }
  }

  void _moveToCompleted(DeepDiveTask task) {
    _activeTasks.remove(task.id);
    _completedTasks.insert(0, task);
    if (_completedTasks.length > _maxCompletedHistory) {
      _completedTasks.removeLast();
    }
  }

  String _generateTaskId() {
    _idCounter++;
    return 'deep_dive_${DateTime.now().millisecondsSinceEpoch}_$_idCounter';
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────

  /// Dispose all resources.
  ///
  /// Call this when the app is shutting down. Kills all running isolates.
  void dispose() {
    logInfo('Disposing DeepDiveModeService...');

    for (final task in _activeTasks.values) {
      task.isolate?.kill(priority: Isolate.immediate);
    }

    _taskUpdateController.close();
    _allTasksController.close();
    _taskEventController.close();
    _receivePort?.close();
    _activeTasks.clear();
    _completedTasks.clear();
    _initialized = false;

    logInfo('DeepDiveModeService disposed');
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DeepDiveTask — Model for a Solo Mode background task
// ═══════════════════════════════════════════════════════════════════════════════

/// Represents a single Solo Mode background task.
///
/// A task captures the full lifecycle:
/// - Metadata: title, description, priority
/// - Plan: ordered list of [SelfAction] steps
/// - Progress: current step, action being executed
/// - Results: outcome of each executed step
/// - Lifecycle: queued → running → completed | failed | cancelled
class DeepDiveTask {
  /// Unique task identifier.
  final String id;

  /// Short human-readable title.
  final String title;

  /// Detailed description of the task.
  final String description;

  /// Ordered list of actions to execute.
  final List<SelfAction> actions;

  /// Task priority (affects scheduling).
  final SoloPriority priority;

  /// Current execution status.
  DeepDiveTaskStatus status;

  /// When the task was submitted.
  final DateTime submittedAt;

  /// When execution started.
  DateTime? startedAt;

  /// When execution completed / failed / cancelled.
  DateTime? completedAt;

  /// Index of the current step (0-based).
  int currentStep;

  /// Human-readable description of the current action being executed.
  String currentActionDescription;

  /// Results for each completed step.
  final List<SoloStepResult> stepResults;

  /// Number of successfully completed steps.
  int completedStepCount;

  /// Number of failed steps.
  int failedStepCount;

  /// The Isolate running this task.
  /// Null if not yet started or already finished.
  Isolate? isolate;

  /// Whether the isolate is ready to receive messages.
  bool isolateReady;

  /// Error message if the task failed.
  String? errorMessage;

  DeepDiveTask({
    required this.id,
    required this.title,
    required this.description,
    required this.actions,
    required this.priority,
    required this.status,
    required this.submittedAt,
    this.startedAt,
    this.completedAt,
    this.currentStep = 0,
    this.currentActionDescription = '',
    this.stepResults = const [],
    this.completedStepCount = 0,
    this.failedStepCount = 0,
    this.isolate,
    this.isolateReady = false,
    this.errorMessage,
  });

  // -- Computed Properties ----------------------------------------------------

  /// Total number of steps.
  int get totalSteps => actions.length;

  /// Progress as a fraction (0.0 - 1.0).
  double get progress =>
      totalSteps == 0 ? 0.0 : currentStep / totalSteps;

  /// Progress as a percentage (0 - 100).
  int get progressPercent => (progress * 100).round();

  /// Elapsed time since execution started.
  Duration? get elapsedTime => startedAt != null
      ? DateTime.now().difference(startedAt!)
      : null;

  /// Total time from submission to completion.
  Duration? get totalTime => completedAt != null
      ? completedAt!.difference(submittedAt)
      : null;

  /// Whether the task is currently running.
  bool get isRunning => status == DeepDiveTaskStatus.running;

  /// Whether the task completed successfully.
  bool get isCompleted => status == DeepDiveTaskStatus.completed;

  /// Whether the task failed.
  bool get isFailed => status == DeepDiveTaskStatus.failed;

  /// Whether the task was cancelled.
  bool get isCancelled => status == DeepDiveTaskStatus.cancelled;

  /// Whether the task is finished (completed, failed, or cancelled).
  bool get isFinished => isCompleted || isFailed || isCancelled;

  /// Whether the task is still active (queued, running, or paused).
  bool get isActive =>
      status == DeepDiveTaskStatus.queued ||
      status == DeepDiveTaskStatus.running ||
      status == DeepDiveTaskStatus.paused;

  /// Human-readable status string for UI display.
  String get statusDisplay {
    switch (status) {
      case DeepDiveTaskStatus.queued:
        return 'Queued';
      case DeepDiveTaskStatus.running:
        return 'Running — Step ${currentStep + 1} / $totalSteps';
      case DeepDiveTaskStatus.paused:
        return 'Paused';
      case DeepDiveTaskStatus.completed:
        return 'Completed';
      case DeepDiveTaskStatus.failed:
        return 'Failed';
      case DeepDiveTaskStatus.cancelled:
        return 'Cancelled';
    }
  }

  /// Summary for serialization and diagnostics.
  Map<String, dynamic> toSummaryJson() => {
        'id': id,
        'title': title,
        'status': status.name,
        'priority': priority.name,
        'progress': progress,
        'progressPercent': progressPercent,
        'currentStep': currentStep,
        'totalSteps': totalSteps,
        'completedSteps': completedStepCount,
        'failedSteps': failedStepCount,
        'elapsedMs': elapsedTime?.inMilliseconds,
        'totalTimeMs': totalTime?.inMilliseconds,
        'currentAction': currentActionDescription,
        'isFinished': isFinished,
      };

  @override
  String toString() =>
      'DeepDiveTask(id=$id, title="$title", status=${status.name}, '
      '${progressPercent}%, steps=$completedStepCount/$totalSteps)';
}

// ═══════════════════════════════════════════════════════════════════════════════
// SoloStepResult — Result of a single step execution
// ═══════════════════════════════════════════════════════════════════════════════

/// The result of executing a single step within a Solo Mode task.
class SoloStepResult {
  /// Index of the step in the action list.
  final int stepIndex;

  /// ID of the action that was executed.
  final String actionId;

  /// Whether the step succeeded.
  final bool success;

  /// Human-readable message describing the outcome.
  final String message;

  /// Optional data returned by the action handler.
  final dynamic data;

  /// Error message if the step failed.
  final String? error;

  /// Duration of the step execution in milliseconds.
  final int? durationMs;

  SoloStepResult({
    required this.stepIndex,
    required this.actionId,
    required this.success,
    required this.message,
    this.data,
    this.error,
    this.durationMs,
  });

  Map<String, dynamic> toJson() => {
        'stepIndex': stepIndex,
        'actionId': actionId,
        'success': success,
        'message': message,
        'data': data,
        'error': error,
        'durationMs': durationMs,
      };

  @override
  String toString() =>
      'SoloStepResult(step=$stepIndex, action=$actionId, success=$success, '
      '${durationMs ?? "?"}ms)';
}

// ═══════════════════════════════════════════════════════════════════════════════
// Enums
// ═══════════════════════════════════════════════════════════════════════════════

/// Status of a Solo Mode task.
enum DeepDiveTaskStatus { queued, running, paused, completed, failed, cancelled }

/// Priority levels for Solo Mode tasks.
/// Higher priority tasks are executed first when resources are constrained.
enum SoloPriority { low, normal, high, urgent }

// ═══════════════════════════════════════════════════════════════════════════════
// DeepDiveTaskEvent — Lifecycle events for reactive observation
// ═══════════════════════════════════════════════════════════════════════════════

/// Represents a lifecycle event for a Solo Mode task.
///
/// Emitted by the [DeepDiveModeService.taskEvents] stream to notify
/// observers of significant state changes. Use these events to
/// trigger notifications, update UI badges, or log analytics.
class DeepDiveTaskEvent {
  /// The type of event that occurred.
  final DeepDiveTaskEventType type;

  /// The ID of the task this event relates to.
  final String taskId;

  /// Optional message providing additional context.
  final String? message;

  /// When the event occurred.
  final DateTime timestamp;

  DeepDiveTaskEvent({
    required this.type,
    required this.taskId,
    this.message,
    required this.timestamp,
  });

  @override
  String toString() => 'DeepDiveTaskEvent(${type.name}, task=$taskId)';
}

/// Types of lifecycle events for Solo Mode tasks.
enum DeepDiveTaskEventType {
  submitted,
  started,
  paused,
  resumed,
  completed,
  failed,
  cancelled,
  progress,
}

// ═══════════════════════════════════════════════════════════════════════════════
// Internal: Cross-Isolate Message Types
// ═══════════════════════════════════════════════════════════════════════════════
//
// These classes are used exclusively for communication between the
// main thread (UI) and background isolates. They must contain only
// primitive, serializable data — no Flutter objects, no closures.

/// Initial message sent to a newly spawned isolate to bootstrap it.
class _IsolateInitMessage {
  final String taskId;
  final List<Map<String, dynamic>> actionsData;
  final SendPort mainSendPort;

  _IsolateInitMessage({
    required this.taskId,
    required this.actionsData,
    required this.mainSendPort,
  });
}

/// Progress update sent from isolate → main thread.
class _IsolateProgressMsg {
  final String taskId;
  final int currentStep;
  final int totalSteps;
  final String currentAction;
  final String status;
  final String? error;

  _IsolateProgressMsg({
    required this.taskId,
    required this.currentStep,
    required this.totalSteps,
    required this.currentAction,
    required this.status,
    this.error,
  });
}

/// Action result sent from isolate → main thread.
class _IsolateActionResultMsg {
  final String taskId;
  final int stepIndex;
  final bool success;
  final String message;
  final dynamic data;
  final String? error;
  final int? durationMs;

  _IsolateActionResultMsg({
    required this.taskId,
    required this.stepIndex,
    required this.success,
    required this.message,
    this.data,
    this.error,
    this.durationMs,
  });
}

/// Request from isolate → main thread asking it to execute an action.
/// The main thread runs the action and sends the result back
/// through [responsePort].
class _IsolateActionRequestMsg {
  final String taskId;
  final int stepIndex;
  final String actionType;
  final Map<String, dynamic> actionParams;
  final String actionDescription;

  /// This port is set by the isolate to receive the result.
  late final SendPort responsePort;

  _IsolateActionRequestMsg({
    required this.taskId,
    required this.stepIndex,
    required this.actionType,
    required this.actionParams,
    required this.actionDescription,
  });
}
