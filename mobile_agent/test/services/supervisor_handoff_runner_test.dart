import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/reasoning_strategy_models.dart';
import 'package:mobile_agent/services/reasoning_strategy_runner_contract.dart';
import 'package:mobile_agent/services/strategy_runners.dart';

void main() {
  group('SupervisorHandoffStrategyRunner', () {
    test('creates filtered handoff packets for specialist roles', () async {
      final output = await SupervisorHandoffStrategyRunner(
        startedAt: DateTime.utc(2026, 6, 20),
      ).run(
        ReasoningStrategyRunInput(
          userGoal: 'Coordinate code preview verification',
          memoryPacket: _memoryPacket(),
          strategyId: supervisorHandoffMultiAgentStrategyId,
        ),
      );

      expect(output.trace.handoffCount, 6);
      expect(output.trace.events.map((event) => event.type),
          contains(StrategyEventType.handoff));
      final handoffEvents = output.trace.events
          .where((event) => event.type == StrategyEventType.handoff);
      final roles = <String>{};
      final filters = <String>{};
      for (final event in handoffEvents) {
        final packet = event.metadata['handoff_packet'] as Map<String, dynamic>;
        roles.add(packet['to_role'] as String);
        filters.add(packet['input_filter'] as String);
        expect(packet.toString(), isNot(contains('raw_transcript')));
        expect(packet['allowed_tools'], isA<List<dynamic>>());
        expect(packet['allowed_tools'], isNotEmpty);
        expect(packet['return_contract']['no_raw_secret_echo'], isTrue);
      }
      expect(
        roles,
        containsAll({
          'CodeAgent',
          'RuntimeAgent',
          'PreviewAgent',
          'VerifierAgent',
          'MemoryAgent',
          'ReporterAgent',
        }),
      );
      expect(
          filters,
          containsAll(
              {'summary_only', 'remove_tool_calls', 'evidence_refs_only'}));
      expect(output.countsAsExperiment, isFalse);
    });
  });
}

HarnessMemoryPacket _memoryPacket() {
  return HarnessMemoryPacket(
    packetId: 'hmp-handoff',
    schemaVersion: '0.1.0',
    sessionId: 'session-handoff',
    runId: 'run-handoff',
    createdAt: DateTime.utc(2026, 6, 20),
    ttlSeconds: 86400,
    sourceLimits: const HarnessSourceLimits(),
    userGoal: 'handoff test',
    conversationSummary: 'summary only',
    redaction: const HarnessRedaction(applied: true, classes: ['secret']),
  );
}
