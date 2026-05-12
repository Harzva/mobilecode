// lib/providers/agent_dashboard_provider.dart
// Agent Dashboard Provider — Riverpod provider for the agent dashboard UI.
//
// Exposes agent paradigm configuration, runtime statistics,
// worker status, and system health for the dashboard screen.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/agent_paradigm.dart';
import '../services/agent_action_system.dart';
import 'agent_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Agent Dashboard State
// ═══════════════════════════════════════════════════════════════════════════

/// Immutable state for the agent dashboard.
///
/// Aggregates paradigm configuration, runtime metrics,
/// worker status, and execution history for visualization.
class AgentDashboardState {
  /// Whether the agent system is initialized and ready.
  final bool isReady;

  /// Currently active paradigm modes.
  final Map<String, bool> activeParadigms;

  /// Runtime statistics (counters).
  final AgentRuntimeStats stats;

  /// Status of each worker (name → status).
  final Map<String, WorkerStatus> workerStatuses;

  /// Recent action history entries (last N).
  final List<HistoryEntry> recentActions;

  /// Current supervisor status message.
  final String supervisorStatus;

  /// Whether human confirmation is pending.
  final bool hasPendingConfirmation;

  /// Pending confirmation details, if any.
  final PendingConfirmation? pendingConfirmation;

  /// System health score (0.0 - 1.0).
  final double systemHealth;

  const AgentDashboardState({
    this.isReady = false,
    this.activeParadigms = const {},
    this.stats = const AgentRuntimeStats(),
    this.workerStatuses = const {},
    this.recentActions = const [],
    this.supervisorStatus = 'Initializing...',
    this.hasPendingConfirmation = false,
    this.pendingConfirmation,
    this.systemHealth = 1.0,
  });

  /// Create a modified copy.
  AgentDashboardState copyWith({
    bool? isReady,
    Map<String, bool>? activeParadigms,
    AgentRuntimeStats? stats,
    Map<String, WorkerStatus>? workerStatuses,
    List<HistoryEntry>? recentActions,
    String? supervisorStatus,
    bool? hasPendingConfirmation,
    PendingConfirmation? pendingConfirmation,
    double? systemHealth,
    bool clearPendingConfirmation = false,
  }) {
    return AgentDashboardState(
      isReady: isReady ?? this.isReady,
      activeParadigms: activeParadigms ?? this.activeParadigms,
      stats: stats ?? this.stats,
      workerStatuses: workerStatuses ?? this.workerStatuses,
      recentActions: recentActions ?? this.recentActions,
      supervisorStatus: supervisorStatus ?? this.supervisorStatus,
      hasPendingConfirmation: hasPendingConfirmation ?? this.hasPendingConfirmation,
      pendingConfirmation: clearPendingConfirmation
          ? null
          : (pendingConfirmation ?? this.pendingConfirmation),
      systemHealth: systemHealth ?? this.systemHealth,
    );
  }

  @override
  String toString() =>
      'AgentDashboardState(ready: $isReady, status: "$supervisorStatus", '
      'health: ${(systemHealth * 100).toStringAsFixed(0)}%)';
}

/// Runtime statistics for the agent system.
class AgentRuntimeStats {
  /// Total actions executed (all time).
  final int totalActions;

  /// Successful actions.
  final int successfulActions;

  /// Failed actions.
  final int failedActions;

  /// Total LLM API calls made.
  final int totalApiCalls;

  /// Total tokens consumed (approximate).
  final int totalTokensUsed;

  /// Number of tasks completed.
  final int tasksCompleted;

  /// Number of self-corrections applied.
  final int selfCorrections;

  /// Uptime since last reset.
  final Duration uptime;

  const AgentRuntimeStats({
    this.totalActions = 0,
    this.successfulActions = 0,
    this.failedActions = 0,
    this.totalApiCalls = 0,
    this.totalTokensUsed = 0,
    this.tasksCompleted = 0,
    selfCorrections = 0,
    this.uptime = Duration.zero,
  }) : selfCorrections = selfCorrections;

