import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/core/evidence/action_evidence_store.dart';
import 'package:mobile_agent/services/device_automation_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('mobilecode/system_tools');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('mutation is blocked before provider execution without approval',
      () async {
    final provider = _FakeProvider();
    final store = ActionEvidenceStore();
    final coordinator = DeviceAutomationCoordinator(
      provider: provider,
      evidenceStore: store,
    );

    final execution = await coordinator.execute(
      const DeviceAutomationRequest(
        action: DeviceAutomationActionKind.tapRef,
        targetRef: '@e2~s4',
      ),
    );

    expect(provider.requests, isEmpty);
    expect(execution.success, isFalse);
    expect(execution.result.failureKind, 'approval_required');
    expect(store.length, 1);
    expect(
      execution.evidence.metadata['approval'],
      {'required': true, 'granted': false, 'source': 'none'},
    );
  });

  test('semantic observation records digests, ref frame, surface and device',
      () async {
    final provider = _FakeProvider(
      result: const DeviceAutomationProviderResult(
        success: true,
        data: {
          'status': 'passed',
          'preSnapshotDigest': 'pre-123',
          'postSnapshotDigest': 'post-456',
          'refFrame': {
            'frameId': 's8',
            'refsGeneration': 8,
            'state': 'active',
            'digest': 'post-456',
            'issuedRefCount': 3,
          },
          'snapshot': {
            'frameId': 's8',
            'refsGeneration': 8,
            'frameState': 'active',
            'digest': 'post-456',
            'rootPackageNameHash': 'pkg-a1',
            'rootClassName': 'android.widget.FrameLayout',
            'coordinateContract': {
              'sourceSpace': 'accessibility_screen_px',
              'inputSpace': 'gesture_screen_px',
              'sourceWidth': 1080,
              'sourceHeight': 2400,
              'inputWidth': 1080,
              'inputHeight': 2400,
              'scaleX': 1.0,
              'scaleY': 1.0,
              'origin': 'top_left',
            },
          },
          'device': {
            'platform': 'android',
            'model': 'Pixel 7',
            'sdkInt': 36,
          },
          'redactionApplied': true,
        },
      ),
    );
    final coordinator = DeviceAutomationCoordinator(provider: provider);

    final execution = await coordinator.execute(
      const DeviceAutomationRequest(
        action: DeviceAutomationActionKind.observe,
      ),
    );
    final metadata = execution.evidence.metadata;

    expect(execution.success, isTrue);
    expect(
      (metadata['snapshotEvidence'] as Map)['postDigest'],
      'post-456',
    );
    expect(
      ((metadata['snapshotEvidence'] as Map)['frame'] as Map)['frameId'],
      's8',
    );
    expect((metadata['surface'] as Map)['packageNameHash'], 'pkg-a1');
    expect((metadata['device'] as Map)['sdkInt'], 36);
  });

  test('credential slot is resolved only at execution and value is never saved',
      () async {
    const secretValue = 'never-store-this-OAuth-value';
    Map<String, dynamic>? platformAction;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'performPhoneUseAction');
      final arguments = Map<String, dynamic>.from(call.arguments as Map);
      platformAction = Map<String, dynamic>.from(arguments['action'] as Map);
      return {
        'status': 'passed',
        'accepted': true,
        'requestedAction': 'set_text_ref',
        'preSnapshotDigest': 'before',
        'postSnapshotDigest': 'after',
        'redactionApplied': true,
      };
    });
    final provider = EmbeddedAccessibilityDeviceAutomationProvider(
      secretResolver: (slot) async {
        expect(slot, 'github.oauth.primary');
        return secretValue;
      },
    );
    final coordinator = DeviceAutomationCoordinator(provider: provider);

    final execution = await coordinator.execute(
      const DeviceAutomationRequest(
        action: DeviceAutomationActionKind.setTextRef,
        targetRef: '@e1~s2',
        secretId: 'github.oauth.primary',
        approvalGranted: true,
        approvalSource: 'user_tap',
        sensitiveFlow: true,
      ),
    );

    expect(platformAction?['text'], secretValue);
    expect(platformAction?['ref'], '@e1~s2');
    final encodedEvidence = jsonEncode(execution.evidence.toJson());
    expect(encodedEvidence, isNot(contains(secretValue)));
    expect(encodedEvidence, contains('github.oauth.primary'));
    expect(
      (execution.evidence.metadata['redaction']
          as Map)['credentialValueStored'],
      isFalse,
    );
  });

  test(
      'default credential resolver rejects invalid slot ids before platform IO',
      () async {
    var platformCalled = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      platformCalled = true;
      return <String, dynamic>{};
    });
    final coordinator = DeviceAutomationCoordinator(
      provider: EmbeddedAccessibilityDeviceAutomationProvider(),
    );

    final execution = await coordinator.execute(
      const DeviceAutomationRequest(
        action: DeviceAutomationActionKind.setTextFocused,
        secretId: '../provider-key',
        approvalGranted: true,
        approvalSource: 'user_tap',
        sensitiveFlow: true,
      ),
    );

    expect(platformCalled, isFalse);
    expect(execution.success, isFalse);
    expect(execution.result.failureKind, 'credential_slot_unavailable');
  });

  test('credential slot provisioning is bounded and non-enumerable', () async {
    final values = <String, String>{};
    final service = PhoneUseCredentialSlotService(
      writer: (key, value) async => values[key] = value,
      reader: (key) async => values[key],
      deleter: (key) async => values.remove(key),
    );

    await service.store('takeout.qa.password', 'controlled-fake-value');
    expect(await service.exists('takeout.qa.password'), isTrue);
    expect(values.keys, ['phone_use_slot_takeout.qa.password']);
    expect(service.isValidId('../escape'), isFalse);
    expect(
      () => service.store('../escape', 'value'),
      throwsArgumentError,
    );

    await service.delete('takeout.qa.password');
    expect(await service.exists('takeout.qa.password'), isFalse);
  });

  test('screenshot is suppressed throughout a sensitive flow', () async {
    var platformCalled = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      platformCalled = true;
      return <String, dynamic>{};
    });
    final coordinator = DeviceAutomationCoordinator(
      provider: EmbeddedAccessibilityDeviceAutomationProvider(),
    );

    final execution = await coordinator.execute(
      const DeviceAutomationRequest(
        action: DeviceAutomationActionKind.captureScreenshot,
        approvalGranted: true,
        approvalSource: 'user_tap',
        sensitiveFlow: true,
      ),
    );

    expect(platformCalled, isFalse);
    expect(execution.success, isFalse);
    expect(execution.result.failureKind, 'sensitive_artifact_capture_blocked');
    expect(execution.evidence.artifactPaths, isEmpty);
  });

  test('swipe maps coordinator coordinates to the native x1/y1 contract',
      () async {
    Map<String, dynamic>? platformAction;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final arguments = Map<String, dynamic>.from(call.arguments as Map);
      platformAction = Map<String, dynamic>.from(arguments['action'] as Map);
      return {'status': 'passed', 'accepted': true};
    });
    final coordinator = DeviceAutomationCoordinator(
      provider: EmbeddedAccessibilityDeviceAutomationProvider(),
    );

    final execution = await coordinator.execute(
      const DeviceAutomationRequest(
        action: DeviceAutomationActionKind.swipe,
        x: 400,
        y: 900,
        x2: 400,
        y2: 300,
        approvalGranted: true,
        approvalSource: 'user_tap',
      ),
    );

    expect(execution.success, isTrue);
    expect(platformAction, containsPair('x1', 400));
    expect(platformAction, containsPair('y1', 900));
    expect(platformAction, containsPair('x2', 400));
    expect(platformAction, containsPair('y2', 300));
    expect(platformAction, isNot(contains('x')));
    expect(platformAction, isNot(contains('y')));
  });

  test('typed stale-ref failure is preserved in unified evidence', () async {
    final provider = _FakeProvider(
      result: const DeviceAutomationProviderResult(
        success: false,
        failureKind: 'ref_frame_expired',
        recoveryActions: ['Capture a new semantic snapshot and use its refs.'],
        data: {
          'status': 'blocked',
          'refFrame': {
            'frameId': 's10',
            'refsGeneration': 10,
            'state': 'expired',
            'expiredReason': 'mutation:tap_ref',
          },
          'resolution': {
            'kind': 'semantic_ref',
            'ref': '@e1~s10',
            'frameState': 'expired',
          },
        },
      ),
    );
    final coordinator = DeviceAutomationCoordinator(provider: provider);

    final execution = await coordinator.execute(
      const DeviceAutomationRequest(
        action: DeviceAutomationActionKind.tapRef,
        targetRef: '@e1~s10',
        approvalGranted: true,
        approvalSource: 'user_tap',
      ),
    );

    expect(execution.result.failureKind, 'ref_frame_expired');
    expect(execution.evidence.failureKind, 'ref_frame_expired');
    expect(
      (execution.evidence.metadata['resolution'] as Map)['frameState'],
      'expired',
    );
  });

  test('external transaction is blocked after normal action approval',
      () async {
    final provider = _FakeProvider();
    final coordinator = DeviceAutomationCoordinator(provider: provider);

    final execution = await coordinator.execute(
      const DeviceAutomationRequest(
        action: DeviceAutomationActionKind.tapRef,
        targetRef: '@e9~s12',
        approvalGranted: true,
        approvalSource: 'user_tap',
        riskClass: DeviceAutomationRiskClass.externalTransaction,
        transactionPreviewDigest: 'aabbccdd',
      ),
    );

    expect(provider.requests, isEmpty);
    expect(execution.result.failureKind, 'transaction_approval_required');
    expect(
      execution.evidence.recoveryActions,
      contains(contains('Do not auto-retry')),
    );
    expect(
      execution.evidence.metadata['transactionApproval'],
      containsPair('granted', false),
    );
  });

  test('external transaction approval is bound to current preview digest',
      () async {
    final provider = _FakeProvider();
    final coordinator = DeviceAutomationCoordinator(provider: provider);

    final mismatch = await coordinator.execute(
      const DeviceAutomationRequest(
        action: DeviceAutomationActionKind.tapRef,
        targetRef: '@e9~s12',
        approvalGranted: true,
        approvalSource: 'final_order_confirmation',
        riskClass: DeviceAutomationRiskClass.externalTransaction,
        transactionPreviewDigest: 'aabbccdd',
        transactionApprovalDigest: '11223344',
        transactionApprovalId: 'approval-order-qa-1',
      ),
    );
    expect(mismatch.success, isFalse);
    expect(provider.requests, isEmpty);

    final approved = await coordinator.execute(
      const DeviceAutomationRequest(
        action: DeviceAutomationActionKind.tapRef,
        targetRef: '@e9~s12',
        approvalGranted: true,
        approvalSource: 'final_order_confirmation',
        riskClass: DeviceAutomationRiskClass.externalTransaction,
        transactionPreviewDigest: 'aabbccdd',
        transactionApprovalDigest: 'aabbccdd',
        transactionApprovalId: 'approval-order-qa-1',
      ),
    );

    expect(approved.success, isTrue);
    expect(provider.requests, hasLength(1));
    expect(
      approved.evidence.metadata['transactionApproval'],
      containsPair('digestMatched', true),
    );
  });

  test('trusted classifier issues a page-bound one-shot transaction ticket',
      () async {
    final tickets = DeviceAutomationApprovalTicketStore(
      ttl: const Duration(seconds: 20),
    );
    final provider = _RiskFakeProvider(
      assessment: const DeviceAutomationRiskAssessment(
        success: true,
        trusted: true,
        riskClass: DeviceAutomationRiskClass.externalTransaction,
        policyId: 'phone_use_transaction_risk_v1',
        reason: 'trusted_policy_high_impact_label',
        previewDigest:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        frameDigest:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        targetLabel: 'Confirm order',
        targetLabelHash:
            'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
      ),
    );
    final coordinator = DeviceAutomationCoordinator(
      provider: provider,
      approvalTickets: tickets,
    );

    final preview = await coordinator.previewForApproval(
      const DeviceAutomationRequest(
        action: DeviceAutomationActionKind.tapRef,
        targetRef: '@e7~s4',
      ),
    );

    expect(provider.requests, isEmpty);
    expect(preview.result.failureKind, 'approval_required');
    expect(
      preview.evidence.metadata['riskAssessment'],
      containsPair('riskClass', 'externalTransaction'),
    );
    final ticket = preview.evidence.metadata['approvalTicket'] as Map;
    expect(ticket['oneShot'], isTrue);
    expect(ticket['expiresAt'], isNotNull);

    final approved = await coordinator.executeApprovedTicket(
      ticket['id'] as String,
      approvalId: 'user-approval-1',
    );
    expect(approved, isNotNull);
    expect(approved!.success, isTrue);
    expect(provider.requests, hasLength(1));
    expect(provider.requests.single.approvalGranted, isTrue);
    expect(
      provider.requests.single.preconditionSnapshotDigest,
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    );
    expect(
      provider.requests.single.transactionApprovalDigest,
      provider.requests.single.transactionPreviewDigest,
    );

    final replay = await coordinator.executeApprovedTicket(
      ticket['id'] as String,
      approvalId: 'user-approval-2',
    );
    expect(replay, isNull);
    expect(provider.requests, hasLength(1));
  });

  test('expired approval ticket fails closed without provider execution',
      () async {
    final tickets = DeviceAutomationApprovalTicketStore(ttl: Duration.zero);
    final provider = _RiskFakeProvider();
    final coordinator = DeviceAutomationCoordinator(
      provider: provider,
      approvalTickets: tickets,
    );
    final preview = await coordinator.previewForApproval(
      const DeviceAutomationRequest(
        action: DeviceAutomationActionKind.back,
      ),
    );
    final ticket = preview.evidence.metadata['approvalTicket'] as Map;

    final execution = await coordinator.executeApprovedTicket(
      ticket['id'] as String,
      approvalId: 'expired-approval',
    );

    expect(execution, isNull);
    expect(provider.requests, isEmpty);
  });

  test('controlled credential slot stays secret through preview and approval',
      () async {
    const secretValue = 'fake-account-password-never-in-evidence';
    var riskPreviewCalls = 0;
    var executionCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final arguments = Map<String, dynamic>.from(call.arguments as Map);
      final action = Map<String, dynamic>.from(arguments['action'] as Map);
      if (action['type'] == 'risk_preview') {
        riskPreviewCalls += 1;
        expect(action['requestedAction'], 'set_text_ref');
        expect(action, isNot(contains('text')));
        return {
          'status': 'passed',
          'accepted': true,
          'riskAssessment': {
            'trusted': true,
            'policyId': 'phone_use_transaction_risk_v1',
            'riskClass': 'reversible',
            'reason': 'trusted_policy_reversible_action',
            'previewDigest':
                'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
            'frameDigest':
                'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
            'targetLabel': '<editable>',
            'targetLabelHash':
                'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
          },
        };
      }
      executionCalls += 1;
      expect(action['type'], 'set_text_ref');
      expect(action['text'], secretValue);
      expect(
        action['preconditionSnapshotDigest'],
        'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
      );
      return {'status': 'passed', 'accepted': true, 'redactionApplied': true};
    });
    final tickets = DeviceAutomationApprovalTicketStore();
    final coordinator = DeviceAutomationCoordinator(
      provider: EmbeddedAccessibilityDeviceAutomationProvider(
        secretResolver: (slot) async {
          expect(slot, 'takeout.qa.password');
          return secretValue;
        },
      ),
      approvalTickets: tickets,
    );
    final preview = await coordinator.previewForApproval(
      const DeviceAutomationRequest(
        action: DeviceAutomationActionKind.setTextRef,
        targetRef: '@e2~s8',
        secretId: 'takeout.qa.password',
        sensitiveFlow: true,
      ),
    );
    final previewJson = jsonEncode(preview.evidence.toJson());
    expect(previewJson, isNot(contains(secretValue)));
    final ticket = preview.evidence.metadata['approvalTicket'] as Map;

    final approved = await coordinator.executeApprovedTicket(
      ticket['id'] as String,
      approvalId: 'controlled-account-user-tap',
    );

    expect(approved, isNotNull);
    expect(approved!.success, isTrue);
    expect(riskPreviewCalls, 1);
    expect(executionCalls, 1);
    expect(
        jsonEncode(approved.evidence.toJson()), isNot(contains(secretValue)));
    expect(jsonEncode(approved.evidence.toJson()),
        contains('takeout.qa.password'));
  });
}

