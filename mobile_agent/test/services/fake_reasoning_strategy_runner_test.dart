import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/fake_reasoning_strategy_runner.dart';
import 'package:mobile_agent/services/reasoning_strategy_models.dart';

void main() {
  group('FakeReasoningStrategyRunner', () {
    test('happy path emits plan -> execute -> verify -> report', () {
      final result = FakeReasoningStrategyRunner().run(
        FakeReasoningStrategyRequest(
          userGoal: 'Create a fake preview artifact',
          memoryPacket: _memoryPacket(),
          strategyId: 'plan_execute_verify_single_agent',
          steps: const [
            FakeReasoningStep(stepId: 'step_001', task: 'fake edit'),
            FakeReasoningStep(stepId: 'step_002', task: 'fake verify'),
          ],
        ),
      );

      expect(result.finalStatus, 'passed');
      expect(result.countsAsExperiment, isFalse);
      expect(result.runKind, 'strategy_dry_run_not_counted');
      expect(result.verifications, hasLength(2));
      expect(result.verifications.every((item) => item.countsAsVerifiedSuccess == false), isTrue);
      expect(result.trace.traceStatus, StrategyTraceStatus.dryRunNotCounted);
      expect(result.trace.events.map((event) => event.type).toList(), [
        StrategyEventType.scaffold,
        StrategyEventType.plan,
        StrategyEventType.think,
        StrategyEventType.act,
        StrategyEventType.observe,
        StrategyEventType.verify,
        StrategyEventType.think,
        StrategyEventType.act,
        StrategyEventType.observe,
        StrategyEventType.verify,
        StrategyEventType.report,
      ]);
      expect(result.toJson()['evidence_boundary'], contains('fake_runner_only'));
    });

    test('retry path recovers fail -> retry -> pass', () {
      final result = FakeReasoningStrategyRunner().run(
        FakeReasoningStrategyRequest(
          userGoal: 'Retry a fake verifier failure',
          memoryPacket: _memoryPacket(),
          strategyId: 'plan_execute_verify_single_agent',
          steps: const [
            FakeReasoningStep(stepId: 'step_001', task: 'fake flaky step'),
          ],
          scriptedOutcomes: const [
            FakeStepScriptedOutcome(
              stepId: 'step_001',
              firstStatus: StepVerificationStatus.fail,
              retryStatus: StepVerificationStatus.pass,
              retryAllowed: true,
              issues: ['first fake attempt failed'],
            ),
          ],
        ),
      );

      expect(result.finalStatus, 'passed');
      expect(result.verifications.map((item) => item.status), [
        StepVerificationStatus.fail,
        StepVerificationStatus.pass,
      ]);
      expect(result.trace.planningRevisions, 1);
      expect(result.trace.verificationFailuresRecovered, 1);
      expect(result.trace.events.map((event) => event.type), contains(StrategyEventType.replan));
    });

    test('failure path supports failAccepted after retry failure', () {
      final result = FakeReasoningStrategyRunner().run(
        FakeReasoningStrategyRequest(
          userGoal: 'Accept fake failure after retry budget',
          memoryPacket: _memoryPacket(),
          strategyId: 'plan_execute_verify_single_agent',
          steps: const [
            FakeReasoningStep(stepId: 'step_001', task: 'fake unrecoverable warning'),
          ],
          scriptedOutcomes: const [
            FakeStepScriptedOutcome(
              stepId: 'step_001',
              firstStatus: StepVerificationStatus.fail,
              retryStatus: StepVerificationStatus.fail,
              retryAllowed: true,
              failAcceptedAfterRetryFailure: true,
              issues: ['fake issue remains after retry'],
            ),
          ],
        ),
      );

      expect(result.finalStatus, 'failAccepted');
      expect(result.trace.traceStatus, StrategyTraceStatus.dryRunNotCounted);
      expect(result.verifications.last.status, StepVerificationStatus.failAccepted);
      expect(result.verifications.last.countsAsVerifiedSuccess, isFalse);
    });

    test('failure path supports blocked status', () {
      final result = FakeReasoningStrategyRunner().run(
        FakeReasoningStrategyRequest(
          userGoal: 'Block fake execution',
          memoryPacket: _memoryPacket(),
          strategyId: 'plan_execute_verify_single_agent',
          steps: const [
            FakeReasoningStep(stepId: 'step_001', task: 'fake blocked step'),
          ],
          scriptedOutcomes: const [
            FakeStepScriptedOutcome(
              stepId: 'step_001',
              firstStatus: StepVerificationStatus.blocked,
              retryAllowed: false,
              issues: ['fake missing authorization'],
            ),
          ],
        ),
      );

      expect(result.finalStatus, 'blocked');
      expect(result.trace.traceStatus, StrategyTraceStatus.dryRunNotCounted);
      expect(result.verifications.single.status, StepVerificationStatus.blocked);
    });

    test('event IDs and event order are stable', () {
      final result = FakeReasoningStrategyRunner(
        startedAt: DateTime.utc(2026, 2, 1),
      ).run(
        FakeReasoningStrategyRequest(
          userGoal: 'Stable order',
          memoryPacket: _memoryPacket(),
          strategyId: 'plan_execute_verify_single_agent',
          steps: const [FakeReasoningStep(stepId: 'step_001', task: 'fake one step')],
        ),
      );

      expect(result.trace.events.map((event) => event.eventId), [
        'evt_001',
        'evt_002',
        'evt_003',
        'evt_004',
        'evt_005',
        'evt_006',
        'evt_007',
      ]);
      expect(result.trace.events.first.startedAt, DateTime.utc(2026, 2, 1));
      expect(result.trace.events.last.type, StrategyEventType.report);
    });

    test('sanitizes unsupported counted run kind back to dry-run not counted', () {
      final result = FakeReasoningStrategyRunner().run(
        FakeReasoningStrategyRequest(
          userGoal: 'Do not count fake result',
          memoryPacket: _memoryPacket(),
          strategyId: 'plan_execute_verify_single_agent',
          runKind: 'strategy_ablation_result',
        ),
      );

      expect(result.runKind, 'strategy_dry_run_not_counted');
      expect(result.countsAsExperiment, isFalse);
      expect(result.trace.toBenchmarkJson()['counts_as_experiment'], isFalse);
    });
  });
}

HarnessMemoryPacket _memoryPacket() {
  return HarnessMemoryPacket(
    packetId: 'hmp-run-1-turn-1',
    schemaVersion: '0.1.0',
    sessionId: 'session-1',
    runId: 'run-1',
    createdAt: DateTime.utc(2026, 1, 1),
    ttlSeconds: 86400,
    sourceLimits: const HarnessSourceLimits(),
    userGoal: 'fake closed-loop test',
    conversationSummary: 'compact summary only',
    recentTurns: const [
      HarnessRecentTurn(role: 'user', summary: 'requested fake runner'),
    ],
    activeConstraints: const ['no network', 'no model', 'no device'],
    redaction: const HarnessRedaction(applied: true, classes: ['secret']),
  );
}
