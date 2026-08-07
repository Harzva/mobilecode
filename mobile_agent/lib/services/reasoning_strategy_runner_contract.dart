/// Runner contract and instrumentation gates for strategy-ablation P4a.
///
/// This file defines the bridge between fake scaffolds and future real runners.
/// It still performs no provider, network, model, tool, or device execution.
library;

import '../core/evidence/evidence_model.dart';
import 'reasoning_strategy_models.dart';

const String strategyScaffoldNotRun = 'strategy_scaffold_not_run';
const String strategyDryRunNotCounted = 'strategy_dry_run_not_counted';
const String strategyPilotNotCounted = 'strategy_pilot_not_counted';
const String strategyAblationResult = 'strategy_ablation_result';

class StrategyPhaseSpan {
  const StrategyPhaseSpan({
    required this.phase,
    required this.startedAt,
    required this.endedAt,
  });

  final String phase;
  final DateTime startedAt;
  final DateTime endedAt;

  int get durationMs => endedAt.difference(startedAt).inMilliseconds;

  Map<String, dynamic> toJson() => {
        'phase': phase,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt.toIso8601String(),
        'duration_ms': durationMs,
      };

  factory StrategyPhaseSpan.fromJson(Map<String, dynamic> json) {
    return StrategyPhaseSpan(
      phase: json['phase']?.toString() ?? '',
      startedAt: DateTime.tryParse(json['started_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      endedAt: DateTime.tryParse(json['ended_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class StrategyTimeMetrics {
  const StrategyTimeMetrics({
    this.wallTimeMs,
    this.planningTimeMs,
    this.executionTimeMs,
    this.verificationTimeMs,
    this.reportingTimeMs,
    this.meanTimePerSuccessfulTaskMs,
  });

  final int? wallTimeMs;
  final int? planningTimeMs;
  final int? executionTimeMs;
  final int? verificationTimeMs;
  final int? reportingTimeMs;
  final int? meanTimePerSuccessfulTaskMs;

  Map<String, dynamic> toJson() => {
        'wall_time_ms': wallTimeMs,
        'planning_time_ms': planningTimeMs,
        'execution_time_ms': executionTimeMs,
        'verification_time_ms': verificationTimeMs,
        'reporting_time_ms': reportingTimeMs,
        'mean_time_per_successful_task_ms': meanTimePerSuccessfulTaskMs,
      };

  factory StrategyTimeMetrics.fromJson(Map<String, dynamic> json) {
    return StrategyTimeMetrics(
      wallTimeMs: _intOrNull(json['wall_time_ms'] ?? json['wallTimeMs']),
      planningTimeMs: _intOrNull(json['planning_time_ms'] ?? json['planningTimeMs']),
      executionTimeMs: _intOrNull(json['execution_time_ms'] ?? json['executionTimeMs']),
      verificationTimeMs:
          _intOrNull(json['verification_time_ms'] ?? json['verificationTimeMs']),
      reportingTimeMs: _intOrNull(json['reporting_time_ms'] ?? json['reportingTimeMs']),
      meanTimePerSuccessfulTaskMs: _intOrNull(
        json['mean_time_per_successful_task_ms'] ?? json['meanTimePerSuccessfulTaskMs'],
      ),
    );
  }

  static const empty = StrategyTimeMetrics();
}

class StrategyTokenMetrics {
  const StrategyTokenMetrics({
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
    this.toolInputChars,
    this.toolOutputChars,
    this.estimatedToolTokens,
    this.tokensPerSuccessfulTask,
    this.tokensPerVerifiedSuccess,
  });

  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
  final int? toolInputChars;
  final int? toolOutputChars;
  final int? estimatedToolTokens;
  final int? tokensPerSuccessfulTask;
  final int? tokensPerVerifiedSuccess;

  Map<String, dynamic> toJson() => {
        'prompt_tokens': promptTokens,
        'completion_tokens': completionTokens,
        'total_tokens': totalTokens,
        'tool_input_chars': toolInputChars,
        'tool_output_chars': toolOutputChars,
        'estimated_tool_tokens': estimatedToolTokens,
        'tokens_per_successful_task': tokensPerSuccessfulTask,
        'tokens_per_verified_success': tokensPerVerifiedSuccess,
      };

  factory StrategyTokenMetrics.fromJson(Map<String, dynamic> json) {
    return StrategyTokenMetrics(
      promptTokens: _intOrNull(json['prompt_tokens'] ?? json['promptTokens']),
      completionTokens: _intOrNull(json['completion_tokens'] ?? json['completionTokens']),
      totalTokens: _intOrNull(json['total_tokens'] ?? json['totalTokens']),
      toolInputChars: _intOrNull(json['tool_input_chars'] ?? json['toolInputChars']),
      toolOutputChars: _intOrNull(json['tool_output_chars'] ?? json['toolOutputChars']),
      estimatedToolTokens:
          _intOrNull(json['estimated_tool_tokens'] ?? json['estimatedToolTokens']),
      tokensPerSuccessfulTask: _intOrNull(
        json['tokens_per_successful_task'] ?? json['tokensPerSuccessfulTask'],
      ),
      tokensPerVerifiedSuccess: _intOrNull(
        json['tokens_per_verified_success'] ?? json['tokensPerVerifiedSuccess'],
      ),
    );
  }

  static const empty = StrategyTokenMetrics();
}

class StrategyEffectMetrics {
  const StrategyEffectMetrics({
    this.taskSuccess,
    this.verifiedSuccess,
    this.traceCompleteness,
    this.recoveryRate,
    this.artifactAvailability,
    this.humanInterventionCount,
    this.stepsToCompletion,
    this.strategyOverheadSteps,
    this.handoffCount,
    this.planningRevisions,
    this.verificationFailuresRecovered,
  });

  final double? taskSuccess;
  final double? verifiedSuccess;
  final double? traceCompleteness;
  final double? recoveryRate;
  final double? artifactAvailability;
  final int? humanInterventionCount;
  final int? stepsToCompletion;
  final int? strategyOverheadSteps;
  final int? handoffCount;
  final int? planningRevisions;
  final int? verificationFailuresRecovered;

  Map<String, dynamic> toJson() => {
        'task_success': taskSuccess,
        'verified_success': verifiedSuccess,
        'trace_completeness': traceCompleteness,
        'recovery_rate': recoveryRate,
        'artifact_availability': artifactAvailability,
        'human_intervention_count': humanInterventionCount,
        'steps_to_completion': stepsToCompletion,
        'strategy_overhead_steps': strategyOverheadSteps,
        'handoff_count': handoffCount,
        'planning_revisions': planningRevisions,
        'verification_failures_recovered': verificationFailuresRecovered,
      };

  factory StrategyEffectMetrics.fromJson(Map<String, dynamic> json) {
    return StrategyEffectMetrics(
      taskSuccess: _doubleOrNull(json['task_success'] ?? json['taskSuccess']),
      verifiedSuccess: _doubleOrNull(json['verified_success'] ?? json['verifiedSuccess']),
      traceCompleteness:
          _doubleOrNull(json['trace_completeness'] ?? json['traceCompleteness']),
      recoveryRate: _doubleOrNull(json['recovery_rate'] ?? json['recoveryRate']),
      artifactAvailability:
          _doubleOrNull(json['artifact_availability'] ?? json['artifactAvailability']),
      humanInterventionCount: _intOrNull(
        json['human_intervention_count'] ?? json['humanInterventionCount'],
      ),
      stepsToCompletion: _intOrNull(json['steps_to_completion'] ?? json['stepsToCompletion']),
      strategyOverheadSteps: _intOrNull(
        json['strategy_overhead_steps'] ?? json['strategyOverheadSteps'],
      ),
      handoffCount: _intOrNull(json['handoff_count'] ?? json['handoffCount']),
      planningRevisions: _intOrNull(json['planning_revisions'] ?? json['planningRevisions']),
      verificationFailuresRecovered: _intOrNull(
        json['verification_failures_recovered'] ?? json['verificationFailuresRecovered'],
      ),
    );
  }

  static const empty = StrategyEffectMetrics();
}

class StrategyTokenUsageAccumulator {
  int _promptTokens = 0;
  int _completionTokens = 0;
  int _toolInputChars = 0;
  int _toolOutputChars = 0;

  void addProviderUsage({int promptTokens = 0, int completionTokens = 0}) {
    _promptTokens += promptTokens;
    _completionTokens += completionTokens;
  }

  void addToolIo({int inputChars = 0, int outputChars = 0}) {
    _toolInputChars += inputChars;
    _toolOutputChars += outputChars;
  }

  StrategyTokenMetrics snapshot({
    int? successfulTasks,
    int? verifiedSuccesses,
  }) {
    final estimatedToolTokens = ((_toolInputChars + _toolOutputChars) / 4).ceil();
    final total = _promptTokens + _completionTokens + estimatedToolTokens;
    return StrategyTokenMetrics(
      promptTokens: _promptTokens,
      completionTokens: _completionTokens,
      totalTokens: total,
      toolInputChars: _toolInputChars,
      toolOutputChars: _toolOutputChars,
      estimatedToolTokens: estimatedToolTokens,
      tokensPerSuccessfulTask: _safeDivide(total, successfulTasks),
      tokensPerVerifiedSuccess: _safeDivide(total, verifiedSuccesses),
    );
  }
}

class StrategyInstrumentationRecorder {
  StrategyInstrumentationRecorder({required this.startedAt});

  final DateTime startedAt;
  final List<StrategyPhaseSpan> _spans = [];
  final StrategyTokenUsageAccumulator tokenUsage = StrategyTokenUsageAccumulator();
  DateTime? _endedAt;

  void addPhase({
    required String phase,
    required DateTime startedAt,
    required DateTime endedAt,
  }) {
    _spans.add(StrategyPhaseSpan(phase: phase, startedAt: startedAt, endedAt: endedAt));
  }

  void finish(DateTime endedAt) {
    _endedAt = endedAt;
  }

  StrategyTimeMetrics timeMetrics({int? successfulTasks}) {
    final endedAt = _endedAt;
    final wall = endedAt == null ? null : endedAt.difference(startedAt).inMilliseconds;
    return StrategyTimeMetrics(
      wallTimeMs: wall,
      planningTimeMs: _sumPhase('planning'),
      executionTimeMs: _sumPhase('execution'),
      verificationTimeMs: _sumPhase('verification'),
      reportingTimeMs: _sumPhase('reporting'),
      meanTimePerSuccessfulTaskMs: _safeDivide(wall, successfulTasks),
    );
  }

  List<StrategyPhaseSpan> get spans => List.unmodifiable(_spans);

  int? _sumPhase(String phase) {
    final total = _spans
        .where((span) => span.phase == phase)
        .fold<int>(0, (sum, span) => sum + span.durationMs);
    return total == 0 ? null : total;
  }
}

class StrategyEvidenceManifest {
  const StrategyEvidenceManifest({
    this.modelLogIds = const [],
    this.tokenRecordIds = const [],
    this.verifierEvidenceIds = const [],
    this.deviceEvidenceIds = const [],
    this.toolEvidenceIds = const [],
    this.screenshotIds = const [],
  });

  final List<String> modelLogIds;
  final List<String> tokenRecordIds;
  final List<String> verifierEvidenceIds;
  final List<String> deviceEvidenceIds;
  final List<String> toolEvidenceIds;
  final List<String> screenshotIds;

  Map<String, dynamic> toJson() => {
        'model_log_ids': modelLogIds,
        'token_record_ids': tokenRecordIds,
        'verifier_evidence_ids': verifierEvidenceIds,
        'device_evidence_ids': deviceEvidenceIds,
        'tool_evidence_ids': toolEvidenceIds,
        'screenshot_ids': screenshotIds,
      };

  factory StrategyEvidenceManifest.fromJson(Map<String, dynamic> json) {
    return StrategyEvidenceManifest(
      modelLogIds: _stringList(json['model_log_ids'] ?? json['modelLogIds']),
      tokenRecordIds: _stringList(json['token_record_ids'] ?? json['tokenRecordIds']),
      verifierEvidenceIds:
          _stringList(json['verifier_evidence_ids'] ?? json['verifierEvidenceIds']),
      deviceEvidenceIds: _stringList(json['device_evidence_ids'] ?? json['deviceEvidenceIds']),
      toolEvidenceIds: _stringList(json['tool_evidence_ids'] ?? json['toolEvidenceIds']),
      screenshotIds: _stringList(json['screenshot_ids'] ?? json['screenshotIds']),
    );
  }
}

class StrategyPromotionDecision {
  const StrategyPromotionDecision({
    required this.allowed,
    required this.reason,
    this.missingEvidence = const [],
  });

  final bool allowed;
  final String reason;
  final List<String> missingEvidence;

  Map<String, dynamic> toJson() => {
        'allowed': allowed,
        'reason': reason,
        'missing_evidence': missingEvidence,
      };
}

class StrategyPromotionGate {
  const StrategyPromotionGate();

  StrategyPromotionDecision evaluate({
    required String runKind,
    required bool requestedCountsAsExperiment,
    required StrategyEvidenceManifest evidence,
  }) {
    if (runKind != strategyAblationResult || !requestedCountsAsExperiment) {
      return const StrategyPromotionDecision(
        allowed: false,
        reason: 'non_counted_run_kind_or_not_requested',
      );
    }

    final missing = <String>[];
    if (evidence.modelLogIds.isEmpty) {
      missing.add('model_logs');
    }
    if (evidence.tokenRecordIds.isEmpty) {
      missing.add('token_records');
    }
    if (evidence.verifierEvidenceIds.isEmpty) {
      missing.add('verifier_evidence');
    }
    if (evidence.toolEvidenceIds.isEmpty) {
      missing.add('tool_evidence');
    }
    if (evidence.deviceEvidenceIds.isEmpty) {
      missing.add('device_evidence');
    }

    if (missing.isNotEmpty) {
      return StrategyPromotionDecision(
        allowed: false,
        reason: 'missing_required_evidence_for_counted_strategy_result',
        missingEvidence: missing,
      );
    }

    return const StrategyPromotionDecision(
      allowed: true,
      reason: 'all_required_evidence_present',
    );
  }
}

class ReasoningStrategyRunInput {
  const ReasoningStrategyRunInput({
    required this.userGoal,
    required this.memoryPacket,
    required this.strategyId,
    this.runKind = strategyPilotNotCounted,
    this.promptBudget = const {},
    this.toolAccessPolicy = const {},
    this.maxSteps = 16,
  });

  final String userGoal;
  final HarnessMemoryPacket memoryPacket;
  final String strategyId;
  final String runKind;
  final Map<String, dynamic> promptBudget;
  final Map<String, dynamic> toolAccessPolicy;
  final int maxSteps;

  Map<String, dynamic> toJson() => {
        'user_goal': userGoal,
        'memory_packet': memoryPacket.toJson(),
        'strategy_id': strategyId,
        'run_kind': runKind,
        'prompt_budget': promptBudget,
        'tool_access_policy': toolAccessPolicy,
        'max_steps': maxSteps,
      };
}

class ReasoningStrategyRunOutput {
  const ReasoningStrategyRunOutput({
    required this.runKind,
    required this.trace,
    required this.verifications,
    required this.actionEvidence,
    required this.timeMetrics,
    required this.tokenMetrics,
    required this.effectMetrics,
    required this.promotionDecision,
  });

  final String runKind;
  final StrategyTrace trace;
  final List<StepVerification> verifications;
  final List<ActionEvidence> actionEvidence;
  final StrategyTimeMetrics timeMetrics;
  final StrategyTokenMetrics tokenMetrics;
  final StrategyEffectMetrics effectMetrics;
  final StrategyPromotionDecision promotionDecision;

  bool get countsAsExperiment => promotionDecision.allowed;

  Map<String, dynamic> toJson() => {
        'run_kind': runKind,
        'trace': trace.toBenchmarkJson(),
        'step_verifications': verifications.map((item) => item.toJson()).toList(),
        'action_evidence': actionEvidence.map((item) => item.toJson()).toList(),
        'time_metrics': timeMetrics.toJson(),
        'token_metrics': tokenMetrics.toJson(),
        'effect_metrics': effectMetrics.toJson(),
        'counts_as_experiment': countsAsExperiment,
        'counts_as_strategy_ablation_result': countsAsExperiment,
        'promotion_decision': promotionDecision.toJson(),
      };
}

abstract class ReasoningStrategyRunnerContract {
  Future<ReasoningStrategyRunOutput> run(ReasoningStrategyRunInput input);
}

int? _intOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value.toString());
}

double? _doubleOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value.toString());
}

int? _safeDivide(int? numerator, int? denominator) {
  if (numerator == null || denominator == null || denominator == 0) {
    return null;
  }
  return (numerator / denominator).round();
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.map((item) => item.toString()).toList(growable: false);
}
