// lib/core/error_handler.dart
// Production Error Handling System for Mobile Agent

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/logger_service.dart';

// ---------------------------------------------------------------------------
// Log Level Enumeration
// ---------------------------------------------------------------------------

/// Severity levels for application logging.
///
/// Ordered from most verbose to most critical:
/// - [verbose]: Extremely detailed internal state (debug builds only)
/// - [debug]: Development diagnostics, variable dumps
/// - [info]: Normal operational events (default for production)
/// - [warning]: Recoverable issues, degraded functionality
/// - [error]: Operation failures requiring attention
/// - [fatal]: Unrecoverable crash-level errors
enum LogLevel {
  verbose,
  debug,
  info,
  warning,
  error,
  fatal,
}

// ---------------------------------------------------------------------------
// AppException - Structured Application Error
// ---------------------------------------------------------------------------

/// A structured, production-grade exception type used throughout the app.
///
/// Every error in the app is wrapped in [AppException] to provide:
/// - A machine-readable [code] for programmatic handling
/// - A user-friendly [message] for display in the UI
/// - Optional [technicalDetails] for debugging and crash reports
/// - A [isRetryable] flag to drive retry logic
/// - A [timestamp] for chronological analysis
///
/// ```dart
/// throw AppException.networkTimeout(
///   message: 'Connection timed out. Please check your network.',
/// );
/// ```
class AppException implements Exception {
  /// Machine-readable error code, e.g. `"NETWORK_TIMEOUT"`, `"API_RATE_LIMIT"`.
  final String code;

  /// Human-readable message suitable for display in the UI.
  final String message;

  /// Technical details for debugging (stack traces, raw responses, etc.).
  /// Should NOT be shown to end users.
  final String? technicalDetails;

  /// Whether this error can be resolved by retrying the same operation.
  final bool isRetryable;

  /// When the error occurred.
  final DateTime timestamp;

  /// The original underlying error, if any.
  final dynamic originalError;

  /// Optional HTTP status code if this came from an API call.
  final int? statusCode;

