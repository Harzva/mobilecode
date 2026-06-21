/// Real runner adapter skeleton for strategy-ablation P4b.
///
/// This class is intentionally safe-by-default: without injected callbacks it
/// returns blocked/fake outputs and never touches providers, tools, devices, or
/// the network. With injected callbacks it can exercise the future real runner
/// shape, but still remains non-counted unless a later phase explicitly enables
/// promotion and provides all required evidence.
library;

import '../core/evidence/evidence_model.dart';
import 'reasoning_strategy_models.dart';
import 'reasoning_strategy_runner_contract.dart';

typedef StrategyModelCallback = Future<StrategyModelCallbackResult> Function(
  StrategyModelCallbackRequest request,
);

typedef StrategyToolCallback = Future<StrategyToolCallbackResult> Function(
  StrategyToolCallbackRequest request,
);

typedef StrategyVerifierCallback = Future<StepVerification> Function(
  StrategyVerifierCallbackRequest request,
);

class StrategyModelCallbackRequest {
  const StrategyModelCallbackRequest({
    required this.phase,
    required this.role,
    required this.prompt,
    this.stepId,
    this.metadata = const {},
  });

  final String phase;
  final String role;
  final String prompt;
  final String? stepId;
  final Map<String, dynamic> metadata;
}

class StrategyModelCallbackResult {
  const StrategyModelCallbackResult({
    required this.status,
    required this.content,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.modelLogId,
    this.failureKind,
    this.blockers = const [],
  });

  final String status;
  final String content;
  final int promptTokens;
  final int completionTokens;
  final String? modelLogId;
  final String? failureKind;
  final List<String> blockers;

  bool get blocked => status == 'blocked';
}

class StrategyToolCallbackRequest {
  const StrategyToolCallbackRequest({
    required this.toolName,
    required this.stepId,
    required this.arguments,
    this.metadata = const {},
  });

  final String toolName;
  final String stepId;
  final Map<String, dynamic> arguments;
  final Map<String, dynamic> metadata;
}

class StrategyToolCallbackResult {
  const StrategyToolCallbackResult({
    required this.status,
    required this.observation,
    this.inputChars = 0,
    this.outputChars = 0,
    this.evidenceId,
    this.artifactPaths = const [],
    this.failureKind,
    this.blockers = const [],
  });

  final String status;
  final String observation;
  final int inputChars;
  final int outputChars;
  final String? evidenceId;
  final List<String> artifactPaths;
  final String? failureKind;
  final List<String> blockers;

  bool get blocked => status == 'blocked';
  bool get succeeded => status == 'succeeded';
}

class StrategyVerifierCallbackRequest {
  const StrategyVerifierCallbackRequest({
    required this.stepId,
    required this.stepTask,
    required this.modelResult,
    required this.toolResult,
    required this.retryCount,
  });

  final String stepId;
  final String stepTask;
  final StrategyModelCallbackResult modelResult;
  final StrategyToolCallbackResult toolResult;
  final int retryCount;
}

class RealRunnerAdapterStep {
  const RealRunnerAdapterStep({
    required this.stepId,
    required this.task,
    this.toolName = 'blocked_tool',
    this.role = 'CodeAgent',
  });

  final String stepId;
  final String task;
  final String toolName;
  final String role;
}

class ReasoningStrategyRealRunnerAdapter implements ReasoningStrategyRunnerContract {
  ReasoningStrategyRealRunnerAdapter({
    StrategyModelCallback? modelCallback,
    StrategyToolCallback? toolCallback,
    StrategyVerifierCallback? verifierCallback,
    StrategyPromotionGate promotionGate = const StrategyPromotionGate(),
    StrategyEvidenceManifest evidenceManifest = const StrategyEvidenceManifest(),
    this.allowCountedPromotion = false,
    DateTime? startedAt,
  })  : _modelCallback = modelCallback ?? _defaultBlockedModelCallback,
        _toolCallback = toolCallback ?? _defaultBlockedToolCallback,
        _verifierCallback = verifierCallback ?? _defaultBlockedVerifierCallback,
        _promotionGate = promotionGate,
        _evidenceManifest = evidenceManifest,
        _startedAt = startedAt ?? DateTime.now().toUtc();

  final StrategyModelCallback _modelCallback;
  final StrategyToolCallback _toolCallback;
  final StrategyVerifierCallback _verifierCallback;
  final StrategyPromotionGate _promotionGate;
  final StrategyEvidenceManifest _evidenceManifest;
  final bool allowCountedPromotion;
  final DateTime _startedAt;

