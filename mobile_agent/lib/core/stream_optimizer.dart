// lib/core/stream_optimizer.dart
// Stream Optimization Utilities for Mobile Agent
//
// Provides stream transformation extensions and optimized controllers
// for reducing memory allocations and unnecessary rebuilds:
//
// - Throttle: emit first event, suppress rest for duration
// - Debounce: wait for pause, emit last event
// - Deduplicate: skip consecutive equal events
// - Buffer: batch events for efficient processing
// - Sample: emit latest at regular intervals
// - RateLimit: max N events per duration
//
// Also includes OptimizedStreamController with last-value tracking
// and memory-conscious cleanup.

import 'dart:async';

import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// StreamOptimizerX — Stream Extensions
// ---------------------------------------------------------------------------

/// Extension methods for optimizing Stream processing.
///
/// These transformations reduce memory pressure and unnecessary widget
/// rebuilds by filtering, batching, and deduplicating stream events.
///
/// ```dart
/// myStream
///   .throttle(const Duration(milliseconds: 100))
///   .deduplicate()
///   .listen((event) => handle(event));
/// ```
extension StreamOptimizerX<T> on Stream<T> {
  // -- Throttling --

  /// Throttle: emit the first event, then suppress subsequent events
  /// for [duration].
  ///
  /// Useful for scroll events, resize notifications, or any high-frequency
  /// stream where only the leading edge matters.
  ///
  /// ```dart
  /// scrollStream.throttle(const Duration(milliseconds: 100))
  ///   .listen((offset) => updateUI(offset));
  /// ```
  Stream<T> throttle(Duration duration) {
    Timer? timer;
    bool hasPending = false;
    T? pendingEvent;

    return transform(StreamTransformer<T, T>.fromHandlers(
      handleData: (event, sink) {
        if (timer?.isActive ?? false) {
          // Suppress: track the latest pending event for trailing emit.
          pendingEvent = event;
          hasPending = true;
          return;
        }
        // Emit immediately.
        sink.add(event);
        timer = Timer(duration, () {
          timer = null;
          // Emit trailing event if one was suppressed.
          if (hasPending && pendingEvent != null) {
            sink.add(pendingEvent as T);
            hasPending = false;
            pendingEvent = null;
          }
        });
      },
      handleDone: (sink) {
        timer?.cancel();
        sink.close();
      },
    ));
  }

  /// Throttle leading only: emit first, suppress all until duration expires.
  ///
  /// Unlike [throttle], this does NOT emit a trailing event.
  Stream<T> throttleLeading(Duration duration) {
    Timer? timer;

    return transform(StreamTransformer<T, T>.fromHandlers(
      handleData: (event, sink) {
        if (timer?.isActive ?? false) return;
        sink.add(event);
        timer = Timer(duration, () => timer = null);
      },
      handleDone: (sink) {
        timer?.cancel();
        sink.close();
      },
    ));
  }

  // -- Debouncing --

  /// Debounce: wait for [duration] of silence, then emit the last event.
  ///
  /// Useful for search input, form validation, or any scenario where
  /// you want to react only after the user pauses.
  ///
  /// ```dart
  /// searchInputStream.debounce(const Duration(milliseconds: 300))
  ///   .listen((query) => performSearch(query));
  /// ```
  Stream<T> debounce(Duration duration) {
    Timer? timer;

    return transform(StreamTransformer<T, T>.fromHandlers(
      handleData: (event, sink) {
        timer?.cancel();
        timer = Timer(duration, () => sink.add(event));
      },
      handleDone: (sink) {
        timer?.cancel();
        sink.close();
      },
    ));
  }

  /// Debounce with an optional leading emit.
  ///
  /// If [leading] is true, the first event in a burst is emitted
  /// immediately, then debouncing applies to subsequent events.
  Stream<T> debounceWithLeading(Duration duration, {bool leading = false}) {
    Timer? timer;
    bool hasEmittedLeading = false;

    return transform(StreamTransformer<T, T>.fromHandlers(
      handleData: (event, sink) {
        final isFirst = !(timer?.isActive ?? false);
        timer?.cancel();

        if (leading && isFirst && !hasEmittedLeading) {
          sink.add(event);
          hasEmittedLeading = true;
        }

        timer = Timer(duration, () {
          hasEmittedLeading = false;
          if (!leading) {
            sink.add(event);
          }
        });
      },
      handleDone: (sink) {
        timer?.cancel();
        sink.close();
      },
    ));
  }

  // -- Deduplication --

