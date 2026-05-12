import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'github_deep_service.dart';

// =============================================================================
// GITHUB GIST SERVICE
// =============================================================================

/// GitHub Gist API integration for MobileCode.
///
/// Create, read, update, delete, and star Gists. Gists are perfect
/// for sharing code snippets, quick notes, and single-file demos.
///
/// Uses the authenticated session from [GitHubDeepService] for all API calls.
///
/// Example:
/// ```dart
/// final gistService = GitHubGistService(githubDeepService);
/// final gists = await gistService.listGists();
/// final newGist = await gistService.createGist(
///   description: 'My snippet',
///   files: {'hello.dart': GistFile(filename: 'hello.dart', size: 0, content: 'void main() {}')},
/// );
/// ```
class GitHubGistService {
  static const String _baseUrl = 'https://api.github.com';
  static const String _apiVersion = '2022-11-28';

  final GitHubDeepService _github;
  final http.Client _httpClient;

  GitHubGistService(this._github, {http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  // ── Auth Helper ─────────────────────────────────────────────────────

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

  // ── CRUD ────────────────────────────────────────────────────────────

  /// List gists for the currently authenticated user.
  Future<List<Gist>> listGists({int page = 1, int perPage = 30}) async {
    final data = await _getJsonList(
      '/gists',
      query: {'page': '$page', 'per_page': '$perPage'},
    );
    return data.map((item) => Gist.fromJson(item as Map<String, dynamic>)).toList();
  }

  /// List public gists for discovery (no auth required).
  Future<List<Gist>> listPublicGists({int page = 1, int perPage = 30}) async {
    final data = await _getJsonList(
      '/gists/public',
      query: {'page': '$page', 'per_page': '$perPage'},
    );
    return data.map((item) => Gist.fromJson(item as Map<String, dynamic>)).toList();
  }

  /// List gists starred by the authenticated user.
  Future<List<Gist>> listStarredGists({int page = 1, int perPage = 30}) async {
    final data = await _getJsonList(
      '/gists/starred',
      query: {'page': '$page', 'per_page': '$perPage'},
    );
    return data.map((item) => Gist.fromJson(item as Map<String, dynamic>)).toList();
  }

  /// Get a single gist by its ID.
  ///
  /// Returns the gist with full file contents.
  Future<Gist> getGist(String gistId) async {
    final data = await _getJson('/gists/$gistId');
    if (data == null) {
      throw GitHubDeepException(message: 'Gist not found: $gistId');
    }
    return Gist.fromJson(data);
  }

  /// Create a new gist.
  ///
  /// [description] - Optional description of the gist.
  /// [files] - Map of filename to [GistFile]. Each file should have [content] set.
  /// [isPublic] - If true, the gist will be publicly discoverable.
  Future<Gist> createGist({
    required String description,
    required Map<String, GistFile> files,
    bool isPublic = true,
  }) async {
    final fileMap = <String, dynamic>{};
    for (final entry in files.entries) {
      fileMap[entry.key] = {
        'content': entry.value.content ?? '',
      };
    }

    final body = {
      'description': description,
      'public': isPublic,
      'files': fileMap,
    };

    final data = await _postJson('/gists', body: body);
    return Gist.fromJson(data);
  }

  /// Update an existing gist.
  ///
  /// Pass null content for a file to delete it. Pass new files to add them.
  /// Existing files not mentioned in [files] are left unchanged.
  Future<Gist> updateGist(
    String gistId, {
    String? description,
    Map<String, GistFile>? files,
  }) async {
    final body = <String, dynamic>{};
    if (description != null) {
      body['description'] = description;
    }
    if (files != null) {
      final fileMap = <String, dynamic>{};
      for (final entry in files.entries) {
        if (entry.value.content == null) {
          // Delete the file by passing null.
          fileMap[entry.key] = null;
        } else {
          fileMap[entry.key] = {'content': entry.value.content};
        }
      }
      body['files'] = fileMap;
    }

    final data = await _patchJson('/gists/$gistId', body: body);
    return Gist.fromJson(data);
  }

  /// Delete a gist permanently.
  Future<void> deleteGist(String gistId) async {
    await _deleteJson('/gists/$gistId');
  }

  // ── Stars ───────────────────────────────────────────────────────────

  /// Star a gist.
  Future<void> starGist(String gistId) async {
    await _putJson('/gists/$gistId/star', body: {});
  }

  /// Unstar a gist.
  Future<void> unstarGist(String gistId) async {
    await _deleteJson('/gists/$gistId/star');
  }

  /// Check if the authenticated user has starred a gist.
  Future<bool> isGistStarred(String gistId) async {
    try {
      final response = await _httpClient.get(
        _uri('/gists/$gistId/star'),
        headers: _headers,
      );
      return response.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  // ── Forks ───────────────────────────────────────────────────────────

  /// Fork a gist to the authenticated user's account.
  Future<Gist> forkGist(String gistId) async {
    final data = await _postJson('/gists/$gistId/forks', body: {});
    return Gist.fromJson(data);
  }

  /// List forks of a gist.
  Future<List<Gist>> listForks(String gistId) async {
    final data = await _getJsonList('/gists/$gistId/forks');
    return data.map((item) => Gist.fromJson(item as Map<String, dynamic>)).toList();
  }

  // ── Comments ────────────────────────────────────────────────────────

  /// List comments on a gist.
  Future<List<GistComment>> listComments(String gistId) async {
    final data = await _getJsonList('/gists/$gistId/comments');
    return data
        .map((item) => GistComment.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Create a comment on a gist.
  Future<GistComment> createComment(String gistId, String body) async {
    final data = await _postJson(
      '/gists/$gistId/comments',
      body: {'body': body},
    );
    return GistComment.fromJson(data);
  }

  /// Delete a comment on a gist.
  Future<void> deleteComment(String gistId, int commentId) async {
    await _deleteJson('/gists/$gistId/comments/$commentId');
  }

  // ── HTTP Helpers ────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _getJson(
    String path, {
    Map<String, String>? query,
  }) async {
    final response = await _httpClient.get(_uri(path, query: query), headers: _headers);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    _handleError(response, path);
    return null;
  }

  Future<List<dynamic>> _getJsonList(
    String path, {
    Map<String, String>? query,
  }) async {
    final response = await _httpClient.get(_uri(path, query: query), headers: _headers);
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

  Future<void> _putJson(String path, {Map<String, dynamic>? body}) async {
    final response = await _httpClient.put(
      _uri(path),
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    );
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    _handleError(response, path);
  }

  Future<void> _deleteJson(String path) async {
    final response = await _httpClient.delete(_uri(path), headers: _headers);
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    _handleError(response, path);
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

/// Represents a GitHub Gist — a single code snippet or collection of files.
@immutable
class Gist {
  final String id;
  final String description;
  final bool isPublic;
  final String owner;
  final String ownerAvatar;
  final Map<String, GistFile> files;
  final int comments;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int forks;
  final int stars;

  const Gist({
    required this.id,
    required this.description,
    required this.isPublic,
    required this.owner,
    required this.ownerAvatar,
    required this.files,
    required this.comments,
    required this.createdAt,
    required this.updatedAt,
    required this.forks,
    required this.stars,
  });

  /// Parse a Gist from the GitHub API JSON response.
  factory Gist.fromJson(Map<String, dynamic> json) {
    final ownerData = json['owner'] as Map<String, dynamic>?;
    final filesData = json['files'] as Map<String, dynamic>? ?? {};

    final files = <String, GistFile>{};
    for (final entry in filesData.entries) {
      final fileData = entry.value as Map<String, dynamic>?;
      if (fileData != null) {
        files[entry.key] = GistFile.fromJson(fileData);
      }
    }

    return Gist(
      id: json['id'] as String? ?? '',
      description: json['description'] as String? ?? '',
      isPublic: json['public'] as bool? ?? true,
      owner: ownerData?['login'] as String? ?? 'anonymous',
      ownerAvatar: ownerData?['avatar_url'] as String? ?? '',
      files: files,
      comments: json['comments'] as int? ?? 0,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
      forks: (json['forks'] as List<dynamic>?)?.length ?? 0,
      stars: 0, // GitHub doesn't return star count directly for gists.
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  /// HTML URL for viewing the gist in a browser.
  String get htmlUrl {
    if (owner == 'anonymous') return 'https://gist.github.com/$id';
    return 'https://gist.github.com/$owner/$id';
  }

  /// JavaScript embed URL for embedding the gist in web pages.
  String get embedUrl {
    if (owner == 'anonymous') return 'https://gist.github.com/$id.js';
    return 'https://gist.github.com/$owner/$id.js';
  }

  /// Number of files in this gist.
  int get fileCount => files.length;

  /// Name of the first file (for display purposes).
  String? get firstFileName => files.keys.firstOrNull;

  /// Language of the first file (for icon/display purposes).
  String? get firstFileLanguage => files.values.firstOrNull?.language;

  /// Get the content of a specific file by name.
  String? getFileContent(String filename) => files[filename]?.content;

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
  String toString() => 'Gist[$id]: $description (${files.length} files)';
}

/// Represents a single file within a GitHub Gist.
@immutable
class GistFile {
  final String filename;
  final String? language;
  final String? rawUrl;
  final int size;
  final String? content;
  final String? type;

  const GistFile({
    required this.filename,
    this.language,
    this.rawUrl,
    required this.size,
    this.content,
    this.type,
  });

  /// Parse a GistFile from the GitHub API JSON response.
  factory GistFile.fromJson(Map<String, dynamic> json) {
    return GistFile(
      filename: json['filename'] as String? ?? 'untitled',
      language: json['language'] as String?,
      rawUrl: json['raw_url'] as String?,
      size: json['size'] as int? ?? 0,
      content: json['content'] as String?,
      type: json['type'] as String?,
    );
  }

  /// Create a new GistFile with content for uploading.
  factory GistFile.withContent(String filename, String content, {String? language}) {
    return GistFile(
      filename: filename,
      language: language,
      size: content.length,
      content: content,
    );
  }

  /// Whether this file has its content loaded.
  bool get hasContent => content != null && content!.isNotEmpty;

  /// Short display name (truncated if too long).
  String get displayName => filename.length > 40 ? '${filename.substring(0, 37)}...' : filename;

  @override
  String toString() => 'GistFile[$filename, $language, $size bytes]';
}

/// Represents a comment on a GitHub Gist.
@immutable
class GistComment {
  final int id;
  final String user;
  final String userAvatar;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;

  const GistComment({
    required this.id,
    required this.user,
    required this.userAvatar,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Parse a GistComment from the GitHub API JSON response.
  factory GistComment.fromJson(Map<String, dynamic> json) {
    final userData = json['user'] as Map<String, dynamic>?;
    return GistComment(
      id: json['id'] as int? ?? 0,
      user: userData?['login'] as String? ?? 'unknown',
      userAvatar: userData?['avatar_url'] as String? ?? '',
      body: json['body'] as String? ?? '',
      createdAt: Gist._parseDate(json['created_at']),
      updatedAt: Gist._parseDate(json['updated_at']),
    );
  }

  @override
  String toString() => 'GistComment[$id by $user]';
}
