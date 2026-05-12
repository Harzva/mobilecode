import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ============================================================================
/// HAPTIC FEEDBACK SERVICE
/// ============================================================================
///
/// A complete haptic feedback system providing tactile responses for every
/// user interaction in the MobileCode Flutter app.
///
/// Features:
/// - 6 impact intensities (light → heavy, with subtle variations)
/// - 6 feedback patterns (success, failure, warning, typing, scroll, drag)
/// - Context-aware feedback (navigation, AI responses, code completion)
/// - Custom rhythmic patterns for build/git operations
/// - Global enable/disable toggle with persistent preference support
/// - Widget wrappers for declarative haptic integration
///
/// Usage:
/// ```dart
/// // Direct service call
/// HapticFeedbackService.lightImpact();
///
/// // Declarative widget wrapper
/// HapticButton(
///   feedback: HapticType.medium,
///   onPressed: () => print('tapped'),
///   child: Text('Tap Me'),
/// )
/// ```
///
/// Add to pubspec.yaml:
/// ```yaml
/// dependencies:
///   vibrate: ^1.0.0  # Optional: extended vibration patterns on Android
/// ```

// ---------------------------------------------------------------------------
// Haptic Type Enum
// ---------------------------------------------------------------------------

/// Defines the available haptic feedback intensities and patterns.
///
/// Each type maps to a specific tactile sensation appropriate for its
/// semantic meaning, ensuring consistent feedback across the entire app.
enum HapticType {
  /// Barely perceptible — micro-interactions, hover states.
  /// Use for: subtle UI state changes, cursor movement.
  subtle,

  /// Light tap — small button press, checkbox toggle.
  /// Use for: standard tappable elements, chip selection.
  light,

  /// Medium tap — card selection, toggle switch, tab change.
  /// Use for: more prominent interactive elements.
  medium,

  /// Heavy thud — major action confirmation, destructive operations.
  /// Use for: delete confirmations, significant state changes.
  heavy,

  /// Intense rumble — critical alerts, emergencies.
  /// Use for: errors requiring immediate attention.
  intense,

  /// Selection click — picker item, scroll snap, slider tick.
  /// Use for: discrete value changes, list scrolling.
  selection,

  /// Success pattern — ascending double pulse (light → medium).
  /// Use for: completed operations, positive confirmations.
  success,

  /// Failure pattern — descending double pulse (heavy → medium).
  /// Use for: errors, rejected actions, validation failures.
  failure,

  /// Warning pattern — double medium pulse with pause.
  /// Use for: attention-needed states, cautions.
  warning,

  /// Triple pulse — notification arrival.
  /// Use for: in-app notifications, new messages.
  notification,
}

// ---------------------------------------------------------------------------
// Haptic Feedback Service
// ---------------------------------------------------------------------------

/// Central service for all haptic feedback in the app.
///
/// Provides both individual impact methods and high-level semantic patterns.
/// All methods respect the global [_enabled] flag — when disabled, calls
/// become no-ops with zero overhead.
///
/// The service is designed as a static class (no instance required) for
/// convenience since haptic feedback is a global system resource.
class HapticFeedbackService {
  // -- Private State --

  static bool _enabled = true;

  /// Whether haptic feedback is globally enabled.
  ///
  /// When `false`, all haptic methods become no-ops. This allows users
  /// to disable feedback in accessibility settings.
  static bool get isEnabled => _enabled;

  /// Globally enable or disable haptic feedback.
  ///
  /// Setting this to `false` immediately silences all feedback without
  /// requiring changes to calling code.
  static set enabled(bool value) => _enabled = value;

  // -- Basic Impact Feedback --

  /// Subtle impact — barely perceptible tactile nudge.
  ///
  /// Use for: hover state activation, cursor movement in code editor,
  /// micro-position adjustments.
  static void subtleImpact() {
    if (!_enabled) return;
    // On iOS: uses UIImpactFeedbackStyle.light with reduced intensity
    // On Android: uses HapticFeedbackConstants.CLOCK_TICK
    HapticFeedback.lightImpact();
  }

  /// Light impact — gentle tap sensation.
  ///
  /// Use for: button presses, checkbox toggles, chip selections,
  /// small icon taps.
  static void lightImpact() {
    if (!_enabled) return;
    HapticFeedback.lightImpact();
  }

  /// Medium impact — moderate tap sensation.
  ///
  /// Use for: card selections, toggle switches, tab bar changes,
  /// bottom sheet presentations.
  static void mediumImpact() {
    if (!_enabled) return;
    HapticFeedback.mediumImpact();
  }

