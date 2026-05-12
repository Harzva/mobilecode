// lib/services/screenshot_to_code_service.dart
// Core service: converts UI screenshots to code via multimodal LLM

import 'dart:convert';
import 'dart:developer' as developer;
import 'api_service.dart';
import '../models/api_config.dart';

// ── Enums ──────────────────────────────────────────────────────────

enum TargetFramework { flutter, html, react, vue }

extension TFExt on TargetFramework {
  String get label {
    switch (this) {
      case TargetFramework.flutter: return 'Flutter';
      case TargetFramework.html: return 'HTML/CSS';
      case TargetFramework.react: return 'React';
      case TargetFramework.vue: return 'Vue';
    }
  }

  String get fileExt {
    switch (this) {
      case TargetFramework.flutter: return '.dart';
      case TargetFramework.html: return '.html';
      case TargetFramework.react: return '.jsx';
      case TargetFramework.vue: return '.vue';
    }
  }

  String get langId {
    switch (this) {
      case TargetFramework.flutter: return 'dart';
      case TargetFramework.html: return 'html';
      case TargetFramework.react: return 'javascript';
      case TargetFramework.vue: return 'javascript';
    }
  }
}

// ── Result Classes ─────────────────────────────────────────────────

class CodeConversionResult {
  final String code;
  final String explanation;
  final Map<String, String> colorPalette;
  final List<String> components;
  final TargetFramework framework;
  final double confidence;
  final String rawResponse;
  final DateTime timestamp;

  const CodeConversionResult({
    required this.code,
    required this.explanation,
    required this.colorPalette,
    required this.components,
    required this.framework,
    this.confidence = 0.0,
    this.rawResponse = '',
    required this.timestamp,
  });

  factory CodeConversionResult.empty(TargetFramework fw) =>
      CodeConversionResult(code: '', explanation: '', colorPalette: const {},
          components: const [], framework: fw, timestamp: DateTime.now());
}

class ErrorFixResult {
  final String errorType;
  final String rootCause;
  final String fixedCode;
  final List<String> suggestions;
  final double confidence;

  const ErrorFixResult({
    required this.errorType, required this.rootCause,
    required this.fixedCode, required this.suggestions,
    this.confidence = 0.0,
  });

  factory ErrorFixResult.empty() =>
      const ErrorFixResult(errorType: 'Unknown', rootCause: '', fixedCode: '', suggestions: []);
}

class ConversionHistoryEntry {
  final String id;
  final String imageBase64;
  final CodeConversionResult result;
  final DateTime createdAt;

  ConversionHistoryEntry({required this.imageBase64, required this.result})
      : id = 'conv_${DateTime.now().millisecondsSinceEpoch}',
        createdAt = DateTime.now();
}

// ── Main Service ───────────────────────────────────────────────────

class ScreenshotToCodeService {
  final ApiService _api;
  final List<ConversionHistoryEntry> _history = [];
  static const int _maxHistory = 50;

  ScreenshotToCodeService(this._api);

  List<ConversionHistoryEntry> get history => List.unmodifiable(_history);
  void clearHistory() => _history.clear();

  // ── Core Conversions ────────────────────────────────────────────

  Future<CodeConversionResult> convertToFlutter(
      String imageBase64, ApiConfig config, {String? userDescription}) async {
    final response = await _analyzeImage(_buildFlutterPrompt(userDescription), imageBase64, config);
    return _parseCodeResult(response, TargetFramework.flutter);
  }

  Future<CodeConversionResult> convertToHtml(
      String imageBase64, ApiConfig config, {String? userDescription}) async {
    final response = await _analyzeImage(_buildHtmlPrompt(userDescription), imageBase64, config);
    return _parseCodeResult(response, TargetFramework.html);
  }

  Future<CodeConversionResult> convertToReact(
      String imageBase64, ApiConfig config, {String? userDescription}) async {
    final response = await _analyzeImage(_buildReactPrompt(userDescription), imageBase64, config);
    return _parseCodeResult(response, TargetFramework.react);
  }

  Future<CodeConversionResult> convertToVue(
      String imageBase64, ApiConfig config, {String? userDescription}) async {
    final response = await _analyzeImage(_buildVuePrompt(userDescription), imageBase64, config);
    return _parseCodeResult(response, TargetFramework.vue);
  }

  Future<CodeConversionResult> convert(
      String imageBase64, TargetFramework framework, ApiConfig config,
      {String? userDescription}) {
    switch (framework) {
      case TargetFramework.flutter: return convertToFlutter(imageBase64, config, userDescription: userDescription);
      case TargetFramework.html: return convertToHtml(imageBase64, config, userDescription: userDescription);
      case TargetFramework.react: return convertToReact(imageBase64, config, userDescription: userDescription);
      case TargetFramework.vue: return convertToVue(imageBase64, config, userDescription: userDescription);
    }
  }

