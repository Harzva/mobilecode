// lib/widgets/contribution_graph.dart

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../core/theme.dart';
import '../services/vibing_activity_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Contribution Graph Widget
// ═══════════════════════════════════════════════════════════════════════════

/// {@template contribution_graph}
/// GitHub-style contribution heatmap widget.
///
/// Renders a 53-column x 7-row grid of activity cells.
/// Each cell's color intensity represents the activity level (0-4).
/// Supports tap for detail popup, month labels, and day labels.
///
/// Colors (dark theme, matching GitHub's green palette):
/// - Level 0: #161B22 (empty)
/// - Level 1: #0E4429 (light)
/// - Level 2: #006D32 (medium)
/// - Level 3: #26A641 (high)
/// - Level 4: #39D353 (very high)
///
/// Implementation uses CustomPainter for high performance.
/// {@endtemplate}
class ContributionGraph extends StatelessWidget {
  /// Activity data for each day.
  final List<ContributionDay> data;

  /// Callback when a cell is tapped.
  final void Function(ContributionDay day)? onCellTap;

  /// Number of weeks to display (default 53 for a full year).
  final int weeks;

  /// Size of each cell in logical pixels.
  final double cellSize;

  /// Gap between cells.
  final double cellGap;

  /// Border radius of each cell.
  final double cellRadius;

  const ContributionGraph({
    super.key,
    required this.data,
    this.onCellTap,
    this.weeks = 53,
    this.cellSize = 12,
    this.cellGap = 3,
    this.cellRadius = 2.5,
  });

  /// Get the color for a given activity level (0-4).
  static Color levelColor(int level) {
    switch (level.clamp(0, 4)) {
      case 0:
        return const Color(0xFF161B22);
      case 1:
        return const Color(0xFF0E4429);
      case 2:
        return const Color(0xFF006D32);
      case 3:
        return const Color(0xFF26A641);
      case 4:
        return const Color(0xFF39D353);
      default:
        return const Color(0xFF161B22);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelWidth = 32.0;
        final monthLabelHeight = 18.0;
        final availableWidth = constraints.maxWidth - labelWidth;

        // Compute adaptive cell size to fit within available width.
        final computedCellSize = math.min(
          cellSize,
          (availableWidth - (weeks + 1) * cellGap) / weeks,
        );
        final computedCellGap = cellGap;
        final computedCellRadius = cellRadius;

        final painter = _ContributionGraphPainter(
          data: data,
          weeks: weeks,
          cellSize: computedCellSize,
          cellGap: computedCellGap,
          cellRadius: computedCellRadius,
          labelWidth: labelWidth,
          monthLabelHeight: monthLabelHeight,
        );

        final graphWidth = labelWidth +
            weeks * (computedCellSize + computedCellGap) +
            computedCellGap;
        final graphHeight = monthLabelHeight +
            7 * (computedCellSize + computedCellGap) +
            computedCellGap;

        return SizedBox(
          width: graphWidth,
          height: graphHeight,
          child: CustomPaint(
            painter: painter,
            size: Size(graphWidth, graphHeight),
            child: _ContributionGraphHitTest(
              data: data,
              weeks: weeks,
              cellSize: computedCellSize,
              cellGap: computedCellGap,
              labelWidth: labelWidth,
              monthLabelHeight: monthLabelHeight,
              onCellTap: onCellTap,
            ),
          ),
        );
      },
    );
  }
}

// ── Hit Test Layer ───────────────────────────────────────────────────

/// Invisible hit-test layer overlaid on the painted graph.
/// Detects taps on individual cells and triggers the callback.
class _ContributionGraphHitTest extends StatelessWidget {
  final List<ContributionDay> data;
  final int weeks;
  final double cellSize;
  final double cellGap;
  final double labelWidth;
  final double monthLabelHeight;
  final void Function(ContributionDay day)? onCellTap;

