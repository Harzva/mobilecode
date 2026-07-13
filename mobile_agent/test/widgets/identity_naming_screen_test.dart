import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/screens/identity_naming_screen.dart';
import 'package:mobile_agent/services/identity_naming_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('identity screen edits and saves local naming preferences',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = IdentityNamingService(prefs: prefs);

    await tester.pumpWidget(
      MaterialApp(
        home: IdentityNamingScreen(service: service),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Identity'), findsOneWidget);
    expect(find.text('用户称呼'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'Harzva');
    await tester.enterText(find.byType(TextField).at(1), 'MobileCode Lab');
    await tester.enterText(find.byType(TextField).at(2), 'Codex Local');
    await tester.tap(find.byKey(const ValueKey('identity.save')));
    await tester.pumpAndSettle();

    final loaded = await service.load();
    expect(loaded.userDisplayName, 'Harzva');
    expect(loaded.mobileCodeNickname, 'MobileCode Lab');
    expect(loaded.assistantPersonaLabel, 'Codex Local');
  });
}
