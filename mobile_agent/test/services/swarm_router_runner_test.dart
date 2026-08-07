import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/reasoning_strategy_models.dart';
import 'package:mobile_agent/services/reasoning_strategy_runner_contract.dart';
import 'package:mobile_agent/services/strategy_runners.dart';

void main() {
  group('SwarmRouterStrategyRunner', () {
    test('routes by task category and records judge verification', () async {
      final output = await SwarmRouterStrategyRunner(
        startedAt: DateTime.utc(2026, 6, 20),
      ).run(
        ReasoningStrategyRunInput(
          userGoal: 'Preview a generated html artifact',
          memoryPacket: _memoryPacket(),
          strategyId: swarmRouterMultiAgentStrategyId,
          toolAccessPolicy: const {
            'task_category': 'preview_verification',
            'device_tier': 'android_emulator',
          },
        ),
      );

      expect(
          output.trace.events.map((event) => event.type),
          containsAll([
            StrategyEventType.plan,
            StrategyEventType.handoff,
            StrategyEventType.verify,
            StrategyEventType.report,
          ]));
      expect(output.trace.events.any((event) => event.role == 'SwarmRouter'),
          isTrue);
      expect(output.verifications.single.verifierId, 'swarm_judge_v1');
      expect(output.countsAsExperiment, isFalse);
    });
  });
}

HarnessMemoryPacket _memoryPacket() {
  return HarnessMemoryPacket(
    packetId: 'hmp-swarm',
    schemaVersion: '0.1.0',
    sessionId: 'session-swarm',
    runId: 'run-swarm',
    createdAt: DateTime.utc(2026, 6, 20),
    ttlSeconds: 86400,
    sourceLimits: const HarnessSourceLimits(),
    userGoal: 'swarm test',
    conversationSummary: 'summary only',
    redaction: const HarnessRedaction(applied: true, classes: ['secret']),
  );
}
