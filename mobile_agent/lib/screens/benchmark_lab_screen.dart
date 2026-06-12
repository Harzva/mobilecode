import 'package:flutter/material.dart';

const _labBg = Color(0xFFF7FAFF);
const _labPanel = Color(0xFFFFFFFF);
const _labPanelSoft = Color(0xFFF0F5FF);
const _labLine = Color(0xFFDDE7F7);
const _labText = Color(0xFF0B1020);
const _labMuted = Color(0xFF536079);
const _labMint = Color(0xFF0B9B7E);
const _labCyan = Color(0xFF16B9C7);
const _labAmber = Color(0xFFB7791F);
const _labRose = Color(0xFFE0526E);
const _labViolet = Color(0xFF7557E8);
const _labBlue = Color(0xFF2555FF);

class BenchmarkLabScreen extends StatelessWidget {
  const BenchmarkLabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _labBg,
      appBar: AppBar(
        title: const Text('Benchmark Lab'),
        backgroundColor: _labBg,
        foregroundColor: _labText,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: const [
          _BenchmarkHero(),
          SizedBox(height: 12),
          _BenchmarkStatGrid(),
          SizedBox(height: 12),
          _PatternPanel(),
          SizedBox(height: 12),
          _TaskRegistryPanel(),
          SizedBox(height: 12),
          _EvidenceTierPanel(),
          SizedBox(height: 12),
          _EvidencePackPanel(),
          SizedBox(height: 12),
          _OpenGatePanel(),
        ],
      ),
    );
  }
}

class _BenchmarkHero extends StatelessWidget {
  const _BenchmarkHero();

