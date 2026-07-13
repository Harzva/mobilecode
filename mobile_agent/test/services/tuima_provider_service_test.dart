import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/tuima_provider_service.dart';

void main() {
  group('TuimaProviderService routing', () {
    test('prefers a ready local model and exposes cloud retry', () {
      final decision = TuimaProviderService.route(
        preference: HybridModelPreference.localPreferred,
        localState: TuimaConnectionState.modelReady,
        cloudConfigured: true,
      );

      expect(decision.target, HybridModelTarget.tuimaLocal);
      expect(decision.reason, HybridModelRouteReason.localModelReady);
      expect(decision.canRetryOnCloud, isTrue);
    });

    test('falls back to cloud when local service has no loaded model', () {
      final decision = TuimaProviderService.route(
        preference: HybridModelPreference.localPreferred,
        localState: TuimaConnectionState.serviceReady,
        cloudConfigured: true,
      );

      expect(decision.target, HybridModelTarget.cloud);
      expect(
        decision.reason,
        HybridModelRouteReason.localUnavailableCloudFallback,
      );
    });

    test('keeps local-only requests offline when TuiMa is unavailable', () {
      final decision = TuimaProviderService.route(
        preference: HybridModelPreference.localOnly,
        localState: TuimaConnectionState.unavailable,
        cloudConfigured: true,
      );

      expect(decision.target, HybridModelTarget.unavailable);
      expect(decision.reason, HybridModelRouteReason.localOnlyUnavailable);
      expect(decision.canRetryOnCloud, isFalse);
    });

    test('publishes a complete local OpenAI-compatible configuration', () {
      expect(TuimaProviderService.localOpenAiConfig(), {
        'provider': 'custom',
        'baseUrl': 'http://127.0.0.1:8080/v1',
        'model': 'qwen2.5-0.5b-instruct-q4_k_m',
        'apiKey': 'local',
      });
    });

    test('falls back to a ready local model only before cloud text is emitted',
        () {
      expect(
        TuimaProviderService.fallbackAfterCloudFailure(
          localState: TuimaConnectionState.modelReady,
          emittedCloudText: false,
        ).target,
        HybridModelTarget.tuimaLocal,
      );
      expect(
        TuimaProviderService.fallbackAfterCloudFailure(
          localState: TuimaConnectionState.modelReady,
          emittedCloudText: true,
        ).target,
        HybridModelTarget.unavailable,
      );
    });
  });

  group('TuimaProviderService transport', () {
    late HttpServer server;
    late TuimaProviderService service;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final root = Uri.parse('http://127.0.0.1:${server.port}');
      service = TuimaProviderService(
        healthUri: root.resolve('/health'),
        chatUri: root.resolve('/v1/chat/completions'),
      );
    });

    tearDown(() async {
      service.close();
      await server.close(force: true);
    });

    test('probes a model-ready MobileCore service', () async {
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'status': 'ok',
          'version': '0.1.3-rc2',
          'backend': 'llama.cpp',
          'active_model': 'qwen',
          'model_loaded': true,
        }));
        await request.response.close();
      });

      final health = await service.probe();
      expect(health.state, TuimaConnectionState.modelReady);
      expect(health.activeModel, 'qwen');
    });

    test('accepts buffered JSON when a provider ignores stream=true', () async {
      server.listen((request) async {
        expect(request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer local');
        expect(request.contentLength, greaterThan(0));
        expect(request.headers.chunkedTransferEncoding, isFalse);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'local answer'}
            }
          ]
        }));
        await request.response.close();
      });

      final chunks = await service.streamChat(
        messages: const [
          {'role': 'user', 'content': 'hello'}
        ],
        model: 'qwen',
      ).toList();
      expect(chunks.join(), 'local answer');
    });

    test('parses OpenAI-compatible SSE deltas', () async {
      server.listen((request) async {
        request.response.headers.contentType =
            ContentType('text', 'event-stream', charset: 'utf-8');
        request.response
            .write('data: {"choices":[{"delta":{"content":"本地"}}]}\n\n');
        request.response
            .write('data: {"choices":[{"delta":{"content":"推理"}}]}\n\n');
        request.response.write('data: [DONE]\n\n');
        await request.response.close();
      });

      final chunks = await service.streamChat(
        messages: const [
          {'role': 'user', 'content': 'hello'}
        ],
        model: 'qwen',
      ).toList();
      expect(chunks.join(), '本地推理');
    });
  });
}
