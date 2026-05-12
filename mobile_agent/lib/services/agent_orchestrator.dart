// lib/services/agent_orchestrator.dart
// Agent Orchestration Service
//
// Implements Supervisor-Worker multi-agent pattern:
// - Supervisor receives user request
// - Supervisor breaks down into sub-tasks
// Each sub-task assigned to a specialized worker agent
// - Workers report progress back to supervisor
// - Supervisor coordinates and resolves conflicts

import 'dart:async';
import 'dart:math' show max;
import 'package:flutter/material.dart';
import '../models/agent_task.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Worker Agent Definition
// ═══════════════════════════════════════════════════════════════════════════

/// Definition of a specialized worker agent.
///
/// Each worker has a unique set of capabilities used by the supervisor
/// to assign appropriate steps.
class WorkerAgent {
  /// Unique agent identifier.
  final String id;

  /// Display name.
  final String name;

  /// Icon identifier string.
  final String icon;

  /// Human-readable description of agent's skills.
  final String description;

  /// List of capability tags.
  final List<String> capabilities;

  /// Accent color for UI.
  final Color accentColor;

  const WorkerAgent({
    required this.id,
    required this.name,
    required this.icon,
    required this.description,
    required this.capabilities,
    required this.accentColor,
  });

  /// Check if this agent has a specific capability.
  bool hasCapability(String cap) => capabilities.contains(cap);

  /// Check if this agent has any of the given capabilities.
  bool hasAnyCapability(List<String> caps) =>
      caps.any((c) => capabilities.contains(c));

  @override
  String toString() => 'WorkerAgent[$id: $name] (${capabilities.join(", ")})';
}

// ═══════════════════════════════════════════════════════════════════════════
// Agent Orchestrator
// ═══════════════════════════════════════════════════════════════════════════

/// Central orchestrator implementing the Supervisor-Worker pattern.
///
/// The orchestrator manages a pool of specialized worker agents and
/// coordinates their execution of task plans. It provides real-time
/// progress tracking through streams.
class AgentOrchestrator {
  AgentOrchestrator._();

  static final AgentOrchestrator _instance = AgentOrchestrator._();

  /// Get the singleton instance.
  factory AgentOrchestrator() => _instance;

  // ── Agent Registry ────────────────────────────────────────────────────

  /// Available worker agents indexed by ID.
  final Map<String, WorkerAgent> _agents = {
    'code_expert': const WorkerAgent(
      id: 'code_expert',
      name: '\u4ee3\u7801\u4e13\u5bb6',
      icon: 'code',
      description: '\u64c5\u957f\u4ee3\u7801\u751f\u6210\u3001\u91cd\u6784\u548c\u4f18\u5316',
      capabilities: ['code_generation', 'code_review', 'refactoring'],
      accentColor: Color(0xFF7B2FF7),
    ),
    'debugger': const WorkerAgent(
      id: 'debugger',
      name: '\u8c03\u8bd5\u52a9\u624b',
      icon: 'bug',
      description: '\u64c5\u957f\u9519\u8bef\u8bca\u65ad\u548c\u4fee\u590d',
      capabilities: ['error_diagnosis', 'bug_fix', 'testing'],
      accentColor: Color(0xFFFF6B6B),
    ),
    'git_helper': const WorkerAgent(
      id: 'git_helper',
      name: 'Git\u52a9\u624b',
      icon: 'git',
      description: '\u64c5\u957f\u7248\u672c\u63a7\u5236\u548c\u534f\u4f5c',
      capabilities: ['git_operations', 'merge_conflict', 'history'],
      accentColor: Color(0xFF00D4AA),
    ),
    'terminal_runner': const WorkerAgent(
      id: 'terminal_runner',
      name: '\u7ec8\u7aef\u6267\u884c\u8005',
      icon: 'terminal',
      description: '\u64c5\u957f\u547d\u4ee4\u6267\u884c\u548c\u6784\u5efa',
      capabilities: ['command_execution', 'build', 'deploy'],
      accentColor: Color(0xFFFFA500),
    ),
    'project_manager': const WorkerAgent(
      id: 'project_manager',
      name: '\u9879\u76ee\u7ba1\u5bb6',
      icon: 'folder',
      description: '\u64c5\u957f\u9879\u76ee\u7ba1\u7406\u548c\u7ec4\u7ec7',
      capabilities: ['project_setup', 'file_organization', 'dependency_mgmt'],
      accentColor: Color(0xFF4ECDC4),
    ),
  };

