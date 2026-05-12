// lib/core/agent_paradigm.dart
// Agent Paradigm Configuration
//
// Based on the "AI Agent 范式全景图":
// MobileCode uses a carefully selected subset of paradigms
// optimized for lightweight mobile coding.
//
// ═══════════════════════════════════════════════════════════════════════════
// SELECTION RATIONALE
// ═══════════════════════════════════════════════════════════════════════════
//
// MobileCode is a LIGHTWEIGHT mobile coding agent. We must balance
// capability against resource constraints (battery, memory, network).
//
// Selected paradigms (lightweight & effective):
//   ReAct, Prompt Chaining, Routing, Supervisor-Worker,
//   Function Calling, Reflection, Human-in-the-Loop
//
// Excluded paradigms (too heavy or wrong fit):
//   Swarm, Debate, MCP, Computer Use — see inline documentation
//
// Architecture diagram:
//
//   ┌─────────────────────────────────────────────────────────┐
//   │                    Supervisor Agent                      │
//   │          (understands需求, decomposes tasks)             │
//   └─────────────────────────┬───────────────────────────────┘
//                             │ delegates
//         ┌───────────────────┼───────────────────┐
//         ▼                   ▼                   ▼
//   ┌──────────┐      ┌──────────┐      ┌──────────────┐
//   │  Code    │      │  Debug   │      │    Git       │
//   │  Expert  │      │  Helper  │      │   Helper     │
//   │  Worker  │      │  Worker  │      │   Worker     │
//   └──────────┘      └──────────┘      └──────────────┘
//         │                   │                   │
//         └───────────────────┼───────────────────┘
//                             ▼
//              ┌──────────────────────────┐
//              │    Function Calling       │
//              │  writeFile, readFile,     │
//              │  runCommand, gitCommit    │
//              └──────────────────────────┘

import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 一、核心推理范式: ReAct (Reason + Act)
// ═══════════════════════════════════════════════════════════════════════════
//
// ReAct Loop:
//   思考(Thought) → 行动(Action) → 观察(Observation) → 循环迭代
//
// Example for "create a login page":
//   Thought: "用户要创建一个登录页面，我需要先生成布局代码"
//   Action: writeFile("login_page.dart", layoutCode)
//   Observation: "文件写入成功，但缺少表单验证逻辑"
//   Thought: "需要添加表单验证，用TextFormField"
//   Action: editFile("login_page.dart", addValidation)
//   ... until done
//
// Why ReAct? It provides transparent reasoning and is proven effective
// for coding tasks. The thought-observation loop naturally handles
// debugging and iterative refinement.

/// ReAct (Reason + Act) paradigm configuration.
class ReActConfig {
  const ReActConfig._();

  /// Enable ReAct reasoning loop.
  static const bool enabled = true;

  /// Maximum number of reasoning-acting iterations before stopping.
  /// Prevents infinite loops when the agent gets stuck.
  static const int maxIterations = 10;

  /// Prompt template for the reasoning phase.
  static const String reasoningPrompt = '''
You are a coding assistant using the ReAct paradigm.
For the given task, follow this loop:
1. THOUGHT: Analyze what needs to be done and plan the next action.
2. ACTION: Choose one available action and specify parameters.
3. OBSERVATION: Review the result and decide if more actions are needed.

Available actions:
- writeFile(path, content): Create or overwrite a file
- editFile(path, oldText, newText): Replace text in a file
- readFile(path): Read file content for context
- runCommand(command): Execute a terminal command
- searchCode(query): Search codebase for relevant code

Think step by step. Explain your reasoning clearly.
''';

  /// Whether to include the full reasoning trace in responses.
  static const bool exposeReasoningTrace = true;
}

// ═══════════════════════════════════════════════════════════════════════════
// 二、工作流编排: Prompt Chaining + Routing
// ═══════════════════════════════════════════════════════════════════════════
//
// Prompt Chaining: Multi-step code generation pipeline
//   Step 1: Analyze requirements → Generate architecture
//   Step 2: Generate data models
//   Step 3: Generate UI code
//   Step 4: Generate business logic
//   Step 5: Integrate and test
//
// Routing: Route tasks to specialized workers based on intent
//   "修复bug"     → Debugger Agent Worker
//   "写新功能"    → Code Expert Worker
//   "Git操作"     → Git Helper Worker
//   "项目结构"    → Project Manager Worker

