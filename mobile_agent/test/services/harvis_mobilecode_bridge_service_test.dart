import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/core/evidence/action_evidence_store.dart';
import 'package:mobile_agent/core/evidence/action_runner.dart';
import 'package:mobile_agent/core/evidence/evidence_model.dart';
import 'package:mobile_agent/services/harvis_mobilecode_bridge_service.dart';

void main() {
  group('HarvisMobileCodeBridgeService', () {
    test('exports read-only status from recent ActionEvidence', () {
      final store = ActionEvidenceStore();
      store.add(ActionEvidence.succeeded(
        actionName: MobileCodeAction.virtualStatus,
        startedAt: DateTime.utc(2026, 6, 29, 9),
        paramsSummary: 'virtual status',
        evidenceId: 'ev-status',
      ));
      final service = HarvisMobileCodeBridgeService(
        evidenceStore: store,
        clock: () => DateTime.utc(2026, 6, 29, 9, 41),
      );

      final status = service.exportStatus(
        taskId: 'hm_task_project_check_001',
        correlationId: 'corr_mobilecode_harvis_001',
        approval: const {
          'required': true,
          'approval_id': 'appr_project_check_001',
          'status': 'approved',
        },
      );

      expect(status['type'], 'mobilecode.status.v1');
      expect(status['task_id'], 'hm_task_project_check_001');
      expect(status['correlation_id'], 'corr_mobilecode_harvis_001');
      expect(status['state'], 'running');
      expect(status['runtime']['name'], 'mobilecode');
      expect(status['capabilities'], contains('status_export'));
      expect(status['approval']['approval_id'], 'appr_project_check_001');
      expect(status['updated_at'], '2026-06-29T09:41:00.000Z');
    });

    test('exports ActionEvidence as project_check evidence by default', () {
      final evidence = ActionEvidence.succeeded(
        actionName: MobileCodeAction.virtualStatus,
        startedAt: DateTime.utc(2026, 6, 29, 9),
        evidenceId: 'ev-project-check',
        paramsSummary: 'Project status inspected',
        artifactPaths: const ['/Users/example/private/status.json'],
        logs: const ['status ok'],
      );
      final service = HarvisMobileCodeBridgeService(
        evidenceStore: ActionEvidenceStore(),
      );

      final exported = service.exportActionEvidence(
        evidence: evidence,
        taskId: 'hm_task_project_check_001',
        correlationId: 'corr_mobilecode_harvis_001',
      );

      expect(exported['type'], 'mobilecode.action_evidence.v1');
      expect(exported['action'], 'project_check');
      expect(exported['status'], 'verified');
      expect(exported['summary'], 'Project status inspected');
      expect(exported['artifacts'][0]['ref'], '[local-path]');
      expect(exported.toString(), isNot(contains('/Users/example')));
    });

    test('maps validation actions to validate evidence', () {
      final evidence = ActionEvidence.failed(
        actionName: MobileCodeAction.validateJson,
        startedAt: DateTime.utc(2026, 6, 29, 9),
        evidenceId: 'ev-validate',
        paramsSummary: 'Validate JSON fixture',
        failureKind: ActionFailureKind.processFailed,
        logs: const ['invalid json'],
      );
      final service = HarvisMobileCodeBridgeService();

      final exported = service.exportActionEvidence(
        evidence: evidence,
        taskId: 'hm_task_validate_001',
        correlationId: 'corr_validate_001',
      );

      expect(exported['action'], 'validate');
      expect(exported['status'], 'failed');
      expect(exported['observations'][0]['message'], 'invalid json');
    });

    test('parses a prefixed mobilecode handoff transport message', () {
      final service = HarvisMobileCodeBridgeService();

      final handoff = service.parseHandoffMessage(
        '[mobilecode-handoff] ${_handoffPayload(action: 'validate')}',
      );

      expect(handoff.taskId, 'hm_task_project_check_001');
      expect(handoff.correlationId, 'corr_mobilecode_harvis_001');
      expect(handoff.action, 'validate');
      expect(handoff.approvalId, 'appr_project_check_001');
    });

    test('accepts the checked-in project_check handoff fixture', () async {
      final service = HarvisMobileCodeBridgeService();
      final raw = await File(
        'test/fixtures/harvis_mobilecode_handoff.project_check.json',
      ).readAsString();

      final handoff = HarvisMobileCodeHandoff.fromTransportPayload(
        jsonDecode(raw) as Map<String, dynamic>,
      );

      expect(handoff.taskId, 'hm_task_project_check_001');
      expect(handoff.action, 'project_check');
      expect(handoff.toActionSchema().params['taskKind'], 'project_check');
      expect(
          service.exportStatus(
            taskId: handoff.taskId,
            correlationId: handoff.correlationId,
          )['type'],
          'mobilecode.status.v1');
    });

    test('rejects handoff transport without approval id', () {
      final service = HarvisMobileCodeBridgeService();
      final payload = _handoffMap();
      (payload['approval'] as Map<String, dynamic>).remove('approval_id');

      expect(
        service.runApprovedHandoff(
          payload: payload,
          runner: ActionRunner(workspaceRootPath: Directory.systemTemp.path),
        ),
        throwsA(isA<HarvisMobileCodeHandoffException>()),
      );
    });

    test('runs approved project_check handoff through typed runner', () async {
      final workspace =
          await Directory.systemTemp.createTemp('mobilecode_harvis_handoff_');
      final store = ActionEvidenceStore();
      final runner = ActionRunner(
        workspaceRootPath: workspace.path,
        evidenceStore: store,
        termuxTaskInvoker: (taskKind, payload) async {
          expect(taskKind, 'project_check');
          expect(payload['args']['approvalId'], 'appr_project_check_001');
          expect(
              payload['args']['correlationId'], 'corr_mobilecode_harvis_001');
          return {
            'status': 'succeeded',
            'taskId': 'helper_project_check_001',
            'stdout': 'project check ok',
            'exitCode': 0,
          };
        },
      );
      final service = HarvisMobileCodeBridgeService(evidenceStore: store);

      try {
        final result = await service.runApprovedHandoff(
          payload: _handoffMap(),
          runner: runner,
        );

        expect(result.runnerResult.success, true);
        expect(result.runnerResult.evidence.actionName,
            MobileCodeAction.termuxTaskStart);
        expect(result.actionEvidence['type'], 'mobilecode.action_evidence.v1');
        expect(result.actionEvidence['action'], 'project_check');
        expect(result.actionEvidence['status'], 'verified');
        expect(result.actionEvidence['approval']['approval_id'],
            'appr_project_check_001');
        expect(
            result.actionEvidence.toString(), isNot(contains(workspace.path)));
        expect(store.getById('ev_hm_task_project_check_001'), isNotNull);
      } finally {
        if (await workspace.exists()) {
          await workspace.delete(recursive: true);
        }
      }
    });

    test('runs an approved prefixed handoff message through typed runner',
        () async {
      final workspace =
          await Directory.systemTemp.createTemp('mobilecode_harvis_message_');
      final store = ActionEvidenceStore();
      final runner = ActionRunner(
        workspaceRootPath: workspace.path,
        evidenceStore: store,
        termuxTaskInvoker: (taskKind, payload) async {
          expect(taskKind, 'validate');
          expect(payload['args']['taskId'], 'hm_task_project_check_001');
          return {
            'status': 'succeeded',
            'taskId': 'helper_validate_001',
            'stdout': 'validate ok',
            'exitCode': 0,
          };
        },
      );
      final service = HarvisMobileCodeBridgeService(evidenceStore: store);

      try {
        final result = await service.runApprovedHandoffMessage(
          text: '[mobilecode-handoff] ${_handoffPayload(action: 'validate')}',
          runner: runner,
        );

        expect(result.handoff.action, 'validate');
        expect(result.runnerResult.success, true);
        expect(result.actionEvidence['type'], 'mobilecode.action_evidence.v1');
        expect(result.actionEvidence['action'], 'validate');
        expect(result.actionEvidence['status'], 'verified');
      } finally {
        if (await workspace.exists()) {
          await workspace.delete(recursive: true);
        }
      }
    });

    test('writes failed ActionEvidence when typed runtime is unavailable',
        () async {
      final workspace =
          await Directory.systemTemp.createTemp('mobilecode_harvis_handoff_');
      final store = ActionEvidenceStore();
      final runner = ActionRunner(
        workspaceRootPath: workspace.path,
        evidenceStore: store,
      );
      final service = HarvisMobileCodeBridgeService(evidenceStore: store);

      try {
        final result = await service.runApprovedHandoff(
          payload: _handoffMap(action: 'validate'),
          runner: runner,
        );

        expect(result.runnerResult.success, false);
        expect(result.actionEvidence['action'], 'validate');
        expect(result.actionEvidence['status'], 'failed');
        expect(result.actionEvidence['observations'][0]['message'],
            contains('Termux typed task route is not connected'));
      } finally {
        if (await workspace.exists()) {
          await workspace.delete(recursive: true);
        }
      }
    });
  });
}

