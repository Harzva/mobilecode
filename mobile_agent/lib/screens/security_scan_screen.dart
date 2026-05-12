// lib/screens/security_scan_screen.dart
// Security Scan Screen — Detailed security scan results.
//
// Displays a comprehensive security report with:
// - Animated risk score gauge (0-100)
// - Severity breakdown counts (critical/high/medium/low)
// - Filterable issue list with search
// - Export to Markdown/JSON/clipboard
// - Individual issue actions (resolve, share)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_agent/core/theme.dart';
import 'package:mobile_agent/services/binary_analysis_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Severity Filter Enum
// ═══════════════════════════════════════════════════════════════════════════

enum SeverityFilter { all, critical, high, medium, low }

extension SeverityFilterX on SeverityFilter {
  String get label => switch (this) {
    SeverityFilter.all => '全部',
    SeverityFilter.critical => '严重',
    SeverityFilter.high => '高危',
    SeverityFilter.medium => '中危',
    SeverityFilter.low => '低危',
  };
  String? get severityValue => switch (this) {
    SeverityFilter.all => null,
    SeverityFilter.critical => 'critical',
    SeverityFilter.high => 'high',
    SeverityFilter.medium => 'medium',
    SeverityFilter.low => 'low',
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// Security Scan Screen
// ═══════════════════════════════════════════════════════════════════════════

class SecurityScanScreen extends StatefulWidget {
  final SecurityScanResult result;
  final String projectPath;

  const SecurityScanScreen({
    super.key,
    required this.result,
    required this.projectPath,
  });

  @override
  State<SecurityScanScreen> createState() => _SecurityScanScreenState();
}

class _SecurityScanScreenState extends State<SecurityScanScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  SeverityFilter _currentFilter = SeverityFilter.all;
  final Set<String> _resolvedIssues = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _currentFilter = SeverityFilter.values[_tabController.index]);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<SecurityIssue> get _activeIssues {
    return widget.result.issues.where((i) => !_resolvedIssues.contains(i.id)).toList();
  }

  List<SecurityIssue> get _filteredIssues {
    var issues = _activeIssues;
    if (_currentFilter != SeverityFilter.all) {
      issues = issues.where((i) => i.severity == _currentFilter.severityValue).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      issues = issues.where((i) =>
        i.title.toLowerCase().contains(q) ||
        i.description.toLowerCase().contains(q) ||
        (i.filePath?.toLowerCase().contains(q) ?? false),
      ).toList();
    }
    return issues;
  }

