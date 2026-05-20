// ============================================================
// animated_background.dart — MobileCode Dynamic Backgrounds
// ============================================================
// Per-theme animated backgrounds rendered via CustomPainter:
// - DeepSpace: Floating star particles with parallax
// - Aurora: Gradient wave animation (sinusoidal bands)
// - MidnightForest: Firefly particles with organic movement
// - CyberSunset: Pulsing gradient orbs with trails
// - MonochromeGeek: Animated noise texture overlay
// ============================================================

import 'dart:math' show Random, pi, sin, cos, atan2, sqrt, Point;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/theme_manager.dart';

// ============================================================
// SECTION 1: Background Router Widget
// ============================================================

/// Routes to the correct animated background painter based on
/// the active [AppTheme]. Wraps any screen to provide a dynamic
/// animated backdrop that responds to the current theme.
class AnimatedBackground extends StatelessWidget {
  final Widget child;
  final AppTheme theme;
  final bool animate;

  const AnimatedBackground({
    Key? key,
    required this.child,
    required this.theme,
    this.animate = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Layer 1: Themed animated background
        _buildBackground(context),
        // Layer 2: Subtle vignette overlay for depth
        _buildVignette(),
        // Layer 3: Content
        child,
      ],
    );
  }

  Widget _buildBackground(BuildContext context) {
    switch (theme) {
      case AppTheme.deepSpace:
        return DeepSpaceParticles(animate: animate);
      case AppTheme.aurora:
        return AuroraWaves(animate: animate);
      case AppTheme.midnightForest:
        return MidnightFireflies(animate: animate);
      case AppTheme.cyberSunset:
        return CyberSunsetOrbs(animate: animate);
      case AppTheme.monochromeGeek:
        return MonochromeNoise(animate: animate);
      case AppTheme.claudeYellow:
        return const ThemedSoftGlowBackground(
          base: Color(0xFF19110A),
          primary: Color(0xFFD97706),
          accent: Color(0xFFFFB86B),
        );
      case AppTheme.codexBlue:
        return const ThemedSoftGlowBackground(
          base: Color(0xFF071326),
          primary: Color(0xFF2555FF),
          accent: Color(0xFF16B9C7),
        );
    }
  }

  Widget _buildVignette() {
    final baseColor = _baseColorForTheme(theme);
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.2,
            colors: [
              Colors.transparent,
              baseColor.withOpacity(0.6),
            ],
            stops: const [0.4, 1.0],
          ),
        ),
      ),
    );
  }

  Color _baseColorForTheme(AppTheme t) {
    switch (t) {
      case AppTheme.deepSpace:
        return const Color(0xFF030508);
      case AppTheme.aurora:
        return const Color(0xFF0A1628);
      case AppTheme.midnightForest:
        return const Color(0xFF0A1A0A);
      case AppTheme.cyberSunset:
        return const Color(0xFF0D0B2B);
      case AppTheme.monochromeGeek:
        return const Color(0xFF000000);
      case AppTheme.claudeYellow:
        return const Color(0xFF19110A);
      case AppTheme.codexBlue:
        return const Color(0xFF071326);
    }
  }
}

// ============================================================
// SECTION 1.5: Soft Brand Background — Lightweight themed glow
// ============================================================

class ThemedSoftGlowBackground extends StatelessWidget {
  final Color base;
  final Color primary;
  final Color accent;

  const ThemedSoftGlowBackground({
    Key? key,
    required this.base,
    required this.primary,
    required this.accent,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ThemedSoftGlowPainter(
        base: base,
        primary: primary,
        accent: accent,
      ),
      size: Size.infinite,
    );
  }
}

class _ThemedSoftGlowPainter extends CustomPainter {
  final Color base;
  final Color primary;
  final Color accent;

