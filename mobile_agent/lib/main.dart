import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'themes/app_theme.dart';
import 'screens/home_screen.dart';

const _brandThemePrefsKey = 'mobilecode.brandTheme';
const _brandThemeCodexBlue = 'codexBlue';
const _brandThemeClaudeYellow = 'claudeYellow';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set preferred orientations
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.auroraSurface,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const ProviderScope(child: MobileAgentApp()));
}

/// Root app widget
class MobileAgentApp extends StatefulWidget {
  const MobileAgentApp({super.key});

  @override
  State<MobileAgentApp> createState() => _MobileAgentAppState();
}

class _MobileAgentAppState extends State<MobileAgentApp> {
  String _brandTheme = _brandThemeCodexBlue;

  @override
  void initState() {
    super.initState();
    _loadBrandTheme();
  }

  Future<void> _loadBrandTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_brandThemePrefsKey);
    if (!mounted || saved == null) return;
    setState(() => _brandTheme = _normalizeBrandTheme(saved));
  }

  Future<void> _setBrandTheme(String theme) async {
    final normalized = _normalizeBrandTheme(theme);
    if (_brandTheme != normalized) {
      setState(() => _brandTheme = normalized);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_brandThemePrefsKey, normalized);
  }

  String _normalizeBrandTheme(String theme) {
    return theme == _brandThemeClaudeYellow
        ? _brandThemeClaudeYellow
        : _brandThemeCodexBlue;
  }

  ThemeData get _activeLightTheme {
    return _brandTheme == _brandThemeClaudeYellow
        ? AppTheme.claudeYellowLightTheme
        : AppTheme.codexBlueLightTheme;
  }

  @override
  Widget build(BuildContext context) {
    final theme = _activeLightTheme;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: theme.colorScheme.surface,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    return MaterialApp(
      title: 'Mobile Agent',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      home: HomeScreen(
        brandTheme: _brandTheme,
        onBrandThemeChanged: _setBrandTheme,
      ),
    );
  }
}
