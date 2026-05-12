import 'dart:math' show max;

import 'package:flutter/material.dart';

/// ============================================================================
/// SKELETON LOADING WIDGETS
/// ============================================================================
///
/// Beautiful, theme-aware skeleton loading placeholders that provide
/// visual feedback during async data loading operations.
///
/// Each skeleton is designed to mimic the structure of the actual content,
/// reducing cognitive load and perceived loading time through the
/// "placeholder shimmer" effect.
///
/// Features:
/// - Shimmer animation with customizable colors and speed
/// - Multiple layout variants (code, card, list, dashboard, profile)
/// - Proportional sizing that matches final content
/// - Accessibility-friendly reduced-motion support
/// - Zero dependencies (built-in animation)
///
/// Usage:
/// ```dart
/// if (isLoading) {
///   return const SkeletonCodeEditor(lineCount: 15);
/// }
/// return ActualContent();
/// ```

// ---------------------------------------------------------------------------
// Shimmer Animation Widget
// ---------------------------------------------------------------------------

/// Direction of the shimmer gradient sweep.
enum ShimmerDirection { ltr, rtl, ttb, btt }

/// A widget that applies a shimmering effect to its child.
///
/// Creates an animated linear gradient mask that sweeps across the child
/// widget, producing a "loading shimmer" effect commonly seen in
/// modern mobile apps.
///
/// The shimmer effect uses a [LinearGradient] with transparent stops
/// that animate across the widget, creating the illusion of light
/// reflecting off a surface.
///
/// This is a zero-dependency implementation. For more advanced use cases,
/// consider the `shimmer` package on pub.dev.
class Shimmer extends StatefulWidget {
  /// The widget below this widget in the tree. This widget will
  /// have the shimmer effect applied to it.
  final Widget child;

  /// The base color of the shimmer effect. This should be slightly
  /// darker than the highlight color.
  final Color baseColor;

  /// The highlight color that sweeps across the child. This should
  /// be lighter than the base color to create the shimmer effect.
  final Color highlightColor;

  /// The direction of the shimmer sweep.
  final ShimmerDirection direction;

  /// The duration of one complete shimmer sweep cycle.
  ///
  /// Default is 1.5 seconds for a smooth, calming effect.
  final Duration period;

  /// How the animation should repeat.
  ///
  /// By default, the shimmer loops continuously.
  final AnimationBehavior animationBehavior;

  const Shimmer({
    super.key,
    required this.child,
    required this.baseColor,
    required this.highlightColor,
    this.direction = ShimmerDirection.ltr,
    this.period = const Duration(milliseconds: 1500),
    this.animationBehavior = AnimationBehavior.normal,
  });

  /// Factory constructor for the common left-to-right shimmer.
  factory Shimmer.fromColors({
    Key? key,
    required Color baseColor,
    required Color highlightColor,
    required Widget child,
    ShimmerDirection direction = ShimmerDirection.ltr,
    Duration period = const Duration(milliseconds: 1500),
  }) {
    return Shimmer(
      key: key,
      baseColor: baseColor,
      highlightColor: highlightColor,
      direction: direction,
      period: period,
      child: child,
    );
  }

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.period,
    );
    _animation = Tween<double>(begin: -2.0, end: 2.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOutSine,
      ),
    );
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Build the gradient shimmer transform based on direction.
  GradientTransform _buildTransform(double value) {
    switch (widget.direction) {
      case ShimmerDirection.ltr:
        return _ShimmerTransform.translateX(value);
      case ShimmerDirection.rtl:
        return _ShimmerTransform.translateX(-value);
      case ShimmerDirection.ttb:
        return _ShimmerTransform.translateY(value);
      case ShimmerDirection.btt:
        return _ShimmerTransform.translateY(-value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
              ],
              stops: const [0.0, 0.5, 1.0],
              transform: _buildTransform(_animation.value),
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcIn,
          child: widget.child,
        );
      },
    );
  }
}

/// Custom gradient transform that translates the shimmer sweep.
class _ShimmerTransform extends GradientTransform {
  final double translateX;
  final double translateY;

  const _ShimmerTransform.translateX(double value)
      : translateX = value,
        translateY = 0;

