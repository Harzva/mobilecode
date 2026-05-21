import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/core/evidence/action_evidence_store.dart';
import 'package:mobile_agent/core/evidence/action_runner.dart';
import 'package:mobile_agent/core/evidence/evidence_model.dart';
import 'package:mobile_agent/services/tool_call_adapter.dart';

void main() {
  test('detects DeepSeek beta as strict OpenAI-compatible tool provider', () {
    final profile = ToolCallProviderProfile.detect(
      'https://api.deepseek.com/beta',
      'deepseek-chat',
    );

    expect(profile.isDeepSeek, true);
    expect(profile.isOpenAiCompatible, true);
    expect(profile.strictTools, true);
    expect(profile.supportsNativeToolCalls, true);
  });

  test('excludes DeepSeek experimental model that does not support tool calls', () {
    final profile = ToolCallProviderProfile.detect(
      'https://api.deepseek.com/v1',
      'DeepSeek-V3.2-Exp',
    );

    expect(profile.isDeepSeek, true);
    expect(profile.supportsNativeToolCalls, false);
  });

  test('builds strict tool schema for safe MobileCode tools only', () {
    final tools = OpenAiCompatibleToolCallAdapter.toolDefinitions(strict: true);
    final names = tools
        .map((tool) => ((tool['function'] as Map<String, dynamic>)['name'] as String))
        .toList();

    expect(names, ['write_file', 'read_file', 'preview_html', 'report_result']);
    for (final tool in tools) {
      final function = tool['function'] as Map<String, dynamic>;
      final parameters = function['parameters'] as Map<String, dynamic>;
      final properties = parameters['properties'] as Map<String, dynamic>;
      expect(function['strict'], true);
      expect(parameters['additionalProperties'], false);
      expect(parameters['required'], properties.keys.toList());
    }
  });

  test('parses non-streaming tool_calls and maps write_file to ActionSchema', () {
    final adapter = OpenAiCompatibleToolCallAdapter(
      profile: ToolCallProviderProfile.detect('https://api.deepseek.com/v1', 'deepseek-chat'),
    );

    final parsed = adapter.parseChatCompletion({
      'choices': [
        {
          'finish_reason': 'tool_calls',
          'message': {
            'role': 'assistant',
            'content': '',
            'tool_calls': [
              {
                'id': 'call_write',
                'type': 'function',
                'function': {
                  'name': 'write_file',
                  'arguments': '{"path":"game/index.html","content":"<!doctype html>","overwrite":true}',
                },
              },
            ],
          },
        },
      ],
    });

    expect(parsed.finishReason, 'tool_calls');
    expect(parsed.toolCalls.single.name, 'write_file');
    final schema = adapter.toActionSchema(parsed.toolCalls.single)!;
    expect(schema.actionName, MobileCodeAction.writeFile);
    expect(schema.params['path'], 'game/index.html');
    expect(schema.params['content'], '<!doctype html>');
    expect(schema.params['overwrite'], true);
  });

  test('assembles streaming delta.tool_calls fragments', () {
    final assembler = OpenAiToolCallStreamAssembler()
      ..addChunk({
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'call_read',
                  'function': {'name': 'read_file', 'arguments': '{"path":"index'},
                },
              ],
            },
          },
        ],
      })
      ..addChunk({
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'index': 0,
                  'function': {'arguments': '.html","max_bytes":1024}'},
                },
              ],
            },
          },
        ],
      });

    final calls = assembler.finish();
    expect(calls.single.id, 'call_read');
    expect(calls.single.name, 'read_file');
    expect(calls.single.arguments['path'], 'index.html');
    expect(calls.single.arguments['max_bytes'], 1024);
  });

  test('builds tool result message from ActionRunner evidence', () async {
    final workspace = await Directory.systemTemp.createTemp('mobilecode_tool_adapter_');
    final store = ActionEvidenceStore();
    final runner = ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
    final adapter = OpenAiCompatibleToolCallAdapter(
      profile: ToolCallProviderProfile.detect('https://api.deepseek.com/v1', 'deepseek-chat'),
    );
    try {
      final call = const ProviderToolCall(
        id: 'call_write',
        name: 'write_file',
        arguments: {
          'path': 'index.html',
          'content': '<!doctype html><title>Hi</title>',
          'overwrite': true,
        },
      );
      final result = await runner.run(adapter.toActionSchema(call)!);
      final message = adapter.buildToolResultMessage(call, result);

      expect(message['role'], 'tool');
      expect(message['tool_call_id'], 'call_write');
      expect(message['content'], contains('"success":true'));
      expect(message['content'], contains('"evidenceId":"call_write"'));
    } finally {
      if (await workspace.exists()) {
        await workspace.delete(recursive: true);
      }
    }
  });
}
