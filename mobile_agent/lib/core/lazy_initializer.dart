import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// LAZY INITIALIZER
// ═══════════════════════════════════════════════════════════════════════════════

/// Lazy Initializer
///
/// Defers initialization of non-critical services until the optimal moment,
/// improving app startup time by 200-800ms.
///
/// Services can be registered with different triggers:
/// - [LazyLoadTrigger.onIdle]: Initialize after the first frame renders
/// - [LazyLoadTrigger.onNavigate]: Initialize when user navigates to the feature
/// - [LazyLoadTrigger.delayed]: Initialize after a specified delay
/// - [LazyLoadTrigger.onDemand]: Only when explicitly requested
/// - [LazyLoadTrigger.never]: Manual initialization only
///
/// ## Usage
/// ```dart
/// // Register services during app setup
/// LazyInitializer.register<GitHubService>(
///   id: 'github',
///   name: 'GitHub Service',
///   initializer: () => GitHubService.create(),
///   trigger: LazyLoadTrigger.onIdle,
///   priority: 10,
/// );
///
/// // Trigger initialization
/// LazyInitializer.markIdle(); // Triggers onIdle services
///
/// // Or initialize on demand
/// final service = await LazyInitializer.initializeNow<GitHubService>('github');
/// ```
class LazyInitializer {
  LazyInitializer._();

  // ── Internal Registry ──────────────────────────────────────────────

  static final Map<String, _LazyEntry> _registry = {};
  static final Set<String> _pendingInitializations = {};
  static bool _isIdle = false;
  static bool _isInitializing = false;

  /// Whether the app has reached idle state (first frame rendered).
  static bool get isIdle => _isIdle;

  /// Whether any lazy initialization is currently in progress.
  static bool get isInitializing => _isInitializing;

  /// Number of registered services.
  static int get registeredCount => _registry.length;

  /// Number of fully initialized services.
  static int get initializedCount =>
      _registry.values.where((e) => e.isInitialized).length;

  // ── Registration ───────────────────────────────────────────────────

  /// Register a service for lazy initialization.
  ///
  /// [id] — Unique identifier for the service.
  /// [name] — Human-readable name for logging.
  /// [initializer] — Factory function that creates the service.
  /// [trigger] — When to initialize the service (default: onIdle).
  /// [delay] — Additional delay before initialization (for delayed trigger).
  /// [priority] — Higher priority services are initialized first (default: 0).
  static void register<T>({
    required String id,
    required String name,
    required Future<T> Function() initializer,
    LazyLoadTrigger trigger = LazyLoadTrigger.onIdle,
    Duration? delay,
    int priority = 0,
  }) {
    if (_registry.containsKey(id)) {
      debugPrint(
        '[LazyInitializer] Warning: Service $id is already registered. '
        'Overwriting previous registration.',
      );
    }

    _registry[id] = _LazyEntry<T>(
      id: id,
      name: name,
      initializer: initializer,
      trigger: trigger,
      delay: delay,
      priority: priority,
    );

    debugPrint(
      '[LazyInitializer] Registered: $name (id: $id, trigger: $trigger, '
      'priority: $priority)',
    );
  }

  /// Register multiple services at once.
  static void registerAll(List<LazyRegistration> registrations) {
    for (final reg in registrations) {
      register(
        id: reg.id,
        name: reg.name,
        initializer: reg.initializer,
        trigger: reg.trigger,
        delay: reg.delay,
        priority: reg.priority,
      );
    }
  }

  // ── Initialization ─────────────────────────────────────────────────

  /// Initialize all services matching the given trigger.
  ///
  /// Services are sorted by priority (highest first) and initialized
  /// sequentially to avoid overwhelming the system.
  static Future<void> initializeAll(LazyLoadTrigger trigger) async {
    final entries = _registry.values
        .where((e) => e.trigger == trigger && !e.isInitialized)
        .toList();

    if (entries.isEmpty) return;

    // Sort by priority (highest first)
    entries.sort((a, b) => b.priority.compareTo(a.priority));

    debugPrint(
      '[LazyInitializer] Initializing ${entries.length} services '
      'for trigger: $trigger',
    );

    _isInitializing = true;

    for (final entry in entries) {
      if (entry.isInitialized) continue;

      try {
        await entry.initialize();
      } catch (e, stackTrace) {
        debugPrint(
          '[LazyInitializer] Failed to initialize ${entry.name}: $e\n'
          '$stackTrace',
        );
      }
    }

    _isInitializing = false;
  }

  /// Initialize a specific service on demand.
  ///
  /// Returns the initialized service value. If the service is already
  /// initialized, returns the cached value immediately.
  ///
  /// Throws if the service is not registered.
  static Future<T> initializeNow<T>(String id) async {
    final entry = _registry[id];
    if (entry == null) {
      throw LazyInitializerException('Service "$id" is not registered');
    }
    return await entry.initialize() as T;
  }

