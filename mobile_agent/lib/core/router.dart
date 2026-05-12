import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../screens/splash_screen.dart';
import '../screens/home_screen.dart';
import '../screens/editor_screen.dart';
import '../screens/project_screen.dart';
import '../screens/project_detail_screen.dart';
import '../screens/snippet_screen.dart';
import '../screens/snippet_editor_screen.dart';
import '../screens/github_screen.dart';
import '../screens/github_repo_screen.dart';
import '../screens/ai_chat_screen.dart';
import '../screens/api_config_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/team_hub_screen.dart';
import '../screens/team_members_screen.dart';
import '../screens/team_knowledge_screen.dart';
import '../screens/api_usage_screen.dart';
import '../screens/screenshot_to_code_screen.dart';
import '../services/screenshot_to_code_service.dart';

/// Global router provider for the application.
///
/// Provides the GoRouter instance configured with all application routes.
/// Access via: `ref.watch(routerProvider)`
final routerProvider = Provider<GoRouter>((ref) {
  return _createRouter();
});

/// Route path constants for type-safe navigation.
///
/// Usage:
/// ```dart
/// context.push(AppRoutes.editor);
/// context.push(AppRoutes.editorWithId('123'));
/// ```
class AppRoutes {
  AppRoutes._();

  static const String splash = '/splash';
  static const String home = '/';
  static const String editor = '/editor';
  static const String projects = '/projects';
  static const String projectDetail = '/project/:id';
  static const String snippets = '/snippets';
  static const String snippetEditor = '/snippet-editor';
  static const String github = '/github';
  static const String githubRepo = '/github/repo';
  static const String aiChat = '/ai-chat';
  static const String apiConfig = '/api-config';
  static const String settings = '/settings';
  static const String teamHub = '/team';
  static const String teamMembers = '/team/members';
  static const String teamKnowledge = '/team/knowledge';
  static const String apiUsage = '/api-usage';

  // ── New Routes ────────────────────────────────────────────────────

  /// Screenshot to Code - AI-powered UI screenshot to code conversion
  static const String screenshotToCode = '/screenshot-to-code';

  /// Agent Hub - Main AI agent control center
  static const String agent = '/agent';

  /// Terminal - Command runner (implemented by another team)
  static const String terminal = '/terminal';

  /// Generate editor route with optional project ID
  static String editorWithId(String? projectId) {
    if (projectId == null || projectId.isEmpty) return editor;
    return '$editor?projectId=$projectId';
  }

  /// Generate project editor route
  static String editorForProject(String projectId) => editorWithId(projectId);

  /// Generate screenshot-to-code route with optional target framework
  static String screenshotToCodeWithFramework(String? framework) {
    if (framework == null || framework.isEmpty) return screenshotToCode;
    return '$screenshotToCode?framework=$framework';
  }
}

