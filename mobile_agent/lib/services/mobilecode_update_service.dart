import 'dart:convert';

import 'package:dio/dio.dart';

class MobileCodeUpdateService {
  MobileCodeUpdateService({Dio? dio}) : _dio = dio ?? Dio();

  static const String pagesUrl = 'https://harzva.github.io/mobilecode/';
  static const String defaultFeedUrl =
      'https://harzva.github.io/mobilecode/mobilecode-update.json';
  static const String githubRepoUrl = 'https://github.com/Harzva/mobilecode';
  static const String currentVersion = '0.1.68-mobile-harness-d2dd9a7';
  static const int currentBuildNumber = 58;

  final Dio _dio;

  Future<MobileCodeUpdateFeed> fetch({
    String feedUrl = defaultFeedUrl,
  }) async {
    final response = await _dio.getUri<Object>(
      Uri.parse(feedUrl),
      options: Options(
        responseType: ResponseType.plain,
        receiveTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 8),
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    final statusCode = response.statusCode ?? 0;
    if (statusCode < 200 || statusCode >= 300) {
      throw MobileCodeUpdateException(
        'Update feed returned HTTP $statusCode.',
      );
    }

    final body = response.data;
    final Object? decoded = body is String ? jsonDecode(body) : body;
    if (decoded is! Map<String, dynamic>) {
      throw const MobileCodeUpdateException(
        'Update feed is not a JSON object.',
      );
    }
    return MobileCodeUpdateFeed.fromJson(decoded, sourceUrl: feedUrl);
  }

  void dispose() {
    _dio.close();
  }
}

class MobileCodeUpdateException implements Exception {
  const MobileCodeUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MobileCodeUpdateFeed {
  const MobileCodeUpdateFeed({
    required this.schemaVersion,
    required this.channel,
    required this.title,
    required this.message,
    required this.latestVersion,
    required this.latestBuildNumber,
    required this.minimumSupportedBuildNumber,
    required this.severity,
    required this.publishedAt,
    required this.pagesUrl,
    required this.releaseUrl,
    required this.downloadUrl,
    required this.githubUrl,
    required this.ctaLabel,
    required this.secondaryCtaLabel,
    required this.releaseNotes,
    required this.sourceUrl,
  });

  final int schemaVersion;
  final String channel;
  final String title;
  final String message;
  final String latestVersion;
  final int latestBuildNumber;
  final int minimumSupportedBuildNumber;
  final String severity;
  final DateTime? publishedAt;
  final String pagesUrl;
  final String releaseUrl;
  final String downloadUrl;
  final String githubUrl;
  final String ctaLabel;
  final String secondaryCtaLabel;
  final List<String> releaseNotes;
  final String sourceUrl;

  bool get hasPagesUrl => pagesUrl.trim().isNotEmpty;
  bool get hasDownloadUrl => downloadUrl.trim().isNotEmpty;
  bool get hasReleaseUrl => releaseUrl.trim().isNotEmpty;

  bool isNewerThan({
    required String currentVersion,
    required int currentBuildNumber,
  }) {
    if (latestBuildNumber > currentBuildNumber) return true;
    if (latestBuildNumber < currentBuildNumber) return false;
    return _compareLooseVersion(latestVersion, currentVersion) > 0;
  }

  bool requiresUpgrade({required int currentBuildNumber}) {
    return minimumSupportedBuildNumber > currentBuildNumber;
  }

  String get primaryUrl {
    if (pagesUrl.trim().isNotEmpty) return pagesUrl.trim();
    if (downloadUrl.trim().isNotEmpty) return downloadUrl.trim();
    if (releaseUrl.trim().isNotEmpty) return releaseUrl.trim();
    return githubUrl.trim();
  }

  String get secondaryUrl {
    if (downloadUrl.trim().isNotEmpty) return downloadUrl.trim();
    if (releaseUrl.trim().isNotEmpty) return releaseUrl.trim();
    if (githubUrl.trim().isNotEmpty) return githubUrl.trim();
    return pagesUrl.trim();
  }

  factory MobileCodeUpdateFeed.fromJson(
    Map<String, dynamic> json, {
    String sourceUrl = '',
  }) {
    final releaseUrl = _stringValue(json['releaseUrl']);
    final downloadUrl = _stringValue(json['downloadUrl']);
    final pagesUrl = _stringValue(json['pagesUrl']);
    return MobileCodeUpdateFeed(
      schemaVersion: _intValue(json['schemaVersion'], fallback: 1),
      channel: _stringValue(json['channel'], fallback: 'stable'),
      title: _stringValue(json['title'], fallback: 'MobileCode update'),
      message: _stringValue(json['message']),
      latestVersion: _stringValue(
        json['latestVersion'],
        fallback: MobileCodeUpdateService.currentVersion,
      ),
      latestBuildNumber: _intValue(
        json['latestBuildNumber'],
        fallback: MobileCodeUpdateService.currentBuildNumber,
      ),
      minimumSupportedBuildNumber: _intValue(
        json['minimumSupportedBuildNumber'],
        fallback: 0,
      ),
      severity: _stringValue(json['severity'], fallback: 'info'),
      publishedAt: DateTime.tryParse(_stringValue(json['publishedAt'])),
      pagesUrl: pagesUrl.isEmpty ? MobileCodeUpdateService.pagesUrl : pagesUrl,
      releaseUrl: releaseUrl,
      downloadUrl: downloadUrl.isEmpty ? releaseUrl : downloadUrl,
      githubUrl: _stringValue(
        json['githubUrl'],
        fallback: MobileCodeUpdateService.githubRepoUrl,
      ),
      ctaLabel: _stringValue(json['ctaLabel'], fallback: 'Open Pages'),
      secondaryCtaLabel: _stringValue(
        json['secondaryCtaLabel'],
        fallback: 'Download',
      ),
      releaseNotes: _stringList(json['releaseNotes']),
      sourceUrl: sourceUrl,
    );
  }
}

int _compareLooseVersion(String left, String right) {
  final leftParts = _versionParts(left);
  final rightParts = _versionParts(right);
  final length = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (var index = 0; index < length; index++) {
    final a = index < leftParts.length ? leftParts[index] : 0;
    final b = index < rightParts.length ? rightParts[index] : 0;
    if (a != b) return a.compareTo(b);
  }
  return 0;
}

List<int> _versionParts(String version) {
  final semanticCore = version
      .trim()
      .replaceFirst(RegExp(r'^[vV]'), '')
      .split('+')
      .first
      .split('-')
      .first;
  return semanticCore
      .split('.')
      .map((part) => RegExp(r'^\d+').firstMatch(part)?.group(0) ?? '0')
      .map((part) => int.tryParse(part) ?? 0)
      .toList(growable: false);
}

String _stringValue(Object? value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

int _intValue(Object? value, {required int fallback}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
