// ignore_for_file: avoid_print

/// ============================================================================
/// Self-Use Session Models
/// ============================================================================
///
/// Represents a complete self-use session:
/// - User request (e.g. "Create a todo app")
/// - Plan (list of actions to execute)
/// - Execution results
/// - Real-time status tracking
///
/// Also includes [SelfAction] and [SelfActionResult] which are the building
/// blocks of a session.
/// ============================================================================

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Session Status
// ---------------------------------------------------------------------------

enum SessionStatus {
  /// Session created but not yet started planning.
  pending,

  /// AI is planning the sequence of actions.
  planning,

  /// Actions are being executed.
  executing,

  /// Execution paused (user intervention or error).
  paused,

  /// All actions completed successfully.
  completed,

  /// One or more actions failed.
  failed,
}

// ---------------------------------------------------------------------------
// SelfAction -- A single planned action
// ---------------------------------------------------------------------------

/// Represents one planned action within a [SelfUseSession].
///
/// An action has:
/// - A unique [id] for tracking.
/// - An [action] string in dotted format (e.g. `editor.writeCode`).
/// - A [params] map containing all arguments.
/// - An optional [description] explaining why this action is taken.
/// - An optional [dependsOn] list of action IDs that must complete first.
@immutable
class SelfAction {
  final String id;
  final String action;
  final Map<String, dynamic> params;
  final String? description;
  final List<String> dependsOn;

  const SelfAction({
    required this.id,
    required this.action,
    required this.params,
    this.description,
    this.dependsOn = const [],
  });

  /// Create from a JSON map.
  factory SelfAction.fromJson(Map<String, dynamic> json) {
    return SelfAction(
      id: json['id'] as String,
      action: json['action'] as String,
      params: (json['params'] as Map<String, dynamic>?) ?? const {},
      description: json['description'] as String?,
      dependsOn: (json['dependsOn'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );
  }

  /// Convert to a JSON map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'action': action,
        'params': params,
        'description': description,
        'dependsOn': dependsOn,
      };

  /// Dotted action category, e.g. `editor` from `editor.writeCode`.
  String get category => action.split('.').first;

  /// Dotted action verb, e.g. `writeCode` from `editor.writeCode`.
  String get verb => action.split('.').last;

  /// Whether this action depends on any other actions.
  bool get hasDependencies => dependsOn.isNotEmpty;

  @override
  String toString() => 'SelfAction($action, id=$id)';

  SelfAction copyWith({
    String? id,
    String? action,
    Map<String, dynamic>? params,
    String? description,
    List<String>? dependsOn,
  }) {
    return SelfAction(
      id: id ?? this.id,
      action: action ?? this.action,
      params: params ?? this.params,
      description: description ?? this.description,
      dependsOn: dependsOn ?? this.dependsOn,
    );
  }
}

// ---------------------------------------------------------------------------
// SelfActionResult -- Result of executing a single action
// ---------------------------------------------------------------------------

/// Result of executing a [SelfAction].
///
/// Contains:
/// - [actionId] reference back to the action.
/// - [success] flag.
/// - [data] returned by the handler (may be null).
/// - [error] message if the action failed.
/// - Timing information ([startedAt], [completedAt]).
@immutable
class SelfActionResult {
  final String actionId;
  final bool success;
  final dynamic data;
  final String? error;
  final DateTime startedAt;
  final DateTime? completedAt;

  const SelfActionResult({
    required this.actionId,
    required this.success,
    this.data,
    this.error,
    required this.startedAt,
    this.completedAt,
  });

  /// Duration of action execution.
  Duration get duration =>
      (completedAt ?? DateTime.now()).difference(startedAt);

  /// Whether this result has meaningful data.
  bool get hasData => data != null;

  /// Whether this result represents an error.
  bool get isError => !success && error != null;

  factory SelfActionResult.fromJson(Map<String, dynamic> json) {
    return SelfActionResult(
      actionId: json['actionId'] as String,
      success: json['success'] as bool,
      data: json['data'],
      error: json['error'] as String?,
      startedAt: DateTime.parse(json['startedAt'] as String),
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'actionId': actionId,
        'success': success,
        'data': data,
        'error': error,
        'startedAt': startedAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'durationMs': duration.inMilliseconds,
      };

  /// Create a successful result.
  factory SelfActionResult.success(String actionId, dynamic data,
      {DateTime? startedAt, DateTime? completedAt}) {
    return SelfActionResult(
      actionId: actionId,
      success: true,
      data: data,
      startedAt: startedAt ?? DateTime.now(),
      completedAt: completedAt ?? DateTime.now(),
    );
  }

  /// Create a failed result.
  factory SelfActionResult.failure(String actionId, String error,
      {DateTime? startedAt, DateTime? completedAt}) {
    return SelfActionResult(
      actionId: actionId,
      success: false,
      error: error,
      startedAt: startedAt ?? DateTime.now(),
      completedAt: completedAt ?? DateTime.now(),
    );
  }

  @override
  String toString() =>
      'SelfActionResult(id=$actionId, success=$success, duration=${duration.inMilliseconds}ms)';
}

// ---------------------------------------------------------------------------
// Session Log Entry -- For real-time streaming logs
// ---------------------------------------------------------------------------

enum LogLevel { debug, info, warning, error }

@immutable
class SessionLogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String? actionId;

