/// Non-network fake Plan-Execute-Verify runner for strategy-ablation P2.
///
/// This runner is deliberately deterministic. It does not call a model, tool,
/// provider, network, shell, or device. Every output is non-counted and is safe
/// to use only as a fake closed-loop scaffold.
library;

import 'reasoning_strategy_models.dart';

class FakeReasoningStep {
  const FakeReasoningStep({
    required this.stepId,
    required this.task,
    this.role = 'PlannerExecutorVerifier',
    this.toolName = 'fake_tool',
  });

  final String stepId;
  final String task;
  final String role;
  final String toolName;
}

class FakeStepScriptedOutcome {
  const FakeStepScriptedOutcome({
    required this.stepId,
    this.firstStatus = StepVerificationStatus.pass,
    this.retryStatus,
    this.retryAllowed = false,
    this.failAcceptedAfterRetryFailure = false,
    this.critique = 'Fake verifier critique for dry-run scaffold.',
    this.issues = const [],
  });

  final String stepId;
  final StepVerificationStatus firstStatus;
  final StepVerificationStatus? retryStatus;
  final bool retryAllowed;
  final bool failAcceptedAfterRetryFailure;
  final String critique;
  final List<String> issues;
}

class FakeReasoningStrategyRequest {
  const FakeReasoningStrategyRequest({
    required this.userGoal,
    required this.memoryPacket,
    required this.strategyId,
    this.steps = const [],
    this.scriptedOutcomes = const [],
    this.runKind = 'strategy_dry_run_not_counted',
  });

  final String userGoal;
  final HarnessMemoryPacket memoryPacket;
  final String strategyId;
  final List<FakeReasoningStep> steps;
  final List<FakeStepScriptedOutcome> scriptedOutcomes;
  final String runKind;
}

class FakeReasoningStrategyResult {
  const FakeReasoningStrategyResult({
    required this.trace,
    required this.verifications,
    required this.finalStatus,
    required this.runKind,
    this.countsAsExperiment = false,
  });

  final StrategyTrace trace;
  final List<StepVerification> verifications;
  final String finalStatus;
  final String runKind;
  final bool countsAsExperiment;

  Map<String, dynamic> toJson() => {
        'run_kind': runKind,
        'final_status': finalStatus,
        'counts_as_experiment': countsAsExperiment,
        'trace': trace.toBenchmarkJson(),
        'step_verifications':
            verifications.map((item) => item.toJson()).toList(),
        'evidence_boundary':
            'fake_runner_only_dry_run_not_counted_no_model_no_device_no_network',
      };
}

class FakeReasoningStrategyRunner {
  FakeReasoningStrategyRunner({DateTime? startedAt})
      : _clock = _DeterministicClock(startedAt ?? DateTime.utc(2026, 1, 1));

  final _DeterministicClock _clock;
  int _eventCounter = 0;

  FakeReasoningStrategyResult run(FakeReasoningStrategyRequest request) {
    final runKind = _safeRunKind(request.runKind);
    final steps =
        request.steps.isEmpty ? _defaultSteps(request.userGoal) : request.steps;
    final outcomes = <String, FakeStepScriptedOutcome>{
      for (final outcome in request.scriptedOutcomes) outcome.stepId: outcome,
    };
    final trace = StrategyTrace(
      traceId: 'strace_${request.memoryPacket.runId}_${request.strategyId}',
      strategyId: request.strategyId,
      traceStatus: StrategyTraceStatus.dryRunNotCounted,
    );
    final verifications = <StepVerification>[];

    _append(
      trace,
      type: StrategyEventType.scaffold,
      role: 'Harness',
      summary:
          'P1/P2 fake reasoning strategy runner; no model, no tools, no device, no network.',
      metadata: {
        'run_kind': runKind,
        'counts_as_experiment': false,
        'memory_packet_id': request.memoryPacket.packetId,
      },
    );

    _append(
      trace,
      type: StrategyEventType.plan,
      role: 'PlannerAgent',
      summary: 'Generated ${steps.length} fake PEV steps for dry-run scaffold.',
      metadata: {
        'user_goal_summary': request.userGoal,
        'step_ids': steps.map((step) => step.stepId).toList(),
      },
    );

    for (final step in steps) {
      _executeStep(trace, step);
      final outcome =
          outcomes[step.stepId] ?? FakeStepScriptedOutcome(stepId: step.stepId);
      final firstVerification =
          _verifyStep(step, outcome, retryCount: 0, retry: false);
      verifications.add(firstVerification);
      _appendVerify(trace, firstVerification, retry: false);

      if (firstVerification.shouldRetry) {
        _append(
          trace,
          type: StrategyEventType.replan,
          role: 'PlannerAgent',
          stepId: step.stepId,
          summary:
              'Retry once from fake verifier critique; still dry-run not counted.',
          metadata: {'critique': firstVerification.critique},
        );
        _executeStep(trace, step, retry: true);
        final retryVerification =
            _verifyStep(step, outcome, retryCount: 1, retry: true);
        verifications.add(retryVerification);
        _appendVerify(trace, retryVerification, retry: true);
        if (retryVerification.status == StepVerificationStatus.pass) {
          trace.verificationFailuresRecovered += 1;
        }
      }
    }

    final finalStatus = _finalStatus(verifications);
    trace.traceStatus = runKind == 'strategy_scaffold_not_run'
        ? StrategyTraceStatus.scaffoldNotRun
        : StrategyTraceStatus.dryRunNotCounted;
    trace.failureKind = finalStatus == 'passed' ? null : 'fake_$finalStatus';

    _append(
      trace,
      type: StrategyEventType.report,
      role: 'ReporterAgent',
      summary:
          'Fake PEV runner finished with $finalStatus; result remains $runKind and non-counted.',
      metadata: {
        'final_status': finalStatus,
        'counts_as_experiment': false,
        'counts_as_strategy_ablation_result': false,
      },
    );

    return FakeReasoningStrategyResult(
      trace: trace,
      verifications: verifications,
      finalStatus: finalStatus,
      runKind: runKind,
    );
  }

