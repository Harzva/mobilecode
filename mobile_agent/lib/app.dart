import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/theme.dart';

/// Root application widget for Mobile Agent.
///
/// Configures the MaterialApp with:
/// - Dark theme from [AppTheme]
/// - GoRouter for declarative routing
/// - Riverpod integration for state management
/// - System-level UI configurations
class MobileAgentApp extends ConsumerWidget {
  const MobileAgentApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Mobile Agent',
      debugShowCheckedModeBanner: false,
      
      // Theme configuration
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark, // Default to dark theme for code editor
      
      // Routing
      routerConfig: router,
      
      // Localization
      // TODO: Add localization delegates
      // localizationsDelegates: AppLocalizations.localizationsDelegates,
      // supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}