// ignore_for_file: avoid_print

/// ============================================================================
/// Self-Use State Provider
/// ============================================================================
///
/// Manages:
/// - Current active session
/// - Session history
/// - Real-time progress
/// - Action logs stream
///
/// Providers:
/// - selfUseSessionProvider:    Current active session (null if none)
/// - selfUseHistoryProvider:    Past sessions list
/// - selfUseProgressProvider:   Real-time progress (0.0 - 1.0)
/// - selfUseLogsProvider:       Latest log entries
/// - selfUseIsActiveProvider:   Whether a session is running
/// - selfUseCurrentActionProvider: The action being executed right now
/// - selfUseStatsProvider:      Session statistics
/// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/self_use_session.dart';

// ---------------------------------------------------------------------------
// Internal State Notifier
// ---------------------------------------------------------------------------

/// Holds the mutable state for self-use sessions.
class _SelfUseState {
  final SelfUseSession? currentSession;
  final List<SelfUseSession> history;

  const _SelfUseState({
    this.currentSession,
    this.history = const [],
  });

  _SelfUseState copyWith({
    SelfUseSession? currentSession,
    List<SelfUseSession>? history,
  }) {
    return _SelfUseState(
      currentSession: currentSession ?? this.currentSession,
      history: history ?? this.history,
    );
  }
}

// ---------------------------------------------------------------------------
// State Notifier
// ---------------------------------------------------------------------------

/// Main state notifier for self-use sessions.
///
/// Manages the lifecycle of sessions: creation, planning, execution,
/// pausing, resuming, and completion.
class SelfUseNotifier extends StateNotifier<_SelfUseState> {
  SelfUseNotifier() : super(const _SelfUseState());

  // -- Session Lifecycle ----------------------------------------------------

  /// Create and start a new session from a user request.
  ///
  /// If a session is already active, it will be moved to history first.
  SelfUseSession startSession({
    required String userRequest,
    required List<SelfAction> plannedActions,
    String? planDescription,
  }) {
    // Archive any existing active session
    final existing = state.currentSession;
    if (existing != null && !existing.isComplete) {
      existing.markFailed();
      _archiveCurrentSession();
    }

    final session = SelfUseSession(
      id: generateSessionId(),
      userRequest: userRequest,
      plannedActions: plannedActions,
      planDescription: planDescription,
    );

    session.markPlanningStarted();
    session.addLog(SessionLogEntry.info('Session started: "$userRequest"'));
    session.addLog(SessionLogEntry.info(
      'Planned ${plannedActions.length} actions',
    ));

    state = state.copyWith(currentSession: session);
    return session;
  }

  /// Transition from planning to execution.
  void markExecutionStarted() {
    final session = state.currentSession;
    if (session == null) return;

    session.markExecutionStarted();
    session.addLog(SessionLogEntry.info('Execution started'));
    _notifyUpdate();
  }

  /// Record the result of the current action and advance.
  void recordActionResult(SelfActionResult result) {
    final session = state.currentSession;
    if (session == null) return;

    session.recordResult(result);

    if (result.success) {
      session.addLog(
        SessionLogEntry.info(
          'Action completed: ${result.actionId} (${result.duration.inMilliseconds}ms)',
          actionId: result.actionId,
        ),
      );
    } else {
      session.addLog(
        SessionLogEntry.error(
          'Action failed: ${result.actionId} -- ${result.error}',
          actionId: result.actionId,
        ),
      );
    }

    session.advanceStep();
    _notifyUpdate();
  }

  /// Mark the current action as started (for timing).
  void markActionStarted(String actionId) {
    final session = state.currentSession;
    if (session == null) return;

    final action = session.currentAction;
    if (action == null) return;

    session.addLog(
      SessionLogEntry.debug(
        'Executing: ${action.action}',
        actionId: actionId,
      ),
    );
    _notifyUpdate();
  }

