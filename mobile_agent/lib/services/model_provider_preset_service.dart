enum ModelProviderPreset {
  tuimaLocal,
  mimo,
  deepSeek,
  deepSeekAuto,
  tierFlowAuto,
  anthropic,
  openAi,
  custom,
}

class ModelProviderPresetService {
  const ModelProviderPresetService._();

  static const defaultBaseUrl =
      'https://token-plan-cn.xiaomimimo.com/anthropic';
  static const defaultModel = 'mimo-v2.5-pro';
  static const tierFlowBaseUrl = 'https://cn.tierflow.ai/v1';
  static const tierFlowModel = 'auto';
  static const deepSeekFlashModel = 'deepseek-v4-flash';
  static const deepSeekProModel = 'deepseek-v4-pro';
  static const tuimaBaseUrl = 'http://127.0.0.1:8080/v1';
  static const tuimaModel = 'qwen2.5-0.5b-instruct-q4_k_m';
  static const tuimaLocalToken = 'local';

  static String label(ModelProviderPreset preset) => switch (preset) {
        ModelProviderPreset.tuimaLocal => 'TuiMa Local',
        ModelProviderPreset.mimo => 'Mimo',
        ModelProviderPreset.deepSeek => 'DeepSeek v4',
        ModelProviderPreset.deepSeekAuto => 'DeepSeek Auto',
        ModelProviderPreset.tierFlowAuto => 'TierFlow Auto',
        ModelProviderPreset.anthropic => 'Anthropic',
        ModelProviderPreset.openAi => 'OpenAI',
        ModelProviderPreset.custom => 'Custom',
      };

  static String baseUrl(ModelProviderPreset preset) => switch (preset) {
        ModelProviderPreset.tuimaLocal => tuimaBaseUrl,
        ModelProviderPreset.mimo => defaultBaseUrl,
        ModelProviderPreset.deepSeek => 'https://api.deepseek.com',
        ModelProviderPreset.deepSeekAuto => 'https://api.deepseek.com',
        ModelProviderPreset.tierFlowAuto => tierFlowBaseUrl,
        ModelProviderPreset.anthropic => 'https://api.anthropic.com',
        ModelProviderPreset.openAi => 'https://api.openai.com/v1',
        ModelProviderPreset.custom => '',
      };

  static String model(ModelProviderPreset preset) => switch (preset) {
        ModelProviderPreset.tuimaLocal => tuimaModel,
        ModelProviderPreset.mimo => defaultModel,
        ModelProviderPreset.deepSeek => deepSeekFlashModel,
        ModelProviderPreset.deepSeekAuto => deepSeekFlashModel,
        ModelProviderPreset.tierFlowAuto => tierFlowModel,
        ModelProviderPreset.anthropic => 'claude-3-5-sonnet-latest',
        ModelProviderPreset.openAi => 'gpt-4o-mini',
        ModelProviderPreset.custom => '',
      };

  static bool isAutoRouter(ModelProviderPreset preset) =>
      preset == ModelProviderPreset.tierFlowAuto ||
      preset == ModelProviderPreset.deepSeekAuto;

  static List<String> routingModels(ModelProviderPreset preset) =>
      switch (preset) {
        ModelProviderPreset.deepSeekAuto => const [
            deepSeekFlashModel,
            deepSeekProModel,
          ],
        ModelProviderPreset.tierFlowAuto => const [tierFlowModel],
        _ => [model(preset)].where((value) => value.isNotEmpty).toList(),
      };

  static ModelProviderPreset detect({
    required String baseUrl,
    required String model,
  }) {
    final probe = '$baseUrl $model'.toLowerCase();
    final normalizedModel = model.trim().toLowerCase();
    if (probe.contains('127.0.0.1:8080') ||
        probe.contains('localhost:8080') ||
        probe.contains('tuima') ||
        normalizedModel == tuimaModel) {
      return ModelProviderPreset.tuimaLocal;
    }
    if (probe.contains('tierflow') || normalizedModel == tierFlowModel) {
      return ModelProviderPreset.tierFlowAuto;
    }
    if (probe.contains('xiaomimimo') || probe.contains('mimo-')) {
      return ModelProviderPreset.mimo;
    }
    if (probe.contains('deepseek-auto') || probe.contains('deepseek v4 auto')) {
      return ModelProviderPreset.deepSeekAuto;
    }
    if (probe.contains('deepseek')) {
      return ModelProviderPreset.deepSeek;
    }
    if (probe.contains('anthropic') || probe.contains('claude')) {
      return ModelProviderPreset.anthropic;
    }
    if (probe.contains('openai') || probe.contains('gpt-')) {
      return ModelProviderPreset.openAi;
    }
    return ModelProviderPreset.custom;
  }

  static List<ModelProviderPreset> get composerChoices => const [
        ModelProviderPreset.tuimaLocal,
        ModelProviderPreset.mimo,
        ModelProviderPreset.deepSeek,
        ModelProviderPreset.deepSeekAuto,
        ModelProviderPreset.tierFlowAuto,
        ModelProviderPreset.openAi,
        ModelProviderPreset.anthropic,
        ModelProviderPreset.custom,
      ];
}
