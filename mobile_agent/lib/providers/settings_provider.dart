// lib/providers/settings_provider.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/storage_service.dart';
import 'storage_provider.dart';

// ─── Theme Mode ────────────────────────────────────────────────────

/// Manages the app's theme mode (light/dark/system).
///
/// Persisted to local storage under the key 'theme_mode'.
/// Uses [ThemeMode] enum values: 'light', 'dark', 'system'.
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final StorageService _storage;

  ThemeModeNotifier(this._storage) : super(ThemeMode.dark) {
    _load();
  }

  static const String _key = 'theme_mode';

  Future<void> _load() async {
    try {
      final value = await _storage.getSetting<String>(_key);
      if (value != null) {
        state = _parseThemeMode(value);
      }
    } catch (e) {
      debugPrint('[ThemeModeNotifier] Failed to load theme mode: $e');
    }
  }

  ThemeMode _parseThemeMode(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.dark;
    }
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  /// Set the theme mode and persist it.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (state == mode) return;
    state = mode;
    try {
      await _storage.setSetting<String>(_key, _themeModeToString(mode));
    } catch (e) {
      debugPrint('[ThemeModeNotifier] Failed to save theme mode: $e');
    }
  }

  /// Toggle between light and dark mode.
  Future<void> toggle() async {
    final newMode = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await setThemeMode(newMode);
  }
}

/// Provider for the app's theme mode.
///
/// Controls light/dark/system theming across the app.
///
/// ```dart
/// final themeMode = ref.watch(themeModeProvider);
/// MaterialApp(themeMode: themeMode, ...)
/// ```
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(ref.watch(storageServiceProvider)),
);

/// Whether the app is currently in dark mode (for UI decisions).
///
/// This is a derived provider that resolves the actual theme mode
/// considering the system setting if 'system' is selected.
final isDarkModeProvider = Provider<bool>((ref) {
  final themeMode = ref.watch(themeModeProvider);
  switch (themeMode) {
    case ThemeMode.dark:
      return true;
    case ThemeMode.light:
      return false;
    case ThemeMode.system:
    // We can't know system brightness here without context,
    // so default to dark (the app's default theme).
      return true;
  }
});

// ─── Font Size ─────────────────────────────────────────────────────

/// Manages the editor font size.
///
/// Persisted to local storage. Range: 8.0 - 32.0.
class FontSizeNotifier extends StateNotifier<double> {
  final StorageService _storage;

  FontSizeNotifier(this._storage) : super(14.0) {
    _load();
  }

  static const String _key = 'font_size';
  static const double _minSize = 8.0;
  static const double _maxSize = 32.0;
  static const double _defaultSize = 14.0;

  Future<void> _load() async {
    try {
      final value = await _storage.getSetting<double>(_key);
      state = value ?? _defaultSize;
    } catch (e) {
      debugPrint('[FontSizeNotifier] Failed to load font size: $e');
    }
  }

  /// Set the font size.
  Future<void> setFontSize(double size) async {
    final clamped = size.clamp(_minSize, _maxSize);
    if (state == clamped) return;
    state = clamped;
    try {
      await _storage.setSetting<double>(_key, clamped);
    } catch (e) {
      debugPrint('[FontSizeNotifier] Failed to save font size: $e');
    }
  }

  /// Increase font size by 1 point.
  Future<void> increase() async {
    await setFontSize(state + 1.0);
  }

  /// Decrease font size by 1 point.
  Future<void> decrease() async {
    await setFontSize(state - 1.0);
  }

  /// Reset to default font size.
  Future<void> reset() async {
    await setFontSize(_defaultSize);
  }
}

/// Provider for the editor font size.
///
/// Controls the font size in the code editor.
///
/// ```dart
/// final fontSize = ref.watch(fontSizeProvider);
/// TextStyle(fontSize: fontSize, fontFamily: 'JetBrainsMono')
/// ```
final fontSizeProvider = StateNotifierProvider<FontSizeNotifier, double>(
  (ref) => FontSizeNotifier(ref.watch(storageServiceProvider)),
);

// ─── Font Family ───────────────────────────────────────────────────

/// Manages the editor font family.
///
/// Persisted to local storage. Default: 'JetBrainsMono'.
class FontFamilyNotifier extends StateNotifier<String> {
  final StorageService _storage;

  FontFamilyNotifier(this._storage) : super('JetBrainsMono') {
    _load();
  }

  static const String _key = 'font_family';

  Future<void> _load() async {
    try {
      final value = await _storage.getSetting<String>(_key);
      if (value != null && value.isNotEmpty) {
        state = value;
      }
    } catch (e) {
      debugPrint('[FontFamilyNotifier] Failed to load font family: $e');
    }
  }

