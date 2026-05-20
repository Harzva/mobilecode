import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/token_usage_service.dart';

void main() {
  group('TokenUsageService parsers', () {
    test('parses OpenAI usage with cached tokens', () {
      final usage = TokenUsageService.parseOpenAiUsage({
        'usage': {
          'prompt_tokens': 120,
          'completion_tokens': 30,
          'total_tokens': 150,
          'prompt_tokens_details': {'cached_tokens': 50},
        },
      });

      expect(usage.inputTokens, 120);
      expect(usage.outputTokens, 30);
      expect(usage.totalTokens, 150);
      expect(usage.cacheReadTokens, 50);
      expect(usage.cacheMissTokens, 70);
      expect(usage.estimated, isFalse);
    });

    test('parses Anthropic usage with cache creation and read tokens', () {
      final usage = TokenUsageService.parseAnthropicUsage({
        'usage': {
          'input_tokens': 200,
          'output_tokens': 80,
          'cache_creation_input_tokens': 40,
          'cache_read_input_tokens': 60,
        },
      });

      expect(usage.inputTokens, 200);
      expect(usage.outputTokens, 80);
      expect(usage.totalTokens, 280);
      expect(usage.cacheWriteTokens, 40);
      expect(usage.cacheReadTokens, 60);
      expect(usage.cacheMissTokens, 100);
      expect(usage.estimated, isFalse);
    });

    test('accumulator falls back to local estimate when provider omits usage', () {
      final accumulator = TokenUsageAccumulator(providerKind: 'openai')..addChunk({'choices': []});
      final snapshot = accumulator.snapshot(inputChars: 400, outputChars: 160);

      expect(snapshot.estimated, isTrue);
      expect(snapshot.inputTokens, 100);
      expect(snapshot.outputTokens, 40);
      expect(snapshot.totalTokens, 140);
    });
  });
}
