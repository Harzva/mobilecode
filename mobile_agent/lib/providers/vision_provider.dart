// lib/providers/vision_provider.dart
// Riverpod provider for Screenshot-to-Code state management

import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/screenshot_to_code_service.dart';
import '../services/api_service.dart';

// ── Vision Flow Step ───────────────────────────────────────────────

enum VisionFlowStep { welcome, preview, processing, results, error }

// ── Vision State ───────────────────────────────────────────────────

@immutable
class VisionState {
  final VisionFlowStep step;
  final TargetFramework framework;
  final String? imageBase64;
  final Uint8List? imageBytes;
  final CodeConversionResult? result;
  final String? errorMessage;
  final String? userDescription;

  bool get isProcessing => step == VisionFlowStep.processing;
  bool get hasResult => result != null;
  bool get hasError => errorMessage != null;

  const VisionState({
    this.step = VisionFlowStep.welcome,
    this.framework = TargetFramework.flutter,
    this.imageBase64,
    this.imageBytes,
    this.result,
    this.errorMessage,
    this.userDescription,
  });

  VisionState copyWith({
    VisionFlowStep? step,
    TargetFramework? framework,
    String? imageBase64,
    Uint8List? imageBytes,
    Object? imageBase64N = _sentinel,
    Object? imageBytesN = _sentinel,
    CodeConversionResult? result,
    Object? resultN = _sentinel,
    String? errorMessage,
    Object? errorMessageN = _sentinel,
    String? userDescription,
  }) => VisionState(
    step: step ?? this.step,
    framework: framework ?? this.framework,
    imageBase64: imageBase64N == _sentinel ? (imageBase64 ?? this.imageBase64) : null,
    imageBytes: imageBytesN == _sentinel ? (imageBytes ?? this.imageBytes) : null,
    result: resultN == _sentinel ? (result ?? this.result) : null,
    errorMessage: errorMessageN == _sentinel ? (errorMessage ?? this.errorMessage) : null,
    userDescription: userDescription ?? this.userDescription,
  );
}

const Object _sentinel = Object();

// ── Vision Notifier ────────────────────────────────────────────────

class VisionNotifier extends StateNotifier<VisionState> {
  ScreenshotToCodeService? _service;

  VisionNotifier() : super(const VisionState());

  void setService(ScreenshotToCodeService service) => _service = service;

  // Navigation
  void goToStep(VisionFlowStep step) => state = state.copyWith(
    step: step, errorMessageN: _sentinel, errorMessage: null);
  void reset() => state = const VisionState();
  void resetResult() => state = state.copyWith(
    step: VisionFlowStep.preview, resultN: _sentinel, result: null);

  // Image
  void setImage(String base64, Uint8List bytes) => state = state.copyWith(
    imageBase64: base64, imageBytes: bytes, step: VisionFlowStep.preview,
    errorMessage: null, resultN: _sentinel, result: null);
  void clearImage() => state = state.copyWith(
    imageBase64N: _sentinel, imageBytesN: _sentinel, resultN: _sentinel,
    errorMessageN: _sentinel, step: VisionFlowStep.welcome);

  // Framework
  void selectFramework(TargetFramework framework) => state = state.copyWith(framework: framework);

  // Description
  void setUserDescription(String description) => state = state.copyWith(userDescription: description);
  void clearError() => state = state.copyWith(errorMessageN: _sentinel);

  // Conversion
  Future<void> startConversion() async {
    if (state.imageBase64 == null || _service == null) return;
    state = state.copyWith(step: VisionFlowStep.processing,
      errorMessageN: _sentinel, resultN: _sentinel);

    try {
      // TODO: Use real service call:
      // final config = ref.read(apiConfigProvider);
      // final result = await _service!.convert(state.imageBase64!, state.framework, config,
      //   userDescription: state.userDescription);

      // Demo result
      await Future.delayed(const Duration(seconds: 2));
      final result = _demoResult();
      _service?.persistConversion(state.imageBase64!, result);
      state = state.copyWith(step: VisionFlowStep.results, result: result);
    } catch (e) {
      state = state.copyWith(step: VisionFlowStep.error, errorMessage: e.toString());
    }
  }

  Future<void> retry() => startConversion();

  CodeConversionResult _demoResult() => CodeConversionResult(
    code: '''import 'package:flutter/material.dart';

class GeneratedScreen extends StatelessWidget {
  const GeneratedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030508),
      body: SafeArea(
        child: Center(
          child: Text('Hello, MobileCode!',
            style: TextStyle(fontSize: 24, color: Color(0xFFF0F0F5))),
        ),
      ),
    );
  }
}''',
    explanation: '由截图自动生成的 Flutter 页面，使用深空暗色主题。',
    colorPalette: const {'Background': '#030508', 'Text Primary': '#F0F0F5'},
    components: const ['Scaffold', 'SafeArea', 'Center', 'Text'],
    framework: state.framework,
    confidence: 0.85,
    timestamp: DateTime.now(),
  );
}

// ── Selection Providers ──────────────────────────────────────────

/// Whether an image is currently selected
final hasImageProvider = Provider<bool>((ref) => ref.watch(visionProvider).imageBase64 != null);

/// Confidence score of the current result (0.0 - 1.0)
final confidenceProvider = Provider<double>((ref) {
  final result = ref.watch(visionProvider).result;
  return result?.confidence ?? 0.0;
});

/// Color palette of the current result
final colorPaletteProvider = Provider<Map<String, String>>((ref) {
  final result = ref.watch(visionProvider).result;
  return result?.colorPalette ?? const {};
});

/// Components list of the current result
final componentsProvider = Provider<List<String>>((ref) {
  final result = ref.watch(visionProvider).result;
  return result?.components ?? const [];
});

/// Generated code from current result
final generatedCodeProvider = Provider<String>((ref) {
  final result = ref.watch(visionProvider).result;
  return result?.code ?? '';
});

/// Current step in the vision flow
final visionStepProvider = Provider<VisionFlowStep>((ref) => ref.watch(visionProvider).step);

/// Selected framework
final visionFrameworkProvider = Provider<TargetFramework>((ref) => ref.watch(visionProvider).framework);

/// Current result
final visionResultProvider = Provider<CodeConversionResult?>((ref) => ref.watch(visionProvider).result);

/// Whether processing is in progress
final visionProcessingProvider = Provider<bool>((ref) => ref.watch(visionProvider).isProcessing);

/// Current error message
final visionErrorProvider = Provider<String?>((ref) => ref.watch(visionProvider).errorMessage);

// ── Service Providers ─────────────────────────────────────────────

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

final screenshotToCodeServiceProvider = Provider<ScreenshotToCodeService>((ref) {
  final api = ref.watch(apiServiceProvider);
  return ScreenshotToCodeService(api);
});

final conversionHistoryProvider = Provider<List<ConversionHistoryEntry>>((ref) {
  return ref.watch(screenshotToCodeServiceProvider).history;
});

// ── Notifier Provider with Auto-init ──────────────────────────────

/// Pre-initialized vision notifier with service injected.
/// Use this in screens to get a fully wired-up notifier.
final visionNotifierProvider = StateNotifierProvider<VisionNotifier, VisionState>((ref) {
  final notifier = VisionNotifier();
  final service = ref.watch(screenshotToCodeServiceProvider);
  notifier.setService(service);
  return notifier;
});
