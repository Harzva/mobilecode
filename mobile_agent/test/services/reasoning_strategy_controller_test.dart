import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/fake_reasoning_strategy_runner.dart';
import 'package:mobile_agent/services/reasoning_strategy_controller.dart';
import 'package:mobile_agent/services/reasoning_strategy_models.dart';

void main() {
  group('ReasoningStrategyController P3-lite', () {
    test('builds compact redacted HarnessMemoryPacket without durable writes', () {
      final controller = ReasoningStrategyController();
      final packet = controller.buildMemoryPacket(
        ReasoningStrategyControllerRequest(
          userGoal: 'Create fake benchmark adapter',
          sessionId: 'session-p3',
          runId: 'run-p3',
          conversationSummary: 'summary-${List.filled(100, 'x').join()}',
          sourceLimits: const HarnessSourceLimits(recentTurns: 1, maxChars: 80, maxErrorPatterns: 1),
          recentTurns: const [
            HarnessRecentTurn(role: 'user', summary: 'first turn'),
            HarnessRecentTurn(role: 'assistant', summary: 'second turn'),
          ],
          errorPatterns: const [
            {'pattern': 'one'},
            {'pattern': 'two'},
          ],
          createdAt: DateTime.utc(2026, 3, 1),
        ),
      );

      expect(packet.packetId, 'hmp_run-p3_001');
      expect(packet.sessionId, 'session-p3');
      expect(packet.redaction.applied, isTrue);
      expect(packet.redaction.classes, contains('raw_transcript'));
      expect(packet.recentTurns, hasLength(1));
      expect(packet.recentTurns.single.summary, 'second turn');
      expect(packet.errorPatterns, hasLength(1));
      expect(packet.isExpired(DateTime.utc(2026, 3, 2, 0, 0, 1)), isTrue);
    });

    test('runs fake closed loop and maps trace events to non-counted evidence', () {
      final result = ReasoningStrategyController().runFakeClosedLoop(
        ReasoningStrategyControllerRequest(
          userGoal: 'Run fake P3-lite controller',
          sessionId: 'session-p3',
          runId: 'run-p3',
          strategyId: 'plan_execute_verify_single_agent',
          steps: const [
            FakeReasoningStep(stepId: 'step_001', task: 'fake adapter step'),
          ],
          createdAt: DateTime.utc(2026, 3, 1),
        ),
      );

      expect(result.finalStatus, 'passed');
      expect(result.countsAsExperiment, isFalse);
      expect(result.trace.strategyId, 'plan_execute_verify_single_agent');
      expect(result.evidence, hasLength(result.trace.events.length));
      expect(result.evidence.every((item) => item.success == false), isTrue);
      expect(
        result.evidence.every(
          (item) => item.metadata['counts_as_strategy_ablation_result'] == false,
        ),
        isTrue,
      );
      expect(result.evidence.first.failureKind, 'dryRunNotCounted');
    });

    test('exports benchmark dry-run record with null metrics and evidence boundary', () {
      final result = ReasoningStrategyController().runFakeClosedLoop(
        ReasoningStrategyControllerRequest(
          userGoal: 'Export dry-run record',
          sessionId: 'session-p3',
          runId: 'run-p3',
          runKind: 'strategy_scaffold_not_run',
          steps: const [
            FakeReasoningStep(stepId: 'step_001', task: 'fake scaffold step'),
          ],
        ),
      );

      final record = result.toBenchmarkDryRunRecord();
      final timeMetrics = record['time_metrics'] as Map<String, dynamic>;
      final tokenMetrics = record['token_metrics'] as Map<String, dynamic>;
      final effectMetrics = record['effect_metrics'] as Map<String, dynamic>;

      expect(record['counts_as_experiment'], isFalse);
      expect(record['counts_as_strategy_ablation_result'], isFalse);
      expect(record['run_kind'], 'strategy_scaffold_not_run');
      expect(record['trace_status'], 'scaffold_not_run');
      expect(record['evidence_boundary'], contains('p3_lite_fake_controller_only'));
      expect(timeMetrics.values.every((value) => value == null), isTrue);
      expect(tokenMetrics.values.every((value) => value == null), isTrue);
      expect(effectMetrics.values.every((value) => value == null), isTrue);
    });

    test('preserves fake retry semantics through controller result', () {
      final result = ReasoningStrategyController().runFakeClosedLoop(
        ReasoningStrategyControllerRequest(
          userGoal: 'Retry through controller',
          sessionId: 'session-p3',
          runId: 'run-p3',
          steps: const [
            FakeReasoningStep(stepId: 'step_001', task: 'fake flaky adapter step'),
          ],
          scriptedOutcomes: const [
            FakeStepScriptedOutcome(
              stepId: 'step_001',
              firstStatus: StepVerificationStatus.fail,
              retryStatus: StepVerificationStatus.pass,
              retryAllowed: true,
            ),
          ],
        ),
      );

      expect(result.finalStatus, 'passed');
      expect(result.verifications.map((item) => item.status), [
        StepVerificationStatus.fail,
        StepVerificationStatus.pass,
      ]);
      expect(result.trace.verificationFailuresRecovered, 1);
      expect(result.trace.planningRevisions, 1);
    });
  });
}
