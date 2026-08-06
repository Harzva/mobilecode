import 'device_telemetry_service.dart';
import 'tuima_provider_service.dart';

enum MobileCorePolicyTarget { local, cloud, unavailable }

enum MobileCoreOfflineSource {
  none,
  explicit,
  osConnectivity,
  cloudTransport,
  osAndCloudTransport,
}

enum MobileCoreCloudApprovalState {
  notRequired,
  pending,
  approved,
  declined,
}

enum MobileCorePolicyReason {
  privacyRequiresLocal,
  offlineRequiresLocal,
  localMediaSupported,
  localMediaUnavailable,
  thermalOrMemoryPressure,
  complexTaskCloudApproved,
  complexTaskAwaitingApproval,
  localReady,
  localUnavailableCloudAvailable,
  noProviderAvailable,
}

class MobileCoreTaskSignals {
  const MobileCoreTaskSignals({
    this.privacySensitive = false,
    this.offline = false,
    this.complexTask = false,
    this.cloudAvailable = false,
    this.cloudApproved = false,
    this.offlineSource = MobileCoreOfflineSource.none,
    this.cloudApprovalState = MobileCoreCloudApprovalState.notRequired,
    this.cloudApprovalId,
  });

  final bool privacySensitive;
  final bool offline;
  final bool complexTask;
  final bool cloudAvailable;
  final bool cloudApproved;
  final MobileCoreOfflineSource offlineSource;
  final MobileCoreCloudApprovalState cloudApprovalState;
  final String? cloudApprovalId;

  bool get forceLocal => privacySensitive || offline;
  bool get requiresCloudApproval =>
      complexTask && cloudAvailable && !forceLocal && !cloudApproved;

  Map<String, Object> get evidenceMetadata => {
        'privacySensitive': privacySensitive,
        'offline': offline,
        'complexTask': complexTask,
        'cloudAvailable': cloudAvailable,
        'cloudApproved': cloudApproved,
        'forceLocal': forceLocal,
        'offlineSource': offlineSource.name,
        'cloudApprovalState': cloudApprovalState.name,
        'cloudApprovalScope':
            cloudApprovalState == MobileCoreCloudApprovalState.notRequired
                ? 'none'
                : 'single_task',
        if (cloudApprovalId != null) 'cloudApprovalId': cloudApprovalId!,
        'redaction': 'request_text_omitted',
      };

  MobileCoreTaskSignals copyWith({
    bool? privacySensitive,
    bool? offline,
    bool? complexTask,
    bool? cloudAvailable,
    bool? cloudApproved,
    MobileCoreOfflineSource? offlineSource,
    MobileCoreCloudApprovalState? cloudApprovalState,
    String? cloudApprovalId,
  }) =>
      MobileCoreTaskSignals(
        privacySensitive: privacySensitive ?? this.privacySensitive,
        offline: offline ?? this.offline,
        complexTask: complexTask ?? this.complexTask,
        cloudAvailable: cloudAvailable ?? this.cloudAvailable,
        cloudApproved: cloudApproved ?? this.cloudApproved,
        offlineSource: offlineSource ?? this.offlineSource,
        cloudApprovalState: cloudApprovalState ?? this.cloudApprovalState,
        cloudApprovalId: cloudApprovalId ?? this.cloudApprovalId,
      );

  MobileCoreTaskSignals resolveCloudApproval({
    required bool approved,
    required String approvalId,
  }) =>
      copyWith(
        cloudApproved: approved,
        cloudApprovalState: approved
            ? MobileCoreCloudApprovalState.approved
            : MobileCoreCloudApprovalState.declined,
        cloudApprovalId: approvalId,
      );

  static MobileCoreTaskSignals classify({
    required String userText,
    required bool offline,
    required bool agentTask,
    required int inputCharacters,
    required int maxTokens,
    required bool cloudAvailable,
    required bool cloudApproved,
    MobileCoreOfflineSource offlineSource = MobileCoreOfflineSource.explicit,
    bool explicitlySensitive = false,
  }) {
    final probe = userText.toLowerCase();
    final privacySensitive = explicitlySensitive ||
        _privacyMarkers.any((marker) => probe.contains(marker));
    final complexTask = agentTask ||
        inputCharacters >= 12000 ||
        maxTokens >= 3072 ||
        _complexMarkers.any((marker) => probe.contains(marker));
    final forceLocal = privacySensitive || offline;
    final approvalState = complexTask && cloudAvailable && !forceLocal
        ? cloudApproved
            ? MobileCoreCloudApprovalState.approved
            : MobileCoreCloudApprovalState.pending
        : MobileCoreCloudApprovalState.notRequired;
    return MobileCoreTaskSignals(
      privacySensitive: privacySensitive,
      offline: offline,
      complexTask: complexTask,
      cloudAvailable: cloudAvailable,
      cloudApproved: cloudApproved,
      offlineSource: offline ? offlineSource : MobileCoreOfflineSource.none,
      cloudApprovalState: approvalState,
    );
  }

