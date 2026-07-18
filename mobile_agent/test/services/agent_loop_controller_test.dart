import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/core/evidence/action_evidence_store.dart';
import 'package:mobile_agent/core/evidence/action_runner.dart';
import 'package:mobile_agent/core/evidence/evidence_model.dart';
import 'package:mobile_agent/services/agent_loop_controller.dart';
import 'package:mobile_agent/services/device_automation_provider.dart';
import 'package:mobile_agent/services/harness_permission_service.dart';
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
    final runner =
        ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
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
    expect(store.recent(count: 10).where((evidence) => evidence.success),
        isNotEmpty);
  });

  test('AgentLoop exposes raw_shell only in full access mode', () {
    final runner =
        ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);

    final defaultController = AgentLoopController(
      adapter: adapter,
      actionRunner: runner,
      preset: AgentPreset.autoAgent,
    );
    final fullAccessController = AgentLoopController(
      adapter: adapter,
      actionRunner: runner,
      preset: AgentPreset.autoAgent,
      permissionMode: HarnessPermissionMode.fullAccess,
    );

    expect(defaultController.allowedToolNames, isNot(contains('raw_shell')));
    expect(fullAccessController.allowedToolNames, contains('raw_shell'));
  });

  test('AgentLoop exposes cli_hub_task only when CLI Hub route is connected',
      () {
    final noCliRunner =
        ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
    final cliRunner = ActionRunner(
      workspaceRootPath: workspace.path,
      evidenceStore: store,
      cliHubTaskInvoker: (taskKind, payload) async => const {
        'success': false,
        'status': 'failed',
        'failureKind': 'dependencyMissing',
      },
    );

    final defaultController = AgentLoopController(
      adapter: adapter,
      actionRunner: noCliRunner,
      preset: AgentPreset.autoAgent,
    );
    final cliController = AgentLoopController(
      adapter: adapter,
      actionRunner: cliRunner,
      preset: AgentPreset.autoAgent,
    );

    expect(defaultController.allowedToolNames, isNot(contains('cli_hub_task')));
    expect(cliController.allowedToolNames, contains('cli_hub_task'));
    expect(cliController.allowedToolNames, isNot(contains('raw_shell')));
  });

  test('AgentLoop exposes Phone Use tools only when device route is connected',
      () {
    final noDeviceRunner =
        ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
    final deviceRunner = ActionRunner(
      workspaceRootPath: workspace.path,
      evidenceStore: store,
      deviceAutomationCoordinator: DeviceAutomationCoordinator(
        provider: EmbeddedAccessibilityDeviceAutomationProvider(),
      ),
    );

    final disconnectedController = AgentLoopController(
      adapter: adapter,
      actionRunner: noDeviceRunner,
      preset: AgentPreset.autoAgent,
    );
    final connectedController = AgentLoopController(
      adapter: adapter,
      actionRunner: deviceRunner,
      preset: AgentPreset.autoAgent,
    );

    expect(disconnectedController.allowedToolNames,
        isNot(contains('phone_use_observe')));
    expect(disconnectedController.allowedToolNames,
        isNot(contains('phone_use_action')));
    expect(connectedController.allowedToolNames, contains('phone_use_observe'));
    expect(connectedController.allowedToolNames, contains('phone_use_action'));
    expect(
      AgentPreset.autoAgent.systemInstruction,
      allOf(contains('one-shot human approval card'), contains('secret_id')),
    );
  });

  test('AgentLoop executes cli_hub_task through ActionRunner evidence bridge',
      () async {
    final runner = ActionRunner(
      workspaceRootPath: workspace.path,
      evidenceStore: store,
      cliHubTaskInvoker: (taskKind, payload) async {
        expect(taskKind, 'github_cli_auth_status');
        expect(payload['cliId'], 'github-cli');
        return const {
          'success': true,
          'status': 'authenticated',
          'taskId': 'github-auth-status-1',
          'stdout': 'Logged in to github.com as octocat',
          'stderr': '',
          'metadata': {'runtime': 'linuxSandbox'},
        };
      },
    );
    final controller = AgentLoopController(
      adapter: adapter,
      actionRunner: runner,
      preset: AgentPreset.autoAgent,
    );
    final events = <AgentLoopEvent>[];

    final result = await controller.run(
      initialMessages: const [
        {'role': 'user', 'content': '帮我看 gh 登录状态'},
      ],
      requestModel: (messages, {required round}) async {
        if (round == 1) {
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_cli_status',
                name: 'cli_hub_task',
                arguments: {
                  'cliId': 'github-cli',
                  'taskKind': 'github_cli_auth_status',
                  'payload': {},
                  'reason': 'check GitHub CLI auth status',
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
                'summary': 'GitHub CLI is authenticated.',
                'detail': 'Evidence captured from cli_hub_task.',
              },
            ),
          ],
        );
      },
      onEvent: events.add,
    );

    expect(result.usedNativeToolCalls, true);
    expect(result.toolCallCount, 2);
    expect(result.answer, contains('GitHub CLI is authenticated'));
    final evidence = store.recent(count: 5);
    expect(
      evidence.any((item) =>
          item.actionName == MobileCodeAction.cliHubTaskStart &&
          item.metadata['cliId'] == 'github-cli' &&
          item.metadata['taskKind'] == 'github_cli_auth_status'),
      isTrue,
    );
    final cliObservation = events.firstWhere((event) =>
        event.toolName == 'cli_hub_task' &&
        event.evidenceMetadata['cliId'] == 'github-cli');
    expect(cliObservation.evidenceMetadata['cliId'], 'github-cli');
    expect(
      cliObservation.evidenceMetadata['taskKind'],
      'github_cli_auth_status',
    );
    expect(cliObservation.evidenceMetadata['runtime'], 'linuxSandbox');
  });

  test('AgentLoop surfaces CLI Hub approval preview metadata without executing',
      () async {
    var runtimeCalled = false;
    final runner = ActionRunner(
      workspaceRootPath: workspace.path,
      evidenceStore: store,
      cliHubTaskInvoker: (taskKind, payload) async {
        runtimeCalled = true;
        return const {
          'success': true,
          'status': 'installed',
          'stdout': '',
          'stderr': '',
        };
      },
    );
    final controller = AgentLoopController(
      adapter: adapter,
      actionRunner: runner,
      preset: AgentPreset.autoAgent,
    );
    final events = <AgentLoopEvent>[];

    final result = await controller.run(
      initialMessages: const [
        {'role': 'user', 'content': '帮我安装 GitHub CLI'},
      ],
      onEvent: events.add,
      requestModel: (messages, {required round}) async {
        if (round == 1) {
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_cli_install_preview',
                name: 'cli_hub_task',
                arguments: {
                  'cliId': 'github-cli',
                  'taskKind': 'package_install',
                  'payload': {'profileId': 'githubCli'},
                  'reason': 'install GitHub CLI',
                },
              ),
            ],
          );
        }
        return const ProviderToolCallResponse(
          content: 'GitHub CLI install preview is waiting for approval.',
          toolCalls: [],
        );
      },
    );

    expect(result.answer, contains('waiting for approval'));
    expect(runtimeCalled, isFalse);
    final previewEvent = events.firstWhere((event) =>
        event.toolName == 'cli_hub_task' &&
        event.evidenceMetadata['status'] == 'approvalRequired');
    expect(previewEvent.evidenceMetadata['previewOnly'], true);
    expect(previewEvent.evidenceMetadata['cliId'], 'github-cli');
    expect(previewEvent.evidenceMetadata['cliTitle'], 'GitHub CLI');
    expect(previewEvent.evidenceMetadata['taskKind'], 'package_install');
    expect(previewEvent.evidenceMetadata['profileId'], 'githubCli');
    expect(previewEvent.evidenceMetadata['riskLevel'], 'high');
    expect(previewEvent.evidenceMetadata['credentialPolicy'], 'secureStorage');
    expect(previewEvent.evidenceMetadata['runtime'], 'linuxSandbox');
    expect(previewEvent.evidenceMetadata['packages'], contains('github-cli'));
    expect(
      previewEvent.evidenceMetadata['payloadPreview'],
      containsPair('profileId', 'githubCli'),
    );
  });

  test('AgentLoop executes approved CLI Hub install after preview confirmation',
      () async {
    final runtimeCalls = <Map<String, dynamic>>[];
    final runner = ActionRunner(
      workspaceRootPath: workspace.path,
      evidenceStore: store,
      cliHubTaskInvoker: (taskKind, payload) async {
        runtimeCalls.add({
          'taskKind': taskKind,
          'payload': Map<String, dynamic>.from(payload),
        });
        return const {
          'success': true,
          'status': 'installed',
          'taskId': 'github-cli-install-1',
          'stdout': 'gh version 2.93.0',
          'stderr': '',
          'metadata': {'runtime': 'linuxSandbox'},
        };
      },
    );
    final controller = AgentLoopController(
      adapter: adapter,
      actionRunner: runner,
      preset: AgentPreset.autoAgent,
    );
    final events = <AgentLoopEvent>[];

    final result = await controller.run(
      initialMessages: const [
        {'role': 'user', 'content': '帮我安装 GitHub CLI'},
      ],
      onEvent: events.add,
      requestModel: (messages, {required round}) async {
        if (round == 1) {
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_cli_install_approved',
                name: 'cli_hub_task',
                arguments: {
                  'cliId': 'github-cli',
                  'taskKind': 'package_install',
                  'payload': {
                    'profileId': 'githubCli',
                    'approved': true,
                  },
                  'reason': 'install GitHub CLI after explicit approval',
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
                'summary': 'GitHub CLI installed after approval.',
                'detail': 'Approved cli_hub_task evidence captured.',
              },
            ),
          ],
        );
      },
    );

    expect(result.answer, contains('installed after approval'));
    expect(runtimeCalls, hasLength(1));
    expect(runtimeCalls.single['taskKind'], 'package_install');
    expect(runtimeCalls.single['payload'], containsPair('cliId', 'github-cli'));
    expect(
        runtimeCalls.single['payload'], containsPair('profileId', 'githubCli'));
    expect(runtimeCalls.single['payload'], containsPair('approved', true));
    final cliEvent = events.firstWhere((event) =>
        event.toolName == 'cli_hub_task' &&
        event.evidenceMetadata['taskKind'] == 'package_install');
    expect(cliEvent.success, isTrue);
    expect(cliEvent.evidenceMetadata['status'], 'installed');
    expect(cliEvent.evidenceMetadata['runtime'], 'linuxSandbox');
    expect(
      store.recent(count: 5).any((item) =>
          item.actionName == MobileCodeAction.cliHubTaskStart &&
          item.success &&
          item.metadata['cliId'] == 'github-cli' &&
          item.metadata['taskKind'] == 'package_install'),
      isTrue,
    );
  });

  test(
      'AgentLoop returns Alpine recovery when approved CLI install needs setup',
      () async {
    final runtimeCalls = <Map<String, dynamic>>[];
    final runner = ActionRunner(
      workspaceRootPath: workspace.path,
      evidenceStore: store,
      cliHubTaskInvoker: (taskKind, payload) async {
        runtimeCalls.add({
          'taskKind': taskKind,
          'payload': Map<String, dynamic>.from(payload),
        });
        return const {
          'success': false,
          'status': 'needsSetup',
          'failureKind': ActionFailureKind.dependencyMissing,
          'taskId': 'github-cli-install-needs-setup',
          'stdout': '',
          'stderr': 'Alpine Linux Runtime is not installed.',
          'metadata': {
            'runtime': 'linuxSandbox',
            'alpineRuntime': 'needsSetup',
          },
        };
      },
    );
    final controller = AgentLoopController(
      adapter: adapter,
      actionRunner: runner,
      preset: AgentPreset.autoAgent,
    );
    final events = <AgentLoopEvent>[];

    final result = await controller.run(
      initialMessages: const [
        {'role': 'user', 'content': '用户已确认安装 GitHub CLI'},
      ],
      onEvent: events.add,
      requestModel: (messages, {required round}) async {
        if (round == 1) {
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_cli_install_without_alpine',
                name: 'cli_hub_task',
                arguments: {
                  'cliId': 'github-cli',
                  'taskKind': 'package_install',
                  'payload': {
                    'profileId': 'githubCli',
                    'approved': true,
                  },
                  'reason': 'install GitHub CLI after explicit approval',
                },
              ),
            ],
          );
        }
        return const ProviderToolCallResponse(
          content: '需要先安装或校验 Alpine Linux Runtime。',
          toolCalls: [],
        );
      },
    );

    expect(result.answer, contains('Alpine Linux Runtime'));
    expect(runtimeCalls, hasLength(1));
    expect(runtimeCalls.single['taskKind'], 'package_install');
    final evidence = store.recent(count: 5).firstWhere((item) =>
        item.actionName == MobileCodeAction.cliHubTaskStart &&
        item.metadata['taskKind'] == 'package_install');
    expect(evidence.success, isFalse);
    expect(evidence.failureKind, ActionFailureKind.dependencyMissing);
    expect(evidence.metadata['status'], 'needsSetup');
    expect(evidence.metadata['runtime'], 'linuxSandbox');
    expect(evidence.metadata['runtimeMetadata'],
        containsPair('alpineRuntime', 'needsSetup'));
    expect(
        evidence.recoveryActions.join(' '), contains('Alpine Linux Runtime'));
  });

  test('AgentLoop keeps CLI Hub install preview and approval as separate steps',
      () async {
    final runtimeCalls = <Map<String, dynamic>>[];
    final runner = ActionRunner(
      workspaceRootPath: workspace.path,
      evidenceStore: store,
      cliHubTaskInvoker: (taskKind, payload) async {
        runtimeCalls.add({
          'taskKind': taskKind,
          'payload': Map<String, dynamic>.from(payload),
        });
        return const {
          'success': true,
          'status': 'installed',
          'taskId': 'github-cli-install-approved',
          'stdout': 'gh version 2.93.0',
          'stderr': '',
          'metadata': {'runtime': 'linuxSandbox'},
        };
      },
    );
    final controller = AgentLoopController(
      adapter: adapter,
      actionRunner: runner,
      preset: AgentPreset.autoAgent,
    );
    final previewEvents = <AgentLoopEvent>[];

    final preview = await controller.run(
      initialMessages: const [
        {'role': 'user', 'content': '帮我安装 GitHub CLI'},
      ],
      onEvent: previewEvents.add,
      requestModel: (messages, {required round}) async {
        if (round == 1) {
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_cli_install_preview_two_step',
                name: 'cli_hub_task',
                arguments: {
                  'cliId': 'github-cli',
                  'taskKind': 'package_install',
                  'payload': {'profileId': 'githubCli'},
                  'reason': 'install GitHub CLI',
                },
              ),
            ],
          );
        }
        return const ProviderToolCallResponse(
          content: '等待用户确认安装 GitHub CLI。',
          toolCalls: [],
        );
      },
    );

    expect(preview.answer, contains('等待用户确认'));
    expect(runtimeCalls, isEmpty);
    final previewEvent = previewEvents.firstWhere((event) =>
        event.toolName == 'cli_hub_task' &&
        event.evidenceMetadata['status'] == 'approvalRequired');
    expect(previewEvent.evidenceMetadata['previewOnly'], true);
    expect(previewEvent.evidenceMetadata['profileId'], 'githubCli');
    expect(previewEvent.evidenceMetadata['packages'], contains('github-cli'));

    final approvedEvents = <AgentLoopEvent>[];
    final approved = await controller.run(
      initialMessages: const [
        {'role': 'user', 'content': '用户已确认安装 GitHub CLI'},
      ],
      onEvent: approvedEvents.add,
      requestModel: (messages, {required round}) async {
        if (round == 1) {
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_cli_install_approved_two_step',
                name: 'cli_hub_task',
                arguments: {
                  'cliId': 'github-cli',
                  'taskKind': 'package_install',
                  'payload': {
                    'profileId': 'githubCli',
                    'approved': true,
                  },
                  'reason': 'install GitHub CLI after user confirmation',
                },
              ),
            ],
          );
        }
        return const ProviderToolCallResponse(
          content: '',
          toolCalls: [
            ProviderToolCall(
              id: 'call_report_install_approved',
              name: 'report_result',
              arguments: {
                'status': 'success',
                'summary': 'GitHub CLI installed after explicit approval.',
                'detail': 'Approved install evidence captured.',
              },
            ),
          ],
        );
      },
    );

    expect(approved.answer, contains('installed after explicit approval'));
    expect(runtimeCalls, hasLength(1));
    expect(runtimeCalls.single['taskKind'], 'package_install');
    expect(runtimeCalls.single['payload'], containsPair('approved', true));
    expect(
        runtimeCalls.single['payload'], containsPair('profileId', 'githubCli'));
    final approvedEvent = approvedEvents.firstWhere((event) =>
        event.toolName == 'cli_hub_task' &&
        event.evidenceMetadata['taskKind'] == 'package_install');
    expect(approvedEvent.success, true);
    expect(approvedEvent.evidenceMetadata['status'], 'installed');
  });

  test('AgentLoop starts GitHub CLI login as approval preview only', () async {
    var runtimeCalled = false;
    final runner = ActionRunner(
      workspaceRootPath: workspace.path,
      evidenceStore: store,
      cliHubTaskInvoker: (taskKind, payload) async {
        runtimeCalled = true;
        return const {
          'success': true,
          'status': 'authStarted',
          'stdout': '',
          'stderr': '',
        };
      },
    );
    final controller = AgentLoopController(
      adapter: adapter,
      actionRunner: runner,
      preset: AgentPreset.autoAgent,
    );
    final events = <AgentLoopEvent>[];

    final result = await controller.run(
      initialMessages: const [
        {'role': 'user', 'content': '帮我登录 GitHub CLI'},
      ],
      onEvent: events.add,
      requestModel: (messages, {required round}) async {
        if (round == 1) {
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_github_cli_login_preview',
                name: 'cli_hub_task',
                arguments: {
                  'cliId': 'github-cli',
                  'taskKind': 'github_cli_auth_login',
                  'payload': {},
                  'reason': 'start official GitHub CLI login',
                },
              ),
            ],
          );
        }
        return const ProviderToolCallResponse(
          content: 'GitHub CLI 登录需要用户确认。',
          toolCalls: [],
        );
      },
    );

    expect(result.answer, contains('需要用户确认'));
    expect(runtimeCalled, isFalse);
    final previewEvent = events.firstWhere((event) =>
        event.toolName == 'cli_hub_task' &&
        event.evidenceMetadata['status'] == 'approvalRequired');
    expect(previewEvent.evidenceMetadata['cliId'], 'github-cli');
    expect(previewEvent.evidenceMetadata['taskKind'], 'github_cli_auth_login');
    expect(previewEvent.evidenceMetadata['previewOnly'], true);
    expect(previewEvent.evidenceMetadata['credentialPolicy'], 'secureStorage');
  });

  test('AgentLoop maps GitHub repo list intent to catalog read-only task',
      () async {
    final runtimeCalls = <Map<String, dynamic>>[];
    final runner = ActionRunner(
      workspaceRootPath: workspace.path,
      evidenceStore: store,
      cliHubTaskInvoker: (taskKind, payload) async {
        runtimeCalls.add({
          'taskKind': taskKind,
          'payload': Map<String, dynamic>.from(payload),
        });
        return const {
          'success': true,
          'status': 'succeeded',
          'taskId': 'github-repo-list-1',
          'stdout': '[{\"name\":\"mobilecode\",\"owner\":\"octocat\"}]',
          'stderr': '',
          'metadata': {
            'runtime': 'linuxSandbox',
            'commandId': 'repo_list',
            'limit': 10,
          },
        };
      },
    );
    final controller = AgentLoopController(
      adapter: adapter,
      actionRunner: runner,
      preset: AgentPreset.autoAgent,
    );
    final events = <AgentLoopEvent>[];

    final result = await controller.run(
      initialMessages: const [
        {'role': 'user', 'content': '列出我的 GitHub repo'},
      ],
      onEvent: events.add,
      requestModel: (messages, {required round}) async {
        if (round == 1) {
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_repo_list',
                name: 'cli_hub_task',
                arguments: {
                  'cliId': 'github-cli',
                  'taskKind': 'github_cli_execute',
                  'payload': {
                    'commandId': 'repo_list',
                    'limit': 10,
                  },
                  'reason': 'list GitHub repositories',
                },
              ),
            ],
          );
        }
        final toolMessage =
            messages.lastWhere((message) => message['role'] == 'tool');
        final payload = jsonDecode(toolMessage['content'].toString())
            as Map<String, dynamic>;
        expect(payload['success'], true);
        expect(payload['metadata']['commandId'], 'repo_list');
        expect(payload['metadata']['stdout'], contains('mobilecode'));
        expect(payload['metadata'].toString(), isNot(contains('command:')));
        expect(payload['metadata'].toString(), isNot(contains('shell')));

        return const ProviderToolCallResponse(
          content: '',
          toolCalls: [
            ProviderToolCall(
              id: 'call_report',
              name: 'report_result',
              arguments: {
                'status': 'success',
                'summary': 'GitHub repositories listed.',
                'detail': 'Used catalog read-only repo_list typed task.',
              },
            ),
          ],
        );
      },
    );

    expect(result.answer, contains('GitHub repositories listed'));
    expect(runtimeCalls, hasLength(1));
    expect(runtimeCalls.single['taskKind'], 'github_cli_execute');
    expect(runtimeCalls.single['payload'], containsPair('cliId', 'github-cli'));
    expect(
        runtimeCalls.single['payload'], containsPair('commandId', 'repo_list'));
    expect(runtimeCalls.single['payload'], containsPair('limit', 10));
    expect(runtimeCalls.single['payload'], isNot(contains('command')));
    expect(runtimeCalls.single['payload'], isNot(contains('shell')));
    final cliEvent = events.firstWhere((event) =>
        event.type == AgentLoopEventType.observation &&
        event.toolName == 'cli_hub_task' &&
        event.evidenceMetadata['taskKind'] == 'github_cli_execute');
    expect(cliEvent.success, isTrue);
    expect(cliEvent.evidenceMetadata['commandId'], 'repo_list');
    expect(cliEvent.evidenceMetadata['runtime'], 'linuxSandbox');
  });

  test('AgentLoop maps non-GitHub business intents to catalog read-only tasks',
      () async {
    final cases = [
      {
        'user': '列出 Google Drive 文件',
        'cliId': 'google-workspace-cli',
        'taskKind': 'gws_cli_execute',
        'commandId': 'drive_files_list',
        'limitKey': 'pageSize',
        'summary': 'Google Drive files listed.',
      },
      {
        'user': '看最近邮件',
        'cliId': 'agent-mail-cli',
        'taskKind': 'agently_cli_execute',
        'commandId': 'message_list',
        'limitKey': 'limit',
        'summary': 'Agent Mail messages listed.',
      },
      {
        'user': '列出 Lark Wiki 空间',
        'cliId': 'lark-cli',
        'taskKind': 'lark_cli_execute',
        'commandId': 'wiki_space_list',
        'limitKey': 'pageSize',
        'summary': 'Lark Wiki spaces listed.',
      },
    ];

    for (final item in cases) {
      final runtimeCalls = <Map<String, dynamic>>[];
      final runner = ActionRunner(
        workspaceRootPath: workspace.path,
        evidenceStore: store,
        cliHubTaskInvoker: (taskKind, payload) async {
          runtimeCalls.add({
            'taskKind': taskKind,
            'payload': Map<String, dynamic>.from(payload),
          });
          return {
            'success': true,
            'status': 'succeeded',
            'taskId': '${item['commandId']}-1',
            'stdout': 'item for user@example.test phone +1 415 555 0100',
            'stderr': '',
            'metadata': {
              'runtime': 'linuxSandbox',
              'commandId': item['commandId'],
            },
          };
        },
      );
      final controller = AgentLoopController(
        adapter: adapter,
        actionRunner: runner,
        preset: AgentPreset.autoAgent,
      );
      final events = <AgentLoopEvent>[];

      final result = await controller.run(
        initialMessages: [
          {'role': 'user', 'content': item['user']},
        ],
        onEvent: events.add,
        requestModel: (messages, {required round}) async {
          if (round == 1) {
            return ProviderToolCallResponse(
              content: '',
              toolCalls: [
                ProviderToolCall(
                  id: 'call_${item['commandId']}',
                  name: 'cli_hub_task',
                  arguments: {
                    'cliId': item['cliId'],
                    'taskKind': item['taskKind'],
                    'payload': {
                      'commandId': item['commandId'],
                      item['limitKey']!: 10,
                    },
                    'reason': 'run ${item['commandId']}',
                  },
                ),
              ],
            );
          }
          final toolMessage =
              messages.lastWhere((message) => message['role'] == 'tool');
          final payload = jsonDecode(toolMessage['content'].toString())
              as Map<String, dynamic>;
          expect(payload['success'], true);
          expect(payload['metadata']['commandId'], item['commandId']);
          expect(payload['metadata']['stdout'], contains('[REDACTED_EMAIL]'));
          expect(payload['metadata']['stdout'], contains('[REDACTED_PHONE]'));
          expect(payload['metadata']['stdout'], isNot(contains('@example')));
          expect(payload['metadata'].toString(), isNot(contains('command:')));
          expect(payload['metadata'].toString(), isNot(contains('shell')));

          return ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_report_${item['commandId']}',
                name: 'report_result',
                arguments: {
                  'status': 'success',
                  'summary': item['summary'],
                  'detail': 'Used catalog read-only typed task.',
                },
              ),
            ],
          );
        },
      );

      expect(result.answer, contains(item['summary'].toString()));
      expect(runtimeCalls, hasLength(1));
      expect(runtimeCalls.single['taskKind'], item['taskKind']);
      expect(
          runtimeCalls.single['payload'], containsPair('cliId', item['cliId']));
      expect(runtimeCalls.single['payload'],
          containsPair('commandId', item['commandId']));
      expect(runtimeCalls.single['payload'], isNot(contains('command')));
      expect(runtimeCalls.single['payload'], isNot(contains('shell')));
      final cliEvent = events.firstWhere((event) =>
          event.type == AgentLoopEventType.observation &&
          event.toolName == 'cli_hub_task' &&
          event.evidenceMetadata['taskKind'] == item['taskKind']);
      expect(cliEvent.success, isTrue);
      expect(cliEvent.evidenceMetadata['commandId'], item['commandId']);
      expect(cliEvent.evidenceMetadata['stdout'], contains('[REDACTED_EMAIL]'));
      expect(cliEvent.evidenceMetadata['stdout'], contains('[REDACTED_PHONE]'));
      expect(cliEvent.evidenceMetadata['stdout'], isNot(contains('@example')));
    }
  });

  test('AgentLoop returns provider login recovery for unauthenticated CLI task',
      () async {
    final runner = ActionRunner(
      workspaceRootPath: workspace.path,
      evidenceStore: store,
      cliHubTaskInvoker: (taskKind, payload) async {
        expect(taskKind, 'gws_cli_execute');
        expect(payload['commandId'], 'drive_files_list');
        return const {
          'success': false,
          'status': 'authFailed',
          'failureKind': 'authFailed',
          'taskId': 'gws-drive-auth-failed',
          'stdout': '',
          'stderr': 'Please login as user@example.test before listing files.',
        };
      },
    );
    final controller = AgentLoopController(
      adapter: adapter,
      actionRunner: runner,
      preset: AgentPreset.autoAgent,
    );
    final events = <AgentLoopEvent>[];

    final result = await controller.run(
      initialMessages: const [
        {'role': 'user', 'content': '列出 Google Drive 文件'},
      ],
      onEvent: events.add,
      requestModel: (messages, {required round}) async {
        if (round == 1) {
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_drive_files',
                name: 'cli_hub_task',
                arguments: {
                  'cliId': 'google-workspace-cli',
                  'taskKind': 'gws_cli_execute',
                  'payload': {
                    'commandId': 'drive_files_list',
                    'pageSize': 10,
                  },
                  'reason': 'list Google Drive files',
                },
              ),
            ],
          );
        }

        final toolMessage =
            messages.lastWhere((message) => message['role'] == 'tool');
        final payload = jsonDecode(toolMessage['content'].toString())
            as Map<String, dynamic>;
        expect(payload['success'], false);
        expect(payload['failureKind'], ActionFailureKind.authFailed);
        expect(
          payload['recoveryActions'].toString(),
          contains('Run the official login task for Google Workspace CLI'),
        );
        expect(payload['metadata'].toString(), isNot(contains('@example')));
        expect(payload['text'].toString(), contains('[REDACTED_EMAIL]'));

        return const ProviderToolCallResponse(
          content: '',
          toolCalls: [
            ProviderToolCall(
              id: 'call_report_drive_auth',
              name: 'report_result',
              arguments: {
                'status': 'blocked',
                'summary': 'Google Drive listing needs official login.',
                'detail': 'Provider-specific recovery was returned.',
              },
            ),
          ],
        );
      },
    );

    expect(result.answer, contains('needs official login'));
    final failedEvent = events.firstWhere((event) =>
        event.type == AgentLoopEventType.failed &&
        event.toolName == 'cli_hub_task');
    expect(failedEvent.success, isFalse);
    expect(failedEvent.evidenceMetadata['status'], 'authfailed');
    expect(
        failedEvent.evidenceMetadata['stderr'], contains('[REDACTED_EMAIL]'));
    expect(store.failures().single.failureKind, ActionFailureKind.authFailed);
  });

  test('Reviewer preset blocks write_file and records failed evidence',
      () async {
    final runner =
        ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
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
    expect(
        store.failures().single.failureKind, ActionFailureKind.commandBlocked);
  });

  test('Reviewer preset blocks apply_patch mutations', () async {
    final runner =
        ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
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
                  'patch':
                      '--- a/a.txt\n+++ b/a.txt\n@@ -0,0 +1,1 @@\n+blocked',
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
    expect(
        store.failures().single.failureKind, ActionFailureKind.commandBlocked);
  });

  test(
      'Auto preset lets the model choose web and file tools without a fixed sequence',
      () async {
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
    expect(store.recent(count: 10).map((evidence) => evidence.actionName),
        contains(MobileCodeAction.webSearch));
    expect(store.recent(count: 10).map((evidence) => evidence.actionName),
        contains(MobileCodeAction.writeFile));
  });

  test('filters relay-backed web tools when no managed relay is configured',
      () async {
    final runner =
        ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
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
                'detail':
                    'Agent should continue with local tools or ask for relay configuration.',
              },
            ),
          ],
        );
      },
    );

    expect(result.answer, contains('Web tools were unavailable'));
    expect(store.failures().single.logs.join(' '), contains('not allowed'));
  });

  test(
      'builder writes HTML when provider omits path but sends complete content',
      () async {
    final runner =
        ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
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
                  'content':
                      '<!doctype html><html><body>Default path</body></html>',
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
    expect(await File('${workspace.path}/index.html').readAsString(),
        contains('Default path'));
  });

  test('Repair preset can find, read, patch, preview, and report', () async {
    final file = File('${workspace.path}/repair/index.html');
    await file.parent.create(recursive: true);
    await file.writeAsString('<h1>Broken</h1>\n<p>Keep</p>');
    final runner =
        ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
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
                arguments: {
                  'pattern': '*.html',
                  'path': '.',
                  'max_results': 10
                },
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
                  'patch':
                      '--- a/repair/index.html\n+++ b/repair/index.html\n@@ -1,2 +1,2 @@\n-<h1>Broken</h1>\n+<h1>Fixed</h1>\n <p>Keep</p>',
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
    expect(store.recent(count: 10).map((evidence) => evidence.actionName),
        contains(MobileCodeAction.applyPatch));
  });

  test(
      'invalid patch is reported as a safe block instead of a run failure event',
      () async {
    final file = File('${workspace.path}/safe/index.html');
    await file.parent.create(recursive: true);
    await file.writeAsString('<h1>Existing</h1>');
    final runner =
        ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
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
                  'patch':
                      '--- a/safe/index.html\n+++ b/safe/index.html\n@@ ... @@\n-<h1>Existing</h1>\n+<h1>Fixed</h1>',
                  'reason': 'model emitted an invalid hunk placeholder',
                },
              ),
            ],
          );
        }
        return const ProviderToolCallResponse(
          content:
              'Cannot apply the patch until the model sends real hunk coordinates.',
          toolCalls: [],
        );
      },
    );

    expect(result.answer, contains('Cannot apply'));
    expect(events.map((event) => event.type),
        contains(AgentLoopEventType.blocked));
    expect(events.map((event) => event.type),
        isNot(contains(AgentLoopEventType.failed)));
    expect(
        store.failures().single.failureKind, ActionFailureKind.commandBlocked);
  });

  test('invalid apply_patch is actionable and a later valid patch can proceed',
      () async {
    final file = File('${workspace.path}/safe_recover/index.html');
    await file.parent.create(recursive: true);
    await file.writeAsString('<h1>Existing</h1>');
    final runner =
        ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
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
                  'patch':
                      '--- a/safe_recover/index.html\n+++ b/safe_recover/index.html\n@@ ... @@\n-<h1>Existing</h1>\n+<h1>Recovered</h1>',
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
                  'patch':
                      '--- a/safe_recover/index.html\n+++ b/safe_recover/index.html\n@@ -1,1 +1,1 @@\n-<h1>Existing</h1>\n+<h1>Recovered</h1>',
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
    final blockedEvents = events
        .where((event) => event.type == AgentLoopEventType.blocked)
        .toList();
    expect(blockedEvents.length, 1);
    final blockedMessage = blockedEvents.first.message;
    expect(blockedMessage, contains('failureKind=commandBlocked'));
    expect(blockedMessage, contains('toolName=apply_patch'));
    expect(blockedMessage, contains('blockedCount=1'));
    expect(blockedMessage, contains('safeNextAction'));
    expect(blockedMessage, contains('recoveryContract'));
    expect(blockedMessage, contains('read_file'));
    expect(blockedMessage, contains('write_file'));
    expect(blockedMessage, contains('unified diff headers'));
  });

  test('repeated blocked apply_patch asks for a strategy switch', () async {
    final file = File('${workspace.path}/safe_repeat/index.html');
    await file.parent.create(recursive: true);
    await file.writeAsString('<h1>Existing</h1>');
    final runner =
        ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
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
                  'patch':
                      '--- a/safe_repeat/index.html\n+++ b/safe_repeat/index.html\n@@ ... @@\n-<h1>Existing</h1>\n+<h1>Recovered</h1>',
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
    final blocked = events
        .where((event) => event.type == AgentLoopEventType.blocked)
        .toList();
    expect(blocked.length, 2);
    expect(blocked[1].message, contains('Switch strategy'));
    expect(blocked[1].message, contains('blockedCount=2'));
    expect(blocked[1].message, contains('Do not resend the same apply_patch'));
    final toolObservations = round3Messages!
        .where((message) => message['role'] == 'tool')
        .map((message) => message['content'].toString())
        .join(' ');
    expect(toolObservations, contains('Switch strategy'));
    expect(toolObservations, contains('read_file'));
    expect(toolObservations, contains('write_file'));
    expect(store.failures(), isNotEmpty);
  });

  test('repeated blocked write_file escalates to read_file first strategy',
      () async {
    final runner =
        ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
    final controller = AgentLoopController(
      adapter: adapter,
      actionRunner: runner,
      preset: AgentPreset.builder,
      maxRounds: 3,
    );
    final events = <AgentLoopEvent>[];
    final result = await controller.run(
      initialMessages: const [
        {
          'role': 'user',
          'content': 'run repeated write_file with invalid args'
        },
      ],
      onEvent: events.add,
      requestModel: (messages, {required round}) async {
        if (round <= 2) {
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_repeat_write',
                name: 'write_file',
                arguments: {
                  'content': '<h1>broken</h1>',
                },
              ),
            ],
          );
        }
        return const ProviderToolCallResponse(
          content: 'write_file must recover with read_file guidance.',
          toolCalls: [],
        );
      },
    );

    expect(result.answer,
        contains('write_file must recover with read_file guidance.'));
    final blocked = events
        .where((event) => event.type == AgentLoopEventType.blocked)
        .toList();
    expect(blocked, hasLength(2));
    expect(blocked[1].message, contains('Switch strategy'));
    expect(blocked[1].message, contains('read_file'));
    expect(blocked[1].message, contains('apply_patch'));
  });

  test('invalid apply_patch can recover with complete write_file replacement',
      () async {
    final file = File('${workspace.path}/safe_write_recover/index.html');
    await file.parent.create(recursive: true);
    await file.writeAsString('<h1>Broken</h1>');
    final runner =
        ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
    final controller = AgentLoopController(
      adapter: adapter,
      actionRunner: runner,
      preset: AgentPreset.repair,
      maxRounds: 3,
    );
    final events = <AgentLoopEvent>[];

    final result = await controller.run(
      initialMessages: const [
        {'role': 'user', 'content': 'repair the small html artifact'},
      ],
      onEvent: events.add,
      requestModel: (messages, {required round}) async {
        if (round == 1) {
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_bad_patch_then_write',
                name: 'apply_patch',
                arguments: {
                  'patch':
                      '--- a/safe_write_recover/index.html\n+++ b/safe_write_recover/index.html\n@@ ... @@\n-<h1>Broken</h1>\n+<h1>Recovered</h1>',
                },
              ),
            ],
          );
        }
        if (round == 2) {
          final observations = messages
              .where((message) => message['role'] == 'tool')
              .map((message) => message['content'].toString())
              .join(' ');
          expect(observations, contains('write_file'));
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_complete_write_recovery',
                name: 'write_file',
                arguments: {
                  'path': 'safe_write_recover/index.html',
                  'content': '<h1>Recovered via write_file</h1>',
                  'overwrite': true,
                },
              ),
            ],
          );
        }
        return const ProviderToolCallResponse(
          content: 'Recovered with complete write_file after blocked patch.',
          toolCalls: [],
        );
      },
    );

    expect(result.answer, contains('Recovered with complete write_file'));
    expect(await file.readAsString(), contains('Recovered via write_file'));
    final blocked = events
        .where((event) => event.type == AgentLoopEventType.blocked)
        .toList();
    expect(blocked, hasLength(1));
    expect(blocked.single.message, contains('complete write_file'));
  });

  test('missing write_file path is reported with clear blocked observation',
      () async {
    final runner =
        ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
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
    final blocked = events
        .where((event) => event.type == AgentLoopEventType.blocked)
        .toList();
    expect(blocked, isNotEmpty);
    expect(blocked.first.message, contains('failureKind=commandBlocked'));
    expect(blocked.first.message, contains('toolName=write_file'));
    expect(blocked.first.message, contains('blockedCount=1'));
    expect(blocked.first.message, contains('safeNextAction'));
    expect(blocked.first.message, contains('recoveryContract'));
    expect(blocked.first.message, contains('path'));
    expect(blocked.first.message, contains('path=index.html'));
  });

  test('Sub-Agent Lite open eval close returns read-only mailbox observations',
      () async {
    await File('${workspace.path}/index.html')
        .writeAsString('<h1>MobileCode</h1>');
    final runner =
        ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
    final controller = AgentLoopController(
      adapter: adapter,
      actionRunner: runner,
      preset: AgentPreset.reviewer,
      maxRounds: 4,
    );
    final events = <AgentLoopEvent>[];
    String? agentId;

    String readAgentIdFromLastTool(List<Map<String, dynamic>> messages) {
      final toolMessage =
          messages.lastWhere((message) => message['role'] == 'tool');
      final resultPayload =
          jsonDecode(toolMessage['content'].toString()) as Map<String, dynamic>;
      final sessionPayload =
          jsonDecode(resultPayload['text'].toString()) as Map<String, dynamic>;
      return sessionPayload['agent_id'].toString();
    }

    final result = await controller.run(
      initialMessages: const [
        {
          'role': 'user',
          'content': 'open a read-only explorer and summarize files'
        },
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
                  'timeout_ms': 10000,
                  'token_budget': 1200,
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
    expect(events.map((event) => event.roleName).whereType<String>().join(' '),
        contains('Explorer sub-agent'));
    expect(store.recent(count: 20).map((evidence) => evidence.evidenceId),
        contains('call_agent_open'));
  });

  test('Sub-Agent Lite v2 limits background workers to two concurrent sessions',
      () async {
    final runner =
        ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
    final controller = AgentLoopController(
      adapter: adapter,
      actionRunner: runner,
      preset: AgentPreset.autoAgent,
      maxRounds: 2,
    );

    final result = await controller.run(
      initialMessages: const [
        {'role': 'user', 'content': 'open several read-only workers'},
      ],
      requestModel: (messages, {required round}) async {
        if (round == 1) {
          return const ProviderToolCallResponse(
            content: '',
            toolCalls: [
              ProviderToolCall(
                id: 'call_agent_open_1',
                name: 'agent_open',
                arguments: {
                  'role': 'explorer',
                  'task': 'Inspect root one.',
                  'path': '.',
                  'focus': '',
                  'timeout_ms': 10000,
                  'token_budget': 1200,
                },
              ),
              ProviderToolCall(
                id: 'call_agent_open_2',
                name: 'agent_open',
                arguments: {
                  'role': 'reviewer',
                  'task': 'Inspect root two.',
                  'path': '.',
                  'focus': '',
                  'timeout_ms': 10000,
                  'token_budget': 1200,
                },
              ),
              ProviderToolCall(
                id: 'call_agent_open_3',
                name: 'agent_open',
                arguments: {
                  'role': 'explorer',
                  'task': 'This third worker should be blocked.',
                  'path': '.',
                  'focus': '',
                  'timeout_ms': 10000,
                  'token_budget': 1200,
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
                'summary': 'Concurrent worker limit was enforced.',
                'detail':
                    'Only two read-only background workers may run at once.',
              },
            ),
          ],
        );
      },
    );

    expect(result.answer, contains('Concurrent worker limit was enforced'));
    final failures = store.failures();
    expect(failures, isNotEmpty);
    expect(failures.map((evidence) => evidence.logs.join(' ')).join(' '),
        contains('at most 2 concurrent'));
  });

  test('Sub-Agent Lite blocks non-read-only roles', () async {
    final runner =
        ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
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
                  'timeout_ms': 10000,
                  'token_budget': 1200,
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
    expect(events.map((event) => event.type),
        contains(AgentLoopEventType.blocked));
    expect(
        store.failures().single.failureKind, ActionFailureKind.commandBlocked);
    expect(store.failures().single.logs.join(' '),
        contains('read-only explorer or reviewer'));
  });

  test('Sub-Agent Lite tools still obey preset allow-list', () async {
    final runner =
        ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
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
                  'timeout_ms': 10000,
                  'token_budget': 1200,
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
    expect(events.map((event) => event.type),
        contains(AgentLoopEventType.blocked));
    expect(
        store.failures().single.failureKind, ActionFailureKind.commandBlocked);
    expect(store.failures().single.logs.join(' '),
        contains('not allowed for Builder'));
  });

  test(
      'agent loop appends assistant tool-call message with reasoning before tool results',
      () async {
    final runner =
        ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
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
          fail(
              'Expected second round to include assistant tool-call and tool result history.');
        }

        final assistantMessages = loopMessages
            .where((message) =>
                message['role'] == 'assistant' && message['tool_calls'] != null)
            .toList();
        expect(assistantMessages, isNotEmpty);
        expect(assistantMessages.first.containsKey('finish_reason'), false);
        expect(assistantMessages.first['reasoning_content'],
            'Create index file first.');
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

  test('blocks repeated write_file after a successful write until verification',
      () async {
    final runner =
        ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
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
    expect(await File('${workspace.path}/repeat/index.html').readAsString(),
        contains('First'));
    expect(store.failures().single.logs.join(' '),
        contains('already changed successfully'));
  });
}