  int _eventCounter = 0;

  @override
  Future<ReasoningStrategyRunOutput> run(ReasoningStrategyRunInput input) async {
    final safeRunKind = _safeRunKind(input.runKind);
    final recorder = StrategyInstrumentationRecorder(startedAt: _startedAt);
    final trace = StrategyTrace(
      traceId: 'strace_${input.memoryPacket.runId}_${input.strategyId}_adapter',
      strategyId: input.strategyId,
      traceStatus: _traceStatusForRunKind(safeRunKind),
    );
    final actionEvidence = <ActionEvidence>[];
    final verifications = <StepVerification>[];

    _append(
      trace,
      type: StrategyEventType.scaffold,
      role: 'Harness',
      summary: 'P4b real runner adapter skeleton; default callbacks are blocked/fake.',
      metadata: {
        'run_kind': safeRunKind,
        'allow_counted_promotion': allowCountedPromotion,
        'counts_as_experiment': false,
      },
    );

    final planningStarted = _startedAt.add(const Duration(milliseconds: 10));
    final planningResult = await _modelCallback(
      StrategyModelCallbackRequest(
        phase: 'planning',
        role: 'PlannerAgent',
        prompt: _planningPrompt(input),
        metadata: {
          'strategy_id': input.strategyId,
          'max_steps': input.maxSteps,
        },
      ),
    );
    final planningEnded = planningStarted.add(const Duration(milliseconds: 10));
    recorder.addPhase(phase: 'planning', startedAt: planningStarted, endedAt: planningEnded);
    recorder.tokenUsage.addProviderUsage(
      promptTokens: planningResult.promptTokens,
      completionTokens: planningResult.completionTokens,
    );
    _append(
      trace,
      type: StrategyEventType.plan,
      role: 'PlannerAgent',
      summary: planningResult.blocked
          ? 'Planning callback blocked; using safe non-counted fallback steps.'
          : 'Planning callback returned non-counted adapter plan.',
      metadata: {
        'model_status': planningResult.status,
        'model_log_id': planningResult.modelLogId,
        'blockers': planningResult.blockers,
      },
    );

    final steps = _adapterSteps(input, planningResult).take(input.maxSteps).toList(growable: false);

    for (final step in steps) {
      final stepStarted = planningEnded.add(Duration(milliseconds: 20 * (verifications.length + 1)));
      final modelResult = await _modelCallback(
        StrategyModelCallbackRequest(
          phase: 'step_think',
          role: step.role,
          stepId: step.stepId,
          prompt: 'Think about ${step.task}. Return a compact non-secret action plan.',
          metadata: {'tool_name': step.toolName},
        ),
      );
      recorder.tokenUsage.addProviderUsage(
        promptTokens: modelResult.promptTokens,
        completionTokens: modelResult.completionTokens,
      );
      _append(
        trace,
        type: StrategyEventType.think,
        role: step.role,
        stepId: step.stepId,
        summary: modelResult.blocked
            ? 'Model callback blocked for ${step.stepId}.'
            : 'Model callback produced non-counted step thought.',
        metadata: {
          'model_status': modelResult.status,
          'model_log_id': modelResult.modelLogId,
          'blockers': modelResult.blockers,
        },
      );

      final toolResult = await _toolCallback(
        StrategyToolCallbackRequest(
          toolName: step.toolName,
          stepId: step.stepId,
          arguments: {
            'task': step.task,
            'model_content': modelResult.content,
            'dry_run_not_counted': true,
          },
          metadata: {'strategy_id': input.strategyId},
        ),
      );
      recorder.tokenUsage.addToolIo(
        inputChars: toolResult.inputChars,
        outputChars: toolResult.outputChars,
      );
      final stepEnded = stepStarted.add(const Duration(milliseconds: 30));
      recorder.addPhase(phase: 'execution', startedAt: stepStarted, endedAt: stepEnded);
      _append(
        trace,
        type: StrategyEventType.act,
        role: step.role,
        stepId: step.stepId,
        toolName: step.toolName,
        summary: toolResult.blocked
            ? 'Tool callback blocked for ${step.stepId}; no real tool executed.'
            : 'Tool callback returned non-counted observation.',
        metadata: {
          'tool_status': toolResult.status,
          'blockers': toolResult.blockers,
        },
      );
      _append(
        trace,
        type: StrategyEventType.observe,
        role: step.role,
        stepId: step.stepId,
        evidenceId: toolResult.evidenceId,
        summary: toolResult.observation,
        metadata: {'dry_run_not_counted': true},
      );
      actionEvidence.add(_toolResultEvidence(step: step, result: toolResult, startedAt: stepStarted));

      final verificationStarted = stepEnded;
      final verification = await _verifierCallback(
        StrategyVerifierCallbackRequest(
          stepId: step.stepId,
          stepTask: step.task,
          modelResult: modelResult,
          toolResult: toolResult,
          retryCount: 0,
        ),
      );
      final verificationEnded = verificationStarted.add(const Duration(milliseconds: 5));
      recorder.addPhase(
        phase: 'verification',
        startedAt: verificationStarted,
        endedAt: verificationEnded,
      );
      verifications.add(verification);
      _append(
        trace,
        type: StrategyEventType.verify,
        role: 'VerifierAgent',
        stepId: step.stepId,
        evidenceId: verification.evidenceIds.isEmpty ? null : verification.evidenceIds.first,
        summary: 'Verifier callback status: ${verification.status.wire}; non-counted.',
        metadata: verification.toJson(),
      );
    }

    final finalStatus = _finalStatus(verifications);
    trace.traceStatus = _traceStatusForRunKind(safeRunKind);
    trace.failureKind = finalStatus == 'passed' ? null : 'adapter_$finalStatus';
    recorder.finish(_startedAt.add(const Duration(milliseconds: 1000)));
    recorder.addPhase(
      phase: 'reporting',
      startedAt: _startedAt.add(const Duration(milliseconds: 900)),
      endedAt: _startedAt.add(const Duration(milliseconds: 1000)),
    );
    _append(
      trace,
      type: StrategyEventType.report,
      role: 'ReporterAgent',
      summary: 'P4b adapter completed with $finalStatus; output remains non-counted.',
      metadata: {
        'final_status': finalStatus,
        'counts_as_experiment': false,
        'counts_as_strategy_ablation_result': false,
      },
    );

    final gateDecision = _promotionGate.evaluate(
      runKind: input.runKind,
      requestedCountsAsExperiment: allowCountedPromotion && input.runKind == strategyAblationResult,
      evidence: _evidenceManifest,
    );
    final promotionDecision = gateDecision.allowed
        ? const StrategyPromotionDecision(
            allowed: false,
            reason: 'p4b_adapter_skeleton_never_promotes_without_later_review_gate',
          )
        : gateDecision;

    return ReasoningStrategyRunOutput(
      runKind: safeRunKind,
      trace: trace,
      verifications: verifications,
      actionEvidence: actionEvidence,
      timeMetrics: recorder.timeMetrics(successfulTasks: finalStatus == 'passed' ? 1 : 0),
      tokenMetrics: recorder.tokenUsage.snapshot(
        successfulTasks: finalStatus == 'passed' ? 1 : 0,
        verifiedSuccesses: _verifiedSuccessCount(verifications),
      ),
      effectMetrics: StrategyEffectMetrics(
        taskSuccess: null,
        verifiedSuccess: null,
        traceCompleteness: null,
        recoveryRate: null,
        artifactAvailability: null,
        humanInterventionCount: 0,
        stepsToCompletion: steps.length,
        strategyOverheadSteps: trace.events.length,
        handoffCount: trace.handoffCount,
        planningRevisions: trace.planningRevisions,
        verificationFailuresRecovered: trace.verificationFailuresRecovered,
      ),
      promotionDecision: promotionDecision,
    );
  }

