// lib/providers/multimodal_llm_provider.dart
// Riverpod provider for Multimodal LLM: manages image analysis state

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_config.dart';
import '../services/api_service.dart';
import '../services/multimodal_llm_service.dart';
import 'api_config_provider.dart';
import 'llm_service_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Service Provider
// ═══════════════════════════════════════════════════════════════════════════

final multimodalLLMServiceProvider = Provider<MultimodalLLMService>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return MultimodalLLMService(apiService);
});

// ═══════════════════════════════════════════════════════════════════════════
// Analysis State
// ═══════════════════════════════════════════════════════════════════════════

enum AnalysisStatus { idle, preparing, processing, streaming, completed, error }

@immutable
class MultimodalAnalysisState {
  final AnalysisStatus status;
  final String? imageBase64;
  final Uint8List? imageBytes;
  final String prompt;
  final String response;
  final String streamBuffer;
  final ImageAnalysisResult? result;
  final String? errorMessage;
  final DateTime? startedAt;
  final DateTime? completedAt;

  const MultimodalAnalysisState({
    this.status = AnalysisStatus.idle,
    this.imageBase64,
    this.imageBytes,
    this.prompt = '',
    this.response = '',
    this.streamBuffer = '',
    this.result,
    this.errorMessage,
    this.startedAt,
    this.completedAt,
  });

  bool get isLoading =>
      status == AnalysisStatus.preparing ||
      status == AnalysisStatus.processing ||
      status == AnalysisStatus.streaming;
  bool get isSuccess => status == AnalysisStatus.completed;
  bool get isError => status == AnalysisStatus.error;
  bool get hasImage => imageBase64 != null && imageBase64!.isNotEmpty;
  Duration? get duration => startedAt == null ? null : (completedAt ?? DateTime.now()).difference(startedAt!);

  MultimodalAnalysisState copyWith({
    AnalysisStatus? status,
    String? imageBase64,
    Uint8List? imageBytes,
    Object? imageBase64N = _sentinel,
    Object? imageBytesN = _sentinel,
    String? prompt,
    String? response,
    String? streamBuffer,
    ImageAnalysisResult? result,
    Object? resultN = _sentinel,
    String? errorMessage,
    Object? errorMessageN = _sentinel,
    DateTime? startedAt,
    DateTime? completedAt,
  }) => MultimodalAnalysisState(
    status: status ?? this.status,
    imageBase64: imageBase64N == _sentinel ? (imageBase64 ?? this.imageBase64) : null,
    imageBytes: imageBytesN == _sentinel ? (imageBytes ?? this.imageBytes) : null,
    prompt: prompt ?? this.prompt,
    response: response ?? this.response,
    streamBuffer: streamBuffer ?? this.streamBuffer,
    result: resultN == _sentinel ? (result ?? this.result) : null,
    errorMessage: errorMessageN == _sentinel ? (errorMessage ?? this.errorMessage) : null,
    startedAt: startedAt ?? this.startedAt,
    completedAt: completedAt ?? this.completedAt,
  );
}

const Object _sentinel = Object();

// ═══════════════════════════════════════════════════════════════════════════
// Analysis Notifier
// ═══════════════════════════════════════════════════════════════════════════

class MultimodalAnalysisNotifier extends StateNotifier<MultimodalAnalysisState> {
  MultimodalLLMService? _service;
  MultimodalAnalysisNotifier() : super(const MultimodalAnalysisState());

  void setService(MultimodalLLMService service) => _service = service;

  void setImage(String base64, Uint8List bytes) => state = state.copyWith(
    imageBase64: base64, imageBytes: bytes, status: AnalysisStatus.idle,
    errorMessageN: _sentinel, resultN: _sentinel, response: '', streamBuffer: '');

  void clearImage() => state = const MultimodalAnalysisState();

  void setPrompt(String prompt) => state = state.copyWith(prompt: prompt);

  Future<void> analyze(ApiConfig? activeConfig) async {
    if (state.imageBase64 == null) {
      state = state.copyWith(status: AnalysisStatus.error, errorMessage: 'No image selected');
      return;
    }
    if (_service == null) {
      state = state.copyWith(status: AnalysisStatus.error, errorMessage: 'Service not initialized');
      return;
    }
    if (activeConfig == null) {
      state = state.copyWith(status: AnalysisStatus.error, errorMessage: 'No API config');
      return;
    }

    state = state.copyWith(
      status: AnalysisStatus.preparing,
      errorMessageN: _sentinel, resultN: _sentinel,
      response: '', streamBuffer: '', startedAt: DateTime.now());

    if (!_service!.validateImage(state.imageBase64!)) {
      state = state.copyWith(status: AnalysisStatus.error, errorMessage: 'Invalid image format');
      return;
    }

    try {
      await _analyzeStreaming(activeConfig);
    } on ImageValidationException catch (e) {
      state = state.copyWith(status: AnalysisStatus.error, errorMessage: 'Image validation: $e');
    } on VisionNotSupportedException catch (e) {
      state = state.copyWith(status: AnalysisStatus.error,
        errorMessage: 'Vision not supported for ${e.provider}/${e.model}');
    } on LLMException catch (e) {
      state = state.copyWith(status: AnalysisStatus.error, errorMessage: 'API error: ${e.message}');
    } catch (e) {
      state = state.copyWith(status: AnalysisStatus.error, errorMessage: 'Error: $e');
    }
  }

