import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

enum ExternalPreviewKind {
  html,
  markdown,
  text,
  unsupported,
}

class ExternalPreviewFile {
  const ExternalPreviewFile({
    required this.path,
    required this.displayName,
    required this.mimeType,
    required this.sizeBytes,
    required this.source,
    required this.kind,
  });

  final String path;
  final String displayName;
  final String mimeType;
  final int sizeBytes;
  final String source;
  final ExternalPreviewKind kind;

  bool get isTextReadable => kind != ExternalPreviewKind.unsupported;

  String get kindLabel {
    switch (kind) {
      case ExternalPreviewKind.html:
        return 'HTML Preview';
      case ExternalPreviewKind.markdown:
        return 'Markdown Preview';
      case ExternalPreviewKind.text:
        return 'Text Preview';
      case ExternalPreviewKind.unsupported:
        return 'Unsupported';
    }
  }

  String get shortSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    final kb = sizeBytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  }

  Future<String> readText({int maxBytes = 1024 * 1024}) async {
    final bytes = await File(path).openRead(0, maxBytes).fold<BytesBuilder>(
      BytesBuilder(copy: false),
      (builder, chunk) {
        builder.add(chunk);
        return builder;
      },
    );
    return utf8.decode(bytes.takeBytes(), allowMalformed: true);
  }
}

class ExternalFilePreviewService {
  ExternalFilePreviewService._();

  static final ExternalFilePreviewService instance = ExternalFilePreviewService._();
  static const MethodChannel _channel = MethodChannel('mobilecode/system_tools');

  Future<ExternalPreviewFile?> consumePendingFile() async {
    final raw = await _channel.invokeMethod<dynamic>('consumePendingSharedFile');
    if (raw == null) return null;
    if (raw is! Map) return null;

    final path = _stringValue(raw['path']);
    if (path == null || path.trim().isEmpty) return null;
    final file = File(path);
    final exists = await file.exists();
    if (!exists) return null;

    final displayName = _stringValue(raw['displayName']) ?? p.basename(path);
    final mimeType = _stringValue(raw['mimeType']) ?? '';
    final source = _stringValue(raw['source']) ?? 'external_app';
    final sizeBytes = _intValue(raw['sizeBytes']) ?? await file.length();
    final sample = await _readSample(file);
    final kind = ExternalFilePreviewClassifier.classify(
      displayName: displayName,
      mimeType: mimeType,
      sample: sample,
    );

    return ExternalPreviewFile(
      path: path,
      displayName: displayName,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      source: source,
      kind: kind,
    );
  }

  static Future<Uint8List> _readSample(File file) async {
    final length = await file.length();
    final end = length < 8192 ? length : 8192;
    if (end <= 0) return Uint8List(0);
    return file.openRead(0, end).fold<BytesBuilder>(
      BytesBuilder(copy: false),
      (builder, chunk) {
        builder.add(chunk);
        return builder;
      },
    ).then((builder) => builder.takeBytes());
  }

  static String? _stringValue(Object? value) {
    if (value == null) return null;
    return value.toString();
  }

  static int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

class ExternalFilePreviewClassifier {
  ExternalFilePreviewClassifier._();

  static ExternalPreviewKind classify({
    required String displayName,
    required String mimeType,
    required Uint8List sample,
  }) {
    final lowerName = displayName.toLowerCase();
    final lowerMime = mimeType.toLowerCase();
    final extension = p.extension(lowerName);

    if (_isHtmlExtension(extension) || _isHtmlMime(lowerMime)) {
      return ExternalPreviewKind.html;
    }
    if (_isMarkdownExtension(extension) || _isMarkdownMime(lowerMime)) {
      return ExternalPreviewKind.markdown;
    }
    if (_looksBinary(sample)) {
      return ExternalPreviewKind.unsupported;
    }

    final text = utf8.decode(sample, allowMalformed: true).trimLeft();
    final lowerText = text.toLowerCase();
    if (lowerText.startsWith('<!doctype html') ||
        lowerText.startsWith('<html') ||
        lowerText.contains('<body')) {
      return ExternalPreviewKind.html;
    }
    if (_looksMarkdown(text)) {
      return ExternalPreviewKind.markdown;
    }
    if (_isTextExtension(extension) || lowerMime.startsWith('text/')) {
      return ExternalPreviewKind.text;
    }
    if (text.isNotEmpty && !_hasReplacementHeavyText(text)) {
      return ExternalPreviewKind.text;
    }
    return ExternalPreviewKind.unsupported;
  }

  static bool _isHtmlExtension(String extension) {
    return const {'.html', '.htm', '.xhtml'}.contains(extension);
  }

  static bool _isHtmlMime(String mimeType) {
    return const {'text/html', 'application/xhtml+xml'}.contains(mimeType);
  }

  static bool _isMarkdownExtension(String extension) {
    return const {'.md', '.markdown', '.mdown', '.mkd'}.contains(extension);
  }

  static bool _isMarkdownMime(String mimeType) {
    return const {
      'text/markdown',
      'text/x-markdown',
      'application/markdown',
    }.contains(mimeType);
  }

  static bool _isTextExtension(String extension) {
    return const {
      '.txt',
      '.text',
      '.log',
      '.json',
      '.jsonl',
      '.xml',
      '.csv',
      '.tsv',
      '.yaml',
      '.yml',
      '.css',
      '.js',
      '.mjs',
      '.ts',
      '.tsx',
      '.jsx',
      '.dart',
      '.java',
      '.kt',
      '.kts',
      '.py',
      '.rb',
      '.go',
      '.rs',
      '.c',
      '.cpp',
      '.h',
      '.hpp',
      '.sh',
      '.sql',
    }.contains(extension);
  }

  static bool _looksBinary(Uint8List sample) {
    if (sample.isEmpty) return false;
    var controlCount = 0;
    for (final byte in sample) {
      if (byte == 0) return true;
      final allowedControl = byte == 9 || byte == 10 || byte == 13;
      if (byte < 32 && !allowedControl) controlCount++;
    }
    return controlCount / sample.length > 0.08;
  }

  static bool _looksMarkdown(String text) {
    if (text.isEmpty) return false;
    final lines = text.split('\n').take(20).map((line) => line.trimRight()).toList();
    final joined = lines.join('\n');
    if (RegExp(r'^#{1,6}\s+\S', multiLine: true).hasMatch(joined)) return true;
    if (RegExp(r'^[-*+]\s+\S', multiLine: true).hasMatch(joined)) return true;
    if (RegExp(r'^```', multiLine: true).hasMatch(joined)) return true;
    if (RegExp(r'\[[^\]]+\]\([^)]+\)').hasMatch(joined)) return true;
    return false;
  }

  static bool _hasReplacementHeavyText(String text) {
    if (text.isEmpty) return false;
    final replacements = '�'.allMatches(text).length;
    return replacements / text.length > 0.05;
  }
}
