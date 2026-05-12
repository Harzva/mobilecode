// lib/services/foreground_service.dart
// Android Foreground Service — Keeps Solo Mode Alive
//
// When Solo Mode tasks are running, this foreground service keeps the
// MobileCode app alive even when the user switches to other apps or
// the device screen is off.
//
// Why a Foreground Service is needed:
//   - Android aggressively kills background apps to free memory
//   - Without this service, Solo Mode tasks would be interrupted
//   - A foreground service shows a persistent notification that the
//     system respects — the app gets higher priority and won't be killed
//
// This service:
//   - Starts when the first Solo Mode task begins
//   - Stops when all tasks complete
//   - Shows a persistent notification with current task info
//   - Updates the notification as task progress changes
//   - Uses minimal resources when idle
//
// Required AndroidManifest.xml entries:
//   <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
//   <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
//   <service
//     android:name="com.pravera.flutter_foreground_task.ForegroundService"
//     android:foregroundServiceType="dataSync"
//     android:exported="false" />

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../core/error_handler.dart';
import 'notification_manager.dart';
import 'deep_dive_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Foreground Service
// ═══════════════════════════════════════════════════════════════════════════════

/// Android Foreground Service that keeps MobileCode alive during Solo Mode.
///
/// When Solo Mode tasks are running, the system may kill the app to free
/// memory. This foreground service prevents that by elevating the app's
/// priority. The service shows a persistent notification that informs the
/// user that background tasks are active.
///
/// ## Android Setup
///
/// Add to `AndroidManifest.xml`:
/// ```xml
/// <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
/// <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
/// <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
/// <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
///
/// <service
///   android:name="com.pravera.flutter_foreground_task.ForegroundService"
///   android:foregroundServiceType="dataSync"
///   android:exported="false" />
/// ```
///
/// ## Usage
///
/// ```dart
/// // Initialize at app startup
/// await ForegroundService.initialize();
///
/// // Start when a Solo Mode task begins
/// await ForegroundService.start(
///   title: 'Solo Mode — Creating todo app',
///   body: 'Step 3/12: Writing main.dart',
/// );
///
/// // Update as progress changes
/// await ForegroundService.update(
///   title: 'Solo Mode — Creating todo app',
///   body: 'Step 7/12: Adding navigation',
///   progress: 58,
/// );
///
/// // Stop when all tasks complete
/// await ForegroundService.stop();
/// ```
class ForegroundService with ErrorLogging {
  ForegroundService._internal();

  static final ForegroundService _instance = ForegroundService._internal();

  /// Get the singleton instance.
  factory ForegroundService() => _instance;

  @override
  String get logTag => 'ForegroundService';

  // ── Configuration ──────────────────────────────────────────────────────────

  /// Whether the foreground service has been initialized.
  bool _initialized = false;

  /// Whether the foreground service is currently running.
  bool _isRunning = false;

  /// Current notification title displayed by the service.
  String _currentTitle = 'Solo Mode';

  /// Current notification body displayed by the service.
  String _currentBody = 'Background tasks are running';

  /// Current progress percentage (0-100).
  int _currentProgress = 0;

  /// Timer for periodically checking task status.
  Timer? _statusCheckTimer;

  /// Stream subscription to Solo Mode task events.
  StreamSubscription<DeepDiveTaskEvent>? _taskEventSubscription;

  /// Stream subscription to Solo Mode task updates.
  StreamSubscription<DeepDiveTask>? _taskUpdateSubscription;

  // ── Initialization ─────────────────────────────────────────────────────────

  /// Initialize the foreground service system.
  ///
  /// Must be called once during app startup, before [start] is used.
  /// Configures the foreground task handler and notification channel.
  Future<void> initialize() async {
    if (_initialized) {
      logDebug('ForegroundService already initialized');
      return;
    }

    try {
      // Configure the foreground task options.
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'deep_dive_foreground',
          channelName: 'Solo Mode Foreground Service',
          channelDescription:
              'Keeps Solo Mode tasks running when the app is in the background',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
          playSound: false,
          enableVibration: false,
          showBadge: false,
          showWhen: true,
          visibility: NotificationVisibility.public,
          iconData: const NotificationIconData(
            resType: ResourceType.mipmap,
            resPrefix: ResourcePrefix.ic,
            name: 'launcher',
          ),
          // Buttons shown on the notification.
          buttons: const [
            NotificationButton(
              id: 'open_app',
              text: 'Open',
            ),
            NotificationButton(
              id: 'cancel_all',
              text: 'Cancel All',
            ),
          ],
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: true,
          playSound: false,
        ),
        foregroundTaskOptions: const ForegroundTaskOptions(
          // Run the service task every 5 seconds.
          interval: 5000,
          // Allow auto-run on boot.
          autoRunOnBoot: true,
          // Allow wake lock to keep CPU running during tasks.
          allowWakeLock: true,
          // Allow wifi lock to keep network available.
          allowWifiLock: true,
        ),
      );

