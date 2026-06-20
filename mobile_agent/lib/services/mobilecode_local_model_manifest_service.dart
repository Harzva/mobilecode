import 'dart:convert';

import 'package:dio/dio.dart';

class MobileCodeLocalModelManifestService {
  MobileCodeLocalModelManifestService({Dio? dio}) : _dio = dio ?? Dio();

  static const String defaultManifestUrl =
      'https://harzva.github.io/mobilecode/mobilecode-local-models.json';

  final Dio _dio;

  Future<MobileCodeLocalModelManifest> fetch({
    String manifestUrl = defaultManifestUrl,
  }) async {
    final response = await _dio.getUri<Object>(
      Uri.parse(manifestUrl),
      options: Options(
        responseType: ResponseType.plain,
        receiveTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 8),
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    final statusCode = response.statusCode ?? 0;
    if (statusCode < 200 || statusCode >= 300) {
      throw MobileCodeLocalModelManifestException(
        'Local model manifest returned HTTP $statusCode.',
      );
    }

    final body = response.data;
    final Object? decoded = body is String ? jsonDecode(body) : body;
    if (decoded is! Map<String, dynamic>) {
      throw const MobileCodeLocalModelManifestException(
        'Local model manifest is not a JSON object.',
      );
    }
    return MobileCodeLocalModelManifest.fromJson(
      decoded,
      sourceUrl: manifestUrl,
    );
  }

  void dispose() {
    _dio.close();
  }
}

class MobileCodeLocalModelManifestException implements Exception {
  const MobileCodeLocalModelManifestException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MobileCodeLocalModelManifest {
  const MobileCodeLocalModelManifest({
    required this.schemaVersion,
    required this.updatedAt,
    required this.docsUrl,
    required this.sourceUrl,
    required this.models,
  });

  final int schemaVersion;
  final DateTime? updatedAt;
  final String docsUrl;
  final String sourceUrl;
  final List<MobileCodeLocalModelEntry> models;

  int get readyModelCount =>
      models.where((model) => model.canDirectDownload).length;

  bool get hasModels => models.isNotEmpty;

  MobileCodeLocalModelEntry? get primaryModel =>
      models.isEmpty ? null : models.first;

  factory MobileCodeLocalModelManifest.fromJson(
    Map<String, dynamic> json, {
    String sourceUrl = '',
  }) =>
      MobileCodeLocalModelManifest(
        schemaVersion: _intValue(json['schemaVersion'], fallback: 1),
        updatedAt: DateTime.tryParse(_stringValue(json['updatedAt'])),
        docsUrl: _stringValue(json['docsUrl']),
        sourceUrl: sourceUrl,
        models: _modelList(json['models']),
      );
}

class MobileCodeLocalModelEntry {
  const MobileCodeLocalModelEntry({
    required this.id,
    required this.displayName,
    required this.status,
    required this.runtime,
    required this.platforms,
    required this.format,
    required this.downloadPageUrl,
    required this.modelUrl,
    required this.tokenizerUrl,
    required this.modelSha256,
    required this.tokenizerSha256,
    required this.approxBytes,
    required this.minRamMb,
    required this.license,
    required this.notes,
  });

  final String id;
  final String displayName;
  final String status;
  final String runtime;
  final List<String> platforms;
  final String format;
  final String downloadPageUrl;
  final String modelUrl;
  final String tokenizerUrl;
  final String modelSha256;
  final String tokenizerSha256;
  final int approxBytes;
  final int minRamMb;
  final String license;
  final List<String> notes;

  bool get isReady => status.toLowerCase() == 'ready';

  bool get hasVerifiedArtifacts =>
      _isHttpsUrl(modelUrl) &&
      _isHttpsUrl(tokenizerUrl) &&
      _isSha256(modelSha256) &&
      _isSha256(tokenizerSha256);

  bool get canDirectDownload => isReady && hasVerifiedArtifacts;

  String get primaryDownloadUrl {
    if (canDirectDownload) return modelUrl.trim();
    if (downloadPageUrl.trim().isNotEmpty) return downloadPageUrl.trim();
    if (modelUrl.trim().isNotEmpty) return modelUrl.trim();
    return '';
  }

  String get sizeLabel {
    if (approxBytes <= 0) return 'Size TBD';
    const gib = 1024 * 1024 * 1024;
    const mib = 1024 * 1024;
    if (approxBytes >= gib) {
      return '${(approxBytes / gib).toStringAsFixed(1)} GB';
    }
    return '${(approxBytes / mib).toStringAsFixed(0)} MB';
  }

  factory MobileCodeLocalModelEntry.fromJson(Map<String, dynamic> json) =>
      MobileCodeLocalModelEntry(
        id: _stringValue(json['id']),
        displayName: _stringValue(json['displayName'], fallback: 'Local model'),
        status: _stringValue(json['status'], fallback: 'candidate'),
        runtime: _stringValue(json['runtime'], fallback: 'unknown'),
        platforms: _stringList(json['platforms']),
        format: _stringValue(json['format']),
        downloadPageUrl: _stringValue(json['downloadPageUrl']),
        modelUrl: _stringValue(json['modelUrl']),
        tokenizerUrl: _stringValue(json['tokenizerUrl']),
        modelSha256: _stringValue(json['modelSha256']),
        tokenizerSha256: _stringValue(json['tokenizerSha256']),
        approxBytes: _intValue(json['approxBytes'], fallback: 0),
        minRamMb: _intValue(json['minRamMb'], fallback: 0),
        license: _stringValue(json['license'], fallback: 'check upstream'),
        notes: _stringList(json['notes']),
      );
}

List<MobileCodeLocalModelEntry> _modelList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map<String, dynamic>>()
      .map(MobileCodeLocalModelEntry.fromJson)
      .where((model) => model.id.isNotEmpty)
      .toList(growable: false);
}

bool _isHttpsUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
}

bool _isSha256(String value) =>
    RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(value.trim());

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
