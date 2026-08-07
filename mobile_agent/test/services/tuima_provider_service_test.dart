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
        omniLoadUri: root.resolve('/mobilecore/omni/load'),
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

    test('fails closed when Android background-restricts MobileCore', () async {
      var chatRequests = 0;
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/health') {
          request.response.write(jsonEncode({
            ..._healthPayload(),
            'background_restricted': true,
          }));
        } else {
          chatRequests += 1;
          request.response.write('{"choices":[]}');
        }
        await request.response.close();
      });

      final health = await service.probe();
      expect(health.state, TuimaConnectionState.serviceReady);
      expect(health.canInfer, isFalse);
      expect(health.backgroundRestricted, isTrue);
      expect(health.failureCode, 'background_restricted');
      expect(health.activeModel, 'qwen');

      await expectLater(
        service.completeChat(
          messages: const [
            {'role': 'user', 'content': 'hello'}
          ],
          model: 'qwen',
        ),
        throwsA(isA<MobileCoreProviderException>().having(
          (error) => error.code,
          'code',
          'background_restricted',
        )),
      );
      expect(chatRequests, 0);
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
                  'backend': 'llama.cpp',
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
            'uptime_seconds': 99,
            'requests_total': 8,
            'requests_completed': 6,
            'requests_failed': 1,
            'inference_cancel_requests': 1,
            'inference_busy_rejections': 2,
            'last_decode_tokens_per_second': 18.5,
            'average_decode_tokens_per_second': 17.25,
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
      expect(models.single.backend, 'llama.cpp');
      expect(models.single.quantization, 'Q4_K_M');
      expect(models.single.projectorId, 'mmproj-small-q4-bf16');
      expect(models.single.projectorSizeBytes, 456);
      expect(models.single.capabilities.imageInput, isTrue);
      expect(models.single.toString(), isNot(contains('/private/')));
      expect(metrics.decodeTokensPerSecond, 18.5);
      expect(metrics.averageDecodeTokensPerSecond, 17.25);
      expect(metrics.firstTokenMs, 82);
      expect(metrics.uptimeSeconds, 99);
      expect(metrics.requestsTotal, 8);
      expect(metrics.requestsCompleted, 6);
      expect(metrics.requestsFailed, 1);
      expect(metrics.inferenceCancelRequests, 1);
      expect(metrics.inferenceBusyRejections, 2);
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

    test('keeps a restricted loaded model visible in a coherent snapshot',
        () async {
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        switch (request.uri.path) {
          case '/health':
            request.response.write(jsonEncode({
              ..._healthPayload(model: 'small-q4'),
              'background_restricted': true,
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
            }));
            break;
          case '/v1/recommendations':
            request.response.write('{"recommendations":[]}');
            break;
        }
        await request.response.close();
      });

      final snapshot = await service.runtimeSnapshot();
      expect(snapshot.health.backgroundRestricted, isTrue);
      expect(snapshot.health.canInfer, isFalse);
      expect(snapshot.health.activeModel, 'small-q4');
      expect(snapshot.models.single.loaded, isTrue);
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

    test(
        'switch preflight counts only the matching active runtime as reclaimable',
        () async {
      var activeModel = 'current-q4';
      var loadRequests = 0;
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        switch (request.uri.path) {
          case '/health':
            request.response.write(
              jsonEncode(_healthPayload(model: activeModel)),
            );
            break;
          case '/v1/models':
            request.response.write(jsonEncode({
              'data': [
                {
                  'id': 'current-q4',
                  'mobilecore': {
                    'backend': 'llama.cpp',
                    'size_bytes': 480 * 1024 * 1024,
                    'context_length': 4096,
                    'loaded': activeModel == 'current-q4',
                  },
                },
                {
                  'id': 'target-q4',
                  'mobilecore': {
                    'backend': 'llama.cpp',
                    'size_bytes': 468 * 1024 * 1024,
                    'context_length': 32768,
                    'loaded': activeModel == 'target-q4',
                  },
                },
              ],
            }));
            break;
          case '/metrics':
            request.response.write(jsonEncode({
              'active_model': activeModel,
              'backend': 'android-llama-cpp',
              'memory_peak_mb': 456,
            }));
            break;
          case '/v1/recommendations':
            request.response.write(jsonEncode({
              'device': {'available_ram_mb': 554},
              'recommendations': [
                {
                  'model_id': 'current-q4',
                  'fit': 'too_tight',
                  'estimated_memory_mb': 589,
                  'context_length': 4096,
                  'loaded': activeModel == 'current-q4',
                  'score': 0,
                },
                {
                  'model_id': 'target-q4',
                  'fit': 'too_tight',
                  'estimated_memory_mb': 596,
                  'context_length': 32768,
                  'loaded': activeModel == 'target-q4',
                  'score': 0,
                },
              ],
            }));
            break;
          case '/mobilecore/model/load':
            final body = jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
            expect(body['model_id'], 'target-q4');
            expect(body['context_length'], 4096);
            expect(body.containsKey('path'), isFalse);
            loadRequests += 1;
            activeModel = 'target-q4';
            request.response.write('{"ok":true}');
            break;
        }
        await request.response.close();
      });

      final result = await service.switchModelWithPreflight('target-q4');
      expect(result.health.activeModel, 'target-q4');
      expect(result.plan.allowed, isTrue);
      expect(result.plan.serverFit, 'too_tight');
      expect(result.plan.availableMemoryMb, 554);
      expect(result.plan.reclaimableRuntimeMemoryMb, 456);
      expect(result.plan.projectedAvailableMemoryMb, 1010);
      expect(result.plan.estimatedRequiredMemoryMb, 596);
      expect(result.plan.usedReclaimableRuntimeMemory, isTrue);
      expect(result.plan.contextLength, 4096);
      expect(result.plan.evidenceMetadata.toString(), isNot(contains('/')));
      expect(loadRequests, 1);
    });

    test('switch preflight rejects a stale runtime before model load',
        () async {
      var healthRequests = 0;
      var loadRequests = 0;
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        switch (request.uri.path) {
          case '/health':
            healthRequests += 1;
            request.response.write(jsonEncode(_healthPayload(
              model: healthRequests <= 2 ? 'current-q4' : 'other-q4',
            )));
            break;
          case '/v1/models':
            request.response.write(jsonEncode({
              'data': [
                {
                  'id': 'current-q4',
                  'mobilecore': {
                    'size_bytes': 128 * 1024 * 1024,
                    'loaded': true,
                  },
                },
                {
                  'id': 'target-q4',
                  'mobilecore': {
                    'size_bytes': 128 * 1024 * 1024,
                    'loaded': false,
                  },
                },
              ],
            }));
            break;
          case '/metrics':
            request.response.write(jsonEncode({
              'active_model': 'current-q4',
              'backend': 'android-llama-cpp',
              'memory_peak_mb': 100,
            }));
            break;
          case '/v1/recommendations':
            request.response.write(jsonEncode({
              'device': {'available_ram_mb': 1000},
              'recommendations': [
                {
                  'model_id': 'target-q4',
                  'fit': 'good',
                  'estimated_memory_mb': 256,
                  'context_length': 4096,
                },
              ],
            }));
            break;
          case '/mobilecore/model/load':
            loadRequests += 1;
            request.response.write('{"ok":true}');
            break;
        }
        await request.response.close();
      });

      await expectLater(
        service.switchModelWithPreflight('target-q4'),
        throwsA(isA<MobileCoreProviderException>().having(
          (error) => error.code,
          'code',
          'runtime_snapshot_changed',
        )),
      );
      expect(healthRequests, 3);
      expect(loadRequests, 0);
    });

    test('switch preflight rejects insufficient projected memory without load',
        () async {
      var loadRequests = 0;
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        switch (request.uri.path) {
          case '/health':
            request.response
                .write(jsonEncode(_healthPayload(model: 'current-q4')));
            break;
          case '/v1/models':
            request.response.write(jsonEncode({
              'data': [
                {
                  'id': 'current-q4',
                  'mobilecore': {
                    'size_bytes': 128 * 1024 * 1024,
                    'loaded': true,
                  },
                },
                {
                  'id': 'large-q4',
                  'mobilecore': {
                    'size_bytes': 700 * 1024 * 1024,
                    'context_length': 8192,
                    'loaded': false,
                  },
                },
              ],
            }));
            break;
          case '/metrics':
            request.response.write(jsonEncode({
              'active_model': 'current-q4',
              'backend': 'android-llama-cpp',
              'memory_peak_mb': 100,
            }));
            break;
          case '/v1/recommendations':
            request.response.write(jsonEncode({
              'device': {'available_ram_mb': 200},
              'recommendations': [
                {
                  'model_id': 'large-q4',
                  'fit': 'too_tight',
                  'estimated_memory_mb': 700,
                  'context_length': 8192,
                  'score': 0,
                },
              ],
            }));
            break;
          case '/mobilecore/model/load':
            loadRequests += 1;
            request.response.write('{"ok":true}');
            break;
        }
        await request.response.close();
      });

      await expectLater(
        service.switchModelWithPreflight('large-q4'),
        throwsA(isA<MobileCoreProviderException>().having(
          (error) => error.code,
          'code',
          'insufficient_memory',
        )),
      );
      expect(loadRequests, 0);
    });

    test('activates only a verified Omni pair and rechecks audio capability',
        () async {
      var loaded = false;
      var loadRequests = 0;
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        switch (request.uri.path) {
          case '/health':
            request.response.write(jsonEncode({
              'status': 'ok',
              'service': 'mobilecore',
              'protocol': _mobileCoreProtocolV2,
              'version': '0.1.4-rc4',
              'backend': 'cpu',
              'runtime': loaded ? 'llama.cpp/libmtmd' : 'llama.cpp',
              'active_model': loaded ? 'Qwen2.5-Omni-3B-Q4_K_M' : null,
              'model_loaded': loaded,
              'capabilities': {
                'text_input': loaded,
                'image_input': loaded,
                'audio_input': loaded,
                'text_output': loaded,
              },
              'artifacts': loaded
                  ? {
                      'main': {
                        'installed': true,
                        'verified': true,
                        'digest_algorithm': 'sha256',
                        'digest': 'main-pin',
                      },
                      'mmproj': {
                        'installed': true,
                        'verified': true,
                        'digest_algorithm': 'sha256',
                        'digest': 'projector-pin',
                      },
                    }
                  : const {},
            }));
            break;
          case '/mobilecore/omni/status':
            request.response.write(jsonEncode({
              'model_id': 'qwen2.5-omni-3b-verified',
              'revision': 'fixed-public-revision',
              'phase': 'verified',
              'pair_verified': true,
              'artifacts': {
                'main': {
                  'installed': true,
                  'verified': true,
                  'digest_algorithm': 'sha256',
                  'digest': 'main-pin',
                },
                'mmproj': {
                  'installed': true,
                  'verified': true,
                  'digest_algorithm': 'sha256',
                  'digest': 'projector-pin',
                },
              },
              'preflight': {'passed': true},
            }));
            break;
          case '/mobilecore/omni/load':
            loadRequests += 1;
            expect(request.headers.value(HttpHeaders.authorizationHeader),
                'Bearer local');
            final body = jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
            expect(body['context_length'], 2048);
            expect(body['threads'], 4);
            expect(body['gpu_layers'], 0);
            expect(body.containsKey('path'), isFalse);
            loaded = true;
            request.response.write('{"loaded":true}');
            break;
        }
        await request.response.close();
      });

      final result = await service.loadVerifiedOmni(
        requiredCapability: MobileCoreAttachmentKind.audio,
        contextLength: 2048,
      );

      expect(loadRequests, 1);
      expect(result.status.loadable, isTrue);
      expect(result.status.preflightPassed, isTrue);
      expect(result.health.capabilities.audioInput, isTrue);
      expect(result.health.mainArtifact.verified, isTrue);
      expect(result.health.projectorArtifact.verified, isTrue);
      expect(result.status.evidenceMetadata.toString(),
          isNot(contains('/private/')));
      expect(
          result.status.evidenceMetadata.toString(), isNot(contains('.gguf')));
    });

    test('rejects an unverified Omni pair before the load route', () async {
      var loadRequests = 0;
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/health') {
          request.response.write(jsonEncode({
            ..._healthPayload(),
            'active_model': null,
            'model_loaded': false,
          }));
        } else if (request.uri.path == '/mobilecore/omni/status') {
          request.response.write(jsonEncode({
            'model_id': 'qwen2.5-omni-3b-verified',
            'phase': 'installed',
            'pair_verified': false,
            'artifacts': {
              'main': {'installed': true, 'verified': true},
              'mmproj': {'installed': true, 'verified': false},
            },
          }));
        } else if (request.uri.path == '/mobilecore/omni/load') {
          loadRequests += 1;
          request.response.write('{"loaded":true}');
        }
        await request.response.close();
      });

      await expectLater(
        service.loadVerifiedOmni(
          requiredCapability: MobileCoreAttachmentKind.image,
        ),
        throwsA(isA<MobileCoreProviderException>().having(
          (error) => error.code,
          'code',
          'omni_pair_not_verified',
        )),
      );
      expect(loadRequests, 0);
    });

    test('rejects audio when the loaded Omni runtime reports image only',
        () async {
      var loaded = false;
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/health') {
          request.response.write(jsonEncode({
            'status': 'ok',
            'service': 'mobilecore',
            'protocol': _mobileCoreProtocolV2,
            'version': '0.1.4-rc4',
            'backend': 'cpu',
            'runtime': loaded ? 'llama.cpp/libmtmd' : 'llama.cpp',
            'active_model': loaded ? 'Qwen2.5-Omni-3B-Q4_K_M' : null,
            'model_loaded': loaded,
            'capabilities': {
              'text_input': loaded,
              'image_input': loaded,
              'audio_input': false,
              'text_output': loaded,
            },
            'artifacts': loaded
                ? {
                    'main': {'installed': true, 'verified': true},
                    'mmproj': {'installed': true, 'verified': true},
                  }
                : const {},
          }));
        } else if (request.uri.path == '/mobilecore/omni/status') {
          request.response.write(jsonEncode({
            'model_id': 'qwen2.5-omni-3b-verified',
            'phase': 'verified',
            'pair_verified': true,
            'artifacts': {
              'main': {'installed': true, 'verified': true},
              'mmproj': {'installed': true, 'verified': true},
            },
          }));
        } else if (request.uri.path == '/mobilecore/omni/load') {
          await utf8.decoder.bind(request).join();
          loaded = true;
          request.response.write('{"loaded":true}');
        }
        await request.response.close();
      });

      await expectLater(
        service.loadVerifiedOmni(
          requiredCapability: MobileCoreAttachmentKind.audio,
        ),
        throwsA(isA<MobileCoreProviderException>().having(
          (error) => error.code,
          'code',
          'unsupported_modality',
        )),
      );
    });

    test('rejects a loaded Omni runtime whose artifact digest changed',
        () async {
      var loaded = false;
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/health') {
          request.response.write(jsonEncode({
            'status': 'ok',
            'service': 'mobilecore',
            'protocol': _mobileCoreProtocolV2,
            'version': '0.1.4-rc4',
            'backend': 'cpu',
            'runtime': loaded ? 'llama.cpp/libmtmd' : 'llama.cpp',
            'active_model': loaded ? 'Qwen2.5-Omni-3B-Q4_K_M' : null,
            'model_loaded': loaded,
            'capabilities': {
              'text_input': loaded,
              'image_input': loaded,
              'audio_input': loaded,
              'text_output': loaded,
            },
            'artifacts': loaded
                ? {
                    'main': {
                      'installed': true,
                      'verified': true,
                      'digest_algorithm': 'sha256',
                      'digest': 'different-main',
                    },
                    'mmproj': {
                      'installed': true,
                      'verified': true,
                      'digest_algorithm': 'sha256',
                      'digest': 'projector-pin',
                    },
                  }
                : const {},
          }));
        } else if (request.uri.path == '/mobilecore/omni/status') {
          request.response.write(jsonEncode({
            'model_id': 'qwen2.5-omni-3b-verified',
            'phase': 'verified',
            'pair_verified': true,
            'artifacts': {
              'main': {
                'installed': true,
                'verified': true,
                'digest_algorithm': 'sha256',
                'digest': 'main-pin',
              },
              'mmproj': {
                'installed': true,
                'verified': true,
                'digest_algorithm': 'sha256',
                'digest': 'projector-pin',
              },
            },
          }));
        } else if (request.uri.path == '/mobilecore/omni/load') {
          await utf8.decoder.bind(request).join();
          loaded = true;
          request.response.write('{"loaded":true}');
        }
        await request.response.close();
      });

      await expectLater(
        service.loadVerifiedOmni(
          requiredCapability: MobileCoreAttachmentKind.image,
        ),
        throwsA(isA<MobileCoreProviderException>().having(
          (error) => error.code,
          'code',
          'omni_runtime_not_ready',
        )),
      );
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
      'background_restricted': false,
      'capabilities': const {
        'text_input': true,
        'text_output': true,
      },
    };
