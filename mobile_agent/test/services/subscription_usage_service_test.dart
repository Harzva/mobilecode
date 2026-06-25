import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/subscription_usage_service.dart';

void main() {
  group('SubscriptionUsageService', () {
    test('starts with four provider groups and mock quota cards', () {
      final service = SubscriptionUsageService(
        credentialVault: _MemoryCredentialVault(),
        clock: () => DateTime(2026, 6, 25, 10),
      );

      expect(service.states.map((state) => state.provider.name), [
        'Claude',
        'Copilot / GitHub',
        'Antigravity / Google',
        'Codex / ChatGPT',
      ]);
      expect(service.states.every((state) => state.quotas.isNotEmpty), isTrue);
      expect(
        service.states
            .expand((state) => state.quotas)
            .every((quota) => quota.mock),
        isTrue,
      );
    });

    test('stores credentials only through the vault and returns redacted state',
        () async {
      final vault = _MemoryCredentialVault();
      final service = SubscriptionUsageService(
        credentialVault: vault,
        loginAdapters: const {},
        clock: () => DateTime(2026, 6, 25, 10),
      );

      await service.connectManualCredential(
        providerId: 'claude',
        accountLabel: 'Work Claude',
        credential: 'credential-value',
      );

      expect(vault.values, {'claude|claude.default': 'credential-value'});
      final claude = service.stateFor('claude');
      expect(claude.connected, isTrue);
      expect(claude.account!.toRedactedJson()['credential'],
          'stored_in_secure_storage');
      expect(service.redactedSnapshot().toString(),
          isNot(contains('credential-value')));
    });

    test('official login planning creates provider-specific recovery state',
        () async {
      final service = SubscriptionUsageService(
        credentialVault: _MemoryCredentialVault(),
        clock: () => DateTime(2026, 6, 25, 10),
      );

      await service.planOfficialLogin('copilotGithub');

      final state = service.stateFor('copilotGithub');
      expect(state.account!.connected, isFalse);
      expect(state.account!.failureKind, 'official_flow_not_connected_locally');
      expect(state.account!.recoveryHint, contains('GitHub'));
      expect(state.hasError, isTrue);
    });

    test('validates GitHub token before storing Copilot credential', () async {
      final vault = _MemoryCredentialVault();
      final service = SubscriptionUsageService(
        credentialVault: vault,
        loginAdapters: {
          'copilotGithub': _FakeLoginAdapter(
            const SubscriptionLoginValidation(
              success: true,
              accountLabel: '@octocat',
            ),
          ),
        },
        clock: () => DateTime(2026, 6, 25, 10),
      );

      await service.connectManualCredential(
        providerId: 'copilotGithub',
        accountLabel: 'GitHub account',
        credential: 'test_valid_pat',
        method: ProviderLoginMethod.manualAccessToken,
      );

      expect(vault.values, {
        'copilotGithub|copilotGithub.default': 'test_valid_pat',
      });
      final state = service.stateFor('copilotGithub');
      expect(state.connected, isTrue);
      expect(state.account!.displayName, '@octocat');
      expect(state.account!.loginMethod, ProviderLoginMethod.manualAccessToken);
      expect(service.redactedSnapshot().toString(),
          isNot(contains('test_valid_pat')));
    });

    test('does not store GitHub token when validation fails', () async {
      final vault = _MemoryCredentialVault();
      final service = SubscriptionUsageService(
        credentialVault: vault,
        loginAdapters: {
          'copilotGithub': _FakeLoginAdapter(
            const SubscriptionLoginValidation(
              success: false,
              failureKind: 'github_token_validation_failed',
              recoveryHint: 'GitHub rejected this token.',
            ),
          ),
        },
        clock: () => DateTime(2026, 6, 25, 10),
      );

      await service.connectManualCredential(
        providerId: 'copilotGithub',
        accountLabel: 'GitHub account',
        credential: 'test_bad_pat',
        method: ProviderLoginMethod.manualAccessToken,
      );

      expect(vault.values, isEmpty);
      final state = service.stateFor('copilotGithub');
      expect(state.connected, isFalse);
      expect(state.account!.failureKind, 'github_token_validation_failed');
      expect(state.hasError, isTrue);
      expect(service.redactedSnapshot().toString(),
          isNot(contains('test_bad_pat')));
    });

    test('GitHub adapter validates token against user endpoint', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(server.first.then((request) async {
        expect(request.uri.path, '/user');
        expect(request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer test_adapter_valid_pat');
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'login': 'octocat'}));
        await request.response.close();
      }));
      final adapter = GitHubSubscriptionLoginAdapter(
        userEndpoint: Uri.parse('http://127.0.0.1:${server.port}/user'),
      );

      final result = await adapter.validateCredential(
        provider: serviceProvider('copilotGithub'),
        credential: 'test_adapter_valid_pat',
        method: ProviderLoginMethod.manualAccessToken,
      );

      expect(result.success, isTrue);
      expect(result.accountLabel, '@octocat');
    });

    test('GitHub adapter rejects failed token validation', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(server.first.then((request) async {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
      }));
      final adapter = GitHubSubscriptionLoginAdapter(
        userEndpoint: Uri.parse('http://127.0.0.1:${server.port}/user'),
      );

      final result = await adapter.validateCredential(
        provider: serviceProvider('copilotGithub'),
        credential: 'test_adapter_invalid_pat',
        method: ProviderLoginMethod.manualAccessToken,
      );

      expect(result.success, isFalse);
      expect(result.failureKind, 'github_token_validation_failed');
    });

    test('OpenAI adapter validates key against models endpoint', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(server.first.then((request) async {
        expect(request.uri.path, '/v1/models');
        expect(request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer test_openai_key');
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'data': []}));
        await request.response.close();
      }));
      final adapter = OpenAiSubscriptionLoginAdapter(
        modelsEndpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/models'),
      );

      final result = await adapter.validateCredential(
        provider: serviceProvider('codexChatGpt'),
        credential: 'test_openai_key',
        method: ProviderLoginMethod.manualApiKey,
      );

      expect(result.success, isTrue);
      expect(result.accountLabel, 'OpenAI API key');
    });

    test('Anthropic adapter sends required headers to models endpoint',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(server.first.then((request) async {
        expect(request.uri.path, '/v1/models');
        expect(request.headers.value('x-api-key'), 'test_anthropic_key');
        expect(request.headers.value('anthropic-version'), '2023-06-01');
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'data': []}));
        await request.response.close();
      }));
      final adapter = AnthropicSubscriptionLoginAdapter(
        modelsEndpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/models'),
      );

      final result = await adapter.validateCredential(
        provider: serviceProvider('claude'),
        credential: 'test_anthropic_key',
        method: ProviderLoginMethod.manualApiKey,
      );

      expect(result.success, isTrue);
      expect(result.accountLabel, 'Claude API key');
    });

    test('Gemini adapter validates key using models list query parameter',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(server.first.then((request) async {
        expect(request.uri.path, '/v1beta/models');
        expect(request.uri.queryParameters['key'], 'test_gemini_key');
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'models': []}));
        await request.response.close();
      }));
      final adapter = GeminiSubscriptionLoginAdapter(
        modelsEndpoint:
            Uri.parse('http://127.0.0.1:${server.port}/v1beta/models'),
      );

      final result = await adapter.validateCredential(
        provider: serviceProvider('antigravityGoogle'),
        credential: 'test_gemini_key',
        method: ProviderLoginMethod.manualApiKey,
      );

      expect(result.success, isTrue);
      expect(result.accountLabel, 'Gemini API key');
    });

    test('logout clears secure credential and keeps quota cards redacted',
        () async {
      final vault = _MemoryCredentialVault();
      final service = SubscriptionUsageService(
        credentialVault: vault,
        loginAdapters: const {},
        clock: () => DateTime(2026, 6, 25, 10),
      );

      await service.connectManualCredential(
        providerId: 'codexChatGpt',
        accountLabel: 'ChatGPT',
        credential: 'credential-value',
      );
      await service.logout('codexChatGpt');

      expect(vault.values, isEmpty);
      expect(service.stateFor('codexChatGpt').connected, isFalse);
    });
  });
}