  const SessionLogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.actionId,
  });

  factory SessionLogEntry.info(String message, {String? actionId}) {
    return SessionLogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.info,
      message: message,
      actionId: actionId,
    );
  }

  factory SessionLogEntry.error(String message, {String? actionId}) {
    return SessionLogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.error,
      message: message,
      actionId: actionId,
    );
  }

  factory SessionLogEntry.debug(String message, {String? actionId}) {
    return SessionLogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.debug,
      message: message,
      actionId: actionId,
    );
  }

  @override
  String toString() =>
      '[${timestamp.toIso8601String()}] ${level.name.toUpperCase()}: $message';
}

// ---------------------------------------------------------------------------
// SelfUseSession -- The main session model
// ---------------------------------------------------------------------------

/// Represents a complete self-use session.
///
/// A session captures the entire lifecycle of an AI-driven self-action:
/// 1. [userRequest] -- what the user asked for.
/// 2. [plannedActions] -- the AI-generated plan.
/// 3. [results] -- results of each executed action.
/// 4. [status] -- current execution state.
/// 5. [currentStep] -- index into [plannedActions].
class SelfUseSession {
  /// Unique session identifier.
  final String id;

  /// The original user request, e.g. "Create a todo app".
  final String userRequest;

  /// When the session was created.
  final DateTime createdAt;

  /// The AI-generated plan: ordered list of actions to execute.
  final List<SelfAction> plannedActions;

  /// Results of executed actions (grows as actions complete).
  final List<SelfActionResult> results;

  /// Current status of the session.
  SessionStatus status;

  /// Index of the action currently being executed (or next to execute).
  int currentStep;

  /// Optional human-readable plan description.
  final String? planDescription;

  /// Real-time log entries for UI streaming.
  final List<SessionLogEntry> logs;

  /// When planning started.
  DateTime? planningStartedAt;

  /// When execution started.
  DateTime? executionStartedAt;

  /// When the session completed or failed.
  DateTime? completedAt;

  SelfUseSession({
    required this.id,
    required this.userRequest,
    required this.plannedActions,
    this.planDescription,
  })  : createdAt = DateTime.now(),
        results = [],
        status = SessionStatus.pending,
        currentStep = 0,
        logs = [];

  // -- Computed Properties --------------------------------------------------

  /// Overall progress as a fraction (0.0 - 1.0).
  double get progress =>
      plannedActions.isEmpty ? 0.0 : currentStep / plannedActions.length;

  /// Progress as a percentage (0 - 100).
  int get progressPercent => (progress * 100).round();

  /// Whether the session is finished (successfully or with failure).
  bool get isComplete =>
      status == SessionStatus.completed ||
      status == SessionStatus.failed;

  /// Whether the session is currently running.
  bool get isActive => status == SessionStatus.executing;

  /// Whether the session is waiting for user input.
  bool get isPaused => status == SessionStatus.paused;

  /// Number of successfully completed steps.
  int get completedSteps => results.where((r) => r.success).length;

  /// Number of failed steps.
  int get failedSteps => results.where((r) => !r.success).length;

  /// Total elapsed time since session creation.
  Duration get elapsedTime => DateTime.now().difference(createdAt);

  /// Time spent in planning phase.
  Duration? get planningDuration =>
      (planningStartedAt != null && executionStartedAt != null)
          ? executionStartedAt!.difference(planningStartedAt!)
          : null;

  /// Time spent in execution phase.
  Duration? get executionDuration {
    if (executionStartedAt == null) return null;
    final end = completedAt ?? DateTime.now();
    return end.difference(executionStartedAt!);
  }

  /// The action currently being executed (or next to execute).
  SelfAction? get currentAction =>
      currentStep < plannedActions.length ? plannedActions[currentStep] : null;

  /// The next action after the current one.
  SelfAction? get nextAction =>
      currentStep + 1 < plannedActions.length
          ? plannedActions[currentStep + 1]
          : null;

