import 'dart:convert';

import '../core/evidence/action_runner.dart';
import '../core/evidence/evidence_model.dart';
import 'tool_call_adapter.dart';

enum AgentExecutionMode {
  singleShot,
  agentLoop,
}

enum AgentPreset {
  autoAgent,
  builder,
  researchBuilder,
  repair,
  reviewer,
}

enum AgentLoopEventType {
  started,
  modelRequest,
  toolCall,
  observation,
  blocked,
  completed,
  failed,
}

class AgentLoopEvent {
  AgentLoopEvent({
    required this.type,
    required this.message,
    DateTime? createdAt,
    this.round,
    this.toolName,
    this.roleName,
    this.evidenceId,
    this.success,
  }) : createdAt = createdAt ?? DateTime.now();

  final AgentLoopEventType type;
  final String message;
  final DateTime createdAt;
  final int? round;
  final String? toolName;
  final String? roleName;
  final String? evidenceId;
  final bool? success;
}

class AgentLoopResult {
  const AgentLoopResult({
    required this.answer,
    required this.usedNativeToolCalls,
    required this.rounds,
    required this.toolCallCount,
    this.generatedPath,
  });

  final String answer;
  final bool usedNativeToolCalls;
  final int rounds;
  final int toolCallCount;
  final String? generatedPath;
}

typedef AgentLoopProviderCall = Future<ProviderToolCallResponse> Function(
  List<Map<String, dynamic>> messages, {
  required int round,
});

extension AgentExecutionModeCopy on AgentExecutionMode {
  String get label => switch (this) {
        AgentExecutionMode.singleShot => 'Single-shot',
        AgentExecutionMode.agentLoop => 'Agent Loop',
      };
}

extension AgentPresetConfig on AgentPreset {
  String get label => switch (this) {
        AgentPreset.autoAgent => 'Auto',
        AgentPreset.builder => 'Builder',
        AgentPreset.researchBuilder => 'Research',
        AgentPreset.repair => 'Repair',
        AgentPreset.reviewer => 'Reviewer',
      };

  String get shortDescription => switch (this) {
        AgentPreset.autoAgent => 'model chooses tools',
        AgentPreset.builder => 'write, verify, preview',
        AgentPreset.researchBuilder => 'search, build, snapshot',
        AgentPreset.repair => 'read, fix, preview',
        AgentPreset.reviewer => 'read-only review',
      };

  List<String> get allowedToolNames => switch (this) {
        AgentPreset.autoAgent => const [
            'list_files',
            'find_files',
            'grep_files',
            'agent_open',
            'agent_eval',
            'agent_close',
            'web_search',
            'fetch_url',
            'write_file',
            'read_file',
            'move_file',
            'apply_patch',
            'preview_html',
            'preview_snapshot',
            'report_result',
          ],
        AgentPreset.builder => const [
            'list_files',
            'find_files',
            'grep_files',
            'write_file',
            'read_file',
            'move_file',
            'apply_patch',
            'preview_html',
            'report_result',
          ],
        AgentPreset.researchBuilder => const [
            'list_files',
            'find_files',
            'grep_files',
            'agent_open',
            'agent_eval',
            'agent_close',
            'web_search',
            'fetch_url',
            'write_file',
            'read_file',
            'move_file',
            'apply_patch',
            'preview_html',
            'preview_snapshot',
            'report_result',
          ],
        AgentPreset.repair => const [
            'list_files',
            'find_files',
            'grep_files',
            'read_file',
            'apply_patch',
            'preview_html',
            'preview_snapshot',
            'report_result',
          ],
        AgentPreset.reviewer => const [
            'list_files',
            'find_files',
            'grep_files',
            'agent_open',
            'agent_eval',
            'agent_close',
            'read_file',
            'preview_html',
            'preview_snapshot',
            'report_result',
          ],
      };

