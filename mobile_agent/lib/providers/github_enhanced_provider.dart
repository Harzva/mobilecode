// lib/providers/github_enhanced_provider.dart
//
// Enhanced GitHub Provider with pagination, search, and filter state.
//
// This provider builds on top of the basic github_provider.dart and adds:
// - Paginated repository list with search/filter
// - Repository sorting (name, updated, stars, pushed)
// - Search state persistence
// - Filter state persistence
// - Selected repository
// - Issue/PR filter state
// - Notification unread count
// - Rate limit status

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/github_repo.dart';
import '../services/github_cache_service.dart';
import '../services/github_deep_service.dart';
import 'github_provider.dart';

// =============================================================================
// ENUMS
// =============================================================================

/// Sort options for repository lists.
enum RepoSort {
  /// Sort alphabetically by name.
  name,

  /// Sort by most recently updated.
  updated,

  /// Sort by most stars (descending).
  stars,

  /// Sort by most recently pushed.
  pushed,
}

/// Extension methods for [RepoSort].
extension RepoSortExtension on RepoSort {
  /// The API sort parameter value.
  String get apiValue {
    switch (this) {
      case RepoSort.name:
        return 'full_name';
      case RepoSort.updated:
        return 'updated';
      case RepoSort.stars:
        return 'stars';
      case RepoSort.pushed:
        return 'pushed';
    }
  }

  /// Human-readable display label.
  String get label {
    switch (this) {
      case RepoSort.name:
        return '\u6309\u540d\u79f0'; // 按名称
      case RepoSort.updated:
        return '\u6700\u8fd1\u66f4\u65b0'; // 最近更新
      case RepoSort.stars:
        return '\u6700\u591a\u661f\u6807'; // 最多星标
      case RepoSort.pushed:
        return '\u6700\u8fd1\u63a8\u9001'; // 最近推送
    }
  }
}

/// Filter options for repository lists.
enum RepoFilter {
  /// Show all accessible repositories.
  all,

  /// Show only repositories owned by the authenticated user.
  owner,

  /// Show only repositories where user is a member.
  member,

  /// Show only repositories where user is a collaborator.
  collaborator,
}

/// Extension methods for [RepoFilter].
extension RepoFilterExtension on RepoFilter {
  /// The API type parameter value.
  String get apiValue {
    switch (this) {
      case RepoFilter.all:
        return 'all';
      case RepoFilter.owner:
        return 'owner';
      case RepoFilter.member:
        return 'member';
      case RepoFilter.collaborator:
        return 'collaborator';
    }
  }

  /// Human-readable display label.
  String get label {
    switch (this) {
      case RepoFilter.all:
        return '\u5168\u90e8'; // 全部
      case RepoFilter.owner:
        return '\u6211\u7684'; // 我的
      case RepoFilter.member:
        return '\u6210\u5458'; // 成员
      case RepoFilter.collaborator:
        return '\u534f\u4f5c\u8005'; // 协作者
    }
  }
}

/// State filter for issues and pull requests.
enum IssueStateFilter {
  open,
  closed,
  all,
}

/// Extension methods for [IssueStateFilter].
extension IssueStateFilterExtension on IssueStateFilter {
  String get apiValue {
    switch (this) {
      case IssueStateFilter.open:
        return 'open';
      case IssueStateFilter.closed:
        return 'closed';
      case IssueStateFilter.all:
        return 'all';
    }
  }

  String get label {
    switch (this) {
      case IssueStateFilter.open:
        return '\u5f00\u653e\u4e2d'; // 开放中
      case IssueStateFilter.closed:
        return '\u5df2\u5173\u95ed'; // 已关闭
      case IssueStateFilter.all:
        return '\u5168\u90e8'; // 全部
    }
  }
}

// =============================================================================
// DEEP SERVICE PROVIDER
// =============================================================================

/// Provider for the deep GitHub service with full API coverage.
///
/// Falls back to a basic instance if the apiServiceProvider is not available.
final gitHubDeepServiceProvider = Provider<GitHubDeepService>((ref) {
  final service = GitHubDeepService();

  // Initialize on first use
  service.initialize().then((_) {
    debugPrint('[GitHubDeepService] Auto-initialized');
  }).catchError((e) {
    debugPrint('[GitHubDeepService] Auto-init failed: $e');
  });

  ref.onDispose(() => service.dispose());
  return service;
});

