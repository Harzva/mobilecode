import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/reasoning_strategy_models.dart';
import 'package:mobile_agent/services/reasoning_strategy_runner_contract.dart';
import 'package:mobile_agent/services/strategy_runners.dart';

void main() {
  group('ReactStrategyRunner', () {
    test('emits think act observe repeat report with action evidence',
        () async {
      final output = await ReactStrategyRunner(
        maxIterations: 2,
        startedAt: DateTime.utc(2026, 6, 20),
      ).run(
        ReasoningStrategyRunInput(
          userGoal: 'Build a tiny preview',
          memoryPacket: _memoryPacket(),
          strategyId: reactSingleAgentStrategyId,
          runKind: strategyPilotNotCounted,
          toolAccessPolicy: const {
            'allowed_tools': ['read_file', 'preview_html'],
          },
        ),
      );

      expect(output.trace.strategyId, reactSingleAgentStrategyId);
      expect(
          output.trace.events.map((event) => event.type),
          containsAllInOrder([
            StrategyEventType.think,
            StrategyEventType.act,
            StrategyEventType.observe,
            StrategyEventType.think,
            StrategyEventType.act,
            StrategyEventType.observe,
            StrategyEventType.report,
          ]));
      expect(output.actionEvidence.length, 2);
      expect(output.countsAsExperiment, isFalse);
    });
  });
}

HarnessMemoryPacket _memoryPacket() {
  return HarnessMemoryPacket(
    packetId: 'hmp-react',
    schemaVersion: '0.1.0',
    sessionId: 'session-react',
    runId: 'run-react',
    createdAt: DateTime.utc(2026, 6, 20),
    ttlSeconds: 86400,
    sourceLimits: const HarnessSourceLimits(),
    userGoal: 'react test',
    conversationSummary: 'summary only',
    redaction: const HarnessRedaction(applied: true, classes: ['secret']),
  );
}
