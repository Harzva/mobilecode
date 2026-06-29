import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/core/evidence/action_evidence_store.dart';
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
  });
}
