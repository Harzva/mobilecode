import 'package:flutter/material.dart';

class AgentTraceRecoveryBox extends StatelessWidget {
  const AgentTraceRecoveryBox({
    super.key,
    required this.actions,
    required this.color,
    required this.onOpenCapabilityCenter,
  });

  final List<String> actions;
  final Color color;
  final VoidCallback onOpenCapabilityCenter;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();

    final primary = actions.first;
    final shouldOpenCapabilityCenter =
        actions.any(agentTraceRecoveryLooksLikeCapabilityCenter);
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final mutedColor = theme.colorScheme.onSurfaceVariant;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.support_agent_outlined, color: color, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Recovery',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            primary,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: mutedColor, fontSize: 11.5, height: 1.32),
          ),
          if (shouldOpenCapabilityCenter) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onOpenCapabilityCenter,
                icon: const Icon(Icons.apps_outlined, size: 15),
                label: const Text('打开能力中心'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

bool agentTraceRecoveryLooksLikeCapabilityCenter(String action) {
  final lower = action.toLowerCase();
  return lower.contains('capability center') ||
      lower.contains('extension center') ||
      lower.contains('cli hub') ||
      lower.contains('alpine') ||
      lower.contains('install') ||
      lower.contains('profile') ||
      action.contains('能力中心') ||
      action.contains('扩展中心');
}
