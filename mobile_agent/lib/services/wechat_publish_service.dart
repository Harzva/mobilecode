// lib/services/wechat_publish_service.dart
// WeChat Publish Service — Publishes articles to WeChat Official Account (微信公众号).
//
// Authentication methods:
// 1. WeChat Official Account API (AppID + AppSecret)
// 2. WeChat Work / Open Platform
// 3. Manual publish assist (generate QR code for scan)
//
// Features:
// - Draft article creation
// - Media upload (images)
// - Article preview before publish
// - Schedule publishing
// - Publish history

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/agent_paradigm.dart';
import 'secure_storage_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Exceptions
// ═══════════════════════════════════════════════════════════════════════════

/// Exception thrown when WeChat API operations fail.
class WeChatApiException implements Exception {
  final int errcode;
  final String errmsg;
  final String? operation;

  const WeChatApiException({
    required this.errcode,
    required this.errmsg,
    this.operation,
  });

  @override
  String toString() =>
      'WeChatApiException [$operation] code=$errcode: $errmsg';
}

/// Exception thrown when authentication fails.
class WeChatAuthException implements Exception {
  final String message;

  const WeChatAuthException({required this.message});

  @override
  String toString() => 'WeChatAuthException: $message';
}

// ═══════════════════════════════════════════════════════════════════════════
// Data Models
// ═══════════════════════════════════════════════════════════════════════════

/// Represents a WeChat article draft.
class WeChatDraft {
  final String mediaId;
  final String title;
  final String content;
  final String? author;
  final String? digest;
  final DateTime createTime;
  final DateTime updateTime;
  final String? thumbUrl;
  final String? contentSourceUrl;
  final int needOpenComment;
  final int onlyFansCanComment;

  const WeChatDraft({
    required this.mediaId,
    required this.title,
    required this.content,
    this.author,
    this.digest,
    required this.createTime,
    required this.updateTime,
    this.thumbUrl,
    this.contentSourceUrl,
    this.needOpenComment = 0,
    this.onlyFansCanComment = 0,
  });

  /// Serializes to JSON for API requests.
  Map<String, dynamic> toJson() => {
        'title': title,
        'content': content,
        if (author != null) 'author': author,
        if (digest != null) 'digest': digest,
        if (thumbUrl != null) 'thumb_media_id': thumbUrl,
        if (contentSourceUrl != null) 'content_source_url': contentSourceUrl,
        'need_open_comment': needOpenComment,
        'only_fans_can_comment': onlyFansCanComment,
      };

  /// Creates a copy with some fields modified.
  WeChatDraft copyWith({
    String? mediaId,
    String? title,
    String? content,
    String? author,
    String? digest,
    DateTime? createTime,
    DateTime? updateTime,
    String? thumbUrl,
    String? contentSourceUrl,
    int? needOpenComment,
    int? onlyFansCanComment,
  }) {
    return WeChatDraft(
      mediaId: mediaId ?? this.mediaId,
      title: title ?? this.title,
      content: content ?? this.content,
      author: author ?? this.author,
      digest: digest ?? this.digest,
      createTime: createTime ?? this.createTime,
      updateTime: updateTime ?? this.updateTime,
      thumbUrl: thumbUrl ?? this.thumbUrl,
      contentSourceUrl: contentSourceUrl ?? this.contentSourceUrl,
      needOpenComment: needOpenComment ?? this.needOpenComment,
      onlyFansCanComment: onlyFansCanComment ?? this.onlyFansCanComment,
    );
  }

  @override
  String toString() => 'WeChatDraft($mediaId): "$title"';
}

/// Represents a published WeChat article.
class WeChatArticle {
  final String msgId;
  final String title;
  final String? url;
  final DateTime publishTime;
  final int readCount;
  final int likeCount;

  const WeChatArticle({
    required this.msgId,
    required this.title,
    this.url,
    required this.publishTime,
    this.readCount = 0,
    this.likeCount = 0,
  });

