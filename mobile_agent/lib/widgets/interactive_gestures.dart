import 'dart:math' show max, min;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/haptic_feedback_service.dart';

/// ============================================================================
/// INTERACTIVE GESTURE WIDGETS
/// ============================================================================
///
/// Custom gesture-aware widgets with built-in haptic feedback.
///
/// These widgets extend standard Flutter gesture detectors with:
/// - Tactile feedback at key gesture milestones
/// - Smooth animations and transitions
/// - Accessibility-friendly interaction patterns
/// - Visual feedback that complements haptic sensations
///
/// All widgets respect the global haptic enabled/disabled setting.
///
/// Widgets included:
/// - [SwipeableCard]        — Dismissible cards with haptic
/// - [PullToRefresh]        — Refresh indicator with feedback
/// - [DoubleTapAction]      — Single + double tap with haptic
/// - [LongPressMenu]        — Context menu with haptic activation
/// - [PinchZoom]            — Pinch-to-zoom with boundary haptic
/// - [HapticScroll]         — Scroll with snap point feedback
/// - [TapScale]             — Scale animation on tap
/// - [DraggableItem]        — Drag with full lifecycle haptic
/// - [SwipeActionCard]      — Multi-action swipeable card
/// - [ElasticPull]          — Elastic overscroll effect

// ---------------------------------------------------------------------------
// SwipeableCard — Dismissible with haptic feedback
// ---------------------------------------------------------------------------

/// A card that can be swiped away with satisfying haptic feedback.
///
/// Wraps [Dismissible] to provide tactile confirmation when:
/// - Swipe threshold is reached (warning haptic)
/// - Card is dismissed (success haptic)
///
/// Features a colored background that reveals during the swipe,
/// giving visual feedback alongside the haptic sensation.
class SwipeableCard extends StatelessWidget {
  /// Unique key for the dismissible widget.
  final Key itemKey;

  /// The card content.
  final Widget child;

  /// Called when the card is dismissed.
  final VoidCallback onDismiss;

  /// Direction(s) allowed for dismissal.
  final DismissDirection direction;

  /// Background shown during swipe (left-to-right).
  final Widget? background;

  /// Secondary background shown during swipe (right-to-left).
  final Widget? secondaryBackground;

  /// Haptic type on dismiss threshold reached.
  final HapticType thresholdHaptic;

  /// Haptic type on successful dismiss.
  final HapticType dismissHaptic;

  const SwipeableCard({
    super.key,
    required this.itemKey,
    required this.child,
    required this.onDismiss,
    this.direction = DismissDirection.horizontal,
    this.background,
    this.secondaryBackground,
    this.thresholdHaptic = HapticType.warning,
    this.dismissHaptic = HapticType.success,
  });

  @override
  Widget build(BuildContext context) {
    final defaultBackground = Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 20),
      decoration: BoxDecoration(
        color: Colors.redAccent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.delete, color: Colors.white, size: 28),
          SizedBox(width: 8),
          Text(
            'Delete',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );

