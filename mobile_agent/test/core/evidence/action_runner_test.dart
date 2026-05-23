import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/core/evidence/action_evidence_store.dart';
import 'package:mobile_agent/core/evidence/action_runner.dart';
import 'package:mobile_agent/core/evidence/evidence_model.dart';

void main() {
  late Directory workspace;
  late ActionEvidenceStore store;
  late ActionRunner runner;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('mobilecode_action_runner_');
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
    await file.writeAsString('<h1>Animal island</h1>\n<p>Touch friendly preview</p>');

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
    expect(await File('${workspace.path}/backup/draft.html').readAsString(), contains('Draft'));
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
    expect(await Directory('${workspace.path}/generated/assets/icons').exists(), true);
    expect(result.evidence.actionName, MobileCodeAction.makeDirectory);
    expect(store.getById('ev-mkdir'), isNotNull);
  });

  test('deleteFile requires confirmation and saves pre-delete snapshot', () async {
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
    expect(await File('${workspace.path}/published/index.html').readAsString(), contains('Draft'));
    expect(result.evidence.actionName, MobileCodeAction.moveFile);
    expect(result.evidence.metadata['sourcePath'], 'draft.html');
    expect(store.getById('ev-move'), isNotNull);
  });

  test('saveSnapshot and virtualDiff compare workspace changes without shell', () async {
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

  test('restoreSnapshot restores confirmed files and backs up current versions', () async {
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

  test('projectSummary returns compact entrypoints and extension counts', () async {
    final file = File('${workspace.path}/demo/index.html');
    await file.parent.create(recursive: true);
    await file.writeAsString('<!doctype html><title>Demo</title>');
    await File('${workspace.path}/demo/app.js').writeAsString('console.log("hi");');

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
    expect(result.evidence.metadata['entrypoints'], contains('demo${Platform.pathSeparator}index.html'));
    expect(result.evidence.actionName, MobileCodeAction.projectSummary);
  });

  test('changeHistory and virtualStatus expose writes and restore points', () async {
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
    await File('${workspace.path}/demo/pubspec.yaml').writeAsString('name: demo\n');
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

  test('validateHtml reports mobile readiness warnings without executing scripts', () async {
    final file = File('${workspace.path}/demo/index.html');
    await file.parent.create(recursive: true);
    await file.writeAsString('<html><head><title>Demo</title></head><body><h1>Hello</h1></body></html>');

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
    expect(result.evidence.actionName, MobileCodeAction.validateHtml);
  });

  test('validateJson and validateMarkdown report structure issues without shell', () async {
    final jsonFile = File('${workspace.path}/data/config.json');
    await jsonFile.parent.create(recursive: true);
    await jsonFile.writeAsString('{"name": "demo", "items": [1, 2]}');
    final badMarkdown = File('${workspace.path}/README.md');
    await badMarkdown.writeAsString('## Missing top heading\n#### Jumped\nSee https://example.com\n');

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
    expect(markdownResult.evidence.metadata['issueCount'], greaterThanOrEqualTo(2));
  });

  test('validateJson reports invalid JSON as validation metadata, not shell failure', () async {
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
    expect(result.evidence.metadata['changedFiles'], contains('demo${Platform.pathSeparator}index.html'));
    expect(result.evidence.logs.join(' '), contains('Saved 1 pre-patch snapshot'));
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
    expect(await File('${workspace.path}/new-note.txt').readAsString(), 'hello\nmobile');
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
        'patch': '--- a/../escape.txt\n+++ b/../escape.txt\n@@ -0,0 +1,1 @@\n+bad',
        'reason': 'escape',
      },
      requestId: 'ev-patch-outside',
    ));

    expect(deleteResult.success, false);
    expect(deleteResult.evidence.failureKind, ActionFailureKind.commandBlocked);
    expect(outsideResult.success, false);
    expect(outsideResult.evidence.failureKind, ActionFailureKind.cwdOutsideWorkspace);
  });

  test('applyPatch rejects oversized patches', () async {
    final hugePatch = '--- a/a.txt\n+++ b/a.txt\n@@ -0,0 +1,1 @@\n+${List.filled(90 * 1024, 'x').join()}';

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

  test('termuxTaskStart fails closed without helper and never runs raw shell', () async {
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
    expect(unavailable.evidence.failureKind, ActionFailureKind.dependencyMissing);
    expect(unavailable.text, contains('No raw shell was executed'));
    expect(unavailable.evidence.metadata['taskKind'], 'project_check');
    expect(blockedRaw.success, false);
    expect(blockedRaw.evidence.failureKind, ActionFailureKind.commandBlocked);
  });

  test('termuxTaskStart records taskId stdout stderr from typed helper', () async {
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
  });

  test('previewHtml from inline html writes preview file and returns file url', () async {
    final result = await runner.run(ActionSchema(
      actionName: MobileCodeAction.previewHtml,
      params: const {'html': '<!doctype html><title>Hi</title>'},
      requestId: 'ev-preview',
    ));

    expect(result.success, true);
    expect(result.path, endsWith('index.html'));
    expect(result.url, startsWith('file:'));
    expect(await File(result.path!).readAsString(), contains('<title>Hi</title>'));
    expect(result.evidence.urls.single, result.url);
    expect(store.getById('ev-preview'), isNotNull);
  });

  test('webSearch calls injected relay tool and records compact results', () async {
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

  test('fetchUrl rejects non-public or non-https URLs before relay call', () async {
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
    await file.writeAsString('<!doctype html><html><head><title>Island</title></head><body><h1>3D Island</h1></body></html>');

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
    final snapshot = jsonDecode(await File(result.path!).readAsString()) as Map<String, dynamic>;
    expect(snapshot['title'], 'Island');
    expect(snapshot['bodyTextPreview'], contains('3D Island'));
    expect(result.evidence.artifactPaths.length, 2);
    expect(store.getById('ev-snapshot'), isNotNull);
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

  test('unsupported action fails closed', () async {
    final result = await runner.run(ActionSchema(
      actionName: MobileCodeAction.runCommand,
      paramsSummary: 'run pwd',
      params: const {'command': 'pwd'},
      requestId: 'ev-command',
    ));

    expect(result.success, false);
    expect(result.evidence.failureKind, ActionFailureKind.commandBlocked);
    expect(result.evidence.logs.single, contains('does not support runCommand'));
  });
}
