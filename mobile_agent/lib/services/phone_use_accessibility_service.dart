import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PhoneUseAccessibilityStatus {
  const PhoneUseAccessibilityStatus({
    required this.platform,
    required this.supported,
    required this.serviceId,
    required this.accessibilityEnabled,
    required this.serviceConnected,
    required this.canObserveActiveWindow,
    required this.canPerformGestures,
    required this.canSetText,
    required this.supportedActions,
    required this.blockedReason,
    required this.eventCount,
    required this.countsAsExperiment,
    required this.countsAsStrategyAblationResult,
    required this.rawTextIncluded,
    required this.redactionApplied,
    required this.fallback,
  });

  final String platform;
  final bool supported;
  final String serviceId;
  final bool accessibilityEnabled;
  final bool serviceConnected;
  final bool canObserveActiveWindow;
  final bool canPerformGestures;
  final bool canSetText;
  final List<String> supportedActions;
  final String? blockedReason;
  final int eventCount;
  final bool countsAsExperiment;
  final bool countsAsStrategyAblationResult;
  final bool rawTextIncluded;
  final bool redactionApplied;
  final bool fallback;

  bool get ready =>
      supported &&
      accessibilityEnabled &&
      serviceConnected &&
      canObserveActiveWindow;

  factory PhoneUseAccessibilityStatus.fromMap(Map<String, dynamic> map) =>
      PhoneUseAccessibilityStatus(
        platform: map['platform'] as String? ?? 'android',
        supported: _boolValue(map['supported'], fallback: true),
        serviceId: map['serviceId'] as String? ?? '',
        accessibilityEnabled: _boolValue(map['accessibilityEnabled']),
        serviceConnected: _boolValue(map['serviceConnected']),
        canObserveActiveWindow: _boolValue(map['canObserveActiveWindow']),
        canPerformGestures: _boolValue(map['canPerformGestures']),
        canSetText: _boolValue(map['canSetText']),
        supportedActions: _stringList(map['supportedActions']),
        blockedReason: _nullableString(map['blockedReason']),
        eventCount: _intValue(map['eventCount']),
        countsAsExperiment: _boolValue(map['countsAsExperiment']),
        countsAsStrategyAblationResult:
            _boolValue(map['countsAsStrategyAblationResult']),
        rawTextIncluded: _boolValue(map['rawTextIncluded']),
        redactionApplied: _boolValue(map['redactionApplied'], fallback: true),
        fallback: _boolValue(map['fallback']),
      );

  factory PhoneUseAccessibilityStatus.fallback({Object? error}) {
    final platform = kIsWeb ? 'web' : Platform.operatingSystem;
    return PhoneUseAccessibilityStatus(
      platform: platform,
      supported: false,
      serviceId: '',
      accessibilityEnabled: false,
      serviceConnected: false,
      canObserveActiveWindow: false,
      canPerformGestures: false,
      canSetText: false,
      supportedActions: const [],
      blockedReason: error == null
          ? 'unsupported_platform'
          : 'phone_use_platform_channel_unavailable',
      eventCount: 0,
      countsAsExperiment: false,
      countsAsStrategyAblationResult: false,
      rawTextIncluded: false,
      redactionApplied: true,
      fallback: true,
    );
  }
}

class PhoneUseAccessibilityService {
  PhoneUseAccessibilityService._();

  static final PhoneUseAccessibilityService instance =
      PhoneUseAccessibilityService._();
  static const _channel = MethodChannel('mobilecode/system_tools');

  Future<PhoneUseAccessibilityStatus> getStatus() async {
    if (kIsWeb) return PhoneUseAccessibilityStatus.fallback();
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getPhoneUseAccessibilityStatus',
      );
      if (raw == null) return PhoneUseAccessibilityStatus.fallback();
      return PhoneUseAccessibilityStatus.fromMap(
        Map<String, dynamic>.from(raw),
      );
    } on Object catch (error) {
      return PhoneUseAccessibilityStatus.fallback(error: error);
    }
  }

  Future<bool> openAccessibilitySettings() async {
    if (kIsWeb) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'openPhoneUseAccessibilitySettings',
          ) ??
          false;
    } on Object {
      return false;
    }
  }

  Future<bool> openAppSettings() async {
    if (kIsWeb) return false;
    try {
      return await _channel.invokeMethod<bool>('openAppSettings') ?? false;
    } on Object {
      return false;
    }
  }

  Future<bool> openBatteryOptimizationSettings() async {
    if (kIsWeb) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'openBatteryOptimizationSettings',
          ) ??
          false;
    } on Object {
      return false;
    }
  }

  Future<Map<String, dynamic>> runDryProbe() async =>
      _invokeMap('runPhoneUseDryProbe');

  Future<Map<String, dynamic>> performAction(
    Map<String, dynamic> action,
  ) async =>
      _invokeMap('performPhoneUseAction', {'action': action});

  Future<Map<String, dynamic>> _invokeMap(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    if (kIsWeb) return _blockedMap('unsupported_platform');
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        method,
        arguments,
      );
      if (raw == null) return _blockedMap('empty_phone_use_response');
      return Map<String, dynamic>.from(raw);
    } on Object catch (error) {
      return _blockedMap(
        'phone_use_platform_channel_unavailable',
        error: error.runtimeType.toString(),
      );
    }
  }
}

Map<String, dynamic> _blockedMap(String failureKind, {String? error}) => {
      'status': 'blocked',
      'failureKind': failureKind,
      if (error != null) 'errorType': error,
      'countsAsExperiment': false,
      'countsAsStrategyAblationResult': false,
      'rawTextIncluded': false,
      'redactionApplied': true,
    };

List<String> _stringList(Object? value) {
  if (value is List) {
    return value
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  if (value is String && value.isNotEmpty) return [value];
  return const [];
}

int _intValue(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

bool _boolValue(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is String) return value.toLowerCase() == 'true';
  return fallback;
}

String? _nullableString(Object? value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) return null;
  return text;
}
