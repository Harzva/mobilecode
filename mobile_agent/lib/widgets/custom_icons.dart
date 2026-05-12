// ============================================================
// custom_icons.dart — MobileCode Custom Icon System
// ============================================================
// A unified icon system providing:
// - Consistent icon set for all app features
// - Three size presets (small/medium/large)
// - Adaptive coloring based on active theme
// - Animated variants (rotating gear, pulsing dot, etc.)
// - All icons are implemented as clean, crisp vector shapes
// ============================================================

import 'dart:math' show pi;
import 'package:flutter/material.dart';
import '../core/theme_manager.dart';
import '../core/animations.dart';

// ============================================================
// SECTION 1: Icon Size Presets
// ============================================================

/// Standardized icon sizes used throughout the app.
class IconSizes {
  static const double small = 16;
  static const double medium = 24;
  static const double large = 32;
  static const double xlarge = 48;
  static const double xxlarge = 64;
}

// ============================================================
// SECTION 2: Adaptive Icon Color Helpers
// ============================================================

/// Returns the appropriate icon color based on context and state.
Color _adaptiveColor(BuildContext context, {
  Color? color,
  bool primary = false,
  bool muted = false,
  bool onSurface = false,
}) {
  if (color != null) return color;
  final scheme = Theme.of(context).colorScheme;
  if (primary) return scheme.primary;
  if (muted) return scheme.onSurfaceVariant.withOpacity(0.6);
  if (onSurface) return scheme.onSurface;
  return scheme.onSurfaceVariant;
}

// ============================================================
// SECTION 3: Custom Icons Namespace
// ============================================================

/// All custom icons for the MobileCode app.
/// Each icon is a self-contained widget built from vector paths.
class CustomIcons {
  CustomIcons._();

  // -- Navigation --

  /// Back arrow / navigate left
  static Widget arrowLeft({double size = IconSizes.medium, Color? color, bool primary = false}) {
    return _BaseIcon(
      size: size,
      color: color,
      primary: primary,
      pathBuilder: (canvas, paint, s) {
        final p = Path()
          ..moveTo(s * 0.65, s * 0.2)
          ..lineTo(s * 0.35, s * 0.5)
          ..lineTo(s * 0.65, s * 0.8);
        paint.strokeWidth = s * 0.1;
        paint.strokeCap = StrokeCap.round;
        paint.strokeJoin = StrokeJoin.round;
        canvas.drawPath(p, paint..style = PaintingStyle.stroke);
      },
    );
  }

  /// Forward arrow / navigate right
  static Widget arrowRight({double size = IconSizes.medium, Color? color, bool primary = false}) {
    return _BaseIcon(
      size: size,
      color: color,
      primary: primary,
      pathBuilder: (canvas, paint, s) {
        final p = Path()
          ..moveTo(s * 0.35, s * 0.2)
          ..lineTo(s * 0.65, s * 0.5)
          ..lineTo(s * 0.35, s * 0.8);
        paint.strokeWidth = s * 0.1;
        paint.strokeCap = StrokeCap.round;
        paint.strokeJoin = StrokeJoin.round;
        canvas.drawPath(p, paint..style = PaintingStyle.stroke);
      },
    );
  }

  /// Chevron down
  static Widget chevronDown({double size = IconSizes.medium, Color? color, bool primary = false}) {
    return _BaseIcon(
      size: size,
      color: color,
      primary: primary,
      pathBuilder: (canvas, paint, s) {
        final p = Path()
          ..moveTo(s * 0.25, s * 0.35)
          ..lineTo(s * 0.5, s * 0.65)
          ..lineTo(s * 0.75, s * 0.35);
        paint.strokeWidth = s * 0.1;
        paint.strokeCap = StrokeCap.round;
        paint.strokeJoin = StrokeJoin.round;
        canvas.drawPath(p, paint..style = PaintingStyle.stroke);
      },
    );
  }

  // -- Feature Icons --

