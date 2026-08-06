import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum PhoneUseLifecycleState {
  disabled,
  enabledDisconnected,
  ready,
  interrupted,
  backgroundRestricted,
  recovering,
  unsupported,
  unknown;

  static PhoneUseLifecycleState fromWire(Object? value) {
    return switch (value?.toString()) {
      'disabled' => disabled,
      'enabled_disconnected' => enabledDisconnected,
      'ready' => ready,
      'interrupted' => interrupted,
      'background_restricted' => backgroundRestricted,
      'recovering' => recovering,
      'unsupported' => unsupported,
      _ => unknown,
    };
  }

  String get wireValue => switch (this) {
        disabled => 'disabled',
        enabledDisconnected => 'enabled_disconnected',
        ready => 'ready',
        interrupted => 'interrupted',
        backgroundRestricted => 'background_restricted',
        recovering => 'recovering',
        unsupported => 'unsupported',
        unknown => 'unknown',
      };
}

class PhoneUseCoordinateContract {
  const PhoneUseCoordinateContract({
    required this.sourceSpace,
    required this.inputSpace,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.inputWidth,
    required this.inputHeight,
    required this.scaleX,
    required this.scaleY,
    required this.origin,
  });

  final String sourceSpace;
  final String inputSpace;
  final int sourceWidth;
  final int sourceHeight;
  final int inputWidth;
  final int inputHeight;
  final double scaleX;
  final double scaleY;
  final String origin;

  factory PhoneUseCoordinateContract.fromMap(Map<String, dynamic> map) =>
      PhoneUseCoordinateContract(
        sourceSpace: map['sourceSpace']?.toString() ?? 'unknown',
        inputSpace: map['inputSpace']?.toString() ?? 'unknown',
        sourceWidth: _intValue(map['sourceWidth']),
        sourceHeight: _intValue(map['sourceHeight']),
        inputWidth: _intValue(map['inputWidth']),
        inputHeight: _intValue(map['inputHeight']),
        scaleX: _doubleValue(map['scaleX'], fallback: 1),
        scaleY: _doubleValue(map['scaleY'], fallback: 1),
        origin: map['origin']?.toString() ?? 'top_left',
      );

  Map<String, dynamic> toJson() => {
        'sourceSpace': sourceSpace,
        'inputSpace': inputSpace,
        'sourceWidth': sourceWidth,
        'sourceHeight': sourceHeight,
        'inputWidth': inputWidth,
        'inputHeight': inputHeight,
        'scaleX': scaleX,
        'scaleY': scaleY,
        'origin': origin,
      };
}

class PhoneUseSemanticNode {
  const PhoneUseSemanticNode({
    required this.ref,
    required this.role,
    required this.label,
    required this.identityHash,
    required this.bounds,
    required this.actions,
    required this.clickable,
    required this.editable,
    required this.enabled,
    required this.sensitive,
  });

  final String ref;
  final String role;
  final String label;
  final String identityHash;
  final Map<String, int> bounds;
  final List<String> actions;
  final bool clickable;
  final bool editable;
  final bool enabled;
  final bool sensitive;

  String pinnedRef(int generation) => '$ref~s$generation';

  factory PhoneUseSemanticNode.fromMap(Map<String, dynamic> map) =>
      PhoneUseSemanticNode(
        ref: map['ref']?.toString() ?? '',
        role: map['role']?.toString() ?? 'View',
        label: map['label']?.toString() ?? '',
        identityHash: map['identityHash']?.toString() ?? '',
        bounds: _intMap(map['bounds']),
        actions: _stringList(map['actions']),
        clickable: _boolValue(map['clickable']),
        editable: _boolValue(map['editable']),
        enabled: _boolValue(map['enabled'], fallback: true),
        sensitive: _boolValue(map['sensitive']),
      );

  Map<String, dynamic> toJson() => {
        'ref': ref,
        'role': role,
        'label': label,
        'identityHash': identityHash,
        'bounds': bounds,
        'actions': actions,
        'clickable': clickable,
        'editable': editable,
        'enabled': enabled,
        'sensitive': sensitive,
      };
}

class PhoneUseSemanticSnapshot {
  const PhoneUseSemanticSnapshot({
    required this.canObserveActiveWindow,
    required this.frameId,
    required this.refsGeneration,
    required this.frameState,
    required this.digest,
    required this.captureMode,
    required this.nodes,
    required this.nodeCount,
    required this.interactiveNodeCount,
    required this.truncated,
    required this.rootPackageNameHash,
    required this.rootClassName,
    required this.coordinateContract,
    required this.screenshotFallbackRecommended,
    required this.rawTextIncluded,
    required this.redactionApplied,
  });

