// lib/providers/deep_dive_provider.dart
// Solo Mode Riverpod Providers
//
// Reactive state management for Solo Mode background execution.
// These providers connect the Solo Mode services to the Flutter UI,
// enabling reactive widgets that update automatically as tasks progress.
//
// Architecture:
//   DeepDiveModeService (business logic)
//     └── Streams (taskUpdates, allTasksUpdates, taskEvents)
//           └── Riverpod Providers (this file)
//                 └── Flutter Widgets (SoloPage, MiniProgressBar, etc.)
//
// Usage:
//   final task = ref.watch(soloCurrentTaskProvider);
//   final progress = ref.watch(soloProgressProvider);
//   final isRunning = ref.watch(soloIsRunningProvider);

// ignore_for_file: avoid_print

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/error_handler.dart';
import '../services/foreground_service.dart';
import '../services/notification_manager.dart';
import '../services/deep_dive_service.dart';
import '../services/deep_dive_task_manager.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Core Solo Mode Providers
// ═══════════════════════════════════════════════════════════════════════════════

/// The singleton DeepDiveModeService instance.
///
/// This provider gives access to the full service API for operations
/// like submitting tasks, pausing, cancelling, etc.
final soloModeServiceProvider = Provider<DeepDiveModeService>((ref) {
  final service = DeepDiveModeService();

  // Auto-dispose when the provider is no longer used.
  ref.onDispose(() {
    // Don't dispose the singleton — other providers may need it.
  });

  return service;
});

/// The singleton DeepDiveTaskManager instance.
///
/// Use this provider to queue tasks, check queue status, and manage
/// the task lifecycle at a higher level than DeepDiveModeService.
final deepDiveTaskManagerProvider = Provider<DeepDiveTaskManager>((ref) {
  final manager = DeepDiveTaskManager();

  ref.onDispose(() {
    // Don't dispose — shared with other providers.
  });

  return manager;
});

// ── Current Task State ───────────────────────────────────────────────────────

/// The currently running Solo Mode task, or null if none is running.
///
/// Updates automatically when tasks start, complete, or fail.
/// Use this to show the primary task UI (Solo page, mini progress bar).
final soloCurrentTaskProvider = StateProvider<DeepDiveTask?>((ref) {
  final service = ref.watch(soloModeServiceProvider);

  // Set up a listener to keep this provider in sync with the service.
  _setupTaskListener(ref, service);

  return service.currentRunningTask;
});

/// All currently active tasks (queued, running, paused).
///
/// Updates whenever any active task changes. Use this for the
/// active tasks list in the Solo page.
final soloActiveTasksProvider = StateProvider<List<DeepDiveTask>>((ref) {
  final service = ref.watch(soloModeServiceProvider);

  _setupAllTasksListener(ref, service);

  return service.activeTasks;
});

/// All completed tasks (including failed and cancelled).
///
/// Updates whenever a task completes. Use this for the history
/// section in the Solo page.
final soloCompletedTasksProvider = StateProvider<List<DeepDiveTask>>((ref) {
  final service = ref.watch(soloModeServiceProvider);

  _setupAllTasksListener(ref, service);

  return service.completedTasks;
});

/// Combined list of all tasks (active + completed).
///
/// Convenience provider for views that want to display everything.
final soloAllTasksProvider = StateProvider<List<DeepDiveTask>>((ref) {
  final active = ref.watch(soloActiveTasksProvider);
  final completed = ref.watch(soloCompletedTasksProvider);
  return [...active, ...completed];
});

// ── Boolean State ────────────────────────────────────────────────────────────

/// Whether any Solo Mode task is currently running.
///
/// Use this to conditionally show the mini progress bar, enable
/// FAB buttons, or change app bar indicators.
final soloIsRunningProvider = Provider<bool>((ref) {
  final activeTasks = ref.watch(soloActiveTasksProvider);
  return activeTasks.any((t) => t.isRunning);
});