  // ── Error Analysis ──────────────────────────────────────────────

  Future<ErrorFixResult> analyzeErrorScreenshot(
      String errorImageBase64, String currentCode, String language, ApiConfig config) async {
    final prompt = _buildErrorAnalysisPrompt(currentCode, language);
    final response = await _analyzeImage(prompt, errorImageBase64, config);
    return _parseErrorFixResult(response);
  }

  // ── Mockup Conversion ───────────────────────────────────────────

  Future<CodeConversionResult> convertMockup(
      String mockupBase64, ApiConfig config,
      {required TargetFramework framework, String? userDescription}) async {
    final prompt = _buildMockupPrompt(framework, userDescription);
    final response = await _analyzeImage(prompt, mockupBase64, config);
    return _parseCodeResult(response, framework);
  }

  // ── Prompt Builders ─────────────────────────────────────────────

  String _buildFlutterPrompt(String? desc) => '''
You are an expert Flutter developer. Given the UI screenshot, generate pixel-perfect Flutter code.

Requirements:
- Use Material 3 design system
- Extract EXACT colors (Color(0xFFRRGGBB))
- Extract EXACT font sizes, weights, spacing
- Use responsive LayoutBuilder where needed
- Add Chinese comments for complex widgets
- Include proper imports
- Code must be ready to paste into a Flutter project

${desc != null ? 'User description: $desc' : ''}

Return ONLY the code in \`\`\`dart ... \`\`\` blocks. Include explanation in Chinese after code.
List extracted colors as: - ColorName: #RRGGBB
List components as: - ComponentName'''.trim();

  String _buildHtmlPrompt(String? desc) => '''
You are an expert frontend developer. Given the UI screenshot, generate HTML/CSS code.

Requirements:
- Semantic HTML5, modern CSS (flexbox/grid)
- Extract EXACT colors as CSS custom properties
- Extract EXACT fonts, spacing, border-radius
- Responsive with media queries
- Add Chinese comments
- Single file with style in head

${desc != null ? 'User description: $desc' : ''}

Return in \`\`\`html ... \`\`\` blocks. Explanation in Chinese after code.'''.trim();

  String _buildReactPrompt(String? desc) => '''
You are an expert React developer. Given the UI screenshot, generate React code.

Requirements:
- Modern React with hooks
- Extract EXACT colors (Tailwind or CSS variables)
- Extract EXACT fonts, spacing
- Component-based architecture
- Add Chinese comments
- Code must be ready to use

${desc != null ? 'User description: $desc' : ''}

Return in \`\`\`jsx ... \`\`\` blocks. Explanation in Chinese after code.'''.trim();

  String _buildVuePrompt(String? desc) => '''
You are an expert Vue 3 developer. Given the UI screenshot, generate Vue code.

Requirements:
- Vue 3 Composition API with <script setup>
- Extract EXACT colors
- Extract EXACT fonts, spacing
- Scoped CSS or Tailwind
- Add Chinese comments

${desc != null ? 'User description: $desc' : ''}

Return in \`\`\`vue ... \`\`\` blocks. Explanation in Chinese after code.'''.trim();

  String _buildErrorAnalysisPrompt(String code, String lang) => '''
You are an expert debugger. Analyze this error screenshot and code.

Current code:
```$lang
$code
```

Return format:
1. Error Type: <classification>
2. Root Cause: <Chinese explanation>
3. Fixed code in \`\`\`$lang ... \`\`\` block
4. Suggestions: <numbered list in Chinese>'''.trim();

  String _buildMockupPrompt(TargetFramework fw, String? desc) => '''
Convert this design mockup to ${fw.label} code. Pay attention to pixel-perfect alignment,
color accuracy, typography, shadows, and spacing.

${desc != null ? 'Context: $desc' : ''}

Return code in appropriate markdown block. Explanation in Chinese.'''.trim();

  // ── Multimodal API ──────────────────────────────────────────────

  Future<String> _analyzeImage(String prompt, String imageBase64, ApiConfig config) async {
    _api.setBaseUrl(config.baseUrl);
    if (config.isGemini) return _analyzeGemini(prompt, imageBase64, config);
    if (config.isClaude) return _analyzeClaude(prompt, imageBase64, config);
    return _analyzeOpenAI(prompt, imageBase64, config);
  }

