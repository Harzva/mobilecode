// lib/providers/error_provider.dart
// Riverpod Error State Management for Mobile Agent

import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/error_handler.dart';

// ---------------------------------------------------------------------------
// AppError - UI-facing error representation
// ---------------------------------------------------------------------------

/// A UI-ready error object that wraps [AppException] with display metadata.
///
/// This is what the error provider exposes to widgets. It includes
/// everything needed to render an error message, offer retry,
/// and track error statistics.
@immutable
class AppError {
  /// Unique ID for this error instance.
  final String id;

  /// The underlying exception.
  final AppException exception;

  /// When this error occurred.
  final DateTime timestamp;

  /// Whether this error has been dismissed by the user.
  final bool isDismissed;

  /// Whether a retry is currently in progress.
  final bool isRetrying;

  /// Number of retry attempts made so far.
  final int retryCount;

  /// Optional callback to retry the failed operation.
  final Future<void> Function()? retryAction;

  const AppError({
    required this.id,
    required this.exception,
    required this.timestamp,
    this.isDismissed = false,
    this.isRetrying = false,
    this.retryCount = 0,
    this.retryAction,
  });

  /// User-friendly message from the exception.
  String get message => exception.message;

  /// Error code from the exception.
  String get code => exception.code;

  /// Whether this error can be retried.
  bool get isRetryable => exception.isRetryable && retryAction != null;

  /// Technical details (debug only).
  String? get technicalDetails => exception.technicalDetails;

  /// Create a copy with modified fields.
  AppError copyWith({
    bool? isDismissed,
    bool? isRetrying,
    int? retryCount,
    Future<void> Function()? retryAction,
  }) {
    return AppError(
      id: id,
      exception: exception,
      timestamp: timestamp,
      isDismissed: isDismissed ?? this.isDismissed,
      isRetrying: isRetrying ?? this.isRetrying,
      retryCount: retryCount ?? this.retryCount,
      retryAction: retryAction ?? this.retryAction,
    );
  }
}

// ---------------------------------------------------------------------------
// ErrorState - Immutable error state for the entire app
// ---------------------------------------------------------------------------

/// The complete error state of the application.
///
/// Contains:
/// - [activeErrors]: Currently visible errors (not dismissed)
/// - [errorHistory]: All recent errors including dismissed ones
/// - [isGlobalLoading]: Whether any global async operation is in progress
/// - [lastErrorTimestamp]: When the most recent error occurred
@immutable
class ErrorState {
  /// Maximum number of errors to keep in history.
  static const int maxHistorySize = 50;

  /// Currently active (non-dismissed) errors.
  final List<AppError> activeErrors;

  /// Full error history including dismissed errors.
  final List<AppError> errorHistory;

  /// Whether a global loading indicator should be shown.
  final bool isGlobalLoading;

  /// Timestamp of the most recent error.
  final DateTime? lastErrorTimestamp;

  const ErrorState({
    this.activeErrors = const [],
    this.errorHistory = const [],
    this.isGlobalLoading = false,
    this.lastErrorTimestamp,
  });

  /// Whether there are any active errors to display.
  bool get hasErrors => activeErrors.isNotEmpty;

  /// The most recent active error.
  AppError? get mostRecentError => activeErrors.isNotEmpty ? activeErrors.last : null;

  /// Number of active errors.
  int get activeErrorCount => activeErrors.length;

  /// Error count by code for statistics.
  Map<String, int> get errorCountsByCode {
    final counts = <String, int>{};
    for (final error in errorHistory) {
      counts[error.code] = (counts[error.code] ?? 0) + 1;
    }
    return counts;
  }

  /// Errors in the last hour.
  List<AppError> get recentErrors {
    final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
    return errorHistory.where((e) => e.timestamp.isAfter(oneHourAgo)).toList();
  }