  /// Code editor / file icon
  static Widget codeFile({double size = IconSizes.medium, Color? color, bool primary = false}) {
    return _BaseIcon(
      size: size,
      color: color,
      primary: primary,
      pathBuilder: (canvas, paint, s) {
        // File outline
        final path = Path()
          ..moveTo(s * 0.25, s * 0.15)
          ..lineTo(s * 0.55, s * 0.15)
          ..lineTo(s * 0.75, s * 0.35)
          ..lineTo(s * 0.75, s * 0.85)
          ..lineTo(s * 0.25, s * 0.85)
          ..close();
        paint.strokeWidth = s * 0.08;
        paint.strokeCap = StrokeCap.round;
        paint.strokeJoin = StrokeJoin.round;
        canvas.drawPath(path, paint..style = PaintingStyle.stroke);
        // Folded corner
        final fold = Path()
          ..moveTo(s * 0.55, s * 0.15)
          ..lineTo(s * 0.55, s * 0.35)
          ..lineTo(s * 0.75, s * 0.35);
        canvas.drawPath(fold, paint..style = PaintingStyle.stroke);
        // Code brackets
        final bracketPaint = Paint()
          ..color = paint.color
          ..strokeWidth = s * 0.07
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        // <
        canvas.drawLine(Offset(s * 0.37, s * 0.45), Offset(s * 0.30, s * 0.55), bracketPaint);
        canvas.drawLine(Offset(s * 0.30, s * 0.55), Offset(s * 0.37, s * 0.65), bracketPaint);
        // /
        canvas.drawLine(Offset(s * 0.42, s * 0.65), Offset(s * 0.48, s * 0.45), bracketPaint);
        // >
        canvas.drawLine(Offset(s * 0.53, s * 0.45), Offset(s * 0.60, s * 0.55), bracketPaint);
        canvas.drawLine(Offset(s * 0.60, s * 0.55), Offset(s * 0.53, s * 0.65), bracketPaint);
      },
    );
  }

