import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import 'github_deep_service.dart';
import 'terminal_service.dart';

// =============================================================================
// GITHUB PAGES SERVICE
// =============================================================================

/// Deploy static sites directly from MobileCode to GitHub Pages.
///
/// Supports deploying Flutter Web builds, static HTML sites, and Jekyll sites.
/// Orchestrates the build process, branch management, and GitHub Pages
/// configuration through the GitHub API.
///
/// Example:
/// ```dart
/// final pages = GitHubPagesService(githubService);
/// final result = await pages.deploy(
///   localProjectPath: '/projects/my-app',
///   owner: 'username',
///   repo: 'my-app',
///   buildType: BuildType.flutterWeb,
/// );
/// if (result.success) print('Deployed to: ${result.url}');
/// ```
class GitHubPagesService {
  static const String _baseUrl = 'https://api.github.com';
  static const String _apiVersion = '2022-11-28';

  final GitHubDeepService _github;
  final TerminalService _terminal;
  final http.Client _httpClient;

  GitHubPagesService(
    this._github, {
    TerminalService? terminalService,
    http.Client? httpClient,
  })  : _terminal = terminalService ?? TerminalService(),
        _httpClient = httpClient ?? http.Client();

  // ── Auth / Headers ──────────────────────────────────────────────────

  Map<String, String> get _headers {
    final token = _github.activeSession?.token;
    if (token == null) {
      throw const GitHubDeepException(message: 'Not authenticated');
    }
    return {
      'Authorization': 'Bearer $token',
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': _apiVersion,
      'Content-Type': 'application/json',
      'User-Agent': 'MobileAgent/1.0',
    };
  }

  Uri _uri(String path, {Map<String, String>? query}) {
    final base = Uri.parse('$_baseUrl$path');
    if (query == null || query.isEmpty) return base;
    return base.replace(queryParameters: query);
  }

  static GitHubPagesFailureDetails describeFailure(Object error) {
    if (error is GitHubDeepException) {
      final status = error.statusCode;
      final lower = error.message.toLowerCase();
      if (status == 401) {
        return GitHubPagesFailureDetails(
          message: 'GitHub token is invalid or expired.',
          recoveryHint: 'Open GitHub login and save a fresh token before publishing again.',
          failureKind: 'auth_invalid',
          statusCode: status,
          endpoint: error.endpoint,
        );
      }
      if (status == 403) {
        final rateLimited = lower.contains('rate limit') || lower.contains('secondary rate');
        return GitHubPagesFailureDetails(
          message: rateLimited
              ? 'GitHub rejected the request because this token or device is rate limited.'
              : 'GitHub token does not have enough repository or Pages permission.',
          recoveryHint: rateLimited
              ? 'Wait for the rate limit window to reset, then retry. If this keeps happening, use an authenticated token.'
              : 'Fine-grained tokens need Repository contents read/write, Pages read/write, and Administration read/write. Classic PATs need the repo scope.',
          failureKind: rateLimited ? 'rate_limited' : 'permission_denied',
          statusCode: status,
          endpoint: error.endpoint,
        );
      }
      if (status == 404) {
        return GitHubPagesFailureDetails(
          message: 'GitHub repository or Pages endpoint is not visible to this token.',
          recoveryHint: 'Confirm the owner/repo name, repository visibility, and token access. Private repos require a token that can read and write that repo.',
          failureKind: 'not_found_or_not_visible',
          statusCode: status,
          endpoint: error.endpoint,
        );
      }
      if (status == 409) {
        return GitHubPagesFailureDetails(
          message: 'GitHub Pages is already configured but the Pages source could not be updated.',
          recoveryHint: 'Retry after a moment. If it still fails, check that the gh-pages branch exists and the token can administer Pages.',
          failureKind: 'pages_conflict',
          statusCode: status,
          endpoint: error.endpoint,
        );
      }
      if (status == 422) {
        return GitHubPagesFailureDetails(
          message: 'GitHub rejected the repository or Pages configuration.',
          recoveryHint: 'Use a simpler repository name, publish to a public repo when possible, and make sure the Pages source branch/path is valid.',
          failureKind: 'validation_failed',
          statusCode: status,
          endpoint: error.endpoint,
        );
      }
      return GitHubPagesFailureDetails(
        message: error.message,
        recoveryHint: 'Review the GitHub response and retry after correcting the repository, token, or Pages settings.',
        failureKind: 'github_api_failed',
        statusCode: status,
        endpoint: error.endpoint,
      );
    }

    return GitHubPagesFailureDetails(
      message: error.toString(),
      recoveryHint: 'Check network connectivity and retry. If this repeats, run the GitHub connectivity test from Tools.',
      failureKind: 'unexpected_failure',
    );
  }

