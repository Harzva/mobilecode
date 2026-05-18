import 'dart:async';

import 'package:flutter/material.dart';

import '../services/token_usage_service.dart';

const _usageBg = Color(0xFFF7FAFF);
const _usagePanel = Color(0xFFFFFFFF);
const _usageLine = Color(0xFFDDE7F7);
const _usageText = Color(0xFF0B1020);
const _usageMuted = Color(0xFF536079);
const _usageFaint = Color(0xFF8B97AD);
const _usageMint = Color(0xFF0B9B7E);
const _usageCyan = Color(0xFF16B9C7);
const _usageAmber = Color(0xFFB7791F);
const _usageRose = Color(0xFFE0526E);
const _usageViolet = Color(0xFF7557E8);

class ApiUsageScreen extends StatefulWidget {
  const ApiUsageScreen({super.key});

  @override
  State<ApiUsageScreen> createState() => _ApiUsageScreenState();
}

class _ApiUsageScreenState extends State<ApiUsageScreen> {
  final _usageService = TokenUsageService.instance;
  StreamSubscription<TokenUsageSummary>? _summarySub;
  TokenUsageSummary _summary = TokenUsageSummary.empty;

  @override
  void initState() {
    super.initState();
    _summarySub = _usageService.watchSummary().listen((summary) {
      if (mounted) setState(() => _summary = summary);
    });
  }

