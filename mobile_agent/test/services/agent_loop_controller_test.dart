import 'dart:convert';
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

  test('Reviewer preset blocks apply_patch mutations', () async {
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
                id: 'call_blocked_patch',
                name: 'apply_patch',
                arguments: {
                  'patch': '--- a/a.txt\n+++ b/a.txt\n@@ -0,0 +1,1 @@\n+blocked',
                  'reason': 'should be blocked',
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
                'summary': 'Patch was blocked for reviewer.',
                'detail': 'Reviewer is read-only.',
              },
            ),
          ],
        );
      },
    );

    expect(result.answer, contains('Patch was blocked'));
    expect(await File('${workspace.path}/a.txt').exists(), false);
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

  test('filters relay-backed web tools when no managed relay is configured', () async {
    final runner = ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
    final controller = AgentLoopController(
      adapter: adapter,
      actionRunner: runner,
      preset: AgentPreset.autoAgent,
    );

    expect(controller.allowedToolNames, isNot(contains('web_search')));
    expect(controller.allowedToolNames, isNot(contains('fetch_url')));

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
                arguments: {'query': 'mobile reference', 'count': 1},
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
                'summary': 'Web tools were unavailable.',
                'detail': 'Agent should continue with local tools or ask for relay configuration.',
              },
            ),
          ],
        );
      },
    );

    expect(result.answer, contains('Web tools were unavailable'));
    expect(store.failures().single.logs.join(' '), contains('not allowed'));
  });

  test('builder writes HTML when provider omits path but sends complete content', () async {
    final runner = ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
    final controller = AgentLoopController(
      adapter: adapter,
      actionRunner: runner,
      preset: AgentPreset.builder,
    );

    final result = await controller.run(
      initialMessages: const [
        {'role': 'user', 'content': 'build a minimal page'},
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
                  'content': '<!doctype html><html><body>Default path</body></html>',
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
                'status': 'success',
                'summary': 'Default path write completed.',
                'detail': 'index.html was used.',
              },
            ),
          ],
        );
      },
    );

    expect(result.answer, contains('Default path write completed'));
    expect(await File('${workspace.path}/index.html').readAsString(), contains('Default path'));
  });

  test('Repair preset can find, read, patch, preview, and report', () async {
    final file = File('${workspace.path}/repair/index.html');
    await file.parent.create(recursive: true);
    await file.writeAsString('<h1>Broken</h1>\n<p>Keep</p>');
    final runner = ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
    final controller = AgentLoopController(
      adapter: adapter,
      actionRunner: runner,
      preset: AgentPreset.repair,
      maxRounds: 4,
    );

    final result = await controller.run(
      initialMessages: const [
        {'role': 'user', 'content': 'repair the page'},
      ],
      requestModel: (messages, {required round}) async {
        if (round == 1) {
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_find',
                name: 'find_files',
                arguments: {'pattern': '*.html', 'path': '.', 'max_results': 10},
              ),
              ProviderToolCall(
                id: 'call_read',
                name: 'read_file',
                arguments: {'path': 'repair/index.html', 'max_bytes': 4096},
              ),
            ],
          );
        }
        if (round == 2) {
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_patch',
                name: 'apply_patch',
                arguments: {
                  'patch': '--- a/repair/index.html\n+++ b/repair/index.html\n@@ -1,2 +1,2 @@\n-<h1>Broken</h1>\n+<h1>Fixed</h1>\n <p>Keep</p>',
                  'reason': 'fix heading',
                },
              ),
            ],
          );
        }
        if (round == 3) {
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_preview',
                name: 'preview_html',
                arguments: {'path': 'repair/index.html', 'html': ''},
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
                'summary': 'Repair completed.',
                'detail': 'find/read/patch/preview/report path verified.',
              },
            ),
          ],
        );
      },
    );

    expect(result.answer, contains('Repair completed'));
    expect(await file.readAsString(), contains('Fixed'));
    expect(store.recent(count: 10).map((evidence) => evidence.actionName), contains(MobileCodeAction.applyPatch));
  });

  test('invalid patch is reported as a safe block instead of a run failure event', () async {
    final file = File('${workspace.path}/safe/index.html');
    await file.parent.create(recursive: true);
    await file.writeAsString('<h1>Existing</h1>');
    final runner = ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
    final controller = AgentLoopController(
      adapter: adapter,
      actionRunner: runner,
      preset: AgentPreset.repair,
      maxRounds: 2,
    );
    final events = <AgentLoopEvent>[];

    final result = await controller.run(
      initialMessages: const [
        {'role': 'user', 'content': 'repair the page'},
      ],
      onEvent: events.add,
      requestModel: (messages, {required round}) async {
        if (round == 1) {
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_bad_patch',
                name: 'apply_patch',
                arguments: {
                  'patch': '--- a/safe/index.html\n+++ b/safe/index.html\n@@ ... @@\n-<h1>Existing</h1>\n+<h1>Fixed</h1>',
                  'reason': 'model emitted an invalid hunk placeholder',
                },
              ),
            ],
          );
        }
        return const ProviderToolCallResponse(
          content: 'Cannot apply the patch until the model sends real hunk coordinates.',
          toolCalls: [],
        );
      },
    );

    expect(result.answer, contains('Cannot apply'));
    expect(events.map((event) => event.type), contains(AgentLoopEventType.blocked));
    expect(events.map((event) => event.type), isNot(contains(AgentLoopEventType.failed)));
    expect(store.failures().single.failureKind, ActionFailureKind.commandBlocked);
  });

  test('invalid apply_patch is actionable and a later valid patch can proceed', () async {
    final file = File('${workspace.path}/safe_recover/index.html');
    await file.parent.create(recursive: true);
    await file.writeAsString('<h1>Existing</h1>');
    final runner = ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
    final controller = AgentLoopController(
      adapter: adapter,
      actionRunner: runner,
      preset: AgentPreset.repair,
      maxRounds: 3,
    );
    final events = <AgentLoopEvent>[];

    final result = await controller.run(
      initialMessages: const [
        {'role': 'user', 'content': 'repair the page'},
      ],
      onEvent: events.add,
      requestModel: (messages, {required round}) async {
        if (round == 1) {
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_bad_patch',
                name: 'apply_patch',
                arguments: {
                  'patch': '--- a/safe_recover/index.html\n+++ b/safe_recover/index.html\n@@ ... @@\n-<h1>Existing</h1>\n+<h1>Recovered</h1>',
                  'reason': 'test invalid then fix',
                },
              ),
            ],
          );
        }
        if (round == 2) {
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_valid_patch',
                name: 'apply_patch',
                arguments: {
                  'patch': '--- a/safe_recover/index.html\n+++ b/safe_recover/index.html\n@@ -1,1 +1,1 @@\n-<h1>Existing</h1>\n+<h1>Recovered</h1>',
                },
              ),
            ],
          );
        }
        return const ProviderToolCallResponse(
          content: 'Valid patch fixed the artifact after one recovery hint.',
          toolCalls: [],
        );
      },
    );

    expect(result.answer, contains('Valid patch fixed the artifact'));
    expect(await file.readAsString(), contains('Recovered'));
    final blockedEvents = events.where((event) => event.type == AgentLoopEventType.blocked).toList();
    expect(blockedEvents.length, 1);
    final blockedMessage = blockedEvents.first.message;
    expect(blockedMessage, contains('failureKind=commandBlocked'));
    expect(blockedMessage, contains('toolName=apply_patch'));
    expect(blockedMessage, contains('safeNextAction'));
    expect(blockedMessage, contains('unified diff headers'));
  });

  test('repeated blocked apply_patch asks for a strategy switch', () async {
    final file = File('${workspace.path}/safe_repeat/index.html');
    await file.parent.create(recursive: true);
    await file.writeAsString('<h1>Existing</h1>');
    final runner = ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
    final controller = AgentLoopController(
      adapter: adapter,
      actionRunner: runner,
      preset: AgentPreset.repair,
      maxRounds: 3,
    );
    final events = <AgentLoopEvent>[];
    List<Map<String, dynamic>>? round3Messages;

    final result = await controller.run(
      initialMessages: const [
        {'role': 'user', 'content': 'repair the page'},
      ],
      onEvent: events.add,
      requestModel: (messages, {required round}) async {
        if (round <= 2) {
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_repeat_patch',
                name: 'apply_patch',
                arguments: {
                  'patch': '--- a/safe_repeat/index.html\n+++ b/safe_repeat/index.html\n@@ ... @@\n-<h1>Existing</h1>\n+<h1>Recovered</h1>',
                },
              ),
            ],
          );
        }
        round3Messages = messages;
        return const ProviderToolCallResponse(
          content: 'Still blocked to avoid repeating the same invalid patch.',
          toolCalls: [],
        );
      },
    );

    expect(result.answer, contains('Still blocked'));
    final blocked = events.where((event) => event.type == AgentLoopEventType.blocked).toList();
    expect(blocked.length, 2);
    expect(blocked[1].message, contains('Switch strategy'));
    final toolObservations = round3Messages!
        .where((message) => message['role'] == 'tool')
        .map((message) => message['content'].toString())
        .join(' ');
    expect(toolObservations, contains('Switch strategy'));
    expect(store.failures(), isNotEmpty);
  });

  test('missing write_file path is reported with clear blocked observation', () async {
    final runner = ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
    final controller = AgentLoopController(
      adapter: adapter,
      actionRunner: runner,
      preset: AgentPreset.builder,
      maxRounds: 2,
    );
    final events = <AgentLoopEvent>[];

    final result = await controller.run(
      initialMessages: const [
        {'role': 'user', 'content': 'missing path case'},
      ],
      onEvent: events.add,
      requestModel: (messages, {required round}) async {
        if (round == 1) {
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_missing_path',
                name: 'write_file',
                arguments: {
                  'content': 'not full html',
                  'overwrite': true,
                },
              ),
            ],
          );
        }
        return const ProviderToolCallResponse(
          content: 'Missing path should be actionable.',
          toolCalls: [],
        );
      },
    );

    expect(result.answer, contains('Missing path should be actionable'));
    final blocked = events.where((event) => event.type == AgentLoopEventType.blocked).toList();
    expect(blocked, isNotEmpty);
    expect(blocked.first.message, contains('failureKind=commandBlocked'));
    expect(blocked.first.message, contains('toolName=write_file'));
    expect(blocked.first.message, contains('safeNextAction'));
    expect(blocked.first.message, contains('path'));
    expect(blocked.first.message, contains('path=index.html'));
  });

  test('Sub-Agent Lite open eval close returns read-only mailbox observations', () async {
    await File('${workspace.path}/index.html').writeAsString('<h1>MobileCode</h1>');
    final runner = ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
    final controller = AgentLoopController(
      adapter: adapter,
      actionRunner: runner,
      preset: AgentPreset.reviewer,
      maxRounds: 4,
    );
    final events = <AgentLoopEvent>[];
    String? agentId;

    String readAgentIdFromLastTool(List<Map<String, dynamic>> messages) {
      final toolMessage = messages.lastWhere((message) => message['role'] == 'tool');
      final resultPayload = jsonDecode(toolMessage['content'].toString()) as Map<String, dynamic>;
      final sessionPayload = jsonDecode(resultPayload['text'].toString()) as Map<String, dynamic>;
      return sessionPayload['agent_id'].toString();
    }

    final result = await controller.run(
      initialMessages: const [
        {'role': 'user', 'content': 'open a read-only explorer and summarize files'},
      ],
      onEvent: events.add,
      requestModel: (messages, {required round}) async {
        if (round == 1) {
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_agent_open',
                name: 'agent_open',
                arguments: {
                  'role': 'explorer',
                  'task': 'Inspect the local web artifact without writing.',
                  'path': '.',
                  'focus': 'MobileCode',
                },
              ),
            ],
          );
        }
        if (round == 2) {
          agentId = readAgentIdFromLastTool(messages);
          return ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_agent_eval',
                name: 'agent_eval',
                arguments: {'agent_id': agentId},
              ),
            ],
          );
        }
        if (round == 3) {
          return ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_agent_close',
                name: 'agent_close',
                arguments: {
                  'agent_id': agentId,
                  'reason': 'Parent run collected the read-only mailbox.',
                },
              ),
            ],
          );
        }
        return const ProviderToolCallResponse(
          content: 'Sub-Agent Lite inspected safely.',
          toolCalls: [],
        );
      },
    );

    expect(result.answer, contains('Sub-Agent Lite inspected safely'));
    expect(agentId, isNotNull);
    expect(events.map((event) => event.message).join(' '), contains('Mailbox'));
    expect(events.map((event) => event.roleName).whereType<String>().join(' '), contains('Explorer sub-agent'));
    expect(store.recent(count: 20).map((evidence) => evidence.evidenceId), contains('call_agent_open'));
  });

  test('Sub-Agent Lite blocks non-read-only roles', () async {
    final runner = ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
    final controller = AgentLoopController(
      adapter: adapter,
      actionRunner: runner,
      preset: AgentPreset.autoAgent,
      maxRounds: 2,
    );
    final events = <AgentLoopEvent>[];

    final result = await controller.run(
      initialMessages: const [
        {'role': 'user', 'content': 'try unsafe sub agent'},
      ],
      onEvent: events.add,
      requestModel: (messages, {required round}) async {
        if (round == 1) {
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_agent_unsafe',
                name: 'agent_open',
                arguments: {
                  'role': 'implementer',
                  'task': 'write code in the background',
                  'path': '.',
                  'focus': '',
                },
              ),
            ],
          );
        }
        return const ProviderToolCallResponse(
          content: 'Unsafe sub-agent was blocked.',
          toolCalls: [],
        );
      },
    );

    expect(result.answer, contains('Unsafe sub-agent was blocked'));
    expect(events.map((event) => event.type), contains(AgentLoopEventType.blocked));
    expect(store.failures().single.failureKind, ActionFailureKind.commandBlocked);
    expect(store.failures().single.logs.join(' '), contains('read-only explorer or reviewer'));
  });

  test('Sub-Agent Lite tools still obey preset allow-list', () async {
    final runner = ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
    final controller = AgentLoopController(
      adapter: adapter,
      actionRunner: runner,
      preset: AgentPreset.builder,
      maxRounds: 2,
    );
    final events = <AgentLoopEvent>[];

    final result = await controller.run(
      initialMessages: const [
        {'role': 'user', 'content': 'builder should not open sub agents'},
      ],
      onEvent: events.add,
      requestModel: (messages, {required round}) async {
        if (round == 1) {
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_agent_forbidden',
                name: 'agent_open',
                arguments: {
                  'role': 'explorer',
                  'task': 'Inspect files',
                  'path': '.',
                  'focus': '',
                },
              ),
            ],
          );
        }
        return const ProviderToolCallResponse(
          content: 'Forbidden sub-agent was blocked.',
          toolCalls: [],
        );
      },
    );

    expect(result.answer, contains('Forbidden sub-agent was blocked'));
    expect(events.map((event) => event.type), contains(AgentLoopEventType.blocked));
    expect(store.failures().single.failureKind, ActionFailureKind.commandBlocked);
    expect(store.failures().single.logs.join(' '), contains('not allowed for Builder'));
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

  test('blocks repeated write_file after a successful write until verification', () async {
    final runner = ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
    final controller = AgentLoopController(
      adapter: adapter,
      actionRunner: runner,
      preset: AgentPreset.builder,
      maxRounds: 3,
    );

    final result = await controller.run(
      initialMessages: const [
        {'role': 'user', 'content': 'build a minimal file'},
      ],
      requestModel: (loopMessages, {required round}) async {
        if (round == 1) {
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_write_1',
                name: 'write_file',
                arguments: {
                  'path': 'repeat/index.html',
                  'content': '<!doctype html><title>First</title>',
                  'overwrite': true,
                },
              ),
            ],
          );
        }
        if (round == 2) {
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_write_2',
                name: 'write_file',
                arguments: {
                  'path': 'repeat/index.html',
                  'content': '<!doctype html><title>Second</title>',
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
                'status': 'partial',
                'summary': 'Repeat write was blocked.',
                'detail': 'The agent must read or preview before rewriting.',
              },
            ),
          ],
        );
      },
    );

    expect(result.answer, contains('Repeat write was blocked'));
    expect(await File('${workspace.path}/repeat/index.html').readAsString(), contains('First'));
    expect(store.failures().single.logs.join(' '), contains('already changed successfully'));
  });
}
