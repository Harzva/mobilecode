import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/reasoning_strategy_models.dart';
import 'package:mobile_agent/services/reasoning_strategy_real_runner_adapter.dart';
import 'package:mobile_agent/services/reasoning_strategy_runner_contract.dart';

void main() {
  group('ReasoningStrategyRealRunnerAdapter', () {
    test('default callbacks are blocked and non-counted', () async {
      final output = await ReasoningStrategyRealRunnerAdapter(
        startedAt: DateTime.utc(2026, 6, 1),
      ).run(
        ReasoningStrategyRunInput(
          userGoal: 'Default blocked skeleton',
          memoryPacket: _memoryPacket(),
          strategyId: 'plan_execute_verify_single_agent',
        ),
      );

      expect(output.runKind, strategyPilotNotCounted);
      expect(output.countsAsExperiment, isFalse);
      expect(output.trace.traceStatus, StrategyTraceStatus.dryRunNotCounted);
      expect(output.verifications.single.status, StepVerificationStatus.blocked);
      expect(output.actionEvidence.single.success, isFalse);
      expect(output.actionEvidence.single.failureKind, 'defaultBlockedToolCallback');
      expect(output.toJson()['counts_as_strategy_ablation_result'], isFalse);
    });

    test('injected fake callbacks can pass but still remain non-counted', () async {
      final output = await ReasoningStrategyRealRunnerAdapter(
        startedAt: DateTime.utc(2026, 6, 1),
        modelCallback: (request) async => StrategyModelCallbackResult(
          status: 'completed',
          content: request.phase == 'planning' ? 'create fake artifact then verify it' : 'call fake tool',
          promptTokens: 10,
          completionTokens: 5,
          modelLogId: 'model-${request.phase}',
        ),
        toolCallback: (request) async => StrategyToolCallbackResult(
          status: 'succeeded',
          observation: 'fake observation for ${request.stepId}',
          inputChars: 40,
          outputChars: 80,
          evidenceId: 'tool-ev-${request.stepId}',
          artifactPaths: const ['fake/out.html'],
        ),
        verifierCallback: (request) async => StepVerification(
          stepId: request.stepId,
          status: StepVerificationStatus.pass,
          confidence: 0.9,
          checks: [
            StepVerificationCheck(
              name: 'fake_adapter_verifier',
              status: StepVerificationStatus.pass,
              evidenceId: request.toolResult.evidenceId,
            ),
          ],
          evidenceIds: [request.toolResult.evidenceId ?? 'missing'],
          countsAsVerifiedSuccess: false,
        ),
      ).run(
        ReasoningStrategyRunInput(
          userGoal: 'Injected fake callbacks',
          memoryPacket: _memoryPacket(),
          strategyId: 'plan_execute_verify_single_agent',
        ),
      );

      expect(output.verifications.single.status, StepVerificationStatus.pass);
      expect(output.actionEvidence.single.artifactPaths, ['fake/out.html']);
      expect(output.tokenMetrics.promptTokens, 20);
      expect(output.tokenMetrics.completionTokens, 10);
      expect(output.tokenMetrics.toolInputChars, 40);
      expect(output.tokenMetrics.toolOutputChars, 80);
      expect(output.countsAsExperiment, isFalse);
      expect(output.promotionDecision.allowed, isFalse);
    });

    test('requested counted result is downgraded unless a later phase enables it', () async {
      final output = await ReasoningStrategyRealRunnerAdapter(
        startedAt: DateTime.utc(2026, 6, 1),
        allowCountedPromotion: true,
        evidenceManifest: const StrategyEvidenceManifest(
          modelLogIds: ['model-log'],
          tokenRecordIds: ['token'],
          verifierEvidenceIds: ['verifier'],
          toolEvidenceIds: ['tool'],
          deviceEvidenceIds: ['device'],
        ),
        modelCallback: (request) async => const StrategyModelCallbackResult(
          status: 'completed',
          content: 'fake callback',
          promptTokens: 1,
          completionTokens: 1,
          modelLogId: 'model-log',
        ),
        toolCallback: (request) async => const StrategyToolCallbackResult(
          status: 'succeeded',
          observation: 'fake tool callback',
          evidenceId: 'tool',
        ),
        verifierCallback: (request) async => StepVerification(
          stepId: request.stepId,
          status: StepVerificationStatus.pass,
          confidence: 0.9,
          evidenceIds: const ['verifier'],
          countsAsVerifiedSuccess: false,
        ),
      ).run(
        ReasoningStrategyRunInput(
          userGoal: 'Attempt counted run',
          memoryPacket: _memoryPacket(),
          strategyId: 'plan_execute_verify_single_agent',
          runKind: strategyAblationResult,
        ),
      );

      expect(output.runKind, strategyPilotNotCounted);
      expect(output.countsAsExperiment, isFalse);
      expect(output.promotionDecision.reason, 'p4b_adapter_skeleton_never_promotes_without_later_review_gate');
      expect(output.toJson()['counts_as_experiment'], isFalse);
    });

    test('scaffold run keeps scaffold trace status', () async {
      final output = await ReasoningStrategyRealRunnerAdapter(
        startedAt: DateTime.utc(2026, 6, 1),
      ).run(
        ReasoningStrategyRunInput(
          userGoal: 'Scaffold run',
          memoryPacket: _memoryPacket(),
          strategyId: 'plan_execute_verify_single_agent',
          runKind: strategyScaffoldNotRun,
        ),
      );

      expect(output.runKind, strategyScaffoldNotRun);
      expect(output.trace.traceStatus, StrategyTraceStatus.scaffoldNotRun);
      expect(output.countsAsExperiment, isFalse);
    });
  });
}

HarnessMemoryPacket _memoryPacket() {
  return HarnessMemoryPacket(
    packetId: 'hmp-run-p4b-001',
    schemaVersion: '0.1.0',
    sessionId: 'session-p4b',
    runId: 'run-p4b',
    createdAt: DateTime.utc(2026, 6, 1),
    ttlSeconds: 86400,
    sourceLimits: const HarnessSourceLimits(),
    userGoal: 'real runner adapter skeleton',
    conversationSummary: 'summary only',
    redaction: const HarnessRedaction(applied: true, classes: ['secret']),
  );
}
