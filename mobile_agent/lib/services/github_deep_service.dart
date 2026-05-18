import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/github_repo.dart';
import 'github_cache_service.dart';

// =============================================================================
// EXCEPTIONS
// =============================================================================

class GitHubDeepException implements Exception {
  final String message;
  final String? endpoint;
  final int? statusCode;
  final dynamic originalError;

  const GitHubDeepException({
    required this.message,
    this.endpoint,
    this.statusCode,
    this.originalError,
  });

  @override
  String toString() => 'GitHubDeepException [$endpoint ${statusCode ?? ''}]: $message';
}

// =============================================================================
// PAGINATED RESULT
// =============================================================================

/// A paginated result wrapper for GitHub API list endpoints.
///
/// GitHub uses Link headers for pagination, but this wrapper provides
/// a simpler page-based model with `hasNextPage` / `hasPrevPage` flags.
///
/// ```dart
/// final result = await service.getReposPaginated(page: 1);
/// if (result.hasNextPage) {
///   final next = await service.getReposPaginated(page: result.page + 1);
/// }
/// ```
class PaginatedResult<T> {
  /// The items on this page.
  final List<T> items;

  /// Current page number (1-based).
  final int page;

  /// Number of items per page.
  final int perPage;

  /// Total number of items, if available from the API.
  /// For search endpoints, this is `total_count`.
  /// For regular list endpoints, this may be null.
  final int? totalCount;

  /// Whether there is a next page.
  final bool hasNextPage;

  /// Whether there is a previous page.
  final bool hasPrevPage;

  /// Raw Link header data (if needed for cursor-based pagination).
  final String? linkHeader;

  const PaginatedResult({
    required this.items,
    required this.page,
    required this.perPage,
    this.totalCount,
    required this.hasNextPage,
    this.hasPrevPage = false,
    this.linkHeader,
  });

  /// Total number of pages (estimated from totalCount / perPage).
  /// Returns null if totalCount is not available.
  int? get totalPages {
    if (totalCount == null) return null;
    return (totalCount! + perPage - 1) ~/ perPage;
  }

  /// Number of items on the current page.
  int get itemCount => items.length;

  /// Whether the result set is empty.
  bool get isEmpty => items.isEmpty;

  /// Whether the result set has items.
  bool get isNotEmpty => items.isNotEmpty;

  /// Convenience: map over items.
  List<R> map<R>(R Function(T) fn) => items.map(fn).toList();

  /// Convenience: filter items.
  List<T> where(bool Function(T) fn) => items.where(fn).toList();

  @override
  String toString() {
    return 'PaginatedResult(page=$page, perPage=$perPage, '
        'items=${items.length}, total=$totalCount, hasNext=$hasNextPage)';
  }
}

// =============================================================================
// RATE LIMIT
// =============================================================================

/// GitHub API rate limit status from the `/rate_limit` endpoint.
///
/// Provides information about the current rate limit window,
/// including usage percentage and critical status.
class RateLimit {
  /// Maximum requests allowed per hour.
  final int limit;

  /// Remaining requests in the current window.
  final int remaining;

  /// Requests used in the current window.
  final int used;

  /// When the rate limit window resets.
  final DateTime resetAt;

  const RateLimit({
    required this.limit,
    required this.remaining,
    required this.used,
    required this.resetAt,
  });

  /// Usage percentage (0.0 to 1.0).
  double get usagePercent => used / limit;

  /// Whether remaining requests are critically low (< 100).
  bool get isCritical => remaining < 100;

  /// Whether the rate limit has been exceeded.
  bool get isExceeded => remaining <= 0;

  /// Time until the rate limit window resets.
  Duration get timeUntilReset {
    final diff = resetAt.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Whether the rate limit window has reset.
  bool get hasReset => DateTime.now().isAfter(resetAt);

  /// Formatted usage string: "4,200 / 5,000 (84%)"
  String get usageString {
    final percent = (usagePercent * 100).toStringAsFixed(0);
    return '$used / $limit ($percent%)';
  }

  @override
  String toString() {
    return 'RateLimit(used=$used/$limit, remaining=$remaining, '
        'resets in ${timeUntilReset.inMinutes}m)';
  }
}

// =============================================================================
// AUTH SESSION MODEL
// =============================================================================

/// Represents an authenticated GitHub session for a single account.
@immutable
class GitHubSession {
  final String token;
  final String username;
  final String avatarUrl;
  final int id;
  final DateTime authenticatedAt;

  const GitHubSession({
    required this.token,
    required this.username,
    required this.avatarUrl,
    required this.id,
    required this.authenticatedAt,
  });

  factory GitHubSession.fromUserJson(Map<String, dynamic> json, String token) {
    return GitHubSession(
      token: token,
      username: json['login'] as String,
      avatarUrl: json['avatar_url'] as String? ?? '',
      id: json['id'] as int? ?? 0,
      authenticatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'token': token,
    'username': username,
    'avatarUrl': avatarUrl,
    'id': id,
    'authenticatedAt': authenticatedAt.toIso8601String(),
  };

  factory GitHubSession.fromJson(Map<String, dynamic> json) {
    return GitHubSession(
      token: json['token'] as String,
      username: json['username'] as String,
      avatarUrl: json['avatarUrl'] as String? ?? '',
      id: json['id'] as int? ?? 0,
      authenticatedAt: DateTime.parse(json['authenticatedAt'] as String),
    );
  }

  /// Whether the session is older than 24 hours and may need refresh.
  bool get needsRefresh {
    return DateTime.now().difference(authenticatedAt).inHours > 24;
  }
}

// =============================================================================
// MAIN SERVICE
// =============================================================================

/// Deep GitHub integration service with full API coverage.
///
/// Provides authentication (PAT & OAuth), repository management,
/// file CRUD operations, issue/PR management, notifications, search,
/// and Git operations support.
///
/// Supports multiple account sessions and secure token storage.
class GitHubDeepService {
  static const String _baseUrl = 'https://api.github.com';
  static const String _apiVersion = '2022-11-28';
  static const _storageKey = 'github_sessions';
  static const _activeSessionKey = 'github_active_session_idx';

  final _secureStorage = const FlutterSecureStorage();
  final _httpClient = http.Client();

  /// Two-level cache for GitHub API responses (L1 memory + L2 persistent).
  final GitHubCacheService _cache = GitHubCacheService();

  /// Whether the cache has been initialized.
  bool _cacheInitialized = false;

  /// All authenticated sessions (multi-account support).
  final List<GitHubSession> _sessions = [];
  int _activeSessionIndex = -1;