/// Whether any task is paused.
///
/// Use this to show a "resume" button or paused indicator.
final soloIsPausedProvider = Provider<bool>((ref) {
  final activeTasks = ref.watch(soloActiveTasksProvider);
  return activeTasks.any((t) => t.status == DeepDiveTaskStatus.paused);
});

/// Whether Solo Mode has any active or completed tasks.
///
/// Use this to conditionally show/hide the Solo Mode navigation item.
final soloHasTasksProvider = Provider<bool>((ref) {
  final active = ref.watch(soloActiveTasksProvider);
  final completed = ref.watch(soloCompletedTasksProvider);
  return active.isNotEmpty || completed.isNotEmpty;
});

/// Whether there are tasks that have completed (success or failure).
///
/// Use this to show a "clear history" button.
final soloHasCompletedTasksProvider = Provider<bool>((ref) {
  final completed = ref.watch(soloCompletedTasksProvider);
  return completed.isNotEmpty;
});

// ── Progress Providers ───────────────────────────────────────────────────────

/// Current task progress as a double (0.0 - 1.0).
///
/// Returns 0.0 if no task is running. Use with [LinearProgressIndicator].
final soloProgressProvider = Provider<double>((ref) {
  final task = ref.watch(soloCurrentTaskProvider);
  if (task == null) return 0.0;
  return task.progress.clamp(0.0, 1.0);
});

/// Current task progress as a percentage (0 - 100).
///
/// Use for text displays like "42%".
final soloProgressPercentProvider = Provider<int>((ref) {
  final task = ref.watch(soloCurrentTaskProvider);
  if (task == null) return 0;
  return task.progressPercent;
});

/// Progress text for display — shows step count and percentage.
///
/// Example: "Step 3 / 12 (25%)".
final soloProgressTextProvider = Provider<String>((ref) {
  final task = ref.watch(soloCurrentTaskProvider);
  if (task == null) return 'No active task';
  return 'Step ${task.currentStep + 1} / ${task.totalSteps} (${task.progressPercent}%)';
});

/// Current action description — what the task is doing right now.
///
/// Example: "Writing lib/main.dart".
final soloCurrentActionProvider = Provider<String>((ref) {
  final task = ref.watch(soloCurrentTaskProvider);
  if (task == null) return 'Idle';
  return task.currentActionDescription.isNotEmpty
      ? task.currentActionDescription
      : 'Initializing...';
});

// ── Task Detail Providers ────────────────────────────────────────────────────

/// Get a specific task by ID.
///
/// Usage: `ref.watch(deepDiveTaskByIdProvider('deep_dive_123'))`
final deepDiveTaskByIdProvider =
    Provider.family<DeepDiveTask?, String>((ref, taskId) {
  final allTasks = ref.watch(soloAllTasksProvider);
  try {
    return allTasks.firstWhere((t) => t.id == taskId);
  } catch (_) {
    return null;
  }
});

/// Get the result history for a specific task.
///
/// Usage: `ref.watch(deepDiveTaskResultsProvider('deep_dive_123'))`
final deepDiveTaskResultsProvider =
    Provider.family<List<SoloStepResult>, String>((ref, taskId) {
  final task = ref.watch(deepDiveTaskByIdProvider(taskId));
  return task?.stepResults ?? [];
});

/// Get elapsed time for the current task as a formatted string.
///
/// Example: "2m 34s".
final soloElapsedTimeProvider = Provider<String>((ref) {
  final task = ref.watch(soloCurrentTaskProvider);
  final elapsed = task?.elapsedTime;
  if (elapsed == null) return '--:--';

  final minutes = elapsed.inMinutes;
  final seconds = elapsed.inSeconds % 60;

  if (minutes >= 60) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return '${hours}h ${mins}m ${seconds}s';
  }

  return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
});

// ── Queue Status Providers ───────────────────────────────────────────────────

