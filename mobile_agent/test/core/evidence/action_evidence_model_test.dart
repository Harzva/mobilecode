import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/core/evidence/evidence_model.dart';
import 'package:mobile_agent/core/evidence/action_evidence_store.dart';

void main() {
  group('MobileCodeAction enum', () {
    test('contains all 27 canonical action names', () {
      expect(MobileCodeAction.values.length, 27);
      expect(MobileCodeAction.values.map((e) => e.name), containsAll([
        'listFiles', 'findFiles', 'grepFiles', 'writeFile', 'readFile', 'moveFile',
        'applyPatch', 'openFile', 'previewHtml',
        'webSearch', 'fetchUrl', 'previewSnapshot',
        'publishPages', 'runCommand', 'cloneRepo', 'linkRemoteRepo',
        'commitFiles', 'triggerGitHubAction', 'inspectRelease',
        'installSkill', 'registerMcp', 'openFolder',
        'traceParseInstruction', 'traceSelectTool', 'traceCallProvider',
        'traceWriteArtifact', 'traceReportChat',
      ]));
    });
  });

  group('ActionSchema', () {
    test('JSON roundtrip preserves all fields', () {
      final schema = ActionSchema(
        actionName: MobileCodeAction.writeFile,
        paramsSummary: 'write /tmp/test.dart',
        params: {'path': '/tmp/test.dart', 'overwrite': true},
        requestId: 'req-001',
        risk: ActionRisk.medium,
        approvalRequired: true,
        createdAt: DateTime(2026, 5, 20, 10, 30),
      );

      final json = schema.toJson();
      final restored = ActionSchema.fromJson(json);

      expect(restored.actionName, MobileCodeAction.writeFile);
      expect(restored.paramsSummary, 'write /tmp/test.dart');
      expect(restored.params['path'], '/tmp/test.dart');
      expect(restored.params['overwrite'], true);
      expect(restored.requestId, 'req-001');
      expect(restored.risk, ActionRisk.medium);
      expect(restored.approvalRequired, true);
      expect(restored.createdAt, DateTime(2026, 5, 20, 10, 30));
    });

    test('defaults to safe risk and no approval', () {
      final schema = ActionSchema(
        actionName: MobileCodeAction.readFile,
        paramsSummary: 'read /tmp/a.txt',
        params: {'path': '/tmp/a.txt'},
      );
      expect(schema.paramsSummary, 'read /tmp/a.txt');
      expect(schema.risk, ActionRisk.safe);
      expect(schema.approvalRequired, false);
      expect(schema.requestId, isNull);
    });

    test('fromJson handles missing optional fields', () {
      final json = <String, dynamic>{
        'actionName': 'openFolder',
        'params': <String, dynamic>{},
      };
      final schema = ActionSchema.fromJson(json);
      expect(schema.actionName, MobileCodeAction.openFolder);
      expect(schema.paramsSummary, '');
      expect(schema.risk, ActionRisk.safe);
      expect(schema.approvalRequired, false);
    });
  });

  group('ActionEvidence', () {
    test('JSON roundtrip preserves all fields', () {
      final started = DateTime(2026, 5, 20, 10, 0, 0);
      final ended = DateTime(2026, 5, 20, 10, 0, 5);
      final evidence = ActionEvidence(
        evidenceId: 'ev-test-001',
        actionName: MobileCodeAction.runCommand,
        paramsSummary: 'flutter build apk',
        startedAt: started,
        endedAt: ended,
        success: true,
        artifactPaths: ['build/app.apk'],
        urls: ['https://example.com/build'],
        logs: ['Building...', 'Done.'],
        exitCode: 0,
      );

      final json = evidence.toJson();
      final restored = ActionEvidence.fromJson(json);

      expect(restored.evidenceId, 'ev-test-001');
      expect(restored.actionName, MobileCodeAction.runCommand);
      expect(restored.paramsSummary, 'flutter build apk');
      expect(restored.startedAt, started);
      expect(restored.endedAt, ended);
      expect(restored.success, true);
      expect(restored.artifactPaths, ['build/app.apk']);
      expect(restored.urls, ['https://example.com/build']);
      expect(restored.logs, ['Building...', 'Done.']);
      expect(restored.exitCode, 0);
      expect(restored.durationMs, 5000);
      expect(restored.failureKind, isNull);
      expect(restored.recoveryActions, isEmpty);
    });

    test('durationMs computes correctly', () {
      final started = DateTime(2026, 5, 20, 10, 0, 0);
      final ended = DateTime(2026, 5, 20, 10, 0, 3);
      final evidence = ActionEvidence(
        evidenceId: 'ev-dur',
        actionName: MobileCodeAction.cloneRepo,
        startedAt: started,
        endedAt: ended,
        success: true,
      );
      expect(evidence.durationMs, 3000);
    });

    test('failed evidence carries failureKind and recoveryActions', () {
      final evidence = ActionEvidence.failed(
        actionName: MobileCodeAction.runCommand,
        startedAt: DateTime(2026, 5, 20, 10, 0, 0),
        failureKind: ActionFailureKind.processFailed,
        recoveryActions: [
          'Check if Flutter SDK is installed',
          'Run flutter doctor',
        ],
        logs: ['error: unable to find sdk'],
        exitCode: 1,
      );

      expect(evidence.success, false);
      expect(evidence.failureKind, 'processFailed');
      expect(evidence.recoveryActions, hasLength(2));
      expect(evidence.exitCode, 1);

      // Roundtrip
      final json = evidence.toJson();
      final restored = ActionEvidence.fromJson(json);
      expect(restored.failureKind, 'processFailed');
      expect(restored.recoveryActions, hasLength(2));
    });

    test('started factory creates in-progress evidence', () {
      final evidence = ActionEvidence.started(
        actionName: MobileCodeAction.publishPages,
        paramsSummary: 'index.html -> github pages',
      );
      expect(evidence.success, false);
      expect(evidence.failureKind, isNull);
      expect(evidence.actionName, MobileCodeAction.publishPages);
      expect(evidence.evidenceId, isNotEmpty);
    });

    test('succeeded factory creates success evidence', () {
      final started = DateTime(2026, 5, 20, 10, 0, 0);
      final evidence = ActionEvidence.succeeded(
        actionName: MobileCodeAction.writeFile,
        startedAt: started,
        artifactPaths: ['/tmp/out.dart'],
      );
      expect(evidence.success, true);
      expect(evidence.artifactPaths, ['/tmp/out.dart']);
    });

    test('toEvidence converts to unified Evidence model', () {
      final evidence = ActionEvidence.succeeded(
        actionName: MobileCodeAction.previewHtml,
        startedAt: DateTime(2026, 5, 20, 10, 0, 0),
        paramsSummary: 'preview index.html',
        urls: ['http://localhost:8080'],
      );

      final ev = evidence.toEvidence();
      expect(ev.id, evidence.evidenceId);
      expect(ev.source, EvidenceSource.runtimeProvider);
      expect(ev.category, EvidenceCategory.executed);
      expect(ev.status, EvidenceStatus.executed);
      expect(ev.title, contains('previewHtml'));
      expect(ev.title, contains('succeeded'));
      expect(ev.relatedActionId, evidence.evidenceId);
      // Full ActionEvidence JSON is embedded in details.
      expect(ev.details['actionName'], 'previewHtml');
      expect(ev.details['urls'], ['http://localhost:8080']);
    });

    test('toEvidence for failed action uses error category', () {
      final evidence = ActionEvidence.failed(
        actionName: MobileCodeAction.runCommand,
        startedAt: DateTime(2026, 5, 20, 10, 0, 0),
        failureKind: ActionFailureKind.timeout,
      );

      final ev = evidence.toEvidence();
      expect(ev.category, EvidenceCategory.error);
      expect(ev.status, EvidenceStatus.failed);
      expect(ev.severity, EvidenceSeverity.high); // timeout -> high
    });

    test('fromJson handles missing optional fields gracefully', () {
      final json = <String, dynamic>{
        'evidenceId': 'ev-minimal',
        'actionName': 'readFile',
        'startedAt': '2026-05-20T10:00:00.000',
        'endedAt': '2026-05-20T10:00:01.000',
      };
      final evidence = ActionEvidence.fromJson(json);
      expect(evidence.evidenceId, 'ev-minimal');
      expect(evidence.actionName, MobileCodeAction.readFile);
      expect(evidence.success, false);
      expect(evidence.artifactPaths, isEmpty);
      expect(evidence.failureKind, isNull);
    });
  });

  group('ActionFailureKind', () {
    test('constants match expected stable values', () {
      expect(ActionFailureKind.timeout, 'timeout');
      expect(ActionFailureKind.cancelled, 'cancelled');
      expect(ActionFailureKind.dependencyMissing, 'dependencyMissing');
      expect(ActionFailureKind.commandBlocked, 'commandBlocked');
      expect(ActionFailureKind.cwdOutsideWorkspace, 'cwdOutsideWorkspace');
      expect(ActionFailureKind.authFailed, 'authFailed');
      expect(ActionFailureKind.processFailed, 'processFailed');
      expect(ActionFailureKind.runtimeLost, 'runtimeLost');
      expect(ActionFailureKind.unknown, 'unknown');
    });
  });

  group('Trace-specific actions', () {
    test('trace actions create valid ActionEvidence', () {
      for (final action in [
        MobileCodeAction.traceParseInstruction,
        MobileCodeAction.traceSelectTool,
        MobileCodeAction.traceCallProvider,
        MobileCodeAction.traceWriteArtifact,
        MobileCodeAction.traceReportChat,
      ]) {
        final started = DateTime(2026, 5, 20, 10, 0, 0);
        final evidence = ActionEvidence(
          evidenceId: 'ev-trace-${action.name}',
          actionName: action,
          paramsSummary: 'trace step for ${action.name}',
          startedAt: started,
          endedAt: started.add(const Duration(milliseconds: 500)),
          success: true,
        );
        expect(evidence.actionName, action);
        expect(evidence.evidenceId, contains(action.name));
        expect(evidence.durationMs, 500);

        final json = evidence.toJson();
        final restored = ActionEvidence.fromJson(json);
        expect(restored.actionName, action);
        expect(restored.evidenceId, contains(action.name));
      }
    });

    test('trace actions work with factory helpers', () {
      final started = ActionEvidence.started(
        actionName: MobileCodeAction.traceCallProvider,
        paramsSummary: 'streaming provider',
      );
      expect(started.success, false);
      expect(started.actionName, MobileCodeAction.traceCallProvider);

      final succeeded = ActionEvidence.succeeded(
        actionName: MobileCodeAction.traceWriteArtifact,
        startedAt: DateTime(2026, 5, 20, 10, 0, 0),
        artifactPaths: ['/tmp/output.dart'],
      );
      expect(succeeded.success, true);
      expect(succeeded.artifactPaths, ['/tmp/output.dart']);

      final failed = ActionEvidence.failed(
        actionName: MobileCodeAction.traceReportChat,
        startedAt: DateTime(2026, 5, 20, 10, 0, 0),
        failureKind: ActionFailureKind.processFailed,
      );
      expect(failed.success, false);
      expect(failed.failureKind, 'processFailed');
    });

    test('trace action fromJson defaults to runCommand for unknown name', () {
      final json = <String, dynamic>{
        'evidenceId': 'ev-unknown',
        'actionName': 'nonexistentAction',
        'startedAt': '2026-05-20T10:00:00.000',
        'endedAt': '2026-05-20T10:00:01.000',
      };
      final evidence = ActionEvidence.fromJson(json);
      expect(evidence.actionName, MobileCodeAction.runCommand);
    });
  });

  group('ActionEvidenceStore', () {
    late ActionEvidenceStore store;

    setUp(() {
      store = ActionEvidenceStore();
    });

    test('starts empty', () {
      expect(store.isEmpty, true);
      expect(store.length, 0);
      expect(store.records, isEmpty);
    });

    test('add and getById', () {
      final evidence = ActionEvidence.succeeded(
        actionName: MobileCodeAction.writeFile,
        startedAt: DateTime(2026, 5, 20, 10, 0, 0),
      );
      store.add(evidence);

      expect(store.length, 1);
      expect(store.isNotEmpty, true);
      expect(store.getById(evidence.evidenceId), isNotNull);
      expect(store.getById(evidence.evidenceId)!.actionName,
          MobileCodeAction.writeFile);
    });

    test('add overwrites duplicate evidenceId', () {
      final e1 = ActionEvidence(
        evidenceId: 'ev-dup',
        actionName: MobileCodeAction.writeFile,
        startedAt: DateTime(2026, 5, 20, 10, 0, 0),
        success: false,
      );
      final e2 = ActionEvidence(
        evidenceId: 'ev-dup',
        actionName: MobileCodeAction.writeFile,
        startedAt: DateTime(2026, 5, 20, 10, 0, 0),
        success: true,
      );
      store.add(e1);
      store.add(e2);

      expect(store.length, 1);
      expect(store.getById('ev-dup')!.success, true);
    });

    test('getById returns null for missing id', () {
      expect(store.getById('nonexistent'), isNull);
    });

    test('recent returns newest first, limited by count', () {
      for (var i = 0; i < 5; i++) {
        store.add(ActionEvidence(
          evidenceId: 'ev-$i',
          actionName: MobileCodeAction.runCommand,
          startedAt: DateTime(2026, 5, 20, 10, 0, i),
        ));
      }
      final recent = store.recent(count: 3);
      expect(recent, hasLength(3));
      // Most recent should be ev-4
      expect(recent.first.evidenceId, 'ev-4');
    });

    test('byAction filters by action name', () {
      store.add(ActionEvidence(
        evidenceId: 'ev-w',
        actionName: MobileCodeAction.writeFile,
        startedAt: DateTime(2026, 5, 20, 10, 0, 0),
      ));
      store.add(ActionEvidence(
        evidenceId: 'ev-r',
        actionName: MobileCodeAction.readFile,
        startedAt: DateTime(2026, 5, 20, 10, 0, 1),
      ));
      store.add(ActionEvidence(
        evidenceId: 'ev-w2',
        actionName: MobileCodeAction.writeFile,
        startedAt: DateTime(2026, 5, 20, 10, 0, 2),
      ));

      expect(store.byAction(MobileCodeAction.writeFile), hasLength(2));
      expect(store.byAction(MobileCodeAction.readFile), hasLength(1));
      expect(store.byAction(MobileCodeAction.cloneRepo), isEmpty);
    });

    test('failures returns only failed records', () {
      store.add(ActionEvidence.succeeded(
        actionName: MobileCodeAction.writeFile,
        startedAt: DateTime(2026, 5, 20, 10, 0, 0),
      ));
      store.add(ActionEvidence.failed(
        actionName: MobileCodeAction.runCommand,
        startedAt: DateTime(2026, 5, 20, 10, 0, 1),
        failureKind: ActionFailureKind.processFailed,
      ));

      expect(store.failures(), hasLength(1));
      expect(store.failures().first.failureKind, 'processFailed');
    });

    test('clear removes all records', () {
      store.add(ActionEvidence(
        evidenceId: 'ev-c',
        actionName: MobileCodeAction.readFile,
        startedAt: DateTime(2026, 5, 20, 10, 0, 0),
      ));
      store.clear();
      expect(store.isEmpty, true);
    });

    test('toJson / loadFromJson roundtrip', () {
      store.add(ActionEvidence.succeeded(
        actionName: MobileCodeAction.writeFile,
        startedAt: DateTime(2026, 5, 20, 10, 0, 0),
        artifactPaths: ['/tmp/a.dart'],
      ));
      store.add(ActionEvidence.failed(
        actionName: MobileCodeAction.runCommand,
        startedAt: DateTime(2026, 5, 20, 10, 0, 1),
        failureKind: ActionFailureKind.processFailed,
        recoveryActions: ['Check SDK'],
      ));

      final json = store.toJson();
      final newStore = ActionEvidenceStore();
      newStore.loadFromJson(json);

      expect(newStore.length, 2);
      expect(newStore.getById(store.records[0].evidenceId), isNotNull);
      expect(newStore.getById(store.records[1].evidenceId)!.failureKind,
          'processFailed');
    });

    test('loadFromJson replaces existing records', () {
      store.add(ActionEvidence(
        evidenceId: 'ev-old',
        actionName: MobileCodeAction.readFile,
        startedAt: DateTime(2026, 5, 20, 10, 0, 0),
      ));

      final json = [
        ActionEvidence(
          evidenceId: 'ev-new',
          actionName: MobileCodeAction.writeFile,
          startedAt: DateTime(2026, 5, 20, 10, 0, 1),
        ).toJson(),
      ];
      store.loadFromJson(json);

      expect(store.length, 1);
      expect(store.getById('ev-old'), isNull);
      expect(store.getById('ev-new'), isNotNull);
    });
  });
}