  const _ThemedSoftGlowPainter({
    required this.base,
    required this.primary,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            base,
            Color.lerp(base, primary, 0.16)!,
            Color.lerp(base, accent, 0.12)!,
          ],
        ).createShader(rect),
    );

    final glowPaint = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 70);
    canvas.drawCircle(
      Offset(size.width * 0.22, size.height * 0.24),
      size.shortestSide * 0.34,
      glowPaint..color = primary.withOpacity(0.12),
    );
    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.72),
      size.shortestSide * 0.28,
      glowPaint..color = accent.withOpacity(0.10),
    );

    final linePaint = Paint()
      ..color = accent.withOpacity(0.045)
      ..strokeWidth = 0.8;
    for (int i = 0; i < 8; i++) {
      final y = size.height * (0.16 + i * 0.11);
      canvas.drawLine(Offset(0, y), Offset(size.width, y + size.height * 0.04), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ThemedSoftGlowPainter old) =>
      old.base != base || old.primary != primary || old.accent != accent;
}

// ============================================================
// SECTION 2: DeepSpace — Floating Star Particles
// ============================================================

/// A starfield with multiple particle layers:
/// - Background distant stars (slow drift, small)
/// - Mid-layer stars (medium speed, twinkling)
/// - Foreground nebula wisps (parallax on pointer)
class DeepSpaceParticles extends StatefulWidget {
  final bool animate;
  const DeepSpaceParticles({Key? key, this.animate = true}) : super(key: key);

  @override
  State<DeepSpaceParticles> createState() => _DeepSpaceParticlesState();
}

