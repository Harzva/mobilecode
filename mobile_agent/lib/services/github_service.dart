// lib/services/github_service.dart

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/file_item.dart';
import '../models/github_repo.dart';
import 'api_service.dart';

/// Exception specific to GitHub API failures.
class GitHubException implements Exception {
  final String message;
  final String? endpoint;
  final int? statusCode;
  final dynamic originalError;

  const GitHubException({
    required this.message,
    this.endpoint,
    this.statusCode,
    this.originalError,
  });

  @override
  String toString() => 'GitHubException [$endpoint ${statusCode ?? ''}]: $message';
}

/// Service for interacting with the GitHub API.
///
/// Provides authentication, repository browsing, file operations,
/// issue management, and more. Uses a personal access token (PAT)
/// for authentication.
///
/// All endpoints use the GitHub REST API v3.
/// Rate limits apply: 5,000 requests/hour for authenticated users.
///
/// ```dart
/// final gh = GitHubService(api);
/// await gh.authenticate('ghp_xxxxxxxx');
/// final repos = await gh.getRepositories();
/// ```
class GitHubService {
  static const String _baseUrl = 'https://api.github.com';
  static const String _apiVersion = '2022-11-28';

  final ApiService _api;

  /// Current authentication token (PAT).
  String? _token;

  /// Whether the service is currently authenticated.
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;

  /// The authenticated user's login (set after successful auth).
  String? _currentUser;
  String? get currentUser => _currentUser;

  /// Create a [GitHubService] backed by an [ApiService] HTTP client.
  GitHubService(this._api);

  // ─── Authentication ────────────────────────────────────────────────

  /// Authenticate with a GitHub personal access token.
  ///
  /// Validates the token by fetching the current user's profile.
  /// Returns true if authentication succeeds.
  ///
  /// [token] A GitHub personal access token (classic) with appropriate scopes:
  ///         - repo: full repo access
  ///         - read:user: read user profile
  ///         - read:org: read organization data
  Future<bool> authenticate(String token) async {
    _api.init();
    _api.setBaseUrl(_baseUrl);
    _api.setAuthHeader(token);
    _api.setHeader('X-GitHub-Api-Version', _apiVersion);
    _api.setHeader('Accept', 'application/vnd.github+json');

    try {
      final response = await _api.get('/user');
      final data = response.data as Map<String, dynamic>;
      _token = token;
      _currentUser = data['login'] as String?;
      debugPrint('[GitHubService] Authenticated as $_currentUser');
      return true;
    } on Exception catch (e) {
      _token = null;
      _currentUser = null;
      debugPrint('[GitHubService] Authentication failed: $e');
      return false;
    }
  }

  /// Clear authentication state.
  void logout() {
    _token = null;
    _currentUser = null;
    _api.clearAuthHeader();
    debugPrint('[GitHubService] Logged out');
  }

  // ─── Repositories ──────────────────────────────────────────────────

  /// Get repositories for the authenticated user.
  ///
  /// Fetches all accessible repos (owned, collaborator, org member)
  /// sorted by most recently pushed. Results are paginated.
  ///
  /// Returns a list of [GitHubRepo] objects.
  Future<List<GitHubRepo>> getRepositories({int perPage = 100}) async {
    _ensureAuthenticated();

    try {
      final repos = <GitHubRepo>[];
      int page = 1;

      while (true) {
        final response = await _api.get(
          '/user/repos',
          query: {
            'sort': 'pushed',
            'direction': 'desc',
            'per_page': perPage,
            'page': page,
          },
        );

        final data = response.data as List<dynamic>;
        if (data.isEmpty) break;

        for (final item in data) {
          if (item is Map<String, dynamic>) {
            repos.add(GitHubRepo.fromJson(item));
          }
        }

        if (data.length < perPage) break;
        page++;

        // Safety limit: max 10 pages (1000 repos).
        if (page > 10) break;
      }

      debugPrint('[GitHubService] Fetched ${repos.length} repositories');
      return repos;
    } on Exception catch (e) {
      throw _mapError(e, '/user/repos');
    }
  }

  /// Get a specific repository's details.
  Future<GitHubRepo> getRepository(String owner, String repo) async {
    _ensureAuthenticated();

    try {
      final response = await _api.get('/repos/$owner/$repo');
      return GitHubRepo.fromJson(response.data as Map<String, dynamic>);
    } on Exception catch (e) {
      throw _mapError(e, '/repos/$owner/$repo');
    }
  }

  // ─── Repository Contents ───────────────────────────────────────────

