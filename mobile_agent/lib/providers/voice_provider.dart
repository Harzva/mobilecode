// lib/providers/voice_provider.dart
//
// Riverpod provider for voice input state management.
// Bridges VoiceService <-> UI <-> LLM with full lifecycle management.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/voice_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Provider Exports
// ─────────────────────────────────────────────────────────────────────────────

/// Global VoiceService instance provider (singleton).
///
/// ```dart
/// final voiceService = ref.watch(voiceServiceProvider);
/// ```
final voiceServiceProvider = Provider<VoiceService>((ref) {
  final service = VoiceService();

  ref.onDispose(() {
    service.dispose();
    debugPrint('[VoiceProvider] VoiceService disposed');
  });

  return service;
});

/// Voice state notifier provider - the main interface for voice UI.
///
/// ```dart
/// final voiceState = ref.watch(voiceStateProvider);
/// final notifier = ref.read(voiceStateProvider.notifier);
/// notifier.startListening();
/// ```
final voiceStateProvider =
    StateNotifierProvider<VoiceStateNotifier, VoiceInputState>((ref) {
  final service = ref.watch(voiceServiceProvider);
  return VoiceStateNotifier(service);
});

/// Stream provider for real-time transcript updates.
///
/// ```dart
/// final transcript = ref.watch(voiceTranscriptStreamProvider);
/// ```
final voiceTranscriptStreamProvider = StreamProvider<String>((ref) {
  final service = ref.watch(voiceServiceProvider);
  return service.onTranscriptUpdate;
});

/// Stream provider for audio level visualization data.
///
/// ```dart
/// final audioLevel = ref.watch(voiceAudioLevelStreamProvider);
/// audioLevel.whenData((level) => waveform.update(level));
/// ```
final voiceAudioLevelStreamProvider = StreamProvider<AudioLevel>((ref) {
  final service = ref.watch(voiceServiceProvider);
  return service.onAudioLevel;
});

// ─────────────────────────────────────────────────────────────────────────────
// Voice Input State
// ─────────────────────────────────────────────────────────────────────────────

/// Immutable state object for voice input UI.
///
/// Contains all the information needed to render the voice input panel:
/// current lifecycle state, transcript text, detected intent,
/// error messages, and processing status.
@immutable
class VoiceInputState {
  /// Current lifecycle state (idle, listening, processing, done, error).
  final VoiceState voiceState;

  /// Current or final transcript text.
  final String transcript;

  /// Detected code intent from the transcript (null until analysis).
  final CodeIntent? codeIntent;

  /// Structured prompt for LLM (null until intent is analyzed).
  final String? codePrompt;

  /// Error message if in error state.
  final String? errorMessage;

  /// Whether the service is initialized and ready.
  final bool isInitialized;

  /// Whether the LLM is currently generating a response.
  final bool isGeneratingCode;

  /// The generated code response from the LLM (null until received).
  final String? generatedCode;

  /// Timestamp of state creation for debug/animation purposes.
  final DateTime timestamp;

  const VoiceInputState({
    this.voiceState = VoiceState.idle,
    this.transcript = '',
    this.codeIntent,
    this.codePrompt,
    this.errorMessage,
    this.isInitialized = false,
    this.isGeneratingCode = false,
    this.generatedCode,
    required this.timestamp,
  });

  /// Factory for initial state.
  factory VoiceInputState.initial() {
    return VoiceInputState(timestamp: DateTime.now());
  }

