import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Output formats understood by the HTML renderer contract.
enum HtmlRenderFormat {
  png,
  pdf,
  mp4,
  pptx,
}

extension HtmlRenderFormatX on HtmlRenderFormat {
  String get id => name;

  String get mimeType => switch (this) {
        HtmlRenderFormat.png => 'image/png',
        HtmlRenderFormat.pdf => 'application/pdf',
        HtmlRenderFormat.mp4 => 'video/mp4',
        HtmlRenderFormat.pptx =>
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      };

  String get extension => switch (this) {
        HtmlRenderFormat.png => 'png',
        HtmlRenderFormat.pdf => 'pdf',
        HtmlRenderFormat.mp4 => 'mp4',
        HtmlRenderFormat.pptx => 'pptx',
      };
}

enum HtmlPptxMode {
  visual,
  editableText,
}

/// A deterministic request to render one HTML preview artifact.
class HtmlRenderRequest {
  const HtmlRenderRequest({
    required this.sourceUrl,
    required this.viewportWidth,
    required this.viewportHeight,
    this.deviceScaleFactor = 1.0,
    this.format = HtmlRenderFormat.png,
    this.timeout = const Duration(seconds: 15),
    this.suggestedName,
    this.inlineHtml,
    this.sourcePath,
    this.slideCount,
    this.slideAspectRatio = '16:9',
    this.pptxMode = HtmlPptxMode.visual,
  });

  final String sourceUrl;
  final int viewportWidth;
  final int viewportHeight;
  final double deviceScaleFactor;
  final HtmlRenderFormat format;
  final Duration timeout;
  final String? suggestedName;
  final String? inlineHtml;
  final String? sourcePath;
  final int? slideCount;
  final String slideAspectRatio;
  final HtmlPptxMode pptxMode;

  Map<String, Object?> toPlatformArguments() => {
        'url': sourceUrl,
        'width': viewportWidth,
        'height': viewportHeight,
        'deviceScaleFactor': deviceScaleFactor,
        'format': format.id,
        'timeoutMs': timeout.inMilliseconds,
        'suggestedName': suggestedName,
        if (inlineHtml != null) 'inlineHtml': inlineHtml,
        if (sourcePath != null) 'sourcePath': sourcePath,
        if (slideCount != null) 'slideCount': slideCount,
        'slideAspectRatio': slideAspectRatio,
        'pptxMode': pptxMode.name,
      };
}

/// A materialized renderer output. The path may initially point at a native
/// temporary file and can then be copied into the workspace artifact store.
class HtmlRenderArtifact {
  HtmlRenderArtifact({
    required this.path,
    required this.format,
    required this.mimeType,
    required this.bytes,
    required this.sha256,
    required this.width,
    required this.height,
    required this.backend,
    DateTime? createdAt,
    this.metadata = const {},
  }) : createdAt = createdAt ?? DateTime.now();

  final String path;
  final HtmlRenderFormat format;
  final String mimeType;
  final int bytes;
  final String sha256;
  final int width;
  final int height;
  final String backend;
  final DateTime createdAt;
  final Map<String, dynamic> metadata;

