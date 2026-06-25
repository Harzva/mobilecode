import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/screens/subscription_usage_hub_screen.dart';
import 'package:mobile_agent/services/subscription_usage_service.dart';

void main() {
  testWidgets('shows provider tabs, quota cards, and privacy boundary',
      (tester) async {
    final service = SubscriptionUsageService(
      credentialVault: _MemoryCredentialVault(),
      clock: () => DateTime(2026, 6, 25, 10),
    );

    await tester.pumpWidget(
      MaterialApp(home: SubscriptionUsageHubScreen(service: service)),
    );

    expect(find.text('Usage Hub'), findsOneWidget);
    expect(find.text('Claude'), findsWidgets);
    expect(find.text('Copilot / GitHub'), findsOneWidget);
    expect(find.text('Antigravity / Google'), findsOneWidget);
    expect(find.text('Codex / ChatGPT'), findsOneWidget);
    expect(find.text('当前会话'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.textContaining('secure storage'), findsOneWidget);
  });

  testWidgets('official login button exposes recovery state', (tester) async {
    final service = SubscriptionUsageService(
      credentialVault: _MemoryCredentialVault(),
      clock: () => DateTime(2026, 6, 25, 10),
    );

    await tester.pumpWidget(
      MaterialApp(home: SubscriptionUsageHubScreen(service: service)),
    );

    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用 Claude 登录'));
    await tester.pumpAndSettle();

    expect(service.stateFor('claude').hasError, isTrue);
    expect(find.text('错误'), findsWidgets);
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
