// lib/services/navigation_controller.dart
// Navigation Controller — Self-Use Navigation for MobileCode
//
// Allows SelfInvocationService to navigate between screens, show
// dialogs, bottom sheets, toasts, and snackbars — all without
// needing any BuildContext from the calling side.
//
// Uses a GlobalKey<NavigatorState> to access the navigator from
// anywhere in the app. This is the key mechanism that enables
// the Agent to control UI navigation programmatically.
//
// Usage:
// ```dart
// // In your MaterialApp:
// MaterialApp(
//   navigatorKey: NavigationController.navigatorKey,
//   ...
// )
//
// // Anywhere in the app (including from the Agent):
// NavigationController.goEditor(filePath: "lib/main.dart");
// NavigationController.showToast("Hello from the Agent!");
// ```

import 'package:flutter/material.dart';

import '../core/theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Navigation Controller
// ═══════════════════════════════════════════════════════════════════════════

/// Navigation controller that enables programmatic navigation
/// without needing a BuildContext.
///
/// This is the bridge between the self-invocation system and the
/// Flutter navigation system. It uses a [GlobalKey<NavigatorState>]
/// to access the navigator from anywhere — including background
/// isolates and service layers.
///
/// ## Setup
///
/// Pass the navigator key to your [MaterialApp]:
/// ```dart
/// MaterialApp(
///   navigatorKey: NavigationController.navigatorKey,
///   ...
/// )
/// ```
///
/// ## Route Names
///
/// The following named routes are used throughout the app:
/// | Route | Screen |
/// |-------|--------|
/// | `/editor` | Code Editor |
/// | `/terminal` | Terminal |
/// | `/projects` | Project Manager |
/// | `/github` | GitHub Integration |
/// | `/ai_chat` | AI Chat |
/// | `/settings` | Settings |
class NavigationController {
  NavigationController._();

  /// The global navigator key used to access navigation without context.
  ///
  /// This key must be passed to [MaterialApp.navigatorKey]:
  /// ```dart
  /// MaterialApp(
  ///   navigatorKey: NavigationController.navigatorKey,
  ///   ...
  /// )
  /// ```
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Whether the navigator key has been assigned to a MaterialApp.
  static bool get isInitialized => navigatorKey.currentState != null;

  /// Access the navigator state directly.
  static NavigatorState? get _navigator => navigatorKey.currentState;

  /// Access the current BuildContext from the navigator.
  static BuildContext? get currentContext =>
      navigatorKey.currentState?.overlay?.context;

  // ── Core Navigation ───────────────────────────────────────────────────

  /// Navigate to a named route.
  ///
  /// Uses [Navigator.pushNamed] with optional route arguments.
  /// Returns the result from the pushed route when it pops.
  ///
  /// Example:
  /// ```dart
  /// await NavigationController.navigateTo('/editor', args: {'file': 'main.dart'});
  /// ```
  static Future<T?> navigateTo<T>(
    String route, {
    Map<String, dynamic>? args,
  }) async {
    if (!isInitialized) {
      debugPrint('[NavigationController] Not initialized, cannot navigate to $route');
      return null;
    }

    final result = await _navigator!.pushNamed<T>(
      route,
      arguments: args,
    );
    return result;
  }

  /// Navigate to a named route and replace the current route.
  ///
  /// Uses [Navigator.pushReplacementNamed]. The current route is
  /// removed from the navigation stack.
  static Future<T?> navigateToAndReplace<T, TO>(
    String route, {
    Map<String, dynamic>? args,
    TO? result,
  }) async {
    if (!isInitialized) return null;

    return _navigator!.pushReplacementNamed<T, TO>(
      route,
      arguments: args,
      result: result,
    );
  }

  /// Navigate to a named route and clear all previous routes.
  ///
  /// Uses [Navigator.pushNamedAndRemoveUntil] with a predicate
  /// that always returns false, clearing the entire stack.
  static Future<T?> navigateToAndClear<T>(
    String route, {
    Map<String, dynamic>? args,
  }) async {
    if (!isInitialized) return null;

    return _navigator!.pushNamedAndRemoveUntil<T>(
      route,
      (predicate) => false,
      arguments: args,
    );
  }

