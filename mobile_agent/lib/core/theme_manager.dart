// ============================================================
// theme_manager.dart — MobileCode Complete Theme System
// ============================================================
// Defines 5 distinct themes: DeepSpace, Aurora, MidnightForest,
// CyberSunset, MonochromeGeek with full Material theming support,
// persistence, dynamic detection, and component-specific styles.
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:math' show Point;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================
// SECTION 1: Theme Enum & Metadata
// ============================================================

/// Unique identifier for each of the five available themes.
enum AppTheme {
  deepSpace,
  aurora,
  midnightForest,
  cyberSunset,
  monochromeGeek,
}

/// Per-theme personality: human-readable labels, descriptions,
/// and accent color previews used by the settings UI.
extension AppThemeMetadata on AppTheme {
  String get label {
    switch (this) {
      case AppTheme.deepSpace:
        return 'DeepSpace';
      case AppTheme.aurora:
        return 'Aurora';
      case AppTheme.midnightForest:
        return 'Midnight Forest';
      case AppTheme.cyberSunset:
        return 'Cyber Sunset';
      case AppTheme.monochromeGeek:
        return 'Monochrome Geek';
    }
  }

  String get description {
    switch (this) {
      case AppTheme.deepSpace:
        return 'Deep space exploration with violet nebulae and cyan starlight.';
      case AppTheme.aurora:
        return 'Northern lights dancing across a dark teal sky.';
      case AppTheme.midnightForest:
        return 'An emerald canopy glowing with amber fireflies at midnight.';
      case AppTheme.cyberSunset:
        return 'Neon-soaked sunset on a distant cyberpunk horizon.';
      case AppTheme.monochromeGeek:
        return 'Distraction-free monochrome for the focused developer.';
    }
  }

  String get emoji {
    switch (this) {
      case AppTheme.deepSpace:
        return '🌌';
      case AppTheme.aurora:
        return '🌈';
      case AppTheme.midnightForest:
        return '🌲';
      case AppTheme.cyberSunset:
        return '🌇';
      case AppTheme.monochromeGeek:
        return '🖥️';
    }
  }

  /// Primary accent color — used for quick preview swatches.
  Color get previewPrimary {
    switch (this) {
      case AppTheme.deepSpace:
        return const Color(0xFF7B2FF7);
      case AppTheme.aurora:
        return const Color(0xFF00FF88);
      case AppTheme.midnightForest:
        return const Color(0xFF2ECC71);
      case AppTheme.cyberSunset:
        return const Color(0xFFFF7B54);
      case AppTheme.monochromeGeek:
        return const Color(0xFFFFFFFF);
    }
  }

  /// Secondary accent color — used for preview swatches.
  Color get previewSecondary {
    switch (this) {
      case AppTheme.deepSpace:
        return const Color(0xFF00D4AA);
      case AppTheme.aurora:
        return const Color(0xFFFF6B9D);
      case AppTheme.midnightForest:
        return const Color(0xFFF39C12);
      case AppTheme.cyberSunset:
        return const Color(0xFF9B59B6);
      case AppTheme.monochromeGeek:
        return const Color(0xFF888888);
    }
  }
}

// ============================================================
// SECTION 2: Theme Constants — Raw Color Palettes
// ============================================================

/// Immutable color constants for the **DeepSpace** theme.
class _DeepSpaceColors {
  static const Color bgPrimary = Color(0xFF030508);
  static const Color bgSecondary = Color(0xFF0A0E17);
  static const Color bgTertiary = Color(0xFF111827);
  static const Color primary = Color(0xFF7B2FF7);
  static const Color primaryLight = Color(0xFF9D5CFF);
  static const Color primaryDark = Color(0xFF5A1DBF);
  static const Color accent = Color(0xFF00D4AA);
  static const Color accentLight = Color(0xFF33E5C0);
  static const Color accentDark = Color(0xFF00A884);
  static const Color textPrimary = Color(0xFFF0F0F5);
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color surface = Color(0xFF0D1117);
  static const Color surfaceLight = Color(0xFF161B22);
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color success = Color(0xFF10B981);
  static const Color glass = Color(0x0DFFFFFF);
}