  String get systemInstruction => switch (this) {
        AgentPreset.autoAgent =>
          'Agent preset Auto: choose the smallest safe next tool based on the user request and MobileCode observations. Role flow is Planner -> Builder -> Reviewer -> Repair inside one execution lane. You may open read-only Sub-Agent Lite explorer/reviewer sessions with agent_open/agent_eval/agent_close when a task needs isolated inspection. Do not follow a fixed sequence; call only the tools that are useful, and stop with report_result when the task is done or blocked.',
        AgentPreset.builder =>
          'Agent preset Builder: inspect with find_files/grep_files/read_file when useful, create or update local artifacts with write_file/apply_patch, preview them, then report concise evidence.',
        AgentPreset.researchBuilder =>
          'Agent preset Research Builder: use public reference tools when they are useful, inspect local files, optionally open read-only explorer/reviewer Sub-Agent Lite sessions, build or patch one local artifact, preview it, capture preview evidence when needed, then report refIds and evidenceIds.',
        AgentPreset.repair =>
          'Agent preset Repair: find, grep, and read the existing artifact or evidence, apply a focused patch to the relevant local file, preview again, then report what changed.',
        AgentPreset.reviewer =>
          'Agent preset Reviewer: inspect local files, preview evidence, and optionally open read-only explorer/reviewer Sub-Agent Lite sessions. Do not write files, publish, run shell, or mutate projects.',
      };

  bool get supportsWrite => allowedToolNames.contains('write_file') || allowedToolNames.contains('apply_patch');
}

class AgentLoopController {
  AgentLoopController({
    required this.adapter,
    required this.actionRunner,
    required this.preset,
    List<String>? allowedToolNames,
    this.maxRounds = 6,
  }) : _allowedToolNames = allowedToolNames;

  final OpenAiCompatibleToolCallAdapter adapter;
  final ActionRunner actionRunner;
  final AgentPreset preset;
  final List<String>? _allowedToolNames;
  final int maxRounds;

  List<String> get allowedToolNames {
    final base = _allowedToolNames ?? preset.allowedToolNames;
    if (actionRunner.webToolInvoker != null) return List<String>.unmodifiable(base);
    return List<String>.unmodifiable(
      base.where((name) => name != 'web_search' && name != 'fetch_url'),
    );
  }

