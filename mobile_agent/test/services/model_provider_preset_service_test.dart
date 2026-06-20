import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/model_provider_preset_service.dart';

void main() {
  group('ModelProviderPresetService', () {
    test('defines TierFlow auto as an OpenAI-compatible routing preset', () {
      const preset = ModelProviderPreset.tierFlowAuto;

      expect(ModelProviderPresetService.label(preset), 'TierFlow Auto');
      expect(
        ModelProviderPresetService.baseUrl(preset),
        'https://cn.tierflow.ai/v1',
      );
      expect(ModelProviderPresetService.model(preset), 'auto');
    });

    test('detects TierFlow auto provider from base URL or auto model', () {
      expect(
        ModelProviderPresetService.detect(
          baseUrl: 'https://cn.tierflow.ai/v1',
          model: 'auto',
        ),
        ModelProviderPreset.tierFlowAuto,
      );
      expect(
        ModelProviderPresetService.detect(
          baseUrl: 'https://example.com/v1',
          model: 'auto',
        ),
        ModelProviderPreset.tierFlowAuto,
      );
    });

    test('defines DeepSeek auto as a Flash to Pro routing preset', () {
      const preset = ModelProviderPreset.deepSeekAuto;

      expect(ModelProviderPresetService.label(preset), 'DeepSeek Auto');
      expect(
        ModelProviderPresetService.baseUrl(preset),
        'https://api.deepseek.com',
      );
      expect(
        ModelProviderPresetService.model(preset),
        'deepseek-v4-flash',
      );
      expect(
        ModelProviderPresetService.routingModels(preset),
        ['deepseek-v4-flash', 'deepseek-v4-pro'],
      );
      expect(ModelProviderPresetService.isAutoRouter(preset), true);
    });
  });
}
