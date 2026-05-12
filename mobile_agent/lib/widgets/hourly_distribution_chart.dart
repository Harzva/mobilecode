// lib/widgets/hourly_distribution_chart.dart
// Hourly Distribution Chart — CustomPainter-based 24-hour activity bar chart.
//
// Horizontal bar showing 24 hours (0:00 - 23:59).
// - Color intensity = activity level (gradient from dark to bright)
// - Peak hours highlighted with glow effect
// - Tap hour to see details tooltip
//
// Design: Dark background, gradient bars, violet/cyan accent colors.

import 'package:flutter/material.dart';

import '../core/theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Hourly Distribution Chart Widget
// ═══════════════════════════════════════════════════════════════════════════

/// A 24-hour activity distribution horizontal bar chart.
///
/// Displays activity levels across all 24 hours using color intensity.
/// Peak hours are highlighted with a glow effect. Users can tap on any
/// hour to see a detail tooltip.
///
/// ```dart
/// HourlyDistributionChart(
///   distribution: {0: 5, 1: 2, 2: 0, ..., 20: 45, 21: 38, ...},
/// )
/// ```
class HourlyDistributionChart extends StatefulWidget {
  /// Hour (0-23) -> activity count mapping.
  final Map<int, int> distribution;

  /// Height of the chart area.
  final double height;

  /// Whether to show hour labels below the bars.
  final bool showLabels;

  const HourlyDistributionChart({
    super.key,
    required this.distribution,
    this.height = 90,
    this.showLabels = true,
  });

  @override
  State<HourlyDistributionChart> createState() => _HourlyDistributionChartState();
}

class _HourlyDistributionChartState extends State<HourlyDistributionChart> {
  int? _hoveredHour;

