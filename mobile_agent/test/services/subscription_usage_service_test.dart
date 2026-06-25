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

    test('logout clears secure credential and keeps quota cards redacted',
        () async {
      final vault = _MemoryCredentialVault();
      final service = SubscriptionUsageService(
        credentialVault: vault,
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
