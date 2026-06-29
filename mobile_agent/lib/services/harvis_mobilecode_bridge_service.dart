import '../core/evidence/action_evidence_store.dart';
import '../core/evidence/evidence_model.dart';

/// Read-only exporter for the Harvis <-> MobileCode bridge.
///
/// This service does not execute actions, control devices, publish to GitHub, or
/// call the network. It only converts existing MobileCode runtime state and
/// ActionEvidence into public-safe JSON envelopes that Harvis can render in
/// Agent Room.
class HarvisMobileCodeBridgeService {
  HarvisMobileCodeBridgeService({
    ActionEvidenceStore? evidenceStore,
    DateTime Function()? clock,
  })  : evidenceStore = evidenceStore ?? ActionEvidenceStore.shared,
        _clock = clock ?? DateTime.now;

  final ActionEvidenceStore evidenceStore;
  final DateTime Function() _clock;

  Map<String, dynamic> exportStatus({
    required String taskId,
    required String correlationId,
    String state = 'running',
    String phase = 'project_check',
    String nextAction = 'continue_project_check',
    String runtimeVersion = 'unknown',
    Map<String, dynamic> progress = const {},
    Map<String, dynamic> approval = const {},
    Map<String, dynamic> device = const {
      'kind': 'none',
      'required': false,
      'status': 'not_required',
    },
  }) {
    final recent = evidenceStore.recent(count: 5);
    return {
      'type': 'mobilecode.status.v1',
      'task_id': taskId,
      'correlation_id': correlationId,
      'runtime': {
        'name': 'mobilecode',
        'mode': 'existing-runtime-adapter',
        'version': runtimeVersion,
        'host': 'local',
      },
      'state': _allowedState(state),
      'phase': phase,
      'progress': progress.isNotEmpty
          ? _redactMap(progress)
          : {
              'completed': recent.where((item) => item.success).length,
              'total': recent.length,
              'current': recent.isEmpty ? 'idle' : recent.first.actionName.name,
            },
      'capabilities': const [
        'status_export',
        'evidence_export',
        'project_check',
      ],
      'device': _redactMap(device),
      if (approval.isNotEmpty) 'approval': _redactMap(approval),
      'updated_at': _clock().toUtc().toIso8601String(),
      'next_action': nextAction,
    };
  }

  Map<String, dynamic> exportActionEvidence({
    required ActionEvidence evidence,
    required String taskId,
    required String correlationId,
    String? action,
    String nextAction = 'render_in_harvis_agent_room',
  }) {
    final bridgeAction = action ?? _bridgeActionFor(evidence.actionName);
    return {
      'type': 'mobilecode.action_evidence.v1',
      'task_id': taskId,
      'correlation_id': correlationId,
      'action': _allowedAction(bridgeAction),
      'status': evidence.success ? 'verified' : 'failed',
      'summary': evidence.paramsSummary.isNotEmpty
          ? evidence.paramsSummary
          : evidence.actionName.name,
      'observations': [
        {
          'kind': 'action_evidence',
          'status': evidence.success ? 'passed' : 'failed',
          'message': evidence.logs.isEmpty
              ? evidence.actionName.name
              : evidence.logs.take(3).join('\n'),
        }
      ],
      'artifacts': [
        for (final path in evidence.artifactPaths)
          {
            'kind': 'file',
            'label': 'artifact',
            'ref': _redactValue(path),
          },
        for (final url in evidence.urls)
          {
            'kind': 'url',
            'label': 'url',
            'ref': _redactValue(url),
          },
      ],
      'redaction': 'public_safe',
      'created_at': evidence.endedAt.toUtc().toIso8601String(),
      'next_action': nextAction,
    };
  }

  String _bridgeActionFor(MobileCodeAction action) => switch (action) {
        MobileCodeAction.validateHtml ||
        MobileCodeAction.validateJson ||
        MobileCodeAction.validateMarkdown =>
          'validate',
        _ => 'project_check',
      };

  String _allowedAction(String value) =>
      value == 'validate' ? 'validate' : 'project_check';

  String _allowedState(String value) {
    const allowed = {
      'queued',
      'accepted',
      'running',
      'needs_human',
      'verified',
      'failed',
      'cancelled',
    };
    return allowed.contains(value) ? value : 'running';
  }
}

Map<String, dynamic> _redactMap(Map<String, dynamic> value) =>
    value.map((key, item) => MapEntry(key, _redactValue(item)));

dynamic _redactValue(dynamic value) {
  if (value is String) {
    return value.replaceAll(
      RegExp(r'(?:/Users|/Volumes|/private|/var/folders)/[^\s]+'),
      '[local-path]',
    );
  }
  if (value is List) {
    return value.map(_redactValue).toList();
  }
  if (value is Map) {
    return value
        .map((key, item) => MapEntry(key.toString(), _redactValue(item)));
  }
  return value;
}
