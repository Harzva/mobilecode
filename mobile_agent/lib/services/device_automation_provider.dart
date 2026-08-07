import 'dart:math';

import '../core/evidence/action_evidence_store.dart';
import '../core/evidence/evidence_model.dart';
import 'phone_use_accessibility_service.dart';
import 'secure_storage_service.dart';

enum DeviceAutomationProviderType {
  embeddedAccessibility,
  agentDeviceQa,
  iosXCTestHelper,
  cloud;
}

enum DeviceAutomationRiskClass {
  reversible,
  externalTransaction;
}

enum DeviceAutomationActionKind {
  observe,
  tapRef,
  tapCoordinate,
  swipe,
  setTextRef,
  setTextFocused,
  back,
  home,
  captureScreenshot,
  replay;

  bool get mutatesDevice => switch (this) {
        observe || captureScreenshot => false,
        _ => true,
      };

  bool get capturesSensitiveArtifact => this == captureScreenshot;
}

class DeviceAutomationCapabilities {
  const DeviceAutomationCapabilities({
    required this.semanticSnapshots,
    required this.semanticRefs,
    required this.coordinateActions,
    required this.screenshots,
    required this.video,
    required this.logs,
    required this.replay,
    required this.physicalDevices,
    required this.simulators,
  });

  final bool semanticSnapshots;
  final bool semanticRefs;
  final bool coordinateActions;
  final bool screenshots;
  final bool video;
  final bool logs;
  final bool replay;
  final bool physicalDevices;
  final bool simulators;

  Map<String, dynamic> toJson() => {
        'semanticSnapshots': semanticSnapshots,
        'semanticRefs': semanticRefs,
        'coordinateActions': coordinateActions,
        'screenshots': screenshots,
        'video': video,
        'logs': logs,
        'replay': replay,
        'physicalDevices': physicalDevices,
        'simulators': simulators,
      };
}

class DeviceAutomationHealth {
  const DeviceAutomationHealth({
    required this.available,
    required this.ready,
    required this.state,
    required this.failureKind,
    required this.recoveryActions,
    required this.capabilities,
  });

  final bool available;
  final bool ready;
  final String state;
  final String? failureKind;
  final List<String> recoveryActions;
  final DeviceAutomationCapabilities capabilities;
}

class DeviceAutomationRequest {
  const DeviceAutomationRequest({
    required this.action,
    this.targetRef,
    this.x,
    this.y,
    this.x2,
    this.y2,
    this.durationMs,
    this.text,
    this.secretId,
    this.approvalGranted = false,
    this.approvalSource = 'none',
    this.captureIfSparse = false,
    this.sensitiveFlow = false,
    this.artifactIds = const [],
    this.riskClass = DeviceAutomationRiskClass.reversible,
    this.transactionPreviewDigest,
    this.transactionApprovalDigest,
    this.transactionApprovalId,
    this.preconditionSnapshotDigest,
  });

  final DeviceAutomationActionKind action;
  final String? targetRef;
  final int? x;
  final int? y;
  final int? x2;
  final int? y2;
  final int? durationMs;
  final String? text;
  final String? secretId;
  final bool approvalGranted;
  final String approvalSource;
  final bool captureIfSparse;
  final bool sensitiveFlow;
  final List<String> artifactIds;
  final DeviceAutomationRiskClass riskClass;
  final String? transactionPreviewDigest;
  final String? transactionApprovalDigest;
  final String? transactionApprovalId;
  final String? preconditionSnapshotDigest;

  bool get requiresApproval =>
      action.mutatesDevice ||
      action.capturesSensitiveArtifact ||
      captureIfSparse;

  bool get requiresTransactionApproval =>
      riskClass == DeviceAutomationRiskClass.externalTransaction;

  bool get transactionApprovalSatisfied =>
      !requiresTransactionApproval ||
      (transactionApprovalId?.trim().isNotEmpty == true &&
          transactionPreviewDigest?.trim().isNotEmpty == true &&
          transactionApprovalDigest == transactionPreviewDigest);

  String get safeSummary {
    final target = targetRef == null ? '' : ' target=${_safeToken(targetRef!)}';
    final coordinate = x == null || y == null ? '' : ' coordinate=($x,$y)';
    final credential = secretId == null
        ? ''
        : ' credential_slot=${_safeToken(secretId!, maxLength: 48)}';
    final risk =
        requiresTransactionApproval ? ' risk=external_transaction' : '';
    return '${action.name}$target$coordinate$credential$risk';
  }

