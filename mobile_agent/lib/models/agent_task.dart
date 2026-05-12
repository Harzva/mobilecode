// lib/models/agent_task.dart
// Agent Task Models
//
// Represents a task plan with steps, progress, and agent assignments.
// Used by the task plan sidebar and agent orchestrator to track
// multi-agent execution in real-time.

import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Enums
// ═══════════════════════════════════════════════════════════════════════════

/// Overall status of a task plan.
enum TaskPlanStatus {
  /// Plan created but not yet started.
  pending,

  /// Plan is actively executing.
  running,

  /// Execution paused by user.
  paused,

  /// All steps completed successfully.
  completed,

  /// One or more steps failed.
  failed,
}

/// Status of an individual task step.
enum StepStatus {
  /// Step is waiting to be executed.
  pending,

  /// Step is currently being executed.
  running,

  /// Step completed successfully.
  completed,

  /// Step failed with an error.
  failed,

  /// Step was intentionally skipped.
  skipped,
}

/// Log level for step execution logs.
enum LogLevel {
  /// Informational message.
  info,

  /// Warning message (non-fatal).
  warning,

  /// Error message (fatal to step).
  error,
}

/// State of an agent worker process.
enum AgentState {
  /// Agent is idle, waiting for assignment.
  idle,

  /// Agent is analyzing/planning.
  thinking,

  /// Agent is actively executing a task.
  working,

  /// Agent encountered an error.
  error,
}

// ═══════════════════════════════════════════════════════════════════════════
// Step Log
// ═══════════════════════════════════════════════════════════════════════════

/// A single log entry from a step's execution.
///
/// Provides timestamped, leveled logging for debugging and monitoring.
class StepLog {
  /// When the log was created.
  final DateTime timestamp;

  /// Severity level of the log.
  final LogLevel level;

  /// Log message content.
  final String message;

  const StepLog({
    required this.timestamp,
    required this.level,
    required this.message,
  });

  /// Create an info-level log.
  factory StepLog.info(String message) => StepLog(
        timestamp: DateTime.now(),
        level: LogLevel.info,
        message: message,
      );

  /// Create a warning-level log.
  factory StepLog.warning(String message) => StepLog(
        timestamp: DateTime.now(),
        level: LogLevel.warning,
        message: message,
      );

  /// Create an error-level log.
  factory StepLog.error(String message) => StepLog(
        timestamp: DateTime.now(),
        level: LogLevel.error,
        message: message,
      );

  /// Get color associated with this log level.
  Color get color {
    switch (level) {
      case LogLevel.info:
        return const Color(0xFFF0F0F5);
      case LogLevel.warning:
        return const Color(0xFFF59E0B);
      case LogLevel.error:
        return const Color(0xFFEF4444);
    }
  }

  /// Format timestamp as HH:MM:SS.mmm
  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  /// Short level indicator for compact display.
  String get levelIndicator {
    switch (level) {
      case LogLevel.info:
        return 'I';
      case LogLevel.warning:
        return 'W';
      case LogLevel.error:
        return 'E';
    }
  }

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'level': level.name,
        'message': message,
      };

  @override
  String toString() => '[$formattedTime $levelIndicator] $message';
}

// ═══════════════════════════════════════════════════════════════════════════
// Task Step
// ═══════════════════════════════════════════════════════════════════════════

/// A single step within a task plan.
///
/// Each step represents an atomic unit of work that can be assigned
/// to a specific agent for execution.
class TaskStep {
  /// Unique step identifier.
  final String id;

  /// Step order number (1, 2, 3...).
  final int order;

  /// Short step title.
  final String title;

  /// Detailed step description.
  final String description;

  /// Current execution status.
  final StepStatus status;

  /// ID of the agent assigned to this step.
  final String? assignedAgentId;

  /// The action to execute (from agent_action_system.dart).
  final dynamic action;

  /// When the step started executing.
  final DateTime? startedAt;

  /// When the step finished executing.
  final DateTime? completedAt;

  /// Success message or error description.
  final String? result;

  /// Real-time execution logs.
  final List<StepLog> logs;

  const TaskStep({
    required this.id,
    required this.order,
    required this.title,
    required this.description,
    this.status = StepStatus.pending,
    this.assignedAgentId,
    this.action,
    this.startedAt,
    this.completedAt,
    this.result,
    this.logs = const [],
  });