  /// Calculate success rate (0.0 - 1.0).
  double get successRate =>
      totalActions > 0 ? successfulActions / totalActions : 1.0;

  /// Calculate average tokens per API call.
  double get avgTokensPerCall =>
      totalApiCalls > 0 ? totalTokensUsed / totalApiCalls : 0;

  AgentRuntimeStats copyWith({
    int? totalActions,
    int? successfulActions,
    int? failedActions,
    int? totalApiCalls,
    int? totalTokensUsed,
    int? tasksCompleted,
    int? selfCorrections,
    Duration? uptime,
  }) {
    return AgentRuntimeStats(
      totalActions: totalActions ?? this.totalActions,
      successfulActions: successfulActions ?? this.successfulActions,
      failedActions: failedActions ?? this.failedActions,
      totalApiCalls: totalApiCalls ?? this.totalApiCalls,
      totalTokensUsed: totalTokensUsed ?? this.totalTokensUsed,
      tasksCompleted: tasksCompleted ?? this.tasksCompleted,
      selfCorrections: selfCorrections ?? this.selfCorrections,
      uptime: uptime ?? this.uptime,
    );
  }
}

/// Status of a worker agent.
enum WorkerStatus {
  /// Worker is idle and available.
  idle,

  /// Worker is currently processing a task.
  busy,

  /// Worker encountered an error.
  error,

  /// Worker is disabled.
  disabled,
}

/// Pending human confirmation request.
class PendingConfirmation {
  final String actionName;
  final Map<String, dynamic> actionParams;
  final String reason;
  final DateTime requestedAt;

