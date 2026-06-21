import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/phone_use_accessibility_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('mobilecode/system_tools');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('reads Android phone-use accessibility status from method channel',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getPhoneUseAccessibilityStatus');
      return {
        'platform': 'android',
        'supported': true,
        'serviceId': 'com.mobilecode.app/.PhoneUseAccessibilityService',
        'accessibilityEnabled': true,
        'serviceConnected': true,
        'canObserveActiveWindow': true,
        'canPerformGestures': true,
        'canSetText': true,
        'supportedActions': ['observe_ui', 'tap', 'swipe', 'set_text'],
        'blockedReason': null,
        'eventCount': 7,
        'countsAsExperiment': false,
        'countsAsStrategyAblationResult': false,
        'rawTextIncluded': false,
        'redactionApplied': true,
      };
    });

    final status = await PhoneUseAccessibilityService.instance.getStatus();

    expect(status.ready, isTrue);
    expect(status.supportedActions, contains('tap'));
    expect(status.countsAsExperiment, isFalse);
    expect(status.rawTextIncluded, isFalse);
    expect(status.eventCount, 7);
  });

  test('runs dry probe and preserves non-counted boundary', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'runPhoneUseDryProbe');
      return {
        'status': 'passed',
        'probe': 'accessibility_observe_dry_probe',
        'observation': {
          'canObserveActiveWindow': true,
          'nodeCount': 12,
          'clickableNodeCount': 3,
          'editableNodeCount': 1,
          'rootPackageName': 'com.mobilecode.app',
          'rootClassName': 'android.widget.FrameLayout',
        },
        'countsAsExperiment': false,
        'countsAsStrategyAblationResult': false,
        'rawTextIncluded': false,
        'redactionApplied': true,
      };
    });

    final probe = await PhoneUseAccessibilityService.instance.runDryProbe();

    expect(probe['status'], 'passed');
    expect(probe['countsAsExperiment'], isFalse);
    expect(probe['rawTextIncluded'], isFalse);
    expect((probe['observation'] as Map)['nodeCount'], 12);
  });

  test('sends explicit phone-use action payload through method channel',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'performPhoneUseAction');
      final arguments = Map<String, dynamic>.from(call.arguments as Map);
      expect(arguments['action'], {'type': 'tap', 'x': 12, 'y': 34});
      return {
        'status': 'passed',
        'requestedAction': 'tap',
        'accepted': true,
        'countsAsExperiment': false,
        'countsAsStrategyAblationResult': false,
      };
    });

    final result = await PhoneUseAccessibilityService.instance.performAction(
      {'type': 'tap', 'x': 12, 'y': 34},
    );

    expect(result['accepted'], isTrue);
    expect(result['countsAsExperiment'], isFalse);
  });

  test('falls back when phone-use platform channel is unavailable', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'missing');
    });

    final status = await PhoneUseAccessibilityService.instance.getStatus();
    final probe = await PhoneUseAccessibilityService.instance.runDryProbe();

    expect(status.fallback, isTrue);
    expect(status.blockedReason, 'phone_use_platform_channel_unavailable');
    expect(probe['status'], 'blocked');
    expect(probe['countsAsExperiment'], isFalse);
  });
}