  /// Try to initialize a service, returning null on failure.
  static Future<T?> tryInitializeNow<T>(String id) async {
    try {
      return await initializeNow<T>(id);
    } catch (e) {
      debugPrint('[LazyInitializer] tryInitializeNow failed for $id: $e');
      return null;
    }
  }

  /// Initialize a service only if it hasn't been initialized yet.
  static Future<T?> initializeIfNeeded<T>(String id) async {
    final entry = _registry[id];
    if (entry == null) return null;
    if (entry.isInitialized) return entry.value as T?;
    return await entry.initialize() as T;
  }

  // ── Idle Trigger ───────────────────────────────────────────────────

  /// Mark the app as idle (first frame has rendered).
  ///
  /// This triggers all [LazyLoadTrigger.onIdle] services to initialize.
  /// Should be called from a post-frame callback.
  static void markIdle() {
    if (_isIdle) return;
    _isIdle = true;

    debugPrint('[LazyInitializer] App marked idle — starting idle services');

    // Trigger idle-initialized services in the background
    initializeAll(LazyLoadTrigger.onIdle);

    // Also schedule delayed services
    _scheduleDelayedServices();
  }

  /// Schedule a callback to mark idle after the next frame.
  static void scheduleMarkIdle() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      markIdle();
    });
  }

  // ── Pre-warming ────────────────────────────────────────────────────

  /// Pre-warm a service (initialize before user needs it).
  ///
  /// This is useful when you anticipate the user will need a service soon,
  /// e.g., pre-warming the GitHub service when the user opens the code tab.
  static Future<void> prewarm(String id) async {
    final entry = _registry[id];
    if (entry != null && !entry.isInitialized) {
      // Use a microtask to avoid blocking the current frame
      scheduleMicrotask(() async {
        try {
          await entry.initialize();
        } catch (e) {
          debugPrint('[LazyInitializer] Prewarm failed for ${entry.name}: $e');
        }
      });
    }
  }

  /// Pre-warm multiple services by their IDs.
  static Future<void> prewarmAll(List<String> ids) async {
    for (final id in ids) {
      await prewarm(id);
    }
  }

  // ── Status & Introspection ────────────────────────────────────────

  /// Get initialization status for all registered services.
  static Map<String, bool> getStatus() {
    return {
      for (final entry in _registry.entries)
        entry.value.name: entry.value.isInitialized,
    };
  }

  /// Get a detailed status report.
  static Map<String, dynamic> getDetailedStatus() {
    final status = <String, dynamic>{};

    for (final entry in _registry.values) {
      status[entry.id] = {
        'name': entry.name,
        'initialized': entry.isInitialized,
        'trigger': entry.trigger.toString(),
        'priority': entry.priority,
        'initTimeMs': entry.initTimeMs,
      };
    }

    return status;
  }

  /// Check if a service is initialized.
  static bool isInitialized(String id) {
    return _registry[id]?.isInitialized ?? false;
  }

  /// Get an initialized service value, or null if not ready.
  static T? getValue<T>(String id) {
    return _registry[id]?.value as T?;
  }

  /// Wait for a service to be initialized.
  static Future<T> waitFor<T>(String id, {Duration? timeout}) async {
    final entry = _registry[id];
    if (entry == null) {
      throw LazyInitializerException('Service "$id" is not registered');
    }

    if (entry.isInitialized) return entry.value as T;

    // Wait for initialization with optional timeout
    final completer = Completer<T>();

    entry.addOnInitialized(() {
      if (!completer.isCompleted) {
        completer.complete(entry.value as T);
      }
    });

    if (timeout != null) {
      return completer.future.timeout(
        timeout,
        onTimeout: () => throw LazyInitializerException(
          'Timeout waiting for service "$id"',
        ),
      );
    }

    return completer.future;
  }

  // ── Navigation Trigger ─────────────────────────────────────────────

  /// Call this when navigating to a feature to trigger its services.
  static Future<void> onNavigate(String featureId) async {
    final entries = _registry.values
        .where(
          (e) =>
              e.trigger == LazyLoadTrigger.onNavigate &&
              !e.isInitialized &&
              e.id.startsWith(featureId),
        )
        .toList();

    for (final entry in entries) {
      try {
        await entry.initialize();
      } catch (e) {
        debugPrint(
          '[LazyInitializer] Nav-triggered init failed for ${entry.name}: $e',
        );
      }
    }
  }

  // ── Cleanup ────────────────────────────────────────────────────────

  /// Reset all registrations (useful for testing).
  static void reset() {
    _registry.clear();
    _pendingInitializations.clear();
    _isIdle = false;
    _isInitializing = false;
  }

  /// Dispose a specific service and remove it from the registry.
  static Future<void> dispose(String id) async {
    final entry = _registry.remove(id);
    if (entry != null && entry.value is ChangeNotifier) {
      (entry.value as ChangeNotifier).dispose();
    }
  }

  // ── Private ────────────────────────────────────────────────────────

  static void _scheduleDelayedServices() {
    final entries = _registry.values
        .where(
          (e) =>
              e.trigger == LazyLoadTrigger.delayed &&
              !e.isInitialized &&
              e.delay != null,
        )
        .toList();

    for (final entry in entries) {
      Future.delayed(entry.delay!, () async {
        try {
          await entry.initialize();
        } catch (e) {
          debugPrint(
            '[LazyInitializer] Delayed init failed for ${entry.name}: $e',
          );
        }
      });
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LAZY LOAD TRIGGER ENUM
// ═══════════════════════════════════════════════════════════════════════════════

/// Defines when a lazy-registered service should be initialized.
enum LazyLoadTrigger {
  /// Initialize after the first frame renders (app is idle).
  ///
  /// This is the default and best for most background services that
  /// the user doesn't immediately need.
  onIdle,

  /// Initialize when the user navigates to the relevant feature.
  ///
  /// The app should call [LazyInitializer.onNavigate] with the feature ID
  /// when the user opens that feature.
  onNavigate,

  /// Initialize after a specified delay.
  ///
  /// Use [LazyLoadTrigger.delayed] with a [Duration] for services that
  /// should start after a fixed time (e.g., 3 seconds after startup).
  delayed,

  /// Only initialize when explicitly requested via [initializeNow].
  ///
  /// Use for optional features that most users won't need.
  onDemand,

  /// Never initialize automatically — only via manual [initializeNow].
  never,
}

// ═══════════════════════════════════════════════════════════════════════════════
// INTERNAL: LAZY ENTRY
// ═══════════════════════════════════════════════════════════════════════════════

/// Internal representation of a lazily-initialized service.
class _LazyEntry<T> {
  final String id;
  final String name;
  final Future<T> Function() initializer;
  final LazyLoadTrigger trigger;
  final Duration? delay;
  final int priority;

  T? _value;
  bool _isInitialized = false;
  int? _initTimeMs;
  final List<VoidCallback> _onInitializedCallbacks = [];

  _LazyEntry({
    required this.id,
    required this.name,
    required this.initializer,
    required this.trigger,
    this.delay,
    required this.priority,
  });

  /// Whether this service has been initialized.
  bool get isInitialized => _isInitialized;

  /// The initialized value (null if not yet initialized).
  T? get value => _value;

  /// Time taken to initialize in milliseconds (null if not initialized).
  int? get initTimeMs => _initTimeMs;

  /// Initialize the service.
  ///
  /// If already initialized, returns the cached value immediately.
  /// Measures and logs initialization time.
  Future<T> initialize() async {
    if (_isInitialized) return _value as T;

    // Apply delay if specified
    if (delay != null) {
      await Future.delayed(delay!);
    }

    final stopwatch = Stopwatch()..start();

    try {
      _value = await initializer();
      _isInitialized = true;
      stopwatch.stop();
      _initTimeMs = stopwatch.elapsedMilliseconds;

      debugPrint(
        '[LazyInitializer] Initialized: $name in ${stopwatch.elapsedMilliseconds}ms',
      );

      // Notify listeners
      for (final callback in _onInitializedCallbacks) {
        callback();
      }

      return _value as T;
    } catch (e) {
      stopwatch.stop();
      debugPrint(
        '[LazyInitializer] Error initializing $name after '
        '${stopwatch.elapsedMilliseconds}ms: $e',
      );
      rethrow;
    }
  }

  /// Add a callback to be called when initialization completes.
  void addOnInitialized(VoidCallback callback) {
    if (_isInitialized) {
      callback();
    } else {
      _onInitializedCallbacks.add(callback);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LAZY REGISTRATION HELPER
// ═══════════════════════════════════════════════════════════════════════════════

/// A helper class for batch service registration.
class LazyRegistration {
  final String id;
  final String name;
  final Future<dynamic> Function() initializer;
  final LazyLoadTrigger trigger;
  final Duration? delay;
  final int priority;

  const LazyRegistration({
    required this.id,
    required this.name,
    required this.initializer,
    this.trigger = LazyLoadTrigger.onIdle,
    this.delay,
    this.priority = 0,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// LAZY INITIALIZER EXCEPTION
// ═══════════════════════════════════════════════════════════════════════════════

/// Exception thrown by [LazyInitializer] when operations fail.
class LazyInitializerException implements Exception {
  final String message;

  LazyInitializerException(this.message);

  @override
  String toString() => 'LazyInitializerException: $message';
}

// ═══════════════════════════════════════════════════════════════════════════════
// LAZY BUILDER WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// A widget that builds its child only when a lazy service is ready.
///
/// Shows a [placeholder] while the service is initializing, then builds
/// the child with the initialized value.
class LazyBuilder<T> extends StatefulWidget {
  /// The ID of the registered service to wait for.
  final String serviceId;

  /// Builder called with the initialized service value.
  final Widget Function(BuildContext, T) builder;

  /// Widget shown while the service is initializing.
  final Widget placeholder;

  /// Error widget shown if initialization fails.
  final Widget? errorWidget;

  /// Whether to trigger initialization if the service is not yet initialized.
  final bool autoInitialize;

  const LazyBuilder({
    required this.serviceId,
    required this.builder,
    this.placeholder = const SizedBox.shrink(),
    this.errorWidget,
    this.autoInitialize = true,
  });

  @override
  State<LazyBuilder<T>> createState() => _LazyBuilderState<T>();
}

class _LazyBuilderState<T> extends State<LazyBuilder<T>> {
  T? _value;
  Object? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadService();
  }

  Future<void> _loadService() async {
    try {
      if (widget.autoInitialize) {
        final value = await LazyInitializer.initializeNow<T>(widget.serviceId);
        if (mounted) {
          setState(() {
            _value = value;
            _isLoading = false;
          });
        }
      } else {
        final value = await LazyInitializer.waitFor<T>(widget.serviceId);
        if (mounted) {
          setState(() {
            _value = value;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return widget.placeholder;
    if (_error != null) return widget.errorWidget ?? widget.placeholder;
    return widget.builder(context, _value as T);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LAZY INITIALIZER OBSERVER
// ═══════════════════════════════════════════════════════════════════════════════

/// Observes lazy initialization progress and reports it.
///
/// Use this to show a loading indicator during background initialization.
class LazyInitializerObserver extends ChangeNotifier {
  static final LazyInitializerObserver _instance =
      LazyInitializerObserver._internal();

  factory LazyInitializerObserver() => _instance;

  LazyInitializerObserver._internal();

  int _totalServices = 0;
  int _initializedServices = 0;
  bool _isComplete = false;

  /// Total number of services to initialize.
  int get totalServices => _totalServices;

  /// Number of services that have been initialized.
  int get initializedServices => _initializedServices;

  /// Progress as a value between 0.0 and 1.0.
  double get progress =>
      _totalServices > 0 ? _initializedServices / _totalServices : 0.0;

  /// Whether all services have been initialized.
  bool get isComplete => _isComplete;

  /// Whether initialization is in progress.
  bool get isInProgress =>
      _initializedServices > 0 && _initializedServices < _totalServices;

  void updateProgress(int initialized, int total) {
    _initializedServices = initialized;
    _totalServices = total;
    _isComplete = initialized >= total;
    notifyListeners();
  }

  void reset() {
    _totalServices = 0;
    _initializedServices = 0;
    _isComplete = false;
    notifyListeners();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BATCH INITIALIZATION HELPER
// ═══════════════════════════════════════════════════════════════════════════════

/// Utility for batch-initializing services with progress tracking.
class BatchInitializer {
  final List<String> _serviceIds;
  final void Function(int completed, int total)? onProgress;
  final void Function(String serviceId, Object error)? onError;

  BatchInitializer({
    required List<String> serviceIds,
    this.onProgress,
    this.onError,
  }) : _serviceIds = serviceIds;

  /// Initialize all services in the batch.
  Future<void> run() async {
    final total = _serviceIds.length;
    var completed = 0;

    for (final id in _serviceIds) {
      try {
        await LazyInitializer.initializeNow(id);
        completed++;
        onProgress?.call(completed, total);
      } catch (e) {
        onError?.call(id, e);
      }
    }
  }

  /// Initialize all services in parallel.
  Future<void> runParallel({int concurrency = 3}) async {
    final total = _serviceIds.length;
    final pool = _Semaphore(concurrency);
    var completed = 0;

    await Future.wait(
      _serviceIds.map((id) async {
        await pool.acquire();
        try {
          await LazyInitializer.initializeNow(id);
          completed++;
          onProgress?.call(completed, total);
        } catch (e) {
          onError?.call(id, e);
        } finally {
          pool.release();
        }
      }),
    );
  }
}

// ── Simple Semaphore Implementation ─────────────────────────────────

class _Semaphore {
  final int maxPermits;
  int _currentPermits;
  final Queue<Completer<void>> _waiters = Queue();

  _Semaphore(this.maxPermits) : _currentPermits = maxPermits;

  Future<void> acquire() async {
    if (_currentPermits > 0) {
      _currentPermits--;
      return;
    }

    final completer = Completer<void>();
    _waiters.add(completer);
    await completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      final waiter = _waiters.removeFirst();
      waiter.complete();
    } else {
      _currentPermits++;
    }
  }
}
