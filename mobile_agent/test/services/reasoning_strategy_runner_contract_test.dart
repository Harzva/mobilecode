import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/reasoning_strategy_models.dart';
import 'package:mobile_agent/services/reasoning_strategy_runner_contract.dart';

void main() {
  group('Strategy instrumentation metrics', () {
    test('aggregates time phases and token usage', () {
      final recorder = StrategyInstrumentationRecorder(startedAt: DateTime.utc(2026, 4, 1));
      recorder.addPhase(
        phase: 'planning',
        startedAt: DateTime.utc(2026, 4, 1),
        endedAt: DateTime.utc(2026, 4, 1, 0, 0, 0, 100),
      );
      recorder.addPhase(
        phase: 'execution',
        startedAt: DateTime.utc(2026, 4, 1, 0, 0, 0, 100),
        endedAt: DateTime.utc(2026, 4, 1, 0, 0, 0, 350),
      );
      recorder.addPhase(
        phase: 'verification',
        startedAt: DateTime.utc(2026, 4, 1, 0, 0, 0, 350),
        endedAt: DateTime.utc(2026, 4, 1, 0, 0, 0, 500),
      );
      recorder.finish(DateTime.utc(2026, 4, 1, 0, 0, 1));
      recorder.tokenUsage.addProviderUsage(promptTokens: 100, completionTokens: 50);
      recorder.tokenUsage.addToolIo(inputChars: 200, outputChars: 600);

      final time = recorder.timeMetrics(successfulTasks: 2);
      final token = recorder.tokenUsage.snapshot(successfulTasks: 2, verifiedSuccesses: 1);

      expect(time.wallTimeMs, 1000);
      expect(time.planningTimeMs, 100);
      expect(time.executionTimeMs, 250);
      expect(time.verificationTimeMs, 150);
      expect(time.meanTimePerSuccessfulTaskMs, 500);
      expect(token.estimatedToolTokens, 200);
      expect(token.totalTokens, 350);
      expect(token.tokensPerSuccessfulTask, 175);
      expect(token.tokensPerVerifiedSuccess, 350);
    });

    test('roundtrips metrics JSON', () {
      const time = StrategyTimeMetrics(
        wallTimeMs: 10,
        planningTimeMs: 2,
        executionTimeMs: 5,
      );
      const token = StrategyTokenMetrics(
        promptTokens: 8,
        completionTokens: 4,
        totalTokens: 12,
      );
      const effect = StrategyEffectMetrics(
        taskSuccess: 1,
        verifiedSuccess: 0,
        handoffCount: 2,
      );

      expect(StrategyTimeMetrics.fromJson(time.toJson()).wallTimeMs, 10);
      expect(StrategyTokenMetrics.fromJson(token.toJson()).totalTokens, 12);
      expect(StrategyEffectMetrics.fromJson(effect.toJson()).handoffCount, 2);
    });
  });

  group('StrategyPromotionGate', () {
    test('blocks fake or pilot runs even if requested', () {
      final decision = const StrategyPromotionGate().evaluate(
        runKind: strategyPilotNotCounted,
        requestedCountsAsExperiment: true,
        evidence: const StrategyEvidenceManifest(
          modelLogIds: ['m1'],
          tokenRecordIds: ['t1'],
          verifierEvidenceIds: ['v1'],
          toolEvidenceIds: ['tool1'],
          deviceEvidenceIds: ['d1'],
        ),
      );

      expect(decision.allowed, isFalse);
      expect(decision.reason, 'non_counted_run_kind_or_not_requested');
    });

    test('blocks counted result without required evidence', () {
      final decision = const StrategyPromotionGate().evaluate(
        runKind: strategyAblationResult,
        requestedCountsAsExperiment: true,
        evidence: const StrategyEvidenceManifest(modelLogIds: ['m1']),
      );

      expect(decision.allowed, isFalse);
      expect(decision.missingEvidence, containsAll([
        'token_records',
        'verifier_evidence',
        'tool_evidence',
        'device_evidence',
      ]));
    });

    test('allows counted result only when all required evidence is present', () {
      final decision = const StrategyPromotionGate().evaluate(
        runKind: strategyAblationResult,
        requestedCountsAsExperiment: true,
        evidence: const StrategyEvidenceManifest(
          modelLogIds: ['m1'],
          tokenRecordIds: ['t1'],
          verifierEvidenceIds: ['v1'],
          toolEvidenceIds: ['tool1'],
          deviceEvidenceIds: ['d1'],
        ),
      );

      expect(decision.allowed, isTrue);
      expect(decision.reason, 'all_required_evidence_present');
    });
  });

  group('ReasoningStrategyRunOutput', () {
    test('keeps counts false when promotion decision blocks', () {
      final output = ReasoningStrategyRunOutput(
        runKind: strategyDryRunNotCounted,
        trace: StrategyTrace(
          traceId: 'trace-1',
          strategyId: 'plan_execute_verify_single_agent',
          traceStatus: StrategyTraceStatus.dryRunNotCounted,
        ),
        verifications: const [],
        actionEvidence: const [],
        timeMetrics: StrategyTimeMetrics.empty,
        tokenMetrics: StrategyTokenMetrics.empty,
        effectMetrics: StrategyEffectMetrics.empty,
        promotionDecision: const StrategyPromotionDecision(
          allowed: false,
          reason: 'dry_run_not_counted',
        ),
      );

      final json = output.toJson();
      expect(output.countsAsExperiment, isFalse);
      expect(json['counts_as_experiment'], isFalse);
      expect(json['counts_as_strategy_ablation_result'], isFalse);
      expect(json['time_metrics'], isA<Map<String, dynamic>>());
      expect(json['token_metrics'], isA<Map<String, dynamic>>());
      expect(json['effect_metrics'], isA<Map<String, dynamic>>());
    });
  });
}
