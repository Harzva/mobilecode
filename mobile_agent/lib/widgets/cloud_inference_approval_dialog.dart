import 'package:flutter/material.dart';

class CloudInferenceApprovalDialog extends StatelessWidget {
  const CloudInferenceApprovalDialog({
    super.key,
    required this.providerLabel,
    required this.localAvailable,
    required this.onDecision,
  });

  final String providerLabel;
  final bool localAvailable;
  final ValueChanged<bool> onDecision;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Cloud inference approval'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This task was classified as long or complex. Sending it to the selected cloud provider may improve reasoning, but task context leaves this device.',
            ),
            const SizedBox(height: 12),
            Text('Provider: $providerLabel'),
            Text(
              localAvailable
                  ? 'Declining keeps this task on MobileCore.'
                  : 'MobileCore is unavailable; declining cancels this request.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Approval applies only to this chat or Agent task. It never approves Phone Use, login, payment, or ordering actions.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => onDecision(false),
            child: Text(localAvailable ? 'Use MobileCore' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => onDecision(true),
            child: const Text('Send to cloud once'),
          ),
        ],
      );
}