  // ── Internal State ────────────────────────────────────────────────────

  /// Active task plans indexed by ID.
  final Map<String, TaskPlan> _plans = {};

  /// Current agent runtime status.
  final Map<String, AgentStatus> _agentStatuses = {};

  /// Whether a plan is currently paused.
  final Set<String> _pausedPlans = {};

  /// Whether a plan has been cancelled.
  final Set<String> _cancelledPlans = {};

  /// Currently executing plan IDs and their completers.
  final Map<String, Completer<void>> _executingPlans = {};

  // ── Stream Controllers ────────────────────────────────────────────────

  final StreamController<TaskPlan> _planUpdates =
      StreamController<TaskPlan>.broadcast();
  final StreamController<AgentStatus> _agentUpdates =
      StreamController<AgentStatus>.broadcast();
  final StreamController<AgentActivity> _activityLog =
      StreamController<AgentActivity>.broadcast();

  // ── Public Streams ────────────────────────────────────────────────────

  /// Stream of plan updates for real-time UI.
  Stream<TaskPlan> get planUpdates => _planUpdates.stream;

  /// Stream of agent status updates for real-time UI.
  Stream<AgentStatus> get agentUpdates => _agentUpdates.stream;

  /// Stream of activity logs from all agents.
  Stream<AgentActivity> get activityLog => _activityLog.stream;

  // ── Agent Access ──────────────────────────────────────────────────────

  /// Get a worker agent by ID.
  WorkerAgent? getAgent(String agentId) => _agents[agentId];

  /// Get all registered worker agents.
  List<WorkerAgent> get allAgents => _agents.values.toList();

  /// Get all agent IDs.
  List<String> get agentIds => _agents.keys.toList();

  // ── Task Planning ─────────────────────────────────────────────────────

  /// Create a task plan from a user request.
  ///
  /// The supervisor analyzes the request and breaks it down into
  /// sequential steps, each assigned to the most suitable worker.
  Future<TaskPlan> createPlan(String userRequest) async {
    // Emit activity
    _logActivity(
      agentId: 'supervisor',
      agentName: '\u4e3b\u7ba1\u63a7\u5236',
      action: '\u5206\u6790\u8bf7\u6c42: ${userRequest.length > 30 ? '${userRequest.substring(0, 30)}...' : userRequest}',
    );

    await Future.delayed(const Duration(milliseconds: 300));

    final steps = _generateStepsFromRequest(userRequest);
    final plan = TaskPlan(
      id: 'plan_${DateTime.now().millisecondsSinceEpoch}',
      title: _generateTitle(userRequest),
      description: userRequest,
      steps: steps,
      createdAt: DateTime.now(),
      progress: 0.0,
    );

    _plans[plan.id] = plan;

    _logActivity(
      agentId: 'supervisor',
      agentName: '\u4e3b\u7ba1\u63a7\u5236',
      action: '\u521b\u5efa\u4efb\u52a1\u8ba1\u5212: ${plan.title}',
      result: '\u5171 ${steps.length} \u4e2a\u6b65\u9aa4',
    );

    return plan;
  }