  int _countByFilter(SeverityFilter filter) {
    if (filter == SeverityFilter.all) return _activeIssues.length;
    return _activeIssues.where((i) => i.severity == filter.severityValue).length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('安全扫描报告'),
        backgroundColor: AppTheme.backgroundElevated,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        actions: [
          _ExportMenu(result: widget.result, onExport: () => setState(() {})),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildRiskHeader(),
          _buildSearchBar(),
          _buildFilterTabs(),
          Expanded(
            child: _filteredIssues.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _filteredIssues.length,
                    itemBuilder: (context, index) {
                      final issue = _filteredIssues[index];
                      return _IssueCard(
                        issue: issue,
                        onResolve: () => setState(() => _resolvedIssues.add(issue.id)),
                        onShare: () => _shareIssue(issue),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskHeader() {
    final c = _riskColor(widget.result.riskScore);
    return Container(
      margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withOpacity(0.3))),
      child: Column(children: [
        Row(children: [
          SizedBox(width: 90, height: 90, child: Stack(fit: StackFit.expand, children: [
            CircularProgressIndicator(value: widget.result.riskScore / 100, strokeWidth: 8, backgroundColor: AppTheme.border, valueColor: AlwaysStoppedAnimation<Color>(c)),
            Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${widget.result.riskScore}', style: TextStyle(fontFamily: AppTheme.fontBody, fontSize: 24, fontWeight: FontWeight.bold, color: c)),
              const Text('/ 100', style: TextStyle(fontFamily: AppTheme.fontBody, fontSize: 10, color: AppTheme.textTertiary)),
            ])),
          ])),
          const SizedBox(width: 20),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_riskLabel(widget.result.riskScore), style: TextStyle(fontFamily: AppTheme.fontBody, fontSize: 20, fontWeight: FontWeight.bold, color: c)),
            const SizedBox(height: 4),
            Text('共发现 ${widget.result.totalIssues} 个问题', style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 13, color: AppTheme.textSecondary)),
            if (widget.projectPath.isNotEmpty) Text(widget.projectPath, style: const TextStyle(fontFamily: AppTheme.fontCode, fontSize: 11, color: AppTheme.textTertiary), overflow: TextOverflow.ellipsis),
          ])),
        ]),
        const SizedBox(height: 16), const Divider(color: AppTheme.divider), const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _SeverityStat(label: '严重', count: widget.result.criticalIssues, color: AppTheme.error),
          _SeverityStat(label: '高危', count: widget.result.highIssues, color: const Color(0xFFF97316)),
          _SeverityStat(label: '中危', count: widget.result.mediumIssues, color: const Color(0xFFFBBF24)),
          _SeverityStat(label: '低危', count: widget.result.lowIssues, color: AppTheme.info),
        ]),
        if (_resolvedIssues.isNotEmpty) ...[const SizedBox(height: 12), const Divider(color: AppTheme.divider),
          Row(children: [Icon(Icons.check_circle, size: 14, color: AppTheme.success), const SizedBox(width: 6),
            Text('${_resolvedIssues.length} 个问题已解决', style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 12, color: AppTheme.success)),
            const Spacer(),
            TextButton(onPressed: () => setState(() => _resolvedIssues.clear()), style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary, padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap), child: const Text('撤销全部', style: TextStyle(fontSize: 12))),
          ]),
        ],
      ]),
    );
  }

  Widget _buildSearchBar() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16), margin: const EdgeInsets.only(bottom: 8),
    child: TextField(
      controller: _searchController,
      style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 14, color: AppTheme.textPrimary),
      decoration: InputDecoration(
        hintText: '搜索问题标题、描述、文件路径...', hintStyle: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 14, color: AppTheme.textTertiary),
        prefixIcon: const Icon(Icons.search, size: 18, color: AppTheme.textTertiary),
        suffixIcon: _searchQuery.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 18, color: AppTheme.textTertiary), onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); }) : null,
        filled: true, fillColor: AppTheme.surface, contentPadding: const EdgeInsets.symmetric(vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
      ),
      onChanged: (v) => setState(() => _searchQuery = v),
    ),
  );

  Widget _buildFilterTabs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        labelColor: AppTheme.primary,
        unselectedLabelColor: AppTheme.textTertiary,
        indicatorColor: AppTheme.primary,
        indicatorWeight: 2,
        labelStyle: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 13, fontWeight: FontWeight.w500),
        tabs: SeverityFilter.values.map((f) {
          final isActive = _currentFilter == f;
          final fc = _filterColor(f);
          return Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(f.label),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: fc.withOpacity(isActive ? 0.2 : 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_countByFilter(f)}',
                    style: TextStyle(fontFamily: AppTheme.fontBody, fontSize: 11, fontWeight: FontWeight.w600, color: isActive ? fc : AppTheme.textTertiary),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmptyState() {
    final isSearch = _searchQuery.isNotEmpty;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSearch ? Icons.search_off : Icons.check_circle_outline,
            size: 56,
            color: isSearch ? AppTheme.textTertiary.withOpacity(0.4) : AppTheme.success.withOpacity(0.5),
          ),
          const SizedBox(height: 12),
          Text(
            isSearch ? '未找到 "$_searchQuery" 的问题' : (_currentFilter == SeverityFilter.all ? '所有问题已解决 ✓' : '该级别下没有问题'),
            style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 15, color: AppTheme.textSecondary),
          ),
          if (!isSearch && _currentFilter == SeverityFilter.all && _resolvedIssues.isNotEmpty)
            TextButton(onPressed: () => setState(() => _resolvedIssues.clear()), child: const Text('显示已解决问题')),
          if (isSearch)
            TextButton(onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); }, child: const Text('清除搜索')),
        ],
      ),
    );
  }

  Color _filterColor(SeverityFilter f) => switch (f) {
    SeverityFilter.critical => AppTheme.error,
    SeverityFilter.high => const Color(0xFFF97316),
    SeverityFilter.medium => const Color(0xFFFBBF24),
    SeverityFilter.low => AppTheme.info,
    SeverityFilter.all => AppTheme.primary,
  };

  Color _riskColor(int s) => s == 0 ? AppTheme.success : s < 30 ? AppTheme.warning : s < 60 ? const Color(0xFFF97316) : AppTheme.error;

  String _riskLabel(int s) => s == 0 ? '安全' : s < 20 ? '低风险' : s < 40 ? '中低风险' : s < 60 ? '中风险' : s < 80 ? '高风险' : '严重风险';

  void _shareIssue(SecurityIssue issue) {
    Clipboard.setData(ClipboardData(text: 'Security: ${issue.title}\nSeverity: ${issue.severity}\nCategory: ${issue.category}\n${issue.description}\n${issue.recommendation ?? ''}'));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Severity Stat
// ═══════════════════════════════════════════════════════════════════════════

class _SeverityStat extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _SeverityStat({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$count',
          style: TextStyle(fontFamily: AppTheme.fontBody, fontSize: 22, fontWeight: FontWeight.bold, color: count > 0 ? color : AppTheme.textTertiary)),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 12, color: AppTheme.textSecondary)),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Issue Card
