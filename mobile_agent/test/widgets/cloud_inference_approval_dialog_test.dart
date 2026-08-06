import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/widgets/cloud_inference_approval_dialog.dart';

void main() {
  testWidgets('approves cloud for one task without rendering request content',
      (tester) async {
    bool? decision;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CloudInferenceApprovalDialog(
          providerLabel: 'selected-cloud',
          localAvailable: true,
          onDecision: (value) => decision = value,
        ),
      ),
    ));

    expect(find.text('Provider: selected-cloud'), findsOneWidget);
    expect(
        find.textContaining('only to this chat or Agent task'), findsOneWidget);
    expect(find.textContaining('secret_id'), findsNothing);
    await tester.tap(find.text('Send to cloud once'));

    expect(decision, isTrue);
  });

  testWidgets('decline stays local when MobileCore is ready', (tester) async {
    bool? decision;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CloudInferenceApprovalDialog(
          providerLabel: 'selected-cloud',
          localAvailable: true,
          onDecision: (value) => decision = value,
        ),
      ),
    ));

    await tester.tap(find.text('Use MobileCore'));

    expect(decision, isFalse);
  });
}
