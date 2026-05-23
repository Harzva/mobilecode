import 'dart:async';
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
            'copy_file',
            'mkdir',
            'delete_file',
            'move_file',
            'save_snapshot',
            'virtual_diff',
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
            'copy_file',
            'mkdir',
            'delete_file',
            'move_file',
            'save_snapshot',
            'virtual_diff',
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
            'copy_file',
            'mkdir',
            'move_file',
            'save_snapshot',
            'virtual_diff',
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
            'write_file',
            'copy_file',
            'mkdir',
            'delete_file',
            'move_file',
            'save_snapshot',
            'virtual_diff',
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
            'save_snapshot',
            'virtual_diff',
            'preview_html',
            'preview_snapshot',
            'report_result',
          ],
      };

  String get systemInstruction => switch (this) {
        AgentPreset.autoAgent =>
          'Agent preset Auto: choose the smallest safe next tool based on the user request and MobileCode observations. Role flow is Planner -> Builder -> Reviewer -> Repair inside one execution lane. You may open read-only Sub-Agent Lite explorer/reviewer sessions with agent_open/agent_eval/agent_close when a task needs isolated inspection. Do not follow a fixed sequence; call only the tools that are useful, and stop with report_result when the task is done or blocked.',
        AgentPreset.builder =>
          'Agent preset Builder: inspect with find_files/grep_files/read_file when useful, save snapshots or virtual diffs for safety, create or update local artifacts with write_file/copy_file/mkdir/delete_file/move_file/apply_patch, preview them, then report concise evidence. If apply_patch is blocked, do not repeat the same malformed patch; read the target and retry a valid unified diff or use complete write_file for a small generated artifact.',
        AgentPreset.researchBuilder =>
          'Agent preset Research Builder: use public reference tools when they are useful, inspect local files, optionally open read-only background explorer/reviewer Sub-Agent Lite sessions, build or patch one local artifact, preview it, capture preview evidence when needed, then report refIds and evidenceIds.',
        AgentPreset.repair =>
          'Agent preset Repair: find, grep, and read the existing artifact or evidence, save a snapshot when useful, apply a focused patch or complete write_file replacement for small artifacts, preview again, then report what changed. If apply_patch is blocked, switch strategy: read_file the exact target, send a valid unified diff, or use complete write_file for a small HTML artifact.',
        AgentPreset.reviewer =>
          'Agent preset Reviewer: inspect local files, save snapshots, inspect virtual diffs, preview evidence, and optionally open read-only background explorer/reviewer Sub-Agent Lite sessions. Do not write files, publish, run shell, or mutate projects.',
      };

  bool get supportsWrite =>
      allowedToolNames.contains('write_file') ||
      allowedToolNames.contains('apply_patch') ||
      allowedToolNames.contains('move_file') ||
      allowedToolNames.contains('copy_file') ||
      allowedToolNames.contains('mkdir') ||
      allowedToolNames.contains('delete_file');
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
    final blockedCounts = <String, int>{};
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
        final blockedSignature = _blockedSignature(call: call, evidence: evidence);
        final blockedCount = isBlocked ? (blockedCounts[blockedSignature] = (blockedCounts[blockedSignature] ?? 0) + 1) : 0;
        final repeatedFailure = blockedCount > 1;
        final blockedObservation = isBlocked
            ? _blockedActionMessage(
                call: call,
                evidence: evidence,
                repeatedFailure: repeatedFailure,
                blockedCount: blockedCount,
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
            call.name == 'list_files' ||
            call.name == 'preview_html' ||
            call.name == 'preview_snapshot' ||
            call.name == 'save_snapshot' ||
            call.name == 'virtual_diff') {
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
    required int blockedCount,
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
    final recoveryContract = _recoveryContract(
      call.name,
      repeatedFailure: repeatedFailure,
      blockedCount: blockedCount,
    );
    return 'failureKind=${evidence.failureKind}; toolName=${call.name}; blockedCount=$blockedCount; what failed: ${_compact(whatFailed, 200)}; safeNextAction: $safeNextAction; recoveryContract: $recoveryContract';
  }

  String _blockedSignature({
    required ProviderToolCall call,
    required ActionEvidence evidence,
  }) {
    final whatFailed = evidence.logs.isNotEmpty ? evidence.logs.join(' ') : 'tool call blocked';
    return '${call.name}|${evidence.failureKind}|${_compact(whatFailed, 140)}';
  }

  String _escalateRecovery(String toolName, String fallback) {
    final previousRecovery = fallback.trim().isEmpty ? '' : ' Previous recovery: ${_compact(fallback, 160)}';
    if (toolName == 'apply_patch') {
      return 'Switch strategy: do not resend the same apply_patch. Call read_file for the exact target, then send a valid @@-based unified diff, or use complete write_file for a small HTML artifact.$previousRecovery';
    }
    if (toolName == 'write_file') {
      return 'Switch strategy: do not resend write_file with the same blocked arguments. Provide path and content, or inspect with find_files/read_file before trying again.$previousRecovery';
    }
    return 'Switch strategy: avoid repeating the same blocked call and choose a different safe tool flow.$previousRecovery';
  }

  String _toolSpecificRecovery(String toolName) {
    if (toolName == 'apply_patch') {
      return 'Valid apply_patch requires unified diff headers (--- a/path, +++ b/path) and @@ -oldStart,oldCount +newStart,newCount @@ hunks; if context is uncertain, call read_file first, then retry a smaller patch or use complete write_file for a small artifact.';
    }
    if (toolName == 'write_file') {
      return 'write_file requires path, content, and overwrite. For a generated web preview artifact, use path=index.html only when that is the requested artifact target, with complete file content.';
    }
    return '';
  }

  String _recoveryContract(
    String toolName, {
    required bool repeatedFailure,
    required int blockedCount,
  }) {
    if (toolName == 'apply_patch') {
      final prefix = repeatedFailure
          ? 'Do not resend the same apply_patch. This exact failure has happened $blockedCount times.'
          : 'Do not guess patch syntax or target context.';
      return '$prefix Next tool options: find_files if the target path is unknown; read_file with the exact target path before patching; apply_patch only with a minimal unified diff containing --- a/path, +++ b/path, and @@ -oldStart,oldCount +newStart,newCount @@; or write_file(path, complete content) for a small generated HTML artifact. Never send @@ ... @@ or prose as a patch.';
    }
    if (toolName == 'write_file') {
      final prefix = repeatedFailure
          ? 'Do not repeat the same missing or invalid write_file arguments.'
          : 'write_file is allowed only with explicit structured arguments.';
      return '$prefix Required args: path, content, overwrite. If the user asked for a generated preview artifact and no other target was specified, path=index.html is acceptable; otherwise call find_files/read_file to confirm the target first.';
    }
    if (toolName == 'delete_file') {
      return 'Only delete a confirmed workspace file. If unsure, call find_files or list_files first, then report_result instead of guessing.';
    }
    return repeatedFailure
        ? 'Do not repeat the same blocked call. Inspect with a read-only tool or report_result with the blocker.'
        : 'Choose the smallest safe read-only or typed action that resolves the blocker.';
  }

  void _throwIfCancelled(bool Function()? isCancelled) {
    if (isCancelled?.call() == true) {
      throw Exception('Agent run stopped by user.');
    }
  }
}