  /// Pause the current session.
  void pauseSession() {
    final session = state.currentSession;
    if (session == null || session.isComplete) return;

    session.markPaused();
    session.addLog(SessionLogEntry.info('Session paused'));
    _notifyUpdate();
  }

  /// Resume a paused session.
  void resumeSession() {
    final session = state.currentSession;
    if (session == null || session.isComplete) return;

    session.markResumed();
    session.addLog(SessionLogEntry.info('Session resumed'));
    _notifyUpdate();
  }

  /// Mark the current session as completed.
  void completeSession() {
    final session = state.currentSession;
    if (session == null) return;

    session.markCompleted();
    session.addLog(SessionLogEntry.info(
      'Session completed in ${session.elapsedTime.inSeconds}s',
    ));
    _archiveCurrentSession();
  }

  /// Mark the current session as failed.
  void failSession(String? reason) {
    final session = state.currentSession;
    if (session == null) return;

    session.markFailed();
    session.addLog(SessionLogEntry.error(
      'Session failed${reason != null ? ': $reason' : ''}',
    ));
    _archiveCurrentSession();
  }

  /// Cancel the current session (marks as failed and archives).
  void cancelSession() {
    final session = state.currentSession;
    if (session == null) return;

    session.markFailed();
    session.addLog(SessionLogEntry.warning('Session cancelled by user'));
    _archiveCurrentSession();
  }

  /// Clear the current session without archiving.
  void clearCurrentSession() {
    state = state.copyWith(currentSession: null);
  }

  /// Add a log entry to the current session.
  void addLog(SessionLogEntry entry) {
    final session = state.currentSession;
    if (session == null) return;
    session.addLog(entry);
    _notifyUpdate();
  }

  // -- History Management ---------------------------------------------------

  /// Archive the current session to history and clear it.
  void _archiveCurrentSession() {
    final session = state.currentSession;
    if (session == null) return;

    final updatedHistory = [...state.history, session];
    state = _SelfUseState(
      currentSession: null,
      history: updatedHistory,
    );
  }

  /// Clear all history.
  void clearHistory() {
    state = state.copyWith(history: []);
  }

  /// Remove a specific session from history.
  void removeFromHistory(String sessionId) {
    final updated = state.history.where((s) => s.id != sessionId).toList();
    state = state.copyWith(history: updated);
  }

  // -- Helpers --------------------------------------------------------------

  /// Trigger a rebuild with the same state (for log updates).
  void _notifyUpdate() {
    state = state.copyWith();
  }
}

// ---------------------------------------------------------------------------
// Riverpod Providers
// ---------------------------------------------------------------------------

/// Main provider that holds all self-use state.
///
/// Use this to access [SelfUseNotifier] for mutations.
final selfUseProvider =
    StateNotifierProvider<SelfUseNotifier, _SelfUseState>((ref) {
  return SelfUseNotifier();
});

/// The currently active session, or null if none.
///
/// ```dart
/// final session = ref.watch(selfUseSessionProvider);
/// if (session != null) {
///   print('Progress: ${session.progressPercent}%');
/// }
/// ```
final selfUseSessionProvider = Provider<SelfUseSession?>((ref) {
  return ref.watch(selfUseProvider).currentSession;
});

/// List of past (completed or failed) sessions.
///
/// Ordered oldest first. Use [reversed] for newest-first.
final selfUseHistoryProvider = Provider<List<SelfUseSession>>((ref) {
  return ref.watch(selfUseProvider).history;
});

/// Real-time progress as a double (0.0 - 1.0).
///
/// Returns 0.0 when no session is active.
final selfUseProgressProvider = Provider<double>((ref) {
  final session = ref.watch(selfUseSessionProvider);
  if (session == null) return 0.0;
  return session.progress;
});

/// Real-time progress as a percentage (0 - 100).
final selfUseProgressPercentProvider = Provider<int>((ref) {
  final session = ref.watch(selfUseSessionProvider);
  if (session == null) return 0;
  return session.progressPercent;
});