  DeviceAutomationRequest copyWith({
    bool? approvalGranted,
    String? approvalSource,
    DeviceAutomationRiskClass? riskClass,
    String? transactionPreviewDigest,
    String? transactionApprovalDigest,
    String? transactionApprovalId,
    String? preconditionSnapshotDigest,
  }) =>
      DeviceAutomationRequest(
        action: action,
        targetRef: targetRef,
        x: x,
        y: y,
        x2: x2,
        y2: y2,
        durationMs: durationMs,
        text: text,
        secretId: secretId,
        approvalGranted: approvalGranted ?? this.approvalGranted,
        approvalSource: approvalSource ?? this.approvalSource,
        captureIfSparse: captureIfSparse,
        sensitiveFlow: sensitiveFlow,
        artifactIds: artifactIds,
        riskClass: riskClass ?? this.riskClass,
        transactionPreviewDigest:
            transactionPreviewDigest ?? this.transactionPreviewDigest,
        transactionApprovalDigest:
            transactionApprovalDigest ?? this.transactionApprovalDigest,
        transactionApprovalId:
            transactionApprovalId ?? this.transactionApprovalId,
        preconditionSnapshotDigest:
            preconditionSnapshotDigest ?? this.preconditionSnapshotDigest,
      );
}

class DeviceAutomationProviderResult {
  const DeviceAutomationProviderResult({
    required this.success,
    required this.data,
    this.failureKind,
    this.recoveryActions = const [],
    this.artifactPaths = const [],
    this.artifactIds = const [],
  });

  final bool success;
  final Map<String, dynamic> data;
  final String? failureKind;
  final List<String> recoveryActions;
  final List<String> artifactPaths;
  final List<String> artifactIds;
}

typedef DeviceSecretResolver = Future<String?> Function(String secretId);

class DeviceAutomationRiskAssessment {
  const DeviceAutomationRiskAssessment({
    required this.success,
    required this.trusted,
    required this.riskClass,
    required this.policyId,
    required this.reason,
    required this.previewDigest,
    required this.frameDigest,
    required this.targetLabel,
    required this.targetLabelHash,
    this.failureKind,
    this.recoveryActions = const [],
  });

  final bool success;
  final bool trusted;
  final DeviceAutomationRiskClass riskClass;
  final String policyId;
  final String reason;
  final String previewDigest;
  final String frameDigest;
  final String targetLabel;
  final String targetLabelHash;
  final String? failureKind;
  final List<String> recoveryActions;

  Map<String, dynamic> toEvidenceJson() => {
        'trusted': trusted,
        'policyId': _safeToken(policyId, maxLength: 64),
        'riskClass': riskClass.name,
        'reason': _safeToken(reason, maxLength: 80),
        'previewDigest': _safeDigest(previewDigest),
        'frameDigest': _safeDigest(frameDigest),
        'targetLabel': _safeToken(targetLabel, maxLength: 96),
        'targetLabelHash': _safeDigest(targetLabelHash),
      };
}

abstract interface class DeviceAutomationRiskClassifier {
  Future<DeviceAutomationRiskAssessment> classifyRisk(
    DeviceAutomationRequest request,
  );
}

class DeviceAutomationApprovalTicket {
  const DeviceAutomationApprovalTicket({
    required this.id,
    required this.request,
    required this.assessment,
    required this.issuedAt,
    required this.expiresAt,
  });

  final String id;
  final DeviceAutomationRequest request;
  final DeviceAutomationRiskAssessment assessment;
  final DateTime issuedAt;
  final DateTime expiresAt;

  Map<String, dynamic> toEvidenceJson() => {
        'id': _safeToken(id, maxLength: 72),
        'issuedAt': issuedAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'oneShot': true,
        'rawTextIncludedInEvidence': false,
      };
}

class DeviceAutomationApprovalTicketStore {
  DeviceAutomationApprovalTicketStore({
    this.ttl = const Duration(seconds: 20),
  });

  static final shared = DeviceAutomationApprovalTicketStore();

  final Duration ttl;
  final Map<String, DeviceAutomationApprovalTicket> _tickets = {};
  final Random _random = Random.secure();

  DeviceAutomationApprovalTicket issue(
    DeviceAutomationRequest request,
    DeviceAutomationRiskAssessment assessment,
  ) {
    _removeExpired();
    final now = DateTime.now();
    final random = List<int>.generate(12, (_) => _random.nextInt(256))
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    final ticket = DeviceAutomationApprovalTicket(
      id: 'phone-approval-$random',
      request: request,
      assessment: assessment,
      issuedAt: now,
      expiresAt: now.add(ttl),
    );
    _tickets[ticket.id] = ticket;
    return ticket;
  }

