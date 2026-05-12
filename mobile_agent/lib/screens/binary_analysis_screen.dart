// lib/screens/binary_analysis_screen.dart
// Binary Analysis Screen — Main UI for binary/static analysis.
// Features: 6-tab selector (APK/IPA/Quality/Security/Deps/Size),
// file picker, summary cards, type-specific results, risk gauge, export.
// Design: Dark theme with cards and color-coded severity.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_agent/core/theme.dart';
import 'package:mobile_agent/providers/binary_analysis_provider.dart';
import 'package:mobile_agent/screens/security_scan_screen.dart';
import 'package:mobile_agent/services/binary_analysis_service.dart';

enum AnalysisType {
  apk(label: 'APK分析', icon: Icons.android, color: AppTheme.success),
  ipa(label: 'IPA分析', icon: Icons.apple, color: AppTheme.textPrimary),
  codeQuality(label: '代码质量', icon: Icons.code, color: AppTheme.info),
  security(label: '安全扫描', icon: Icons.security, color: AppTheme.error),
  dependencies(label: '依赖分析', icon: Icons.account_tree, color: AppTheme.accent),
  size(label: '大小分析', icon: Icons.folder_open, color: AppTheme.warning);
  final String label; final IconData icon; final Color color;
  const AnalysisType({required this.label, required this.icon, required this.color});
}

class BinaryAnalysisScreen extends ConsumerStatefulWidget {
  const BinaryAnalysisScreen({super.key});
  @override ConsumerState<BinaryAnalysisScreen> createState() => _BinaryAnalysisScreenState();
}

class _BinaryAnalysisScreenState extends ConsumerState<BinaryAnalysisScreen> with SingleTickerProviderStateMixin {
  late final TabController _tc;
  AnalysisType _type = AnalysisType.security;
  final _pathCtrl = TextEditingController();
  bool _analyzing = false;