  // ── Computed Properties ───────────────────────────────────────────────

  /// Duration of step execution (if completed or running).
  Duration? get duration {
    if (startedAt == null) return null;
    final end = completedAt ?? DateTime.now();
    return end.difference(startedAt!);
  }

  /// Formatted duration string (e.g. "2.3s" or "1m 45s").
  String get durationFormatted {
    final d = duration;
    if (d == null) return '--';
    if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${(d.inSeconds % 60).toString().padLeft(2, '0')}s';
    }
    return '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';
  }

  /// Whether this step is currently running.
  bool get isRunning => status == StepStatus.running;

  /// Whether this step has completed (success, failed, or skipped).
  bool get isDone =>
      status == StepStatus.completed ||
      status == StepStatus.failed ||
      status == StepStatus.skipped;

  /// Color associated with this step's status.
  Color get statusColor {
    switch (status) {
      case StepStatus.pending:
        return const Color(0xFF6B7280);
      case StepStatus.running:
        return const Color(0xFF7B2FF7);
      case StepStatus.completed:
        return const Color(0xFF10B981);
      case StepStatus.failed:
        return const Color(0xFFEF4444);
      case StepStatus.skipped:
        return const Color(0xFF4B5563);
    }
  }

  // ── Copy with ─────────────────────────────────────────────────────────

  TaskStep copyWith({
    StepStatus? status,
    String? result,
    DateTime? startedAt,
    DateTime? completedAt,
    List<StepLog>? logs,
    String? assignedAgentId,
  }) {
    return TaskStep(
      id: id,
      order: order,
      title: title,
      description: description,
      status: status ?? this.status,
      assignedAgentId: assignedAgentId ?? this.assignedAgentId,
      action: action,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      result: result ?? this.result,
      logs: logs ?? this.logs,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'order': order,
        'title': title,
        'description': description,
        'status': status.name,
        'assignedAgentId': assignedAgentId,
        'startedAt': startedAt?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'result': result,
        'logs': logs.map((l) => l.toJson()).toList(),
      };

  @override
  String toString() => 'TaskStep[$order: $title] (${status.name})';
}

// ═══════════════════════════════════════════════════════════════════════════
// Task Plan
// ═══════════════════════════════════════════════════════════════════════════

/// A complete task plan with multiple steps.
///
/// Represents the supervisor's decomposition of a user request into
/// actionable steps that can be distributed to worker agents.
class TaskPlan {
  /// Unique plan identifier.
  final String id;

  /// Plan title (e.g. "Create Bookkeeping App").
  final String title;

  /// Plan description from user request.
  final String description;

  /// Overall plan status.
  final TaskPlanStatus status;

  /// All steps in the plan.
  final List<TaskStep> steps;

  /// When the plan was created.
  final DateTime createdAt;

  /// When execution started.
  final DateTime? startedAt;

  /// When execution finished.
  final DateTime? completedAt;

  /// Overall progress (0.0 - 1.0).
  final double progress;

  const TaskPlan({
    required this.id,
    required this.title,
    required this.description,
    this.status = TaskPlanStatus.pending,
    this.steps = const [],
    required this.createdAt,
    this.startedAt,
    this.completedAt,
    this.progress = 0.0,
  });

  // ── Computed Properties ───────────────────────────────────────────────

  /// Number of completed steps.
  int get completedSteps =>
      steps.where((s) => s.status == StepStatus.completed).length;

  /// Total number of steps.
  int get totalSteps => steps.length;

  /// Number of failed steps.
  int get failedSteps =>
      steps.where((s) => s.status == StepStatus.failed).length;

  /// Number of currently running steps.
  int get runningSteps =>
      steps.where((s) => s.status == StepStatus.running).length;

  /// Number of pending steps.
  int get pendingSteps =>
      steps.where((s) => s.status == StepStatus.pending).length;

  /// Elapsed time since execution started.
  Duration? get elapsedTime {
    if (startedAt == null) return null;
    return DateTime.now().difference(startedAt!);
  }

