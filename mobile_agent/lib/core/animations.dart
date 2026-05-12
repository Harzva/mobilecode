// ============================================================
// animations.dart — MobileCode Shared Animation Library
// ============================================================
// Reusable animation widgets, transitions, and effects used
// across all screens and themes. All transitions respect the
// active theme's animation personality (duration, curve).
// ============================================================

import 'dart:math' show pi, sin, cos;
import 'package:flutter/material.dart';
import 'theme_manager.dart';

// ============================================================
// SECTION 1: Animation Constants
// ============================================================

/// Global animation durations that individual themes can override
/// via [MobileTheme.transitionDuration] and [MobileTheme.microAnimationDuration].
class AnimationDurations {
  static const Duration instant = Duration(milliseconds: 50);
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);
  static const Duration pageTransition = Duration(milliseconds: 400);
  static const Duration staggerBase = Duration(milliseconds: 50);
  static const Duration shimmerCycle = Duration(milliseconds: 1800);
  static const Duration pulseCycle = Duration(milliseconds: 1200);
  static const Duration blinkCycle = Duration(milliseconds: 800);
}

/// Curves used across the app. Themes can inject their own personality.
class AnimationCurves {
  static const Curve pageEnter = Curves.easeOutCubic;
  static const Curve pageExit = Curves.easeInCubic;
  static const Curve elementEnter = Curves.easeOutQuart;
  static const Curve elementBounce = Curves.elasticOut;
  static const Curve smoothDecelerate = Curves.decelerate;
  static const Curve spring = Curves.fastOutSlowIn;
}

// ============================================================
// SECTION 2: Page Transitions
// ============================================================

/// Slide transition — enters from right, exits to left.
class SlidePageRoute<T> extends PageRouteBuilder<T> {
  final Widget child;
  final Duration duration;
  final Curve curve;

  SlidePageRoute({
    required this.child,
    this.duration = AnimationDurations.pageTransition,
    this.curve = AnimationCurves.pageEnter,
    RouteSettings? settings,
  }) : super(
          settings: settings,
          transitionDuration: duration,
          reverseTransitionDuration: duration,
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: curve,
              reverseCurve: AnimationCurves.pageExit.flipped,
            );
            final slideAnim = Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(curved);
            final fadeAnim = Tween<double>(
              begin: 0.0,
              end: 1.0,
            ).animate(curved);
            return FadeTransition(
              opacity: fadeAnim,
              child: SlideTransition(
                position: slideAnim,
                child: child,
              ),
            );
          },
        );
}

/// Fade transition — cross-fade between pages.
class FadePageRoute<T> extends PageRouteBuilder<T> {
  final Widget child;
  final Duration duration;

  FadePageRoute({
    required this.child,
    this.duration = AnimationDurations.pageTransition,
    RouteSettings? settings,
  }) : super(
          settings: settings,
          transitionDuration: duration,
          reverseTransitionDuration: duration,
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final fadeAnim = Tween<double>(
              begin: 0.0,
              end: 1.0,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: AnimationCurves.pageEnter,
            ));
            return FadeTransition(opacity: fadeAnim, child: child);
          },
        );

  /// Cross-fade that also slides vertically.
  FadePageRoute.vertical({
    required this.child,
    this.duration = AnimationDurations.pageTransition,
    RouteSettings? settings,
  }) : super(
          settings: settings,
          transitionDuration: duration,
          reverseTransitionDuration: duration,
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: AnimationCurves.pageEnter),
            );
            final slideAnim = Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: AnimationCurves.pageEnter));
            return FadeTransition(
              opacity: fadeAnim,
              child: SlideTransition(position: slideAnim, child: child),
            );
          },
        );
}

/// Scale transition — page scales up from center with fade.
class ScalePageRoute<T> extends PageRouteBuilder<T> {
  final Widget child;
  final Duration duration;
  final Alignment alignment;