/// Immutable color constants for the **Aurora** theme.
class _AuroraColors {
  static const Color bgPrimary = Color(0xFF0A1628);
  static const Color bgSecondary = Color(0xFF0E2236);
  static const Color bgTertiary = Color(0xFF142D44);
  static const Color primary = Color(0xFF00FF88);
  static const Color primaryLight = Color(0xFF33FFA0);
  static const Color primaryDark = Color(0xFF00CC6A);
  static const Color accent = Color(0xFFFF6B9D);
  static const Color accentLight = Color(0xFFFF8FB0);
  static const Color accentDark = Color(0xFFE0558A);
  static const Color textPrimary = Color(0xFFE8F4F0);
  static const Color textSecondary = Color(0xFF9DB8B0);
  static const Color textMuted = Color(0xFF6B8A80);
  static const Color surface = Color(0xFF0E1D2E);
  static const Color surfaceLight = Color(0xFF162D3F);
  static const Color error = Color(0xFFFF5555);
  static const Color warning = Color(0xFFFFBB33);
  static const Color success = Color(0xFF00FF88);
  static const Color glass = Color(0x1200FF88);
}

/// Immutable color constants for the **MidnightForest** theme.
class _MidnightForestColors {
  static const Color bgPrimary = Color(0xFF0A1A0A);
  static const Color bgSecondary = Color(0xFF0F240F);
  static const Color bgTertiary = Color(0xFF162E16);
  static const Color primary = Color(0xFF2ECC71);
  static const Color primaryLight = Color(0xFF52D687);
  static const Color primaryDark = Color(0xFF25A55A);
  static const Color accent = Color(0xFFF39C12);
  static const Color accentLight = Color(0xFFF5B041);
  static const Color accentDark = Color(0xFFD68910);
  static const Color textPrimary = Color(0xFFF2F8F0);
  static const Color textSecondary = Color(0xFFA8C4A0);
  static const Color textMuted = Color(0xFF708C68);
  static const Color surface = Color(0xFF0D1F0D);
  static const Color surfaceLight = Color(0xFF142B14);
  static const Color error = Color(0xFFE74C3C);
  static const Color warning = Color(0xFFF39C12);
  static const Color success = Color(0xFF2ECC71);
  static const Color glass = Color(0x102ECC71);
}

/// Immutable color constants for the **CyberSunset** theme.
class _CyberSunsetColors {
  static const Color bgPrimary = Color(0xFF0D0B2B);
  static const Color bgSecondary = Color(0xFF12103A);
  static const Color bgTertiary = Color(0xFF1A1648);
  static const Color primary = Color(0xFFFF7B54);
  static const Color primaryLight = Color(0xFFFF9D80);
  static const Color primaryDark = Color(0xFFE06040);
  static const Color accent = Color(0xFF9B59B6);
  static const Color accentLight = Color(0xFFB07DC9);
  static const Color accentDark = Color(0xFF7D3C98);
  static const Color textPrimary = Color(0xFFFFF0EB);
  static const Color textSecondary = Color(0xFFD4AFA8);
  static const Color textMuted = Color(0xFF9A7880);
  static const Color surface = Color(0xFF110E34);
  static const Color surfaceLight = Color(0xFF1A1645);
  static const Color error = Color(0xFFFF4757);
  static const Color warning = Color(0xFFFFA502);
  static const Color success = Color(0xFF2ED573);
  static const Color glass = Color(0x15FF7B54);
}

/// Immutable color constants for the **MonochromeGeek** theme.
class _MonochromeGeekColors {
  static const Color bgPrimary = Color(0xFF000000);
  static const Color bgSecondary = Color(0xFF0A0A0A);
  static const Color bgTertiary = Color(0xFF111111);
  static const Color primary = Color(0xFFFFFFFF);
  static const Color primaryLight = Color(0xFFF5F5F5);
  static const Color primaryDark = Color(0xFFCCCCCC);
  static const Color accent = Color(0xFF888888);
  static const Color accentLight = Color(0xFFAAAAAA);
  static const Color accentDark = Color(0xFF666666);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFAAAAAA);
  static const Color textMuted = Color(0xFF666666);
  static const Color surface = Color(0xFF080808);
  static const Color surfaceLight = Color(0xFF141414);
  static const Color error = Color(0xFFFF4444);
  static const Color warning = Color(0xFFFFBB33);
  static const Color success = Color(0xFF33CC33);
  static const Color glass = Color(0x10FFFFFF);
}

// ============================================================
// SECTION 3: MobileTheme — Aggregated Theme Data Object
// ============================================================