  static const _privacyMarkers = <String>[
    'secret_id',
    'sensitive_flow',
    'credential slot',
    'credential_slot',
    'login',
    'log in',
    'sign in',
    '登录',
    'password',
    '密码',
    'one-time code',
    'verification code',
    '验证码',
    'otp',
    'cookie',
    '银行卡',
    'bank card',
    'payment',
    '付款',
    'place order',
    '下单',
    '支付口令',
  ];

  static const _complexMarkers = <String>[
    '多文件',
    '重构',
    '架构',
    '长文本',
    '复杂推理',
    'refactor',
    'architecture',
    'long context',
  ];
}

class MobileCorePolicyDecision {
  const MobileCorePolicyDecision({
    required this.target,
    required this.reason,
    required this.contextLength,
    required this.requiresCloudApproval,
    required this.allowCloudPayload,
    this.resourceConstrained = false,
    this.recommendedModelId,
    this.maxOutputTokens = 256,
  });

  final MobileCorePolicyTarget target;
  final MobileCorePolicyReason reason;
  final int contextLength;
  final bool requiresCloudApproval;
  final bool allowCloudPayload;
  final bool resourceConstrained;
  final String? recommendedModelId;
  final int maxOutputTokens;

  int constrainOutputTokens(int requested) =>
      requested.clamp(1, maxOutputTokens);

  Map<String, Object?> get evidenceMetadata => {
        'target': target.name,
        'reason': reason.name,
        'contextLength': contextLength,
        'requiresCloudApproval': requiresCloudApproval,
        'allowCloudPayload': allowCloudPayload,
        'resourceConstrained': resourceConstrained,
        'recommendedModelId': recommendedModelId,
        'maxOutputTokens': maxOutputTokens,
      };
}

/// Pure policy layer. MobileCore reports runtime truth; MobileCode keeps the
/// routing, approval, and device-action authority.
class MobileCoreAdaptivePolicy {
  const MobileCoreAdaptivePolicy._();

  static bool shouldUseMobileCore({
    required bool mobileCoreSelected,
    required MobileCoreTaskSignals task,
  }) =>
      mobileCoreSelected || task.forceLocal || task.requiresCloudApproval;

  /// Returns whether a pressure decision should change the active text model.
  ///
  /// Attachment work is deliberately excluded: the smallest recommendation
  /// may not preserve the active image/audio capability. MobileCore remains the
  /// runtime source of truth for a compatible multimodal pair.
  static bool shouldSwitchToRecommendedModel({
    required MobileCorePolicyDecision decision,
    required String? activeModelId,
    MobileCoreAttachmentKind? attachmentKind,
  }) {
    final recommended = decision.recommendedModelId?.trim() ?? '';
    return decision.target == MobileCorePolicyTarget.local &&
        decision.resourceConstrained &&
        attachmentKind == null &&
        recommended.isNotEmpty &&
        recommended != activeModelId;
  }

