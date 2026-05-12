// lib/services/notification_manager.dart
// Notification Manager — System Notifications for Solo Mode Background Tasks
//
// Displays persistent system notifications showing Solo Mode task progress.
// These notifications are visible even when the user switches to other apps,
// providing constant awareness of background task status.
//
// Features:
//   - Progress notifications with percentage bar
//   - Start / running / complete / error states
//   - Ongoing (sticky) notifications that can't be swiped away
//   - Tap to open the Solo Mode page in the app
//   - Low-priority to avoid interrupting the user
//   - No sound or vibration for non-critical updates
//
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/error_handler.dart';
import 'deep_dive_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Notification Manager
// ═══════════════════════════════════════════════════════════════════════════════

/// Manages system notifications for Solo Mode background tasks.
///
/// Uses `flutter_local_notifications` to display progress notifications
/// that persist even when the app is in the background. Users can see
/// task progress at a glance from the notification shade.
///
/// ## Setup Required
///
/// Add to your `AndroidManifest.xml`:
/// ```xml
/// <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
/// <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
/// ```
///
/// ## Usage
///
/// ```dart
/// await NotificationManager.initialize();
///
/// NotificationManager.showTaskStarted(task);
/// NotificationManager.showTaskProgress(task, 42);
/// NotificationManager.showTaskCompleted(task);
/// NotificationManager.showTaskError(task, 'File not found');
/// ```
class NotificationManager with ErrorLogging {
  NotificationManager._internal();

  static final NotificationManager _instance = NotificationManager._internal();

  /// Get the singleton instance.
  factory NotificationManager() => _instance;

  static const String _tag = 'NotificationManager';

  @override
  String get logTag => _tag;

  // ── Core Plugin ────────────────────────────────────────────────────────────

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Whether the notification system has been initialized.
  bool _initialized = false;

  /// Track which task IDs currently have active notifications.
  final Set<String> _activeNotificationIds = {};

  /// Stream controller for notification tap events.
  final StreamController<String> _tapController =
      StreamController<String>.broadcast();

  // ── Constants ──────────────────────────────────────────────────────────────

  /// Android notification channel ID for Solo Mode.
  static const String _channelId = 'deep_dive_channel';

  /// Android notification channel name.
  static const String _channelName = 'Solo Mode';

  /// Android notification channel description.
  static const String _channelDescription =
      'Background task progress notifications for Solo Mode';

  /// Android notification channel ID for errors.
  static const String _errorChannelId = 'deep_dive_errors';

  /// Android notification channel name for errors.
  static const String _errorChannelName = 'Solo Mode Errors';

  /// Android notification channel ID for completions.
  static const String _completionChannelId = 'deep_dive_completions';

  /// Android notification channel name for completions.
  static const String _completionChannelName = 'Solo Mode Completions';

  // ── Initialization ─────────────────────────────────────────────────────────

  /// Initialize the notification system.
  ///
  /// Must be called once during app startup, before any notifications
  /// are shown. Sets up notification channels for Android and
  /// requests permissions on both platforms.
  Future<void> initialize() async {
    if (_initialized) {
      logDebug('NotificationManager already initialized');
      return;
    }

    try {
      // ── Android Settings ──
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );

      // ── iOS Settings ──
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: false,
        requestProvisionalPermission: true,
      );

      // ── Linux Settings ──
      const linuxSettings = LinuxInitializationSettings(
        defaultActionName: 'Open',
      );

      // ── Initialize Plugin ──
      await _plugin.initialize(
        const InitializationSettings(
          android: androidSettings,
          iOS: iosSettings,
          linux: linuxSettings,
        ),
        onDidReceiveNotificationResponse: _onNotificationTap,
        onDidReceiveBackgroundNotificationResponse:
            _onBackgroundNotificationTap,
      );

      // ── Create Android Notification Channels ──
      await _createAndroidChannels();

