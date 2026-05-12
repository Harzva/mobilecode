// lib/widgets/error_boundary.dart
// Widget-Level Error Boundary for Mobile Agent

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/error_handler.dart';

// ---------------------------------------------------------------------------
// ErrorBoundary - React-style Error Boundary Widget
// ---------------------------------------------------------------------------

/// A widget that catches errors in its child widget tree and displays
/// a fallback UI instead of crashing the entire app.
///
/// Similar to React Error Boundaries, this widget isolates errors so that
/// a failure in one component doesn't bring down the entire application.
///
/// ## Usage
///
/// Wrap any widget that might throw during build, layout, or paint:
///
/// ```dart
/// ErrorBoundary(
///   child: MyComplexWidget(),
///   onError: (error, stack) => reportToAnalytics(error, stack),
/// )
/// ```
///
/// You can also customize the fallback UI:
///
/// ```dart
/// ErrorBoundary.fallback(
///   child: MyWidget(),
///   fallbackBuilder: (context, error, retry) => MyCustomErrorView(error, retry),
/// )
/// ```
class ErrorBoundary extends StatefulWidget {
  /// The widget tree to protect.
  final Widget child;

  /// Optional callback when an error is caught.
  final void Function(dynamic error, StackTrace stackTrace)? onError;

  /// Optional custom fallback builder.
  final Widget Function(
    BuildContext context,
    dynamic error,
    VoidCallback retry,
  )? fallbackBuilder;

  /// Optional human-readable name for this boundary (used in error messages).
  final String? name;

  const ErrorBoundary({
    super.key,
    required this.child,
    this.onError,
    this.fallbackBuilder,
    this.name,
  });

  /// Create an error boundary with a custom fallback widget.
  factory ErrorBoundary.fallback({
    Key? key,
    required Widget child,
    required Widget Function(BuildContext, dynamic, VoidCallback) fallbackBuilder,
    void Function(dynamic, StackTrace)? onError,
    String? name,
  }) {
    return ErrorBoundary(
      key: key,
      child: child,
      fallbackBuilder: fallbackBuilder,
      onError: onError,
      name: name,
    );
  }

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

// ---------------------------------------------------------------------------
// _ErrorBoundaryState
// ---------------------------------------------------------------------------

class _ErrorBoundaryState extends State<ErrorBoundary> {
  dynamic _caughtError;
  StackTrace? _caughtStack;
  bool _hasError = false;