  /// Terminal / command line icon
  static Widget terminal({double size = IconSizes.medium, Color? color, bool primary = false}) {
    return _BaseIcon(
      size: size,
      color: color,
      primary: primary,
      pathBuilder: (canvas, paint, s) {
        // Terminal window
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.1, s * 0.15, s * 0.8, s * 0.7),
          Radius.circular(s * 0.08),
        );
        paint.strokeWidth = s * 0.08;
        canvas.drawRRect(rect, paint..style = PaintingStyle.stroke);
        // Title bar dots
        final dotPaint = Paint()
          ..color = paint.color
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(s * 0.22, s * 0.27), s * 0.04, dotPaint);
        canvas.drawCircle(Offset(s * 0.32, s * 0.27), s * 0.04, dotPaint);
        canvas.drawCircle(Offset(s * 0.42, s * 0.27), s * 0.04, dotPaint);
        // Prompt symbol >
        final linePaint = Paint()
          ..color = paint.color
          ..strokeWidth = s * 0.07
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        canvas.drawLine(Offset(s * 0.25, s * 0.45), Offset(s * 0.30, s * 0.52), linePaint);
        canvas.drawLine(Offset(s * 0.30, s * 0.52), Offset(s * 0.25, s * 0.59), linePaint);
        // Cursor
        canvas.drawLine(Offset(s * 0.35, s * 0.52), Offset(s * 0.52, s * 0.52), linePaint);
      },
    );
  }

  /// Settings / gear icon (static)
  static Widget settings({double size = IconSizes.medium, Color? color, bool primary = false}) {
    return _BaseIcon(
      size: size,
      color: color,
      primary: primary,
      pathBuilder: (canvas, paint, s) {
        final center = Offset(s / 2, s / 2);
        final outerRadius = s * 0.38;
        final innerRadius = s * 0.28;
        final teeth = 8;
        final path = Path();
        for (int i = 0; i < teeth * 2; i++) {
          final angle = (i / (teeth * 2)) * 2 * pi - pi / 2;
          final radius = i % 2 == 0 ? outerRadius : innerRadius;
          final x = center.dx + cos(angle) * radius;
          final y = center.dy + sin(angle) * radius;
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
        paint.strokeWidth = s * 0.08;
        paint.strokeJoin = StrokeJoin.round;
        canvas.drawPath(path, paint..style = PaintingStyle.stroke);
        // Center circle
        canvas.drawCircle(center, s * 0.1, paint);
      },
    );
  }

  /// Settings gear with continuous rotation animation
  static Widget settingsAnimated({
    double size = IconSizes.medium,
    Color? color,
    bool primary = false,
    Duration duration = const Duration(seconds: 8),
  }) {
    return RotationAnimation(
      duration: duration,
      child: settings(size: size, color: color, primary: primary),
    );
  }

  /// Moon / dark mode icon
  static Widget moon({double size = IconSizes.medium, Color? color, bool primary = false}) {
    return _BaseIcon(
      size: size,
      color: color,
      primary: primary,
      pathBuilder: (canvas, paint, s) {
        final path = Path()
          ..moveTo(s * 0.58, s * 0.15)
          ..arcToPoint(
            Offset(s * 0.58, s * 0.85),
            radius: Radius.circular(s * 0.35),
            clockwise: false,
          )
          ..arcToPoint(
            Offset(s * 0.58, s * 0.15),
            radius: Radius.circular(s * 0.25),
            clockwise: true,
          )
          ..close();
        paint.strokeWidth = s * 0.08;
        paint.strokeCap = StrokeCap.round;
        canvas.drawPath(path, paint..style = PaintingStyle.fill);
      },
    );
  }

  /// Sun / light mode icon
  static Widget sun({double size = IconSizes.medium, Color? color, bool primary = false}) {
    return _BaseIcon(
      size: size,
      color: color,
      primary: primary,
      pathBuilder: (canvas, paint, s) {
        final center = Offset(s / 2, s / 2);
        // Center circle
        canvas.drawCircle(center, s * 0.18, paint..style = PaintingStyle.fill);
        // Rays
        final rayPaint = Paint()
          ..color = paint.color
          ..strokeWidth = s * 0.06
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        for (int i = 0; i < 8; i++) {
          final angle = (i / 8) * 2 * pi - pi / 2;
          final innerR = s * 0.26;
          final outerR = s * 0.38;
          canvas.drawLine(
            Offset(center.dx + cos(angle) * innerR, center.dy + sin(angle) * innerR),
            Offset(center.dx + cos(angle) * outerR, center.dy + sin(angle) * outerR),
            rayPaint,
          );
        }
      },
    );
  }

  /// Magic wand / theme toggle icon
  static Widget magicWand({double size = IconSizes.medium, Color? color, bool primary = false}) {
    return _BaseIcon(
      size: size,
      color: color,
      primary: primary,
      pathBuilder: (canvas, paint, s) {
        // Wand stick
        final linePaint = Paint()
          ..color = paint.color
          ..strokeWidth = s * 0.08
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        canvas.drawLine(
          Offset(s * 0.25, s * 0.75),
          Offset(s * 0.65, s * 0.25),
          linePaint,
        );
        // Wand star head
        canvas.drawCircle(Offset(s * 0.65, s * 0.25), s * 0.08, paint..style = PaintingStyle.fill);
        // Sparkles
        canvas.drawCircle(Offset(s * 0.75, s * 0.18), s * 0.04, paint);
        canvas.drawCircle(Offset(s * 0.72, s * 0.35), s * 0.03, paint);
      },
    );
  }

  /// Sparkles / animated background icon
  static Widget sparkles({double size = IconSizes.medium, Color? color, bool primary = false}) {
    return _BaseIcon(
      size: size,
      color: color,
      primary: primary,
      pathBuilder: (canvas, paint, s) {
        void drawSparkle(double cx, double cy, double r) {
          final path = Path()
            ..moveTo(cx, cy - r)
            ..lineTo(cx + r * 0.25, cy - r * 0.25)
            ..lineTo(cx + r, cy)
            ..lineTo(cx + r * 0.25, cy + r * 0.25)
            ..lineTo(cx, cy + r)
            ..lineTo(cx - r * 0.25, cy + r * 0.25)
            ..lineTo(cx - r, cy)
            ..lineTo(cx - r * 0.25, cy - r * 0.25)
            ..close();
          canvas.drawPath(path, paint..style = PaintingStyle.fill);
        }
        drawSparkle(s * 0.65, s * 0.25, s * 0.12);
        drawSparkle(s * 0.35, s * 0.35, s * 0.08);
        drawSparkle(s * 0.55, s * 0.6, s * 0.06);
      },
    );
  }

  /// System / device icon
  static Widget system({double size = IconSizes.medium, Color? color, bool primary = false}) {
    return _BaseIcon(
      size: size,
      color: color,
      primary: primary,
      pathBuilder: (canvas, paint, s) {
        // Monitor
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.1, s * 0.15, s * 0.8, s * 0.5),
          Radius.circular(s * 0.06),
        );
        paint.strokeWidth = s * 0.08;
        canvas.drawRRect(rect, paint..style = PaintingStyle.stroke);
        // Stand
        canvas.drawLine(
          Offset(s * 0.5, s * 0.65),
          Offset(s * 0.5, s * 0.78),
          paint..style = PaintingStyle.stroke,
        );
        // Base
        final baseRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.3, s * 0.76, s * 0.4, s * 0.06),
          Radius.circular(s * 0.03),
        );
        canvas.drawRRect(baseRect, paint);
        // Screen dot
        canvas.drawCircle(Offset(s * 0.5, s * 0.42), s * 0.04, paint..style = PaintingStyle.fill);
      },
    );
  }

  /// Home icon
  static Widget home({double size = IconSizes.medium, Color? color, bool primary = false}) {
    return _BaseIcon(
      size: size,
      color: color,
      primary: primary,
      pathBuilder: (canvas, paint, s) {
        final path = Path()
          ..moveTo(s * 0.5, s * 0.12)
          ..lineTo(s * 0.1, s * 0.48)
          ..lineTo(s * 0.2, s * 0.48)
          ..lineTo(s * 0.2, s * 0.85)
          ..lineTo(s * 0.42, s * 0.85)
          ..lineTo(s * 0.42, s * 0.62)
          ..lineTo(s * 0.58, s * 0.62)
          ..lineTo(s * 0.58, s * 0.85)
          ..lineTo(s * 0.8, s * 0.85)
          ..lineTo(s * 0.8, s * 0.48)
          ..lineTo(s * 0.9, s * 0.48)
          ..close();
        paint.strokeWidth = s * 0.08;
        paint.strokeJoin = StrokeJoin.round;
        paint.strokeCap = StrokeCap.round;
        canvas.drawPath(path, paint..style = PaintingStyle.stroke);
      },
    );
  }

  /// Search / magnifying glass icon
  static Widget search({double size = IconSizes.medium, Color? color, bool primary = false}) {
    return _BaseIcon(
      size: size,
      color: color,
      primary: primary,
      pathBuilder: (canvas, paint, s) {
        // Circle
        canvas.drawCircle(
          Offset(s * 0.42, s * 0.42),
          s * 0.22,
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.08,
        );
        // Handle
        canvas.drawLine(
          Offset(s * 0.57, s * 0.57),
          Offset(s * 0.78, s * 0.78),
          paint..strokeCap = StrokeCap.round,
        );
      },
    );
  }

  /// Folder icon
  static Widget folder({double size = IconSizes.medium, Color? color, bool primary = false}) {
    return _BaseIcon(
      size: size,
      color: color,
      primary: primary,
      pathBuilder: (canvas, paint, s) {
        final path = Path()
          ..moveTo(s * 0.1, s * 0.3)
          ..lineTo(s * 0.1, s * 0.78)
          ..lineTo(s * 0.9, s * 0.78)
          ..lineTo(s * 0.9, s * 0.3)
          ..lineTo(s * 0.55, s * 0.3)
          ..lineTo(s * 0.45, s * 0.22)
          ..lineTo(s * 0.1, s * 0.22)
          ..close();
        paint.strokeWidth = s * 0.08;
        paint.strokeJoin = StrokeJoin.round;
        canvas.drawPath(path, paint..style = PaintingStyle.stroke);
      },
    );
  }

  /// Git branch icon
  static Widget gitBranch({double size = IconSizes.medium, Color? color, bool primary = false}) {
    return _BaseIcon(
      size: size,
      color: color,
      primary: primary,
      pathBuilder: (canvas, paint, s) {
        final paintStyle = paint
          ..strokeWidth = s * 0.08
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        // Top circle
        canvas.drawCircle(Offset(s * 0.35, s * 0.25), s * 0.1, paintStyle);
        // Bottom circle
        canvas.drawCircle(Offset(s * 0.35, s * 0.75), s * 0.1, paintStyle);
        // Right circle
        canvas.drawCircle(Offset(s * 0.72, s * 0.55), s * 0.1, paintStyle);
        // Vertical line
        canvas.drawLine(Offset(s * 0.35, s * 0.35), Offset(s * 0.35, s * 0.65), paintStyle);
        // Horizontal line
        canvas.drawLine(Offset(s * 0.35, s * 0.45), Offset(s * 0.72, s * 0.55), paintStyle);
      },
    );
  }

  /// Bug / issue icon
  static Widget bug({double size = IconSizes.medium, Color? color, bool primary = false}) {
    return _BaseIcon(
      size: size,
      color: color,
      primary: primary,
      pathBuilder: (canvas, paint, s) {
        final p = paint..strokeWidth = s * 0.07;
        // Body
        canvas.drawOval(
          Rect.fromCenter(center: Offset(s * 0.5, s * 0.52), width: s * 0.22, height: s * 0.38),
          p..style = PaintingStyle.stroke,
        );
        // Head
        canvas.drawCircle(Offset(s * 0.5, s * 0.22), s * 0.1, p..style = PaintingStyle.stroke);
        // Antennae
        canvas.drawLine(Offset(s * 0.42, s * 0.16), Offset(s * 0.3, s * 0.08), p..strokeCap = StrokeCap.round);
        canvas.drawLine(Offset(s * 0.58, s * 0.16), Offset(s * 0.7, s * 0.08), p);
        // Legs
        canvas.drawLine(Offset(s * 0.35, s * 0.38), Offset(s * 0.2, s * 0.32), p);
        canvas.drawLine(Offset(s * 0.35, s * 0.52), Offset(s * 0.18, s * 0.52), p);
        canvas.drawLine(Offset(s * 0.35, s * 0.65), Offset(s * 0.2, s * 0.72), p);
        canvas.drawLine(Offset(s * 0.65, s * 0.38), Offset(s * 0.8, s * 0.32), p);
        canvas.drawLine(Offset(s * 0.65, s * 0.52), Offset(s * 0.82, s * 0.52), p);
        canvas.drawLine(Offset(s * 0.65, s * 0.65), Offset(s * 0.8, s * 0.72), p);
      },
    );
  }

  /// User / profile icon
  static Widget user({double size = IconSizes.medium, Color? color, bool primary = false}) {
    return _BaseIcon(
      size: size,
      color: color,
      primary: primary,
      pathBuilder: (canvas, paint, s) {
        // Head
        canvas.drawCircle(
          Offset(s * 0.5, s * 0.35),
          s * 0.18,
          paint..strokeWidth = s * 0.08..style = PaintingStyle.stroke,
        );
        // Shoulders
        final path = Path()
          ..moveTo(s * 0.15, s * 0.88)
          ..quadraticBezierTo(s * 0.5, s * 0.55, s * 0.85, s * 0.88);
        canvas.drawPath(
          path,
          paint..style = PaintingStyle.stroke..strokeCap = StrokeCap.round,
        );
      },
    );
  }

  /// Checkmark icon
  static Widget check({double size = IconSizes.medium, Color? color, bool primary = false}) {
    return _BaseIcon(
      size: size,
      color: color,
      primary: primary,
      pathBuilder: (canvas, paint, s) {
        final p = Path()
          ..moveTo(s * 0.2, s * 0.52)
          ..lineTo(s * 0.42, s * 0.75)
          ..lineTo(s * 0.8, s * 0.28);
        paint.strokeWidth = s * 0.12;
        paint.strokeCap = StrokeCap.round;
        paint.strokeJoin = StrokeJoin.round;
        canvas.drawPath(p, paint..style = PaintingStyle.stroke);
      },
    );
  }

  /// Plus / add icon
  static Widget plus({double size = IconSizes.medium, Color? color, bool primary = false}) {
    return _BaseIcon(
      size: size,
      color: color,
      primary: primary,
      pathBuilder: (canvas, paint, s) {
        final p = paint
          ..strokeWidth = s * 0.1
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        canvas.drawLine(Offset(s * 0.5, s * 0.2), Offset(s * 0.5, s * 0.8), p);
        canvas.drawLine(Offset(s * 0.2, s * 0.5), Offset(s * 0.8, s * 0.5), p);
      },
    );
  }

  /// Close / X icon
  static Widget close({double size = IconSizes.medium, Color? color, bool primary = false}) {
    return _BaseIcon(
      size: size,
      color: color,
      primary: primary,
      pathBuilder: (canvas, paint, s) {
        final p = paint
          ..strokeWidth = s * 0.1
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        canvas.drawLine(Offset(s * 0.25, s * 0.25), Offset(s * 0.75, s * 0.75), p);
        canvas.drawLine(Offset(s * 0.75, s * 0.25), Offset(s * 0.25, s * 0.75), p);
      },
    );
  }

  /// Info / details icon
  static Widget info({double size = IconSizes.medium, Color? color, bool primary = false}) {
    return _BaseIcon(
      size: size,
      color: color,
      primary: primary,
      pathBuilder: (canvas, paint, s) {
        // Circle
        canvas.drawCircle(
          Offset(s * 0.5, s * 0.5),
          s * 0.36,
          paint..strokeWidth = s * 0.08..style = PaintingStyle.stroke,
        );
        // Dot
        canvas.drawCircle(Offset(s * 0.5, s * 0.35), s * 0.05, paint..style = PaintingStyle.fill);
        // Line
        canvas.drawLine(
          Offset(s * 0.5, s * 0.48),
          Offset(s * 0.5, s * 0.72),
          paint..strokeWidth = s * 0.08..strokeCap = StrokeCap.round..style = PaintingStyle.stroke,
        );
      },
    );
  }

  /// Warning / alert icon
  static Widget warning({double size = IconSizes.medium, Color? color, bool primary = false}) {
    return _BaseIcon(
      size: size,
      color: color,
      primary: primary,
      pathBuilder: (canvas, paint, s) {
        // Triangle
        final path = Path()
          ..moveTo(s * 0.5, s * 0.1)
          ..lineTo(s * 0.9, s * 0.85)
          ..lineTo(s * 0.1, s * 0.85)
          ..close();
        paint.strokeWidth = s * 0.08;
        paint.strokeJoin = StrokeJoin.round;
        canvas.drawPath(path, paint..style = PaintingStyle.stroke);
        // Exclamation
        canvas.drawLine(
          Offset(s * 0.5, s * 0.38),
          Offset(s * 0.5, s * 0.62),
          paint..strokeCap = StrokeCap.round..style = PaintingStyle.stroke,
        );
        canvas.drawCircle(Offset(s * 0.5, s * 0.72), s * 0.05, paint..style = PaintingStyle.fill);
      },
    );
  }

  /// Trash / delete icon
  static Widget trash({double size = IconSizes.medium, Color? color, bool primary = false}) {
    return _BaseIcon(
      size: size,
      color: color,
      primary: primary,
      pathBuilder: (canvas, paint, s) {
        final p = paint..strokeWidth = s * 0.08;
        // Lid
        final lidRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.3, s * 0.15, s * 0.4, s * 0.08),
          Radius.circular(s * 0.02),
        );
        canvas.drawRRect(lidRect, p..style = PaintingStyle.stroke);
        // Handle
        canvas.drawLine(Offset(s * 0.38, s * 0.15), Offset(s * 0.38, s * 0.08), p..style = PaintingStyle.stroke);
        canvas.drawLine(Offset(s * 0.62, s * 0.15), Offset(s * 0.62, s * 0.08), p);
        canvas.drawLine(Offset(s * 0.38, s * 0.08), Offset(s * 0.62, s * 0.08), p);
        // Body
        final bodyRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.22, s * 0.25, s * 0.56, s * 0.62),
          Radius.circular(s * 0.06),
        );
        canvas.drawRRect(bodyRect, p);
        // Lines inside
        canvas.drawLine(Offset(s * 0.38, s * 0.4), Offset(s * 0.38, s * 0.72), p..strokeCap = StrokeCap.round);
        canvas.drawLine(Offset(s * 0.5, s * 0.4), Offset(s * 0.5, s * 0.72), p);
        canvas.drawLine(Offset(s * 0.62, s * 0.4), Offset(s * 0.62, s * 0.72), p);
      },
    );
  }

  /// Copy / duplicate icon
  static Widget copy({double size = IconSizes.medium, Color? color, bool primary = false}) {
    return _BaseIcon(
      size: size,
      color: color,
      primary: primary,
      pathBuilder: (canvas, paint, s) {
        final p = paint..strokeWidth = s * 0.08;
        // Back page
        final backRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.22, s * 0.12, s * 0.56, s * 0.62),
          Radius.circular(s * 0.06),
        );
        canvas.drawRRect(backRect, p..style = PaintingStyle.stroke);
        // Front page
        final frontRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.22, s * 0.25, s * 0.56, s * 0.62),
          Radius.circular(s * 0.06),
        );
        canvas.drawRRect(frontRect, p);
        // Lines
        final lineP = p..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
        canvas.drawLine(Offset(s * 0.32, s * 0.45), Offset(s * 0.68, s * 0.45), lineP);
        canvas.drawLine(Offset(s * 0.32, s * 0.58), Offset(s * 0.68, s * 0.58), lineP);
        canvas.drawLine(Offset(s * 0.32, s * 0.71), Offset(s * 0.55, s * 0.71), lineP);
      },
    );
  }

  /// Play / run icon
  static Widget play({double size = IconSizes.medium, Color? color, bool primary = false}) {
    return _BaseIcon(
      size: size,
      color: color,
      primary: primary,
      pathBuilder: (canvas, paint, s) {
        final path = Path()
          ..moveTo(s * 0.3, s * 0.15)
          ..lineTo(s * 0.8, s * 0.5)
          ..lineTo(s * 0.3, s * 0.85)
          ..close();
        canvas.drawPath(path, paint..style = PaintingStyle.fill);
      },
    );
  }

  /// Pause icon
  static Widget pause({double size = IconSizes.medium, Color? color, bool primary = false}) {
    return _BaseIcon(
      size: size,
      color: color,
      primary: primary,
      pathBuilder: (canvas, paint, s) {
        final p = paint..style = PaintingStyle.fill;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(s * 0.28, s * 0.15, s * 0.15, s * 0.7),
            Radius.circular(s * 0.03),
          ),
          p,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(s * 0.57, s * 0.15, s * 0.15, s * 0.7),
            Radius.circular(s * 0.03),
          ),
          p,
        );
      },
    );
  }

  /// Refresh / sync icon
  static Widget refresh({double size = IconSizes.medium, Color? color, bool primary = false}) {
    return RotationAnimation(
      duration: const Duration(seconds: 1),
      child: _BaseIcon(
        size: size,
        color: color,
        primary: primary,
        pathBuilder: (canvas, paint, s) {
          final p = paint..strokeWidth = s * 0.08..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
          final center = Offset(s * 0.5, s * 0.5);
          final radius = s * 0.28;
          // Arc
          final rect = Rect.fromCircle(center: center, radius: radius);
          canvas.drawArc(rect, -pi * 0.8, pi * 1.6, false, p);
          // Arrow head
          final arrowX = center.dx + cos(-pi * 0.8) * radius;
          final arrowY = center.dy + sin(-pi * 0.8) * radius;
          canvas.drawLine(Offset(arrowX, arrowY), Offset(arrowX + s * 0.06, arrowY - s * 0.08), p);
          canvas.drawLine(Offset(arrowX, arrowY), Offset(arrowX + s * 0.08, arrowY + s * 0.04), p);
        },
      ),
    );
  }

  /// Lock / secure icon
  static Widget lock({double size = IconSizes.medium, Color? color, bool primary = false}) {
    return _BaseIcon(
      size: size,
      color: color,
      primary: primary,
      pathBuilder: (canvas, paint, s) {
        final p = paint..strokeWidth = s * 0.08;
        // Shackle
        final arcPath = Path()
          ..moveTo(s * 0.3, s * 0.45)
          ..arcToPoint(Offset(s * 0.7, s * 0.45), radius: Radius.circular(s * 0.2), clockwise: false);
        canvas.drawPath(arcPath, p..style = PaintingStyle.stroke);
        // Body
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(s * 0.2, s * 0.42, s * 0.6, s * 0.45),
            Radius.circular(s * 0.08),
          ),
          p..style = PaintingStyle.stroke,
        );
        // Keyhole
        canvas.drawCircle(Offset(s * 0.5, s * 0.58), s * 0.05, p..style = PaintingStyle.fill);
        canvas.drawRect(
          Rect.fromLTWH(s * 0.45, s * 0.58, s * 0.1, s * 0.15),
          p..style = PaintingStyle.fill,
        );
      },
    );
  }

  /// Pulsing dot — used for "live" / "recording" / "active" indicators
  static Widget pulsingDot({
    double size = IconSizes.small,
    required Color color,
    Duration duration = AnimationDurations.pulseCycle,
  }) {
    return PulseDot(color: color, size: size, duration: duration);
  }

  /// Rotating gear — used for loading / processing states
  static Widget rotatingGear({
    double size = IconSizes.medium,
    Color? color,
    bool primary = false,
    Duration duration = const Duration(seconds: 3),
  }) {
    return settingsAnimated(size: size, color: color, primary: primary, duration: duration);
  }

  /// Pulsing notification bell
  static Widget notificationBell({
    double size = IconSizes.medium,
    Color? color,
    bool primary = false,
    bool hasNotification = false,
    Color notificationColor = Colors.red,
  }) {
    return Stack(
      children: [
        _BaseIcon(
          size: size,
          color: color,
          primary: primary,
          pathBuilder: (canvas, paint, s) {
            final p = paint..strokeWidth = s * 0.08;
            // Bell body
            final path = Path()
              ..moveTo(s * 0.2, s * 0.65)
              ..quadraticBezierTo(s * 0.15, s * 0.55, s * 0.25, s * 0.45)
              ..lineTo(s * 0.3, s * 0.35)
              ..quadraticBezierTo(s * 0.3, s * 0.12, s * 0.5, s * 0.12)
              ..quadraticBezierTo(s * 0.7, s * 0.12, s * 0.7, s * 0.35)
              ..lineTo(s * 0.75, s * 0.45)
              ..quadraticBezierTo(s * 0.85, s * 0.55, s * 0.8, s * 0.65)
              ..close();
            canvas.drawPath(path, p..style = PaintingStyle.stroke..strokeJoin = StrokeJoin.round);
            // Clapper
            canvas.drawLine(Offset(s * 0.35, s * 0.75), Offset(s * 0.65, s * 0.75), p..strokeCap = StrokeCap.round);
          },
        ),
        if (hasNotification)
          Positioned(
            top: 0,
            right: 0,
            child: PulseDot(color: notificationColor, size: size * 0.35),
          ),
      ],
    );
  }
}