  /// Go back to the previous route.
  ///
  /// Uses [Navigator.pop]. If there is no previous route,
  /// nothing happens.
  static Future<void> goBack<T>([T? result]) async {
    if (!isInitialized) return;
    if (_navigator!.canPop()) {
      _navigator!.pop(result);
    }
  }

  /// Pop until the named route is reached.
  ///
  /// Uses [Navigator.popUntil] to pop routes until [routeName]
  /// is at the top of the stack.
  static void popUntil(String routeName) {
    if (!isInitialized) return;
    _navigator!.popUntil(ModalRoute.withName(routeName));
  }

  /// Pop the current route and return to the previous one.
  static void pop<T>([T? result]) {
    if (!isInitialized) return;
    _navigator!.pop(result);
  }

  // ── Named Route Shortcuts ─────────────────────────────────────────────

  /// Navigate to the code editor.
  ///
  /// Optionally specify a [filePath] to open immediately.
  static Future<T?> goEditor<T>({String? filePath}) async {
    return navigateTo<T>(
      '/editor',
      args: filePath != null ? {'filePath': filePath} : null,
    );
  }

  /// Navigate to the terminal.
  static Future<T?> goTerminal<T>() async {
    return navigateTo<T>('/terminal');
  }

  /// Navigate to the projects screen.
  static Future<T?> goProjects<T>() async {
    return navigateTo<T>('/projects');
  }

  /// Navigate to the GitHub integration screen.
  static Future<T?> goGitHub<T>() async {
    return navigateTo<T>('/github');
  }

  /// Navigate to the AI chat screen.
  static Future<T?> goAIChat<T>() async {
    return navigateTo<T>('/ai_chat');
  }

  /// Navigate to the settings screen.
  static Future<T?> goSettings<T>() async {
    return navigateTo<T>('/settings');
  }

  // ── Dialog ────────────────────────────────────────────────────────────