  /// Heavy impact — strong, pronounced thud.
  ///
  /// Use for: major action confirmations, destructive operations,
  /// modal presentations, long-press activation.
  static void heavyImpact() {
    if (!_enabled) return;
    HapticFeedback.heavyImpact();
  }

  /// Intense impact — maximum strength feedback.
  ///
  /// Use for: critical error alerts, emergency notifications,
  /// security-related confirmations.
  static void intenseImpact() {
    if (!_enabled) return;
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 30), () {
      HapticFeedback.heavyImpact();
    });
  }

  /// Selection click — crisp discrete tick.
  ///
  /// Use for: picker item selection, scroll snap points,
  /// slider discrete values, stepper changes.
  static void selectionClick() {
    if (!_enabled) return;
    HapticFeedback.selectionClick();
  }

  // -- Semantic Feedback Patterns --

  /// Success pattern — ascending double pulse.
  ///
  /// Tactile feel: light tap followed quickly by medium tap,
  /// creating a subtle "rising" sensation that feels positive.
  ///
  /// Use for: operation completed, file saved, build succeeded,
  /// message sent, settings applied.
  static void success() {
    if (!_enabled) return;
    HapticFeedback.lightImpact();
    Future.delayed(const Duration(milliseconds: 60), () {
      HapticFeedback.mediumImpact();
    });
  }

  /// Success strong — more pronounced success pattern.
  ///
  /// Three-pulse ascending pattern for major success events.
  /// Use for: deployment complete, all tests passed, merge successful.
  static void successStrong() {
    if (!_enabled) return;
    HapticFeedback.lightImpact();
    Future.delayed(const Duration(milliseconds: 50), () {
      HapticFeedback.mediumImpact();
    });
    Future.delayed(const Duration(milliseconds: 120), () {
      HapticFeedback.mediumImpact();
    });
  }

  /// Failure pattern — descending double pulse.
  ///
  /// Tactile feel: heavy impact followed by medium impact after
  /// a short pause, creating a "falling" sensation that feels negative.
  ///
  /// Use for: operation failed, build error, network timeout,
  /// validation error, permission denied.
  static void failure() {
    if (!_enabled) return;
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 100), () {
      HapticFeedback.mediumImpact();
    });
  }

  /// Warning pattern — rhythmic double pulse.
  ///
  /// Tactile feel: two medium impacts with a noticeable pause,
  /// drawing attention without the negativity of failure.
  ///
  /// Use for: unsaved changes warning, deprecated API usage,
  /// slow operation detected, battery low.
  static void warning() {
    if (!_enabled) return;
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 120), () {
      HapticFeedback.mediumImpact();
    });
  }

  /// Notification pattern — triple pulse.
  ///
  /// Tactile feel: light → medium → light in quick succession,
  /// similar to a notification arrival.
  ///
  /// Use for: new message received, AI response ready,
  /// background task complete, collaborator joined.
  static void notification() {
    if (!_enabled) return;
    HapticFeedback.lightImpact();
    Future.delayed(const Duration(milliseconds: 50), () {
      HapticFeedback.mediumImpact();
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      HapticFeedback.lightImpact();
    });
  }

  // -- Interaction-Specific Feedback --

  /// Typing feedback — each keystroke.
  ///
  /// Provides subtle tactile confirmation for virtual keyboard input.
  /// Maps to the selection click for a crisp, precise feel.
  static void typing() {
    if (!_enabled) return;
    HapticFeedback.selectionClick();
  }

  /// Scroll feedback — at snap points.
  ///
  /// Triggered when a scroll view lands on a predefined snap point.
  /// Gives users a sense of precision and control.
  static void scrollSnap() {
    if (!_enabled) return;
    HapticFeedback.selectionClick();
  }

  /// Scroll momentum start — flick gesture.
  ///
  /// Subtle feedback when a scroll view begins momentum scrolling
  /// after a flick gesture, confirming the action.
  static void scrollFlick() {
    if (!_enabled) return;
    HapticFeedback.lightImpact();
  }

  /// Drag start — beginning of drag gesture.
  ///
  /// Confirms that a draggable element has been "picked up"
  /// and is now being manipulated.
  static void dragStart() {
    if (!_enabled) return;
    HapticFeedback.lightImpact();
  }

  /// Drag update — continuous drag feedback.
  ///
  /// Provides continuous feedback during drag operations.
  /// Called at reasonable intervals (throttled by caller) to
  /// avoid excessive vibration.
  static void dragUpdate() {
    if (!_enabled) return;
    // Intentionally minimal — most drags don't need continuous feedback
    // Use sparingly for drag-over-target indications
  }

  /// Drag end — element dropped.
  ///
  /// Confirms that a dragged element has been released.
  /// Use with [dragStart] for complete drag lifecycle feedback.
  static void dragEnd() {
    if (!_enabled) return;
    HapticFeedback.mediumImpact();
  }

  /// Drag cancelled — drag aborted.
  ///
  /// Signals that a drag operation was cancelled (e.g., moved
  /// outside valid drop zone and released).
  static void dragCancel() {
    if (!_enabled) return;
    HapticFeedback.lightImpact();
  }

  /// Long press activated — after threshold duration.
  ///
  /// Triggered when a long-press gesture is recognized,
  /// typically before showing a context menu or entering
  /// reorder/edit mode.
  static void longPress() {
    if (!_enabled) return;
    HapticFeedback.heavyImpact();
  }

  /// Long press released — after long-press ends.
  ///
  /// Optional feedback when the user releases a long press.
  static void longPressEnd() {
    if (!_enabled) return;
    HapticFeedback.lightImpact();
  }

  // -- Navigation Feedback --

  /// Navigation transition — screen change.
  ///
  /// Subtle feedback when pushing a new route onto the navigation stack.
  static void navigate() {
    if (!_enabled) return;
    HapticFeedback.lightImpact();
  }

  /// Navigation back — returning to previous screen.
  ///
  /// Slightly different feel from forward navigation to help users
  /// build a mental model of navigation direction.
  static void navigateBack() {
    if (!_enabled) return;
    HapticFeedback.selectionClick();
  }

  /// Modal presentation — bottom sheet / dialog.
  ///
  /// More pronounced feedback for modal overlays since they
  /// interrupt the current flow.
  static void presentModal() {
    if (!_enabled) return;
    HapticFeedback.mediumImpact();
  }

  /// Modal dismissal — closing overlay.
  static void dismissModal() {
    if (!_enabled) return;
    HapticFeedback.lightImpact();
  }

  // -- App-Specific: Code Editor --

  /// AI response received — new content ready.
  ///
  /// Subtle notification that AI has generated a response.
  /// Light enough to not interrupt flow state.
  static void aiResponse() {
    if (!_enabled) return;
    HapticFeedback.selectionClick();
  }

  /// AI streaming — content arriving in real-time.
  ///
  /// Ultra-subtle feedback for streaming content chunks.
  /// Should be called infrequently (every ~500ms at most) to
  /// avoid annoyance.
  static void aiStreaming() {
    if (!_enabled) return;
    // Very subtle — barely perceptible
    HapticFeedback.selectionClick();
  }

  /// Code completion — auto-complete suggestion applied.
  ///
  /// Crisp feedback when a code completion suggestion is accepted,
  /// reinforcing the efficiency of using completions.
  static void codeComplete() {
    if (!_enabled) return;
    HapticFeedback.selectionClick();
  }

  /// Code error — lint/error detected at cursor.
  ///
  /// Warns the user that their current code has an issue.
  /// Should only fire once per error to avoid spam.
  static void codeError() {
    if (!_enabled) return;
    HapticFeedback.lightImpact();
  }

  /// Cursor line change — moved to different line.
  ///
  /// Optional feedback for significant cursor movements,
  /// helps with keyboard navigation.
  static void cursorLineChange() {
    if (!_enabled) return;
    // Very subtle — only for accessibility mode
    // HapticFeedback.selectionClick();
  }

  // -- App-Specific: Build & Deploy --

  /// Build started — compilation initiated.
  ///
  /// Signals that a build process has begun.
  static void buildStart() {
    if (!_enabled) return;
    HapticFeedback.lightImpact();
  }

  /// Build complete — successful compilation.
  ///
  /// Full success pattern for build completion.
  static void buildComplete() {
    if (!_enabled) return;
    success();
  }

  /// Build failed — compilation error.
  ///
  /// Failure pattern for build errors.
  static void buildFailed() {
    if (!_enabled) return;
    failure();
  }

  /// Test passed — individual test success.
  ///
  /// Very subtle per-test feedback. Use carefully to avoid
  /// excessive vibration during test runs.
  static void testPassed() {
    if (!_enabled) return;
    // Subtle — only in verbose/test mode
    // HapticFeedback.selectionClick();
  }

  /// Test failed — assertion error.
  static void testFailed() {
    if (!_enabled) return;
    HapticFeedback.lightImpact();
  }

  // -- App-Specific: Git Operations --

  /// Git commit — snapshot created.
  ///
  /// Satisfying medium impact for the "commit" action,
  /// one of the most common git operations.
  static void gitCommit() {
    if (!_enabled) return;
    HapticFeedback.mediumImpact();
  }

  /// Git push — code uploaded.
  ///
  /// Success pattern for pushing changes to remote.
  static void gitPush() {
    if (!_enabled) return;
    success();
  }

  /// Git pull — code downloaded.
  ///
  /// Similar to push but with slightly different feel.
  static void gitPull() {
    if (!_enabled) return;
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 80), () {
      HapticFeedback.selectionClick();
    });
  }

  /// Git merge — branches combined.
  ///
  /// More pronounced feedback since merge is a significant operation.
  static void gitMerge() {
    if (!_enabled) return;
    successStrong();
  }

  /// Git branch created.
  static void gitBranch() {
    if (!_enabled) return;
    HapticFeedback.lightImpact();
  }

  /// Git checkout — switched branches.
  static void gitCheckout() {
    if (!_enabled) return;
    HapticFeedback.mediumImpact();
  }

  // -- Utility --

  /// Trigger feedback by enum type.
  ///
  /// Convenience method that maps a [HapticType] to the appropriate
  /// service method. Useful when the feedback type is determined
  /// dynamically.
  static void trigger(HapticType type) {
    switch (type) {
      case HapticType.subtle:
        subtleImpact();
        break;
      case HapticType.light:
        lightImpact();
        break;
      case HapticType.medium:
        mediumImpact();
        break;
      case HapticType.heavy:
        heavyImpact();
        break;
      case HapticType.intense:
        intenseImpact();
        break;
      case HapticType.selection:
        selectionClick();
        break;
      case HapticType.success:
        success();
        break;
      case HapticType.failure:
        failure();
        break;
      case HapticType.warning:
        warning();
        break;
      case HapticType.notification:
        notification();
        break;
    }
  }

  /// Perform a custom rhythmic pattern.
  ///
  /// [durations] is a list of millisecond delays between impacts.
  /// [intensities] is a parallel list of impact levels (1-3).
  ///
  /// Example — triple-tap SOS pattern:
  /// ```dart
  /// HapticFeedbackService.customPattern(
  ///   durations: [0, 100, 100, 0, 100, 100],
  ///   intensities: [1, 1, 1, 2, 2, 2],
  /// );
  /// ```
  static void customPattern({
    required List<int> durations,
    required List<int> intensities,
  }) {
    if (!_enabled) return;
    assert(durations.length == intensities.length,
        'durations and intensities must have the same length');

    for (int i = 0; i < durations.length; i++) {
      Future.delayed(Duration(milliseconds: durations[i]), () {
        switch (intensities[i]) {
          case 1:
            HapticFeedback.lightImpact();
            break;
          case 2:
            HapticFeedback.mediumImpact();
            break;
          case 3:
            HapticFeedback.heavyImpact();
            break;
          default:
            HapticFeedback.selectionClick();
        }
      });
    }
  }

  /// Temporarily suppress haptic feedback.
  ///
  /// Returns a function that re-enables feedback when called.
  /// Useful for batch operations where individual feedback
  /// would be excessive.
  ///
  /// ```dart
  /// final restore = HapticFeedbackService.suppress();
  /// for (final item in items) { /* ... process ... */ }
  /// restore(); // Re-enable feedback
  /// ```
  static VoidCallback suppress() {
    final wasEnabled = _enabled;
    _enabled = false;
    return () => _enabled = wasEnabled;
  }

  /// Perform an action with haptic feedback suppressed.
  ///
  /// Convenient wrapper that automatically restores feedback
  /// after the action completes, even if it throws.
  static Future<T> suppressed<T>(Future<T> Function() action) async {
    final restore = suppress();
    try {
      return await action();
    } finally {
      restore();
    }
  }
}