class _DeepSpaceParticlesState extends State<DeepSpaceParticles>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<StarParticle> _particles = [];
  final Random _random = Random(42);

  @override
  void initState() {
    super.initState();
    _initParticles();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    );
    if (widget.animate) {
      _controller.repeat();
    }
  }

  void _initParticles() {
    // Background stars (small, slow)
    for (int i = 0; i < 80; i++) {
      _particles.add(StarParticle(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        size: 0.5 + _random.nextDouble() * 1.5,
        speed: 0.05 + _random.nextDouble() * 0.1,
        brightness: 0.3 + _random.nextDouble() * 0.4,
        twinkleSpeed: 0.5 + _random.nextDouble() * 2,
        twinklePhase: _random.nextDouble() * 2 * pi,
        layer: 0,
      ));
    }
    // Mid stars (medium)
    for (int i = 0; i < 40; i++) {
      _particles.add(StarParticle(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        size: 1.2 + _random.nextDouble() * 2,
        speed: 0.1 + _random.nextDouble() * 0.2,
        brightness: 0.5 + _random.nextDouble() * 0.5,
        twinkleSpeed: 1 + _random.nextDouble() * 3,
        twinklePhase: _random.nextDouble() * 2 * pi,
        layer: 1,
      ));
    }
    // Bright foreground stars
    for (int i = 0; i < 15; i++) {
      _particles.add(StarParticle(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        size: 2 + _random.nextDouble() * 3,
        speed: 0.2 + _random.nextDouble() * 0.3,
        brightness: 0.7 + _random.nextDouble() * 0.3,
        twinkleSpeed: 2 + _random.nextDouble() * 4,
        twinklePhase: _random.nextDouble() * 2 * pi,
        layer: 2,
        color: [
          const Color(0xFF7B2FF7),
          const Color(0xFF00D4AA),
          const Color(0xFF9D5CFF),
          const Color(0xFF33E5C0),
          Colors.white,
        ][_random.nextInt(5)],
      ));
    }
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
        return CustomPaint(
          painter: _DeepSpacePainter(
            progress: _controller.value,
            particles: _particles,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class StarParticle {
  double x, y;
  final double size;
  final double speed;
  final double brightness;
  final double twinkleSpeed;
  final double twinklePhase;
  final int layer;
  final Color? color;

  StarParticle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.brightness,
    required this.twinkleSpeed,
    required this.twinklePhase,
    required this.layer,
    this.color,
  });
}

class _DeepSpacePainter extends CustomPainter {
  final double progress;
  final List<StarParticle> particles;

  _DeepSpacePainter({required this.progress, required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    // Deep space gradient background
    final bgPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.3, -0.5),
        radius: 0.8,
        colors: [
          const Color(0xFF0A0E2A),
          const Color(0xFF030508),
          const Color(0xFF020204),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Subtle nebula glow
    final nebulaPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60)
      ..color = const Color(0xFF7B2FF7).withOpacity(0.06);
    canvas.drawCircle(
      Offset(size.width * 0.3, size.height * 0.25),
      size.width * 0.35,
      nebulaPaint,
    );
    final nebulaPaint2 = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 50)
      ..color = const Color(0xFF00D4AA).withOpacity(0.04);
    canvas.drawCircle(
      Offset(size.width * 0.7, size.height * 0.6),
      size.width * 0.25,
      nebulaPaint2,
    );

    // Draw particles
    for (final p in particles) {
      final driftX = (progress * p.speed) % 1.0;
      final drawX = ((p.x + driftX) % 1.0) * size.width;
      final drawY = p.y * size.height;
      final twinkle = sin(progress * p.twinkleSpeed * 2 * pi + p.twinklePhase);
      final alpha = (p.brightness * (0.6 + 0.4 * twinkle)).clamp(0.0, 1.0);

      final starPaint = Paint()
        ..color = (p.color ?? Colors.white).withOpacity(alpha)
        ..maskFilter = p.layer >= 2
            ? const MaskFilter.blur(BlurStyle.normal, 2)
            : null;

      canvas.drawCircle(Offset(drawX, drawY), p.size, starPaint);

      // Cross flare for bright stars
      if (p.layer >= 2 && p.color != null) {
        final flarePaint = Paint()
          ..color = p.color!.withOpacity(alpha * 0.3)
          ..strokeWidth = 0.5;
        canvas.drawLine(
          Offset(drawX - p.size * 4, drawY),
          Offset(drawX + p.size * 4, drawY),
          flarePaint,
        );
        canvas.drawLine(
          Offset(drawX, drawY - p.size * 4),
          Offset(drawX, drawY + p.size * 4),
          flarePaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DeepSpacePainter old) => true;
}

// ============================================================
// SECTION 3: Aurora — Gradient Wave Animation
// ============================================================

/// Northern-lights inspired animated gradient waves using
/// multiple overlapping sine bands with phase offsets.
class AuroraWaves extends StatefulWidget {
  final bool animate;
  const AuroraWaves({Key? key, this.animate = true}) : super(key: key);

  @override
  State<AuroraWaves> createState() => _AuroraWavesState();
}

class _AuroraWavesState extends State<AuroraWaves>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
    if (widget.animate) {
      _controller.repeat();
    }
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
        return CustomPaint(
          painter: _AuroraPainter(progress: _controller.value),
          size: Size.infinite,
        );
      },
    );
  }
}

class _AuroraPainter extends CustomPainter {
  final double progress;

