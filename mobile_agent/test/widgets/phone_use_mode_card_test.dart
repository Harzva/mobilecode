import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/device_automation_provider.dart';
import 'package:mobile_agent/widgets/phone_use_mode_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('mobilecode/system_tools');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('shows permission-gated non-counted phone-use status',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getPhoneUseAccessibilityStatus':
          return _status(accessibilityEnabled: false, serviceConnected: false);
        default:
          return false;
      }
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: PhoneUseModeCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mobile Phone Use'), findsOneWidget);
    expect(find.text('Permission gated'), findsOneWidget);
    expect(find.text('counts_as_experiment=false'), findsWidgets);
    expect(find.textContaining('Accessibility: enabled=false'), findsOneWidget);
    expect(
      find.textContaining('Blocked reason: accessibility_permission_required'),
      findsOneWidget,
    );
  });

  testWidgets('runs dry probe and renders blocked evidence', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getPhoneUseAccessibilityStatus':
          return _status(accessibilityEnabled: false, serviceConnected: false);
        case 'performPhoneUseAction':
          expect((call.arguments as Map)['action'], {
            'type': 'semantic_snapshot',
            'approved': false,
          });
          return {
            'status': 'blocked',
            'requestedAction': 'semantic_snapshot',
            'failureKind': 'accessibility_permission_required',
            'countsAsExperiment': false,
            'countsAsStrategyAblationResult': false,
            'rawTextIncluded': false,
            'redactionApplied': true,
          };
        default:
          return false;
      }
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: PhoneUseModeCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Run dry probe'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Dry probe status: blocked'), findsOneWidget);
    expect(
      find.textContaining('Blocked reason: accessibility_permission_required'),
      findsOneWidget,
    );
    expect(find.textContaining('raw_text_included=false'), findsOneWidget);
  });

  testWidgets('re-observes after focusing an editable semantic target',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getPhoneUseAccessibilityStatus') {
        return _status(accessibilityEnabled: true, serviceConnected: true);
      }
      return false;
    });
    var observeCount = 0;
    var setTextUsedRefreshedGeneration = false;
    final provider = _ActionProbeProvider((request) async {
      if (request.action == DeviceAutomationActionKind.observe) {
        observeCount += 1;
        final generation = 6 + observeCount;
        return DeviceAutomationProviderResult(
          success: true,
          data: {
            'status': 'passed',
            'snapshot': {
              'canObserveActiveWindow': true,
              'frameId': 's$generation',
              'refsGeneration': generation,
              'frameState': 'active',
              'digest': 'snapshot-$generation',
              'interactiveNodes': [
                {
                  'ref': '@e$observeCount',
                  'role': 'EditText',
                  'label': 'Probe target',
                  'identityHash': 'probe-editable',
                  'bounds': {'left': 10, 'top': 20, 'right': 200, 'bottom': 80},
                  'actions': ['set_text'],
                  'clickable': true,
                  'editable': true,
                  'enabled': true,
                  'sensitive': false,
                },
              ],
              'nodeCount': 1,
              'interactiveNodeCount': 1,
              'rawTextIncluded': false,
              'redactionApplied': true,
            },
          },
        );
      }
      if (request.action == DeviceAutomationActionKind.tapRef) {
        expect(request.targetRef, '@e1~s7');
      }
      if (request.action == DeviceAutomationActionKind.setTextRef) {
        setTextUsedRefreshedGeneration = request.targetRef == '@e2~s8';
      }
      return const DeviceAutomationProviderResult(
        success: true,
        data: {'status': 'passed', 'accepted': true},
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PhoneUseModeCard(
              deviceAutomationCoordinator:
                  DeviceAutomationCoordinator(provider: provider),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Run action probe'));
    await tester.tap(find.text('Run action probe'));
    await tester.pumpAndSettle();

    expect(setTextUsedRefreshedGeneration, isTrue);
    expect(provider.requests.map((request) => request.action), [
      DeviceAutomationActionKind.observe,
      DeviceAutomationActionKind.tapRef,
      DeviceAutomationActionKind.observe,
      DeviceAutomationActionKind.setTextRef,
      DeviceAutomationActionKind.tapCoordinate,
      DeviceAutomationActionKind.swipe,
    ]);
  });

  testWidgets('stores a controlled credential slot without rendering its value',
      (tester) async {
    final values = <String, String>{};
    final slots = PhoneUseCredentialSlotService(
      writer: (key, value) async => values[key] = value,
      reader: (key) async => values[key],
      deleter: (key) async => values.remove(key),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getPhoneUseAccessibilityStatus') {
        return _status(accessibilityEnabled: false, serviceConnected: false);
      }
      return false;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PhoneUseModeCard(credentialSlotService: slots),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Controlled credential slot'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(
          TextField, 'Slot ID (for example takeout.qa.password)'),
      'takeout.qa.password',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Credential value'),
      'controlled-fake-account-value',
    );
    await tester.tap(find.text('Store locally'));
    await tester.pumpAndSettle();

    expect(
      values['phone_use_slot_takeout.qa.password'],
      'controlled-fake-account-value',
    );
    expect(find.text('controlled-fake-account-value'), findsNothing);
    expect(find.text('Stored locally as takeout.qa.password.'), findsOneWidget);
  });
}

Map<String, dynamic> _status({
  required bool accessibilityEnabled,
  required bool serviceConnected,
}) {
  return {
    'platform': 'android',
    'supported': true,
    'serviceId': 'com.mobilecode.app/.PhoneUseAccessibilityService',
    'accessibilityEnabled': accessibilityEnabled,
    'serviceConnected': serviceConnected,
    'canObserveActiveWindow': accessibilityEnabled && serviceConnected,
    'canPerformGestures': accessibilityEnabled && serviceConnected,
    'canSetText': accessibilityEnabled && serviceConnected,
    'supportedActions': [
      'observe_ui',
      'global_back',
      'global_home',
      'tap',
      'swipe',
      'set_text',
    ],
    'blockedReason': accessibilityEnabled && serviceConnected
        ? null
        : 'accessibility_permission_required',
    'eventCount': 0,
    'countsAsExperiment': false,
    'countsAsStrategyAblationResult': false,
    'rawTextIncluded': false,
    'redactionApplied': true,
  };
}

class _ActionProbeProvider implements DeviceAutomationProvider {
  _ActionProbeProvider(this.handler);

  final Future<DeviceAutomationProviderResult> Function(
    DeviceAutomationRequest request,
  ) handler;
  final List<DeviceAutomationRequest> requests = [];

  @override
  String get name => 'action-probe-test';

  @override
  DeviceAutomationProviderType get type =>
      DeviceAutomationProviderType.embeddedAccessibility;

  @override
  Future<DeviceAutomationProviderResult> execute(
    DeviceAutomationRequest request,
  ) async {
    requests.add(request);
    return handler(request);
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
          video: false,
          logs: false,
          replay: false,
          physicalDevices: false,
          simulators: true,
        ),
      );
}
