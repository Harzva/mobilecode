import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
        'model': 'mobilecore-active',
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
        modelsUri: root.resolve('/v1/models'),
        metricsUri: root.resolve('/metrics'),
        recommendationsUri: root.resolve('/v1/recommendations'),
        modelLoadUri: root.resolve('/mobilecore/model/load'),
        modelUnloadUri: root.resolve('/mobilecore/model/unload'),
        omniStatusUri: root.resolve('/mobilecore/omni/status'),
        inferenceCancelUri: root.resolve('/mobilecore/inference/cancel'),
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
          'service': 'mobilecore',
          'protocol': _mobileCoreProtocolV2,
          'version': '0.1.3-rc2',
          'backend': 'llama.cpp',
          'runtime': 'llama.cpp/libmtmd',
          'llama_cpp_revision': 'b7035',
          'quantization': 'Q4_K_M',
          'active_model': 'qwen',
          'model_loaded': true,
          'capabilities': {
            'text_input': true,
            'image_input': true,
            'audio_input': false,
            'video_input': false,
            'text_output': true,
            'audio_output': false,
          },
          'artifacts': {
            'main': {'present': true, 'verified': true},
            'mmproj': {'present': true, 'verified': false},
          },
          'preflight': {
            'memory': {
              'available_bytes': 8000,
              'required_bytes': 4000,
              'ok': true,
            },
            'storage': {
              'available_bytes': 16000,
              'required_bytes': 4000,
              'ok': true,
            },
            'ok': true,
          },
        }));
        await request.response.close();
      });

      final health = await service.probe();
      expect(health.state, TuimaConnectionState.modelReady);
      expect(health.activeModel, 'qwen');
      expect(health.quantization, 'Q4_K_M');
      expect(health.capabilities.imageInput, isTrue);
      expect(health.capabilities.audioInput, isFalse);
      expect(health.preflight.ok, isTrue);
      expect(health.mainArtifact.verified, isTrue);
      expect(health.evidenceMetadata.toString(), isNot(contains('8000')));
    });

    test('rejects a missing MobileCoreClient protocol handshake', () async {
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          ..._healthPayload(),
          'protocol': null,
        }));
        await request.response.close();
      });

      final health = await service.probe();
      expect(health.state, TuimaConnectionState.unavailable);
      expect(health.failureCode, 'protocol_missing');
      expect(health.evidenceMetadata['failureCode'], 'protocol_missing');
    });

    test('blocks model control when the protocol major is unsupported',
        () async {
      var controlRequests = 0;
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/health') {
          request.response.write(jsonEncode({
            ..._healthPayload(),
            'protocol': const {
              'name': 'mobilecore.local',
              'major': 3,
              'minor': 0,
              'min_client_major': 3,
              'max_client_major': 3,
            },
          }));
        } else {
          controlRequests += 1;
          request.response.write('{"ok":true}');
        }
        await request.response.close();
      });

      await expectLater(
        service.switchModel('small-q4'),
        throwsA(isA<MobileCoreProviderException>().having(
          (error) => error.code,
          'code',
          'protocol_unsupported',
        )),
      );
      expect(controlRequests, 0);
    });

    test('checks the active model before sending inference payloads', () async {
      var chatRequests = 0;
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/health') {
          request.response
              .write(jsonEncode(_healthPayload(model: 'active-q4')));
        } else {
          chatRequests += 1;
          request.response.write('{"choices":[]}');
        }
        await request.response.close();
      });

      await expectLater(
        service.completeChat(
          messages: const [
            {'role': 'user', 'content': 'hello'}
          ],
          model: 'stale-q4',
        ),
        throwsA(isA<MobileCoreProviderException>().having(
          (error) => error.code,
          'code',
          'model_state_mismatch',
        )),
      );
      expect(chatRequests, 0);
    });

    test('maps a buffered local inference timeout to typed evidence', () async {
      var cancelRequests = 0;
      server.listen((request) async {
        if (request.uri.path == '/health') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(_healthPayload()));
        } else if (request.uri.path == '/mobilecore/inference/cancel') {
          cancelRequests += 1;
          request.response.headers.contentType = ContentType.json;
          request.response.write('{"ok":true,"cancel_requested":true}');
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 150));
          request.response.headers.contentType = ContentType.json;
          request.response.write('{"choices":[]}');
        }
        await request.response.close();
      });

      await expectLater(
        service.completeChat(
          messages: const [
            {'role': 'user', 'content': 'hello'}
          ],
          model: 'qwen',
          timeout: const Duration(milliseconds: 30),
        ),
        throwsA(isA<MobileCoreProviderException>().having(
          (error) => error.code,
          'code',
          'inference_timeout',
        )),
      );
      expect(cancelRequests, 1);
    });

    test('sends an authenticated inference cancellation request', () async {
      server.listen((request) async {
        expect(request.uri.path, '/mobilecore/inference/cancel');
        expect(request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer local');
        await utf8.decoder.bind(request).join();
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"ok":true,"cancel_requested":true}');
        await request.response.close();
      });

      expect(await service.cancelInference(), isTrue);
    });

    test('accepts buffered JSON when a provider ignores stream=true', () async {
      server.listen((request) async {
        if (request.uri.path == '/health') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(_healthPayload()));
          await request.response.close();
          return;
        }
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
        if (request.uri.path == '/health') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(_healthPayload()));
          await request.response.close();
          return;
        }
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

    test('lists models and parses metrics without exposing model paths',
        () async {
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/v1/models') {
          request.response.write(jsonEncode({
            'object': 'list',
            'data': [
              {
                'id': 'small-q4',
                'mobilecore': {
                  'path': '/private/models/small-q4.gguf',
                  'quantization': 'Q4_K_M',
                  'context_length': 4096,
                  'size_bytes': 1234,
                  'loaded': true,
                  'projector_id': 'mmproj-small-q4-bf16',
                  'projector_size_bytes': 456,
                  'capabilities': {
                    'text_input': true,
                    'image_input': true,
                    'text_output': true,
                  },
                }
              }
            ]
          }));
        } else {
          request.response.write(jsonEncode({
            'active_model': 'small-q4',
            'backend': 'llama.cpp',
            'last_decode_tokens_per_second': 18.5,
            'last_first_token_ms': 82,
            'last_total_ms': 200,
            'memory_peak_mb': 512,
          }));
        }
        await request.response.close();
      });

      final models = await service.listModels();
      final metrics = await service.metrics();
      expect(models.single.id, 'small-q4');
      expect(models.single.quantization, 'Q4_K_M');
      expect(models.single.projectorId, 'mmproj-small-q4-bf16');
      expect(models.single.projectorSizeBytes, 456);
      expect(models.single.capabilities.imageInput, isTrue);
      expect(models.single.toString(), isNot(contains('/private/')));
      expect(metrics.decodeTokensPerSecond, 18.5);
      expect(metrics.firstTokenMs, 82);
    });

    test('reads a coherent runtime snapshot across control endpoints',
        () async {
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        switch (request.uri.path) {
          case '/health':
            request.response.write(jsonEncode({
              'status': 'ok',
              'service': 'mobilecore',
              'protocol': _mobileCoreProtocolV2,
              'version': '0.1.4-rc2',
              'backend': 'cpu',
              'runtime': 'llama.cpp',
              'llama_cpp_revision': 'fixed-revision',
              'quantization': 'Q4_K_M',
              'active_model': 'small-q4',
              'model_loaded': true,
              'capabilities': {
                'text_input': true,
                'text_output': true,
              },
            }));
            break;
          case '/v1/models':
            request.response.write(jsonEncode({
              'data': [
                {
                  'id': 'small-q4',
                  'mobilecore': {
                    'size_bytes': 1234,
                    'loaded': true,
                    'quantization': 'Q4_K_M',
                  },
                },
              ],
            }));
            break;
          case '/metrics':
            request.response.write(jsonEncode({
              'active_model': 'small-q4',
              'backend': 'cpu',
              'last_decode_tokens_per_second': 8.5,
            }));
            break;
          case '/v1/recommendations':
            request.response.write(jsonEncode({
              'device': {'available_ram_mb': 4096},
              'recommendations': [
                {
                  'model_id': 'small-q4',
                  'fit': 'perfect',
                  'score': 90,
                },
              ],
            }));
            break;
        }
        await request.response.close();
      });

      final snapshot = await service.runtimeSnapshot();
      expect(snapshot.health.activeModel, 'small-q4');
      expect(snapshot.models.single.loaded, isTrue);
      expect(snapshot.metrics.decodeTokensPerSecond, 8.5);
      expect(
          snapshot.recommendations.recommendations.single.modelId, 'small-q4');
    });

    test('rejects a control snapshot that keeps changing', () async {
      var healthRequests = 0;
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/health') {
          healthRequests += 1;
          request.response.write(jsonEncode({
            'status': 'ok',
            'service': 'mobilecore',
            'protocol': _mobileCoreProtocolV2,
            'version': '0.1.4-rc2',
            'backend': 'cpu',
            'runtime': 'llama.cpp',
            'llama_cpp_revision': 'fixed-revision',
            'quantization': 'Q4_K_M',
            'active_model': 'model-$healthRequests',
            'model_loaded': true,
            'capabilities': {
              'text_input': true,
              'text_output': true,
            },
          }));
        } else if (request.uri.path == '/v1/models') {
          request.response.write(jsonEncode({
            'data': [
              {
                'id': 'stable-model',
                'mobilecore': {'size_bytes': 1234, 'loaded': true},
              },
            ],
          }));
        } else if (request.uri.path == '/metrics') {
          request.response.write('{"backend":"cpu"}');
        } else if (request.uri.path == '/v1/recommendations') {
          request.response.write('{"recommendations":[]}');
        }
        await request.response.close();
      });

      await expectLater(
        service.runtimeSnapshot(),
        throwsA(isA<MobileCoreProviderException>().having(
          (error) => error.code,
          'code',
          'runtime_snapshot_changed',
        )),
      );
      expect(healthRequests, 3);
    });

    test('switches by public model/projector ids without submitting a path',
        () async {
      var loaded = false;
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/mobilecore/model/load') {
          final body = jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>;
          expect(body['model_id'], 'small-q4');
          expect(body['projector_id'], 'mmproj-small-q4-bf16');
          expect(body.containsKey('path'), isFalse);
          loaded = true;
          request.response.write('{"ok":true}');
        } else if (request.uri.path == '/mobilecore/model/unload') {
          loaded = false;
          request.response.write('{"ok":true}');
        } else if (request.uri.path == '/health') {
          request.response.write(jsonEncode({
            'status': 'ok',
            'service': 'mobilecore',
            'protocol': _mobileCoreProtocolV2,
            'version': '0.1.3-rc2',
            'backend': 'cpu',
            'active_model': loaded ? 'small-q4' : null,
            'model_loaded': loaded,
          }));
        }
        await request.response.close();
      });

      final loadedHealth = await service.switchModel(
        'small-q4',
        projectorId: 'mmproj-small-q4-bf16',
      );
      expect(loadedHealth.activeModel, 'small-q4');
      final unloadedHealth = await service.unloadModel();
      expect(unloadedHealth.canInfer, isFalse);
    });

    test('rejects path-like lifecycle ids before contacting MobileCore',
        () async {
      var requests = 0;
      server.listen((request) async {
        requests += 1;
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      });

      await expectLater(
        service.switchModel('../private/model.gguf'),
        throwsA(isA<MobileCoreProviderException>().having(
          (error) => error.code,
          'code',
          'invalid_model_id',
        )),
      );
      await expectLater(
        service.switchModel(
          'small-q4',
          projectorId: '/private/mmproj.gguf',
        ),
        throwsA(isA<MobileCoreProviderException>().having(
          (error) => error.code,
          'code',
          'invalid_projector_id',
        )),
      );
      expect(requests, 0);
    });

    test('does not accept a substring model as a successful switch', () async {
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/mobilecore/model/load') {
          await utf8.decoder.bind(request).join();
          request.response.write('{"ok":true}');
        } else if (request.uri.path == '/health') {
          request.response.write(jsonEncode({
            'status': 'ok',
            'service': 'mobilecore',
            'protocol': _mobileCoreProtocolV2,
            'version': '0.1.4-rc2',
            'backend': 'cpu',
            'active_model': 'old-small-q4-copy',
            'model_loaded': true,
          }));
        }
        await request.response.close();
      });

      await expectLater(
        service.switchModel('small-q4'),
        throwsA(isA<MobileCoreProviderException>().having(
          (error) => error.code,
          'code',
          'model_state_mismatch',
        )),
      );
    });

    test('extracts final inference metrics from the SSE terminal event',
        () async {
      server.listen((request) async {
        if (request.uri.path == '/health') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(_healthPayload(model: 'small-q4')));
          await request.response.close();
          return;
        }
        request.response.headers.contentType =
            ContentType('text', 'event-stream', charset: 'utf-8');
        request.response
            .write('data: {"choices":[{"delta":{"content":"ok"}}]}\n\n');
        request.response.write(
          'data: {"model":"small-q4","choices":[{"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":2,"completion_tokens":1,"total_tokens":3},"mobilecore":{"backend":"llama.cpp","decode_tokens_per_second":11.5,"first_token_ms":90,"total_ms":180,"memory_peak_mb":400}}\n\n',
        );
        request.response.write('data: [DONE]\n\n');
        await request.response.close();
      });

      MobileCoreMetrics? metrics;
      final chunks = await service.streamChat(
        messages: const [
          {'role': 'user', 'content': 'hello'}
        ],
        model: 'small-q4',
        onMetrics: (value) => metrics = value,
      ).toList();
      expect(chunks.join(), 'ok');
      expect(metrics?.activeModel, 'small-q4');
      expect(metrics?.decodeTokensPerSecond, 11.5);
      expect(metrics?.totalTokens, 3);
    });
  });

  test('multimodal attachment evidence never contains payload data', () {
    final attachment = MobileCoreAttachment(
      kind: MobileCoreAttachmentKind.image,
      bytes: Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]),
      mimeType: 'image/png',
      displayName: 'private.png',
    );

    final part = attachment.toContentPart();
    expect(part['type'], 'image_url');
    expect(part.toString(), contains('base64'));
    expect(attachment.evidenceMetadata.toString(), isNot(contains('iVBOR')));
    expect(attachment.evidenceMetadata['redaction'], 'payload_omitted');
  });
}

const _mobileCoreProtocolV2 = <String, Object>{
  'name': 'mobilecore.local',
  'major': 2,
  'minor': 0,
  'min_client_major': 2,
  'max_client_major': 2,
};

Map<String, Object?> _healthPayload({String model = 'qwen'}) => {
      'status': 'ok',
      'service': 'mobilecore',
      'protocol': _mobileCoreProtocolV2,
      'version': '0.1.4-rc4',
      'backend': 'cpu',
      'runtime': 'llama.cpp',
      'llama_cpp_revision': 'fixed-revision',
      'quantization': 'Q4_K_M',
      'active_model': model,
      'model_loaded': true,
      'capabilities': const {
        'text_input': true,
        'text_output': true,
      },
    };