  /// Estimated time of arrival (based on average step duration).
  Duration? get estimatedTimeRemaining {
    if (startedAt == null || completedSteps == 0) return null;
    final elapsed = elapsedTime;
    if (elapsed == null) return null;
    final avgPerStep = elapsed.inSeconds / completedSteps;
    final remaining = pendingSteps + runningSteps;
    return Duration(seconds: (avgPerStep * remaining).round());
  }

  /// Whether the plan is currently active (running).
  bool get isActive => status == TaskPlanStatus.running;

  /// Whether the plan is in a terminal state.
  bool get isTerminal =>
      status == TaskPlanStatus.completed || status == TaskPlanStatus.failed;

  /// Formatted elapsed time string.
  String get elapsedTimeFormatted {
    final d = elapsedTime;
    if (d == null) return '00:00';
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Formatted ETA string.
  String get etaFormatted {
    final eta = estimatedTimeRemaining;
    if (eta == null) return '--:--';
    final m = eta.inMinutes.toString().padLeft(2, '0');
    final s = (eta.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Copy with ─────────────────────────────────────────────────────────

  TaskPlan copyWith({
    TaskPlanStatus? status,
    List<TaskStep>? steps,
    DateTime? startedAt,
    DateTime? completedAt,
    double? progress,
  }) {
    return TaskPlan(
      id: id,
      title: title,
      description: description,
      status: status ?? this.status,
      steps: steps ?? this.steps,
      createdAt: createdAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      progress: progress ?? this.progress,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'status': status.name,
        'steps': steps.map((s) => s.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'startedAt': startedAt?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'progress': progress,
      };

  @override
  String toString() =>
      'TaskPlan[$id: $title] ($completedSteps/$totalSteps steps, ${(progress * 100).toStringAsFixed(0)}%)';
}

// ═══════════════════════════════════════════════════════════════════════════
// Agent Status
// ═══════════════════════════════════════════════════════════════════════════

/// Real-time status of a single agent worker.
///
/// Used by the agent dashboard to display what each agent is doing.
class AgentStatus {
  /// Unique agent identifier.
  final String agentId;

  /// Display name (e.g. "Code Expert" / "Debug Assistant").
  final String name;

  /// Icon identifier string.
  final String icon;

  /// Current agent state.
  final AgentState state;

  /// Description of what the agent is currently doing.
  final String? currentTask;

  /// Progress of current task (0.0 - 1.0), null if not working.
  final double? progress;

  /// When the current task started.
  final DateTime? taskStartedAt;

  /// Last 5 actions performed by this agent.
  final List<String> recentActions;

  /// Accent color for this agent's UI.
  final Color accentColor;

  const AgentStatus({
    required this.agentId,
    required this.name,
    required this.icon,
    required this.state,
    this.currentTask,
    this.progress,
    this.taskStartedAt,
    this.recentActions = const [],
    required this.accentColor,
  });

  // ── Computed Properties ───────────────────────────────────────────────

  /// Whether the agent is currently idle.
  bool get isIdle => state == AgentState.idle;

  /// Whether the agent is currently working.
  bool get isWorking => state == AgentState.working;

  /// Whether the agent is thinking/planning.
  bool get isThinking => state == AgentState.thinking;

  /// Whether the agent has encountered an error.
  bool get hasError => state == AgentState.error;

  /// How long the agent has been on the current task.
  Duration? get currentTaskDuration {
    if (taskStartedAt == null) return null;
    return DateTime.now().difference(taskStartedAt!);
  }

  /// Formatted task duration string.
  String get taskDurationFormatted {
    final d = currentTaskDuration;
    if (d == null) return '--';
    if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${(d.inSeconds % 60).toString().padLeft(2, '0')}s';
    }
    return '${d.inSeconds}s';
  }

  /// Color for the agent's state indicator.
  Color get stateColor {
    switch (state) {
      case AgentState.idle:
        return const Color(0xFF6B7280);
      case AgentState.thinking:
        return const Color(0xFF3B82F6);
      case AgentState.working:
        return accentColor;
      case AgentState.error:
        return const Color(0xFFEF4444);
    }
  }

  /// Human-readable state label.
  String get stateLabel {
    switch (state) {
      case AgentState.idle:
        return 'Idle';
      case AgentState.thinking:
        return 'Thinking';
      case AgentState.working:
        return 'Working';
      case AgentState.error:
        return 'Error';
    }
  }

  AgentStatus copyWith({
    AgentState? state,
    String? currentTask,
    double? progress,
    DateTime? taskStartedAt,
    List<String>? recentActions,
  }) {
    return AgentStatus(
      agentId: agentId,
      name: name,
      icon: icon,
      state: state ?? this.state,
      currentTask: currentTask ?? this.currentTask,
      progress: progress ?? this.progress,
      taskStartedAt: taskStartedAt ?? this.taskStartedAt,
      recentActions: recentActions ?? this.recentActions,
      accentColor: accentColor,
    );
  }

  Map<String, dynamic> toJson() => {
        'agentId': agentId,
        'name': name,
        'icon': icon,
        'state': state.name,
        'currentTask': currentTask,
        'progress': progress,
        'taskStartedAt': taskStartedAt?.toIso8601String(),
        'recentActions': recentActions,
      };

  @override
  String toString() => 'AgentStatus[$name: ${state.name}]';
}

// ═══════════════════════════════════════════════════════════════════════════
// Agent Activity (for activity log)
// ═══════════════════════════════════════════════════════════════════════════

/// A single activity entry in the shared activity log.
///
/// All agents write to a shared activity stream for real-time monitoring.
class AgentActivity {
  /// When the activity occurred.
  final DateTime timestamp;

  /// ID of the agent that performed the action.
  final String agentId;

  /// Name of the agent that performed the action.
  final String agentName;

  /// Description of the action.
  final String action;

  /// Optional result or output of the action.
  final String? result;

  /// Log level for this activity.
  final LogLevel level;

  const AgentActivity({
    required this.timestamp,
    required this.agentId,
    required this.agentName,
    required this.action,
    this.result,
    this.level = LogLevel.info,
  });

  /// Get color based on activity level.
  Color get color {
    switch (level) {
      case LogLevel.info:
        return const Color(0xFFF0F0F5);
      case LogLevel.warning:
        return const Color(0xFFF59E0B);
      case LogLevel.error:
        return const Color(0xFFEF4444);
    }
  }

  /// Formatted timestamp string.
  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'agentId': agentId,
        'agentName': agentName,
        'action': action,
        'result': result,
        'level': level.name,
      };

  @override
  String toString() => '[${agentName}] $action';
}

// ═══════════════════════════════════════════════════════════════════════════
// Extension Helpers
// ═══════════════════════════════════════════════════════════════════════════

/// Extension on TaskPlanStatus for UI helpers.
extension TaskPlanStatusExt on TaskPlanStatus {
  /// Human-readable label in Chinese.
  String get label {
    switch (this) {
      case TaskPlanStatus.pending:
        return 'Pending';
      case TaskPlanStatus.running:
        return 'Running';
      case TaskPlanStatus.paused:
        return 'Paused';
      case TaskPlanStatus.completed:
        return 'Completed';
      case TaskPlanStatus.failed:
        return 'Failed';
    }
  }

  /// Color for this status.
  Color get color {
    switch (this) {
      case TaskPlanStatus.pending:
        return const Color(0xFF6B7280);
      case TaskPlanStatus.running:
        return const Color(0xFF7B2FF7);
      case TaskPlanStatus.paused:
        return const Color(0xFFF59E0B);
      case TaskPlanStatus.completed:
        return const Color(0xFF10B981);
      case TaskPlanStatus.failed:
        return const Color(0xFFEF4444);
    }
  }
}

/// Extension on StepStatus for icon helpers.
extension StepStatusExt on StepStatus {
  /// IconData for this step status.
  IconData get icon {
    switch (this) {
      case StepStatus.pending:
        return Icons.schedule;
      case StepStatus.running:
        return Icons.play_circle_outline;
      case StepStatus.completed:
        return Icons.check_circle;
      case StepStatus.failed:
        return Icons.error;
      case StepStatus.skipped:
        return Icons.skip_next;
    }
  }

  /// Human-readable label.
  String get label {
    switch (this) {
      case StepStatus.pending:
        return 'Pending';
      case StepStatus.running:
        return 'Running';
      case StepStatus.completed:
        return 'Completed';
      case StepStatus.failed:
        return 'Failed';
      case StepStatus.skipped:
        return 'Skipped';
    }
  }
}
