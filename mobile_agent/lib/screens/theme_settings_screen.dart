// ============================================================
// theme_settings_screen.dart — MobileCode Theme Settings
// ============================================================
// Complete theme selection UI with:
// - 5 theme cards with live preview miniatures
// - Animated transitions between theme selections
// - Color swatches and personality descriptions
// - Quick toggle in app bar
// - Persistent selection with visual feedback
// - Glassmorphism cards adapted to each theme
// ============================================================

import 'dart:math' show Random, sin, cos, pi;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme_manager.dart';
import '../core/animations.dart';
import '../widgets/animated_background.dart';
import '../widgets/custom_icons.dart';

// ============================================================
// SECTION 1: Main Settings Screen
// ============================================================

class ThemeSettingsScreen extends StatefulWidget {
  const ThemeSettingsScreen({Key? key}) : super(key: key);

  @override
  State<ThemeSettingsScreen> createState() => _ThemeSettingsScreenState();
}

class _ThemeSettingsScreenState extends State<ThemeSettingsScreen>
    with SingleTickerProviderStateMixin {
  late ThemeManager _themeManager;
  late AnimationController _transitionController;
  late Animation<double> _pageFadeAnim;
  late Animation<Offset> _pageSlideAnim;

  @override
  void initState() {
    super.initState();
    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pageFadeAnim = CurvedAnimation(
      parent: _transitionController,
      curve: Curves.easeOutCubic,
    );
    _pageSlideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _transitionController,
      curve: Curves.easeOutCubic,
    ));
    _transitionController.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _themeManager = ThemeProvider.of(context);
  }

  @override
  void dispose() {
    _transitionController.dispose();
    super.dispose();
  }

  void _onThemeChanged(AppTheme newTheme) {
    if (_themeManager.activeThemeId == newTheme) return;
    HapticFeedback.mediumImpact();
    _themeManager.setTheme(newTheme);
    _transitionController
        .reverse()
        .then((_) => _transitionController.forward());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mobileTheme = _themeManager.activeTheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: AnimatedBuilder(
        animation: _themeManager,
        builder: (context, child) {
          return AnimatedBackground(
            theme: _themeManager.activeThemeId,
            child: FadeTransition(
              opacity: _pageFadeAnim,
              child: SlideTransition(
                position: _pageSlideAnim,
                child: SafeArea(
                  child: CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      // App Bar
                      _buildAppBar(theme, mobileTheme),
                      // Current theme indicator
                      _buildCurrentThemeHeader(theme, mobileTheme),
                      // Theme cards grid
                      _buildThemeGrid(theme),
                      // Theme detail section
                      _buildThemeDetail(theme, mobileTheme),
                      // Settings
                      _buildSettingsSection(theme, mobileTheme),
                      const SliverToBoxAdapter(child: SizedBox(height: 40)),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // -- App Bar --
  Widget _buildAppBar(ThemeData theme, MobileTheme mobileTheme) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            // Back button
            _GlassIconButton(
              icon: CustomIcons.arrowLeft(size: 20),
              onTap: () => Navigator.of(context).pop(),
              mobileTheme: mobileTheme,
            ),
            const SizedBox(width: 16),
            // Title
            Expanded(
              child: SlideInAnimation(
                direction: AxisDirection.right,
                duration: const Duration(milliseconds: 400),
                child: Text(
                  'Appearance',
                  style: theme.textTheme.headlineMedium,
                ),
              ),
            ),
            // Quick theme toggle
            _GlassIconButton(
              icon: CustomIcons.magicWand(size: 20),
              onTap: () {
                HapticFeedback.mediumImpact();
                _themeManager.quickToggle();
              },
              mobileTheme: mobileTheme,
              tooltip: 'Quick cycle themes',
            ),
          ],
        ),
      ),
    );
  }

  // -- Current theme header --
  Widget _buildCurrentThemeHeader(ThemeData theme, MobileTheme mobileTheme) {
    final meta = _themeManager.activeThemeId;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: BounceInAnimation(
          duration: const Duration(milliseconds: 500),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: Glassmorphism.card(mobileTheme),
            child: Row(
              children: [
                // Theme emoji icon
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        meta.previewPrimary.withOpacity(0.3),
                        meta.previewSecondary.withOpacity(0.2),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: meta.previewPrimary.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      meta.emoji,
                      style: const TextStyle(fontSize: 28),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Theme info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meta.label,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        meta.description,
                        style: theme.textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Live indicator
                PulseAnimation(
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: meta.previewPrimary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: meta.previewPrimary.withOpacity(0.5),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -- Theme selection grid --
  Widget _buildThemeGrid(ThemeData theme) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.78,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final appTheme = AppTheme.values[index];
            final isActive = _themeManager.activeThemeId == appTheme;
            final meta = appTheme;

            return StaggeredItem(
              index: index,
              delay: Duration(milliseconds: 80 * index),
              duration: const Duration(milliseconds: 400),
              child: _ThemeCard(
                appTheme: appTheme,
                isActive: isActive,
                onTap: () => _onThemeChanged(appTheme),
              ),
            );
          },
          childCount: AppTheme.values.length,
        ),
      ),
    );
  }

  // -- Theme detail section --
  Widget _buildThemeDetail(ThemeData theme, MobileTheme mobileTheme) {
    final meta = _themeManager.activeThemeId;
    final colors = [
      meta.previewPrimary,
      meta.previewSecondary,
      ..._getThemeAccentColors(meta),
    ];

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
        child: StaggeredItem(
          index: 0,
          delay: const Duration(milliseconds: 300),
          duration: const Duration(milliseconds: 400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Color Palette',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              // Color swatches
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: colors.map((color) {
                  return _ColorSwatch(
                    color: color,
                    hex: '#${color.value.toRadixString(16).substring(2).toUpperCase()}',
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              // Personality traits
              Text(
                'Theme Personality',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              _buildPersonalityChips(theme, meta),
            ],
          ),
        ),
      ),
    );
  }

  // -- Personality chips --
  Widget _buildPersonalityChips(ThemeData theme, AppTheme meta) {
    final traits = _getPersonalityTraits(meta);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: traits.map((trait) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.colorScheme.outline.withOpacity(0.2),
            ),
          ),
          child: Text(
            trait,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );
      }).toList(),
    );
  }

  // -- Settings section --
  Widget _buildSettingsSection(ThemeData theme, MobileTheme mobileTheme) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Preferences',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            // Dark mode toggle
            _SettingTile(
              icon: CustomIcons.moon(size: 20, color: theme.colorScheme.primary),
              title: 'Dark Mode',
              subtitle: 'Always use dark interface',
              trailing: Switch(
                value: true,
                onChanged: (v) {},
              ),
              mobileTheme: mobileTheme,
            ),
            const SizedBox(height: 8),
            // Animated backgrounds toggle
            _SettingTile(
              icon: CustomIcons.sparkles(size: 20, color: theme.colorScheme.primary),
              title: 'Animated Backgrounds',
              subtitle: 'Show live animated backdrops',
              trailing: Switch(
                value: true,
                onChanged: (v) {},
              ),
              mobileTheme: mobileTheme,
            ),
            const SizedBox(height: 8),
            // Follow system toggle
            _SettingTile(
              icon: CustomIcons.system(size: 20, color: theme.colorScheme.primary),
              title: 'Follow System',
              subtitle: 'Match device theme settings',
              trailing: Switch(
                value: _themeManager.followSystem,
                onChanged: (v) => _themeManager.setFollowSystem(v),
              ),
              mobileTheme: mobileTheme,
            ),
          ],
        ),
      ),
    );
  }

  // -- Helpers --
  List<Color> _getThemeAccentColors(AppTheme theme) {
    switch (theme) {
      case AppTheme.deepSpace:
        return [
          const Color(0xFF7B2FF7),
          const Color(0xFF00D4AA),
          const Color(0xFF9D5CFF),
          const Color(0xFF33E5C0),
          const Color(0xFF0A0E17),
          const Color(0xFF0D1117),
        ];
      case AppTheme.aurora:
        return [
          const Color(0xFF00FF88),
          const Color(0xFFFF6B9D),
          const Color(0xFF33FFA0),
          const Color(0xFFFF8FB0),
          const Color(0xFF0E2236),
          const Color(0xFF0E1D2E),
        ];
      case AppTheme.midnightForest:
        return [
          const Color(0xFF2ECC71),
          const Color(0xFFF39C12),
          const Color(0xFF52D687),
          const Color(0xFFF5B041),
          const Color(0xFF0F240F),
          const Color(0xFF0D1F0D),
        ];
      case AppTheme.cyberSunset:
        return [
          const Color(0xFFFF7B54),
          const Color(0xFF9B59B6),
          const Color(0xFFFF9D80),
          const Color(0xFFB07DC9),
          const Color(0xFF12103A),
          const Color(0xFF110E34),
        ];
      case AppTheme.monochromeGeek:
        return [
          const Color(0xFFFFFFFF),
          const Color(0xFF888888),
          const Color(0xFFCCCCCC),
          const Color(0xFF666666),
          const Color(0xFF0A0A0A),
          const Color(0xFF080808),
        ];
      case AppTheme.claudeYellow:
        return [
          const Color(0xFFD97706),
          const Color(0xFFEF925B),
          const Color(0xFFFFB86B),
          const Color(0xFFFFC18C),
          const Color(0xFF24170C),
          const Color(0xFF3A250F),
        ];
      case AppTheme.codexBlue:
        return [
          const Color(0xFF2555FF),
          const Color(0xFF16B9C7),
          const Color(0xFF6EA8FF),
          const Color(0xFF6BE4EE),
          const Color(0xFF0B1B33),
          const Color(0xFF122A4D),
        ];
    }
  }

  List<String> _getPersonalityTraits(AppTheme theme) {
    switch (theme) {
      case AppTheme.deepSpace:
        return ['Cosmic', 'Mysterious', 'Focused', 'Technical', 'Dark'];
      case AppTheme.aurora:
        return ['Vibrant', 'Flowing', 'Creative', 'Ethereal', 'Dynamic'];
      case AppTheme.midnightForest:
        return ['Organic', 'Natural', 'Calm', 'Warm', 'Alive'];
      case AppTheme.cyberSunset:
        return ['Neon', 'Warm', 'Retro-futurism', 'Bold', 'Energetic'];
      case AppTheme.monochromeGeek:
        return ['Minimal', 'Pure', 'Distraction-free', 'Clean', 'Precise'];
      case AppTheme.claudeYellow:
        return ['Warm', 'Readable', 'Reflective', 'Editorial', 'Calm'];
      case AppTheme.codexBlue:
        return ['Focused', 'Technical', 'Clear', 'Precise', 'Release-ready'];
    }
  }
}