  @override void initState() {
    super.initState();
    _tc = TabController(length: 6, vsync: this);
    _tc.addListener(() { if (!_tc.indexIsChanging) setState(() => _type = AnalysisType.values[_tc.index]); });
  }
  @override void dispose() { _tc.dispose(); _pathCtrl.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    final state = ref.watch(binaryAnalysisProvider);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('二进制分析'),
        backgroundColor: AppTheme.backgroundElevated, foregroundColor: AppTheme.textPrimary, elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            height: 56, padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(color: AppTheme.backgroundElevated, border: Border(bottom: BorderSide(color: AppTheme.divider))),
            child: TabBar(
              controller: _tc, isScrollable: true, labelColor: AppTheme.primary, unselectedLabelColor: AppTheme.textTertiary,
              indicatorColor: AppTheme.primary, indicatorWeight: 2, tabAlignment: TabAlignment.start,
              tabs: AnalysisType.values.map((t) => Tab(icon: Icon(t.icon, size: 18), text: t.label)).toList(),
            ),
          ),
        ),
      ),
      body: Column(children: [
        _buildFileSelector(),
        Expanded(child: _analyzing ? _buildLoading() : _buildResults(state)),
        if (state.hasResults) _buildBottomBar(state),
      ]),
    );
  }

  Widget _buildFileSelector() => Container(
    margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(_type.icon, color: _type.color, size: 20), const SizedBox(width: 8),
        Text('选择分析目标 — ${_type.label}', style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
        const Spacer(),
        TextButton.icon(
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('导出功能开发中...'))),
          icon: const Icon(Icons.download, size: 14), label: const Text('导出'),
          style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
        ),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: TextField(
          controller: _pathCtrl,
          style: const TextStyle(fontFamily: AppTheme.fontCode, fontSize: 13, color: AppTheme.textSecondary),
          decoration: InputDecoration(
            hintText: _hintText(), hintStyle: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 13, color: AppTheme.textTertiary),
            filled: true, fillColor: AppTheme.surfaceInput,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          onChanged: (_) => setState(() {}),
        )),
        const SizedBox(width: 12),
        ElevatedButton.icon(onPressed: _pickFile, icon: const Icon(Icons.folder_open, size: 16), label: const Text('浏览'),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: AppTheme.textOnPrimary, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(width: 8),
        ElevatedButton.icon(onPressed: _pathCtrl.text.isNotEmpty ? _startAnalysis : null, icon: const Icon(Icons.play_arrow, size: 16), label: const Text('分析'),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: AppTheme.background, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), disabledBackgroundColor: AppTheme.accent.withOpacity(0.3))),
      ]),
    ]),
  );

  Widget _buildLoading() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 3, valueColor: AlwaysStoppedAnimation<Color>(_type.color))),
    const SizedBox(height: 20),
    Text('正在分析 — ${_type.label}', style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 16, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
    const SizedBox(height: 8),
    const Text('纯静态分析过程，不会执行任何代码', style: TextStyle(fontFamily: AppTheme.fontBody, fontSize: 12, color: AppTheme.textTertiary)),
    const SizedBox(height: 16),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.info_outline, size: 14, color: AppTheme.info),
        const SizedBox(width: 6),
        Text('分析类型: ${_type.label}', style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 12, color: AppTheme.textSecondary)),
      ]),
    ),
  ]));

  Widget _buildResults(BinaryAnalysisState state) {
    if (!state.hasResults) return _buildEmpty();
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildSummaryCards(state), const SizedBox(height: 16),
        _buildTypeResults(state), const SizedBox(height: 32),
      ]),
    );
  }

  Widget _buildEmpty() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(_type.icon, size: 64, color: AppTheme.textTertiary.withOpacity(0.3)),
    const SizedBox(height: 16),
    Text('选择文件开始${_type.label}', style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 16, color: AppTheme.textSecondary)),
    const SizedBox(height: 8),
    const Text('支持 APK、IPA、pubspec.yaml、Flutter 项目目录', style: TextStyle(fontFamily: AppTheme.fontBody, fontSize: 12, color: AppTheme.textTertiary)),
  ]));

  Widget _buildSummaryCards(BinaryAnalysisState s) => GridView.count(
    shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.8,
    children: [
      _SummaryCard('总文件数', '${s.totalFiles}', Icons.folder, AppTheme.info),
      _SummaryCard('代码行数', '${s.totalLines}', Icons.code, AppTheme.accent),
      _SummaryCard('发现问题', '${s.totalIssues}', Icons.report_problem, s.totalIssues > 0 ? AppTheme.error : AppTheme.success),
      _SummaryCard('风险评分', '${s.riskScore}', Icons.speed, _riskColor(s.riskScore)),
      _SummaryCard('依赖数量', '${s.totalDependencies}', Icons.account_tree, AppTheme.warning),
      _SummaryCard('应用大小', s.formattedSize, Icons.storage, AppTheme.primary),
    ],
  );

  Widget _buildTypeResults(BinaryAnalysisState s) {
    switch (_type) {
      case AnalysisType.apk: return _buildApk(s);
      case AnalysisType.ipa: return _buildIpa(s);
      case AnalysisType.codeQuality: return _buildQuality(s);
      case AnalysisType.security: return _buildSecurity(s);
      case AnalysisType.dependencies: return _buildDeps(s);
      case AnalysisType.size: return _buildSize(s);
    }
  }

  Widget _buildApk(BinaryAnalysisState s) {
    if (s.apkAnalysis == null) return const SizedBox.shrink();
    final a = s.apkAnalysis!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SecTitle('APK 信息'),
      _InfoCard([
        _InfoRow('文件名', a.fileName), _InfoRow('文件大小', a.formattedSize), _InfoRow('包名', a.packageName),
        _InfoRow('版本名称', a.versionName), _InfoRow('版本号', '${a.versionCode}'),
        _InfoRow('最低 SDK', 'API ${a.minSdkVersion}'), _InfoRow('目标 SDK', 'API ${a.targetSdkVersion}'),
        _InfoRow('调试模式', a.isDebuggable ? '是 ⚠️' : '否 ✓', vc: a.isDebuggable ? AppTheme.error : AppTheme.success),
        _InfoRow('已签名', a.isSigned ? '是 ✓' : '否 ⚠️', vc: a.isSigned ? AppTheme.success : AppTheme.warning),
      ]),
      const _SecTitle('组件'),
      _InfoCard([
        _InfoRow('Activities', '${a.activities.length}'), _InfoRow('Services', '${a.services.length}'),
        _InfoRow('Receivers', '${a.receivers.length}'), _InfoRow('Providers', '${a.providers.length}'),
        _InfoRow('权限', '${a.permissions.length}'), _InfoRow('DEX', '${a.dexCount}'),
        _InfoRow('原生库', '${a.nativeLibCount}'), _InfoRow('资源', '${a.resourceCount}'), _InfoRow('Assets', '${a.assetCount}'),
      ]),
      if (a.permissions.isNotEmpty) ...[const _SecTitle('权限列表'), _ChipList(a.permissions)],
      if (a.activities.isNotEmpty) ...[const _SecTitle('Activities'), _ChipList(a.activities)],
    ]);
  }

  Widget _buildIpa(BinaryAnalysisState s) {
    if (s.ipaAnalysis == null) return const SizedBox.shrink();
    final i = s.ipaAnalysis!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SecTitle('IPA 信息'),
      _InfoCard([
        _InfoRow('文件名', i.fileName), _InfoRow('大小', i.formattedSize),
        _InfoRow('Bundle ID', i.bundleIdentifier), _InfoRow('应用名称', i.bundleName),
        _InfoRow('版本', i.bundleVersion), _InfoRow('构建号', i.buildNumber),
        _InfoRow('最低系统', i.minimumOsVersion), _InfoRow('框架数', '${i.frameworkCount}'),
      ]),
    ]);
  }

  Widget _buildQuality(BinaryAnalysisState s) {
    if (s.qualityMetrics == null) return const SizedBox.shrink();
    final q = s.qualityMetrics!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SecTitle('代码质量指标'),
      _Gauge(q.qualityScore.toInt(), q.qualityScore > 80 ? AppTheme.success : q.qualityScore > 50 ? AppTheme.warning : AppTheme.error, '质量评分'),
      const SizedBox(height: 16),
      _InfoCard([
        _InfoRow('总文件数', '${q.totalFiles}'), _InfoRow('总行数', '${q.totalLines}'), _InfoRow('代码行', '${q.codeLines}'),
        _InfoRow('注释行', '${q.commentLines}'), _InfoRow('空行', '${q.blankLines}'),
        _InfoRow('注释比', '${(q.commentRatio * 100).toStringAsFixed(1)}%'),
        _InfoRow('平均复杂度', '${q.avgComplexity}'),
        _InfoRow('最大复杂度', '${q.maxComplexity}', vc: q.maxComplexity > 20 ? AppTheme.error : AppTheme.success),
      ]),
    ]);
  }

  Widget _buildSecurity(BinaryAnalysisState s) {
    if (s.securityResult == null) return const SizedBox.shrink();
    final r = s.securityResult!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SecTitle('安全风险评分'),
      _Gauge(r.riskScore, _riskColor(r.riskScore), _riskLabel(r.riskScore)),
      const SizedBox(height: 16),
      const _SecTitle('问题统计'),
      Row(children: [
        _SevBadge('严重', r.criticalIssues, AppTheme.error), const SizedBox(width: 8),
        _SevBadge('高危', r.highIssues, const Color(0xFFF97316)), const SizedBox(width: 8),
        _SevBadge('中危', r.mediumIssues, const Color(0xFFFBBF24)), const SizedBox(width: 8),
        _SevBadge('低危', r.lowIssues, AppTheme.info),
      ]),
      const SizedBox(height: 16),
      if (r.issues.isNotEmpty) ...[const _SecTitle('发现的问题'), ...r.issues.map((i) => _IssueCardW(i))],
      const SizedBox(height: 8),
      Center(child: TextButton.icon(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SecurityScanScreen(result: r, projectPath: _pathCtrl.text))),
        icon: const Icon(Icons.open_in_new, size: 16), label: const Text('查看详细安全报告'),
      )),
    ]);
  }

  Widget _buildDeps(BinaryAnalysisState s) {
    if (s.dependencyAnalysis == null) return const SizedBox.shrink();
    final d = s.dependencyAnalysis!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SecTitle('依赖概览'),
      _InfoCard([
        _InfoRow('直接依赖', '${d.directDependencies}'), _InfoRow('开发依赖', '${d.devDependencies}'),
        _InfoRow('传递依赖', '${d.transitiveDependencies}'), _InfoRow('未使用', '${d.unusedDependencies.length}', vc: d.unusedDependencies.isNotEmpty ? AppTheme.warning : AppTheme.success),
      ]),
      if (d.outdatedDependencies.isNotEmpty) ...[const _SecTitle('过时依赖'), ...d.outdatedDependencies.map((d) => _DepCard(d))],
      if (d.vulnerableDependencies.isNotEmpty) ...[const _SecTitle('漏洞依赖 ⚠️'), ...d.vulnerableDependencies.map((v) => _VulnCard(v))],
    ]);
  }

  Widget _buildSize(BinaryAnalysisState s) {
    if (s.sizeAnalysis == null) return const SizedBox.shrink();
    final z = s.sizeAnalysis!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SecTitle('大小分析 — ${z.formattedSize}'),
      ...z.breakdown.entries.map((e) => _SizeBar(_catLabel(e.key), '${_fmt(e.value)} (${z.totalSizeBytes > 0 ? (e.value / z.totalSizeBytes * 100).toStringAsFixed(1) : 0}%)', z.totalSizeBytes > 0 ? e.value / z.totalSizeBytes : 0, _catColor(e.key))),
      if (z.largestFiles.isNotEmpty) ...[const _SecTitle('最大文件'), ...z.largestFiles.take(10).map((f) => _FileRow(f))],
    ]);
  }

  String _hintText() => switch(_type) { AnalysisType.apk => '输入 APK 文件路径', AnalysisType.ipa => '输入 IPA 文件路径', AnalysisType.dependencies => '输入 pubspec.yaml 路径', _ => '输入 Flutter 项目路径' };
  Color _riskColor(int s) => s == 0 ? AppTheme.success : s < 30 ? AppTheme.warning : s < 60 ? const Color(0xFFF97316) : AppTheme.error;
  String _riskLabel(int s) => s == 0 ? '安全' : s < 20 ? '低风险' : s < 40 ? '中低风险' : s < 60 ? '中风险' : s < 80 ? '高风险' : '严重风险';
  String _catLabel(String k) => {'dart_code': 'Dart 代码', 'assets': '资源文件', 'dependencies': '依赖', 'config': '配置', 'other': '其他'}[k] ?? k;
  Color _catColor(String k) => {'dart_code': AppTheme.info, 'assets': AppTheme.accent, 'dependencies': AppTheme.warning, 'config': AppTheme.textSecondary, 'other': AppTheme.textTertiary}[k] ?? AppTheme.textTertiary;
  String _fmt(int b) => b < 1024 ? '${b}B' : b < 1048576 ? '${(b/1024).toStringAsFixed(1)}KB' : '${(b/1048576).toStringAsFixed(1)}MB';

  void _pickFile() => setState(() { _pathCtrl.text = '/path/to/sample/${_type == AnalysisType.apk ? "app.apk" : _type == AnalysisType.ipa ? "app.ipa" : "pubspec.yaml"}'; });

  Future<void> _startAnalysis() async {
    setState(() => _analyzing = true);
    try { await ref.read(binaryAnalysisProvider.notifier).runAnalysis(type: _type, path: _pathCtrl.text); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('分析失败: $e'))); }
    finally { if (mounted) setState(() => _analyzing = false); }
  }

  Widget _buildBottomBar(BinaryAnalysisState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: AppTheme.backgroundElevated, border: Border(top: BorderSide(color: AppTheme.divider))),
      child: SafeArea(
        child: Row(children: [
          if (state.lastAnalysisType != null) ...[
            Icon(state.lastAnalysisType!.icon, size: 14, color: AppTheme.textTertiary),
            const SizedBox(width: 6),
            Text('上次: ${state.lastAnalysisType!.label}', style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 12, color: AppTheme.textTertiary)),
          ],
          const Spacer(),
          TextButton.icon(
            onPressed: () => ref.read(binaryAnalysisProvider.notifier).clear(),
            icon: const Icon(Icons.clear_all, size: 14), label: const Text('清除结果'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () { if (state.securityResult != null) Navigator.of(context).push(MaterialPageRoute(builder: (_) => SecurityScanScreen(result: state.securityResult!, projectPath: _pathCtrl.text))); },
            icon: const Icon(Icons.open_in_new, size: 14), label: const Text('安全详情'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primary, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
          ),
        ]),
      ),
    );
  }
}