// ============================================================
// SECTION 4: Base Icon Painter
// ============================================================

/// The foundation for all custom icons. Handles sizing, color
/// resolution, and painting the custom path.
class _BaseIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final bool primary;
  final void Function(Canvas canvas, Paint paint, double s) pathBuilder;

  const _BaseIcon({
    Key? key,
    required this.size,
    required this.color,
    required this.primary,
    required this.pathBuilder,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ??
        (primary
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant);

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _IconPainter(
          color: resolvedColor,
          pathBuilder: pathBuilder,
        ),
        size: Size(size, size),
      ),
    );
  }
}

class _IconPainter extends CustomPainter {
  final Color color;
  final void Function(Canvas canvas, Paint paint, double s) pathBuilder;

  _IconPainter({required this.color, required this.pathBuilder});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    pathBuilder(canvas, paint, size.shortestSide);
  }

  @override
  bool shouldRepaint(covariant _IconPainter old) => old.color != color;
}

// ============================================================
// SECTION 5: Animated Icon Button
// ============================================================

/// A tappable icon button that scales on press with haptic feedback.
class AnimatedIconButton extends StatefulWidget {
  final Widget icon;
  final VoidCallback onTap;
  final double size;
  final EdgeInsets padding;
  final Color? backgroundColor;
  final Color? hoverColor;
  final String? tooltip;

