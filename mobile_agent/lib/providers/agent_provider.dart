// lib/providers/agent_provider.dart
// Agent State Provider — Manages the AI Agent's state including task planning,
// action execution, progress tracking, and session history.
//
// Uses Riverpod for reactive state management.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_config.dart';
import '../services/agent_action_system.dart';
import '../services/coding_prompts.dart';
import '../services/llm_service.dart';
import '../services/project_learning_service.dart';
import '../services/storage_service.dart';
import 'api_config_provider.dart';
import 'llm_service_provider.dart';
import 'storage_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Agent State
// ═══════════════════════════════════════════════════════════════════════════

/// Immutable state representing the AI Agent's current condition.
///
/// Tracks task planning, execution progress, action history, and
/// any errors that occur during operation.
class AgentState {
  /// Whether the agent is currently planning a task.
  final bool isPlanning;

  /// Whether the agent is executing actions.
  final bool isExecuting;

  /// Current execution progress (0.0 to 1.0).
  final double progress;

  /// Currently executing plan, if any.
  final AgentTaskPlan? currentPlan;

  /// Results of the last plan execution.
  final PlanResult? lastResult;

  /// Error message, if any.
  final String? error;

  /// Current status message for UI display.
  final String statusMessage;

  /// Detected intent from the last user message.
  final CodingTaskType? detectedIntent;

  /// Currently active project path.
  final String? activeProjectPath;

  /// Learned knowledge about the active project.
  final ProjectKnowledge? projectKnowledge;

  /// Action execution history.
  final List<HistoryEntry> actionHistory;

  const AgentState({
    this.isPlanning = false,
    this.isExecuting = false,
    this.progress = 0.0,
    this.currentPlan,
    this.lastResult,
    this.error,
    this.statusMessage = 'Ready',
    this.detectedIntent,
    this.activeProjectPath,
    this.projectKnowledge,
    this.actionHistory = const [],
  });

  /// Whether the agent is busy (planning or executing).
  bool get isBusy => isPlanning || isExecuting;

  /// Whether the last execution succeeded.
  bool? get lastExecutionSucceeded => lastResult?.success;

  /// Create a copy with some fields modified.
  AgentState copyWith({
    bool? isPlanning,
    bool? isExecuting,
    double? progress,
    AgentTaskPlan? currentPlan,
    PlanResult? lastResult,
    String? error,
    String? statusMessage,
    CodingTaskType? detectedIntent,
    String? activeProjectPath,
    ProjectKnowledge? projectKnowledge,
    List<HistoryEntry>? actionHistory,
    bool clearError = false,
    bool clearPlan = false,
    bool clearResult = false,
  }) {
    return AgentState(
      isPlanning: isPlanning ?? this.isPlanning,
      isExecuting: isExecuting ?? this.isExecuting,
      progress: progress ?? this.progress,
      currentPlan: clearPlan ? null : (currentPlan ?? this.currentPlan),
      lastResult: clearResult ? null : (lastResult ?? this.lastResult),
      error: clearError ? null : (error ?? this.error),
      statusMessage: statusMessage ?? this.statusMessage,
      detectedIntent: detectedIntent ?? this.detectedIntent,
      activeProjectPath: activeProjectPath ?? this.activeProjectPath,
      projectKnowledge: projectKnowledge ?? this.projectKnowledge,
      actionHistory: actionHistory ?? this.actionHistory,
    );
  }