/// A richer theme container that bundles:
/// - Material [ColorScheme] & [ThemeData]
/// - Custom component colors (editor, terminal, cards)
/// - Animation configuration per theme
/// - Glassmorphism parameters
@immutable
class MobileTheme {
  final AppTheme id;
  final String name;
  final ColorScheme colorScheme;
  final ThemeData themeData;

  // -- Custom component colors --
  final Color editorBackground;
  final Color editorLineHighlight;
  final Color terminalBackground;
  final Color terminalText;
  final Color cardGlassBackground;
  final Color cardGlassBorder;
  final Color sidebarBackground;
  final Color statusBarBackground;
  final Color toolbarBackground;
  final Color dividerColor;

  // -- Glassmorphism --
  final double glassOpacity;
  final double glassBlur;
  final Color glassOverlayColor;
  final Color glassBorderColor;

  // -- Animation personality --
  final Duration transitionDuration;
  final Curve transitionCurve;
  final Duration microAnimationDuration;
  final Curve microAnimationCurve;
  final Curve bounceCurve;
  final Duration staggerDelay;

  const MobileTheme({
    required this.id,
    required this.name,
    required this.colorScheme,
    required this.themeData,
    required this.editorBackground,
    required this.editorLineHighlight,
    required this.terminalBackground,
    required this.terminalText,
    required this.cardGlassBackground,
    required this.cardGlassBorder,
    required this.sidebarBackground,
    required this.statusBarBackground,
    required this.toolbarBackground,
    required this.dividerColor,
    required this.glassOpacity,
    required this.glassBlur,
    required this.glassOverlayColor,
    required this.glassBorderColor,
    required this.transitionDuration,
    required this.transitionCurve,
    required this.microAnimationDuration,
    required this.microAnimationCurve,
    required this.bounceCurve,
    required this.staggerDelay,
  });
}

// ============================================================
// SECTION 4: Theme Builder — Material ThemeData Factory
// ============================================================

class _ThemeBuilder {
  /// Creates a complete [MobileTheme] for a given raw palette and metadata.
  static MobileTheme build({
    required AppTheme id,
    required String name,
    required Color bgPrimary,
    required Color bgSecondary,
    required Color bgTertiary,
    required Color primary,
    required Color primaryLight,
    required Color primaryDark,
    required Color accent,
    required Color accentLight,
    required Color accentDark,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
    required Color surface,
    required Color surfaceLight,
    required Color error,
    required Color warning,
    required Color success,
    required Color glassBase,
    required Duration transitionDuration,
    required Curve transitionCurve,
    required Duration microDuration,
    required Curve microCurve,
  }) {
    final brightness = Brightness.dark;

    // -- Material ColorScheme --
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: _contrastColor(primary),
      primaryContainer: primaryDark.withOpacity(0.3),
      onPrimaryContainer: primaryLight,
      secondary: accent,
      onSecondary: _contrastColor(accent),
      secondaryContainer: accentDark.withOpacity(0.25),
      onSecondaryContainer: accentLight,
      tertiary: _lerpColor(primary, accent, 0.5),
      onTertiary: textPrimary,
      tertiaryContainer: bgTertiary,
      onTertiaryContainer: textSecondary,
      error: error,
      onError: Colors.white,
      errorContainer: error.withOpacity(0.15),
      onErrorContainer: error.withLightness(+0.2),
      surface: surface,
      onSurface: textPrimary,
      surfaceContainerHighest: surfaceLight,
      onSurfaceVariant: textSecondary,
      outline: textMuted.withOpacity(0.3),
      outlineVariant: textMuted.withOpacity(0.15),
      shadow: Colors.black.withOpacity(0.5),
      scrim: Colors.black.withOpacity(0.7),
      inverseSurface: textPrimary,
      onInverseSurface: bgPrimary,
      inversePrimary: primaryLight,
    );

