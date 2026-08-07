import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/core/evidence/action_evidence_store.dart';
import 'package:mobile_agent/core/evidence/action_runner.dart';
import 'package:mobile_agent/core/evidence/evidence_model.dart';
import 'package:mobile_agent/services/device_automation_provider.dart';
import 'package:mobile_agent/services/html_render_provider.dart';

class _FakeHtmlRenderProvider implements HtmlRenderProvider {
  _FakeHtmlRenderProvider(this.artifactPath);

  final String artifactPath;

  @override
  Future<HtmlRenderArtifact> render(HtmlRenderRequest request) async {
    return HtmlRenderArtifact(
      path: artifactPath,
      format: request.format,
      mimeType: 'image/png',
      bytes: 4,
      sha256: 'fake-sha256',
      width: request.viewportWidth,
      height: request.viewportHeight,
      backend: 'fake_webview',
    );
  }
}

class _FakeDeviceAutomationProvider
    implements DeviceAutomationProvider, DeviceAutomationRiskClassifier {
  final List<DeviceAutomationRequest> requests = [];
  final List<DeviceAutomationRequest> riskRequests = [];

  @override
  String get name => 'action-runner-fake-device';

  @override
  DeviceAutomationProviderType get type =>
      DeviceAutomationProviderType.agentDeviceQa;

  @override
  Future<DeviceAutomationProviderResult> execute(
    DeviceAutomationRequest request,
  ) async {
    requests.add(request);
    return const DeviceAutomationProviderResult(
      success: true,
      data: {
        'status': 'passed',
        'accepted': true,
        'preSnapshotDigest': 'pre-runner',
        'postSnapshotDigest': 'post-runner',
        'redactionApplied': true,
      },
    );
  }

  @override
  Future<DeviceAutomationRiskAssessment> classifyRisk(
    DeviceAutomationRequest request,
  ) async {
    riskRequests.add(request);
    return const DeviceAutomationRiskAssessment(
      success: true,
      trusted: true,
      riskClass: DeviceAutomationRiskClass.reversible,
      policyId: 'phone_use_transaction_risk_v1',
      reason: 'trusted_policy_reversible_action',
      previewDigest:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      frameDigest:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      targetLabel: 'Continue',
      targetLabelHash:
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
    );
  }

  @override
  Future<DeviceAutomationHealth> healthCheck() async =>
      const DeviceAutomationHealth(
        available: true,
        ready: true,
        state: 'ready',
        failureKind: null,
        recoveryActions: [],
        capabilities: DeviceAutomationCapabilities(
          semanticSnapshots: true,
          semanticRefs: true,
          coordinateActions: true,
          screenshots: true,
          video: true,
          logs: true,
          replay: true,
          physicalDevices: true,
          simulators: true,
        ),
      );
}