/// Current queue status from the task manager.
///
/// Use this to show queue depth, concurrency info, and capacity.
final soloQueueStatusProvider = StreamProvider<QueueStatus>((ref) {
  final manager = ref.watch(deepDiveTaskManagerProvider);
  return manager.statusUpdates;
});

/// Number of tasks currently running.
final soloRunningCountProvider = Provider<int>((ref) {
  final active = ref.watch(soloActiveTasksProvider);
  return active.where((t) => t.isRunning).length;
});

/// Number of tasks queued (waiting for capacity).
final soloQueuedCountProvider = Provider<int>((ref) {
  final active = ref.watch(soloActiveTasksProvider);
  return active.where((t) => t.status == DeepDiveTaskStatus.queued).length;
});

// ── Stream Providers ─────────────────────────────────────────────────────────

/// Stream of task lifecycle events.
///
/// Use this to trigger one-shot actions like showing snackbars,
/// playing sounds, or logging analytics.
final deepDiveTaskEventsProvider = StreamProvider<DeepDiveTaskEvent>((ref) {
  final service = ref.watch(soloModeServiceProvider);
  return service.taskEvents;
});

/// Stream of individual task updates.
///
/// Each emission represents a state change in a single task.
/// Use for detailed progress tracking.
final deepDiveTaskUpdatesProvider = StreamProvider<DeepDiveTask>((ref) {
  final service = ref.watch(soloModeServiceProvider);
  return service.taskUpdates;
});

// ── UI State Providers ───────────────────────────────────────────────────────

/// Whether to show the mini progress bar at the bottom of the screen.
///
/// This is a user preference that can be toggled. Even when enabled,
/// the bar only appears when a task is running.
final soloShowMiniBarProvider = StateProvider<bool>((ref) => true);

/// Whether the Solo Mode page is currently open.
///
/// Used to suppress certain notifications when the user is already
/// viewing the Solo page.
final soloPageOpenProvider = StateProvider<bool>((ref) => false);

/// Selected task ID in the Solo Mode page.
///
/// Used to show detailed view for a specific task.
final soloSelectedTaskIdProvider = StateProvider<String?>((ref) => null);

/// The selected task, or null if none selected.
final soloSelectedTaskProvider = Provider<DeepDiveTask?>((ref) {
  final taskId = ref.watch(soloSelectedTaskIdProvider);
  if (taskId == null) return null;
  return ref.watch(deepDiveTaskByIdProvider(taskId));
});

// ── Notification Integration ─────────────────────────────────────────────────

/// Whether system notifications are enabled for Solo Mode.
///
/// This is a user preference stored in settings.
final soloNotificationsEnabledProvider = StateProvider<bool>((ref) => true);

/// The notification manager instance.
final notificationManagerProvider = Provider<NotificationManager>((ref) {
  return NotificationManager();
});

// ── Foreground Service ───────────────────────────────────────────────────────

/// Whether the Android foreground service is active.
final soloForegroundServiceActiveProvider = StateProvider<bool>((ref) {
  final service = ForegroundService();
  return service.isActive;
});

// ═══════════════════════════════════════════════════════════════════════════════
// Internal: Stream-to-State Bridge Helpers
// ═══════════════════════════════════════════════════════════════════════════════

/// Set up a listener that keeps StateProvider values in sync with
/// the DeepDiveModeService streams.
///
/// This bridges the imperative stream API of DeepDiveModeService with
/// the reactive provider API of Riverpod.
void _setupTaskListener(Ref ref, DeepDiveModeService service) {
  // Use a subscription that gets cleaned up when the provider is disposed.
  final subscription = service.taskUpdates.listen((_) {
    // Trigger a re-read of the current task.
    ref.invalidate(_soloCurrentTaskRawProvider);
  });

  ref.onDispose(() {
    subscription.cancel();
  });
}

