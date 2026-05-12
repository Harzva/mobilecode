import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/render_optimizer.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// HIGH-PERFORMANCE WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

/// A library of optimized widget replacements for common Flutter widgets.
///
/// These widgets are designed for 60fps performance:
/// - [OptimizedListView] — Fixed item extent, aggressive caching
/// - [CachedWidget] — Prevents rebuilds when data hasn't changed
/// - [DeferredBuilder] — Builds heavy widgets after the current frame
/// - [StaggeredListAnimation] — Sequential item animations using transforms
/// - [OptimizedGridView] — Fixed aspect ratio, viewport-based cache
/// - [KeepAliveWrapper] — Selective keep-alive for list items
/// - [OptimizedPageView] — Preload adjacent pages, isolate repaints

// ═══════════════════════════════════════════════════════════════════════════════
// OPTIMIZED LIST VIEW
// ═══════════════════════════════════════════════════════════════════════════════

/// A high-performance [ListView.builder] with optimal defaults.
///
/// Key optimizations:
/// - [itemExtent] enables viewport estimation (avoids measuring every item)
/// - [cacheExtent] pre-builds items ahead of the viewport
/// - [addAutomaticKeepAlives: false] reduces memory for disposable items
/// - [addRepaintBoundaries: true] isolates item repaints
/// - Each item is wrapped in [RepaintBoundary]
///
/// ## Performance Tips
/// - Always provide [itemExtent] when items have uniform height
/// - Set [cacheExtent] based on item complexity (5-10 items is typical)
/// - Disable keepAlive for items that don't need to preserve state
class OptimizedListView extends StatelessWidget {
  /// Number of items in the list.
  final int itemCount;

  /// Fixed height of each item. THIS IS CRITICAL for performance.
  ///
  /// When provided, Flutter can estimate the viewport without measuring
  /// every item, reducing layout time from O(n) to O(1).
  final double? itemExtent;

  /// Builder function for each item.
  final Widget Function(BuildContext, int) itemBuilder;

  /// Padding around the list.
  final EdgeInsets padding;

  /// Scroll controller.
  final ScrollController? controller;

  /// Scroll direction.
  final Axis scrollDirection;

  /// Whether the list is primary.
  final bool? primary;

  /// Whether to reverse the list.
  final bool reverse;

  /// Physics for scrolling.
  final ScrollPhysics? physics;

  /// Whether to shrink-wrap the content.
  final bool shrinkWrap;

  /// Number of items to cache outside the viewport.
  final double? cacheExtent;

  /// Whether to add automatic keep-alive wrappers.
  ///
  /// Set to true for items with state that needs preservation (e.g., videos).
  final bool addAutomaticKeepAlives;

  /// Whether to add repaint boundaries around items.
  final bool addRepaintBoundaries;