  const PendingConfirmation({
    required this.actionName,
    required this.actionParams,
    required this.reason,
    required this.requestedAt,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Agent Dashboard Notifier
// ═══════════════════════════════════════════════════════════════════════════

/// Manages the agent dashboard state.
///
/// Aggregates data from the agent system, paradigm configuration,
/// and action history to provide a unified dashboard view.
class AgentDashboardNotifier extends StateNotifier<AgentDashboardState> {
  Timer? _healthCheckTimer;
  DateTime? _startTime;

  AgentDashboardNotifier() : super(const AgentDashboardState()) {
    _initialize();
  }

  /// Initialize dashboard state.
  void _initialize() {
    _startTime = DateTime.now();

    // Load active paradigms from configuration.
    final paradigms = AgentParadigm.enabledParadigms;

    // Initialize worker statuses.
    final workerStatuses = <String, WorkerStatus>{};
    for (final entry in AgentParadigm.workers.entries) {
      workerStatuses[entry.key] = WorkerStatus.idle;
    }

    state = state.copyWith(
      isReady: true,
      activeParadigms: paradigms,
      workerStatuses: workerStatuses,
      supervisorStatus: 'Agent system ready',
    );

    // Start periodic health check.
    _healthCheckTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _updateHealth(),
    );

    debugPrint('[AgentDashboard] Initialized with ${paradigms.length} paradigms');
  }

  /// Update system health score based on various factors.
  void _updateHealth() {
    var health = 1.0;

    // Reduce health if many recent failures.
    final recentFailures = state.recentActions
        .where((a) => !a.result.success)
        .length;
    if (recentFailures > 3) {
      health -= 0.2;
    }

    // Reduce health if workers are in error state.
    final errorWorkers = state.workerStatuses.values
        .where((s) => s == WorkerStatus.error)
        .length;
    health -= errorWorkers * 0.15;

    // Reduce health if pending confirmation (blocked).
    if (state.hasPendingConfirmation) {
      health -= 0.1;
    }

    // Update uptime.
    final uptime = _startTime != null
        ? DateTime.now().difference(_startTime!)
        : Duration.zero;

    state = state.copyWith(
      systemHealth: health.clamp(0.0, 1.0),
      stats: state.stats.copyWith(uptime: uptime),
    );
  }

  // ── Stats Management ───────────────────────────────────────

  /// Record a successful action.
  void recordSuccess(String actionName, {int tokensUsed = 0}) {
    state = state.copyWith(
      stats: state.stats.copyWith(
        totalActions: state.stats.totalActions + 1,
        successfulActions: state.stats.successfulActions + 1,
        totalTokensUsed: state.stats.totalTokensUsed + tokensUsed,
      ),
    );
  }

  /// Record a failed action.
  void recordFailure(String actionName, {int tokensUsed = 0}) {
    state = state.copyWith(
      stats: state.stats.copyWith(
        totalActions: state.stats.totalActions + 1,
        failedActions: state.stats.failedActions + 1,
        totalTokensUsed: state.stats.totalTokensUsed + tokensUsed,
      ),
    );
  }

  /// Record an API call.
  void recordApiCall({int tokensUsed = 0}) {
    state = state.copyWith(
      stats: state.stats.copyWith(
        totalApiCalls: state.stats.totalApiCalls + 1,
        totalTokensUsed: state.stats.totalTokensUsed + tokensUsed,
      ),
    );
  }

  /// Record a completed task.
  void recordTaskCompleted() {
    state = state.copyWith(
      stats: state.stats.copyWith(
        tasksCompleted: state.stats.tasksCompleted + 1,
      ),
      supervisorStatus: 'Task completed',
    );
  }

  /// Record a self-correction event.
  void recordSelfCorrection() {
    state = state.copyWith(
      stats: state.stats.copyWith(
        selfCorrections: state.stats.selfCorrections + 1,
      ),
    );
  }

  // ── Worker Status ──────────────────────────────────────────

  /// Update a worker's status.
  void setWorkerStatus(String workerId, WorkerStatus status) {
    final updated = Map<String, WorkerStatus>.from(state.workerStatuses);
    updated[workerId] = status;
    state = state.copyWith(workerStatuses: updated);
  }

  /// Mark a worker as busy.
  void setWorkerBusy(String workerId) {
    setWorkerStatus(workerId, WorkerStatus.busy);
  }

  /// Mark a worker as idle.
  void setWorkerIdle(String workerId) {
    setWorkerStatus(workerId, WorkerStatus.idle);
  }

  /// Mark a worker as errored.
  void setWorkerError(String workerId) {
    setWorkerStatus(workerId, WorkerStatus.error);
  }

  // ── Human-in-the-Loop ──────────────────────────────────────

  /// Request human confirmation for an action.
  void requestConfirmation({
    required String actionName,
    required Map<String, dynamic> actionParams,
    required String reason,
  }) {
    state = state.copyWith(
      hasPendingConfirmation: true,
      pendingConfirmation: PendingConfirmation(
        actionName: actionName,
        actionParams: actionParams,
        reason: reason,
        requestedAt: DateTime.now(),
      ),
      supervisorStatus: 'Waiting for human confirmation: $actionName',
    );
  }

  /// Confirm the pending action.
  void confirmPendingAction() {
    state = state.copyWith(
      hasPendingConfirmation: false,
      clearPendingConfirmation: true,
      supervisorStatus: 'Action confirmed by user',
    );
  }

  /// Deny the pending action.
  void denyPendingAction() {
    state = state.copyWith(
      hasPendingConfirmation: false,
      clearPendingConfirmation: true,
      supervisorStatus: 'Action denied by user',
    );
  }

  // ── Supervisor Status ──────────────────────────────────────

  /// Update the supervisor status message.
  void setSupervisorStatus(String status) {
    state = state.copyWith(supervisorStatus: status);
  }

  // ── Action History ─────────────────────────────────────────

  /// Add a history entry to the recent actions list.
  void addHistoryEntry(HistoryEntry entry) {
    final updated = [...state.recentActions, entry];
    // Keep only last 50 entries.
    if (updated.length > 50) {
      updated.removeAt(0);
    }
    state = state.copyWith(recentActions: updated);
  }

  /// Clear action history.
  void clearHistory() {
    state = state.copyWith(recentActions: const []);
  }

  // ── Reset ──────────────────────────────────────────────────

  /// Reset all runtime stats.
  void resetStats() {
    _startTime = DateTime.now();
    state = state.copyWith(
      stats: const AgentRuntimeStats(),
      supervisorStatus: 'Stats reset',
    );
  }

  @override
  void dispose() {
    _healthCheckTimer?.cancel();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Providers
// ═══════════════════════════════════════════════════════════════════════════

/// Primary provider for the agent dashboard state.
///
/// ```dart
/// // Watch full dashboard state
/// final dashboard = ref.watch(agentDashboardProvider);
///
/// // Access notifier
/// final notifier = ref.read(agentDashboardProvider.notifier);
/// notifier.recordSuccess('writeFile');
/// ```
final agentDashboardProvider =
    StateNotifierProvider<AgentDashboardNotifier, AgentDashboardState>((ref) {
  return AgentDashboardNotifier();
});

// ── Derived Providers ───────────────────────────────────────────

/// Whether the agent system is ready.
final dashboardReadyProvider = Provider<bool>((ref) {
  return ref.watch(agentDashboardProvider).isReady;
});

/// Active paradigms map.
final activeParadigmsProvider = Provider<Map<String, bool>>((ref) {
  return ref.watch(agentDashboardProvider).activeParadigms;
});

/// Agent runtime stats.
final runtimeStatsProvider = Provider<AgentRuntimeStats>((ref) {
  return ref.watch(agentDashboardProvider).stats;
});

/// Worker statuses.
final workerStatusesProvider = Provider<Map<String, WorkerStatus>>((ref) {
  return ref.watch(agentDashboardProvider).workerStatuses;
});

/// Recent action history.
final dashboardHistoryProvider = Provider<List<HistoryEntry>>((ref) {
  return ref.watch(agentDashboardProvider).recentActions;
});

/// Supervisor status message.
final supervisorStatusProvider = Provider<String>((ref) {
  return ref.watch(agentDashboardProvider).supervisorStatus;
});

/// Whether a human confirmation is pending.
final pendingConfirmationProvider = Provider<bool>((ref) {
  return ref.watch(agentDashboardProvider).hasPendingConfirmation;
});

/// System health score (0.0 - 1.0).
final systemHealthProvider = Provider<double>((ref) {
  return ref.watch(agentDashboardProvider).systemHealth;
});

/// Success rate of actions (0.0 - 1.0).
final actionSuccessRateProvider = Provider<double>((ref) {
  return ref.watch(agentDashboardProvider).stats.successRate;
});

/// Combined dashboard metrics for UI display.
final dashboardMetricsProvider = Provider<DashboardMetrics>((ref) {
  final state = ref.watch(agentDashboardProvider);
  return DashboardMetrics(
    totalActions: state.stats.totalActions,
    successRate: state.stats.successRate,
    tasksCompleted: state.stats.tasksCompleted,
    selfCorrections: state.stats.selfCorrections,
    activeWorkers: state.workerStatuses.values.where((s) => s == WorkerStatus.busy).length,
    totalWorkers: state.workerStatuses.length,
    systemHealth: state.systemHealth,
    uptime: state.stats.uptime,
  );
});

/// Bundle of key dashboard metrics for display.
class DashboardMetrics {
  final int totalActions;
  final double successRate;
  final int tasksCompleted;
  final int selfCorrections;
  final int activeWorkers;
  final int totalWorkers;
  final double systemHealth;
  final Duration uptime;

  const DashboardMetrics({
    required this.totalActions,
    required this.successRate,
    required this.tasksCompleted,
    required this.selfCorrections,
    required this.activeWorkers,
    required this.totalWorkers,
    required this.systemHealth,
    required this.uptime,
  });
}
