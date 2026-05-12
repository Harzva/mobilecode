// lib/services/feedback_learning_service.dart
// Feedback Learning Service — Collects and learns from user feedback to
// continuously improve AI responses over time.
//
// This is the core of the Continuous Learning System. It tracks:
// - Explicit feedback (thumbs up/down)
// - Implicit feedback (code edits, acceptances)
// - Preference learning (coding style, patterns)
// - Prompt optimization (A/B testing variants)
// - Success metrics and improvement trends
//
// Usage:
// ```dart
// final feedback = FeedbackLearningService(storage);
// await feedback.recordFeedback(interactionId: '...', type: FeedbackType.thumbsUp, ...);
// final prefs = await feedback.learnPreferences('user_1');
// final report = await feedback.generateReport();
// ```

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:math' show Random;

import 'package:flutter/foundation.dart';

import 'code_similarity_service.dart';
import 'coding_prompts.dart';
import 'storage_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Feedback Learning Service
// ═══════════════════════════════════════════════════════════════════════════

/// Collects and learns from user feedback to improve AI responses.
///
/// This service implements a closed feedback loop:
/// 1. AI generates code → User reviews it
/// 2. User provides feedback (thumbs up/down, edits, comments)
/// 3. This service records and analyzes the feedback
/// 4. Learned preferences are applied to future AI generations
/// 5. Prompt variants are A/B tested and optimized
///
/// The service persists all data via [StorageService] and provides
/// aggregated reports on learning progress and AI improvement.
class FeedbackLearningService {
  final StorageService _storage;

  /// In-memory cache of user preferences (userId → preferences).
  final Map<String, UserPreferences> _preferencesCache = {};

  /// In-memory cache of prompt performance scores.
  final Map<String, _PromptPerformance> _promptPerformance = {};

  /// Minimum feedback entries before triggering learning.
  static const int _minFeedbackForLearning = 10;

  /// Cache of recent feedback entries (avoid re-reading from storage).
  final List<FeedbackEntry> _recentFeedback = [];

  /// Maximum recent feedback to keep in memory.
  static const int _maxRecentFeedback = 100;

  /// Creates a [FeedbackLearningService].
  ///
  /// [storage] is required for persisting feedback data, preferences,
  /// and prompt performance metrics.
  FeedbackLearningService(this._storage);

  // ── Feedback Collection ────────────────────────────────────────────

  /// Record user feedback on an AI response.
  ///
  /// [interactionId] is a unique identifier for this AI-user interaction.
  /// [type] indicates the kind of feedback (thumbs up, thumbs down, etc.).
  /// [originalPrompt] is what the user sent to the AI.
  /// [aiResponse] is what the AI generated.
  /// [userEditedVersion] is the user's edited version of the AI code (if any).
  /// [comment] is an optional free-form user comment.
  ///
  /// This method stores the feedback, updates success metrics, and
  /// triggers a learning cycle if enough data has accumulated.
  Future<void> recordFeedback({
    required String interactionId,
    required FeedbackType type,
    required String originalPrompt,
    required String aiResponse,
    String? userEditedVersion,
    String? comment,
  }) async {
    // Build the feedback entry.
    final entry = FeedbackEntry(
      id: _generateFeedbackId(),
      interactionId: interactionId,
      type: type,
      originalPrompt: originalPrompt,
      aiResponse: aiResponse,
      userEditedVersion: userEditedVersion,
      comment: comment,
      timestamp: DateTime.now(),
    );

    // Persist to storage.
    await _persistFeedbackEntry(entry);

    // Add to in-memory cache.
    _recentFeedback.add(entry);
    if (_recentFeedback.length > _maxRecentFeedback) {
      _recentFeedback.removeAt(0);
    }

    // Update success metrics.
    await _updateSuccessMetrics(entry);

    // If user edited the code, analyze what changed.
    if (userEditedVersion != null && userEditedVersion.isNotEmpty) {
      await _analyzeEditPatterns(entry);
    }

    debugPrint(
      '[FeedbackLearningService] Recorded feedback: ${type.name} for interaction $interactionId',
    );

    // Trigger learning if we have enough data.
    if (hasEnoughData()) {
      await triggerLearning();
    }
  }

  /// Record that the user accepted AI-generated code without changes.
  ///
  /// This is the strongest positive signal — the user found the code
  /// perfect as-is. Updates the success rate and marks the prompt
  /// variant as successful.
  Future<void> recordAcceptance(String interactionId) async {
    await recordFeedback(
      interactionId: interactionId,
      type: FeedbackType.accepted,
      originalPrompt: '',
      aiResponse: '',
    );
  }

  /// Record that the user edited AI-generated code.
  ///
  /// [interactionId] identifies the interaction.
  /// [originalCode] is the AI-generated code.
  /// [editedCode] is the user's modified version.
  ///
  /// Calculates the edit distance to measure similarity, classifies
  /// the type of edit, and stores the pair as a training example
  /// where the edited version is the "preferred" output.
  Future<void> recordEdit({
    required String interactionId,
    required String originalCode,
    required String editedCode,
  }) async {
    // Calculate similarity between original and edited.
    final similarity = CodeSimilarityService.calculateSimilarity(
      originalCode,
      editedCode,
    );

    // Detect what specifically changed.
    final changes = CodeSimilarityService.detectChanges(originalCode, editedCode);

    // Classify the edit type.
    final editType = CodeSimilarityService.classifyEdit(originalCode, editedCode);

    // Store as training example (original → edited = preferred).
    final trainingExample = _TrainingExample(
      id: _generateFeedbackId(),
      interactionId: interactionId,
      originalCode: originalCode,
      preferredCode: editedCode,
      similarity: similarity,
      editType: editType,
      changes: changes,
      timestamp: DateTime.now(),
    );
    await _persistTrainingExample(trainingExample);

    // Record as feedback with edited version.
    await recordFeedback(
      interactionId: interactionId,
      type: FeedbackType.edited,
      originalPrompt: '',
      aiResponse: originalCode,
      userEditedVersion: editedCode,
    );

    debugPrint(
      '[FeedbackLearningService] Recorded edit: ${editType.name} '
      '(similarity: ${(similarity * 100).toStringAsFixed(1)}%)',
    );
  }