  const _ContributionGraphHitTest({
    required this.data,
    required this.weeks,
    required this.cellSize,
    required this.cellGap,
    required this.labelWidth,
    required this.monthLabelHeight,
    this.onCellTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Day labels column (no hit targets).
        SizedBox(width: labelWidth),
        // Grid area with gesture detector.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Month labels row (no hit targets).
              SizedBox(height: monthLabelHeight),
              // Cell grid with gesture detection.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTapUp: (details) {
                        final localPos = details.localPosition;
                        final cellWithGap = cellSize + cellGap;

                        final weekIndex =
                            (localPos.dx / cellWithGap).floor();
                        final dayIndex =
                            (localPos.dy / cellWithGap).floor();

                        if (weekIndex >= 0 &&
                            weekIndex < weeks &&
                            dayIndex >= 0 &&
                            dayIndex < 7) {
                          final dataIndex = weekIndex * 7 + dayIndex;
                          // Account for starting day offset.
                          final effectiveIndex = dataIndex;
                          if (effectiveIndex >= 0 &&
                              effectiveIndex < data.length) {
                            onCellTap?.call(data[effectiveIndex]);
                          }
                        }
                      },
                      child: Container(color: Colors.transparent),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Custom Painter ───────────────────────────────────────────────────

class _ContributionGraphPainter extends CustomPainter {
  final List<ContributionDay> data;
  final int weeks;
  final double cellSize;
  final double cellGap;
  final double cellRadius;
  final double labelWidth;
  final double monthLabelHeight;

  _ContributionGraphPainter({
    required this.data,
    required this.weeks,
    required this.cellSize,
    required this.cellGap,
    required this.cellRadius,
    required this.labelWidth,
    required this.monthLabelHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Fill background.
    final bgPaint = Paint()..color = const Color(0xFF0D1117);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      bgPaint,
    );

    _paintDayLabels(canvas);
    _paintMonthLabels(canvas);
    _paintCells(canvas);
  }

  /// Paint day-of-week labels on the left (Mon, Wed, Fri).
  void _paintDayLabels(Canvas canvas) {
    final days = ['一', '三', '五'];
    final dayIndices = [0, 2, 4];
    final textStyle = TextStyle(
      color: AppTheme.textTertiary.withOpacity(0.7),
      fontSize: 10,
      fontFamily: AppTheme.fontBody,
    );
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
    );

    for (var i = 0; i < days.length; i++) {
      final dayIndex = dayIndices[i];
      final y = monthLabelHeight +
          cellGap +
          dayIndex * (cellSize + cellGap) +
          cellSize / 2 -
          6;

      textPainter.text = TextSpan(text: days[i], style: textStyle);
      textPainter.layout(maxWidth: labelWidth - 4);
      textPainter.paint(canvas, Offset(labelWidth - textPainter.width - 4, y));
    }
  }

  /// Paint month labels at the top of each column group.
  void _paintMonthLabels(Canvas canvas) {
    final textStyle = TextStyle(
      color: AppTheme.textTertiary.withOpacity(0.7),
      fontSize: 10,
      fontFamily: AppTheme.fontBody,
    );
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
    );

    final cellWithGap = cellSize + cellGap;
    String? lastMonth;

    for (var week = 0; week < weeks; week++) {
      final dataIndex = week * 7;
      if (dataIndex >= data.length) break;

      final day = data[dataIndex];
      final month = '${day.date.month}月';

      if (month != lastMonth) {
        lastMonth = month;
        final x = labelWidth + cellGap + week * cellWithGap;
        textPainter.text = TextSpan(text: month, style: textStyle);
        textPainter.layout();
        textPainter.paint(canvas, Offset(x, 2));
      }
    }
  }