  _AuroraPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    // Base dark teal background
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF0A1628),
          Color(0xFF0C1E30),
          Color(0xFF081020),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Aurora wave bands
    final bands = [
      _AuroraBand(
        baseY: 0.15,
        amplitude: 0.08,
        frequency: 2,
        phase: progress * 2 * pi,
        phase2: progress * 2 * pi * 0.7,
        colors: [const Color(0xFF00FF88), const Color(0xFF00CC6A)],
        opacity: 0.15,
        blur: 40,
      ),
      _AuroraBand(
        baseY: 0.35,
        amplitude: 0.1,
        frequency: 1.5,
        phase: progress * 2 * pi * 1.3 + 1.0,
        phase2: progress * 2 * pi * 0.9 + 2.0,
        colors: [const Color(0xFFFF6B9D), const Color(0xFFFF8FB0)],
        opacity: 0.12,
        blur: 50,
      ),
      _AuroraBand(
        baseY: 0.55,
        amplitude: 0.06,
        frequency: 2.5,
        phase: progress * 2 * pi * 0.8 + 2.5,
        phase2: progress * 2 * pi * 1.1 + 0.5,
        colors: [const Color(0xFF00FFAA), const Color(0xFF00DD99)],
        opacity: 0.1,
        blur: 35,
      ),
      _AuroraBand(
        baseY: 0.25,
        amplitude: 0.12,
        frequency: 1.2,
        phase: -progress * 2 * pi * 0.6 + 3.0,
        phase2: -progress * 2 * pi * 0.8 + 1.5,
        colors: [const Color(0xFFAA44FF), const Color(0xFF00FF88)],
        opacity: 0.08,
        blur: 55,
      ),
    ];

    for (final band in bands) {
      _drawAuroraBand(canvas, size, band);
    }

    // Subtle star dots
    final random = Random(7);
    final starPaint = Paint()
      ..color = Colors.white.withOpacity(0.3);
    for (int i = 0; i < 30; i++) {
      final sx = random.nextDouble() * size.width;
      final sy = random.nextDouble() * size.height * 0.5;
      final twinkle = sin(progress * 3 + i) * 0.5 + 0.5;
      canvas.drawCircle(
        Offset(sx, sy),
        0.8 * twinkle,
        starPaint..color = Colors.white.withOpacity(0.25 * twinkle),
      );
    }
  }

  void _drawAuroraBand(Canvas canvas, Size size, _AuroraBand band) {
    final path = Path();
    const steps = 100;
    double firstY = 0;

    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = t * size.width;
      final wave1 = sin(t * band.frequency * 2 * pi + band.phase);
      final wave2 = sin(t * band.frequency * 1.5 * 2 * pi + band.phase2);
      final y = (band.baseY + band.amplitude * (wave1 * 0.6 + wave2 * 0.4)) *
          size.height;
      if (i == 0) {
        path.moveTo(x, y);
        firstY = y;
      } else {
        path.lineTo(x, y);
      }
    }

    // Close the path at bottom to create filled region
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        band.colors[0].withOpacity(band.opacity),
        band.colors[1].withOpacity(band.opacity * 0.5),
        band.colors[1].withOpacity(0),
      ],
      stops: const [0.0, 0.3, 1.0],
    );

    final paint = Paint()
      ..shader = gradient.createShader(
        Rect.fromLTWH(0, firstY * 0.5, size.width, size.height),
      )
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, band.blur);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter old) => true;
}

class _AuroraBand {
  final double baseY;
  final double amplitude;
  final double frequency;
  final double phase;
  final double phase2;
  final List<Color> colors;
  final double opacity;
  final double blur;

  _AuroraBand({
    required this.baseY,
    required this.amplitude,
    required this.frequency,
    required this.phase,
    required this.phase2,
    required this.colors,
    required this.opacity,
    required this.blur,
  });
}

// ============================================================
// SECTION 4: MidnightForest — Floating Fireflies
// ============================================================

/// Organic firefly particles that drift with Perlin-like movement,
/// leaving faint trails. Colors: emerald + amber.
class MidnightFireflies extends StatefulWidget {
  final bool animate;
  const MidnightFireflies({Key? key, this.animate = true}) : super(key: key);

  @override
  State<MidnightFireflies> createState() => _MidnightFirefliesState();
}

