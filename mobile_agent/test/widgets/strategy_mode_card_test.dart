import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/widgets/strategy_mode_card.dart';

void main() {
  group('StrategyModeCard', () {
    testWidgets('defaults to safe Auto and shows a non-counted trace summary',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: StrategyModeCard()),
          ),
        ),
      );

      expect(find.text('Mobile Harness Strategy'), findsOneWidget);
      expect(find.text('Auto'), findsWidgets);
      expect(find.textContaining('Safe Auto'), findsWidgets);

      await tester.tap(find.text('Run dry trace'));
      await tester.pumpAndSettle();

      expect(find.textContaining('plan_execute_verify_single_agent'),
          findsOneWidget);
      expect(find.textContaining('Run status: strategy_pilot_not_counted'),
          findsOneWidget);
      expect(find.textContaining('counts_as_experiment=false'), findsOneWidget);
      expect(find.textContaining('Trace events:'), findsOneWidget);
      expect(find.textContaining('Evidence records:'), findsOneWidget);
      expect(find.textContaining('Memory packet:'), findsOneWidget);
    });

    testWidgets('experimental swarm is visible but blocked by default',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: StrategyModeCard()),
          ),
        ),
      );

      await tester.tap(find.text('Experimental Swarm'));
      await tester.tap(find.text('Run dry trace'));
      await tester.pumpAndSettle();

      expect(find.textContaining('swarm_router_multi_agent'), findsOneWidget);
      expect(
          find.textContaining('Blocked reason: experimental_strategy_disabled'),
          findsOneWidget);
      expect(find.textContaining('Experimental gate is off'), findsOneWidget);
    });
  });
}