  @override
  Widget build(BuildContext context) {
    return const _LabPanel(
      color: _labMint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LabPill(label: 'MobileHarnessBench', icon: Icons.science_outlined, color: _labMint),
          SizedBox(height: 12),
          Text(
            'App 内 Benchmark Lab 原型',
            style: TextStyle(color: _labText, fontSize: 24, height: 1.05, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 8),
          Text(
            '把 MobileHarnessBench 从文档推进到产品面：任务注册、Skill 合约、证据等级、Verifier 和 open gates 都在手机端可见。当前仍是只读原型，不声称真实 Android/iOS 实验已完成。',
            style: TextStyle(color: _labMuted, height: 1.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _BenchmarkStatGrid extends StatelessWidget {
  const _BenchmarkStatGrid();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: _build,
    );
  }

  static Widget _build(BuildContext context, BoxConstraints constraints) {
    final narrow = constraints.maxWidth < 620;
    const stats = [
      _LabStat(label: 'candidate tasks', value: '1000', detail: 'v2 task bank · 6 categories', color: _labMint),
      _LabStat(label: 'T0 smoke', value: '60', detail: '50 passed · 10 typed blocked', color: _labCyan),
      _LabStat(label: 'verifier contracts', value: '12', detail: '1225 task definitions checked', color: _labViolet),
      _LabStat(label: 'submission gate', value: '16', detail: 'ready_for_upload=false', color: _labAmber),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: stats.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: narrow ? 2 : 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: narrow ? 1.26 : 1.18,
      ),
      itemBuilder: (context, index) => stats[index],
    );
  }
}

class _PatternPanel extends StatelessWidget {
  const _PatternPanel();

  @override
  Widget build(BuildContext context) {
    return const _LabSection(
      title: 'On-device AI gallery pattern',
      subtitle: '从 chat demo 走向 task、skill、tool、runtime、benchmark surfaces；MobileCode 把这个模式用于手机端 AI coding harness。',
      icon: Icons.view_carousel_outlined,
      color: _labBlue,
      children: [
        _MethodRow(
          title: 'MobileCode Skill Spec',
          detail: 'SKILL.md + scripts/index.html + permission tokens + verifier contract。',
          icon: Icons.extension_outlined,
          color: _labMint,
        ),
        _MethodRow(
          title: 'Harness Task Registry',
          detail: '把 Tools、bottom sheets、pushed routes 和 skills 统一为 task metadata。',
          icon: Icons.schema_outlined,
          color: _labCyan,
        ),
        _MethodRow(
          title: 'Benchmark Lab',
          detail: '在 App 内展示 task set、evidence tier、verifier readiness 和 open gates。',
          icon: Icons.fact_check_outlined,
          color: _labViolet,
        ),
      ],
    );
  }
}

class _TaskRegistryPanel extends StatelessWidget {
  const _TaskRegistryPanel();

  @override
  Widget build(BuildContext context) {
    const tasks = [
      _RegistryItem('intake.file.open_with', 'External file preview', 'file_intake', 'partial', _labMint),
      _RegistryItem('edit.artifact.html', 'Artifact editor route', 'code_edit', 'partial', _labCyan),
      _RegistryItem('preview.html.basic', 'HTML WebView preview', 'preview_verification', 'partial', _labViolet),
      _RegistryItem('preview.markdown.basic', 'Markdown preview', 'preview_verification', 'planned', _labAmber),
      _RegistryItem('delivery.github.pages', 'GitHub Pages publish', 'github_delivery', 'partial', _labBlue),
      _RegistryItem('benchmark.lab.inspect', 'Benchmark Lab route', 'harness_evidence', 'prototype', _labRose),
    ];
    return _LabSection(
      title: 'Harness Task Registry',
      subtitle: '每个入口都要说明 category、surface、permission、runtime、verifier 和 evidence tier。',
      icon: Icons.account_tree_outlined,
      color: _labCyan,
      children: tasks,
    );
  }
}

class _EvidenceTierPanel extends StatelessWidget {
  const _EvidenceTierPanel();

  @override
  Widget build(BuildContext context) {
    const tiers = [
      _TierItem('T0', 'Offline fixture', '当前可计入草稿机械验证；不是 mobile device evidence。', _labMint),
      _TierItem('T1', 'Android emulator', '用于 UI/WebView 回归；不能替代真机。', _labCyan),
      _TierItem('T2', 'Android real device', '真实分享入口、Open with、低内存和 WebView 证据。', _labAmber),
      _TierItem('T3', 'iOS simulator', 'Mac/Xcode 回归层，用于 Document Picker 与 WebView。', _labViolet),
      _TierItem('T4', 'iOS real device', '真实 Open In、Files app、权限和后台行为。', _labRose),
      _TierItem('T5', 'GitHub sandbox', 'commit、Pages、Actions、artifact delivery。', _labBlue),
    ];
    return _LabSection(
      title: 'Evidence ladder',
      subtitle: '候选任务、离线 fixture、模拟器、真机和 GitHub sandbox 必须分层报告。',
      icon: Icons.stacked_line_chart_outlined,
      color: _labViolet,
      children: tiers,
    );
  }
}

class _EvidencePackPanel extends StatelessWidget {
  const _EvidencePackPanel();

  @override
  Widget build(BuildContext context) {
    return const _LabSection(
      title: 'Evidence pack index',
      subtitle: '把 README、论文草稿和 verifier 的证据链压到 App 内可读索引；仍保持只读，不把 readiness 包装成实验结果。',
      icon: Icons.inventory_2_outlined,
      color: _labBlue,
      children: [
        _EvidenceLinkRow(
          'Verifier readiness',
          '12 contracts · 1225 task definitions checked',
          'docs/mobile-harness-benchmark/reports/verifier-contract-readiness.md',
        ),
        _EvidenceLinkRow(
          'T0 smoke run',
          '60 tasks · 50 fixture passes · 10 typed GitHub blocks',
          'docs/mobile-harness-benchmark/runs/2026-06-06-smoke-v2-t0/summary.md',
        ),
        _EvidenceLinkRow(
          'Mobile evidence pack',
          '48 Android T2 / iOS T3 templates · counts_as_mobile_experiment=false',
          'docs/mobile-harness-benchmark/reports/mobile-evidence-pack-readiness.md',
        ),
        _EvidenceLinkRow(
          'Submission gate',
          'not upload-ready until mobile evidence, baselines and supplement are complete',
          'docs/mobile-harness-benchmark/reports/submission-readiness.md',
        ),
      ],
    );
  }
}

class _OpenGatePanel extends StatelessWidget {
  const _OpenGatePanel();

  @override
  Widget build(BuildContext context) {
    return const _LabSection(
      title: 'Open gates',
      subtitle: '当前 App 原型只展示 benchmark 状态；后续要跑真实 mobile tier、baseline 和 report export。',
      icon: Icons.warning_amber_outlined,
      color: _labAmber,
      children: [
        _GateRow('Real Android/iOS runs', '需要 device metadata、screenshot/logcat 或 Xcode log、run summary。'),
        _GateRow('Counted baseline comparison', '三组 baseline 需要模型锁、transcript、artifact、verifier output。'),
        _GateRow('Frozen subset runner', 'App 内选择 frozen subset，运行任务，导出 Markdown/JSON report。'),
        _GateRow('Screenshot-grade preview', 'metadata-only preview 不能包装成 bitmap screenshot evidence。'),
      ],
    );
  }
}

class _LabSection extends StatelessWidget {
  const _LabSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.children,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _LabPanel(
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: _labText, fontWeight: FontWeight.w900, fontSize: 17)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: _labMuted, height: 1.42, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children.expand((child) => [child, const SizedBox(height: 8)]).take(children.length * 2 - 1),
        ],
      ),
    );
  }
}