  // ── Deployment ──────────────────────────────────────────────────────

  /// Deploy a local project to GitHub Pages.
  ///
  /// Steps performed:
  /// 1. Build the project based on [buildType]
  /// 2. Get or create the target branch (default: 'gh-pages')
  /// 3. Commit build output to the branch
  /// 4. Enable GitHub Pages if not already enabled
  /// 5. Return the deployment URL
  ///
  /// [customDomain] - Optional custom domain (creates CNAME file).
  Future<DeploymentResult> deploy({
    required String localProjectPath,
    required String owner,
    required String repo,
    required BuildType buildType,
    String? branch,
    String? customDomain,
  }) async {
    final targetBranch = branch ?? 'gh-pages';
    final steps = <String>[];

    try {
      // Step 1: Build.
      steps.add('Building project (${buildType.name})...');
      final String buildOutputPath;
      switch (buildType) {
        case BuildType.flutterWeb:
          buildOutputPath = await _buildFlutterWeb(localProjectPath);
          break;
        case BuildType.staticHtml:
          buildOutputPath = await _buildStatic(localProjectPath);
          break;
        case BuildType.jekyll:
          buildOutputPath = await _buildJekyll(localProjectPath);
          break;
      }
      steps.add('Build complete: $buildOutputPath');

      // Step 2: Prepare build output (CNAME, etc.).
      final preparedPath = await _prepareBuildOutput(
        buildOutputPath,
        customDomain: customDomain,
      );
      if (customDomain != null) {
        steps.add('Custom domain configured: $customDomain');
      }

      // Step 3: Get the default branch SHA for orphan branch creation.
      steps.add('Creating $targetBranch branch...');
      final repoDetails = await _github.getRepoDetails(owner, repo);
      final defaultBranch = repoDetails['default_branch'] as String? ?? 'main';

      // Step 4: Create/update gh-pages branch via GitHub API (tree + commit + ref).
      await _commitBuildOutput(
        owner: owner,
        repo: repo,
        buildPath: preparedPath,
        branch: targetBranch,
        defaultBranch: defaultBranch,
        steps: steps,
      );
      steps.add('Build output committed to $targetBranch');

      // Step 5: Enable GitHub Pages.
      steps.add('Enabling GitHub Pages...');
      await enablePages(owner, repo, branch: targetBranch);
      steps.add('GitHub Pages enabled');

      // Step 6: Set custom domain via API if provided.
      if (customDomain != null && customDomain.isNotEmpty) {
        await setCustomDomain(owner, repo, customDomain);
        steps.add('Custom domain set: $customDomain');
      }

      // Determine the deployment URL.
      final url = _buildPagesUrl(owner, repo, customDomain);

      return DeploymentResult(
        success: true,
        url: url,
        customDomain: customDomain,
        deployedAt: DateTime.now(),
        steps: steps,
      );
    } on GitHubDeepException catch (e) {
      final failure = describeFailure(e);
      steps.add('Error: ${failure.message}');
      return DeploymentResult(
        success: false,
        url: null,
        customDomain: customDomain,
        deployedAt: DateTime.now(),
        error: failure.message,
        recoveryHint: failure.recoveryHint,
        failureKind: failure.failureKind,
        statusCode: failure.statusCode,
        steps: steps,
      );
    } catch (e) {
      final failure = describeFailure(e);
      steps.add('Unexpected error: ${failure.message}');
      return DeploymentResult(
        success: false,
        url: null,
        customDomain: customDomain,
        deployedAt: DateTime.now(),
        error: failure.message,
        recoveryHint: failure.recoveryHint,
        failureKind: failure.failureKind,
        statusCode: failure.statusCode,
        steps: steps,
      );
    }
  }

