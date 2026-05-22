import '../core/evidence/action_runner.dart';
import '../core/evidence/evidence_model.dart';
import 'tool_call_adapter.dart';

enum AgentExecutionMode {
  singleShot,
  agentLoop,
}

enum AgentPreset {
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
        AgentPreset.builder => 'Builder',
        AgentPreset.researchBuilder => 'Research',
        AgentPreset.repair => 'Repair',
        AgentPreset.reviewer => 'Reviewer',
      };

  String get shortDescription => switch (this) {
        AgentPreset.builder => 'write, verify, preview',
        AgentPreset.researchBuilder => 'search, build, snapshot',
        AgentPreset.repair => 'read, fix, preview',
        AgentPreset.reviewer => 'read-only review',
      };

  List<String> get allowedToolNames => switch (this) {
        AgentPreset.builder => const [
            'write_file',
            'read_file',
            'preview_html',
            'report_result',
          ],
        AgentPreset.researchBuilder => const [
            'web_search',
            'fetch_url',
            'write_file',
            'read_file',
            'preview_html',
            'preview_snapshot',
            'report_result',
          ],
        AgentPreset.repair => const [
            'read_file',
            'write_file',
            'preview_html',
            'preview_snapshot',
            'report_result',
          ],
        AgentPreset.reviewer => const [
            'read_file',
            'preview_html',
            'preview_snapshot',
            'report_result',
          ],
      };

  String get systemInstruction => switch (this) {
        AgentPreset.builder =>
          'Agent preset Builder: create or update a local artifact, read it back, preview it, then report concise evidence.',
        AgentPreset.researchBuilder =>
          'Agent preset Research Builder: search public references first, optionally fetch public HTTPS pages, build one local artifact, preview it, capture preview evidence, then report refIds and evidenceIds.',
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
    this.maxRounds = 6,
  });

  final OpenAiCompatibleToolCallAdapter adapter;
  final ActionRunner actionRunner;
  final AgentPreset preset;
  final int maxRounds;

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

    onEvent?.call(AgentLoopEvent(
      type: AgentLoopEventType.started,
      message: '${preset.label} started with ${preset.allowedToolNames.join(', ')}.',
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

        final result = await _executeCall(call);
        messages.add(adapter.buildToolResultMessage(call, result));
        final evidence = result.evidence;
        final status = result.success ? 'ok' : 'failed';
        observations.add('${call.name}: $status · evidence ${evidence.evidenceId}');
        if (result.path != null && result.path!.trim().isNotEmpty && call.name != 'preview_snapshot') {
          generatedPath = result.path;
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
      answer: 'Agent loop stopped after the $maxRounds-round safety limit.\n\n${observations.join('\n')}',
      usedNativeToolCalls: usedNativeToolCalls,
      rounds: maxRounds,
      toolCallCount: toolCallCount,
      generatedPath: generatedPath,
    );
  }

  Future<ActionRunnerResult> _executeCall(ProviderToolCall call) async {
    if (!preset.allowedToolNames.contains(call.name)) {
      return _blockedProviderToolResult(
        call,
        'Tool ${call.name} is not allowed for ${preset.label}.',
        ['Switch agent preset or use an allowed tool: ${preset.allowedToolNames.join(', ')}.'],
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