// ── Sub-Widgets ──────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final String label, value; final IconData icon; final Color color;
  const _SummaryCard(this.label, this.value, this.icon, this.color);
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
      Row(children: [Icon(icon, size: 16, color: color), const SizedBox(width: 6), Text(label, style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 11, color: AppTheme.textTertiary))]),
      const SizedBox(height: 6),
      Text(value, style: TextStyle(fontFamily: AppTheme.fontBody, fontSize: 18, fontWeight: FontWeight.bold, color: color)),
    ]));
}

class _SecTitle extends StatelessWidget {
  final String text; const _SecTitle(this.text);
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10, top: 4),
    child: Text(text, style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)));
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children; const _InfoCard(this.children);
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.border)),
    child: Column(children: children));
}

class _InfoRow extends StatelessWidget {
  final String label, value; final Color? vc; const _InfoRow(this.label, this.value, {this.vc});
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(flex: 2, child: Text(label, style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 13, color: AppTheme.textSecondary))),
      Expanded(flex: 3, child: Text(value, style: TextStyle(fontFamily: AppTheme.fontCode, fontSize: 13, color: vc ?? AppTheme.textPrimary))),
    ]));
}

class _ChipList extends StatelessWidget {
  final List<String> items; const _ChipList(this.items);
  @override Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 6,
    children: items.map((item) => Chip(
      label: Text(item, style: const TextStyle(fontFamily: AppTheme.fontCode, fontSize: 11, color: AppTheme.textSecondary)),
      backgroundColor: AppTheme.surfaceHover, side: const BorderSide(color: AppTheme.border),
      padding: const EdgeInsets.symmetric(horizontal: 6), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    )).toList());
}