/// Prompt Chaining configuration.
class PromptChainingConfig {
  const PromptChainingConfig._();

  /// Enable prompt chaining for multi-step code generation.
  static const bool enabled = true;

  /// Code generation pipeline stages.
  static const List<CodeGenStage> stages = [
    CodeGenStage(
      name: 'architecture',
      description: 'Analyze requirements and design architecture',
      promptTemplate: 'Given the requirement: {requirement}\n'
          'Design the architecture: file structure, classes, dependencies.',
    ),
    CodeGenStage(
      name: 'models',
      description: 'Generate data models',
      promptTemplate: 'Based on the architecture, define data models '
          'and classes for: {context}',
    ),
    CodeGenStage(
      name: 'ui',
      description: 'Generate UI code',
      promptTemplate: 'Create the UI components using the models: {context}',
    ),
    CodeGenStage(
      name: 'logic',
      description: 'Generate business logic',
      promptTemplate: 'Implement business logic and state management: {context}',
    ),
    CodeGenStage(
      name: 'integrate',
      description: 'Integration and cleanup',
      promptTemplate: 'Integrate all components and ensure consistency: {context}',
    ),
  ];
}

/// A single stage in the code generation pipeline.
class CodeGenStage {
  final String name;
  final String description;
  final String promptTemplate;

  const CodeGenStage({
    required this.name,
    required this.description,
    required this.promptTemplate,
  });
}

/// Routing configuration for task dispatch.
class RoutingConfig {
  const RoutingConfig._();

  /// Enable intent-based routing to specialized workers.
  static const bool enabled = true;

  /// Route definitions: intent keyword → worker type.
  static const Map<String, String> routes = {
    // Code generation
    'create': 'code_expert',
    'generate': 'code_expert',
    'write': 'code_expert',
    '新建': 'code_expert',
    '创建': 'code_expert',
    '生成': 'code_expert',
    '写一个': 'code_expert',

    // Debugging
    'fix': 'debugger',
    'debug': 'debugger',
    'error': 'debugger',
    'bug': 'debugger',
    'broken': 'debugger',
    '修复': 'debugger',
    '调试': 'debugger',
    '报错': 'debugger',
    '错误': 'debugger',

    // Git operations
    'git': 'git_helper',
    'commit': 'git_helper',
    'push': 'git_helper',
    'pull': 'git_helper',
    'branch': 'git_helper',

    // Refactoring
    'refactor': 'code_expert',
    'improve': 'code_expert',
    'optimize': 'code_expert',
    '重构': 'code_expert',
    '优化': 'code_expert',
    '改进': 'code_expert',

    // Explanation
    'explain': 'explainer',
    'what does': 'explainer',
    'how does': 'explainer',
    '解释': 'explainer',
    '说明': 'explainer',
    '讲解': 'explainer',

    // Testing
    'test': 'code_expert',
    'testing': 'code_expert',
    '单元测试': 'code_expert',

    // Documentation
    'document': 'explainer',
    'doc': 'explainer',
    '注释': 'explainer',
    '文档': 'explainer',
  };