  Future<AgentLoopResult> run({
    required List<Map<String, dynamic>> initialMessages,
    required AgentLoopProviderCall requestModel,
    void Function(AgentLoopEvent event)? onEvent,
    bool Function()? isCancelled,
  }) async {
    final messages = initialMessages.map((message) => Map<String, dynamic>.from(message)).toList();
    final observations = <String>[];
    String? generatedPath;
    var usedNativeToolCalls = false;
    var toolCallCount = 0;
    var writeNeedsVerification = false;
    String? lastBlockedSignature;
    final subAgentLite = _SubAgentLiteManager(actionRunner: actionRunner);

    onEvent?.call(AgentLoopEvent(
      type: AgentLoopEventType.started,
      message: '${preset.label} started with role flow Planner -> Builder -> Reviewer -> Repair and tools ${allowedToolNames.join(', ')}.',
      roleName: 'Planner',
    ));

    for (var round = 1; round <= maxRounds; round++) {
      _throwIfCancelled(isCancelled);
      onEvent?.call(AgentLoopEvent(
        type: AgentLoopEventType.modelRequest,
        message: 'Round $round: asking provider for structured tool calls.',
        round: round,
        roleName: _roleForModelRequest(round),
      ));

      final parsed = await requestModel(List<Map<String, dynamic>>.unmodifiable(messages), round: round);
      _throwIfCancelled(isCancelled);

      if (!parsed.hasToolCalls) {
        final answer = parsed.content.trim();
        onEvent?.call(AgentLoopEvent(
          type: AgentLoopEventType.completed,
          message: answer.isEmpty ? 'Agent loop completed from observations.' : 'Provider returned final answer.',
          round: round,
          roleName: 'Reviewer',
          success: true,
        ));
        return AgentLoopResult(
          answer: answer.isNotEmpty ? answer : 'Agent loop completed.\n\n${observations.join('\n')}',
          usedNativeToolCalls: usedNativeToolCalls,
          rounds: round,
          toolCallCount: toolCallCount,
          generatedPath: generatedPath,
        );
      }

      usedNativeToolCalls = true;
      toolCallCount += parsed.toolCalls.length;
      messages.add(adapter.assistantToolCallMessage(parsed));

      for (final call in parsed.toolCalls) {
        _throwIfCancelled(isCancelled);
        final roleName = _roleForTool(call.name);
        onEvent?.call(AgentLoopEvent(
          type: AgentLoopEventType.toolCall,
          message: 'Running ${call.name}.',
          round: round,
          toolName: call.name,
          roleName: roleName,
        ));

        if (call.isReportResult) {
          messages.add(adapter.buildReportResultToolMessage(call));
          final report = adapter.reportResultText(call);
          observations.add('report_result: accepted');
          onEvent?.call(AgentLoopEvent(
            type: AgentLoopEventType.completed,
            message: report.isEmpty ? 'Final report accepted.' : report,
            round: round,
            toolName: call.name,
            roleName: 'Reviewer',
            success: true,
          ));
          return AgentLoopResult(
            answer: report.isEmpty ? 'Agent loop completed.\n\n${observations.join('\n')}' : report,
            usedNativeToolCalls: true,
            rounds: round,
            toolCallCount: toolCallCount,
            generatedPath: generatedPath,
          );
        }

        final result = await _dispatchToolCall(
          call,
          round: round,
          subAgentLite: subAgentLite,
          writeNeedsVerification: writeNeedsVerification,
          onEvent: onEvent,
        );
        final evidence = result.evidence;
        final isBlocked = evidence.failureKind == ActionFailureKind.commandBlocked;
        final blockedSignature = '${call.name}|${evidence.failureKind}';
        final repeatedFailure = isBlocked && blockedSignature == lastBlockedSignature;
        lastBlockedSignature = isBlocked ? blockedSignature : null;
        final blockedObservation = isBlocked
            ? _blockedActionMessage(
                call: call,
                evidence: evidence,
                repeatedFailure: repeatedFailure,
              )
            : null;
        messages.add(adapter.buildToolResultMessage(
          call,
          result,
          observationHint: blockedObservation,
        ));
        final status = _statusForResult(result);
        observations.add('${call.name}: $status · evidence ${evidence.evidenceId}');
        if (result.path != null && result.path!.trim().isNotEmpty && call.name != 'preview_snapshot') {
          generatedPath = result.path;
        }
        if (_isMutationTool(call.name) && result.success) {
          writeNeedsVerification = true;
        } else if (call.name == 'read_file' ||
            call.name == 'grep_files' ||
            call.name == 'find_files' ||
            call.name == 'preview_html' ||
            call.name == 'preview_snapshot') {
          writeNeedsVerification = false;
        }

        onEvent?.call(AgentLoopEvent(
          type: _eventTypeForResult(result),
          message: blockedObservation ?? '${call.name}: $status · ${_compact(evidence.logs.join(' '), 180)}',
          round: round,
          toolName: call.name,
          roleName: result.success ? _observationRoleForTool(call.name) : 'Repair',
          evidenceId: evidence.evidenceId,
          success: result.success,
        ));
      }
    }

    onEvent?.call(AgentLoopEvent(
      type: AgentLoopEventType.completed,
      message: 'Stopped at the $maxRounds-round safety limit.',
      roleName: 'Reviewer',
      success: true,
    ));
    return AgentLoopResult(
      answer: generatedPath == null
          ? 'Agent loop stopped after the $maxRounds-round safety limit.\n\n${observations.join('\n')}'
          : 'Agent loop reached the $maxRounds-round safety limit after saving an artifact.\n\nArtifact: $generatedPath\n\n${observations.join('\n')}',
      usedNativeToolCalls: usedNativeToolCalls,
      rounds: maxRounds,
      toolCallCount: toolCallCount,
      generatedPath: generatedPath,
    );
  }

  Future<ActionRunnerResult> _executeCall(ProviderToolCall call) async {
    final schema = adapter.toActionSchema(call);
    if (schema == null) {
      return _blockedProviderToolResult(
        call,
        'Unsupported provider-native tool: ${call.name}.',
        ['Use only safe MobileCode tool calls exposed by the adapter.'],
      );
    }
    return actionRunner.run(schema);
  }

