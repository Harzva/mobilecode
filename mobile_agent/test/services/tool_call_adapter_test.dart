import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/core/evidence/action_evidence_store.dart';
import 'package:mobile_agent/core/evidence/action_runner.dart';
import 'package:mobile_agent/core/evidence/evidence_model.dart';
import 'package:mobile_agent/services/lark_api_service.dart';
import 'package:mobile_agent/services/tool_call_adapter.dart';

void main() {
  test('detects DeepSeek beta as strict OpenAI-compatible tool provider', () {
    final profile = ToolCallProviderProfile.detect(
      'https://api.deepseek.com/beta',
      'deepseek-v4-pro',
    );

    expect(profile.isDeepSeek, true);
    expect(profile.deepSeekProfile, DeepSeekProviderProfileKind.strictBeta);
    expect(profile.isDeepSeekStrictBeta, true);
    expect(profile.isOpenAiCompatible, true);
    expect(profile.strictTools, true);
    expect(profile.supportsNativeToolCalls, true);
  });

  test('detects DeepSeek v4 flash and pro provider profiles', () {
    final flash = ToolCallProviderProfile.detect(
      'https://api.deepseek.com/v1',
      'deepseek-v4-flash',
    );
    final pro = ToolCallProviderProfile.detect(
      'https://api.deepseek.com',
      'deepseek-v4-pro',
    );

    expect(flash.deepSeekProfile, DeepSeekProviderProfileKind.v4Flash);
    expect(flash.label, 'DeepSeek v4 Flash');
    expect(flash.isDeepSeekV4, true);
    expect(flash.supportsNativeToolCalls, true);
    expect(pro.deepSeekProfile, DeepSeekProviderProfileKind.v4Pro);
    expect(pro.label, 'DeepSeek v4 Pro');
    expect(pro.isDeepSeekV4, true);
    expect(pro.supportsNativeToolCalls, true);
  });

  test('detects DeepSeek legacy aliases without recommending them as v4', () {
    final chat = ToolCallProviderProfile.detect(
      'https://api.deepseek.com/v1',
      'deepseek-chat',
    );
    final reasoner = ToolCallProviderProfile.detect(
      'https://api.deepseek.com/v1',
      'deepseek-reasoner',
    );

    expect(chat.deepSeekProfile, DeepSeekProviderProfileKind.legacyChat);
    expect(chat.isDeepSeekLegacy, true);
    expect(chat.isDeepSeekV4, false);
    expect(chat.supportsNativeToolCalls, true);
    expect(
        reasoner.deepSeekProfile, DeepSeekProviderProfileKind.legacyReasoner);
    expect(reasoner.isDeepSeekLegacy, true);
    expect(reasoner.supportsNativeToolCalls, true);
  });

  test('excludes DeepSeek experimental model that does not support tool calls',
      () {
    final profile = ToolCallProviderProfile.detect(
      'https://api.deepseek.com',
      'DeepSeek-V3.2-Exp',
    );

    expect(profile.isDeepSeek, true);
    expect(
      profile.deepSeekProfile,
      DeepSeekProviderProfileKind.experimentalUnsupported,
    );
    expect(profile.supportsNativeToolCalls, false);
  });

  test('builds strict tool schema for safe MobileCode tools only', () {
    final tools = OpenAiCompatibleToolCallAdapter.toolDefinitions(strict: true);
    final names = tools
        .map((tool) =>
            ((tool['function'] as Map<String, dynamic>)['name'] as String))
        .toList();

    expect(names, [
      'list_files',
      'find_files',
      'grep_files',
      'project_summary',
      'detect_project_type',
      'change_history',
      'virtual_status',
      'agent_open',
      'agent_eval',
      'agent_close',
      'web_search',
      'fetch_url',
      'lark_readiness',
      'lark_wiki_list_spaces',
      'lark_docx_create',
      'lark_docx_append_blocks',
      'lark_sheets_append',
      'lark_bitable_create_records',
      'lark_drive_upload_preview',
      'write_file',
      'read_file',
      'copy_file',
      'mkdir',
      'delete_file',
      'move_file',
      'save_snapshot',
      'virtual_diff',
      'restore_snapshot',
      'validate_html',
      'validate_json',
      'validate_markdown',
      'apply_patch',
      'preview_html',
      'preview_snapshot',
      'termux_task_start',
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

  test('filters tool schema to currently exposed MobileCode tools', () {
    final tools = OpenAiCompatibleToolCallAdapter.toolDefinitions(
      allowedToolNames: const [
        'list_files',
        'write_file',
        'read_file',
        'report_result'
      ],
    );
    final names = tools
        .map((tool) =>
            ((tool['function'] as Map<String, dynamic>)['name'] as String))
        .toList();

    expect(names, ['list_files', 'write_file', 'read_file', 'report_result']);
    expect(names, isNot(contains('web_search')));
    expect(names, isNot(contains('fetch_url')));
    expect(names, isNot(contains('agent_open')));
  });

  test('filters Sub-Agent Lite tools when allowed by the preset', () {
    final tools = OpenAiCompatibleToolCallAdapter.toolDefinitions(
      allowedToolNames: const ['agent_open', 'agent_eval', 'agent_close'],
    );
    final names = tools
        .map((tool) =>
            ((tool['function'] as Map<String, dynamic>)['name'] as String))
        .toList();

    expect(names, ['agent_open', 'agent_eval', 'agent_close']);
  });

  test('parses non-streaming tool_calls and maps write_file to ActionSchema',
      () {
    final adapter = OpenAiCompatibleToolCallAdapter(
      profile: ToolCallProviderProfile.detect(
        'https://api.deepseek.com',
        'deepseek-v4-pro',
      ),
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
                  'arguments':
                      '{"path":"game/index.html","content":"<!doctype html>","overwrite":true}',
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

  test('write_file defaults missing path for complete HTML content', () {
    final adapter = OpenAiCompatibleToolCallAdapter(
      profile: ToolCallProviderProfile.detect(
        'https://api.deepseek.com',
        'deepseek-v4-flash',
      ),
    );

    final schema = adapter.toActionSchema(const ProviderToolCall(
      id: 'call_write',
      name: 'write_file',
      arguments: {
        'content': '<!doctype html><html><body>Hi</body></html>',
        'overwrite': true,
      },
    ))!;

    expect(schema.params['path'], 'index.html');
    expect(schema.params['content'], contains('<body>Hi</body>'));
    expect(schema.params['adapterRepair'],
        contains('inferred safe workspace path'));
  });

  test('write_file accepts common file path aliases', () {
    final adapter = OpenAiCompatibleToolCallAdapter(
      profile: ToolCallProviderProfile.detect(
        'https://api.deepseek.com',
        'deepseek-v4-flash',
      ),
    );

    final schema = adapter.toActionSchema(const ProviderToolCall(
      id: 'call_write',
      name: 'write_file',
      arguments: {
        'filename': 'demo.html',
        'content': '<!doctype html><html></html>',
      },
    ))!;

    expect(schema.params['path'], 'demo.html');
    expect(schema.params['adapterRepair'],
        contains('normalized path from `filename`'));
  });

  test('maps history status validators and typed termux tools to ActionSchema',
      () {
    final adapter = OpenAiCompatibleToolCallAdapter(
      profile: ToolCallProviderProfile.detect(
        'https://api.deepseek.com',
        'deepseek-v4-flash',
      ),
    );

    final history = adapter.toActionSchema(const ProviderToolCall(
      id: 'call_history',
      name: 'change_history',
      arguments: {
        'count': 12,
        'include_read_only': true,
        'action_filter': '',
      },
    ))!;
    final status = adapter.toActionSchema(const ProviderToolCall(
      id: 'call_status',
      name: 'virtual_status',
      arguments: {
        'path': '.',
        'max_files': 50,
        'max_recent': 8,
      },
    ))!;
    final detect = adapter.toActionSchema(const ProviderToolCall(
      id: 'call_detect',
      name: 'detect_project_type',
      arguments: {
        'path': '.',
        'max_depth': 3,
        'max_files': 100,
      },
    ))!;
    final json = adapter.toActionSchema(const ProviderToolCall(
      id: 'call_json',
      name: 'validate_json',
      arguments: {
        'path': 'package.json',
        'json': '',
        'max_bytes': 4096,
      },
    ))!;
    final markdown = adapter.toActionSchema(const ProviderToolCall(
      id: 'call_md',
      name: 'validate_markdown',
      arguments: {
        'path': 'README.md',
        'markdown': '',
        'max_bytes': 4096,
      },
    ))!;
    final termux = adapter.toActionSchema(const ProviderToolCall(
      id: 'call_termux',
      name: 'termux_task_start',
      arguments: {
        'task_kind': 'project_check',
        'path': '.',
        'args_json': '{}',
        'timeout_ms': 30000,
        'max_output_bytes': 4096,
        'reason': 'verify',
      },
    ))!;

    expect(history.actionName, MobileCodeAction.changeHistory);
    expect(history.params['includeReadOnly'], true);
    expect(status.actionName, MobileCodeAction.virtualStatus);
    expect(detect.actionName, MobileCodeAction.detectProjectType);
    expect(json.actionName, MobileCodeAction.validateJson);
    expect(markdown.actionName, MobileCodeAction.validateMarkdown);
    expect(termux.actionName, MobileCodeAction.termuxTaskStart);
    expect(termux.params['taskKind'], 'project_check');
  });

  test(
      'repairs malformed write_file arguments that contain a complete HTML document',
      () {
    final adapter = OpenAiCompatibleToolCallAdapter(
      profile: ToolCallProviderProfile.detect(
        'https://api.deepseek.com',
        'deepseek-v4-flash',
      ),
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
                  'arguments':
                      '<!doctype html><html><body>Recovered</body></html>',
                },
              },
            ],
          },
        },
      ],
    });

    final schema = adapter.toActionSchema(parsed.toolCalls.single)!;
    expect(schema.params['path'], 'index.html');
    expect(schema.params['content'], contains('Recovered'));
    expect(schema.params['adapterRepair'], contains('recovered complete HTML'));
  });

  test('maps relay web tools and preview snapshot to ActionSchema', () {
    final adapter = OpenAiCompatibleToolCallAdapter(
      profile: ToolCallProviderProfile.detect(
        'https://api.deepseek.com',
        'deepseek-v4-pro',
      ),
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

  test('maps typed Lark tools to native Lark API ActionSchema', () {
    final adapter = OpenAiCompatibleToolCallAdapter(
      profile: ToolCallProviderProfile.detect(
        'https://api.deepseek.com',
        'deepseek-v4-pro',
      ),
    );

    final appendDoc = adapter.toActionSchema(const ProviderToolCall(
      id: 'call_lark_doc',
      name: 'lark_docx_append_blocks',
      arguments: {
        'document_id': 'doccnDemo',
        'block_id': '',
        'title': 'MobileCode run',
        'content': 'Verifier passed',
        'dry_run': true,
        'confirm': false,
      },
    ))!;

    expect(appendDoc.actionName, MobileCodeAction.larkApi);
    expect(appendDoc.params['kind'], 'docxAppendBlocks');
    expect(appendDoc.params['documentId'], 'doccnDemo');
    expect(appendDoc.params['dryRun'], true);
    expect(appendDoc.params['confirm'], false);
  });

  test('keeps Lark CLI parity catalog aligned with native actions', () {
    final service = LarkApiService();
    final draft = const LarkApiPayloadDraft(
      title: 'MobileCode parity',
      content: 'Verifier evidence',
      documentId: 'doccnDemo',
      blockId: 'blockDemo',
      driveParentNode: 'fldcnDemo',
      spreadsheetToken: 'shtcnDemo',
      bitableAppToken: 'bascnDemo',
      bitableTableId: 'tblDemo',
    );
    final expectedPaths = <LarkApiActionKind, String>{
      LarkApiActionKind.docxCreate: 'POST /docx/v1/documents',
      LarkApiActionKind.docxAppendBlocks:
          'POST /docx/v1/documents/{document_id}/blocks/{block_id}/children',
      LarkApiActionKind.sheetsAppend:
          'POST /sheets/v2/spreadsheets/{spreadsheetToken}/values_append',
      LarkApiActionKind.driveUploadSmallFile: 'POST /drive/v1/files/upload_all',
      LarkApiActionKind.wikiListSpaces: 'GET /wiki/v2/spaces?page_size=10',
    };

    for (final entry in expectedPaths.entries) {
      final parity = LarkApiService.cliParityFor(entry.key);
      final spec = service.buildSpec(kind: entry.key, draft: draft);

      expect(parity['cliCommandTemplate'], isNot('N/A'));
      expect(parity['mobileNativePath'], entry.value);
      expect(parity['requiredScopes'], isNotEmpty);
      expect(spec.requiredScopes, isNotEmpty);
      expect(spec.method, entry.value.split(' ').first);
    }
  });

  test('records Lark CLI reference on dry-run evidence', () async {
    final workspace =
        await Directory.systemTemp.createTemp('mobilecode_lark_dry_run_');
    final store = ActionEvidenceStore();
    final runner = ActionRunner(
      workspaceRootPath: workspace.path,
      evidenceStore: store,
      larkApiService: _FakeLarkApiService(),
    );

    try {
      final result = await runner.run(ActionSchema(
        actionName: MobileCodeAction.larkApi,
        requestId: 'call_lark_dry_run',
        paramsSummary: 'test lark dry-run evidence',
        params: const {
          'kind': 'wikiListSpaces',
          'dryRun': true,
          'confirm': false,
        },
      ));

      expect(result.success, true);
      expect(result.evidence.metadata['dryRun'], true);
      final cliReference =
          result.evidence.metadata['cliReference'] as Map<String, Object?>;
      expect(cliReference['action'], 'wikiListSpaces');
      expect(
          cliReference['mobileNativePath'], 'GET /wiki/v2/spaces?page_size=10');
    } finally {
      if (await workspace.exists()) {
        await workspace.delete(recursive: true);
      }
    }
  });

  test('records Lark failure attribution for native API execution', () async {
    final workspace =
        await Directory.systemTemp.createTemp('mobilecode_lark_failure_');
    final store = ActionEvidenceStore();
    final runner = ActionRunner(
      workspaceRootPath: workspace.path,
      evidenceStore: store,
      larkApiService: _FakeLarkApiService(
        response: const LarkApiCallResult(
          success: false,
          statusCode: 403,
          elapsedMs: 17,
          endpoint: 'https://open.larksuite.com/open-apis/wiki/v2/spaces',
          tokenMode: 'user_access_token',
          larkCode: 99991663,
          larkMessage: 'permission denied',
          requestId: 'req-lark-403',
          body: '{"code":99991663,"msg":"permission denied"}',
          error: 'permission denied',
        ),
      ),
    );

    try {
      final result = await runner.run(ActionSchema(
        actionName: MobileCodeAction.larkApi,
        requestId: 'call_lark_failure',
        paramsSummary: 'test lark failed evidence attribution',
        params: const {
          'kind': 'wikiListSpaces',
          'dryRun': false,
          'confirm': false,
        },
      ));

      expect(result.success, false);
      expect(result.evidence.failureKind, ActionFailureKind.authFailed);
      final attribution = result.evidence.metadata['requestAttribution']
          as Map<String, Object?>;
      expect(attribution['tokenMode'], 'user_access_token');
      expect(attribution['tool'], 'wikiListSpaces');
      expect(attribution['httpStatus'], 403);
      expect(attribution['requestId'], 'req-lark-403');
      expect(attribution['errorCode'], 99991663);
      expect(attribution['dryRun'], false);
      final cliReference = attribution['cliReference'] as Map<String, Object?>;
      expect(cliReference['action'], 'wikiListSpaces');
    } finally {
      if (await workspace.exists()) {
        await workspace.delete(recursive: true);
      }
    }
  });

  test(
      'maps list/find/grep/summary/copy/mkdir/delete/move/snapshot/diff/restore/validate/patch to safe ActionSchema actions',
      () {
    final adapter = OpenAiCompatibleToolCallAdapter(
      profile: ToolCallProviderProfile.detect(
        'https://api.deepseek.com',
        'deepseek-v4-flash',
      ),
    );

    final list = adapter.toActionSchema(const ProviderToolCall(
      id: 'call_list',
      name: 'list_files',
      arguments: {'path': '.', 'recursive': false, 'max_entries': 20},
    ))!;
    expect(list.actionName, MobileCodeAction.listFiles);
    expect(list.params['path'], '.');
    expect(list.params['recursive'], false);
    expect(list.params['maxEntries'], 20);

    final find = adapter.toActionSchema(const ProviderToolCall(
      id: 'call_find',
      name: 'find_files',
      arguments: {'pattern': '*.html', 'path': '.', 'max_results': 12},
    ))!;
    expect(find.actionName, MobileCodeAction.findFiles);
    expect(find.params['pattern'], '*.html');
    expect(find.params['maxResults'], 12);

    final grep = adapter.toActionSchema(const ProviderToolCall(
      id: 'call_grep',
      name: 'grep_files',
      arguments: {
        'query': 'score',
        'path': '.',
        'include_glob': '*.html',
        'max_results': 7,
        'max_bytes': 4096,
      },
    ))!;
    expect(grep.actionName, MobileCodeAction.grepFiles);
    expect(grep.params['query'], 'score');
    expect(grep.params['includeGlob'], '*.html');
    expect(grep.params['maxBytes'], 4096);

    final summary = adapter.toActionSchema(const ProviderToolCall(
      id: 'call_summary',
      name: 'project_summary',
      arguments: {'path': '.', 'max_depth': 2, 'max_files': 30},
    ))!;
    expect(summary.actionName, MobileCodeAction.projectSummary);
    expect(summary.params['maxDepth'], 2);
    expect(summary.params['maxFiles'], 30);

    final copy = adapter.toActionSchema(const ProviderToolCall(
      id: 'call_copy',
      name: 'copy_file',
      arguments: {
        'source_path': 'draft.html',
        'destination_path': 'backup/draft.html',
        'overwrite': true,
      },
    ))!;
    expect(copy.actionName, MobileCodeAction.copyFile);
    expect(copy.params['sourcePath'], 'draft.html');
    expect(copy.params['destinationPath'], 'backup/draft.html');
    expect(copy.params['overwrite'], true);

    final mkdir = adapter.toActionSchema(const ProviderToolCall(
      id: 'call_mkdir',
      name: 'mkdir',
      arguments: {'path': 'generated/assets', 'recursive': true},
    ))!;
    expect(mkdir.actionName, MobileCodeAction.makeDirectory);
    expect(mkdir.params['path'], 'generated/assets');
    expect(mkdir.params['recursive'], true);

    final delete = adapter.toActionSchema(const ProviderToolCall(
      id: 'call_delete',
      name: 'delete_file',
      arguments: {'path': 'old.txt', 'confirm': true},
    ))!;
    expect(delete.actionName, MobileCodeAction.deleteFile);
    expect(delete.params['path'], 'old.txt');
    expect(delete.params['confirm'], true);

    final move = adapter.toActionSchema(const ProviderToolCall(
      id: 'call_move',
      name: 'move_file',
      arguments: {
        'source_path': 'draft.html',
        'destination_path': 'published/index.html',
        'overwrite': true,
      },
    ))!;
    expect(move.actionName, MobileCodeAction.moveFile);
    expect(move.params['sourcePath'], 'draft.html');
    expect(move.params['destinationPath'], 'published/index.html');
    expect(move.params['overwrite'], true);

    final snapshot = adapter.toActionSchema(const ProviderToolCall(
      id: 'call_snapshot',
      name: 'save_snapshot',
      arguments: {
        'path': '.',
        'label': 'before repair',
        'max_files': 40,
        'max_bytes': 8192
      },
    ))!;
    expect(snapshot.actionName, MobileCodeAction.saveSnapshot);
    expect(snapshot.params['path'], '.');
    expect(snapshot.params['label'], 'before repair');
    expect(snapshot.params['maxFiles'], 40);

    final diff = adapter.toActionSchema(const ProviderToolCall(
      id: 'call_diff',
      name: 'virtual_diff',
      arguments: {
        'path': '.',
        'snapshot_id': 'snapshot_123',
        'snapshot_path': '',
        'max_bytes': 4096,
      },
    ))!;
    expect(diff.actionName, MobileCodeAction.virtualDiff);
    expect(diff.params['snapshotId'], 'snapshot_123');
    expect(diff.params['maxBytes'], 4096);

    final restore = adapter.toActionSchema(const ProviderToolCall(
      id: 'call_restore',
      name: 'restore_snapshot',
      arguments: {
        'path': 'demo',
        'snapshot_id': 'snapshot_123',
        'snapshot_path': '',
        'confirm': true,
        'max_files': 20,
        'max_bytes': 4096,
      },
    ))!;
    expect(restore.actionName, MobileCodeAction.restoreSnapshot);
    expect(restore.params['snapshotId'], 'snapshot_123');
    expect(restore.params['confirm'], true);

    final validate = adapter.toActionSchema(const ProviderToolCall(
      id: 'call_validate',
      name: 'validate_html',
      arguments: {
        'path': 'index.html',
        'html': '',
        'max_bytes': 8192,
      },
    ))!;
    expect(validate.actionName, MobileCodeAction.validateHtml);
    expect(validate.params['path'], 'index.html');
    expect(validate.params['maxBytes'], 8192);

    final patch = adapter.toActionSchema(const ProviderToolCall(
      id: 'call_patch',
      name: 'apply_patch',
      arguments: {
        'patch': '--- a/a.txt\n+++ b/a.txt\n@@ -1,1 +1,1 @@\n-old\n+new',
        'reason': 'replace text',
      },
    ))!;
    expect(patch.actionName, MobileCodeAction.applyPatch);
    expect(patch.params['patch'], contains('+new'));
    expect(patch.params['reason'], 'replace text');
  });

  test(
      'assistant tool-call message preserves reasoning_content and tool_calls JSON',
      () {
    final adapter = OpenAiCompatibleToolCallAdapter(
      profile: ToolCallProviderProfile.detect(
        'https://api.deepseek.com',
        'deepseek-v4-pro',
      ),
    );

    final request = adapter.buildChatCompletionRequest(
      model: 'deepseek-v4-pro',
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
                  'arguments':
                      '{"path":"snake/index.html","content":"<!doctype html>","overwrite":true}',
                },
              },
            ],
          },
        },
      ],
    });

    expect(parsed.reasoningContent, 'Need to create one HTML file.');
    expect(parsed.finishReason, 'tool_calls');
    expect(parsed.toolCalls.single.id, 'call_write');
    expect(parsed.toolCalls.single.name, 'write_file');
    final assistantMessage = adapter.assistantToolCallMessage(parsed);
    final assistantToolCalls = assistantMessage['tool_calls'] as List;
    expect(assistantMessage['role'], 'assistant');
    expect(assistantMessage['content'], '');
    expect(assistantMessage.containsKey('finish_reason'), false);
    expect(
        assistantMessage['reasoning_content'], 'Need to create one HTML file.');
    expect(assistantToolCalls.length, 1);
    expect(assistantToolCalls.first['id'], 'call_write');
    expect(assistantToolCalls.first['type'], 'function');
    expect(assistantToolCalls.first['function']['name'], 'write_file');
    expect(
      assistantToolCalls.first['function']['arguments'],
      contains('\"path\":\"snake/index.html\"'),
    );
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
                  'function': {
                    'name': 'read_file',
                    'arguments': '{"path":"index'
                  },
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

  test('streams content and reasoning_content together with tool call deltas',
      () {
    final assembler = OpenAiToolCallStreamAssembler()
      ..addChunk({
        'choices': [
          {
            'delta': {
              'content': 'I think',
              'reasoning_content': 'Need a file.',
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'call_read',
                  'function': {
                    'name': 'read_file',
                    'arguments': '{"path":"demo/'
                  },
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
              'content': ' and preview it.',
              'reasoning_content': 'Then inspect result.',
              'tool_calls': [
                {
                  'index': 0,
                  'function': {'arguments': 'index.html","max_bytes":1024}'},
                },
              ],
            },
          },
        ],
      });

    final calls = assembler.finish();
    expect(assembler.content, 'I think and preview it.');
    expect(assembler.reasoningContent, 'Need a file.Then inspect result.');
    expect(calls.single.id, 'call_read');
    expect(calls.single.name, 'read_file');
    expect(calls.single.arguments['path'], 'demo/index.html');
    expect(calls.single.arguments['max_bytes'], 1024);
  });

  test(
      'ignores keep-alive, empty, and DONE chunks when parsing stream payloads',
      () {
    final ignoreDone = [
      parseOpenAiStreamEvent(''),
      parseOpenAiStreamEvent('event: ping'),
      parseOpenAiStreamEvent(': keep-alive'),
      parseOpenAiStreamEvent('data: [DONE]'),
      parseOpenAiStreamEvent('[DONE]'),
    ];

    expect(ignoreDone.every((event) => event.isIgnore || event.isDone), isTrue);
    expect(parseOpenAiStreamEvent('data:').isIgnore, isTrue);
    expect(parseOpenAiStreamEvent('data: [DONE]').isDone, isTrue);
    expect(parseOpenAiStreamEvent('data: {"a":1}').payload, '{"a":1}');
    expect(parseOpenAiStreamEvent('   data: [DONE]   ').isDone, isTrue);
  });

  test('multiple interleaved tool calls are assembled by index order', () {
    final assembler = OpenAiToolCallStreamAssembler()
      ..addChunk({
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'index': 1,
                  'id': 'call_beta',
                  'function': {
                    'name': 'preview_html',
                    'arguments': '{"path":"beta/',
                  },
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
                  'id': 'call_alpha',
                  'function': {
                    'name': 'write_file',
                    'arguments': '{"path":"alpha',
                  },
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
                  'index': 1,
                  'function': {'arguments': 'file.html","overwrite":true}'},
                },
                {
                  'index': 0,
                  'function': {'arguments': '.txt","content":"ok"}'},
                },
              ],
            },
          },
        ],
      });

    final calls = assembler.finish();
    expect(calls.length, 2);
    expect(calls[0].id, 'call_alpha');
    expect(calls[0].name, 'write_file');
    expect(calls[0].arguments['path'], 'alpha.txt');
    expect(calls[0].arguments['content'], 'ok');
    expect(calls[1].id, 'call_beta');
    expect(calls[1].name, 'preview_html');
    expect(calls[1].arguments['path'], 'beta/file.html');
    expect(calls[1].arguments['overwrite'], isTrue);
  });

  test(
      'choices=[] chunks with usage are ignored and never create fake tool calls',
      () {
    final assembler = OpenAiToolCallStreamAssembler()
      ..addChunk({
        'id': 'response-id',
        'usage': {'prompt_tokens': 32, 'completion_tokens': 13},
      })
      ..addChunk({
        'choices': [],
        'usage': {'prompt_tokens': 42, 'completion_tokens': 18},
      })
      ..addChunk({
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'call_report',
                  'function': {
                    'name': 'report_result',
                    'arguments':
                        '{"status":"success","summary":"ok","detail":"ok"}',
                  },
                },
              ],
            },
          },
        ],
      });

    final calls = assembler.finish();
    expect(calls.length, 1);
    expect(calls.single.id, 'call_report');
  });

  test('reassembles tool arguments from multiple JSON string fragments', () {
    final assembler = OpenAiToolCallStreamAssembler()
      ..addChunk({
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'call_read',
                  'function': {
                    'name': 'read_file',
                    'arguments': '{',
                  },
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
                  'function': {'arguments': '"path": "a/'},
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
                  'function': {'arguments': 'b/c.json", "max_bytes": 2'},
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
                  'function': {'arguments': '0}'},
                },
              ],
            },
          },
        ],
      });

    final calls = assembler.finish();
    expect(calls.length, 1);
    expect(calls.single.name, 'read_file');
    expect(calls.single.arguments['path'], 'a/b/c.json');
    expect(calls.single.arguments['max_bytes'], 20);
  });

  test('exposes streaming tool argument progress for long write_file calls',
      () {
    final assembler = OpenAiToolCallStreamAssembler()
      ..addChunk({
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'call_write',
                  'function': {
                    'name': 'write_file',
                    'arguments': '{"path":"index.html","content":"',
                  },
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
                  'function': {'arguments': 'x'.padRight(2400, 'x')},
                },
              ],
            },
          },
        ],
      });

    final progress = assembler.progress.single;
    expect(progress.index, 0);
    expect(progress.name, 'write_file');
    expect(progress.argumentChars, greaterThan(2400));
    expect(progress.key, '0:write_file');
  });

  test('builds tool result message from ActionRunner evidence', () async {
    final workspace =
        await Directory.systemTemp.createTemp('mobilecode_tool_adapter_');
    final store = ActionEvidenceStore();
    final runner =
        ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
    final adapter = OpenAiCompatibleToolCallAdapter(
      profile: ToolCallProviderProfile.detect(
        'https://api.deepseek.com',
        'deepseek-v4-pro',
      ),
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

  test(
      'tool result records adapter repair evidence when arguments are recovered',
      () async {
    final workspace = await Directory.systemTemp
        .createTemp('mobilecode_tool_adapter_repair_');
    final store = ActionEvidenceStore();
    final runner =
        ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
    final adapter = OpenAiCompatibleToolCallAdapter(
      profile: ToolCallProviderProfile.detect(
        'https://api.deepseek.com',
        'deepseek-v4-flash',
      ),
    );
    try {
      final call = const ProviderToolCall(
        id: 'call_write',
        name: 'write_file',
        arguments: {
          'content': '<!doctype html><html><body>Repair evidence</body></html>',
          'overwrite': true,
        },
      );
      final result = await runner.run(adapter.toActionSchema(call)!);

      expect(result.success, true);
      expect(result.evidence.logs.join(' '),
          contains('Adapter repaired tool arguments'));
      expect(result.evidence.metadata['adapterRepair'],
          contains('inferred safe workspace path'));
      expect(await File('${workspace.path}/index.html').exists(), true);
    } finally {
      if (await workspace.exists()) {
        await workspace.delete(recursive: true);
      }
    }
  });
}

class _FakeLarkApiService extends LarkApiService {
  _FakeLarkApiService({this.response});

  final LarkApiCallResult? response;

  @override
  Future<LarkApiConnection> loadConnection() async {
    return const LarkApiConnection(
      accessToken: 'user-access-token-for-test',
      tokenMode: LarkTokenMode.userAccessToken,
    );
  }

  @override
  Future<LarkApiCallResult> execute({
    required LarkApiConnection connection,
    required LarkApiRequestSpec spec,
  }) async {
    return response ??
        LarkApiCallResult(
          success: true,
          statusCode: 200,
          elapsedMs: 11,
          endpoint: spec.uri(connection.baseUrl).toString(),
          tokenMode: connection.tokenMode.evidenceName,
          body: '{"code":0,"msg":"ok"}',
        );
  }
}
