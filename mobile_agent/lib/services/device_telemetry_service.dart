import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DeviceTelemetrySnapshot {
  const DeviceTelemetrySnapshot({
    required this.platform,
    required this.manufacturer,
    required this.model,
    required this.androidVersion,
    required this.sdkInt,
    required this.abis,
    required this.cpuCores,
    required this.cpuUsagePercent,
    required this.totalMemoryMb,
    required this.availableMemoryMb,
    required this.lowMemory,
    required this.appRssMb,
    required this.appHeapMb,
    required this.storageTotalMb,
    required this.storageFreeMb,
    required this.batteryLevel,
    required this.batteryCharging,
    required this.batteryTemperatureC,
    required this.thermalStatus,
    required this.timestamp,
    required this.fallback,
  });

  final String platform;
  final String manufacturer;
  final String model;
  final String androidVersion;
  final int sdkInt;
  final List<String> abis;
  final int cpuCores;
  final double cpuUsagePercent;
  final int totalMemoryMb;
  final int availableMemoryMb;
  final bool lowMemory;
  final int appRssMb;
  final int appHeapMb;
  final int storageTotalMb;
  final int storageFreeMb;
  final int batteryLevel;
  final bool batteryCharging;
  final double batteryTemperatureC;
  final int thermalStatus;
  final DateTime timestamp;
  final bool fallback;

  double get memoryUsedPercent {
    if (totalMemoryMb <= 0) return 0;
    return (totalMemoryMb - availableMemoryMb).clamp(0, totalMemoryMb) / totalMemoryMb;
  }

  double get storageUsedPercent {
    if (storageTotalMb <= 0) return 0;
    return (storageTotalMb - storageFreeMb).clamp(0, storageTotalMb) / storageTotalMb;
  }

  double get batteryPercent => batteryLevel < 0 ? 0 : batteryLevel / 100;

  factory DeviceTelemetrySnapshot.fromMap(Map<String, dynamic> map) {
    return DeviceTelemetrySnapshot(
      platform: map['platform'] as String? ?? 'android',
      manufacturer: map['manufacturer'] as String? ?? '',
      model: map['model'] as String? ?? 'Unknown device',
      androidVersion: map['androidVersion'] as String? ?? '',
      sdkInt: _intValue(map['sdkInt']),
      abis: _stringList(map['abis']),
      cpuCores: _intValue(map['cpuCores'], fallback: Platform.numberOfProcessors),
      cpuUsagePercent: _doubleValue(map['cpuUsagePercent']),
      totalMemoryMb: _intValue(map['totalMemoryMb']),
      availableMemoryMb: _intValue(map['availableMemoryMb']),
      lowMemory: map['lowMemory'] as bool? ?? false,
      appRssMb: _intValue(map['appRssMb']),
      appHeapMb: _intValue(map['appHeapMb']),
      storageTotalMb: _intValue(map['storageTotalMb']),
      storageFreeMb: _intValue(map['storageFreeMb']),
      batteryLevel: _intValue(map['batteryLevel'], fallback: -1),
      batteryCharging: map['batteryCharging'] as bool? ?? false,
      batteryTemperatureC: _doubleValue(map['batteryTemperatureC']),
      thermalStatus: _intValue(map['thermalStatus'], fallback: -1),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        _intValue(map['timestamp'], fallback: DateTime.now().millisecondsSinceEpoch),
      ),
      fallback: map['fallback'] as bool? ?? false,
    );
  }

  factory DeviceTelemetrySnapshot.fallback({Object? error}) {
    final rssMb = (ProcessInfo.currentRss / (1024 * 1024)).round();
    return DeviceTelemetrySnapshot(
      platform: kIsWeb ? 'web' : Platform.operatingSystem,
      manufacturer: '',
      model: error == null ? 'Flutter fallback' : 'Flutter fallback (${error.runtimeType})',
      androidVersion: '',
      sdkInt: 0,
      abis: const [],
      cpuCores: Platform.numberOfProcessors,
      cpuUsagePercent: 0,
      totalMemoryMb: 0,
      availableMemoryMb: 0,
      lowMemory: false,
      appRssMb: rssMb,
      appHeapMb: rssMb,
      storageTotalMb: 0,
      storageFreeMb: 0,
      batteryLevel: -1,
      batteryCharging: false,
      batteryTemperatureC: 0,
      thermalStatus: -1,
      timestamp: DateTime.now(),
      fallback: true,
    );
  }
}

class DeviceTelemetryService {
  DeviceTelemetryService._();

  static final DeviceTelemetryService instance = DeviceTelemetryService._();
  static const _channel = MethodChannel('mobilecode/system_tools');

  Future<DeviceTelemetrySnapshot> getStaticProfile() => getLatestSnapshot();

  Future<DeviceTelemetrySnapshot> getLatestSnapshot() async {
    if (kIsWeb) return DeviceTelemetrySnapshot.fallback();
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('getDeviceTelemetry');
      if (raw == null) return DeviceTelemetrySnapshot.fallback();
      return DeviceTelemetrySnapshot.fromMap(Map<String, dynamic>.from(raw));
    } on Object catch (error) {
      return DeviceTelemetrySnapshot.fallback(error: error);
    }
  }

  Stream<DeviceTelemetrySnapshot> watchTelemetry({
    Duration interval = const Duration(seconds: 1),
  }) {
    late final StreamController<DeviceTelemetrySnapshot> controller;
    Timer? timer;

    Future<void> emit() async {
      if (controller.isClosed) return;
      controller.add(await getLatestSnapshot());
    }

    controller = StreamController<DeviceTelemetrySnapshot>(
      onListen: () {
        unawaited(emit());
        timer = Timer.periodic(interval, (_) => unawaited(emit()));
      },
      onCancel: () {
        timer?.cancel();
        timer = null;
      },
    );
    return controller.stream;
  }
}

List<String> _stringList(Object? value) {
  if (value is List) return value.map((item) => item.toString()).where((item) => item.isNotEmpty).toList();
  if (value is String && value.isNotEmpty) return [value];
  return const [];
}

int _intValue(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

double _doubleValue(Object? value, {double fallback = 0}) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}
