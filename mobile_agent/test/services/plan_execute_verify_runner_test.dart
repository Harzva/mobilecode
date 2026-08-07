import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/reasoning_strategy_models.dart';
import 'package:mobile_agent/services/reasoning_strategy_runner_contract.dart';
import 'package:mobile_agent/services/strategy_runners.dart';

void main() {
  group('PlanExecuteVerifyStrategyRunner', () {
    test('plans 3 steps and gates every step with verification', () async {
      final output = await PlanExecuteVerifyStrategyRunner(
        startedAt: DateTime.utc(2026, 6, 20),
      ).run(
        ReasoningStrategyRunInput(
          userGoal: 'Generate preview and verify',
          memoryPacket: _memoryPacket(),
          strategyId: planExecuteVerifySingleAgentStrategyId,
          maxSteps: 4,
        ),
      );

      expect(output.trace.events.first.type, StrategyEventType.plan);
      expect(output.verifications.length, 3);
      expect(
          output.trace.events
              .where((event) => event.type == StrategyEventType.verify),
          hasLength(3));
      expect(output.actionEvidence.length, 3);
      expect(output.countsAsExperiment, isFalse);
    });

    test('records replan and recovered verification when retry succeeds',
        () async {
      final output = await PlanExecuteVerifyStrategyRunner(
        startedAt: DateTime.utc(2026, 6, 20),
        scriptedOutcomes: const [
          StrategyStepOutcome(
            stepId: 'step_001',
            firstStatus: StepVerificationStatus.fail,
            retryStatus: StepVerificationStatus.pass,
            retryAllowed: true,
          ),
        ],
      ).run(
        ReasoningStrategyRunInput(
          userGoal: 'Retry one step',
          memoryPacket: _memoryPacket(runId: 'run-pev-retry'),
          strategyId: planExecuteVerifySingleAgentStrategyId,
        ),
      );

      expect(output.trace.planningRevisions, 1);
      expect(output.trace.verificationFailuresRecovered, 1);
      expect(output.trace.failureKind, isNull);
    });
  });
}

HarnessMemoryPacket _memoryPacket({String runId = 'run-pev'}) {
  return HarnessMemoryPacket(
    packetId: 'hmp-$runId',
    schemaVersion: '0.1.0',
    sessionId: 'session-pev',
    runId: runId,
    createdAt: DateTime.utc(2026, 6, 20),
    ttlSeconds: 86400,
    sourceLimits: const HarnessSourceLimits(),
    userGoal: 'pev test',
    conversationSummary: 'summary only',
    redaction: const HarnessRedaction(applied: true, classes: ['secret']),
  );
}