  void _executeStep(
    StrategyTrace trace,
    FakeReasoningStep step, {
    bool retry = false,
  }) {
    final retryLabel = retry ? ' retry' : '';
    _append(
      trace,
      type: StrategyEventType.think,
      role: step.role,
      stepId: step.stepId,
      summary: 'Fake$retryLabel thought for ${step.task}.',
    );
    _append(
      trace,
      type: StrategyEventType.act,
      role: step.role,
      stepId: step.stepId,
      toolName: step.toolName,
      summary: 'Fake$retryLabel action; no real tool invoked.',
      metadata: {'dry_run_not_counted': true},
    );
    _append(
      trace,
      type: StrategyEventType.observe,
      role: step.role,
      stepId: step.stepId,
      evidenceId: 'fake_ev_${step.stepId}_${retry ? 'retry' : 'first'}',
      summary: 'Fake$retryLabel observation from scripted scaffold evidence.',
    );
  }

  StepVerification _verifyStep(
    FakeReasoningStep step,
    FakeStepScriptedOutcome outcome, {
    required int retryCount,
    required bool retry,
  }) {
    var status = retry
        ? outcome.retryStatus ?? outcome.firstStatus
        : outcome.firstStatus;
    if (retry &&
        status == StepVerificationStatus.fail &&
        outcome.failAcceptedAfterRetryFailure) {
      status = StepVerificationStatus.failAccepted;
    }
    final passed = status == StepVerificationStatus.pass;
    final retryAllowed =
        !retry && outcome.retryAllowed && status == StepVerificationStatus.fail;
    return StepVerification(
      stepId: step.stepId,
      status: status,
      confidence: passed ? 0.92 : 0.3,
      checks: [
        StepVerificationCheck(
          name: 'fake_scripted_outcome',
          status: status,
          evidenceId: 'fake_ev_${step.stepId}_${retry ? 'retry' : 'first'}',
        ),
      ],
      issues: passed ? const [] : outcome.issues,
      critique: passed ? '' : outcome.critique,
      retryAllowed: retryAllowed,
      retryCount: retryCount,
      evidenceIds: ['fake_ev_${step.stepId}_${retry ? 'retry' : 'first'}'],
      countsAsVerifiedSuccess: false,
    );
  }

  void _appendVerify(
    StrategyTrace trace,
    StepVerification verification, {
    required bool retry,
  }) {
    _append(
      trace,
      type: StrategyEventType.verify,
      role: 'VerifierAgent',
      stepId: verification.stepId,
      evidenceId: verification.evidenceIds.isEmpty
          ? null
          : verification.evidenceIds.first,
      summary:
          'Fake verifier ${retry ? 'retry ' : ''}status: ${verification.status.wire}; non-counted.',
      metadata: {
        'retry_count': verification.retryCount,
        'retry_allowed': verification.retryAllowed,
        'counts_as_verified_success': false,
      },
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
    final startedAt = _clock.next();
    trace.appendEvent(
      StrategyTraceEvent(
        eventId: 'evt_${(++_eventCounter).toString().padLeft(3, '0')}',
        type: type,
        role: role,
        stepId: stepId,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(milliseconds: 1)),
        toolName: toolName,
        evidenceId: evidenceId,
        summary: summary,
        countsAsExperiment: false,
        metadata: metadata,
      ),
    );
  }

  List<FakeReasoningStep> _defaultSteps(String userGoal) {
    final normalizedGoal = userGoal.trim().isEmpty
        ? 'requested mobile harness task'
        : userGoal.trim();
    return [
      FakeReasoningStep(
        stepId: 'step_001',
        task: 'Plan minimal fake execution for: $normalizedGoal',
        toolName: 'fake_plan_tool',
      ),
      const FakeReasoningStep(
        stepId: 'step_002',
        task: 'Execute fake artifact action without touching real runtime',
        toolName: 'fake_execute_tool',
      ),
      const FakeReasoningStep(
        stepId: 'step_003',
        task: 'Verify fake evidence and produce non-counted report',
        toolName: 'fake_verify_tool',
      ),
    ];
  }

  String _safeRunKind(String runKind) {
    return runKind == 'strategy_scaffold_not_run' ||
            runKind == 'strategy_dry_run_not_counted' ||
            runKind == 'strategy_pilot_not_counted'
        ? runKind
        : 'strategy_dry_run_not_counted';
  }

  String _finalStatus(List<StepVerification> verifications) {
    final latestByStep = <String, StepVerification>{};
    for (final verification in verifications) {
      latestByStep[verification.stepId] = verification;
    }
    final latest = latestByStep.values;

    if (latest.any((item) => item.status == StepVerificationStatus.blocked)) {
      return 'blocked';
    }
    if (latest.any((item) => item.status == StepVerificationStatus.fail)) {
      return 'failed';
    }
    if (latest
        .any((item) => item.status == StepVerificationStatus.failAccepted)) {
      return 'failAccepted';
    }
    return 'passed';
  }
}

class _DeterministicClock {
  _DeterministicClock(this._current);

  DateTime _current;

  DateTime next() {
    final value = _current;
    _current = _current.add(const Duration(milliseconds: 10));
    return value;
  }
}
