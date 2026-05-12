// lib/widgets/waveform_visualizer.dart
//
// Custom waveform animation widget for voice input visualization.
// Renders animated vertical bars with smooth amplitude transitions
// using CustomPainter for 60fps performance.

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Waveform Data
// ─────────────────────────────────────────────────────────────────────────────

/// Immutable snapshot of waveform bar heights.
class WaveformSnapshot {
  /// Normalized heights (0.0 - 1.0) for each bar.
  final List<double> barHeights;

  /// Timestamp of this snapshot.
  final DateTime timestamp;

  const WaveformSnapshot({
    required this.barHeights,
    required this.timestamp,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Waveform Visualizer Widget
// ─────────────────────────────────────────────────────────────────────────────

/// Animated audio waveform visualization.
///
/// Renders vertical bars that animate smoothly in response to audio level
/// changes. Uses [CustomPainter] for high-performance 60fps rendering.
///
/// ```dart
/// WaveformVisualizer(
///   audioStream: voiceService.onAudioLevel,
///   barCount: 32,
///   height: 120,
/// )
/// ```
class WaveformVisualizer extends StatefulWidget {
  /// Stream of audio amplitude values (0.0 - 1.0).
  final Stream<double>? audioStream;

  /// Number of vertical bars to render.
  final int barCount;

  /// Height of the waveform area.
  final double height;

  /// Color gradient start (left bars).
  final Color? gradientStart;

  /// Color gradient end (right bars).
  final Color? gradientEnd;

  /// Width of each bar in logical pixels.
  final double barWidth;

  /// Spacing between bars.
  final double barSpacing;

  /// Smoothing factor for amplitude transitions (0.0 = instant, 1.0 = very smooth).
  final double smoothing;

  /// Whether the waveform should be mirrored vertically (symmetric bars).
  final bool symmetric;

  /// Border radius for bar caps.
  final double borderRadius;

  /// Whether to show a subtle glow effect on active bars.
  final bool glowEffect;

  /// Idle animation speed when no audio input.
  final double idleSpeed;

  const WaveformVisualizer({
    super.key,
    this.audioStream,
    this.barCount = 32,
    this.height = 120,
    this.gradientStart,
    this.gradientEnd,
    this.barWidth = 4,
    this.barSpacing = 3,
    this.smoothing = 0.25,
    this.symmetric = true,
    this.borderRadius = 2,
    this.glowEffect = true,
    this.idleSpeed = 1.0,
  });

  @override
  State<WaveformVisualizer> createState() => _WaveformVisualizerState();
}

class _WaveformVisualizerState extends State<WaveformVisualizer>
    with TickerProviderStateMixin {
  /// Current bar heights (target values from audio stream).
  late List<double> _targetHeights;

  /// Smoothed bar heights (animated display values).
  late List<double> _currentHeights;

  /// Previous bar heights for velocity calculation.
  late List<double> _previousHeights;

  /// Stream subscription for audio levels.
  StreamSubscription<double>? _audioSub;

  /// Idle animation controller.
  late AnimationController _idleController;

  /// Latest amplitude from audio stream.
  double _latestAmplitude = 0.0;

  /// Whether we're receiving audio data.
  bool _isActive = false;

  /// Inactivity timer to resume idle animation.
  Timer? _inactivityTimer;

  @override
  void initState() {
    super.initState();
    _initHeights();
    _initIdleAnimation();
    _subscribeToAudioStream();
  }

  void _initHeights() {
    _targetHeights = List.filled(widget.barCount, 0.05);
    _currentHeights = List.filled(widget.barCount, 0.05);
    _previousHeights = List.filled(widget.barCount, 0.05);
  }

  void _initIdleAnimation() {
    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _idleController.addListener(_onIdleTick);
  }

  void _subscribeToAudioStream() {
    if (widget.audioStream != null) {
      _audioSub = widget.audioStream!.listen(
        _onAudioLevel,
        onError: (_) => _isActive = false,
        onDone: () => _isActive = false,
      );
    }
  }

  @override
  void didUpdateWidget(WaveformVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.barCount != widget.barCount) {
      _initHeights();
    }

    if (oldWidget.audioStream != widget.audioStream) {
      _audioSub?.cancel();
      _subscribeToAudioStream();
    }

    if (oldWidget.idleSpeed != widget.idleSpeed) {
      _idleController.duration =
          Duration(milliseconds: (2000 / widget.idleSpeed).round());
      if (!_idleController.isAnimating) {
        _idleController.repeat();
      }
    }
  }

  /// Handle new audio amplitude from stream.
  void _onAudioLevel(double amplitude) {
    _latestAmplitude = amplitude;
    _isActive = true;

    // Reset inactivity timer.
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(milliseconds: 500), () {
      _isActive = false;
    });

    // Generate target heights with organic pattern.
    _updateTargetHeights(amplitude);
  }

  /// Update target heights based on amplitude with organic variation.
  void _updateTargetHeights(double amplitude) {
    final time = DateTime.now().millisecondsSinceEpoch * 0.003;
    final random = math.Random();

    for (int i = 0; i < widget.barCount; i++) {
      // Create a wave-like pattern centered on the middle bars.
      final barPosition = i / (widget.barCount - 1); // 0.0 to 1.0
      final centerDist = (barPosition - 0.5).abs() * 2.0; // 0.0 at center, 1.0 at edges

      // Multiple sine waves for organic feel.
      final wave1 = math.sin(time + barPosition * math.pi * 3);
      final wave2 = math.cos(time * 1.3 + barPosition * math.pi * 5);
      final wave3 = math.sin(time * 0.7 + i * 0.5);

      // Combine waves and scale by amplitude.
      final combinedWave = (wave1 * 0.5 + wave2 * 0.3 + wave3 * 0.2) / 1.0;

      // Bars in the center react more strongly.
      final centerBoost = 1.0 - (centerDist * 0.4);

      // Add some randomness.
      final noise = random.nextDouble() * 0.15 - 0.075;

      final height = (amplitude * centerBoost * (0.6 + 0.4 * combinedWave.abs()) + noise)
          .clamp(0.03, 1.0);

      _targetHeights[i] = height;
    }
  }

  /// Handle idle animation tick (when no audio input).
  void _onIdleTick() {
    if (!mounted) return;

    if (!_isActive) {
      // Gentle breathing animation when idle.
      final time = _idleController.value * math.pi * 2;
      for (int i = 0; i < widget.barCount; i++) {
        final barPosition = i / (widget.barCount - 1);
        final wave = math.sin(time + barPosition * math.pi * 2);
        _targetHeights[i] = (0.08 + 0.06 * wave.abs()).clamp(0.03, 0.2);
      }
    }

    // Apply smoothing interpolation.
    for (int i = 0; i < widget.barCount; i++) {
      _previousHeights[i] = _currentHeights[i];
      _currentHeights[i] = _lerp(
        _currentHeights[i],
        _targetHeights[i],
        widget.smoothing,
      );
    }

    setState(() {});
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _audioSub?.cancel();
    _idleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: CustomPaint(
        size: Size(double.infinity, widget.height),
        painter: _WaveformPainter(
          barHeights: _currentHeights,
          barWidth: widget.barWidth,
          barSpacing: widget.barSpacing,
          gradientStart: widget.gradientStart ?? AppTheme.primary,
          gradientEnd: widget.gradientEnd ?? AppTheme.accent,
          symmetric: widget.symmetric,
          borderRadius: widget.borderRadius,
          glowEffect: widget.glowEffect,
          isActive: _isActive,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Waveform Painter
// ─────────────────────────────────────────────────────────────────────────────

/// CustomPainter that renders the waveform bars.
class _WaveformPainter extends CustomPainter {
  final List<double> barHeights;
  final double barWidth;
  final double barSpacing;
  final Color gradientStart;
  final Color gradientEnd;
  final bool symmetric;
  final double borderRadius;
  final bool glowEffect;
  final bool isActive;

  _WaveformPainter({
    required this.barHeights,
    required this.barWidth,
    required this.barSpacing,
    required this.gradientStart,
    required this.gradientEnd,
    required this.symmetric,
    required this.borderRadius,
    required this.glowEffect,
    required this.isActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barCount = barHeights.length;
    final totalBarWidth = barWidth + barSpacing;
    final totalWidth = barCount * totalBarWidth - barSpacing;

    // Center the waveform horizontally.
    final startX = (size.width - totalWidth) / 2;
    final centerY = size.height / 2;

    for (int i = 0; i < barCount; i++) {
      final height = barHeights[i] * (size.height / 2);
      final x = startX + i * totalBarWidth;

      // Compute bar color via gradient interpolation.
      final t = i / (barCount - 1);
      final color = Color.lerp(gradientStart, gradientEnd, t)!;

      // Glow effect for active bars.
      if (glowEffect && isActive && barHeights[i] > 0.3) {
        final glowPaint = Paint()
          ..color = color.withOpacity(0.2 * barHeights[i])
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

        final glowRect = symmetric
            ? Rect.fromLTRB(x - 2, centerY - height - 4, x + barWidth + 4, centerY + height + 4)
            : RRect.fromLTRBR(
                x - 2,
                centerY - height * 2 - 4,
                x + barWidth + 4,
                centerY + 4,
                Radius.circular(borderRadius),
              );

        if (symmetric) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(glowRect as Rect, Radius.circular(borderRadius + 2)),
            glowPaint,
          );
        } else {
          canvas.drawRRect(glowRect as RRect, glowPaint);
        }
      }

      // Main bar.
      final paint = Paint()..color = color;

      if (symmetric) {
        // Mirrored bar (extends both up and down from center).
        final barRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, centerY - height, barWidth, height * 2),
          Radius.circular(borderRadius),
        );
        canvas.drawRRect(barRect, paint);

        // Subtle center highlight.
        final highlightPaint = Paint()
          ..color = Colors.white.withOpacity(0.15 * barHeights[i]);
        final highlightRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x + barWidth * 0.25, centerY - height * 0.5, barWidth * 0.5, height),
          Radius.circular(borderRadius * 0.5),
        );
        canvas.drawRRect(highlightRect, highlightPaint);
      } else {
        // Single bar (extends up from bottom).
        final barRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, centerY - height * 2, barWidth, height * 2),
          Radius.circular(borderRadius),
        );
        canvas.drawRRect(barRect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    // Always repaint since bar heights are constantly changing.
    return true;
  }

  @override
  bool shouldRebuildSemantics(covariant _WaveformPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Static Waveform (for non-animated display)
// ─────────────────────────────────────────────────────────────────────────────

/// A static waveform display that shows a pre-rendered waveform pattern.
/// Useful for showing a "voice wave" icon or placeholder.
class StaticWaveform extends StatelessWidget {
  final double height;
  final int barCount;
  final double barWidth;
  final double barSpacing;
  final Color color;
  final bool symmetric;

  const StaticWaveform({
    super.key,
    this.height = 40,
    this.barCount = 20,
    this.barWidth = 3,
    this.barSpacing = 2,
    this.color = AppTheme.primary,
    this.symmetric = true,
  });

  @override
  Widget build(BuildContext context) {
    // Generate a voice-like pattern.
    final heights = _generateVoicePattern(barCount);

    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size(double.infinity, height),
        painter: _WaveformPainter(
          barHeights: heights,
          barWidth: barWidth,
          barSpacing: barSpacing,
          gradientStart: color,
          gradientEnd: AppTheme.accent,
          symmetric: symmetric,
          borderRadius: 2,
          glowEffect: false,
          isActive: false,
        ),
      ),
    );
  }

  List<double> _generateVoicePattern(int count) {
    final random = math.Random(42); // Fixed seed for consistent pattern.
    return List.generate(count, (i) {
      final centerDist = (i / (count - 1) - 0.5).abs() * 2;
      final centerBoost = 1.0 - centerDist * 0.5;
      return (0.3 + random.nextDouble() * 0.5) * centerBoost;
    });
  }
}
