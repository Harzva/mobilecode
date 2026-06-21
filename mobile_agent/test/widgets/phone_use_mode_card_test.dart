import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
        case 'runPhoneUseDryProbe':
          return {
            'status': 'blocked',
            'probe': 'accessibility_observe_dry_probe',
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
