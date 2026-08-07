import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/reasoning_strategy_models.dart';
import 'package:mobile_agent/services/reasoning_strategy_runner_contract.dart';
import 'package:mobile_agent/services/strategy_dispatcher.dart';

void main() {
  group('StrategyDispatcher', () {
    test('routes all registered strategy IDs to non-counted runners', () async {
      final dispatcher = StrategyDispatcher.defaultSafe();
      const strategyIds = [
        reactSingleAgentStrategyId,
        planExecuteVerifySingleAgentStrategyId,
        reactWithFinalVerifierStrategyId,
        supervisorHandoffMultiAgentStrategyId,
        swarmRouterMultiAgentStrategyId,
        hierarchicalSwarmMultiAgentStrategyId,
      ];

      for (final strategyId in strategyIds) {
        final output = await dispatcher.run(
          ReasoningStrategyRunInput(
            userGoal: 'Route $strategyId',
            memoryPacket: _memoryPacket(runId: 'run-$strategyId'),
            strategyId: strategyId,
            runKind: strategyPilotNotCounted,
          ),
        );

        expect(output.runKind, strategyPilotNotCounted, reason: strategyId);
        expect(output.trace.strategyId, strategyId, reason: strategyId);
        expect(output.countsAsExperiment, isFalse, reason: strategyId);
        expect(output.trace.events, isNotEmpty, reason: strategyId);
      }
    });

    test('falls back to safe auto PEV runner for unknown strategy IDs',
        () async {
      final output = await StrategyDispatcher.defaultSafe().run(
        ReasoningStrategyRunInput(
          userGoal: 'Unknown strategy',
          memoryPacket: _memoryPacket(),
          strategyId: 'unknown_strategy',
        ),
      );

      expect(output.trace.strategyId, planExecuteVerifySingleAgentStrategyId);
      expect(output.promotionDecision.allowed, isFalse);
    });

    test('blocks experimental strategies when capability gate disables them',
        () async {
      final dispatcher = StrategyDispatcher.defaultSafe(
        capabilities: const StrategyCapabilities(
          enableExperimentalSwarm: false,
        ),
      );

      final output = await dispatcher.run(
        ReasoningStrategyRunInput(
          userGoal: 'Try swarm',
          memoryPacket: _memoryPacket(),
          strategyId: swarmRouterMultiAgentStrategyId,
        ),
      );

      expect(output.trace.strategyId, swarmRouterMultiAgentStrategyId);
      expect(
          output.verifications.single.status, StepVerificationStatus.blocked);
      expect(output.trace.failureKind, 'experimental_strategy_disabled');
      expect(output.countsAsExperiment, isFalse);
    });
  });
}

HarnessMemoryPacket _memoryPacket({String runId = 'run-dispatcher'}) {
  return HarnessMemoryPacket(
    packetId: 'hmp-$runId',
    schemaVersion: '0.1.0',
    sessionId: 'session-dispatcher',
    runId: runId,
    createdAt: DateTime.utc(2026, 6, 20),
    ttlSeconds: 86400,
    sourceLimits: const HarnessSourceLimits(),
    userGoal: 'dispatcher test',
    conversationSummary: 'summary only',
    redaction: const HarnessRedaction(applied: true, classes: ['secret']),
  );
}