  /// Check the current GitHub Pages deployment status.
  Future<DeploymentStatus> getDeploymentStatus(String owner, String repo) async {
    try {
      final response = await _httpClient.get(
        _uri('/repos/$owner/$repo/pages'),
        headers: _headers,
      );
      if (response.statusCode == 404) {
        return const DeploymentStatus(isEnabled: false);
      }
      if (response.statusCode != 200) {
        return DeploymentStatus(
          isEnabled: false,
          error: 'HTTP ${response.statusCode}',
        );
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final source = data['source'] as Map<String, dynamic>?;
      return DeploymentStatus(
        isEnabled: data['status'] == 'built',
        url: data['html_url'] as String?,
        status: data['status'] as String?, // building, built, errored
        lastDeployedAt: _parseDateTime(data['updated_at']),
      );
    } catch (e) {
      return DeploymentStatus(isEnabled: false, error: e.toString());
    }
  }

  /// Enable GitHub Pages for a repository.
  Future<void> enablePages(
    String owner,
    String repo, {
    String branch = 'gh-pages',
    String path = '/',
  }) async {
    final response = await _httpClient.post(
      _uri('/repos/$owner/$repo/pages'),
      headers: _headers,
      body: jsonEncode({
        'source': {
          'branch': branch,
          'path': path,
        },
      }),
    );
    if (response.statusCode == 201 || response.statusCode == 204 || response.statusCode == 409) {
      if (response.statusCode == 409) {
        await _updatePagesSource(owner, repo, branch: branch, path: path);
      }
      return;
    }
    _handleError(response, '/repos/$owner/$repo/pages');
  }

  Future<void> _updatePagesSource(
    String owner,
    String repo, {
    required String branch,
    required String path,
  }) async {
    final response = await _httpClient.put(
      _uri('/repos/$owner/$repo/pages'),
      headers: _headers,
      body: jsonEncode({
        'source': {
          'branch': branch,
          'path': path,
        },
      }),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    _handleError(response, '/repos/$owner/$repo/pages');
  }

  /// Disable GitHub Pages for a repository.
  Future<void> disablePages(String owner, String repo) async {
    final response = await _httpClient.delete(
      _uri('/repos/$owner/$repo/pages'),
      headers: _headers,
    );
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    _handleError(response, '/repos/$owner/$repo/pages');
  }

  /// Set a custom domain for GitHub Pages.
  Future<void> setCustomDomain(String owner, String repo, String domain) async {
    final response = await _httpClient.put(
      _uri('/repos/$owner/$repo/pages'),
      headers: _headers,
      body: jsonEncode({
        'cname': domain,
        'source': {
          'branch': 'gh-pages',
          'path': '/',
        },
      }),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    _handleError(response, '/repos/$owner/$repo/pages');
  }

  /// Get deployment history for a repository.
  Future<List<Deployment>> getDeployments(String owner, String repo) async {
    final data = await _getJsonList('/repos/$owner/$repo/deployments');
    return data
        .map((item) => Deployment.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Get the latest deployment for a repository.
  Future<Deployment?> getLatestDeployment(String owner, String repo) async {
    final deployments = await getDeployments(owner, repo);
    if (deployments.isEmpty) return null;
    return deployments.first;
  }

  // ── Build Automation ────────────────────────────────────────────────

  /// Build a Flutter Web project. Returns the path to the build/web directory.
  Future<String> _buildFlutterWeb(String projectPath) async {
    final buildDir = path.join(projectPath, 'build', 'web');

    // Clean previous build.
    final cleanResult = await _terminal.flutterClean(projectPath);
    if (!cleanResult.success) {
      debugPrint('[PagesService] flutter clean warning: ${cleanResult.stderr}');
    }

    // Build for web.
    final result = await _terminal.execute(
      'flutter build web --release',
      workingDirectory: projectPath,
      timeoutSeconds: 300,
    );
    if (!result.success) {
      throw GitHubDeepException(
        message: 'Flutter web build failed: ${result.stderr}',
      );
    }

    if (!Directory(buildDir).existsSync()) {
      throw const GitHubDeepException(message: 'Build output directory not found');
    }
    return buildDir;
  }

  /// Build a static HTML project. Returns the project path (no build needed).
  Future<String> _buildStatic(String projectPath) async {
    // Static HTML projects don't need a build step.
    // Return the project root; we'll deploy all HTML/CSS/JS files.
    return projectPath;
  }

  /// Build a Jekyll site. Returns the path to the _site directory.
  Future<String> _buildJekyll(String projectPath) async {
    final result = await _terminal.execute(
      'bundle exec jekyll build',
      workingDirectory: projectPath,
      timeoutSeconds: 180,
    );
    if (!result.success) {
      throw GitHubDeepException(
        message: 'Jekyll build failed: ${result.stderr}',
      );
    }
    final siteDir = path.join(projectPath, '_site');
    if (!Directory(siteDir).existsSync()) {
      throw const GitHubDeepException(message: 'Jekyll _site directory not found');
    }
    return siteDir;
  }

  /// Prepare build output for deployment.
  ///
  /// Creates a CNAME file if [customDomain] is provided.
  /// Returns the path to the prepared build directory.
  Future<String> _prepareBuildOutput(
    String buildPath, {
    String? customDomain,
  }) async {
    if (customDomain != null && customDomain.isNotEmpty) {
      final cnameFile = File(path.join(buildPath, 'CNAME'));
      await cnameFile.writeAsString(customDomain);
    }
    return buildPath;
  }

  // ── GitHub API: Commit Build Output ─────────────────────────────────

  /// Commit all files from [buildPath] to the [branch] branch using the
  /// GitHub Git Data API (trees + commits + refs).
  Future<void> _commitBuildOutput({
    required String owner,
    required String repo,
    required String buildPath,
    required String branch,
    required String defaultBranch,
    required List<String> steps,
  }) async {
    // 1. Get the current commit SHA of the default branch.
    final defaultRef = await _getJson('/repos/$owner/$repo/git/refs/heads/$defaultBranch');
    final baseCommitSha = defaultRef?['object']?['sha'] as String?;
    if (baseCommitSha == null) {
      throw const GitHubDeepException(message: 'Could not get default branch commit');
    }

    // 2. Collect all files from the build directory.
    final buildDir = Directory(buildPath);
    if (!buildDir.existsSync()) {
      throw GitHubDeepException(message: 'Build directory not found: $buildPath');
    }

    final fileEntries = <_FileEntry>[];
    await for (final entity in buildDir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final relativePath = path.relative(entity.path, from: buildPath);
        // Skip hidden files and directories.
        if (relativePath.startsWith('.')) continue;
        final content = await entity.readAsBytes();
        fileEntries.add(_FileEntry(path: relativePath, content: content));
      }
    }

    steps.add('Found ${fileEntries.length} files to deploy');

    // 3. Create blobs for each file.
    final treeItems = <Map<String, dynamic>>[];
    for (var i = 0; i < fileEntries.length; i++) {
      final entry = fileEntries[i];
      final isBinary = _isBinaryContent(entry.content);

      if (isBinary) {
        // Create a blob for binary content.
        final blobData = await _postJson(
          '/repos/$owner/$repo/git/blobs',
          body: {
            'content': base64Encode(entry.content),
            'encoding': 'base64',
          },
        );
        final blobSha = blobData['sha'] as String;
        treeItems.add({
          'path': entry.path,
          'mode': '100644',
          'type': 'blob',
          'sha': blobSha,
        });
      } else {
        // For text files, inline the content in the tree.
        treeItems.add({
          'path': entry.path,
          'mode': '100644',
          'type': 'blob',
          'content': utf8.decode(entry.content, allowMalformed: true),
        });
      }

      if ((i + 1) % 50 == 0) {
        steps.add('Processed ${i + 1}/${fileEntries.length} files...');
      }
    }

    // 4. Create a tree.
    final treeData = await _postJson(
      '/repos/$owner/$repo/git/trees',
      body: {'tree': treeItems},
    );
    final treeSha = treeData['sha'] as String;

    // 5. Create a commit.
    final commitData = await _postJson(
      '/repos/$owner/$repo/git/commits',
      body: {
        'message': 'Deploy to GitHub Pages from MobileCode',
        'tree': treeSha,
        if (baseCommitSha != null) 'parents': [baseCommitSha],
      },
    );
    final newCommitSha = commitData['sha'] as String;

    // 6. Update or create the branch ref.
    try {
      await _postJson(
        '/repos/$owner/$repo/git/refs',
        body: {
          'ref': 'refs/heads/$branch',
          'sha': newCommitSha,
        },
      );
    } catch (e) {
      // Ref might already exist; update it.
      await _patchJson(
        '/repos/$owner/$repo/git/refs/heads/$branch',
        body: {'sha': newCommitSha, 'force': true},
      );
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  String _buildPagesUrl(String owner, String repo, String? customDomain) {
    if (customDomain != null && customDomain.isNotEmpty) {
      return 'https://$customDomain';
    }
    return 'https://$owner.github.io/$repo';
  }

  bool _isBinaryContent(List<int> bytes) {
    // Check if content contains null bytes (likely binary).
    for (var i = 0; i < bytes.length && i < 8000; i++) {
      if (bytes[i] == 0) return true;
    }
    return false;
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  // ── HTTP Helpers ────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _getJson(String path) async {
    final response = await _httpClient.get(_uri(path), headers: _headers);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    _handleError(response, path);
    return null;
  }

  Future<List<dynamic>> _getJsonList(String path) async {
    final response = await _httpClient.get(_uri(path), headers: _headers);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return [];
      return jsonDecode(response.body) as List<dynamic>;
    }
    _handleError(response, path);
    return [];
  }

  Future<Map<String, dynamic>> _postJson(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _httpClient.post(
      _uri(path),
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    _handleError(response, path);
    return {};
  }

  Future<Map<String, dynamic>> _patchJson(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _httpClient.patch(
      _uri(path),
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    _handleError(response, path);
    return {};
  }

  void _handleError(http.Response response, String path) {
    String message = 'Request failed';
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      message = body['message'] as String? ?? response.body;
    } catch (_) {
      message = response.body.isNotEmpty ? response.body : 'HTTP ${response.statusCode}';
    }
    throw GitHubDeepException(
      message: message,
      endpoint: path,
      statusCode: response.statusCode,
    );
  }

  /// Dispose resources.
  void dispose() {
    _httpClient.close();
  }
}

// =============================================================================
// DATA MODELS
// =============================================================================

/// The type of project to build and deploy.
enum BuildType {
  /// Flutter web project (builds with `flutter build web`).
  flutterWeb,

  /// Static HTML/CSS/JS project (no build step).
  staticHtml,

  /// Jekyll site (builds with `bundle exec jekyll build`).
  jekyll,
}

/// Result of a deployment operation.
@immutable
class DeploymentResult {
  final bool success;
  final String? url;
  final String? customDomain;
  final DateTime deployedAt;
  final String? error;
  final String? recoveryHint;
  final String? failureKind;
  final int? statusCode;
  final List<String> steps;

  const DeploymentResult({
    required this.success,
    this.url,
    this.customDomain,
    required this.deployedAt,
    this.error,
    this.recoveryHint,
    this.failureKind,
    this.statusCode,
    this.steps = const [],
  });

  @override
  String toString() =>
      'DeploymentResult[success=$success, url=$url, steps=${steps.length}]';
}

/// User-facing explanation for GitHub Pages failures.
class GitHubPagesFailureDetails {
  const GitHubPagesFailureDetails({
    required this.message,
    required this.recoveryHint,
    required this.failureKind,
    this.statusCode,
    this.endpoint,
  });

  final String message;
  final String recoveryHint;
  final String failureKind;
  final int? statusCode;
  final String? endpoint;
}

/// Current status of GitHub Pages for a repository.
@immutable
class DeploymentStatus {
  final bool isEnabled;
  final String? url;
  final String? status;
  final DateTime? lastDeployedAt;
  final String? error;

  const DeploymentStatus({
    required this.isEnabled,
    this.url,
    this.status,
    this.lastDeployedAt,
    this.error,
  });

  @override
  String toString() =>
      'DeploymentStatus[enabled=$isEnabled, status=$status, url=$url]';
}

/// A single deployment entry from the GitHub deployments API.
@immutable
class Deployment {
  final int id;
  final String sha;
  final String ref;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? creator;
  final String environment;
  final String state;

  const Deployment({
    required this.id,
    required this.sha,
    required this.ref,
    this.description,
    required this.createdAt,
    required this.updatedAt,
    this.creator,
    required this.environment,
    required this.state,
  });

  factory Deployment.fromJson(Map<String, dynamic> json) {
    final creatorData = json['creator'] as Map<String, dynamic>?;
    return Deployment(
      id: json['id'] as int? ?? 0,
      sha: json['sha'] as String? ?? '',
      ref: json['ref'] as String? ?? '',
      description: json['description'] as String?,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
      creator: creatorData?['login'] as String?,
      environment: json['environment'] as String? ?? 'github-pages',
      state: json['state'] as String? ?? 'unknown',
    );
  }

  /// Whether this deployment was successful.
  bool get isSuccess => state == 'success';

  /// Whether this deployment failed.
  bool get isFailure => state == 'failure' || state == 'error';

  /// Whether this deployment is still pending.
  bool get isPending => state == 'pending';

  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return DateTime.now();
      }
    }
    return DateTime.now();
  }

  @override
  String toString() => 'Deployment[$id, $ref, $state]';
}

// Internal helper for file entries during deployment.
class _FileEntry {
  final String path;
  final List<int> content;

  _FileEntry({required this.path, required this.content});
}