  ScalePageRoute({
    required this.child,
    this.duration = AnimationDurations.pageTransition,
    this.alignment = Alignment.center,
    RouteSettings? settings,
  }) : super(
          settings: settings,
          transitionDuration: duration,
          reverseTransitionDuration: duration,
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final scaleAnim = Tween<double>(begin: 0.92, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: AnimationCurves.elementBounce),
            );
            final fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: AnimationCurves.pageEnter),
            );
            return FadeTransition(
              opacity: fadeAnim,
              child: ScaleTransition(
                alignment: alignment,
                scale: scaleAnim,
                child: child,
              ),
            );
          },
        );
}

/// Shared axis transition (Material design Z-axis transition).
class SharedAxisPageRoute<T> extends PageRouteBuilder<T> {
  final Widget child;
  final SharedAxisTransitionType type;
  final Duration duration;

  SharedAxisPageRoute({
    required this.child,
    this.type = SharedAxisTransitionType.scaled,
    this.duration = AnimationDurations.pageTransition,
    RouteSettings? settings,
  }) : super(
          settings: settings,
          transitionDuration: duration,
          reverseTransitionDuration: duration,
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SharedAxisTransition(
              animation: animation,
              secondaryAnimation: secondaryAnimation,
              transitionType: type,
              child: child,
            );
          },
        );
}

/// Built-in SharedAxisTransition types
enum SharedAxisTransitionType { scaled, horizontal, vertical }

/// SharedAxisTransition widget implementation
class SharedAxisTransition extends StatelessWidget {
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final SharedAxisTransitionType transitionType;
  final Widget child;

  const SharedAxisTransition({
    Key? key,
    required this.animation,
    required this.secondaryAnimation,
    required this.transitionType,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enterAnim = CurvedAnimation(
      parent: animation,
      curve: AnimationCurves.pageEnter,
    );
    final exitAnim = CurvedAnimation(
      parent: secondaryAnimation,
      curve: AnimationCurves.pageExit,
    );

    Widget result = child;

    if (transitionType == SharedAxisTransitionType.scaled) {
      final scaleEnter = Tween<double>(begin: 0.88, end: 1.0).animate(enterAnim);
      final scaleExit = Tween<double>(begin: 1.0, end: 0.88).animate(exitAnim);
      final fadeEnter = Tween<double>(begin: 0.0, end: 1.0).animate(enterAnim);
      final fadeExit = Tween<double>(begin: 1.0, end: 0.0).animate(exitAnim);

      result = FadeTransition(
        opacity: fadeEnter,
        child: ScaleTransition(
          scale: scaleEnter,
          child: FadeTransition(
            opacity: fadeExit,
            child: ScaleTransition(scale: scaleExit, child: child),
          ),
        ),
      );
    } else {
      final isHorizontal = transitionType == SharedAxisTransitionType.horizontal;
      final slideEnter = Tween<Offset>(
        begin: isHorizontal ? const Offset(0.3, 0) : const Offset(0, 0.3),
        end: Offset.zero,
      ).animate(enterAnim);
      final slideExit = Tween<Offset>(
        begin: Offset.zero,
        end: isHorizontal ? const Offset(-0.3, 0) : const Offset(0, -0.3),
      ).animate(exitAnim);
      final fadeEnter = Tween<double>(begin: 0.0, end: 1.0).animate(enterAnim);
      final fadeExit = Tween<double>(begin: 1.0, end: 0.0).animate(exitAnim);

      result = FadeTransition(
        opacity: fadeEnter,
        child: SlideTransition(
          position: slideEnter,
          child: FadeTransition(
            opacity: fadeExit,
            child: SlideTransition(position: slideExit, child: child),
          ),
        ),
      );
    }

    return result;
  }
}

// ============================================================
// SECTION 3: Card Hover Effects
// ============================================================

/// A card that responds to hover/tap with elevation, scale, and
/// subtle glow effects. Adapted to the active theme's primary color.
class HoverCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? glowColor;
  final double hoverScale;
  final double borderRadius;
  final EdgeInsets padding;
  final EdgeInsets margin;