  factory WeChatArticle.fromJson(Map<String, dynamic> json) {
    return WeChatArticle(
      msgId: json['msg_id']?.toString() ?? json['msg_data_id']?.toString() ?? '',
      title: json['title'] ?? '',
      url: json['url'] ?? json['content_url'],
      publishTime: json['publish_time'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['publish_time'] as int) * 1000)
          : DateTime.now(),
      readCount: json['read_count'] ?? 0,
      likeCount: json['like_count'] ?? 0,
    );
  }

  @override
  String toString() => 'WeChatArticle($msgId): "$title"';
}

/// Result of a publish operation.
class WeChatPublishResult {
  final bool success;
  final String? publishId;
  final String? mediaId;
  final String? error;
  final DateTime? timestamp;

  const WeChatPublishResult({
    required this.success,
    this.publishId,
    this.mediaId,
    this.error,
    this.timestamp,
  });

  factory WeChatPublishResult.success({
    required String publishId,
    String? mediaId,
  }) {
    return WeChatPublishResult(
      success: true,
      publishId: publishId,
      mediaId: mediaId,
      timestamp: DateTime.now(),
    );
  }

  factory WeChatPublishResult.failure(String error) {
    return WeChatPublishResult(
      success: false,
      error: error,
      timestamp: DateTime.now(),
    );
  }

  @override
  String toString() =>
      success ? 'PublishResult OK($publishId)' : 'PublishResult FAIL: $error';
}

/// Publish status enum.
enum PublishStatus {
  /// Publishing in progress.
  publishing,

  /// Published successfully.
  published,

  /// Publish failed.
  failed,

  /// Unknown status.
  unknown,
}

/// Article statistics (reads, likes, shares, etc.).
class ArticleStats {
  final int readCount;
  final int likeCount;
  final int shareCount;
  final int commentCount;
  final int forwardCount;

  const ArticleStats({
    this.readCount = 0,
    this.likeCount = 0,
    this.shareCount = 0,
    this.commentCount = 0,
    this.forwardCount = 0,
  });

  factory ArticleStats.fromJson(Map<String, dynamic> json) {
    return ArticleStats(
      readCount: json['int_page_read_user'] ?? json['read_count'] ?? 0,
      likeCount: json['like_user'] ?? json['like_count'] ?? 0,
      shareCount: json['share_user'] ?? json['share_count'] ?? 0,
      commentCount: json['comment_count'] ?? 0,
      forwardCount: json['add_to_fav_user'] ?? json['forward_count'] ?? 0,
    );
  }

  @override
  String toString() =>
      'ArticleStats(reads=$readCount, likes=$likeCount, shares=$shareCount)';
}

// ═══════════════════════════════════════════════════════════════════════════
// WeChat Publish Service
// ═══════════════════════════════════════════════════════════════════════════

/// Publishes articles to WeChat Official Account (微信公众号).
///
/// Uses the WeChat Official Account API for draft management,
/// media upload, publishing, and statistics.
///
/// ## Usage
/// ```dart
/// final service = WeChatPublishService(secureStorage);
/// await service.authenticate(appId, appSecret);
/// final draft = await service.createDraft(title: 'Hello', content: '<p>World</p>');
/// final result = await service.publish(draft.mediaId);
/// ```
class WeChatPublishService {
  final SecureStorageService _secureStorage;
  final Dio _dio;

  String? _accessToken;
  DateTime? _tokenExpiry;
  String? _currentAppId;

  // ── Constants ──────────────────────────────────────────────

  static const String _baseUrl = 'https://api.weixin.qq.com/cgi-bin';
  static const String _storageKeyAppId = 'wechat_app_id';
  static const String _storageKeyAppSecret = 'wechat_app_secret';
  static const Duration _tokenBuffer = Duration(minutes: 5);

  // In-memory cache for drafts and articles.
  final List<WeChatDraft> _draftCache = [];
  final List<WeChatArticle> _articleCache = [];

  // ── Constructor ────────────────────────────────────────────

  WeChatPublishService(this._secureStorage) : _dio = Dio(BaseOptions(
          baseUrl: _baseUrl,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ));