  /// Execute a task plan step by step.
  ///
  /// Each step is assigned to the best worker and executed sequentially.
  /// Progress is reported through the [onProgress] callback and
  /// [planUpdates] stream.
  Future<void> executePlan(
    TaskPlan plan, {
    Function(TaskPlan)? onProgress,
  }) async {
    if (_cancelledPlans.contains(plan.id)) return;

    // Mark as running
    var current = plan.copyWith(
      status: TaskPlanStatus.running,
      startedAt: DateTime.now(),
    );
    _plans[current.id] = current;
    _pausedPlans.remove(plan.id);
    _planUpdates.add(current);
    onProgress?.call(current);

    _logActivity(
      agentId: 'supervisor',
      agentName: '\u4e3b\u7ba1\u63a7\u5236',
      action: '\u5f00\u59cb\u6267\u884c\u8ba1\u5212: ${plan.title}',
    );

    final completer = Completer<void>();
    _executingPlans[plan.id] = completer;

    try {
      for (int i = 0; i < current.steps.length; i++) {
        // Check cancellation
        if (_cancelledPlans.contains(plan.id)) {
          _logActivity(
            agentId: 'supervisor',
            agentName: '\u4e3b\u7ba1\u63a7\u5236',
            action: '\u8ba1\u5212\u5df2\u53d6\u6d88: ${plan.title}',
          );
          break;
        }

        // Check pause
        while (_pausedPlans.contains(plan.id) &&
            !_cancelledPlans.contains(plan.id)) {
          await Future.delayed(const Duration(milliseconds: 200));
        }

        final step = current.steps[i];

        // Update step to running
        final updatedSteps = [...current.steps];
        updatedSteps[i] = step.copyWith(
          status: StepStatus.running,
          startedAt: DateTime.now(),
        );

        current = current.copyWith(
          steps: updatedSteps,
          progress: i / current.steps.length,
        );
        _plans[current.id] = current;
        _planUpdates.add(current);
        onProgress?.call(current);

        // Assign to best agent
        final agent = selectAgentForStep(current.steps[i]);
        final agentName = agent?.name ?? '\u672a\u77e5\u4ee3\u7406';

        if (agent != null) {
          _updateAgentStatus(
            agent.id,
            AgentState.working,
            currentTask: '\u6267\u884c: ${step.title}',
            progress: 0.0,
          );
        }

        // Emit step start activity
        _logActivity(
          agentId: agent?.id ?? 'unknown',
          agentName: agentName,
          action: '\u5f00\u59cb\u6b65\u9aa4 ${step.order}: ${step.title}',
        );

        // Execute step (simulate)
        final result = await _executeStep(current.steps[i], agent);

        // Check cancellation again after execution
        if (_cancelledPlans.contains(plan.id)) break;

        // Update step with result
        final finalSteps = [...current.steps];
        final success = result['success'] == true;
        finalSteps[i] = current.steps[i].copyWith(
          status: success ? StepStatus.completed : StepStatus.failed,
          completedAt: DateTime.now(),
          result: result['message'] as String?,
          assignedAgentId: agent?.id,
        );

        current = current.copyWith(
          steps: finalSteps,
          progress: (i + 1) / current.steps.length,
        );
        _plans[current.id] = current;
        _planUpdates.add(current);
        onProgress?.call(current);

        // Update agent status
        if (agent != null) {
          _updateAgentStatus(
            agent.id,
            success ? AgentState.idle : AgentState.error,
            currentTask: null,
            progress: null,
          );
          if (success) {
            _addAgentAction(agent.id, '\u5b8c\u6210: ${step.title}');
          }
        }

        // Emit step complete activity
        _logActivity(
          agentId: agent?.id ?? 'unknown',
          agentName: agentName,
          action: success
              ? '\u5b8c\u6210\u6b65\u9aa4 ${step.order}: ${step.title}'
              : '\u5931\u8d25\u6b65\u9aa4 ${step.order}: ${step.title}',
          result: result['message'] as String?,
          level: success ? LogLevel.info : LogLevel.error,
        );
      }

      // Finalize plan status
      if (!_cancelledPlans.contains(plan.id)) {
        final allCompleted = current.steps.every(
          (s) =>
              s.status == StepStatus.completed ||
              s.status == StepStatus.skipped,
        );
        final anyFailed = current.steps.any(
          (s) => s.status == StepStatus.failed,
        );

        final finalStatus = anyFailed
            ? TaskPlanStatus.failed
            : allCompleted
                ? TaskPlanStatus.completed
                : current.status;

        current = current.copyWith(
          status: finalStatus,
          completedAt: DateTime.now(),
          progress: anyFailed ? current.progress : 1.0,
        );
        _plans[current.id] = current;
        _planUpdates.add(current);
        onProgress?.call(current);

        _logActivity(
          agentId: 'supervisor',
          agentName: '\u4e3b\u7ba1\u63a7\u5236',
          action: '\u8ba1\u5212\u5b8c\u6210: ${current.title}',
          result: finalStatus == TaskPlanStatus.completed
              ? '\u5168\u90e8\u6b65\u9aa4\u5b8c\u6210'
              : '\u90e8\u5206\u6b65\u9aa4\u5931\u8d25',
          level: finalStatus == TaskPlanStatus.completed
              ? LogLevel.info
              : LogLevel.warning,
        );
      }
    } catch (e) {
      current = current.copyWith(status: TaskPlanStatus.failed);
      _plans[current.id] = current;
      _planUpdates.add(current);
      onProgress?.call(current);

      _logActivity(
        agentId: 'supervisor',
        agentName: '\u4e3b\u7ba1\u63a7\u5236',
        action: '\u8ba1\u5212\u6267\u884c\u5f02\u5e38: $e',
        level: LogLevel.error,
      );
    } finally {
      _executingPlans.remove(plan.id);
      if (!completer.isCompleted) completer.complete();
    }
  }

