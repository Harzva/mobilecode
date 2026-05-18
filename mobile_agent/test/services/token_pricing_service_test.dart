import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/token_pricing_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads built-in LiteLLM-compatible snapshot and estimates cost', () async {
    SharedPreferences.setMockInitialValues({});
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
    SharedPreferences.setMockInitialValues({});
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
}