  Future<ActionRunnerResult> _dispatchToolCall(
    ProviderToolCall call, {
    required int round,
    required _SubAgentLiteManager subAgentLite,
    required bool writeNeedsVerification,
    void Function(AgentLoopEvent event)? onEvent,
  }) async {
    final currentAllowedToolNames = allowedToolNames;
    if (!currentAllowedToolNames.contains(call.name)) {
      return _blockedProviderToolResult(
        call,
        'Tool ${call.name} is not allowed for ${preset.label}.',
        ['Switch agent preset or use an allowed tool: ${currentAllowedToolNames.join(', ')}.'],
      );
    }

    if (_isSubAgentTool(call.name)) {
      return subAgentLite.execute(
        call,
        round: round,
        onEvent: onEvent,
      );
    }

    if (_isMutationTool(call.name) && writeNeedsVerification) {
      return _blockedProviderToolResult(
        call,
        'A workspace file was already changed successfully. Use read_file, grep_files, preview_html, preview_snapshot, or report_result before another mutation.',
        const ['Read, grep, or preview the changed artifact before another mutating tool call.'],
      );
    }

    return _executeCall(call);
  }

  ActionRunnerResult _blockedProviderToolResult(
    ProviderToolCall call,
    String message,
    List<String> recoveryActions,
  ) {
    final evidence = ActionEvidence.failed(
      evidenceId: call.id,
      actionName: MobileCodeAction.traceCallProvider,
      paramsSummary: 'blocked provider tool ${call.name}',
      startedAt: DateTime.now(),
      failureKind: ActionFailureKind.commandBlocked,
      recoveryActions: recoveryActions,
      logs: [message],
    );
    actionRunner.evidenceStore.add(evidence);
    return ActionRunnerResult(evidence: evidence);
  }

  String _blockedActionMessage({
    required ProviderToolCall call,
    required ActionEvidence evidence,
    required bool repeatedFailure,
  }) {
    final whatFailed = evidence.logs.isNotEmpty ? evidence.logs.join(' ') : 'tool call blocked';
    final baseRecovery = evidence.recoveryActions.isNotEmpty
        ? evidence.recoveryActions.join(' ')
        : 'Pick a different safe recovery action and retry.';
    final toolSpecificRecovery = _toolSpecificRecovery(call.name);
    final recovery = toolSpecificRecovery.isEmpty ? baseRecovery : '$baseRecovery $toolSpecificRecovery';
    final safeNextAction = repeatedFailure
        ? _escalateRecovery(call.name, recovery)
        : recovery;
    return 'failureKind=${evidence.failureKind}; toolName=${call.name}; what failed: ${_compact(whatFailed, 200)}; safeNextAction: $safeNextAction';
  }

  String _escalateRecovery(String toolName, String fallback) {
    final previousRecovery = fallback.trim().isEmpty ? '' : ' Previous recovery: ${_compact(fallback, 160)}';
    if (toolName == 'apply_patch') {
      return 'Switch strategy: read_file target first, then send a valid @@-based unified diff, or use complete write_file for a small HTML artifact.$previousRecovery';
    }
    if (toolName == 'write_file') {
      return 'Switch strategy: do not resend write with the same blocked arguments; provide a confirmed safe path or use read/preview flow.$previousRecovery';
    }
    return 'Switch strategy: avoid repeating the same blocked call and choose a different safe tool flow.$previousRecovery';
  }

  String _toolSpecificRecovery(String toolName) {
    if (toolName == 'apply_patch') {
      return 'Valid apply_patch requires unified diff headers (--- a/path, +++ b/path) and @@ -oldStart,oldCount +newStart,newCount @@ hunks; if context is uncertain, read_file first, then retry a smaller patch or use complete write_file for a small artifact.';
    }
    if (toolName == 'write_file') {
      return 'write_file requires path, content, and overwrite; for the default generated web artifact, use path=index.html with complete file content.';
    }
    return '';
  }