class _MidnightFirefliesState extends State<MidnightFireflies>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<Firefly> _fireflies = [];
  final Random _random = Random(123);

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 50; i++) {
      _fireflies.add(Firefly(
        x: _random.nextDouble(),
        y: 0.2 + _random.nextDouble() * 0.7,
        size: 1.5 + _random.nextDouble() * 3,
        speedX: (_random.nextDouble() - 0.5) * 0.15,
        speedY: (_random.nextDouble() - 0.5) * 0.08,
        phase: _random.nextDouble() * 2 * pi,
        glowPhase: _random.nextDouble() * 2 * pi,
        glowSpeed: 1.5 + _random.nextDouble() * 3,
        color: [
          const Color(0xFF2ECC71),
          const Color(0xFFF39C12),
          const Color(0xFF52D687),
          const Color(0xFFF5B041),
          const Color(0xFF82E0AA),
        ][_random.nextInt(5)],
        trailLength: 3 + _random.nextInt(6),
      ));
    }
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );
    if (widget.animate) {
      _controller.repeat();
    }
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
        return CustomPaint(
          painter: _FireflyPainter(
            progress: _controller.value,
            fireflies: _fireflies,
            time: _controller.lastElapsedDuration?.inMilliseconds.toDouble() ??
                0,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class Firefly {
  double x, y;
  final double size;
  final double speedX;
  final double speedY;
  final double phase;
  final double glowPhase;
  final double glowSpeed;
  final Color color;
  final int trailLength;
  final List<Offset> trail = [];

  Firefly({
    required this.x,
    required this.y,
    required this.size,
    required this.speedX,
    required this.speedY,
    required this.phase,
    required this.glowPhase,
    required this.glowSpeed,
    required this.color,
    required this.trailLength,
  });
}

class _FireflyPainter extends CustomPainter {
  final double progress;
  final List<Firefly> fireflies;
  final double time;

  _FireflyPainter({
    required this.progress,
    required this.fireflies,
    required this.time,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Dark green background
    final bgPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.5, 0.8),
        radius: 1.2,
        colors: [
          const Color(0xFF0F3D0F),
          const Color(0xFF0A1A0A),
          const Color(0xFF060F06),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Subtle fog layers
    final fogPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80)
      ..color = const Color(0xFF1A3A1A).withOpacity(0.2);
    canvas.drawCircle(
      Offset(size.width * 0.2, size.height * 0.7),
      size.width * 0.4,
      fogPaint,
    );

    // Update and draw fireflies
    for (final f in fireflies) {
      // Organic movement using sine combinations
      final organicX = sin(progress * 2 * pi * 2 + f.phase) * 0.02;
      final organicY = cos(progress * 2 * pi * 1.5 + f.phase * 1.3) * 0.015;

      f.x += f.speedX * 0.01 + organicX * 0.01;
      f.y += f.speedY * 0.01 + organicY * 0.01;

      // Wrap around
      if (f.x < -0.05) f.x = 1.05;
      if (f.x > 1.05) f.x = -0.05;
      if (f.y < 0) f.y = 1.0;
      if (f.y > 1.0) f.y = 0;

      final drawX = f.x * size.width;
      final drawY = f.y * size.height;

      // Update trail
      f.trail.add(Offset(drawX, drawY));
      if (f.trail.length > f.trailLength) {
        f.trail.removeAt(0);
      }

      // Glow intensity (pulsing)
      final glowIntensity =
          (sin(progress * f.glowSpeed * 2 * pi + f.glowPhase) * 0.5 + 0.5);
      final alpha = 0.3 + glowIntensity * 0.7;

      // Draw trail
      if (f.trail.length > 1) {
        for (int i = 0; i < f.trail.length - 1; i++) {
          final trailAlpha = (i / f.trail.length) * alpha * 0.3;
          final trailPaint = Paint()
            ..color = f.color.withOpacity(trailAlpha)
            ..strokeWidth = f.size * (i / f.trail.length) * 0.5
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(f.trail[i], f.trail[i + 1], trailPaint);
        }
      }

      // Outer glow
      final glowPaint = Paint()
        ..color = f.color.withOpacity(alpha * 0.3)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, f.size * 3);
      canvas.drawCircle(Offset(drawX, drawY), f.size * 2, glowPaint);

      // Inner core
      final corePaint = Paint()
        ..color = f.color.withOpacity(alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, f.size * 0.5);
      canvas.drawCircle(Offset(drawX, drawY), f.size, corePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FireflyPainter old) => true;
}

// ============================================================
// SECTION 5: CyberSunset — Gradient Orb Movement
// ============================================================

/// Large, slowly drifting gradient orbs that overlap to create
/// warm sunset hues with a cyberpunk edge.
class CyberSunsetOrbs extends StatefulWidget {
  final bool animate;
  const CyberSunsetOrbs({Key? key, this.animate = true}) : super(key: key);

  @override
  State<CyberSunsetOrbs> createState() => _CyberSunsetOrbsState();
}

class _CyberSunsetOrbsState extends State<CyberSunsetOrbs>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
    if (widget.animate) {
      _controller.repeat();
    }
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
        return CustomPaint(
          painter: _CyberSunsetPainter(progress: _controller.value),
          size: Size.infinite,
        );
      },
    );
  }
}