  Future<void> retry(ApiConfig? activeConfig) => analyze(activeConfig);

  void cancel() {
    if (state.isLoading) state = state.copyWith(status: AnalysisStatus.idle, completedAt: DateTime.now());
  }

  void reset() => state = const MultimodalAnalysisState();

  void clearResult() => state = state.copyWith(
    status: AnalysisStatus.idle, response: '', streamBuffer: '',
    resultN: _sentinel, errorMessageN: _sentinel);

  Future<void> _analyzeStreaming(ApiConfig config) async {
    state = state.copyWith(status: AnalysisStatus.streaming, streamBuffer: '');
    final buffer = StringBuffer();
    await for (final chunk in _service!.streamAnalyzeImage(
      prompt: state.prompt, imageBase64: state.imageBase64!, config: config)) {
      buffer.write(chunk);
      state = state.copyWith(streamBuffer: buffer.toString());
    }
    final fullResponse = buffer.toString();
    state = state.copyWith(
      status: AnalysisStatus.completed, response: fullResponse, streamBuffer: fullResponse,
      result: ImageAnalysisResult(
        rawResponse: fullResponse,
        codeBlocks: _service!.extractCodeBlocks(fullResponse),
        colorPalette: _service!.extractColorPalette(fullResponse),
        components: _extractComponents(fullResponse),
        explanation: _service!.extractExplanation(fullResponse),
        confidence: _estimateConfidence(fullResponse)),
      completedAt: DateTime.now());
  }

  List<String> _extractComponents(String response) {
    final components = <String>[];
    final section = RegExp(r'(Components?|组件)[:：]\s*\n((?:[-*]\s*[^\n]+\n?)+)',
      caseSensitive: false, multiLine: true).firstMatch(response);
    if (section != null) {
      for (final cm in RegExp(r'[-*]\s*(.+)').allMatches(section.group(2) ?? '')) {
        final c = cm.group(1)?.trim();
        if (c != null && c.isNotEmpty) components.add(c);
      }
    }
    return components;
  }

  double _estimateConfidence(String response) {
    double score = 0.5;
    if (RegExp(r'```\w*\n').hasMatch(response)) score += 0.2;
    if (response.length > 500) score += 0.1;
    return score.clamp(0.0, 1.0);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Notifier Provider
// ═══════════════════════════════════════════════════════════════════════════

final multimodalAnalysisProvider =
    StateNotifierProvider<MultimodalAnalysisNotifier, MultimodalAnalysisState>((ref) {
  final notifier = MultimodalAnalysisNotifier();
  notifier.setService(ref.watch(multimodalLLMServiceProvider));
  return notifier;
});

// ═══════════════════════════════════════════════════════════════════════════
// Derived Providers
// ═══════════════════════════════════════════════════════════════════════════

final hasAnalysisImageProvider = Provider<bool>((ref) =>
  ref.watch(multimodalAnalysisProvider).hasImage);

final isAnalysisLoadingProvider = Provider<bool>((ref) =>
  ref.watch(multimodalAnalysisProvider).isLoading);

final analysisResponseProvider = Provider<String>((ref) =>
  ref.watch(multimodalAnalysisProvider).response);

final analysisStreamBufferProvider = Provider<String>((ref) =>
  ref.watch(multimodalAnalysisProvider).streamBuffer);

final analysisResultProvider = Provider<ImageAnalysisResult?>((ref) =>
  ref.watch(multimodalAnalysisProvider).result);

final analysisErrorProvider = Provider<String?>((ref) =>
  ref.watch(multimodalAnalysisProvider).errorMessage);

final analysisPrimaryCodeProvider = Provider<CodeBlock?>((ref) =>
  ref.watch(multimodalAnalysisProvider).result?.primaryCode);

final analysisColorPaletteProvider = Provider<Map<String, String>>((ref) =>
  ref.watch(multimodalAnalysisProvider).result?.colorPalette ?? {});

final activeConfigSupportsVisionProvider = Provider<bool>((ref) {
  final config = ref.watch(activeApiConfigProvider);
  return config != null && config.supportsVision;
});