  void _append(
    StrategyTrace trace, {
    required StrategyEventType type,
    required String role,
    required String summary,
    String? stepId,
    String? toolName,
    String? evidenceId,
    Map<String, dynamic> metadata = const {},
  }) {
    final eventTime = _startedAt.add(Duration(milliseconds: 10 * _eventCounter));
    trace.appendEvent(
      StrategyTraceEvent(
        eventId: 'evt_${(++_eventCounter).toString().padLeft(3, '0')}',
        type: type,
        role: role,
        stepId: stepId,
        startedAt: eventTime,
        endedAt: eventTime.add(const Duration(milliseconds: 1)),
        toolName: toolName,
        evidenceId: evidenceId,
        summary: summary,
        countsAsExperiment: false,
        metadata: metadata,
      ),
    );
  }

  String _safeRunKind(String runKind) {
    return switch (runKind) {
      strategyScaffoldNotRun => strategyScaffoldNotRun,
      strategyDryRunNotCounted => strategyDryRunNotCounted,
      strategyPilotNotCounted => strategyPilotNotCounted,
      _ => strategyPilotNotCounted,
    };
  }

  StrategyTraceStatus _traceStatusForRunKind(String runKind) {
    return runKind == strategyScaffoldNotRun
        ? StrategyTraceStatus.scaffoldNotRun
        : StrategyTraceStatus.dryRunNotCounted;
  }

