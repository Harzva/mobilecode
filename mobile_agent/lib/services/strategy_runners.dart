/// Release-gated reasoning strategy runners for MobileCode.
///
/// These runners implement the app-level strategy shapes without enabling
/// counted benchmark results by default. They produce StrategyTrace,
/// StepVerification, and ActionEvidence records while remaining safe for local
/// fake/dry-run execution.
library;

import '../core/evidence/evidence_model.dart';
import 'reasoning_strategy_models.dart';
import 'reasoning_strategy_runner_contract.dart';

const String reactSingleAgentStrategyId = 'react_single_agent';
const String planExecuteVerifySingleAgentStrategyId =
    'plan_execute_verify_single_agent';
const String reactWithFinalVerifierStrategyId = 'react_with_final_verifier';
const String supervisorHandoffMultiAgentStrategyId =
    'supervisor_handoff_multi_agent';
const String swarmRouterMultiAgentStrategyId = 'swarm_router_multi_agent';
const String hierarchicalSwarmMultiAgentStrategyId =
    'hierarchical_swarm_multi_agent';

class StrategyStepOutcome {
  const StrategyStepOutcome({
    required this.stepId,
    this.firstStatus = StepVerificationStatus.pass,
    this.retryStatus,
    this.retryAllowed = false,
    this.failAcceptedAfterRetryFailure = false,
  });

  final String stepId;
  final StepVerificationStatus firstStatus;
  final StepVerificationStatus? retryStatus;
  final bool retryAllowed;
  final bool failAcceptedAfterRetryFailure;
}

class StrategyRunnerStep {
  const StrategyRunnerStep({
    required this.stepId,
    required this.task,
    required this.role,
    required this.toolName,
  });

  final String stepId;
  final String task;
  final String role;
  final String toolName;
}

abstract class _BaseStrategyRunner implements ReasoningStrategyRunnerContract {
  _BaseStrategyRunner({
    required this.strategyId,
    DateTime? startedAt,
    StrategyPromotionGate promotionGate = const StrategyPromotionGate(),
    StrategyEvidenceManifest evidenceManifest =
        const StrategyEvidenceManifest(),
  })  : startedAt = startedAt ?? DateTime.now().toUtc(),
        promotionGate = promotionGate,
        evidenceManifest = evidenceManifest;

  final String strategyId;
  final DateTime startedAt;
  final StrategyPromotionGate promotionGate;
  final StrategyEvidenceManifest evidenceManifest;
  int _eventCounter = 0;

  StrategyTrace newTrace(ReasoningStrategyRunInput input) {
    return StrategyTrace(
      traceId: 'strace_${input.memoryPacket.runId}_$strategyId',
      strategyId: strategyId,
      traceStatus: _traceStatus(input.runKind),
    );
  }

  void append(
    StrategyTrace trace, {
    required StrategyEventType type,
    required String role,
    required String summary,
    String? stepId,
    String? toolName,
    String? evidenceId,
    Map<String, dynamic> metadata = const {},
  }) {
    final time = startedAt.add(Duration(milliseconds: 10 * _eventCounter));
    trace.appendEvent(
      StrategyTraceEvent(
        eventId: 'evt_${(++_eventCounter).toString().padLeft(3, '0')}',
        type: type,
        role: role,
        stepId: stepId,
        startedAt: time,
        endedAt: time.add(const Duration(milliseconds: 1)),
        toolName: toolName,
        evidenceId: evidenceId,
        summary: _redact(summary),
        countsAsExperiment: false,
        metadata: _redactMap(metadata),
      ),
    );
  }

  ActionEvidence evidenceFor({
    required StrategyRunnerStep step,
    required String evidenceId,
    required MobileCodeAction action,
    bool success = true,
    String? failureKind,
    List<String> artifactPaths = const [],
  }) {
    return ActionEvidence(
      evidenceId: evidenceId,
      actionName: action,
      paramsSummary: 'Strategy $strategyId ${step.toolName} for ${step.stepId}',
      startedAt: startedAt.add(Duration(milliseconds: 10 * _eventCounter)),
      endedAt: startedAt.add(Duration(milliseconds: 10 * _eventCounter + 1)),
      success: success,
      artifactPaths: artifactPaths,
      failureKind: failureKind,
      logs: [
        'non_counted_strategy_runner=$strategyId',
        'no provider, device, network, or dangerous tool invoked by default',
      ],
      metadata: {
        'strategy_id': strategyId,
        'step_id': step.stepId,
        'counts_as_experiment': false,
      },
    );
  }

