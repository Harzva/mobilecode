import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/reasoning_strategy_models.dart';
import 'package:mobile_agent/services/reasoning_strategy_pilot_runner.dart';
import 'package:mobile_agent/services/reasoning_strategy_runner_contract.dart';

void main() {
  group('NonCountedReasoningStrategyPilotRunner', () {
    test('implements runner contract and emits non-counted pilot output', () async {
      final runner = NonCountedReasoningStrategyPilotRunner();
      final output = await runner.run(
        ReasoningStrategyRunInput(
          userGoal: 'Pilot fake runner contract',
          memoryPacket: _memoryPacket(),
          strategyId: 'plan_execute_verify_single_agent',
          runKind: strategyPilotNotCounted,
        ),
      );

      expect(output.runKind, strategyPilotNotCounted);
      expect(output.countsAsExperiment, isFalse);
      expect(output.trace.strategyId, 'plan_execute_verify_single_agent');
      expect(output.verifications, isNotEmpty);
      expect(output.actionEvidence, hasLength(output.trace.events.length));
      expect(output.toJson()['counts_as_strategy_ablation_result'], isFalse);
    });

    test('downgrades requested counted result to non-counted fake pilot', () async {
      final runner = NonCountedReasoningStrategyPilotRunner(
        evidenceManifest: const StrategyEvidenceManifest(
          modelLogIds: ['model-log'],
          tokenRecordIds: ['token-record'],
          verifierEvidenceIds: ['verifier'],
          toolEvidenceIds: ['tool'],
          deviceEvidenceIds: ['device'],
        ),
      );
      final output = await runner.run(
        ReasoningStrategyRunInput(
          userGoal: 'Do not count fake pilot',
          memoryPacket: _memoryPacket(),
          strategyId: 'plan_execute_verify_single_agent',
          runKind: strategyAblationResult,
        ),
      );

      expect(output.runKind, strategyPilotNotCounted);
      expect(output.countsAsExperiment, isFalse);
      expect(output.promotionDecision.reason, 'fake_pilot_runner_never_promotes_to_counted_result');
      expect(output.toJson()['counts_as_experiment'], isFalse);
    });

    test('keeps scaffold run kind when explicitly requested', () async {
      final output = await NonCountedReasoningStrategyPilotRunner().run(
        ReasoningStrategyRunInput(
          userGoal: 'Scaffold fake output',
          memoryPacket: _memoryPacket(),
          strategyId: 'plan_execute_verify_single_agent',
          runKind: strategyScaffoldNotRun,
        ),
      );

      expect(output.runKind, strategyScaffoldNotRun);
      expect(output.trace.traceStatus.wire, 'scaffold_not_run');
      expect(output.countsAsExperiment, isFalse);
    });
  });
}

HarnessMemoryPacket _memoryPacket() {
  return HarnessMemoryPacket(
    packetId: 'hmp-run-p4a-001',
    schemaVersion: '0.1.0',
    sessionId: 'session-p4a',
    runId: 'run-p4a',
    createdAt: DateTime.utc(2026, 5, 1),
    ttlSeconds: 86400,
    sourceLimits: const HarnessSourceLimits(),
    userGoal: 'fake pilot contract',
    conversationSummary: 'summary only',
    redaction: const HarnessRedaction(applied: true, classes: ['secret']),
  );
}