  final bool canObserveActiveWindow;
  final String? frameId;
  final int? refsGeneration;
  final String frameState;
  final String? digest;
  final String captureMode;
  final List<PhoneUseSemanticNode> nodes;
  final int nodeCount;
  final int interactiveNodeCount;
  final bool truncated;
  final String rootPackageNameHash;
  final String rootClassName;
  final PhoneUseCoordinateContract? coordinateContract;
  final bool screenshotFallbackRecommended;
  final bool rawTextIncluded;
  final bool redactionApplied;

  factory PhoneUseSemanticSnapshot.fromMap(Map<String, dynamic> map) {
    final rawNodes = map['interactiveNodes'];
    final nodes = rawNodes is List
        ? rawNodes
            .whereType<Map<Object?, Object?>>()
            .map((node) => PhoneUseSemanticNode.fromMap(
                  Map<String, dynamic>.from(node),
                ))
            .toList(growable: false)
        : const <PhoneUseSemanticNode>[];
    final coordinateMap = _mapValue(map['coordinateContract']);
    return PhoneUseSemanticSnapshot(
      canObserveActiveWindow: _boolValue(map['canObserveActiveWindow']),
      frameId: _nullableString(map['frameId']),
      refsGeneration: _nullableInt(map['refsGeneration']),
      frameState: map['frameState']?.toString() ?? 'none',
      digest: _nullableString(map['digest']),
      captureMode: map['captureMode']?.toString() ?? 'accessibility_tree',
      nodes: nodes,
      nodeCount: _intValue(map['nodeCount']),
      interactiveNodeCount:
          _intValue(map['interactiveNodeCount'], fallback: nodes.length),
      truncated: _boolValue(map['truncated']),
      rootPackageNameHash: map['rootPackageNameHash']?.toString() ?? '',
      rootClassName: map['rootClassName']?.toString() ?? '',
      coordinateContract: coordinateMap == null
          ? null
          : PhoneUseCoordinateContract.fromMap(coordinateMap),
      screenshotFallbackRecommended:
          _boolValue(map['screenshotFallbackRecommended']),
      rawTextIncluded: _boolValue(map['rawTextIncluded']),
      redactionApplied: _boolValue(map['redactionApplied'], fallback: true),
    );
  }

  Map<String, dynamic> toEvidenceJson() => {
        'canObserveActiveWindow': canObserveActiveWindow,
        'frameId': frameId,
        'refsGeneration': refsGeneration,
        'frameState': frameState,
        'digest': digest,
        'captureMode': captureMode,
        'interactiveNodeCount': interactiveNodeCount,
        'nodeCount': nodeCount,
        'truncated': truncated,
        'rootPackageNameHash': rootPackageNameHash,
        'rootClassName': rootClassName,
        if (coordinateContract != null)
          'coordinateContract': coordinateContract!.toJson(),
        'screenshotFallbackRecommended': screenshotFallbackRecommended,
        'rawTextIncluded': rawTextIncluded,
        'redactionApplied': redactionApplied,
      };
}