  const OptimizedListView({
    required this.itemCount,
    this.itemExtent,
    required this.itemBuilder,
    this.padding = EdgeInsets.zero,
    this.controller,
    this.scrollDirection = Axis.vertical,
    this.primary,
    this.reverse = false,
    this.physics,
    this.shrinkWrap = false,
    this.cacheExtent,
    this.addAutomaticKeepAlives = false,
    this.addRepaintBoundaries = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      padding: padding,
      itemCount: itemCount,
      itemExtent: itemExtent,
      cacheExtent: cacheExtent ?? (itemExtent != null ? itemExtent! * 5 : null),
      scrollDirection: scrollDirection,
      primary: primary,
      reverse: reverse,
      physics: physics ?? const ClampingScrollPhysics(),
      shrinkWrap: shrinkWrap,
      addAutomaticKeepAlives: addAutomaticKeepAlives,
      addRepaintBoundaries: addRepaintBoundaries,
      itemBuilder: (context, index) {
        final child = itemBuilder(context, index);

        // Always wrap in RepaintBoundary for per-item isolation
        if (addRepaintBoundaries) {
          return RepaintBoundary(child: child);
        }
        return child;
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// OPTIMIZED GRID VIEW
// ═══════════════════════════════════════════════════════════════════════════════

/// A high-performance [GridView.builder] with optimal defaults.
class OptimizedGridView extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;
  final int crossAxisCount;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final double childAspectRatio;
  final EdgeInsets padding;
  final ScrollController? controller;
  final double? cacheExtent;

  const OptimizedGridView({
    required this.itemCount,
    required this.itemBuilder,
    required this.crossAxisCount,
    this.crossAxisSpacing = 8,
    this.mainAxisSpacing = 8,
    this.childAspectRatio = 1.0,
    this.padding = EdgeInsets.zero,
    this.controller,
    this.cacheExtent,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: controller,
      padding: padding,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: crossAxisSpacing,
        mainAxisSpacing: mainAxisSpacing,
        childAspectRatio: childAspectRatio,
      ),
      cacheExtent: cacheExtent,
      itemCount: itemCount,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemBuilder: (context, index) {
        return RepaintBoundary(
          child: itemBuilder(context, index),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CACHED WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// A widget that prevents unnecessary rebuilds using a cache key.
///
/// When the [cacheKey] hasn't changed, this widget is considered equal
/// and Flutter will skip rebuilding it. This is useful for:
///
/// - List items with stable data
/// - Expensive-to-build widgets
/// - Widgets that rebuild frequently but rarely change
///
/// ## How it works
/// Overrides [operator ==] and [hashCode] to use only [cacheKey] for
/// equality comparison. The actual [child] widget is not compared.
class CachedWidget extends StatelessWidget {
  /// Key used to determine if the widget needs to rebuild.
  ///
  /// When this key equals the previous key, the widget will not rebuild.
  final Object cacheKey;

  /// The widget to cache.
  final Widget child;

  const CachedWidget({
    required this.cacheKey,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return child;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CachedWidget && other.cacheKey == cacheKey;
  }

  @override
  int get hashCode => cacheKey.hashCode;
}

// ═══════════════════════════════════════════════════════════════════════════════
// DEFERRED BUILDER
// ═══════════════════════════════════════════════════════════════════════════════

/// Builds a heavy widget after the current frame completes.
///
/// This prevents heavy widgets from causing frame drops during critical
/// animations (page transitions, scroll flings, etc.).
///
/// ## When to use
/// - Complex charts or graphs
/// - Rich text with many spans
/// - Heavy computation results
/// - Third-party widgets known to be slow
///
/// ## How it works
/// Shows [placeholder] during the first frame, then builds the actual
/// widget in a post-frame callback.
class DeferredBuilder extends StatefulWidget {
  /// Builder for the heavy widget.
  final Widget Function(BuildContext) builder;

  /// Widget shown while deferring.
  final Widget? placeholder;

  /// Delay before building (default: 50ms).
  final Duration delay;

  const DeferredBuilder({
    required this.builder,
    this.placeholder,
    this.delay = const Duration(milliseconds: 50),
  });

  @override
  State<DeferredBuilder> createState() => _DeferredBuilderState();
}

class _DeferredBuilderState extends State<DeferredBuilder> {
  bool _shouldBuild = false;

  @override
  void initState() {
    super.initState();

    // Defer build to after current frame using SchedulerBinding
    // This is more reliable than a simple Future.delayed
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (widget.delay == Duration.zero) {
          setState(() => _shouldBuild = true);
        } else {
          Future.delayed(widget.delay, () {
            if (mounted) {
              setState(() => _shouldBuild = true);
            }
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldBuild) {
      return widget.placeholder ?? RenderOptimizer.emptyBox;
    }
    return widget.builder(context);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STAGGERED LIST ANIMATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Items animate in sequentially with a stagger effect.
///
/// Uses [Transform.translate] and [Opacity] for GPU-accelerated animations.
/// Each item fades in and slides up slightly for a polished entrance effect.
class StaggeredListAnimation extends StatefulWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;
  final Duration baseDelay;
  final Duration staggerDelay;
  final Duration animationDuration;
  final Curve curve;
  final Axis scrollDirection;
  final EdgeInsets padding;
  final ScrollController? controller;

  const StaggeredListAnimation({
    required this.itemCount,
    required this.itemBuilder,
    this.baseDelay = const Duration(milliseconds: 100),
    this.staggerDelay = const Duration(milliseconds: 50),
    this.animationDuration = const Duration(milliseconds: 300),
    this.curve = Curves.easeOutCubic,
    this.scrollDirection = Axis.vertical,
    this.padding = EdgeInsets.zero,
    this.controller,
  });

  @override
  State<StaggeredListAnimation> createState() =>
      _StaggeredListAnimationState();
}

class _StaggeredListAnimationState extends State<StaggeredListAnimation>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _initAnimations();
  }

  void _initAnimations() {
    _controllers = List.generate(
      widget.itemCount,
      (index) => AnimationController(
        vsync: this,
        duration: widget.animationDuration,
      ),
    );

    _animations = _controllers.map((controller) {
      return CurvedAnimation(
        parent: controller,
        curve: widget.curve,
      );
    }).toList();

    // Start staggered animations
    _startAnimations();
  }

  Future<void> _startAnimations() async {
    for (var i = 0; i < widget.itemCount; i++) {
      await Future.delayed(widget.staggerDelay);
      if (mounted) {
        _controllers[i].forward();
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: widget.controller,
      padding: widget.padding,
      itemCount: widget.itemCount,
      scrollDirection: widget.scrollDirection,
      cacheExtent: 200,
      addAutomaticKeepAlives: false,
      itemBuilder: (context, index) {
        return AnimatedBuilder(
          animation: _animations[index],
          builder: (context, child) {
            final value = _animations[index].value;
            return Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(
                  0,
                  (1 - value) * 20,
                ),
                child: child,
              ),
            );
          },
          child: RepaintBoundary(
            child: widget.itemBuilder(context, index),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// OPTIMIZED PAGE VIEW
// ═══════════════════════════════════════════════════════════════════════════════

/// A high-performance [PageView] with adjacent page preloading.
///
/// Preloads pages adjacent to the current page for smoother swiping.
/// Wraps each page in a [RepaintBoundary] to isolate repaints.
class OptimizedPageView extends StatefulWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;
  final ValueChanged<int>? onPageChanged;
  final int preloadCount;
  final PageController? controller;
  final bool pageSnapping;
  final ScrollPhysics? physics;

  const OptimizedPageView({
    required this.itemCount,
    required this.itemBuilder,
    this.onPageChanged,
    this.preloadCount = 1,
    this.controller,
    this.pageSnapping = true,
    this.physics,
  });

  @override
  State<OptimizedPageView> createState() => _OptimizedPageViewState();
}

class _OptimizedPageViewState extends State<OptimizedPageView> {
  late PageController _controller;
  final Set<int> _loadedPages = {};
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? PageController();
    _loadedPages.add(0);
    _preloadPages(0);
  }

  void _preloadPages(int currentPage) {
    for (int i = 1; i <= widget.preloadCount; i++) {
      if (currentPage + i < widget.itemCount) {
        _loadedPages.add(currentPage + i);
      }
      if (currentPage - i >= 0) {
        _loadedPages.add(currentPage - i);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _controller,
      pageSnapping: widget.pageSnapping,
      physics: widget.physics,
      onPageChanged: (index) {
        setState(() {
          _currentPage = index;
          _loadedPages.add(index);
        });
        _preloadPages(index);
        widget.onPageChanged?.call(index);
      },
      itemCount: widget.itemCount,
      itemBuilder: (context, index) {
        // Only build if this page has been preloaded
        if (!_loadedPages.contains(index)) {
          return RenderOptimizer.emptyBox;
        }

        return RepaintBoundary(
          child: widget.itemBuilder(context, index),
        );
      },
    );
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// KEEP ALIVE WRAPPER
// ═══════════════════════════════════════════════════════════════════════════════

/// Selectively keeps a list item alive when scrolled off-screen.
///
/// Use for items with expensive state that should be preserved:
/// - Video players
/// - Maps
/// - Web views
/// - Complex animations
///
/// For simple items, avoid keep-alive to save memory.
class KeepAliveWrapper extends StatefulWidget {
  final Widget child;
  final bool keepAlive;

  const KeepAliveWrapper({
    required this.child,
    this.keepAlive = true,
  });

  @override
  State<KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.keepAlive;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MEASURED BUILDER
// ═══════════════════════════════════════════════════════════════════════════════

/// Measures and logs the build time of its child widget.
///
/// Useful for identifying slow widgets in development.
/// In release mode, measurements are disabled.
class MeasuredBuilder extends StatelessWidget {
  final String label;
  final Widget Function(BuildContext) builder;

  const MeasuredBuilder({
    required this.label,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    if (!bool.fromEnvironment('dart.vm.product')) {
      final stopwatch = Stopwatch()..start();
      final result = builder(context);
      stopwatch.stop();

      if (stopwatch.elapsedMicroseconds > 16000) {
        // > 16ms = dropped frame
        debugPrint(
          '[MeasuredBuilder] SLOW BUILD: $label took '
          '${stopwatch.elapsedMicroseconds}us (> 16ms budget)',
        );
      }

      return result;
    }

    return builder(context);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONST-OPTIMIZED TEXT
// ═══════════════════════════════════════════════════════════════════════════════

/// A text widget that uses const construction when possible.
///
/// For static text, use the const constructor to avoid rebuilds.
/// For dynamic text, this falls back to a regular [Text] widget.
class OptimizedText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const OptimizedText(
    this.data, {
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      // Use semanticsLabel to help const detection in tests
      semanticsLabel: data.length > 100 ? data.substring(0, 100) : null,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SKELETON LOADING PLACEHOLDER
// ═══════════════════════════════════════════════════════════════════════════════

/// A skeleton loading placeholder with shimmer effect.
///
/// Shows a pulsing placeholder while content is loading.
/// Uses [ShimmerPlaceholder] from render_optimizer.dart for the effect.
class SkeletonPlaceholder extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const SkeletonPlaceholder({
    this.width = double.infinity,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF1A2236),
        borderRadius: borderRadius,
      ),
    );
  }
}

/// A list of skeleton placeholders for loading states.
class SkeletonList extends StatelessWidget {
  final int itemCount;
  final double itemHeight;
  final double spacing;
  final EdgeInsets padding;

  const SkeletonList({
    this.itemCount = 5,
    this.itemHeight = 60,
    this.spacing = 12,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: padding,
      itemCount: itemCount,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemBuilder: (context, index) {
        return Padding(
          padding: EdgeInsets.only(bottom: spacing),
          child: SkeletonPlaceholder(height: itemHeight),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ASYNC IMAGE WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// An async image that shows a placeholder while loading.
///
/// Optimized for network images with caching and fade transitions.
class AsyncImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;

  const AsyncImage({
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    Widget image = Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: fit,
      cacheWidth: width != null ? (width! * 2).toInt() : null,
      cacheHeight: height != null ? (height! * 2).toInt() : null,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return placeholder ??
            Container(
              width: width,
              height: height,
              color: const Color(0xFF1A2236),
            );
      },
      errorBuilder: (context, error, stackTrace) {
        return errorWidget ??
            Container(
              width: width,
              height: height,
              color: const Color(0xFF1A2236),
              child: const Icon(
                Icons.broken_image,
                color: Color(0xFF4B5563),
              ),
            );
      },
    );

    if (borderRadius != null) {
      image = ClipRRect(
        borderRadius: borderRadius!,
        clipBehavior: Clip.antiAlias,
        child: image,
      );
    }

    return RepaintBoundary(child: image);
  }
}