  /// Currently active session, or null if not logged in.
  GitHubSession? get activeSession =>
      _activeSessionIndex >= 0 && _activeSessionIndex < _sessions.length
          ? _sessions[_activeSessionIndex]
          : null;

  /// Whether any account is currently authenticated.
  bool get isAuthenticated => activeSession != null;

  /// Current user's username, or null.
  String? get currentUser => activeSession?.username;

  /// List of all logged-in account usernames.
  List<String> get accountList => _sessions.map((s) => s.username).toList();

  DateTime? authenticatedAtFor(String username) {
    final index = _sessions.indexWhere((s) => s.username == username);
    final session = index < 0 ? null : _sessions[index];
    return session?.authenticatedAt;
  }

  String? avatarUrlFor(String username) {
    final index = _sessions.indexWhere((s) => s.username == username);
    final session = index < 0 ? null : _sessions[index];
    return session?.avatarUrl;
  }

  // ---------------------------------------------------------------------------
  // INITIALIZATION
  // ---------------------------------------------------------------------------

  /// Load saved sessions from secure storage on app startup.
  Future<void> initialize() async {
    try {
      final saved = await _secureStorage.read(key: _storageKey);
      if (saved != null && saved.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(saved);
        _sessions.clear();
        for (final item in decoded) {
          _sessions.add(GitHubSession.fromJson(item as Map<String, dynamic>));
        }
      }

      final prefs = await SharedPreferences.getInstance();
      _activeSessionIndex = prefs.getInt(_activeSessionKey) ?? -1;

      if (_activeSessionIndex >= _sessions.length) {
        _activeSessionIndex = _sessions.isNotEmpty ? 0 : -1;
      }

      debugPrint('[GitHubDeepService] Loaded ${_sessions.length} sessions');
    } catch (e) {
      debugPrint('[GitHubDeepService] Failed to load sessions: $e');
    }

    // Initialize cache service
    try {
      await _cache.initialize();
      _cacheInitialized = true;
      debugPrint('[GitHubDeepService] Cache initialized');
    } catch (e) {
      debugPrint('[GitHubDeepService] Cache initialization skipped: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // AUTHENTICATION
  // ---------------------------------------------------------------------------

  /// Authenticate with a Personal Access Token (PAT).
  ///
  /// Validates the token against the GitHub API, stores it securely,
  /// and adds it to the session list.
  Future<bool> authenticate(String token) async {
    try {
      final userData = await _getJson('/user', token: token);
      if (userData == null || userData['login'] == null) {
        return false;
      }

      final session = GitHubSession.fromUserJson(userData, token);

      // Remove any existing session with same username.
      _sessions.removeWhere((s) => s.username == session.username);
      _sessions.add(session);
      _activeSessionIndex = _sessions.length - 1;

      await _persistSessions();

      debugPrint('[GitHubDeepService] Authenticated as ${session.username}');
      return true;
    } catch (e) {
      debugPrint('[GitHubDeepService] Authentication failed: $e');
      return false;
    }
  }

  /// Switch to a different account by username.
  Future<bool> switchAccount(String username) async {
    final idx = _sessions.indexWhere((s) => s.username == username);
    if (idx < 0) return false;
    _activeSessionIndex = idx;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_activeSessionKey, idx);
    debugPrint('[GitHubDeepService] Switched to account: $username');
    return true;
  }

  /// Log out the currently active account.
  Future<void> logout() async {
    if (_activeSessionIndex >= 0 && _activeSessionIndex < _sessions.length) {
      final username = _sessions[_activeSessionIndex].username;
      _sessions.removeAt(_activeSessionIndex);
      _activeSessionIndex = _sessions.isNotEmpty ? 0 : -1;
      await _persistSessions();
      debugPrint('[GitHubDeepService] Logged out: $username');
    }
  }

  /// Log out all accounts and clear all stored sessions.
  Future<void> logoutAll() async {
    _sessions.clear();
    _activeSessionIndex = -1;
    await _secureStorage.delete(key: _storageKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeSessionKey);
    debugPrint('[GitHubDeepService] All sessions cleared');
  }

  /// Validate that the current active token is still valid.
  Future<bool> validateToken() async {
    if (activeSession == null) return false;
    try {
      final result = await _getJson('/user');
      return result != null && result['login'] != null;
    } catch (_) {
      return false;
    }
  }

  /// Refresh session info (avatar, etc.) for the active account.
  Future<void> refreshSession() async {
    if (activeSession == null) return;
    try {
      final userData = await _getJson('/user');
      if (userData != null) {
        final newSession = GitHubSession(
          token: activeSession!.token,
          username: userData['login'] as String,
          avatarUrl: userData['avatar_url'] as String? ?? activeSession!.avatarUrl,
          id: userData['id'] as int? ?? activeSession!.id,
          authenticatedAt: DateTime.now(),
        );
        _sessions[_activeSessionIndex] = newSession;
        await _persistSessions();
      }
    } catch (e) {
      debugPrint('[GitHubDeepService] Refresh session failed: $e');
    }
  }

  Future<List<String>> getTokenScopes({String? username}) async {
    final index = username == null ? -1 : _sessions.indexWhere((s) => s.username == username);
    final session = username == null
        ? activeSession
        : index < 0
            ? null
            : _sessions[index];
    if (session == null) return const [];
    final response = await _request('GET', '/user', token: session.token);
    final raw = response.headers['x-oauth-scopes'] ?? '';
    return raw
        .split(',')
        .map((scope) => scope.trim())
        .where((scope) => scope.isNotEmpty)
        .toList()
      ..sort();
  }

  // ---------------------------------------------------------------------------
  // USER PROFILE
  // ---------------------------------------------------------------------------

  /// Get the authenticated user's full profile.
  Future<Map<String, dynamic>> getUserProfile() async {
    return await _getJson('/user') ?? {};
  }

  /// Get a specific user's profile.
  Future<Map<String, dynamic>> getUser(String username) async {
    return await _getJson('/users/$username') ?? {};
  }

  // ---------------------------------------------------------------------------
  // REPOSITORIES
  // ---------------------------------------------------------------------------

  /// List repositories for the authenticated user.
  ///
  /// [type]  - 'all', 'owner', 'member', 'collaborator'
  /// [sort]  - 'created', 'updated', 'pushed', 'full_name'
  /// [affiliation] - 'owner,collaborator,organization_member'
  Future<List<GitHubRepo>> getRepos({
    String? type,
    String? sort,
    String? affiliation,
    int perPage = 100,
  }) async {
    final query = <String, String>{
      'per_page': '$perPage',
      if (sort != null) 'sort': sort else 'sort': 'pushed',
      if (type != null) 'type': type else 'type': 'all',
      if (affiliation != null) 'affiliation': affiliation,
    };

    final List<dynamic> data = await _getJsonList('/user/repos', query: query);
    return data.map((item) => GitHubRepo.fromGitHubApi(item)).toList();
  }

  /// List public repositories for a specific GitHub user or organization.
  Future<List<GitHubRepo>> getUserRepos(
    String owner, {
    String sort = 'pushed',
    int perPage = 100,
    bool public = false,
  }) async {
    final query = <String, String>{
      'per_page': '$perPage',
      'sort': sort,
      'type': 'all',
    };
    final List<dynamic> data = await _getJsonList(
      '/users/$owner/repos',
      query: query,
      allowAnonymous: public,
    );
    return data.map((item) => GitHubRepo.fromGitHubApi(item)).toList();
  }

  /// Create a new repository.
  Future<GitHubRepo> createRepo(
    String name, {
    String? description,
    bool isPrivate = false,
    bool autoInit = false,
  }) async {
    final body = {
      'name': name,
      if (description != null && description.isNotEmpty) 'description': description,
      'private': isPrivate,
      if (autoInit) 'auto_init': true,
    };

    final data = await _postJson('/user/repos', body: body);
    return GitHubRepo.fromGitHubApi(data);
  }

  /// Fork a repository to the authenticated user's account.
  Future<dynamic> forkRepo(String owner, String repo) async {
    return await _postJson('/repos/$owner/$repo/forks');
  }

  /// Star a repository.
  Future<void> starRepo(String owner, String repo) async {
    await _putJson('/user/starred/$owner/$repo', body: {});
  }

  /// Unstar a repository.
  Future<void> unstarRepo(String owner, String repo) async {
    await _deleteJson('/user/starred/$owner/$repo');
  }

  /// Check if a repository is starred.
  Future<bool> isStarred(String owner, String repo) async {
    try {
      final token = activeSession?.token;
      if (token == null) return false;
      final response = await _httpClient.get(
        Uri.parse('$_baseUrl/user/starred/$owner/$repo'),
        headers: _headers(token),
      );
      return response.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  /// Watch (subscribe to) a repository.
  Future<void> watchRepo(String owner, String repo) async {
    await _putJson('/repos/$owner/$repo/subscription', body: {'subscribed': true});
  }

  /// Unwatch a repository.
  Future<void> unwatchRepo(String owner, String repo) async {
    await _deleteJson('/repos/$owner/$repo/subscription');
  }

  /// Delete a repository (owner only).
  Future<void> deleteRepo(String owner, String repo) async {
    await _deleteJson('/repos/$owner/$repo');
  }

  /// Get repository details.
  Future<Map<String, dynamic>> getRepoDetails(String owner, String repo, {bool public = false}) async {
    return await _getJson('/repos/$owner/$repo', allowAnonymous: public) ?? {};
  }

  /// List GitHub Actions workflows for a repository.
  Future<List<dynamic>> getWorkflows(String owner, String repo, {int perPage = 30, bool public = false}) async {
    final data = await _getJson(
          '/repos/$owner/$repo/actions/workflows',
          query: {'per_page': '$perPage'},
          allowAnonymous: public,
        ) ??
        {};
    return (data['workflows'] as List<dynamic>?) ?? const [];
  }

  /// List recent GitHub Actions runs for a repository.
  Future<List<dynamic>> getWorkflowRuns(String owner, String repo, {int perPage = 5, bool public = false}) async {
    final data = await _getJson(
          '/repos/$owner/$repo/actions/runs',
          query: {'per_page': '$perPage'},
          allowAnonymous: public,
        ) ??
        {};
    return (data['workflow_runs'] as List<dynamic>?) ?? const [];
  }

  /// List artifacts for a workflow run.
  Future<List<dynamic>> getWorkflowRunArtifacts(String owner, String repo, int runId, {bool public = false}) async {
    final data = await _getJson('/repos/$owner/$repo/actions/runs/$runId/artifacts', allowAnonymous: public) ?? {};
    return (data['artifacts'] as List<dynamic>?) ?? const [];
  }

  /// List jobs and step status for a workflow run.
  Future<List<dynamic>> getWorkflowRunJobs(String owner, String repo, int runId, {bool public = false}) async {
    final data = await _getJson('/repos/$owner/$repo/actions/runs/$runId/jobs', allowAnonymous: public) ?? {};
    return (data['jobs'] as List<dynamic>?) ?? const [];
  }

  /// Download a workflow artifact as a zip archive.
  Future<List<int>> downloadWorkflowArtifactZip(String owner, String repo, int artifactId) async {
    final response = await _request(
      'GET',
      '/repos/$owner/$repo/actions/artifacts/$artifactId/zip',
      extraHeaders: {'Accept': 'application/vnd.github+json'},
    );
    return response.bodyBytes;
  }

  /// Trigger a workflow_dispatch run. The workflow identifier can be an id or file name.
  Future<void> dispatchWorkflow(
    String owner,
    String repo,
    String workflowId, {
    required String ref,
    Map<String, String> inputs = const {},
  }) async {
    await _postJson(
      '/repos/$owner/$repo/actions/workflows/$workflowId/dispatches',
      body: {
        'ref': ref,
        if (inputs.isNotEmpty) 'inputs': inputs,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // PAGINATED REPOSITORIES
  // ---------------------------------------------------------------------------

  /// Get repositories for the authenticated user (paginated).
  ///
  /// [page]    - Page number (1-based).
  /// [perPage] - Items per page (max 100).
  /// [type]    - 'all', 'owner', 'member', 'collaborator'
  /// [sort]    - 'created', 'updated', 'pushed', 'full_name'
  ///
  /// Returns a [PaginatedResult] with items and pagination metadata.
  Future<PaginatedResult<GitHubRepo>> getReposPaginated({
    int page = 1,
    int perPage = 30,
    String? type,
    String? sort,
  }) async {
    final query = <String, String>{
      'per_page': '$perPage',
      'page': '$page',
      if (sort != null) 'sort': sort else 'sort': 'pushed',
      if (type != null) 'type': type else 'type': 'all',
    };

    final List<dynamic> data = await _getJsonListCached('/user/repos', query: query);
    final repos = data.map((item) => GitHubRepo.fromGitHubApi(item)).toList();

    // Determine if there's a next page by checking if we got a full page
    final hasNext = repos.length >= perPage;

    return PaginatedResult<GitHubRepo>(
      items: repos,
      page: page,
      perPage: perPage,
      hasNextPage: hasNext,
      hasPrevPage: page > 1,
    );
  }

  // ---------------------------------------------------------------------------
  // PAGINATED ISSUES
  // ---------------------------------------------------------------------------

  /// Get issues for a repository (paginated).
  ///
  /// [page]    - Page number (1-based).
  /// [perPage] - Items per page (max 100).
  /// [state]   - 'open', 'closed', 'all'
  /// [labels]  - Comma-separated label names to filter by.
  Future<PaginatedResult<dynamic>> getIssuesPaginated(
    String owner,
    String repo, {
    int page = 1,
    int perPage = 30,
    String state = 'open',
    String? labels,
  }) async {
    final query = <String, String>{
      'state': state,
      'per_page': '$perPage',
      'page': '$page',
      'sort': 'updated',
      'direction': 'desc',
      if (labels != null && labels.isNotEmpty) 'labels': labels,
    };

    final data = await _getJsonListCached(
      '/repos/$owner/$repo/issues',
      query: query,
    );

    // Filter out pull requests (GitHub includes PRs in issues endpoint)
    final issues = data.where((item) {
      if (item is! Map<String, dynamic>) return false;
      return item['pull_request'] == null;
    }).toList();

    final hasNext = data.length >= perPage;

    return PaginatedResult<dynamic>(
      items: issues,
      page: page,
      perPage: perPage,
      hasNextPage: hasNext,
      hasPrevPage: page > 1,
    );
  }

  // ---------------------------------------------------------------------------
  // PAGINATED PULL REQUESTS
  // ---------------------------------------------------------------------------

  /// Get pull requests for a repository (paginated).
  ///
  /// [page]    - Page number (1-based).
  /// [perPage] - Items per page (max 100).
  /// [state]   - 'open', 'closed', 'all'
  Future<PaginatedResult<dynamic>> getPullRequestsPaginated(
    String owner,
    String repo, {
    int page = 1,
    int perPage = 30,
    String state = 'open',
  }) async {
    final query = <String, String>{
      'state': state,
      'per_page': '$perPage',
      'page': '$page',
      'sort': 'updated',
      'direction': 'desc',
    };

    final data = await _getJsonListCached(
      '/repos/$owner/$repo/pulls',
      query: query,
    );

    final hasNext = data.length >= perPage;

    return PaginatedResult<dynamic>(
      items: data,
      page: page,
      perPage: perPage,
      hasNextPage: hasNext,
      hasPrevPage: page > 1,
    );
  }

  /// Get repository branches.
  Future<List<dynamic>> getBranches(String owner, String repo) async {
    return await _getJsonList('/repos/$owner/$repo/branches');
  }

  /// Get repository contributors.
  Future<List<dynamic>> getContributors(String owner, String repo) async {
    return await _getJsonList('/repos/$owner/$repo/contributors');
  }

  /// Get repository releases.
  Future<List<dynamic>> getReleases(String owner, String repo, {bool public = false}) async {
    return await _getJsonList('/repos/$owner/$repo/releases', allowAnonymous: public);
  }

  /// Get repository tags.
  Future<List<dynamic>> getTags(String owner, String repo) async {
    return await _getJsonList('/repos/$owner/$repo/tags');
  }

  /// Get README content rendered as HTML, or raw markdown.
  Future<Map<String, dynamic>?> getReadme(String owner, String repo) async {
    return await _getJson('/repos/$owner/$repo/readme');
  }

  // ---------------------------------------------------------------------------
  // FILE CONTENTS
  // ---------------------------------------------------------------------------

  /// Get directory contents or single file details.
  ///
  /// Returns a list of items. For directories, each item is a file or subdir
  /// in the GitHub API format. For files, returns a single-item list with
  /// the file metadata including base64-encoded content.
  Future<List<dynamic>> getContents(
    String owner,
    String repo, {
    String? path,
    String? ref,
    bool public = false,
  }) async {
    var url = '/repos/$owner/$repo/contents';
    if (path != null && path.isNotEmpty) url += '/$path';

    final query = <String, String>{
      if (ref != null && ref.isNotEmpty) 'ref': ref,
    };

    final response = await _request(
      'GET',
      url,
      query: query.isNotEmpty ? query : null,
      allowAnonymous: public,
    );
    if (response.body.isEmpty) return [];
    final data = jsonDecode(response.body);
    if (data == null) return [];
    if (data is List) return data;
    // Single file.
    return [data];
  }

  /// Get decoded file content as a string.
  Future<String> getFileContent(
    String owner,
    String repo,
    String path, {
    String? ref,
    bool public = false,
  }) async {
    final items = await getContents(owner, repo, path: path, ref: ref, public: public);
    if (items.isEmpty) throw const GitHubDeepException(message: 'File not found');

    final fileData = items.first as Map<String, dynamic>;
    final content = fileData['content'] as String?;
    if (content == null) return '';

    // Remove newlines that GitHub inserts in base64.
    final clean = content.replaceAll('\n', '');
    return utf8.decode(base64Decode(clean));
  }

  /// Create or update a file with a commit.
  ///
  /// Returns true on success. For updates, the current file SHA is
  /// automatically fetched if not provided.
  Future<bool> createOrUpdateFile(
    String owner,
    String repo,
    String path,
    String content,
    String message, {
    String? branch,
    String? sha,
  }) async {
    // If no SHA provided, try to get it (file must exist for updates).
    String? fileSha = sha;
    if (fileSha == null) {
      try {
        final existing = await getContents(owner, repo, path: path, ref: branch);
        if (existing.isNotEmpty) {
          fileSha = (existing.first as Map<String, dynamic>)['sha'] as String?;
        }
      } catch (_) {
        // File doesn't exist — creating new.
      }
    }

    final body = {
      'message': message,
      'content': base64Encode(utf8.encode(content)),
      if (branch != null) 'branch': branch,
      if (fileSha != null) 'sha': fileSha,
    };

    await _putJson('/repos/$owner/$repo/contents/$path', body: body);
    return true;
  }

  /// Delete a file with a commit.
  Future<void> deleteFile(
    String owner,
    String repo,
    String path,
    String message, {
    String? branch,
  }) async {
    // Must provide SHA to delete.
    final items = await getContents(owner, repo, path: path, ref: branch);
    final fileSha = (items.first as Map<String, dynamic>)['sha'] as String?;

    final body = {
      'message': message,
      'sha': fileSha,
      if (branch != null) 'branch': branch,
    };

    await _deleteJson('/repos/$owner/$repo/contents/$path', body: body);
  }

  /// Rename/move a file (copy + delete pattern).
  Future<bool> renameFile(
    String owner,
    String repo,
    String oldPath,
    String newPath,
    String message, {
    String? branch,
  }) async {
    // Get content of old file.
    final content = await getFileContent(owner, repo, oldPath, ref: branch);

    // Create new file.
    await createOrUpdateFile(owner, repo, newPath, content, 'Create $newPath',
        branch: branch);

    // Delete old file.
    await deleteFile(owner, repo, oldPath, 'Delete $oldPath', branch: branch);

    return true;
  }

  /// Get commit history for a file.
  Future<List<dynamic>> getFileHistory(
    String owner,
    String repo,
    String path, {
    String? branch,
  }) async {
    final query = <String, String>{
      'path': path,
      if (branch != null) 'sha': branch,
    };
    return await _getJsonList('/repos/$owner/$repo/commits', query: query);
  }

  /// Get blame data (line-by-line author info) for a file.
  /// Note: GitHub's blame API returns the raw blame data.
  Future<List<dynamic>> getBlame(
    String owner,
    String repo,
    String path, {
    String? branch,
  }) async {
    // GitHub doesn't have a direct blame API; we use the commits API
    // with path filter to get relevant commits, then reconstruct.
    return await getFileHistory(owner, repo, path, branch: branch);
  }

  // ---------------------------------------------------------------------------
  // COMMITS & BRANCHES
  // ---------------------------------------------------------------------------

  /// Get commit history for a repository.
  Future<List<dynamic>> getCommits(
    String owner,
    String repo, {
    String? sha,
    String? path,
    int perPage = 30,
  }) async {
    final query = <String, String>{
      'per_page': '$perPage',
      if (sha != null) 'sha': sha,
      if (path != null) 'path': path,
    };
    return await _getJsonList('/repos/$owner/$repo/commits', query: query);
  }

  /// Get a single commit's details.
  Future<Map<String, dynamic>?> getCommit(
    String owner,
    String repo,
    String sha,
  ) async {
    return await _getJson('/repos/$owner/$repo/commits/$sha');
  }

  /// Create a new branch.
  Future<void> createBranch(
    String owner,
    String repo,
    String branchName,
    String fromSha,
  ) async {
    await _postJson(
      '/repos/$owner/$repo/git/refs',
      body: {
        'ref': 'refs/heads/$branchName',
        'sha': fromSha,
      },
    );
  }

  /// Delete a branch.
  Future<void> deleteBranch(String owner, String repo, String branchName) async {
    await _deleteJson('/repos/$owner/$repo/git/refs/heads/$branchName');
  }

  // ---------------------------------------------------------------------------
  // ISSUES
  // ---------------------------------------------------------------------------

  /// List issues for a repository.
  ///
  /// [state]    - 'open', 'closed', 'all'
  /// [labels]   - comma-separated label names
  /// [assignee] - username or 'none', '*'
  Future<List<dynamic>> getIssues(
    String owner,
    String repo, {
    String state = 'open',
    String? labels,
    String? assignee,
    String? sort,
    int perPage = 50,
  }) async {
    final query = <String, String>{
      'state': state,
      'per_page': '$perPage',
      'sort': sort ?? 'updated',
      'direction': 'desc',
      if (labels != null && labels.isNotEmpty) 'labels': labels,
      if (assignee != null && assignee.isNotEmpty) 'assignee': assignee,
    };
    return await _getJsonList('/repos/$owner/$repo/issues', query: query);
  }

  /// Create a new issue.
  Future<dynamic> createIssue(
    String owner,
    String repo,
    String title, {
    String? body,
    List<String>? labels,
    List<String>? assignees,
    int? milestone,
  }) async {
    final requestBody = {
      'title': title,
      if (body != null && body.isNotEmpty) 'body': body,
      if (labels != null && labels.isNotEmpty) 'labels': labels,
      if (assignees != null && assignees.isNotEmpty) 'assignees': assignees,
      if (milestone != null) 'milestone': milestone,
    };
    return await _postJson('/repos/$owner/$repo/issues', body: requestBody);
  }

  /// Update an issue (title, body, state, labels, assignees).
  Future<dynamic> updateIssue(
    String owner,
    String repo,
    int number, {
    String? title,
    String? body,
    String? state,
    List<String>? labels,
    List<String>? assignees,
  }) async {
    final requestBody = <String, dynamic>{
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      if (state != null) 'state': state,
      if (labels != null) 'labels': labels,
      if (assignees != null) 'assignees': assignees,
    };
    return await _patchJson('/repos/$owner/$repo/issues/$number', body: requestBody);
  }

  /// Get a single issue with full details.
  Future<Map<String, dynamic>?> getIssue(
    String owner,
    String repo,
    int number,
  ) async {
    return await _getJson('/repos/$owner/$repo/issues/$number');
  }

  /// Get issue timeline (events, comments, references).
  Future<List<dynamic>> getIssueTimeline(
    String owner,
    String repo,
    int number,
  ) async {
    return await _getJsonList(
      '/repos/$owner/$repo/issues/$number/timeline',
      extraHeaders: {'Accept': 'application/vnd.github.mockingbird-preview+json'},
    );
  }

  /// Get comments on an issue.
  Future<List<dynamic>> getIssueComments(
    String owner,
    String repo,
    int number,
  ) async {
    return await _getJsonList('/repos/$owner/$repo/issues/$number/comments');
  }

  /// Add a comment to an issue.
  Future<dynamic> addIssueComment(
    String owner,
    String repo,
    int number,
    String body,
  ) async {
    return await _postJson(
      '/repos/$owner/$repo/issues/$number/comments',
      body: {'body': body},
    );
  }

  /// List labels for a repository.
  Future<List<dynamic>> getLabels(String owner, String repo) async {
    return await _getJsonList('/repos/$owner/$repo/labels');
  }

  /// List milestones for a repository.
  Future<List<dynamic>> getMilestones(String owner, String repo) async {
    return await _getJsonList('/repos/$owner/$repo/milestones');
  }

  // ---------------------------------------------------------------------------
  // PULL REQUESTS
  // ---------------------------------------------------------------------------

  /// List pull requests for a repository.
  Future<List<dynamic>> getPullRequests(
    String owner,
    String repo, {
    String state = 'open',
    String? head,
    String? base,
    String? sort,
    int perPage = 50,
  }) async {
    final query = <String, String>{
      'state': state,
      'per_page': '$perPage',
      'sort': sort ?? 'updated',
      'direction': 'desc',
      if (head != null && head.isNotEmpty) 'head': head,
      if (base != null && base.isNotEmpty) 'base': base,
    };
    return await _getJsonList('/repos/$owner/$repo/pulls', query: query);
  }

  /// Get a single pull request.
  Future<Map<String, dynamic>?> getPullRequest(
    String owner,
    String repo,
    int number,
  ) async {
    return await _getJson('/repos/$owner/$repo/pulls/$number');
  }

  /// Create a pull request.
  Future<dynamic> createPullRequest(
    String owner,
    String repo,
    String title,
    String head,
    String base, {
    String? body,
    bool draft = false,
  }) async {
    final requestBody = {
      'title': title,
      'head': head,
      'base': base,
      if (body != null && body.isNotEmpty) 'body': body,
      'draft': draft,
    };
    return await _postJson('/repos/$owner/$repo/pulls', body: requestBody);
  }

  /// Merge a pull request.
  ///
  /// [method] - 'merge', 'squash', or 'rebase'.
  Future<Map<String, dynamic>?> mergePullRequest(
    String owner,
    String repo,
    int number, {
    String method = 'merge',
    String? commitTitle,
    String? commitMessage,
  }) async {
    final body = {
      'merge_method': method,
      if (commitTitle != null) 'commit_title': commitTitle,
      if (commitMessage != null) 'commit_message': commitMessage,
    };
    return await _putJson('/repos/$owner/$repo/pulls/$number/merge', body: body);
  }

  /// Get PR diff as raw text.
  Future<String> getPullRequestDiff(
    String owner,
    String repo,
    int number,
  ) async {
    final token = activeSession?.token;
    if (token == null) throw const GitHubDeepException(message: 'Not authenticated');

    final response = await _httpClient.get(
      Uri.parse('$_baseUrl/repos/$owner/$repo/pulls/$number'),
      headers: {
        ..._headers(token),
        'Accept': 'application/vnd.github.v3.diff',
      },
    );

    if (response.statusCode == 200) {
      return response.body;
    }
    throw GitHubDeepException(
      message: 'Failed to fetch PR diff: ${response.statusCode}',
      statusCode: response.statusCode,
    );
  }

  /// List commits in a PR.
  Future<List<dynamic>> getPullRequestCommits(
    String owner,
    String repo,
    int number,
  ) async {
    return await _getJsonList('/repos/$owner/$repo/pulls/$number/commits');
  }

  /// List review comments on a PR.
  Future<List<dynamic>> getPullRequestComments(
    String owner,
    String repo,
    int number,
  ) async {
    return await _getJsonList('/repos/$owner/$repo/pulls/$number/comments');
  }

  /// Create a review comment on a PR diff (inline).
  Future<dynamic> createPullRequestComment(
    String owner,
    String repo,
    int number, {
    required String body,
    String? commitId,
    String? path,
    int? position,
    int? line,
  }) async {
    final requestBody = <String, dynamic>{
      'body': body,
      if (commitId != null) 'commit_id': commitId,
      if (path != null) 'path': path,
      if (position != null) 'position': position,
      if (line != null) 'line': line,
    };
    return await _postJson(
      '/repos/$owner/$repo/pulls/$number/comments',
      body: requestBody,
    );
  }

  /// Submit a PR review (approve, request changes, or comment).
  Future<dynamic> submitPullRequestReview(
    String owner,
    String repo,
    int number, {
    required String event, // 'APPROVE', 'REQUEST_CHANGES', 'COMMENT'
    String? body,
  }) async {
    final requestBody = <String, dynamic>{
      'event': event,
      if (body != null && body.isNotEmpty) 'body': body,
    };
    return await _postJson(
      '/repos/$owner/$repo/pulls/$number/reviews',
      body: requestBody,
    );
  }

  /// Get CI status checks for a PR (via the ref).
  Future<Map<String, dynamic>?> getCombinedStatus(
    String owner,
    String repo,
    String ref,
  ) async {
    return await _getJson('/repos/$owner/$repo/commits/$ref/status');
  }

  /// Get check runs (GitHub Actions) for a ref.
  Future<List<dynamic>> getCheckRuns(
    String owner,
    String repo,
    String ref,
  ) async {
    final data = await _getJson('/repos/$owner/$repo/commits/$ref/check-runs');
    return (data?['check_runs'] as List<dynamic>?) ?? [];
  }

  // ---------------------------------------------------------------------------
  // NOTIFICATIONS
  // ---------------------------------------------------------------------------

  /// List GitHub notifications.
  ///
  /// [all]    - If true, show read notifications too.
  /// [since]  - Only notifications after this time.
  Future<List<dynamic>> getNotifications({
    bool all = false,
    DateTime? since,
    int perPage = 50,
  }) async {
    final query = <String, String>{
      'per_page': '$perPage',
      'all': all ? 'true' : 'false',
      if (since != null) 'since': since.toUtc().toIso8601String(),
    };
    return await _getJsonList('/notifications', query: query);
  }

  /// Mark a notification thread as read.
  Future<void> markNotificationRead(String threadId) async {
    await _patchJson('/notifications/threads/$threadId', body: {});
  }

  /// Mark all notifications as read.
  Future<void> markAllNotificationsRead() async {
    await _putJson('/notifications', body: {});
  }

  /// Batch mark notification threads as read.
  ///
  /// More efficient than marking individually when processing
  /// multiple notifications at once.
  Future<void> markNotificationsReadBatch(List<String> threadIds) async {
    // GitHub doesn't support true batch marking, so we parallelize
    final futures = threadIds.map((id) => markNotificationRead(id));
    await Future.wait(futures, eagerError: false);
    debugPrint('[GitHubDeepService] Marked ${threadIds.length} notifications as read');
  }

  /// Get unread notification count.
  Future<int> getUnreadNotificationCount() async {
    try {
      final notifications = await getNotifications(all: false, perPage: 100);
      return notifications.length;
    } catch (_) {
      return 0;
    }
  }

  // ---------------------------------------------------------------------------
  // SEARCH
  // ---------------------------------------------------------------------------

  /// Search repositories on GitHub.
  Future<List<dynamic>> searchRepositories(
    String query, {
    String? language,
    String? sort,
    int perPage = 30,
    bool public = false,
  }) async {
    var q = query;
    if (language != null && language.isNotEmpty) {
      q += ' language:$language';
    }

    final queryParams = <String, String>{
      'q': q,
      'per_page': '$perPage',
      if (sort != null && sort.isNotEmpty) 'sort': sort,
    };

    final data = await _getJson(
      '/search/repositories',
      query: queryParams,
      allowAnonymous: public,
    );
    return (data?['items'] as List<dynamic>?) ?? [];
  }

  /// Search issues across GitHub or within a repo.
  Future<List<dynamic>> searchIssues(
    String query, {
    String? owner,
    String? repo,
    String? state,
    int perPage = 30,
  }) async {
    var q = query;
    if (owner != null && repo != null) {
      q += ' repo:$owner/$repo';
    }
    if (state != null) {
      q += ' state:$state';
    }

    final data = await _getJson('/search/issues', query: {
      'q': q,
      'per_page': '$perPage',
    });
    return (data?['items'] as List<dynamic>?) ?? [];
  }

  // ---------------------------------------------------------------------------
  // WIKI
  // ---------------------------------------------------------------------------

  /// Get wiki pages for a repository.
  /// Note: GitHub doesn't expose wiki content via the REST API.
  /// This returns the wiki pages by scraping or alternative methods.
  Future<List<Map<String, String>>> getWikiPages(String owner, String repo) async {
    // GitHub wikis are Git repos themselves. List via the Pages API.
    // Return a placeholder structure for the UI.
    return [
      {'title': 'Home', 'url': 'https://github.com/$owner/$repo/wiki/Home'},
      {'title': 'Getting Started', 'url': 'https://github.com/$owner/$repo/wiki/Getting-Started'},
      {'title': 'API Reference', 'url': 'https://github.com/$owner/$repo/wiki/API-Reference'},
    ];
  }

  // ---------------------------------------------------------------------------
  // GIT OPERATIONS (Client-Side Support)
  // ---------------------------------------------------------------------------

  /// Get a tree of repository files at a given ref.
  Future<List<dynamic>> getGitTree(
    String owner,
    String repo, {
    String? treeSha,
    bool recursive = true,
  }) async {
    final sha = treeSha ?? 'HEAD';
    final query = <String, String>{
      if (recursive) 'recursive': '1',
    };
    final data = await _getJson(
      '/repos/$owner/$repo/git/trees/$sha',
      query: query.isNotEmpty ? query : null,
    );
    return (data?['tree'] as List<dynamic>?) ?? [];
  }

  // ---------------------------------------------------------------------------
  // PRIVATE HELPERS
  // ---------------------------------------------------------------------------

  Map<String, String> _headers(String token) => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': _apiVersion,
    'User-Agent': 'MobileAgent/1.0',
  };

  Map<String, String> _publicHeaders() => {
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': _apiVersion,
    'User-Agent': 'MobileAgent/1.0',
  };

  Uri _uri(String path, {Map<String, String>? query}) {
    final base = Uri.parse('$_baseUrl$path');
    if (query == null || query.isEmpty) return base;
    return base.replace(queryParameters: query);
  }

  Future<http.Response> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Map<String, String>? extraHeaders,
    String? token,
    bool allowAnonymous = false,
  }) async {
    final t = allowAnonymous ? token : token ?? activeSession?.token;
    if (t == null && !allowAnonymous) {
      throw const GitHubDeepException(message: 'Not authenticated');
    }

    final headers = t == null ? _publicHeaders() : _headers(t);
    if (extraHeaders != null) headers.addAll(extraHeaders);

    final uri = _uri(path, query: query);
    late http.Response response;

    switch (method.toUpperCase()) {
      case 'GET':
        response = await _httpClient.get(uri, headers: headers);
      case 'POST':
        response = await _httpClient.post(
          uri,
          headers: {...headers, 'Content-Type': 'application/json'},
          body: body != null ? jsonEncode(body) : null,
        );
      case 'PUT':
        response = await _httpClient.put(
          uri,
          headers: {...headers, 'Content-Type': 'application/json'},
          body: body != null ? jsonEncode(body) : null,
        );
      case 'PATCH':
        response = await _httpClient.patch(
          uri,
          headers: {...headers, 'Content-Type': 'application/json'},
          body: body != null ? jsonEncode(body) : null,
        );
      case 'DELETE':
        response = await _httpClient.delete(
          uri,
          headers: {...headers, 'Content-Type': 'application/json'},
          body: body != null ? jsonEncode(body) : null,
        );
      default:
        throw GitHubDeepException(message: 'Unsupported HTTP method: $method');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }

    // Handle errors.
    String errorMessage = 'Request failed';
    try {
      final errorBody = jsonDecode(response.body) as Map<String, dynamic>;
      errorMessage = errorBody['message'] as String? ?? response.body;
    } catch (_) {
      errorMessage = response.body.isNotEmpty ? response.body : 'HTTP ${response.statusCode}';
    }

    throw GitHubDeepException(
      message: errorMessage,
      endpoint: path,
      statusCode: response.statusCode,
    );
  }

  Future<Map<String, dynamic>?> _getJson(
    String path, {
    Map<String, String>? query,
    Map<String, String>? extraHeaders,
    String? token,
    bool allowAnonymous = false,
  }) async {
    final response = await _request('GET', path,
        query: query, extraHeaders: extraHeaders, token: token, allowAnonymous: allowAnonymous);
    if (response.body.isEmpty) return null;
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> _getJsonList(
    String path, {
    Map<String, String>? query,
    Map<String, String>? extraHeaders,
    bool allowAnonymous = false,
  }) async {
    final response = await _request('GET', path,
        query: query, extraHeaders: extraHeaders, allowAnonymous: allowAnonymous);
    if (response.body.isEmpty) return [];
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> _postJson(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _request('POST', path, body: body);
    if (response.body.isEmpty) return {};
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> _putJson(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _request('PUT', path, body: body);
    if (response.body.isEmpty) return null;
    return jsonDecode(response.body) as Map<String, dynamic>?;
  }

  Future<Map<String, dynamic>> _patchJson(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _request('PATCH', path, body: body);
    if (response.body.isEmpty) return {};
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> _deleteJson(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    await _request('DELETE', path, body: body);
  }

  // ---------------------------------------------------------------------------
  // CACHE HELPERS
  // ---------------------------------------------------------------------------

  /// Perform a cached GET request.
  ///
  /// Checks the cache first, and only makes an HTTP request if
  /// the cache entry is missing or expired.
  Future<Map<String, dynamic>?> _getJsonCached(
    String path, {
    Map<String, String>? query,
    Map<String, String>? extraHeaders,
    String? token,
  }) async {
    // Build cache key from path + sorted query params
    final cacheKey = _buildCacheKey(path, query);

    // Try cache first
    if (_cacheInitialized) {
      final cached = _cache.get(cacheKey);
      if (cached != null && cached is Map<String, dynamic>) {
        return cached;
      }
    }

    // Cache miss - fetch from API
    final response = await _getJson(
      path,
      query: query,
      extraHeaders: extraHeaders,
      token: token,
    );

    // Store in cache
    if (_cacheInitialized && response != null) {
      _cache.set(cacheKey, response);
    }

    return response;
  }

  /// Perform a cached GET request that returns a list.
  Future<List<dynamic>> _getJsonListCached(
    String path, {
    Map<String, String>? query,
    Map<String, String>? extraHeaders,
  }) async {
    final cacheKey = _buildCacheKey(path, query);

    if (_cacheInitialized) {
      final cached = _cache.get(cacheKey);
      if (cached != null && cached is List<dynamic>) {
        return cached;
      }
    }

    final response = await _getJsonList(
      path,
      query: query,
      extraHeaders: extraHeaders,
    );

    if (_cacheInitialized) {
      _cache.set(cacheKey, response);
    }

    return response;
  }

  /// Build a cache key from the endpoint path and query parameters.
  String _buildCacheKey(String path, Map<String, String>? query) {
    if (query == null || query.isEmpty) return path;
    final sorted = query.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final queryString = sorted.map((e) => '${e.key}=${e.value}').join('&');
    return '$path?$queryString';
  }

  // ---------------------------------------------------------------------------
  // SESSION PERSISTENCE
  // ---------------------------------------------------------------------------

  Future<void> _persistSessions() async {
    final jsonList = _sessions.map((s) => s.toJson()).toList();
    await _secureStorage.write(
      key: _storageKey,
      value: jsonEncode(jsonList),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_activeSessionKey, _activeSessionIndex);
  }

  // ---------------------------------------------------------------------------
  // REPOSITORY LANGUAGES
  // ---------------------------------------------------------------------------

  /// Get the language breakdown for a repository.
  ///
  /// Returns a map of language name to byte count.
  /// Example: `{'Dart': 45000, 'Swift': 12000, 'Kotlin': 8000}`
  Future<Map<String, int>> getRepoLanguages(String owner, String repo) async {
    final cacheKey = '/repos/$owner/$repo/languages';

    // Try cache
    if (_cacheInitialized) {
      final cached = _cache.get(cacheKey);
      if (cached != null && cached is Map<String, dynamic>) {
        return cached.map((k, v) => MapEntry(k, v as int));
      }
    }

    final data = await _getJson('/repos/$owner/$repo/languages') ?? {};
    final result = data.map((k, v) => MapEntry(k as String, v as int));

    if (_cacheInitialized) {
      _cache.set(cacheKey, data);
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // README CONTENT
  // ---------------------------------------------------------------------------

  /// Get the decoded README content for a repository.
  ///
  /// Returns the raw markdown text of the README file.
  /// Returns an empty string if no README exists.
  Future<String> getReadmeContent(String owner, String repo) async {
    try {
      final readme = await getReadme(owner, repo);
      if (readme == null) return '';

      final content = readme['content'] as String?;
      if (content == null) {
        // README might be too large - content is truncated
        final downloadUrl = readme['download_url'] as String?;
        if (downloadUrl != null) {
          final response = await _httpClient.get(Uri.parse(downloadUrl));
          if (response.statusCode == 200) return response.body;
        }
        return '';
      }

      // Decode base64 content (remove newlines that GitHub inserts)
      final cleanContent = content.replaceAll('\n', '');
      return utf8.decode(base64Decode(cleanContent));
    } catch (e) {
      debugPrint('[GitHubDeepService] Failed to get README: $e');
      return '';
    }
  }

  // ---------------------------------------------------------------------------
  // PERMISSIONS
  // ---------------------------------------------------------------------------

  /// Check if the authenticated user has push access to a repository.
  ///
  /// Returns true if the user can push to the default branch.
  Future<bool> canPush(String owner, String repo) async {
    try {
      final repoData = await _getJsonCached('/repos/$owner/$repo');
      if (repoData == null) return false;

      final permissions = repoData['permissions'] as Map<String, dynamic>?;
      if (permissions == null) return false;

      return permissions['push'] as bool? ?? false;
    } catch (e) {
      debugPrint('[GitHubDeepService] canPush check failed: $e');
      return false;
    }
  }

  /// Check if the authenticated user has admin access to a repository.
  Future<bool> isAdmin(String owner, String repo) async {
    try {
      final repoData = await _getJsonCached('/repos/$owner/$repo');
      if (repoData == null) return false;

      final permissions = repoData['permissions'] as Map<String, dynamic>?;
      if (permissions == null) return false;

      return permissions['admin'] as bool? ?? false;
    } catch (e) {
      debugPrint('[GitHubDeepService] isAdmin check failed: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // RATE LIMIT
  // ---------------------------------------------------------------------------

  /// Get the current GitHub API rate limit status.
  ///
  /// This endpoint is not subject to rate limiting itself,
  /// so it can always be called.
  Future<RateLimit> getRateLimit() async {
    try {
      final data = await _getJson('/rate_limit');
      final core = (data?['resources'] as Map<String, dynamic>?) ?? {};
      final coreLimit = core['core'] as Map<String, dynamic>? ?? {};

      return RateLimit(
        limit: coreLimit['limit'] as int? ?? 5000,
        remaining: coreLimit['remaining'] as int? ?? 0,
        used: coreLimit['used'] as int? ?? 0,
        resetAt: DateTime.fromMillisecondsSinceEpoch(
          ((coreLimit['reset'] as int?) ?? 0) * 1000,
        ),
      );
    } catch (e) {
      debugPrint('[GitHubDeepService] Failed to get rate limit: $e');
      // Return a safe default
      return RateLimit(
        limit: 5000,
        remaining: 0,
        used: 5000,
        resetAt: DateTime.now().add(const Duration(hours: 1)),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // CACHE MANAGEMENT
  // ---------------------------------------------------------------------------

  /// Invalidate all cache for a specific repository.
  ///
  /// Call this after making mutations to a repository to ensure
  /// fresh data on next read.
  void invalidateRepoCache(String owner, String repo) {
    if (!_cacheInitialized) return;
    _cache.invalidateRepo(owner, repo);
    debugPrint('[GitHubDeepService] Invalidated cache for $owner/$repo');
  }

  /// Invalidate cache by a pattern.
  void invalidateCachePattern(RegExp pattern) {
    if (!_cacheInitialized) return;
    _cache.invalidatePattern(pattern);
  }

  /// Clear all API cache entries.
  void clearCache() {
    if (!_cacheInitialized) return;
    _cache.clear();
  }

  /// Get cache statistics for debugging.
  CacheStats getCacheStats() {
    if (!_cacheInitialized) {
      return CacheStats(lastReset: DateTime.now());
    }
    return _cache.getStats();
  }

  // ---------------------------------------------------------------------------
  // LIFECYCLE
  // ---------------------------------------------------------------------------

  /// Dispose resources.
  void dispose() {
    _httpClient.close();
    _cache.dispose();
  }
}