  // ═══════════════════════════════════════════════════════════════════════
  // Authentication
  // ═══════════════════════════════════════════════════════════════════════

  /// Whether the service is currently authenticated.
  bool get isAuthenticated =>
      _accessToken != null &&
      _tokenExpiry != null &&
      DateTime.now().isBefore(_tokenExpiry!.subtract(_tokenBuffer));

  /// Current AppID (if authenticated).
  String? get currentAppId => _currentAppId;

  /// Authenticate with WeChat Official Account using AppID + AppSecret.
  ///
  /// Stores credentials securely for future sessions.
  /// Returns `true` if authentication succeeded.
  Future<bool> authenticate(String appId, String appSecret) async {
    try {
      debugPrint('[WeChatPublish] Authenticating with AppID: $appId');

      final token = await _fetchAccessToken(appId, appSecret);
      if (token == null) {
        throw const WeChatAuthException(message: 'Failed to obtain access token');
      }

      _accessToken = token;
      _tokenExpiry = DateTime.now().add(const Duration(hours: 2));
      _currentAppId = appId;

      // Store credentials securely.
      await _secureStorage.write(_storageKeyAppId, appId);
      await _secureStorage.write(_storageKeyAppSecret, appSecret);

      debugPrint('[WeChatPublish] Authenticated successfully');
      return true;
    } catch (e) {
      debugPrint('[WeChatPublish] Authentication failed: $e');
      _accessToken = null;
      _tokenExpiry = null;
      _currentAppId = null;
      return false;
    }
  }

  /// Restore authentication from securely stored credentials.
  ///
  /// Call this on app startup to re-authenticate without
  /// requiring the user to re-enter credentials.
  Future<bool> restoreAuthentication() async {
    try {
      final appId = await _secureStorage.read(_storageKeyAppId);
      final appSecret = await _secureStorage.read(_storageKeyAppSecret);

      if (appId == null || appSecret == null) {
        debugPrint('[WeChatPublish] No stored credentials found');
        return false;
      }

      return authenticate(appId, appSecret);
    } catch (e) {
      debugPrint('[WeChatPublish] Failed to restore authentication: $e');
      return false;
    }
  }

  /// Logout and clear all credentials.
  Future<void> logout() async {
    _accessToken = null;
    _tokenExpiry = null;
    _currentAppId = null;
    _draftCache.clear();
    _articleCache.clear();

    try {
      await _secureStorage.delete(_storageKeyAppId);
      await _secureStorage.delete(_storageKeyAppSecret);
    } catch (e) {
      debugPrint('[WeChatPublish] Error clearing credentials: $e');
    }

    debugPrint('[WeChatPublish] Logged out');
  }