  /// Get the worker type for a given user message.
  static String? routeFor(String message) {
    final lower = message.toLowerCase();
    for (final entry in routes.entries) {
      if (lower.contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }
    return null; // Default: supervisor handles it
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 三、多Agent协作: Supervisor-Worker
// ═══════════════════════════════════════════════════════════════════════════
//
// Supervisor: Main agent that understands requirements,
//            decomposes tasks, and coordinates workers.
//
// Workers:
//   - Code Expert:  Writes and edits code files
//   - Debug Helper: Diagnoses and fixes bugs
//   - Git Helper:   Handles version control operations
//   - Explainer:    Explains code and concepts
//
// NOT using (too heavy for mobile):
//   - Swarm/Handoff (群体/移交): Requires multiple agents running in parallel,
//     consumes too much memory and battery on mobile.
//   - Debate/Discussion (辩论/讨论): Conversational decision-making is too slow
//     for real-time coding assistance.
//   - Specialized Experts (专业化专家) as dynamic allocation: Static routing
//     is sufficient and more predictable.

/// Supervisor-Worker paradigm configuration.
class SupervisorWorkerConfig {
  const SupervisorWorkerConfig._();

  /// Enable supervisor-worker orchestration.
  static const bool enabled = true;

  /// Maximum concurrent workers (limited for mobile performance).
  static const int maxConcurrentWorkers = 2;

  /// Worker timeout (seconds).
  static const int workerTimeoutSeconds = 60;

  /// Available worker types.
  static const Map<String, WorkerDefinition> workers = {
    'code_expert': WorkerDefinition(
      name: 'Code Expert',
      description: 'Writes, edits, and refactors code. Generates widgets, '
          'models, services, and business logic.',
      capabilities: ['writeFile', 'editFile', 'replaceCode', 'insertCode', 'deleteCode'],
      systemPrompt: 'You are an expert Flutter/Dart developer. Write clean, '
          'well-documented code following best practices. Use Riverpod for '
          'state management, Dio for networking, and follow the existing '
          'project architecture.',
    ),
    'debugger': WorkerDefinition(
      name: 'Debug Helper',
      description: 'Diagnoses errors, analyzes stack traces, and fixes bugs.',
      capabilities: ['readFile', 'editFile', 'runCommand', 'searchCode'],
      systemPrompt: 'You are a debugging expert. Analyze error messages and '
          'stack traces carefully. Identify root causes and apply minimal, '
          'targeted fixes. Always verify your fix by examining the context.',
    ),
    'git_helper': WorkerDefinition(
      name: 'Git Helper',
      description: 'Handles Git operations: commit, push, pull, branch, merge.',
      capabilities: ['gitCommit', 'gitPush', 'gitPull', 'runCommand'],
      systemPrompt: 'You are a Git expert. Follow conventional commit formats. '
          'Always check status before operations. Never force-push to shared branches.',
    ),
    'explainer': WorkerDefinition(
      name: 'Explainer',
      description: 'Explains code, concepts, and architecture.',
      capabilities: ['readFile', 'searchCode'],
      systemPrompt: 'You are a technical educator. Explain concepts clearly '
          'with examples. Reference actual code from the project when possible.',
    ),
  };
}

/// Definition of a worker agent.
class WorkerDefinition {
  final String name;
  final String description;
  final List<String> capabilities;
  final String systemPrompt;

  const WorkerDefinition({
    required this.name,
    required this.description,
    required this.capabilities,
    required this.systemPrompt,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// 四、交互执行: Function Calling
// ═══════════════════════════════════════════════════════════════════════════
//
// Function Calling: Agent calls tool functions to interact with the environment.
//   - writeFile(path, content): Create/overwrite files
//   - readFile(path): Read file content
//   - runCommand(command): Execute terminal commands
//   - gitCommit(message): Commit changes
//   - searchCode(query): Search codebase
//
// NOT using:
//   - MCP (Model Context Protocol): Requires server-side infrastructure
//     that is not available in a mobile-only setup.
//   - Computer Use: This paradigm is for UI automation (clicking buttons,
//     typing in apps), not for writing code. Wrong paradigm for coding.

/// Function Calling paradigm configuration.
class FunctionCallingConfig {
  const FunctionCallingConfig._();

  /// Enable function calling for tool use.
  static const bool enabled = true;

  /// Available functions for the agent.
  static const List<AgentFunction> functions = [
    AgentFunction(
      name: 'writeFile',
      description: 'Write content to a file (creates or overwrites)',
      parameters: {
        'filePath': 'string (required) — Absolute path to the file',
        'content': 'string (required) — File content',
      },
    ),
    AgentFunction(
      name: 'editFile',
      description: 'Replace specific text in a file',
      parameters: {
        'filePath': 'string (required)',
        'oldText': 'string (required) — Text to find',
        'newText': 'string (required) — Replacement text',
      },
    ),
    AgentFunction(
      name: 'readFile',
      description: 'Read the content of a file',
      parameters: {
        'filePath': 'string (required)',
      },
    ),
    AgentFunction(
      name: 'runCommand',
      description: 'Execute a terminal command in the project directory',
      parameters: {
        'command': 'string (required) — Shell command to execute',
      },
    ),
    AgentFunction(
      name: 'gitCommit',
      description: 'Stage all changes and commit with a message',
      parameters: {
        'message': 'string (required) — Commit message',
      },
    ),
    AgentFunction(
      name: 'searchCode',
      description: 'Search the codebase for files matching a query',
      parameters: {
        'query': 'string (required) — Search term or pattern',
      },
    ),
  ];

  /// Get function definitions as a formatted string for LLM prompts.
  static String getFunctionsDescription() {
    final buffer = StringBuffer('Available Functions:\n');
    for (var i = 0; i < functions.length; i++) {
      final f = functions[i];
      buffer.writeln('${i + 1}. ${f.name} — ${f.description}');
      for (final param in f.parameters.entries) {
        buffer.writeln('   ${param.key}: ${param.value}');
      }
    }
    return buffer.toString();
  }
}

/// Definition of an agent-callable function.
class AgentFunction {
  final String name;
  final String description;
  final Map<String, String> parameters;

  const AgentFunction({
    required this.name,
    required this.description,
    required this.parameters,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// 五、可靠性增强: Reflection + Self-Correction + Guardrails
// ═══════════════════════════════════════════════════════════════════════════
//
// Reflection: After each action, the agent reflects:
//   "我写的代码对吗？能编译吗？有bug吗？"
//
// Self-Correction: If reflection detects issues, the agent
//   automatically retries with corrections (up to max attempts).
//
// Iterative Refinement: Progressive code quality improvement.
//   Step 1: Generate skeleton → Step 2: Add details
//   Step 3: Optimize performance → Step 4: Add documentation
//
// Guardrails: Safety barriers to prevent harmful actions.
//   - Block deletion of important files (.git, pubspec.yaml, etc.)
//   - Rate-limit API calls
//   - Scan generated code for security issues

/// Reflection and self-correction configuration.
class ReflectionConfig {
  const ReflectionConfig._();

  /// Enable reflection after each action.
  static const bool useReflection = true;

  /// Enable automatic self-correction on failure.
  static const bool useSelfCorrection = true;

  /// Maximum self-correction attempts before giving up.
  static const int maxSelfCorrectionAttempts = 3;

  /// Enable iterative code refinement.
  static const bool useIterativeRefinement = true;

  /// Reflection prompt template.
  static const String reflectionPrompt = '''
After performing the action, reflect on the result:
1. Was the action successful?
2. Does the code compile without errors?
3. Are there any potential bugs or issues?
4. Can the code be improved?
5. Is the change consistent with the existing codebase?

If any issues are found, plan a correction action.
''';

  /// Self-correction prompt template.
  static const String selfCorrectionPrompt = '''
The previous action had issues. Please correct it.
Analyze the error and apply a minimal fix.
Preserve the intent of the original change while fixing the problem.
''';
}

/// Safety guardrails configuration.
class GuardrailsConfig {
  const GuardrailsConfig._();

  /// Enable safety guardrails.
  static const bool enabled = true;

  /// Files that must NOT be deleted or modified.
  static const List<String> protectedFiles = [
    '.git/',
    'pubspec.yaml',
    'pubspec.lock',
    'android/',
    'ios/',
    'macos/',
    'windows/',
    'linux/',
    'README.md',
  ];

  /// Maximum API calls per minute (rate limiting).
  static const int maxApiCallsPerMinute = 30;

  /// Maximum file size that can be written (bytes).
  static const int maxFileSizeBytes = 1024 * 1024; // 1MB

  /// Blocked command patterns (security).
  static const List<String> blockedCommands = [
    'rm -rf /',
    'rm -rf ~',
    'dd if=',
    ':(){:|:&};:', // fork bomb
    '> /dev/',
    'mkfs.',
    'chmod -R 777 /',
  ];

  /// Check if a file path is protected.
  static bool isProtected(String filePath) {
    for (final protected in protectedFiles) {
      if (filePath.contains(protected)) return true;
    }
    return false;
  }

  /// Check if a command is blocked.
  static bool isBlockedCommand(String command) {
    final lower = command.toLowerCase();
    for (final blocked in blockedCommands) {
      if (lower.contains(blocked.toLowerCase())) return true;
    }
    return false;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 六、人机协同: Human-in-the-Loop
// ═══════════════════════════════════════════════════════════════════════════
//
// Human-in-the-Loop: The agent pauses at critical decision points
// and requests human confirmation before proceeding.
//
// Critical actions requiring confirmation:
//   - Deleting files
//   - Pushing to Git remote
//   - Deploying to production
//   - High token usage (costly operations)
//
// This ensures the user maintains control over destructive or expensive actions.

/// Human-in-the-Loop configuration.
class HumanInTheLoopConfig {
  const HumanInTheLoopConfig._();

  /// Enable human-in-the-loop for critical actions.
  static const bool enabled = true;

  /// Actions that require human confirmation.
  static const List<String> humanConfirmActions = [
    'delete_file',
    'git_push',
    'git_force_push',
    'deploy_production',
    'high_token_usage',
    'modify_protected_file',
    'run_shell_command',
  ];

  /// Token threshold for "high usage" warning.
  static const int highTokenThreshold = 10000;

  /// Confirmation prompt template.
  static String buildConfirmationPrompt(String action, Map<String, dynamic> details) {
    final buffer = StringBuffer();
    buffer.writeln('## Action Requires Confirmation');
    buffer.writeln();
    buffer.writeln('**Action**: $action');
    buffer.writeln();
    buffer.writeln('**Details**:');
    for (final entry in details.entries) {
      buffer.writeln('- ${entry.key}: ${entry.value}');
    }
    buffer.writeln();
    buffer.writeln('Do you want to proceed? (yes/no)');
    return buffer.toString();
  }

  /// Check if an action requires human confirmation.
  static bool requiresConfirmation(String actionName, {Map<String, dynamic>? params}) {
    final normalized = actionName.toLowerCase();

    // Check explicit action names.
    if (humanConfirmActions.contains(normalized)) return true;

    // Check for file deletion.
    if (normalized.contains('delete') || normalized.contains('remove')) {
      if (params != null && params.containsKey('filePath')) {
        final path = params['filePath'] as String?;
        if (path != null && GuardrailsConfig.isProtected(path)) {
          return true; // Protected file deletion always requires confirmation.
        }
      }
      return true;
    }

    // Check for git push.
    if (normalized.contains('push') && normalized.contains('git')) return true;

    return false;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Master Configuration Class
// ═══════════════════════════════════════════════════════════════════════════

/// Master agent paradigm configuration for MobileCode.
///
/// This class serves as the single source of truth for all agent
/// paradigm settings. It combines all sub-configurations and provides
/// a unified interface.
///
/// ```dart
/// // Check if a paradigm is enabled
/// if (AgentParadigm.useReAct) { ... }
///
/// // Get ReAct max iterations
/// final maxIter = AgentParadigm.maxIterations;
///
/// // Check if action needs confirmation
/// final needsConfirm = AgentParadigm.requiresHumanConfirm('delete_file');
/// ```
class AgentParadigm {
  const AgentParadigm._();

  // ── ReAct ──────────────────────────────────────────────────

  /// Enable ReAct (Reason + Act) reasoning loop.
  static const bool useReAct = ReActConfig.enabled;

  /// Maximum ReAct iterations before stopping.
  static const int maxIterations = ReActConfig.maxIterations;

  // ── Prompt Chaining ────────────────────────────────────────

  /// Enable prompt chaining for multi-step code generation.
  static const bool usePromptChaining = PromptChainingConfig.enabled;

  /// Code generation pipeline stages.
  static const List<CodeGenStage> codeGenStages = PromptChainingConfig.stages;

  // ── Routing ────────────────────────────────────────────────

  /// Enable intent-based routing to specialized workers.
  static const bool useRouting = RoutingConfig.enabled;

  /// Route a user message to the appropriate worker type.
  static String? routeMessage(String message) => RoutingConfig.routeFor(message);

  // ── Supervisor-Worker ──────────────────────────────────────

  /// Enable supervisor-worker orchestration.
  static const bool useSupervisorWorker = SupervisorWorkerConfig.enabled;

  /// Maximum concurrent workers (mobile performance limit).
  static const int maxConcurrentWorkers = SupervisorWorkerConfig.maxConcurrentWorkers;

  /// Available worker definitions.
  static const Map<String, WorkerDefinition> workers = SupervisorWorkerConfig.workers;

  // ── Excluded paradigms (documented reasons) ────────────────

  /// Swarm/Handoff: Multiple parallel agents — too heavy for mobile.
  /// Memory and battery constraints make this impractical.
  static const bool useSwarm = false;

  /// Debate/Discussion: Conversational decision-making is too slow
  /// for real-time coding assistance on mobile.
  static const bool useDebate = false;

  // ── Function Calling ───────────────────────────────────────

  /// Enable function calling for tool use.
  static const bool useFunctionCalling = FunctionCallingConfig.enabled;

  /// Get function descriptions for LLM prompts.
  static String get functionDescriptions => FunctionCallingConfig.getFunctionsDescription();

  // ── Excluded paradigms ─────────────────────────────────────

  /// MCP (Model Context Protocol): Requires server infrastructure.
  /// Mobile-only setup cannot host MCP servers.
  static const bool useMCP = false;

  /// Computer Use: Wrong paradigm — it's for UI automation, not coding.
  /// We need code generation, not screen interaction.
  static const bool useComputerUse = false;

  // ── Reflection ─────────────────────────────────────────────

  /// Enable reflection after each action.
  static const bool useReflection = ReflectionConfig.useReflection;

  /// Enable automatic self-correction on failure.
  static const bool useSelfCorrection = ReflectionConfig.useSelfCorrection;

  /// Maximum self-correction attempts.
  static const int maxSelfCorrectionAttempts = ReflectionConfig.maxSelfCorrectionAttempts;

  /// Enable iterative code refinement.
  static const bool useIterativeRefinement = ReflectionConfig.useIterativeRefinement;

  // ── Guardrails ─────────────────────────────────────────────

  /// Enable safety guardrails.
  static const bool useGuardrails = GuardrailsConfig.enabled;

  /// Check if a file is protected from modification.
  static bool isProtectedFile(String path) => GuardrailsConfig.isProtected(path);

  /// Check if a command is blocked for security.
  static bool isBlockedCommand(String cmd) => GuardrailsConfig.isBlockedCommand(cmd);

  // ── Human-in-the-Loop ──────────────────────────────────────

  /// Enable human-in-the-loop for critical actions.
  static const bool useHumanInTheLoop = HumanInTheLoopConfig.enabled;

  /// Actions requiring human confirmation.
  static const List<String> humanConfirmActions = HumanInTheLoopConfig.humanConfirmActions;

  /// Check if an action requires human confirmation.
  static bool requiresHumanConfirm(String action, {Map<String, dynamic>? params}) {
    return HumanInTheLoopConfig.requiresConfirmation(action, params: params);
  }

  /// Build a confirmation prompt for an action.
  static String buildConfirmPrompt(String action, Map<String, dynamic> details) {
    return HumanInTheLoopConfig.buildConfirmationPrompt(action, details);
  }

  // ── Utility ────────────────────────────────────────────────

  /// Get a summary of all enabled paradigms.
  static Map<String, bool> get enabledParadigms => {
        'ReAct': useReAct,
        'Prompt Chaining': usePromptChaining,
        'Routing': useRouting,
        'Supervisor-Worker': useSupervisorWorker,
        'Function Calling': useFunctionCalling,
        'Reflection': useReflection,
        'Self-Correction': useSelfCorrection,
        'Iterative Refinement': useIterativeRefinement,
        'Guardrails': useGuardrails,
        'Human-in-the-Loop': useHumanInTheLoop,
      };

  /// Get a summary of all excluded paradigms with reasons.
  static Map<String, String> get excludedParadigms => {
        'Swarm/Handoff': 'Too heavy for mobile (memory/battery)',
        'Debate/Discussion': 'Too slow for real-time coding',
        'MCP': 'Requires server infrastructure',
        'Computer Use': 'Wrong paradigm (UI automation vs coding)',
      };

  /// Print paradigm configuration summary (for debugging).
  static void printSummary() {
    debugPrint('═══ Agent Paradigm Configuration ═══');
    debugPrint('Enabled:');
    for (final entry in enabledParadigms.entries) {
      debugPrint('  ${entry.key}: ${entry.value ? "ON" : "OFF"}');
    }
    debugPrint('Excluded (by design):');
    for (final entry in excludedParadigms.entries) {
      debugPrint('  ${entry.key}: ${entry.value}');
    }
    debugPrint('═══════════════════════════════════');
  }
}