  /// Pause execution of a running plan.
  void pausePlan(String planId) {
    final plan = _plans[planId];
    if (plan == null || plan.status != TaskPlanStatus.running) return;

    _pausedPlans.add(planId);
    final updated = plan.copyWith(status: TaskPlanStatus.paused);
    _plans[planId] = updated;
    _planUpdates.add(updated);

    _logActivity(
      agentId: 'supervisor',
      agentName: '\u4e3b\u7ba1\u63a7\u5236',
      action: '\u6682\u505c\u8ba1\u5212: ${plan.title}',
    );
  }

  /// Resume a paused plan.
  void resumePlan(String planId) {
    final plan = _plans[planId];
    if (plan == null || plan.status != TaskPlanStatus.paused) return;

    _pausedPlans.remove(planId);
    final updated = plan.copyWith(status: TaskPlanStatus.running);
    _plans[planId] = updated;
    _planUpdates.add(updated);

    _logActivity(
      agentId: 'supervisor',
      agentName: '\u4e3b\u7ba1\u63a7\u5236',
      action: '\u6062\u590d\u6267\u884c: ${plan.title}',
    );
  }

  /// Cancel a plan permanently.
  void cancelPlan(String planId) {
    final plan = _plans[planId];
    if (plan == null) return;

    _cancelledPlans.add(planId);
    _pausedPlans.remove(planId);

    final updated = plan.copyWith(status: TaskPlanStatus.failed);
    _plans[planId] = updated;
    _planUpdates.add(updated);

    _logActivity(
      agentId: 'supervisor',
      agentName: '\u4e3b\u7ba1\u63a7\u5236',
      action: '\u53d6\u6d88\u8ba1\u5212: ${plan.title}',
    );

    // Complete any pending completer
    _executingPlans[planId]?.complete();
    _executingPlans.remove(planId);
  }

  // ── Agent Assignment ──────────────────────────────────────────────────

  /// Select the best agent for a given step.
  ///
  /// Uses capability matching to find the agent most suited for
  /// the step's requirements.
  WorkerAgent? selectAgentForStep(TaskStep step) {
    final actionName = step.action?.toString() ?? '';

    // Map actions to capabilities
    final requiredCaps = _inferCapabilities(actionName, step.title);

    // Find agent with most matching capabilities
    WorkerAgent? bestAgent;
    int bestScore = -1;

    for (final agent in _agents.values) {
      int score = 0;
      for (final cap in requiredCaps) {
        if (agent.hasCapability(cap)) score++;
      }
      if (score > bestScore) {
        bestScore = score;
        bestAgent = agent;
      }
    }

    return bestAgent;
  }