  const AnimatedIconButton({
    Key? key,
    required this.icon,
    required this.onTap,
    this.size = 44,
    this.padding = const EdgeInsets.all(8),
    this.backgroundColor,
    this.hoverColor,
    this.tooltip,
  }) : super(key: key);

  @override
  State<AnimatedIconButton> createState() => _AnimatedIconButtonState();
}

class _AnimatedIconButtonState extends State<AnimatedIconButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    HapticFeedback.lightImpact();
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = widget.backgroundColor ??
        theme.colorScheme.surfaceContainerHighest.withOpacity(0.5);
    final hoverBg = widget.hoverColor ??
        theme.colorScheme.primary.withOpacity(0.1);

    Widget button = AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 1.0 - _controller.value * 0.12;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: widget.size,
            height: widget.size,
            padding: widget.padding,
            decoration: BoxDecoration(
              color: _isHovered ? hoverBg : bg,
              borderRadius: BorderRadius.circular(widget.size * 0.28),
              border: Border.all(
                color: theme.colorScheme.outline.withOpacity(0.1),
              ),
            ),
            child: widget.icon,
          ),
        );
      },
    );

    button = GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: widget.onTap,
      child: button,
    );

    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: button,
    );
  }
}

// ============================================================
// SECTION 6: Adaptive Icon Wrapper
// ============================================================