  DeviceAutomationApprovalTicket? consume(String id) {
    final ticket = _tickets.remove(id);
    if (ticket == null || !ticket.expiresAt.isAfter(DateTime.now())) {
      return null;
    }
    return ticket;
  }

  void clear() => _tickets.clear();

  void _removeExpired() {
    final now = DateTime.now();
    _tickets.removeWhere((_, ticket) => !ticket.expiresAt.isAfter(now));
  }
}

final RegExp _phoneUseSecretSlotPattern = RegExp(r'^[A-Za-z0-9._-]{1,48}$');

typedef PhoneUseCredentialSlotWriter = Future<void> Function(
  String key,
  String value,
);
typedef PhoneUseCredentialSlotReader = Future<String?> Function(String key);
typedef PhoneUseCredentialSlotDeleter = Future<void> Function(String key);

/// Explicit provisioning seam for Phone Use credentials.
///
/// Callers can store, check, or delete a named slot, but cannot enumerate
/// values. Device actions receive only the slot ID; the value is resolved at
/// the final approved execution boundary and never enters ActionEvidence.
class PhoneUseCredentialSlotService {
  PhoneUseCredentialSlotService({
    PhoneUseCredentialSlotWriter? writer,
    PhoneUseCredentialSlotReader? reader,
    PhoneUseCredentialSlotDeleter? deleter,
  })  : _writer = writer ?? _writeSecureValue,
        _reader = reader ?? _readSecureValue,
        _deleter = deleter ?? _deleteSecureValue;

  final PhoneUseCredentialSlotWriter _writer;
  final PhoneUseCredentialSlotReader _reader;
  final PhoneUseCredentialSlotDeleter _deleter;

  bool isValidId(String slotId) => _phoneUseSecretSlotPattern.hasMatch(slotId);

  Future<void> store(String slotId, String value) async {
    if (!isValidId(slotId)) {
      throw ArgumentError.value(slotId, 'slotId', 'Invalid credential slot ID');
    }
    if (value.isEmpty) {
      throw ArgumentError.value('', 'value', 'Credential value is empty');
    }
    await _writer(_storageKey(slotId), value);
  }

  Future<bool> exists(String slotId) async {
    if (!isValidId(slotId)) return false;
    final value = await _reader(_storageKey(slotId));
    return value?.isNotEmpty == true;
  }

  Future<void> delete(String slotId) async {
    if (!isValidId(slotId)) {
      throw ArgumentError.value(slotId, 'slotId', 'Invalid credential slot ID');
    }
    await _deleter(_storageKey(slotId));
  }

  static String _storageKey(String slotId) => 'phone_use_slot_$slotId';

  static Future<void> _writeSecureValue(String key, String value) async {
    final storage = SecureStorageService();
    await storage.initialize();
    await storage.write(key, value);
  }

  static Future<String?> _readSecureValue(String key) async {
    final storage = SecureStorageService();
    await storage.initialize();
    return storage.read(key);
  }

  static Future<void> _deleteSecureValue(String key) async {
    final storage = SecureStorageService();
    await storage.initialize();
    await storage.delete(key);
  }
}

Future<String?> _resolvePhoneUseSecretSlot(String secretId) async {
  if (!_phoneUseSecretSlotPattern.hasMatch(secretId)) return null;
  try {
    final storage = SecureStorageService();
    await storage.initialize();
    return storage.read('phone_use_slot_$secretId');
  } on Object {
    // Credential resolution fails closed. The value and storage error must not
    // enter ActionEvidence or platform logs.
    return null;
  }
}

abstract class DeviceAutomationProvider {
  DeviceAutomationProviderType get type;
  String get name;

  Future<DeviceAutomationHealth> healthCheck();

  Future<DeviceAutomationProviderResult> execute(
    DeviceAutomationRequest request,
  );
}