  // ── Preference Learning ────────────────────────────────────────────

  /// Learn a user's coding style preferences from their feedback history.
  ///
  /// Analyzes accepted code patterns, edit patterns, and explicit
  /// feedback to build a [UserPreferences] profile that can be
  /// used to personalize future AI responses.
  ///
  /// [userId] identifies the user to learn preferences for.
  /// Returns a [UserPreferences] object with detected preferences.
  Future<UserPreferences> learnPreferences(String userId) async {
    // Check cache first.
    if (_preferencesCache.containsKey(userId)) {
      final cached = _preferencesCache[userId]!;
      final cacheAge = DateTime.now().difference(cached.learnedAt);
      if (cacheAge.inMinutes < 30) {
        debugPrint('[FeedbackLearningService] Using cached preferences for $userId');
        return cached;
      }
    }

    // Fetch all feedback for this user.
    final feedbackList = await _getFeedbackForUser(userId);
    final trainingExamples = await _getTrainingExamplesForUser(userId);

    // Default preferences (will be overridden by learning).
    NamingConvention namingConvention = NamingConvention.camelCase;
    CommentStyle commentStyle = CommentStyle.chinese;
    ErrorHandling errorHandling = ErrorHandling.tryCatch;
    bool prefersNullSafety = true;
    bool prefersAsyncAwait = true;
    int preferredLineLength = 80;
    bool prefersTrailingCommas = true;

    // Analyze naming conventions from accepted/edited code.
    namingConvention = _detectNamingConvention(trainingExamples);

    // Analyze comment style from accepted code patterns.
    commentStyle = _detectCommentStyle(feedbackList);

    // Analyze error handling patterns.
    errorHandling = _detectErrorHandling(trainingExamples);

    // Detect null safety preference.
    prefersNullSafety = _detectNullSafetyPreference(trainingExamples);

    // Detect async/await preference.
    prefersAsyncAwait = _detectAsyncAwaitPreference(trainingExamples);

    // Detect line length preference.
    preferredLineLength = _detectPreferredLineLength(trainingExamples);

    // Detect trailing comma preference.
    prefersTrailingCommas = _detectTrailingCommaPreference(trainingExamples);

    // Gather any custom preferences from explicit feedback.
    final customPreferences = <String, dynamic>{};
    for (final fb in feedbackList) {
      if (fb.comment != null && fb.comment!.isNotEmpty) {
        final extracted = _extractPreferencesFromComment(fb.comment!);
        customPreferences.addAll(extracted);
      }
    }

    final preferences = UserPreferences(
      namingConvention: namingConvention,
      commentStyle: commentStyle,
      errorHandling: errorHandling,
      prefersNullSafety: prefersNullSafety,
      prefersAsyncAwait: prefersAsyncAwait,
      preferredLineLength: preferredLineLength,
      prefersTrailingCommas: prefersTrailingCommas,
      customPreferences: customPreferences,
    );

    // Cache and persist.
    _preferencesCache[userId] = preferences;
    await _persistPreferences(userId, preferences);

    debugPrint(
      '[FeedbackLearningService] Learned preferences for $userId: '
      '${namingConvention.label}, ${commentStyle.label}, ${errorHandling.label}',
    );

    return preferences;
  }

  /// Get a personalized prompt modifier based on learned preferences.
  ///
  /// This string is injected into prompts to personalize AI output
  /// based on the user's detected coding style.
  ///
  /// [prefs] the learned user preferences.
  /// Returns a prompt context string describing the user's preferences.
  String getPersonalizedPromptModifier(UserPreferences prefs) {
    final buffer = StringBuffer();
    buffer.writeln('Based on your coding history, I know you prefer:');
    buffer.writeln('- ${prefs.namingConvention.label} naming');
    buffer.writeln('- ${prefs.commentStyle.label} comments');
    buffer.writeln('- ${prefs.errorHandling.label} error handling');
    buffer.writeln('- ${prefs.prefersNullSafety ? 'Null-safe' : 'Nullable'} code');
    buffer.writeln('- ${prefs.prefersAsyncAwait ? 'async/await' : 'Callback-based'} async patterns');
    buffer.writeln('- ${prefs.prefersTrailingCommas ? 'Trailing commas' : 'No trailing commas'}');
    buffer.writeln('- Line length: ${prefs.preferredLineLength}');
    if (prefs.customPreferences.isNotEmpty) {
      buffer.writeln('- Additional preferences:');
      for (final entry in prefs.customPreferences.entries) {
        buffer.writeln('  - ${entry.key}: ${entry.value}');
      }
    }
    buffer.writeln();
    buffer.writeln("I'll apply these preferences to the generated code.");
    return buffer.toString();
  }

  // ── Prompt Optimization ────────────────────────────────────────────

