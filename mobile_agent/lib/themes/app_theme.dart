import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Mobile Agent App Theme
/// Aurora Light is the default MobileCode product theme.
class AppTheme {
  AppTheme._();

  // ── Core Colors ──────────────────────────────────────────────
  static const Color auroraBackground = Color(0xFFF7FAFF);
  static const Color auroraSurface = Color(0xFFFFFFFF);
  static const Color auroraSurfaceSoft = Color(0xFFF0F5FF);
  static const Color auroraBorder = Color(0xFFDDE7F7);
  static const Color auroraText = Color(0xFF0B1020);
  static const Color auroraTextMuted = Color(0xFF536079);
  static const Color auroraTextFaint = Color(0xFF8B97AD);
  static const Color auroraBlue = Color(0xFF2555FF);
  static const Color auroraCyan = Color(0xFF16B9C7);
  static const Color auroraViolet = Color(0xFF7557E8);
  static const Color claudeBackground = Color(0xFFFFFAF3);
  static const Color claudeSurface = Color(0xFFFFFFFF);
  static const Color claudeSurfaceSoft = Color(0xFFFFF1DD);
  static const Color claudeBorder = Color(0xFFEEDCC6);
  static const Color claudeText = Color(0xFF1B130A);
  static const Color claudeTextMuted = Color(0xFF755C43);
  static const Color claudeTextFaint = Color(0xFFA48767);
  static const Color claudeAmber = Color(0xFFD97706);
  static const Color claudeCoral = Color(0xFFEF925B);

  static const Color deepSpace = Color(0xFF030508);
  static const Color surfaceDark = Color(0xFF0A0E1A);
  static const Color surfaceElevated = Color(0xFF12162B);
  static const Color surfaceCard = Color(0xFF161B2E);
  static const Color divider = Color(0xFF1E2440);
  static const Color border = Color(0xFF2A3050);

  static const Color violet = Color(0xFF7B2FF7);
  static const Color violetLight = Color(0xFF9B5FFF);
  static const Color violetDark = Color(0xFF5A1DB5);
  static const Color violetGlow = Color(0x407B2FF7);

  static const Color cyan = Color(0xFF00D4AA);
  static const Color cyanLight = Color(0xFF33E0BF);
  static const Color cyanGlow = Color(0x4000D4AA);

  static const Color textPrimary = Color(0xFFE8ECF4);
  static const Color textSecondary = Color(0xFF8B92B9);
  static const Color textTertiary = Color(0xFF5A6080);

  static const Color error = Color(0xFFFF4757);
  static const Color warning = Color(0xFFFFA502);
  static const Color success = Color(0xFF2ED573);

  // ── Gradients ────────────────────────────────────────────────
  static const Gradient auroraGradient = LinearGradient(
    colors: [violet, cyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Gradient violetGradient = LinearGradient(
    colors: [violetDark, violet, violetLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Gradient surfaceGradient = LinearGradient(
    colors: [surfaceDark, deepSpace],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ── Glassmorphism ────────────────────────────────────────────
  static BoxDecoration glassDecoration = BoxDecoration(
    color: surfaceCard.withOpacity(0.6),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: border.withOpacity(0.5), width: 1),
    boxShadow: [
      BoxShadow(
        color: violetGlow.withOpacity(0.1),
        blurRadius: 20,
        spreadRadius: 0,
      ),
    ],
  );

  static BoxDecoration glassDecorationRounded = BoxDecoration(
    color: surfaceCard.withOpacity(0.5),
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: border.withOpacity(0.4), width: 1),
  );

  // ── Typography ───────────────────────────────────────────────
  static const String fontCode = 'JetBrainsMono';
  static const String fontDisplay = 'Inter';

  static TextTheme get textTheme => const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: textPrimary,
          letterSpacing: 0,
        ),
        displayMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: textPrimary),
        bodyMedium: TextStyle(fontSize: 14, color: textSecondary),
        bodySmall: TextStyle(fontSize: 12, color: textTertiary),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
      );