class _SevBadge extends StatelessWidget {
  final String label; final int count; final Color color;
  const _SevBadge(this.label, this.count, this.color);
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.3))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
      const SizedBox(width: 6),
      Text('$label ', style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 12, color: AppTheme.textSecondary)),
      Text('$count', style: TextStyle(fontFamily: AppTheme.fontBody, fontSize: 14, fontWeight: FontWeight.bold, color: color)),
    ]));
}

class _Gauge extends StatelessWidget {
  final int score; final Color color; final String label;
  const _Gauge(this.score, this.color, this.label);
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.3))),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      SizedBox(width: 100, height: 100, child: Stack(fit: StackFit.expand, children: [
        CircularProgressIndicator(value: score / 100, strokeWidth: 10, backgroundColor: AppTheme.border, valueColor: AlwaysStoppedAnimation<Color>(color)),
        Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('$score', style: TextStyle(fontFamily: AppTheme.fontBody, fontSize: 28, fontWeight: FontWeight.bold, color: color)),
          const Text('/ 100', style: TextStyle(fontFamily: AppTheme.fontBody, fontSize: 10, color: AppTheme.textTertiary)),
        ])),
      ])),
      const SizedBox(width: 24),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$label — ${score == 0 ? "安全" : score < 30 ? "低风险" : score < 60 ? "中风险" : "高风险"}', style: TextStyle(fontFamily: AppTheme.fontBody, fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(score == 0 ? '未发现安全问题' : '建议按优先级修复', style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 13, color: AppTheme.textSecondary)),
      ])),
    ]));
}

