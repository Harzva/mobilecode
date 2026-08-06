import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/device_telemetry_service.dart';
import 'package:mobile_agent/services/mobilecore_adaptive_policy.dart';
import 'package:mobile_agent/services/tuima_provider_service.dart';

void main() {
  test('privacy and offline tasks never become cloud payloads', () {
    final decision = MobileCoreAdaptivePolicy.decide(
      health: _health(),
      recommendations: _recommendations(),
      telemetry: _telemetry(),
      privacySensitive: true,
      cloudAvailable: true,
      cloudApproved: true,
    );

    expect(decision.target, MobileCorePolicyTarget.local);
    expect(decision.allowCloudPayload, isFalse);
    expect(decision.reason, MobileCorePolicyReason.privacyRequiresLocal);
  });

  test('local media is unavailable instead of silently falling back', () {
    final decision = MobileCoreAdaptivePolicy.decide(
      health: _health(image: false),
      recommendations: _recommendations(),
      telemetry: _telemetry(),
      attachmentKind: MobileCoreAttachmentKind.image,
      cloudAvailable: true,
      cloudApproved: true,
    );

    expect(decision.target, MobileCorePolicyTarget.unavailable);
    expect(decision.allowCloudPayload, isFalse);
    expect(decision.requiresCloudApproval, isFalse);
  });

  test('thermal pressure shortens context and selects the smallest safe model',
      () {
    final decision = MobileCoreAdaptivePolicy.decide(
      health: _health(),
      recommendations: _recommendations(),
      telemetry: _telemetry(thermalStatus: 5),
    );

    expect(decision.reason, MobileCorePolicyReason.thermalOrMemoryPressure);
    expect(decision.contextLength, 2048);
    expect(decision.recommendedModelId, 'small-q4');
  });

  test('complex work needs explicit approval before cloud routing', () {
    final pending = MobileCoreAdaptivePolicy.decide(
      health: _health(),
      recommendations: _recommendations(),
      telemetry: _telemetry(),
      complexTask: true,
      cloudAvailable: true,
    );
    final approved = MobileCoreAdaptivePolicy.decide(
      health: _health(),
      recommendations: _recommendations(),
      telemetry: _telemetry(),
      complexTask: true,
      cloudAvailable: true,
      cloudApproved: true,
    );

    expect(pending.target, MobileCorePolicyTarget.local);
    expect(pending.requiresCloudApproval, isTrue);
    expect(pending.allowCloudPayload, isFalse);
    expect(approved.target, MobileCorePolicyTarget.cloud);
    expect(approved.allowCloudPayload, isTrue);
  });
}

TuimaHealth _health({bool image = true}) => TuimaHealth(
      state: TuimaConnectionState.modelReady,
      version: '0.1.3-rc2',
      backend: 'cpu',
      runtime: 'llama.cpp/libmtmd',
      activeModel: 'small-q4',
      quantization: 'Q4_K_M',
      capabilities: MobileCoreCapabilities(
        textInput: true,
        textOutput: true,
        imageInput: image,
      ),
      preflight: const MobileCorePreflight(
        ok: true,
        memory: MobileCoreResourceHealth(
          availableBytes: 8000,
          requiredBytes: 4000,
          ok: true,
        ),
        storage: MobileCoreResourceHealth(
          availableBytes: 16000,
          requiredBytes: 4000,
          ok: true,
        ),
      ),
    );

MobileCoreRecommendations _recommendations() => const MobileCoreRecommendations(
      availableRamMb: 4096,
      recommendations: [
        MobileCoreRecommendation(
          modelId: 'large-q4',
          fit: 'good',
          score: 90,
          estimatedMemoryMb: 3000,
        ),
        MobileCoreRecommendation(
          modelId: 'small-q4',
          fit: 'perfect',
          score: 80,
          estimatedMemoryMb: 800,
        ),
      ],
    );

DeviceTelemetrySnapshot _telemetry({int thermalStatus = 0}) =>
    DeviceTelemetrySnapshot(
      platform: 'android',
      manufacturer: 'test',
      model: 'test',
      androidVersion: '15',
      sdkInt: 35,
      abis: const ['arm64-v8a'],
      cpuCores: 8,
      cpuUsagePercent: 10,
      totalMemoryMb: 8192,
      availableMemoryMb: 4096,
      lowMemory: false,
      appRssMb: 256,
      appHeapMb: 128,
      storageTotalMb: 64000,
      storageFreeMb: 32000,
      batteryLevel: 80,
      batteryCharging: false,
      batteryTemperatureC: 32,
      thermalStatus: thermalStatus,
      timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      fallback: false,
    );