  /// Get current status of a single agent.
  AgentStatus getAgentStatus(String agentId) {
    final agent = _agents[agentId];
    if (agent == null) {
      return AgentStatus(
        agentId: agentId,
        name: '\u672a\u77e5',
        icon: 'help',
        state: AgentState.idle,
        accentColor: const Color(0xFF6B7280),
      );
    }

    return _agentStatuses[agentId] ??
        AgentStatus(
          agentId: agentId,
          name: agent.name,
          icon: agent.icon,
          state: AgentState.idle,
          accentColor: agent.accentColor,
        );
  }

  /// Get status of all agents.
  List<AgentStatus> getAllAgentStatuses() =>
      _agents.keys.map(getAgentStatus).toList();

  /// Get currently active (working/thinking) agents.
  List<AgentStatus> getActiveAgents() => getAllAgentStatuses()
      .where((a) => a.state == AgentState.working || a.state == AgentState.thinking)
      .toList();

  // ── Plan Access ───────────────────────────────────────────────────────

  /// Get a plan by ID.
  TaskPlan? getPlan(String planId) => _plans[planId];

  /// Get all plans.
  List<TaskPlan> get allPlans => _plans.values.toList();

  /// Get currently active plans.
  List<TaskPlan> get activePlans => _plans.values
      .where((p) => p.status == TaskPlanStatus.running)
      .toList();

  // ── Cleanup ───────────────────────────────────────────────────────────

  /// Dispose all stream controllers.
  void dispose() {
    _planUpdates.close();
    _agentUpdates.close();
    _activityLog.close();
  }

  // ── Internal Helpers ──────────────────────────────────────────────────

  /// Update an agent's status and emit to stream.
  void _updateAgentStatus(
    String agentId,
    AgentState state, {
    String? currentTask,
    double? progress,
  }) {
    final agent = _agents[agentId];
    if (agent == null) return;

    final existing = _agentStatuses[agentId];
    final updated = AgentStatus(
      agentId: agentId,
      name: agent.name,
      icon: agent.icon,
      state: state,
      currentTask: currentTask,
      progress: progress,
      taskStartedAt: state == AgentState.working
          ? (existing?.taskStartedAt ?? DateTime.now())
          : null,
      recentActions: existing?.recentActions ?? [],
      accentColor: agent.accentColor,
    );

    _agentStatuses[agentId] = updated;
    _agentUpdates.add(updated);
  }

  /// Add an action to an agent's recent actions list.
  void _addAgentAction(String agentId, String action) {
    final existing = _agentStatuses[agentId];
    if (existing == null) return;

    final actions = [action, ...existing.recentActions];
    if (actions.length > 5) actions.removeLast();

    _agentStatuses[agentId] = existing.copyWith(recentActions: actions);
  }

  /// Log an activity to the shared activity stream.
  void _logActivity({
    required String agentId,
    required String agentName,
    required String action,
    String? result,
    LogLevel level = LogLevel.info,
  }) {
    final activity = AgentActivity(
      timestamp: DateTime.now(),
      agentId: agentId,
      agentName: agentName,
      action: action,
      result: result,
      level: level,
    );
    _activityLog.add(activity);
  }

  /// Infer required capabilities from action name and step title.
  List<String> _inferCapabilities(String actionName, String stepTitle) {
    final text = '$actionName $stepTitle'.toLowerCase();
    final caps = <String>[];

    if (text.contains('code') ||
        text.contains('\u4ee3\u7801') ||
        text.contains('file') ||
        text.contains('\u6587\u4ef6') ||
        text.contains('write') ||
        text.contains('edit')) {
      caps.add('code_generation');
    }
    if (text.contains('bug') ||
        text.contains('fix') ||
        text.contains('error') ||
        text.contains('debug') ||
        text.contains('\u4fee\u590d') ||
        text.contains('\u8c03\u8bd5')) {
      caps.add('bug_fix');
    }
    if (text.contains('git') ||
        text.contains('commit') ||
        text.contains('push') ||
        text.contains('merge')) {
      caps.add('git_operations');
    }
    if (text.contains('command') ||
        text.contains('build') ||
        text.contains('run') ||
        text.contains('\u7f16\u8bd1') ||
        text.contains('\u8fd0\u884c') ||
        text.contains('terminal')) {
      caps.add('command_execution');
    }
    if (text.contains('project') ||
        text.contains('setup') ||
        text.contains('struct') ||
        text.contains('\u9879\u76ee') ||
        text.contains('\u7ed3\u6784')) {
      caps.add('project_setup');
    }
    if (text.contains('test')) {
      caps.add('testing');
    }

    if (caps.isEmpty) caps.add('code_generation');
    return caps;
  }