  void _throwIfCancelled(bool Function()? isCancelled) {
    if (isCancelled?.call() == true) {
      throw Exception('Agent run stopped by user.');
    }
  }
}

bool _isMutationTool(String toolName) {
  return toolName == 'write_file' || toolName == 'apply_patch' || toolName == 'move_file';
}

bool _isSubAgentTool(String toolName) {
  return toolName == 'agent_open' || toolName == 'agent_eval' || toolName == 'agent_close';
}

class _SubAgentLiteManager {
  _SubAgentLiteManager({required this.actionRunner});

  final ActionRunner actionRunner;
  final Map<String, _SubAgentLiteSession> _sessions = {};
  var _nextId = 1;

  Future<ActionRunnerResult> execute(
    ProviderToolCall call, {
    required int round,
    void Function(AgentLoopEvent event)? onEvent,
  }) async {
    switch (call.name) {
      case 'agent_open':
        return _open(call, round: round, onEvent: onEvent);
      case 'agent_eval':
        return _eval(call, round: round, onEvent: onEvent);
      case 'agent_close':
        return _close(call, round: round, onEvent: onEvent);
      default:
        return _failed(call, 'Unsupported Sub-Agent Lite tool ${call.name}.', const ['Use agent_open, agent_eval, or agent_close.']);
    }
  }

  Future<ActionRunnerResult> _open(
    ProviderToolCall call, {
    required int round,
    void Function(AgentLoopEvent event)? onEvent,
  }) async {
    final role = _stringArg(call.arguments, 'role').toLowerCase().trim();
    if (role != 'explorer' && role != 'reviewer') {
      return _failed(
        call,
        'Sub-Agent Lite only supports read-only explorer or reviewer roles. Requested role: ${role.isEmpty ? "(empty)" : role}.',
        const ['Open role=explorer for code search or role=reviewer for read-only validation. Shell, implementer, writer, and verifier roles are blocked in this mobile-safe phase.'],
      );
    }

    final task = _stringArg(call.arguments, 'task').trim();
    if (task.isEmpty) {
      return _failed(call, 'agent_open requires a non-empty task.', const ['Provide a compact read-only task for the explorer or reviewer session.']);
    }
    final path = _stringArg(call.arguments, 'path').trim().isEmpty ? '.' : _stringArg(call.arguments, 'path').trim();
    final focus = _stringArg(call.arguments, 'focus').trim();
    final session = _SubAgentLiteSession(
      id: 'sub_${DateTime.now().millisecondsSinceEpoch}_${_nextId++}',
      role: role,
      task: task,
      path: path,
      focus: focus,
    );
    _sessions[session.id] = session;
    session.add('Started', '$role opened for read-only task: ${_compact(task, 140)}');
    _emit(onEvent, round, call.name, role, 'Mailbox Started: ${session.id} ${session.mailbox.last.message}');

    final listResult = await actionRunner.run(ActionSchema(
      actionName: MobileCodeAction.listFiles,
      requestId: '${call.id}_list',
      paramsSummary: 'sub-agent-lite $role list_files',
      params: {
        'path': path,
        'recursive': false,
        'maxEntries': 40,
      },
    ));
    session.evidenceIds.add(listResult.evidence.evidenceId);
    session.add(
      listResult.success ? 'ToolCallCompleted' : 'ToolCallFailed',
      'list_files on $path: ${listResult.success ? "ok" : "failed"} · evidence ${listResult.evidence.evidenceId}',
    );
    _emit(onEvent, round, call.name, role, 'Mailbox ${session.mailbox.last.type}: ${session.mailbox.last.message}');

    if (focus.isNotEmpty) {
      final grepResult = await actionRunner.run(ActionSchema(
        actionName: MobileCodeAction.grepFiles,
        requestId: '${call.id}_grep',
        paramsSummary: 'sub-agent-lite $role grep_files',
        params: {
          'query': focus,
          'path': path,
          'includeGlob': '*',
          'maxResults': 12,
          'maxBytes': 96 * 1024,
        },
      ));
      session.evidenceIds.add(grepResult.evidence.evidenceId);
      session.add(
        grepResult.success ? 'ToolCallCompleted' : 'ToolCallFailed',
        'grep_files focus "$focus": ${grepResult.success ? "ok" : "failed"} · evidence ${grepResult.evidence.evidenceId}',
      );
      _emit(onEvent, round, call.name, role, 'Mailbox ${session.mailbox.last.type}: ${session.mailbox.last.message}');
    }

    session.status = 'completed';
    session.add('Completed', '$role returned SUMMARY / CHANGES / EVIDENCE / RISKS / BLOCKERS.');
    _emit(onEvent, round, call.name, role, 'Mailbox Completed: ${session.id} ready for agent_eval.');

    return _succeeded(call, 'agent_open ${session.id}', _sessionPayload(session));
  }