  const HoverCard({
    Key? key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.glowColor,
    this.hoverScale = 1.02,
    this.borderRadius = 16,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.all(0),
  }) : super(key: key);

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _elevationAnim;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AnimationDurations.fast,
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: widget.hoverScale).animate(
      CurvedAnimation(parent: _controller, curve: AnimationCurves.elementEnter),
    );
    _elevationAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: AnimationCurves.elementEnter),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onEnter(PointerEvent event) {
    if (!mounted) return;
    setState(() => _isHovered = true);
    _controller.forward();
  }

  void _onExit(PointerEvent event) {
    if (!mounted) return;
    setState(() => _isHovered = false);
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = widget.glowColor ?? theme.colorScheme.primary;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnim.value,
          child: Container(
            margin: widget.margin,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(
                color: _isHovered
                    ? primaryColor.withOpacity(0.4)
                    : theme.colorScheme.outline.withOpacity(0.3),
                width: _isHovered ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: _isHovered
                      ? primaryColor.withOpacity(0.15)
                      : Colors.black.withOpacity(0.1),
                  blurRadius: _isHovered ? 20 : 8,
                  offset: _isHovered ? const Offset(0, 6) : const Offset(0, 2),
                  spreadRadius: _isHovered ? 2 : 0,
                ),
                if (_isHovered)
                  BoxShadow(
                    color: primaryColor.withOpacity(0.05),
                    blurRadius: 40,
                    offset: Offset.zero,
                  ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onTap,
                  onLongPress: widget.onLongPress,
                  onHover: (hovering) {
                    if (hovering) {
                      _controller.forward();
                    } else {
                      _controller.reverse();
                    }
                  },
                  splashColor: primaryColor.withOpacity(0.1),
                  highlightColor: primaryColor.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  child: Padding(
                    padding: widget.padding,
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================
// SECTION 4: Button Ripple Effects
// ============================================================

/// An elevated button with a themed ripple burst animation on tap.
class RippleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final EdgeInsets padding;
  final double borderRadius;
  final double? height;
  final double? width;

  const RippleButton({
    Key? key,
    required this.child,
    this.onTap,
    this.backgroundColor,
    this.foregroundColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    this.borderRadius = 12,
    this.height,
    this.width,
  }) : super(key: key);

  @override
  State<RippleButton> createState() => _RippleButtonState();
}

class _RippleButtonState extends State<RippleButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _rippleController;
  late Animation<double> _rippleAnim;
  Offset? _tapPosition;

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      vsync: this,
      duration: AnimationDurations.slow,
    );
    _rippleAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _rippleController, curve: Curves.easeOut),
    );
    _rippleController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _rippleController.reset();
      }
    });
  }

  @override
  void dispose() {
    _rippleController.dispose();
    super.dispose();
  }

  void _handleTap(TapDownDetails details) {
    _tapPosition = details.localPosition;
    _rippleController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = widget.backgroundColor ?? theme.colorScheme.primary;
    final fg = widget.foregroundColor ?? theme.colorScheme.onPrimary;

    return GestureDetector(
      onTapDown: _handleTap,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _rippleController,
        builder: (context, child) {
          return Container(
            width: widget.width,
            height: widget.height,
            padding: widget.padding,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              boxShadow: [
                BoxShadow(
                  color: bg.withOpacity(0.3 + _rippleAnim.value * 0.2),
                  blurRadius: 12 + _rippleAnim.value * 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Ripple burst
                  if (_tapPosition != null)
                    Positioned(
                      left: _tapPosition!.dx - 50,
                      top: _tapPosition!.dy - 50,
                      child: Opacity(
                        opacity: 1.0 - _rippleAnim.value,
                        child: Transform.scale(
                          scale: _rippleAnim.value * 3,
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.3),
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Button content
                  DefaultTextStyle(
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    child: widget.child,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ============================================================
// SECTION 5: List Item Entrance Animations
// ============================================================

/// Animates a list of children with staggered slide+fade entrance.
class StaggeredListView extends StatelessWidget {
  final List<Widget> children;
  final Duration duration;
  final Duration staggerDelay;
  final Axis scrollDirection;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final EdgeInsets? padding;

  const StaggeredListView({
    Key? key,
    required this.children,
    this.duration = AnimationDurations.normal,
    this.staggerDelay = AnimationDurations.staggerBase,
    this.scrollDirection = Axis.vertical,
    this.shrinkWrap = true,
    this.physics,
    this.padding,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView(
      scrollDirection: scrollDirection,
      shrinkWrap: shrinkWrap,
      physics: physics ?? const BouncingScrollPhysics(),
      padding: padding,
      children: List.generate(children.length, (index) {
        return StaggeredItem(
          index: index,
          delay: Duration(milliseconds: staggerDelay.inMilliseconds * index),
          duration: duration,
          child: children[index],
        );
      }),
    );
  }
}

/// Individual list item that slides and fades in with optional slide direction.
class StaggeredItem extends StatefulWidget {
  final int index;
  final Duration delay;
  final Duration duration;
  final Widget child;
  final Offset slideBegin;

  const StaggeredItem({
    Key? key,
    required this.index,
    required this.delay,
    required this.duration,
    required this.child,
    this.slideBegin = const Offset(0, 0.3),
  }) : super(key: key);

  @override
  State<StaggeredItem> createState() => _StaggeredItemState();
}

class _StaggeredItemState extends State<StaggeredItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: AnimationCurves.elementEnter,
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(curve);
    _slideAnim = Tween<Offset>(
      begin: widget.slideBegin,
      end: Offset.zero,
    ).animate(curve);
    _scaleAnim = Tween<double>(begin: 0.96, end: 1.0).animate(curve);

    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
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
        return FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: Transform.scale(
              scale: _scaleAnim.value,
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}

/// Sliver variant for use inside CustomScrollView.
class SliverStaggeredList extends StatelessWidget {
  final List<Widget> children;
  final Duration duration;
  final Duration staggerDelay;

  const SliverStaggeredList({
    Key? key,
    required this.children,
    this.duration = AnimationDurations.normal,
    this.staggerDelay = AnimationDurations.staggerBase,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          return StaggeredItem(
            index: index,
            delay: Duration(milliseconds: staggerDelay.inMilliseconds * index),
            duration: duration,
            child: children[index],
          );
        },
        childCount: children.length,
      ),
    );
  }
}

// ============================================================
// SECTION 6: Shimmer Loading Effect
// ============================================================

/// Shimmer loading placeholder that sweeps a gradient across
/// its child area. Adapts to theme surface colors.
class ShimmerLoading extends StatefulWidget {
  final double? width;
  final double? height;
  final double borderRadius;
  final Widget? child;
  final Color? baseColor;
  final Color? highlightColor;

  const ShimmerLoading({
    Key? key,
    this.width,
    this.height,
    this.borderRadius = 8,
    this.child,
    this.baseColor,
    this.highlightColor,
  }) : super(key: key);

  /// Factory for a shimmer card placeholder.
  factory ShimmerLoading.card({
    double width = double.infinity,
    double height = 120,
    double borderRadius = 16,
    Color? baseColor,
    Color? highlightColor,
  }) {
    return ShimmerLoading(
      width: width,
      height: height,
      borderRadius: borderRadius,
      baseColor: baseColor,
      highlightColor: highlightColor,
    );
  }

  /// Factory for a shimmer text line.
  factory ShimmerLoading.line({
    double width = double.infinity,
    double height = 14,
    double borderRadius = 7,
    Color? baseColor,
    Color? highlightColor,
  }) {
    return ShimmerLoading(
      width: width,
      height: height,
      borderRadius: borderRadius,
      baseColor: baseColor,
      highlightColor: highlightColor,
    );
  }

  /// Factory for a shimmer circle (avatar placeholder).
  factory ShimmerLoading.circle({
    double size = 48,
    Color? baseColor,
    Color? highlightColor,
  }) {
    return ShimmerLoading(
      width: size,
      height: size,
      borderRadius: size / 2,
      baseColor: baseColor,
      highlightColor: highlightColor,
    );
  }

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController.unbounded(vsync: this);
    _shimmerController.repeat(
      min: -1.5,
      max: 1.5,
      period: AnimationDurations.shimmerCycle,
    );
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = widget.baseColor ??
        theme.colorScheme.surfaceContainerHighest.withOpacity(0.5);
    final highlight = widget.highlightColor ??
        theme.colorScheme.surfaceContainerHighest.withOpacity(0.8);

    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: [base, highlight, base],
              stops: const [0.1, 0.5, 0.9],
              begin: const Alignment(-1.0, -0.3),
              end: const Alignment(1.0, 0.3),
              transform: _SlidingGradientTransform(
                slidePercent: _shimmerController.value,
              ),
            ).createShader(bounds);
          },
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(widget.borderRadius),
            ),
            child: widget.child,
          ),
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;

  const _SlidingGradientTransform({required this.slidePercent});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(
      bounds.width * slidePercent,
      0.0,
      0.0,
    );
  }
}

// ============================================================
// SECTION 7: Pulse Animation
// ============================================================

/// A smoothly pulsing widget — ideal for status indicators,
/// recording dots, and "live" badges. Uses a sine wave for
/// organic-feeling pulsing.
class PulseAnimation extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double minScale;
  final double maxScale;
  final double minOpacity;
  final double maxOpacity;

  const PulseAnimation({
    Key? key,
    required this.child,
    this.duration = AnimationDurations.pulseCycle,
    this.minScale = 0.9,
    this.maxScale = 1.1,
    this.minOpacity = 0.6,
    this.maxOpacity = 1.0,
  }) : super(key: key);

  @override
  State<PulseAnimation> createState() => _PulseAnimationState();
}

class _PulseAnimationState extends State<PulseAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final sineValue = sin(_pulseController.value * 2 * pi);
        final scale = lerpDouble(
          widget.minScale,
          widget.maxScale,
          (sineValue + 1) / 2,
        );
        final opacity = lerpDouble(
          widget.minOpacity,
          widget.maxOpacity,
          (sineValue + 1) / 2,
        );
        return Transform.scale(
          scale: scale ?? 1.0,
          child: Opacity(
            opacity: opacity ?? 1.0,
            child: widget.child,
          ),
        );
      },
    );
  }
}