  /// Set the font family.
  Future<void> setFontFamily(String family) async {
    if (state == family) return;
    state = family;
    try {
      await _storage.setSetting<String>(_key, family);
    } catch (e) {
      debugPrint('[FontFamilyNotifier] Failed to save font family: $e');
    }
  }
}

/// Provider for the editor font family.
///
/// Controls the font used in the code editor.
///
/// ```dart
/// final fontFamily = ref.watch(fontFamilyProvider);
/// TextStyle(fontFamily: fontFamily, fontSize: 14)
/// ```
final fontFamilyProvider = StateNotifierProvider<FontFamilyNotifier, String>(
  (ref) => FontFamilyNotifier(ref.watch(storageServiceProvider)),
);

// ─── Show Line Numbers ─────────────────────────────────────────────

/// Manages whether line numbers are shown in the editor.
///
/// Persisted to local storage. Default: true.
class ShowLineNumbersNotifier extends StateNotifier<bool> {
  final StorageService _storage;

  ShowLineNumbersNotifier(this._storage) : super(true) {
    _load();
  }

  static const String _key = 'show_line_numbers';

  Future<void> _load() async {
    try {
      final value = await _storage.getSetting<bool>(_key);
      if (value != null) {
        state = value;
      }
    } catch (e) {
      debugPrint('[ShowLineNumbersNotifier] Failed to load setting: $e');
    }
  }

  /// Toggle line numbers visibility.
  Future<void> toggle() async {
    state = !state;
    try {
      await _storage.setSetting<bool>(_key, state);
    } catch (e) {
      debugPrint('[ShowLineNumbersNotifier] Failed to save setting: $e');
    }
  }

  /// Set line numbers visibility.
  Future<void> setValue(bool value) async {
    if (state == value) return;
    state = value;
    try {
      await _storage.setSetting<bool>(_key, value);
    } catch (e) {
      debugPrint('[ShowLineNumbersNotifier] Failed to save setting: $e');
    }
  }
}

/// Provider for showing/hiding line numbers in the editor.
///
/// Controls the visibility of line number gutter in the code editor.
///
/// ```dart
/// final showLineNumbers = ref.watch(showLineNumbersProvider);
/// if (showLineNumbers) { ... }
/// ```
final showLineNumbersProvider =
    StateNotifierProvider<ShowLineNumbersNotifier, bool>(
  (ref) => ShowLineNumbersNotifier(ref.watch(storageServiceProvider)),
);

// ─── Word Wrap ─────────────────────────────────────────────────────

/// Manages whether word wrap is enabled in the editor.
///
/// Persisted to local storage. Default: false.
class WordWrapNotifier extends StateNotifier<bool> {
  final StorageService _storage;

  WordWrapNotifier(this._storage) : super(false) {
    _load();
  }

  static const String _key = 'word_wrap';

  Future<void> _load() async {
    try {
      final value = await _storage.getSetting<bool>(_key);
      if (value != null) {
        state = value;
      }
    } catch (e) {
      debugPrint('[WordWrapNotifier] Failed to load setting: $e');
    }
  }

  /// Toggle word wrap.
  Future<void> toggle() async {
    state = !state;
    try {
      await _storage.setSetting<bool>(_key, state);
    } catch (e) {
      debugPrint('[WordWrapNotifier] Failed to save setting: $e');
    }
  }
}

/// Provider for word wrap in the editor.
final wordWrapSettingProvider = StateNotifierProvider<WordWrapNotifier, bool>(
  (ref) => WordWrapNotifier(ref.watch(storageServiceProvider)),
);

// ─── Tab Size ──────────────────────────────────────────────────────

/// Manages the editor tab size.
///
/// Persisted to local storage. Default: 2 spaces.
class TabSizeNotifier extends StateNotifier<int> {
  final StorageService _storage;

  TabSizeNotifier(this._storage) : super(2) {
    _load();
  }

  static const String _key = 'tab_size';

  Future<void> _load() async {
    try {
      final value = await _storage.getSetting<int>(_key);
      if (value != null) {
        state = value.clamp(1, 8);
      }
    } catch (e) {
      debugPrint('[TabSizeNotifier] Failed to load tab size: $e');
    }
  }

  /// Set the tab size.
  Future<void> setTabSize(int size) async {
    final clamped = size.clamp(1, 8);
    if (state == clamped) return;
    state = clamped;
    try {
      await _storage.setSetting<int>(_key, clamped);
    } catch (e) {
      debugPrint('[TabSizeNotifier] Failed to save tab size: $e');
    }
  }
}

/// Provider for the editor tab size.
final tabSizeProvider = StateNotifierProvider<TabSizeNotifier, int>(
  (ref) => TabSizeNotifier(ref.watch(storageServiceProvider)),
);