  Future<String> _analyzeOpenAI(String prompt, String imageBase64, ApiConfig config) async {
    _api.setAuthHeader(config.apiKey);
    final body = {
      'model': config.model,
      'messages': [
        {'role': 'system', 'content': 'You are an expert UI developer. Convert screenshots to code with pixel-perfect accuracy.'},
        {'role': 'user', 'content': [
          {'type': 'text', 'text': prompt},
          {'type': 'image_url', 'image_url': {'url': 'data:image/jpeg;base64,$imageBase64', 'detail': 'high'}}
        ]},
      ],
      'max_tokens': config.maxTokens ?? 4096,
      'temperature': config.temperature ?? 0.2,
    };
    final response = await _api.post('/v1/chat/completions', data: body);
    final choices = (response.data as Map)['choices'] as List?;
    if (choices == null || choices.isEmpty) return '';
    return ((choices[0] as Map)['message'] as Map)['content'] as String? ?? '';
  }

  Future<String> _analyzeClaude(String prompt, String imageBase64, ApiConfig config) async {
    _api.setHeader('x-api-key', config.apiKey);
    _api.setHeader('anthropic-version', '2023-06-01');
    final body = {
      'model': config.model,
      'max_tokens': config.maxTokens ?? 4096,
      'temperature': config.temperature ?? 0.2,
      'messages': [{
        'role': 'user',
        'content': [
          {'type': 'image', 'source': {'type': 'base64', 'media_type': 'image/jpeg', 'data': imageBase64}},
          {'type': 'text', 'text': prompt},
        ],
      }],
    };
    final response = await _api.post('/v1/messages', data: body);
    final content = (response.data as Map)['content'] as List?;
    if (content == null || content.isEmpty) return '';
    return (content[0] as Map)['text'] as String? ?? '';
  }