class _FakeProvider implements DeviceAutomationProvider {
  _FakeProvider({
    this.result = const DeviceAutomationProviderResult(
      success: true,
      data: {'status': 'passed'},
    ),
  });

  final DeviceAutomationProviderResult result;
  final List<DeviceAutomationRequest> requests = [];

  @override
  String get name => 'fake-provider';

  @override
  DeviceAutomationProviderType get type =>
      DeviceAutomationProviderType.agentDeviceQa;

  @override
  Future<DeviceAutomationProviderResult> execute(
    DeviceAutomationRequest request,
  ) async {
    requests.add(request);
    return result;
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

class _RiskFakeProvider extends _FakeProvider
    implements DeviceAutomationRiskClassifier {
  _RiskFakeProvider({
    DeviceAutomationRiskAssessment? assessment,
  }) : assessment = assessment ??
            const DeviceAutomationRiskAssessment(
              success: true,
              trusted: true,
              riskClass: DeviceAutomationRiskClass.reversible,
              policyId: 'phone_use_transaction_risk_v1',
              reason: 'trusted_policy_reversible_action',
              previewDigest:
                  '1111111111111111111111111111111111111111111111111111111111111111',
              frameDigest:
                  '2222222222222222222222222222222222222222222222222222222222222222',
              targetLabel: 'Back',
              targetLabelHash:
                  '3333333333333333333333333333333333333333333333333333333333333333',
            );

  final DeviceAutomationRiskAssessment assessment;
  final List<DeviceAutomationRequest> riskRequests = [];

  @override
  Future<DeviceAutomationRiskAssessment> classifyRisk(
    DeviceAutomationRequest request,
  ) async {
    riskRequests.add(request);
    return assessment;
  }
}
