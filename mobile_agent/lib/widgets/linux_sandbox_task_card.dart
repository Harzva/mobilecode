import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../themes/app_theme.dart';
import 'glass_card_widget.dart';

class LinuxSandboxTaskPreview {
  const LinuxSandboxTaskPreview({
    required this.taskKind,
    required this.cwd,
    required this.args,
    required this.timeout,
    required this.capability,
    required this.impact,
  });

  final String taskKind;
  final String cwd;
  final List<String> args;
  final Duration timeout;
  final String capability;
  final String impact;

  String get commandText {
    final suffix = args.isEmpty ? '' : ' ${args.join(' ')}';
    return '$taskKind$suffix';
  }
}

class LinuxSandboxTaskCard extends StatelessWidget {
  const LinuxSandboxTaskCard({
    super.key,
    required this.preview,
    required this.installed,
    required this.onRun,
    this.onInstall,
  });

  final LinuxSandboxTaskPreview preview;
  final bool installed;
  final VoidCallback onRun;
  final VoidCallback? onInstall;

  @override
  Widget build(BuildContext context) {
    return GlassCardWidget(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.play_circle_outline,
                  color: AppTheme.cyan,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    preview.taskKind,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _StatusPill(
                  label: installed ? 'ready' : 'needs rootfs',
                  color: installed ? AppTheme.success : AppTheme.warning,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _PreviewRow(label: 'cwd', value: preview.cwd),
            _PreviewRow(label: 'args', value: preview.args.join(' ')),
            _PreviewRow(
                label: 'timeout', value: '${preview.timeout.inSeconds}s'),
            _PreviewRow(label: 'capability', value: preview.capability),
            _PreviewRow(label: 'impact', value: preview.impact),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('linuxSandbox.runTask'),
                    onPressed: installed ? onRun : onInstall,
                    icon: Icon(installed ? Icons.play_arrow : Icons.download),
                    label: Text(
                      installed ? 'Run in Linux Sandbox' : 'Install rootfs',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const ValueKey('linuxSandbox.copyCommand'),
                  tooltip: '复制命令',
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: preview.commandText),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制 typed task')),
                    );
                  },
                  icon: const Icon(Icons.copy, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.textTertiary),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