/// A compact pulsing dot used as a status indicator.
class PulseDot extends StatelessWidget {
  final Color color;
  final double size;
  final Duration duration;

  const PulseDot({
    Key? key,
    required this.color,
    this.size = 8,
    this.duration = AnimationDurations.pulseCycle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return PulseAnimation(
      duration: duration,
      minScale: 0.85,
      maxScale: 1.15,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.5),
              blurRadius: size,
              spreadRadius: size * 0.5,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SECTION 8: Typing Cursor Blink Animation
// ============================================================

/// A blinking cursor used in editors and terminals.
/// Mimics a hardware cursor with configurable width, color, and blink rate.
class BlinkingCursor extends StatefulWidget {
  final Color cursorColor;
  final double width;
  final double height;
  final Duration blinkDuration;

  const BlinkingCursor({
    Key? key,
    required this.cursorColor,
    this.width = 2.5,
    this.height = 20,
    this.blinkDuration = AnimationDurations.blinkCycle,
  }) : super(key: key);

  /// Block cursor variant (fills a rectangle).
  const BlinkingCursor.block({
    Key? key,
    required this.cursorColor,
    this.width = 10,
    this.height = 20,
    this.blinkDuration = AnimationDurations.blinkCycle,
  }) : super(key: key);

  @override
  State<BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _blinkController;
  late Animation<double> _opacityAnim;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: widget.blinkDuration,
    );
    _opacityAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.0)
            .chain(CurveTween(curve: const Interval(0.0, 0.5))),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 0.0)
            .chain(CurveTween(curve: const Interval(0.0, 1.0))),
        weight: 25,
      ),
    ]).animate(_blinkController);
    _blinkController.repeat();
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _blinkController,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnim.value,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: widget.cursorColor,
              borderRadius: BorderRadius.circular(widget.width <= 3 ? 1 : 2),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================