void _setupAllTasksListener(Ref ref, DeepDiveModeService service) {
  final subscription = service.allTasksUpdates.listen((_) {
    ref.invalidate(_soloActiveTasksRawProvider);
    ref.invalidate(_soloCompletedTasksRawProvider);
  });

  ref.onDispose(() {
    subscription.cancel();
  });
}

// Internal providers used for invalidation targets.
final _soloCurrentTaskRawProvider = Provider<DeepDiveTask?>((ref) {
  return DeepDiveModeService().currentRunningTask;
});

final _soloActiveTasksRawProvider = Provider<List<DeepDiveTask>>((ref) {
  return DeepDiveModeService().activeTasks;
});

final _soloCompletedTasksRawProvider = Provider<List<DeepDiveTask>>((ref) {
  return DeepDiveModeService().completedTasks;
});

// ═══════════════════════════════════════════════════════════════════════════════
// Async Task Submission — Notifier Pattern
// ═══════════════════════════════════════════════════════════════════════════════

/// A Riverpod AsyncNotifier that handles task submission with loading states.
///
/// Usage:
/// ```dart
/// final state = ref.watch(deepDiveTaskSubmitProvider);
///
/// // Submit a task
/// ref.read(deepDiveTaskSubmitProvider.notifier).submit(
///   title: 'Create a todo app',
///   description: 'User requested...',
///   actions: plannedActions,
/// );
/// ```
class DeepDiveTaskSubmitNotifier extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {
    // Nothing to do on initial build.
    return null;
  }

  /// Submit a new Solo Mode task.
  ///
  /// Sets the state to [AsyncLoading] while submitting, then
  /// [AsyncData] on success or [AsyncError] on failure.
  Future<void> submit({
    required String title,
    required String description,
    required List<SelfAction> actions,
    SoloPriority priority = SoloPriority.normal,
  }) async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      final service = ref.read(soloModeServiceProvider);
      final task = await service.submitTask(
        title: title,
        description: description,
        actions: actions,
        priority: priority,
      );

      // Sync notification if enabled.
      final notificationsEnabled = ref.read(soloNotificationsEnabledProvider);
      if (notificationsEnabled) {
        await NotificationManager().showTaskStarted(task);
      }

      // Start foreground service.
      await ForegroundService().initialize();
      await ForegroundService().start(
        title: '\u{1F916} Solo Mode — $title',
        body: 'Starting...',
      );
    });
  }

  /// Submit a task from a [SelfUseSession].
  Future<void> submitFromSession(SelfUseSession session,
      {SoloPriority priority = SoloPriority.normal}) async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      final service = ref.read(soloModeServiceProvider);
      final task = await service.submitFromSession(session);

      final notificationsEnabled = ref.read(soloNotificationsEnabledProvider);
      if (notificationsEnabled) {
        await NotificationManager().showTaskStarted(task);
      }
    });
  }

  /// Cancel the current running task.
  void cancelCurrent() {
    final service = ref.read(soloModeServiceProvider);
    final currentTask = service.currentRunningTask;
    if (currentTask != null) {
      service.cancelTask(currentTask.id);
    }
  }

  /// Pause the current running task.
  void pauseCurrent() {
    final service = ref.read(soloModeServiceProvider);
    final currentTask = service.currentRunningTask;
    if (currentTask != null) {
      service.pauseTask(currentTask.id);
    }
  }

  /// Resume the current paused task.
  void resumeCurrent() {
    final service = ref.read(soloModeServiceProvider);
    final currentTask = service.currentRunningTask;
    if (currentTask != null) {
      service.resumeTask(currentTask.id);
    }
  }

  /// Retry a failed task.
  Future<void> retryTask(String taskId) async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      final service = ref.read(soloModeServiceProvider);
      await service.retryTask(taskId);
    });
  }
}

/// Provider for the [DeepDiveTaskSubmitNotifier].
final deepDiveTaskSubmitProvider =
    AsyncNotifierProvider<DeepDiveTaskSubmitNotifier, void>(
  () => DeepDiveTaskSubmitNotifier(),
);