  StepVerification verificationFor({
    required StrategyRunnerStep step,
    required StepVerificationStatus status,
    int retryCount = 0,
    bool retryAllowed = false,
    String verifierId = 'mobilecode_step_verifier_v1',
    String? evidenceId,
  }) {
    final pass = status == StepVerificationStatus.pass;
    return StepVerification(
      stepId: step.stepId,
      verifierId: verifierId,
      status: status,
      confidence: pass ? 0.9 : 0.35,
      checks: [
        StepVerificationCheck(
          name: '${strategyId}_non_counted_check',
          status: status,
          evidenceId: evidenceId,
        ),
      ],
      issues: pass ? const [] : ['non-counted strategy runner scripted issue'],
      critique:
          pass ? '' : 'Retry or accept failure according to strategy budget.',
      retryAllowed: retryAllowed,
      retryCount: retryCount,
      evidenceIds: evidenceId == null ? const [] : [evidenceId],
      countsAsVerifiedSuccess: false,
    );
  }

  ReasoningStrategyRunOutput output({
    required ReasoningStrategyRunInput input,
    required StrategyTrace trace,
    required List<StepVerification> verifications,
    required List<ActionEvidence> actionEvidence,
    int? stepsToCompletion,
  }) {
    final finalStatus = _finalStatus(verifications);
    trace.traceStatus = _traceStatus(input.runKind);
    if (finalStatus == 'passed') {
      trace.failureKind = null;
    } else {
      trace.failureKind ??= '${strategyId}_$finalStatus';
    }
    final decision = promotionGate.evaluate(
      runKind: input.runKind,
      requestedCountsAsExperiment: input.runKind == strategyAblationResult,
      evidence: evidenceManifest,
    );
    return ReasoningStrategyRunOutput(
      runKind: _safeRunKind(input.runKind),
      trace: trace,
      verifications: verifications,
      actionEvidence: actionEvidence,
      timeMetrics: StrategyTimeMetrics.empty,
      tokenMetrics: StrategyTokenMetrics.empty,
      effectMetrics: StrategyEffectMetrics(
        taskSuccess: null,
        verifiedSuccess: null,
        traceCompleteness: trace.events.isEmpty ? 0 : 1,
        recoveryRate: null,
        artifactAvailability: actionEvidence.isEmpty ? 0 : 1,
        humanInterventionCount: 0,
        stepsToCompletion: stepsToCompletion,
        strategyOverheadSteps: trace.events.length,
        handoffCount: trace.handoffCount,
        planningRevisions: trace.planningRevisions,
        verificationFailuresRecovered: trace.verificationFailuresRecovered,
      ),
      promotionDecision: decision.allowed
          ? const StrategyPromotionDecision(
              allowed: false,
              reason:
                  'strategy_runner_default_non_counted_until_real_review_gate',
            )
          : decision,
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

  StrategyTraceStatus _traceStatus(String runKind) {
    return runKind == strategyScaffoldNotRun
        ? StrategyTraceStatus.scaffoldNotRun
        : StrategyTraceStatus.dryRunNotCounted;
  }
}

class ReactStrategyRunner extends _BaseStrategyRunner {
  ReactStrategyRunner({
    this.maxIterations = 3,
    DateTime? startedAt,
  }) : super(strategyId: reactSingleAgentStrategyId, startedAt: startedAt);

  final int maxIterations;

  @override
  Future<ReasoningStrategyRunOutput> run(
      ReasoningStrategyRunInput input) async {
    final trace = newTrace(input);
    final evidence = <ActionEvidence>[];
    final allowedTools = _allowedTools(input);
    final iterations = maxIterations.clamp(1, input.maxSteps);

    for (var index = 0; index < iterations; index += 1) {
      final step = StrategyRunnerStep(
        stepId: 'react_${(index + 1).toString().padLeft(3, '0')}',
        task: input.userGoal,
        role: 'ReActAgent',
        toolName: allowedTools[index % allowedTools.length],
      );
      append(
        trace,
        type: StrategyEventType.think,
        role: step.role,
        stepId: step.stepId,
        summary: 'Reason about ${input.userGoal} before one safe action.',
      );
      final evidenceId = 'react_ev_${step.stepId}';
      append(
        trace,
        type: StrategyEventType.act,
        role: step.role,
        stepId: step.stepId,
        toolName: step.toolName,
        evidenceId: evidenceId,
        summary: 'Invoke allowed non-counted strategy action ${step.toolName}.',
      );
      append(
        trace,
        type: StrategyEventType.observe,
        role: step.role,
        stepId: step.stepId,
        evidenceId: evidenceId,
        summary: 'Observe synthetic non-counted action evidence.',
      );
      evidence.add(
        evidenceFor(
          step: step,
          evidenceId: evidenceId,
          action: MobileCodeAction.traceSelectTool,
        ),
      );
    }

    final reportStep = StrategyRunnerStep(
      stepId: 'react_report',
      task: 'Report ReAct result',
      role: 'ReporterAgent',
      toolName: 'report',
    );
    final verification = verificationFor(
      step: reportStep,
      status: StepVerificationStatus.pass,
      evidenceId: evidence.isEmpty ? null : evidence.last.evidenceId,
    );
    append(
      trace,
      type: StrategyEventType.report,
      role: 'ReporterAgent',
      stepId: reportStep.stepId,
      summary:
          'ReAct strategy reported non-counted trace and evidence summary.',
    );
    return output(
      input: input,
      trace: trace,
      verifications: [verification],
      actionEvidence: evidence,
      stepsToCompletion: iterations,
    );
  }
}

class PlanExecuteVerifyStrategyRunner extends _BaseStrategyRunner {
  PlanExecuteVerifyStrategyRunner({
    this.scriptedOutcomes = const [],
    DateTime? startedAt,
  }) : super(
            strategyId: planExecuteVerifySingleAgentStrategyId,
            startedAt: startedAt);

  final List<StrategyStepOutcome> scriptedOutcomes;

  @override
  Future<ReasoningStrategyRunOutput> run(
      ReasoningStrategyRunInput input) async {
    final trace = newTrace(input);
    final steps = _planSteps(input, input.maxSteps);
    final evidence = <ActionEvidence>[];
    final verifications = <StepVerification>[];
    final outcomes = {
      for (final outcome in scriptedOutcomes) outcome.stepId: outcome
    };

    append(
      trace,
      type: StrategyEventType.plan,
      role: 'PlannerAgent',
      summary: 'Create ${steps.length} bounded Plan-Execute-Verify steps.',
      metadata: {'step_ids': steps.map((step) => step.stepId).toList()},
    );

    for (final step in steps) {
      final result = _executeAndVerify(
        input: input,
        trace: trace,
        step: step,
        outcome:
            outcomes[step.stepId] ?? StrategyStepOutcome(stepId: step.stepId),
      );
      evidence.addAll(result.evidence);
      verifications.addAll(result.verifications);
    }

    append(
      trace,
      type: StrategyEventType.report,
      role: 'ReporterAgent',
      summary: 'PEV strategy reported all step verification gates.',
    );
    return output(
      input: input,
      trace: trace,
      verifications: verifications,
      actionEvidence: evidence,
      stepsToCompletion: steps.length,
    );
  }

  _StepRunResult _executeAndVerify({
    required ReasoningStrategyRunInput input,
    required StrategyTrace trace,
    required StrategyRunnerStep step,
    required StrategyStepOutcome outcome,
  }) {
    final evidence = <ActionEvidence>[];
    final verifications = <StepVerification>[];
    append(trace,
        type: StrategyEventType.think,
        role: step.role,
        stepId: step.stepId,
        summary: 'Think before ${step.task}.');
    final evidenceId = 'pev_ev_${step.stepId}_first';
    append(trace,
        type: StrategyEventType.act,
        role: step.role,
        stepId: step.stepId,
        toolName: step.toolName,
        evidenceId: evidenceId,
        summary: 'Execute bounded non-counted PEV action.');
    append(trace,
        type: StrategyEventType.observe,
        role: step.role,
        stepId: step.stepId,
        evidenceId: evidenceId,
        summary: 'Observe non-counted PEV evidence.');
    evidence.add(evidenceFor(
        step: step,
        evidenceId: evidenceId,
        action: MobileCodeAction.traceWriteArtifact));

    final first = verificationFor(
      step: step,
      status: outcome.firstStatus,
      retryAllowed: outcome.retryAllowed &&
          outcome.firstStatus == StepVerificationStatus.fail,
      evidenceId: evidenceId,
    );
    verifications.add(first);
    append(trace,
        type: StrategyEventType.verify,
        role: 'VerifierAgent',
        stepId: step.stepId,
        evidenceId: evidenceId,
        summary: 'Verify PEV step: ${first.status.wire}.',
        metadata: first.toJson());

    if (first.shouldRetry) {
      append(trace,
          type: StrategyEventType.replan,
          role: 'PlannerAgent',
          stepId: step.stepId,
          summary: 'Retry from verifier critique.');
      final retryEvidenceId = 'pev_ev_${step.stepId}_retry';
      append(trace,
          type: StrategyEventType.act,
          role: step.role,
          stepId: step.stepId,
          toolName: step.toolName,
          evidenceId: retryEvidenceId,
          summary: 'Retry bounded non-counted PEV action.');
      append(trace,
          type: StrategyEventType.observe,
          role: step.role,
          stepId: step.stepId,
          evidenceId: retryEvidenceId,
          summary: 'Observe retry evidence.');
      evidence.add(evidenceFor(
          step: step,
          evidenceId: retryEvidenceId,
          action: MobileCodeAction.traceWriteArtifact));
      var retryStatus = outcome.retryStatus ?? outcome.firstStatus;
      if (retryStatus == StepVerificationStatus.fail &&
          outcome.failAcceptedAfterRetryFailure) {
        retryStatus = StepVerificationStatus.failAccepted;
      }
      final retry = verificationFor(
        step: step,
        status: retryStatus,
        retryCount: 1,
        evidenceId: retryEvidenceId,
      );
      verifications.add(retry);
      append(trace,
          type: StrategyEventType.verify,
          role: 'VerifierAgent',
          stepId: step.stepId,
          evidenceId: retryEvidenceId,
          summary: 'Verify retry PEV step: ${retry.status.wire}.',
          metadata: retry.toJson());
      if (retry.status == StepVerificationStatus.pass) {
        trace.verificationFailuresRecovered += 1;
      }
    }
    return _StepRunResult(evidence: evidence, verifications: verifications);
  }
}

class ReactWithFinalVerifierStrategyRunner extends _BaseStrategyRunner {
  ReactWithFinalVerifierStrategyRunner({DateTime? startedAt})
      : super(
            strategyId: reactWithFinalVerifierStrategyId, startedAt: startedAt);

  @override
  Future<ReasoningStrategyRunOutput> run(
      ReasoningStrategyRunInput input) async {
    final react =
        await ReactStrategyRunner(maxIterations: 2, startedAt: startedAt).run(
      ReasoningStrategyRunInput(
        userGoal: input.userGoal,
        memoryPacket: input.memoryPacket,
        strategyId: reactSingleAgentStrategyId,
        runKind: input.runKind,
        promptBudget: input.promptBudget,
        toolAccessPolicy: input.toolAccessPolicy,
        maxSteps: input.maxSteps,
      ),
    );
    final trace = newTrace(input);
    for (final event in react.trace.events) {
      trace.appendEvent(event);
    }
    final verifierStep = const StrategyRunnerStep(
      stepId: 'final_verifier',
      task: 'Verify actor trace summary',
      role: 'VerifierAgent',
      toolName: 'final_verifier',
    );
    append(
      trace,
      type: StrategyEventType.verify,
      role: 'VerifierAgent',
      stepId: verifierStep.stepId,
      summary: 'Final verifier received filtered trace summary only.',
      metadata: {
        'input_filter': 'summary_only',
        'raw_transcript_included': false,
      },
    );
    final verification = verificationFor(
      step: verifierStep,
      status: StepVerificationStatus.pass,
      verifierId: 'final_verifier_v1',
    );
    append(trace,
        type: StrategyEventType.report,
        role: 'ReporterAgent',
        summary: 'Final verifier strategy reported non-counted output.');
    return output(
      input: input,
      trace: trace,
      verifications: [verification],
      actionEvidence: react.actionEvidence,
      stepsToCompletion: react.effectMetrics.stepsToCompletion,
    );
  }
}

class SupervisorHandoffStrategyRunner extends _BaseStrategyRunner {
  SupervisorHandoffStrategyRunner({DateTime? startedAt})
      : super(
            strategyId: supervisorHandoffMultiAgentStrategyId,
            startedAt: startedAt);

  @override
  Future<ReasoningStrategyRunOutput> run(
      ReasoningStrategyRunInput input) async {
    final trace = newTrace(input);
    final evidence = <ActionEvidence>[];
    final roles = const [
      (
        'CodeAgent',
        ['read_file', 'apply_patch'],
        HandoffInputFilter.summaryOnly
      ),
      ('RuntimeAgent', ['runtime_check'], HandoffInputFilter.removeToolCalls),
      (
        'PreviewAgent',
        ['webview_preview'],
        HandoffInputFilter.evidenceRefsOnly
      ),
      ('VerifierAgent', ['evidence_record'], HandoffInputFilter.summaryOnly),
      (
        'MemoryAgent',
        ['memory_packet', 'memory_proposal'],
        HandoffInputFilter.removeToolCalls
      ),
      (
        'ReporterAgent',
        ['strategy_report'],
        HandoffInputFilter.evidenceRefsOnly
      ),
    ];
    append(trace,
        type: StrategyEventType.plan,
        role: 'Supervisor',
        summary: 'Supervisor planned specialist handoffs.');
    var index = 0;
    for (final role in roles) {
      index += 1;
      final step = StrategyRunnerStep(
        stepId: 'handoff_${index.toString().padLeft(3, '0')}',
        task: 'Specialist work for ${role.$1}',
        role: role.$1,
        toolName: role.$2.first,
      );
      final packet = HandoffPacket(
        handoffId: 'hoff_${input.memoryPacket.runId}_$index',
        fromRole: 'Supervisor',
        toRole: role.$1,
        reason: 'Specialist capability required',
        priority: 'normal',
        stepId: step.stepId,
        task: step.task,
        inputFilter: role.$3,
        allowedTools: role.$2,
        forbiddenTools: const ['raw_shell', 'untyped_termux'],
        context: {
          'goal_summary': input.userGoal,
          'raw_transcript': 'must be removed',
          'evidence_ids': evidence.map((item) => item.evidenceId).toList(),
          'role_context': {
            'MemoryAgent': {
              'memory_commit_mode': 'proposal_only',
              'durable_write_allowed': false,
            },
            'ReporterAgent': {
              'report_scope': 'summary_and_evidence_refs_only',
            },
          },
        },
      );
      append(
        trace,
        type: StrategyEventType.handoff,
        role: 'Supervisor',
        stepId: step.stepId,
        summary: 'Hand off to ${role.$1} with filtered context.',
        metadata: {'handoff_packet': packet.toJson()},
      );
      final evidenceId = 'handoff_ev_${step.stepId}';
      evidence.add(evidenceFor(
          step: step,
          evidenceId: evidenceId,
          action: MobileCodeAction.traceSelectTool));
      append(trace,
          type: StrategyEventType.observe,
          role: role.$1,
          stepId: step.stepId,
          evidenceId: evidenceId,
          summary: '${role.$1} returned compact evidence.');
    }
    final verifierStep = const StrategyRunnerStep(
        stepId: 'handoff_final',
        task: 'Final handoff verification',
        role: 'VerifierAgent',
        toolName: 'evidence_record');
    final verification = verificationFor(
        step: verifierStep,
        status: StepVerificationStatus.pass,
        verifierId: 'handoff_verifier_v1');
    append(trace,
        type: StrategyEventType.verify,
        role: 'VerifierAgent',
        stepId: verifierStep.stepId,
        summary: 'Verify all handoff return contracts.');
    append(trace,
        type: StrategyEventType.report,
        role: 'ReporterAgent',
        summary: 'Supervisor/Handoff strategy reported non-counted evidence.');
    return output(
        input: input,
        trace: trace,
        verifications: [verification],
        actionEvidence: evidence,
        stepsToCompletion: roles.length);
  }
}

class SwarmRouterStrategyRunner extends _BaseStrategyRunner {
  SwarmRouterStrategyRunner({DateTime? startedAt})
      : super(
            strategyId: swarmRouterMultiAgentStrategyId, startedAt: startedAt);

  @override
  Future<ReasoningStrategyRunOutput> run(
      ReasoningStrategyRunInput input) async {
    final trace = newTrace(input);
    final category =
        input.toolAccessPolicy['task_category']?.toString() ?? 'code_edit';
    final workerGroup =
        category.contains('preview') ? 'PreviewSwarm' : 'CodeSwarm';
    final step = StrategyRunnerStep(
        stepId: 'swarm_001',
        task: 'Route $category',
        role: workerGroup,
        toolName: 'swarm_worker');
    append(trace,
        type: StrategyEventType.plan,
        role: 'SwarmRouter',
        summary: 'Route task by category/device/runtime profile.',
        metadata: {'task_category': category, 'worker_group': workerGroup});
    append(trace,
        type: StrategyEventType.handoff,
        role: 'SwarmRouter',
        stepId: step.stepId,
        summary: 'Dispatch task to $workerGroup.',
        metadata: {
          'worker_group': workerGroup,
          'load': 'low',
          'risk': 'medium'
        });
    final evidenceId = 'swarm_ev_${step.stepId}';
    final evidence = [
      evidenceFor(
          step: step,
          evidenceId: evidenceId,
          action: MobileCodeAction.traceSelectTool)
    ];
    append(trace,
        type: StrategyEventType.observe,
        role: workerGroup,
        stepId: step.stepId,
        evidenceId: evidenceId,
        summary: '$workerGroup returned synthetic result.');
    final verification = verificationFor(
        step: step,
        status: StepVerificationStatus.pass,
        verifierId: 'swarm_judge_v1',
        evidenceId: evidenceId);
    append(trace,
        type: StrategyEventType.verify,
        role: 'JudgeAgent',
        stepId: step.stepId,
        evidenceId: evidenceId,
        summary: 'Judge reviewed swarm output.');
    append(trace,
        type: StrategyEventType.report,
        role: 'SwarmRouter',
        summary: 'Swarm router reported non-counted pilot result.');
    return output(
        input: input,
        trace: trace,
        verifications: [verification],
        actionEvidence: evidence,
        stepsToCompletion: 1);
  }
}

class HierarchicalSwarmStrategyRunner extends _BaseStrategyRunner {
  HierarchicalSwarmStrategyRunner({
    this.maxWorkers = 3,
    this.maxHandoffs = 6,
    DateTime? startedAt,
  }) : super(
            strategyId: hierarchicalSwarmMultiAgentStrategyId,
            startedAt: startedAt);

  final int maxWorkers;
  final int maxHandoffs;

  @override
  Future<ReasoningStrategyRunOutput> run(
      ReasoningStrategyRunInput input) async {
    final trace = newTrace(input);
    final evidence = <ActionEvidence>[];
    final workerCount = maxWorkers.clamp(1, input.maxSteps);
    append(trace,
        type: StrategyEventType.plan,
        role: 'ManagerAgent',
        summary: 'Manager decomposed task into bounded worker subtasks.',
        metadata: {'max_workers': maxWorkers, 'max_handoffs': maxHandoffs});
    for (var index = 0;
        index < workerCount && trace.handoffCount < maxHandoffs;
        index += 1) {
      final step = StrategyRunnerStep(
        stepId: 'hier_${(index + 1).toString().padLeft(3, '0')}',
        task: 'Worker subtask ${index + 1}',
        role: 'WorkerAgent${index + 1}',
        toolName: 'worker_tool',
      );
      append(trace,
          type: StrategyEventType.handoff,
          role: 'ManagerAgent',
          stepId: step.stepId,
          summary: 'Delegate bounded subtask to ${step.role}.');
      final evidenceId = 'hier_ev_${step.stepId}';
      evidence.add(evidenceFor(
          step: step,
          evidenceId: evidenceId,
          action: MobileCodeAction.traceSelectTool));
      append(trace,
          type: StrategyEventType.observe,
          role: step.role,
          stepId: step.stepId,
          evidenceId: evidenceId,
          summary: '${step.role} returned compact output.');
    }
    final judgeStep = const StrategyRunnerStep(
        stepId: 'hier_judge',
        task: 'Judge worker outputs',
        role: 'JudgeAgent',
        toolName: 'judge');
    final verification = verificationFor(
        step: judgeStep,
        status: StepVerificationStatus.pass,
        verifierId: 'hierarchical_judge_v1');
    append(trace,
        type: StrategyEventType.verify,
        role: 'JudgeAgent',
        stepId: judgeStep.stepId,
        summary: 'Judge verified worker outputs.');
    append(trace,
        type: StrategyEventType.report,
        role: 'ManagerAgent',
        summary: 'Manager reconciled worker outputs and reported result.');
    return output(
        input: input,
        trace: trace,
        verifications: [verification],
        actionEvidence: evidence,
        stepsToCompletion: workerCount);
  }
}

class BlockedStrategyRunner extends _BaseStrategyRunner {
  BlockedStrategyRunner({
    required String strategyId,
    required this.reason,
    DateTime? startedAt,
  }) : super(strategyId: strategyId, startedAt: startedAt);

  final String reason;

  @override
  Future<ReasoningStrategyRunOutput> run(
      ReasoningStrategyRunInput input) async {
    final trace = newTrace(input);
    trace.failureKind = reason;
    final step = StrategyRunnerStep(
        stepId: 'blocked_001',
        task: input.userGoal,
        role: 'StrategyGate',
        toolName: 'capability_gate');
    append(trace,
        type: StrategyEventType.scaffold,
        role: 'StrategyGate',
        stepId: step.stepId,
        summary: 'Strategy blocked by capability gate: $reason.');
    final verification = verificationFor(
        step: step,
        status: StepVerificationStatus.blocked,
        verifierId: 'strategy_capability_gate_v1');
    return output(
        input: input,
        trace: trace,
        verifications: [verification],
        actionEvidence: const [],
        stepsToCompletion: 0);
  }
}

List<String> _allowedTools(ReasoningStrategyRunInput input) {
  final value = input.toolAccessPolicy['allowed_tools'];
  if (value is List && value.isNotEmpty) {
    return value.map((item) => item.toString()).toList(growable: false);
  }
  return const ['read_file', 'preview_html', 'evidence_record'];
}

List<StrategyRunnerStep> _planSteps(
    ReasoningStrategyRunInput input, int maxSteps) {
  final count = maxSteps < 3 ? maxSteps.clamp(1, 3) : 3;
  return List.generate(
    count,
    (index) => StrategyRunnerStep(
      stepId: 'step_${(index + 1).toString().padLeft(3, '0')}',
      task: 'PEV step ${index + 1} for ${input.userGoal}',
      role: 'PlannerExecutorVerifier',
      toolName: switch (index) {
        0 => 'read_file',
        1 => 'apply_patch',
        _ => 'evidence_record',
      },
    ),
  );
}

String _finalStatus(List<StepVerification> verifications) {
  final latest = <String, StepVerification>{};
  for (final verification in verifications) {
    latest[verification.stepId] = verification;
  }
  final values = latest.values;
  if (values.any((item) => item.status == StepVerificationStatus.blocked)) {
    return 'blocked';
  }
  if (values.any((item) => item.status == StepVerificationStatus.fail)) {
    return 'failed';
  }
  if (values
      .any((item) => item.status == StepVerificationStatus.failAccepted)) {
    return 'failAccepted';
  }
  return 'passed';
}

String _redact(String value) {
  return value
      .replaceAll(
        RegExp(r'(api[_-]?key|token|secret)\s*[:=]\s*\S+',
            caseSensitive: false),
        r'$1=<redacted>',
      )
      .replaceAll(RegExp(r'/Users/[^ \n\t]+'), '<private_path>')
      .replaceAll(RegExp(r'/Volumes/[^ \n\t]+'), '<private_path>');
}

Map<String, dynamic> _redactMap(Map<String, dynamic> value) {
  return value.map((key, item) {
    if (item is String) {
      return MapEntry(key, _redact(item));
    }
    if (item is Map<String, dynamic>) {
      return MapEntry(key, _redactMap(item));
    }
    if (item is List) {
      return MapEntry(
        key,
        item
            .map((entry) => entry is String
                ? _redact(entry)
                : entry is Map<String, dynamic>
                    ? _redactMap(entry)
                    : entry)
            .toList(growable: false),
      );
    }
    return MapEntry(key, item);
  });
}

class _StepRunResult {
  const _StepRunResult({
    required this.evidence,
    required this.verifications,
  });

  final List<ActionEvidence> evidence;
  final List<StepVerification> verifications;
}