bool _isMutationTool(String toolName) {
  return toolName == 'write_file' ||
      toolName == 'apply_patch' ||
      toolName == 'move_file' ||
      toolName == 'copy_file' ||
      toolName == 'mkdir' ||
      toolName == 'delete_file';
}

bool _isSubAgentTool(String toolName) {
  return toolName == 'agent_open' || toolName == 'agent_eval' || toolName == 'agent_close';
}

class _SubAgentLiteManager {
  _SubAgentLiteManager({required this.actionRunner});

  static const _maxConcurrent = 2;

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
    _reapExpiredSessions();
    final runningCount = _sessions.values.where((session) => session.isRunning).length;
    if (runningCount >= _maxConcurrent) {
      return _failed(
        call,
        'Sub-Agent Lite v2 allows at most $_maxConcurrent concurrent read-only workers.',
        const ['Call agent_eval/agent_close on an existing worker, or wait for one to complete before opening another.'],
      );
    }
    final path = _stringArg(call.arguments, 'path').trim().isEmpty ? '.' : _stringArg(call.arguments, 'path').trim();
    final focus = _stringArg(call.arguments, 'focus').trim();
    final timeoutMs = _boundedIntArgAny(
      call.arguments,
      const ['timeout_ms', 'timeoutMs'],
      defaultValue: 10000,
      min: 1000,
      max: 30000,
    );
    final tokenBudget = _boundedIntArgAny(
      call.arguments,
      const ['token_budget', 'tokenBudget'],
      defaultValue: 1200,
      min: 200,
      max: 4000,
    );
    final session = _SubAgentLiteSession(
      id: 'sub_${DateTime.now().millisecondsSinceEpoch}_${_nextId++}',
      role: role,
      task: task,
      path: path,
      focus: focus,
      timeoutMs: timeoutMs,
      tokenBudget: tokenBudget,
    );
    _sessions[session.id] = session;
    session.add('Started', '$role background worker opened for read-only task: ${_compact(task, 140)}');
    _emit(onEvent, round, call.name, role, 'Mailbox Started: ${session.id} ${session.mailbox.last.message}');
    unawaited(_runReadOnlyWorker(
      session: session,
      parentCall: call,
      round: round,
      onEvent: onEvent,
    ));