// ═══════════════════════════════════════════════════════════════════════════════
// Task Action Notifier — Pause / Resume / Cancel individual tasks
// ═══════════════════════════════════════════════════════════════════════════════

/// A notifier that provides imperative control over individual tasks.
///
/// Unlike [DeepDiveTaskSubmitNotifier] which manages async submission state,
/// this notifier provides synchronous actions that take effect immediately.
class DeepDiveTaskActionNotifier extends Notifier<void> {
  @override
  void build() {
    // No state to manage — this notifier is all about side effects.
    return null;
  }

  /// Pause a task by ID.
  void pause(String taskId) {
    ref.read(soloModeServiceProvider).pauseTask(taskId);
  }

  /// Resume a paused task by ID.
  void resume(String taskId) {
    ref.read(soloModeServiceProvider).resumeTask(taskId);
  }

  /// Cancel a task by ID.
  void cancel(String taskId) {
    ref.read(soloModeServiceProvider).cancelTask(taskId);
  }

  /// Retry a failed or cancelled task by ID.
  Future<void> retry(String taskId) async {
    await ref.read(soloModeServiceProvider).retryTask(taskId);
  }

  /// Cancel all running tasks.
  void cancelAll() {
    final service = ref.read(soloModeServiceProvider);
    for (final task in service.activeTasks) {
      service.cancelTask(task.id);
    }
  }

  /// Pause all running tasks.
  void pauseAll() {
    final service = ref.read(soloModeServiceProvider);
    for (final task in service.activeTasks.where((t) => t.isRunning)) {
      service.pauseTask(task.id);
    }
  }

  /// Resume all paused tasks.
  void resumeAll() {
    final service = ref.read(soloModeServiceProvider);
    for (final task in service.activeTasks.where((t) => t.status == DeepDiveTaskStatus.paused)) {
      service.resumeTask(task.id);
    }
  }
}

/// Provider for the [DeepDiveTaskActionNotifier].
final deepDiveTaskActionProvider =
    NotifierProvider<DeepDiveTaskActionNotifier, void>(
  () => DeepDiveTaskActionNotifier(),
);

// ═══════════════════════════════════════════════════════════════════════════════
// Solo Mode Page State — Combined state for the Solo Mode page UI
// ═══════════════════════════════════════════════════════════════════════════════

/// Combined state object for the Solo Mode page.
///
/// This bundles all the state a Solo Mode page needs into a single
/// object, reducing the number of individual providers a widget
/// must watch.
@immutable
class SoloPageState {
  final DeepDiveTask? currentTask;
  final List<DeepDiveTask> activeTasks;
  final List<DeepDiveTask> completedTasks;
  final bool isRunning;
  final bool isPaused;
  final double progress;
  final int progressPercent;
  final String currentAction;
  final String elapsedTime;
  final String progressText;
  final bool showMiniBar;
  final int runningCount;
  final int queuedCount;

  const SoloPageState({
    this.currentTask,
    this.activeTasks = const [],
    this.completedTasks = const [],
    this.isRunning = false,
    this.isPaused = false,
    this.progress = 0.0,
    this.progressPercent = 0,
    this.currentAction = 'Idle',
    this.elapsedTime = '--:--',
    this.progressText = 'No active task',
    this.showMiniBar = true,
    this.runningCount = 0,
    this.queuedCount = 0,
  });

