import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Design system for Mobile Agent.
///
/// Defines the complete visual identity including colors, typography,
/// component themes, and gradients. All themes are dark-mode oriented
/// for optimal code editing experience.
///
/// ## Color Palette
/// - Background: Deep space dark (#030508)
/// - Primary: Violet (#7B2FF7)
/// - Accent: Cyan (#00D4AA)
/// - Surfaces: Layered dark grays
/// - Text: White to gray scale
/// - Status: Success green, Error red, Warning amber
class AppTheme {
  AppTheme._();

  // ── Background Colors ───────────────────────────────────────────────

  /// Deepest background - used for scaffold and base layers
  static const Color background = Color(0xFF030508);

  /// Slightly elevated background for contrast
  static const Color backgroundElevated = Color(0xFF0A0E14);

  /// Card and container backgrounds
  static const Color surface = Color(0xFF111827);

  /// Hover/pressed state for interactive surfaces
  static const Color surfaceHover = Color(0xFF1A2236);

  /// Input field backgrounds
  static const Color surfaceInput = Color(0xFF151B27);

  // ── Primary & Accent Colors ─────────────────────────────────────────

  /// Primary brand color - Violet
  static const Color primary = Color(0xFF7B2FF7);

  /// Primary hover/active state
  static const Color primaryHover = Color(0xFF9460FF);

  /// Primary with reduced opacity
  static const Color primaryMuted = Color(0x407B2FF7);

  /// Accent color - Cyan (used for highlights, active states)
  static const Color accent = Color(0xFF00D4AA);

  /// Accent hover state
  static const Color accentHover = Color(0xFF33E0BF);

  /// Accent with reduced opacity
  static const Color accentMuted = Color(0x4000D4AA);

  // ── Text Colors ─────────────────────────────────────────────────────

  /// Primary text - white
  static const Color textPrimary = Color(0xFFF0F0F5);

  /// Secondary text - light gray
  static const Color textSecondary = Color(0xFF9CA3AF);

  /// Tertiary/muted text
  static const Color textTertiary = Color(0xFF6B7280);

  /// Text on primary colored backgrounds
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  /// Disabled text
  static const Color textDisabled = Color(0xFF4B5563);

  // ── Status Colors ───────────────────────────────────────────────────

  /// Success - Green
  static const Color success = Color(0xFF10B981);

  /// Error - Red
  static const Color error = Color(0xFFEF4444);

  /// Warning - Amber
  static const Color warning = Color(0xFFF59E0B);

  /// Info - Blue
  static const Color info = Color(0xFF3B82F6);

  // ── Border & Divider Colors ─────────────────────────────────────────

  /// Default border color
  static const Color border = Color(0xFF1F2937);

  /// Border for focused/active states
  static const Color borderActive = Color(0xFF7B2FF7);

  /// Divider color
  static const Color divider = Color(0xFF1A2236);

  // ── Code Editor Theme Colors ────────────────────────────────────────

  /// Editor background
  static const Color editorBackground = Color(0xFF0D1117);

  /// Editor gutter (line numbers area)
  static const Color editorGutter = Color(0xFF0A0E14);

  /// Editor active line highlight
  static const Color editorActiveLine = Color(0xFF151B27);

  /// Editor selection color
  static const Color editorSelection = Color(0x407B2FF7);

  /// Editor cursor color
  static const Color editorCursor = Color(0xFF7B2FF7);

  /// Editor line number color
  static const Color editorLineNumber = Color(0xFF4B5563);

  /// Editor comment color
  static const Color codeComment = Color(0xFF6B7280);

  /// Editor keyword color
  static const Color codeKeyword = Color(0xFFC084FC);

  /// Editor string color
  static const Color codeString = Color(0xFF34D399);

  /// Editor function color
  static const Color codeFunction = Color(0xFF60A5FA);

  /// Editor number/color literal
  static const Color codeLiteral = Color(0xFFFBBF24);

  /// Editor type/class color
  static const Color codeType = Color(0xFF00D4AA);

  /// Editor variable color
  static const Color codeVariable = Color(0xFFF0F0F5);

  /// Editor operator color
  static const Color codeOperator = Color(0xFFF87171);

  // ── Gradients ───────────────────────────────────────────────────────

