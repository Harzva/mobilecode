import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/model_provider_preset_service.dart';
import 'package:mobile_agent/services/model_routing_service.dart';

void main() {
  group('ModelRoutingService', () {
    test('keeps simple DeepSeek Auto chat on Flash', () {
      final decision = ModelRoutingService.decide(
        preset: ModelProviderPreset.deepSeekAuto,
        configuredModel: ModelProviderPresetService.deepSeekFlashModel,
        endpoint: ModelRouteEndpoint.chat,
        maxTokens: 1024,
        inputCharacters: 900,
        userText: '帮我解释这段 Dart 函数。',
      );

      expect(decision.model, ModelProviderPresetService.deepSeekFlashModel);
      expect(decision.reason, ModelRouteReason.deepSeekAutoDefaultFlash);
      expect(decision.canRetryWithPro, isTrue);
      expect(decision.metadata['actualModel'], decision.model);
      expect(decision.metadata['routeReason'], 'deepSeekAutoDefaultFlash');
    });

    test('routes long-context DeepSeek Auto requests to Pro', () {
      final decision = ModelRoutingService.decide(
        preset: ModelProviderPreset.deepSeekAuto,
        configuredModel: ModelProviderPresetService.deepSeekFlashModel,
        endpoint: ModelRouteEndpoint.chat,
        maxTokens: 4096,
        inputCharacters: 16000,
        userText: '请基于这些文件做一次完整审查。',
      );

      expect(decision.model, ModelProviderPresetService.deepSeekProModel);
      expect(decision.reason, ModelRouteReason.deepSeekAutoLongContextPro);
      expect(decision.canRetryWithPro, isFalse);
    });

    test('routes complex coding DeepSeek Auto requests to Pro', () {
      final decision = ModelRoutingService.decide(
        preset: ModelProviderPreset.deepSeekAuto,
        configuredModel: ModelProviderPresetService.deepSeekFlashModel,
        endpoint: ModelRouteEndpoint.agent,
        maxTokens: 2048,
        inputCharacters: 3000,
        userText: '重构多个文件并修复 verifier 失败，记录 evidence ledger。',
      );

      expect(decision.model, ModelProviderPresetService.deepSeekProModel);
      expect(decision.reason, ModelRouteReason.deepSeekAutoComplexCodingPro);
      expect(decision.canRetryWithPro, isFalse);
    });

    test('retries a failed Flash DeepSeek Auto request on Pro', () {
      final initial = ModelRoutingService.decide(
        preset: ModelProviderPreset.deepSeekAuto,
        configuredModel: ModelProviderPresetService.deepSeekFlashModel,
        endpoint: ModelRouteEndpoint.chat,
        maxTokens: 1024,
        inputCharacters: 700,
        userText: '生成一个小组件。',
      );

      final retry = ModelRoutingService.retryAfterFailure(
        initial,
        failureSummary: 'HTTP 429 rate limited',
      );

      expect(retry, isNotNull);
      expect(retry!.model, ModelProviderPresetService.deepSeekProModel);
      expect(retry.reason, ModelRouteReason.deepSeekAutoFailureRetryPro);
      expect(retry.failureSummary, 'HTTP 429 rate limited');
      expect(retry.metadata['fallbackFromModel'], initial.model);
    });

    test('leaves non-auto providers on their configured model', () {
      final decision = ModelRoutingService.decide(
        preset: ModelProviderPreset.openAi,
        configuredModel: 'gpt-4o-mini',
        endpoint: ModelRouteEndpoint.chat,
        maxTokens: 4096,
        inputCharacters: 20000,
        userText: '重构多个文件。',
      );

      expect(decision.model, 'gpt-4o-mini');
      expect(decision.reason, ModelRouteReason.configuredModel);
      expect(decision.canRetryWithPro, isFalse);
      expect(decision.isAutoRoute, isFalse);
    });
  });
}
