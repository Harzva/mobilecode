// lib/services/multimodal_llm_service.dart
// Multimodal LLM Service: text + image for OpenAI, Claude, Gemini

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/api_config.dart';
import '../models/chat_message.dart';
import 'api_service.dart';
import 'llm_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Extensions
// ═══════════════════════════════════════════════════════════════════════════

extension ProviderTypeExt on ApiConfig {
  bool get isOpenAI => provider == 'openai' || provider == 'custom';
  bool get isClaude => provider == 'claude';
  bool get isGemini => provider == 'gemini';

  bool get supportsVision {
    final m = model.toLowerCase();
    if (isOpenAI) return m.contains('gpt-4') || m.contains('gpt-4o') || m.contains('o1');
    if (isClaude) return m.contains('claude-3');
    if (isGemini) return m.contains('gemini') && !m.contains('gemini-1.0');
    return false;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Data Models
// ═══════════════════════════════════════════════════════════════════════════

@immutable
class CodeBlock {
  final String language;
  final String code;
  final String? filePath;
  const CodeBlock({required this.language, required this.code, this.filePath});
}

@immutable
class ImageAnalysisResult {
  final String rawResponse;
  final List<CodeBlock> codeBlocks;
  final Map<String, String> colorPalette;
  final List<String> components;
  final String explanation;
  final double confidence;
  const ImageAnalysisResult({
    required this.rawResponse,
    this.codeBlocks = const [],
    this.colorPalette = const {},
    this.components = const [],
    this.explanation = '',
    this.confidence = 0.0,
  });
  CodeBlock? get primaryCode => codeBlocks.isNotEmpty ? codeBlocks.first : null;
  bool get hasCode => codeBlocks.isNotEmpty;
}

class ImageValidationException implements Exception {
  final String message;
  const ImageValidationException(this.message);
  @override
  String toString() => 'ImageValidationException: $message';
}

class VisionNotSupportedException implements Exception {
  final String provider;
  final String model;
  const VisionNotSupportedException(this.provider, this.model);
  @override
  String toString() => 'VisionNotSupportedException: $provider/$model';
}

// ═══════════════════════════════════════════════════════════════════════════
// Size Helper
// ═══════════════════════════════════════════════════════════════════════════

class Size {
  final double width;
  final double height;
  const Size(this.width, this.height);
  static const Size zero = Size(0, 0);
  double get aspectRatio => width > 0 ? width / height : 1.0;
  @override
  String toString() => 'Size(${width.toInt()}x${height.toInt()})';
}

// ═══════════════════════════════════════════════════════════════════════════
// Multimodal LLM Service
// ═══════════════════════════════════════════════════════════════════════════

class MultimodalLLMService {
  final ApiService _api;
  late final LLMService _textLlm;

  static const int defaultMaxDimension = 1024;
  static const int defaultJpegQuality = 85;
  static const int maxBase64Length = 7 * 1024 * 1024;

  MultimodalLLMService(this._api) {
    _textLlm = LLMService(_api);
  }

  // ── Text-only (delegates to LLMService) ───────────────────────────

  Future<String> complete(String prompt, {ApiConfig? config}) async {
    if (config == null) {
      throw const LLMException(message: 'No API config', provider: 'unknown');
    }
    return _textLlm.chat(prompt, [], config);
  }

  Stream<String> streamComplete(String prompt, {ApiConfig? config}) {
    if (config == null) {
      return Stream.error(const LLMException(
        message: 'No API config for streaming', provider: 'unknown'));
    }
    return _textLlm.chatStream(prompt, [], config);
  }

  // ── Multimodal: Text + Image ──────────────────────────────────────

  Future<String> analyzeImage({
    required String prompt,
    required String imageBase64,
    ApiConfig? config,
  }) async {
    config ??= _fallbackConfig;
    if (config == null) {
      throw const LLMException(message: 'No API config', provider: 'unknown');
    }
    if (!validateImage(imageBase64)) {
      throw const ImageValidationException('Invalid image: must be JPEG/PNG');
    }
    if (imageBase64.length > maxBase64Length) {
      throw ImageValidationException(
        'Image too large: ${imageBase64.length} chars (max $maxBase64Length)');
    }
    if (!config.supportsVision) {
      throw VisionNotSupportedException(config.provider, config.model);
    }
    try {
      if (config.isOpenAI) return await _openAIAnalyzeImage(prompt, imageBase64, config);
      if (config.isClaude) return await _claudeAnalyzeImage(prompt, imageBase64, config);
      if (config.isGemini) return await _geminiAnalyzeImage(prompt, imageBase64, config);
      throw LLMException(
        message: 'Unsupported provider: ${config.provider}',
        provider: config.provider, model: config.model);
    } on LLMException { rethrow; }
    catch (e) {
      throw LLMException(
        message: 'Image analysis failed: $e',
        provider: config.provider, model: config.model, originalError: e);
    }
  }

  Stream<String> streamAnalyzeImage({
    required String prompt,
    required String imageBase64,
    ApiConfig? config,
  }) async* {
    config ??= _fallbackConfig;
    if (config == null) {
      yield* Stream.error(const LLMException(message: 'No API config', provider: 'unknown'));
      return;
    }
    if (!validateImage(imageBase64)) {
      yield* Stream.error(const ImageValidationException('Invalid image'));
      return;
    }
    if (!config.supportsVision) {
      yield* Stream.error(VisionNotSupportedException(config.provider, config.model));
      return;
    }
    try {
      if (config.isOpenAI) yield* _openAIStreamAnalyzeImage(prompt, imageBase64, config);
      else if (config.isClaude) yield* _claudeStreamAnalyzeImage(prompt, imageBase64, config);
      else if (config.isGemini) yield* _geminiStreamAnalyzeImage(prompt, imageBase64, config);
      else yield* Stream.error(LLMException(
        message: 'Unsupported provider: ${config.provider}', provider: config.provider));
    } catch (e) {
      yield* Stream.error(LLMException(
        message: 'Streaming failed: $e', provider: config.provider, model: config.model));
    }
  }

  // ── Structured Result ─────────────────────────────────────────────

  Future<ImageAnalysisResult> analyzeImageStructured({
    required String prompt, required String imageBase64, ApiConfig? config,
  }) async {
    final raw = await analyzeImage(prompt: prompt, imageBase64: imageBase64, config: config);
    return ImageAnalysisResult(
      rawResponse: raw,
      codeBlocks: extractCodeBlocks(raw),
      colorPalette: extractColorPalette(raw),
      components: _extractComponents(raw),
      explanation: extractExplanation(raw),
      confidence: _estimateConfidence(raw),
    );
  }

  // ── OpenAI ────────────────────────────────────────────────────────

  Future<String> _openAIAnalyzeImage(String prompt, String imageBase64, ApiConfig config) async {
    _api.setBaseUrl(config.baseUrl);
    _api.setAuthHeader(config.apiKey);
    final body = {
      'model': config.model,
      'messages': [
        {'role': 'system', 'content': 'You are an expert UI developer.'},
        {'role': 'user', 'content': [
          {'type': 'text', 'text': prompt},
          {'type': 'image_url', 'image_url': {
            'url': 'data:image/jpeg;base64,$imageBase64', 'detail': 'high'}}
        ]},
      ],
      'max_tokens': 4096, 'temperature': 0.2,
    };
    final response = await _api.post('/v1/chat/completions', data: body);
    return _extractOpenAIContent(response.data);
  }

  Stream<String> _openAIStreamAnalyzeImage(String prompt, String imageBase64, ApiConfig config) async* {
    _api.setBaseUrl(config.baseUrl);
    _api.setAuthHeader(config.apiKey);
    final body = {
      'model': config.model,
      'messages': [{'role': 'user', 'content': [
        {'type': 'text', 'text': prompt},
        {'type': 'image_url', 'image_url': {
          'url': 'data:image/jpeg;base64,$imageBase64', 'detail': 'high'}}
      ]}],
      'max_tokens': 4096, 'temperature': 0.2, 'stream': true,
    };
    await for (final line in _api.sseStream('/v1/chat/completions', data: body)) {
      if (line.isEmpty || line == 'data: [DONE]') continue;
      if (line.startsWith('data: ')) {
        try {
          final jsonData = jsonDecode(line.substring(6)) as Map<String, dynamic>;
          final content = _extractOpenAIStreamContent(jsonData);
          if (content != null && content.isNotEmpty) yield content;
        } catch (e) { debugPrint('[MultimodalLLM] Skipped malformed line: $e'); }
      }
    }
  }

  // ── Claude ────────────────────────────────────────────────────────

  Future<String> _claudeAnalyzeImage(String prompt, String imageBase64, ApiConfig config) async {
    _api.setBaseUrl(config.baseUrl);
    _api.setHeader('x-api-key', config.apiKey);
    _api.setHeader('anthropic-version', '2023-06-01');
    final body = {
      'model': config.model, 'max_tokens': 4096, 'temperature': 0.2,
      'messages': [{'role': 'user', 'content': [
        {'type': 'image', 'source': {
          'type': 'base64', 'media_type': 'image/jpeg', 'data': imageBase64}},
        {'type': 'text', 'text': prompt},
      ]}],
    };
    final response = await _api.post('/v1/messages', data: body);
    return _extractClaudeContent(response.data);
  }

  Stream<String> _claudeStreamAnalyzeImage(String prompt, String imageBase64, ApiConfig config) async* {
    _api.setBaseUrl(config.baseUrl);
    _api.setHeader('x-api-key', config.apiKey);
    _api.setHeader('anthropic-version', '2023-06-01');
    final body = {
      'model': config.model, 'max_tokens': 4096, 'temperature': 0.2, 'stream': true,
      'messages': [{'role': 'user', 'content': [
        {'type': 'image', 'source': {
          'type': 'base64', 'media_type': 'image/jpeg', 'data': imageBase64}},
        {'type': 'text', 'text': prompt},
      ]}],
    };
    await for (final line in _api.sseStream('/v1/messages', data: body)) {
      if (line.isEmpty) continue;
      try {
        final jsonData = jsonDecode(line) as Map<String, dynamic>;
        final type = jsonData['type'] as String?;
        if (type == 'content_block_delta') {
          final text = (jsonData['delta'] as Map?)?['text'] as String?;
          if (text != null && text.isNotEmpty) yield text;
        }
      } catch (e) { debugPrint('[MultimodalLLM] Skipped Claude line: $e'); }
    }
  }

  // ── Gemini ────────────────────────────────────────────────────────

  Future<String> _geminiAnalyzeImage(String prompt, String imageBase64, ApiConfig config) async {
    final body = {
      'contents': [{'parts': [
        {'text': prompt},
        {'inline_data': {'mime_type': 'image/jpeg', 'data': imageBase64}},
      ]}],
      'generationConfig': {'maxOutputTokens': 4096, 'temperature': 0.2},
    };
    final url = '/${config.model}:generateContent?key=${config.apiKey}';
    _api.setBaseUrl(config.baseUrl);
    final response = await _api.post(url, data: body);
    return _extractGeminiContent(response.data);
  }

  Stream<String> _geminiStreamAnalyzeImage(String prompt, String imageBase64, ApiConfig config) async* {
    final body = {
      'contents': [{'parts': [
        {'text': prompt},
        {'inline_data': {'mime_type': 'image/jpeg', 'data': imageBase64}},
      ]}],
      'generationConfig': {'maxOutputTokens': 4096, 'temperature': 0.2},
    };
    final url = '/${config.model}:streamGenerateContent?key=${config.apiKey}';
    _api.setBaseUrl('');
    await for (final line in _api.sseStream(url, data: body)) {
      if (line.isEmpty) continue;
      try {
        final clean = line.startsWith(',') ? line.substring(1) : line;
        if (clean.trim().isEmpty) continue;
        final jsonData = jsonDecode(clean) as Map<String, dynamic>;
        final candidates = jsonData['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final parts = (candidates[0]['content'] as Map?)?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            final text = parts[0]['text'] as String?;
            if (text != null && text.isNotEmpty) yield text;
          }
        }
      } catch (e) { debugPrint('[MultimodalLLM] Skipped Gemini line: $e'); }
    }
  }

  // ── Image Preprocessing ───────────────────────────────────────────

  Future<String> preprocessImage(String imageBase64, {
    int maxWidth = defaultMaxDimension,
    int maxHeight = defaultMaxDimension,
    int quality = defaultJpegQuality,
  }) async {
    try {
      final imageBytes = base64Decode(imageBase64);
      final decoded = _decodeImage(imageBytes);
      if (decoded == null) return imageBase64;
      if (decoded.width <= maxWidth && decoded.height <= maxHeight) return imageBase64;
      final ratio = math.min(maxWidth / decoded.width, maxHeight / decoded.height);
      final newW = (decoded.width * ratio).round();
      final newH = (decoded.height * ratio).round();
      final resized = _resizeImage(decoded, newW, newH);
      return base64Encode(_encodeJpeg(resized, quality));
    } catch (e) {
      debugPrint('[MultimodalLLM] preprocessImage error: $e');
      return imageBase64;
    }
  }

  bool validateImage(String imageBase64) {
    try {
      if (imageBase64.isEmpty) return false;
      final bytes = base64Decode(imageBase64);
      if (bytes.length < 8) return false;
      final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
      final isPng = bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47;
      return isJpeg || isPng;
    } catch (_) { return false; }
  }

  Future<Size> getImageDimensions(String imageBase64) async {
    try {
      final imageBytes = base64Decode(imageBase64);
      final decoded = _decodeImage(imageBytes);
      if (decoded == null) return Size.zero;
      return Size(decoded.width.toDouble(), decoded.height.toDouble());
    } catch (_) { return Size.zero; }
  }

  // ── Response Parsing ──────────────────────────────────────────────

  List<CodeBlock> extractCodeBlocks(String response) {
    final blocks = <CodeBlock>[];
    final regex = RegExp(r'```(\w+)(?::([^
]+))?\n([\s\S]*?)\n?```', multiLine: true);
    for (final match in regex.allMatches(response)) {
      final lang = match.group(1) ?? 'text';
      final path = match.group(2);
      final code = match.group(3)?.trim() ?? '';
      if (code.isNotEmpty) blocks.add(CodeBlock(language: lang, code: code, filePath: path));
    }
    return blocks;
  }

  Map<String, String> extractColorPalette(String response) {
    final palette = <String, String>{};
    final pattern = RegExp(r'[-*]\s*([^:#\n]+?)\s*[:：]\s*#?([0-9A-Fa-f]{6})', multiLine: true);
    for (final m in pattern.allMatches(response)) {
      final name = m.group(1)?.trim();
      final hex = m.group(2)?.trim();
      if (name != null && hex != null && name.isNotEmpty) palette[name] = '#${hex.toUpperCase()}';
    }
    return palette;
  }

  String extractExplanation(String response) {
    final withoutCode = response.replaceAllMapped(
      RegExp(r'```[\s\S]*?```', multiLine: true), (_) => '');
    final withoutComponents = withoutCode.replaceAllMapped(
      RegExp(r'(Components?|组件)[:：]\s*\n((?:[-*]\s*[^\n]+\n?)+)', caseSensitive: false, multiLine: true), (_) => '');
    final withoutColors = withoutComponents.replaceAllMapped(
      RegExp(r'(Colors?|颜色)[:：]\s*\n((?:[-*]\s*[^\n]+\n?)+)', caseSensitive: false, multiLine: true), (_) => '');
    return withoutColors.trim();
  }

  // ── Private: Response Extraction ──────────────────────────────────

  String _extractOpenAIContent(Map<String, dynamic> data) {
    final choices = data['choices'] as List?;
    if (choices != null && choices.isNotEmpty) {
      return ((choices[0] as Map)['message'] as Map?)?['content'] as String? ?? '';
    }
    return '';
  }

  String? _extractOpenAIStreamContent(Map<String, dynamic> data) {
    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) return null;
    return ((choices[0] as Map)['delta'] as Map?)?['content'] as String?;
  }

  String _extractClaudeContent(Map<String, dynamic> data) {
    final content = data['content'] as List?;
    if (content != null && content.isNotEmpty) return (content[0] as Map)['text'] as String? ?? '';
    return data['completion'] as String? ?? '';
  }

  String _extractGeminiContent(Map<String, dynamic> data) {
    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) return '';
    final parts = (candidates[0]['content'] as Map?)?['parts'] as List?;
    if (parts == null || parts.isEmpty) return '';
    return parts[0]['text'] as String? ?? '';
  }

  // ── Private: Helpers ──────────────────────────────────────────────

  List<String> _extractComponents(String response) {
    final components = <String>[];
    final section = RegExp(r'(Components?|组件)[:：]\s*\n((?:[-*]\s*[^\n]+\n?)+)', caseSensitive: false, multiLine: true)
        .firstMatch(response);
    if (section != null) {
      for (final cm in RegExp(r'[-*]\s*(.+)').allMatches(section.group(2) ?? '')) {
        final c = cm.group(1)?.trim();
        if (c != null && c.isNotEmpty) components.add(c);
      }
    }
    if (components.isEmpty) {
      for (final cm in RegExp(r'class\s+(\w+)\s+extends').allMatches(response)) {
        final name = cm.group(1);
        if (name != null) components.add(name);
      }
    }
    return components;
  }

  double _estimateConfidence(String response) {
    double score = 0.5;
    if (RegExp(r'```\w*\n').hasMatch(response)) score += 0.2;
    if (response.length > 100) score += 0.1;
    if (response.length > 500) score += 0.1;
    if (extractColorPalette(response).isNotEmpty) score += 0.1;
    return score.clamp(0.0, 1.0);
  }

  // ── Private: Image Decoding ───────────────────────────────────────

  _SimpleImage? _decodeImage(List<int> bytes) {
    try {
      if (bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) return _parseJpeg(bytes);
      if (bytes.length > 24 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47)
        return _parsePng(bytes);
      return null;
    } catch (_) { return null; }
  }

  _SimpleImage? _parseJpeg(List<int> bytes) {
    for (var i = 0; i < bytes.length - 9; i++) {
      if (bytes[i] == 0xFF && (bytes[i + 1] == 0xC0 || bytes[i + 1] == 0xC1 || bytes[i + 1] == 0xC2)) {
        final h = (bytes[i + 5] << 8) | bytes[i + 6];
        final w = (bytes[i + 7] << 8) | bytes[i + 8];
        return _SimpleImage(width: w, height: h, bytes: bytes);
      }
    }
    return null;
  }

  _SimpleImage? _parsePng(List<int> bytes) {
    if (bytes.length < 24) return null;
    final w = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
    final h = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
    return _SimpleImage(width: w, height: h, bytes: bytes);
  }

  _SimpleImage _resizeImage(_SimpleImage img, int w, int h) {
    // Client-side resize requires `image` package. LLM APIs resize internally.
    return _SimpleImage(width: w, height: h, bytes: img.bytes);
  }

  List<int> _encodeJpeg(_SimpleImage img, int quality) => img.bytes;

  ApiConfig? get _fallbackConfig => null;
}

// ═══════════════════════════════════════════════════════════════════════════
// Internal: Lightweight Image
// ═══════════════════════════════════════════════════════════════════════════

class _SimpleImage {
  final int width;
  final int height;
  final List<int> bytes;
  _SimpleImage({required this.width, required this.height, required this.bytes});
}
