import 'dart:async';

import 'package:flutter/material.dart';

import '../services/token_pricing_service.dart';
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
  final _pricingService = TokenPricingService.instance;
  StreamSubscription<TokenUsageSummary>? _summarySub;
  TokenUsageSummary _summary = TokenUsageSummary.empty;
  var _checkingPricingUpdate = false;

  @override
  void initState() {
    super.initState();
    _pricingService.addListener(_handlePricingChanged);
    unawaited(_pricingService.initialize());
    _summarySub = _usageService.watchSummary().listen((summary) {
      if (mounted) setState(() => _summary = summary);
    });
  }

  @override
  void dispose() {
    _pricingService.removeListener(_handlePricingChanged);
    _summarySub?.cancel();
    super.dispose();
  }

  void _handlePricingChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openPricingOverrideSheet([TokenPrice? price]) async {
    final override = await showModalBottomSheet<TokenPrice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _usagePanel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
      builder: (context) => _PricingOverrideSheet(initialPrice: price),
    );
    if (override != null) {
      await _pricingService.upsertOverride(override);
    }
  }

  Future<void> _checkLiteLlmUpdate() async {
    if (_checkingPricingUpdate) return;
    setState(() => _checkingPricingUpdate = true);
    try {
      final update = await _pricingService.checkLiteLlmUpdate();
      if (!mounted) return;
      final apply = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: _usagePanel,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
        builder: (context) => _PricingUpdateSheet(update: update),
      );
      if (apply == true) {
        await _pricingService.applySnapshotUpdate(update);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pricing snapshot updated: ${update.modelCount} models from LiteLLM.')),
        );
      }
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('LiteLLM update check failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _checkingPricingUpdate = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = _usageService.recentEvents.take(40).toList(growable: false);
    final breakdown = _breakdownByProviderModel(_usageService.recentEvents);
    final catalog = _pricingService.catalog;
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
          _PricingPanel(
            catalog: catalog,
            prices: _pricingService.snapshotPrices,
            overrides: _pricingService.overrides,
            checkingUpdate: _checkingPricingUpdate,
            onCheckUpdate: () => unawaited(_checkLiteLlmUpdate()),
            onAdd: () => unawaited(_openPricingOverrideSheet()),
            onEdit: (price) => unawaited(_openPricingOverrideSheet(price)),
            onRemove: (price) => unawaited(_pricingService.removeOverride(price.key)),
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

List<TokenPrice> _combinedPrices({
  required List<TokenPrice> prices,
  required List<TokenPrice> overrides,
}) {
  final combined = <String, TokenPrice>{};
  for (final price in prices) {
    combined[price.key] = price;
  }
  for (final price in overrides) {
    combined[price.key] = price;
  }
  final values = combined.values.toList(growable: false)
    ..sort((a, b) {
      final provider = a.provider.compareTo(b.provider);
      if (provider != 0) return provider;
      return a.model.compareTo(b.model);
    });
  return values;
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

class _PricingPanel extends StatelessWidget {
  const _PricingPanel({
    required this.catalog,
    required this.prices,
    required this.overrides,
    required this.checkingUpdate,
    required this.onCheckUpdate,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
  });

  final TokenPricingCatalog catalog;
  final List<TokenPrice> prices;
  final List<TokenPrice> overrides;
  final bool checkingUpdate;
  final VoidCallback onCheckUpdate;
  final VoidCallback onAdd;
  final ValueChanged<TokenPrice> onEdit;
  final ValueChanged<TokenPrice> onRemove;

  @override
  Widget build(BuildContext context) {
    final previewPrices = prices.take(8).toList(growable: false);
    final totalVisible = _combinedPrices(prices: prices, overrides: overrides).length;
    return _UsagePanel(
      title: 'Pricing table',
      icon: Icons.price_change_outlined,
      color: _usageAmber,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${catalog.sourceName} · ${catalog.snapshotCount} models · updated ${_dateLabel(catalog.updatedAt)}',
            style: const TextStyle(color: _usageMuted, fontSize: 11, height: 1.35),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: checkingUpdate ? null : onCheckUpdate,
                icon: checkingUpdate
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_sync_outlined, size: 16),
                label: Text(checkingUpdate ? 'Checking...' : 'Check LiteLLM update'),
              ),
              TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_outlined, size: 16),
                label: const Text('Override'),
              ),
              TextButton.icon(
                onPressed: totalVisible == 0 ? null : () => _openPriceBrowser(context),
                icon: const Icon(Icons.search_outlined, size: 16),
                label: const Text('Search all'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (overrides.isNotEmpty) ...[
            const Text('User overrides', style: TextStyle(color: _usageText, fontSize: 12, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            for (final price in overrides)
              _PriceRow(
                price: price,
                onEdit: () => onEdit(price),
                onRemove: () => onRemove(price),
              ),
            const SizedBox(height: 8),
          ],
          const Text('Current snapshot', style: TextStyle(color: _usageText, fontSize: 12, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(
            prices.length <= previewPrices.length
                ? 'Showing all ${prices.length} snapshot models.'
                : 'Showing ${previewPrices.length} of ${prices.length} snapshot models. Use Search all for the full table.',
            style: const TextStyle(color: _usageFaint, fontSize: 10.5, height: 1.3),
          ),
          const SizedBox(height: 8),
          if (previewPrices.isEmpty)
            const _EmptyUsageText(text: 'No snapshot prices loaded yet. Check LiteLLM update or add an override.')
          else
            for (final price in previewPrices)
              _PriceRow(
                price: price,
                onEdit: () => onEdit(price),
                onRemove: price.custom ? () => onRemove(price) : null,
              ),
        ],
      ),
    );
  }

  void _openPriceBrowser(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _usagePanel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.92,
        child: _PricingCatalogSearchSheet(
          catalog: catalog,
          prices: prices,
          overrides: overrides,
          onAdd: onAdd,
          onEdit: onEdit,
          onRemove: onRemove,
        ),
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.price,
    required this.onEdit,
    this.onRemove,
  });

  final TokenPrice price;
  final VoidCallback onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: price.custom ? _usageAmber.withOpacity(0.08) : _usageCyan.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: (price.custom ? _usageAmber : _usageLine).withOpacity(0.55)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${price.provider} / ${price.model}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _usageText, fontSize: 12, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  'in \$${price.inputPerMillion.toStringAsFixed(3)} / out \$${price.outputPerMillion.toStringAsFixed(3)} per 1M tokens',
                  style: const TextStyle(color: _usageMuted, fontSize: 11, height: 1.3),
                ),
                Text(
                  '${price.custom ? 'User override' : price.sourceName} · ${_dateLabel(price.updatedAt)}',
                  style: const TextStyle(color: _usageFaint, fontSize: 10.5, height: 1.3),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: price.custom ? 'Edit override' : 'Create override from this price',
            onPressed: onEdit,
            icon: const Icon(Icons.tune_outlined, size: 18),
          ),
          if (onRemove != null)
            IconButton(
              tooltip: 'Remove override',
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline, size: 18),
            ),
        ],
      ),
    );
  }
}