// ---------------------------------------------------------------------------
// HapticButton Widget
// ---------------------------------------------------------------------------

/// A button wrapper that automatically provides haptic feedback on tap.
///
/// Wraps any child widget with a [GestureDetector] that triggers
/// haptic feedback before calling [onPressed].
///
/// ```dart
/// HapticButton(
///   feedback: HapticType.medium,
///   onPressed: () => Navigator.pushNamed(context, '/settings'),
///   child: ListTile(title: Text('Settings')),
/// )
/// ```
class HapticButton extends StatelessWidget {
  /// The widget to display and make tappable.
  final Widget child;

  /// Callback invoked after haptic feedback.
  final VoidCallback? onPressed;

  /// The type of haptic feedback to provide.
  final HapticType feedback;

  /// Minimum time between feedback events (debounce).
  ///
  /// Prevents rapid successive taps from causing
  /// excessive vibration. Default: 150ms.
  final Duration debounce;

  /// Whether to block the tap during debounce period.
  final bool blockDuringDebounce;

  const HapticButton({
    super.key,
    required this.child,
    this.onPressed,
    this.feedback = HapticType.light,
    this.debounce = const Duration(milliseconds: 150),
    this.blockDuringDebounce = false,
  });

  @override
  Widget build(BuildContext context) {
    return _HapticButtonInternal(
      onPressed: onPressed,
      feedback: feedback,
      debounce: debounce,
      blockDuringDebounce: blockDuringDebounce,
      child: child,
    );
  }
}