  Future<String> _analyzeGemini(String prompt, String imageBase64, ApiConfig config) async {
    final body = {
      'contents': [{
        'parts': [
          {'text': prompt},
          {'inline_data': {'mime_type': 'image/jpeg', 'data': imageBase64}},
        ],
      }],
      'generationConfig': {
        'maxOutputTokens': config.maxTokens ?? 4096,
        'temperature': config.temperature ?? 0.2,
      },
    };
    final url = '/${config.model}:generateContent?key=${config.apiKey}';
    final response = await _api.post(url, data: body);
    final candidates = (response.data as Map)['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) return '';
    final parts = ((candidates[0] as Map)['content'] as Map)['parts'] as List?;
    if (parts == null || parts.isEmpty) return '';
    return (parts[0] as Map)['text'] as String? ?? '';
  }

  // ── Response Parsers ────────────────────────────────────────────

  CodeConversionResult _parseCodeResult(String response, TargetFramework fw) {
    try {
      final code = _extractCodeBlock(response);
      final explanation = _extractExplanation(response);
      final colorPalette = _extractColorPalette(response);
      final components = _extractComponents(response);
      final confidence = _estimateConfidence(response, code);

      return CodeConversionResult(
        code: code, explanation: explanation, colorPalette: colorPalette,
        components: components, framework: fw, confidence: confidence,
        rawResponse: response, timestamp: DateTime.now(),
      );
    } catch (e, stack) {
      developer.log('[S2C] Parse error: \$e\n\$stack', name: 'ScreenshotToCode');
      return CodeConversionResult(
        code: '// Parse error: \$e', explanation: 'Parsing failed, please retry.',
        colorPalette: const {}, components: const [], framework: fw,
        rawResponse: response, timestamp: DateTime.now(),
      );
    }
  }

  ErrorFixResult _parseErrorFixResult(String response) {
    try {
      final errorType = _extractLine(response, 'Error Type:') ?? _extractLine(response, '错误类型：') ?? 'Unknown';
      final rootCause = _extractLine(response, 'Root Cause:') ?? _extractLine(response, '根因：') ?? '';
      final fixedCode = _extractCodeBlock(response);
      final suggestions = _extractNumberedList(response);
      return ErrorFixResult(
        errorType: errorType.trim(), rootCause: rootCause.trim(),
        fixedCode: fixedCode, suggestions: suggestions,
        confidence: _estimateConfidence(response, fixedCode),
      );
    } catch (e) {
      return ErrorFixResult.empty();
    }
  }

  // ── Extraction Helpers ──────────────────────────────────────────

  String _extractCodeBlock(String response) {
    final patterns = [
      RegExp(r'```dart\n([\s\S]*?)\n```', multiLine: true),
      RegExp(r'```html\n([\s\S]*?)\n```', multiLine: true),
      RegExp(r'```jsx?\n([\s\S]*?)\n```', multiLine: true),
      RegExp(r'```vue\n([\s\S]*?)\n```', multiLine: true),
      RegExp(r'```\w*\n([\s\S]*?)\n```', multiLine: true),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(response);
      if (m != null && m.group(1) != null) return m.group(1)!.trim();
    }
    return response.trim();
  }

  String _extractExplanation(String response) {
    final afterCode = response.split('```').lastOrNull ?? '';
    final parts = afterCode.split(RegExp(r'[\n\r](Colors?|颜色):', caseSensitive: false));
    return (parts.firstOrNull ?? afterCode).trim();
  }

  Map<String, String> _extractColorPalette(String response) {
    final palette = <String, String>{};
    final pattern = RegExp(r'[-*]\s*([^:#\n]+?)\s*[:：]\s*#?([0-9A-Fa-f]{6})', multiLine: true);
    for (final m in pattern.allMatches(response)) {
      final name = m.group(1)?.trim();
      final hex = m.group(2)?.trim();
      if (name != null && hex != null && name.isNotEmpty) {
        palette[name] = '#${hex.toUpperCase()}';
      }
    }
    return palette;
  }

  List<String> _extractComponents(String response) {
    final components = <String>[];
    final section = RegExp(r'(Components?|组件)[:：]\s*\n((?:[-*]\s*[^\n]+\n?)+)', caseSensitive: false, multiLine: true);
    final m = section.firstMatch(response);
    if (m != null) {
      for (final cm in RegExp(r'[-*]\s*(.+)').allMatches(m.group(2) ?? '')) {
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

  String? _extractLine(String response, String prefix) {
    final m = RegExp('^${RegExp.escape(prefix)}\\s*(.+)', multiLine: true, caseSensitive: false).firstMatch(response);
    return m?.group(1);
  }

  List<String> _extractNumberedList(String response) {
    return RegExp(r'^\d+\.\s*(.+)$', multiLine: true)
        .allMatches(response)
        .map((m) => m.group(1)?.trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  double _estimateConfidence(String response, String code) {
    double score = 0.5;
    if (RegExp(r'```\w*\n').hasMatch(response)) score += 0.2;
    if (code.length > 100) score += 0.1;
    if (code.length > 500) score += 0.1;
    if (_extractColorPalette(response).isNotEmpty) score += 0.1;
    if (_extractExplanation(response).length > 20) score += 0.1;
    return score.clamp(0.0, 1.0);
  }

  // ── Batch Conversion ────────────────────────────────────────────

  /// Convert multiple images in sequence, returning results in order.
  Future<List<CodeConversionResult>> batchConvert(
    List<String> imageBase64List,
    TargetFramework framework,
    ApiConfig config, {
    String? userDescription,
    void Function(int current, int total, String status)? onProgress,
  }) async {
    final results = <CodeConversionResult>[];
    for (var i = 0; i < imageBase64List.length; i++) {
      onProgress?.call(i + 1, imageBase64List.length, 'Processing image ${i + 1}');
      try {
        final result = await convert(imageBase64List[i], framework, config,
          userDescription: userDescription);
        results.add(result);
      } catch (e) {
        results.add(CodeConversionResult.empty(framework));
      }
    }
    return results;
  }

  // ── Code Export ─────────────────────────────────────────────────

  /// Wrap generated code in a complete file scaffold for the framework.
  String wrapInScaffold(String code, TargetFramework framework) {
    switch (framework) {
      case TargetFramework.flutter:
        if (code.contains('import ')) return code;
        return "import 'package:flutter/material.dart';\n\n$code";
      case TargetFramework.html:
        if (code.contains('<!DOCTYPE')) return code;
        return '<!DOCTYPE html>\n<html lang="zh-CN">\n<head>\n  <meta charset="UTF-8">\n  <meta name="viewport" content="width=device-width, initial-scale=1.0">\n  <title>Generated</title>\n<style>\n\n</style>\n</head>\n<body>\n$code\n</body>\n</html>';
      case TargetFramework.react:
        if (code.contains('import React')) return code;
        return "import React from 'react';\n\n$code";
      case TargetFramework.vue:
        if (code.contains('<template>')) return code;
        return '<template>\n<div>\n$code\n</div>\n</template>\n\n<script setup>\n</script>\n\n<style scoped>\n</style>';
    }
  }

  // ── Validation ──────────────────────────────────────────────────

  /// Validate that a Base64 string represents a valid image.
  bool isValidImageBase64(String base64String) {
    try {
      final bytes = base64Decode(base64String);
      // Check for JPEG or PNG magic numbers
      if (bytes.length < 4) return false;
      final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8;
      final isPng = bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47;
      return isJpeg || isPng;
    } catch (_) {
      return false;
    }
  }

  /// Truncate Base64 to reduce token usage for LLM.
  /// Preserves image quality up to max dimension.
  String truncateBase64ForLLM(String base64String, {int maxChars = 500000}) {
    if (base64String.length <= maxChars) return base64String;
    // If too large, return first portion (LLM will still process at lower resolution)
    return base64String.substring(0, maxChars);
  }

  // ── History ─────────────────────────────────────────────────────

  void persistConversion(String imageBase64, CodeConversionResult result) {
    _history.insert(0, ConversionHistoryEntry(imageBase64: imageBase64, result: result));
    while (_history.length > _maxHistory) _history.removeLast();
  }
}