  SoloPageState copyWith({
    DeepDiveTask? currentTask,
    List<DeepDiveTask>? activeTasks,
    List<DeepDiveTask>? completedTasks,
    bool? isRunning,
    bool? isPaused,
    double? progress,
    int? progressPercent,
    String? currentAction,
    String? elapsedTime,
    String? progressText,
    bool? showMiniBar,
    int? runningCount,
    int? queuedCount,
  }) {
    return SoloPageState(
      currentTask: currentTask ?? this.currentTask,
      activeTasks: activeTasks ?? this.activeTasks,
      completedTasks: completedTasks ?? this.completedTasks,
      isRunning: isRunning ?? this.isRunning,
      isPaused: isPaused ?? this.isPaused,
      progress: progress ?? this.progress,
      progressPercent: progressPercent ?? this.progressPercent,
      currentAction: currentAction ?? this.currentAction,
      elapsedTime: elapsedTime ?? this.elapsedTime,
      progressText: progressText ?? this.progressText,
      showMiniBar: showMiniBar ?? this.showMiniBar,
      runningCount: runningCount ?? this.runningCount,
      queuedCount: queuedCount ?? this.queuedCount,
    );
  }

  /// Whether there is any meaningful state to display.
  bool get hasContent => activeTasks.isNotEmpty || completedTasks.isNotEmpty;

  /// Whether there is a currently running task.
  bool get hasRunningTask => currentTask != null;
}

/// A notifier that maintains the combined [SoloPageState].
///
/// Watches all relevant providers and rebuilds the combined state
/// whenever any of them change. Widgets can watch just this provider
/// instead of multiple individual ones.
class SoloPageStateNotifier extends Notifier<SoloPageState> {
  @override
  SoloPageState build() {
    final currentTask = ref.watch(soloCurrentTaskProvider);
    final activeTasks = ref.watch(soloActiveTasksProvider);
    final completedTasks = ref.watch(soloCompletedTasksProvider);
    final isRunning = ref.watch(soloIsRunningProvider);
    final isPaused = ref.watch(soloIsPausedProvider);
    final progress = ref.watch(soloProgressProvider);
    final progressPercent = ref.watch(soloProgressPercentProvider);
    final currentAction = ref.watch(soloCurrentActionProvider);
    final elapsedTime = ref.watch(soloElapsedTimeProvider);
    final progressText = ref.watch(soloProgressTextProvider);
    final showMiniBar = ref.watch(soloShowMiniBarProvider);
    final runningCount = ref.watch(soloRunningCountProvider);
    final queuedCount = ref.watch(soloQueuedCountProvider);

    return SoloPageState(
      currentTask: currentTask,
      activeTasks: activeTasks,
      completedTasks: completedTasks,
      isRunning: isRunning,
      isPaused: isPaused,
      progress: progress,
      progressPercent: progressPercent,
      currentAction: currentAction,
      elapsedTime: elapsedTime,
      progressText: progressText,
      showMiniBar: showMiniBar,
      runningCount: runningCount,
      queuedCount: queuedCount,
    );
  }

  /// Toggle the mini progress bar visibility.
  void toggleMiniBar() {
    final current = ref.read(soloShowMiniBarProvider);
    ref.read(soloShowMiniBarProvider.notifier).state = !current;
  }

  /// Select a task for detailed viewing.
  void selectTask(String? taskId) {
    ref.read(soloSelectedTaskIdProvider.notifier).state = taskId;
  }

  /// Clear the task history.
  Future<void> clearHistory() async {
    await DeepDiveTaskManager().clearHistory();
  }
}

/// Provider for the [SoloPageStateNotifier].
final soloPageStateProvider =
    NotifierProvider<SoloPageStateNotifier, SoloPageState>(
  () => SoloPageStateNotifier(),
);

// ═══════════════════════════════════════════════════════════════════════════════
// Mini Progress Bar State — Compact state for the floating progress indicator
// ═══════════════════════════════════════════════════════════════════════════════

/// Compact state for the mini progress bar widget.
///
/// Contains only the fields needed to render a small floating progress
/// indicator, minimizing rebuilds.
@immutable
class MiniProgressBarState {
  final bool visible;
  final double progress;
  final int progressPercent;
  final String title;
  final String subtitle;
  final bool isPaused;

  const MiniProgressBarState({
    this.visible = false,
    this.progress = 0.0,
    this.progressPercent = 0,
    this.title = '',
    this.subtitle = '',
    this.isPaused = false,
  });