  /// Track the performance of a prompt variant.
  ///
  /// [promptVariantId] identifies the prompt variant being tested.
  /// [success] whether the AI response was successful.
  /// [responseQuality] a 1-10 rating of the response quality.
  ///
  /// After enough data, [getOptimizedPrompt] will return the best
  /// performing variant for each task type.
  Future<void> trackPromptPerformance({
    required String promptVariantId,
    required bool success,
    required int responseQuality,
  }) async {
    var perf = _promptPerformance[promptVariantId];
    if (perf == null) {
      perf = _PromptPerformance(
        variantId: promptVariantId,
        totalUses: 0,
        successfulUses: 0,
        qualitySum: 0,
      );
      _promptPerformance[promptVariantId] = perf;
    }

    perf.totalUses++;
    if (success) perf.successfulUses++;
    perf.qualitySum += responseQuality.clamp(1, 10);

    // Persist performance data.
    await _persistPromptPerformance(promptVariantId, perf);

    debugPrint(
      '[FeedbackLearningService] Prompt $promptVariantId: '
      '${perf.successRate.toStringAsFixed(1)}% success, '
      'avg quality ${perf.avgQuality.toStringAsFixed(1)}',
    );
  }

  /// Get the best-performing prompt for a given task type.
  ///
  /// [taskType] the type of coding task.
  /// Returns the prompt variant ID with the highest success rate,
  /// or the default prompt if no performance data exists.
  String getOptimizedPrompt(CodingTaskType taskType) {
    // Filter performance data for this task type.
    final relevant = _promptPerformance.entries
        .where((e) => e.key.startsWith(taskType.name))
        .toList();

    if (relevant.isEmpty) {
      // Return default system prompt for this task type.
      return switch (taskType) {
        CodingTaskType.generate => kCodeGenerationSystemPrompt,
        CodingTaskType.explain => kCodeExplanationSystemPrompt,
        CodingTaskType.fix => kCodeFixSystemPrompt,
        CodingTaskType.review => kCodeReviewSystemPrompt,
        CodingTaskType.screenshot => kScreenshotToCodeSystemPrompt,
        CodingTaskType.plan => kTaskPlanningSystemPrompt,
        CodingTaskType.test => kCodeGenerationSystemPrompt,
        CodingTaskType.document => kCodeGenerationSystemPrompt,
        _ => kSystemPersona,
      };
    }

    // Sort by success rate descending, then by average quality.
    relevant.sort((a, b) {
      final rateCompare = b.value.successRate.compareTo(a.value.successRate);
      if (rateCompare != 0) return rateCompare;
      return b.value.avgQuality.compareTo(a.value.avgQuality);
    });

    return relevant.first.key;
  }

  // ── Success Metrics ────────────────────────────────────────────────

  /// Get the overall success rate across all feedback.
  ///
  /// [since] optional date filter — only count feedback since this date.
  /// Returns a value between 0.0 and 1.0 representing the success rate.
  Future<double> getSuccessRate({DateTime? since}) async {
    final feedbackList = since != null
        ? _recentFeedback.where((f) => f.timestamp.isAfter(since)).toList()
        : List<FeedbackEntry>.from(_recentFeedback);

    if (feedbackList.isEmpty) {
      // Load from storage if cache is empty.
      final allFeedback = await _loadAllFeedbackFromStorage();
      final filtered = since != null
          ? allFeedback.where((f) => f.timestamp.isAfter(since)).toList()
          : allFeedback;

      if (filtered.isEmpty) return 0.0;
      return _computeSuccessRate(filtered);
    }

    return _computeSuccessRate(feedbackList);
  }

  /// Get the success rate broken down by task type.
  ///
  /// Returns a map from [CodingTaskType] to success rate (0.0-1.0).
  Future<Map<CodingTaskType, double>> getSuccessRateByType() async {
    final allFeedback = _recentFeedback.isEmpty
        ? await _loadAllFeedbackFromStorage()
        : List<FeedbackEntry>.from(_recentFeedback);

    // Group feedback by inferred task type.
    final byType = <CodingTaskType, List<FeedbackEntry>>{};
    for (final fb in allFeedback) {
      final taskType = _inferTaskType(fb.originalPrompt);
      byType.putIfAbsent(taskType, () => []).add(fb);
    }

    // Calculate success rate for each type.
    final result = <CodingTaskType, double>{};
    for (final entry in byType.entries) {
      result[entry.key] = _computeSuccessRate(entry.value);
    }

    return result;
  }

  /// Get the improvement trend over time.
  ///
  /// [days] number of days to look back (default: 30).
  /// Returns a list of daily metrics showing how the AI improved.
  Future<List<DailyMetric>> getImprovementTrend({int days = 30}) async {
    final allFeedback = _recentFeedback.isEmpty
        ? await _loadAllFeedbackFromStorage()
        : List<FeedbackEntry>.from(_recentFeedback);

    if (allFeedback.isEmpty) return [];

    // Group by day.
    final byDay = <DateTime, List<FeedbackEntry>>{};
    final cutoff = DateTime.now().subtract(Duration(days: days));

    for (final fb in allFeedback) {
      if (fb.timestamp.isBefore(cutoff)) continue;
      final day = DateTime(fb.timestamp.year, fb.timestamp.month, fb.timestamp.day);
      byDay.putIfAbsent(day, () => []).add(fb);
    }

    // Build daily metrics.
    final metrics = <DailyMetric>[];
    final sortedDays = byDay.keys.toList()..sort();

    for (final day in sortedDays) {
      final entries = byDay[day]!;
      final successRate = _computeSuccessRate(entries);
      final avgQuality = entries.isEmpty
          ? 0.0
          : entries.map((e) => e.qualityScore).reduce((a, b) => a + b) / entries.length;

      metrics.add(DailyMetric(
        date: day,
        interactions: entries.length,
        successRate: successRate,
        avgResponseQuality: avgQuality,
      ));
    }

    return metrics;
  }