  /// Show an alert dialog.
  ///
  /// Displays a Material dialog with the given [title] and [content].
  /// Optionally customize the confirm/cancel button text.
  static Future<bool?> showDialog({
    required String title,
    required String content,
    String confirmText = 'OK',
    String? cancelText,
    bool barrierDismissible = true,
  }) async {
    final context = currentContext;
    if (context == null) {
      debugPrint('[NavigationController] No context for dialog: $title');
      return null;
    }

    return showAdaptiveDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.border, width: 1),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        content: Text(
          content,
          style: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
        actions: [
          if (cancelText != null)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                cancelText,
                style: const TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              confirmText,
              style: const TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Show a confirmation dialog and return true if confirmed.
  static Future<bool> confirm({
    required String title,
    required String content,
    String confirmText = 'Confirm',
    String cancelText = 'Cancel',
  }) async {
    final result = await showDialog(
      title: title,
      content: content,
      confirmText: confirmText,
      cancelText: cancelText,
    );
    return result == true;
  }

  // ── Bottom Sheet ──────────────────────────────────────────────────────

  /// Show a modal bottom sheet with the given [widget].
  ///
  /// The bottom sheet uses the app's dark theme with rounded corners.
  static Future<T?> showBottomSheet<T>(
    Widget widget, {
    bool isScrollControlled = true,
    bool isDismissible = true,
  }) async {
    final context = currentContext;
    if (context == null) {
      debugPrint('[NavigationController] No context for bottom sheet');
      return null;
    }

    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      isDismissible: isDismissible,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => widget,
    );
  }

  /// Show a bottom sheet that takes up most of the screen.
  static Future<T?> showFullBottomSheet<T>(Widget widget) async {
    final context = currentContext;
    if (context == null) return null;

    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => widget,
      ),
    );
  }

  // ── Toast ─────────────────────────────────────────────────────────────

  /// Show a toast message.
  ///
  /// Uses [OverlayEntry] to display a temporary floating message
  /// that fades out after [duration].
  static void showToast(
    String message, {
    Duration duration = const Duration(seconds: 2),
    ToastPosition position = ToastPosition.bottom,
  }) {
    final context = currentContext;
    if (context == null) {
      debugPrint('[NavigationController] Toast: $message');
      return;
    }

    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (ctx) => _ToastWidget(
        message: message,
        position: position,
        onDismiss: () => overlayEntry.remove(),
      ),
    );

    overlay.insert(overlayEntry);

    // Auto-dismiss
    Future.delayed(duration + const Duration(milliseconds: 300), () {
      if (overlayEntry.mounted) {
        overlayEntry.remove();
      }
    });
  }

  /// Show a success toast (green accent).
  static void showSuccessToast(String message) {
    showToast(message, duration: const Duration(seconds: 2));
  }

  /// Show an error toast (red accent).
  static void showErrorToast(String message) {
    showToast(
      'Error: $message',
      duration: const Duration(seconds: 3),
    );
  }

  // ── Snackbar ──────────────────────────────────────────────────────────

  /// Show a snackbar message.
  ///
  /// Uses the ScaffoldMessenger to display a snackbar at the
  /// bottom of the screen.
  static void showSnackbar(
    String message, {
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
    Color? backgroundColor,
  }) {
    final context = currentContext;
    if (context == null) {
      debugPrint('[NavigationController] Snackbar: $message');
      return;
    }

    final messenger = ScaffoldMessenger.of(context);

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 14,
            color: AppTheme.textPrimary,
          ),
        ),
        duration: duration,
        backgroundColor: backgroundColor ?? AppTheme.surfaceHover,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        behavior: SnackBarBehavior.floating,
        action: actionLabel != null
            ? SnackBarAction(
                label: actionLabel,
                textColor: AppTheme.primary,
                onPressed: onAction ?? () {},
              )
            : null,
      ),
    );
  }

  /// Show a snackbar with an undo action.
  static void showUndoSnackbar(
    String message, {
    required VoidCallback onUndo,
    Duration duration = const Duration(seconds: 5),
  }) {
    showSnackbar(
      message,
      duration: duration,
      actionLabel: 'UNDO',
      onAction: onUndo,
    );
  }

  // ── Loading / Progress ────────────────────────────────────────────────

  /// Show a loading dialog.
  ///
  /// Returns a function that dismisses the dialog when called.
  static VoidCallback showLoading({String message = 'Loading...'}) {
    final context = currentContext;
    if (context == null) {
      return () {};
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                  strokeWidth: 3,
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return () {
      final ctx = currentContext;
      if (ctx != null && Navigator.of(ctx).canPop()) {
        Navigator.of(ctx).pop();
      }
    };
  }

  // ── Utilities ─────────────────────────────────────────────────────────

  /// Get the current route name.
  static String? get currentRoute {
    if (!isInitialized) return null;
    final route = ModalRoute.of(currentContext!);
    return route?.settings.name;
  }

  /// Check if currently on a specific route.
  static bool isOnRoute(String routeName) {
    return currentRoute == routeName;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Toast Position Enum
// ═══════════════════════════════════════════════════════════════════════════

/// Vertical position of a toast on screen.
enum ToastPosition {
  /// Top of the screen.
  top,

  /// Center of the screen.
  center,

  /// Bottom of the screen (default).
  bottom,
}

// ═══════════════════════════════════════════════════════════════════════════
// Toast Widget (internal)
// ═══════════════════════════════════════════════════════════════════════════

/// Internal widget for rendering toast messages.
class _ToastWidget extends StatefulWidget {
  final String message;
  final ToastPosition position;
  final VoidCallback onDismiss;

  const _ToastWidget({
    required this.message,
    required this.position,
    required this.onDismiss,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    _controller.forward();

    // Auto-fade out
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _controller.reverse().then((_) => widget.onDismiss());
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Alignment get _alignment {
    switch (widget.position) {
      case ToastPosition.top:
        return Alignment.topCenter;
      case ToastPosition.center:
        return Alignment.center;
      case ToastPosition.bottom:
        return Alignment.bottomCenter;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Align(
        alignment: _alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceHover.withOpacity(0.95),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              widget.message,
              style: const TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 14,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