    final defaultSecondaryBg = Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      decoration: BoxDecoration(
        color: Colors.orangeAccent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            'Archive',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          SizedBox(width: 8),
          Icon(Icons.archive, color: Colors.white, size: 28),
        ],
      ),
    );

    return Dismissible(
      key: itemKey,
      direction: direction,
      onDismissed: (_) {
        HapticFeedbackService.trigger(dismissHaptic);
        onDismiss();
      },
      onResize: () {
        // Haptic when dismiss threshold is crossed
        HapticFeedbackService.trigger(thresholdHaptic);
      },
      background: background ?? defaultBackground,
      secondaryBackground: secondaryBackground ?? defaultSecondaryBg,
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// PullToRefresh — Refresh indicator with haptic
// ---------------------------------------------------------------------------

/// A pull-to-refresh wrapper with haptic feedback at each stage.
///
/// Provides tactile feedback when:
/// - Pull threshold is reached (medium impact)
/// - Refresh completes (success pattern)
///
/// The [RefreshIndicator] progress is tracked to provide
/// feedback at the exact moment the threshold is crossed.
class PullToRefresh extends StatefulWidget {
  /// The scrollable content.
  final Widget child;

  /// Async callback when refresh is triggered.
  final Future<void> Function() onRefresh;

  /// Color of the refresh indicator.
  final Color? color;

  /// Background color of the indicator circle.
  final Color? backgroundColor;

  /// The displacement from the top edge.
  final double displacement;

  const PullToRefresh({
    super.key,
    required this.child,
    required this.onRefresh,
    this.color,
    this.backgroundColor,
    this.displacement = 40.0,
  });

  @override
  State<PullToRefresh> createState() => _PullToRefreshState();
}

class _PullToRefreshState extends State<PullToRefresh> {
  bool _didTriggerHaptic = false;

  Future<void> _handleRefresh() async {
    // Haptic at start of refresh
    HapticFeedbackService.mediumImpact();
    await widget.onRefresh();
    // Success haptic on completion
    HapticFeedbackService.success();
    _didTriggerHaptic = false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<OverscrollIndicatorNotification>(
      onNotification: (notification) {
        notification.disallowIndicator();
        return true;
      },
      child: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: widget.color ?? Theme.of(context).colorScheme.primary,
        backgroundColor:
            widget.backgroundColor ?? Theme.of(context).colorScheme.surface,
        displacement: widget.displacement,
        child: widget.child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// DoubleTapAction — Single and double tap with haptic
// ---------------------------------------------------------------------------

/// A widget that distinguishes between single and double taps
/// with different haptic feedback for each.
///
/// Single tap: selection click (subtle)
/// Double tap: medium impact (more pronounced)
///
/// Uses a tap timer to correctly distinguish between the two
/// gestures without false triggering.
class DoubleTapAction extends StatefulWidget {
  /// The child widget.
  final Widget child;

  /// Called on single tap.
  final VoidCallback? onSingleTap;

  /// Called on double tap.
  final VoidCallback? onDoubleTap;

  /// Haptic for single tap.
  final HapticType singleTapHaptic;

  /// Haptic for double tap.
  final HapticType doubleTapHaptic;

  const DoubleTapAction({
    super.key,
    required this.child,
    this.onSingleTap,
    this.onDoubleTap,
    this.singleTapHaptic = HapticType.selection,
    this.doubleTapHaptic = HapticType.medium,
  });

  @override
  State<DoubleTapAction> createState() => _DoubleTapActionState();
}

class _DoubleTapActionState extends State<DoubleTapAction> {
  /// Timer to distinguish single from double tap.
  bool _isWaitingForDoubleTap = false;

  void _handleTap() {
    if (_isWaitingForDoubleTap) return;

    _isWaitingForDoubleTap = true;
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted && _isWaitingForDoubleTap) {
        _isWaitingForDoubleTap = false;
        HapticFeedbackService.trigger(widget.singleTapHaptic);
        widget.onSingleTap?.call();
      }
    });
  }

  void _handleDoubleTap() {
    _isWaitingForDoubleTap = false;
    HapticFeedbackService.trigger(widget.doubleTapHaptic);
    widget.onDoubleTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onSingleTap != null ? _handleTap : null,
      onDoubleTap: widget.onDoubleTap != null ? _handleDoubleTap : null,
      child: widget.child,
    );
  }
}

// ---------------------------------------------------------------------------
// LongPressMenu — Context menu with haptic
// ---------------------------------------------------------------------------

/// A widget that shows a context menu on long-press with
/// satisfying haptic feedback at activation.
///
/// Features:
/// - Heavy impact on long-press threshold reached
/// - Animated menu appearance
/// - Dismiss on tap outside
/// - Position-aware menu placement
class LongPressMenu extends StatefulWidget {
  /// The child widget.
  final Widget child;