  HtmlRenderArtifact copyWith({
    String? path,
    int? bytes,
    String? sha256,
    Map<String, dynamic>? metadata,
  }) {
    return HtmlRenderArtifact(
      path: path ?? this.path,
      format: format,
      mimeType: mimeType,
      bytes: bytes ?? this.bytes,
      sha256: sha256 ?? this.sha256,
      width: width,
      height: height,
      backend: backend,
      createdAt: createdAt,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'format': format.id,
        'mimeType': mimeType,
        'bytes': bytes,
        'sha256': sha256,
        'width': width,
        'height': height,
        'backend': backend,
        'createdAt': createdAt.toIso8601String(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  static Future<HtmlRenderArtifact> fromPlatform(
    Map<String, dynamic> raw,
    HtmlRenderRequest request,
  ) async {
    final path = raw['path']?.toString() ?? '';
    if (path.isEmpty) {
      throw const FormatException('HTML renderer returned no artifact path.');
    }
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('HTML renderer artifact does not exist: $path');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('HTML renderer returned an empty artifact: $path');
    }
    return HtmlRenderArtifact(
      path: path,
      format: request.format,
      mimeType: raw['mimeType']?.toString() ?? request.format.mimeType,
      bytes: bytes.length,
      sha256: crypto.sha256.convert(bytes).toString(),
      width: (raw['width'] as num?)?.toInt() ?? request.viewportWidth,
      height: (raw['height'] as num?)?.toInt() ?? request.viewportHeight,
      backend: raw['backend']?.toString() ?? 'platform_webview',
      metadata: raw['metadata'] is Map
          ? Map<String, dynamic>.from(raw['metadata'] as Map)
          : const {},
    );
  }

  static Future<HtmlRenderArtifact> fromWorkerPayload(
    Map<String, dynamic> raw,
    HtmlRenderRequest request,
  ) async {
    final encoded = raw['artifactBase64']?.toString();
    if (encoded != null && encoded.isNotEmpty) {
      return fromBytes(
        base64Decode(encoded),
        request,
        backend: raw['backend']?.toString() ?? 'html_render_worker',
        metadata: raw['metadata'] is Map
            ? Map<String, dynamic>.from(raw['metadata'] as Map)
            : const {},
      );
    }
    return fromPlatform(raw, request);
  }

  static Future<HtmlRenderArtifact> fromBytes(
    List<int> rawBytes,
    HtmlRenderRequest request, {
    required String backend,
    Map<String, dynamic> metadata = const {},
  }) async {
    final bytes = Uint8List.fromList(rawBytes);
    if (bytes.isEmpty) {
      throw StateError('HTML renderer returned an empty artifact.');
    }
    final directory = Directory(
      p.join(Directory.systemTemp.path, 'mobilecode-html-render'),
    );
    await directory.create(recursive: true);
    final file = File(
      p.join(
        directory.path,
        'worker_${DateTime.now().microsecondsSinceEpoch}.${request.format.extension}',
      ),
    );
    await file.writeAsBytes(bytes, flush: true);
    return HtmlRenderArtifact(
      path: file.path,
      format: request.format,
      mimeType: request.format.mimeType,
      bytes: bytes.length,
      sha256: crypto.sha256.convert(bytes).toString(),
      width: request.viewportWidth,
      height: request.viewportHeight,
      backend: backend,
      metadata: metadata,
    );
  }
}

/// A platform renderer. Providers are intentionally replaceable so the same
/// evidence contract can later use a Helper, HyperFrames, or a remote worker.
abstract interface class HtmlRenderProvider {
  Future<HtmlRenderArtifact> render(HtmlRenderRequest request);
}

/// Android/iOS native WebView renderer for local PNG/PDF output.
class PlatformHtmlRenderProvider implements HtmlRenderProvider {
  const PlatformHtmlRenderProvider({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'mobilecode/html_renderer';
  final MethodChannel _channel;

  @override
  Future<HtmlRenderArtifact> render(HtmlRenderRequest request) async {
    if (request.format != HtmlRenderFormat.png &&
        request.format != HtmlRenderFormat.pdf) {
      throw UnsupportedError(
        'PlatformHtmlRenderProvider renders PNG/PDF only; use a worker for '
        '${request.format.id}.',
      );
    }
    if (request.sourceUrl.trim().isEmpty) {
      throw ArgumentError.value(request.sourceUrl, 'sourceUrl');
    }
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      request.format == HtmlRenderFormat.pdf ? 'renderPdf' : 'renderPng',
      request.toPlatformArguments(),
    );
    if (raw == null) {
      throw StateError('Native HTML renderer returned no result.');
    }
    return HtmlRenderArtifact.fromPlatform(
      Map<String, dynamic>.from(raw),
      request,
    );
  }
}

/// Generic HTTP adapter for a Helper/remote HTML artifact worker.
class HtmlWorkerRenderProvider implements HtmlRenderProvider {
  HtmlWorkerRenderProvider({
    required this.endpoint,
    required this.engine,
    required this.outputFormat,
    this.authToken,
    this.timeout = const Duration(minutes: 5),
  });

  static final HttpClient _client = HttpClient();
  final Uri endpoint;
  final String engine;
  final HtmlRenderFormat outputFormat;
  final String? authToken;
  final Duration timeout;

  @override
  Future<HtmlRenderArtifact> render(HtmlRenderRequest request) async {
    if (request.format != outputFormat) {
      throw UnsupportedError(
        '$engine worker renders ${outputFormat.id}; received ${request.format.id}.',
      );
    }
    final httpRequest = await _client.postUrl(endpoint).timeout(timeout);
    httpRequest.headers.contentType = ContentType.json;
    if (authToken != null && authToken!.isNotEmpty) {
      httpRequest.headers
          .set(HttpHeaders.authorizationHeader, 'Bearer $authToken');
    }
    httpRequest.add(
      utf8.encode(
        jsonEncode({
          'protocolVersion': 'mobilecode.html-render.v1',
          'engine': engine,
          'request': request.toPlatformArguments(),
        }),
      ),
    );
    final response = await httpRequest.close().timeout(timeout);
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'HTML render worker returned HTTP ${response.statusCode}: $body',
        uri: endpoint,
      );
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException(
          'HTML render worker returned a non-object response.');
    }
    final payload = Map<String, dynamic>.from(decoded);
    if (payload['success'] == false) {
      throw StateError(
          payload['error']?.toString() ?? 'HTML render worker failed.');
    }
    final artifactUrl = payload['artifactUrl']?.toString();
    if (artifactUrl != null && artifactUrl.isNotEmpty) {
      final downloadUrl = Uri.tryParse(artifactUrl);
      if (downloadUrl == null) {
        throw const FormatException(
            'HTML render worker returned an invalid artifact URL.');
      }
      final downloadRequest =
          await _client.getUrl(downloadUrl).timeout(timeout);
      if (authToken != null && authToken!.isNotEmpty) {
        downloadRequest.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $authToken',
        );
      }
      final downloadResponse = await downloadRequest.close().timeout(timeout);
      if (downloadResponse.statusCode < 200 ||
          downloadResponse.statusCode >= 300) {
        throw HttpException(
          'HTML render artifact download returned HTTP ${downloadResponse.statusCode}.',
          uri: downloadUrl,
        );
      }
      final bytes = await _readBytes(downloadResponse);
      return HtmlRenderArtifact.fromBytes(
        bytes,
        request,
        backend: payload['backend']?.toString() ?? '${engine}_worker',
        metadata: payload['metadata'] is Map
            ? Map<String, dynamic>.from(payload['metadata'] as Map)
            : const {},
      );
    }
    return HtmlRenderArtifact.fromWorkerPayload(payload, request);
  }

