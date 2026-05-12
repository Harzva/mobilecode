// lib/providers/github_provider.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/github_repo.dart';
import '../services/api_service.dart';
import '../services/github_service.dart';

// ─── Service Provider ──────────────────────────────────────────────

/// Provider for the GitHub API service.
///
/// Lazily created from the shared [ApiService].
/// Use [githubServiceProvider] to access the service directly
/// for operations not covered by state providers.
///
/// ```dart
/// final ghService = ref.read(githubServiceProvider);
/// await ghService.authenticate(token);
/// ```
final githubServiceProvider = Provider<GitHubService>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return GitHubService(apiService);
});

/// Provider for the shared [ApiService].
/// Override this in main.dart with the initialized singleton.
final apiServiceProvider = Provider<ApiService>((ref) {
  throw UnimplementedError(
    'apiServiceProvider must be overridden in the ProviderScope during app initialization.',
  );
});

// ─── Authentication State ──────────────────────────────────────────

/// Whether the user is authenticated with GitHub.
///
/// Updated after [authenticate] or [logout] calls.
/// Use this to show/hide GitHub-connected UI.
///
/// ```dart
/// final isAuthed = ref.watch(githubAuthProvider);
/// if (isAuthed) { ... }
/// ```
final githubAuthProvider = StateProvider<bool>((ref) => false);

/// The current GitHub personal access token.
///
/// Empty string means no token is set.
/// Set via the settings screen.
final githubTokenProvider = StateProvider<String>((ref) => '');

/// The authenticated GitHub user's login name.
///
/// Null if not authenticated. Set after successful authentication.
final githubUserProvider = StateProvider<String?>((ref) => null);

// ─── Repositories ──────────────────────────────────────────────────

/// Provider that fetches the authenticated user's repositories.
///
/// Automatically refreshes when [githubAuthProvider] changes to true.
/// Returns [AsyncValue] to handle loading/error states.
///
/// ```dart
/// final reposAsync = ref.watch(githubReposProvider);
/// reposAsync.when(
///   data: (repos) => RepoList(repos: repos),
///   loading: () => CircularProgressIndicator(),
///   error: (e, _) => Text('Error: $e'),
/// );
/// ```
final githubReposProvider = FutureProvider<List<GitHubRepo>>((ref) async {
  final isAuth = ref.watch(githubAuthProvider);
  if (!isAuth) return [];

  final service = ref.watch(githubServiceProvider);
  return service.getRepositories();
});

// ─── Selected Repository ───────────────────────────────────────────

/// The currently selected GitHub repository.
///
/// Used when browsing a specific repo's contents.
/// Null means no repo is selected.
final selectedGitHubRepoProvider = StateProvider<GitHubRepo?>((ref) => null);

/// The current path within the selected GitHub repository.
///
/// Empty string means root. Used for breadcrumb navigation.
final githubRepoPathProvider = StateProvider<String>((ref) => '');

// ─── Repository Contents ───────────────────────────────────────────

/// Provider that fetches the contents of the selected repo path.
///
/// Automatically reloads when the selected repo or path changes.
/// Returns [AsyncValue<List<FileItem>>] for directory listings.
final githubRepoContentsProvider =
    FutureProvider<List<dynamic>>((ref) async {
  final repo = ref.watch(selectedGitHubRepoProvider);
  final path = ref.watch(githubRepoPathProvider);

  if (repo == null) return [];

  final service = ref.watch(githubServiceProvider);
  try {
    return await service.getRepoContents(repo.owner, repo.name, path);
  } catch (e) {
    debugPrint('[githubRepoContentsProvider] Error: $e');
    throw e;
  }
});

// ─── Issues ────────────────────────────────────────────────────────

/// Provider that fetches issues for the selected repository.
final githubIssuesProvider = FutureProvider<List<dynamic>>((ref) async {
  final repo = ref.watch(selectedGitHubRepoProvider);
  if (repo == null) return [];

  final service = ref.watch(githubServiceProvider);
  return service.getIssues(repo.owner, repo.name);
});

// ─── Authentication Actions ────────────────────────────────────────

/// Notifier for GitHub authentication actions.
class GitHubAuthNotifier extends StateNotifier<bool> {
  final Ref _ref;

  GitHubAuthNotifier(this._ref) : super(false);

  /// Authenticate with a GitHub personal access token.
  ///
  /// Validates the token and updates all auth-related providers.
  /// Returns true if authentication succeeds.
  Future<bool> authenticate(String token) async {
    if (token.isEmpty) {
      debugPrint('[GitHubAuthNotifier] Empty token provided');
      return false;
    }

    try {
      final service = _ref.read(githubServiceProvider);
      final success = await service.authenticate(token);

      if (success) {
        state = true;
        _ref.read(githubAuthProvider.notifier).state = true;
        _ref.read(githubTokenProvider.notifier).state = token;
        _ref.read(githubUserProvider.notifier).state = service.currentUser;

        // Invalidate repos cache to trigger reload.
        _ref.invalidate(githubReposProvider);

        debugPrint('[GitHubAuthNotifier] Authentication successful');
      } else {
        debugPrint('[GitHubAuthNotifier] Authentication failed');
      }

      return success;
    } catch (e) {
      // SECURITY: Don't log full error details which may contain tokens.
      debugPrint('[GitHubAuthNotifier] Auth error occurred');
      return false;
    }
  }

  /// Log out and clear all GitHub state.
  void logout() {
    _ref.read(githubServiceProvider).logout();

    state = false;
    _ref.read(githubAuthProvider.notifier).state = false;
    _ref.read(githubTokenProvider.notifier).state = '';
    _ref.read(githubUserProvider.notifier).state = null;
    _ref.read(selectedGitHubRepoProvider.notifier).state = null;
    _ref.read(githubRepoPathProvider.notifier).state = '';

    // Invalidate caches.
    _ref.invalidate(githubReposProvider);
    _ref.invalidate(githubRepoContentsProvider);
    _ref.invalidate(githubIssuesProvider);

    debugPrint('[GitHubAuthNotifier] Logged out');
  }
}

/// Provider for GitHub authentication actions.
///
/// Use this for login/logout operations.
final githubAuthActionsProvider =
    StateNotifierProvider<GitHubAuthNotifier, bool>(
  (ref) => GitHubAuthNotifier(ref),
);