  /// Create a copy with modified fields.
  ErrorState copyWith({
    List<AppError>? activeErrors,
    List<AppError>? errorHistory,
    bool? isGlobalLoading,
    DateTime? lastErrorTimestamp,
  }) {
    return ErrorState(
      activeErrors: activeErrors ?? this.activeErrors,
      errorHistory: errorHistory ?? this.errorHistory,
      isGlobalLoading: isGlobalLoading ?? this.isGlobalLoading,
      lastErrorTimestamp: lastErrorTimestamp ?? this.lastErrorTimestamp,
    );
  }
}

// ---------------------------------------------------------------------------
// ErrorNotifier - Riverpod StateNotifier for error management
// ---------------------------------------------------------------------------

/// Manages all application errors through Riverpod.
///
/// Provides a centralized way to:
/// - Report errors from anywhere in the app
/// - Display error messages to users
/// - Track retry attempts
/// - Maintain error statistics
///
/// ## Usage
///
/// ```dart
/// // In a widget:
/// final errorState = ref.watch(errorNotifierProvider);
/// if (errorState.hasErrors) { ... }
///
/// // Report an error:
/// ref.read(errorNotifierProvider.notifier).reportError(
///   AppException.networkTimeout(),
///   retryAction: () => retryTheOperation(),
/// );
///
/// // Dismiss an error:
/// ref.read(errorNotifierProvider.notifier).dismissError(errorId);
///
/// // Retry an error:
/// ref.read(errorNotifierProvider.notifier).retryError(errorId);
/// ```
class ErrorNotifier extends StateNotifier<ErrorState> {
  ErrorNotifier() : super(const ErrorState());

  // -- Error Reporting --

  /// Report a new error to be displayed to the user.
  ///
  /// [exception] is the error to report.
  /// [retryAction] is an optional async function to retry the operation.
  void reportError(
    AppException exception, {
    Future<void> Function()? retryAction,
  }) {
    final error = AppError(
      id: _generateId(),
      exception: exception,
      timestamp: DateTime.now(),
      retryAction: retryAction,
    );

    // Log the error through the global handler.
    AppErrorHandler.log(
      exception.message,
      level: LogLevel.error,
      tag: 'ErrorProvider',
      error: exception,
    );

    final newActive = [...state.activeErrors, error];
    final newHistory = [...state.errorHistory, error];

    // Trim history if needed.
    final trimmedHistory = newHistory.length > ErrorState.maxHistorySize
        ? newHistory.sublist(newHistory.length - ErrorState.maxHistorySize)
        : newHistory;

    state = state.copyWith(
      activeErrors: newActive,
      errorHistory: trimmedHistory,
      lastErrorTimestamp: error.timestamp,
    );
  }

  /// Report a warning (lower severity, auto-dismissed after delay).
  void reportWarning(String message, {String? code}) {
    reportError(
      AppException.now(
        code: code ?? 'WARNING',
        message: message,
        isRetryable: false,
      ),
    );

    // Auto-dismiss warnings after 8 seconds.
    Future.delayed(const Duration(seconds: 8), () {
      final warnings = state.activeErrors.where((e) => e.code == (code ?? 'WARNING')).toList();
      if (warnings.isNotEmpty) {
        dismissError(warnings.last.id);
      }
    });
  }

  /// Report an informational message (not an error, but worth showing).
  void reportInfo(String message) {
    reportError(
      AppException.now(
        code: 'INFO',
        message: message,
        isRetryable: false,
      ),
    );

    // Auto-dismiss info messages after 5 seconds.
    Future.delayed(const Duration(seconds: 5), () {
      final infos = state.activeErrors.where((e) => e.code == 'INFO').toList();
      if (infos.isNotEmpty) {
        dismissError(infos.last.id);
      }
    });
  }

  // -- Error Actions --

  /// Dismiss an active error by its ID.
  void dismissError(String errorId) {
    final newActive = state.activeErrors
        .where((e) => e.id != errorId)
        .toList();

    state = state.copyWith(activeErrors: newActive);
  }

  /// Dismiss all active errors.
  void dismissAllErrors() {
    state = state.copyWith(activeErrors: const []);
  }