  /// Create a copy with optional field overrides.
  VoiceInputState copyWith({
    VoiceState? voiceState,
    String? transcript,
    CodeIntent? codeIntent,
    String? codePrompt,
    String? errorMessage,
    bool? isInitialized,
    bool? isGeneratingCode,
    String? generatedCode,
    DateTime? timestamp,
  }) {
    return VoiceInputState(
      voiceState: voiceState ?? this.voiceState,
      transcript: transcript ?? this.transcript,
      codeIntent: codeIntent ?? this.codeIntent,
      codePrompt: codePrompt ?? this.codePrompt,
      errorMessage: errorMessage ?? this.errorMessage,
      isInitialized: isInitialized ?? this.isInitialized,
      isGeneratingCode: isGeneratingCode ?? this.isGeneratingCode,
      generatedCode: generatedCode ?? this.generatedCode,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  // ── Convenience Getters ──────────────────────────────────────────────

  /// Whether the voice service is currently listening.
  bool get isListening => voiceState == VoiceState.listening;

  /// Whether the transcript is being processed.
  bool get isProcessing => voiceState == VoiceState.processing;

  /// Whether a transcript is ready for review.
  bool get hasResult => voiceState == VoiceState.done && transcript.isNotEmpty;

  /// Whether an error occurred.
  bool get hasError => voiceState == VoiceState.error;

  /// Whether there's a transcript to show (partial or final).
  bool get hasTranscript => transcript.isNotEmpty;

  /// Whether a code intent was successfully detected.
  bool get hasCodeIntent => codeIntent != null && codeIntent!.isCodeRelated;

  /// Whether the transcript can be submitted to LLM.
  bool get canSubmit => hasResult || (hasTranscript && !isListening);

  @override
  String toString() {
    return 'VoiceInputState('
        'voiceState: $voiceState, '
        'transcript: "${transcript.length > 30 ? "${transcript.substring(0, 30)}..." : transcript}", '
        'hasCodeIntent: $hasCodeIntent, '
        'isGeneratingCode: $isGeneratingCode)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VoiceInputState &&
        other.voiceState == voiceState &&
        other.transcript == transcript &&
        other.isGeneratingCode == isGeneratingCode &&
        other.generatedCode == generatedCode &&
        other.isInitialized == isInitialized;
  }

  @override
  int get hashCode => Object.hash(
        voiceState,
        transcript,
        isGeneratingCode,
        generatedCode,
        isInitialized,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Voice State Notifier
// ─────────────────────────────────────────────────────────────────────────────

/// StateNotifier that manages the complete voice input lifecycle.
///
/// Coordinates between the [VoiceService] (speech recognition),
/// the UI (voice input panel), and the LLM (code generation).
///
/// ## Lifecycle
/// ```
/// idle -> [startListening] -> listening -> [stopListening] -> processing -> done
///                                                                   |
///                                                          [submitToLLM] -> generatingCode
///                                                                   |
///                                                          [reset] -> idle
/// ```
class VoiceStateNotifier extends StateNotifier<VoiceInputState> {
  final VoiceService _service;

  // ── Subscriptions ────────────────────────────────────────────────────
  StreamSubscription<VoiceState>? _stateSub;
  StreamSubscription<String>? _transcriptSub;
  StreamSubscription<AudioLevel>? _audioSub;

  // ── Callbacks ────────────────────────────────────────────────────────

  /// Called when a code prompt is ready to be sent to LLM.
  /// Set this to connect with your LLM service.
  void Function(String prompt, CodeIntent intent)? onCodePromptReady;

  /// Called when the voice input flow completes (transcript ready).
  void Function(String transcript)? onTranscriptReady;

  /// Called when code is generated by the LLM.
  void Function(String code, CodeIntent intent)? onCodeGenerated;

  // ── Constructor ──────────────────────────────────────────────────────

  VoiceStateNotifier(this._service) : super(VoiceInputState.initial()) {
    _initListeners();
  }

  void _initListeners() {
    // Listen to voice state changes from the service.
    _stateSub = _service.onStateChange.listen(
      _onVoiceStateChanged,
      onError: (e) => _setError('State stream error: $e'),
    );

    // Listen to transcript updates.
    _transcriptSub = _service.onTranscriptUpdate.listen(
      _onTranscriptUpdate,
      onError: (e) => _setError('Transcript stream error: $e'),
    );
  }

  // ── Public API ───────────────────────────────────────────────────────

  /// Initialize the voice service (request permissions, setup engine).
  ///
  /// Must be called before using any voice features.
  /// Returns `true` if initialization succeeded.
  Future<bool> initialize() async {
    try {
      final available = await _service.initialize();
      state = state.copyWith(isInitialized: available);
      return available;
    } catch (e) {
      state = state.copyWith(
        isInitialized: false,
        voiceState: VoiceState.error,
        errorMessage: 'Initialization failed: $e',
      );
      return false;
    }
  }

  /// Start listening for voice input.
  ///
  /// Resets previous state and begins speech recognition.
  Future<void> startListening() async {
    if (!state.isInitialized) {
      final ok = await initialize();
      if (!ok) return;
    }

    // Reset previous transcript and intent.
    state = VoiceInputState(
      voiceState: VoiceState.listening,
      isInitialized: true,
      timestamp: DateTime.now(),
    );

    try {
      await _service.startListening();
    } catch (e) {
      _setError('Failed to start listening: $e');
    }
  }

  /// Stop listening and process the transcript.
  ///
  /// Analyzes intent and builds code prompt automatically.
  Future<void> stopListening() async {
    try {
      final transcript = await _service.stopListening();

      if (transcript.isEmpty) {
        state = state.copyWith(
          voiceState: VoiceState.idle,
          transcript: '',
          timestamp: DateTime.now(),
        );
        return;
      }

      // Analyze intent and build code prompt.
      final codeIntent = _service.analyzeIntent(transcript);
      final codePrompt = _service.buildCodePrompt(codeIntent);

      state = state.copyWith(
        voiceState: VoiceState.done,
        transcript: transcript,
        codeIntent: codeIntent,
        codePrompt: codePrompt,
        timestamp: DateTime.now(),
      );

      // Notify listeners.
      onTranscriptReady?.call(transcript);

      // Auto-submit if confidence is high enough.
      if (codeIntent.confidence > 0.6 && codeIntent.isCodeRelated) {
        onCodePromptReady?.call(codePrompt, codeIntent);
      }
    } catch (e) {
      _setError('Failed to process speech: $e');
    }
  }

  /// Cancel listening and discard results.
  Future<void> cancel() async {
    await _service.cancel();
    state = VoiceInputState(
      isInitialized: state.isInitialized,
      timestamp: DateTime.now(),
    );
  }

  /// Reset to idle state (clear transcript, keep initialization).
  void reset() {
    state = VoiceInputState(
      isInitialized: state.isInitialized,
      timestamp: DateTime.now(),
    );
  }

  /// Submit the current code prompt to LLM for generation.
  ///
  /// Call this when the user confirms they want to generate code
  /// from the current transcript.
  ///
  /// [generateFn] is an async function that calls the LLM and returns code.
  Future<void> submitToLLM(
    Future<String> Function(String prompt) generateFn,
  ) async {
    if (!state.hasCodeIntent || state.codePrompt == null) return;

    state = state.copyWith(
      isGeneratingCode: true,
      timestamp: DateTime.now(),
    );

    try {
      final code = await generateFn(state.codePrompt!);

      state = state.copyWith(
        isGeneratingCode: false,
        generatedCode: code,
        timestamp: DateTime.now(),
      );

      if (state.codeIntent != null) {
        onCodeGenerated?.call(code, state.codeIntent!);
      }
    } catch (e) {
      state = state.copyWith(
        isGeneratingCode: false,
        voiceState: VoiceState.error,
        errorMessage: 'Code generation failed: $e',
        timestamp: DateTime.now(),
      );
    }
  }

  /// Set the generated code directly (e.g. from an external LLM stream).
  void setGeneratedCode(String code) {
    state = state.copyWith(
      isGeneratingCode: false,
      generatedCode: code,
      timestamp: DateTime.now(),
    );
  }

  /// Update the transcript manually (e.g. user edits before submitting).
  void updateTranscript(String newTranscript) {
    state = state.copyWith(
      transcript: newTranscript,
      timestamp: DateTime.now(),
    );
  }

  // ── Internal Handlers ────────────────────────────────────────────────

  void _onVoiceStateChanged(VoiceState voiceState) {
    // Only update if state actually changed (avoid loops).
    if (state.voiceState != voiceState) {
      state = state.copyWith(
        voiceState: voiceState,
        timestamp: DateTime.now(),
      );
    }
  }

  void _onTranscriptUpdate(String transcript) {
    // Only update transcript - don't change state (still listening).
    state = state.copyWith(transcript: transcript);
  }

  void _setError(String message) {
    debugPrint('[VoiceStateNotifier] Error: $message');
    state = state.copyWith(
      voiceState: VoiceState.error,
      errorMessage: message,
      timestamp: DateTime.now(),
    );
  }

  // ── Cleanup ──────────────────────────────────────────────────────────

  @override
  void dispose() {
    _stateSub?.cancel();
    _transcriptSub?.cancel();
    _audioSub?.cancel();
    super.dispose();
  }
}