  ActionRunnerResult _eval(
    ProviderToolCall call, {
    required int round,
    void Function(AgentLoopEvent event)? onEvent,
  }) {
    final agentId = _stringArgAny(call.arguments, const ['agent_id', 'agentId', 'id']).trim();
    final session = _sessions[agentId];
    if (session == null) {
      return _failed(call, 'Unknown Sub-Agent Lite session: ${agentId.isEmpty ? "(empty)" : agentId}.', const ['Call agent_open first, then pass the returned agent_id to agent_eval.']);
    }
    session.add('Progress', 'agent_eval read mailbox with ${session.mailbox.length} entries.');
    _emit(onEvent, round, call.name, session.role, 'Mailbox Eval: ${session.id} ${session.status}.');
    return _succeeded(call, 'agent_eval ${session.id}', _sessionPayload(session));
  }

  ActionRunnerResult _close(
    ProviderToolCall call, {
    required int round,
    void Function(AgentLoopEvent event)? onEvent,
  }) {
    final agentId = _stringArgAny(call.arguments, const ['agent_id', 'agentId', 'id']).trim();
    final session = _sessions[agentId];
    if (session == null) {
      return _failed(call, 'Unknown Sub-Agent Lite session: ${agentId.isEmpty ? "(empty)" : agentId}.', const ['Call agent_close only with a currently open Sub-Agent Lite session id.']);
    }
    final reason = _stringArg(call.arguments, 'reason').trim();
    session.status = 'closed';
    session.add('Closed', reason.isEmpty ? 'Closed by parent AgentLoop.' : reason);
    _emit(onEvent, round, call.name, session.role, 'Mailbox Closed: ${session.id}.');
    return _succeeded(call, 'agent_close ${session.id}', _sessionPayload(session));
  }

  Map<String, dynamic> _sessionPayload(_SubAgentLiteSession session) {
    return {
      'agent_id': session.id,
      'role': session.role,
      'status': session.status,
      'task': session.task,
      'path': session.path,
      if (session.focus.isNotEmpty) 'focus': session.focus,
      'allowed_tools': session.allowedTools,
      'output_contract': const ['SUMMARY', 'CHANGES', 'EVIDENCE', 'RISKS', 'BLOCKERS'],
      'mailbox': session.mailbox.map((entry) => entry.toJson()).toList(),
      'evidence_ids': session.evidenceIds,
      'summary': '${session.role} inspected ${session.path} with read-only MobileCode tools.',
      'changes': const [],
      'risks': const ['Sub-Agent Lite is read-only and not a parallel background worker yet.'],
      'blockers': const [],
    };
  }

  ActionRunnerResult _succeeded(ProviderToolCall call, String paramsSummary, Map<String, dynamic> payload) {
    final startedAt = DateTime.now();
    final evidence = ActionEvidence.succeeded(
      actionName: MobileCodeAction.traceCallProvider,
      startedAt: startedAt,
      evidenceId: call.id,
      paramsSummary: paramsSummary,
      logs: ['Sub-Agent Lite ${call.name} succeeded.'],
    );
    actionRunner.evidenceStore.add(evidence);
    return ActionRunnerResult(evidence: evidence, text: jsonEncode(payload));
  }