// =============================================================================
// SIMPLE STATE PROVIDERS (StateProvider for filter/sort/search state)
// =============================================================================

/// Current sort option for the repository list.
final githubReposSortProvider = StateProvider<RepoSort>((ref) => RepoSort.pushed);

/// Current filter option for the repository list.
final githubReposFilterProvider = StateProvider<RepoFilter>((ref) => RepoFilter.all);

/// Current search query for the repository list.
/// Empty string means no search filter.
final githubReposSearchProvider = StateProvider<String>((ref) => '');

/// Currently selected repository (null if none selected).
final githubSelectedRepoProvider = StateProvider<GitHubRepo?>((ref) => null);

/// Current issue state filter.
final githubIssuesFilterProvider = StateProvider<IssueStateFilter>(
  (ref) => IssueStateFilter.open,
);

/// Current PR state filter.
final githubPrsFilterProvider = StateProvider<IssueStateFilter>(
  (ref) => IssueStateFilter.open,
);

/// Current page number for paginated repo list (1-based).
final githubReposPageProvider = StateProvider<int>((ref) => 1);

/// Number of items per page.
final githubReposPerPageProvider = StateProvider<int>((ref) => 30);

// =============================================================================
// PAGINATED REPOSITORIES NOTIFIER
// =============================================================================

/// State for the paginated repository list.
class GitHubReposState {
  final List<GitHubRepo> repos;
  final int page;
  final int perPage;
  final bool hasNextPage;
  final bool hasPrevPage;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;