class _PricingCatalogSearchSheet extends StatefulWidget {
  const _PricingCatalogSearchSheet({
    required this.catalog,
    required this.prices,
    required this.overrides,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
  });

  final TokenPricingCatalog catalog;
  final List<TokenPrice> prices;
  final List<TokenPrice> overrides;
  final VoidCallback onAdd;
  final ValueChanged<TokenPrice> onEdit;
  final ValueChanged<TokenPrice> onRemove;

  @override
  State<_PricingCatalogSearchSheet> createState() => _PricingCatalogSearchSheetState();
}

class _PricingCatalogSearchSheetState extends State<_PricingCatalogSearchSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prices = _filteredPrices;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.manage_search_outlined, color: _usageAmber, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pricing table · ${_formatInt(prices.length)} / ${_formatInt(_allPrices.length)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _usageText, fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_outlined),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${widget.catalog.sourceName} · updated ${_dateLabel(widget.catalog.updatedAt)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _usageMuted, fontSize: 11, height: 1.35),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_outlined),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () => setState(_query.clear),
                        icon: const Icon(Icons.close_outlined),
                      ),
                hintText: 'Search provider, model, source...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _UsageBadge(label: '${_formatInt(widget.prices.length)} snapshot', color: _usageCyan),
                _UsageBadge(label: '${_formatInt(widget.overrides.length)} overrides', color: _usageAmber),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onAdd();
                  },
                  icon: const Icon(Icons.add_outlined, size: 16),
                  label: const Text('Add override'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: prices.isEmpty
                  ? const Center(child: _EmptyUsageText(text: 'No pricing rows match this search.'))
                  : ListView.builder(
                      itemCount: prices.length,
                      itemBuilder: (context, index) {
                        final price = prices[index];
                        return _PriceRow(
                          price: price,
                          onEdit: () {
                            Navigator.of(context).pop();
                            widget.onEdit(price);
                          },
                          onRemove: price.custom
                              ? () {
                                  Navigator.of(context).pop();
                                  widget.onRemove(price);
                                }
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<TokenPrice> get _allPrices => _combinedPrices(
        prices: widget.prices,
        overrides: widget.overrides,
      );

  List<TokenPrice> get _filteredPrices {
    final needle = _query.text.trim().toLowerCase();
    if (needle.isEmpty) return _allPrices;
    return _allPrices.where((price) {
      final haystack = '${price.provider} ${price.model} ${price.sourceName} ${price.notes}'.toLowerCase();
      return haystack.contains(needle);
    }).toList(growable: false);
  }
}

class _PricingUpdateSheet extends StatelessWidget {
  const _PricingUpdateSheet({required this.update});

  final TokenPricingSnapshotUpdate update;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                children: [
                  Icon(Icons.cloud_sync_outlined, color: _usageAmber, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('LiteLLM pricing update', style: TextStyle(color: _usageText, fontSize: 16, fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'This is a manual snapshot update. MobileCode will not update prices in the background, and user overrides still take priority.',
                style: TextStyle(color: _usageMuted, fontSize: 12, height: 1.35),
              ),
              const SizedBox(height: 12),
              _PricingUpdateMetric(label: 'Models', value: _formatInt(update.modelCount), color: _usageViolet),
              _PricingUpdateMetric(label: 'New', value: _formatInt(update.newCount), color: _usageMint),
              _PricingUpdateMetric(label: 'Price changes', value: _formatInt(update.changedCount), color: _usageAmber),
              _PricingUpdateMetric(label: 'Unchanged', value: _formatInt(update.unchangedCount), color: _usageCyan),
              const SizedBox(height: 10),
              Text(
                '${update.sourceName} · updated ${_dateLabel(update.updatedAt)}',
                style: const TextStyle(color: _usageText, fontSize: 12, fontWeight: FontWeight.w900, height: 1.35),
              ),
              const SizedBox(height: 4),
              SelectableText(
                update.sourceUrl,
                style: const TextStyle(color: _usageMuted, fontSize: 11, height: 1.35),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: update.modelCount == 0 ? null : () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.download_done_outlined),
                      label: const Text('Apply snapshot'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PricingUpdateMetric extends StatelessWidget {
  const _PricingUpdateMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: _usageMuted, fontSize: 12, fontWeight: FontWeight.w700))),
          Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _PricingOverrideSheet extends StatefulWidget {
  const _PricingOverrideSheet({this.initialPrice});

  final TokenPrice? initialPrice;

  @override
  State<_PricingOverrideSheet> createState() => _PricingOverrideSheetState();
}

class _PricingOverrideSheetState extends State<_PricingOverrideSheet> {
  late final TextEditingController _provider;
  late final TextEditingController _model;
  late final TextEditingController _inputPerMillion;
  late final TextEditingController _outputPerMillion;
  late final TextEditingController _cacheReadPerMillion;
  late final TextEditingController _cacheWritePerMillion;

  @override
  void initState() {
    super.initState();
    final price = widget.initialPrice;
    _provider = TextEditingController(text: price?.provider ?? '');
    _model = TextEditingController(text: price?.model ?? '');
    _inputPerMillion = TextEditingController(text: price == null ? '' : price.inputPerMillion.toStringAsFixed(6));
    _outputPerMillion = TextEditingController(text: price == null ? '' : price.outputPerMillion.toStringAsFixed(6));
    _cacheReadPerMillion = TextEditingController(text: price == null || price.cacheReadPerMillion == 0 ? '' : price.cacheReadPerMillion.toStringAsFixed(6));
    _cacheWritePerMillion = TextEditingController(text: price == null || price.cacheWritePerMillion == 0 ? '' : price.cacheWritePerMillion.toStringAsFixed(6));
  }

  @override
  void dispose() {
    _provider.dispose();
    _model.dispose();
    _inputPerMillion.dispose();
    _outputPerMillion.dispose();
    _cacheReadPerMillion.dispose();
    _cacheWritePerMillion.dispose();
    super.dispose();
  }

  void _save() {
    final provider = _provider.text.trim();
    final model = _model.text.trim();
    final input = _moneyPerMillion(_inputPerMillion.text);
    final output = _moneyPerMillion(_outputPerMillion.text);
    final cacheRead = _moneyPerMillion(_cacheReadPerMillion.text);
    final cacheWrite = _moneyPerMillion(_cacheWritePerMillion.text);
    if (provider.isEmpty || model.isEmpty || input == null || output == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Provider, model, input and output prices are required.')));
      return;
    }
    Navigator.of(context).pop(TokenPrice(
      provider: provider,
      model: model,
      inputCostPerToken: input,
      outputCostPerToken: output,
      cacheReadCostPerToken: cacheRead ?? 0,
      cacheWriteCostPerToken: cacheWrite ?? 0,
      sourceName: 'User override',
      sourceUrl: '',
      updatedAt: DateTime.now(),
      custom: true,
      notes: 'User-configured MobileCode price override.',
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                children: [
                  Icon(Icons.price_change_outlined, color: _usageAmber, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Pricing override', style: TextStyle(color: _usageText, fontSize: 16, fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter USD prices per 1M tokens. MobileCode stores only the price table, not prompts or responses.',
                style: TextStyle(color: _usageMuted, fontSize: 12, height: 1.35),
              ),
              const SizedBox(height: 12),
              TextField(controller: _provider, decoration: const InputDecoration(labelText: 'Provider, e.g. openai / anthropic / custom')),
              const SizedBox(height: 8),
              TextField(controller: _model, decoration: const InputDecoration(labelText: 'Model, e.g. gpt-4o-mini')),
              const SizedBox(height: 8),
              TextField(
                controller: _inputPerMillion,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Input USD / 1M tokens'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _outputPerMillion,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Output USD / 1M tokens'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _cacheReadPerMillion,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Cache read USD / 1M tokens (optional)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _cacheWritePerMillion,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Cache write USD / 1M tokens (optional)'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
          const SizedBox(height: 4),
          Text(
            'price: ${event.pricingSource} · ${_dateLabel(event.pricingUpdatedAt)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _usageFaint, fontSize: 10.5, height: 1.3),
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

double? _moneyPerMillion(String value) {
  final parsed = double.tryParse(value.trim());
  if (parsed == null || parsed < 0) return null;
  return parsed / 1000000;
}

String _dateLabel(DateTime value) {
  final y = value.year.toString().padLeft(4, '0');
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String _timeLabel(DateTime value) {
  final h = value.hour.toString().padLeft(2, '0');
  final m = value.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