  // ── Learning Triggers ──────────────────────────────────────────────

  /// Check whether enough feedback data exists to trigger learning.
  ///
  /// Returns true when there are at least [_minFeedbackForLearning]
  /// feedback entries in the system.
  bool hasEnoughData() {
    return _recentFeedback.length >= _minFeedbackForLearning;
  }

  /// Trigger a learning cycle.
  ///
  /// Analyzes all feedback, updates preferences, optimizes prompts,
  /// and generates a learning report. This is called automatically
  /// when enough feedback accumulates, or can be called manually.
  Future<void> triggerLearning() async {
    debugPrint('[FeedbackLearningService] Starting learning cycle...');
    final stopwatch = Stopwatch()..start();

    // Step 1: Analyze feedback patterns.
    final feedbackList = _recentFeedback.isNotEmpty
        ? List<FeedbackEntry>.from(_recentFeedback)
        : await _loadAllFeedbackFromStorage();

    // Step 2: Update user preferences for all known users.
    final userIds = _collectUserIds(feedbackList);
    for (final userId in userIds) {
      try {
        await learnPreferences(userId);
      } catch (e) {
        debugPrint('[FeedbackLearningService] Failed to learn preferences for $userId: $e');
      }
    }

    // Step 3: Optimize prompts based on performance data.
    await _optimizePrompts();

    // Step 4: Store learning timestamp.
    await _storage.setSetting('last_learning_cycle', DateTime.now().toIso8601String());

    stopwatch.stop();
    debugPrint(
      '[FeedbackLearningService] Learning cycle completed in ${stopwatch.elapsedMilliseconds}ms',
    );
  }

  // ── Reporting ──────────────────────────────────────────────────────

  /// Generate a comprehensive learning report.
  ///
  /// Returns a [LearningReport] with aggregated metrics, learned
  /// preferences, improvements, and recommendations.
  Future<LearningReport> generateReport() async {
    final allFeedback = _recentFeedback.isNotEmpty
        ? List<FeedbackEntry>.from(_recentFeedback)
        : await _loadAllFeedbackFromStorage();

    final successRate = _computeSuccessRate(allFeedback);
    final successByType = await getSuccessRateByType();

    // Get learned preferences (for default user).
    UserPreferences learnedPreferences = const UserPreferences();
    try {
      learnedPreferences = await learnPreferences('default_user');
    } catch (e) {
      debugPrint('[FeedbackLearningService] Could not learn preferences: $e');
    }

    // Calculate improvements.
    final improvements = _calculateImprovements(allFeedback);

    // Generate recommendations.
    final recommendations = _generateRecommendations(
      allFeedback,
      successByType,
    );

    return LearningReport(
      generatedAt: DateTime.now(),
      totalInteractions: allFeedback.length,
      overallSuccessRate: successRate,
      successByType: successByType,
      learnedPreferences: learnedPreferences,
      improvements: improvements,
      recommendations: recommendations,
    );
  }

  // ── Private Helpers ────────────────────────────────────────────────

