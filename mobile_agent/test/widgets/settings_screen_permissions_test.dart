import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('mobilecode/system_tools');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('shows system permission rows and opens Android settings',
      (tester) async {
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      switch (call.method) {
        case 'getPhoneUseAccessibilityStatus':
          return _status(accessibilityEnabled: false, serviceConnected: false);
        case 'openPhoneUseAccessibilitySettings':
        case 'openBatteryOptimizationSettings':
        case 'openAppSettings':
          return true;
        default:
          return false;
      }
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: SettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('系统权限'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('系统权限'), findsOneWidget);
    expect(find.text('Harness 权限模式'), findsOneWidget);
    expect(find.text('无障碍服务'), findsOneWidget);
    expect(find.text('后台运行权限'), findsOneWidget);
    expect(find.text('未开启'), findsOneWidget);
    expect(find.textContaining('service disconnected'), findsOneWidget);
    expect(find.textContaining('PhoneUseAccessibilityService'), findsOneWidget);

    final accessibilityRow = find.byKey(
      const ValueKey('settings.accessibility'),
    );
    await tester.ensureVisible(accessibilityRow);
    await tester.pumpAndSettle();
    await tester.tap(accessibilityRow);
    await tester.pumpAndSettle();

    expect(methods, contains('openPhoneUseAccessibilitySettings'));

    final backgroundPermissionRow = find.byKey(
      const ValueKey('settings.backgroundPermission'),
    );
    await tester.ensureVisible(backgroundPermissionRow);
    await tester.pumpAndSettle();
    await tester.tap(backgroundPermissionRow);
    await tester.pumpAndSettle();
    await tester.tap(find.text('电池设置'));
    await tester.pumpAndSettle();

    expect(methods, contains('openBatteryOptimizationSettings'));
  });

  testWidgets('lets the user choose Harness permission mode', (tester) async {
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
        home: SettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('settings.harnessPermissionMode'));
    await tester.scrollUntilVisible(
      row,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Approve safe typed tasks'), findsNothing);
    expect(find.text('Typed'), findsOneWidget);

    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.text('Ask every time'), findsOneWidget);
    expect(find.text('Approve safe typed tasks'), findsOneWidget);
    expect(find.text('Full access'), findsOneWidget);

    await tester.tap(find.text('Full access'));
    await tester.pumpAndSettle();

    expect(find.text('Full'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('mobilecode.harness.permissionMode'), 'fullAccess');
  });

  testWidgets('shows enabled permission waiting for service connection',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getPhoneUseAccessibilityStatus':
          return _status(accessibilityEnabled: true, serviceConnected: false);
        default:
          return false;
      }
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: SettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('系统权限'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('待连接'), findsOneWidget);
    expect(find.textContaining('service disconnected'), findsOneWidget);
    expect(find.textContaining('service_not_connected'), findsOneWidget);
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
    'supportedActions': ['observe_ui', 'tap', 'swipe', 'set_text'],
    'blockedReason': accessibilityEnabled && serviceConnected
        ? null
        : accessibilityEnabled
            ? 'service_not_connected'
            : 'accessibility_permission_required',
    'eventCount': 0,
    'countsAsExperiment': false,
    'countsAsStrategyAblationResult': false,
    'rawTextIncluded': false,
    'redactionApplied': true,
  };
}