/// Automatically selects the appropriate icon color based on
/// the active theme and widget context.
class AdaptiveIcon extends StatelessWidget {
  final IconData iconData;
  final double size;
  final bool primary;
  final bool muted;

  const AdaptiveIcon(
    this.iconData, {
    Key? key,
    this.size = IconSizes.medium,
    this.primary = false,
    this.muted = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    late Color color;
    if (primary) {
      color = theme.colorScheme.primary;
    } else if (muted) {
      color = theme.colorScheme.onSurfaceVariant.withOpacity(0.5);
    } else {
      color = theme.colorScheme.onSurfaceVariant;
    }
    return Icon(iconData, size: size, color: color);
  }
}

// ============================================================
// SECTION 7: Feature Icon Map
// ============================================================

/// Maps feature names to their corresponding icons.
/// Used by dynamic UI builders and navigation systems.
class FeatureIcons {
  FeatureIcons._();

  static Widget forFeature(String feature, {double size = IconSizes.medium}) {
    switch (feature.toLowerCase()) {
      case 'home':
      case 'dashboard':
        return CustomIcons.home(size: size);
      case 'editor':
      case 'code':
        return CustomIcons.codeFile(size: size);
      case 'terminal':
      case 'shell':
        return CustomIcons.terminal(size: size);
      case 'files':
      case 'explorer':
        return CustomIcons.folder(size: size);
      case 'search':
        return CustomIcons.search(size: size);
      case 'git':
      case 'source control':
        return CustomIcons.gitBranch(size: size);
      case 'debug':
      case 'issues':
        return CustomIcons.bug(size: size);
      case 'settings':
        return CustomIcons.settings(size: size);
      case 'user':
      case 'profile':
        return CustomIcons.user(size: size);
      case 'theme':
      case 'appearance':
        return CustomIcons.magicWand(size: size);
      default:
        return CustomIcons.info(size: size);
    }
  }
}