  /// Simulate step execution (placeholder for real implementation).
  ///
  /// In production, this would dispatch to the actual LLM agent.
  Future<Map<String, dynamic>> _executeStep(
    TaskStep step,
    WorkerAgent? agent,
  ) async {
    // Simulate processing time based on step complexity
    final delay = Duration(
      milliseconds: 800 + (step.title.length * 50).clamp(0, 3000),
    );

    // Simulate progress ticks
    final ticks = 5;
    for (int i = 1; i <= ticks; i++) {
      await Future.delayed(delay ~/ ticks);

      if (agent != null && _agentStatuses.containsKey(agent.id)) {
        _updateAgentStatus(
          agent.id,
          AgentState.working,
          currentTask: '\u6267\u884c: ${step.title}',
          progress: i / ticks,
        );
      }
    }

    // Simulate occasional failure (5% chance)
    final failed = (step.order % 7 == 0); // Deterministic for demo

    if (failed) {
      return {
        'success': false,
        'message': '\u6b65\u9aa4 ${step.order} \u6267\u884c\u5931\u8d25: \u6a21\u62df\u9519\u8bef',
      };
    }

    return {
      'success': true,
      'message': '\u6b65\u9aa4 ${step.order} \u5b8c\u6210\u6210\u529f',
    };
  }

  /// Generate plan title from user request.
  String _generateTitle(String request) {
    if (request.length <= 20) return request;
    return '${request.substring(0, 20)}...';
  }