  ActionRunnerResult _failed(ProviderToolCall call, String message, List<String> recoveryActions) {
    final evidence = ActionEvidence.failed(
      actionName: MobileCodeAction.traceCallProvider,
      startedAt: DateTime.now(),
      evidenceId: call.id,
      paramsSummary: 'blocked sub-agent-lite ${call.name}',
      failureKind: ActionFailureKind.commandBlocked,
      recoveryActions: recoveryActions,
      logs: [message],
    );
    actionRunner.evidenceStore.add(evidence);
    return ActionRunnerResult(evidence: evidence);
  }

  void _emit(
    void Function(AgentLoopEvent event)? onEvent,
    int round,
    String toolName,
    String role,
    String message,
  ) {
    onEvent?.call(AgentLoopEvent(
      type: AgentLoopEventType.observation,
      message: message,
      round: round,
      toolName: toolName,
      roleName: '${_titleCase(role)} sub-agent',
      success: true,
    ));
  }
}

class _SubAgentLiteSession {
  _SubAgentLiteSession({
    required this.id,
    required this.role,
    required this.task,
    required this.path,
    required this.focus,
  });

  final String id;
  final String role;
  final String task;
  final String path;
  final String focus;
  final List<_SubAgentLiteMailboxEntry> mailbox = [];
  final List<String> evidenceIds = [];
  String status = 'running';

  List<String> get allowedTools => role == 'explorer'
      ? const ['list_files', 'find_files', 'grep_files', 'read_file']
      : const ['list_files', 'find_files', 'grep_files', 'read_file', 'preview_snapshot'];

  void add(String type, String message) {
    mailbox.add(_SubAgentLiteMailboxEntry(type: type, message: message));
  }
}

class _SubAgentLiteMailboxEntry {
  _SubAgentLiteMailboxEntry({
    required this.type,
    required this.message,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String type;
  final String message;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'type': type,
        'message': message,
        'createdAt': createdAt.toIso8601String(),
      };
}

AgentLoopEventType _eventTypeForResult(ActionRunnerResult result) {
  if (result.success) return AgentLoopEventType.observation;
  if (result.evidence.failureKind == ActionFailureKind.commandBlocked) {
    return AgentLoopEventType.blocked;
  }
  return AgentLoopEventType.failed;
}

String _statusForResult(ActionRunnerResult result) {
  if (result.success) return 'ok';
  if (result.evidence.failureKind == ActionFailureKind.commandBlocked) return 'blocked';
  return 'failed';
}

String _roleForModelRequest(int round) {
  return round == 1 ? 'Planner' : 'Planner';
}

String _roleForTool(String toolName) {
  if (toolName == 'find_files' || toolName == 'grep_files' || toolName == 'list_files' || toolName == 'read_file') {
    return 'Planner';
  }
  if (toolName == 'write_file' || toolName == 'move_file' || toolName == 'apply_patch') {
    return 'Builder';
  }
  if (toolName == 'preview_html' || toolName == 'preview_snapshot' || toolName == 'report_result') {
    return 'Reviewer';
  }
  if (toolName == 'web_search' || toolName == 'fetch_url') {
    return 'Research';
  }
  return 'Repair';
}

String _observationRoleForTool(String toolName) {
  if (toolName == 'write_file' || toolName == 'move_file' || toolName == 'apply_patch') {
    return 'Reviewer';
  }
  if (toolName == 'preview_html' || toolName == 'preview_snapshot' || toolName == 'report_result') {
    return 'Reviewer';
  }
  if (toolName == 'web_search' || toolName == 'fetch_url') {
    return 'Research';
  }
  return 'Planner';
}

String _stringArg(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value == null) return '';
  return value.toString();
}

String _stringArgAny(Map<String, dynamic> args, List<String> keys) {
  for (final key in keys) {
    final value = _stringArg(args, key).trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}

String _titleCase(String value) {
  if (value.isEmpty) return value;
  return '${value[0].toUpperCase()}${value.substring(1)}';
}

String _compact(String value, int limit) {
  final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (trimmed.length <= limit) return trimmed;
  return '${trimmed.substring(0, limit)}...';
}
