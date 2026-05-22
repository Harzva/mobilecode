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