// ─── Use Spaces for Tabs ──────────────────────────────────────────

/// Whether to use spaces instead of tabs.
///
/// Persisted to local storage. Default: true.
class UseSpacesNotifier extends StateNotifier<bool> {
  final StorageService _storage;

  UseSpacesNotifier(this._storage) : super(true) {
    _load();
  }

  static const String _key = 'use_spaces';

  Future<void> _load() async {
    try {
      final value = await _storage.getSetting<bool>(_key);
      if (value != null) {
        state = value;
      }
    } catch (e) {
      debugPrint('[UseSpacesNotifier] Failed to load setting: $e');
    }
  }

  /// Toggle.
  Future<void> toggle() async {
    state = !state;
    try {
      await _storage.setSetting<bool>(_key, state);
    } catch (e) {
      debugPrint('[UseSpacesNotifier] Failed to save setting: $e');
    }
  }
}

/// Provider for using spaces instead of tabs.
final useSpacesProvider = StateNotifierProvider<UseSpacesNotifier, bool>(
  (ref) => UseSpacesNotifier(ref.watch(storageServiceProvider)),
);

// ─── Auto-Save ─────────────────────────────────────────────────────

/// Whether auto-save is enabled.
///
/// Persisted to local storage. Default: true.
class AutoSaveNotifier extends StateNotifier<bool> {
  final StorageService _storage;

  AutoSaveNotifier(this._storage) : super(true) {
    _load();
  }

  static const String _key = 'auto_save';

  Future<void> _load() async {
    try {
      final value = await _storage.getSetting<bool>(_key);
      if (value != null) {
        state = value;
      }
    } catch (e) {
      debugPrint('[AutoSaveNotifier] Failed to load setting: $e');
    }
  }

  /// Toggle auto-save.
  Future<void> toggle() async {
    state = !state;
    try {
      await _storage.setSetting<bool>(_key, state);
    } catch (e) {
      debugPrint('[AutoSaveNotifier] Failed to save setting: $e');
    }
  }
}

/// Provider for auto-save setting.
final autoSaveProvider = StateNotifierProvider<AutoSaveNotifier, bool>(
  (ref) => AutoSaveNotifier(ref.watch(storageServiceProvider)),
);

// ─── Settings Screen ───────────────────────────────────────────────

/// Whether the settings screen is currently open.
///
/// Used to prevent multiple settings screens from stacking.
final settingsScreenOpenProvider = StateProvider<bool>((ref) => false);

/// The currently selected settings category tab.
///
/// Values: 'general', 'editor', 'api', 'github', 'about'.
final settingsTabProvider = StateProvider<String>((ref) => 'general');

// ─── Derived: Editor Settings Bundle ───────────────────────────────

/// Bundle of all editor-related settings for easy consumption.
///
/// ```dart
/// final editorSettings = ref.watch(editorSettingsBundleProvider);
/// TextField(
///   style: TextStyle(
///     fontSize: editorSettings.fontSize,
///     fontFamily: editorSettings.fontFamily,
///   ),
/// )
/// ```
final editorSettingsBundleProvider = Provider<EditorSettings>((ref) {
  return EditorSettings(
    fontSize: ref.watch(fontSizeProvider),
    fontFamily: ref.watch(fontFamilyProvider),
    showLineNumbers: ref.watch(showLineNumbersProvider),
    wordWrap: ref.watch(wordWrapSettingProvider),
    tabSize: ref.watch(tabSizeProvider),
    useSpaces: ref.watch(useSpacesProvider),
    autoSave: ref.watch(autoSaveProvider),
  );
});

/// Immutable bundle of editor settings.
class EditorSettings {
  final double fontSize;
  final String fontFamily;
  final bool showLineNumbers;
  final bool wordWrap;
  final int tabSize;
  final bool useSpaces;
  final bool autoSave;

  const EditorSettings({
    required this.fontSize,
    required this.fontFamily,
    required this.showLineNumbers,
    required this.wordWrap,
    required this.tabSize,
    required this.useSpaces,
    required this.autoSave,
  });

  EditorSettings copyWith({
    double? fontSize,
    String? fontFamily,
    bool? showLineNumbers,
    bool? wordWrap,
    int? tabSize,
    bool? useSpaces,
    bool? autoSave,
  }) {
    return EditorSettings(
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      showLineNumbers: showLineNumbers ?? this.showLineNumbers,
      wordWrap: wordWrap ?? this.wordWrap,
      tabSize: tabSize ?? this.tabSize,
      useSpaces: useSpaces ?? this.useSpaces,
      autoSave: autoSave ?? this.autoSave,
    );
  }
}