  /// Get contents of a repository directory.
  ///
  /// [owner] Repository owner (user or org).
  /// [repo]  Repository name.
  /// [path]  Directory path within the repo (empty string for root).
  ///
  /// Returns a list of [FileItem]s representing files and subdirectories.
  Future<List<FileItem>> getRepoContents(
    String owner,
    String repo, [
    String path = '',
  ]) async {
    _ensureAuthenticated();

    try {
      final response = await _api.get(
        '/repos/$owner/$repo/contents/$path',
      );

      final data = response.data;
      if (data is! List) {
        // Single file response.
        final fileData = data as Map<String, dynamic>;
        return [
          FileItem.file(
            name: fileData['name'] as String,
            path: fileData['path'] as String,
            content: fileData['content'] != null
                ? utf8.decode(base64Decode(fileData['content'] as String))
                : null,
            size: fileData['size'] as int?,
          ),
        ];
      }

      final items = <FileItem>[];
      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;

        final type = item['type'] as String;
        final name = item['name'] as String;
        final itemPath = item['path'] as String;

        if (type == 'dir') {
          items.add(FileItem.directory(
            name: name,
            path: itemPath,
            parentPath: path,
          ));
        } else if (type == 'file') {
          items.add(FileItem.file(
            name: name,
            path: itemPath,
            size: item['size'] as int?,
            modifiedAt: item['git_url'] as String?,
          ));
        }
      }

      // Sort: directories first, then files alphabetically.
      items.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      return items;
    } on Exception catch (e) {
      throw _mapError(e, '/repos/$owner/$repo/contents/$path');
    }
  }

  /// Get the content of a specific file.
  ///
  /// Automatically decodes base64 content from the GitHub API.
  Future<String> getFileContent(
    String owner,
    String repo,
    String path,
  ) async {
    _ensureAuthenticated();

    try {
      final response = await _api.get(
        '/repos/$owner/$repo/contents/$path',
      );

      final data = response.data as Map<String, dynamic>;
      final content = data['content'] as String?;
      final sha = data['sha'] as String?;

      if (content == null) {
        throw const GitHubException(message: 'File content is empty');
      }

      // GitHub returns base64 with newlines; remove them before decoding.
      final cleanContent = content.replaceAll('\n', '');
      final decoded = utf8.decode(base64Decode(cleanContent));

      debugPrint('[GitHubService] Fetched file: $path (${decoded.length} chars)');
      return decoded;
    } on FormatException catch (e) {
      throw GitHubException(
        message: 'Failed to decode file content: $e',
        endpoint: '/repos/$owner/$repo/contents/$path',
      );
    } on Exception catch (e) {
      throw _mapError(e, '/repos/$owner/$repo/contents/$path');
    }
  }

  /// Create or update a file in a repository.
  ///
  /// [owner]   Repository owner.
  /// [repo]    Repository name.
  /// [path]    File path within the repo.
  /// [content] The new file content (plain text, will be base64 encoded).
  /// [message] The commit message.
  ///
  /// Returns true if the operation succeeds.
  Future<bool> updateFile(
    String owner,
    String repo,
    String path,
    String content,
    String message,
  ) async {
    _ensureAuthenticated();

    try {
      // First, get the current file's SHA (needed for updates).
      String? currentSha;
      try {
        final existing = await _api.get('/repos/$owner/$repo/contents/$path');
        currentSha = (existing.data as Map<String, dynamic>)['sha'] as String?;
      } on Exception {
        // File doesn't exist — we'll create it.
        debugPrint('[GitHubService] File does not exist, creating new file');
      }

      final body = {
        'message': message,
        'content': base64Encode(utf8.encode(content)),
        if (currentSha != null) 'sha': currentSha,
      };

      await _api.put('/repos/$owner/$repo/contents/$path', data: body);

      debugPrint('[GitHubService] Updated file: $path');
      return true;
    } on Exception catch (e) {
      throw _mapError(e, '/repos/$owner/$repo/contents/$path');
    }
  }

  // ─── Issues ────────────────────────────────────────────────────────

  /// Get issues for a repository.
  ///
  /// [owner] Repository owner.
  /// [repo]  Repository name.
  /// [state] Filter by state: 'open', 'closed', 'all' (default: 'open').
  ///
  /// Returns a list of issue objects (maps) from the GitHub API.
  Future<List<dynamic>> getIssues(
    String owner,
    String repo, {
    String state = 'open',
    int perPage = 50,
  }) async {
    _ensureAuthenticated();

    try {
      final response = await _api.get(
        '/repos/$owner/$repo/issues',
        query: {
          'state': state,
          'per_page': perPage,
          'sort': 'updated',
          'direction': 'desc',
        },
      );

      final data = response.data as List<dynamic>;

      // Filter out pull requests (GitHub includes PRs in issues endpoint).
      final issues = data.where((item) {
        if (item is! Map<String, dynamic>) return false;
        return item['pull_request'] == null;
      }).toList();

      debugPrint('[GitHubService] Fetched ${issues.length} issues for $owner/$repo');
      return issues;
    } on Exception catch (e) {
      throw _mapError(e, '/repos/$owner/$repo/issues');
    }
  }

  /// Create a comment on an issue.
  ///
  /// [owner]       Repository owner.
  /// [repo]        Repository name.
  /// [issueNumber] The issue number (not ID).
  /// [body]        The comment text (markdown supported).
  ///
  /// Returns true if the comment was created successfully.
  Future<bool> createIssueComment(
    String owner,
    String repo,
    int issueNumber,
    String body,
  ) async {
    _ensureAuthenticated();

    try {
      await _api.post(
        '/repos/$owner/$repo/issues/$issueNumber/comments',
        data: {'body': body},
      );

      debugPrint('[GitHubService] Created comment on issue #$issueNumber');
      return true;
    } on Exception catch (e) {
      throw _mapError(e, '/repos/$owner/$repo/issues/$issueNumber/comments');
    }
  }

  // ─── Pull Requests ─────────────────────────────────────────────────

  /// Get pull requests for a repository.
  Future<List<dynamic>> getPullRequests(
    String owner,
    String repo, {
    String state = 'open',
    int perPage = 50,
  }) async {
    _ensureAuthenticated();

    try {
      final response = await _api.get(
        '/repos/$owner/$repo/pulls',
        query: {
          'state': state,
          'per_page': perPage,
          'sort': 'updated',
          'direction': 'desc',
        },
      );

      return response.data as List<dynamic>;
    } on Exception catch (e) {
      throw _mapError(e, '/repos/$owner/$repo/pulls');
    }
  }

  /// Get the diff of a pull request.
  Future<String> getPullRequestDiff(
    String owner,
    String repo,
    int pullNumber,
  ) async {
    _ensureAuthenticated();

    try {
      final response = await _api.get(
        '/repos/$owner/$repo/pulls/$pullNumber',
        query: {'mediaType': {'diff': true}},
      );

      // GitHub returns diff as plain text when Accept: application/vnd.github.v3.diff is set.
      return response.data.toString();
    } on Exception catch (e) {
      throw _mapError(e, '/repos/$owner/$repo/pulls/$pullNumber');
    }
  }

  // ─── Commits ───────────────────────────────────────────────────────

  /// Get recent commits for a repository.
  Future<List<dynamic>> getCommits(
    String owner,
    String repo, {
    String? path,
    int perPage = 30,
  }) async {
    _ensureAuthenticated();

    try {
      final query = <String, dynamic>{
        'per_page': perPage,
        if (path != null) 'path': path,
      };

      final response = await _api.get(
        '/repos/$owner/$repo/commits',
        query: query,
      );

      return response.data as List<dynamic>;
    } on Exception catch (e) {
      throw _mapError(e, '/repos/$owner/$repo/commits');
    }
  }

  // ─── User ──────────────────────────────────────────────────────────

  /// Get the currently authenticated user's profile.
  Future<Map<String, dynamic>> getCurrentUser() async {
    _ensureAuthenticated();

    try {
      final response = await _api.get('/user');
      return response.data as Map<String, dynamic>;
    } on Exception catch (e) {
      throw _mapError(e, '/user');
    }
  }

  // ─── Private Helpers ───────────────────────────────────────────────

  void _ensureAuthenticated() {
    if (!isAuthenticated) {
      throw const GitHubException(
        message: 'Not authenticated. Call authenticate() first.',
      );
    }
  }

  /// Map generic errors to [GitHubException].
  GitHubException _mapError(Exception error, String endpoint) {
    if (error is GitHubException) return error;

    if (error is ApiException) {
      String message = error.message;
      int? code = error.statusCode;

      // Provide user-friendly messages for common GitHub errors.
      if (code == 401) {
        message = 'Authentication failed. Please check your token.';
      } else if (code == 403) {
        message = error.message.contains('rate limit')
            ? 'GitHub API rate limit exceeded. Please try again later.'
            : 'Access forbidden. Your token may lack required permissions.';
      } else if (code == 404) {
        message = 'Repository or resource not found.';
      } else if (code == 422) {
        message = 'Validation failed. The request data may be invalid.';
      }

      return GitHubException(
        message: message,
        endpoint: endpoint,
        statusCode: code,
        originalError: error,
      );
    }

    return GitHubException(
      message: error.toString(),
      endpoint: endpoint,
      originalError: error,
    );
  }
}