class _CyberSunsetPainter extends CustomPainter {
  final double progress;

  _CyberSunsetPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    // Deep purple-blue base
    final bgPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.5, 0.3),
        radius: 1.0,
        colors: [
          const Color(0xFF1A1645),
          const Color(0xFF0D0B2B),
          const Color(0xFF08071E),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Orb definitions with movement paths
    final orbs = [
      // Large orange orb
      _DriftingOrb(
        baseX: 0.2,
        baseY: 0.4,
        radius: 0.35,
        driftAmpX: 0.15,
        driftAmpY: 0.1,
        driftFreqX: 1.0,
        driftFreqY: 0.7,
        phaseX: 0,
        phaseY: 1.5,
        color: const Color(0xFFFF7B54),
        opacity: 0.12,
        blur: 80,
      ),
      // Purple orb
      _DriftingOrb(
        baseX: 0.7,
        baseY: 0.3,
        radius: 0.3,
        driftAmpX: 0.12,
        driftAmpY: 0.15,
        driftFreqX: 0.8,
        driftFreqY: 1.1,
        phaseX: 2.0,
        phaseY: 0.5,
        color: const Color(0xFF9B59B6),
        opacity: 0.1,
        blur: 70,
      ),
      // Secondary orange
      _DriftingOrb(
        baseX: 0.5,
        baseY: 0.7,
        radius: 0.25,
        driftAmpX: 0.1,
        driftAmpY: 0.08,
        driftFreqX: 1.2,
        driftFreqY: 0.9,
        phaseX: 1.0,
        phaseY: 3.0,
        color: const Color(0xFFFF9D80),
        opacity: 0.08,
        blur: 60,
      ),
      // Accent magenta orb
      _DriftingOrb(
        baseX: 0.3,
        baseY: 0.6,
        radius: 0.18,
        driftAmpX: 0.2,
        driftAmpY: 0.12,
        driftFreqX: 0.6,
        driftFreqY: 0.5,
        phaseX: 3.5,
        phaseY: 2.0,
        color: const Color(0xFFE84393),
        opacity: 0.06,
        blur: 50,
      ),
      // Warm amber orb
      _DriftingOrb(
        baseX: 0.8,
        baseY: 0.6,
        radius: 0.2,
        driftAmpX: 0.08,
        driftAmpY: 0.18,
        driftFreqX: 1.5,
        driftFreqY: 1.0,
        phaseX: 4.0,
        phaseY: 0.0,
        color: const Color(0xFFFFA502),
        opacity: 0.07,
        blur: 55,
      ),
    ];

    // Draw orbs back-to-front
    for (final orb in orbs) {
      final ox = (orb.baseX +
              sin(progress * 2 * pi * orb.driftFreqX + orb.phaseX) *
                  orb.driftAmpX) *
          size.width;
      final oy = (orb.baseY +
              cos(progress * 2 * pi * orb.driftFreqY + orb.phaseY) *
                  orb.driftAmpY) *
          size.height;

      final orbPaint = Paint()
        ..color = orb.color.withOpacity(orb.opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, orb.blur);
      canvas.drawCircle(
        Offset(ox, oy),
        orb.radius * size.shortestSide,
        orbPaint,
      );
    }

    // Subtle grid overlay for cyber feel
    final gridPaint = Paint()
      ..color = const Color(0xFFFF7B54).withOpacity(0.03)
      ..strokeWidth = 0.5;
    final gridSpacing = size.width / 20;
    for (int i = 0; i < 20; i++) {
      final x = i * gridSpacing;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        gridPaint,
      );
    }
    for (int i = 0; i < 30; i++) {
      final y = i * (size.height / 30);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CyberSunsetPainter old) => true;
}

