import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/mobile_code_helper_provider.dart';
import 'package:mobile_agent/services/model_provider_adapter_service.dart';

void main() {
  group('ModelRouter and CopilotBridgeModelProviderAdapter', () {
    late HttpServer server;
    late Uri baseUri;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUri = Uri.parse('http://127.0.0.1:${server.port}');
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test(
        'forwards GitHub credential to copilot bridge task and redacts metadata',
        () async {
      unawaited(server.first.then((request) async {
        expect(request.uri.path, '/v1/task/start');
        final body = await utf8.decoder.bind(request).join();
        final payload = jsonDecode(body) as Map<String, dynamic>;
        expect(payload['taskKind'], 'copilot_chat');
        expect(payload['path'], '.');
        expect(payload['timeoutMs'], 120000);

        final args = payload['args'] as Map<String, dynamic>;
        expect(args['modelId'], 'copilot-chat');
        expect(args['githubToken'], 'gho_test_token');
        final messages = jsonDecode(args['messagesJson'] as String) as List;
        expect(messages.single, {
          'role': 'user',
          'content': 'hello',
        });

        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'success': true,
            'taskId': 'typed-123',
            'taskKind': 'copilot_chat',
            'status': 'succeeded',
            'stdout': jsonEncode({'text': 'hello from copilot'}),
            'stderr': '',
            'exitCode': 0,
            'durationMs': 10,
            'failureKind': 'none',
          }));
        await request.response.close();
      }));

      final router = ModelRouter(
        credentialResolver: const _FakeCredentialResolver(
          ProviderCredential(
            providerId: 'copilotGithub',
            accountLabel: '@octocat',
            location: 'github_deep_service_secure_storage',
            secret: 'gho_test_token',
          ),
        ),
        adapters: [
          CopilotBridgeModelProviderAdapter(
            helper: MobileCodeHelperProvider(baseUri: baseUri),
          ),
        ],
      );

      final chunks = await router
          .chat(
            const ModelForwardRequest(
              providerId: 'copilotGithub',
              modelId: 'copilot-chat',
              messages: [ModelMessage(role: 'user', content: 'hello')],
            ),
          )
          .toList();

      expect(chunks, hasLength(1));
      expect(chunks.single.text, 'hello from copilot');
      expect(chunks.single.providerId, 'copilotGithub');
      expect(chunks.single.modelId, 'copilot-chat');
      expect(chunks.single.metadata['credential'].toString(),
          isNot(contains('gho_test_token')));
      expect(chunks.single.metadata['credential'].toString(),
          contains('redacted'));
    });

    test('throws provider failure when copilot bridge is not configured',
        () async {
      unawaited(server.first.then((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'success': false,
            'taskId': 'typed-bridge-missing',
            'taskKind': 'copilot_chat',
            'status': 'failed',
            'stdout': '',
            'stderr': 'MOBILECODE_COPILOT_BRIDGE_CMD is not configured.',
            'exitCode': 127,
            'durationMs': 1,
            'failureKind': 'dependencyMissing',
          }));
        await request.response.close();
      }));
      final router = ModelRouter(
        credentialResolver: const _FakeCredentialResolver(
          ProviderCredential(
            providerId: 'copilotGithub',
            accountLabel: '@octocat',
            location: 'github_deep_service_secure_storage',
            secret: 'gho_test_token',
          ),
        ),
        adapters: [
          CopilotBridgeModelProviderAdapter(
            helper: MobileCodeHelperProvider(baseUri: baseUri),
          ),
        ],
      );

      expect(
        () => router
            .chat(
              const ModelForwardRequest(
                providerId: 'copilotGithub',
                modelId: 'copilot-chat',
                messages: [ModelMessage(role: 'user', content: 'hello')],
              ),
            )
            .drain<void>(),
        throwsA(
          isA<ModelRouterException>()
              .having((error) => error.failureKind, 'failureKind',
                  'dependencyMissing')
              .having((error) => error.message, 'message',
                  contains('MOBILECODE_COPILOT_BRIDGE_CMD')),
        ),
      );
    });

    test('fails before provider adapter when credential is missing', () async {
      final router = ModelRouter(
        credentialResolver: const _FakeCredentialResolver(null),
        adapters: [
          CopilotBridgeModelProviderAdapter(
            helper: MobileCodeHelperProvider(baseUri: baseUri),
          ),
        ],
      );

      expect(
        () => router
            .chat(
              const ModelForwardRequest(
                providerId: 'copilotGithub',
                modelId: 'copilot-chat',
                messages: [ModelMessage(role: 'user', content: 'hello')],
              ),
            )
            .drain<void>(),
        throwsA(
          isA<ModelRouterException>().having(
            (error) => error.failureKind,
            'failureKind',
            'credential_missing',
          ),
        ),
      );
    });
  });
}

class _FakeCredentialResolver implements ProviderCredentialResolver {
  const _FakeCredentialResolver(this.credential);

  final ProviderCredential? credential;

  @override
  Future<ProviderCredential?> resolve(String providerId) async {
    if (credential?.providerId != providerId) return null;
    return credential;
  }
}