  /// Deduplicate: ignore consecutive equal events.
  ///
  /// Uses [==] for equality comparison. Only emits when the event
  /// differs from the previous one.
  ///
  /// ```dart
  /// statusStream.deduplicate().listen((status) => updateStatus(status));
  /// ```
  Stream<T> deduplicate() {
    T? lastEvent;
    bool hasLast = false;

    return transform(StreamTransformer<T, T>.fromHandlers(
      handleData: (event, sink) {
        if (!hasLast || event != lastEvent) {
          lastEvent = event;
          hasLast = true;
          sink.add(event);
        }
      },
    ));
  }

  /// Deduplicate with a custom equality function.
  ///
  /// Useful when events need field-level comparison rather than full [==].
  Stream<T> deduplicateBy<R>(R Function(T event) keySelector) {
    R? lastKey;
    bool hasLast = false;

    return transform(StreamTransformer<T, T>.fromHandlers(
      handleData: (event, sink) {
        final key = keySelector(event);
        if (!hasLast || key != lastKey) {
          lastKey = key;
          hasLast = true;
          sink.add(event);
        }
      },
    ));
  }

  // -- Buffering --

  /// Buffer: collect events into batches, emitting every [duration]
  /// or when [maxSize] is reached.
  ///
  /// Useful for batch-processing high-frequency events efficiently.
  ///
  /// ```dart
  /// clickStream.buffer(const Duration(milliseconds: 100), maxSize: 50)
  ///   .listen((batch) => processBatch(batch));
  /// ```
  Stream<List<T>> buffer(Duration duration, {int maxSize = 100}) {
    final buffer = <T>[];
    Timer? timer;
    bool isDone = false;

    void flush(StreamSink<List<T>> sink) {
      if (buffer.isNotEmpty) {
        sink.add(List<T>.unmodifiable(buffer));
        buffer.clear();
      }
    }

    return transform(StreamTransformer<T, List<T>>.fromHandlers(
      handleData: (event, sink) {
        buffer.add(event);

        if (buffer.length >= maxSize) {
          timer?.cancel();
          flush(sink);
          return;
        }

        timer ??= Timer.periodic(duration, (_) {
          flush(sink);
        });
      },
      handleDone: (sink) {
        timer?.cancel();
        flush(sink);
        sink.close();
      },
    ));
  }

  // -- Sampling --

  /// Sample: emit the latest event at regular [interval].
  ///
  /// If no new event arrived since the last sample, nothing is emitted.
  ///
  /// ```dart
  /// mousePositionStream.sample(const Duration(milliseconds: 50))
  ///   .listen((pos) => updateCursor(pos));
  /// ```
  Stream<T> sample(Duration interval) {
    T? latest;
    bool hasValue = false;
    Timer? timer;

    return transform(StreamTransformer<T, T>.fromHandlers(
      handleData: (event, sink) {
        latest = event;
        hasValue = true;

        timer ??= Timer.periodic(interval, (_) {
          if (hasValue && latest != null) {
            sink.add(latest as T);
            hasValue = false;
          }
        });
      },
      handleDone: (sink) {
        timer?.cancel();
        if (hasValue && latest != null) {
          sink.add(latest as T);
        }
        sink.close();
      },
    ));
  }

  // -- Rate Limiting --

  /// Rate limit: emit at most [maxCount] events per [duration].
  ///
  /// Excess events are silently dropped.
  ///
  /// ```dart
  /// apiCallStream.rateLimit(5, const Duration(seconds: 1))
  ///   .listen((req) => sendRequest(req));
  /// ```
  Stream<T> rateLimit(int maxCount, Duration duration) {
    final timestamps = <DateTime>[];

    return transform(StreamTransformer<T, T>.fromHandlers(
      handleData: (event, sink) {
        final now = DateTime.now();

        // Remove timestamps outside the window.
        timestamps.removeWhere((t) => now.difference(t) > duration);

        if (timestamps.length < maxCount) {
          timestamps.add(now);
          sink.add(event);
        }
      },
    ));
  }

  // -- Memory-Conscious Operations --