  @override
  Widget build(BuildContext context) {
    // Find max value for normalization.
    final maxValue = widget.distribution.values.isEmpty
        ? 1
        : widget.distribution.values.reduce((a, b) => a > b ? a : b);

    // Calculate peak hours (top 3).
    final sortedEntries = widget.distribution.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final peakHours = sortedEntries.take(3).map((e) => e.key).toSet();

    return GestureDetector(
      onTapUp: (details) {
        // Calculate which hour was tapped.
        final box = context.findRenderObject() as RenderBox;
        final localPos = box.globalToLocal(details.globalPosition);
        final barWidth = box.size.width / 24;
        final hour = (localPos.dx / barWidth).floor().clamp(0, 23);
        setState(() => _hoveredHour = _hoveredHour == hour ? null : hour);
      },
      child: Column(
        children: [
          SizedBox(
            height: widget.height,
            child: CustomPaint(
              size: Size.infinite,
              painter: _HourlyBarPainter(
                distribution: widget.distribution,
                maxValue: maxValue.toDouble(),
                peakHours: peakHours,
                hoveredHour: _hoveredHour,
              ),
            ),
          ),
          if (widget.showLabels) ...[
            const SizedBox(height: 4),
            // Hour labels
            SizedBox(
              height: 16,
              child: Row(
                children: List.generate(24, (hour) {
                  final isPeak = peakHours.contains(hour);
                  final isHovered = _hoveredHour == hour;
                  return Expanded(
                    child: Center(
                      child: isHovered || (hour % 3 == 0)
                          ? Text(
                              '$hour',
                              style: TextStyle(
                                fontFamily: AppTheme.fontBody,
                                fontSize: isHovered ? 11 : 8,
                                fontWeight: isHovered ? FontWeight.w700 : FontWeight.w500,
                                color: isHovered
                                    ? AppTheme.accent
                                    : isPeak
                                        ? AppTheme.primary
                                        : AppTheme.textTertiary,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  );
                }),
              ),
            ),
          ],
          // Tooltip
          if (_hoveredHour != null) ...[
            const SizedBox(height: 6),
            _buildTooltip(_hoveredHour!, widget.distribution[_hoveredHour] ?? 0, peakHours),
          ],
        ],
      ),
    );
  }

  Widget _buildTooltip(int hour, int value, Set<int> peakHours) {
    final isPeak = peakHours.contains(hour);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHover,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPeak ? AppTheme.accent.withOpacity(0.5) : AppTheme.border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPeak ? Icons.local_fire_department : Icons.access_time,
            color: isPeak ? AppTheme.accent : AppTheme.textSecondary,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            '${hour.toString().padLeft(2, '0')}:00 - ${hour.toString().padLeft(2, '0')}:59',
            style: const TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isPeak
                  ? AppTheme.accent.withOpacity(0.15)
                  : AppTheme.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$value 分钟',
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isPeak ? AppTheme.accent : AppTheme.primary,
              ),
            ),
          ),
          if (isPeak) ...[
            const SizedBox(width: 8),
            const Text(
              '峰值时段',
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 11,
                color: AppTheme.accent,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Custom Painter
// ═══════════════════════════════════════════════════════════════════════════

/// Custom painter for rendering the 24-hour bar chart.
class _HourlyBarPainter extends CustomPainter {
  final Map<int, int> distribution;
  final double maxValue;
  final Set<int> peakHours;
  final int? hoveredHour;

  _HourlyBarPainter({
    required this.distribution,
    required this.maxValue,
    required this.peakHours,
    this.hoveredHour,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (maxValue <= 0) return;

    final barWidth = size.width / 24;
    final gap = 2.0;
    final effectiveBarWidth = barWidth - gap;

    for (var hour = 0; hour < 24; hour++) {
      final value = distribution[hour] ?? 0;
      final normalizedValue = value / maxValue;
      final barHeight = normalizedValue * size.height;

      final left = hour * barWidth + gap / 2;
      final top = size.height - barHeight;
      final rect = Rect.fromLTWH(left, top, effectiveBarWidth, barHeight);

      final isPeak = peakHours.contains(hour);
      final isHovered = hoveredHour == hour;

      // Paint bar with gradient.
      final gradient = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: isHovered
            ? [AppTheme.accent.withOpacity(0.9), AppTheme.accent.withOpacity(0.4)]
            : isPeak
                ? [AppTheme.primary.withOpacity(0.9), AppTheme.primary.withOpacity(0.3)]
                : [
                    _getBarColor(normalizedValue).withOpacity(0.7),
                    _getBarColor(normalizedValue).withOpacity(0.2),
                  ],
      );

      final paint = Paint()
        ..shader = gradient.createShader(rect)
        ..style = PaintingStyle.fill;

      final rrect = RRect.fromRectAndRadius(
        rect,
        const Radius.circular(3),
      );

      canvas.drawRRect(rrect, paint);

      // Glow effect for peak hours.
      if (isPeak) {
        final glowPaint = Paint()
          ..color = AppTheme.primary.withOpacity(0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 6);
        canvas.drawRRect(rrect, glowPaint);
      }

      // Highlight for hovered hour.
      if (isHovered) {
        final highlightPaint = Paint()
          ..color = AppTheme.accent.withOpacity(0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 8);
        canvas.drawRRect(rrect, highlightPaint);

        // Border stroke.
        final borderPaint = Paint()
          ..color = AppTheme.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawRRect(rrect, borderPaint);
      }
    }

    // Draw horizontal baseline.
    final baselinePaint = Paint()
      ..color = AppTheme.border
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      baselinePaint,
    );
  }

  /// Get bar color based on normalized activity level.
  Color _getBarColor(double normalized) {
    if (normalized <= 0) return AppTheme.border;
    if (normalized < 0.25) return AppTheme.textTertiary.withOpacity(0.4);
    if (normalized < 0.5) return AppTheme.textSecondary.withOpacity(0.5);
    if (normalized < 0.75) return AppTheme.primary.withOpacity(0.6);
    return AppTheme.primary;
  }

  @override
  bool shouldRepaint(covariant _HourlyBarPainter oldDelegate) {
    return oldDelegate.distribution != distribution ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.peakHours != peakHours ||
        oldDelegate.hoveredHour != hoveredHour;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Mini Hourly Preview (compact version for small spaces)
// ═══════════════════════════════════════════════════════════════════════════

/// A compact mini version of the hourly distribution chart.
///
/// Shows only the bar visualization without labels or interaction.
/// Ideal for dashboards and summary cards.
class MiniHourlyPreview extends StatelessWidget {
  final Map<int, int> distribution;
  final double height;

  const MiniHourlyPreview({
    super.key,
    required this.distribution,
    this.height = 32,
  });

  @override
  Widget build(BuildContext context) {
    final maxValue = distribution.values.isEmpty
        ? 1
        : distribution.values.reduce((a, b) => a > b ? a : b);

    final peakHours = distribution.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final peakSet = peakHours.take(2).map((e) => e.key).toSet();

    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _HourlyBarPainter(
          distribution: distribution,
          maxValue: maxValue.toDouble(),
          peakHours: peakSet,
        ),
      ),
    );
  }
}