  // ── Aurora Light Theme ───────────────────────────────────────
  static ThemeData get auroraLightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: auroraBackground,
        colorScheme: const ColorScheme.light(
          primary: auroraBlue,
          onPrimary: Colors.white,
          secondary: auroraCyan,
          onSecondary: Colors.white,
          tertiary: auroraViolet,
          surface: auroraSurface,
          surfaceContainerHighest: auroraSurfaceSoft,
          error: error,
          onError: Colors.white,
          onSurface: auroraText,
          outline: auroraBorder,
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: auroraText, letterSpacing: 0),
          displayMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: auroraText),
          titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: auroraText),
          titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: auroraText),
          bodyLarge: TextStyle(fontSize: 16, color: auroraText),
          bodyMedium: TextStyle(fontSize: 14, color: auroraTextMuted),
          bodySmall: TextStyle(fontSize: 12, color: auroraTextFaint),
          labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: auroraText),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: auroraSurface,
          foregroundColor: auroraText,
          elevation: 0,
          centerTitle: true,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: auroraSurface,
          indicatorColor: auroraBlue.withOpacity(0.10),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              color: states.contains(WidgetState.selected) ? auroraBlue : auroraTextFaint,
              fontSize: 11,
              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? auroraBlue : auroraTextFaint,
            ),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: auroraBlue,
          foregroundColor: Colors.white,
          elevation: 2,
        ),
        cardTheme: CardThemeData(
          color: auroraSurface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: auroraBorder),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: auroraSurfaceSoft,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: auroraBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: auroraBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: auroraBlue, width: 1.6),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          labelStyle: const TextStyle(color: auroraTextMuted),
          hintStyle: const TextStyle(color: auroraTextFaint),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: auroraBlue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: auroraBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: auroraText,
            backgroundColor: auroraSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: auroraBorder),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: auroraBlue),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: auroraSurface,
          selectedColor: auroraBlue.withOpacity(0.12),
          labelStyle: const TextStyle(color: auroraTextMuted, fontSize: 12, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: const BorderSide(color: auroraBorder),
          ),
        ),
        dividerTheme: const DividerThemeData(color: auroraBorder, thickness: 1, space: 1),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: auroraText,
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          behavior: SnackBarBehavior.floating,
        ),
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: auroraText,
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      );

  static ThemeData get codexBlueLightTheme => auroraLightTheme;

  static ThemeData get claudeYellowLightTheme {
    final base = auroraLightTheme;
    return base.copyWith(
      scaffoldBackgroundColor: claudeBackground,
      colorScheme: const ColorScheme.light(
        primary: claudeAmber,
        onPrimary: Colors.white,
        secondary: claudeCoral,
        onSecondary: Colors.white,
        tertiary: auroraBlue,
        surface: claudeSurface,
        surfaceContainerHighest: claudeSurfaceSoft,
        error: error,
        onError: Colors.white,
        onSurface: claudeText,
        outline: claudeBorder,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: claudeSurface,
        foregroundColor: claudeText,
        elevation: 0,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: claudeSurface,
        indicatorColor: claudeAmber.withOpacity(0.12),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected) ? claudeAmber : claudeTextFaint,
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? claudeAmber : claudeTextFaint,
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: claudeAmber,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: claudeSurfaceSoft,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: claudeBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: claudeBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: claudeAmber, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        labelStyle: const TextStyle(color: claudeTextMuted),
        hintStyle: const TextStyle(color: claudeTextFaint),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: claudeAmber,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: claudeAmber,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: claudeAmber),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: claudeSurface,
        selectedColor: claudeAmber.withOpacity(0.12),
        labelStyle: const TextStyle(
          color: claudeTextMuted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: const BorderSide(color: claudeBorder),
        ),
      ),
      dividerTheme: const DividerThemeData(color: claudeBorder, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: claudeText,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Dark Theme ───────────────────────────────────────────────
  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: deepSpace,
        colorScheme: const ColorScheme.dark(
          primary: violet,
          onPrimary: Colors.white,
          secondary: cyan,
          onSecondary: Colors.white,
          surface: surfaceDark,
          surfaceContainerHighest: surfaceElevated,
          error: error,
          onError: Colors.white,
          onSurface: textPrimary,
          outline: border,
        ),
        textTheme: textTheme,
        appBarTheme: const AppBarTheme(
          backgroundColor: surfaceDark,
          foregroundColor: textPrimary,
          elevation: 0,
          centerTitle: true,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: surfaceDark,
          selectedItemColor: violet,
          unselectedItemColor: textTertiary,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
          selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          unselectedLabelStyle: TextStyle(fontSize: 11),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: violet,
          foregroundColor: Colors.white,
          elevation: 4,
        ),
        cardTheme: CardThemeData(
          color: surfaceCard,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surfaceElevated,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: violet, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          hintStyle: const TextStyle(color: textTertiary),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: violet,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: cyan),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: surfaceElevated,
          selectedColor: violet.withOpacity(0.3),
          labelStyle: const TextStyle(color: textSecondary, fontSize: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: divider,
          thickness: 1,
          space: 1,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: surfaceElevated,
          contentTextStyle: const TextStyle(color: textPrimary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          behavior: SnackBarBehavior.floating,
        ),
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: surfaceCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border),
          ),
          textStyle: const TextStyle(color: textPrimary, fontSize: 12),
        ),
      );

  // ── Syntax Highlighting Colors ───────────────────────────────
  static const Color syntaxKeyword = Color(0xFF7B2FF7);
  static const Color syntaxString = Color(0xFF00D4AA);
  static const Color syntaxComment = Color(0xFF5A6080);
  static const Color syntaxNumber = Color(0xFFFFA502);
  static const Color syntaxFunction = Color(0xFF4FC3F7);
  static const Color syntaxType = Color(0xFFCE93D8);
  static const Color syntaxOperator = Color(0xFFFF8A65);

  // ── Animation Durations ──────────────────────────────────────
  static const Duration animFast = Duration(milliseconds: 150);
  static const Duration animNormal = Duration(milliseconds: 300);
  static const Duration animSlow = Duration(milliseconds: 500);
}