/// Production app adapter. It never starts Node, ADB, or XCTest inside the APK.
class EmbeddedAccessibilityDeviceAutomationProvider
    implements DeviceAutomationProvider, DeviceAutomationRiskClassifier {
  EmbeddedAccessibilityDeviceAutomationProvider({
    PhoneUseAccessibilityService? service,
    DeviceSecretResolver? secretResolver,
  })  : service = service ?? PhoneUseAccessibilityService.instance,
        secretResolver = secretResolver ?? _resolvePhoneUseSecretSlot;

  final PhoneUseAccessibilityService service;
  final DeviceSecretResolver secretResolver;

  @override
  DeviceAutomationProviderType get type =>
      DeviceAutomationProviderType.embeddedAccessibility;

  @override
  String get name => 'Android embedded Accessibility';

  @override
  Future<DeviceAutomationHealth> healthCheck() async {
    final status = await service.getStatus();
    return DeviceAutomationHealth(
      available: status.supported,
      ready: status.ready,
      state: status.lifecycleState.wireValue,
      failureKind: status.blockedReason,
      recoveryActions: status.recoveryActions,
      capabilities: DeviceAutomationCapabilities(
        semanticSnapshots: status.canObserveActiveWindow,
        semanticRefs: status.canObserveActiveWindow,
        coordinateActions: status.canPerformGestures,
        screenshots: status.canCaptureScreenshot,
        video: false,
        logs: false,
        replay: false,
        physicalDevices: true,
        simulators: true,
      ),
    );
  }

  @override
  Future<DeviceAutomationProviderResult> execute(
    DeviceAutomationRequest request,
  ) async {
    if (request.action == DeviceAutomationActionKind.captureScreenshot) {
      return _captureScreenshot(request);
    }
    if (request.action == DeviceAutomationActionKind.replay) {
      return const DeviceAutomationProviderResult(
        success: false,
        data: {'status': 'blocked'},
        failureKind: 'replay_requires_external_agent_device_adapter',
        recoveryActions: [
          'Run replay through the Mac/CI agent-device QA adapter.',
        ],
      );
    }

    final payload = <String, dynamic>{
      'type': switch (request.action) {
        DeviceAutomationActionKind.observe => 'semantic_snapshot',
        DeviceAutomationActionKind.tapRef => 'tap_ref',
        DeviceAutomationActionKind.tapCoordinate => 'tap',
        DeviceAutomationActionKind.swipe => 'swipe',
        DeviceAutomationActionKind.setTextRef => 'set_text_ref',
        DeviceAutomationActionKind.setTextFocused => 'set_text',
        DeviceAutomationActionKind.back => 'global_back',
        DeviceAutomationActionKind.home => 'global_home',
        _ => 'unsupported',
      },
      'approved': request.approvalGranted,
      if (request.targetRef != null) 'ref': request.targetRef,
      if (request.x != null)
        if (request.action == DeviceAutomationActionKind.swipe)
          'x1': request.x
        else
          'x': request.x,
      if (request.y != null)
        if (request.action == DeviceAutomationActionKind.swipe)
          'y1': request.y
        else
          'y': request.y,
      if (request.x2 != null) 'x2': request.x2,
      if (request.y2 != null) 'y2': request.y2,
      if (request.durationMs != null) 'durationMs': request.durationMs,
      if (request.preconditionSnapshotDigest != null)
        'preconditionSnapshotDigest': request.preconditionSnapshotDigest,
    };

    if (request.action == DeviceAutomationActionKind.setTextRef ||
        request.action == DeviceAutomationActionKind.setTextFocused) {
      final text = await _resolveText(request);
      if (text == null) {
        return DeviceAutomationProviderResult(
          success: false,
          data: const {'status': 'blocked'},
          failureKind: request.secretId == null
              ? 'text_value_missing'
              : 'credential_slot_unavailable',
          recoveryActions: request.secretId == null
              ? const ['Provide text for the approved typed action.']
              : const [
                  'Unlock the approved credential slot and retry without exposing its value.',
                ],
        );
      }
      payload['text'] = text;
    }

    final data = await service.performAction(payload);
    final artifacts = <Map<String, dynamic>>[];
    if (_shouldCaptureSparseFallback(request, data)) {
      final screenshot = await service.captureScreenshot(
        approved: request.approvalGranted,
        sensitiveFlow: request.sensitiveFlow || request.secretId != null,
      );
      if (screenshot['status'] == 'passed') artifacts.add(screenshot);
    }
    final merged = artifacts.isEmpty ? data : {...data, 'artifacts': artifacts};
    return _fromMap(merged);
  }

  @override
  Future<DeviceAutomationRiskAssessment> classifyRisk(
    DeviceAutomationRequest request,
  ) async {
    final data = await service.performAction({
      'type': 'risk_preview',
      'requestedAction': _wireActionName(request.action),
      if (request.targetRef != null) 'ref': request.targetRef,
      if (request.x != null) 'x': request.x,
      if (request.y != null) 'y': request.y,
      if (request.x2 != null) 'x2': request.x2,
      if (request.y2 != null) 'y2': request.y2,
    });
    final raw = _mapValue(data['riskAssessment']);
    final trusted = raw?['trusted'] == true;
    final previewDigest = _nullableString(raw?['previewDigest']) ?? '';
    final frameDigest = _nullableString(raw?['frameDigest']) ?? '';
    final success = data['status'] == 'passed' &&
        data['accepted'] != false &&
        trusted &&
        _isFullSha256(previewDigest) &&
        _isFullSha256(frameDigest);
    final classifiedRisk = raw?['riskClass']?.toString() ==
            DeviceAutomationRiskClass.externalTransaction.name
        ? DeviceAutomationRiskClass.externalTransaction
        : DeviceAutomationRiskClass.reversible;
    return DeviceAutomationRiskAssessment(
      success: success,
      trusted: trusted,
      riskClass:
          request.riskClass == DeviceAutomationRiskClass.externalTransaction
              ? DeviceAutomationRiskClass.externalTransaction
              : classifiedRisk,
      policyId: _nullableString(raw?['policyId']) ?? 'unavailable',
      reason: _nullableString(raw?['reason']) ?? 'risk_preview_failed',
      previewDigest: previewDigest,
      frameDigest: frameDigest,
      targetLabel: _nullableString(raw?['targetLabel']) ?? '<unavailable>',
      targetLabelHash: _nullableString(raw?['targetLabelHash']) ?? '',
      failureKind: success
          ? null
          : (_nullableString(data['failureKind']) ??
              'trusted_risk_classification_failed'),
      recoveryActions: success
          ? const []
          : const [
              'Capture a new semantic snapshot and request the action again.',
              'Do not downgrade or bypass a failed trusted risk classification.',
            ],
    );
  }

  Future<String?> _resolveText(DeviceAutomationRequest request) async {
    if (request.secretId != null) {
      return secretResolver(request.secretId!);
    }
    return request.text;
  }

  bool _shouldCaptureSparseFallback(
    DeviceAutomationRequest request,
    Map<String, dynamic> data,
  ) {
    if (!request.captureIfSparse ||
        !request.approvalGranted ||
        request.sensitiveFlow ||
        request.secretId != null) {
      return false;
    }
    final snapshot = _mapValue(data['snapshot'] ?? data['observation']);
    return snapshot?['screenshotFallbackRecommended'] == true;
  }

  Future<DeviceAutomationProviderResult> _captureScreenshot(
    DeviceAutomationRequest request,
  ) async {
    if (request.sensitiveFlow || request.secretId != null) {
      return const DeviceAutomationProviderResult(
        success: false,
        data: {
          'status': 'blocked',
          'artifactSuppressedReason': 'credential_or_sensitive_flow',
        },
        failureKind: 'sensitive_artifact_capture_blocked',
        recoveryActions: [
          'Finish the credential step, move to a non-sensitive screen, then capture reviewed evidence.',
        ],
      );
    }
    return _fromMap(
      await service.captureScreenshot(
        approved: request.approvalGranted,
        sensitiveFlow: request.sensitiveFlow || request.secretId != null,
      ),
    );
  }

  DeviceAutomationProviderResult _fromMap(Map<String, dynamic> data) {
    final artifacts = <Map<String, dynamic>>[
      if (data['artifactId'] != null) data,
      ...?_mapList(data['artifacts']),
    ];
    return DeviceAutomationProviderResult(
      success: data['status'] == 'passed' && data['accepted'] != false,
      data: data,
      failureKind: _nullableString(data['failureKind']),
      recoveryActions: _stringList(data['recoveryActions']),
      artifactPaths: artifacts
          .map((item) => _nullableString(item['artifactPath']))
          .whereType<String>()
          .toList(growable: false),
      artifactIds: artifacts
          .map((item) => _nullableString(item['artifactId']))
          .whereType<String>()
          .toList(growable: false),
    );
  }
}