    // -- TextTheme — uses Inter-style metrics (assumed font) --
    final textTheme = TextTheme(
      displayLarge: TextStyle(
        fontSize: 48,
        fontWeight: FontWeight.w800,
        color: textPrimary,
        letterSpacing: -1.5,
      ),
      displayMedium: TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        letterSpacing: -1.0,
      ),
      displaySmall: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        letterSpacing: -0.5,
      ),
      headlineLarge: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        letterSpacing: -0.5,
      ),
      headlineMedium: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: textPrimary,
        letterSpacing: -0.3,
      ),
      headlineSmall: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      titleSmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: textSecondary,
        letterSpacing: 0.5,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: textPrimary,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: textPrimary,
        height: 1.4,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: textSecondary,
        height: 1.3,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: textPrimary,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: textSecondary,
      ),
      labelSmall: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: textMuted,
        letterSpacing: 0.5,
      ),
    );

    // -- Component Themes --
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: textMuted.withOpacity(0.2)),
    );

    final themeData = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bgPrimary,
      canvasColor: bgSecondary,
      cardColor: surface,
      dividerColor: textMuted.withOpacity(0.15),
      shadowColor: Colors.black.withOpacity(0.4),
      textTheme: textTheme,
      fontFamily: 'Inter',
      // -- AppBar --
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: bgSecondary.withOpacity(0.85),
        foregroundColor: textPrimary,
        centerTitle: true,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
      ),
      // -- Card --
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
      ),
      // -- ElevatedButton --
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: primary,
          foregroundColor: _contrastColor(primary),
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      // -- OutlinedButton --
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          side: BorderSide(color: primary.withOpacity(0.5), width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      // -- TextButton --
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(48, 40),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      // -- InputDecoration --
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: error, width: 1.5),
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(color: textMuted),
        labelStyle: textTheme.bodyMedium?.copyWith(color: textSecondary),
      ),
      // -- Bottom Navigation --
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: bgSecondary.withOpacity(0.9),
        selectedItemColor: primary,
        unselectedItemColor: textMuted,
        selectedLabelStyle: textTheme.labelSmall,
        unselectedLabelStyle: textTheme.labelSmall,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        showSelectedLabels: true,
        showUnselectedLabels: true,
      ),
      // -- BottomSheet --
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: bgSecondary,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        clipBehavior: Clip.antiAlias,
        elevation: 8,
      ),
      // -- Dialog --
      dialogTheme: DialogTheme(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium,
        elevation: 4,
      ),
      // -- Chip --
      chipTheme: ChipThemeData(
        backgroundColor: surfaceLight,
        selectedColor: primary.withOpacity(0.2),
        labelStyle: textTheme.labelMedium,
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(color: primary),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide.none,
      ),
      // -- TabBar --
      tabBarTheme: TabBarTheme(
        labelColor: primary,
        unselectedLabelColor: textMuted,
        indicatorColor: primary,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: textTheme.labelLarge,
        dividerColor: Colors.transparent,
      ),
      // -- Switch --
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary;
          return textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primary.withOpacity(0.35);
          }
          return textMuted.withOpacity(0.2);
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      // -- Slider --
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        inactiveTrackColor: textMuted.withOpacity(0.2),
        thumbColor: primaryLight,
        overlayColor: primary.withOpacity(0.1),
        trackHeight: 4,
      ),
      // -- ProgressIndicator --
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: textMuted.withOpacity(0.15),
        circularTrackColor: textMuted.withOpacity(0.15),
      ),
      // -- Snackbar --
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceLight,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
        elevation: 2,
      ),
      // -- Tooltip --
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: surfaceLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: textMuted.withOpacity(0.15)),
        ),
        textStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        preferBelow: true,
      ),
      // -- Divider --
      dividerTheme: DividerThemeData(
        color: textMuted.withOpacity(0.12),
        thickness: 1,
        space: 1,
      ),
      // -- ListTile --
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        minLeadingWidth: 36,
        iconColor: textSecondary,
        textColor: textPrimary,
        selectedColor: primary,
        selectedTileColor: primary.withOpacity(0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      // -- FloatingActionButton --
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: _contrastColor(primary),
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      // -- PopupMenu --
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 4,
        textStyle: textTheme.bodyMedium,
      ),
    );

    return MobileTheme(
      id: id,
      name: name,
      colorScheme: colorScheme,
      themeData: themeData,
      // Editor
      editorBackground: bgSecondary,
      editorLineHighlight: primary.withOpacity(0.06),
      // Terminal
      terminalBackground: Color(0xFF0C0C0C) == bgPrimary ? bgSecondary : bgPrimary,
      terminalText: textPrimary,
      // Glassmorphism card
      cardGlassBackground: glassBase.withOpacity(0.08),
      cardGlassBorder: glassBase.withOpacity(0.15),
      // Sidebar
      sidebarBackground: bgSecondary.withOpacity(0.9),
      // Status bar
      statusBarBackground: bgSecondary,
      // Toolbar
      toolbarBackground: surfaceLight.withOpacity(0.8),
      // Divider
      dividerColor: textMuted.withOpacity(0.12),
      // Glassmorphism params
      glassOpacity: 0.08,
      glassBlur: 20,
      glassOverlayColor: glassBase.withOpacity(0.06),
      glassBorderColor: glassBase.withOpacity(0.2),
      // Animation personality
      transitionDuration: transitionDuration,
      transitionCurve: transitionCurve,
      microAnimationDuration: microDuration,
      microAnimationCurve: microCurve,
      bounceCurve: Curves.elasticOut,
      staggerDelay: const Duration(milliseconds: 40),
    );
  }

  // -- Helpers --
  static Color _contrastColor(Color color) {
    final luminance = color.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  static Color _lerpColor(Color a, Color b, double t) {
    return Color.lerp(a, b, t) ?? a;
  }
}

