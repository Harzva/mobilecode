import 'device_telemetry_service.dart';
import 'tuima_provider_service.dart';

enum MobileCorePolicyTarget { local, cloud, unavailable }

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

class MobileCorePolicyDecision {
  const MobileCorePolicyDecision({
    required this.target,
    required this.reason,
    required this.contextLength,
    required this.requiresCloudApproval,
    required this.allowCloudPayload,
    this.recommendedModelId,
  });

  final MobileCorePolicyTarget target;
  final MobileCorePolicyReason reason;
  final int contextLength;
  final bool requiresCloudApproval;
  final bool allowCloudPayload;
  final String? recommendedModelId;

  Map<String, Object?> get evidenceMetadata => {
        'target': target.name,
        'reason': reason.name,
        'contextLength': contextLength,
        'requiresCloudApproval': requiresCloudApproval,
        'allowCloudPayload': allowCloudPayload,
        'recommendedModelId': recommendedModelId,
      };
}

/// Pure policy layer. MobileCore reports runtime truth; MobileCode keeps the
/// routing, approval, and device-action authority.
class MobileCoreAdaptivePolicy {
  const MobileCoreAdaptivePolicy._();

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
  }) {
    final localReady = health.canInfer && health.capabilities.textInput;
    final recommendation = _bestSafeRecommendation(recommendations);
    final pressured = _isPressured(health, recommendations, telemetry);
    final constrainedContext = pressured ? 2048 : 4096;

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
        recommendedModelId: recommendation?.modelId,
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
        recommendedModelId: recommendation?.modelId,
      );
    }

    if (pressured && localReady) {
      return MobileCorePolicyDecision(
        target: MobileCorePolicyTarget.local,
        reason: MobileCorePolicyReason.thermalOrMemoryPressure,
        contextLength: constrainedContext,
        requiresCloudApproval: false,
        allowCloudPayload: false,
        recommendedModelId: recommendation?.modelId,
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
        recommendedModelId: recommendation?.modelId,
      );
    }

    if (localReady) {
      return MobileCorePolicyDecision(
        target: MobileCorePolicyTarget.local,
        reason: MobileCorePolicyReason.localReady,
        contextLength: constrainedContext,
        requiresCloudApproval: false,
        allowCloudPayload: false,
        recommendedModelId: recommendation?.modelId,
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
      recommendedModelId: recommendation?.modelId,
    );
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