  /// Retry a failed operation by its error ID.
  ///
  /// This updates the error state to show retry progress and
  /// invokes the registered [retryAction]. If the retry fails,
  /// the error remains active with an incremented retry count.
  Future<void> retryError(String errorId) async {
    final errorIndex = state.activeErrors.indexWhere((e) => e.id == errorId);
    if (errorIndex == -1) return;

    final error = state.activeErrors[errorIndex];
    if (!error.isRetryable || error.isRetrying) return;

    // Mark as retrying.
    final retryingError = error.copyWith(isRetrying: true);
    final newActive = [...state.activeErrors];
    newActive[errorIndex] = retryingError;
    state = state.copyWith(activeErrors: newActive);

    try {
      await error.retryAction!();

      // Retry succeeded — dismiss the error.
      dismissError(errorId);

      AppErrorHandler.log(
        'Retry succeeded for error \$errorId',
        level: LogLevel.info,
        tag: 'ErrorProvider',
      );
    } catch (e, st) {
      // Retry failed — update error with incremented count.
      final failedError = error.copyWith(
        isRetrying: false,
        retryCount: error.retryCount + 1,
      );
      final updatedActive = [...state.activeErrors];
      final idx = updatedActive.indexWhere((e) => e.id == errorId);
      if (idx != -1) {
        updatedActive[idx] = failedError;
        state = state.copyWith(activeErrors: updatedActive);
      }

      AppErrorHandler.log(
        'Retry \${failedError.retryCount} failed for error \$errorId',
        level: LogLevel.warning,
        tag: 'ErrorProvider',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Clear all error history (active errors remain).
  void clearHistory() {
    state = state.copyWith(errorHistory: state.activeErrors);
  }

  // -- Global Loading State --

  /// Show the global loading indicator.
  void setLoading(bool loading) {
    state = state.copyWith(isGlobalLoading: loading);
  }

  // -- Private --

  String _generateId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rand = now.hashCode.abs();
    return 'err_\${now.toRadixString(36)}_\${rand.toRadixString(36)}';
  }
}

// ---------------------------------------------------------------------------
// Riverpod Providers
// ---------------------------------------------------------------------------

/// The main error state notifier provider.
///
/// Use this to watch error state and dispatch error actions:
///
/// ```dart
/// final errors = ref.watch(errorNotifierProvider);
/// ref.read(errorNotifierProvider.notifier).reportError(...);
/// ```
final errorNotifierProvider = StateNotifierProvider<ErrorNotifier, ErrorState>((ref) {
  return ErrorNotifier();
});

/// A derived provider that exposes only the active errors list.
///
/// Use this when you only need the active errors (more efficient than
/// watching the entire error state).
///
/// ```dart
/// final activeErrors = ref.watch(activeErrorsProvider);
/// ```
final activeErrorsProvider = Provider<List<AppError>>((ref) {
  return ref.watch(errorNotifierProvider).activeErrors;
});

/// A derived provider that exposes whether any errors are active.
///
/// ```dart
/// final hasErrors = ref.watch(hasErrorsProvider);
/// if (hasErrors) { ... }
/// ```
final hasErrorsProvider = Provider<bool>((ref) {
  return ref.watch(errorNotifierProvider).hasErrors;
});

/// A provider for the most recent error.
///
/// ```dart
/// final latest = ref.watch(mostRecentErrorProvider);
/// ```
final mostRecentErrorProvider = Provider<AppError?>((ref) {
  return ref.watch(errorNotifierProvider).mostRecentError;
});

/// A provider for global loading state.
///
/// ```dart
/// final isLoading = ref.watch(globalLoadingProvider);
/// ```
final globalLoadingProvider = Provider<bool>((ref) {
  return ref.watch(errorNotifierProvider).isGlobalLoading;
});

/// A provider that exposes error statistics.
///
/// ```dart
/// final stats = ref.watch(errorStatsProvider);
/// print(stats.errorCountsByCode);
/// ```
final errorStatsProvider = Provider<ErrorStatistics>((ref) {
  final state = ref.watch(errorNotifierProvider);
  return ErrorStatistics(
    totalErrors: state.errorHistory.length,
    activeErrors: state.activeErrorCount,
    errorCountsByCode: state.errorCountsByCode,
    recentErrors: state.recentErrors.length,
    lastErrorTimestamp: state.lastErrorTimestamp,
  );
});

// ---------------------------------------------------------------------------
// ErrorStatistics - Computed error statistics
// ---------------------------------------------------------------------------

/// Immutable error statistics derived from [ErrorState].
///
/// Use [errorStatsProvider] to access these in widgets.
@immutable
class ErrorStatistics {
  final int totalErrors;
  final int activeErrors;
  final Map<String, int> errorCountsByCode;
  final int recentErrors;
  final DateTime? lastErrorTimestamp;

  const ErrorStatistics({
    required this.totalErrors,
    required this.activeErrors,
    required this.errorCountsByCode,
    required this.recentErrors,
    this.lastErrorTimestamp,
  });

  /// The most common error code.
  String? get mostCommonError {
    if (errorCountsByCode.isEmpty) return null;
    return errorCountsByCode.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }

  /// Whether there have been many recent errors (potential issue).
  bool get hasManyRecentErrors => recentErrors > 10;

  @override
  String toString() {
    return 'ErrorStatistics(total: \$totalErrors, active: \$activeErrors, '
        'recent: \$recentErrors, mostCommon: \$mostCommonError)';
  }
}

// ---------------------------------------------------------------------------
// ErrorToast Widget - Auto-display active errors
// ---------------------------------------------------------------------------

/// A widget that automatically displays active errors as toast/snackbar
/// notifications.
///
/// Place this near the top of your widget tree (inside MaterialApp):
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) => ErrorToast(child: child!),
/// )
/// ```
class ErrorToast extends ConsumerStatefulWidget {
  final Widget child;

