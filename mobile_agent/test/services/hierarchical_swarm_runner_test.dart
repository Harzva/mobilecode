import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/reasoning_strategy_models.dart';
import 'package:mobile_agent/services/reasoning_strategy_runner_contract.dart';
import 'package:mobile_agent/services/strategy_runners.dart';

void main() {
  group('HierarchicalSwarmStrategyRunner', () {
    test('manager delegates bounded worker subtasks then reconciles', () async {
      final output = await HierarchicalSwarmStrategyRunner(
        maxWorkers: 2,
        maxHandoffs: 3,
        startedAt: DateTime.utc(2026, 6, 20),
      ).run(
        ReasoningStrategyRunInput(
          userGoal: 'Coordinate a bounded multi-artifact task',
          memoryPacket: _memoryPacket(),
          strategyId: hierarchicalSwarmMultiAgentStrategyId,
        ),
      );

      expect(output.trace.events.first.role, 'ManagerAgent');
      expect(output.trace.handoffCount, lessThanOrEqualTo(3));
      expect(output.trace.events.any((event) => event.role == 'JudgeAgent'),
          isTrue);
      expect(output.trace.events.last.role, 'ManagerAgent');
      expect(output.verifications.single.verifierId, 'hierarchical_judge_v1');
      expect(output.countsAsExperiment, isFalse);
    });
  });
}

HarnessMemoryPacket _memoryPacket() {
  return HarnessMemoryPacket(
    packetId: 'hmp-hierarchy',
    schemaVersion: '0.1.0',
    sessionId: 'session-hierarchy',
    runId: 'run-hierarchy',
    createdAt: DateTime.utc(2026, 6, 20),
    ttlSeconds: 86400,
    sourceLimits: const HarnessSourceLimits(),
    userGoal: 'hierarchy test',
    conversationSummary: 'summary only',
    redaction: const HarnessRedaction(applied: true, classes: ['secret']),
  );
}