class _IssueCardW extends StatelessWidget {
  final SecurityIssue issue; const _IssueCardW(this.issue);
  Color _sevColor(String s) => switch(s) {'critical' => AppTheme.error, 'high' => const Color(0xFFF97316), 'medium' => const Color(0xFFFBBF24), 'low' => AppTheme.info, _ => AppTheme.textTertiary};
  String _sevLabel(String s) => {'critical': '严重', 'high': '高危', 'medium': '中危', 'low': '低危', 'info': '信息'}[s] ?? s;
  @override Widget build(BuildContext context) {
    final c = _sevColor(issue.severity);
    return Container(
      margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: c.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
            child: Text(_sevLabel(issue.severity), style: TextStyle(fontFamily: AppTheme.fontBody, fontSize: 11, fontWeight: FontWeight.w700, color: c))),
          const SizedBox(width: 8),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: AppTheme.surfaceHover, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppTheme.border)),
            child: Text(issue.category.toUpperCase(), style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 10, color: AppTheme.textTertiary))),
          const Spacer(),
          if (issue.filePath != null) Text(issue.filePath!.split('/').last, style: const TextStyle(fontFamily: AppTheme.fontCode, fontSize: 11, color: AppTheme.textTertiary)),
        ]),
        const SizedBox(height: 8),
        Text(issue.title, style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
        const SizedBox(height: 4),
        Text(issue.description, style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 12, color: AppTheme.textSecondary)),
        if (issue.recommendation != null) ...[
          const SizedBox(height: 8),
          Row(children: [const Icon(Icons.lightbulb_outline, size: 14, color: AppTheme.accent), const SizedBox(width: 6),
            Expanded(child: Text(issue.recommendation!, style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 11, color: AppTheme.accent)))]),
        ],
      ]));
  }
}