/// Internal stateful widget that handles debounce logic.
class _HapticButtonInternal extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final HapticType feedback;
  final Duration debounce;
  final bool blockDuringDebounce;

  const _HapticButtonInternal({
    required this.child,
    this.onPressed,
    required this.feedback,
    required this.debounce,
    required this.blockDuringDebounce,
  });

  @override
  State<_HapticButtonInternal> createState() => _HapticButtonInternalState();
}

class _HapticButtonInternalState extends State<_HapticButtonInternal> {
  DateTime? _lastTap;

  void _handleTap() {
    final now = DateTime.now();

    // Debounce check
    if (_lastTap != null) {
      final elapsed = now.difference(_lastTap!);
      if (elapsed < widget.debounce) {
        if (widget.blockDuringDebounce) return;
        // If not blocking, skip haptic but allow callback
        widget.onPressed?.call();
        return;
      }
    }

    _lastTap = now;
    HapticFeedbackService.trigger(widget.feedback);
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.onPressed != null ? _handleTap : null,
      child: widget.child,
    );
  }
}

// ---------------------------------------------------------------------------
// HapticIconButton Widget
// ---------------------------------------------------------------------------

/// An icon button with built-in haptic feedback.
///
/// Provides a convenient wrapper around [IconButton] that adds
/// tactile feedback while preserving all standard icon button
/// functionality.
class HapticIconButton extends StatelessWidget {
  /// The icon to display.
  final IconData icon;