  /// Generate steps from a user request (smart decomposition).
  ///
  /// In production, this would call the LLM supervisor to analyze
  /// and decompose the request. For now, we generate sensible defaults.
  List<TaskStep> _generateStepsFromRequest(String request) {
    final lower = request.toLowerCase();
    final steps = <TaskStep>[];
    int order = 1;

    // Project setup is usually first
    if (lower.contains('app') ||
        lower.contains('project') ||
        lower.contains('flutter') ||
        lower.contains('\u9879\u76ee')) {
      steps.add(TaskStep(
        id: 'step_${order}',
        order: order++,
        title: '\u521b\u5efa\u9879\u76ee\u7ed3\u6784',
        description: '\u521b\u5efaFlutter\u9879\u76ee\u5e76\u8bbe\u7f6e\u76ee\u5f55\u7ed3\u6784',
        assignedAgentId: 'project_manager',
        action: 'project_setup',
      ));
    }

    // Dependencies
    if (lower.contains('package') ||
        lower.contains('dependency') ||
        lower.contains('pubspec') ||
        lower.contains('\u4f9d\u8d56')) {
      steps.add(TaskStep(
        id: 'step_${order}',
        order: order++,
        title: '\u6dfb\u52a0\u4f9d\u8d56\u9879',
        description: '\u5728pubspec.yaml\u4e2d\u6dfb\u52a0\u5fc5\u8981\u7684\u4f9d\u8d56\u5305',
        assignedAgentId: 'project_manager',
        action: 'dependency_mgmt',
      ));
    }

    // UI/Widget development
    if (lower.contains('ui') ||
        lower.contains('widget') ||
        lower.contains('screen') ||
        lower.contains('page') ||
        lower.contains('\u9875\u9762') ||
        lower.contains('\u754c\u9762')) {
      steps.add(TaskStep(
        id: 'step_${order}',
        order: order++,
        title: '\u5b9e\u73b0UI\u754c\u9762',
        description: '\u521b\u5efa\u4e3b\u754c\u9762\u7ec4\u4ef6\u548c\u5e03\u5c40',
        assignedAgentId: 'code_expert',
        action: 'code_generation',
      ));
    }

    // Business logic
    if (lower.contains('logic') ||
        lower.contains('data') ||
        lower.contains('model') ||
        lower.contains('state') ||
        lower.contains('\u903b\u8f91') ||
        lower.contains('\u6570\u636e')) {
      steps.add(TaskStep(
        id: 'step_${order}',
        order: order++,
        title: '\u5b9e\u73b0\u4e1a\u52a1\u903b\u8f91',
        description: '\u521b\u5efa\u6570\u636e\u6a21\u578b\u548c\u72b6\u6001\u7ba1\u7406',
        assignedAgentId: 'code_expert',
        action: 'code_generation',
      ));
    }

    // API/Network
    if (lower.contains('api') ||
        lower.contains('network') ||
        lower.contains('http') ||
        lower.contains('server') ||
        lower.contains('\u63a5\u53e3') ||
        lower.contains('\u7f51\u7edc')) {
      steps.add(TaskStep(
        id: 'step_${order}',
        order: order++,
        title: '\u5b9e\u73b0\u7f51\u7edc\u8bf7\u6c42',
        description: '\u521b\u5efaAPI\u5c42\u548c\u6570\u636e\u5e8f\u5217\u5316',
        assignedAgentId: 'code_expert',
        action: 'code_generation',
      ));
    }

    // Database/Storage
    if (lower.contains('database') ||
        lower.contains('storage') ||
        lower.contains('sqlite') ||
        lower.contains('hive') ||
        lower.contains('db') ||
        lower.contains('\u6570\u636e\u5e93') ||
        lower.contains('\u5b58\u50a8')) {
      steps.add(TaskStep(
        id: 'step_${order}',
        order: order++,
        title: '\u96c6\u6210\u672c\u5730\u5b58\u50a8',
        description: '\u5b9e\u73b0\u6570\u636e\u5e93\u6a21\u578b\u548c\u6301\u4e45\u5316',
        assignedAgentId: 'code_expert',
        action: 'code_generation',
      ));
    }

    // Testing
    if (lower.contains('test') ||
        lower.contains('\u6d4b\u8bd5') ||
        lower.contains('unit')) {
      steps.add(TaskStep(
        id: 'step_${order}',
        order: order++,
        title: '\u7f16\u5199\u5355\u5143\u6d4b\u8bd5',
        description: '\u4e3a\u6838\u5fc3\u529f\u80fd\u7f16\u5199\u5355\u5143\u6d4b\u8bd5',
        assignedAgentId: 'debugger',
        action: 'testing',
      ));
    }

    // Build
    steps.add(TaskStep(
      id: 'step_${order}',
      order: order++,
      title: '\u6784\u5efa\u548c\u9a8c\u8bc1',
      description: '\u8fd0\u884cflutter build\u9a8c\u8bc1\u9879\u76ee\u53ef\u6784\u5efa',
      assignedAgentId: 'terminal_runner',
      action: 'build',
    ));

    // If no specific steps were matched, add generic steps
    if (steps.isEmpty) {
      steps.addAll([
        TaskStep(
          id: 'step_1',
          order: 1,
          title: '\u5206\u6790\u9700\u6c42',
          description: '\u5206\u6790\u7528\u6237\u8bf7\u6c42\u5e76\u5236\u5b9a\u5b9e\u73b0\u65b9\u6848',
          assignedAgentId: 'code_expert',
          action: 'code_review',
        ),
        TaskStep(
          id: 'step_2',
          order: 2,
          title: '\u5b9e\u73b0\u529f\u80fd',
          description: '\u6839\u636e\u9700\u6c42\u5b9e\u73b0\u6838\u5fc3\u529f\u80fd',
          assignedAgentId: 'code_expert',
          action: 'code_generation',
        ),
        TaskStep(
          id: 'step_3',
          order: 3,
          title: '\u4ee3\u7801\u5ba1\u67e5',
          description: '\u5ba1\u67e5\u4ee3\u7801\u8d28\u91cf\u548c\u6700\u4f73\u5b9e\u8df5',
          assignedAgentId: 'code_expert',
          action: 'code_review',
        ),
      ]);
    }

    return steps;
  }
}