  const AppException({
    required this.code,
    required this.message,
    this.technicalDetails,
    this.isRetryable = false,
    this.originalError,
    this.statusCode,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? null;

  /// Create with automatic timestamp.
  factory AppException.now({
    required String code,
    required String message,
    String? technicalDetails,
    bool isRetryable = false,
    dynamic originalError,
    int? statusCode,
  }) {
    return AppException(
      code: code,
      message: message,
      technicalDetails: technicalDetails,
      isRetryable: isRetryable,
      originalError: originalError,
      statusCode: statusCode,
      timestamp: DateTime.now(),
    );
  }

  // -- Convenience factories for common error types --

  factory AppException.networkTimeout({String? message, dynamic originalError}) {
    return AppException.now(
      code: 'NETWORK_TIMEOUT',
      message: message ?? 'Connection timed out. Please check your network.',
      isRetryable: true,
      originalError: originalError,
    );
  }

  factory AppException.noInternet({String? message, dynamic originalError}) {
    return AppException.now(
      code: 'NO_INTERNET',
      message: message ?? 'No internet connection. Please check your network and try again.',
      isRetryable: true,
      originalError: originalError,
    );
  }

  factory AppException.apiError({required String message, int? statusCode, String? technicalDetails, dynamic originalError}) {
    return AppException.now(
      code: 'API_ERROR',
      message: message,
      statusCode: statusCode,
      technicalDetails: technicalDetails,
      isRetryable: statusCode != null && (statusCode >= 500 || statusCode == 429),
      originalError: originalError,
    );
  }

  factory AppException.rateLimited({String? message, dynamic originalError}) {
    return AppException.now(
      code: 'API_RATE_LIMIT',
      message: message ?? 'Too many requests. Please wait a moment and try again.',
      isRetryable: true,
      originalError: originalError,
    );
  }

  factory AppException.llmError({required String message, String? provider, dynamic originalError}) {
    return AppException.now(
      code: 'LLM_ERROR',
      message: message,
      technicalDetails: provider,
      isRetryable: true,
      originalError: originalError,
    );
  }

  factory AppException.validationError({required String message, String? field}) {
    return AppException.now(
      code: 'VALIDATION_ERROR',
      message: message,
      technicalDetails: field,
      isRetryable: false,
    );
  }

  factory AppException.unexpected({required String message, dynamic originalError, StackTrace? stackTrace}) {
    return AppException.now(
      code: 'UNEXPECTED_ERROR',
      message: message,
      technicalDetails: stackTrace?.toString(),
      isRetryable: false,
      originalError: originalError,
    );
  }

  factory AppException.fileSystem({required String message, String? path, dynamic originalError}) {
    return AppException.now(
      code: 'FILESYSTEM_ERROR',
      message: message,
      technicalDetails: path,
      isRetryable: false,
      originalError: originalError,
    );
  }

  @override
  String toString() => 'AppException [$code${statusCode != null ? ' $statusCode' : ''}]: $message';
}

// ---------------------------------------------------------------------------
// RetryPolicy - Configurable Retry Behavior
// ---------------------------------------------------------------------------

/// Defines retry behavior for transient failures.
///
/// Use [RetryPolicy.defaultPolicy] for standard exponential backoff,
/// or create custom policies for specific operations.
class RetryPolicy {
  /// Maximum number of retry attempts.
  final int maxRetries;

  /// Base delay between retries (multiplied exponentially).
  final Duration baseDelay;

  /// Maximum delay cap to prevent excessive waits.
  final Duration maxDelay;

  /// Multiplier for exponential backoff.
  final double backoffMultiplier;

  /// Additional random jitter to prevent thundering herd.
  final double jitterFactor;

  const RetryPolicy({
    this.maxRetries = 3,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.backoffMultiplier = 2.0,
    this.jitterFactor = 0.25,
  });

  /// Sensible defaults for network operations.
  static const RetryPolicy defaultPolicy = RetryPolicy();

  /// Aggressive retry for critical save operations.
  static const RetryPolicy aggressivePolicy = RetryPolicy(
    maxRetries: 5,
    baseDelay: Duration(milliseconds: 500),
    maxDelay: const Duration(seconds: 10),
    backoffMultiplier: 1.5,
  );

  /// Minimal retry for non-essential operations.
  static const RetryPolicy minimalPolicy = RetryPolicy(
    maxRetries: 1,
    baseDelay: Duration(seconds: 2),
  );

  /// Calculate the delay before the [attempt]th retry (1-indexed).
  Duration delayForAttempt(int attempt) {
    final exponential = baseDelay.inMilliseconds * pow(backoffMultiplier, attempt - 1).toInt();
    final jitter = (exponential * jitterFactor * _random.nextDouble()).toInt();
    final delayMs = (exponential + jitter).clamp(0, maxDelay.inMilliseconds);
    return Duration(milliseconds: delayMs);
  }
}

final _random = Random();

// ---------------------------------------------------------------------------
// AppErrorHandler - Global Error Handling
// ---------------------------------------------------------------------------

/// Production-grade global error handling system for the Mobile Agent app.
///
/// [AppErrorHandler] is a singleton that intercepts ALL errors in the app:
/// - Flutter framework errors (widget build failures, layout errors)
/// - Dart Zone errors (uncaught async exceptions)
/// - Platform channel errors
/// - Network errors with configurable retry
/// - LLM API errors with fallback strategies
///
/// ## Usage
///
/// Call [initialize] once in `main()` before `runApp()`:
///
/// ```dart
/// void main() {
///   WidgetsFlutterBinding.ensureInitialized();
///   AppErrorHandler.initialize();
///   runApp(const ProviderScope(child: MobileAgentApp()));
/// }
/// ```
class AppErrorHandler {
  AppErrorHandler._internal();

  static final AppErrorHandler _instance = AppErrorHandler._internal();

  /// The singleton instance.
  static AppErrorHandler get instance => _instance;

  static bool _initialized = false;

  /// Whether the error handler has been initialized.
  static bool get isInitialized => _initialized;

  /// Logger service instance for structured logging.
  static LoggerService? _logger;

  /// Fatal error callbacks registered by other services.
  static final List<void Function(dynamic, StackTrace)> _fatalErrorCallbacks = [];

  /// Tracks whether the app is currently handling a fatal error
  /// to prevent cascading error reports.
  static bool _isHandlingFatal = false;

  // -- Initialization --

  /// Initialize the global error handling system.
  ///
  /// Must be called once before `runApp()`. This sets up:
  /// 1. Flutter framework error handler
  /// 2. Platform dispatcher error handler
  /// 3. Returns a zone-guarded runner for async error catching
  ///
  /// The returned function should wrap your `runApp()` call:
  ///
  /// ```dart
  /// void main() {
  ///   WidgetsFlutterBinding.ensureInitialized();
  ///   final runGuarded = AppErrorHandler.initialize();
  ///   runGuarded(() => runApp(const MyApp()));
  /// }
  /// ```
  static void Function(void Function()) initialize({LoggerService? logger}) {
    if (_initialized) {
      _logInternal('AppErrorHandler already initialized, skipping.');
      return (fn) => fn();
    }

    _logger = logger;
    _initialized = true;

    // 1. Flutter framework error handler — catches widget build errors,
    //    layout errors, painting errors, and assertion failures.
    FlutterError.onError = (FlutterErrorDetails details) {
      _logFlutterError(details);
      // In debug mode, still dump to console for developer visibility.
      if (kDebugMode) {
        FlutterError.dumpErrorToConsole(details);
      }
    };

    // 2. Platform dispatcher error handler — catches low-level platform
    //    errors that bypass the Flutter framework.
    PlatformDispatcher.instance.onError = (error, stack) {
      _logPlatformError(error, stack);
      return true; // Prevent default handling (which would crash the app).
    };

    // 3. Set up async error handling via zone guarding.
    // The caller wraps runApp with this.
    void runGuarded(void Function() body) {
      runZonedGuarded(
        body,
        (error, stack) {
          _logZoneError(error, stack);
          _handleFatalError(error, stack);
        },
        zoneSpecification: ZoneSpecification(
          handleUncaughtError: (self, parent, zone, error, stackTrace) {
            parent.handleUncaughtError(error, stackTrace);
          },
        ),
      );
    }

    _logInternal('AppErrorHandler initialized');
    return runGuarded;
  }

  // -- Public Logging API --

  /// Log a structured message at the specified level.
  ///
  /// [message] is the human-readable log message.
  /// [level] is the severity (defaults to [LogLevel.info]).
  /// [tag] categorizes the log (e.g., `"API"`, `"LLM"`, `"EDITOR"`).
  /// [error] is the optional raw error object.
  /// [stackTrace] is the optional stack trace.
  ///
  /// ```dart
  /// AppErrorHandler.log('API request completed', tag: 'API', level: LogLevel.info);
  /// ```
  static void log(
    String message, {
    LogLevel level = LogLevel.info,
    String? tag,
    dynamic error,
    StackTrace? stackTrace,
  }) {
    final logger = _logger;
    if (logger != null) {
      _dispatchToLogger(logger, level, tag ?? 'App', message, error, stackTrace);
    } else {
      _logInternal('[$level] ${tag != null ? '[$tag] ' : ''}$message${error != null ? ' | Error: $error' : ''}');
    }
  }

  /// Execute an async operation with automatic retry using exponential backoff.
  ///
  /// [operation] is the async function to execute.
  /// [policy] controls retry behavior (defaults to [RetryPolicy.defaultPolicy]).
  /// [onRetry] is called before each retry attempt with the error and attempt number.
  /// [shouldRetry] allows custom logic to decide if an error is retryable.
  ///
  /// Returns the result of [operation] or throws the final [AppException].
  ///
  /// ```dart
  /// final result = await AppErrorHandler.withRetry(
  ///   () => api.fetchData(),
  ///   policy: RetryPolicy.aggressivePolicy,
  /// );
  /// ```
  static Future<T> withRetry<T>(
    Future<T> Function() operation, {
    RetryPolicy policy = RetryPolicy.defaultPolicy,
    void Function(AppException error, int attempt)? onRetry,
    bool Function(dynamic error)? shouldRetry,
  }) async {
    var lastError = AppException.unexpected(message: 'Retry loop did not execute');

    for (var attempt = 0; attempt <= policy.maxRetries; attempt++) {
      try {
        return await operation();
      } catch (e) {
        final isRetryable = shouldRetry?.call(e) ?? _defaultShouldRetry(e);
        final appEx = e is AppException
            ? e
            : AppException.unexpected(
                message: 'Operation failed: $e',
                originalError: e,
              );

        if (!isRetryable || attempt >= policy.maxRetries) {
          lastError = appEx;
          break;
        }

        final delay = policy.delayForAttempt(attempt + 1);
        log(
          'Retry attempt ${attempt + 1}/${policy.maxRetries} after ${delay.inMilliseconds}ms',
          level: LogLevel.warning,
          tag: 'Retry',
          error: e,
        );

        onRetry?.call(appEx, attempt + 1);
        await Future.delayed(delay);
      }
    }

    throw lastError;
  }

  /// Show a user-friendly error in the UI.
  ///
  /// Displays a [SnackBar] with the error message. If [technicalDetails]
  /// is provided and the app is in debug mode, an expandable section
  /// shows technical information.
  ///
  /// ```dart
  /// AppErrorHandler.showError(context, 'Failed to save file', technicalDetails: stackTrace);
  /// ```
  static void showError(
    BuildContext context,
    String userMessage, {
    String? technicalDetails,
    VoidCallback? onRetry,
    Duration duration = const Duration(seconds: 6),
  }) {
    final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
    if (scaffoldMessenger == null) {
      log('Cannot show error: no ScaffoldMessenger in context', level: LogLevel.warning);
      return;
    }

    scaffoldMessenger.showSnackBar(
      SnackBar(
        duration: duration,
        backgroundColor: Colors.red.shade900,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    userMessage,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            if (kDebugMode && technicalDetails != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  technicalDetails,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        action: onRetry != null
            ? SnackBarAction(
                label: 'RETRY',
                textColor: Colors.amber,
                onPressed: onRetry,
              )
            : null,
      ),
    );
  }

  /// Show a non-error informational message to the user.
  static void showInfo(BuildContext context, String message, {Duration duration = const Duration(seconds: 3)}) {
    final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
    if (scaffoldMessenger == null) return;

    scaffoldMessenger.showSnackBar(
      SnackBar(
        duration: duration,
        backgroundColor: Colors.blue.shade800,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Show a success message to the user.
  static void showSuccess(BuildContext context, String message, {Duration duration = const Duration(seconds: 2)}) {
    final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
    if (scaffoldMessenger == null) return;

    scaffoldMessenger.showSnackBar(
      SnackBar(
        duration: duration,
        backgroundColor: Colors.green.shade800,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Register a callback to be invoked when a fatal error occurs.
  ///
  /// Use this to integrate with crash reporting services (Firebase Crashlytics,
  /// Sentry, etc.) or to perform cleanup before the app terminates.
  static void registerFatalErrorCallback(void Function(dynamic, StackTrace) callback) {
    _fatalErrorCallbacks.add(callback);
  }

  /// Unregister a previously registered fatal error callback.
  static void unregisterFatalErrorCallback(void Function(dynamic, StackTrace) callback) {
    _fatalErrorCallbacks.remove(callback);
  }

  // -- Private Error Handlers --

  /// Log a Flutter framework error (widget build, layout, painting, etc.).
  static void _logFlutterError(FlutterErrorDetails details) {
    final exception = details.exception;
    final stack = details.stack ?? StackTrace.current;

    final context = details.context?.toString();
    final library = details.library;

    final technical = StringBuffer();
    technical.writeln('Context: $context');
    technical.writeln('Library: $library');
    if (details.informationCollector != null) {
      final info = details.informationCollector!();
      for (final entry in info) {
        technical.writeln(entry.toString());
      }
    }

    final appEx = AppException.now(
      code: 'FLUTTER_FRAMEWORK_ERROR',
      message: 'UI rendering error: $exception',
      technicalDetails: technical.toString(),
      originalError: exception,
    );

    log(
      'Flutter framework error: $exception',
      level: LogLevel.error,
      tag: 'Flutter',
      error: exception,
      stackTrace: stack,
    );

    // In production, we don't crash — we log and degrade gracefully.
    // The ErrorBoundary widget will show a fallback UI.
  }

  /// Log an error from the Dart Zone (uncaught async exceptions).
  static void _logZoneError(dynamic error, StackTrace stack) {
    final appEx = error is AppException
        ? error
        : AppException.now(
            code: 'ZONE_ERROR',
            message: 'Uncaught async error: $error',
            technicalDetails: stack.toString(),
            originalError: error,
          );

    log(
      'Zone error: $error',
      level: LogLevel.fatal,
      tag: 'Zone',
      error: error,
      stackTrace: stack,
    );
  }

  /// Log a low-level platform error.
  static void _logPlatformError(dynamic error, StackTrace stack) {
    log(
      'Platform error: $error',
      level: LogLevel.error,
      tag: 'Platform',
      error: error,
      stackTrace: stack,
    );
  }

  /// Handle a fatal error — invokes registered callbacks and attempts
  /// graceful degradation.
  static void _handleFatalError(dynamic error, StackTrace stack) {
    if (_isHandlingFatal) {
      // Prevent cascading fatal error handling.
      return;
    }
    _isHandlingFatal = true;

    log(
      'Fatal error: $error',
      level: LogLevel.fatal,
      tag: 'Fatal',
      error: error,
      stackTrace: stack,
    );

    // Notify all registered crash reporting services.
    for (final callback in _fatalErrorCallbacks) {
      try {
        callback(error, stack);
      } catch (e) {
        _logInternal('Fatal error callback threw: $e');
      }
    }

    // In production, we try to keep the app running rather than crashing.
    // The ErrorBoundary widget catches widget-tree errors and shows fallback UI.
    _isHandlingFatal = false;
  }

  // -- Private Helpers --

  static void _dispatchToLogger(
    LoggerService logger,
    LogLevel level,
    String tag,
    String message,
    dynamic error,
    StackTrace? stackTrace,
  ) {
    switch (level) {
      case LogLevel.verbose:
        logger.v(tag, message);
      case LogLevel.debug:
        logger.d(tag, message);
      case LogLevel.info:
        logger.i(tag, message);
      case LogLevel.warning:
        logger.w(tag, message, error);
      case LogLevel.error:
        logger.e(tag, message, error, stackTrace ?? StackTrace.current);
      case LogLevel.fatal:
        logger.f(tag, message, error, stackTrace ?? StackTrace.current);
    }
  }

  static bool _defaultShouldRetry(dynamic error) {
    if (error is AppException) return error.isRetryable;
    if (error is TimeoutException) return true;
    if (error is SocketException) return true;
    if (error is FormatException) return false;
    return false;
  }

  static void _logInternal(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[AppErrorHandler] $message');
    }
  }
}

// ---------------------------------------------------------------------------
// Error Logging Mixin - Easy integration with any class
// ---------------------------------------------------------------------------

/// A mixin that provides convenient error logging methods to any class.
///
/// ```dart
/// class MyService with ErrorLogging {
///   Future<void> doSomething() async {
///     try {
///       // ... work ...
///     } catch (e, st) {
///       logError('doSomething failed', e, st);
///       rethrow;
///     }
///   }
/// }
/// ```
mixin ErrorLogging {
  /// The tag used for log messages. Defaults to the class name.
  String get logTag => runtimeType.toString();

  void logVerbose(String message) {
    AppErrorHandler.log(message, level: LogLevel.verbose, tag: logTag);
  }

  void logDebug(String message) {
    AppErrorHandler.log(message, level: LogLevel.debug, tag: logTag);
  }

  void logInfo(String message) {
    AppErrorHandler.log(message, level: LogLevel.info, tag: logTag);
  }

  void logWarning(String message, [dynamic error]) {
    AppErrorHandler.log(message, level: LogLevel.warning, tag: logTag, error: error);
  }

  void logError(String message, dynamic error, StackTrace stackTrace) {
    AppErrorHandler.log(message, level: LogLevel.error, tag: logTag, error: error, stackTrace: stackTrace);
  }

  void logFatal(String message, dynamic error, StackTrace stackTrace) {
    AppErrorHandler.log(message, level: LogLevel.fatal, tag: logTag, error: error, stackTrace: stackTrace);
  }

  /// Wrap an async operation with automatic error logging.
  Future<T> logOperation<T>(
    String operationName,
    Future<T> Function() fn, {
    bool rethrowError = true,
  }) async {
    logDebug('Starting: $operationName');
    final sw = Stopwatch()..start();
    try {
      final result = await fn();
      sw.stop();
      logDebug('Completed: $operationName in ${sw.elapsedMilliseconds}ms');
      return result;
    } catch (e, st) {
      sw.stop();
      logError('$operationName failed after ${sw.elapsedMilliseconds}ms', e, st);
      if (rethrowError) rethrow;
      throw AppException.unexpected(
        message: '$operationName failed',
        originalError: e,
        stackTrace: st,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Safe Execution Helpers
// ---------------------------------------------------------------------------

/// Execute a function safely, returning null on error.
///
/// ```dart
/// final result = await safeRun(() => riskyOperation());
/// if (result != null) { ... }
/// ```
Future<T?> safeRun<T>(
  Future<T> Function() fn, {
  void Function(dynamic error, StackTrace)? onError,
  String? operationName,
}) async {
  try {
    return await fn();
  } catch (e, st) {
    AppErrorHandler.log(
      operationName ?? 'safeRun failed',
      level: LogLevel.warning,
      tag: 'SafeRun',
      error: e,
      stackTrace: st,
    );
    onError?.call(e, st);
    return null;
  }
}

/// Execute a synchronous function safely, returning null on error.
T? safeRunSync<T>(
  T Function() fn, {
  void Function(dynamic error, StackTrace)? onError,
  String? operationName,
}) {
  try {
    return fn();
  } catch (e, st) {
    AppErrorHandler.log(
      operationName ?? 'safeRunSync failed',
      level: LogLevel.warning,
      tag: 'SafeRun',
      error: e,
      stackTrace: st,
    );
    onError?.call(e, st);
    return null;
  }
}