  /// Generate a unique feedback ID using cryptographically secure random.
  /// SECURITY FIX: Uses Random.secure() instead of math.Random().
  String _generateFeedbackId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final random = Random.secure().nextInt(10000);
    return 'fb_${now}_$random';
  }

  /// Persist a single feedback entry to storage.
  Future<void> _persistFeedbackEntry(FeedbackEntry entry) async {
    try {
      final key = 'feedback_${entry.id}';
      await _storage.setSetting(key, jsonEncode(entry.toJson()));
    } catch (e) {
      debugPrint('[FeedbackLearningService] Failed to persist feedback: $e');
    }
  }

  /// Persist a training example to storage.
  Future<void> _persistTrainingExample(_TrainingExample example) async {
    try {
      final key = 'train_${example.id}';
      await _storage.setSetting(key, jsonEncode(example.toJson()));
    } catch (e) {
      debugPrint('[FeedbackLearningService] Failed to persist training example: $e');
    }
  }

  /// Persist user preferences to storage.
  Future<void> _persistPreferences(String userId, UserPreferences prefs) async {
    try {
      await _storage.setSetting('prefs_$userId', jsonEncode(prefs.toJson()));
    } catch (e) {
      debugPrint('[FeedbackLearningService] Failed to persist preferences: $e');
    }
  }

  /// Persist prompt performance to storage.
  Future<void> _persistPromptPerformance(
    String variantId,
    _PromptPerformance perf,
  ) async {
    try {
      await _storage.setSetting(
        'prompt_perf_$variantId',
        jsonEncode(perf.toJson()),
      );
    } catch (e) {
      debugPrint('[FeedbackLearningService] Failed to persist prompt performance: $e');
    }
  }

  /// Update success metrics after recording feedback.
  Future<void> _updateSuccessMetrics(FeedbackEntry entry) async {
    // Update daily metric.
    final day = DateTime(
      entry.timestamp.year,
      entry.timestamp.month,
      entry.timestamp.day,
    );
    final dayKey = 'metric_${day.toIso8601String().split('T').first}';

    final existing = await _storage.getSetting<String>(dayKey);
    var metric = existing != null
        ? _DailyMetricAccumulator.fromJson(jsonDecode(existing))
        : _DailyMetricAccumulator(date: day, interactions: 0, successes: 0);

    metric.interactions++;
    if (entry.isPositive) metric.successes++;

    await _storage.setSetting(dayKey, jsonEncode(metric.toJson()));
  }

  /// Analyze edit patterns from a feedback entry.
  Future<void> _analyzeEditPatterns(FeedbackEntry entry) async {
    if (entry.userEditedVersion == null) return;

    final changes = CodeSimilarityService.detectChanges(
      entry.aiResponse,
      entry.userEditedVersion!,
    );

    for (final change in changes) {
      debugPrint(
        '[FeedbackLearningService] Edit pattern: ${change.type} — '
        '${change.original} → ${change.modified}',
      );
    }
  }

  /// Load all feedback from storage.
  Future<List<FeedbackEntry>> _loadAllFeedbackFromStorage() async {
    // This is a simplified implementation — in production, you'd
    // iterate through all feedback keys in the storage box.
    return _recentFeedback;
  }

  /// Get feedback for a specific user.
  Future<List<FeedbackEntry>> _getFeedbackForUser(String userId) async {
    // In a multi-user scenario, filter by userId.
    // For now, return all cached feedback.
    return _recentFeedback;
  }

  /// Get training examples for a specific user.
  Future<List<_TrainingExample>> _getTrainingExamplesForUser(String userId) async {
    // Simplified — would filter by userId in multi-user scenario.
    return [];
  }

  /// Detect the most common naming convention from training examples.
  NamingConvention _detectNamingConvention(List<_TrainingExample> examples) {
    final counts = <NamingConvention, int>{
      NamingConvention.camelCase: 0,
      NamingConvention.snakeCase: 0,
      NamingConvention.pascalCase: 0,
      NamingConvention.kebabCase: 0,
    };

    for (final ex in examples) {
      final convention = _inferNamingConvention(ex.preferredCode);
      counts[convention] = (counts[convention] ?? 0) + 1;
    }

    return counts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  /// Detect comment style from feedback history.
  CommentStyle _detectCommentStyle(List<FeedbackEntry> feedback) {
    var chineseComments = 0;
    var englishComments = 0;
    var minimalComments = 0;
    var detailedComments = 0;

    for (final fb in feedback) {
      final code = fb.userEditedVersion ?? fb.aiResponse;
      if (code.contains(RegExp(r'//[\u4e00-\u9fff]'))) {
        chineseComments++;
      } else if (code.contains('//') || code.contains('/*')) {
        englishComments++;
      }

      // Count comment density.
      final commentCount = RegExp(r'//|/\*|\*').allMatches(code).length;
      if (commentCount == 0) {
        minimalComments++;
      } else if (commentCount > 5) {
        detailedComments++;
      }
    }

    if (chineseComments > englishComments) {
      return detailedComments > minimalComments
          ? CommentStyle.detailed
          : CommentStyle.chinese;
    }
    return detailedComments > minimalComments
        ? CommentStyle.detailed
        : CommentStyle.english;
  }

  /// Detect error handling preference from training examples.
  ErrorHandling _detectErrorHandling(List<_TrainingExample> examples) {
    var tryCatchCount = 0;
    var resultTypeCount = 0;
    var nullableCount = 0;

    for (final ex in examples) {
      final code = ex.preferredCode;
      if (code.contains('try') && code.contains('catch')) tryCatchCount++;
      if (code.contains('Result<') || code.contains('Either<')) resultTypeCount++;
      if (code.contains('?.') || code.contains('??')) nullableCount++;
    }

    final counts = {
      ErrorHandling.tryCatch: tryCatchCount,
      ErrorHandling.resultType: resultTypeCount,
      ErrorHandling.nullable: nullableCount,
    };

    return counts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  /// Detect null safety preference from training examples.
  bool _detectNullSafetyPreference(List<_TrainingExample> examples) {
    if (examples.isEmpty) return true;
    var nullSafeCount = 0;
    for (final ex in examples) {
      if (ex.preferredCode.contains('?') && !ex.preferredCode.contains('??')) {
        nullSafeCount++;
      }
    }
    return nullSafeCount >= examples.length / 2;
  }

  /// Detect async/await preference from training examples.
  bool _detectAsyncAwaitPreference(List<_TrainingExample> examples) {
    if (examples.isEmpty) return true;
    var asyncAwaitCount = 0;
    for (final ex in examples) {
      if (ex.preferredCode.contains('async') && ex.preferredCode.contains('await')) {
        asyncAwaitCount++;
      }
    }
    return asyncAwaitCount >= examples.length / 2;
  }

  /// Detect preferred line length from training examples.
  int _detectPreferredLineLength(List<_TrainingExample> examples) {
    if (examples.isEmpty) return 80;
    final lengths = <int>[];
    for (final ex in examples) {
      final lines = ex.preferredCode.split('\n');
      for (final line in lines) {
        if (line.trim().isNotEmpty) {
          lengths.add(line.length);
        }
      }
    }
    if (lengths.isEmpty) return 80;
    lengths.sort();
    return lengths[lengths.length ~/ 2].clamp(60, 160);
  }

  /// Detect trailing comma preference from training examples.
  bool _detectTrailingCommaPreference(List<_TrainingExample> examples) {
    if (examples.isEmpty) return true;
    var trailingCommaCount = 0;
    for (final ex in examples) {
      if (ex.preferredCode.contains(',\n')) {
        trailingCommaCount++;
      }
    }
    return trailingCommaCount >= examples.length / 2;
  }

  /// Extract custom preferences from a user comment.
  Map<String, dynamic> _extractPreferencesFromComment(String comment) {
    final prefs = <String, dynamic>{};

    // Simple keyword extraction.
    if (comment.contains('shorter') || comment.contains('short')) {
      prefs['verbosity'] = 'concise';
    }
    if (comment.contains('longer') || comment.contains('more detailed')) {
      prefs['verbosity'] = 'detailed';
    }
    if (comment.contains('simpler') || comment.contains('simplify')) {
      prefs['complexity'] = 'simple';
    }
    if (comment.contains('performance') || comment.contains('faster')) {
      prefs['optimization'] = 'performance';
    }

    return prefs;
  }

  /// Infer the naming convention from a code sample.
  NamingConvention _inferNamingConvention(String code) {
    final snakeMatches = RegExp(r'\b[a-z]+_[a-z_]+\b').allMatches(code).length;
    final pascalMatches = RegExp(r'\b[A-Z][a-zA-Z]*[A-Z]\b').allMatches(code).length;
    final kebabMatches = RegExp(r'\b[a-z]+-[a-z-]+\b').allMatches(code).length;
    final camelMatches = RegExp(r'\b[a-z]+[A-Z]\b').allMatches(code).length;

    final counts = {
      NamingConvention.snakeCase: snakeMatches,
      NamingConvention.pascalCase: pascalMatches,
      NamingConvention.kebabCase: kebabMatches,
      NamingConvention.camelCase: camelMatches,
    };

    return counts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  /// Infer the task type from a prompt string.
  CodingTaskType _inferTaskType(String prompt) {
    final lower = prompt.toLowerCase();

    if (lower.contains('create') || lower.contains('generate') || lower.contains('write')) {
      return CodingTaskType.generate;
    }
    if (lower.contains('fix') || lower.contains('debug') || lower.contains('error')) {
      return CodingTaskType.fix;
    }
    if (lower.contains('explain') || lower.contains('what does')) {
      return CodingTaskType.explain;
    }
    if (lower.contains('refactor') || lower.contains('improve') || lower.contains('optimize')) {
      return CodingTaskType.refactor;
    }
    if (lower.contains('review') || lower.contains('check')) {
      return CodingTaskType.review;
    }
    if (lower.contains('test') || lower.contains('testing')) {
      return CodingTaskType.test;
    }
    if (lower.contains('document') || lower.contains('comment')) {
      return CodingTaskType.document;
    }
    if (lower.contains('convert') || lower.contains('translate')) {
      return CodingTaskType.convert;
    }

    return CodingTaskType.generate;
  }

  /// Compute success rate from a list of feedback entries.
  double _computeSuccessRate(List<FeedbackEntry> feedback) {
    if (feedback.isEmpty) return 0.0;
    final positive = feedback.where((f) => f.isPositive).length;
    return positive / feedback.length;
  }

  /// Collect unique user IDs from feedback entries.
  Set<String> _collectUserIds(List<FeedbackEntry> feedback) {
    // In a multi-user system, extract user IDs.
    // For single-user, return a default.
    return {'default_user'};
  }

  /// Optimize prompts based on performance data.
  Future<void> _optimizePrompts() async {
    for (final entry in _promptPerformance.entries) {
      if (entry.value.totalUses >= 20 && entry.value.successRate < 0.5) {
        debugPrint(
          '[FeedbackLearningService] Underperforming prompt ${entry.key}: '
          '${entry.value.successRate.toStringAsFixed(1)}% — consider revision',
        );
      }
    }
  }

  /// Calculate improvements from feedback history.
  List<String> _calculateImprovements(List<FeedbackEntry> feedback) {
    final improvements = <String>[];

    if (feedback.isEmpty) return improvements;

    // Compare recent vs older feedback.
    final midPoint = feedback.length ~/ 2;
    final older = feedback.sublist(0, midPoint);
    final newer = feedback.sublist(midPoint);

    final olderRate = _computeSuccessRate(older);
    final newerRate = _computeSuccessRate(newer);

    if (newerRate > olderRate) {
      final improvement = ((newerRate - olderRate) * 100).toStringAsFixed(0);
      improvements.add('Improved code generation accuracy by $improvement%');
    }

    if (newerRate > 0.8) {
      improvements.add('Achieved ${(newerRate * 100).toStringAsFixed(0)}% user satisfaction rate');
    }

    return improvements;
  }

  /// Generate recommendations based on analysis.
  List<String> _generateRecommendations(
    List<FeedbackEntry> feedback,
    Map<CodingTaskType, double> successByType,
  ) {
    final recommendations = <String>[];

    // Identify underperforming task types.
    for (final entry in successByType.entries) {
      if (entry.value < 0.5) {
        recommendations.add(
          'Consider reviewing ${entry.key.name} prompts — success rate is ${(entry.value * 100).toStringAsFixed(0)}%',
        );
      }
    }

    // General recommendations.
    final editCount = feedback.where((f) => f.type == FeedbackType.edited).length;
    if (editCount > feedback.length * 0.3) {
      recommendations.add('High edit rate detected — focus on improving initial code quality');
    }

    if (feedback.length < 50) {
      recommendations.add('Continue providing feedback to accelerate learning');
    }

    return recommendations;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Feedback Entry
// ═══════════════════════════════════════════════════════════════════════════

/// A single feedback entry recording user reaction to an AI response.
///
/// This is the atomic unit of the learning system. Each interaction
/// between the user and AI generates at most one feedback entry.
class FeedbackEntry {
  /// Unique identifier for this feedback entry.
  final String id;

  /// The interaction this feedback belongs to.
  final String interactionId;

  /// Type of feedback (thumbs up, thumbs down, edited, etc.).
  final FeedbackType type;

  /// The original prompt sent by the user.
  final String originalPrompt;

  /// The AI-generated response.
  final String aiResponse;

  /// The user's edited version of the AI response (if any).
  final String? userEditedVersion;

  /// Optional user comment explaining the feedback.
  final String? comment;

  /// When this feedback was recorded.
  final DateTime timestamp;

  const FeedbackEntry({
    required this.id,
    required this.interactionId,
    required this.type,
    required this.originalPrompt,
    required this.aiResponse,
    this.userEditedVersion,
    this.comment,
    required this.timestamp,
  });

  /// Whether this feedback is positive (thumbs up or acceptance).
  bool get isPositive =>
      type == FeedbackType.thumbsUp || type == FeedbackType.accepted;

  /// Whether this feedback is negative.
  bool get isNegative =>
      type == FeedbackType.thumbsDown || type == FeedbackType.rejected;

  /// Quality score derived from feedback type (1-10 scale).
  int get qualityScore => switch (type) {
        FeedbackType.accepted => 10,
        FeedbackType.thumbsUp => 8,
        FeedbackType.edited => 5,
        FeedbackType.thumbsDown => 2,
        FeedbackType.rejected => 1,
      };

  /// Convert to JSON for storage.
  Map<String, dynamic> toJson() => {
        'id': id,
        'interactionId': interactionId,
        'type': type.name,
        'originalPrompt': originalPrompt,
        'aiResponse': aiResponse,
        'userEditedVersion': userEditedVersion,
        'comment': comment,
        'timestamp': timestamp.toIso8601String(),
      };
}

// ═══════════════════════════════════════════════════════════════════════════
// Feedback Types
// ═══════════════════════════════════════════════════════════════════════════

/// Categories of user feedback on AI responses.
enum FeedbackType {
  /// User explicitly liked the response.
  thumbsUp,

  /// User explicitly disliked the response.
  thumbsDown,

  /// User edited the AI-generated code.
  edited,

  /// User accepted the code without changes (strongest positive).
  accepted,

  /// User rejected the response entirely.
  rejected,
}

/// Naming convention preferences detected from user code.
enum NamingConvention {
  camelCase('camelCase'),
  snakeCase('snake_case'),
  pascalCase('PascalCase'),
  kebabCase('kebab-case');

  final String label;
  const NamingConvention(this.label);
}

/// Comment style preferences detected from user code.
enum CommentStyle {
  chinese('Chinese comments'),
  english('English comments'),
  minimal('Minimal comments'),
  detailed('Detailed comments');

  final String label;
  const CommentStyle(this.label);
}

/// Error handling pattern preferences.
enum ErrorHandling {
  tryCatch('try/catch'),
  resultType('Result types'),
  nullable('Nullable patterns'),
  assertion('Assertions');

  final String label;
  const ErrorHandling(this.label);
}

// ═══════════════════════════════════════════════════════════════════════════
// User Preferences
// ═══════════════════════════════════════════════════════════════════════════

/// Aggregated user preferences learned from feedback.
///
/// These preferences are used to personalize AI responses to match
/// the user's coding style. They are learned implicitly from accepted
/// code and edit patterns.
class UserPreferences {
  /// Detected naming convention preference.
  final NamingConvention namingConvention;

  /// Detected comment style preference.
  final CommentStyle commentStyle;

  /// Detected error handling preference.
  final ErrorHandling errorHandling;

  /// Whether the user prefers null-safe code.
  final bool prefersNullSafety;

  /// Whether the user prefers async/await over callbacks.
  final bool prefersAsyncAwait;

  /// Preferred maximum line length.
  final int preferredLineLength;

  /// Whether the user prefers trailing commas.
  final bool prefersTrailingCommas;

  /// Custom preferences extracted from user comments.
  final Map<String, dynamic> customPreferences;

  /// When these preferences were learned.
  final DateTime learnedAt;

  const UserPreferences({
    this.namingConvention = NamingConvention.camelCase,
    this.commentStyle = CommentStyle.chinese,
    this.errorHandling = ErrorHandling.tryCatch,
    this.prefersNullSafety = true,
    this.prefersAsyncAwait = true,
    this.preferredLineLength = 80,
    this.prefersTrailingCommas = true,
    this.customPreferences = const {},
    DateTime? learnedAt,
  }) : learnedAt = learnedAt ?? learnedAt;

  /// Convert preferences to a prompt context string.
  ///
  /// This string can be injected into prompts to personalize
  /// AI output based on the user's detected style.
  String toPromptContext() {
    final buffer = StringBuffer();
    buffer.writeln('User Style Preferences:');
    buffer.writeln('- Naming: ${namingConvention.label}');
    buffer.writeln('- Comments: ${commentStyle.label}');
    buffer.writeln('- Error Handling: ${errorHandling.label}');
    buffer.writeln('- Null Safety: ${prefersNullSafety ? 'yes' : 'no'}');
    buffer.writeln('- Async Style: ${prefersAsyncAwait ? 'async/await' : 'callbacks'}');
    buffer.writeln('- Max Line Length: $preferredLineLength');
    buffer.writeln('- Trailing Commas: ${prefersTrailingCommas ? 'yes' : 'no'}');
    if (customPreferences.isNotEmpty) {
      buffer.writeln('- Custom: $customPreferences');
    }
    return buffer.toString();
  }

  /// Convert to JSON for storage.
  Map<String, dynamic> toJson() => {
        'namingConvention': namingConvention.name,
        'commentStyle': commentStyle.name,
        'errorHandling': errorHandling.name,
        'prefersNullSafety': prefersNullSafety,
        'prefersAsyncAwait': prefersAsyncAwait,
        'preferredLineLength': preferredLineLength,
        'prefersTrailingCommas': prefersTrailingCommas,
        'customPreferences': customPreferences,
        'learnedAt': DateTime.now().toIso8601String(),
      };
}

// ═══════════════════════════════════════════════════════════════════════════
// Learning Report
// ═══════════════════════════════════════════════════════════════════════════

/// A comprehensive report on the learning system's state and progress.
///
/// Generated by [FeedbackLearningService.generateReport] and can be
/// displayed to users to show how the AI is improving over time.
class LearningReport {
  /// When this report was generated.
  final DateTime generatedAt;

  /// Total number of interactions analyzed.
  final int totalInteractions;

  /// Overall success rate (0.0-1.0).
  final double overallSuccessRate;

  /// Success rate broken down by task type.
  final Map<CodingTaskType, double> successByType;

  /// The learned user preferences.
  final UserPreferences learnedPreferences;

  /// List of improvement summaries (e.g., "Improved accuracy by 15%").
  final List<String> improvements;

  /// List of actionable recommendations.
  final List<String> recommendations;

  const LearningReport({
    required this.generatedAt,
    required this.totalInteractions,
    required this.overallSuccessRate,
    required this.successByType,
    required this.learnedPreferences,
    required this.improvements,
    required this.recommendations,
  });

  /// Format the report as a human-readable string.
  String toDisplayString() {
    final buffer = StringBuffer();
    buffer.writeln('=== Learning Report ===');
    buffer.writeln('Generated: ${generatedAt.toString().split('.').first}');
    buffer.writeln('Total Interactions: $totalInteractions');
    buffer.writeln(
      'Overall Success Rate: ${(overallSuccessRate * 100).toStringAsFixed(1)}%',
    );
    buffer.writeln();

    if (successByType.isNotEmpty) {
      buffer.writeln('Success by Task Type:');
      for (final entry in successByType.entries) {
        buffer.writeln(
          '  ${entry.key.name}: ${(entry.value * 100).toStringAsFixed(1)}%',
        );
      }
      buffer.writeln();
    }

    if (improvements.isNotEmpty) {
      buffer.writeln('Improvements:');
      for (final imp in improvements) {
        buffer.writeln('  + $imp');
      }
      buffer.writeln();
    }

    if (recommendations.isNotEmpty) {
      buffer.writeln('Recommendations:');
      for (final rec in recommendations) {
        buffer.writeln('  - $rec');
      }
    }

    return buffer.toString();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Daily Metric
// ═══════════════════════════════════════════════════════════════════════════

/// A single day's aggregated metrics.
///
/// Used to track the AI's improvement trend over time.
class DailyMetric {
  /// The date of this metric.
  final DateTime date;

  /// Number of interactions on this day.
  final int interactions;

  /// Success rate for this day (0.0-1.0).
  final double successRate;

  /// Average response quality (1.0-10.0).
  final double avgResponseQuality;

  const DailyMetric({
    required this.date,
    required this.interactions,
    required this.successRate,
    required this.avgResponseQuality,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Internal: Training Example
// ═══════════════════════════════════════════════════════════════════════════

/// Internal representation of a training example (original → preferred).
class _TrainingExample {
  final String id;
  final String interactionId;
  final String originalCode;
  final String preferredCode;
  final double similarity;
  final EditType editType;
  final List<CodeChange> changes;
  final DateTime timestamp;

  _TrainingExample({
    required this.id,
    required this.interactionId,
    required this.originalCode,
    required this.preferredCode,
    required this.similarity,
    required this.editType,
    required this.changes,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'interactionId': interactionId,
        'originalCode': originalCode,
        'preferredCode': preferredCode,
        'similarity': similarity,
        'editType': editType.name,
        'timestamp': timestamp.toIso8601String(),
      };
}

// ═══════════════════════════════════════════════════════════════════════════
// Internal: Prompt Performance
// ═══════════════════════════════════════════════════════════════════════════

/// Internal tracking of a prompt variant's performance.
class _PromptPerformance {
  final String variantId;
  int totalUses;
  int successfulUses;
  int qualitySum;

  _PromptPerformance({
    required this.variantId,
    required this.totalUses,
    required this.successfulUses,
    required this.qualitySum,
  });

  /// Success rate as a percentage (0.0-1.0).
  double get successRate => totalUses > 0 ? successfulUses / totalUses : 0.0;

  /// Average quality score (1.0-10.0).
  double get avgQuality => totalUses > 0 ? qualitySum / totalUses : 0.0;

  Map<String, dynamic> toJson() => {
        'variantId': variantId,
        'totalUses': totalUses,
        'successfulUses': successfulUses,
        'qualitySum': qualitySum,
      };
}

// ═══════════════════════════════════════════════════════════════════════════
// Internal: Daily Metric Accumulator
// ═══════════════════════════════════════════════════════════════════════════

/// Internal accumulator for daily metrics before they become [DailyMetric].
class _DailyMetricAccumulator {
  final DateTime date;
  int interactions;
  int successes;

  _DailyMetricAccumulator({
    required this.date,
    required this.interactions,
    required this.successes,
  });

  factory _DailyMetricAccumulator.fromJson(Map<String, dynamic> json) {
    return _DailyMetricAccumulator(
      date: DateTime.parse(json['date'] as String),
      interactions: json['interactions'] as int,
      successes: json['successes'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'interactions': interactions,
        'successes': successes,
      };
}
