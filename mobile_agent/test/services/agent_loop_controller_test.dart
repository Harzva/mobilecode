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
      profile: ToolCallProviderProfile.detect('https://api.deepseek.com/v1', 'deepseek-chat'),
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
}