  /// Fetch access token from WeChat API.
  Future<String?> _fetchAccessToken(String appId, String appSecret) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/token',
      queryParameters: {
        'grant_type': 'client_credential',
        'appid': appId,
        'secret': appSecret,
      },
    );

    final data = response.data;
    if (data == null) return null;

    if (data.containsKey('access_token')) {
      return data['access_token'] as String;
    }

    final errcode = data['errcode'] as int? ?? -1;
    final errmsg = data['errmsg'] as String? ?? 'Unknown error';
    throw WeChatApiException(errcode: errcode, errmsg: errmsg, operation: 'getAccessToken');
  }

  /// Ensure we have a valid access token, refreshing if needed.
  Future<String> _ensureToken() async {
    if (isAuthenticated && _accessToken != null) {
      return _accessToken!;
    }

    // Try to refresh from stored credentials.
    final success = await restoreAuthentication();
    if (!success || _accessToken == null) {
      throw const WeChatAuthException(
        message: 'Not authenticated. Please authenticate first.',
      );
    }
    return _accessToken!;
  }

  // ── API Helper ─────────────────────────────────────────────

  /// Make an authenticated API call.
  Future<Response<Map<String, dynamic>>> _apiGet(
    String path, {
    Map<String, dynamic>? params,
  }) async {
    final token = await _ensureToken();
    final queryParams = <String, dynamic>{'access_token': token};
    if (params != null) queryParams.addAll(params);

    final response = await _dio.get<Map<String, dynamic>>(path, queryParameters: queryParams);
    _checkError(response.data);
    return response;
  }

  /// Make an authenticated POST API call.
  Future<Response<Map<String, dynamic>>> _apiPost(
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParams,
  }) async {
    final token = await _ensureToken();
    final params = <String, dynamic>{'access_token': token};
    if (queryParams != null) params.addAll(queryParams);

    final response = await _dio.post<Map<String, dynamic>>(
      path,
      queryParameters: params,
      data: data,
    );
    _checkError(response.data);
    return response;
  }

  /// Check for WeChat API errors in response.
  void _checkError(Map<String, dynamic>? data) {
    if (data == null) return;
    final errcode = data['errcode'] as int?;
    if (errcode != null && errcode != 0) {
      final errmsg = data['errmsg'] as String? ?? 'Unknown WeChat API error';
      throw WeChatApiException(errcode: errcode, errmsg: errmsg);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Draft Management
  // ═══════════════════════════════════════════════════════════════════════

  /// Create a new draft article.
  ///
  /// [title] Article title (required).
  /// [content] Article content in HTML format (required).
  /// [author] Author name (optional).
  /// [digest] Article summary/digest (optional, max 120 characters).
  /// [contentSourceUrl] Original source URL (optional).
  /// [thumbMediaId] Cover image media ID (optional).
  /// [needOpenComment] Whether to open comments: 0 = no, 1 = yes.
  /// [onlyFansCanComment] Whether only followers can comment: 0 = no, 1 = yes.
  Future<WeChatDraft> createDraft({
    required String title,
    required String content,
    String? author,
    String? digest,
    String? contentSourceUrl,
    String? thumbMediaId,
    int? needOpenComment,
    int? onlyFansCanComment,
  }) async {
    final htmlContent = _convertToWeChatHtml(content);

    final articles = [
      {
        'title': title,
        'content': htmlContent,
        if (author != null && author.isNotEmpty) 'author': author,
        if (digest != null && digest.isNotEmpty) 'digest': digest,
        if (contentSourceUrl != null && contentSourceUrl.isNotEmpty)
          'content_source_url': contentSourceUrl,
        if (thumbMediaId != null && thumbMediaId.isNotEmpty)
          'thumb_media_id': thumbMediaId,
        'need_open_comment': needOpenComment ?? 0,
        'only_fans_can_comment': onlyFansCanComment ?? 0,
        'show_cover_pic': 1,
      }
    ];

    final response = await _apiPost(
      '/draft/add',
      data: {'articles': articles},
    );

    final mediaId = response.data?['media_id'] as String? ??
        response.data?['draft_id']?.toString() ??
        '';

    final draft = WeChatDraft(
      mediaId: mediaId,
      title: title,
      content: content,
      author: author,
      digest: digest,
      createTime: DateTime.now(),
      updateTime: DateTime.now(),
      thumbUrl: thumbMediaId,
      contentSourceUrl: contentSourceUrl,
      needOpenComment: needOpenComment ?? 0,
      onlyFansCanComment: onlyFansCanComment ?? 0,
    );

    _draftCache.add(draft);
    debugPrint('[WeChatPublish] Draft created: $draft');
    return draft;
  }

  /// Update an existing draft article.
  Future<WeChatDraft> updateDraft(
    String mediaId, {
    String? title,
    String? content,
    String? author,
    String? digest,
  }) async {
    // Find existing draft to merge fields.
    final existing = _draftCache.firstWhere(
      (d) => d.mediaId == mediaId,
      orElse: () => WeChatDraft(
        mediaId: mediaId,
        title: title ?? '',
        content: content ?? '',
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      ),
    );

    final htmlContent = content != null ? _convertToWeChatHtml(content) : existing.content;

    final articleData = {
      'title': title ?? existing.title,
      'content': htmlContent,
      'author': author ?? existing.author,
      if (digest != null) 'digest': digest,
      if (digest == null && existing.digest != null) 'digest': existing.digest,
      if (existing.thumbUrl != null) 'thumb_media_id': existing.thumbUrl,
      if (existing.contentSourceUrl != null)
        'content_source_url': existing.contentSourceUrl,
      'need_open_comment': existing.needOpenComment,
      'only_fans_can_comment': existing.onlyFansCanComment,
      'show_cover_pic': 1,
    };

    await _apiPost(
      '/draft/update',
      data: {
        'media_id': mediaId,
        'index': 0,
        'articles': articleData,
      },
    );

    final updated = existing.copyWith(
      title: title,
      content: content,
      author: author,
      digest: digest,
      updateTime: DateTime.now(),
    );

    // Update cache.
    final idx = _draftCache.indexWhere((d) => d.mediaId == mediaId);
    if (idx >= 0) {
      _draftCache[idx] = updated;
    }

    debugPrint('[WeChatPublish] Draft updated: $mediaId');
    return updated;
  }

  /// Get list of drafts.
  Future<List<WeChatDraft>> getDrafts({int offset = 0, int count = 20}) async {
    // If we have cached drafts and offset is 0, return cache.
    if (offset == 0 && _draftCache.isNotEmpty) {
      return List.unmodifiable(_draftCache);
    }

    try {
      final response = await _apiPost(
        '/draft/batchget',
        data: {
          'offset': offset,
          'count': count,
          'no_content': 1,
        },
      );

      final items = response.data?['item'] as List<dynamic>?;
      if (items == null) return List.unmodifiable(_draftCache);

      final drafts = items.map((item) {
        final content = item['content'] as Map<String, dynamic>?;
        final newsItem = content?['news_item']?[0] as Map<String, dynamic>?;

        return WeChatDraft(
          mediaId: item['media_id']?.toString() ?? '',
          title: newsItem?['title'] ?? '',
          content: newsItem?['content'] ?? '',
          author: newsItem?['author'],
          digest: newsItem?['digest'],
          createTime: item['update_time'] != null
              ? DateTime.fromMillisecondsSinceEpoch(
                  (item['update_time'] as int) * 1000)
              : DateTime.now(),
          updateTime: item['update_time'] != null
              ? DateTime.fromMillisecondsSinceEpoch(
                  (item['update_time'] as int) * 1000)
              : DateTime.now(),
          thumbUrl: newsItem?['thumb_media_id'],
          needOpenComment: newsItem?['need_open_comment'] ?? 0,
          onlyFansCanComment: newsItem?['only_fans_can_comment'] ?? 0,
        );
      }).toList();

      if (offset == 0) {
        _draftCache.clear();
        _draftCache.addAll(drafts);
      }

      return List.unmodifiable(drafts);
    } catch (e) {
      debugPrint('[WeChatPublish] Failed to fetch drafts: $e');
      return List.unmodifiable(_draftCache);
    }
  }

  /// Delete a draft.
  Future<void> deleteDraft(String mediaId) async {
    await _apiPost(
      '/draft/delete',
      data: {'media_id': mediaId},
    );
    _draftCache.removeWhere((d) => d.mediaId == mediaId);
    debugPrint('[WeChatPublish] Draft deleted: $mediaId');
  }

  /// Count of cached drafts.
  int get draftCount => _draftCache.length;

  // ═══════════════════════════════════════════════════════════════════════
  // Media Upload
  // ═══════════════════════════════════════════════════════════════════════

  /// Upload an image for use in articles.
  ///
  /// Returns the media ID of the uploaded image.
  Future<String> uploadImage(String imagePath) async {
    final token = await _ensureToken();
    final file = File(imagePath);

    if (!await file.exists()) {
      throw WeChatAuthException(message: 'Image file not found: $imagePath');
    }

    final formData = FormData.fromMap({
      'media': await MultipartFile.fromFile(imagePath),
    });

    final response = await _dio.post<Map<String, dynamic>>(
      '/media/upload',
      queryParameters: {
        'access_token': token,
        'type': 'image',
      },
      data: formData,
    );

    final mediaId = response.data?['media_id'] as String?;
    if (mediaId == null || mediaId.isEmpty) {
      throw WeChatApiException(
        errcode: response.data?['errcode'] ?? -1,
        errmsg: response.data?['errmsg'] ?? 'Upload failed',
        operation: 'uploadImage',
      );
    }

    debugPrint('[WeChatPublish] Image uploaded: $mediaId');
    return mediaId;
  }

  /// Upload a thumbnail image for article cover.
  ///
  /// Returns the media ID of the uploaded thumbnail.
  Future<String> uploadThumbnail(String imagePath) async {
    return uploadImage(imagePath);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Publishing
  // ═══════════════════════════════════════════════════════════════════════

  /// Publish an article (send to all subscribers).
  ///
  /// The article must first be created as a draft.
  /// Returns the publish result with publish ID.
  Future<WeChatPublishResult> publish(String mediaId) async {
    final response = await _apiPost(
      '/freepublish/submit',
      data: {'media_id': mediaId},
    );

    final publishId = response.data?['publish_id']?.toString();
    if (publishId != null) {
      debugPrint('[WeChatPublish] Article published: $publishId');
      return WeChatPublishResult.success(
        publishId: publishId,
        mediaId: mediaId,
      );
    }

    return WeChatPublishResult.failure(
      response.data?['errmsg'] ?? 'Unknown publish error',
    );
  }

  /// Preview a draft by sending it to a specific WeChat user.
  ///
  /// [mediaId] The draft media ID.
  /// [toWxUserOpenId] The OpenID of the WeChat user to receive the preview.
  Future<void> preview(String mediaId, String toWxUserOpenId) async {
    await _apiPost(
      '/draft/preview',
      data: {
        'media_id': mediaId,
        'touser': toWxUserOpenId,
      },
    );
    debugPrint('[WeChatPublish] Preview sent to $toWxUserOpenId');
  }

  /// Get the publish status of an article.
  Future<PublishStatus> getPublishStatus(String publishId) async {
    final response = await _apiPost(
      '/freepublish/get',
      data: {'publish_id': publishId},
    );

    final status = response.data?['publish_status'] as int?;
    switch (status) {
      case 0:
        return PublishStatus.publishing;
      case 1:
        return PublishStatus.published;
      case 2:
        return PublishStatus.failed;
      default:
        return PublishStatus.unknown;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // History
  // ═══════════════════════════════════════════════════════════════════════

  /// Get published articles.
  Future<List<WeChatArticle>> getPublishedArticles({
    int offset = 0,
    int count = 20,
  }) async {
    try {
      final response = await _apiPost(
        '/freepublish/batchget',
        data: {
          'offset': offset,
          'count': count,
          'no_content': 1,
        },
      );

      final items = response.data?['item'] as List<dynamic>?;
      if (items == null) return const [];

      final articles = items.map((item) {
        final content = item['content'] as Map<String, dynamic>?;
        final newsItem = content?['news_item']?[0] as Map<String, dynamic>?;

        return WeChatArticle(
          msgId: item['msg_data_id']?.toString() ?? '',
          title: newsItem?['title'] ?? '',
          url: newsItem?['url'],
          publishTime: item['update_time'] != null
              ? DateTime.fromMillisecondsSinceEpoch(
                  (item['update_time'] as int) * 1000)
              : DateTime.now(),
        );
      }).toList();

      if (offset == 0) {
        _articleCache.clear();
        _articleCache.addAll(articles);
      }

      return List.unmodifiable(articles);
    } catch (e) {
      debugPrint('[WeChatPublish] Failed to fetch published articles: $e');
      return List.unmodifiable(_articleCache);
    }
  }

  /// Delete a published article.
  Future<void> deletePublishedArticle(String articleId) async {
    await _apiPost(
      '/freepublish/delete',
      data: {'article_id': articleId, 'index': 0},
    );
    _articleCache.removeWhere((a) => a.msgId == articleId);
    debugPrint('[WeChatPublish] Published article deleted: $articleId');
  }

  /// Count of cached published articles.
  int get publishedCount => _articleCache.length;

  // ═══════════════════════════════════════════════════════════════════════
  // Statistics
  // ═══════════════════════════════════════════════════════════════════════

  /// Get article read statistics.
  ///
  /// [msgId] The message data ID of the published article.
  Future<ArticleStats> getArticleStats(String msgId) async {
    try {
      final response = await _apiPost(
        '/datacube/getarticletotal',
        data: {
          'msg_data_id': msgId,
          'begin_date': _formatDate(DateTime.now().subtract(const Duration(days: 7))),
          'end_date': _formatDate(DateTime.now()),
        },
      );

      final list = response.data?['list'] as List<dynamic>?;
      if (list == null || list.isEmpty) return const ArticleStats();

      final details = list[0]['details'] as List<dynamic>?;
      if (details == null || details.isEmpty) return const ArticleStats();

      // Aggregate stats across all dates.
      var stats = const ArticleStats();
      for (final detail in details) {
        final itemStats = ArticleStats.fromJson(detail as Map<String, dynamic>);
        stats = ArticleStats(
          readCount: stats.readCount + itemStats.readCount,
          likeCount: stats.likeCount + itemStats.likeCount,
          shareCount: stats.shareCount + itemStats.shareCount,
          commentCount: stats.commentCount + itemStats.commentCount,
          forwardCount: stats.forwardCount + itemStats.forwardCount,
        );
      }

      // Update cache with stats.
      final idx = _articleCache.indexWhere((a) => a.msgId == msgId);
      if (idx >= 0) {
        _articleCache[idx] = WeChatArticle(
          msgId: _articleCache[idx].msgId,
          title: _articleCache[idx].title,
          url: _articleCache[idx].url,
          publishTime: _articleCache[idx].publishTime,
          readCount: stats.readCount,
          likeCount: stats.likeCount,
        );
      }

      return stats;
    } catch (e) {
      debugPrint('[WeChatPublish] Failed to get article stats: $e');
      return const ArticleStats();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════════════

  /// Convert Markdown or plain text to WeChat-compatible HTML.
  ///
  /// WeChat requires specific HTML tags. This method:
  /// 1. Wraps content in proper HTML structure
  /// 2. Ensures images use WeChat-compatible tags
  /// 3. Validates and sanitizes the HTML
  String _convertToWeChatHtml(String content) {
    // If content already looks like HTML, use it directly.
    if (content.trim().startsWith('<')) {
      return _sanitizeWeChatHtml(content);
    }

    // Otherwise, wrap in basic HTML structure.
    // Note: Full Markdown→HTML conversion would use a markdown parser.
    final escaped = content
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');

    return '<p>${escaped.replaceAll('\n', '</p><p>')}</p>';
  }

  /// Sanitize HTML for WeChat compatibility.
  String _sanitizeWeChatHtml(String html) {
    // WeChat supports a limited set of HTML tags.
    // Allow: p, br, img, a, strong, em, span, section
    // Block: script, style, iframe, form, input, etc.
    final blockedTags = RegExp(
      r'<(script|style|iframe|form|input|textarea|select|button|object|embed)[^>]*>[\s\S]*?</\1>',
      caseSensitive: false,
    );

    var sanitized = html.replaceAll(blockedTags, '');

    // Ensure images have proper attributes.
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'<img[^>]*>', caseSensitive: false),
      (match) {
        final tag = match[0]!;
        if (!tag.contains('data-src=') && tag.contains('src=')) {
          return tag.replaceFirst('src=', 'data-src=');
        }
        return tag;
      },
    );

    return sanitized;
  }

  /// Format date for WeChat API (YYYY-MM-DD).
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Dispose the service and clear resources.
  void dispose() {
    _accessToken = null;
    _tokenExpiry = null;
    _currentAppId = null;
    _draftCache.clear();
    _articleCache.clear();
    _dio.close();
    debugPrint('[WeChatPublish] Service disposed');
  }
}