  @override
  String toString() {
    return 'AgentState(isPlanning: $isPlanning, isExecuting: $isExecuting, '
        'progress: ${(progress * 100).toStringAsFixed(0)}%, '
        'status: $statusMessage)';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Agent Notifier
// ═══════════════════════════════════════════════════════════════════════════

/// Manages the AI Agent's state and orchestrates task execution.
///
/// This is the core controller for the agent system. It handles:
/// - Intent detection from user messages
/// - Task planning using the LLM
/// - Action execution with progress tracking
/// - Project learning and context management
/// - Error handling and recovery
///
/// ```dart
/// final agent = ref.read(agentProvider.notifier);
/// await agent.executeFromMessage('Create a login page');
/// ```
class AgentNotifier extends StateNotifier<AgentState> {
  final Ref _ref;

  // Lazy accessors for dependencies.
  LLMService get _llm => _ref.read(llmServiceProvider);
  StorageService get _storage => _ref.read(storageServiceProvider);
  ApiConfig? get _activeConfig => _ref.read(activeApiConfigProvider);

  /// Service for learning project structure.
  ProjectLearningService? _projectLearning;

  /// Factory for creating actions from JSON.
  ActionFactory? _actionFactory;

  /// Action history tracker.
  final ActionHistory _history = ActionHistory();

  AgentNotifier(this._ref) : super(const AgentState()) {
    _initializeServices();
  }

  /// Initialize dependent services.
  void _initializeServices() {
    try {
      _projectLearning = ProjectLearningService(
        storage: _storage,
        llm: _llm,
      );
      _actionFactory = ActionFactory(storage: _storage);
    } catch (e) {
      debugPrint('[AgentNotifier] Failed to initialize services: $e');
    }
  }

  // ─── Intent Detection ──────────────────────────────────────────────

  /// Detect the user's intent from their message.
  ///
  /// Uses keyword matching for fast classification.
  /// Returns the detected [CodingTaskType].
  CodingTaskType detectIntent(String message) {
    final lower = message.toLowerCase();

    // Code generation keywords.
    if (_matchesAny(lower, [
      'create ', 'generate ', 'write ', 'make ', 'build ', '新建', '创建',
      '生成', '写一个', '写一个',
    ])) {
      return CodingTaskType.generate;
    }

    // Explanation keywords.
    if (_matchesAny(lower, [
      'explain ', 'what does', 'how does', 'meaning of', 'meaning',
      '解释', '什么意思', '怎么回事', '说明', '讲解',
    ])) {
      return CodingTaskType.explain;
    }

    // Fix keywords.
    if (_matchesAny(lower, [
      'fix ', 'debug ', 'error ', 'bug ', 'broken ', 'not working',
      '修复', '调试', '报错', '错误', '有问题', '不行',
    ])) {
      return CodingTaskType.fix;
    }

    // Refactor keywords.
    if (_matchesAny(lower, [
      'refactor ', 'improve ', 'optimize ', 'clean up', 'restructure',
      '重构', '优化', '改进', '整理',
    ])) {
      return CodingTaskType.refactor;
    }

    // Review keywords.
    if (_matchesAny(lower, [
      'review ', 'check ', 'evaluate ', 'assess ', 'code review',
      'review', '检查', '评估', '审查', 'code review',
    ])) {
      return CodingTaskType.review;
    }

    // Test keywords.
    if (_matchesAny(lower, [
      'test ', 'testing', 'unit test', 'widget test', 'integration test',
      '测试', '单元测试', '写测试',
    ])) {
      return CodingTaskType.test;
    }

    // Documentation keywords.
    if (_matchesAny(lower, [
      'document ', 'doc ', 'comment ', 'readme', 'documentation',
      '文档', '注释', '写文档',
    ])) {
      return CodingTaskType.document;
    }

    // Screenshot/UI keywords.
    if (_matchesAny(lower, [
      'screenshot', 'ui ', 'design ', 'mockup', '界面', '截图', '设计',
    ])) {
      return CodingTaskType.screenshot;
    }

    // Default to chat for general questions.
    return CodingTaskType.chat;
  }

  bool _matchesAny(String text, List<String> keywords) {
    return keywords.any((k) => text.contains(k));
  }

  // ─── Project Management ────────────────────────────────────────────

  /// Set the active project and learn its structure.
  ///
  /// [projectPath] Absolute path to the project root.
  Future<void> setActiveProject(String projectPath) async {
    state = state.copyWith(
      activeProjectPath: projectPath,
      statusMessage: 'Learning project...',
    );

    try {
      if (_projectLearning != null) {
        final knowledge = await _projectLearning!.learnProject(projectPath);
        state = state.copyWith(
          projectKnowledge: knowledge,
          statusMessage: 'Project learned: ${knowledge.architecture.pattern} architecture',
        );
      } else {
        state = state.copyWith(
          statusMessage: 'Project set (learning unavailable)',
        );
      }
    } catch (e) {
      debugPrint('[AgentNotifier] Project learning failed: $e');
      state = state.copyWith(
        error: 'Failed to learn project: $e',
        statusMessage: 'Project learning failed',
      );
    }
  }

  /// Clear the active project.
  void clearActiveProject() {
    state = state.copyWith(
      clearError: true,
      activeProjectPath: null,
      projectKnowledge: null,
      statusMessage: 'Ready',
    );
  }

  // ─── Task Planning ─────────────────────────────────────────────────

  /// Plan a task from a user request.
  ///
  /// Uses the LLM to break down the request into actionable steps.
  /// Updates state with the plan and detected intent.
  ///
  /// [userRequest] The natural language request.
  Future<AgentTaskPlan?> planTask(String userRequest) async {
    final config = _activeConfig;
    if (config == null) {
      state = state.copyWith(
        error: 'No API configuration. Please add one in Settings.',
        statusMessage: 'No API config',
      );
      return null;
    }

    final intent = detectIntent(userRequest);
    state = state.copyWith(
      isPlanning: true,
      detectedIntent: intent,
      statusMessage: 'Planning task...',
      clearError: true,
    );

    try {
      // Build project context.
      final projectContext = state.projectKnowledge?.toPromptContext() ?? 'No project context.';

      // Generate planning prompt.
      final prompt = taskPlanningPrompt(
        userRequest: userRequest,
        projectContext: projectContext,
      );

      // Get plan from LLM.
      final response = await _llm.chat(prompt, [], config);

      // Parse plan and create actions.
      final actions = _parsePlanToActions(response);

      final plan = AgentTaskPlan(
        originalRequest: userRequest,
        actions: actions,
        description: response.substring(0, response.length > 200 ? 200 : response.length),
      );

      state = state.copyWith(
        isPlanning: false,
        currentPlan: plan,
        statusMessage: 'Plan ready: ${actions.length} steps',
      );

      return plan;
    } catch (e) {
      debugPrint('[AgentNotifier] Task planning failed: $e');
      state = state.copyWith(
        isPlanning: false,
        error: 'Planning failed: $e',
        statusMessage: 'Planning failed',
      );
      return null;
    }
  }

  // ─── Action Execution ──────────────────────────────────────────────

  /// Execute the current plan.
  ///
  /// Runs all actions in the current plan sequentially,
  /// updating progress and status along the way.
  Future<PlanResult?> executePlan() async {
    final plan = state.currentPlan;
    if (plan == null) {
      state = state.copyWith(
        error: 'No plan to execute. Plan a task first.',
        statusMessage: 'No plan available',
      );
      return null;
    }

    state = state.copyWith(
      isExecuting: true,
      progress: 0.0,
      statusMessage: 'Executing ${plan.actionCount} actions...',
      clearError: true,
      clearResult: true,
    );

    try {
      // Execute with progress updates.
      final results = <ActionResult>[];

      for (var i = 0; i < plan.actions.length; i++) {
        final action = plan.actions[i];
        final progress = plan.actions.length > 1 ? i / (plan.actions.length - 1) : 1.0;

        state = state.copyWith(
          progress: progress,
          statusMessage: 'Step ${i + 1}/${plan.actions.length}: ${action.description}',
        );

        final result = await action.execute();
        results.add(result);

        // Track in history.
        _history.add(action, result);

        if (!result.success) {
          // Step failed.
          final planResult = PlanResult.failure(
            failedStep: i,
            errorMessage: result.message,
            partialResults: results,
          );

          state = state.copyWith(
            isExecuting: false,
            progress: 1.0,
            lastResult: planResult,
            error: 'Step ${i + 1} failed: ${result.message}',
            statusMessage: 'Failed at step ${i + 1}',
            actionHistory: List.unmodifiable(_history.entries),
          );

          return planResult;
        }
      }

      // All steps succeeded.
      final planResult = PlanResult.success(
        executedActions: results.length,
        results: results,
      );

      state = state.copyWith(
        isExecuting: false,
        progress: 1.0,
        lastResult: planResult,
        statusMessage: 'Completed ${results.length} actions successfully',
        actionHistory: List.unmodifiable(_history.entries),
      );

      return planResult;
    } catch (e) {
      debugPrint('[AgentNotifier] Execution error: $e');
      state = state.copyWith(
        isExecuting: false,
        progress: 1.0,
        error: 'Execution error: $e',
        statusMessage: 'Execution error',
        actionHistory: List.unmodifiable(_history.entries),
      );
      return null;
    }
  }

  /// Execute a single action directly.
  ///
  /// For simple operations that don't need full planning.
  Future<ActionResult> executeAction(AgentAction action) async {
    state = state.copyWith(
      isExecuting: true,
      statusMessage: 'Executing: ${action.description}',
      clearError: true,
    );

    try {
      final result = await action.execute();
      _history.add(action, result);

      state = state.copyWith(
        isExecuting: false,
        statusMessage: result.success
            ? 'Completed: ${action.description}'
            : 'Failed: ${result.message}',
        error: result.success ? null : result.message,
        actionHistory: List.unmodifiable(_history.entries),
      );

      return result;
    } catch (e) {
      state = state.copyWith(
        isExecuting: false,
        error: 'Action error: $e',
        statusMessage: 'Action error',
      );
      return ActionResult.failure(action.name, 'Exception: $e');
    }
  }

  /// Convenience method: plan and execute from a user message.
  ///
  /// This is the main entry point for natural language task execution.
  /// It detects intent, plans the task, and executes the plan.
  ///
  /// [message] The user's natural language request.
  /// Returns the [PlanResult] if execution occurred, null otherwise.
  Future<PlanResult?> executeFromMessage(String message) async {
    // Detect intent.
    final intent = detectIntent(message);
    state = state.copyWith(detectedIntent: intent);

    // For simple intents that don't need planning, handle directly.
    switch (intent) {
      case CodingTaskType.chat:
        // Chat is handled by the chat system, not the agent.
        return null;
      default:
        // Plan and execute.
        final plan = await planTask(message);
        if (plan != null) {
          return executePlan();
        }
        return null;
    }
  }

  // ─── Rollback ──────────────────────────────────────────────────────

  /// Rollback the last executed plan.
  Future<void> rollback() async {
    final plan = state.currentPlan;
    if (plan == null) {
      state = state.copyWith(
        error: 'No plan to rollback',
        statusMessage: 'Nothing to rollback',
      );
      return;
    }

    state = state.copyWith(
      statusMessage: 'Rolling back...',
    );

    try {
      await plan.rollback();
      state = state.copyWith(
        statusMessage: 'Rollback completed',
        clearResult: true,
      );
    } catch (e) {
      state = state.copyWith(
        error: 'Rollback failed: $e',
        statusMessage: 'Rollback failed',
      );
    }
  }

  // ─── History ───────────────────────────────────────────────────────

  /// Clear action history.
  void clearHistory() {
    _history.clear();
    state = state.copyWith(actionHistory: const []);
  }

  // ─── Helpers ───────────────────────────────────────────────────────

  /// Parse an LLM response into a list of actions.
  ///
  /// This is a simplified parser. In production, the LLM would
  /// return structured JSON that maps directly to action parameters.
  List<AgentAction> _parsePlanToActions(String llmResponse) {
    final actions = <AgentAction>[];

    // Try to find JSON-like action descriptions in the response.
    // This is a best-effort parser for LLM output.
    final jsonPattern = RegExp(
      r'\{\s*["\']?name["\']?\s*:\s*["\'](\w+)["\']',
      multiLine: true,
    );

    final matches = jsonPattern.allMatches(llmResponse);
    for (final match in matches) {
      final actionName = match.group(1);
      if (actionName == null) continue;

      // Extract params from surrounding context.
      final startIdx = match.start;
      var endIdx = llmResponse.indexOf('}', startIdx);
      if (endIdx == -1) endIdx = llmResponse.length;

      final jsonStr = llmResponse.substring(startIdx, endIdx + 1);
      try {
        final action = _parseActionJson(actionName, jsonStr);
        if (action != null) {
          actions.add(action);
        }
      } catch (e) {
        debugPrint('[AgentNotifier] Failed to parse action: $e');
      }
    }

    // If no structured actions found, return empty list.
    // The caller can handle this gracefully.
    return actions;
  }

  /// Parse a single action from a JSON string.
  AgentAction? _parseActionJson(String name, String jsonStr) {
    if (_actionFactory == null) return null;

    // Simple param extraction.
    final params = <String, dynamic>{};
    final paramPattern = RegExp(r'["\'](\w+)["\']\s*:\s*["\']([^"\']+)["\']');
    for (final match in paramPattern.allMatches(jsonStr)) {
      final key = match.group(1);
      final value = match.group(2);
      if (key != null && value != null && key != 'name') {
        params[key] = value;
      }
    }

    return _actionFactory!.fromJson({
      'name': name,
      'params': params,
    });
  }

  @override
  void dispose() {
    _history.clear();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Providers
// ═══════════════════════════════════════════════════════════════════════════

/// Primary provider for the AI Agent state.
///
/// Provides access to the agent's current state and allows
/// task planning, execution, and project management.
///
/// ```dart
/// // Read state
/// final agentState = ref.watch(agentProvider);
/// if (agentState.isBusy) { ... }
///
/// // Execute task
/// await ref.read(agentProvider.notifier).executeFromMessage('Create a button widget');
/// ```
final agentProvider = StateNotifierProvider<AgentNotifier, AgentState>((ref) {
  return AgentNotifier(ref);
});

// ─── Derived Providers ─────────────────────────────────────────────

/// Whether the agent is currently busy (planning or executing).
///
/// ```dart
/// final isBusy = ref.watch(agentBusyProvider);
/// ```
final agentBusyProvider = Provider<bool>((ref) {
  return ref.watch(agentProvider).isBusy;
});

/// Current execution progress (0.0 to 1.0).
///
/// ```dart
/// final progress = ref.watch(agentProgressProvider);
/// ProgressBar(value: progress)
/// ```
final agentProgressProvider = Provider<double>((ref) {
  return ref.watch(agentProvider).progress;
});

/// Current agent status message for display.
///
/// ```dart
/// final status = ref.watch(agentStatusProvider);
/// Text(status)
/// ```
final agentStatusProvider = Provider<String>((ref) {
  return ref.watch(agentProvider).statusMessage;
});

/// Last error message from the agent.
///
/// ```dart
/// final error = ref.watch(agentErrorProvider);
/// if (error != null) { showErrorSnackbar(error); }
/// ```
final agentErrorProvider = Provider<String?>((ref) {
  return ref.watch(agentProvider).error;
});

/// The current task plan.
///
/// ```dart
/// final plan = ref.watch(agentPlanProvider);
/// if (plan != null) { showPlanSteps(plan); }
/// ```
final agentPlanProvider = Provider<AgentTaskPlan?>((ref) {
  return ref.watch(agentProvider).currentPlan;
});

/// Detected intent from the last user message.
///
/// ```dart
/// final intent = ref.watch(agentIntentProvider);
/// if (intent == CodingTaskType.generate) { ... }
/// ```
final agentIntentProvider = Provider<CodingTaskType?>((ref) {
  return ref.watch(agentProvider).detectedIntent;
});

/// Whether the last execution succeeded.
///
/// ```dart
/// final success = ref.watch(agentLastSuccessProvider);
/// if (success == true) { showSuccessToast(); }
/// ```
final agentLastSuccessProvider = Provider<bool?>((ref) {
  return ref.watch(agentProvider).lastExecutionSucceeded;
});

/// Active project knowledge.
///
/// ```dart
/// final knowledge = ref.watch(projectKnowledgeProvider);
/// if (knowledge != null) { useContext(knowledge); }
/// ```
final projectKnowledgeProvider = Provider<ProjectKnowledge?>((ref) {
  return ref.watch(agentProvider).projectKnowledge;
});

/// Number of actions in the current plan.
///
/// ```dart
/// final count = ref.watch(agentPlanStepCountProvider);
/// ```
final agentPlanStepCountProvider = Provider<int>((ref) {
  return ref.watch(agentProvider).currentPlan?.actionCount ?? 0;
});