// SECTION 9: Fade Through Animation (theme transition)
// ============================================================

/// Wraps a child and fades it out/in when the theme changes,
/// creating a smooth visual transition between color palettes.
class ThemeFadeTransition extends StatefulWidget {
  final Widget child;
  final MobileTheme theme;

  const ThemeFadeTransition({
    Key? key,
    required this.child,
    required this.theme,
  }) : super(key: key);

  @override
  State<ThemeFadeTransition> createState() => _ThemeFadeTransitionState();
}

class _ThemeFadeTransitionState extends State<ThemeFadeTransition>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.theme.transitionDuration,
    );
    _fadeAnim = CurvedAnimation(
      parent: _controller,
      curve: widget.theme.transitionCurve,
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(ThemeFadeTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.theme.id != widget.theme.id) {
      _controller
          .reverse()
          .then((_) {
            if (mounted) _controller.forward();
          });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: widget.child,
    );
  }
}

// ============================================================
// SECTION 10: Bouncy Scale Animation
// ============================================================

/// A widget that bounces into view when first rendered or when
/// its `trigger` key changes.
class BounceInAnimation extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;
  final double beginScale;

  const BounceInAnimation({
    Key? key,
    required this.child,
    this.duration = AnimationDurations.normal,
    this.delay = Duration.zero,
    this.beginScale = 0.5,
  }) : super(key: key);

  @override
  State<BounceInAnimation> createState() => _BounceInAnimationState();
}

