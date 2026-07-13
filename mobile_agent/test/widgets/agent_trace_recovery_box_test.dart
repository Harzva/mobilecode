import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/widgets/agent_trace_recovery_box.dart';

void main() {
  testWidgets(
      'shows capability center action for Alpine or CLI profile recovery',
      (tester) async {
    var opened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentTraceRecoveryBox(
            actions: const [
              'Open Capability Center, install Alpine Runtime or the required CLI profile, then retry this typed task.',
            ],
            color: Colors.teal,
            onOpenCapabilityCenter: () => opened = true,
          ),
        ),
      ),
    );

    expect(find.text('Recovery'), findsOneWidget);
    expect(find.textContaining('install Alpine Runtime'), findsOneWidget);
    expect(find.text('打开能力中心'), findsOneWidget);

    await tester.tap(find.text('打开能力中心'));
    expect(opened, isTrue);
  });

  testWidgets('keeps generic recovery text without capability center shortcut',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentTraceRecoveryBox(
            actions: const ['Retry after the provider service is available.'],
            color: Colors.orange,
            onOpenCapabilityCenter: () {},
          ),
        ),
      ),
    );

    expect(find.text('Recovery'), findsOneWidget);
    expect(find.textContaining('provider service'), findsOneWidget);
    expect(find.text('打开能力中心'), findsNothing);
  });
}
