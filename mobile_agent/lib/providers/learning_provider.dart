// lib/providers/learning_provider.dart
// Learning State Provider — Manages the Continuous Learning System state.
//
// Provides Riverpod-based state management for:
// - Feedback submission state (idle/submitting/submitted/error)
// - Learning progress and metrics
// - Learned user preferences display
// - Improvement trends and statistics
//
// Usage:
// ```dart
// // Watch learning state
// final learning = ref.watch(learningProvider);
// if (learning.isSubmitting) { showLoading(); }
//
// // Submit feedback
// await ref.read(learningProvider.notifier).submitFeedback(
//   interactionId: '...',
//   type: FeedbackType.thumbsUp,
//   ...
// );
//
// // View metrics
// final metrics = ref.watch(learningMetricsProvider);
// ```

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/code_similarity_service.dart';
import '../services/coding_prompts.dart';
import '../services/feedback_learning_service.dart';
import '../services/storage_service.dart';
import 'storage_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Learning State
// ═══════════════════════════════════════════════════════════════════════════

/// Immutable state representing the learning system's current condition.
///
/// Tracks feedback submission progress, learned preferences,
/// improvement metrics, and any errors.
class LearningState {
  /// Whether feedback is currently being submitted.
  final bool isSubmitting;

  /// Whether a learning cycle is currently running.
  final bool isLearning;

  /// The last submitted feedback entry (if any).
  final FeedbackEntry? lastFeedback;

  /// The learned user preferences.
  final UserPreferences? preferences;

  /// The latest learning report.
  final LearningReport? latestReport;

  /// Daily improvement metrics.
  final List<DailyMetric> improvementTrend;

  /// Overall success rate (0.0-1.0).
  final double? overallSuccessRate;

  /// Success rate broken down by task type.
  final Map<CodingTaskType, double> successByType;

  /// Error message, if any.
  final String? error;

  /// Status message for UI display.
  final String statusMessage;

  /// Whether the learning system has enough data to provide insights.
  final bool hasEnoughData;

  const LearningState({
    this.isSubmitting = false,
    this.isLearning = false,
    this.lastFeedback,
    this.preferences,
    this.latestReport,
    this.improvementTrend = const [],
    this.overallSuccessRate,
    this.successByType = const {},
    this.error,
    this.statusMessage = 'Ready',
    this.hasEnoughData = false,
  });

  /// Whether any learning operation is in progress.
  bool get isBusy => isSubmitting || isLearning;

  /// The number of feedback entries available.
  int get feedbackCount => latestReport?.totalInteractions ?? 0;

  /// Create a copy with some fields modified.
  LearningState copyWith({
    bool? isSubmitting,
    bool? isLearning,
    FeedbackEntry? lastFeedback,
    UserPreferences? preferences,
    LearningReport? latestReport,
    List<DailyMetric>? improvementTrend,
    double? overallSuccessRate,
    Map<CodingTaskType, double>? successByType,
    String? error,
    String? statusMessage,
    bool? hasEnoughData,
    bool clearError = false,
    bool clearReport = false,
  }) {
    return LearningState(
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isLearning: isLearning ?? this.isLearning,
      lastFeedback: lastFeedback ?? this.lastFeedback,
      preferences: preferences ?? this.preferences,
      latestReport: clearReport ? null : (latestReport ?? this.latestReport),
      improvementTrend: improvementTrend ?? this.improvementTrend,
      overallSuccessRate: overallSuccessRate ?? this.overallSuccessRate,
      successByType: successByType ?? this.successByType,
      error: clearError ? null : (error ?? this.error),
      statusMessage: statusMessage ?? this.statusMessage,
      hasEnoughData: hasEnoughData ?? this.hasEnoughData,
    );
  }