  String _planningPrompt(ReasoningStrategyRunInput input) {
    return 'Plan a MobileHarnessBench strategy pilot for ${input.userGoal}. '
        'Return 2-3 compact steps. Do not include secrets or raw transcript.';
  }

  List<RealRunnerAdapterStep> _adapterSteps(
    ReasoningStrategyRunInput input,
    StrategyModelCallbackResult planningResult,
  ) {
    if (!planningResult.blocked && planningResult.content.trim().isNotEmpty) {
      return [
        RealRunnerAdapterStep(
          stepId: 'step_001',
          task: 'Adapter planned step from model callback: ${planningResult.content.trim()}',
          toolName: 'injected_tool_callback',
        ),
      ];
    }
    return [
      RealRunnerAdapterStep(
        stepId: 'step_001',
        task: 'Blocked/fake adapter step for ${input.userGoal}',
      ),
    ];
  }

  ActionEvidence _toolResultEvidence({
    required RealRunnerAdapterStep step,
    required StrategyToolCallbackResult result,
    required DateTime startedAt,
  }) {
    return ActionEvidence(
      evidenceId: result.evidenceId ?? 'adapter_ev_${step.stepId}',
      actionName: MobileCodeAction.traceCallProvider,
      paramsSummary: 'P4b adapter callback ${step.toolName}: ${result.status}',
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(milliseconds: 1)),
      success: false,
      artifactPaths: result.artifactPaths,
      logs: [
        result.observation,
        'P4b adapter skeleton output; non-counted.',
      ],
      failureKind: result.failureKind ?? (result.blocked ? 'blockedFakeCallback' : 'dryRunNotCounted'),
      recoveryActions: const [
        'Inject reviewed real callbacks and evidence before running counted experiments.',
      ],
      metadata: {
        'step_id': step.stepId,
        'tool_name': step.toolName,
        'callback_status': result.status,
        'counts_as_experiment': false,
        'counts_as_strategy_ablation_result': false,
      },
    );
  }

  String _finalStatus(List<StepVerification> verifications) {
    if (verifications.any((item) => item.status == StepVerificationStatus.blocked)) {
      return 'blocked';
    }
    if (verifications.any((item) => item.status == StepVerificationStatus.fail)) {
      return 'failed';
    }
    if (verifications.any((item) => item.status == StepVerificationStatus.failAccepted)) {
      return 'failAccepted';
    }
    return 'passed';
  }

  int _verifiedSuccessCount(List<StepVerification> verifications) {
    return verifications.where((item) => item.countsAsVerifiedSuccess).length;
  }
}

Future<StrategyModelCallbackResult> _defaultBlockedModelCallback(
  StrategyModelCallbackRequest request,
) async {
  return StrategyModelCallbackResult(
    status: 'blocked',
    content: '',
    failureKind: 'defaultBlockedModelCallback',
    blockers: ['no_model_callback_injected'],
  );
}

Future<StrategyToolCallbackResult> _defaultBlockedToolCallback(
  StrategyToolCallbackRequest request,
) async {
  return StrategyToolCallbackResult(
    status: 'blocked',
    observation: 'Default blocked tool callback; no real tool executed.',
    failureKind: 'defaultBlockedToolCallback',
    blockers: ['no_tool_callback_injected'],
  );
}

Future<StepVerification> _defaultBlockedVerifierCallback(
  StrategyVerifierCallbackRequest request,
) async {
  return StepVerification(
    stepId: request.stepId,
    status: StepVerificationStatus.blocked,
    confidence: 0,
    checks: const [
      StepVerificationCheck(
        name: 'real_callbacks_injected',
        status: StepVerificationStatus.blocked,
      ),
    ],
    issues: const ['model/tool callbacks are default blocked skeletons'],
    critique: 'Inject reviewed callbacks and evidence before attempting real pilots.',
    retryAllowed: false,
    retryCount: request.retryCount,
    evidenceIds: const [],
    countsAsVerifiedSuccess: false,
  );
}
