/// Non-counted pilot runner that implements the P4a runner contract.
///
/// This is the bridge object future UI or tests can call before a real runner
/// exists. It delegates to [ReasoningStrategyController]'s fake closed loop and
/// then applies a promotion gate that always blocks counted fake results.
library;

import 'reasoning_strategy_controller.dart';
import 'reasoning_strategy_runner_contract.dart';

class NonCountedReasoningStrategyPilotRunner implements ReasoningStrategyRunnerContract {
  NonCountedReasoningStrategyPilotRunner({
    ReasoningStrategyController? controller,
    StrategyPromotionGate promotionGate = const StrategyPromotionGate(),
    StrategyEvidenceManifest evidenceManifest = const StrategyEvidenceManifest(),
  })  : _controller = controller ?? ReasoningStrategyController(),
        _promotionGate = promotionGate,
        _evidenceManifest = evidenceManifest;

  final ReasoningStrategyController _controller;
  final StrategyPromotionGate _promotionGate;
  final StrategyEvidenceManifest _evidenceManifest;

  @override
  Future<ReasoningStrategyRunOutput> run(ReasoningStrategyRunInput input) async {
    final safeRunKind = _safeNonCountedRunKind(input.runKind);
    final controllerResult = _controller.runFakeClosedLoop(
      ReasoningStrategyControllerRequest(
        userGoal: input.userGoal,
        sessionId: input.memoryPacket.sessionId,
        runId: input.memoryPacket.runId,
        strategyId: input.strategyId,
        runKind: safeRunKind,
        memoryPacket: input.memoryPacket,
      ),
    );

    final gateDecision = _promotionGate.evaluate(
      runKind: input.runKind,
      requestedCountsAsExperiment: input.runKind == strategyAblationResult,
      evidence: _evidenceManifest,
    );

    return ReasoningStrategyRunOutput(
      runKind: controllerResult.fakeResult.runKind,
      trace: controllerResult.trace,
      verifications: controllerResult.verifications,
      actionEvidence: controllerResult.evidence,
      timeMetrics: StrategyTimeMetrics.empty,
      tokenMetrics: StrategyTokenMetrics.empty,
      effectMetrics: StrategyEffectMetrics.empty,
      promotionDecision: gateDecision.allowed
          ? const StrategyPromotionDecision(
              allowed: false,
              reason: 'fake_pilot_runner_never_promotes_to_counted_result',
            )
          : gateDecision,
    );
  }

  String _safeNonCountedRunKind(String runKind) {
    return switch (runKind) {
      strategyScaffoldNotRun => strategyScaffoldNotRun,
      strategyDryRunNotCounted => strategyDryRunNotCounted,
      strategyPilotNotCounted => strategyPilotNotCounted,
      _ => strategyPilotNotCounted,
    };
  }
}