SubscriptionProvider serviceProvider(String providerId) {
  final service = SubscriptionUsageService(
    credentialVault: _MemoryCredentialVault(),
    loginAdapters: const {},
    clock: () => DateTime(2026, 6, 25, 10),
  );
  return service.stateFor(providerId).provider;
}

class _FakeLoginAdapter implements SubscriptionLoginAdapter {
  const _FakeLoginAdapter(this.result);

  final SubscriptionLoginValidation result;

  @override
  Future<SubscriptionLoginValidation> validateCredential({
    required SubscriptionProvider provider,
    required String credential,
    required ProviderLoginMethod method,
  }) async {
    return result;
  }
}

class _MemoryCredentialVault implements SubscriptionCredentialVault {
  final values = <String, String>{};

  String _key(String providerId, String accountId) => '$providerId|$accountId';

  @override
  Future<void> writeCredential({
    required String providerId,
    required String accountId,
    required String credential,
  }) async {
    values[_key(providerId, accountId)] = credential;
  }

  @override
  Future<String?> readCredential({
    required String providerId,
    required String accountId,
  }) async {
    return values[_key(providerId, accountId)];
  }

  @override
  Future<void> deleteCredential({
    required String providerId,
    required String accountId,
  }) async {
    values.remove(_key(providerId, accountId));
  }
}
