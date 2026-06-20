import 'model_provider_preset_service.dart';

enum ModelRouteEndpoint {
  chat,
  agent,
  toolCall,
}

enum ModelRouteReason {
  configuredModel,
  deepSeekAutoDefaultFlash,
  deepSeekAutoLongContextPro,
  deepSeekAutoComplexCodingPro,
  deepSeekAutoFailureRetryPro,
}

class ModelRouteDecision {
  const ModelRouteDecision({
    required this.preset,
    required this.endpoint,
    required this.model,
    required this.reason,
    required this.isAutoRoute,
    required this.canRetryWithPro,
    required this.candidates,
    this.fallbackFromModel,
    this.failureSummary,
  });

  final ModelProviderPreset preset;
  final ModelRouteEndpoint endpoint;
  final String model;
  final ModelRouteReason reason;
  final bool isAutoRoute;
  final bool canRetryWithPro;
  final List<String> candidates;
  final String? fallbackFromModel;
  final String? failureSummary;

  Map<String, Object?> get metadata => {
        'providerPreset': ModelProviderPresetService.label(preset),
        'endpoint': endpoint.name,
        'actualModel': model,
        'routeReason': reason.name,
        'isAutoRoute': isAutoRoute,
        'canRetryWithPro': canRetryWithPro,
        'routingCandidates': candidates,
        if (fallbackFromModel != null) 'fallbackFromModel': fallbackFromModel,
        if (failureSummary != null) 'failureSummary': failureSummary,
      };

  String get evidenceSummary {
    final suffix =
        fallbackFromModel == null ? '' : ' fallback from $fallbackFromModel';
    return '${ModelProviderPresetService.label(preset)} routed '
        '${endpoint.name} to $model because ${reason.name}$suffix';
  }
}

class ModelRoutingService {
  const ModelRoutingService._();

  static const int _longContextCharacters = 12000;
  static const int _largeOutputTokens = 3072;

  static const List<String> _complexCodingMarkers = [
    '多文件',
    '重构',
    '修复',
    'verifier',
    'evidence ledger',
    '证据账本',
    '架构',
    '调试',
    'debug',
    'refactor',
    'tool call',
    'runtime',
    '失败重试',
    '长上下文',
  ];

  static ModelRouteDecision decide({
    required ModelProviderPreset preset,
    required String configuredModel,
    required ModelRouteEndpoint endpoint,
    required int maxTokens,
    required int inputCharacters,
    String userText = '',
  }) {
    if (preset != ModelProviderPreset.deepSeekAuto) {
      final model = configuredModel.trim().isNotEmpty
          ? configuredModel.trim()
          : ModelProviderPresetService.model(preset);
      return ModelRouteDecision(
        preset: preset,
        endpoint: endpoint,
        model: model,
        reason: ModelRouteReason.configuredModel,
        isAutoRoute: false,
        canRetryWithPro: false,
        candidates: ModelProviderPresetService.routingModels(preset),
      );
    }

    final candidates = ModelProviderPresetService.routingModels(preset);
    final routeToProForContext = inputCharacters >= _longContextCharacters ||
        maxTokens >= _largeOutputTokens;
    if (routeToProForContext) {
      return ModelRouteDecision(
        preset: preset,
        endpoint: endpoint,
        model: ModelProviderPresetService.deepSeekProModel,
        reason: ModelRouteReason.deepSeekAutoLongContextPro,
        isAutoRoute: true,
        canRetryWithPro: false,
        candidates: candidates,
      );
    }

    if (_isComplexCodingRequest(endpoint: endpoint, userText: userText)) {
      return ModelRouteDecision(
        preset: preset,
        endpoint: endpoint,
        model: ModelProviderPresetService.deepSeekProModel,
        reason: ModelRouteReason.deepSeekAutoComplexCodingPro,
        isAutoRoute: true,
        canRetryWithPro: false,
        candidates: candidates,
      );
    }

    return ModelRouteDecision(
      preset: preset,
      endpoint: endpoint,
      model: ModelProviderPresetService.deepSeekFlashModel,
      reason: ModelRouteReason.deepSeekAutoDefaultFlash,
      isAutoRoute: true,
      canRetryWithPro: true,
      candidates: candidates,
    );
  }

  static ModelRouteDecision? retryAfterFailure(
    ModelRouteDecision previous, {
    required String failureSummary,
  }) {
    if (!previous.canRetryWithPro ||
        previous.preset != ModelProviderPreset.deepSeekAuto ||
        previous.model != ModelProviderPresetService.deepSeekFlashModel) {
      return null;
    }
    return ModelRouteDecision(
      preset: previous.preset,
      endpoint: previous.endpoint,
      model: ModelProviderPresetService.deepSeekProModel,
      reason: ModelRouteReason.deepSeekAutoFailureRetryPro,
      isAutoRoute: true,
      canRetryWithPro: false,
      candidates: previous.candidates,
      fallbackFromModel: previous.model,
      failureSummary: failureSummary,
    );
  }

  static bool _isComplexCodingRequest({
    required ModelRouteEndpoint endpoint,
    required String userText,
  }) {
    if (endpoint != ModelRouteEndpoint.chat) {
      return true;
    }
    final probe = userText.toLowerCase();
    return _complexCodingMarkers.any((marker) => probe.contains(marker));
  }
}