class _DepCard extends StatelessWidget {
  final OutdatedDependency dep; const _DepCard(this.dep);
  @override Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.border)),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(dep.name, style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
        const SizedBox(height: 4),
        Text('${dep.currentVersion} → ${dep.latestVersion}', style: const TextStyle(fontFamily: AppTheme.fontCode, fontSize: 12, color: AppTheme.textSecondary)),
      ])),
      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: (dep.severity == 'major' ? AppTheme.error : AppTheme.warning).withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
        child: Text(dep.severity.toUpperCase(), style: TextStyle(fontFamily: AppTheme.fontBody, fontSize: 11, fontWeight: FontWeight.w600, color: dep.severity == 'major' ? AppTheme.error : AppTheme.warning))),
    ]));
}

class _VulnCard extends StatelessWidget {
  final VulnerableDependency v; const _VulnCard(this.v);
  @override Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppTheme.error.withOpacity(0.05), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.error.withOpacity(0.3))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: AppTheme.error.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
          child: Text(v.severity.toUpperCase(), style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.error))),
        const SizedBox(width: 8),
        Text(v.vulnerabilityId, style: const TextStyle(fontFamily: AppTheme.fontCode, fontSize: 11, color: AppTheme.textTertiary)),
      ]),
      const SizedBox(height: 8),
      Text('${v.name} ${v.currentVersion}', style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
      const SizedBox(height: 4),
      Text(v.description, style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 12, color: AppTheme.textSecondary)),
      const SizedBox(height: 8),
      Row(children: [const Icon(Icons.update, size: 14, color: AppTheme.accent), const SizedBox(width: 6), Text('修复: ${v.fixedVersion}', style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 11, color: AppTheme.accent))]),
    ]));
}

class _SizeBar extends StatelessWidget {
  final String label, size; final double percent; final Color color;
  const _SizeBar(this.label, this.size, this.percent, this.color);
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 12, color: AppTheme.textSecondary)),
        Text(size, style: const TextStyle(fontFamily: AppTheme.fontCode, fontSize: 12, color: AppTheme.textPrimary)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: percent, minHeight: 8, backgroundColor: AppTheme.border, valueColor: AlwaysStoppedAnimation<Color>(color))),
    ]));
}

class _FileRow extends StatelessWidget {
  final FileSizeInfo file; const _FileRow(this.file);
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      const Icon(Icons.insert_drive_file, size: 14, color: AppTheme.textTertiary), const SizedBox(width: 8),
      Expanded(child: Text(file.relativePath, style: const TextStyle(fontFamily: AppTheme.fontCode, fontSize: 11, color: AppTheme.textSecondary), overflow: TextOverflow.ellipsis)),
      Text(file.formattedSize, style: const TextStyle(fontFamily: AppTheme.fontCode, fontSize: 11, color: AppTheme.textPrimary)),
    ]));
}