  const GitHubReposState({
    this.repos = const [],
    this.page = 1,
    this.perPage = 30,
    this.hasNextPage = false,
    this.hasPrevPage = false,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  GitHubReposState copyWith({
    List<GitHubRepo>? repos,
    int? page,
    int? perPage,
    bool? hasNextPage,
    bool? hasPrevPage,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
  }) {
    return GitHubReposState(
      repos: repos ?? this.repos,
      page: page ?? this.page,
      perPage: perPage ?? this.perPage,
      hasNextPage: hasNextPage ?? this.hasNextPage,
      hasPrevPage: hasPrevPage ?? this.hasPrevPage,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: error ?? this.error,
    );
  }

  /// Get filtered and sorted repositories based on search query.
  ///
  /// This is a client-side filter applied on top of the API results.
  List<GitHubRepo> getFilteredRepos(String searchQuery) {
    if (searchQuery.isEmpty) return repos;
    final lower = searchQuery.toLowerCase();
    return repos.where((repo) {
      return repo.name.toLowerCase().contains(lower) ||
          repo.owner.toLowerCase().contains(lower) ||
          repo.description.toLowerCase().contains(lower) ||
          repo.topics.any((t) => t.toLowerCase().contains(lower)) ||
          (repo.language?.toLowerCase().contains(lower) ?? false);
    }).toList();
  }

  /// Get sorted repositories based on sort option.
  List<GitHubRepo> getSortedRepos(RepoSort sort) {
    final sorted = List<GitHubRepo>.from(repos);
    switch (sort) {
      case RepoSort.name:
        sorted.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case RepoSort.updated:
        sorted.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case RepoSort.stars:
        sorted.sort((a, b) => b.stars.compareTo(a.stars));
      case RepoSort.pushed:
        sorted.sort((a, b) => b.pushedAt.compareTo(a.pushedAt));
    }
    return sorted;
  }

  /// Apply both sort and filter.
  List<GitHubRepo> getProcessedRepos(RepoSort sort, String searchQuery) {
    var result = getFilteredRepos(searchQuery);
    // Re-sort after filtering
    switch (sort) {
      case RepoSort.name:
        result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case RepoSort.updated:
        result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case RepoSort.stars:
        result.sort((a, b) => b.stars.compareTo(a.stars));
      case RepoSort.pushed:
        result.sort((a, b) => b.pushedAt.compareTo(a.pushedAt));
    }
    return result;
  }
}

/// StateNotifier that manages paginated repository fetching.
class GitHubReposNotifier extends StateNotifier<GitHubReposState> {
  final Ref _ref;
  GitHubDeepService? _service;

  GitHubReposNotifier(this._ref) : super(const GitHubReposState());

  GitHubDeepService get _ensureService {
    _service ??= _ref.read(gitHubDeepServiceProvider);
    return _service!;
  }

  /// Load the first page of repositories.
  ///
  /// Call this on initial load or pull-to-refresh.
  Future<void> loadRepos({
    RepoSort? sort,
    RepoFilter? filter,
  }) async {
    final effectiveSort = sort ?? _ref.read(githubReposSortProvider);
    final effectiveFilter = filter ?? _ref.read(githubReposFilterProvider);
    final perPage = _ref.read(githubReposPerPageProvider);

    state = state.copyWith(isLoading: true, error: null);

    try {
      final result = await _ensureService.getReposPaginated(
        page: 1,
        perPage: perPage,
        sort: effectiveSort.apiValue,
        type: effectiveFilter.apiValue,
      );

      state = GitHubReposState(
        repos: result.items,
        page: 1,
        perPage: perPage,
        hasNextPage: result.hasNextPage,
        hasPrevPage: false,
        isLoading: false,
      );

      // Reset page counter
      _ref.read(githubReposPageProvider.notifier).state = 1;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Load the next page of repositories.
  ///
  /// Appends new items to the existing list.
  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasNextPage) return;

    final nextPage = state.page + 1;
    final sort = _ref.read(githubReposSortProvider);
    final filter = _ref.read(githubReposFilterProvider);

    state = state.copyWith(isLoadingMore: true);

    try {
      final result = await _ensureService.getReposPaginated(
        page: nextPage,
        perPage: state.perPage,
        sort: sort.apiValue,
        type: filter.apiValue,
      );

      state = state.copyWith(
        repos: [...state.repos, ...result.items],
        page: nextPage,
        hasNextPage: result.hasNextPage,
        isLoadingMore: false,
      );

      _ref.read(githubReposPageProvider.notifier).state = nextPage;
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }

  /// Refresh the current page (pull-to-refresh).
  Future<void> refresh() async {
    await loadRepos();
  }

  /// Invalidate cache and reload.
  Future<void> forceRefresh() async {
    _ensureService.clearCache();
    await loadRepos();
  }

  /// Select a repository.
  void selectRepo(GitHubRepo? repo) {
    _ref.read(githubSelectedRepoProvider.notifier).state = repo;
  }
}

/// Enhanced provider for paginated repository list.
///
/// Provides state management for:
/// - Loading and pagination
/// - Sort and filter application
/// - Search query filtering
///
/// ```dart
/// final reposState = ref.watch(githubEnhancedReposProvider);
/// reposState.when(...)
///
/// // Load more
/// ref.read(githubEnhancedReposProvider.notifier).loadMore();
/// ```
final githubEnhancedReposProvider =
    StateNotifierProvider<GitHubReposNotifier, GitHubReposState>((ref) {
  return GitHubReposNotifier(ref);
});

/// Derived provider: processed repository list (sorted + filtered + searched).
///
/// This provider combines the raw repos with sort, filter, and search
/// to produce the final list shown in the UI.
final githubProcessedReposProvider = Provider<List<GitHubRepo>>((ref) {
  final state = ref.watch(githubEnhancedReposProvider);
  final sort = ref.watch(githubReposSortProvider);
  final searchQuery = ref.watch(githubReposSearchProvider);

  return state.getProcessedRepos(sort, searchQuery);
});

/// Derived provider: whether more repos can be loaded.
final githubReposCanLoadMoreProvider = Provider<bool>((ref) {
  final state = ref.watch(githubEnhancedReposProvider);
  return state.hasNextPage && !state.isLoadingMore;
});

// =============================================================================
// PAGINATED ISSUES NOTIFIER
// =============================================================================

/// State for paginated issues.
class GitHubIssuesState {
  final List<dynamic> issues;
  final int page;
  final int perPage;
  final bool hasNextPage;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;

  const GitHubIssuesState({
    this.issues = const [],
    this.page = 1,
    this.perPage = 30,
    this.hasNextPage = false,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  GitHubIssuesState copyWith({
    List<dynamic>? issues,
    int? page,
    int? perPage,
    bool? hasNextPage,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
  }) {
    return GitHubIssuesState(
      issues: issues ?? this.issues,
      page: page ?? this.page,
      perPage: perPage ?? this.perPage,
      hasNextPage: hasNextPage ?? this.hasNextPage,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: error ?? this.error,
    );
  }
}

/// StateNotifier for paginated issues.
class GitHubIssuesNotifier extends StateNotifier<GitHubIssuesState> {
  final Ref _ref;
  GitHubDeepService? _service;

  GitHubIssuesNotifier(this._ref) : super(const GitHubIssuesState());

  GitHubDeepService get _ensureService {
    _service ??= _ref.read(gitHubDeepServiceProvider);
    return _service!;
  }

  /// Load issues for a repository.
  Future<void> loadIssues(
    String owner,
    String repo, {
    IssueStateFilter? stateFilter,
  }) async {
    final filter = stateFilter ?? _ref.read(githubIssuesFilterProvider);

    state = state.copyWith(isLoading: true, error: null);

    try {
      final result = await _ensureService.getIssuesPaginated(
        owner,
        repo,
        page: 1,
        perPage: 30,
        state: filter.apiValue,
      );

      state = GitHubIssuesState(
        issues: result.items,
        page: 1,
        perPage: 30,
        hasNextPage: result.hasNextPage,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Load more issues.
  Future<void> loadMore(String owner, String repo) async {
    if (state.isLoading || state.isLoadingMore || !state.hasNextPage) return;

    final nextPage = state.page + 1;
    final filter = _ref.read(githubIssuesFilterProvider);

    state = state.copyWith(isLoadingMore: true);

    try {
      final result = await _ensureService.getIssuesPaginated(
        owner,
        repo,
        page: nextPage,
        perPage: state.perPage,
        state: filter.apiValue,
      );

      state = state.copyWith(
        issues: [...state.issues, ...result.items],
        page: nextPage,
        hasNextPage: result.hasNextPage,
        isLoadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }

  void clear() {
    state = const GitHubIssuesState();
  }
}

/// Provider for paginated issues of the selected repository.
final githubEnhancedIssuesProvider =
    StateNotifierProvider<GitHubIssuesNotifier, GitHubIssuesState>((ref) {
  return GitHubIssuesNotifier(ref);
});

// =============================================================================
// PAGINATED PULL REQUESTS NOTIFIER
// =============================================================================

/// State for paginated pull requests.
class GitHubPrsState {
  final List<dynamic> pullRequests;
  final int page;
  final int perPage;
  final bool hasNextPage;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;

  const GitHubPrsState({
    this.pullRequests = const [],
    this.page = 1,
    this.perPage = 30,
    this.hasNextPage = false,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  GitHubPrsState copyWith({
    List<dynamic>? pullRequests,
    int? page,
    int? perPage,
    bool? hasNextPage,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
  }) {
    return GitHubPrsState(
      pullRequests: pullRequests ?? this.pullRequests,
      page: page ?? this.page,
      perPage: perPage ?? this.perPage,
      hasNextPage: hasNextPage ?? this.hasNextPage,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: error ?? this.error,
    );
  }
}

/// StateNotifier for paginated pull requests.
class GitHubPrsNotifier extends StateNotifier<GitHubPrsState> {
  final Ref _ref;
  GitHubDeepService? _service;

  GitHubPrsNotifier(this._ref) : super(const GitHubPrsState());

  GitHubDeepService get _ensureService {
    _service ??= _ref.read(gitHubDeepServiceProvider);
    return _service!;
  }

  /// Load pull requests for a repository.
  Future<void> loadPullRequests(
    String owner,
    String repo, {
    IssueStateFilter? stateFilter,
  }) async {
    final filter = stateFilter ?? _ref.read(githubPrsFilterProvider);

    state = state.copyWith(isLoading: true, error: null);

    try {
      final result = await _ensureService.getPullRequestsPaginated(
        owner,
        repo,
        page: 1,
        perPage: 30,
        state: filter.apiValue,
      );

      state = GitHubPrsState(
        pullRequests: result.items,
        page: 1,
        perPage: 30,
        hasNextPage: result.hasNextPage,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Load more pull requests.
  Future<void> loadMore(String owner, String repo) async {
    if (state.isLoading || state.isLoadingMore || !state.hasNextPage) return;

    final nextPage = state.page + 1;
    final filter = _ref.read(githubPrsFilterProvider);

    state = state.copyWith(isLoadingMore: true);

    try {
      final result = await _ensureService.getPullRequestsPaginated(
        owner,
        repo,
        page: nextPage,
        perPage: state.perPage,
        state: filter.apiValue,
      );

      state = state.copyWith(
        pullRequests: [...state.pullRequests, ...result.items],
        page: nextPage,
        hasNextPage: result.hasNextPage,
        isLoadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }

  void clear() {
    state = const GitHubPrsState();
  }
}

/// Provider for paginated pull requests of the selected repository.
final githubEnhancedPrsProvider =
    StateNotifierProvider<GitHubPrsNotifier, GitHubPrsState>((ref) {
  return GitHubPrsNotifier(ref);
});

// =============================================================================
// NOTIFICATIONS
// =============================================================================

/// Unread notification count (refreshed periodically).
///
/// Returns the number of unread GitHub notifications.
final githubNotificationsUnreadProvider = FutureProvider<int>((ref) async {
  final service = ref.watch(gitHubDeepServiceProvider);
  if (!service.isAuthenticated) return 0;

  try {
    return await service.getUnreadNotificationCount();
  } catch (e) {
    debugPrint('[githubNotificationsUnreadProvider] Error: $e');
    return 0;
  }
});

// =============================================================================
// RATE LIMIT
// =============================================================================

/// Current GitHub API rate limit status.
///
/// Auto-refreshes every 5 minutes. Returns null if not authenticated
/// or if the request fails.
final githubRateLimitProvider = FutureProvider<RateLimit?>((ref) async {
  final service = ref.watch(gitHubDeepServiceProvider);
  if (!service.isAuthenticated) return null;

  try {
    return await service.getRateLimit();
  } catch (e) {
    debugPrint('[githubRateLimitProvider] Error: $e');
    return null;
  }
});

// =============================================================================
// REPOSITORY DETAILS
// =============================================================================

/// Provider for the currently selected repository's details.
///
/// Fetches fresh details from the API when the selected repo changes.
final githubSelectedRepoDetailsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final repo = ref.watch(githubSelectedRepoProvider);
  if (repo == null) return {};

  final service = ref.watch(gitHubDeepServiceProvider);
  try {
    return await service.getRepoDetails(repo.owner, repo.name);
  } catch (e) {
    debugPrint('[githubSelectedRepoDetailsProvider] Error: $e');
    return {};
  }
});

/// Provider for the selected repository's language breakdown.
final githubRepoLanguagesProvider = FutureProvider<Map<String, int>>((ref) async {
  final repo = ref.watch(githubSelectedRepoProvider);
  if (repo == null) return {};

  final service = ref.watch(gitHubDeepServiceProvider);
  try {
    return await service.getRepoLanguages(repo.owner, repo.name);
  } catch (e) {
    debugPrint('[githubRepoLanguagesProvider] Error: $e');
    return {};
  }
});

/// Provider for the selected repository's README content.
final githubRepoReadmeProvider = FutureProvider<String>((ref) async {
  final repo = ref.watch(githubSelectedRepoProvider);
  if (repo == null) return '';

  final service = ref.watch(gitHubDeepServiceProvider);
  try {
    return await service.getReadmeContent(repo.owner, repo.name);
  } catch (e) {
    debugPrint('[githubRepoReadmeProvider] Error: $e');
    return '';
  }
});

/// Provider for whether the user can push to the selected repo.
final githubCanPushProvider = FutureProvider<bool>((ref) async {
  final repo = ref.watch(githubSelectedRepoProvider);
  if (repo == null) return false;

  final service = ref.watch(gitHubDeepServiceProvider);
  try {
    return await service.canPush(repo.owner, repo.name);
  } catch (e) {
    debugPrint('[githubCanPushProvider] Error: $e');
    return false;
  }
});

// =============================================================================
// SEARCH
// =============================================================================

/// GitHub search query text.
final githubSearchQueryProvider = StateProvider<String>((ref) => '');

/// Search results for repositories.
final githubSearchReposProvider = FutureProvider<List<dynamic>>((ref) async {
  final query = ref.watch(githubSearchQueryProvider);
  if (query.isEmpty) return [];

  final service = ref.watch(gitHubDeepServiceProvider);
  if (!service.isAuthenticated) return [];

  try {
    return await service.searchRepositories(query);
  } catch (e) {
    debugPrint('[githubSearchReposProvider] Error: $e');
    return [];
  }
});

// =============================================================================
// CACHE STATS (Debug)
// =============================================================================

/// Provider for cache statistics (for debugging).
final githubCacheStatsProvider = Provider<CacheStats>((ref) {
  final service = ref.watch(gitHubDeepServiceProvider);
  return service.getCacheStats();
});