  static MobileCorePolicyDecision decide({
    required TuimaHealth health,
    required MobileCoreRecommendations recommendations,
    required DeviceTelemetrySnapshot telemetry,
    bool privacySensitive = false,
    bool offline = false,
    bool complexTask = false,
    bool cloudAvailable = false,
    bool cloudApproved = false,
    MobileCoreAttachmentKind? attachmentKind,
    double measuredDecodeTokensPerSecond = 0,
  }) {
    final localReady = health.canInfer && health.capabilities.textInput;
    final recommendation = _bestSafeRecommendation(recommendations);
    final pressured = _isPressured(health, recommendations, telemetry);
    final constrainedContext = pressured ? 2048 : 4096;
    final maxOutputTokens = _outputTokenLimit(
      pressured: pressured,
      measuredDecodeTokensPerSecond: measuredDecodeTokensPerSecond,
    );

    if (attachmentKind != null) {
      final supported =
          localReady && health.capabilities.supports(attachmentKind);
      return MobileCorePolicyDecision(
        target: supported
            ? MobileCorePolicyTarget.local
            : MobileCorePolicyTarget.unavailable,
        reason: supported
            ? MobileCorePolicyReason.localMediaSupported
            : MobileCorePolicyReason.localMediaUnavailable,
        contextLength: constrainedContext,
        requiresCloudApproval: false,
        // Selected local attachments are never eligible for cloud forwarding.
        allowCloudPayload: false,
        resourceConstrained: pressured,
        recommendedModelId: recommendation?.modelId,
        maxOutputTokens: maxOutputTokens,
      );
    }

    if (privacySensitive || offline) {
      return MobileCorePolicyDecision(
        target: localReady
            ? MobileCorePolicyTarget.local
            : MobileCorePolicyTarget.unavailable,
        reason: privacySensitive
            ? MobileCorePolicyReason.privacyRequiresLocal
            : MobileCorePolicyReason.offlineRequiresLocal,
        contextLength: constrainedContext,
        requiresCloudApproval: false,
        allowCloudPayload: false,
        resourceConstrained: pressured,
        recommendedModelId: recommendation?.modelId,
        maxOutputTokens: maxOutputTokens,
      );
    }

    if (pressured && localReady) {
      return MobileCorePolicyDecision(
        target: MobileCorePolicyTarget.local,
        reason: MobileCorePolicyReason.thermalOrMemoryPressure,
        contextLength: constrainedContext,
        requiresCloudApproval: false,
        allowCloudPayload: false,
        resourceConstrained: pressured,
        recommendedModelId: recommendation?.modelId,
        maxOutputTokens: maxOutputTokens,
      );
    }

    if (complexTask && cloudAvailable) {
      return MobileCorePolicyDecision(
        target: cloudApproved
            ? MobileCorePolicyTarget.cloud
            : localReady
                ? MobileCorePolicyTarget.local
                : MobileCorePolicyTarget.unavailable,
        reason: cloudApproved
            ? MobileCorePolicyReason.complexTaskCloudApproved
            : MobileCorePolicyReason.complexTaskAwaitingApproval,
        contextLength: constrainedContext,
        requiresCloudApproval: !cloudApproved,
        allowCloudPayload: cloudApproved,
        resourceConstrained: pressured,
        recommendedModelId: recommendation?.modelId,
        maxOutputTokens: maxOutputTokens,
      );
    }

    if (localReady) {
      return MobileCorePolicyDecision(
        target: MobileCorePolicyTarget.local,
        reason: MobileCorePolicyReason.localReady,
        contextLength: constrainedContext,
        requiresCloudApproval: false,
        allowCloudPayload: false,
        resourceConstrained: pressured,
        recommendedModelId: recommendation?.modelId,
        maxOutputTokens: maxOutputTokens,
      );
    }
    return MobileCorePolicyDecision(
      target: cloudAvailable
          ? MobileCorePolicyTarget.cloud
          : MobileCorePolicyTarget.unavailable,
      reason: cloudAvailable
          ? MobileCorePolicyReason.localUnavailableCloudAvailable
          : MobileCorePolicyReason.noProviderAvailable,
      contextLength: constrainedContext,
      requiresCloudApproval: cloudAvailable && !cloudApproved,
      allowCloudPayload: cloudAvailable && cloudApproved,
      resourceConstrained: pressured,
      recommendedModelId: recommendation?.modelId,
      maxOutputTokens: maxOutputTokens,
    );
  }

  static MobileCorePolicyDecision decideForTask({
    required TuimaHealth health,
    required MobileCoreRecommendations recommendations,
    required DeviceTelemetrySnapshot telemetry,
    required MobileCoreTaskSignals task,
    MobileCoreAttachmentKind? attachmentKind,
    double measuredDecodeTokensPerSecond = 0,
  }) =>
      decide(
        health: health,
        recommendations: recommendations,
        telemetry: telemetry,
        privacySensitive: task.privacySensitive,
        offline: task.offline,
        complexTask: task.complexTask,
        cloudAvailable: task.cloudAvailable,
        cloudApproved: task.cloudApproved,
        attachmentKind: attachmentKind,
        measuredDecodeTokensPerSecond: measuredDecodeTokensPerSecond,
      );

  static int _outputTokenLimit({
    required bool pressured,
    required double measuredDecodeTokensPerSecond,
  }) {
    if (measuredDecodeTokensPerSecond > 0 &&
        measuredDecodeTokensPerSecond < 0.5) {
      return 8;
    }
    if (measuredDecodeTokensPerSecond > 0 &&
        measuredDecodeTokensPerSecond < 2) {
      return 32;
    }
    return pressured ? 128 : 256;
  }

  static bool _isPressured(
    TuimaHealth health,
    MobileCoreRecommendations recommendations,
    DeviceTelemetrySnapshot telemetry,
  ) {
    final severeThermal = telemetry.thermalStatus >= 4 ||
        (telemetry.batteryTemperatureC > 0 &&
            telemetry.batteryTemperatureC >= 43);
    final memoryPressure = telemetry.lowMemory ||
        (telemetry.totalMemoryMb > 0 && telemetry.memoryUsedPercent >= 0.88) ||
        recommendations.lowRamDevice ||
        (health.preflight.memory.requiredBytes > 0 &&
            !health.preflight.memory.ok);
    final lowBattery = telemetry.batteryLevel >= 0 &&
        telemetry.batteryLevel <= 15 &&
        !telemetry.batteryCharging;
    return severeThermal || memoryPressure || lowBattery;
  }

  static MobileCoreRecommendation? _bestSafeRecommendation(
    MobileCoreRecommendations recommendations,
  ) {
    final safe = recommendations.recommendations
        .where((item) => item.fit != 'too_tight')
        .toList(growable: false)
      ..sort((a, b) {
        final memory = a.estimatedMemoryMb.compareTo(b.estimatedMemoryMb);
        return memory != 0 ? memory : b.score.compareTo(a.score);
      });
    return safe.isEmpty ? null : safe.first;
  }
}