  /// Primary gradient for hero sections and prominent buttons
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7B2FF7), Color(0xFF4C1D95)],
  );

  /// Accent gradient for highlights
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF00D4AA), Color(0xFF0891B2)],
  );

  /// Subtle surface gradient for cards
  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF111827), Color(0xFF0A0E14)],
  );

  /// Glassmorphism gradient overlay
  static const LinearGradient glassGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x20FFFFFF), Color(0x05FFFFFF)],
  );

  // ── Typography ──────────────────────────────────────────────────────

  static const String fontCode = 'JetBrainsMono';
  static const String fontBody = 'Inter';

  /// Get text theme for the app
  static TextTheme get textTheme {
    return const TextTheme(
      displayLarge: TextStyle(
        fontFamily: fontBody,
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: textPrimary,
        letterSpacing: -0.5,
      ),
      displayMedium: TextStyle(
        fontFamily: fontBody,
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: textPrimary,
        letterSpacing: -0.5,
      ),
      displaySmall: TextStyle(
        fontFamily: fontBody,
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      headlineLarge: TextStyle(
        fontFamily: fontBody,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      headlineMedium: TextStyle(
        fontFamily: fontBody,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      headlineSmall: TextStyle(
        fontFamily: fontBody,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      titleLarge: TextStyle(
        fontFamily: fontBody,
        fontSize: 18,
        fontWeight: FontWeight.w500,
        color: textPrimary,
      ),
      titleMedium: TextStyle(
        fontFamily: fontBody,
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: textPrimary,
      ),
      titleSmall: TextStyle(
        fontFamily: fontBody,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: textSecondary,
      ),
      bodyLarge: TextStyle(
        fontFamily: fontBody,
        fontSize: 16,
        fontWeight: FontWeight.normal,
        color: textPrimary,
      ),
      bodyMedium: TextStyle(
        fontFamily: fontBody,
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: textSecondary,
      ),
      bodySmall: TextStyle(
        fontFamily: fontBody,
        fontSize: 12,
        fontWeight: FontWeight.normal,
        color: textTertiary,
      ),
      labelLarge: TextStyle(
        fontFamily: fontBody,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: textPrimary,
      ),
      labelMedium: TextStyle(
        fontFamily: fontBody,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: textSecondary,
      ),
      labelSmall: TextStyle(
        fontFamily: fontBody,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: textTertiary,
        letterSpacing: 0.5,
      ),
    );
  }

  /// Code-specific text theme
  static TextTheme get codeTextTheme {
    return const TextTheme(
      bodyLarge: TextStyle(
        fontFamily: fontCode,
        fontSize: 16,
        fontWeight: FontWeight.normal,
        color: textPrimary,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontFamily: fontCode,
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: textSecondary,
        height: 1.5,
      ),
      bodySmall: TextStyle(
        fontFamily: fontCode,
        fontSize: 12,
        fontWeight: FontWeight.normal,
        color: textTertiary,
        height: 1.5,
      ),
    );
  }

  // ── Component Themes ────────────────────────────────────────────────

  /// Card theme
  static CardThemeData get cardTheme {
    return CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: border, width: 1),
      ),
      margin: EdgeInsets.zero,
    );
  }

  /// Input decoration theme
  static InputDecorationTheme get inputDecorationTheme {
    return InputDecorationTheme(
      filled: true,
      fillColor: surfaceInput,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: border, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: border, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: error, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: error, width: 1.5),
      ),
      hintStyle: const TextStyle(
        fontFamily: fontBody,
        fontSize: 14,
        color: textTertiary,
      ),
      labelStyle: const TextStyle(
        fontFamily: fontBody,
        fontSize: 14,
        color: textSecondary,
      ),
    );
  }

  /// Button themes
  static ElevatedButtonThemeData get elevatedButtonTheme {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: textOnPrimary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: const TextStyle(
          fontFamily: fontBody,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static OutlinedButtonThemeData get outlinedButtonTheme {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: textPrimary,
        side: const BorderSide(color: border, width: 1),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: const TextStyle(
          fontFamily: fontBody,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static TextButtonThemeData get textButtonTheme {
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: const TextStyle(
          fontFamily: fontBody,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Icon theme
  static IconThemeData get iconTheme {
    return const IconThemeData(
      color: textSecondary,
      size: 24,
    );
  }

  /// AppBar theme
  static AppBarTheme get appBarTheme {
    return AppBarTheme(
      backgroundColor: background.withOpacity(0.8),
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: true,
      scrolledUnderElevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: const TextStyle(
        fontFamily: fontBody,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      shape: Border(
        bottom: BorderSide(color: divider, width: 1),
      ),
    );
  }

  /// Bottom navigation bar theme
  static BottomNavigationBarThemeData get bottomNavTheme {
    return BottomNavigationBarThemeData(
      backgroundColor: backgroundElevated,
      selectedItemColor: primary,
      unselectedItemColor: textTertiary,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      selectedLabelStyle: const TextStyle(
        fontFamily: fontBody,
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
      unselectedLabelStyle: const TextStyle(
        fontFamily: fontBody,
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  /// Chip theme
  static ChipThemeData get chipTheme {
    return ChipThemeData(
      backgroundColor: surface,
      selectedColor: primaryMuted,
      labelStyle: const TextStyle(
        fontFamily: fontBody,
        fontSize: 12,
        color: textSecondary,
      ),
      secondaryLabelStyle: const TextStyle(
        fontFamily: fontBody,
        fontSize: 12,
        color: textPrimary,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: border),
      ),
    );
  }

  /// Divider theme
  static DividerThemeData get dividerTheme {
    return const DividerThemeData(
      color: divider,
      thickness: 1,
      space: 1,
    );
  }

  /// Tab bar theme
  static TabBarThemeData get tabBarTheme {
    return TabBarThemeData(
      labelColor: primary,
      unselectedLabelColor: textTertiary,
      indicatorColor: primary,
      labelStyle: const TextStyle(
        fontFamily: fontBody,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: const TextStyle(
        fontFamily: fontBody,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      indicator: const UnderlineTabIndicator(
        borderSide: BorderSide(color: primary, width: 2),
      ),
    );
  }

  /// Dialog theme
  static DialogThemeData get dialogTheme {
    return DialogThemeData(
      backgroundColor: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: border, width: 1),
      ),
      titleTextStyle: const TextStyle(
        fontFamily: fontBody,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
    );
  }

  /// Bottom sheet theme
  static BottomSheetThemeData get bottomSheetTheme {
    return BottomSheetThemeData(
      backgroundColor: surface,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      modalBarrierColor: Colors.black.withOpacity(0.5),
    );
  }

  // ── Full Theme Data ─────────────────────────────────────────────────

  /// Dark theme (primary app theme)
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: accent,
        surface: surface,
        background: background,
        error: error,
        onPrimary: textOnPrimary,
        onSecondary: background,
        onSurface: textPrimary,
        onBackground: textPrimary,
        onError: textOnPrimary,
        surfaceTint: Colors.transparent,
      ),
      scaffoldBackgroundColor: background,
      canvasColor: backgroundElevated,
      textTheme: textTheme,
      cardTheme: cardTheme,
      inputDecorationTheme: inputDecorationTheme,
      elevatedButtonTheme: elevatedButtonTheme,
      outlinedButtonTheme: outlinedButtonTheme,
      textButtonTheme: textButtonTheme,
      iconTheme: iconTheme,
      appBarTheme: appBarTheme,
      bottomNavigationBarTheme: bottomNavTheme,
      chipTheme: chipTheme,
      dividerTheme: dividerTheme,
      tabBarTheme: tabBarTheme,
      dialogTheme: dialogTheme,
      bottomSheetTheme: bottomSheetTheme,
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHover,
        contentTextStyle: const TextStyle(
          fontFamily: fontBody,
          fontSize: 14,
          color: textPrimary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: surfaceHover,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        textStyle: const TextStyle(
          fontFamily: fontBody,
          fontSize: 12,
          color: textSecondary,
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(textTertiary.withOpacity(0.5)),
        trackColor: WidgetStateProperty.all(Colors.transparent),
        radius: const Radius.circular(4),
        thickness: WidgetStateProperty.all(4),
      ),
    );
  }

  /// Light theme (fallback, not primary)
  static ThemeData get lightTheme {
    // Mobile Agent is dark-mode first, light theme is minimal
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: accent,
      ),
    );
  }
}

/// Extension for convenient access to AppTheme colors in BuildContext
extension ThemeExtension on BuildContext {
  /// Access AppTheme colors directly
  AppColors get appColors => AppColors();
}

/// Container for organized color access
class AppColors {
  /// Code syntax highlighting colors organized by token type
  CodeColors get code => const CodeColors();
}

/// Code syntax highlighting color palette
class CodeColors {
  const CodeColors();

  final Color comment = AppTheme.codeComment;
  final Color keyword = AppTheme.codeKeyword;
  final Color string = AppTheme.codeString;
  final Color function = AppTheme.codeFunction;
  final Color literal = AppTheme.codeLiteral;
  final Color type = AppTheme.codeType;
  final Color variable = AppTheme.codeVariable;
  final Color operator = AppTheme.codeOperator;
}
