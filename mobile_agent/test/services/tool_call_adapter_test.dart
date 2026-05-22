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

    expect(names, [
      'web_search',
      'fetch_url',
      'write_file',
      'read_file',
      'preview_html',
      'preview_snapshot',
      'report_result',
    ]);
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

  test('maps relay web tools and preview snapshot to ActionSchema', () {
    final adapter = OpenAiCompatibleToolCallAdapter(
      profile: ToolCallProviderProfile.detect('https://api.deepseek.com/v1', 'deepseek-chat'),
    );

    final webSearch = adapter.toActionSchema(const ProviderToolCall(
      id: 'call_search',
      name: 'web_search',
      arguments: {'query': 'mobile 3d landing', 'count': 4},
    ))!;
    expect(webSearch.actionName, MobileCodeAction.webSearch);
    expect(webSearch.params['query'], 'mobile 3d landing');

    final fetch = adapter.toActionSchema(const ProviderToolCall(
      id: 'call_fetch',
      name: 'fetch_url',
      arguments: {'url': 'https://example.com', 'max_bytes': 2048},
    ))!;
    expect(fetch.actionName, MobileCodeAction.fetchUrl);
    expect(fetch.params['maxBytes'], 2048);

    final snapshot = adapter.toActionSchema(const ProviderToolCall(
      id: 'call_snapshot',
      name: 'preview_snapshot',
      arguments: {
        'path': 'demo/index.html',
        'url': '',
        'html': '',
        'viewport_width': 390,
        'viewport_height': 844,
      },
    ))!;
    expect(snapshot.actionName, MobileCodeAction.previewSnapshot);
    expect(snapshot.params['viewportWidth'], 390);
  });

  test('preserves DeepSeek reasoning_content when returning tool observations', () {
    final adapter = OpenAiCompatibleToolCallAdapter(
      profile: ToolCallProviderProfile.detect('https://api.deepseek.com/v1', 'deepseek-chat'),
    );

    final request = adapter.buildChatCompletionRequest(
      model: 'deepseek-chat',
      systemPrompt: 'system',
      messages: const [
        {'role': 'user', 'content': 'build snake'},
      ],
    );
    expect(request.containsKey('tool_choice'), false);

    final parsed = adapter.parseChatCompletion({
      'choices': [
        {
          'finish_reason': 'tool_calls',
          'message': {
            'role': 'assistant',
            'content': '',
            'reasoning_content': 'Need to create one HTML file.',
            'tool_calls': [
              {
                'id': 'call_write',
                'type': 'function',
                'function': {
                  'name': 'write_file',
                  'arguments': '{"path":"snake/index.html","content":"<!doctype html>","overwrite":true}',
                },
              },
            ],
          },
        },
      ],
    });

    expect(parsed.reasoningContent, 'Need to create one HTML file.');
    final assistantMessage = adapter.assistantToolCallMessage(parsed);
    expect(assistantMessage['reasoning_content'], 'Need to create one HTML file.');
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
