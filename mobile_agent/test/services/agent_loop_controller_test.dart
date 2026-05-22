import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/core/evidence/action_evidence_store.dart';
import 'package:mobile_agent/core/evidence/action_runner.dart';
import 'package:mobile_agent/core/evidence/evidence_model.dart';
import 'package:mobile_agent/services/agent_loop_controller.dart';
import 'package:mobile_agent/services/tool_call_adapter.dart';

void main() {
  late Directory workspace;
  late ActionEvidenceStore store;
  late OpenAiCompatibleToolCallAdapter adapter;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('mobilecode_agent_loop_');
    store = ActionEvidenceStore();
    adapter = OpenAiCompatibleToolCallAdapter(
      profile: ToolCallProviderProfile.detect(
        'https://api.deepseek.com',
        'deepseek-v4-pro',
      ),
    );
  });

  tearDown(() async {
    if (await workspace.exists()) {
      await workspace.delete(recursive: true);
    }
  });

  test('Builder preset executes write/read/preview/report loop', () async {
    final runner = ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
    final controller = AgentLoopController(
      adapter: adapter,
      actionRunner: runner,
      preset: AgentPreset.builder,
    );

    final result = await controller.run(
      initialMessages: const [
        {'role': 'user', 'content': 'build a page'},
      ],
      requestModel: (messages, {required round}) async {
        if (round == 1) {
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_write',
                name: 'write_file',
                arguments: {
                  'path': 'demo/index.html',
                  'content': '<!doctype html><html><body>Hello</body></html>',
                  'overwrite': true,
                },
              ),
              ProviderToolCall(
                id: 'call_read',
                name: 'read_file',
                arguments: {'path': 'demo/index.html', 'max_bytes': 4096},
              ),
              ProviderToolCall(
                id: 'call_preview',
                name: 'preview_html',
                arguments: {'path': 'demo/index.html', 'html': ''},
              ),
            ],
          );
        }
        return const ProviderToolCallResponse(
          content: '',
          toolCalls: [
            ProviderToolCall(
              id: 'call_report',
              name: 'report_result',
              arguments: {
                'status': 'success',
                'summary': 'Page built and previewed.',
                'detail': 'Evidence captured.',
              },
            ),
          ],
        );
      },
    );

    expect(result.usedNativeToolCalls, true);
    expect(result.toolCallCount, 4);
    expect(result.answer, contains('Page built and previewed.'));
    expect(await File('${workspace.path}/demo/index.html').exists(), true);
    expect(store.recent(count: 10).where((evidence) => evidence.success), isNotEmpty);
  });

  test('Reviewer preset blocks write_file and records failed evidence', () async {
    final runner = ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
    final controller = AgentLoopController(
      adapter: adapter,
      actionRunner: runner,
      preset: AgentPreset.reviewer,
    );

    final result = await controller.run(
      initialMessages: const [
        {'role': 'user', 'content': 'review only'},
      ],
      requestModel: (messages, {required round}) async {
        if (round == 1) {
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_blocked_write',
                name: 'write_file',
                arguments: {
                  'path': 'blocked/index.html',
                  'content': '<!doctype html>',
                  'overwrite': true,
                },
              ),
            ],
          );
        }
        return const ProviderToolCallResponse(
          content: '',
          toolCalls: [
            ProviderToolCall(
              id: 'call_report',
              name: 'report_result',
              arguments: {
                'status': 'blocked',
                'summary': 'Write was blocked for reviewer.',
                'detail': 'Reviewer is read-only.',
              },
            ),
          ],
        );
      },
    );

    expect(result.answer, contains('Write was blocked'));
    expect(await File('${workspace.path}/blocked/index.html').exists(), false);
    expect(store.failures().single.failureKind, ActionFailureKind.commandBlocked);
  });

  test('Auto preset lets the model choose web and file tools without a fixed sequence', () async {
    final runner = ActionRunner(
      workspaceRootPath: workspace.path,
      evidenceStore: store,
      webToolInvoker: (toolName, payload) async {
        expect(toolName, 'web_search');
        return {
          'source': 'test-relay',
          'results': [
            {
              'refId': 'ref_1',
              'title': 'Mobile 3D inspiration',
              'url': 'https://example.com/mobile-3d',
              'snippet': 'Compact mobile-first 3D landing reference.',
            },
          ],
        };
      },
    );
    final controller = AgentLoopController(
      adapter: adapter,
      actionRunner: runner,
      preset: AgentPreset.autoAgent,
    );

    final result = await controller.run(
      initialMessages: const [
        {'role': 'user', 'content': 'research and build a page'},
      ],
      requestModel: (messages, {required round}) async {
        if (round == 1) {
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_search',
                name: 'web_search',
                arguments: {'query': 'mobile 3D landing reference', 'count': 1},
              ),
            ],
          );
        }
        if (round == 2) {
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_write',
                name: 'write_file',
                arguments: {
                  'path': 'auto/index.html',
                  'content': '<!doctype html><html><body>Auto</body></html>',
                  'overwrite': true,
                },
              ),
              ProviderToolCall(
                id: 'call_preview',
                name: 'preview_html',
                arguments: {'path': 'auto/index.html', 'html': ''},
              ),
            ],
          );
        }
        return const ProviderToolCallResponse(
          content: '',
          toolCalls: [
            ProviderToolCall(
              id: 'call_report',
              name: 'report_result',
              arguments: {
                'status': 'success',
                'summary': 'Auto Agent chose search, write, and preview.',
                'detail': 'No fixed A to B to C sequence was required.',
              },
            ),
          ],
        );
      },
    );

    expect(result.usedNativeToolCalls, true);
    expect(result.answer, contains('Auto Agent chose'));
    expect(await File('${workspace.path}/auto/index.html').exists(), true);
    expect(store.recent(count: 10).map((evidence) => evidence.actionName), contains(MobileCodeAction.webSearch));
    expect(store.recent(count: 10).map((evidence) => evidence.actionName), contains(MobileCodeAction.writeFile));
  });

  test('agent loop appends assistant tool-call message with reasoning before tool results', () async {
    final runner = ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
    final controller = AgentLoopController(
      adapter: adapter,
      actionRunner: runner,
      preset: AgentPreset.builder,
    );
    final result = await controller.run(
      initialMessages: const [
        {'role': 'user', 'content': 'build a minimal file'},
      ],
      requestModel: (loopMessages, {required round}) async {
        if (round == 1) {
          return const ProviderToolCallResponse(
            content: '',
            finishReason: 'tool_calls',
            reasoningContent: 'Create index file first.',
            toolCalls: [
              ProviderToolCall(
                id: 'call_write',
                name: 'write_file',
                arguments: {
                  'path': 'round2/index.html',
                  'content': '<!doctype html><title>Round2</title>',
                  'overwrite': true,
                },
              ),
            ],
          );
        }

        if (round == 2 && loopMessages.length < 3) {
          fail('Expected second round to include assistant tool-call and tool result history.');
        }

        final assistantMessages = loopMessages
            .where((message) => message['role'] == 'assistant' && message['tool_calls'] != null)
            .toList();
        expect(assistantMessages, isNotEmpty);
        expect(assistantMessages.first.containsKey('finish_reason'), false);
        expect(assistantMessages.first['reasoning_content'], 'Create index file first.');
        final assistantIndex = loopMessages.indexOf(assistantMessages.first);
        expect(loopMessages[assistantIndex + 1]['role'], 'tool');
        expect(loopMessages[assistantIndex + 1]['tool_call_id'], 'call_write');

        return const ProviderToolCallResponse(
          content: 'Done',
          toolCalls: [
            ProviderToolCall(
              id: 'call_report',
              name: 'report_result',
              arguments: {
                'status': 'success',
                'summary': 'Loop message order verified.',
                'detail': 'Assistant message was before tool result.',
              },
            ),
          ],
        );
      },
    );

    expect(result.usedNativeToolCalls, true);
    expect(result.answer, contains('Loop message order verified.'));
  });
}