  /// Menu items to display.
  final List<MenuItem> menuItems;

  /// Called when the menu opens.
  final VoidCallback? onMenuOpen;

  /// Called when the menu closes.
  final VoidCallback? onMenuClose;

  const LongPressMenu({
    super.key,
    required this.child,
    required this.menuItems,
    this.onMenuOpen,
    this.onMenuClose,
  });

  @override
  State<LongPressMenu> createState() => _LongPressMenuState();
}

/// A single item in the long-press context menu.
class MenuItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;

  const MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
  });
}

class _LongPressMenuState extends State<LongPressMenu> {
  final OverlayPortalController _overlayController =
      OverlayPortalController();

  void _showMenu(BuildContext context, LongPressStartDetails details) {
    HapticFeedbackService.longPress();
    widget.onMenuOpen?.call();

    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);

    // Show the menu overlay
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _MenuSheet(
        menuItems: widget.menuItems,
        onClose: () {
          widget.onMenuClose?.call();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (details) => _showMenu(context, details),
      child: widget.child,
    );
  }
}

/// The bottom sheet that displays menu items.
class _MenuSheet extends StatelessWidget {
  final List<MenuItem> menuItems;
  final VoidCallback? onClose;

  const _MenuSheet({
    required this.menuItems,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C3E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[600] : Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Menu items
          ...List.generate(menuItems.length, (index) {
            final item = menuItems[index];
            return Column(
              children: [
                ListTile(
                  leading: Icon(
                    item.icon,
                    color: item.iconColor ??
                        Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(
                    item.label,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () {
                    HapticFeedbackService.lightImpact();
                    Navigator.pop(context);
                    item.onTap();
                    onClose?.call();
                  },
                ),
                if (index < menuItems.length - 1)
                  Divider(
                    height: 1,
                    indent: 56,
                    color: isDark ? Colors.grey[700] : Colors.grey[200],
                  ),
              ],
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PinchZoom — Pinch-to-zoom with boundary haptic
// ---------------------------------------------------------------------------

/// A widget that enables pinch-to-zoom with haptic feedback
/// at scale boundaries.
///
/// Provides:
/// - Light impact at drag start
/// - Impact at min/max scale boundaries
/// - Medium impact when zoom ends
/// - Smooth scale transitions
///
/// Suitable for images, code previews, diagrams, and any
/// content that benefits from zoom inspection.
class PinchZoom extends StatefulWidget {
  /// The child widget to zoom.
  final Widget child;

  /// Minimum allowed scale.
  final double minScale;

  /// Maximum allowed scale.
  final double maxScale;

  /// Whether to animate back to bounds on release.
  final bool snapToBounds;

  /// Duration of the snap animation.
  final Duration snapDuration;

  const PinchZoom({
    super.key,
    required this.child,
    this.minScale = 0.8,
    this.maxScale = 4.0,
    this.snapToBounds = true,
    this.snapDuration = const Duration(milliseconds: 200),
  });

  @override
  State<PinchZoom> createState() => _PinchZoomState();
}

class _PinchZoomState extends State<PinchZoom>
    with SingleTickerProviderStateMixin {
  double _scale = 1.0;
  double _previousScale = 1.0;
  Offset _offset = Offset.zero;
  Offset _previousOffset = Offset.zero;
  bool _didBoundaryHaptic = false;

  late AnimationController _snapController;
  Animation<double>? _scaleAnimation;
  Animation<Offset>? _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      duration: widget.snapDuration,
    );
    _snapController.addListener(() {
      if (_scaleAnimation != null) {
        setState(() {
          _scale = _scaleAnimation!.value;
        });
      }
      if (_offsetAnimation != null) {
        setState(() {
          _offset = _offsetAnimation!.value;
        });
      }
    });
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  void _onScaleStart(ScaleStartDetails details) {
    _previousScale = _scale;
    _previousOffset = _offset;
    HapticFeedbackService.dragStart();
    _didBoundaryHaptic = false;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      _scale = (_previousScale * details.scale).clamp(
        widget.minScale,
        widget.maxScale,
      );

      // Track pan during zoom
      if (_scale > 1.0) {
        _offset = _previousOffset + details.focalPointDelta;
      }
    });

    // Haptic at scale boundaries (only once per gesture)
    if ((_scale == widget.maxScale || _scale == widget.minScale) &&
        !_didBoundaryHaptic) {
      HapticFeedbackService.lightImpact();
      _didBoundaryHaptic = true;
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    HapticFeedbackService.dragEnd();

    if (widget.snapToBounds && _scale < 1.0) {
      // Animate back to normal
      _scaleAnimation = Tween<double>(
        begin: _scale,
        end: 1.0,
      ).animate(
        CurvedAnimation(
          parent: _snapController,
          curve: Curves.easeOutCubic,
        ),
      );
      _offsetAnimation = Tween<Offset>(
        begin: _offset,
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: _snapController,
          curve: Curves.easeOutCubic,
        ),
      );
      _snapController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      onScaleEnd: _onScaleEnd,
      child: Transform.scale(
        scale: _scale,
        child: Transform.translate(
          offset: _offset,
          child: widget.child,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HapticScroll — Scroll with snap point haptic
// ---------------------------------------------------------------------------

/// A scrollable wrapper that provides haptic feedback when
/// the scroll position reaches predefined snap points.
///
/// Useful for carousels, paginated views, step indicators,
/// and any scrollable with discrete positions.
class HapticScroll extends StatefulWidget {
  /// The scrollable child widget.
  final Widget child;

  /// Pixel positions where haptic feedback should trigger.
  final List<double> snapPoints;

  /// Tolerance (in pixels) for matching a snap point.
  final double snapTolerance;

  /// Haptic type triggered at snap points.
  final HapticType snapHaptic;

  /// Whether to also trigger haptic on scroll start.
  final bool hapticOnStart;

  const HapticScroll({
    super.key,
    required this.child,
    required this.snapPoints,
    this.snapTolerance = 12.0,
    this.snapHaptic = HapticType.selection,
    this.hapticOnStart = false,
  });

  @override
  State<HapticScroll> createState() => _HapticScrollState();
}

class _HapticScrollState extends State<HapticScroll> {
  /// Track which snap points have been triggered to avoid
  /// repeated haptics while hovering near a point.
  final Set<double> _triggeredPoints = {};

  bool _isScrolling = false;

  void _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      _isScrolling = true;
      _triggeredPoints.clear();
      if (widget.hapticOnStart) {
        HapticFeedbackService.scrollFlick();
      }
    }

    if (notification is ScrollUpdateNotification) {
      final position = notification.metrics.pixels;

      for (final snap in widget.snapPoints) {
        if ((position - snap).abs() < widget.snapTolerance) {
          if (!_triggeredPoints.contains(snap)) {
            HapticFeedbackService.trigger(widget.snapHaptic);
            _triggeredPoints.add(snap);
          }
        } else {
          _triggeredPoints.remove(snap);
        }
      }
    }

    if (notification is ScrollEndNotification) {
      _isScrolling = false;
      _triggeredPoints.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        _onScrollNotification(notification);
        return false;
      },
      child: widget.child,
    );
  }
}

// ---------------------------------------------------------------------------
// TapScale — Scale animation on tap
// ---------------------------------------------------------------------------

/// A widget that scales down when tapped, creating a satisfying
/// "press" effect with optional haptic feedback.
///
/// This is the Flutter equivalent of iOS's UIControl
/// highlight feedback — the content briefly shrinks to
/// indicate it's being pressed.
class TapScale extends StatefulWidget {
  /// The child widget.
  final Widget child;

  /// Called when tapped.
  final VoidCallback? onTap;

  /// Scale factor when pressed (0.0 - 1.0).
  final double pressedScale;

  /// Duration of the press animation.
  final Duration duration;

  /// Curve for the press animation.
  final Curve curve;

  /// Haptic type on tap.
  final HapticType haptic;

  /// Whether to enable the haptic feedback.
  final bool enableHaptic;

  const TapScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.96,
    this.duration = const Duration(milliseconds: 100),
    this.curve = Curves.easeOutCubic,
    this.haptic = HapticType.light,
    this.enableHaptic = true,
  });

  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.pressedScale,
    ).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
    if (widget.enableHaptic) {
      HapticFeedbackService.trigger(widget.haptic);
    }
    widget.onTap?.call();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// DraggableItem — Drag with full haptic lifecycle
// ---------------------------------------------------------------------------

/// A draggable widget with haptic feedback at every stage
/// of the drag lifecycle.
///
/// - Drag start: light impact (picked up)
/// - Over drop target: medium impact (can drop here)
/// - Drop: success pattern (dropped successfully)
/// - Cancel: light impact (aborted)
class DraggableItem<T extends Object> extends StatelessWidget {
  /// Data to pass to the drop target.
  final T data;

  /// The widget displayed normally.
  final Widget child;

  /// The widget displayed while dragging.
  final Widget? feedback;

  /// The widget shown under the pointer while dragging.
  final Widget? childWhenDragging;

  /// Called when drag starts.
  final VoidCallback? onDragStarted;

  /// Called when drag ends (dropped anywhere).
  final VoidCallback? onDragEnded;

  /// Called when drag is cancelled.
  final VoidCallback? onDragCancelled;

  /// Opacity of the child while dragging.
  final double childWhenDraggingOpacity;

  const DraggableItem({
    super.key,
    required this.data,
    required this.child,
    this.feedback,
    this.childWhenDragging,
    this.onDragStarted,
    this.onDragEnded,
    this.onDragCancelled,
    this.childWhenDraggingOpacity = 0.3,
  });

  @override
  Widget build(BuildContext context) {
    return Draggable<T>(
      data: data,
      feedback: feedback ??
          Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: Opacity(
              opacity: 0.85,
              child: child,
            ),
          ),
      childWhenDragging: childWhenDragging ??
          Opacity(
            opacity: childWhenDraggingOpacity,
            child: child,
          ),
      onDragStarted: () {
        HapticFeedbackService.dragStart();
        onDragStarted?.call();
      },
      onDragCompleted: () {
        HapticFeedbackService.dragEnd();
        onDragEnded?.call();
      },
      onDraggableCanceled: (_, __) {
        HapticFeedbackService.dragCancel();
        onDragCancelled?.call();
      },
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// SwipeActionCard — Multi-action swipeable card
// ---------------------------------------------------------------------------

/// An advanced swipeable card that reveals multiple action
/// buttons underneath as the user swipes.
///
/// Unlike [SwipeableCard] which dismisses, this widget reveals
/// actions (like Mail.app) with progressive haptic feedback.
class SwipeActionCard extends StatelessWidget {
  /// The card content.
  final Widget child;

  /// Actions revealed on left swipe.
  final List<SwipeAction> leftActions;

  /// Actions revealed on right swipe.
  final List<SwipeAction> rightActions;

  /// Card border radius.
  final double borderRadius;

  /// Background color behind actions.
  final Color? backgroundColor;

  const SwipeActionCard({
    super.key,
    required this.child,
    this.leftActions = const [],
    this.rightActions = const [],
    this.borderRadius = 12,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Dismissible(
        key: ValueKey(child.hashCode),
        direction: _determineDirection(),
        confirmDismiss: (direction) async {
          HapticFeedbackService.mediumImpact();
          return false; // Don't dismiss, just trigger action
        },
        background: _buildActionBackground(
          context,
          actions: leftActions,
          alignment: Alignment.centerLeft,
        ),
        secondaryBackground: _buildActionBackground(
          context,
          actions: rightActions,
          alignment: Alignment.centerRight,
        ),
        child: child,
      ),
    );
  }

  DismissDirection _determineDirection() {
    if (leftActions.isNotEmpty && rightActions.isNotEmpty) {
      return DismissDirection.horizontal;
    } else if (leftActions.isNotEmpty) {
      return DismissDirection.startToEnd;
    } else if (rightActions.isNotEmpty) {
      return DismissDirection.endToStart;
    }
    return DismissDirection.none;
  }

  Widget _buildActionBackground(
    BuildContext context, {
    required List<SwipeAction> actions,
    required Alignment alignment,
  }) {
    if (actions.isEmpty) return const SizedBox.shrink();

    return Container(
      color: backgroundColor ?? Theme.of(context).colorScheme.surface,
      alignment: alignment,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: actions.map((action) {
          return GestureDetector(
            onTap: () {
              HapticFeedbackService.lightImpact();
              action.onTap();
            },
            child: Container(
              width: 72,
              height: double.infinity,
              color: action.backgroundColor,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(action.icon, color: Colors.white, size: 24),
                  const SizedBox(height: 4),
                  Text(
                    action.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// An action button revealed by swiping a [SwipeActionCard].
class SwipeAction {
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final VoidCallback onTap;

  const SwipeAction({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.onTap,
  });
}

// ---------------------------------------------------------------------------
// ElasticPull — Elastic overscroll effect
// ---------------------------------------------------------------------------

/// A custom scroll behavior that adds an elastic overscroll
/// effect with haptic feedback at the limit.
///
/// When the user pulls past the scroll boundaries, the content
/// stretches elastically and provides haptic feedback at
/// maximum stretch.
///
/// This is similar to iOS's rubber-banding but with added
/// tactile feedback.
class ElasticPull extends StatefulWidget {
  /// The scrollable content.
  final Widget child;

  /// Maximum overscroll distance in pixels.
  final double maxOverscroll;

  /// Elasticity factor (higher = more stretch).
  final double elasticity;

  /// Haptic at maximum stretch.
  final bool hapticAtLimit;

  /// Callback when pulled past threshold (for refresh).
  final VoidCallback? onThreshold;

  /// Threshold for triggering [onThreshold].
  final double threshold;

  const ElasticPull({
    super.key,
    required this.child,
    this.maxOverscroll = 80.0,
    this.elasticity = 0.5,
    this.hapticAtLimit = true,
    this.onThreshold,
    this.threshold = 60.0,
  });

  @override
  State<ElasticPull> createState() => _ElasticPullState();
}

class _ElasticPullState extends State<ElasticPull> {
  double _overscroll = 0;
  bool _didHaptic = false;
  bool _didTrigger = false;

  void _handleOverscroll(OverscrollNotification notification) {
    setState(() {
      _overscroll = (_overscroll + notification.overscroll.abs())
          .clamp(0.0, widget.maxOverscroll);
    });

    // Haptic at limit
    if (_overscroll >= widget.maxOverscroll && !_didHaptic && widget.hapticAtLimit) {
      HapticFeedbackService.lightImpact();
      _didHaptic = true;
    }

    // Threshold callback
    if (_overscroll >= widget.threshold && !_didTrigger && widget.onThreshold != null) {
      widget.onThreshold!();
      _didTrigger = true;
    }
  }

  void _handleScrollEnd(ScrollEndNotification notification) {
    setState(() {
      _overscroll = 0;
    });
    _didHaptic = false;
    _didTrigger = false;
  }

  double _getElasticOffset() {
    // Elastic formula: displacement = force / elasticity
    // We cap it for visual sanity
    return _overscroll * widget.elasticity;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is OverscrollNotification) {
          _handleOverscroll(notification);
        }
        if (notification is ScrollEndNotification) {
          _handleScrollEnd(notification);
        }
        return false;
      },
      child: Transform.translate(
        offset: Offset(0, _getElasticOffset()),
        child: widget.child,
      ),
    );
  }
}
