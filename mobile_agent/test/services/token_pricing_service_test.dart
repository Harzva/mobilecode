import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/token_pricing_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TokenPricingService.instance.resetForTesting();
    SharedPreferences.setMockInitialValues({});
  });

  test('loads built-in LiteLLM-compatible snapshot and estimates cost', () async {
    final service = TokenPricingService.instance;
    await service.initialize();

    final estimate = await service.estimateCost(
      provider: 'OpenAI',
      model: 'gpt-4o-mini',
      inputTokens: 1000000,
      outputTokens: 1000000,
      cacheReadTokens: 0,
      cacheWriteTokens: 0,
    );

    expect(estimate.price.sourceName, contains('LiteLLM'));
    expect(estimate.price.inputPerMillion, closeTo(0.15, 0.001));
    expect(estimate.price.outputPerMillion, closeTo(0.60, 0.001));
    expect(estimate.costUsd, closeTo(0.75, 0.01));
  });

  test('user override wins over snapshot', () async {
    final service = TokenPricingService.instance;
    await service.initialize();

    await service.upsertOverride(TokenPrice(
      provider: 'openai',
      model: 'gpt-4o-mini',
      inputCostPerToken: 0.000001,
      outputCostPerToken: 0.000002,
      cacheReadCostPerToken: 0,
      cacheWriteCostPerToken: 0,
      sourceName: 'User override',
      sourceUrl: '',
      updatedAt: DateTime(2026, 5, 18),
      custom: true,
    ));

    final estimate = await service.estimateCost(
      provider: 'openai',
      model: 'gpt-4o-mini',
      inputTokens: 1000000,
      outputTokens: 1000000,
      cacheReadTokens: 0,
      cacheWriteTokens: 0,
    );

    expect(estimate.price.custom, isTrue);
    expect(estimate.costUsd, closeTo(3.0, 0.01));
  });

  test('parses and applies official LiteLLM model-map snapshot', () async {
    final service = TokenPricingService.instance;
    await service.initialize();

    final updatedAt = DateTime(2026, 5, 18);
    final update = service.buildUpdateFromJson(
      jsonEncode({
        'gpt-manual-test': {
          'litellm_provider': 'openai',
          'input_cost_per_token': 0.000001,
          'output_cost_per_token': 0.000002,
          'cache_read_input_token_cost': 0.0000002,
          'cache_creation_input_token_cost': 0.0000005,
        },
      }),
      sourceName: 'LiteLLM remote snapshot',
      sourceUrl: TokenPricingService.officialLiteLlmRawUrl,
      updatedAt: updatedAt,
    );

    expect(update.modelCount, 1);
    expect(update.newCount, 1);

    await service.applySnapshotUpdate(update);
    final catalog = service.catalog;
    expect(catalog.sourceName, 'LiteLLM remote snapshot');
    expect(catalog.snapshotCount, 1);

    final estimate = await service.estimateCost(
      provider: 'openai',
      model: 'gpt-manual-test',
      inputTokens: 1000000,
      outputTokens: 1000000,
      cacheReadTokens: 0,
      cacheWriteTokens: 0,
    );

    expect(estimate.price.sourceUrl, TokenPricingService.officialLiteLlmRawUrl);
    expect(estimate.costUsd, closeTo(3.0, 0.01));

    service.resetForTesting();
    await service.initialize();
    expect(service.catalog.sourceName, 'LiteLLM remote snapshot');

    final reloadedEstimate = await service.estimateCost(
      provider: 'openai',
      model: 'gpt-manual-test',
      inputTokens: 1000000,
      outputTokens: 1000000,
      cacheReadTokens: 0,
      cacheWriteTokens: 0,
    );

    expect(reloadedEstimate.costUsd, closeTo(3.0, 0.01));
  });
}