    return _succeeded(call, 'agent_open ${session.id}', _sessionPayload(session));
  }

  Future<void> _runReadOnlyWorker({
    required _SubAgentLiteSession session,
    required ProviderToolCall parentCall,
    required int round,
    void Function(AgentLoopEvent event)? onEvent,
  }) async {
    await Future<void>.delayed(Duration.zero);
    try {
      if (_shouldStop(session, round: round, toolName: parentCall.name, onEvent: onEvent)) return;
      await _runReadOnlyAction(
        session,
        parentCall,
        round: round,
        onEvent: onEvent,
        actionName: MobileCodeAction.listFiles,
        requestId: '${parentCall.id}_list',
        toolName: 'list_files',
        params: {
          'path': session.path,
          'recursive': false,
          'maxEntries': 40,
        },
      );
      if (_shouldStop(session, round: round, toolName: parentCall.name, onEvent: onEvent)) return;

      if (session.focus.isNotEmpty) {
        await _runReadOnlyAction(
          session,
          parentCall,
          round: round,
          onEvent: onEvent,
          actionName: MobileCodeAction.grepFiles,
          requestId: '${parentCall.id}_grep',
          toolName: 'grep_files',
          params: {
            'query': session.focus,
            'path': session.path,
            'includeGlob': '*',
            'maxResults': 12,
            'maxBytes': 96 * 1024,
          },
        );
        if (_shouldStop(session, round: round, toolName: parentCall.name, onEvent: onEvent)) return;
      }

      if (!session.isRunning) return;
      session.status = 'completed';
      session.finishedAt = DateTime.now();
      session.add('Completed', '${session.role} returned SUMMARY / CHANGES / EVIDENCE / RISKS / BLOCKERS.');
      _emit(onEvent, round, parentCall.name, session.role, 'Mailbox Completed: ${session.id} ready for agent_eval.');
    } catch (error) {
      if (!session.isRunning) return;
      session.status = 'failed';
      session.finishedAt = DateTime.now();
      session.add('Failed', 'Sub-Agent Lite worker failed: ${_compact(error.toString(), 180)}');
      _emit(onEvent, round, parentCall.name, session.role, 'Mailbox Failed: ${session.id} ${session.mailbox.last.message}', success: false);
    }
  }

  Future<void> _runReadOnlyAction(
    _SubAgentLiteSession session,
    ProviderToolCall parentCall, {
    required int round,
    required void Function(AgentLoopEvent event)? onEvent,
    required MobileCodeAction actionName,
    required String requestId,
    required String toolName,
    required Map<String, dynamic> params,
  }) async {
    if (_shouldStop(session, round: round, toolName: parentCall.name, onEvent: onEvent)) return;
    session.add('ToolCallStarted', '$toolName started inside ${session.id}.');
    _emit(onEvent, round, parentCall.name, session.role, 'Mailbox ToolCallStarted: ${session.mailbox.last.message}');
    final result = await actionRunner.run(ActionSchema(
      actionName: actionName,
      requestId: requestId,
      paramsSummary: 'sub-agent-lite ${session.role} $toolName',
      params: params,
    ));
    session.evidenceIds.add(result.evidence.evidenceId);
    final preview = _compact(
      [result.text, result.evidence.logs.join(' ')].whereType<String>().join(' '),
      240,
    );
    session.add(
      result.success ? 'ToolCallCompleted' : 'ToolCallFailed',
      '$toolName on ${session.path}: ${result.success ? "ok" : "failed"} · evidence ${result.evidence.evidenceId}${preview.isEmpty ? "" : " · $preview"}',
    );
    _emit(onEvent, round, parentCall.name, session.role, 'Mailbox ${session.mailbox.last.type}: ${session.mailbox.last.message}', success: result.success);
    if (!result.success && session.isRunning) {
      session.status = 'failed';
      session.finishedAt = DateTime.now();
    }
  }

  ActionRunnerResult _eval(
    ProviderToolCall call, {
    required int round,
    void Function(AgentLoopEvent event)? onEvent,
  }) {
    _reapExpiredSessions();
    final agentId = _stringArgAny(call.arguments, const ['agent_id', 'agentId', 'id']).trim();
    final session = _sessions[agentId];
    if (session == null) {
      return _failed(call, 'Unknown Sub-Agent Lite session: ${agentId.isEmpty ? "(empty)" : agentId}.', const ['Call agent_open first, then pass the returned agent_id to agent_eval.']);
    }
    _shouldStop(session, round: round, toolName: call.name, onEvent: onEvent);
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
    if (session.isRunning) {
      session.cancelRequested = true;
      session.status = 'cancelled';
      session.finishedAt = DateTime.now();
      session.add('Cancelled', reason.isEmpty ? 'Cancelled by parent AgentLoop.' : reason);
      _emit(onEvent, round, call.name, session.role, 'Mailbox Cancelled: ${session.id}.');
    } else {
      session.status = 'closed';
      session.add('Closed', reason.isEmpty ? 'Closed by parent AgentLoop.' : reason);
      _emit(onEvent, round, call.name, session.role, 'Mailbox Closed: ${session.id}.');
    }
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
      'is_background': true,
      'max_concurrent': _maxConcurrent,
      'timeout_ms': session.timeoutMs,
      'token_budget': session.tokenBudget,
      'token_used': session.estimatedTokens,
      'started_at': session.startedAt.toIso8601String(),
      'deadline': session.deadline.toIso8601String(),
      if (session.finishedAt != null) 'finished_at': session.finishedAt!.toIso8601String(),
      'can_cancel': session.isRunning,
      'allowed_tools': session.allowedTools,
      'output_contract': const ['SUMMARY', 'CHANGES', 'EVIDENCE', 'RISKS', 'BLOCKERS'],
      'mailbox': session.mailbox.map((entry) => entry.toJson()).toList(),
      'evidence_ids': session.evidenceIds,
      'summary': '${session.role} ${session.status} while inspecting ${session.path} with read-only MobileCode tools.',
      'changes': const [],
      'risks': const ['Sub-Agent Lite v2 is read-only; write proposals must return to the main AgentLoop before ActionRunner mutates files.'],
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
    String message, {
    bool success = true,
  }) {
    onEvent?.call(AgentLoopEvent(
      type: success ? AgentLoopEventType.observation : AgentLoopEventType.failed,
      message: message,
      round: round,
      toolName: toolName,
      roleName: '${_titleCase(role)} sub-agent',
      success: success,
    ));
  }

  bool _shouldStop(
    _SubAgentLiteSession session, {
    required int round,
    required String toolName,
    void Function(AgentLoopEvent event)? onEvent,
  }) {
    if (!session.isRunning) return true;
    if (session.cancelRequested) {
      _stopSession(session, 'cancelled', 'Cancelled', 'Cancelled by parent AgentLoop.', round, toolName, onEvent);
      return true;
    }
    if (DateTime.now().isAfter(session.deadline)) {
      _stopSession(session, 'timed_out', 'TimedOut', 'Worker timed out after ${session.timeoutMs}ms.', round, toolName, onEvent);
      return true;
    }
    if (session.estimatedTokens >= session.tokenBudget) {
      _stopSession(session, 'token_budget_exhausted', 'TokenBudgetExceeded', 'Worker stopped at token budget ${session.tokenBudget}.', round, toolName, onEvent);
      return true;
    }
    return false;
  }

  void _stopSession(
    _SubAgentLiteSession session,
    String status,
    String mailboxType,
    String message,
    int round,
    String toolName,
    void Function(AgentLoopEvent event)? onEvent,
  ) {
    if (!session.isRunning) return;
    session.status = status;
    session.finishedAt = DateTime.now();
    session.add(mailboxType, message);
    _emit(onEvent, round, toolName, session.role, 'Mailbox $mailboxType: ${session.id} $message', success: status == 'cancelled');
  }

  void _reapExpiredSessions() {
    for (final session in _sessions.values) {
      if (session.isRunning && DateTime.now().isAfter(session.deadline)) {
        session.status = 'timed_out';
        session.finishedAt = DateTime.now();
        session.add('TimedOut', 'Worker timed out after ${session.timeoutMs}ms.');
      }
    }
  }
}