// -- Extension for lightness adjustment --
extension _ColorExt on Color {
  Color withLightness(double delta) {
    final hsl = HSLColor.fromColor(this);
    return hsl
        .withLightness((hsl.lightness + delta).clamp(0.0, 1.0))
        .toColor();
  }
}

// ============================================================
// SECTION 5: Theme Factory — Instantiate All 5 Themes
// ============================================================

class MobileThemeFactory {
  static final Map<AppTheme, MobileTheme> _cache = {};

  static MobileTheme get(AppTheme id) {
    if (_cache.containsKey(id)) return _cache[id]!;
    final theme = _build(id);
    _cache[id] = theme;
    return theme;
  }

  static MobileTheme _build(AppTheme id) {
    switch (id) {
      case AppTheme.deepSpace:
        return _ThemeBuilder.build(
          id: id,
          name: 'DeepSpace',
          bgPrimary: _DeepSpaceColors.bgPrimary,
          bgSecondary: _DeepSpaceColors.bgSecondary,
          bgTertiary: _DeepSpaceColors.bgTertiary,
          primary: _DeepSpaceColors.primary,
          primaryLight: _DeepSpaceColors.primaryLight,
          primaryDark: _DeepSpaceColors.primaryDark,
          accent: _DeepSpaceColors.accent,
          accentLight: _DeepSpaceColors.accentLight,
          accentDark: _DeepSpaceColors.accentDark,
          textPrimary: _DeepSpaceColors.textPrimary,
          textSecondary: _DeepSpaceColors.textSecondary,
          textMuted: _DeepSpaceColors.textMuted,
          surface: _DeepSpaceColors.surface,
          surfaceLight: _DeepSpaceColors.surfaceLight,
          error: _DeepSpaceColors.error,
          warning: _DeepSpaceColors.warning,
          success: _DeepSpaceColors.success,
          glassBase: _DeepSpaceColors.glass,
          transitionDuration: const Duration(milliseconds: 500),
          transitionCurve: Curves.easeInOutCubic,
          microDuration: const Duration(milliseconds: 200),
          microCurve: Curves.easeOutQuart,
        );

      case AppTheme.aurora:
        return _ThemeBuilder.build(
          id: id,
          name: 'Aurora',
          bgPrimary: _AuroraColors.bgPrimary,
          bgSecondary: _AuroraColors.bgSecondary,
          bgTertiary: _AuroraColors.bgTertiary,
          primary: _AuroraColors.primary,
          primaryLight: _AuroraColors.primaryLight,
          primaryDark: _AuroraColors.primaryDark,
          accent: _AuroraColors.accent,
          accentLight: _AuroraColors.accentLight,
          accentDark: _AuroraColors.accentDark,
          textPrimary: _AuroraColors.textPrimary,
          textSecondary: _AuroraColors.textSecondary,
          textMuted: _AuroraColors.textMuted,
          surface: _AuroraColors.surface,
          surfaceLight: _AuroraColors.surfaceLight,
          error: _AuroraColors.error,
          warning: _AuroraColors.warning,
          success: _AuroraColors.success,
          glassBase: _AuroraColors.glass,
          transitionDuration: const Duration(milliseconds: 600),
          transitionCurve: Curves.easeInOutSine,
          microDuration: const Duration(milliseconds: 250),
          microCurve: Curves.easeOutCubic,
        );

      case AppTheme.midnightForest:
        return _ThemeBuilder.build(
          id: id,
          name: 'Midnight Forest',
          bgPrimary: _MidnightForestColors.bgPrimary,
          bgSecondary: _MidnightForestColors.bgSecondary,
          bgTertiary: _MidnightForestColors.bgTertiary,
          primary: _MidnightForestColors.primary,
          primaryLight: _MidnightForestColors.primaryLight,
          primaryDark: _MidnightForestColors.primaryDark,
          accent: _MidnightForestColors.accent,
          accentLight: _MidnightForestColors.accentLight,
          accentDark: _MidnightForestColors.accentDark,
          textPrimary: _MidnightForestColors.textPrimary,
          textSecondary: _MidnightForestColors.textSecondary,
          textMuted: _MidnightForestColors.textMuted,
          surface: _MidnightForestColors.surface,
          surfaceLight: _MidnightForestColors.surfaceLight,
          error: _MidnightForestColors.error,
          warning: _MidnightForestColors.warning,
          success: _MidnightForestColors.success,
          glassBase: _MidnightForestColors.glass,
          transitionDuration: const Duration(milliseconds: 450),
          transitionCurve: Curves.easeInOutQuad,
          microDuration: const Duration(milliseconds: 180),
          microCurve: Curves.easeOutQuart,
        );

      case AppTheme.cyberSunset:
        return _ThemeBuilder.build(
          id: id,
          name: 'Cyber Sunset',
          bgPrimary: _CyberSunsetColors.bgPrimary,
          bgSecondary: _CyberSunsetColors.bgSecondary,
          bgTertiary: _CyberSunsetColors.bgTertiary,
          primary: _CyberSunsetColors.primary,
          primaryLight: _CyberSunsetColors.primaryLight,
          primaryDark: _CyberSunsetColors.primaryDark,
          accent: _CyberSunsetColors.accent,
          accentLight: _CyberSunsetColors.accentLight,
          accentDark: _CyberSunsetColors.accentDark,
          textPrimary: _CyberSunsetColors.textPrimary,
          textSecondary: _CyberSunsetColors.textSecondary,
          textMuted: _CyberSunsetColors.textMuted,
          surface: _CyberSunsetColors.surface,
          surfaceLight: _CyberSunsetColors.surfaceLight,
          error: _CyberSunsetColors.error,
          warning: _CyberSunsetColors.warning,
          success: _CyberSunsetColors.success,
          glassBase: _CyberSunsetColors.glass,
          transitionDuration: const Duration(milliseconds: 550),
          transitionCurve: Curves.easeInOutBack,
          microDuration: const Duration(milliseconds: 220),
          microCurve: Curves.easeOutBack,
        );

      case AppTheme.monochromeGeek:
        return _ThemeBuilder.build(
          id: id,
          name: 'Monochrome Geek',
          bgPrimary: _MonochromeGeekColors.bgPrimary,
          bgSecondary: _MonochromeGeekColors.bgSecondary,
          bgTertiary: _MonochromeGeekColors.bgTertiary,
          primary: _MonochromeGeekColors.primary,
          primaryLight: _MonochromeGeekColors.primaryLight,
          primaryDark: _MonochromeGeekColors.primaryDark,
          accent: _MonochromeGeekColors.accent,
          accentLight: _MonochromeGeekColors.accentLight,
          accentDark: _MonochromeGeekColors.accentDark,
          textPrimary: _MonochromeGeekColors.textPrimary,
          textSecondary: _MonochromeGeekColors.textSecondary,
          textMuted: _MonochromeGeekColors.textMuted,
          surface: _MonochromeGeekColors.surface,
          surfaceLight: _MonochromeGeekColors.surfaceLight,
          error: _MonochromeGeekColors.error,
          warning: _MonochromeGeekColors.warning,
          success: _MonochromeGeekColors.success,
          glassBase: _MonochromeGeekColors.glass,
          transitionDuration: const Duration(milliseconds: 350),
          transitionCurve: Curves.easeInOut,
          microDuration: const Duration(milliseconds: 150),
          microCurve: Curves.easeOut,
        );
    }
  }
}