/// Creates and configures the GoRouter instance.
GoRouter _createRouter() {
  return GoRouter(
    initialLocation: AppRoutes.home,
    debugLogDiagnostics: false,

    // Global error handler for unknown routes
    errorBuilder: (context, state) => _ErrorScreen(
      error: state.error,
      location: state.uri.toString(),
    ),

    routes: [
      // ── Splash ────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.splash,
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),

      // ── Home ──────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.home,
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),

      // ── Editor ────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.editor,
        name: 'editor',
        builder: (context, state) {
          final projectId = state.uri.queryParameters['projectId'];
          final filePath = state.uri.queryParameters['filePath'];
          return EditorScreen(
            projectId: projectId,
            initialFilePath: filePath,
          );
        },
      ),

      // ── Projects ──────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.projects,
        name: 'projects',
        builder: (context, state) => const ProjectScreen(),
      ),

      // ── Project Detail ────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.projectDetail,
        name: 'project-detail',
        builder: (context, state) {
          final projectId = state.pathParameters['id']!;
          return ProjectDetailScreen(projectId: projectId);
        },
      ),

      // ── Snippets ──────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.snippets,
        name: 'snippets',
        builder: (context, state) => const SnippetScreen(),
      ),

      // ── Snippet Editor ────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.snippetEditor,
        name: 'snippet-editor',
        builder: (context, state) {
          final snippetId = state.uri.queryParameters['id'];
          return SnippetEditorScreen(snippetId: snippetId);
        },
      ),

      // ── GitHub ────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.github,
        name: 'github',
        builder: (context, state) => const GitHubScreen(),
      ),

      // ── GitHub Repo ───────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.githubRepo,
        name: 'github-repo',
        builder: (context, state) {
          final owner = state.uri.queryParameters['owner']!;
          final repo = state.uri.queryParameters['repo']!;
          return GitHubRepoScreen(owner: owner, repo: repo);
        },
      ),

      // ── AI Chat ───────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.aiChat,
        name: 'ai-chat',
        builder: (context, state) {
          final codeContext = state.uri.queryParameters['code'];
          return AiChatScreen(initialCodeContext: codeContext);
        },
      ),

      // ── API Configuration ─────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.apiConfig,
        name: 'api-config',
        builder: (context, state) => const ApiConfigScreen(),
      ),

      // ── Settings ──────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.settings,
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),

      // ── Team Hub ──────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.teamHub,
        name: 'team-hub',
        builder: (context, state) => const TeamHubScreen(),
      ),

      // ── Team Members ──────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.teamMembers,
        name: 'team-members',
        builder: (context, state) => const TeamMembersScreen(),
      ),

      // ── Team Knowledge ────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.teamKnowledge,
        name: 'team-knowledge',
        builder: (context, state) => const TeamKnowledgeScreen(),
      ),

      // ── API Usage ─────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.apiUsage,
        name: 'api-usage',
        builder: (context, state) => const ApiUsageScreen(),
      ),

      // ═══════════════════════════════════════════════════════════════════
      // NEW ROUTES
      // ═══════════════════════════════════════════════════════════════════

      // ── Screenshot to Code ────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.screenshotToCode,
        name: 'screenshot-to-code',
        builder: (context, state) {
          final frameworkParam = state.uri.queryParameters['framework'];
          final framework = frameworkParam != null
              ? TargetFramework.values.firstWhere(
                  (f) => f.name == frameworkParam,
                  orElse: () => TargetFramework.flutter,
                )
              : null;
          return ScreenshotToCodeScreen(
            initialFramework: framework,
          );
        },
      ),

      // ── Agent Hub ─────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.agent,
        name: 'agent',
        builder: (context, state) => const _AgentHubPlaceholderScreen(),
      ),

      // ── Terminal ──────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.terminal,
        name: 'terminal',
        builder: (context, state) => const _TerminalPlaceholderScreen(),
      ),
    ],
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Placeholder Screens for Stub Routes
// ═══════════════════════════════════════════════════════════════════════════