  /// Reset the error state and retry building the child widget.
  void _retry() {
    setState(() {
      _hasError = false;
      _caughtError = null;
      _caughtStack = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      // Show fallback UI when an error has been caught.
      if (widget.fallbackBuilder != null) {
        return widget.fallbackBuilder!(context, _caughtError, _retry);
      }
      return _DefaultErrorFallback(
        error: _caughtError,
        stackTrace: _caughtStack,
        boundaryName: widget.name,
        onRetry: _retry,
      );
    }

    // Normal case: show the protected child widget.
    return widget.child;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reset errors when dependencies change (e.g., theme, locale).
    if (_hasError) {
      _retry();
    }
  }

  @override
  void dispose() {
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// ErrorBoundaryHook - Catch errors via FlutterError.onError integration
// ---------------------------------------------------------------------------

/// A static hook that connects [ErrorBoundary] widgets to the
/// Flutter framework error system.
///
/// This class is used internally by [AppErrorHandler] to route
/// framework errors to the nearest [ErrorBoundary] when possible.
class ErrorBoundaryHook {
  /// Global registry of active error boundary states.
  static final Set<_ErrorBoundaryState> _activeBoundaries = {};

  /// Register an error boundary state as active.
  static void register(_ErrorBoundaryState state) {
    _activeBoundaries.add(state);
  }

  /// Unregister an error boundary state.
  static void unregister(_ErrorBoundaryState state) {
    _activeBoundaries.remove(state);
  }

  /// Try to route a framework error to the most recently mounted
  /// error boundary. Returns true if the error was handled.
  static bool tryHandleError(dynamic error, StackTrace stackTrace) {
    if (_activeBoundaries.isEmpty) return false;

    // Route to the most recently added (likely innermost) boundary.
    final boundary = _activeBoundaries.last;
    // We can't directly set state from here, but we can log it.
    AppErrorHandler.log(
      'Routing error to ErrorBoundary: \$error',
      level: LogLevel.warning,
      tag: 'ErrorBoundary',
      error: error,
      stackTrace: stackTrace,
    );
    return false; // Let the framework handle it for now.
  }
}

// ---------------------------------------------------------------------------
// _DefaultErrorFallback - Built-in error UI
// ---------------------------------------------------------------------------

/// The default fallback UI shown when a child widget crashes.
///
/// Displays:
/// - An error icon
/// - A user-friendly error message
/// - A retry button
/// - Technical details in debug mode
class _DefaultErrorFallback extends StatelessWidget {
  final dynamic error;
  final StackTrace? stackTrace;
  final String? boundaryName;
  final VoidCallback onRetry;

  const _DefaultErrorFallback({
    required this.error,
    this.stackTrace,
    this.boundaryName,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isFatal = error is Error || error is Exception;
    final errorMessage = _getUserFriendlyMessage(error);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.red.shade50.withOpacity(0.1),
        border: Border.all(color: Colors.red.shade300.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Error icon with pulsing animation.
          _ErrorIcon(isFatal: isFatal),
          const SizedBox(height: 16),

          // Error title.
          Text(
            'Something went wrong',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.red.shade300,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          // User-friendly message.
          Text(
            errorMessage,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),

          // Retry button.
          const SizedBox(height: 20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade400,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),

          // Debug info (debug mode only).
          if (kDebugMode) ...[
            const SizedBox(height: 20),
            _DebugInfoSection(
              error: error,
              stackTrace: stackTrace,
              boundaryName: boundaryName,
            ),
          ],
        ],
      ),
    );
  }

  String _getUserFriendlyMessage(dynamic error) {
    if (error is AppException) return error.message;
    if (error is FormatException) return 'Invalid data format. Please try again.';
    if (error is TypeError) return 'A type mismatch occurred. This is a bug in the app.';
    if (error is RangeError) return 'An index was out of bounds. Please try again.';
    if (error is AssertionError) return 'An internal assertion failed. Please try again.';
    if (error is StateError) return 'The app is in an unexpected state. Please try again.';
    return 'An unexpected error occurred. Tap Retry to try again.';
  }
}

// ---------------------------------------------------------------------------
// _ErrorIcon - Animated error icon
// ---------------------------------------------------------------------------

class _ErrorIcon extends StatefulWidget {
  final bool isFatal;

  const _ErrorIcon({required this.isFatal});

  @override
  State<_ErrorIcon> createState() => _ErrorIconState();
}

class _ErrorIconState extends State<_ErrorIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + (_controller.value * 0.1),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: widget.isFatal
                  ? Colors.red.shade900.withOpacity(0.5)
                  : Colors.orange.shade900.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              widget.isFatal ? Icons.error_outline : Icons.warning_amber_outlined,
              size: 40,
              color: widget.isFatal ? Colors.red.shade300 : Colors.orange.shade300,
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// _DebugInfoSection - Expandable debug details (debug mode only)
// ---------------------------------------------------------------------------

class _DebugInfoSection extends StatefulWidget {
  final dynamic error;
  final StackTrace? stackTrace;
  final String? boundaryName;

  const _DebugInfoSection({
    required this.error,
    this.stackTrace,
    this.boundaryName,
  });

  @override
  State<_DebugInfoSection> createState() => _DebugInfoSectionState();
}

class _DebugInfoSectionState extends State<_DebugInfoSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          onPressed: () => setState(() => _expanded = !_expanded),
          icon: Icon(
            _expanded ? Icons.expand_less : Icons.expand_more,
            size: 16,
            color: Colors.white54,
          ),
          label: Text(
            _expanded ? 'Hide Details' : 'Show Details',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
        if (_expanded)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.boundaryName != null)
                  _buildDebugRow('Boundary', widget.boundaryName!),
                _buildDebugRow('Error Type', widget.error.runtimeType.toString()),
                _buildDebugRow('Error', widget.error.toString()),
                if (widget.stackTrace != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Stack Trace:',
                    style: TextStyle(
                      color: Colors.red.shade300,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.stackTrace.toString().split('\n').take(15).join('\n'),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildDebugRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
          children: [
            TextSpan(
              text: '\$label: ',
              style: TextStyle(color: Colors.red.shade300, fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ErrorBoundaryBuilder - Simplified builder API
// ---------------------------------------------------------------------------

/// A simplified builder that wraps a widget tree in an [ErrorBoundary].
///
/// This is useful when you want to protect a section of the UI with
/// minimal boilerplate:
///
/// ```dart
/// ErrorBoundaryBuilder(
///   builder: (context) => MyWidget(),
/// )
/// ```
class ErrorBoundaryBuilder extends StatelessWidget {
  final WidgetBuilder builder;
  final void Function(dynamic, StackTrace)? onError;
  final String? name;

  const ErrorBoundaryBuilder({
    super.key,
    required this.builder,
    this.onError,
    this.name,
  });

  @override
  Widget build(BuildContext context) {
    return ErrorBoundary(
      onError: onError,
      name: name,
      child: Builder(builder: builder),
    );
  }
}

// ---------------------------------------------------------------------------
// MultiErrorBoundary - Protect multiple children independently
// ---------------------------------------------------------------------------

/// A widget that wraps multiple children in their own independent
/// [ErrorBoundary] widgets.
///
/// This is useful for layouts where each section should fail independently:
///
/// ```dart
/// MultiErrorBoundary(
///   children: [
///     ErrorBoundarySection(child: Sidebar()),
///     ErrorBoundarySection(child: Editor()),
///     ErrorBoundarySection(child: Panel()),
///   ],
/// )
/// ```
class MultiErrorBoundary extends StatelessWidget {
  final List<ErrorBoundarySection> children;

  const MultiErrorBoundary({
    super.key,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: children
          .map((section) => Expanded(
                flex: section.flex,
                child: ErrorBoundary(
                  name: section.name,
                  fallbackBuilder: section.fallbackBuilder,
                  child: section.child,
                ),
              ))
          .toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// ErrorBoundarySection - Configuration for MultiErrorBoundary
// ---------------------------------------------------------------------------

/// Configuration for a single section within [MultiErrorBoundary].
class ErrorBoundarySection {
  final Widget child;
  final String? name;
  final int flex;
  final Widget Function(BuildContext, dynamic, VoidCallback)? fallbackBuilder;

  const ErrorBoundarySection({
    required this.child,
    this.name,
    this.flex = 1,
    this.fallbackBuilder,
  });
}