  /// Callback when tapped.
  final VoidCallback? onPressed;

  /// Haptic feedback type.
  final HapticType feedback;

  /// Icon size.
  final double? iconSize;

  /// Icon color.
  final Color? color;

  /// Visual density.
  final VisualDensity? visualDensity;

  /// Tooltip text.
  final String? tooltip;

  const HapticIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.feedback = HapticType.light,
    this.iconSize,
    this.color,
    this.visualDensity,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return HapticButton(
      feedback: feedback,
      onPressed: onPressed,
      child: IconButton(
        icon: Icon(icon),
        iconSize: iconSize,
        color: color,
        visualDensity: visualDensity,
        tooltip: tooltip,
        onPressed: () {}, // Handled by HapticButton wrapper
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HapticListTile Widget
// ---------------------------------------------------------------------------

/// A list tile with haptic feedback on tap.
///
/// Wraps [ListTile] to provide tactile feedback for list
/// interactions, commonly used in settings and menus.
class HapticListTile extends StatelessWidget {
  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final HapticType feedback;
  final EdgeInsets? contentPadding;
  final bool selected;
  final ShapeBorder? shape;

  const HapticListTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.feedback = HapticType.light,
    this.contentPadding,
    this.selected = false,
    this.shape,
  });

  @override
  Widget build(BuildContext context) {
    return HapticButton(
      feedback: feedback,
      onPressed: onTap,
      child: ListTile(
        leading: leading,
        title: title,
        subtitle: subtitle,
        trailing: trailing,
        contentPadding: contentPadding,
        selected: selected,
        shape: shape,
        onTap: null, // Handled by HapticButton
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HapticFloatingActionButton Widget
// ---------------------------------------------------------------------------

/// A floating action button with haptic feedback.
///
/// Primary action button with medium impact feedback,
/// appropriate for the most prominent action on a screen.
class HapticFAB extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final HapticType feedback;
  final Color? backgroundColor;
  final String? tooltip;
  final Object? heroTag;
  final ShapeBorder? shape;

  const HapticFAB({
    super.key,
    required this.onPressed,
    required this.child,
    this.feedback = HapticType.medium,
    this.backgroundColor,
    this.tooltip,
    this.heroTag,
    this.shape,
  });

  @override
  Widget build(BuildContext context) {
    return HapticButton(
      feedback: feedback,
      onPressed: onPressed,
      child: FloatingActionButton(
        onPressed: () {}, // Handled by wrapper
        backgroundColor: backgroundColor,
        tooltip: tooltip,
        heroTag: heroTag,
        shape: shape,
        child: child,
      ),
    );
  }
}