  const ErrorToast({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<ErrorToast> createState() => _ErrorToastState();
}

class _ErrorToastState extends ConsumerState<ErrorToast> {
  AppError? _lastShownError;

  @override
  Widget build(BuildContext context) {
    // Watch for new errors.
    final mostRecent = ref.watch(mostRecentErrorProvider);

    // Show a snackbar when a new error arrives.
    if (mostRecent != null && mostRecent.id != _lastShownError?.id) {
      _lastShownError = mostRecent;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showErrorSnackBar(context, mostRecent);
      });
    }

    return widget.child;
  }

  void _showErrorSnackBar(BuildContext context, AppError error) {
    // Don't show INFO/WARNING errors as snackbars (they auto-dismiss).
    if (error.code == 'INFO') return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final isWarning = error.code == 'WARNING';

    messenger.showSnackBar(
      SnackBar(
        duration: isWarning ? const Duration(seconds: 5) : const Duration(seconds: 8),
        backgroundColor: isWarning ? Colors.orange.shade800 : Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            Icon(
              isWarning ? Icons.warning_amber : Icons.error_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                error.message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        action: error.isRetryable
            ? SnackBarAction(
                label: 'RETRY',
                textColor: Colors.amber,
                onPressed: () {
                  ref.read(errorNotifierProvider.notifier).retryError(error.id);
                },
              )
            : SnackBarAction(
                label: 'DISMISS',
                textColor: Colors.white70,
                onPressed: () {
                  ref.read(errorNotifierProvider.notifier).dismissError(error.id);
                },
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ErrorOverlay Widget - Inline error display
// ---------------------------------------------------------------------------

/// An inline widget that displays active errors for a specific section.
///
/// ```dart
/// Column(
///   children: [
///     ErrorOverlay(),
///     MyWidget(),
///   ],
/// )
/// ```
class ErrorOverlay extends ConsumerWidget {
  final String? filterCode;

  const ErrorOverlay({
    super.key,
    this.filterCode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final errors = ref.watch(activeErrorsProvider);
    final filtered = filterCode != null
        ? errors.where((e) => e.code == filterCode).toList()
        : errors;

    if (filtered.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: filtered.map((error) => _ErrorCard(error: error)).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// _ErrorCard - Individual error display card
// ---------------------------------------------------------------------------

class _ErrorCard extends ConsumerWidget {
  final AppError error;

  const _ErrorCard({required this.error});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWarning = error.code == 'WARNING';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isWarning
            ? Colors.orange.shade900.withOpacity(0.3)
            : Colors.red.shade900.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isWarning
              ? Colors.orange.shade600.withOpacity(0.5)
              : Colors.red.shade600.withOpacity(0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                isWarning ? Icons.warning_amber : Icons.error_outline,
                color: isWarning ? Colors.orange.shade300 : Colors.red.shade300,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  error.message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
              if (error.isRetrying)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
                  ),
                )
              else
                IconButton(
                  icon: const Icon(Icons.close, size: 16, color: Colors.white54),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    ref.read(errorNotifierProvider.notifier).dismissError(error.id);
                  },
                ),
            ],
          ),
          if (error.isRetryable && !error.isRetrying) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                ref.read(errorNotifierProvider.notifier).retryError(error.id);
              },
              icon: const Icon(Icons.refresh, size: 14, color: Colors.amber),
              label: Text(
                error.retryCount > 0
                    ? 'Retry (attempt \${error.retryCount + 1})'
                    : 'Retry',
                style: const TextStyle(color: Colors.amber, fontSize: 12),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AsyncErrorHandler - Helper for handling async operation errors
// ---------------------------------------------------------------------------

/// A helper class for consistently handling async operation errors
/// with Riverpod integration.
///
/// ```dart
/// final handler = AsyncErrorHandler(ref);
/// final result = await handler.run(
///   () => api.fetchData(),
///   operationName: 'fetchData',
///   onError: (e) => showCustomError(e),
/// );
/// ```
class AsyncErrorHandler {
  final WidgetRef ref;

  const AsyncErrorHandler(this.ref);

  /// Run an async operation with error handling.
  ///
  /// [operation] is the async function to execute.
  /// [operationName] is a human-readable name for logging.
  /// [retryAction] is an optional retry function.
  /// [onError] is called when an error occurs.
  Future<T?> run<T>(
    Future<T> Function() operation, {
    String? operationName,
    Future<void> Function()? retryAction,
    void Function(AppException)? onError,
  }) async {
    final notifier = ref.read(errorNotifierProvider.notifier);

    try {
      return await operation();
    } on AppException catch (e) {
      notifier.reportError(e, retryAction: retryAction);
      onError?.call(e);
      return null;
    } catch (e, st) {
      final appEx = AppException.unexpected(
        message: operationName != null
            ? '\$operationName failed: \$e'
            : 'Operation failed: \$e',
        originalError: e,
        stackTrace: st,
      );
      notifier.reportError(appEx, retryAction: retryAction);
      onError?.call(appEx);
      return null;
    }
  }

  /// Run an async operation with automatic retry.
  Future<T?> runWithRetry<T>(
    Future<T> Function() operation, {
    String? operationName,
    RetryPolicy policy = RetryPolicy.defaultPolicy,
  }) async {
    final notifier = ref.read(errorNotifierProvider.notifier);

    try {
      return await AppErrorHandler.withRetry(
        operation,
        policy: policy,
        onRetry: (error, attempt) {
          AppErrorHandler.log(
            '\$operationName retry \$attempt after: \${error.message}',
            level: LogLevel.warning,
            tag: 'AsyncRetry',
          );
        },
      );
    } catch (e) {
      final appEx = e is AppException
          ? e
          : AppException.unexpected(
              message: operationName != null
                  ? '\$operationName failed: \$e'
                  : 'Operation failed: \$e',
              originalError: e,
            );
      notifier.reportError(
        appEx,
        retryAction: () => runWithRetry(operation, operationName: operationName),
      );
      return null;
    }
  }
}