  /// Map with memory-conscious batching for large streams.
  ///
  /// Processes events in microtask batches to avoid blocking the UI thread.
  Stream<R> mapAsync<R>(Future<R> Function(T event) mapper,
      {int concurrency = 1}) {
    final controller = StreamController<R>();
    final queue = <T>[];
    int active = 0;
    bool isClosed = false;

    void processNext() {
      if (isClosed || active >= concurrency || queue.isEmpty) return;

      final event = queue.removeAt(0);
      active++;

      mapper(event).then((result) {
        active--;
        if (!controller.isClosed) {
          controller.add(result);
        }
        processNext();
      }).catchError((Object e, StackTrace st) {
        active--;
        if (!controller.isClosed) {
          controller.addError(e, st);
        }
        processNext();
      });
    }

    listen(
      (event) {
        queue.add(event);
        processNext();
      },
      onError: (Object e, StackTrace st) => controller.addError(e, st),
      onDone: () {
        isClosed = true;
        // Close controller when all pending operations complete.
        Timer.periodic(const Duration(milliseconds: 10), (timer) {
          if (active == 0 && queue.isEmpty) {
            timer.cancel();
            controller.close();
          }
        });
      },
      cancelOnError: false,
    );

    return controller.stream;
  }

  /// Filter and map in a single pass to avoid intermediate allocations.
  Stream<R> filterMap<R>(R? Function(T event) transform) {
    return transform(StreamTransformer<T, R>.fromHandlers(
      handleData: (event, sink) {
        final result = transform(event);
        if (result != null) {
          sink.add(result);
        }
      },
    ));
  }

  /// Skip null events (for streams with nullable types).
  Stream<T> skipNull() {
    return where((event) => event != null).cast<T>();
  }
}

// ---------------------------------------------------------------------------
// OptimizedStreamController — Memory-Conscious Broadcast Controller
// ---------------------------------------------------------------------------

/// An optimized broadcast stream controller with last-value tracking,
/// deduplication, and automatic cleanup.
///
/// Unlike a plain [StreamController], this tracks the last emitted value
/// and provides methods for conditional emission (deduplication).
///
/// ```dart
/// final controller = OptimizedStreamController<int>();
///
/// controller.stream.deduplicate().listen(print);
///
/// controller.add(1);        // emitted
/// controller.add(1);        // deduplicated (skipped)
/// controller.addIfChanged(1); // skipped (same as last)
/// controller.addIfChanged(2); // emitted
///
/// print(controller.lastValue); // 2
///
/// controller.dispose(); // clean shutdown
/// ```
class OptimizedStreamController<T> {
  final StreamController<T> _controller;
  T? _lastValue;
  bool _isClosed = false;

  /// Whether to automatically deduplicate consecutive events.
  final bool autoDeduplicate;

  /// Optional debug name for logging.
  final String? debugName;

  /// Create an optimized broadcast stream controller.
  ///
  /// [autoDeduplicate] skips consecutive equal events automatically.
  /// [debugName] is used in debug logging.
  OptimizedStreamController({
    this.autoDeduplicate = false,
    this.debugName,
  }) : _controller = StreamController<T>.broadcast();

  /// The output stream.
  Stream<T> get stream => _controller.stream;

  /// Whether the controller has any active listeners.
  bool get hasListeners => _controller.hasListener;

  /// Number of active listeners.
  int get listenerCount => _controller.hasListener ? 1 : 0;

  /// The last value that was added, or null if none.
  T? get lastValue => _lastValue;

  /// Whether this controller has been closed.
  bool get isClosed => _isClosed;

  /// Whether any value has been emitted.
  bool get hasValue => _lastValue != null;

  /// Add a value to the stream.
  ///
  /// If [autoDeduplicate] is true and the value equals the last value,
  /// it is silently skipped.
  void add(T value) {
    if (_isClosed) {
      if (kDebugMode && debugName != null) {
        debugPrint('[OptimizedStreamController:$debugName] Ignored add to closed controller');
      }
      return;
    }

    if (autoDeduplicate && value == _lastValue) {
      return;
    }

    _lastValue = value;
    _controller.add(value);
  }

  /// Add a value only if it differs from the last emitted value.
  ///
  /// This is an explicit deduplication check, independent of
  /// [autoDeduplicate].
  void addIfChanged(T value) {
    if (_isClosed) return;
    if (value == _lastValue) return;

    _lastValue = value;
    _controller.add(value);
  }

  /// Add an error to the stream.
  void addError(Object error, [StackTrace? stackTrace]) {
    if (_isClosed) return;
    _controller.addError(error, stackTrace);
  }

  /// Get a stream of distinct values (no consecutive duplicates).
  Stream<T> get distinctStream => stream.deduplicate();

  /// Close the controller and release resources.
  ///
  /// Idempotent — safe to call multiple times.
  void dispose() {
    if (_isClosed) return;
    _isClosed = true;
    _lastValue = null;
    _controller.close();
  }

  /// Close the controller (alias for [dispose]).
  void close() => dispose();
}

