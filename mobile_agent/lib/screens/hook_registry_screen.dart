// lib/screens/hook_registry_screen.dart
// Read-only Hook Registry screen. This intentionally does not execute scripts.

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/hook_registry_model.dart';

class HookRegistryScreen extends StatelessWidget {
  const HookRegistryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const snapshot = HookRegistrySnapshot.v1;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background.withOpacity(0.8),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: AppTheme.textSecondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Hook Registry',
          style: TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _SummaryCard(snapshot: snapshot),
          const SizedBox(height: 12),
          for (final entry in snapshot.entries) ...[
            _HookEntryCard(entry: entry),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.snapshot});

  final HookRegistrySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.link_outlined, color: AppTheme.primary, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Read-only extension hooks',
                  style: TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'V1 only exposes lifecycle points and status. User scripts, remote code execution, and background hook automation stay deferred.',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 13,
              height: 1.35,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(label: '${snapshot.enabledCount} enabled', color: AppTheme.success),
              _Pill(label: '${snapshot.deferredCount} deferred', color: AppTheme.warning),
              const _Pill(label: 'No script runtime', color: AppTheme.primary),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _showHookDraftDialog(context),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新增 Hook 草案'),
              ),
              OutlinedButton.icon(
                onPressed: () => _showHookPolishDialog(context),
                icon: const Icon(Icons.auto_awesome_outlined, size: 16),
                label: const Text('AI 润色规范'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

void _showHookDraftDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text('Hook 草案'),
      content: const Text(
        'V1 允许登记 hook 点和启用状态，但不执行任意脚本。下一步会把这里升级成“草案 -> 审核 -> 只读注册”的安全流程。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}

void _showHookPolishDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text('AI 润色 Hook 规范'),
      content: const Text(
        'Hook 的 AI 润色会把用户意图标准化为 phase、trigger、scope、guardrails、confirmation policy。V1 只保存规范草案，不启动脚本。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}

class _HookEntryCard extends StatelessWidget {
  const _HookEntryCard({required this.entry});

  final HookRegistryEntry entry;

  @override
  Widget build(BuildContext context) {
    final statusColor = entry.enabled ? AppTheme.success : AppTheme.textTertiary;
    final safetyColor = switch (entry.safetyLevel) {
      HookSafetyLevel.readOnly => AppTheme.primary,
      HookSafetyLevel.gated => AppTheme.warning,
      HookSafetyLevel.deferred => AppTheme.textTertiary,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: entry.enabled ? AppTheme.primary.withOpacity(0.24) : AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  entry.enabled ? Icons.check_circle_outline : Icons.pause_circle_outline,
                  color: statusColor,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      entry.id,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontCode,
                        fontSize: 11,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            entry.description,
            style: const TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 13,
              height: 1.35,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(label: entry.phase.label, color: AppTheme.accent),
              _Pill(label: entry.enabled ? 'enabled' : 'disabled', color: statusColor),
              _Pill(label: entry.safetyLevel.label, color: safetyColor),
              _Pill(label: entry.owner, color: AppTheme.textSecondary),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppTheme.fontBody,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