  /// Whether the mini bar should actually be rendered.
  bool get shouldShow => visible && progress < 1.0;
}

/// Provider for the mini progress bar state.
final soloMiniProgressBarProvider = Provider<MiniProgressBarState>((ref) {
  final showMiniBar = ref.watch(soloShowMiniBarProvider);
  final currentTask = ref.watch(soloCurrentTaskProvider);
  final isPaused = ref.watch(soloIsPausedProvider);

  if (!showMiniBar || currentTask == null) {
    return const MiniProgressBarState();
  }

  return MiniProgressBarState(
    visible: true,
    progress: currentTask.progress.clamp(0.0, 1.0),
    progressPercent: currentTask.progressPercent,
    title: currentTask.title,
    subtitle: currentTask.currentActionDescription.isNotEmpty
        ? currentTask.currentActionDescription
        : currentTask.statusDisplay,
    isPaused: isPaused,
  );
});

// ═══════════════════════════════════════════════════════════════════════════════
// Notification Sync Provider — Keeps notifications in sync with task state
// ═══════════════════════════════════════════════════════════════════════════════

/// A provider that automatically syncs system notifications with
/// Solo Mode task state.
///
/// Watch this provider at the app root to enable automatic notifications:
/// ```dart
/// // In your app's root widget
/// ref.watch(soloNotificationSyncProvider);
/// ```
///
/// This provider has no meaningful return value — it exists purely for
/// its side effects (updating notifications).
final soloNotificationSyncProvider = Provider<void>((ref) {
  final notificationsEnabled = ref.watch(soloNotificationsEnabledProvider);
  if (!notificationsEnabled) return;

  // Watch task updates and sync notifications.
  final taskAsync = ref.watch(deepDiveTaskUpdatesProvider);

  taskAsync.whenData((task) async {
    final manager = ref.read(notificationManagerProvider);
    await manager.syncTaskNotification(task);
  });

  // Listen for task events to handle start/complete states.
  final eventsAsync = ref.watch(deepDiveTaskEventsProvider);
  eventsAsync.whenData((event) async {
    final manager = ref.read(notificationManagerProvider);
    switch (event.type) {
      case DeepDiveTaskEventType.completed:
        final task = DeepDiveModeService().getTask(event.taskId);
        if (task != null) {
          await manager.showTaskCompleted(task);
        }
        break;
      case DeepDiveTaskEventType.failed:
        final task = DeepDiveModeService().getTask(event.taskId);
        if (task != null) {
          await manager.showTaskError(
            task,
            event.message ?? 'Unknown error',
          );
        }
        break;
      case DeepDiveTaskEventType.cancelled:
        final task = DeepDiveModeService().getTask(event.taskId);
        if (task != null) {
          await manager.showTaskCancelled(task);
        }
        break;
      default:
        break;
    }
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// Initialization Provider — Bootstraps all Solo Mode services
// ═══════════════════════════════════════════════════════════════════════════════

/// Initializes all Solo Mode services.
///
/// Call this once during app startup:
/// ```dart
/// await ref.read(soloModeInitProvider.future);
/// ```
final soloModeInitProvider = FutureProvider<void>((ref) async {
  // Initialize DeepDiveModeService.
  final service = DeepDiveModeService();
  await service.initialize();

  // Initialize DeepDiveTaskManager.
  final manager = DeepDiveTaskManager();
  await manager.initialize();

  // Initialize NotificationManager.
  final notificationManager = NotificationManager();
  await notificationManager.initialize();

  // Initialize ForegroundService.
  final foregroundService = ForegroundService();
  await foregroundService.initialize();

  // Start auto-managing foreground service based on task events.
  DeepDiveModeAutoStartService().startWatching();

  // Sync notifications.
  ref.read(soloNotificationSyncProvider);

  AppErrorHandler.log('Solo Mode system initialized', tag: 'DeepDiveMode');
});
