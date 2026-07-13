import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/identity_naming_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('persists local identity naming and builds compact context block',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = IdentityNamingService(prefs: prefs);

    await service.save(
      const IdentityNamingPreferences(
        userDisplayName: 'Harzva',
        mobileCodeNickname: 'MobileCode Lab',
        assistantPersonaLabel: 'Codex Local',
      ),
    );

    final loaded = await service.load();
    final block = await service.compactContextBlock();

    expect(loaded.userDisplayName, 'Harzva');
    expect(loaded.mobileCodeNickname, 'MobileCode Lab');
    expect(loaded.assistantPersonaLabel, 'Codex Local');
    expect(block, contains('mobileCodeNickname: MobileCode Lab'));
    expect(block, contains('assistantPersonaLabel: Codex Local'));
    expect(block, contains('privacy: localOnly'));
  });

  test('normalizes empty and multiline identity values', () {
    final preferences = const IdentityNamingPreferences().copyWith(
      userDisplayName: '  A\nB\tC  ',
      mobileCodeNickname: '',
      assistantPersonaLabel: '',
    );

    expect(preferences.userDisplayName, 'A B C');
    expect(preferences.mobileCodeNickname, 'MobileCode');
    expect(preferences.assistantPersonaLabel, 'Codex');
  });
}
