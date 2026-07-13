import 'package:flutter/material.dart';

class AgentTraceProgressBox extends StatelessWidget {
  const AgentTraceProgressBox({
    super.key,
    required this.metadata,
    required this.color,
    required this.running,
  });

  final Map<String, dynamic> metadata;
  final Color color;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final summary = agentTraceProgressSummary(metadata);
    if (summary == null && !running) return const SizedBox.shrink();

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
              Icon(
                running ? Icons.sync_outlined : Icons.timeline_outlined,
                color: color,
                size: 15,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  running ? 'Task running' : 'Task event',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (summary?.status != null)
                Text(
                  summary!.status!,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 7),
          if (running)
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 5,
                backgroundColor: color.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          if (summary != null) ...[
            if (running) const SizedBox(height: 7),
            Text(
              summary.label,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: mutedColor, fontSize: 11.5, height: 1.32),
            ),
          ],
        ],
      ),
    );
  }
}

class AgentTraceProgressSummary {
  const AgentTraceProgressSummary({
    required this.label,
    this.status,
  });

  final String label;
  final String? status;
}

AgentTraceProgressSummary? agentTraceProgressSummary(
  Map<String, dynamic> metadata,
) {
  final cli = _firstNonEmpty([
    metadata['cliTitle'],
    metadata['cliId'],
  ]);
  final taskKind = metadata['taskKind']?.toString().trim() ?? '';
  final status = _firstNonEmpty([
    metadata['status'],
    metadata['runtimeStatus'],
  ]);
  final runtime = metadata['runtime']?.toString().trim() ?? '';
  final taskId = metadata['taskId']?.toString().trim() ?? '';
  final commandId = metadata['commandId']?.toString().trim() ?? '';

  if (cli.isEmpty && taskKind.isEmpty && status.isEmpty && taskId.isEmpty) {
    return null;
  }

  final label = [
    if (cli.isNotEmpty) cli,
    if (taskKind.isNotEmpty) taskKind,
    if (commandId.isNotEmpty) 'command:$commandId',
    if (runtime.isNotEmpty) 'runtime:$runtime',
    if (taskId.isNotEmpty) 'task:$taskId',
  ].join(' · ');

  return AgentTraceProgressSummary(
    label: label.isEmpty ? 'CLI Hub typed task event.' : label,
    status: status.isEmpty ? null : status,
  );
}

String _firstNonEmpty(Iterable<Object?> values) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty) return text;
  }
  return '';
}
