import 'dart:convert';

import '../core/evidence/action_evidence_store.dart';
import '../core/evidence/action_runner.dart';
import '../core/evidence/evidence_model.dart';

/// Exporter and minimal approval-gated handoff adapter for the Harvis <->
/// MobileCode bridge.
///
/// P1 methods are read-only exporters. P2 handoff execution is intentionally
/// narrow: it accepts only a validated `mobilecode.handoff.v1` transport
/// payload with an approval id, calls the existing typed ActionRunner route for
/// `project_check` or `validate`, and exports the resulting ActionEvidence. It
/// does not control devices, publish to GitHub, store Lark credentials, or call
/// the network.
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
    Map<String, dynamic> approval = const {},
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
      if (approval.isNotEmpty) 'approval': _redactMap(approval),
      'redaction': 'public_safe',
      'created_at': evidence.endedAt.toUtc().toIso8601String(),
      'next_action': nextAction,
    };
  }

  HarvisMobileCodeHandoff parseHandoffMessage(String text) {
    final trimmed = text.trim();
    final jsonStart = trimmed.indexOf('{');
    if (jsonStart < 0) {
      throw const HarvisMobileCodeHandoffException(
        'handoff message does not contain a JSON payload',
      );
    }
    final decoded = jsonDecode(trimmed.substring(jsonStart));
    if (decoded is! Map<String, dynamic>) {
      throw const HarvisMobileCodeHandoffException(
        'handoff message JSON must be an object',
      );
    }
    return HarvisMobileCodeHandoff.fromTransportPayload(decoded);
  }

  Future<HarvisMobileCodeHandoffResult> runApprovedHandoff({
    required Map<String, dynamic> payload,
    required ActionRunner runner,
  }) async {
    final handoff = HarvisMobileCodeHandoff.fromTransportPayload(payload);
    final result = await runner.run(handoff.toActionSchema());
    final actionEvidence = exportActionEvidence(
      evidence: result.evidence,
      taskId: handoff.taskId,
      correlationId: handoff.correlationId,
      action: handoff.action,
      approval: {
        'required': true,
        'approval_id': handoff.approvalId,
        'status': 'consumed',
      },
    );
    return HarvisMobileCodeHandoffResult(
      handoff: handoff,
      runnerResult: result,
      actionEvidence: actionEvidence,
    );
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

class HarvisMobileCodeHandoff {
  const HarvisMobileCodeHandoff({
    required this.taskId,
    required this.correlationId,
    required this.action,
    required this.approvalId,
    required this.title,
    required this.input,
    required this.timeoutMs,
    required this.source,
    required this.evidenceContract,
  });

  final String taskId;
  final String correlationId;
  final String action;
  final String approvalId;
  final String title;
  final Map<String, dynamic> input;
  final int timeoutMs;
  final Map<String, dynamic> source;
  final Map<String, dynamic> evidenceContract;

  factory HarvisMobileCodeHandoff.fromTransportPayload(
    Map<String, dynamic> payload,
  ) {
    final errors = <String>[];
    final type = _stringValue(payload['type']);
    if (type != 'mobilecode.handoff.v1') {
      errors.add('type must be mobilecode.handoff.v1.');
    }
    if (_stringValue(payload['schema_version']) !=
        'mobilecode.harvis.task.v1') {
      errors.add('schema_version must be mobilecode.harvis.task.v1.');
    }
    final taskId = _stringValue(payload['task_id']);
    if (!taskId.startsWith('hm_task_')) {
      errors.add('task_id must start with hm_task_.');
    }
    final correlationId = _stringValue(payload['correlation_id']);
    if (!correlationId.startsWith('corr_')) {
      errors.add('correlation_id must start with corr_.');
    }
    final action = _stringValue(payload['action']);
    if (action != 'project_check' && action != 'validate') {
      errors.add('action must be project_check or validate.');
    }

    final approval = _mapValue(payload['approval']);
    if (approval['required'] != true) {
      errors.add('approval.required must be true.');
    }
    final approvalId = _stringValue(approval['approval_id']);
    if (!approvalId.startsWith('appr_')) {
      errors.add('approval.approval_id is required and must start with appr_.');
    }

    final source = _mapValue(payload['source']);
    if (_stringValue(source['system']) != 'harvis') {
      errors.add('source.system must be harvis.');
    }

    final task = _mapValue(payload['task']);
    final title = _stringValue(task['title']).isEmpty
        ? 'Harvis MobileCode handoff'
        : _stringValue(task['title']);
    final input = _mapValue(task['input']);
    final timeoutMs = _boundedTimeoutMs(task['timeout_ms']);

    final target = _mapValue(payload['target']);
    final deviceSelector = _mapValue(target['device_selector']);
    if (deviceSelector['required'] == true) {
      errors.add('P2 handoff cannot require a phone, emulator, or simulator.');
    }
    final deviceKind = _stringValue(deviceSelector['kind']);
    if (deviceKind.isNotEmpty && deviceKind != 'none') {
      errors.add('P2 handoff device_selector.kind must be none.');
    }

    final evidenceContract = _mapValue(payload['evidence_contract']);
    final expectedTypes = evidenceContract['expected_types'];
    if (expectedTypes is! List ||
        !expectedTypes.contains('mobilecode.action_evidence.v1')) {
      errors.add(
        'evidence_contract.expected_types must include mobilecode.action_evidence.v1.',
      );
    }

    if (errors.isNotEmpty) {
      throw HarvisMobileCodeHandoffException(
        'MobileCode handoff validation failed.',
        errors,
      );
    }

    return HarvisMobileCodeHandoff(
      taskId: taskId,
      correlationId: correlationId,
      action: action,
      approvalId: approvalId,
      title: title,
      input: input,
      timeoutMs: timeoutMs,
      source: source,
      evidenceContract: evidenceContract,
    );
  }

  ActionSchema toActionSchema() {
    final projectRef = _mapValue(input['project_ref']);
    final args = <String, dynamic>{
      'taskId': taskId,
      'correlationId': correlationId,
      'approvalId': approvalId,
      'projectRefKind': _stringValue(projectRef['kind']),
      'projectRefValue': _stringValue(projectRef['value']),
      'projectRefCommit': _stringValue(projectRef['commit']),
      'sourceSystem': _stringValue(source['system']),
    }..removeWhere((_, value) => _stringValue(value).isEmpty);
    final path = _stringValue(input['path']);
    return ActionSchema(
      actionName: MobileCodeAction.termuxTaskStart,
      requestId: 'ev_$taskId',
      paramsSummary: 'Harvis handoff $action: $title',
      params: {
        'taskKind': action,
        if (path.isNotEmpty) 'path': path,
        'reason': 'Harvis approval $approvalId',
        'argsJson': jsonEncode(args),
        'timeoutMs': timeoutMs,
        'maxOutputBytes': 32768,
      },
    );
  }
}

class HarvisMobileCodeHandoffResult {
  const HarvisMobileCodeHandoffResult({
    required this.handoff,
    required this.runnerResult,
    required this.actionEvidence,
  });

  final HarvisMobileCodeHandoff handoff;
  final ActionRunnerResult runnerResult;
  final Map<String, dynamic> actionEvidence;

  Map<String, dynamic> toJson() => {
        'ok': true,
        'task_id': handoff.taskId,
        'correlation_id': handoff.correlationId,
        'action': handoff.action,
        'approval_id': handoff.approvalId,
        'runner_success': runnerResult.success,
        'action_evidence': actionEvidence,
      };
}

class HarvisMobileCodeHandoffException implements Exception {
  const HarvisMobileCodeHandoffException(
    this.message, [
    this.details = const [],
  ]);

  final String message;
  final List<String> details;

  @override
  String toString() =>
      details.isEmpty ? message : '$message ${details.join(' ')}';
}

Map<String, dynamic> _redactMap(Map<String, dynamic> value) =>
    value.map((key, item) => MapEntry(key, _redactValue(item)));

Map<String, dynamic> _mapValue(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

String _stringValue(Object? value) =>
    value is String ? value.trim() : value?.toString().trim() ?? '';

int _boundedTimeoutMs(Object? value) {
  final parsed =
      value is num ? value.toInt() : int.tryParse(_stringValue(value));
  if (parsed == null || parsed <= 0) return 30000;
  if (parsed < 1000) return 1000;
  if (parsed > 120000) return 120000;
  return parsed;
}

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