// ═══════════════════════════════════════════════════════════════════════════

class _IssueCard extends StatelessWidget {
  final SecurityIssue issue;
  final VoidCallback onResolve;
  final VoidCallback onShare;

  const _IssueCard({required this.issue, required this.onResolve, required this.onShare});

  Color _severityColor(String s) => switch (s) {
    'critical' => AppTheme.error,
    'high' => const Color(0xFFF97316),
    'medium' => const Color(0xFFFBBF24),
    'low' => AppTheme.info,
    _ => AppTheme.textTertiary,
  };

  String _severityLabel(String s) => {'critical': '严重', 'high': '高危', 'medium': '中危', 'low': '低危', 'info': '信息'}[s] ?? s;
  String _categoryLabel(String c) => {'permissions': '权限', 'secrets': '密钥', 'network': '网络', 'storage': '存储', 'crypto': '加密'}[c] ?? c;

  @override
  Widget build(BuildContext context) {
    final c = _severityColor(issue.severity);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: badges + actions
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: c.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                  child: Text(_severityLabel(issue.severity),
                    style: TextStyle(fontFamily: AppTheme.fontBody, fontSize: 11, fontWeight: FontWeight.w700, color: c)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppTheme.surfaceHover, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppTheme.border)),
                  child: Text(_categoryLabel(issue.category),
                    style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 10, color: AppTheme.textTertiary)),
                ),
                const Spacer(),
                Text(issue.id, style: const TextStyle(fontFamily: AppTheme.fontCode, fontSize: 10, color: AppTheme.textTertiary)),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18, color: AppTheme.textTertiary),
                  color: AppTheme.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: AppTheme.border)),
                  onSelected: (v) { if (v == 'resolve') onResolve(); if (v == 'share') onShare(); },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'resolve',
                      child: Row(children: [Icon(Icons.check_circle, size: 16, color: AppTheme.success), SizedBox(width: 8), Text('标记为已解决', style: TextStyle(fontFamily: AppTheme.fontBody, fontSize: 13))])),
                    const PopupMenuItem(value: 'share',
                      child: Row(children: [Icon(Icons.share, size: 16, color: AppTheme.info), SizedBox(width: 8), Text('分享问题', style: TextStyle(fontFamily: AppTheme.fontBody, fontSize: 13))])),
                  ],
                ),
              ],
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Text(issue.title,
              style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          ),
          // Description
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: Text(issue.description,
              style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 13, color: AppTheme.textSecondary)),
          ),
          // File path + line number
          if (issue.filePath != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  const Icon(Icons.insert_drive_file, size: 12, color: AppTheme.textTertiary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(issue.filePath!,
                      style: const TextStyle(fontFamily: AppTheme.fontCode, fontSize: 11, color: AppTheme.textTertiary),
                      overflow: TextOverflow.ellipsis),
                  ),
                  if (issue.lineNumber != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppTheme.surfaceHover, borderRadius: BorderRadius.circular(4)),
                      child: Text('L${issue.lineNumber}',
                        style: const TextStyle(fontFamily: AppTheme.fontCode, fontSize: 10, color: AppTheme.textTertiary)),
                    ),
                  ],
                ],
              ),
            ),
          ],
          // Recommendation
          if (issue.recommendation != null) ...[
            const SizedBox(height: 10),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.accent.withOpacity(0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline, size: 14, color: AppTheme.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(issue.recommendation!,
                      style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 12, color: AppTheme.accent)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Export Menu
// ═══════════════════════════════════════════════════════════════════════════

class _ExportMenu extends StatelessWidget {
  final SecurityScanResult result;
  final VoidCallback onExport;

  const _ExportMenu({required this.result, required this.onExport});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: AppTheme.border)),
      onSelected: (f) => _export(f, context),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'md',
          child: Row(children: [Icon(Icons.description, size: 16, color: AppTheme.textSecondary), SizedBox(width: 8), Text('导出 Markdown', style: TextStyle(fontFamily: AppTheme.fontBody, fontSize: 13, color: AppTheme.textPrimary))])),
        const PopupMenuItem(value: 'json',
          child: Row(children: [Icon(Icons.data_object, size: 16, color: AppTheme.textSecondary), SizedBox(width: 8), Text('导出 JSON', style: TextStyle(fontFamily: AppTheme.fontBody, fontSize: 13, color: AppTheme.textPrimary))])),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'copy',
          child: Row(children: [Icon(Icons.copy, size: 16, color: AppTheme.textSecondary), SizedBox(width: 8), Text('复制摘要', style: TextStyle(fontFamily: AppTheme.fontBody, fontSize: 13, color: AppTheme.textPrimary))])),
      ],
    );
  }

  Future<void> _export(String fmt, BuildContext ctx) async {
    final b = StringBuffer();
    if (fmt == 'md') {
      b.writeln('# Security Scan Report\n\n## Risk Score: ${result.riskScore}/100\n\n| Severity | Count |\n|----------|-------|');
      b.writeln('| Critical | ${result.criticalIssues} |\n| High | ${result.highIssues} |\n| Medium | ${result.mediumIssues} |\n| Low | ${result.lowIssues} |\n\n## Issues');
      for (final i in result.issues) {
        b.writeln('### ${i.id}: ${i.title}\n- **Severity:** ${i.severity}\n- **Category:** ${i.category}${i.filePath != null ? "\n- **File:** `${i.filePath}`" : ""}\n- **Description:** ${i.description}${i.recommendation != null ? "\n- **Fix:** ${i.recommendation}" : ""}\n');
      }
    } else if (fmt == 'json') {
      b.writeln('{\n  "riskScore": ${result.riskScore},\n  "totalIssues": ${result.totalIssues},\n  "critical": ${result.criticalIssues},\n  "high": ${result.highIssues},\n  "medium": ${result.mediumIssues},\n  "low": ${result.lowIssues},\n  "issues": [');
      for (var i = 0; i < result.issues.length; i++) {
        final iss = result.issues[i];
        b.writeln('    {"id": "${iss.id}", "title": "${iss.title}", "severity": "${iss.severity}", "category": "${iss.category}"}${i < result.issues.length - 1 ? "," : ""}');
      }
      b.writeln('  ]\n}');
    } else {
      b.write('Scan: ${result.riskScore}/100 — ${result.totalIssues} issues (C:${result.criticalIssues} H:${result.highIssues} M:${result.mediumIssues} L:${result.lowIssues})');
    }
    await Clipboard.setData(ClipboardData(text: b.toString()));
    onExport();
    if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('已导出为 ${fmt.toUpperCase()}')));
  }
}