  @override
  void dispose() {
    _summarySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final events = _usageService.recentEvents.take(40).toList(growable: false);
    final breakdown = _breakdownByProviderModel(_usageService.recentEvents);
    return Scaffold(
      backgroundColor: _usageBg,
      appBar: AppBar(
        title: const Text('Token Usage'),
        backgroundColor: _usageBg,
        foregroundColor: _usageText,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _UsageHero(summary: _summary),
          const SizedBox(height: 12),
          _UsageStatGrid(summary: _summary),
          const SizedBox(height: 12),
          _UsagePanel(
            title: 'Provider / model breakdown',
            icon: Icons.account_tree_outlined,
            color: _usageViolet,
            child: breakdown.isEmpty
                ? const _EmptyUsageText(text: 'No provider usage has been recorded yet.')
                : Column(
                    children: [
                      for (final entry in breakdown.entries)
                        _BreakdownRow(
                          label: entry.key,
                          value: entry.value,
                          total: _summary.totalTokens,
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          _UsagePanel(
            title: 'Recent runs',
            icon: Icons.timeline_outlined,
            color: _usageCyan,
            child: events.isEmpty
                ? const _EmptyUsageText(text: 'Run chat or RR mode once; usage metadata will appear here.')
                : Column(
                    children: [
                      for (final event in events) _UsageEventTile(event: event),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

Map<String, int> _breakdownByProviderModel(List<TokenUsageEvent> events) {
  final breakdown = <String, int>{};
  for (final event in events) {
    final key = '${event.provider} / ${event.model}';
    breakdown[key] = (breakdown[key] ?? 0) + event.usage.totalTokens;
  }
  final entries = breakdown.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return Map<String, int>.fromEntries(entries.take(12));
}

class _UsageHero extends StatelessWidget {
  const _UsageHero({required this.summary});

  final TokenUsageSummary summary;

  @override
  Widget build(BuildContext context) {
    return _UsagePanel(
      title: 'AI cost observability',
      icon: Icons.token_outlined,
      color: _usageMint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatInt(summary.totalTokens),
            style: const TextStyle(color: _usageText, fontSize: 36, fontWeight: FontWeight.w900, height: 1),
          ),
          const SizedBox(height: 6),
          Text(
            'total tokens across ${summary.requestCount} recorded runs',
            style: const TextStyle(color: _usageMuted, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _UsageBadge(
                label: summary.cacheReadTokens + summary.cacheWriteTokens + summary.cacheMissTokens == 0
                    ? 'cache unknown'
                    : 'cache hit ${(summary.cacheHitRate * 100).toStringAsFixed(1)}%',
                color: _usageMint,
              ),
              _UsageBadge(label: '${summary.estimatedCount} estimated', color: _usageAmber),
              _UsageBadge(label: '\$${summary.costEstimate.toStringAsFixed(4)} est.', color: _usageViolet),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'MobileCode stores usage metadata only. Prompt and response text are not saved in this statistics store.',
            style: TextStyle(color: _usageFaint, fontSize: 11, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _UsageStatGrid extends StatelessWidget {
  const _UsageStatGrid({required this.summary});

  final TokenUsageSummary summary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 560 ? 4 : 2;
        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: columns == 4 ? 1.95 : 1.45,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _UsageStatTile(label: 'Input', value: _formatInt(summary.inputTokens), icon: Icons.input_outlined, color: _usageCyan),
            _UsageStatTile(label: 'Output', value: _formatInt(summary.outputTokens), icon: Icons.output_outlined, color: _usageViolet),
            _UsageStatTile(label: 'Cache read', value: _formatInt(summary.cacheReadTokens), icon: Icons.cached_outlined, color: _usageMint),
            _UsageStatTile(label: 'Success', value: '${summary.successCount}/${summary.requestCount}', icon: Icons.verified_outlined, color: _usageAmber),
          ],
        );
      },
    );
  }
}

class _UsageStatTile extends StatelessWidget {
  const _UsageStatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _usagePanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _usageLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 20),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _usageText, fontSize: 20, fontWeight: FontWeight.w900)),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _usageMuted, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _UsagePanel extends StatelessWidget {
  const _UsagePanel({
    required this.title,
    required this.icon,
    required this.color,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _usagePanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _usageLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(color: _usageText, fontSize: 14, fontWeight: FontWeight.w900))),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.label,
    required this.value,
    required this.total,
  });

  final String label;
  final int value;
  final int total;

  @override
  Widget build(BuildContext context) {
    final progress = total <= 0 ? 0.0 : value / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(color: _usageText, fontSize: 12, fontWeight: FontWeight.w900))),
              Text(_formatInt(value), style: const TextStyle(color: _usageMuted, fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.clamp(0, 1),
              minHeight: 8,
              backgroundColor: _usageViolet.withOpacity(0.12),
              valueColor: const AlwaysStoppedAnimation<Color>(_usageViolet),
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageEventTile extends StatelessWidget {
  const _UsageEventTile({required this.event});

  final TokenUsageEvent event;

  @override
  Widget build(BuildContext context) {
    final color = event.cancelled
        ? _usageAmber
        : event.success
            ? _usageMint
            : _usageRose;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(event.cancelled ? Icons.pause_circle_outline : event.success ? Icons.check_circle_outline : Icons.error_outline, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  event.endpoint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _usageText, fontSize: 13, fontWeight: FontWeight.w900),
                ),
              ),
              if (event.usage.estimated) const _UsageBadge(label: 'estimated', color: _usageAmber),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${event.provider} · ${event.model} · ${event.durationMs}ms · ${_timeLabel(event.createdAt)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _usageMuted, fontSize: 11, height: 1.35),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _UsageBadge(label: 'total ${_formatInt(event.usage.totalTokens)}', color: _usageViolet),
              _UsageBadge(label: 'in ${_formatInt(event.usage.inputTokens)}', color: _usageCyan),
              _UsageBadge(label: 'out ${_formatInt(event.usage.outputTokens)}', color: _usageMint),
              if (event.usage.cacheReadTokens > 0) _UsageBadge(label: 'cache read ${_formatInt(event.usage.cacheReadTokens)}', color: _usageMint),
              if (event.usage.cacheWriteTokens > 0) _UsageBadge(label: 'cache write ${_formatInt(event.usage.cacheWriteTokens)}', color: _usageAmber),
            ],
          ),
        ],
      ),
    );
  }
}

class _UsageBadge extends StatelessWidget {
  const _UsageBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900)),
    );
  }
}

class _EmptyUsageText extends StatelessWidget {
  const _EmptyUsageText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(color: _usageMuted, fontSize: 12, height: 1.35));
  }
}

String _formatInt(int value) {
  final raw = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final reverseIndex = raw.length - i;
    buffer.write(raw[i]);
    if (reverseIndex > 1 && reverseIndex % 3 == 1) buffer.write(',');
  }
  return buffer.toString();
}

String _timeLabel(DateTime value) {
  final h = value.hour.toString().padLeft(2, '0');
  final m = value.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