      // Request notification permission for Android 13+.
      await _requestPermissions();

      // Listen for button taps on the notification.
      FlutterForegroundTask.addTaskDataCallback(_handleTaskData);

      _initialized = true;
      logInfo('=== ForegroundService initialized ===');
    } catch (e, st) {
      logError('Failed to initialize ForegroundService', e, st);
    }
  }

  /// Request necessary permissions.
  Future<void> _requestPermissions() async {
    try {
      // For Android 13+, request notification permission.
      final notificationGranted = await FlutterForegroundTask
          .requestNotificationPermission();
      logDebug('Notification permission: $notificationGranted');

      // Check if we can draw over system UI (for overlay features).
      if (!await FlutterForegroundTask.canDrawOverlays) {
        logDebug('Cannot draw overlays — some features may be limited');
      }

      // Check battery optimization exemption.
      final isIgnoringBatteryOptimizations = await FlutterForegroundTask
          .isIgnoringBatteryOptimizations;
      logDebug(
        'Ignoring battery optimizations: $isIgnoringBatteryOptimizations',
      );
    } catch (e) {
      logWarning('Permission request issue: $e');
    }
  }

  // ── Service Control ────────────────────────────────────────────────────────

  /// Start the foreground service.
  ///
  /// Shows a persistent notification and elevates the app's priority
  /// so Solo Mode tasks continue even when the app is backgrounded.
  ///
  /// [title] — Notification title.
  /// [body] — Notification body text.
  /// [progress] — Optional progress percentage (0-100).
  Future<void> start({
    String title = 'Solo Mode',
    String body = 'Background tasks are running',
    int progress = 0,
  }) async {
    if (!_initialized) {
      logWarning('ForegroundService not initialized, cannot start');
      return;
    }

    if (_isRunning) {
      // Already running — just update.
      await update(title: title, body: body, progress: progress);
      return;
    }

    try {
      _currentTitle = title;
      _currentBody = body;
      _currentProgress = progress;

      // Start the foreground service with a custom task handler.
      await FlutterForegroundTask.startService(
        serviceId: 25678,
        notificationTitle: title,
        notificationText: body,
        notificationIcon: null,
        callback: _startCallback,
      );

      _isRunning = true;

      // Subscribe to Solo Mode events to keep the notification in sync.
      _subscribeToTaskEvents();

      // Start periodic status check.
      _statusCheckTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _checkTaskStatus(),
      );

      logInfo('Foreground service started: "$title"');
    } catch (e, st) {
      logError('Failed to start foreground service', e, st);
    }
  }

  /// Stop the foreground service.
  ///
  /// Removes the persistent notification and allows the app to return
  /// to normal background behavior. Call this when all Solo Mode tasks
  /// have completed.
  Future<void> stop() async {
    if (!_isRunning) return;

    try {
      await FlutterForegroundTask.stopService();

      _isRunning = false;
      _statusCheckTimer?.cancel();
      _statusCheckTimer = null;

      // Unsubscribe from Solo Mode events.
      await _taskEventSubscription?.cancel();
      _taskEventSubscription = null;
      await _taskUpdateSubscription?.cancel();
      _taskUpdateSubscription = null;

      logInfo('Foreground service stopped');
    } catch (e, st) {
      logError('Failed to stop foreground service', e, st);
    }
  }

  /// Update the foreground service notification.
  ///
  /// Call this whenever task progress changes to keep the user informed.
  /// The notification updates in-place without creating a new one.
  Future<void> update({
    String? title,
    String? body,
    int? progress,
  }) async {
    if (!_isRunning) return;

    _currentTitle = title ?? _currentTitle;
    _currentBody = body ?? _currentBody;
    _currentProgress = progress ?? _currentProgress;

    try {
      // Send data to the foreground task to update notification.
      final data = <String, dynamic>{
        'type': 'update',
        'title': _currentTitle,
        'body': _currentBody,
        'progress': _currentProgress,
      };
      FlutterForegroundTask.sendDataToMain(data);

      // Update the service notification directly.
      await FlutterForegroundTask.updateService(
        notificationTitle: _currentTitle,
        notificationText: _currentBody,
      );
    } catch (e) {
      logWarning('Failed to update foreground notification: $e');
    }
  }

  /// Whether the foreground service is currently running.
  Future<bool> isRunning() async {
    return await FlutterForegroundTask.isRunningService;
  }

  /// Whether we have an active foreground service.
  bool get isActive => _isRunning;

  // ── Solo Mode Integration ──────────────────────────────────────────────────

  /// Subscribe to Solo Mode task events to auto-update the notification.
  void _subscribeToTaskEvents() {
    // Listen for task lifecycle events.
    _taskEventSubscription = DeepDiveModeService()
        .taskEvents
        .listen((event) async {
      switch (event.type) {
        case DeepDiveTaskEventType.started:
          final task = DeepDiveModeService().currentRunningTask;
          if (task != null) {
            await update(
              title: '\u{1F916} Solo Mode — ${task.title}',
              body: 'Running...',
              progress: 0,
            );
          }
          break;

        case DeepDiveTaskEventType.completed:
          // Check if any tasks are still running.
          if (!DeepDiveModeService().hasRunningTask) {
            await update(
              title: '\u{2705} Solo Mode — All Complete',
              body: 'All background tasks finished successfully',
              progress: 100,
            );
            // Stop the service after a short delay so the user sees
            // the completion message.
            await Future.delayed(const Duration(seconds: 5));
            await stop();
          }
          break;

        case DeepDiveTaskEventType.failed:
          final allFailed = DeepDiveModeService().activeTasks.every((t) => t.isFailed);
          if (allFailed) {
            await update(
              title: '\u{274C} Solo Mode — Failed',
              body: event.message ?? 'A task failed',
              progress: 0,
            );
            await Future.delayed(const Duration(seconds: 10));
            await stop();
          }
          break;

        case DeepDiveTaskEventType.cancelled:
          if (!DeepDiveModeService().hasRunningTask) {
            await stop();
          }
          break;

        default:
          break;
      }
    });

    // Listen for task progress updates.
    _taskUpdateSubscription = DeepDiveModeService()
        .taskUpdates
        .listen((task) async {
      if (task.isRunning) {
        await update(
          title: '\u{1F916} Solo Mode — ${task.title}',
          body:
              '${task.currentActionDescription} (${task.currentStep + 1}/${task.totalSteps})',
          progress: task.progressPercent,
        );
      }
    });
  }

  /// Periodic check of task status to ensure the service stays in sync.
  void _checkTaskStatus() async {
    final service = DeepDiveModeService();

    if (!service.hasRunningTask) {
      // No tasks running — we can stop the service.
      logDebug('No running tasks detected, stopping foreground service');
      await stop();
      return;
    }

    // Update with the latest running task info.
    final task = service.currentRunningTask;
    if (task != null) {
      await update(
        title: '\u{1F916} Solo Mode — ${task.title}',
        body:
            '${task.currentActionDescription} (${task.currentStep + 1}/${task.totalSteps})',
        progress: task.progressPercent,
      );
    }
  }

  // ── Task Data Handling ─────────────────────────────────────────────────────

  /// Handle data received from the foreground task.
  void _handleTaskData(Object data) {
    if (data is! Map<String, dynamic>) return;

    final type = data['type'] as String?;
    switch (type) {
      case 'button_tap':
        final buttonId = data['buttonId'] as String?;
        _handleButtonTap(buttonId);
        break;
      case 'update':
        // Handle update confirmation if needed.
        break;
      default:
        break;
    }
  }

  /// Handle notification button taps.
  void _handleButtonTap(String? buttonId) {
    switch (buttonId) {
      case 'open_app':
        // Emit event for the app to handle navigation.
        SoloNavigationEventBus.emit(
          SoloNavigationEvent(taskId: 'all', action: 'open'),
        );
        break;
      case 'cancel_all':
        DeepDiveModeService().dispose();
        break;
    }
  }

  // ── Diagnostics ────────────────────────────────────────────────────────────

  /// Get diagnostic information about the foreground service.
  Map<String, dynamic> getDiagnostics() {
    return {
      'initialized': _initialized,
      'isRunning': _isRunning,
      'currentTitle': _currentTitle,
      'currentBody': _currentBody,
      'currentProgress': _currentProgress,
    };
  }

  /// Log diagnostics.
  void logDiagnostics() {
    logInfo('=== ForegroundService Diagnostics ===');
    getDiagnostics().forEach((key, value) {
      logInfo('  $key: $value');
    });
    logInfo('======================================');
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Foreground Task Handler (runs inside the service isolate)
// ═══════════════════════════════════════════════════════════════════════════════

/// The callback that starts the foreground task handler.
///
/// This function reference is passed to [FlutterForegroundTask.startService]
/// and is invoked in the service's own isolate.
@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_DeepDiveModeTaskHandler());
}