class _DriftingOrb {
  final double baseX;
  final double baseY;
  final double radius;
  final double driftAmpX;
  final double driftAmpY;
  final double driftFreqX;
  final double driftFreqY;
  final double phaseX;
  final double phaseY;
  final Color color;
  final double opacity;
  final double blur;

  _DriftingOrb({
    required this.baseX,
    required this.baseY,
    required this.radius,
    required this.driftAmpX,
    required this.driftAmpY,
    required this.driftFreqX,
    required this.driftFreqY,
    required this.phaseX,
    required this.phaseY,
    required this.color,
    required this.opacity,
    required this.blur,
  });
}

// ============================================================
// SECTION 6: MonochromeGeek — Subtle Noise Texture
// ============================================================

/// A nearly imperceptible animated noise field that gives the
/// pure-black background texture without visual distraction.
class MonochromeNoise extends StatefulWidget {
  final bool animate;
  const MonochromeNoise({Key? key, this.animate = true}) : super(key: key);

  @override
  State<MonochromeNoise> createState() => _MonochromeNoiseState();
}

class _MonochromeNoiseState extends State<MonochromeNoise>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<NoiseGrain> _grains = [];
  final Random _random = Random(999);

  @override
  void initState() {
    super.initState();
    // Generate static noise grains
    for (int i = 0; i < 200; i++) {
      _grains.add(NoiseGrain(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        brightness: 0.02 + _random.nextDouble() * 0.06,
        size: 0.5 + _random.nextDouble() * 1.5,
        phase: _random.nextDouble() * 2 * pi,
        speed: 0.3 + _random.nextDouble() * 1.5,
      ));
    }
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
    if (widget.animate) {
      _controller.repeat();
    }
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
        return CustomPaint(
          painter: _NoisePainter(
            progress: _controller.value,
            grains: _grains,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class NoiseGrain {
  final double x;
  final double y;
  final double brightness;
  final double size;
  final double phase;
  final double speed;

  NoiseGrain({
    required this.x,
    required this.y,
    required this.brightness,
    required this.size,
    required this.phase,
    required this.speed,
  });
}

class _NoisePainter extends CustomPainter {
  final double progress;
  final List<NoiseGrain> grains;

  _NoisePainter({required this.progress, required this.grains});

  @override
  void paint(Canvas canvas, Size size) {
    // Pure black base
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black,
    );

    // Noise grain field
    for (final grain in grains) {
      final flicker = sin(progress * grain.speed * 2 * pi + grain.phase);
      final alpha = grain.brightness * (0.5 + 0.5 * flicker);
      final brightness = (0.05 + alpha * 0.1).clamp(0.0, 0.15);

      final paint = Paint()
        ..color = Color.fromRGBO(
          (brightness * 255).toInt(),
          (brightness * 255).toInt(),
          (brightness * 255).toInt(),
          1.0,
        )
        ..strokeWidth = grain.size;
      canvas.drawPoints(
        PointMode.points,
        [Offset(grain.x * size.width, grain.y * size.height)],
        paint,
      );
    }

    // Subtle scan line effect
    final scanlinePaint = Paint()
      ..color = const Color(0xFFFFFFFF).withOpacity(0.02);
    final lineHeight = 2.0;
    final gap = 4.0;
    for (double y = 0; y < size.height; y += (lineHeight + gap)) {
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, lineHeight),
        scanlinePaint,
      );
    }

    // Very subtle CRT vignette
    final vignettePaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.0,
        colors: [
          Colors.transparent,
          const Color(0xFF000000).withOpacity(0.3),
        ],
        stops: const [0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Offset.zero & size, vignettePaint);
  }

  @override
  bool shouldRepaint(covariant _NoisePainter old) => true;
}