class _LabPanel extends StatelessWidget {
  const _LabPanel({
    required this.child,
    required this.color,
  });

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _labPanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.24)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.06),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _LabStat extends StatelessWidget {
  const _LabStat({
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
  });

  final String label;
  final String value;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900)),
          const Spacer(),
          Text(value, style: const TextStyle(color: _labText, fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _labMuted, fontSize: 11.5, height: 1.22)),
        ],
      ),
    );
  }
}

class _MethodRow extends StatelessWidget {
  const _MethodRow({
    required this.title,
    required this.detail,
    required this.icon,
    required this.color,
  });

  final String title;
  final String detail;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _InfoRow(
      leading: Icon(icon, color: color, size: 19),
      title: title,
      detail: detail,
      trailing: _StatusBadge(label: 'spec', color: color),
    );
  }
}

class _RegistryItem extends StatelessWidget {
  const _RegistryItem(this.id, this.title, this.category, this.state, this.color);

  final String id;
  final String title;
  final String category;
  final String state;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _InfoRow(
      leading: Icon(Icons.radio_button_checked_outlined, color: color, size: 18),
      title: title,
      detail: '$id · $category',
      trailing: _StatusBadge(label: state, color: color),
    );
  }
}

class _TierItem extends StatelessWidget {
  const _TierItem(this.tier, this.title, this.detail, this.color);

  final String tier;
  final String title;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _InfoRow(
      leading: _TierBadge(tier: tier, color: color),
      title: title,
      detail: detail,
      trailing: null,
    );
  }
}

class _GateRow extends StatelessWidget {
  const _GateRow(this.title, this.detail);

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return _InfoRow(
      leading: const Icon(Icons.lock_clock_outlined, color: _labAmber, size: 19),
      title: title,
      detail: detail,
      trailing: const _StatusBadge(label: 'open', color: _labAmber),
    );
  }
}

class _EvidenceLinkRow extends StatelessWidget {
  const _EvidenceLinkRow(this.title, this.detail, this.path);

  final String title;
  final String detail;
  final String path;

  @override
  Widget build(BuildContext context) {
    return _InfoRow(
      leading: const Icon(Icons.article_outlined, color: _labBlue, size: 19),
      title: title,
      detail: '$detail\n$path',
      trailing: const _StatusBadge(label: 'read-only', color: _labBlue),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.leading,
    required this.title,
    required this.detail,
    required this.trailing,
  });

  final Widget leading;
  final String title;
  final String detail;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _labPanelSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _labLine),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          leading,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: _labText, fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(detail, style: const TextStyle(color: _labMuted, fontSize: 12, height: 1.34)),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _LabPill extends StatelessWidget {
  const _LabPill({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w900)),
    );
  }
}

class _TierBadge extends StatelessWidget {
  const _TierBadge({
    required this.tier,
    required this.color,
  });

  final String tier;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Text(tier, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900)),
    );
  }
}