// ============================================================
// SECTION 6: Theme Manager — State Management & Persistence
// ============================================================

/// Central theme manager that handles:
/// - Active theme state
/// - Persistence via SharedPreferences
/// - System dark-mode detection
/// - Animated theme transition broadcasting
class ThemeManager extends ChangeNotifier {
  static const String _prefsKey = 'mobilecode_active_theme';
  static const String _modeKey = 'mobilecode_theme_mode';

  late AppTheme _activeTheme;
  ThemeMode _themeMode;
  bool _followSystem;

  // -- Subscriptions for animated transitions --
  final List<VoidCallback> _transitionListeners = [];
  bool _isTransitioning = false;

  // -- Singleton access --
  static ThemeManager? _instance;
  static Future<ThemeManager> getInstance() async {
    if (_instance != null) return _instance!;
    _instance = ThemeManager._internal();
    await _instance!._loadPersisted();
    return _instance!;
  }

  ThemeManager._internal()
      : _activeTheme = AppTheme.deepSpace,
        _themeMode = ThemeMode.dark,
        _followSystem = false;

  // -- Public getters --
  AppTheme get activeThemeId => _activeTheme;
  MobileTheme get activeTheme => MobileThemeFactory.get(_activeTheme);
  ThemeData get activeThemeData => activeTheme.themeData;
  ThemeMode get themeMode => _themeMode;
  bool get followSystem => _followSystem;
  bool get isTransitioning => _isTransitioning;