/// Task handler that runs inside the foreground service isolate.
///
/// This handler receives data from the main app and can send data back.
/// It manages the service lifecycle and handles button tap events.
class _DeepDiveModeTaskHandler extends TaskHandler {
  /// Periodic timer for the service's own heartbeat.
  Timer? _heartbeatTimer;

  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {
    // Called when the foreground service starts.
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) {
        // Send a heartbeat to the main thread to confirm we're alive.
        FlutterForegroundTask.sendDataToMain(<String, dynamic>{
          'type': 'heartbeat',
          'timestamp': DateTime.now().toIso8601String(),
        });
      },
    );
  }

  @override
  Future<void> onEvent(DateTime timestamp, SendPort? sendPort) async {
    // Called periodically based on the interval configured in
    // [ForegroundTaskOptions]. We use this to request status updates
    // from the main thread.
    FlutterForegroundTask.sendDataToMain(<String, dynamic>{
      'type': 'status_request',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {
    // Called when the foreground service is destroyed.
    _heartbeatTimer?.cancel();
  }

  @override
  void onButtonPressed(String id) {
    // Called when a notification button is pressed.
    FlutterForegroundTask.sendDataToMain(<String, dynamic>{
      'type': 'button_tap',
      'buttonId': id,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  @override
  void onNotificationPressed() {
    // Called when the notification itself is pressed.
    FlutterForegroundTask.sendDataToMain(<String, dynamic>{
      'type': 'notification_tap',
      'timestamp': DateTime.now().toIso8601String(),
    });
    // Launch the app if it's not in the foreground.
    FlutterForegroundTask.launchApp('/solo');
  }

  @override
  void onNotificationDismissed() {
    // Called when the user swipes away the notification.
    // For ongoing notifications this won't be called (they can't be
    // dismissed), but if we make it non-ongoing, handle here.
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Auto-Start Service — Watches Solo Mode and manages service lifecycle
// ═══════════════════════════════════════════════════════════════════════════════

/// Automatically manages the foreground service based on Solo Mode state.
///
/// This is a convenience class that watches [DeepDiveModeService] and
/// automatically starts/stops the foreground service as needed.
/// Simply instantiate it and call [startWatching]:
///
/// ```dart
/// final autoStart = DeepDiveModeAutoStartService();
/// autoStart.startWatching();
/// ```
class DeepDiveModeAutoStartService with ErrorLogging {
  DeepDiveModeAutoStartService._internal();

  static final DeepDiveModeAutoStartService _instance =
      DeepDiveModeAutoStartService._internal();

  factory DeepDiveModeAutoStartService() => _instance;

  @override
  String get logTag => 'DeepDiveModeAutoStart';

  StreamSubscription<DeepDiveTaskEvent>? _eventSubscription;
  bool _isWatching = false;

  /// Start watching Solo Mode and auto-manage the foreground service.
  void startWatching() {
    if (_isWatching) return;

    _eventSubscription = DeepDiveModeService()
        .taskEvents
        .listen((event) async {
      final fgService = ForegroundService();

      switch (event.type) {
        case DeepDiveTaskEventType.started:
          if (!fgService.isActive) {
            final task = DeepDiveModeService().currentRunningTask;
            if (task != null) {
              await fgService.start(
                title: '\u{1F916} Solo Mode — ${task.title}',
                body: task.currentActionDescription,
              );
            }
          }
          break;

        case DeepDiveTaskEventType.completed:
        case DeepDiveTaskEventType.failed:
        case DeepDiveTaskEventType.cancelled:
          if (!DeepDiveModeService().hasRunningTask && fgService.isActive) {
            await fgService.stop();
          }
          break;

        default:
          break;
      }
    });

    _isWatching = true;
    logInfo('Auto-start service watching');
  }

  /// Stop watching Solo Mode events.
  void stopWatching() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _isWatching = false;
    logInfo('Auto-start service stopped watching');
  }

  /// Whether the auto-start service is currently watching.
  bool get isWatching => _isWatching;
}