  @override
  String toString() {
    return 'LearningState('
        'submitting: $isSubmitting, '
        'learning: $isLearning, '
        'feedbackCount: $feedbackCount, '
        'status: $statusMessage)';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Learning Notifier
// ═══════════════════════════════════════════════════════════════════════════

/// Manages the learning system state and orchestrates feedback operations.
///
/// This notifier wraps [FeedbackLearningService] and exposes
/// learning functionality through Riverpod state management.
/// It handles feedback submission, learning cycles, preference
/// loading, and report generation.
class LearningNotifier extends StateNotifier<LearningState> {
  final Ref _ref;

  /// Lazy accessor for storage service.
  StorageService get _storage => _ref.read(storageServiceProvider);

  /// The feedback learning service (lazy-initialized).
  FeedbackLearningService? _feedbackService;

  LearningNotifier(this._ref) : super(const LearningState()) {
    _initializeService();
  }

  /// Initialize the feedback learning service.
  void _initializeService() {
    try {
      _feedbackService = FeedbackLearningService(_storage);
      _checkDataAvailability();
    } catch (e) {
      debugPrint('[LearningNotifier] Failed to initialize service: $e');
      state = state.copyWith(
        error: 'Failed to initialize learning service: $e',
        statusMessage: 'Initialization error',
      );
    }
  }

  /// Check if enough feedback data exists for learning.
  void _checkDataAvailability() {
    final hasEnough = _feedbackService?.hasEnoughData() ?? false;
    state = state.copyWith(hasEnoughData: hasEnough);
  }

  // ── Feedback Submission ────────────────────────────────────────────

  /// Submit user feedback on an AI response.
  ///
  /// [interactionId] unique identifier for the AI-user interaction.
  /// [type] the type of feedback (thumbs up, thumbs down, etc.).
  /// [originalPrompt] the user's original prompt.
  /// [aiResponse] the AI-generated response.
  /// [userEditedVersion] optional user-edited version of the code.
  /// [comment] optional user comment.
  Future<void> submitFeedback({
    required String interactionId,
    required FeedbackType type,
    required String originalPrompt,
    required String aiResponse,
    String? userEditedVersion,
    String? comment,
  }) async {
    if (_feedbackService == null) {
      state = state.copyWith(
        error: 'Learning service not initialized',
        statusMessage: 'Service unavailable',
      );
      return;
    }

    state = state.copyWith(
      isSubmitting: true,
      statusMessage: 'Submitting feedback...',
      clearError: true,
    );

    try {
      await _feedbackService!.recordFeedback(
        interactionId: interactionId,
        type: type,
        originalPrompt: originalPrompt,
        aiResponse: aiResponse,
        userEditedVersion: userEditedVersion,
        comment: comment,
      );

      // Build a local representation of the submitted feedback.
      final entry = FeedbackEntry(
        id: 'local_${DateTime.now().millisecondsSinceEpoch}',
        interactionId: interactionId,
        type: type,
        originalPrompt: originalPrompt,
        aiResponse: aiResponse,
        userEditedVersion: userEditedVersion,
        comment: comment,
        timestamp: DateTime.now(),
      );

      state = state.copyWith(
        isSubmitting: false,
        lastFeedback: entry,
        statusMessage: 'Feedback submitted: ${type.name}',
        hasEnoughData: _feedbackService!.hasEnoughData(),
      );

      // Refresh metrics after feedback.
      await refreshMetrics();
    } catch (e) {
      debugPrint('[LearningNotifier] Feedback submission failed: $e');
      state = state.copyWith(
        isSubmitting: false,
        error: 'Failed to submit feedback: $e',
        statusMessage: 'Submission failed',
      );
    }
  }

  /// Submit a simple thumbs-up feedback.
  ///
  /// [interactionId] the interaction being rated.
  Future<void> submitThumbsUp(String interactionId) async {
    await submitFeedback(
      interactionId: interactionId,
      type: FeedbackType.thumbsUp,
      originalPrompt: '',
      aiResponse: '',
    );
  }

  /// Submit a simple thumbs-down feedback.
  ///
  /// [interactionId] the interaction being rated.
  /// [comment] optional reason for the thumbs down.
  Future<void> submitThumbsDown(String interactionId, {String? comment}) async {
    await submitFeedback(
      interactionId: interactionId,
      type: FeedbackType.thumbsDown,
      originalPrompt: '',
      aiResponse: '',
      comment: comment,
    );
  }

  /// Submit feedback that the user accepted code without changes.
  ///
  /// [interactionId] the interaction being accepted.
  Future<void> submitAcceptance(String interactionId) async {
    if (_feedbackService == null) return;

    state = state.copyWith(isSubmitting: true);
    try {
      await _feedbackService!.recordAcceptance(interactionId);
      state = state.copyWith(
        isSubmitting: false,
        statusMessage: 'Code accepted',
        hasEnoughData: _feedbackService!.hasEnoughData(),
      );
      await refreshMetrics();
    } catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        error: 'Failed to record acceptance: $e',
      );
    }
  }