class DeviceAutomationExecution {
  const DeviceAutomationExecution({
    required this.result,
    required this.evidence,
  });

  final DeviceAutomationProviderResult result;
  final ActionEvidence evidence;

  bool get success => result.success && evidence.success;
}

/// Single approval/evidence seam shared by UI, tool calls, and tests.
class DeviceAutomationCoordinator {
  DeviceAutomationCoordinator({
    required this.provider,
    ActionEvidenceStore? evidenceStore,
    DeviceAutomationApprovalTicketStore? approvalTickets,
  })  : evidenceStore = evidenceStore ?? ActionEvidenceStore.shared,
        approvalTickets =
            approvalTickets ?? DeviceAutomationApprovalTicketStore.shared;

  final DeviceAutomationProvider provider;
  final ActionEvidenceStore evidenceStore;
  final DeviceAutomationApprovalTicketStore approvalTickets;

  Future<DeviceAutomationExecution> previewForApproval(
    DeviceAutomationRequest request, {
    String? evidenceId,
    bool persistEvidence = true,
  }) async {
    final startedAt = DateTime.now();
    if (!request.requiresApproval) {
      return execute(
        request,
        evidenceId: evidenceId,
        persistEvidence: persistEvidence,
      );
    }
    final classifier = provider is DeviceAutomationRiskClassifier
        ? provider as DeviceAutomationRiskClassifier
        : null;
    if (classifier == null) {
      const result = DeviceAutomationProviderResult(
        success: false,
        data: {'status': 'blocked'},
        failureKind: 'trusted_risk_classifier_unavailable',
        recoveryActions: [
          'Connect a device provider with a trusted action-risk classifier.',
        ],
      );
      return _record(
        request,
        startedAt,
        result,
        evidenceId: evidenceId,
        persistEvidence: persistEvidence,
      );
    }
    final assessment = await classifier.classifyRisk(request);
    if (!assessment.success || !assessment.trusted) {
      final result = DeviceAutomationProviderResult(
        success: false,
        data: {
          'status': 'blocked',
          'riskAssessment': assessment.toEvidenceJson(),
        },
        failureKind:
            assessment.failureKind ?? 'trusted_risk_classification_failed',
        recoveryActions: assessment.recoveryActions,
      );
      return _record(
        request,
        startedAt,
        result,
        evidenceId: evidenceId,
        persistEvidence: persistEvidence,
      );
    }
    final assessedRequest = request.copyWith(
      riskClass: assessment.riskClass,
      transactionPreviewDigest: assessment.previewDigest,
      preconditionSnapshotDigest: assessment.frameDigest,
    );
    final ticket = approvalTickets.issue(assessedRequest, assessment);
    final result = DeviceAutomationProviderResult(
      success: false,
      data: {
        'status': 'approvalRequired',
        'riskAssessment': assessment.toEvidenceJson(),
        'approvalTicket': ticket.toEvidenceJson(),
      },
      failureKind: 'approval_required',
      recoveryActions: const [
        'Review the trusted target and risk preview, then approve this one-shot ticket.',
      ],
    );
    return _record(
      assessedRequest,
      startedAt,
      result,
      evidenceId: evidenceId,
      persistEvidence: persistEvidence,
    );
  }