// ---------------------------------------------------------------------------
// OptimizedValueNotifier — Lightweight Reactive Value
// ---------------------------------------------------------------------------

/// A lightweight value notifier that deduplicates updates and tracks
/// version for optimistic concurrency.
///
/// More memory-efficient than [ValueNotifier] for high-frequency updates
/// because it skips notifications when the value hasn't changed.
///
/// ```dart
/// final counter = OptimizedValueNotifier<int>(0);
/// counter.addListener(() => print(counter.value));
/// counter.value = 1; // notifies
/// counter.value = 1; // deduplicated, no notification
/// ```
class OptimizedValueNotifier<T> extends ChangeNotifier {
  T _value;
  int _version = 0;

  OptimizedValueNotifier(this._value);

  /// Current value.
  T get value => _value;

  /// Monotonically increasing version counter.
  int get version => _version;

  /// Number of times the value has changed.
  int get changeCount => _version;

  /// Set the value, notifying listeners only if it changed.
  set value(T newValue) {
    if (_value == newValue) return;
    _value = newValue;
    _version++;
    notifyListeners();
  }

  /// Force a notification even if the value hasn't changed.
  void forceNotify() {
    _version++;
    notifyListeners();
  }

  /// Update the value using a transform function.
  void update(T Function(T current) updater) {
    value = updater(_value);
  }
}

// ---------------------------------------------------------------------------
// Stream DisposalTracker — Automatic Cleanup
// ---------------------------------------------------------------------------

/// Tracks active stream subscriptions and provides bulk cancellation.
///
/// Use this in notifiers or controllers that manage multiple subscriptions
/// to ensure all are properly cancelled on dispose.
///
/// ```dart
/// class MyController {
///   final _tracker = StreamDisposalTracker();
///
///   void init() {
///     _tracker.track(stream1.listen((e) => handle1(e)));
///     _tracker.track(stream2.listen((e) => handle2(e)));
///   }
///
///   void dispose() {
///     _tracker.disposeAll();
///   }
/// }
/// ```
class StreamDisposalTracker {
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  /// Number of active subscriptions.
  int get count => _subscriptions.length;

  /// Track a subscription for automatic cleanup.
  void track(StreamSubscription<dynamic> subscription) {
    _subscriptions.add(subscription);
  }

  /// Cancel all tracked subscriptions.
  Future<void> disposeAll() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
  }

  /// Cancel and remove a specific subscription.
  Future<void> cancel(StreamSubscription<dynamic> subscription) async {
    await subscription.cancel();
    _subscriptions.remove(subscription);
  }
}

// ---------------------------------------------------------------------------
// Memory-Effactory Stream Factories
// ---------------------------------------------------------------------------

/// Creates a memory-efficient periodic stream with automatic cleanup.
///
/// The stream emits [initialValue] and then [value] every [period].
/// Automatically cancels the underlying timer when the stream has
/// no listeners.
Stream<T> createPeriodicStream<T>({
  required Duration period,
  required T initialValue,
  required T value,
}) {
  late final StreamController<T> controller;
  Timer? timer;

  controller = StreamController<T>.broadcast(
    onListen: () {
      controller.add(initialValue);
      timer = Timer.periodic(period, (_) {
        if (!controller.isClosed) {
          controller.add(value);
        }
      });
    },
    onCancel: () {
      timer?.cancel();
    },
  );

  return controller.stream;
}

/// Creates a one-shot stream from a future, with early-listener buffering.
///
/// Listeners that attach before the future completes will receive
/// the value once it's available.
Stream<T> createSingleStream<T>(Future<T> future) {
  final controller = StreamController<T>.broadcast();

  future.then((value) {
    if (!controller.isClosed) {
      controller.add(value);
      controller.close();
    }
  }).catchError((Object e, StackTrace st) {
    if (!controller.isClosed) {
      controller.addError(e, st);
      controller.close();
    }
  });

  return controller.stream;
}

/// Merges multiple streams and deduplicates the combined output.
///
/// Useful when multiple sources may produce the same event type
/// and you want to avoid duplicate processing.
Stream<T> mergeAndDeduplicate<T>(List<Stream<T>> streams) {
  if (streams.isEmpty) return const Stream.empty();
  if (streams.length == 1) return streams.first.deduplicate();

  final controller = StreamController<T>.broadcast();
  T? lastValue;

  for (final stream in streams) {
    stream.listen(
      (event) {
        if (event != lastValue) {
          lastValue = event;
          controller.add(event);
        }
      },
      onError: controller.addError,
      onDone: () {
        // Only close when all streams are done.
      },
    );
  }

  return controller.stream;
}