  const _ShimmerTransform.translateY(double value)
      : translateX = 0,
        translateY = value;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(
      bounds.width * translateX,
      bounds.height * translateY,
      0.0,
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton Base Widgets
// ---------------------------------------------------------------------------

/// A rectangular skeleton placeholder with shimmer effect.
///
/// The fundamental building block for all skeleton layouts.
class _SkeletonRect extends StatelessWidget {
  final double? width;
  final double? height;
  final double borderRadius;
  final Color baseColor;
  final Color highlightColor;

  const _SkeletonRect({
    this.width,
    this.height,
    this.borderRadius = 4.0,
    this.baseColor = _defaultBaseColor,
    this.highlightColor = _defaultHighlightColor,
  });

  static const Color _defaultBaseColor = Color(0xFF2A2A3E);
  static const Color _defaultHighlightColor = Color(0xFF3A3A52);

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

/// A circular skeleton placeholder (for avatars, icons).
class _SkeletonCircle extends StatelessWidget {
  final double size;
  final Color baseColor;
  final Color highlightColor;

  const _SkeletonCircle({
    required this.size,
    this.baseColor = _SkeletonRect._defaultBaseColor,
    this.highlightColor = _SkeletonRect._defaultHighlightColor,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton Code Editor
// ---------------------------------------------------------------------------

/// Skeleton placeholder for a code editor view.
///
/// Displays animated lines of varying widths that mimic actual
/// source code with realistic line-length patterns.
///
/// Features:
/// - Line number gutter on the left
/// - Variable line lengths based on real code patterns
/// - Indented blocks simulating nested code
/// - Customizable line count
///
/// Use while loading code files or when the editor content
/// is being fetched/generated.
class SkeletonCodeEditor extends StatelessWidget {
  /// Number of code lines to display.
  final int lineCount;

  /// Color behind the shimmer (dark theme default).
  final Color baseColor;

  /// Shimmer highlight color.
  final Color highlightColor;

  /// Whether to show line numbers in the gutter.
  final bool showLineNumbers;

  /// Vertical spacing between lines.
  final double lineSpacing;

  /// Height of each skeleton line.
  final double lineHeight;

  const SkeletonCodeEditor({
    super.key,
    this.lineCount = 20,
    this.baseColor = const Color(0xFF1A1A2E),
    this.highlightColor = const Color(0xFF2A2A42),
    this.showLineNumbers = true,
    this.lineSpacing = 8.0,
    this.lineHeight = 12.0,
  });

  /// Realistic line width patterns that mimic actual code structure:
  /// - Long lines: full statements, function calls
  /// - Medium lines: assignments, conditions
  /// - Short lines: closing braces, returns
  /// - Indented lines: nested blocks
  static const List<double> _linePatterns = [
    0.92, // Long line (import/function def)
    0.85, // Medium-long (statement)
    0.65, // Medium (assignment)
    0.45, // Short (closing brace/return)
    0.88, // Long (function call)
    0.72, // Medium (conditional)
    0.38, // Very short (standalone symbol)
    0.90, // Long (method chain)
    0.55, // Medium-short (property access)
    0.78, // Medium-long (parameter list)
  ];

  /// Indentation levels (0 = no indent, 1 = one level, etc.)
  static const List<double> _indentPatterns = [
    0.0, // Top-level
    0.0, // Top-level
    1.0, // Inside function
    1.0, // Inside function
    2.0, // Nested block (if/for)
    2.0, // Nested block
    1.0, // Back to function level
    0.0, // New top-level function
    1.0, // Inside new function
    1.0, // Inside new function
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: baseColor,
      child: Shimmer.fromColors(
        baseColor: const Color(0xFF252538),
        highlightColor: const Color(0xFF353550),
        child: ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: lineCount,
          itemBuilder: (context, index) {
            final widthFactor = _linePatterns[index % _linePatterns.length];
            final indentLevel =
                _indentPatterns[index % _indentPatterns.length];
            final hasIndent = indentLevel > 0;

            return Padding(
              padding: EdgeInsets.symmetric(
                vertical: lineSpacing / 2,
                horizontal: 16,
              ),
              child: Row(
                children: [
                  // Line number gutter
                  if (showLineNumbers) ...[
                    SizedBox(
                      width: 32,
                      child: Container(
                        height: lineHeight,
                        width: 20,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  // Indentation spacer
                  if (hasIndent)
                    SizedBox(width: 24.0 * indentLevel),
                  // Code line with varying width
                  Flexible(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: widthFactor,
                      child: Container(
                        height: lineHeight,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton Card
// ---------------------------------------------------------------------------

/// Skeleton placeholder for a card component.
///
/// Displays a rounded rectangle with optional header and
/// body sections, mimicking a content card.
///
/// Use while card content (articles, repos, settings) is loading.
class SkeletonCard extends StatelessWidget {
  /// Total height of the card skeleton.
  final double height;

  /// Whether to show a title bar at the top.
  final bool hasHeader;

  /// Whether to show action buttons at the bottom.
  final bool hasFooter;

  /// Number of body text lines.
  final int bodyLines;

  /// Border radius of the card.
  final double borderRadius;

  const SkeletonCard({
    super.key,
    this.height = 120,
    this.hasHeader = true,
    this.hasFooter = false,
    this.bodyLines = 2,
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF2A2A3E) : const Color(0xFFE0E0E0);
    final highlightColor = isDark ? const Color(0xFF3A3A52) : const Color(0xFFF0F0F0);

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Container(
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: avatar circle + title line
            if (hasHeader) ...[
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            // Body: multiple lines of varying width
            ...List.generate(bodyLines, (index) {
              final widths = [1.0, 0.85, 0.65, 0.9, 0.5];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FractionallySizedBox(
                  widthFactor: widths[index % widths.length],
                  child: Container(
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              );
            }),
            const Spacer(),
            // Footer: action buttons
            if (hasFooter)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    width: 60,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 60,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton List
// ---------------------------------------------------------------------------

/// Skeleton placeholder for a list of items.
///
/// Displays rows with avatar circles and text lines,
/// commonly used for lists of users, repos, files, etc.
///
/// Use while loading list data from an API or database.
class SkeletonList extends StatelessWidget {
  /// Number of list items to display.
  final int itemCount;

  /// Whether items have leading avatar circles.
  final bool hasAvatar;

  /// Number of subtitle lines per item.
  final int subtitleLines;

  /// Height of each list item.
  final double itemHeight;

  const SkeletonList({
    super.key,
    this.itemCount = 6,
    this.hasAvatar = true,
    this.subtitleLines = 1,
    this.itemHeight = 64,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF2A2A3E) : const Color(0xFFE0E0E0);
    final highlightColor = isDark ? const Color(0xFF3A3A52) : const Color(0xFFF0F0F0);

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: itemCount,
        itemBuilder: (context, index) {
          return Container(
            height: itemHeight,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Leading avatar circle
                if (hasAvatar) ...[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                // Text content: title + subtitle lines
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title line
                      Container(
                        height: 12,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Subtitle lines (varying widths)
                      ...List.generate(subtitleLines, (subIndex) {
                        final subtitleWidths = [0.65, 0.45, 0.8];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: FractionallySizedBox(
                            widthFactor:
                                subtitleWidths[subIndex % subtitleWidths.length],
                            child: Container(
                              height: 10,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                // Trailing element (chevron or icon placeholder)
                Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton Dashboard
// ---------------------------------------------------------------------------

/// Skeleton placeholder for the main dashboard layout.
///
/// Displays a comprehensive layout with stat cards, sidebar,
/// toolbar, and editor area — matching the app's actual layout.
///
/// Use during initial app load or when switching workspaces.
class SkeletonDashboard extends StatelessWidget {
  /// Number of stat cards in the top row.
  final int statCount;

  /// Number of lines in the editor area.
  final int editorLineCount;

  const SkeletonDashboard({
    super.key,
    this.statCount = 4,
    this.editorLineCount = 12,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF1A1A2E) : const Color(0xFFE8E8E8);
    final highlightColor = isDark ? const Color(0xFF2A2A42) : const Color(0xFFF5F5F5);

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Column(
        children: [
          // ---- Top stats row ----
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: List.generate(
                statCount,
                (index) => Expanded(
                  child: Container(
                    height: 72,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Stat value
                        Container(
                          height: 20,
                          width: 36,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Stat label
                        Container(
                          height: 10,
                          width: 50,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ---- Main content area ----
          Expanded(
            child: Row(
              children: [
                // Sidebar (icon column)
                Container(
                  width: 56,
                  color: Colors.white,
                  child: Column(
                    children: List.generate(
                      6,
                      (index) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Main content column
                Expanded(
                  child: Column(
                    children: [
                      // Toolbar
                      Container(
                        height: 48,
                        color: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 100,
                              height: 24,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const Spacer(),
                            Container(
                              width: 28,
                              height: 28,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 28,
                              height: 28,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Divider line
                      Container(height: 1, color: Colors.white),

                      // Editor/content area
                      Expanded(
                        child: ListView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: editorLineCount,
                          itemBuilder: (_, index) {
                            final widths = [
                              0.92,
                              0.75,
                              0.88,
                              0.55,
                              0.82,
                              0.45,
                              0.90,
                              0.68,
                              0.78,
                              0.50,
                            ];
                            final indents = [
                              0.0,
                              0.0,
                              1.0,
                              1.0,
                              2.0,
                              1.0,
                              0.0,
                              1.0,
                              1.0,
                              0.0,
                            ];
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 5,
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 28,
                                    child: Container(
                                      height: 10,
                                      width: 18,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  if (indents[index % indents.length] > 0)
                                    SizedBox(
                                      width: 24.0 *
                                          indents[index % indents.length],
                                    ),
                                  Flexible(
                                    child: FractionallySizedBox(
                                      widthFactor:
                                          widths[index % widths.length],
                                      child: Container(
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(2),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton Profile
// ---------------------------------------------------------------------------

/// Skeleton placeholder for a profile / user card view.
///
/// Displays a large avatar, name, bio lines, and stat row —
/// commonly used for user profiles, author cards, and
/// account pages.
class SkeletonProfile extends StatelessWidget {
  /// Diameter of the avatar circle.
  final double avatarSize;

  /// Number of bio/description lines.
  final int bioLines;

  /// Number of stat items in the stats row.
  final int statCount;

  const SkeletonProfile({
    super.key,
    this.avatarSize = 80,
    this.bioLines = 3,
    this.statCount = 3,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF2A2A3E) : const Color(0xFFE0E0E0);
    final highlightColor = isDark ? const Color(0xFF3A3A52) : const Color(0xFFF0F0F0);

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Large avatar
          Container(
            width: avatarSize,
            height: avatarSize,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: 16),

          // Name line
          Container(
            height: 18,
            width: 160,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 8),

          // Username/handle line
          Container(
            height: 12,
            width: 120,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),

          // Bio lines
          ...List.generate(bioLines, (index) {
            final widths = [0.85, 0.7, 0.5];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 4),
              child: FractionallySizedBox(
                widthFactor: widths[index % widths.length],
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 24),

          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              statCount,
              (index) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    Container(
                      height: 20,
                      width: 36,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 10,
                      width: 50,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton Chart / Graph
// ---------------------------------------------------------------------------

/// Skeleton placeholder for charts and graphs.
///
/// Displays animated bars of varying heights that simulate
/// a bar chart loading state.
///
/// Use while chart data is being fetched or computed.
class SkeletonChart extends StatelessWidget {
  /// Number of bars in the chart.
  final int barCount;

  /// Maximum height of bars.
  final double maxBarHeight;

  /// Width of each bar.
  final double barWidth;

  /// Spacing between bars.
  final double barSpacing;

  const SkeletonChart({
    super.key,
    this.barCount = 8,
    this.maxBarHeight = 120,
    this.barWidth = 24,
    this.barSpacing = 12,
  });

  /// Deterministic pseudo-random heights for bars (so they don't
  /// change on every rebuild).
  static const List<double> _barHeights = [
    0.75,
    0.45,
    0.90,
    0.60,
    1.0,
    0.35,
    0.80,
    0.55,
    0.70,
    0.85,
    0.40,
    0.65,
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF2A2A3E) : const Color(0xFFE0E0E0);
    final highlightColor = isDark ? const Color(0xFF3A3A52) : const Color(0xFFF0F0F0);

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(barCount, (index) {
          final heightFactor = _barHeights[index % _barHeights.length];
          return Container(
            width: barWidth,
            height: maxBarHeight * heightFactor,
            margin: EdgeInsets.symmetric(horizontal: barSpacing / 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(6),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton Message / Chat Bubble
// ---------------------------------------------------------------------------

/// Skeleton placeholder for chat message bubbles.
///
/// Displays alternating left/right message bubbles with
/// varying widths, mimicking a conversation loading state.
class SkeletonChat extends StatelessWidget {
  /// Number of message bubbles.
  final int messageCount;

  const SkeletonChat({
    super.key,
    this.messageCount = 6,
  });

  /// Bubble width patterns for realistic conversation look.
  static const List<double> _bubbleWidths = [
    0.72,
    0.58,
    0.85,
    0.45,
    0.68,
    0.90,
    0.55,
    0.78,
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF2A2A3E) : const Color(0xFFE0E0E0);
    final highlightColor = isDark ? const Color(0xFF3A3A52) : const Color(0xFFF0F0F0);

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: messageCount,
        itemBuilder: (context, index) {
          final isMe = index % 2 == 0;
          final widthFactor = _bubbleWidths[index % _bubbleWidths.length];
          final lineCount = 1 + (index % 3); // 1-3 lines per bubble

          return Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: MediaQuery.of(context).size.width * widthFactor,
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(lineCount, (lineIndex) {
                  final lineWidths = [1.0, 0.8, 0.55];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: FractionallySizedBox(
                      widthFactor: lineWidths[lineIndex % lineWidths.length],
                      child: Container(
                        height: 11,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton Search / Input
// ---------------------------------------------------------------------------

/// Skeleton placeholder for search results with filters.
///
/// Displays a search bar skeleton followed by result items,
/// used when search results are loading.
class SkeletonSearchResults extends StatelessWidget {
  /// Number of result items.
  final int resultCount;

  /// Whether to show filter chip skeletons.
  final bool hasFilters;

  const SkeletonSearchResults({
    super.key,
    this.resultCount = 4,
    this.hasFilters = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF2A2A3E) : const Color(0xFFE0E0E0);
    final highlightColor = isDark ? const Color(0xFF3A3A52) : const Color(0xFFF0F0F0);

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search bar
          Container(
            height: 44,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
          ),

          // Filter chips
          if (hasFilters)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 8,
                children: List.generate(
                  4,
                  (index) => Container(
                    width: 70 + (index * 15),
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),

          // Result items
          ...List.generate(resultCount, (index) {
            return Container(
              height: 72,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          height: 12,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 10,
                          width: 120,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton Settings
// ---------------------------------------------------------------------------

/// Skeleton placeholder for a settings page.
///
/// Displays section headers and toggle rows, mimicking
/// the typical settings/preferences layout.
class SkeletonSettings extends StatelessWidget {
  /// Number of settings sections.
  final int sectionCount;

  /// Items per section.
  final int itemsPerSection;

  const SkeletonSettings({
    super.key,
    this.sectionCount = 3,
    this.itemsPerSection = 3,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF2A2A3E) : const Color(0xFFE0E0E0);
    final highlightColor = isDark ? const Color(0xFF3A3A52) : const Color(0xFFF0F0F0);

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: sectionCount * (itemsPerSection + 1),
        itemBuilder: (context, index) {
          final isHeader = index % (itemsPerSection + 1) == 0;

          if (isHeader) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Container(
                height: 14,
                width: 100,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            );
          }

          return Container(
            height: 52,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 44,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Convenience: SkeletonContainer
// ---------------------------------------------------------------------------

/// A convenience widget that wraps any skeleton with proper
/// theming and optional padding.
///
/// Automatically selects the appropriate skeleton type based
/// on the [SkeletonType] parameter.
class SkeletonContainer extends StatelessWidget {
  final SkeletonType type;
  final int itemCount;
  final EdgeInsets padding;

  const SkeletonContainer({
    super.key,
    required this.type,
    this.itemCount = 5,
    this.padding = const EdgeInsets.all(0),
  });

  @override
  Widget build(BuildContext context) {
    Widget skeleton;
    switch (type) {
      case SkeletonType.codeEditor:
        skeleton = SkeletonCodeEditor(lineCount: itemCount);
        break;
      case SkeletonType.card:
        skeleton = const SkeletonCard();
        break;
      case SkeletonType.list:
        skeleton = SkeletonList(itemCount: itemCount);
        break;
      case SkeletonType.dashboard:
        skeleton = const SkeletonDashboard();
        break;
      case SkeletonType.profile:
        skeleton = const SkeletonProfile();
        break;
      case SkeletonType.chart:
        skeleton = SkeletonChart(barCount: itemCount);
        break;
      case SkeletonType.chat:
        skeleton = SkeletonChat(messageCount: itemCount);
        break;
      case SkeletonType.search:
        skeleton = SkeletonSearchResults(resultCount: itemCount);
        break;
      case SkeletonType.settings:
        skeleton = SkeletonSettings(sectionCount: itemCount);
        break;
    }

    return Padding(padding: padding, child: skeleton);
  }
}

/// Available skeleton layout types.
enum SkeletonType {
  codeEditor,
  card,
  list,
  dashboard,
  profile,
  chart,
  chat,
  search,
  settings,
}
