import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/device_telemetry_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('mobilecode/system_tools');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('reads Android telemetry from method channel', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getDeviceTelemetry');
      return {
        'platform': 'android',
        'manufacturer': 'MobileCode',
        'model': 'Test Phone',
        'androidVersion': '15',
        'sdkInt': 35,
        'abis': ['arm64-v8a'],
        'cpuCores': 8,
        'cpuUsagePercent': 42.5,
        'totalMemoryMb': 8192,
        'availableMemoryMb': 4096,
        'lowMemory': false,
        'appRssMb': 180,
        'appHeapMb': 72,
        'storageTotalMb': 128000,
        'storageFreeMb': 64000,
        'batteryLevel': 88,
        'batteryCharging': true,
        'batteryTemperatureC': 31.2,
        'thermalStatus': 1,
        'timestamp': 1710000000000,
        'fallback': false,
      };
    });

    final snapshot = await DeviceTelemetryService.instance.getLatestSnapshot();

    expect(snapshot.fallback, isFalse);
    expect(snapshot.model, 'Test Phone');
    expect(snapshot.cpuUsagePercent, 42.5);
    expect(snapshot.memoryUsedPercent, closeTo(0.5, 0.01));
    expect(snapshot.batteryCharging, isTrue);
  });

  test('falls back when platform channel is unavailable', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'missing');
    });

    final snapshot = await DeviceTelemetryService.instance.getLatestSnapshot();

    expect(snapshot.fallback, isTrue);
    expect(snapshot.cpuCores, greaterThan(0));
    expect(snapshot.appRssMb, greaterThanOrEqualTo(0));
  });
}
