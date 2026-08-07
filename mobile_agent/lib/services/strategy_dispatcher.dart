/// Strategy dispatcher for MobileCode reasoning strategy modes.
library;

export 'strategy_runners.dart'
    show
        hierarchicalSwarmMultiAgentStrategyId,
        planExecuteVerifySingleAgentStrategyId,
        reactSingleAgentStrategyId,
        reactWithFinalVerifierStrategyId,
        supervisorHandoffMultiAgentStrategyId,
        swarmRouterMultiAgentStrategyId;

import 'reasoning_strategy_runner_contract.dart';
import 'strategy_runners.dart';

class StrategyCapabilities {
  const StrategyCapabilities({
    this.enableReAct = true,
    this.enablePlanExecuteVerify = true,
    this.enableSupervisorHandoff = true,
    this.enableExperimentalSwarm = true,
  });

  final bool enableReAct;
  final bool enablePlanExecuteVerify;
  final bool enableSupervisorHandoff;
  final bool enableExperimentalSwarm;
}

class StrategyDispatcher implements ReasoningStrategyRunnerContract {
  StrategyDispatcher({
    required this.capabilities,
    required Map<String, ReasoningStrategyRunnerContract> runners,
  }) : _runners = Map.unmodifiable(runners);

  factory StrategyDispatcher.defaultSafe({
    StrategyCapabilities capabilities = const StrategyCapabilities(),
  }) {
    return StrategyDispatcher(
      capabilities: capabilities,
      runners: {
        reactSingleAgentStrategyId: ReactStrategyRunner(),
        planExecuteVerifySingleAgentStrategyId:
            PlanExecuteVerifyStrategyRunner(),
        reactWithFinalVerifierStrategyId:
            ReactWithFinalVerifierStrategyRunner(),
        supervisorHandoffMultiAgentStrategyId:
            SupervisorHandoffStrategyRunner(),
        swarmRouterMultiAgentStrategyId: SwarmRouterStrategyRunner(),
        hierarchicalSwarmMultiAgentStrategyId:
            HierarchicalSwarmStrategyRunner(),
      },
    );
  }

  final StrategyCapabilities capabilities;
  final Map<String, ReasoningStrategyRunnerContract> _runners;

  @override
  Future<ReasoningStrategyRunOutput> run(ReasoningStrategyRunInput input) {
    final strategyId = _normalizeStrategyId(input.strategyId);
    final blockedReason = _blockedReason(strategyId);
    if (blockedReason != null) {
      return BlockedStrategyRunner(
              strategyId: strategyId, reason: blockedReason)
          .run(
        ReasoningStrategyRunInput(
          userGoal: input.userGoal,
          memoryPacket: input.memoryPacket,
          strategyId: strategyId,
          runKind: input.runKind,
          promptBudget: input.promptBudget,
          toolAccessPolicy: input.toolAccessPolicy,
          maxSteps: input.maxSteps,
        ),
      );
    }
    return _runners[strategyId]!.run(
      ReasoningStrategyRunInput(
        userGoal: input.userGoal,
        memoryPacket: input.memoryPacket,
        strategyId: strategyId,
        runKind: input.runKind,
        promptBudget: input.promptBudget,
        toolAccessPolicy: input.toolAccessPolicy,
        maxSteps: input.maxSteps,
      ),
    );
  }

  String _normalizeStrategyId(String strategyId) {
    if (_runners.containsKey(strategyId)) {
      return strategyId;
    }
    return planExecuteVerifySingleAgentStrategyId;
  }

  String? _blockedReason(String strategyId) {
    if (!capabilities.enableReAct &&
        (strategyId == reactSingleAgentStrategyId ||
            strategyId == reactWithFinalVerifierStrategyId)) {
      return 'react_strategy_disabled';
    }
    if (!capabilities.enablePlanExecuteVerify &&
        strategyId == planExecuteVerifySingleAgentStrategyId) {
      return 'plan_execute_verify_strategy_disabled';
    }
    if (!capabilities.enableSupervisorHandoff &&
        strategyId == supervisorHandoffMultiAgentStrategyId) {
      return 'supervisor_handoff_strategy_disabled';
    }
    if (!capabilities.enableExperimentalSwarm &&
        (strategyId == swarmRouterMultiAgentStrategyId ||
            strategyId == hierarchicalSwarmMultiAgentStrategyId)) {
      return 'experimental_strategy_disabled';
    }
    return null;
  }
}
