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
