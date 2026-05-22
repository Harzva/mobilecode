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
    this.evidenceId,
    this.success,
  }) : createdAt = createdAt ?? DateTime.now();

  final AgentLoopEventType type;
  final String message;
  final DateTime createdAt;
  final int? round;
  final String? toolName;
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
            'web_search',
            'fetch_url',
            'write_file',
            'read_file',
            'move_file',
            'preview_html',
            'preview_snapshot',
            'report_result',
          ],
        AgentPreset.builder => const [
            'list_files',
            'write_file',
            'read_file',
            'move_file',
            'preview_html',
            'report_result',
          ],
        AgentPreset.researchBuilder => const [
            'list_files',
            'web_search',
            'fetch_url',
            'write_file',
            'read_file',
            'move_file',
            'preview_html',
            'preview_snapshot',
            'report_result',
          ],
        AgentPreset.repair => const [
            'list_files',
            'read_file',
            'write_file',
            'move_file',
            'preview_html',
            'preview_snapshot',
            'report_result',
          ],
        AgentPreset.reviewer => const [
            'list_files',
            'read_file',
            'preview_html',
            'preview_snapshot',
            'report_result',
          ],
      };

  String get systemInstruction => switch (this) {
        AgentPreset.autoAgent =>
          'Agent preset Auto: choose the smallest safe next tool based on the user request and MobileCode observations. Do not follow a fixed sequence; call only the tools that are useful, and stop with report_result when the task is done or blocked.',
        AgentPreset.builder =>
          'Agent preset Builder: create or update a local artifact, read it back, preview it, then report concise evidence.',
        AgentPreset.researchBuilder =>
          'Agent preset Research Builder: use public reference tools when they are useful, build one local artifact, preview it, capture preview evidence when needed, then report refIds and evidenceIds.',
        AgentPreset.repair =>
          'Agent preset Repair: read the existing artifact or evidence, modify only the relevant local file, preview again, then report what changed.',
        AgentPreset.reviewer =>
          'Agent preset Reviewer: inspect local files and preview evidence only. Do not write files, publish, run shell, or mutate projects.',
      };

  bool get supportsWrite => allowedToolNames.contains('write_file');
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

    onEvent?.call(AgentLoopEvent(
      type: AgentLoopEventType.started,
      message: '${preset.label} started with ${allowedToolNames.join(', ')}.',
    ));

    for (var round = 1; round <= maxRounds; round++) {
      _throwIfCancelled(isCancelled);
      onEvent?.call(AgentLoopEvent(
        type: AgentLoopEventType.modelRequest,
        message: 'Round $round: asking provider for structured tool calls.',
        round: round,
      ));

      final parsed = await requestModel(List<Map<String, dynamic>>.unmodifiable(messages), round: round);
      _throwIfCancelled(isCancelled);

      if (!parsed.hasToolCalls) {
        final answer = parsed.content.trim();
        onEvent?.call(AgentLoopEvent(
          type: AgentLoopEventType.completed,
          message: answer.isEmpty ? 'Agent loop completed from observations.' : 'Provider returned final answer.',
          round: round,
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
        onEvent?.call(AgentLoopEvent(
          type: AgentLoopEventType.toolCall,
          message: 'Running ${call.name}.',
          round: round,
          toolName: call.name,
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

        final result = call.name == 'write_file' && writeNeedsVerification
            ? _blockedProviderToolResult(
                call,
                'A file was already written successfully. Use read_file, preview_html, preview_snapshot, or report_result before rewriting it.',
                const ['Read or preview the written artifact before another write_file call.'],
              )
            : await _executeCall(call);
        messages.add(adapter.buildToolResultMessage(call, result));
        final evidence = result.evidence;
        final status = result.success ? 'ok' : 'failed';
        observations.add('${call.name}: $status · evidence ${evidence.evidenceId}');
        if (result.path != null && result.path!.trim().isNotEmpty && call.name != 'preview_snapshot') {
          generatedPath = result.path;
        }
        if (call.name == 'write_file' && result.success) {
          writeNeedsVerification = true;
        } else if (call.name == 'read_file' || call.name == 'preview_html' || call.name == 'preview_snapshot') {
          writeNeedsVerification = false;
        }
        onEvent?.call(AgentLoopEvent(
          type: result.success ? AgentLoopEventType.observation : AgentLoopEventType.failed,
          message: '${call.name}: $status · ${_compact(evidence.logs.join(' '), 180)}',
          round: round,
          toolName: call.name,
          evidenceId: evidence.evidenceId,
          success: result.success,
        ));
      }
    }

    onEvent?.call(AgentLoopEvent(
      type: AgentLoopEventType.completed,
      message: 'Stopped at the $maxRounds-round safety limit.',
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
    final currentAllowedToolNames = allowedToolNames;
    if (!currentAllowedToolNames.contains(call.name)) {
      return _blockedProviderToolResult(
        call,
        'Tool ${call.name} is not allowed for ${preset.label}.',
        ['Switch agent preset or use an allowed tool: ${currentAllowedToolNames.join(', ')}.'],
      );
    }

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

  void _throwIfCancelled(bool Function()? isCancelled) {
    if (isCancelled?.call() == true) {
      throw Exception('Agent run stopped by user.');
    }
  }
}

String _compact(String value, int limit) {
  final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (trimmed.length <= limit) return trimmed;
  return '${trimmed.substring(0, limit)}...';
}