class PhoneUseAccessibilityStatus {
  const PhoneUseAccessibilityStatus({
    required this.platform,
    required this.supported,
    required this.serviceId,
    required this.accessibilityEnabled,
    required this.serviceConnected,
    required this.lifecycleState,
    required this.canObserveActiveWindow,
    required this.canPerformGestures,
    required this.canSetText,
    required this.canCaptureScreenshot,
    required this.batteryOptimizationIgnored,
    required this.backgroundRestricted,
    required this.supportedActions,
    required this.blockedReason,
    required this.recoveryActions,
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
  final PhoneUseLifecycleState lifecycleState;
  final bool canObserveActiveWindow;
  final bool canPerformGestures;
  final bool canSetText;
  final bool canCaptureScreenshot;
  final bool batteryOptimizationIgnored;
  final bool backgroundRestricted;
  final List<String> supportedActions;
  final String? blockedReason;
  final List<String> recoveryActions;
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
      canObserveActiveWindow &&
      lifecycleState == PhoneUseLifecycleState.ready;

  factory PhoneUseAccessibilityStatus.fromMap(Map<String, dynamic> map) {
    final enabled = _boolValue(map['accessibilityEnabled']);
    final connected = _boolValue(map['serviceConnected']);
    final inferredLifecycle = !enabled
        ? PhoneUseLifecycleState.disabled
        : connected
            ? PhoneUseLifecycleState.ready
            : PhoneUseLifecycleState.enabledDisconnected;
    final parsedLifecycle = PhoneUseLifecycleState.fromWire(
      map['lifecycleState'],
    );
    return PhoneUseAccessibilityStatus(
      platform: map['platform'] as String? ?? 'android',
      supported: _boolValue(map['supported'], fallback: true),
      serviceId: map['serviceId'] as String? ?? '',
      accessibilityEnabled: enabled,
      serviceConnected: connected,
      lifecycleState: parsedLifecycle == PhoneUseLifecycleState.unknown
          ? inferredLifecycle
          : parsedLifecycle,
      canObserveActiveWindow: _boolValue(map['canObserveActiveWindow']),
      canPerformGestures: _boolValue(map['canPerformGestures']),
      canSetText: _boolValue(map['canSetText']),
      canCaptureScreenshot: _boolValue(map['canCaptureScreenshot']),
      batteryOptimizationIgnored: _boolValue(map['batteryOptimizationIgnored']),
      backgroundRestricted: _boolValue(map['backgroundRestricted']),
      supportedActions: _stringList(map['supportedActions']),
      blockedReason: _nullableString(map['blockedReason']),
      recoveryActions: _stringList(map['recoveryActions']),
      eventCount: _intValue(map['eventCount']),
      countsAsExperiment: _boolValue(map['countsAsExperiment']),
      countsAsStrategyAblationResult:
          _boolValue(map['countsAsStrategyAblationResult']),
      rawTextIncluded: _boolValue(map['rawTextIncluded']),
      redactionApplied: _boolValue(map['redactionApplied'], fallback: true),
      fallback: _boolValue(map['fallback']),
    );
  }

  factory PhoneUseAccessibilityStatus.fallback({Object? error}) {
    final platform = kIsWeb ? 'web' : Platform.operatingSystem;
    return PhoneUseAccessibilityStatus(
      platform: platform,
      supported: false,
      serviceId: '',
      accessibilityEnabled: false,
      serviceConnected: false,
      lifecycleState: PhoneUseLifecycleState.unsupported,
      canObserveActiveWindow: false,
      canPerformGestures: false,
      canSetText: false,
      canCaptureScreenshot: false,
      batteryOptimizationIgnored: false,
      backgroundRestricted: false,
      supportedActions: const [],
      blockedReason: error == null
          ? 'unsupported_platform'
          : 'phone_use_platform_channel_unavailable',
      recoveryActions: const [],
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

  Future<bool> openAccessibilitySettings() =>
      _invokeBool('openPhoneUseAccessibilitySettings');

  Future<bool> openAppSettings() => _invokeBool('openAppSettings');

  Future<bool> openBatteryOptimizationSettings() =>
      _invokeBool('openBatteryOptimizationSettings');

  Future<Map<String, dynamic>> markRecoveryRequested() =>
      _invokeMap('markPhoneUseRecoveryRequested');

  Future<Map<String, dynamic>> runDryProbe() async =>
      _invokeMap('runPhoneUseDryProbe');

  Future<Map<String, dynamic>> performAction(
    Map<String, dynamic> action,
  ) async =>
      _invokeMap('performPhoneUseAction', {'action': action});

  Future<Map<String, dynamic>> captureScreenshot({
    required bool approved,
    bool sensitiveFlow = false,
  }) =>
      _invokeMap('capturePhoneUseScreenshot', {
        'approved': approved,
        'sensitiveFlow': sensitiveFlow,
      });

  Future<PhoneUseSemanticSnapshot?> captureSemanticSnapshot() async {
    final result = await performAction(const {'type': 'semantic_snapshot'});
    final snapshot = _mapValue(result['snapshot'] ?? result['observation']);
    return snapshot == null ? null : PhoneUseSemanticSnapshot.fromMap(snapshot);
  }

  Future<bool> _invokeBool(String method) async {
    if (kIsWeb) return false;
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on Object {
      return false;
    }
  }

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

Map<String, dynamic>? _mapValue(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

Map<String, int> _intMap(Object? value) {
  final map = _mapValue(value);
  if (map == null) return const {};
  return map.map((key, value) => MapEntry(key, _intValue(value)));
}

List<String> _stringList(Object? value) {
  if (value is List) {
    return value
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
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

int? _nullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString());
}

double _doubleValue(Object? value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
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