  Future<DeviceAutomationExecution?> executeApprovedTicket(
    String ticketId, {
    required String approvalId,
    String approvalSource = 'agent_trace_user_tap',
    bool persistEvidence = true,
  }) async {
    final ticket = approvalTickets.consume(ticketId);
    if (ticket == null) return null;
    final requiresTransaction = ticket.assessment.riskClass ==
        DeviceAutomationRiskClass.externalTransaction;
    final approvedRequest = ticket.request.copyWith(
      approvalGranted: true,
      approvalSource: approvalSource,
      transactionApprovalDigest:
          requiresTransaction ? ticket.assessment.previewDigest : null,
      transactionApprovalId: requiresTransaction ? approvalId : null,
    );
    return execute(
      approvedRequest,
      persistEvidence: persistEvidence,
    );
  }

  Future<DeviceAutomationExecution> execute(
    DeviceAutomationRequest request, {
    String? evidenceId,
    bool persistEvidence = true,
  }) async {
    final startedAt = DateTime.now();
    if (request.requiresApproval && !request.approvalGranted) {
      const result = DeviceAutomationProviderResult(
        success: false,
        data: {'status': 'blocked'},
        failureKind: 'approval_required',
        recoveryActions: [
          'Preview the phone action and obtain explicit user approval.',
        ],
      );
      return _record(
        request,
        startedAt,
        result,
        evidenceId: evidenceId,
        persistEvidence: persistEvidence,
      );
    }
    if (!request.transactionApprovalSatisfied) {
      const result = DeviceAutomationProviderResult(
        success: false,
        data: {'status': 'blocked'},
        failureKind: 'transaction_approval_required',
        recoveryActions: [
          'Show the final order preview and obtain a separate approval bound to its current digest.',
          'Do not auto-retry an external transaction after this gate blocks it.',
        ],
      );
      return _record(
        request,
        startedAt,
        result,
        evidenceId: evidenceId,
        persistEvidence: persistEvidence,
      );
    }

    final result = await provider.execute(request);
    return _record(
      request,
      startedAt,
      result,
      evidenceId: evidenceId,
      persistEvidence: persistEvidence,
    );
  }