  /// Paint the activity cells grid.
  void _paintCells(Canvas canvas) {
    final cellWithGap = cellSize + cellGap;

    for (var week = 0; week < weeks; week++) {
      for (var day = 0; day < 7; day++) {
        final dataIndex = week * 7 + day;
        if (dataIndex >= data.length) break;

        final contributionDay = data[dataIndex];
        final color = ContributionGraph.levelColor(contributionDay.level);

        final x = labelWidth + cellGap + week * cellWithGap;
        final y = monthLabelHeight + cellGap + day * cellWithGap;

        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, cellSize, cellSize),
          Radius.circular(cellRadius),
        );

        final paint = Paint()..color = color;
        canvas.drawRRect(rect, paint);

        // Subtle border for empty cells.
        if (contributionDay.level == 0) {
          final borderPaint = Paint()
            ..color = const Color(0xFF21262D)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.5;
          canvas.drawRRect(rect, borderPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ContributionGraphPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.weeks != weeks ||
        oldDelegate.cellSize != cellSize;
  }

  @override
  bool shouldRebuildSemantics(covariant _ContributionGraphPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════════
// Contribution Graph with Tooltip
// ═══════════════════════════════════════════════════════════════════════════

/// {@template contribution_graph_with_tooltip}
/// Enhanced contribution graph that shows a tooltip on long-press
/// with detailed activity information for the selected day.
/// {@endtemplate}
class ContributionGraphWithTooltip extends StatefulWidget {
  /// Activity data.
  final List<ContributionDay> data;

  /// Optional tap callback.
  final void Function(ContributionDay day)? onCellTap;

  const ContributionGraphWithTooltip({
    super.key,
    required this.data,
    this.onCellTap,
  });

  @override
  State<ContributionGraphWithTooltip> createState() =>
      _ContributionGraphWithTooltipState();
}

class _ContributionGraphWithTooltipState
    extends State<ContributionGraphWithTooltip> {
  ContributionDay? _hoveredDay;
  Offset? _tooltipPosition;

  void _onCellHover(ContributionDay day, Offset position) {
    setState(() {
      _hoveredDay = day;
      _tooltipPosition = position;
    });
  }

  void _clearHover() {
    setState(() {
      _hoveredDay = null;
      _tooltipPosition = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ContributionGraph(
          data: widget.data,
          onCellTap: widget.onCellTap,
        ),
        if (_hoveredDay != null && _tooltipPosition != null)
          Positioned(
            left: _tooltipPosition!.dx - 60,
            top: _tooltipPosition!.dy - 50,
            child: _TooltipCard(day: _hoveredDay!),
          ),
      ],
    );
  }
}

// ── Tooltip Card ─────────────────────────────────────────────────────

class _TooltipCard extends StatelessWidget {
  final ContributionDay day;

  const _TooltipCard({required this.day});

  @override
  Widget build(BuildContext context) {
    final dateStr =
        '${day.date.year}年${day.date.month}月${day.date.day}日';
    final weekdayNames = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final weekday = weekdayNames[day.date.weekday];

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceHover,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$dateStr $weekday',
              style: const TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: ContributionGraph.levelColor(day.level),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  day.count > 0 ? '${day.count} 次活动' : '无活动',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
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

// ═══════════════════════════════════════════════════════════════════════════
// Mini Contribution Graph (compact variant)
// ═══════════════════════════════════════════════════════════════════════════

/// {@template mini_contribution_graph}
/// Compact version of the contribution graph for embedding in cards.
/// Shows a single row of 14 cells (2 weeks) or a small grid.
/// {@endtemplate}
class MiniContributionGraph extends StatelessWidget {
  /// Activity data.
  final List<ContributionDay> data;

  /// Number of days to show (default 14).
  final int days;

  /// Cell size (smaller than full graph).
  final double cellSize;

  const MiniContributionGraph({
    super.key,
    required this.data,
    this.days = 14,
    this.cellSize = 10,
  });

  @override
  Widget build(BuildContext context) {
    final recentData = data.length > days ? data.sublist(data.length - days) : data;
    final cellGap = 3.0;
    final cellRadius = 2.5;

    return SizedBox(
      height: cellSize + cellGap * 2,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: recentData.length,
        separatorBuilder: (_, __) => SizedBox(width: cellGap),
        itemBuilder: (context, index) {
          final day = recentData[index];
          return Container(
            width: cellSize,
            height: cellSize,
            decoration: BoxDecoration(
              color: ContributionGraph.levelColor(day.level),
              borderRadius: BorderRadius.circular(cellRadius),
              border: day.level == 0
                  ? Border.all(
                      color: const Color(0xFF21262D),
                      width: 0.5,
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Animated Contribution Graph (with entry animation)
// ═══════════════════════════════════════════════════════════════════════════

/// {@template animated_contribution_graph}
/// Contribution graph with staggered fade-in animation for cells.
/// {@endtemplate}
class AnimatedContributionGraph extends StatefulWidget {
  final List<ContributionDay> data;
  final void Function(ContributionDay day)? onCellTap;

  const AnimatedContributionGraph({
    super.key,
    required this.data,
    this.onCellTap,
  });

  @override
  State<AnimatedContributionGraph> createState() =>
      _AnimatedContributionGraphState();
}

class _AnimatedContributionGraphState
    extends State<AnimatedContributionGraph>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _controller.forward();
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
        // Animate by progressively revealing cells.
        final visibleCount =
            (widget.data.length * _controller.value).round();
        final visibleData = visibleCount < widget.data.length
            ? widget.data.sublist(0, visibleCount)
            : widget.data;

        return ContributionGraph(
          data: visibleData,
          onCellTap: widget.onCellTap,
        );
      },
    );
  }
}