class _SubAgentLiteSession {
  _SubAgentLiteSession({
    required this.id,
    required this.role,
    required this.task,
    required this.path,
    required this.focus,
    required this.timeoutMs,
    required this.tokenBudget,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();

  final String id;
  final String role;
  final String task;
  final String path;
  final String focus;
  final int timeoutMs;
  final int tokenBudget;
  final DateTime startedAt;
  final List<_SubAgentLiteMailboxEntry> mailbox = [];
  final List<String> evidenceIds = [];
  DateTime? finishedAt;
  String status = 'running';
  var estimatedTokens = 0;
  bool cancelRequested = false;

  DateTime get deadline => startedAt.add(Duration(milliseconds: timeoutMs));
  bool get isRunning => status == 'running';

  List<String> get allowedTools => role == 'explorer'
      ? const ['list_files', 'find_files', 'grep_files', 'read_file']
      : const ['list_files', 'find_files', 'grep_files', 'read_file', 'preview_snapshot'];

  void add(String type, String message) {
    mailbox.add(_SubAgentLiteMailboxEntry(type: type, message: message));
    estimatedTokens += (message.length / 4).ceil().clamp(1, 400).toInt();
    if (mailbox.length > 80) {
      mailbox.removeRange(0, mailbox.length - 80);
    }
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
  if (toolName == 'write_file' ||
      toolName == 'copy_file' ||
      toolName == 'mkdir' ||
      toolName == 'delete_file' ||
      toolName == 'move_file' ||
      toolName == 'apply_patch') {
    return 'Builder';
  }
  if (toolName == 'save_snapshot' ||
      toolName == 'virtual_diff' ||
      toolName == 'preview_html' ||
      toolName == 'preview_snapshot' ||
      toolName == 'report_result') {
    return 'Reviewer';
  }
  if (toolName == 'web_search' || toolName == 'fetch_url') {
    return 'Research';
  }
  return 'Repair';
}

String _observationRoleForTool(String toolName) {
  if (toolName == 'write_file' ||
      toolName == 'copy_file' ||
      toolName == 'mkdir' ||
      toolName == 'delete_file' ||
      toolName == 'move_file' ||
      toolName == 'apply_patch') {
    return 'Reviewer';
  }
  if (toolName == 'save_snapshot' ||
      toolName == 'virtual_diff' ||
      toolName == 'preview_html' ||
      toolName == 'preview_snapshot' ||
      toolName == 'report_result') {
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

int _boundedIntArgAny(
  Map<String, dynamic> args,
  List<String> keys, {
  required int defaultValue,
  required int min,
  required int max,
}) {
  Object? raw;
  for (final key in keys) {
    if (args.containsKey(key)) {
      raw = args[key];
      break;
    }
  }
  final parsed = switch (raw) {
    int value => value,
    num value => value.toInt(),
    String value => int.tryParse(value.trim()) ?? defaultValue,
    _ => defaultValue,
  };
  if (parsed < min) return min;
  if (parsed > max) return max;
  return parsed;
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