  DeviceAutomationExecution _record(
    DeviceAutomationRequest request,
    DateTime startedAt,
    DeviceAutomationProviderResult result, {
    String? evidenceId,
    required bool persistEvidence,
  }) {
    final data = result.data;
    final preSnapshot = _mapValue(data['preSnapshot']);
    final postSnapshot = _mapValue(data['postSnapshot'] ?? data['snapshot']);
    final screenshotArtifacts = _mapList(data['artifacts']) ?? const [];
    final artifactMetadata = <Map<String, dynamic>>[
      if (data['artifactId'] != null) _safeArtifact(data),
      ...screenshotArtifacts.map(_safeArtifact),
    ];
    final evidence = ActionEvidence(
      evidenceId: evidenceId ?? generateEvidenceId(),
      actionName: switch (request.action) {
        DeviceAutomationActionKind.observe => MobileCodeAction.phoneUseObserve,
        DeviceAutomationActionKind.captureScreenshot =>
          MobileCodeAction.phoneUseCapture,
        DeviceAutomationActionKind.replay => MobileCodeAction.phoneUseReplay,
        _ => MobileCodeAction.phoneUseAct,
      },
      paramsSummary: request.safeSummary,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      success: result.success,
      artifactPaths: result.artifactPaths,
      logs: [
        'Device automation ${request.action.name} ${result.success ? 'completed' : 'blocked'} through ${provider.name}.',
      ],
      failureKind: result.failureKind,
      recoveryActions: result.recoveryActions,
      metadata: {
        'provider': {
          'type': provider.type.name,
          'name': provider.name,
        },
        'deviceAction': request.action.name,
        if (request.targetRef != null)
          'targetRef': _safeToken(request.targetRef!),
        if (request.x != null && request.y != null)
          'coordinate': {
            'x': request.x,
            'y': request.y,
            if (request.x2 != null) 'x2': request.x2,
            if (request.y2 != null) 'y2': request.y2,
          },
        if (request.secretId != null)
          'credentialSlot': _safeToken(request.secretId!, maxLength: 48),
        'approval': {
          'required': request.requiresApproval,
          'granted': request.approvalGranted,
          'source': _safeToken(request.approvalSource, maxLength: 40),
        },
        'transactionApproval': {
          'required': request.requiresTransactionApproval,
          'granted': request.transactionApprovalSatisfied,
          'previewDigest': _safeDigest(request.transactionPreviewDigest),
          'approvalDigest': _safeDigest(request.transactionApprovalDigest),
          'digestMatched':
              request.transactionPreviewDigest?.isNotEmpty == true &&
                  request.transactionApprovalDigest ==
                      request.transactionPreviewDigest,
          if (request.transactionApprovalId != null)
            'approvalId':
                _safeToken(request.transactionApprovalId!, maxLength: 64),
        },
        if (data['riskAssessment'] is Map)
          'riskAssessment': Map<String, dynamic>.from(
            data['riskAssessment'] as Map,
          ),
        if (data['approvalTicket'] is Map)
          'approvalTicket': Map<String, dynamic>.from(
            data['approvalTicket'] as Map,
          ),
        'snapshotEvidence': {
          'preDigest': data['preSnapshotDigest'] ?? preSnapshot?['digest'],
          'postDigest': data['postSnapshotDigest'] ?? postSnapshot?['digest'],
          'frame': _safeFrame(_mapValue(data['refFrame'])),
          'pre': _safeSnapshot(preSnapshot),
          'post': _safeSnapshot(postSnapshot),
        },
        'resolution': _safeResolution(_mapValue(data['resolution'])),
        'surface': {
          'packageNameHash': data['currentPackageNameHash'] ??
              postSnapshot?['rootPackageNameHash'],
          'className':
              data['currentClassName'] ?? postSnapshot?['rootClassName'],
        },
        'artifactIds': {...request.artifactIds, ...result.artifactIds}.toList(),
        if (artifactMetadata.isNotEmpty) 'artifacts': artifactMetadata,
        'device': _safeDevice(_mapValue(data['device'])),
        'redaction': {
          'rawTextIncluded': false,
          'textValueStored': false,
          'credentialValueStored': false,
          'redactionApplied': data['redactionApplied'] != false,
          'sensitiveArtifactCaptureBlocked':
              request.sensitiveFlow || request.secretId != null,
        },
        'execution': {
          'startedAt': startedAt.toIso8601String(),
          'endedAt': DateTime.now().toIso8601String(),
          'countsAsExperiment': false,
          'countsAsStrategyAblationResult': false,
        },
      },
    );
    if (persistEvidence) evidenceStore.add(evidence);
    return DeviceAutomationExecution(result: result, evidence: evidence);
  }
}