/// Placeholder screen for the Agent Hub route.
///
/// TODO: Replace with the full AgentHubScreen when implemented.
/// This serves as the main control center for AI agent capabilities.
class _AgentHubPlaceholderScreen extends StatelessWidget {
  const _AgentHubPlaceholderScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent Hub'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.home),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.purple, Colors.deepPurple],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.smart_toy,
                size: 40,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Agent Hub',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'AI Agent Control Center\n(Coming Soon)',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => context.go(AppRoutes.home),
              icon: const Icon(Icons.home),
              label: const Text('Go Home'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder screen for the Terminal route.
///
/// TODO: Replace with the full TerminalScreen when implemented by the
/// responsible team. Provides command-line interface within the app.
class _TerminalPlaceholderScreen extends StatelessWidget {
  const _TerminalPlaceholderScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terminal'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.home),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.terminal,
                size: 40,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Terminal',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Command Runner\n(Under Development)',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => context.go(AppRoutes.home),
              icon: const Icon(Icons.home),
              label: const Text('Go Home'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error Screen (internal) ──────────────────────────────────────────────

/// Error screen displayed when navigation fails.
class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({
    this.error,
    required this.location,
  });

  final Exception? error;
  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              'Page Not Found',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'The route "$location" does not exist.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.red,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go(AppRoutes.home),
              child: const Text('Go Home'),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Navigation Extensions
// ═══════════════════════════════════════════════════════════════════════════

/// Extension on [BuildContext] for convenient navigation helpers.
///
/// Provides semantic navigation methods that wrap GoRouter calls:
/// ```dart
/// context.goHome();
/// context.goEditor(projectId: '123');
/// context.pushSnippets();
/// ```
extension NavigationExtension on BuildContext {
  // ── Go (replace current route) ──────────────────────────────────────

  /// Navigate to home screen
  void goHome() => go(AppRoutes.home);

  /// Navigate to editor screen
  void goEditor({String? projectId, String? filePath}) {
    final uri = Uri(
      path: AppRoutes.editor,
      queryParameters: {
        if (projectId != null) 'projectId': projectId,
        if (filePath != null) 'filePath': filePath,
      },
    );
    go(uri.toString());
  }

  /// Navigate to projects screen
  void goProjects() => go(AppRoutes.projects);

  /// Navigate to snippets screen
  void goSnippets() => go(AppRoutes.snippets);

  /// Navigate to GitHub screen
  void goGitHub() => go(AppRoutes.github);

  /// Navigate to API config screen
  void goApiConfig() => go(AppRoutes.apiConfig);

  /// Navigate to settings screen
  void goSettings() => go(AppRoutes.settings);

  /// Navigate to team hub screen
  void goTeamHub() => go(AppRoutes.teamHub);

  /// Navigate to team members screen
  void goTeamMembers() => go(AppRoutes.teamMembers);

  /// Navigate to team knowledge screen
  void goTeamKnowledge() => go(AppRoutes.teamKnowledge);

  /// Navigate to API usage screen
  void goApiUsage() => go(AppRoutes.apiUsage);

  // ── New Go Helpers ────────────────────────────────────────────────

  /// Navigate to Screenshot to Code screen
  void goScreenshotToCode({String? framework}) =>
      go(AppRoutes.screenshotToCodeWithFramework(framework));

  /// Navigate to Agent Hub screen
  void goAgentHub() => go(AppRoutes.agent);

  /// Navigate to Terminal screen
  void goTerminal() => go(AppRoutes.terminal);

  // ── Push (add to navigation stack) ──────────────────────────────────

  /// Push editor screen onto stack
  void pushEditor({String? projectId, String? filePath}) {
    final uri = Uri(
      path: AppRoutes.editor,
      queryParameters: {
        if (projectId != null) 'projectId': projectId,
        if (filePath != null) 'filePath': filePath,
      },
    );
    push(uri.toString());
  }

  /// Push projects screen onto stack
  void pushProjects() => push(AppRoutes.projects);

  /// Push snippets screen onto stack
  void pushSnippets() => push(AppRoutes.snippets);

  /// Push GitHub screen onto stack
  void pushGitHub() => push(AppRoutes.github);

  /// Push API config screen onto stack
  void pushApiConfig() => push(AppRoutes.apiConfig);

  /// Push settings screen onto stack
  void pushSettings() => push(AppRoutes.settings);

  /// Push team hub screen onto stack
  void pushTeamHub() => push(AppRoutes.teamHub);

  /// Push team members screen onto stack
  void pushTeamMembers() => push(AppRoutes.teamMembers);

  /// Push team knowledge screen onto stack
  void pushTeamKnowledge() => push(AppRoutes.teamKnowledge);

  /// Push API usage screen onto stack
  void pushApiUsage() => push(AppRoutes.apiUsage);

  // ── New Push Helpers ──────────────────────────────────────────────

  /// Push Screenshot to Code screen onto stack
  void pushScreenshotToCode({String? framework}) =>
      push(AppRoutes.screenshotToCodeWithFramework(framework));

  /// Push Agent Hub screen onto stack
  void pushAgentHub() => push(AppRoutes.agent);

  /// Push Terminal screen onto stack
  void pushTerminal() => push(AppRoutes.terminal);
}

// ═══════════════════════════════════════════════════════════════════════════
// Bottom Sheet Helpers
// ═══════════════════════════════════════════════════════════════════════════

/// Extension for showing modal bottom sheets that are not route-based.
///
/// These are UI components that overlay the current screen rather than
/// navigating to a new route.
extension BottomSheetHelpers on BuildContext {
  /// Shows the Voice Input Panel as a modal bottom sheet.
  ///
  /// VoiceInputPanel is a bottom sheet modal and does not have a dedicated
  /// route. Use this helper to display it from anywhere in the app.
  ///
  /// Example:
  /// ```dart
  /// context.showVoiceInputPanel(
  ///   onConfirm: (transcript, intent) { ... },
  /// );
  /// ```
  Future<void> showVoiceInputPanel({
    void Function(String transcript, dynamic intent)? onConfirm,
    VoidCallback? onCancel,
  }) async {
    await showModalBottomSheet(
      context: this,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VoiceInputPanelPlaceholder(
        onConfirm: onConfirm,
        onCancel: onCancel,
      ),
    );
  }
}

/// Internal placeholder for VoiceInputPanel to avoid circular imports.
///
/// The actual VoiceInputPanel lives in `../widgets/voice_input_panel.dart`.
/// Import it directly in the screen where you need to show it:
///
/// ```dart
/// import '../widgets/voice_input_panel.dart';
///
/// showModalBottomSheet(
///   context: context,
///   isScrollControlled: true,
///   backgroundColor: Colors.transparent,
///   builder: (_) => const VoiceInputPanel(),
/// );
/// ```
///
/// This stub exists so the router extension methods compile without
/// importing widget-level code. Screens should import and use the
/// real VoiceInputPanel directly.
class VoiceInputPanelPlaceholder extends StatelessWidget {
  final void Function(String transcript, dynamic intent)? onConfirm;
  final VoidCallback? onCancel;

  const VoiceInputPanelPlaceholder({
    super.key,
    this.onConfirm,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 420,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.keyboard_voice,
              size: 48,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              'Voice Input Panel',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Import VoiceInputPanel from\n../widgets/voice_input_panel.dart',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