  // -- Setters with persistence --
  Future<void> setTheme(AppTheme theme, {bool animate = true}) async {
    if (_activeTheme == theme) return;
    if (animate) {
      _isTransitioning = true;
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 50));
    }
    _activeTheme = theme;
    _isTransitioning = false;
    notifyListeners();
    await _persist();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_modeKey, mode.index);
  }

  Future<void> setFollowSystem(bool value) async {
    _followSystem = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_modeKey}_follow_system', value);
  }

  /// Quick toggle between two favourite themes.
  void quickToggle() {
    final themes = AppTheme.values;
    final nextIndex = (themes.indexOf(_activeTheme) + 1) % themes.length;
    setTheme(themes[nextIndex]);
  }

  /// Register a callback that fires when a theme transition begins.
  void addTransitionListener(VoidCallback listener) {
    _transitionListeners.add(listener);
  }

  void removeTransitionListener(VoidCallback listener) {
    _transitionListeners.remove(listener);
  }

  // -- Persistence --
  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _activeTheme.name);
  }

  Future<void> _loadPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null) {
      _activeTheme = AppTheme.values.firstWhere(
        (t) => t.name == saved,
        orElse: () => AppTheme.deepSpace,
      );
    }
    final modeIndex = prefs.getInt(_modeKey);
    if (modeIndex != null) {
      _themeMode = ThemeMode.values[modeIndex];
    }
    _followSystem = prefs.getBool('${_modeKey}_follow_system') ?? false;
  }

  /// Clean up singleton (mainly for testing).
  static void reset() {
    _instance = null;
  }
}

// ============================================================
// SECTION 7: Inherited Notifier — Widget Tree Access
// ============================================================

/// Provides [ThemeManager] access to the widget tree via
/// `ThemeProvider.of(context)`.
class ThemeProvider extends InheritedNotifier<ThemeManager> {
  const ThemeProvider({
    Key? key,
    required ThemeManager notifier,
    required Widget child,
  }) : super(key: key, notifier: notifier, child: child);

  static ThemeManager of(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<ThemeProvider>();
    assert(provider != null, 'ThemeProvider not found in widget tree');
    return provider!.notifier!;
  }
}

// ============================================================
// SECTION 8: Glassmorphism Presets — Reusable Decoration
// ============================================================

/// Static factory for glassmorphism card decorations that adapt
/// automatically to the active theme.
class Glassmorphism {
  /// Builds a glassmorphism card decoration for the given [theme].
  static BoxDecoration card(MobileTheme theme) {
    return BoxDecoration(
      color: theme.cardGlassBackground,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: theme.cardGlassBorder, width: 1),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: theme.colorScheme.primary.withOpacity(0.05),
          blurRadius: 40,
          offset: const Offset(0, 0),
        ),
      ],
    );
  }

  /// A subtle glass chip/pill decoration.
  static BoxDecoration chip(MobileTheme theme, {bool isActive = false}) {
    return BoxDecoration(
      color: isActive
          ? theme.colorScheme.primary.withOpacity(0.15)
          : theme.glassOverlayColor,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: isActive
            ? theme.colorScheme.primary.withOpacity(0.4)
            : theme.glassBorderColor,
        width: 1,
      ),
    );
  }

  /// A floating panel (e.g., bottom toolbar).
  static BoxDecoration panel(MobileTheme theme) {
    return BoxDecoration(
      color: theme.toolbarBackground,
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      border: Border.all(
        color: theme.glassBorderColor.withOpacity(0.3),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.3),
          blurRadius: 20,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  /// Editor container decoration.
  static BoxDecoration editor(MobileTheme theme) {
    return BoxDecoration(
      color: theme.editorBackground,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: theme.dividerColor, width: 1),
    );
  }

  /// Terminal container decoration.
  static BoxDecoration terminal(MobileTheme theme) {
    return BoxDecoration(
      color: theme.terminalBackground,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: theme.dividerColor.withOpacity(0.5), width: 1),
    );
  }
}