// ============================================================
// SECTION 7: Animated Gradient Container (utility)
// ============================================================

/// A reusable container that smoothly animates its gradient
/// background between two color sets.
class AnimatedGradientContainer extends StatefulWidget {
  final List<Color> colors;
  final List<Color> altColors;
  final List<double>? stops;
  final Alignment begin;
  final Alignment end;
  final Duration duration;
  final Widget? child;

  const AnimatedGradientContainer({
    Key? key,
    required this.colors,
    required this.altColors,
    this.stops,
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
    this.duration = const Duration(seconds: 6),
    this.child,
  }) : super(key: key);

  @override
  State<AnimatedGradientContainer> createState() =>
      _AnimatedGradientContainerState();
}

class _AnimatedGradientContainerState extends State<AnimatedGradientContainer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _blend;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _blend = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOutSine,
      ),
    );
    _controller.repeat(reverse: true);
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
        final blendedColors = List<Color>.generate(
          widget.colors.length,
          (i) => Color.lerp(widget.colors[i], widget.altColors[i], _blend.value)!,
        );
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: widget.begin,
              end: widget.end,
              colors: blendedColors,
              stops: widget.stops,
            ),
          ),
          child: widget.child,
        );
      },
    );
  }
}

// ============================================================
// SECTION 8: Particle Burst Effect (transient animation)
// ============================================================

/// A burst of particles that radiates from a point and fades.
/// Used for success feedback, button clicks, etc.
class ParticleBurst extends StatefulWidget {
  final Offset origin;
  final int particleCount;
  final Color color;
  final Duration duration;
  final VoidCallback? onComplete;

  const ParticleBurst({
    Key? key,
    required this.origin,
    this.particleCount = 20,
    required this.color,
    this.duration = const Duration(milliseconds: 800),
    this.onComplete,
  }) : super(key: key);

  @override
  State<ParticleBurst> createState() => _ParticleBurstState();
}

class _ParticleBurstState extends State<ParticleBurst>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<BurstParticle> _particles;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _particles = List.generate(widget.particleCount, (i) {
      final angle = _random.nextDouble() * 2 * pi;
      final speed = 50 + _random.nextDouble() * 150;
      return BurstParticle(
        angle: angle,
        speed: speed,
        size: 2 + _random.nextDouble() * 4,
        opacity: 0.6 + _random.nextDouble() * 0.4,
        decay: 0.5 + _random.nextDouble() * 0.5,
      );
    });
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _controller.forward().then((_) {
      widget.onComplete?.call();
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
        return CustomPaint(
          painter: _BurstPainter(
            progress: _controller.value,
            origin: widget.origin,
            particles: _particles,
            color: widget.color,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class BurstParticle {
  final double angle;
  final double speed;
  final double size;
  final double opacity;
  final double decay;

  BurstParticle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.opacity,
    required this.decay,
  });
}

class _BurstPainter extends CustomPainter {
  final double progress;
  final Offset origin;
  final List<BurstParticle> particles;
  final Color color;

  _BurstPainter({
    required this.progress,
    required this.origin,
    required this.particles,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final distance = p.speed * progress;
      final x = origin.dx + cos(p.angle) * distance;
      final y = origin.dy + sin(p.angle) * distance;
      final currentOpacity = p.opacity * (1 - progress) * p.decay;
      final currentSize = p.size * (1 - progress * 0.5);

      if (currentOpacity <= 0) continue;

      final paint = Paint()
        ..color = color.withOpacity(currentOpacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, currentSize);
      canvas.drawCircle(Offset(x, y), currentSize, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) => true;
}
