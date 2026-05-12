// lib/utils/image_utils.dart
// Image utilities for LLM processing: encode, resize, validate, convert

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// {@template image_utils}
/// Static utility functions for image processing in LLM workflows.
///
/// Handles Base64 encoding/decoding, image validation, dimension
/// extraction, size formatting, and preprocessing for LLM API
/// consumption.
/// {@endtemplate}
class ImageUtils {
  ImageUtils._();

  // ── Constants ─────────────────────────────────────────────────────

  static const int maxBase64Length = 7 * 1024 * 1024; // ~7MB encoded
  static const int maxDecodedBytes = 5 * 1024 * 1024; // 5MB decoded
  static const int defaultMaxDimension = 1024;
  static const int defaultJpegQuality = 85;
  static const List<String> supportedMimeTypes = ['image/jpeg', 'image/png'];

  // ── Base64 Encode/Decode ──────────────────────────────────────────

  static String bytesToBase64(Uint8List bytes) => base64Encode(bytes);

  static Uint8List? base64ToBytes(String base64) {
    try { return base64Decode(base64); } catch (_) { return null; }
  }

  static String stripDataUri(String dataUri) {
    final i = dataUri.indexOf(',');
    return i != -1 ? dataUri.substring(i + 1) : dataUri;
  }

  static String addDataUri(String base64, {String mime = 'image/jpeg'}) {
    return base64.startsWith('data:') ? base64 : 'data:$mime;base64,$base64';
  }

  // ── Resize for LLM ────────────────────────────────────────────────

  static Future<String> resizeForLLM(String base64, {
    int maxDim = defaultMaxDimension, int quality = defaultJpegQuality,
  }) async {
    final dims = await getDimensions(base64);
    if (dims.width <= 0) return base64;
    final maxSide = math.max(dims.width, dims.height);
    if (maxSide <= maxDim) return base64;
    // Client-side resize requires `image` package. APIs resize internally.
    debugPrint('[ImageUtils] ${dims.width}x${dims.height} exceeds $maxDim');
    return base64;
  }

  // ── Get Dimensions ────────────────────────────────────────────────

  static Future<ImageDimensions> getDimensions(String base64) async {
    try { return getDimensionsFromBytes(base64Decode(base64)); }
    catch (_) { return ImageDimensions.zero; }
  }

  static ImageDimensions getDimensionsFromBytes(List<int> bytes) {
    if (bytes.isEmpty) return ImageDimensions.zero;
    if (bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8)
      return _jpegDimensions(bytes);
    if (bytes.length > 24 && bytes[0] == 0x89 && bytes[1] == 0x50)
      return _pngDimensions(bytes);
    return ImageDimensions.zero;
  }

  // ── Format Size ───────────────────────────────────────────────────

  static String formatSize(int bytes, {int decimals = 1}) {
    if (bytes < 0) return 'Unknown';
    if (bytes < 1024) return '${bytes}B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(decimals)}KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(decimals)}MB';
    return '${(mb / 1024).toStringAsFixed(decimals)}GB';
  }

  static String formatBase64Size(String base64) {
    return '${formatSize(base64.length)} encoded / '
        '${formatSize(estimateDecodedSize(base64))} decoded';
  }

  // ── Validation ────────────────────────────────────────────────────

  static bool isValidForLLM(String base64) {
    try {
      if (base64.isEmpty) return false;
      final bytes = base64Decode(base64);
      if (bytes.length < 8 || bytes.length > maxDecodedBytes) return false;
      return _isJpeg(bytes) || _isPng(bytes);
    } catch (_) { return false; }
  }

  static bool isValidImage(String base64) {
    try { return _isJpeg(base64Decode(base64)) || _isPng(base64Decode(base64)); }
    catch (_) { return false; }
  }

  static String detectMimeType(String base64) {
    try {
      final b = base64Decode(base64);
      if (_isJpeg(b)) return 'image/jpeg';
      if (_isPng(b)) return 'image/png';
    } catch (_) {}
    return 'application/octet-stream';
  }

  // ── Size Estimation ───────────────────────────────────────────────

  static int estimateDecodedSize(String base64) {
    var pad = 0;
    if (base64.endsWith('==')) pad = 2; else if (base64.endsWith('=')) pad = 1;
    return ((base64.length * 3) ~/ 4) - pad;
  }

  static int estimateTokenCost(String base64, {String? provider}) {
    final dims = getDimensionsFromBytes(base64Decode(base64));
    if (dims.width <= 0) return 0;
    final tiles = ((dims.width / 512).ceil()) * ((dims.height / 512).ceil());
    switch (provider) {
      case 'openai': return tiles * 170;
      case 'claude': return tiles * 150;
      case 'gemini': return tiles * 258;
      default: return tiles * 170;
    }
  }

  // ── Pick & Encode (stub) ──────────────────────────────────────────

  static Future<String?> pickAndEncode() async {
    // TODO: Integrate image_picker package
    debugPrint('[ImageUtils] pickAndEncode: add image_picker to pubspec');
    return null;
  }

  static Future<String?> captureAndEncode() async {
    // TODO: Integrate image_picker package
    debugPrint('[ImageUtils] captureAndEncode: add image_picker to pubspec');
    return null;
  }

  // ── Private: Format Detection ─────────────────────────────────────

  static bool _isJpeg(List<int> bytes) =>
    bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;

  static bool _isPng(List<int> bytes) =>
    bytes.length >= 4 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47;

  static ImageDimensions _jpegDimensions(List<int> bytes) {
    for (var i = 0; i < bytes.length - 9; i++) {
      if (bytes[i] == 0xFF && (bytes[i+1] == 0xC0 || bytes[i+1] == 0xC1 || bytes[i+1] == 0xC2)) {
        return ImageDimensions(
          height: (bytes[i+5] << 8) | bytes[i+6],
          width: (bytes[i+7] << 8) | bytes[i+8]);
      }
    }
    return ImageDimensions.zero;
  }

  static ImageDimensions _pngDimensions(List<int> bytes) {
    if (bytes.length < 24) return ImageDimensions.zero;
    return ImageDimensions(
      width: (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19],
      height: (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ImageDimensions
// ═══════════════════════════════════════════════════════════════════════════

@immutable
class ImageDimensions {
  final int width;
  final int height;
  const ImageDimensions({required this.width, required this.height});
  static const ImageDimensions zero = ImageDimensions(width: 0, height: 0);

  double get aspectRatio => height > 0 ? width / height : 1.0;
  bool get isLandscape => width > height;
  bool get isPortrait => height > width;
  bool get isSquare => width == height;
  int get pixelCount => width * height;
  int get maxDimension => math.max(width, height);
  bool get isValid => width > 0 && height > 0;

  @override
  String toString() => '${width}x$height';

  @override
  bool operator ==(Object other) =>
    identical(this, other) || other is ImageDimensions && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}