  /// Submit feedback that the user edited the AI-generated code.
  ///
  /// [interactionId] the interaction being edited.
  /// [originalCode] the AI-generated code.
  /// [editedCode] the user's edited version.
  Future<void> submitEdit({
    required String interactionId,
    required String originalCode,
    required String editedCode,
  }) async {
    if (_feedbackService == null) return;

    state = state.copyWith(
      isSubmitting: true,
      statusMessage: 'Analyzing edit...',
      clearError: true,
    );

    try {
      await _feedbackService!.recordEdit(
        interactionId: interactionId,
        originalCode: originalCode,
        editedCode: editedCode,
      );

      // Calculate similarity for display.
      final similarity = CodeSimilarityService.calculateSimilarity(
        originalCode,
        editedCode,
      );

      state = state.copyWith(
        isSubmitting: false,
        statusMessage:
            'Edit recorded (${(similarity * 100).toStringAsFixed(0)}% similar)',
        hasEnoughData: _feedbackService!.hasEnoughData(),
      );

      await refreshMetrics();
    } catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        error: 'Failed to record edit: $e',
        statusMessage: 'Edit recording failed',
      );
    }
  }

  // ── Learning & Preferences ─────────────────────────────────────────

  /// Trigger a manual learning cycle.
  ///
  /// Analyzes all feedback, updates preferences, and optimizes prompts.
  Future<void> triggerLearning() async {
    if (_feedbackService == null || !_feedbackService!.hasEnoughData()) {
      state = state.copyWith(
        statusMessage: 'Not enough data to learn yet',
      );
      return;
    }

    state = state.copyWith(
      isLearning: true,
      statusMessage: 'Learning from feedback...',
      clearError: true,
    );

    try {
      await _feedbackService!.triggerLearning();

      // Refresh preferences and report.
      await _loadPreferences();
      await _loadReport();

      state = state.copyWith(
        isLearning: false,
        statusMessage: 'Learning cycle completed',
      );
    } catch (e) {
      debugPrint('[LearningNotifier] Learning cycle failed: $e');
      state = state.copyWith(
        isLearning: false,
        error: 'Learning failed: $e',
        statusMessage: 'Learning failed',
      );
    }
  }

  /// Load learned preferences for the default user.
  Future<void> loadPreferences() async {
    await _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    if (_feedbackService == null) return;

    try {
      final prefs = await _feedbackService!.learnPreferences('default_user');
      state = state.copyWith(preferences: prefs);
    } catch (e) {
      debugPrint('[LearningNotifier] Failed to load preferences: $e');
    }
  }

  // ── Metrics & Reporting ────────────────────────────────────────────

  /// Refresh all learning metrics.
  ///
  /// Reloads success rates, improvement trends, and the latest report.
  Future<void> refreshMetrics() async {
    if (_feedbackService == null) return;

    try {
      // Refresh success rate.
      final successRate = await _feedbackService!.getSuccessRate();

      // Refresh success by type.
      final successByType = await _feedbackService!.getSuccessRateByType();

      // Refresh improvement trend.
      final trend = await _feedbackService!.getImprovementTrend(days: 30);

      state = state.copyWith(
        overallSuccessRate: successRate,
        successByType: successByType,
        improvementTrend: trend,
      );
    } catch (e) {
      debugPrint('[LearningNotifier] Failed to refresh metrics: $e');
    }
  }

  /// Generate and load a learning report.
  Future<void> generateReport() async {
    if (_feedbackService == null) return;

    state = state.copyWith(
      isLearning: true,
      statusMessage: 'Generating report...',
      clearError: true,
    );

    try {
      await _loadReport();
      state = state.copyWith(
        isLearning: false,
        statusMessage: 'Report generated',
      );
    } catch (e) {
      state = state.copyWith(
        isLearning: false,
        error: 'Failed to generate report: $e',
        statusMessage: 'Report generation failed',
      );
    }
  }

  Future<void> _loadReport() async {
    if (_feedbackService == null) return;

    final report = await _feedbackService!.generateReport();
    state = state.copyWith(latestReport: report);
  }

  // ── Utility ────────────────────────────────────────────────────────

  /// Get the personalized prompt modifier for the learned preferences.
  ///
  /// Returns an empty string if no preferences have been learned yet.
  String getPersonalizedPromptModifier() {
    final prefs = state.preferences;
    if (prefs == null || _feedbackService == null) return '';
    return _feedbackService!.getPersonalizedPromptModifier(prefs);
  }

  /// Get the optimized prompt for a task type.
  ///
  /// [taskType] the type of coding task.
  String getOptimizedPrompt(CodingTaskType taskType) {
    if (_feedbackService == null) return '';
    return _feedbackService!.getOptimizedPrompt(taskType);
  }

  /// Reset all learning data (use with caution).
  Future<void> resetLearningData() async {
    try {
      await _storage.removeSetting('last_learning_cycle');
      _feedbackService = FeedbackLearningService(_storage);

      state = const LearningState(
        statusMessage: 'Learning data reset',
        hasEnoughData: false,
      );

      debugPrint('[LearningNotifier] Learning data reset');
    } catch (e) {
      state = state.copyWith(
        error: 'Failed to reset learning data: $e',
        statusMessage: 'Reset failed',
      );
    }
  }

  @override
  void dispose() {
    _feedbackService = null;
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Providers
// ═══════════════════════════════════════════════════════════════════════════

/// Primary provider for the learning system state.
///
/// Provides access to feedback submission, learning cycles,
/// preferences, and metrics.
///
/// ```dart
/// // Watch state
/// final learning = ref.watch(learningProvider);
/// if (learning.isBusy) { showLoading(); }
///
/// // Submit feedback
/// await ref.read(learningProvider.notifier).submitThumbsUp('interaction_1');
///
/// // Trigger learning
/// await ref.read(learningProvider.notifier).triggerLearning();
/// ```
final learningProvider = StateNotifierProvider<LearningNotifier, LearningState>((ref) {
  return LearningNotifier(ref);
});

// ─── Derived Providers ─────────────────────────────────────────────

/// Whether the learning system is currently busy.
///
/// ```dart
/// final isBusy = ref.watch(learningBusyProvider);
/// if (isBusy) { showLoadingIndicator(); }
/// ```
final learningBusyProvider = Provider<bool>((ref) {
  return ref.watch(learningProvider).isBusy;
});

/// Whether the learning system has enough data.
///
/// ```dart
/// final hasData = ref.watch(learningHasDataProvider);
/// if (hasData) { showInsights(); }
/// ```
final learningHasDataProvider = Provider<bool>((ref) {
  return ref.watch(learningProvider).hasEnoughData;
});

/// The learned user preferences.
///
/// ```dart
/// final prefs = ref.watch(learnedPreferencesProvider);
/// if (prefs != null) { displayPreferences(prefs); }
/// ```
final learnedPreferencesProvider = Provider<UserPreferences?>((ref) {
  return ref.watch(learningProvider).preferences;
});

/// The overall success rate.
///
/// ```dart
/// final rate = ref.watch(successRateProvider);
/// Text('Success: ${(rate * 100).toStringAsFixed(0)}%');
/// ```
final successRateProvider = Provider<double>((ref) {
  return ref.watch(learningProvider).overallSuccessRate ?? 0.0;
});

/// The improvement trend (daily metrics).
///
/// ```dart
/// final trend = ref.watch(improvementTrendProvider);
/// LineChart(data: trend);
/// ```
final improvementTrendProvider = Provider<List<DailyMetric>>((ref) {
  return ref.watch(learningProvider).improvementTrend;
});

/// The latest learning report.
///
/// ```dart
/// final report = ref.watch(learningReportProvider);
/// if (report != null) { showReport(report); }
/// ```
final learningReportProvider = Provider<LearningReport?>((ref) {
  return ref.watch(learningProvider).latestReport;
});

/// Success rate broken down by task type.
///
/// ```dart
/// final byType = ref.watch(successByTypeProvider);
/// for (final entry in byType.entries) { ... }
/// ```
final successByTypeProvider = Provider<Map<CodingTaskType, double>>((ref) {
  return ref.watch(learningProvider).successByType;
});

/// The last submitted feedback entry.
///
/// ```dart
/// final feedback = ref.watch(lastFeedbackProvider);
/// if (feedback != null) { showThankYou(); }
/// ```
final lastFeedbackProvider = Provider<FeedbackEntry?>((ref) {
  return ref.watch(learningProvider).lastFeedback;
});

/// Learning status message for display.
///
/// ```dart
/// final status = ref.watch(learningStatusProvider);
/// Text(status);
/// ```
final learningStatusProvider = Provider<String>((ref) {
  return ref.watch(learningProvider).statusMessage;
});

/// Learning error message.
///
/// ```dart
/// final error = ref.watch(learningErrorProvider);
/// if (error != null) { showErrorSnackbar(error); }
/// ```
final learningErrorProvider = Provider<String?>((ref) {
  return ref.watch(learningProvider).error;
});

/// The personalized prompt modifier based on learned preferences.
///
/// ```dart
/// final modifier = ref.watch(personalizedPromptProvider);
/// if (modifier.isNotEmpty) { prependToPrompt(modifier); }
/// ```
final personalizedPromptProvider = Provider<String>((ref) {
  final prefs = ref.watch(learnedPreferencesProvider);
  if (prefs == null) return '';
  return prefs.toPromptContext();
});