class _BounceInAnimationState extends State<BounceInAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _scaleAnim = Tween<double>(
      begin: widget.beginScale,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: AnimationCurves.elementBounce,
    ));
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    ));
    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
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
        return FadeTransition(
          opacity: _fadeAnim,
          child: Transform.scale(
            scale: _scaleAnim.value,
            child: widget.child,
          ),
        );
      },
    );
  }
}

// ============================================================
// SECTION 11: Rotation Animation
// ============================================================

/// Continuously rotates a child widget. Useful for loading spinners,
/// sync indicators, and gear/settings icons.
class RotationAnimation extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final bool reverse;

  const RotationAnimation({
    Key? key,
    required this.child,
    this.duration = const Duration(seconds: 2),
    this.reverse = false,
  }) : super(key: key);

  @override
  State<RotationAnimation> createState() => _RotationAnimationState();
}

class _RotationAnimationState extends State<RotationAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotateController;

  @override
  void initState() {
    super.initState();
    _rotateController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    if (widget.reverse) {
      _rotateController.repeat(reverse: true);
    } else {
      _rotateController.repeat();
    }
  }

  @override
  void dispose() {
    _rotateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _rotateController,
      child: widget.child,
    );
  }
}

// ============================================================
// SECTION 12: Slide In From Direction
// ============================================================

/// Slides a child in from a specified direction.
class SlideInAnimation extends StatefulWidget {
  final Widget child;
  final AxisDirection direction;
  final Duration duration;
  final Duration delay;
  final Curve curve;

  const SlideInAnimation({
    Key? key,
    required this.child,
    this.direction = AxisDirection.up,
    this.duration = AnimationDurations.normal,
    this.delay = Duration.zero,
    this.curve = AnimationCurves.elementEnter,
  }) : super(key: key);

  @override
  State<SlideInAnimation> createState() => _SlideInAnimationState();
}

class _SlideInAnimationState extends State<SlideInAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    late Offset beginOffset;
    switch (widget.direction) {
      case AxisDirection.up:
        beginOffset = const Offset(0, 0.5);
        break;
      case AxisDirection.down:
        beginOffset = const Offset(0, -0.5);
        break;
      case AxisDirection.left:
        beginOffset = const Offset(0.5, 0);
        break;
      case AxisDirection.right:
        beginOffset = const Offset(-0.5, 0);
        break;
    }
    _slideAnim = Tween<Offset>(
      begin: beginOffset,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: widget.curve));
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0, 0.6, curve: Curves.easeOut)),
    );
    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: widget.child,
      ),
    );
  }
}
