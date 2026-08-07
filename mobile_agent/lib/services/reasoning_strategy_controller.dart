/// P3-lite controller for Mobile Harness Reasoning Strategy.
///
/// This is an adapter layer only. It does not replace AgentLoopController, does
/// not call a provider, does not run real tools, and does not write durable
/// memory. It turns the P1/P2 models and fake PEV runner into a small app-level
/// entry point that future real runners can replace.
library;

import '../core/evidence/evidence_model.dart';
import 'fake_reasoning_strategy_runner.dart';
import 'reasoning_strategy_models.dart';

class ReasoningStrategyControllerRequest {
  const ReasoningStrategyControllerRequest({
    required this.userGoal,
    required this.sessionId,
    required this.runId,
    this.strategyId = 'plan_execute_verify_single_agent',
    this.runKind = 'strategy_dry_run_not_counted',
    this.memoryPacket,
    this.conversationSummary = '',
    this.recentTurns = const [],
    this.projectFacts = const [],
    this.userPreferences = const [],
    this.errorPatterns = const [],
    this.activeConstraints = const [
      'no network',
      'no real model',
      'no real device',
      'no counted benchmark result',
    ],
    this.redaction = const HarnessRedaction(
      applied: true,
      classes: ['secret', 'token', 'raw_transcript'],
    ),
    this.sourceLimits = const HarnessSourceLimits(),
    this.steps = const [],
    this.scriptedOutcomes = const [],
    this.createdAt,
  });

  final String userGoal;
  final String sessionId;
  final String runId;
  final String strategyId;
  final String runKind;
  final HarnessMemoryPacket? memoryPacket;
  final String conversationSummary;
  final List<HarnessRecentTurn> recentTurns;
  final List<Map<String, dynamic>> projectFacts;
  final List<Map<String, dynamic>> userPreferences;
  final List<Map<String, dynamic>> errorPatterns;
  final List<String> activeConstraints;
  final HarnessRedaction redaction;
  final HarnessSourceLimits sourceLimits;
  final List<FakeReasoningStep> steps;
  final List<FakeStepScriptedOutcome> scriptedOutcomes;
  final DateTime? createdAt;
}

class ReasoningStrategyControllerResult {
  const ReasoningStrategyControllerResult({
    required this.memoryPacket,
    required this.fakeResult,
    required this.evidence,
  });

  final HarnessMemoryPacket memoryPacket;
  final FakeReasoningStrategyResult fakeResult;
  final List<ActionEvidence> evidence;

  StrategyTrace get trace => fakeResult.trace;

  List<StepVerification> get verifications => fakeResult.verifications;

  String get finalStatus => fakeResult.finalStatus;

  bool get countsAsExperiment => false;

  Map<String, dynamic> toBenchmarkDryRunRecord() => {
        'run_kind': fakeResult.runKind,
        'strategy_id': trace.strategyId,
        'trace_status': trace.traceStatus.wire,
        'final_status': finalStatus,
        'counts_as_experiment': false,
        'counts_as_strategy_ablation_result': false,
        'memory_packet_id': memoryPacket.packetId,
        'trace': trace.toBenchmarkJson(),
        'step_verifications': verifications.map((item) => item.toJson()).toList(),
        'evidence': evidence.map((item) => item.toJson()).toList(),
        'time_metrics': _nullTimeMetrics(),
        'token_metrics': _nullTokenMetrics(),
        'effect_metrics': _dryRunEffectMetrics(),
        'evidence_boundary': 'p3_lite_fake_controller_only_no_model_no_device_no_network',
      };
}

class ReasoningStrategyController {
  ReasoningStrategyController({FakeReasoningStrategyRunner? runner})
      : _runner = runner ?? FakeReasoningStrategyRunner();

  final FakeReasoningStrategyRunner _runner;