// ============================================================
// SECTION 2: Theme Card Widget
// ============================================================

/// An individual theme selection card with live preview miniature,
/// selection indicator, and glassmorphism styling.
class _ThemeCard extends StatefulWidget {
  final AppTheme appTheme;
  final bool isActive;
  final VoidCallback onTap;

  const _ThemeCard({
    Key? key,
    required this.appTheme,
    required this.isActive,
    required this.onTap,
  }) : super(key: key);

  @override
  State<_ThemeCard> createState() => _ThemeCardState();
}

class _ThemeCardState extends State<_ThemeCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _hoverController;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _hoverController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _hoverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.appTheme;
    final mobileTheme = MobileThemeFactory.get(widget.appTheme);

    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        onEnter: (_) {
          setState(() => _isHovered = true);
          _hoverController.forward();
        },
        onExit: (_) {
          setState(() => _isHovered = false);
          _hoverController.reverse();
        },
        child: AnimatedBuilder(
          animation: _hoverController,
          builder: (context, child) {
            final scale = 1.0 + _hoverController.value * 0.02;
            return Transform.scale(
              scale: scale,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      meta.previewPrimary.withOpacity(0.15),
                      meta.previewSecondary.withOpacity(0.08),
                    ],
                  ),
                  border: Border.all(
                    color: widget.isActive
                        ? meta.previewPrimary.withOpacity(0.7)
                        : _isHovered
                            ? meta.previewPrimary.withOpacity(0.4)
                            : meta.previewPrimary.withOpacity(0.15),
                    width: widget.isActive ? 2.5 : 1,
                  ),
                  boxShadow: [
                    if (widget.isActive)
                      BoxShadow(
                        color: meta.previewPrimary.withOpacity(0.3),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    if (_isHovered && !widget.isActive)
                      BoxShadow(
                        color: meta.previewPrimary.withOpacity(0.15),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    children: [
                      // Mini background preview
                      _MiniBackgroundPreview(theme: widget.appTheme),
                      // Content overlay
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              mobileTheme.themeData.scaffoldBackgroundColor
                                  .withOpacity(0.85),
                            ],
                            stops: const [0.3, 0.75],
                          ),
                        ),
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // Mini color bar
                            Row(
                              children: [
                                _MiniSwatch(color: meta.previewPrimary),
                                const SizedBox(width: 6),
                                _MiniSwatch(color: meta.previewSecondary),
                                const SizedBox(width: 6),
                                _MiniSwatch(
                                  color: meta.previewPrimary.withOpacity(0.5),
                                  isSmall: true,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            // Theme label
                            Text(
                              meta.label,
                              style: mobileTheme.themeData.textTheme
                                  .titleMedium
                                  ?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            // Emoji
                            Text(
                              meta.description,
                              style: mobileTheme.themeData.textTheme.bodySmall
                                  ?.copyWith(fontSize: 10),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      // Active checkmark
                      if (widget.isActive)
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: meta.previewPrimary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: meta.previewPrimary.withOpacity(0.5),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Miniature background preview for each theme card.
class _MiniBackgroundPreview extends StatelessWidget {
  final AppTheme theme;

  const _MiniBackgroundPreview({Key? key, required this.theme})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _getMiniGradientColors(theme),
        ),
      ),
      child: CustomPaint(
        painter: _MiniPreviewPainter(theme: theme),
        size: Size.infinite,
      ),
    );
  }

  List<Color> _getMiniGradientColors(AppTheme t) {
    switch (t) {
      case AppTheme.deepSpace:
        return [
          const Color(0xFF0A0E2A),
          const Color(0xFF030508),
        ];
      case AppTheme.aurora:
        return [
          const Color(0xFF0E1D2E),
          const Color(0xFF0A1628),
        ];
      case AppTheme.midnightForest:
        return [
          const Color(0xFF0D1F0D),
          const Color(0xFF0A1A0A),
        ];
      case AppTheme.cyberSunset:
        return [
          const Color(0xFF110E34),
          const Color(0xFF0D0B2B),
        ];
      case AppTheme.monochromeGeek:
        return [
          const Color(0xFF0A0A0A),
          const Color(0xFF000000),
        ];
      case AppTheme.claudeYellow:
        return [
          const Color(0xFF33200F),
          const Color(0xFF19110A),
        ];
      case AppTheme.codexBlue:
        return [
          const Color(0xFF102544),
          const Color(0xFF071326),
        ];
    }
  }
}

class _MiniPreviewPainter extends CustomPainter {
  final AppTheme theme;
  final Random _random = Random(7);

  _MiniPreviewPainter({required this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    switch (theme) {
      case AppTheme.deepSpace:
        _drawStars(canvas, size, const Color(0xFF7B2FF7), const Color(0xFF00D4AA));
        break;
      case AppTheme.aurora:
        _drawAuroraStrip(canvas, size, const Color(0xFF00FF88), const Color(0xFFFF6B9D));
        break;
      case AppTheme.midnightForest:
        _drawFireflies(canvas, size, const Color(0xFF2ECC71), const Color(0xFFF39C12));
        break;
      case AppTheme.cyberSunset:
        _drawOrbs(canvas, size, const Color(0xFFFF7B54), const Color(0xFF9B59B6));
        break;
      case AppTheme.monochromeGeek:
        _drawNoise(canvas, size);
        break;
      case AppTheme.claudeYellow:
        _drawOrbs(canvas, size, const Color(0xFFD97706), const Color(0xFFFFB86B));
        _drawFireflies(canvas, size, const Color(0xFFFFB86B), const Color(0xFFEF925B));
        break;
      case AppTheme.codexBlue:
        _drawAuroraStrip(canvas, size, const Color(0xFF2555FF), const Color(0xFF16B9C7));
        _drawStars(canvas, size, const Color(0xFF6EA8FF), const Color(0xFF16B9C7));
        break;
    }
  }

  void _drawStars(Canvas canvas, Size size, Color c1, Color c2) {
    for (int i = 0; i < 20; i++) {
      final x = _random.nextDouble() * size.width;
      final y = _random.nextDouble() * size.height;
      final s = 0.5 + _random.nextDouble() * 1.5;
      final color = [c1, c2, Colors.white][_random.nextInt(3)];
      canvas.drawCircle(
        Offset(x, y),
        s,
        Paint()
          ..color = color.withOpacity(0.4 + _random.nextDouble() * 0.4)
          ..maskFilter = s > 1 ? const MaskFilter.blur(BlurStyle.normal, 1) : null,
      );
    }
  }

  void _drawAuroraStrip(Canvas canvas, Size size, Color c1, Color c2) {
    final path = Path();
    path.moveTo(0, size.height * 0.6);
    for (int i = 0; i <= 20; i++) {
      final t = i / 20;
      final x = t * size.width;
      final y = size.height * 0.5 + sin(t * pi * 2) * size.height * 0.15;
      path.lineTo(x, y);
    }
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          colors: [c1.withOpacity(0.3), c2.withOpacity(0.15)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
  }

  void _drawFireflies(Canvas canvas, Size size, Color c1, Color c2) {
    for (int i = 0; i < 8; i++) {
      final x = _random.nextDouble() * size.width;
      final y = 0.3 + _random.nextDouble() * 0.6;
      final color = [c1, c2][_random.nextInt(2)];
      canvas.drawCircle(
        Offset(x, y * size.height),
        2 + _random.nextDouble(),
        Paint()
          ..color = color.withOpacity(0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
  }

  void _drawOrbs(Canvas canvas, Size size, Color c1, Color c2) {
    canvas.drawCircle(
      Offset(size.width * 0.3, size.height * 0.4),
      size.width * 0.25,
      Paint()
        ..color = c1.withOpacity(0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawCircle(
      Offset(size.width * 0.7, size.height * 0.5),
      size.width * 0.2,
      Paint()
        ..color = c2.withOpacity(0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
  }

  void _drawNoise(Canvas canvas, Size size) {
    final paint = Paint()..strokeWidth = 0.5;
    for (int i = 0; i < 30; i++) {
      final x = _random.nextDouble() * size.width;
      final y = _random.nextDouble() * size.height;
      final b = 0.03 + _random.nextDouble() * 0.05;
      canvas.drawPoints(
        PointMode.points,
        [Offset(x, y)],
        paint..color = Colors.white.withOpacity(b),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniPreviewPainter old) => false;
}

// ============================================================
// SECTION 3: Color Swatch Widget
// ============================================================

/// A color swatch with hex label used in the theme detail section.
class _ColorSwatch extends StatefulWidget {
  final Color color;
  final String hex;

  const _ColorSwatch({Key? key, required this.color, required this.hex})
      : super(key: key);

  @override
  State<_ColorSwatch> createState() => _ColorSwatchState();
}

class _ColorSwatchState extends State<_ColorSwatch>
    with SingleTickerProviderStateMixin {
  late AnimationController _tapController;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _tapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
  }

  @override
  void dispose() {
    _tapController.dispose();
    super.dispose();
  }

  void _onTap() {
    HapticFeedback.lightImpact();
    _tapController.forward().then((_) => _tapController.reverse());
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      child: AnimatedBuilder(
        animation: _tapController,
        builder: (context, child) {
          final scale = 1.0 - _tapController.value * 0.1;
          return Transform.scale(
            scale: scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: widget.color.computeLuminance() > 0.5
                          ? Colors.black.withOpacity(0.1)
                          : Colors.white.withOpacity(0.15),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.color.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: _copied
                      ? const Center(
                          child: Icon(Icons.check,
                              color: Colors.white, size: 18))
                      : null,
                ),
                const SizedBox(height: 6),
                Text(
                  _copied ? 'Copied!' : widget.hex,
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace',
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

// ============================================================
// SECTION 4: Glass Icon Button
// ============================================================

/// A compact icon button with glassmorphism styling.
class _GlassIconButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback onTap;
  final MobileTheme mobileTheme;
  final String? tooltip;

  const _GlassIconButton({
    Key? key,
    required this.icon,
    required this.onTap,
    required this.mobileTheme,
    this.tooltip,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: mobileTheme.cardGlassBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: mobileTheme.cardGlassBorder,
              width: 1,
            ),
          ),
          child: Center(child: icon),
        ),
      ),
    );
  }
}

// ============================================================
// SECTION 5: Setting Tile
// ============================================================

/// A settings list tile with glassmorphism background.
class _SettingTile extends StatelessWidget {
  final Widget icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final MobileTheme mobileTheme;

  const _SettingTile({
    Key? key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.mobileTheme,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(child: icon),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

// ============================================================
// SECTION 6: Mini Swatch Widget
// ============================================================

/// A small color dot used inside theme cards.
class _MiniSwatch extends StatelessWidget {
  final Color color;
  final bool isSmall;

  const _MiniSwatch({Key? key, required this.color, this.isSmall = false})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: isSmall ? 12 : 16,
      height: isSmall ? 12 : 16,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(isSmall ? 4 : 6),
        border: Border.all(
          color: color.computeLuminance() > 0.5
              ? Colors.black.withOpacity(0.1)
              : Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
    );
  }
}