// ============================================================
// SECTION 9: Theme Animation Mixin
// ============================================================

/// Mixin for widgets that want to react to theme transitions
/// with built-in animation controllers.
mixin ThemeAnimationMixin<T extends StatefulWidget> on State<T>
    implements TickerProvider {
  late AnimationController _themeAnimController;
  late Animation<double> themeFadeAnimation;
  late Animation<Offset> themeSlideAnimation;

  void initThemeAnimation({
    Duration duration = const Duration(milliseconds: 500),
    Curve curve = Curves.easeInOutCubic,
  }) {
    _themeAnimController = AnimationController(
      vsync: this,
      duration: duration,
    );
    themeFadeAnimation = CurvedAnimation(
      parent: _themeAnimController,
      curve: curve,
    );
    themeSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _themeAnimController,
      curve: curve,
    ));
    _themeAnimController.forward();
  }

  void triggerThemeTransition() {
    _themeAnimController.reset();
    _themeAnimController.forward();
  }

  @override
  void dispose() {
    _themeAnimController.dispose();
    super.dispose();
  }
}

// ============================================================
// SECTION 10: Syntax Highlighting Colors (Editor Themes)
// ============================================================

/// Per-theme syntax highlighting map for the code editor.
extension SyntaxColors on MobileTheme {
  Map<String, Color> get syntaxHighlight {
    switch (id) {
      case AppTheme.deepSpace:
        return {
          'keyword': const Color(0xFF7B2FF7),
          'string': const Color(0xFF00D4AA),
          'comment': const Color(0xFF6B7280),
          'number': const Color(0xFFF59E0B),
          'function': const Color(0xFF9D5CFF),
          'type': const Color(0xFF00D4AA),
          'variable': const Color(0xFFF0F0F5),
          'operator': const Color(0xFF7B2FF7),
        };
      case AppTheme.aurora:
        return {
          'keyword': const Color(0xFF00FF88),
          'string': const Color(0xFFFF6B9D),
          'comment': const Color(0xFF6B8A80),
          'number': const Color(0xFFFFBB33),
          'function': const Color(0xFF33FFA0),
          'type': const Color(0xFFFF8FB0),
          'variable': const Color(0xFFE8F4F0),
          'operator': const Color(0xFF00CC6A),
        };
      case AppTheme.midnightForest:
        return {
          'keyword': const Color(0xFF2ECC71),
          'string': const Color(0xFFF39C12),
          'comment': const Color(0xFF708C68),
          'number': const Color(0xFFF5B041),
          'function': const Color(0xFF52D687),
          'type': const Color(0xFFF5B041),
          'variable': const Color(0xFFF2F8F0),
          'operator': const Color(0xFF25A55A),
        };
      case AppTheme.cyberSunset:
        return {
          'keyword': const Color(0xFFFF7B54),
          'string': const Color(0xFF9B59B6),
          'comment': const Color(0xFF9A7880),
          'number': const Color(0xFFFFA502),
          'function': const Color(0xFFFF9D80),
          'type': const Color(0xFFB07DC9),
          'variable': const Color(0xFFFFF0EB),
          'operator': const Color(0xFFE06040),
        };
      case AppTheme.monochromeGeek:
        return {
          'keyword': const Color(0xFFFFFFFF),
          'string': const Color(0xFFAAAAAA),
          'comment': const Color(0xFF555555),
          'number': const Color(0xFF888888),
          'function': const Color(0xFFDDDDDD),
          'type': const Color(0xFFCCCCCC),
          'variable': const Color(0xFFFFFFFF),
          'operator': const Color(0xFF999999),
        };
    }
  }
}