  HarnessMemoryPacket buildMemoryPacket(ReasoningStrategyControllerRequest request) {
    final createdAt = request.createdAt ?? DateTime.now().toUtc();
    final packet = request.memoryPacket ??
        HarnessMemoryPacket(
          packetId: 'hmp_${request.runId}_001',
          schemaVersion: '0.1.0',
          sessionId: request.sessionId,
          runId: request.runId,
          createdAt: createdAt,
          ttlSeconds: 86400,
          sourceLimits: request.sourceLimits,
          userGoal: request.userGoal,
          conversationSummary: request.conversationSummary,
          recentTurns: request.recentTurns,
          projectFacts: request.projectFacts,
          userPreferences: request.userPreferences,
          errorPatterns: request.errorPatterns,
          activeConstraints: request.activeConstraints,
          redaction: request.redaction,
        );
    return packet.compacted(
      maxChars: packet.sourceLimits.maxChars,
      recentTurnsLimit: packet.sourceLimits.recentTurns,
      maxErrorPatterns: packet.sourceLimits.maxErrorPatterns,
    );
  }

  ReasoningStrategyControllerResult runFakeClosedLoop(
    ReasoningStrategyControllerRequest request,
  ) {
    final memoryPacket = buildMemoryPacket(request);
    final fakeResult = _runner.run(
      FakeReasoningStrategyRequest(
        userGoal: request.userGoal,
        memoryPacket: memoryPacket,
        strategyId: request.strategyId,
        steps: request.steps,
        scriptedOutcomes: request.scriptedOutcomes,
        runKind: request.runKind,
      ),
    );
    return ReasoningStrategyControllerResult(
      memoryPacket: memoryPacket,
      fakeResult: fakeResult,
      evidence: _traceEventsToNonCountedEvidence(fakeResult.trace),
    );
  }

  List<ActionEvidence> _traceEventsToNonCountedEvidence(StrategyTrace trace) {
    return trace.events.map((event) {
      final startedAt = event.startedAt;
      return ActionEvidence(
        evidenceId: event.evidenceId ?? 'p3_${trace.traceId}_${event.eventId}',
        actionName: _actionForEvent(event.type),
        paramsSummary: event.summary,
        startedAt: startedAt,
        endedAt: event.endedAt ?? startedAt,
        success: false,
        logs: [
          'P3-lite fake controller evidence.',
          'event=${event.type.wire}',
          'counts_as_experiment=false',
        ],
        failureKind: 'dryRunNotCounted',
        recoveryActions: const [
          'Run a real model/tool/device verifier before promoting this trace to a counted result.',
        ],
        metadata: {
          'trace_id': trace.traceId,
          'strategy_id': trace.strategyId,
          'event_id': event.eventId,
          'event_type': event.type.wire,
          'step_id': event.stepId,
          'role': event.role,
          'dry_run_not_counted': true,
          'counts_as_experiment': false,
          'counts_as_strategy_ablation_result': false,
        },
      );
    }).toList(growable: false);
  }

  MobileCodeAction _actionForEvent(StrategyEventType type) {
    return switch (type) {
      StrategyEventType.plan => MobileCodeAction.traceParseInstruction,
      StrategyEventType.think => MobileCodeAction.traceSelectTool,
      StrategyEventType.act => MobileCodeAction.traceCallProvider,
      StrategyEventType.observe => MobileCodeAction.traceWriteArtifact,
      StrategyEventType.verify => MobileCodeAction.traceReportChat,
      StrategyEventType.report => MobileCodeAction.traceReportChat,
      StrategyEventType.handoff => MobileCodeAction.traceSelectTool,
      StrategyEventType.scaffold => MobileCodeAction.traceParseInstruction,
      StrategyEventType.replan => MobileCodeAction.traceParseInstruction,
      StrategyEventType.memoryCommit => MobileCodeAction.traceWriteArtifact,
    };
  }
}

Map<String, dynamic> _nullTimeMetrics() => const {
      'wall_time_ms': null,
      'planning_time_ms': null,
      'execution_time_ms': null,
      'verification_time_ms': null,
      'reporting_time_ms': null,
    };

Map<String, dynamic> _nullTokenMetrics() => const {
      'prompt_tokens': null,
      'completion_tokens': null,
      'total_tokens': null,
      'tool_input_chars': null,
      'tool_output_chars': null,
      'estimated_tool_tokens': null,
    };

Map<String, dynamic> _dryRunEffectMetrics() => const {
      'task_success': null,
      'verified_success': null,
      'trace_completeness': null,
      'recovery_rate': null,
      'artifact_availability': null,
      'human_intervention_count': null,
      'steps_to_completion': null,
      'strategy_overhead_steps': null,
      'handoff_count': null,
      'planning_revisions': null,
      'verification_failures_recovered': null,
    };