/// Whether a session is currently active (executing, not paused).
final selfUseIsActiveProvider = Provider<bool>((ref) {
  final session = ref.watch(selfUseSessionProvider);
  return session != null && session.isActive;
});

/// Whether a session is currently paused.
final selfUseIsPausedProvider = Provider<bool>((ref) {
  final session = ref.watch(selfUseSessionProvider);
  return session != null && session.isPaused;
});

/// Whether any session (active or paused) exists.
final selfUseHasSessionProvider = Provider<bool>((ref) {
  return ref.watch(selfUseSessionProvider) != null;
});

/// The action currently being executed.
final selfUseCurrentActionProvider = Provider<SelfAction?>((ref) {
  final session = ref.watch(selfUseSessionProvider);
  return session?.currentAction;
});

/// The next action after the current one.
final selfUseNextActionProvider = Provider<SelfAction?>((ref) {
  final session = ref.watch(selfUseSessionProvider);
  return session?.nextAction;
});

/// Current session statistics.
final selfUseStatsProvider = Provider<SessionStats?>((ref) {
  final session = ref.watch(selfUseSessionProvider);
  return session?.stats;
});

/// Number of completed steps in the current session.
final selfUseCompletedStepsProvider = Provider<int>((ref) {
  final session = ref.watch(selfUseSessionProvider);
  return session?.completedSteps ?? 0;
});

/// Number of failed steps in the current session.
final selfUseFailedStepsProvider = Provider<int>((ref) {
  final session = ref.watch(selfUseSessionProvider);
  return session?.failedSteps ?? 0;
});

/// Total number of steps in the current session.
final selfUseTotalStepsProvider = Provider<int>((ref) {
  final session = ref.watch(selfUseSessionProvider);
  return session?.plannedActions.length ?? 0;
});

/// Elapsed time since the current session started.
final selfUseElapsedTimeProvider = Provider<Duration>((ref) {
  final session = ref.watch(selfUseSessionProvider);
  if (session == null) return Duration.zero;
  return session.elapsedTime;
});

/// The latest log entry from the current session.
final selfUseLatestLogProvider = Provider<SessionLogEntry?>((ref) {
  final session = ref.watch(selfUseSessionProvider);
  if (session == null || session.logs.isEmpty) return null;
  return session.logs.last;
});

/// All log entries from the current session.
final selfUseLogsProvider = Provider<List<SessionLogEntry>>((ref) {
  final session = ref.watch(selfUseSessionProvider);
  return session?.logs ?? [];
});

/// Remaining actions in the current session.
final selfUseRemainingActionsProvider = Provider<List<SelfAction>>((ref) {
  final session = ref.watch(selfUseSessionProvider);
  return session?.remainingActions ?? [];
});

/// Whether the current session is complete.
final selfUseIsCompleteProvider = Provider<bool>((ref) {
  final session = ref.watch(selfUseSessionProvider);
  return session?.isComplete ?? false;
});

/// Session status name for display.
final selfUseStatusNameProvider = Provider<String>((ref) {
  final session = ref.watch(selfUseSessionProvider);
  return session?.status.name ?? 'idle';
});

/// Combined session summary for UI widgets.
final selfUseSummaryProvider = Provider<Map<String, dynamic>?>((ref) {
  final session = ref.watch(selfUseSessionProvider);
  if (session == null) return null;
  return session.toSummaryJson();
});

// ---------------------------------------------------------------------------
// Extension: LogLevel helpers
// ---------------------------------------------------------------------------

extension SessionLogEntryX on SessionLogEntry {
  /// Short formatted string for display.
  String get displayString =>
      '[${level.name.toUpperCase()}] ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')} $message';
}

extension LogLevelHelpers on SessionLogEntry {
  static LogLevel fromString(String name) {
    return LogLevel.values.firstWhere(
      (l) => l.name == name.toLowerCase(),
      orElse: () => LogLevel.info,
    );
  }
}