  /// All remaining actions (including current).
  List<SelfAction> get remainingActions =>
      plannedActions.sublist(min(currentStep, plannedActions.length));

  /// Number of remaining actions.
  int get remainingCount => plannedActions.length - currentStep;

  /// Whether all planned actions have been executed.
  bool get allExecuted => currentStep >= plannedActions.length;

  /// Summary statistics for the session.
  SessionStats get stats => SessionStats(
        totalActions: plannedActions.length,
        completedActions: completedSteps,
        failedActions: failedSteps,
        elapsedMs: elapsedTime.inMilliseconds,
        progress: progress,
      );

  // -- Mutations ------------------------------------------------------------

  /// Advance to the next step.
  void advanceStep() {
    if (currentStep < plannedActions.length) {
      currentStep++;
    }
  }

  /// Record a result for the current (or specified) action.
  void recordResult(SelfActionResult result) {
    results.add(result);
  }

  /// Add a log entry.
  void addLog(SessionLogEntry entry) {
    logs.add(entry);
  }

  /// Mark session as started planning.
  void markPlanningStarted() {
    status = SessionStatus.planning;
    planningStartedAt = DateTime.now();
  }

  /// Mark session as started executing.
  void markExecutionStarted() {
    status = SessionStatus.executing;
    if (executionStartedAt == null) {
      executionStartedAt = DateTime.now();
    }
  }

  /// Mark session as paused.
  void markPaused() {
    status = SessionStatus.paused;
  }

  /// Mark session as completed.
  void markCompleted() {
    status = SessionStatus.completed;
    completedAt = DateTime.now();
  }

  /// Mark session as failed.
  void markFailed() {
    status = SessionStatus.failed;
    completedAt = DateTime.now();
  }

  /// Mark session as resumed from pause.
  void markResumed() {
    status = SessionStatus.executing;
  }

  // -- Serialization --------------------------------------------------------

  /// Convert to a summary JSON map (lightweight).
  Map<String, dynamic> toSummaryJson() => {
        'id': id,
        'userRequest': userRequest,
        'status': status.name,
        'progress': progress,
        'progressPercent': progressPercent,
        'currentStep': currentStep,
        'totalSteps': plannedActions.length,
        'completedSteps': completedSteps,
        'failedSteps': failedSteps,
        'elapsedMs': elapsedTime.inMilliseconds,
        'isComplete': isComplete,
      };

  /// Convert to full JSON map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'userRequest': userRequest,
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
        'planDescription': planDescription,
        'plannedActions': plannedActions.map((a) => a.toJson()).toList(),
        'results': results.map((r) => r.toJson()).toList(),
        'currentStep': currentStep,
        'progress': progress,
        'progressPercent': progressPercent,
        'elapsedMs': elapsedTime.inMilliseconds,
        'stats': stats.toJson(),
        'logs': logs
            .map((l) => {
                  'timestamp': l.timestamp.toIso8601String(),
                  'level': l.level.name,
                  'message': l.message,
                })
            .toList(),
      };

  @override
  String toString() =>
      'SelfUseSession(id=$id, status=${status.name}, progress=${(progress * 100).round()}%)';
}

// ---------------------------------------------------------------------------
// SessionStats -- Immutable summary statistics
// ---------------------------------------------------------------------------

@immutable
class SessionStats {
  final int totalActions;
  final int completedActions;
  final int failedActions;
  final int elapsedMs;
  final double progress;

  const SessionStats({
    required this.totalActions,
    required this.completedActions,
    required this.failedActions,
    required this.elapsedMs,
    required this.progress,
  });

  int get skippedActions => totalActions - completedActions - failedActions;

  double get successRate =>
      totalActions == 0 ? 0.0 : completedActions / totalActions;

  Map<String, dynamic> toJson() => {
        'totalActions': totalActions,
        'completedActions': completedActions,
        'failedActions': failedActions,
        'skippedActions': skippedActions,
        'elapsedMs': elapsedMs,
        'progress': progress,
        'successRate': successRate,
      };

  @override
  String toString() =>
      'SessionStats(total=$totalActions, completed=$completedActions, failed=$failedActions, ${(progress * 100).round()}%)';
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Generate a short unique ID for sessions and actions.
String generateSessionId() {
  final now = DateTime.now().millisecondsSinceEpoch;
  final random = Random().nextInt(9999).toString().padLeft(4, '0');
  return 'sess_${now}_$random';
}

/// Generate a short unique ID for individual actions.
String generateActionId() {
  final now = DateTime.now().millisecondsSinceEpoch;
  final random = Random().nextInt(999).toString().padLeft(3, '0');
  return 'act_${now}_$random';
}