Map<String, dynamic> _handoffMap({String action = 'project_check'}) => {
      'type': 'mobilecode.handoff.v1',
      'schema_version': 'mobilecode.harvis.task.v1',
      'task_id': 'hm_task_project_check_001',
      'correlation_id': 'corr_mobilecode_harvis_001',
      'action': action,
      'approval': {
        'required': true,
        'approval_id': 'appr_project_check_001',
        'risk': 'low',
        'summary': 'Check MobileCode bridge readiness.',
      },
      'source': {
        'system': 'harvis',
        'agent_room_topic_id': 'topic_mobilecode_bridge_001',
      },
      'task': {
        'title': 'Check MobileCode bridge readiness',
        'input': {
          'project_ref': {
            'kind': 'repo',
            'value': 'Harzva/lark-relay',
            'commit': 'P0-fixture',
          },
          'checks': [
            'read protocol fixture',
            'verify status export shape',
            'verify evidence export shape',
          ],
        },
        'timeout_ms': 300000,
      },
      'evidence_contract': {
        'expected_types': [
          'mobilecode.status.v1',
          'mobilecode.action_evidence.v1',
        ],
        'redaction': 'public_safe',
      },
    };

String _handoffPayload({String action = 'project_check'}) =>
    jsonEncode(_handoffMap(action: action));
