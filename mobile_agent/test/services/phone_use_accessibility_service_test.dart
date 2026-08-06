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
        'lifecycleState': 'ready',
        'canObserveActiveWindow': true,
        'canPerformGestures': true,
        'canSetText': true,
        'canCaptureScreenshot': true,
        'batteryOptimizationIgnored': true,
        'backgroundRestricted': false,
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
    expect(status.lifecycleState, PhoneUseLifecycleState.ready);
    expect(status.canCaptureScreenshot, isTrue);
    expect(status.batteryOptimizationIgnored, isTrue);
  });

  test('parses semantic snapshot refs and coordinate contract', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'performPhoneUseAction');
      expect((call.arguments as Map)['action'], {'type': 'semantic_snapshot'});
      return {
        'status': 'passed',
        'snapshot': {
          'canObserveActiveWindow': true,
          'frameId': 's7',
          'refsGeneration': 7,
          'frameState': 'active',
          'digest': 'digest-7',
          'interactiveNodes': [
            {
              'ref': '@e1',
              'role': 'TextField',
              'label': '[redacted-credential]',
              'identityHash': 'node-1',
              'bounds': {'left': 10, 'top': 20, 'right': 200, 'bottom': 80},
              'actions': ['set_text'],
              'clickable': true,
              'editable': true,
              'enabled': true,
              'sensitive': true,
            },
          ],
          'nodeCount': 9,
          'interactiveNodeCount': 1,
          'truncated': false,
          'rootPackageNameHash': 'pkg-hash',
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
          'screenshotFallbackRecommended': true,
          'rawTextIncluded': false,
          'redactionApplied': true,
        },
      };
    });

    final snapshot =
        await PhoneUseAccessibilityService.instance.captureSemanticSnapshot();

    expect(snapshot?.digest, 'digest-7');
    expect(snapshot?.nodes.single.pinnedRef(7), '@e1~s7');
    expect(snapshot?.nodes.single.sensitive, isTrue);
    expect(snapshot?.coordinateContract?.sourceWidth, 1080);
    expect(snapshot?.rawTextIncluded, isFalse);
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

  test('opens Android permission settings through method channel', () async {
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return true;
    });

    final accessibilityOpened =
        await PhoneUseAccessibilityService.instance.openAccessibilitySettings();
    final appSettingsOpened =
        await PhoneUseAccessibilityService.instance.openAppSettings();
    final batterySettingsOpened = await PhoneUseAccessibilityService.instance
        .openBatteryOptimizationSettings();

    expect(accessibilityOpened, isTrue);
    expect(appSettingsOpened, isTrue);
    expect(batterySettingsOpened, isTrue);
    expect(methods, [
      'openPhoneUseAccessibilitySettings',
      'openAppSettings',
      'openBatteryOptimizationSettings',
    ]);
  });

  test('marks recovery and captures a local-only screenshot artifact',
      () async {
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      if (call.method == 'markPhoneUseRecoveryRequested') {
        return {'status': 'passed', 'lifecycleState': 'recovering'};
      }
      return {
        'status': 'passed',
        'artifactId': 'phone-screenshot-1',
        'artifactKind': 'screenshot',
        'localOnly': true,
        'containsPotentiallySensitiveUi': true,
        'shareableWithoutReview': false,
      };
    });

    final recovery =
        await PhoneUseAccessibilityService.instance.markRecoveryRequested();
    final screenshot = await PhoneUseAccessibilityService.instance
        .captureScreenshot(approved: true);

    expect(recovery['lifecycleState'], 'recovering');
    expect(screenshot['artifactId'], 'phone-screenshot-1');
    expect(screenshot['localOnly'], isTrue);
    expect(methods, [
      'markPhoneUseRecoveryRequested',
      'capturePhoneUseScreenshot',
    ]);
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