void main() {
  late Directory workspace;
  late ActionEvidenceStore store;
  late ActionRunner runner;

  setUp(() async {
    workspace =
        await Directory.systemTemp.createTemp('mobilecode_action_runner_');
    store = ActionEvidenceStore();
    runner = ActionRunner(
      workspaceRootPath: workspace.path,
      evidenceStore: store,
    );
  });

  tearDown(() async {
    if (await workspace.exists()) {
      await workspace.delete(recursive: true);
    }
  });

  test('writeFile writes inside workspace and records evidence', () async {
    final result = await runner.run(ActionSchema(
      actionName: MobileCodeAction.writeFile,
      paramsSummary: 'write hello.txt',
      params: const {
        'path': 'hello.txt',
        'content': 'hello mobile',
      },
      requestId: 'ev-write',
    ));

    expect(result.success, true);
    expect(result.evidence.evidenceId, 'ev-write');
    expect(result.evidence.actionName, MobileCodeAction.writeFile);
    expect(result.evidence.artifactPaths.single, result.path);
    expect(await File(result.path!).readAsString(), 'hello mobile');
    expect(store.getById('ev-write'), isNotNull);
  });

  test('readFile returns text and records bounded preview metadata', () async {
    final file = File('${workspace.path}/notes.md');
    await file.writeAsString('alpha beta gamma');

    final result = await runner.run(ActionSchema(
      actionName: MobileCodeAction.readFile,
      params: const {'path': 'notes.md'},
      requestId: 'ev-read',
    ));

    expect(result.success, true);
    expect(result.text, 'alpha beta gamma');
    expect(result.evidence.metadata['relativePath'], 'notes.md');
    expect(result.evidence.metadata['contentPreview'], 'alpha beta gamma');
    expect(store.getById('ev-read'), isNotNull);
  });

  test('listFiles returns workspace-bounded entries and evidence', () async {
    final file = File('${workspace.path}/demo/index.html');
    await file.parent.create(recursive: true);
    await file.writeAsString('<!doctype html>');

    final result = await runner.run(ActionSchema(
      actionName: MobileCodeAction.listFiles,
      params: const {
        'path': '.',
        'recursive': true,
        'maxEntries': 20,
      },
      requestId: 'ev-list',
    ));

    expect(result.success, true);
    expect(result.text, contains('demo${Platform.pathSeparator}index.html'));
    expect(result.evidence.actionName, MobileCodeAction.listFiles);
    expect(result.evidence.metadata['entries'], isNotEmpty);
    expect(store.getById('ev-list'), isNotNull);
  });

  test('findFiles returns bounded glob matches inside workspace', () async {
    await File('${workspace.path}/demo/index.html').create(recursive: true);
    await File('${workspace.path}/demo/app.js').create(recursive: true);

    final result = await runner.run(ActionSchema(
      actionName: MobileCodeAction.findFiles,
      params: const {
        'path': '.',
        'pattern': '*.html',
        'maxResults': 10,
      },
      requestId: 'ev-find',
    ));

    expect(result.success, true);
    expect(result.text, contains('index.html'));
    expect(result.text, isNot(contains('app.js')));
    expect(result.evidence.actionName, MobileCodeAction.findFiles);
    expect(store.getById('ev-find'), isNotNull);
  });

  test('grepFiles finds text matches and records no-match evidence', () async {
    final file = File('${workspace.path}/demo/index.html');
    await file.parent.create(recursive: true);
    await file
        .writeAsString('<h1>Animal island</h1>\n<p>Touch friendly preview</p>');

    final hit = await runner.run(ActionSchema(
      actionName: MobileCodeAction.grepFiles,
      params: const {
        'path': '.',
        'query': 'island',
        'includeGlob': '*.html',
        'maxResults': 10,
        'maxBytes': 4096,
      },
      requestId: 'ev-grep-hit',
    ));
    final miss = await runner.run(ActionSchema(
      actionName: MobileCodeAction.grepFiles,
      params: const {
        'path': '.',
        'query': 'missing-word',
        'includeGlob': '*.html',
        'maxResults': 10,
        'maxBytes': 4096,
      },
      requestId: 'ev-grep-miss',
    ));

    expect(hit.success, true);
    expect(hit.text, contains('demo${Platform.pathSeparator}index.html:1'));
    expect(hit.evidence.metadata['results'], isNotEmpty);
    expect(miss.success, true);
    expect(miss.text, contains('No matches'));
  });

  test('copyFile copies one workspace file and records evidence', () async {
    final source = File('${workspace.path}/draft.html');
    await source.writeAsString('<!doctype html><title>Draft</title>');

    final result = await runner.run(ActionSchema(
      actionName: MobileCodeAction.copyFile,
      params: const {
        'sourcePath': 'draft.html',
        'destinationPath': 'backup/draft.html',
        'overwrite': false,
      },
      requestId: 'ev-copy',
    ));

    expect(result.success, true);
    expect(await source.exists(), true);
    expect(await File('${workspace.path}/backup/draft.html').readAsString(),
        contains('Draft'));
    expect(result.evidence.actionName, MobileCodeAction.copyFile);
    expect(result.evidence.metadata['sourcePath'], 'draft.html');
    expect(store.getById('ev-copy'), isNotNull);
  });

  test('makeDirectory creates nested workspace directory', () async {
    final result = await runner.run(ActionSchema(
      actionName: MobileCodeAction.makeDirectory,
      params: const {
        'path': 'generated/assets/icons',
        'recursive': true,
      },
      requestId: 'ev-mkdir',
    ));

    expect(result.success, true);
    expect(await Directory('${workspace.path}/generated/assets/icons').exists(),
        true);
    expect(result.evidence.actionName, MobileCodeAction.makeDirectory);
    expect(store.getById('ev-mkdir'), isNotNull);
  });

  test('deleteFile requires confirmation and saves pre-delete snapshot',
      () async {
    final file = File('${workspace.path}/old.txt');
    await file.writeAsString('remove me safely');

    final blocked = await runner.run(ActionSchema(
      actionName: MobileCodeAction.deleteFile,
      params: const {
        'path': 'old.txt',
        'confirm': false,
      },
      requestId: 'ev-delete-blocked',
    ));
    final deleted = await runner.run(ActionSchema(
      actionName: MobileCodeAction.deleteFile,
      params: const {
        'path': 'old.txt',
        'confirm': true,
      },
      requestId: 'ev-delete',
    ));

    expect(blocked.success, false);
    expect(blocked.evidence.failureKind, ActionFailureKind.commandBlocked);
    expect(deleted.success, true);
    expect(await file.exists(), false);
    expect(await File(deleted.path!).readAsString(), 'remove me safely');
    expect(deleted.path, contains('.mobilecode_delete_snapshots'));
    expect(deleted.evidence.actionName, MobileCodeAction.deleteFile);
  });

  test('moveFile renames one file inside workspace', () async {
    final file = File('${workspace.path}/draft.html');
    await file.writeAsString('<!doctype html><title>Draft</title>');

    final result = await runner.run(ActionSchema(
      actionName: MobileCodeAction.moveFile,
      params: const {
        'sourcePath': 'draft.html',
        'destinationPath': 'published/index.html',
        'overwrite': false,
      },
      requestId: 'ev-move',
    ));

    expect(result.success, true);
    expect(await file.exists(), false);
    expect(await File('${workspace.path}/published/index.html').readAsString(),
        contains('Draft'));
    expect(result.evidence.actionName, MobileCodeAction.moveFile);
    expect(result.evidence.metadata['sourcePath'], 'draft.html');
    expect(store.getById('ev-move'), isNotNull);
  });

  test('saveSnapshot and virtualDiff compare workspace changes without shell',
      () async {
    final file = File('${workspace.path}/demo/index.html');
    await file.parent.create(recursive: true);
    await file.writeAsString('<h1>Before</h1>\n<p>Keep</p>');

    final snapshot = await runner.run(ActionSchema(
      actionName: MobileCodeAction.saveSnapshot,
      params: const {
        'path': 'demo',
        'label': 'before heading change',
        'maxFiles': 10,
        'maxBytes': 4096,
      },
      requestId: 'ev-save-snapshot',
    ));
    final snapshotPayload = jsonDecode(snapshot.text!) as Map<String, dynamic>;
    await file.writeAsString('<h1>After</h1>\n<p>Keep</p>');

    final diff = await runner.run(ActionSchema(
      actionName: MobileCodeAction.virtualDiff,
      params: {
        'path': 'demo',
        'snapshotId': snapshotPayload['snapshotId'],
        'maxBytes': 4096,
      },
      requestId: 'ev-virtual-diff',
    ));

    expect(snapshot.success, true);
    expect(snapshotPayload['fileCount'], 1);
    expect(diff.success, true);
    expect(diff.text, contains('-<h1>Before</h1>'));
    expect(diff.text, contains('+<h1>After</h1>'));
    expect(diff.evidence.actionName, MobileCodeAction.virtualDiff);
  });

  test('restoreSnapshot restores confirmed files and backs up current versions',
      () async {
    final file = File('${workspace.path}/demo/index.html');
    await file.parent.create(recursive: true);
    await file.writeAsString('<h1>Before</h1>\n<p>Keep</p>');
    final snapshot = await runner.run(ActionSchema(
      actionName: MobileCodeAction.saveSnapshot,
      params: const {
        'path': 'demo',
        'label': 'before restore',
        'maxFiles': 10,
        'maxBytes': 4096,
      },
      requestId: 'ev-restore-save',
    ));
    final snapshotPayload = jsonDecode(snapshot.text!) as Map<String, dynamic>;
    await file.writeAsString('<h1>Broken</h1>\n<p>Keep</p>');

    final blocked = await runner.run(ActionSchema(
      actionName: MobileCodeAction.restoreSnapshot,
      params: {
        'path': 'demo',
        'snapshotId': snapshotPayload['snapshotId'],
        'confirm': false,
      },
      requestId: 'ev-restore-blocked',
    ));
    final restored = await runner.run(ActionSchema(
      actionName: MobileCodeAction.restoreSnapshot,
      params: {
        'path': 'demo',
        'snapshotId': snapshotPayload['snapshotId'],
        'confirm': true,
        'maxFiles': 10,
        'maxBytes': 4096,
      },
      requestId: 'ev-restore',
    ));

    expect(blocked.success, false);
    expect(blocked.evidence.failureKind, ActionFailureKind.commandBlocked);
    expect(restored.success, true);
    expect(await file.readAsString(), '<h1>Before</h1>\n<p>Keep</p>');
    expect(restored.evidence.actionName, MobileCodeAction.restoreSnapshot);
    expect(restored.evidence.metadata['restoredFiles'], isNotEmpty);
    expect(restored.evidence.metadata['backupFiles'], isNotEmpty);
  });

  test('projectSummary returns compact entrypoints and extension counts',
      () async {
    final file = File('${workspace.path}/demo/index.html');
    await file.parent.create(recursive: true);
    await file.writeAsString('<!doctype html><title>Demo</title>');
    await File('${workspace.path}/demo/app.js')
        .writeAsString('console.log("hi");');

    final result = await runner.run(ActionSchema(
      actionName: MobileCodeAction.projectSummary,
      params: const {
        'path': 'demo',
        'maxDepth': 2,
        'maxFiles': 20,
      },
      requestId: 'ev-summary',
    ));

    expect(result.success, true);
    expect(result.text, contains('Project summary'));
    expect(result.text, contains('index.html'));
    expect(result.evidence.metadata['entrypoints'],
        contains('demo${Platform.pathSeparator}index.html'));
    expect(result.evidence.actionName, MobileCodeAction.projectSummary);
  });

  test('changeHistory and virtualStatus expose writes and restore points',
      () async {
    final file = File('${workspace.path}/demo/index.html');
    await file.parent.create(recursive: true);
    await file.writeAsString('<h1>Before</h1>');
    final snapshot = await runner.run(ActionSchema(
      actionName: MobileCodeAction.saveSnapshot,
      params: const {
        'path': 'demo',
        'label': 'history baseline',
        'maxFiles': 10,
        'maxBytes': 4096,
      },
      requestId: 'ev-history-snapshot',
    ));
    final write = await runner.run(ActionSchema(
      actionName: MobileCodeAction.writeFile,
      params: const {
        'path': 'demo/index.html',
        'content': '<h1>After</h1>',
        'overwrite': true,
      },
      requestId: 'ev-history-write',
    ));

    final history = await runner.run(ActionSchema(
      actionName: MobileCodeAction.changeHistory,
      params: const {'count': 10, 'includeReadOnly': false},
      requestId: 'ev-history',
    ));
    final status = await runner.run(ActionSchema(
      actionName: MobileCodeAction.virtualStatus,
      params: const {
        'path': 'demo',
        'maxFiles': 20,
        'maxRecent': 10,
      },
      requestId: 'ev-status',
    ));

    expect(snapshot.success, true);
    expect(write.success, true);
    expect(history.success, true);
    expect(history.text, contains('writeFile ok'));
    expect(history.text, contains('saveSnapshot ok'));
    expect(history.evidence.metadata['records'], isNotEmpty);
    expect(status.success, true);
    expect(status.text, contains('Restore points'));
    expect(status.text, contains('Recent changes'));
    expect(status.evidence.metadata['restorePoints'], isNotEmpty);
  });

  test('detectProjectType identifies static web and Flutter signals', () async {
    await File('${workspace.path}/demo/index.html').create(recursive: true);
    await File('${workspace.path}/demo/pubspec.yaml')
        .writeAsString('name: demo\n');
    await File('${workspace.path}/demo/lib/main.dart').create(recursive: true);

    final result = await runner.run(ActionSchema(
      actionName: MobileCodeAction.detectProjectType,
      params: const {
        'path': 'demo',
        'maxDepth': 4,
        'maxFiles': 40,
      },
      requestId: 'ev-detect-project',
    ));

    expect(result.success, true);
    expect(result.text, contains('flutter'));
    expect(result.text, contains('static_web'));
    expect(result.evidence.metadata['projectTypes'], contains('flutter'));
    expect(result.evidence.metadata['projectTypes'], contains('static_web'));
  });

  test(
      'validateHtml reports mobile readiness warnings without executing scripts',
      () async {
    final file = File('${workspace.path}/demo/index.html');
    await file.parent.create(recursive: true);
    await file.writeAsString(
        '<html><head><title>Demo</title></head><body><h1>Hello</h1></body></html>');

    final result = await runner.run(ActionSchema(
      actionName: MobileCodeAction.validateHtml,
      params: const {
        'path': 'demo/index.html',
        'maxBytes': 4096,
      },
      requestId: 'ev-validate-html',
    ));

    expect(result.success, true);
    expect(result.text, contains('missing_doctype'));
    expect(result.text, contains('missing_viewport'));
    expect(result.evidence.metadata['issueCount'], greaterThanOrEqualTo(2));
    expect(result.evidence.metadata['hasStructuralIssues'], isTrue);
    expect(result.evidence.metadata['issueSeverityCount'], isNotEmpty);
    expect(result.evidence.logs.join('\n'), contains('Top issues'));
    expect(result.evidence.actionName, MobileCodeAction.validateHtml);
  });

  test(
      'validateJson and validateMarkdown report structure issues without shell',
      () async {
    final jsonFile = File('${workspace.path}/data/config.json');
    await jsonFile.parent.create(recursive: true);
    await jsonFile.writeAsString('{"name": "demo", "items": [1, 2]}');
    final badMarkdown = File('${workspace.path}/README.md');
    await badMarkdown.writeAsString(
        '## Missing top heading\n#### Jumped\nSee https://example.com\n');

    final jsonResult = await runner.run(ActionSchema(
      actionName: MobileCodeAction.validateJson,
      params: const {
        'path': 'data/config.json',
        'maxBytes': 4096,
      },
      requestId: 'ev-json-valid',
    ));
    final markdownResult = await runner.run(ActionSchema(
      actionName: MobileCodeAction.validateMarkdown,
      params: const {
        'path': 'README.md',
        'maxBytes': 4096,
      },
      requestId: 'ev-md-issues',
    ));

    expect(jsonResult.success, true);
    expect(jsonResult.text, contains('JSON validation passed'));
    expect(jsonResult.evidence.metadata['valid'], true);
    expect(markdownResult.success, true);
    expect(markdownResult.text, contains('missing_h1'));
    expect(markdownResult.text, contains('bare_url'));
    expect(markdownResult.evidence.metadata['issueCount'],
        greaterThanOrEqualTo(2));
  });

  test(
      'validateJson reports invalid JSON as validation metadata, not shell failure',
      () async {
    final result = await runner.run(ActionSchema(
      actionName: MobileCodeAction.validateJson,
      params: const {
        'json': '{"broken":',
        'maxBytes': 4096,
      },
      requestId: 'ev-json-invalid',
    ));

    expect(result.success, true);
    expect(result.text, contains('syntax issue'));
    expect(result.evidence.metadata['valid'], false);
  });

  test('applyPatch modifies an existing file with snapshot evidence', () async {
    final file = File('${workspace.path}/demo/index.html');
    await file.parent.create(recursive: true);
    await file.writeAsString('<h1>Old</h1>\n<p>Keep</p>');
    const patch = '''
--- a/demo/index.html
+++ b/demo/index.html
@@ -1,2 +1,2 @@
-<h1>Old</h1>
+<h1>New</h1>
 <p>Keep</p>''';

    final result = await runner.run(ActionSchema(
      actionName: MobileCodeAction.applyPatch,
      params: const {
        'patch': patch,
        'reason': 'update heading',
      },
      requestId: 'ev-patch',
    ));

    expect(result.success, true);
    expect(await file.readAsString(), '<h1>New</h1>\n<p>Keep</p>');
    expect(result.evidence.actionName, MobileCodeAction.applyPatch);
    expect(result.evidence.metadata['changedFiles'],
        contains('demo${Platform.pathSeparator}index.html'));
    expect(
        result.evidence.logs.join(' '), contains('Saved 1 pre-patch snapshot'));
  });

  test('applyPatch creates a new text file', () async {
    const patch = '''
--- /dev/null
+++ b/new-note.txt
@@ -0,0 +1,2 @@
+hello
+mobile''';

    final result = await runner.run(ActionSchema(
      actionName: MobileCodeAction.applyPatch,
      params: const {
        'patch': patch,
        'reason': 'create note',
      },
      requestId: 'ev-patch-create',
    ));

    expect(result.success, true);
    expect(await File('${workspace.path}/new-note.txt').readAsString(),
        'hello\nmobile');
  });

  test('applyPatch rejects deletion and outside workspace paths', () async {
    final deleteResult = await runner.run(ActionSchema(
      actionName: MobileCodeAction.applyPatch,
      params: const {
        'patch': '--- a/old.txt\n+++ /dev/null\n@@ -1,1 +0,0 @@\n-old',
        'reason': 'delete',
      },
      requestId: 'ev-patch-delete',
    ));
    final outsideResult = await runner.run(ActionSchema(
      actionName: MobileCodeAction.applyPatch,
      params: const {
        'patch':
            '--- a/../escape.txt\n+++ b/../escape.txt\n@@ -0,0 +1,1 @@\n+bad',
        'reason': 'escape',
      },
      requestId: 'ev-patch-outside',
    ));

    expect(deleteResult.success, false);
    expect(deleteResult.evidence.failureKind, ActionFailureKind.commandBlocked);
    expect(outsideResult.success, false);
    expect(outsideResult.evidence.failureKind,
        ActionFailureKind.cwdOutsideWorkspace);
  });

  test('applyPatch rejects oversized patches', () async {
    final hugePatch =
        '--- a/a.txt\n+++ b/a.txt\n@@ -0,0 +1,1 @@\n+${List.filled(90 * 1024, 'x').join()}';

    final result = await runner.run(ActionSchema(
      actionName: MobileCodeAction.applyPatch,
      params: {
        'patch': hugePatch,
        'reason': 'too large',
      },
      requestId: 'ev-patch-large',
    ));

    expect(result.success, false);
    expect(result.evidence.failureKind, ActionFailureKind.commandBlocked);
  });

  test('termuxTaskStart fails closed without helper and never runs raw shell',
      () async {
    final unavailable = await runner.run(ActionSchema(
      actionName: MobileCodeAction.termuxTaskStart,
      params: const {
        'taskKind': 'project_check',
        'path': '.',
        'argsJson': '{}',
        'timeoutMs': 30000,
        'maxOutputBytes': 4096,
        'reason': 'verify workspace',
      },
      requestId: 'ev-termux-unavailable',
    ));
    final blockedRaw = await runner.run(ActionSchema(
      actionName: MobileCodeAction.termuxTaskStart,
      params: const {
        'taskKind': 'ls && rm -rf',
        'path': '.',
        'argsJson': '{}',
      },
      requestId: 'ev-termux-raw',
    ));

    expect(unavailable.success, false);
    expect(
        unavailable.evidence.failureKind, ActionFailureKind.dependencyMissing);
    expect(unavailable.text, contains('No raw shell was executed'));
    expect(unavailable.evidence.metadata['taskKind'], 'project_check');
    expect(blockedRaw.success, false);
    expect(blockedRaw.evidence.failureKind, ActionFailureKind.commandBlocked);
  });

  test('termuxTaskStart records taskId stdout stderr from typed helper',
      () async {
    final termuxRunner = ActionRunner(
      workspaceRootPath: workspace.path,
      evidenceStore: store,
      termuxTaskInvoker: (taskKind, payload) async {
        expect(taskKind, 'validate');
        expect(payload['path'], '.');
        return const {
          'taskId': 'task-123',
          'success': true,
          'exitCode': 0,
          'stdout': 'validated',
          'stderr': '',
        };
      },
    );

    final result = await termuxRunner.run(ActionSchema(
      actionName: MobileCodeAction.termuxTaskStart,
      params: const {
        'taskKind': 'validate',
        'path': '.',
        'argsJson': '{"entry":"index.html"}',
        'timeoutMs': 30000,
        'maxOutputBytes': 4096,
        'reason': 'typed validation',
      },
      requestId: 'ev-termux-ok',
    ));

    expect(result.success, true);
    expect(result.text, contains('taskId=task-123'));
    expect(result.evidence.metadata['stdout'], 'validated');
    expect(result.evidence.exitCode, 0);
    expect(result.evidence.metadata['status'], 'completed');
  });

  test('termuxTaskStart rejects shell-style args payload keys', () async {
    final termuxRunner =
        ActionRunner(workspaceRootPath: workspace.path, evidenceStore: store);
    final result = await termuxRunner.run(ActionSchema(
      actionName: MobileCodeAction.termuxTaskStart,
      params: const {
        'taskKind': 'validate',
        'path': '.',
        'argsJson': '{"command":"echo blocked"}',
      },
      requestId: 'ev-termux-guard',
    ));

    expect(result.success, false);
    expect(result.evidence.failureKind, ActionFailureKind.commandBlocked);
    expect(result.evidence.recoveryActions.join(' '),
        contains('Do not pass command'));
  });

  test('cliHubTaskStart fails closed without Linux Sandbox route', () async {
    final result = await runner.run(ActionSchema(
      actionName: MobileCodeAction.cliHubTaskStart,
      params: const {
        'cliId': 'github-cli',
        'taskKind': 'github_cli_auth_status',
        'payload': {},
        'reason': 'check gh login',
      },
      requestId: 'ev-cli-hub-unavailable',
    ));

    expect(result.success, false);
    expect(result.evidence.failureKind, ActionFailureKind.dependencyMissing);
    expect(result.evidence.metadata['status'], 'needsSetup');
    expect(result.evidence.metadata['cliId'], 'github-cli');
    expect(result.text, contains('No raw shell was executed'));
  });

  test('cliHubTaskStart records redacted result from typed runtime', () async {
    late String capturedTaskKind;
    late Map<String, dynamic> capturedPayload;
    final cliRunner = ActionRunner(
      workspaceRootPath: workspace.path,
      evidenceStore: store,
      cliHubTaskInvoker: (taskKind, payload) async {
        capturedTaskKind = taskKind;
        capturedPayload = Map<String, dynamic>.from(payload);
        return const {
          'taskId': 'cli-123',
          'success': true,
          'status': 'completed',
          'exitCode': 0,
          'stdout': 'Logged in to github.com as octo',
          'stderr': '',
        };
      },
    );

    final result = await cliRunner.run(ActionSchema(
      actionName: MobileCodeAction.cliHubTaskStart,
      params: const {
        'cliId': 'github-cli',
        'taskKind': 'github_cli_auth_status',
        'payload': {},
        'reason': 'check gh login',
        'maxOutputBytes': 4096,
      },
      requestId: 'ev-cli-hub-ok',
    ));

    if (!result.success) {
      fail(result.evidence.toJson().toString());
    }
    expect(result.success, true);
    expect(capturedTaskKind, 'github_cli_auth_status');
    expect(capturedPayload['cliId'], 'github-cli');
    expect(capturedPayload['access'], 'readOnly');
    expect(result.evidence.actionName, MobileCodeAction.cliHubTaskStart);
    expect(result.evidence.metadata['taskId'], 'cli-123');
    expect(result.evidence.metadata['stdout'], contains('Logged in'));
    expect(
        result.text, contains('github-cli.github_cli_auth_status completed'));
  });

  test('cliHubTaskStart rejects unknown catalog task and unsafe payload',
      () async {
    final badTask = await runner.run(ActionSchema(
      actionName: MobileCodeAction.cliHubTaskStart,
      params: const {
        'cliId': 'github-cli',
        'taskKind': 'gh auth token',
        'payload': {},
      },
      requestId: 'ev-cli-hub-bad-task',
    ));
    final badPayload = await runner.run(ActionSchema(
      actionName: MobileCodeAction.cliHubTaskStart,
      params: const {
        'cliId': 'github-cli',
        'taskKind': 'github_cli_auth_status',
        'payload': {'command': 'gh auth token'},
      },
      requestId: 'ev-cli-hub-bad-payload',
    ));

    expect(badTask.success, false);
    expect(badTask.evidence.failureKind, ActionFailureKind.commandBlocked);
    expect(badPayload.success, false);
    expect(badPayload.evidence.failureKind, ActionFailureKind.commandBlocked);
    expect(badPayload.evidence.logs.join(' '), contains('payload.command'));
  });

  test('cliHubTaskStart supports install login and business typed tasks',
      () async {
    final calls = <String>[];
    final cliRunner = ActionRunner(
      workspaceRootPath: workspace.path,
      evidenceStore: store,
      cliHubTaskInvoker: (taskKind, payload) async {
        calls.add(
          '$taskKind:${payload['cliId']}:${payload['profileId'] ?? ''}:${payload['commandId'] ?? ''}',
        );
        return {
          'taskId': 'task-${calls.length}',
          'success': false,
          'status': 'failed',
          'failureKind': payload['requiresApproval'] == true
              ? 'approvalRequired'
              : 'dependencyMissing',
          'stderr': payload['requiresApproval'] == true
              ? 'approval required'
              : 'missing runtime',
          'metadata': {
            if (payload['commandId'] != null) 'commandId': payload['commandId'],
          },
        };
      },
    );

    final install = await cliRunner.run(ActionSchema(
      actionName: MobileCodeAction.cliHubTaskStart,
      params: const {
        'cliId': 'github-cli',
        'taskKind': 'package_install',
        'payload': {},
        'reason': 'install GitHub CLI',
      },
      requestId: 'ev-cli-install',
    ));
    final login = await cliRunner.run(ActionSchema(
      actionName: MobileCodeAction.cliHubTaskStart,
      params: const {
        'cliId': 'github-cli',
        'taskKind': 'github_cli_auth_login',
        'payload': {'approved': true},
        'reason': 'login GitHub CLI',
      },
      requestId: 'ev-cli-login',
    ));
    final repoList = await cliRunner.run(ActionSchema(
      actionName: MobileCodeAction.cliHubTaskStart,
      params: const {
        'cliId': 'github-cli',
        'taskKind': 'github_cli_execute',
        'payload': {'approved': true},
        'reason': 'list repos',
      },
      requestId: 'ev-cli-repos',
    ));

    expect(install.evidence.failureKind, 'approvalRequired');
    expect(install.evidence.metadata['status'], 'approvalRequired');
    expect(install.evidence.metadata['previewOnly'], true);
    expect(install.evidence.metadata['profileId'], 'githubCli');
    expect(install.evidence.metadata['packages'], contains('github-cli'));
    expect(install.evidence.metadata['estimatedDownloadMb'], greaterThan(0));
    expect(install.evidence.metadata['installedSizeMb'], greaterThan(0));
    expect(
      install.evidence.metadata['approval'],
      containsPair('required', true),
    );
    expect(login.evidence.failureKind, 'approvalRequired');
    expect(repoList.evidence.failureKind, 'dependencyMissing');
    expect(
      repoList.evidence.metadata['runtimeMetadata'],
      containsPair('commandId', 'repo_list'),
    );
    expect(
      calls,
      [
        'github_cli_auth_login:github-cli:githubCli:',
        'github_cli_execute:github-cli:githubCli:repo_list',
      ],
    );
  });

  test('cliHubTaskStart redacts auth output credentials and env paths',
      () async {
    final cliRunner = ActionRunner(
      workspaceRootPath: workspace.path,
      evidenceStore: store,
      cliHubTaskInvoker: (taskKind, payload) async {
        expect(taskKind, 'github_cli_auth_login');
        expect(payload['approved'], true);
        return const {
          'taskId': 'login-redaction',
          'success': false,
          'status': 'authFailed',
          'failureKind': ActionFailureKind.authFailed,
          'stdout':
              'Open https://github.com/login/device and enter oauth_code=ABCD-1234; token=ghp_secret1234567890; config=/tmp/project/.env.local',
          'stderr':
              'cookie: session=secret authorization=Bearer sk-secret1234567890',
          'metadata': {
            'loginUrl': 'https://github.com/login/device',
            'oauth_code': 'ABCD-1234',
            'cookie': 'session=secret',
            'envPath': '/tmp/project/.env.local',
          },
        };
      },
    );

    final result = await cliRunner.run(ActionSchema(
      actionName: MobileCodeAction.cliHubTaskStart,
      params: const {
        'cliId': 'github-cli',
        'taskKind': 'github_cli_auth_login',
        'payload': {'approved': true},
        'reason': 'login GitHub CLI',
        'maxOutputBytes': 4096,
      },
      requestId: 'ev-cli-login-redaction',
    ));

    final serialized = [
      result.text,
      result.evidence.logs.join('\n'),
      jsonEncode(result.evidence.metadata),
    ].join('\n');

    expect(result.success, false);
    expect(result.evidence.failureKind, ActionFailureKind.authFailed);
    expect(serialized, isNot(contains('ABCD-1234')));
    expect(serialized, isNot(contains('ghp_secret1234567890')));
    expect(serialized, isNot(contains('sk-secret1234567890')));
    expect(serialized, isNot(contains('session=secret')));
    expect(serialized, isNot(contains('.env.local')));
    expect(serialized, contains('[REDACTED]'));
    expect(serialized, contains('[REDACTED_ENV]'));
  });

  test('cliHubTaskStart only executes approval tasks after explicit approval',
      () async {
    final calls = <String>[];
    final cliRunner = ActionRunner(
      workspaceRootPath: workspace.path,
      evidenceStore: store,
      cliHubTaskInvoker: (taskKind, payload) async {
        calls.add('$taskKind:${payload['approved']}');
        return {
          'taskId': 'approved-${calls.length}',
          'success': true,
          'status': 'completed',
          'exitCode': 0,
          'stdout': 'installed',
          'stderr': '',
        };
      },
    );

    final preview = await cliRunner.run(ActionSchema(
      actionName: MobileCodeAction.cliHubTaskStart,
      params: const {
        'cliId': 'github-cli',
        'taskKind': 'package_install',
        'payload': {},
        'reason': 'install GitHub CLI',
      },
      requestId: 'ev-cli-install-preview',
    ));
    final approved = await cliRunner.run(ActionSchema(
      actionName: MobileCodeAction.cliHubTaskStart,
      params: const {
        'cliId': 'github-cli',
        'taskKind': 'package_install',
        'payload': {'approved': true},
        'reason': 'install GitHub CLI',
      },
      requestId: 'ev-cli-install-approved',
    ));
    final cancelled = await cliRunner.run(ActionSchema(
      actionName: MobileCodeAction.cliHubTaskStart,
      params: const {
        'cliId': 'github-cli',
        'taskKind': 'github_cli_auth_login',
        'payload': {'cancelled': true},
        'reason': 'login GitHub CLI',
      },
      requestId: 'ev-cli-login-cancelled',
    ));

    expect(preview.success, false);
    expect(preview.evidence.failureKind, 'approvalRequired');
    expect(preview.evidence.metadata['previewOnly'], true);
    expect(approved.success, true);
    expect(approved.evidence.metadata['taskId'], 'approved-1');
    expect(cancelled.success, false);
    expect(cancelled.evidence.failureKind, ActionFailureKind.cancelled);
    expect(cancelled.evidence.metadata['status'], 'cancelled');
    expect(calls, ['package_install:true']);
  });

  test('cliHubTaskStart bounds business read-only output and redacts PII',
      () async {
    Map<String, dynamic>? capturedPayload;
    final cliRunner = ActionRunner(
      workspaceRootPath: workspace.path,
      evidenceStore: store,
      cliHubTaskInvoker: (taskKind, payload) async {
        capturedPayload = Map<String, dynamic>.from(payload);
        return {
          'taskId': 'repo-list-1',
          'success': true,
          'status': 'completed',
          'exitCode': 0,
          'stdout':
              'repo mobilecode owner user@example.test phone +1 415 555 0100 ${List.filled(3000, 'x').join()}',
          'stderr': '',
          'metadata': {'items': 100},
        };
      },
    );

    final result = await cliRunner.run(ActionSchema(
      actionName: MobileCodeAction.cliHubTaskStart,
      params: const {
        'cliId': 'github-cli',
        'taskKind': 'github_cli_execute',
        'payload': {
          'approved': true,
          'limit': 500,
        },
        'maxOutputBytes': 1024,
        'reason': 'list repos',
      },
      requestId: 'ev-cli-repos-paged',
    ));

    expect(result.success, true);
    expect(capturedPayload?['limit'], 50);
    expect(result.evidence.metadata['outputLimitBytes'], 1024);
    expect(result.evidence.metadata['stdoutTruncated'], true);
    expect(result.evidence.metadata['stdout'], contains('[REDACTED_EMAIL]'));
    expect(result.evidence.metadata['stdout'], contains('[REDACTED_PHONE]'));
    expect(result.evidence.metadata['stdout'], isNot(contains('@example')));
    expect(
      result.evidence.metadata['pagination'],
      containsPair('pageSize', 50),
    );
    expect(result.evidence.metadata['piiRedaction'], 'basic-email-phone');
  });

  test('previewHtml from inline html writes preview file and returns file url',
      () async {
    final result = await runner.run(ActionSchema(
      actionName: MobileCodeAction.previewHtml,
      params: const {'html': '<!doctype html><title>Hi</title>'},
      requestId: 'ev-preview',
    ));

    expect(result.success, true);
    expect(result.path, endsWith('index.html'));
    expect(result.url, startsWith('file:'));
    expect(
        await File(result.path!).readAsString(), contains('<title>Hi</title>'));
    expect(result.evidence.urls.single, result.url);
    expect(store.getById('ev-preview'), isNotNull);
  });

  test('webSearch calls injected relay tool and records compact results',
      () async {
    final webRunner = ActionRunner(
      workspaceRootPath: workspace.path,
      evidenceStore: store,
      webToolInvoker: (toolName, payload) async {
        expect(toolName, 'web_search');
        expect(payload['query'], 'mobile 3d landing page');
        return {
          'source': 'fake',
          'results': [
            {
              'refId': 'web_1',
              'title': 'Mobile 3D reference',
              'url': 'https://example.com/3d',
              'snippet': 'Touch-friendly 3D landing page ideas.',
            },
          ],
        };
      },
    );

    final result = await webRunner.run(ActionSchema(
      actionName: MobileCodeAction.webSearch,
      params: const {'query': 'mobile 3d landing page', 'count': 3},
      requestId: 'ev-search',
    ));

    expect(result.success, true);
    expect(result.text, contains('web_1'));
    expect(result.evidence.urls.single, 'https://example.com/3d');
    expect(result.evidence.metadata['source'], 'fake');
    expect(store.getById('ev-search'), isNotNull);
  });

  test('fetchUrl rejects non-public or non-https URLs before relay call',
      () async {
    var called = false;
    final webRunner = ActionRunner(
      workspaceRootPath: workspace.path,
      evidenceStore: store,
      webToolInvoker: (toolName, payload) async {
        called = true;
        return const <String, dynamic>{};
      },
    );

    final result = await webRunner.run(ActionSchema(
      actionName: MobileCodeAction.fetchUrl,
      params: const {'url': 'http://localhost:8080', 'maxBytes': 4096},
      requestId: 'ev-fetch-blocked',
    ));

    expect(called, false);
    expect(result.success, false);
    expect(result.evidence.failureKind, ActionFailureKind.commandBlocked);
  });

  test('previewSnapshot saves metadata artifact for local html', () async {
    final file = File('${workspace.path}/demo/index.html');
    await file.parent.create(recursive: true);
    await file.writeAsString(
        '<!doctype html><html><head><title>Island</title></head><body><h1>3D Island</h1></body></html>');

    final result = await runner.run(ActionSchema(
      actionName: MobileCodeAction.previewSnapshot,
      params: const {
        'path': 'demo/index.html',
        'viewportWidth': 390,
        'viewportHeight': 844,
      },
      requestId: 'ev-snapshot',
    ));

    expect(result.success, true);
    expect(result.path, endsWith('.json'));
    final snapshot = jsonDecode(await File(result.path!).readAsString())
        as Map<String, dynamic>;
    expect(snapshot['title'], 'Island');
    expect(snapshot['bodyTextPreview'], contains('3D Island'));
    expect(snapshot['status'], 'metadata_captured');
    expect(snapshot['captureMode'], 'metadata');
    expect(snapshot['artifactType'], 'json');
    expect(snapshot['bitmapCaptured'], false);
    expect(snapshot.containsKey('bitmapPath'), false);
    expect(snapshot['source'], 'file');
    expect(snapshot['path'], 'demo/index.html');
    expect(snapshot['viewport']['width'], 390);
    expect(snapshot['viewport']['height'], 844);
    expect(result.evidence.metadata['source'], 'file');
    expect(result.evidence.metadata['status'], 'metadata_captured');
    expect(result.evidence.metadata['captureMode'], 'metadata');
    expect(result.evidence.logs,
        contains('No native bitmap screenshot was captured for this action.'));
    expect(result.evidence.artifactPaths.length, 2);
    expect(store.getById('ev-snapshot'), isNotNull);
  });

  test('previewSnapshot copies a real renderer artifact into evidence',
      () async {
    final source = File('${workspace.path}/demo/index.html');
    await source.parent.create(recursive: true);
    await source.writeAsString(
        '<!doctype html><title>Island</title><body><h1>3D Island</h1></body>');
    final nativePng = File('${workspace.path}/native-preview.png');
    await nativePng.writeAsBytes(<int>[137, 80, 78, 71]);
    final bitmapRunner = ActionRunner(
      workspaceRootPath: workspace.path,
      evidenceStore: store,
      htmlRenderProvider: _FakeHtmlRenderProvider(nativePng.path),
    );

    final result = await bitmapRunner.run(ActionSchema(
      actionName: MobileCodeAction.previewSnapshot,
      params: const {
        'path': 'demo/index.html',
        'viewportWidth': 390,
        'viewportHeight': 844,
      },
      requestId: 'ev-bitmap-snapshot',
    ));

    expect(result.success, true);
    final snapshot = jsonDecode(await File(result.path!).readAsString())
        as Map<String, dynamic>;
    expect(snapshot['status'], 'bitmap_captured');
    expect(snapshot['captureMode'], 'fake_webview');
    expect(snapshot['artifactType'], 'png');
    expect(snapshot['bitmapCaptured'], true);
    expect(snapshot['bitmapPath'], contains('.mobilecode_preview_snapshots'));
    expect(snapshot['bitmapMimeType'], 'image/png');
    expect(snapshot['bitmapBytes'], 4);
    expect(snapshot['bitmapSha256'], 'fake-sha256');
    expect(result.evidence.artifactPaths.length, 3);
    expect(result.evidence.logs,
        contains('Captured native HTML bitmap for demo/index.html.'));
    expect(
        result.evidence.logs,
        isNot(contains(
            'No native bitmap screenshot was captured for this action.')));
    expect(await File('${workspace.path}/${snapshot['bitmapPath']}').exists(),
        true);
  });

  test('rejects paths outside workspace', () async {
    final outside = File('${workspace.parent.path}/outside.txt');
    if (await outside.exists()) {
      await outside.delete();
    }

    final result = await runner.run(ActionSchema(
      actionName: MobileCodeAction.writeFile,
      params: {
        'path': outside.path,
        'content': 'nope',
      },
      requestId: 'ev-outside',
    ));

    expect(result.success, false);
    expect(result.evidence.failureKind, ActionFailureKind.cwdOutsideWorkspace);
    expect(await outside.exists(), false);
    expect(store.getById('ev-outside')!.success, false);
  });

  test('rawShell runCommand schema records approval gate without execution',
      () async {
    final result = await runner.run(ActionSchema(
      actionName: MobileCodeAction.runCommand,
      paramsSummary: 'provider-native raw_shell preview',
      approvalRequired: true,
      risk: ActionRisk.high,
      params: const {
        'command': 'rm -rf .',
        'cwd': '.',
        'timeoutMs': 30000,
        'reason': 'user selected full access',
        'requiresSecondApproval': true,
      },
      requestId: 'ev-raw-shell-preview',
    ));

    expect(result.success, false);
    expect(result.evidence.actionName, MobileCodeAction.runCommand);
    expect(result.evidence.failureKind, ActionFailureKind.commandBlocked);
    expect(result.evidence.paramsSummary, 'provider-native raw_shell preview');
    expect(result.evidence.logs.single, contains('requires approval'));
    expect(result.evidence.recoveryActions.join(' '),
        contains('Approve the action before running it'));
    expect(
      store
          .recent(count: 5)
          .where((item) => item.actionName == MobileCodeAction.cliHubTaskStart),
      isEmpty,
    );
  });

  test('phone-use action keeps request correlation and one runner-store record',
      () async {
    final provider = _FakeDeviceAutomationProvider();
    final coordinatorStore = ActionEvidenceStore();
    final phoneRunner = ActionRunner(
      workspaceRootPath: workspace.path,
      evidenceStore: store,
      deviceAutomationCoordinator: DeviceAutomationCoordinator(
        provider: provider,
        evidenceStore: coordinatorStore,
      ),
    );

    final result = await phoneRunner.run(ActionSchema(
      actionName: MobileCodeAction.phoneUseAct,
      requestId: 'ev-phone-ref',
      paramsSummary: 'approved ref tap',
      params: const {
        'action': 'tapRef',
        'targetRef': '@e2~s4',
        'approved': true,
        'approvalSource': 'approval_queue',
      },
    ));

    expect(result.success, isTrue);
    expect(result.evidence.evidenceId, 'ev-phone-ref');
    expect(provider.requests.single.targetRef, '@e2~s4');
    expect(store.getById('ev-phone-ref'), same(result.evidence));
    expect(coordinatorStore, isEmpty);
  });

  test('phone-use model action creates a one-shot preview without executing',
      () async {
    final provider = _FakeDeviceAutomationProvider();
    final tickets = DeviceAutomationApprovalTicketStore();
    final phoneRunner = ActionRunner(
      workspaceRootPath: workspace.path,
      evidenceStore: store,
      deviceAutomationCoordinator: DeviceAutomationCoordinator(
        provider: provider,
        approvalTickets: tickets,
      ),
    );

    final result = await phoneRunner.run(ActionSchema(
      actionName: MobileCodeAction.phoneUseAct,
      requestId: 'ev-phone-preview',
      approvalRequired: true,
      params: const {
        'action': 'tapRef',
        'targetRef': '@e3~s9',
        'approvalPreview': true,
        'approved': false,
      },
    ));

    expect(result.success, isFalse);
    expect(result.evidence.failureKind, 'approval_required');
    expect(provider.riskRequests, hasLength(1));
    expect(provider.requests, isEmpty);
    expect(
      result.evidence.metadata['approvalTicket'],
      allOf(isA<Map>(), containsPair('oneShot', true)),
    );
  });

  test('critical phone-use action requires digest-bound transaction approval',
      () async {
    final provider = _FakeDeviceAutomationProvider();
    final phoneRunner = ActionRunner(
      workspaceRootPath: workspace.path,
      evidenceStore: store,
      deviceAutomationCoordinator: DeviceAutomationCoordinator(
        provider: provider,
      ),
    );

    final result = await phoneRunner.run(ActionSchema(
      actionName: MobileCodeAction.phoneUseAct,
      requestId: 'ev-phone-critical-blocked',
      risk: ActionRisk.critical,
      paramsSummary: 'final external transaction',
      params: const {
        'action': 'tapRef',
        'targetRef': '@e9~s12',
        'approved': true,
      },
    ));

    expect(result.success, isFalse);
    expect(result.evidence.failureKind, 'transaction_approval_required');
    expect(provider.requests, isEmpty);
    expect(
      result.evidence.metadata['transactionApproval'],
      containsPair('required', true),
    );
  });

  test('critical phone-use action forwards matching transaction approval',
      () async {
    final provider = _FakeDeviceAutomationProvider();
    final phoneRunner = ActionRunner(
      workspaceRootPath: workspace.path,
      evidenceStore: store,
      deviceAutomationCoordinator: DeviceAutomationCoordinator(
        provider: provider,
      ),
    );

    final result = await phoneRunner.run(ActionSchema(
      actionName: MobileCodeAction.phoneUseAct,
      requestId: 'ev-phone-critical-approved',
      risk: ActionRisk.critical,
      paramsSummary: 'approved final external transaction',
      params: const {
        'action': 'tapRef',
        'targetRef': '@e9~s12',
        'approved': true,
        'transactionPreviewDigest': 'aabbccdd',
        'transactionApprovalDigest': 'aabbccdd',
        'transactionApprovalId': 'approval-final-1',
      },
    ));

    expect(result.success, isTrue);
    expect(provider.requests.single.riskClass,
        DeviceAutomationRiskClass.externalTransaction);
    expect(provider.requests.single.transactionApprovalSatisfied, isTrue);
    expect(
      result.evidence.metadata['transactionApproval'],
      containsPair('digestMatched', true),
    );
  });

  test('unsupported action fails closed', () async {
    final result = await runner.run(ActionSchema(
      actionName: MobileCodeAction.runCommand,
      paramsSummary: 'run pwd',
      params: const {'command': 'pwd'},
      requestId: 'ev-command',
    ));

    expect(result.success, false);
    expect(result.evidence.failureKind, ActionFailureKind.commandBlocked);
    expect(
        result.evidence.logs.single, contains('does not support runCommand'));
  });
}