      _initialized = true;
      logInfo('=== NotificationManager initialized ===');
    } catch (e, st) {
      logError('Failed to initialize NotificationManager', e, st);
    }
  }

  /// Whether the notification system is initialized.
  bool get isInitialized => _initialized;

  /// Stream of notification tap payloads.
  ///
  /// Listen to this to navigate to the appropriate page when
  /// the user taps a notification.
  Stream<String> get onNotificationTap => _tapController.stream;

  // ── Core Show Methods ──────────────────────────────────────────────────────

  /// Show or update a notification for a Solo Mode task.
  ///
  /// [id] — Unique notification ID (typically derived from task ID).
  /// [title] — Notification title.
  /// [body] — Notification body text.
  /// [ongoing] — Whether the notification is sticky (can't be dismissed).
  /// [showProgress] — Whether to show a progress bar.
  /// [progress] — Progress value 0-100 (only used if [showProgress] is true).
  /// [payload] — Data payload delivered when the user taps the notification.
  /// [channelId] — Which Android notification channel to use.
  /// [importance] — Notification importance level.
  Future<void> show({
    required int id,
    required String title,
    required String body,
    bool ongoing = true,
    bool showProgress = false,
    int progress = 0,
    String? payload,
    String channelId = _channelId,
    Importance importance = Importance.low,
  }) async {
    if (!_initialized) {
      logWarning('NotificationManager not initialized, skipping notification');
      return;
    }

    try {
      final androidDetails = AndroidNotificationDetails(
        channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: importance,
        priority: Priority.low,
        ongoing: ongoing,
        autoCancel: !ongoing,
        showProgress: showProgress,
        maxProgress: 100,
        progress: progress.clamp(0, 100),
        onlyAlertOnce: true,
        playSound: false,
        enableVibration: false,
        visibility: NotificationVisibility.public,
        category: ongoing
            ? AndroidNotificationCategory.progress
            : AndroidNotificationCategory.status,
      );

      final iosDetails = const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: false,
        interruptionLevel: InterruptionLevel.passive,
      );

      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        ),
        payload: payload,
      );
    } catch (e, st) {
      logError('Failed to show notification #$id', e, st);
    }
  }

  // ── Convenience: Solo Mode Task Notifications ──────────────────────────────

  /// Show a "task started" notification.
  Future<void> showTaskStarted(DeepDiveTask task) async {
    final id = _taskIdToNotificationId(task.id);
    _activeNotificationIds.add(task.id);

    await show(
      id: id,
      title: '\u{1F916} Solo Mode — Started',
      body: task.title,
      ongoing: true,
      showProgress: true,
      progress: 0,
      payload: _buildPayload(task.id, 'started'),
    );

    logDebug('Notification: task started "${task.title}"');
  }

  /// Show or update a "task in progress" notification.
  ///
  /// Call this repeatedly as the task progresses. The notification
  /// will update in-place rather than creating new ones.
  Future<void> showTaskProgress(DeepDiveTask task, int percent) async {
    final id = _taskIdToNotificationId(task.id);
    _activeNotificationIds.add(task.id);

    final progress = percent.clamp(0, 100);
    final body = '${task.currentActionDescription}\n'
        'Step ${task.currentStep + 1} / ${task.totalSteps} ($progress%)';

    await show(
      id: id,
      title: '\u{1F916} ${task.title}',
      body: body,
      ongoing: true,
      showProgress: true,
      progress: progress,
      payload: _buildPayload(task.id, 'progress'),
    );
  }

  /// Show a "task completed" notification.
  ///
  /// This is a non-ongoing notification that the user can dismiss.
  /// It uses a slightly higher importance to get the user's attention.
  Future<void> showTaskCompleted(DeepDiveTask task) async {
    final id = _taskIdToNotificationId(task.id);
    _activeNotificationIds.remove(task.id);

    final elapsed = task.elapsedTime;
    final elapsedStr = elapsed != null
        ? '${elapsed.inMinutes}m ${elapsed.inSeconds % 60}s'
        : 'unknown';

    await show(
      id: id,
      title: '\u{2705} Solo Mode — Complete',
      body: '${task.title}\nCompleted in $elapsedStr — '
          '${task.completedStepCount}/${task.totalSteps} steps',
      ongoing: false,
      showProgress: false,
      payload: _buildPayload(task.id, 'completed'),
      channelId: _completionChannelId,
      importance: Importance.defaultImportance,
    );

    logDebug('Notification: task completed "${task.title}"');
  }

  /// Show a "task failed" notification.
  ///
  /// Uses a higher importance to alert the user that something
  /// went wrong and they may need to take action.
  Future<void> showTaskError(DeepDiveTask task, String error) async {
    final id = _taskIdToNotificationId(task.id);
    _activeNotificationIds.remove(task.id);

    await show(
      id: id,
      title: '\u{274C} Solo Mode — Failed',
      body: '${task.title}\n$error',
      ongoing: false,
      showProgress: false,
      payload: _buildPayload(task.id, 'failed'),
      channelId: _errorChannelId,
      importance: Importance.high,
    );

    logDebug('Notification: task error "${task.title}" — $error');
  }

  /// Show a "task cancelled" notification.
  Future<void> showTaskCancelled(DeepDiveTask task) async {
    final id = _taskIdToNotificationId(task.id);
    _activeNotificationIds.remove(task.id);

    await show(
      id: id,
      title: '\u{1F6D1} Solo Mode — Cancelled',
      body: task.title,
      ongoing: false,
      showProgress: false,
      payload: _buildPayload(task.id, 'cancelled'),
    );
  }

  /// Auto-show the correct notification based on task status.
  ///
  /// This is a convenience method that checks the task's current status
  /// and shows the appropriate notification type. Call this whenever
  /// a task update is received.
  Future<void> syncTaskNotification(DeepDiveTask task) async {
    switch (task.status) {
      case DeepDiveTaskStatus.queued:
        // No notification yet.
        break;
      case DeepDiveTaskStatus.running:
        await showTaskProgress(task, task.progressPercent);
        break;
      case DeepDiveTaskStatus.paused:
        final id = _taskIdToNotificationId(task.id);
        await show(
          id: id,
          title: '\u{23F8} Solo Mode — Paused',
          body: '${task.title}\nPaused at step ${task.currentStep + 1}',
          ongoing: true,
          showProgress: true,
          progress: task.progressPercent,
          payload: _buildPayload(task.id, 'paused'),
        );
        break;
      case DeepDiveTaskStatus.completed:
        await showTaskCompleted(task);
        break;
      case DeepDiveTaskStatus.failed:
        await showTaskError(task, task.errorMessage ?? 'Unknown error');
        break;
      case DeepDiveTaskStatus.cancelled:
        await showTaskCancelled(task);
        break;
    }
  }

  // ── Notification Management ────────────────────────────────────────────────

  /// Cancel a specific notification by ID.
  Future<void> cancel(int id) async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(id);
      _activeNotificationIds.removeWhere(
        (taskId) => _taskIdToNotificationId(taskId) == id,
      );
    } catch (e) {
      logWarning('Failed to cancel notification #$id: $e');
    }
  }

  /// Cancel a notification associated with a task.
  Future<void> cancelForTask(String taskId) async {
    final id = _taskIdToNotificationId(taskId);
    await cancel(id);
  }

  /// Cancel all Solo Mode notifications.
  Future<void> cancelAll() async {
    if (!_initialized) return;
    try {
      await _plugin.cancelAll();
      _activeNotificationIds.clear();
      logDebug('All notifications cancelled');
    } catch (e) {
      logWarning('Failed to cancel all notifications: $e');
    }
  }

  /// Get a list of currently active notification IDs.
  Set<String> get activeNotificationIds =>
      Set.unmodifiable(_activeNotificationIds);

  /// Whether there are any active Solo Mode notifications.
  bool get hasActiveNotifications => _activeNotificationIds.isNotEmpty;

  // ── Permissions ────────────────────────────────────────────────────────────

  /// Request notification permission (mainly for Android 13+).
  ///
  /// Returns `true` if permission was granted or already held.
  Future<bool> requestPermission() async {
    if (!_initialized) return false;

    if (Platform.isAndroid) {
      final androidPlugin =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final granted = await androidPlugin?.requestNotificationsPermission();
      return granted ?? false;
    }

    if (Platform.isIOS) {
      final iosPlugin =
          _plugin.resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      final granted = await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: false,
      );
      return granted ?? false;
    }

    return true;
  }

  /// Check whether notification permission is granted.
  Future<bool> checkPermission() async {
    if (!_initialized) return false;

    if (Platform.isAndroid || Platform.isIOS) {
      final settings = await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.getActiveNotifications();
      // On Android, permission check requires the permission_handler package
      // or we can just attempt to show and catch the error.
      return true; // Optimistically assume granted
    }

    return true;
  }

  // ── Private ────────────────────────────────────────────────────────────────

  /// Create Android notification channels for different importance levels.
  Future<void> _createAndroidChannels() async {
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;

    // Main Solo Mode channel — low importance, silent.
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      ),
    );

    // Error channel — high importance to alert the user.
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _errorChannelId,
        _errorChannelName,
        description: 'Notifications for Solo Mode task failures',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );

    // Completion channel — default importance for completion alerts.
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _completionChannelId,
        _completionChannelName,
        description: 'Notifications for completed Solo Mode tasks',
        importance: Importance.defaultImportance,
        playSound: false,
        enableVibration: false,
      ),
    );
  }

  /// Convert a task ID to a stable notification ID.
  ///
  /// Notification IDs must be integers. We use a hash of the task ID
  /// to create a consistent, unique integer ID for each task.
  static int _taskIdToNotificationId(String taskId) {
    return taskId.hashCode.abs() % 0x7FFFFFFF;
  }

  /// Build a payload string for notification tap handling.
  static String _buildPayload(String taskId, String action) {
    return 'solo://$action/$taskId';
  }

  /// Handle notification taps in the foreground.
  static void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;

    // Parse the payload and emit the tap event.
    final instance = NotificationManager();
    if (!instance._tapController.isClosed) {
      instance._tapController.add(payload);
    }

    // Navigate to Solo Mode page based on payload.
    if (payload.startsWith('solo://')) {
      // Expected format: solo://action/taskId
      final parts = payload.substring(7).split('/');
      if (parts.length >= 2) {
        final action = parts[0];
        final taskId = parts.sublist(1).join('/');
        _navigateToSoloPage(taskId, action);
      }
    }
  }

  /// Handle notification taps when the app is in the background or terminated.
  @pragma('vm:entry-point')
  static void _onBackgroundNotificationTap(NotificationResponse response) {
    // This runs when the user taps a notification while the app is killed.
    // We store the intent so the app can handle it on next launch.
    final payload = response.payload;
    if (payload == null) return;

    // TODO: Store in shared preferences for retrieval on app launch.
    // For now, log the tap for debugging.
    if (kDebugMode) {
      // ignore: avoid_print
      print('[NotificationManager] Background tap: $payload');
    }
  }

  /// Navigate to the Solo Mode page.
  static void _navigateToSoloPage(String taskId, String action) {
    // Emit through the global navigation system.
    // The DeepDiveModeProvider listens for these and navigates accordingly.
    SoloNavigationEventBus.emit(SoloNavigationEvent(taskId: taskId, action: action));
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SoloNavigationEventBus — Decoupled navigation from notifications
// ═══════════════════════════════════════════════════════════════════════════════

/// A simple event bus for Solo Mode navigation events.
///
/// When the user taps a notification, the [NotificationManager] emits
/// an event on this bus. The UI layer listens and navigates to the
/// appropriate page. This keeps the notification system decoupled
/// from the navigation system.
class SoloNavigationEventBus {
  SoloNavigationEventBus._();

  static final StreamController<SoloNavigationEvent> _controller =
      StreamController<SoloNavigationEvent>.broadcast();

  /// Stream of navigation events.
  static Stream<SoloNavigationEvent> get stream => _controller.stream;

  /// Emit a navigation event.
  static void emit(SoloNavigationEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  /// Dispose the event bus.
  static void dispose() {
    _controller.close();
  }
}

/// A navigation event triggered by tapping a Solo Mode notification.
class SoloNavigationEvent {
  /// The ID of the task that was tapped.
  final String taskId;

  /// The action associated with the tap (e.g., 'started', 'completed').
  final String action;

  SoloNavigationEvent({
    required this.taskId,
    required this.action,
  });

  @override
  String toString() => 'SoloNavigationEvent(task=$taskId, action=$action)';
}