Map<String, dynamic> _safeSnapshot(Map<String, dynamic>? value) {
  if (value == null) return const {};
  return {
    'frameId': value['frameId'],
    'refsGeneration': value['refsGeneration'],
    'frameState': value['frameState'] ?? value['state'],
    'digest': value['digest'],
    'captureMode': value['captureMode'],
    'interactiveNodeCount': value['interactiveNodeCount'],
    'nodeCount': value['nodeCount'],
    'truncated': value['truncated'],
    'rootPackageNameHash': value['rootPackageNameHash'],
    'rootClassName': value['rootClassName'],
    'screenshotFallbackRecommended': value['screenshotFallbackRecommended'],
    if (value['coordinateContract'] is Map)
      'coordinateContract': value['coordinateContract'],
  };
}

Map<String, dynamic> _safeFrame(Map<String, dynamic>? value) {
  if (value == null) return const {};
  return {
    'frameId': value['frameId'],
    'refsGeneration': value['refsGeneration'],
    'state': value['state'],
    'digest': value['digest'],
    'issuedRefCount': value['issuedRefCount'],
    'expiredReason': value['expiredReason'],
  };
}

Map<String, dynamic> _safeResolution(Map<String, dynamic>? value) {
  if (value == null) return const {};
  return {
    'kind': value['kind'],
    'ref': value['ref'],
    'refsGeneration': value['refsGeneration'],
    'identityHash': value['identityHash'],
    'currentIdentityMatched': value['currentIdentityMatched'],
    'currentGeneration': value['currentGeneration'],
    'mintedGeneration': value['mintedGeneration'],
    'frameState': value['frameState'],
    if (value['coordinateContract'] is Map)
      'coordinateContract': value['coordinateContract'],
  };
}

Map<String, dynamic> _safeDevice(Map<String, dynamic>? value) {
  if (value == null) return const {};
  return {
    'platform': value['platform'],
    'manufacturer': value['manufacturer'],
    'model': value['model'],
    'androidVersion': value['androidVersion'],
    'sdkInt': value['sdkInt'],
    'appPackageHash': value['appPackageHash'],
  };
}

Map<String, dynamic> _safeArtifact(Map<String, dynamic> value) => {
      'artifactId': value['artifactId'],
      'artifactKind': value['artifactKind'],
      'sha256': value['sha256'],
      'width': value['width'],
      'height': value['height'],
      'localOnly': value['localOnly'] == true,
      'containsPotentiallySensitiveUi':
          value['containsPotentiallySensitiveUi'] == true,
      'shareableWithoutReview': value['shareableWithoutReview'] == true,
      if (value['coordinateContract'] is Map)
        'coordinateContract': value['coordinateContract'],
    };

String _safeToken(String value, {int maxLength = 80}) =>
    value.replaceAll(RegExp(r'[^A-Za-z0-9@._~:-]'), '_').takeSafe(maxLength);

String? _safeDigest(String? value) {
  if (value == null || value.isEmpty) return null;
  final normalized = value.replaceAll(RegExp(r'[^A-Fa-f0-9]'), '');
  return normalized.isEmpty ? null : normalized.takeSafe(128);
}

bool _isFullSha256(String value) =>
    RegExp(r'^[A-Fa-f0-9]{64}$').hasMatch(value);

extension on String {
  String takeSafe(int count) => length <= count ? this : substring(0, count);
}

Map<String, dynamic>? _mapValue(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

List<Map<String, dynamic>>? _mapList(Object? value) {
  if (value is! List) return null;
  return value
      .whereType<Map<Object?, Object?>>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.map((item) => item.toString()).toList(growable: false);
}

String? _nullableString(Object? value) {
  final text = value?.toString();
  return text == null || text.isEmpty ? null : text;
}

String _wireActionName(DeviceAutomationActionKind action) => switch (action) {
      DeviceAutomationActionKind.observe => 'semantic_snapshot',
      DeviceAutomationActionKind.tapRef => 'tap_ref',
      DeviceAutomationActionKind.tapCoordinate => 'tap',
      DeviceAutomationActionKind.swipe => 'swipe',
      DeviceAutomationActionKind.setTextRef => 'set_text_ref',
      DeviceAutomationActionKind.setTextFocused => 'set_text',
      DeviceAutomationActionKind.back => 'global_back',
      DeviceAutomationActionKind.home => 'global_home',
      DeviceAutomationActionKind.captureScreenshot => 'capture_screenshot',
      DeviceAutomationActionKind.replay => 'replay',
    };