  Future<List<int>> _readBytes(HttpClientResponse response) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}

/// HyperFrames adapter for external MP4 rendering.
class HyperFramesHtmlRenderProvider extends HtmlWorkerRenderProvider {
  HyperFramesHtmlRenderProvider({
    Uri? endpoint,
    String? authToken,
    Duration timeout = const Duration(minutes: 5),
  }) : super(
          endpoint:
              endpoint ?? Uri.parse('http://127.0.0.1:8790/v1/render/html'),
          engine: 'hyperframes',
          outputFormat: HtmlRenderFormat.mp4,
          authToken: authToken,
          timeout: timeout,
        );
}

/// HTML-to-PPTX adapter. The default worker uses screenshot-backed slides for
/// pixel fidelity; editable text is an explicit second mode in the contract.
class HtmlPptxRenderProvider extends HtmlWorkerRenderProvider {
  HtmlPptxRenderProvider({
    Uri? endpoint,
    String? authToken,
    Duration timeout = const Duration(minutes: 5),
  }) : super(
          endpoint:
              endpoint ?? Uri.parse('http://127.0.0.1:8790/v1/render/pptx'),
          engine: 'html_pptx',
          outputFormat: HtmlRenderFormat.pptx,
          authToken: authToken,
          timeout: timeout,
        );
}

/// Copies renderer outputs into an app-owned artifact directory.
class HtmlArtifactStore {
  const HtmlArtifactStore();

  Future<HtmlRenderArtifact> materialize(
    HtmlRenderArtifact artifact, {
    required Directory directory,
    String? fileName,
  }) async {
    await directory.create(recursive: true);
    final safeName = _safeFileName(
      fileName ??
          'html-render-${DateTime.now().millisecondsSinceEpoch}.${artifact.format.extension}',
      artifact.format.extension,
    );
    final destination = File(p.join(directory.path, safeName));
    await File(artifact.path).copy(destination.path);
    final bytes = await destination.readAsBytes();
    return artifact.copyWith(
      path: destination.path,
      bytes: bytes.length,
      sha256: crypto.sha256.convert(bytes).toString(),
    );
  }

  String _safeFileName(String value, String extension) {
    final basename =
        p.basename(value).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (basename.toLowerCase().endsWith('.$extension')) return basename;
    return '$basename.$extension';
  }
}
