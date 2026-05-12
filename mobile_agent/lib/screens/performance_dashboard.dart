import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/fps_tracker.dart';
import '../providers/performance_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// PERFORMANCE DASHBOARD — Real-time performance visibility
// ═══════════════════════════════════════════════════════════════════════════════

/// A full-screen dashboard that visualises FPS, memory, frame times and
/// offers one-click optimisations.
class PerformanceDashboard extends ConsumerStatefulWidget {
  const PerformanceDashboard({super.key});

  @override
  ConsumerState<PerformanceDashboard> createState() =>
      _PerformanceDashboardState();
}

// ── State ─────────────────────────────────────────────────────────────────────

class _PerformanceDashboardState extends ConsumerState<PerformanceDashboard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  bool _smoothMode = false;
  bool _lowMemMode = false;
  StreamSubscription<FpsData>? _fpsSub;

  @override
  void initState() {
    super.initState();
    FpsTracker().startTracking();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    // Pulse on each FPS tick
    _fpsSub = FpsTracker().fpsStream.listen((_) {
      if (mounted) {
        _pulseController..reset()..forward();
      }
    });
  }

  @override
  void dispose() {
    _fpsSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final fpsAsync = ref.watch(fpsStreamProvider);
    final memAsync = ref.watch(memoryUsageProvider);
    final suggestions = ref.watch(performanceSuggestionsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1D24),
        elevation: 0,
        title: const Text('性能监控',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            tooltip: '重置数据',
            onPressed: () {
              FpsTracker().reset();
              ref.read(lastFpsDataProvider.notifier).state = null;
            },
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white70),
            onPressed: _showInfoDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFpsGauge(fpsAsync),
              const SizedBox(height: 16),
              _buildStatsGrid(fpsAsync, memAsync),
              const SizedBox(height: 16),
              _buildFrameTimeGraph(fpsAsync),
              const SizedBox(height: 16),
              _buildMemoryBar(memAsync),
              const SizedBox(height: 16),
              _buildSuggestions(suggestions),
              const SizedBox(height: 16),
              _buildQuickActions(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ── FPS Gauge (circular) ─────────────────────────────────────────────

  Widget _buildFpsGauge(AsyncValue<FpsData> fpsAsync) {
    final data = fpsAsync.valueOrNull;
    final fps = data?.currentFps ?? 0;
    final grade = data?.grade ?? FpsGrade.poor;
    final color = _gradeColor(grade);
    final size = math.min(MediaQuery.of(context).size.width * 0.35, 160.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(color: color),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, child) => Transform.scale(
              scale: data != null ? Tween<double>(begin: 1.0, end: 1.06)
                  .animate(CurvedAnimation(parent: _pulseController,
                      curve: Curves.easeOut)).value : 1.0,
              child: child,
            ),
            child: SizedBox(
              width: size,
              height: size,
              child: CustomPaint(
                painter: _FpsGaugePainter(
                    fps: fps, maxFps: 60, color: color),
                child: Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(data != null ? '${fps.toStringAsFixed(0)}' : '--',
                      style: TextStyle(color: color, fontSize: 38,
                          fontWeight: FontWeight.bold)),
                    const Text('FPS', style: TextStyle(
                        color: Colors.white38, fontSize: 12)),
                  ],
                )),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (data != null) ...[
                Row(children: [
                  Text(data.gradeEmoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                  _gradeBadge(data.gradeLabel, color),
                ]),
                const SizedBox(height: 10),
                _infoRow('平均 FPS', data.averageFps.toStringAsFixed(1)),
                _infoRow('掉帧总数', '${data.droppedFrames}'),
                _infoRow('95% 帧时间',
                    '${data.percentile95FrameTimeMs.toStringAsFixed(1)} ms'),
                _infoRow('严重卡顿', '${data.jankSpikeCount} 次',
                    valueColor: data.jankSpikeCount > 0
                        ? Colors.redAccent : Colors.white70),
              ] else
                _skeletonBox(width: 100, height: 16),
            ],
          )),
        ],
      ),
    );
  }

  // ── Stats Grid (2×2) ─────────────────────────────────────────────────

  Widget _buildStatsGrid(AsyncValue<FpsData> fpsAsync,
      AsyncValue<MemoryInfo> memAsync) {
    final fps = fpsAsync.valueOrNull;
    final mem = memAsync.valueOrNull;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.5,
      children: [
        _statCard('当前 FPS', fps?.currentFps.toStringAsFixed(0) ?? '--',
          'fps', Icons.speed, fps != null ? _fpsColor(fps.currentFps) : Colors.grey),
        _statCard('平均 FPS', fps?.averageFps.toStringAsFixed(1) ?? '--',
          'fps', Icons.trending_up, fps != null ? _fpsColor(fps.averageFps) : Colors.grey),
        _statCard('掉帧数', fps != null ? '${fps.droppedFrames}' : '--',
          'frames', Icons.warning_amber,
          fps != null && fps.droppedFrames > 10 ? Colors.orange : Colors.green),
        _statCard('内存占用', mem != null ? mem.usedMB.toStringAsFixed(0) : '--',
          'MB', Icons.memory,
          mem != null ? _memColor(mem.usedRatio) : Colors.grey),
      ],
    );
  }

  // ── Frame Time Graph ─────────────────────────────────────────────────

  Widget _buildFrameTimeGraph(AsyncValue<FpsData> fpsAsync) {
    final ftHistory = FpsTracker().frameTimeHistory;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('帧时间趋势',
            style: TextStyle(color: Colors.white70, fontSize: 13,
                fontWeight: FontWeight.w600)),
          if (fpsAsync.valueOrNull != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _fpsColor(fpsAsync.valueOrNull!.currentFps)
                    .withOpacity(0.15),
                borderRadius: BorderRadius.circular(6)),
              child: Text(
                '${fpsAsync.valueOrNull!.frameTimeMs.toStringAsFixed(1)} ms',
                style: TextStyle(
                  color: _fpsColor(fpsAsync.valueOrNull!.currentFps),
                  fontSize: 11, fontWeight: FontWeight.w600)),
            ),
        ]),
        const SizedBox(height: 10),
        SizedBox(height: 120,
          child: ftHistory.isEmpty
            ? Center(child: Text('等待数据...',
                style: TextStyle(color: Colors.white.withOpacity(0.25))))
            : CustomPaint(
                size: const Size(double.infinity, 120),
                painter: _FrameTimePainter(ftHistory),
              ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          _legendDot(Colors.greenAccent, '< 16ms'),
          const SizedBox(width: 10),
          _legendDot(Colors.orangeAccent, '16-33ms'),
          const SizedBox(width: 10),
          _legendDot(Colors.redAccent, '> 33ms'),
        ]),
      ]),
    );
  }

  // ── Memory Usage Bar ─────────────────────────────────────────────────

  Widget _buildMemoryBar(AsyncValue<MemoryInfo> memAsync) {
    return memAsync.when(
      data: (m) => Container(
        padding: const EdgeInsets.all(14),
        decoration: _cardDecoration(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('内存使用',
              style: TextStyle(color: Colors.white70, fontSize: 13,
                  fontWeight: FontWeight.w600)),
            Text('${m.usedMB.toStringAsFixed(0)} / ${m.totalMB.toStringAsFixed(0)} MB',
              style: TextStyle(color: _memColor(m.usedRatio), fontSize: 12,
                  fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: m.usedRatio,
              backgroundColor: Colors.white.withOpacity(0.06),
              valueColor: AlwaysStoppedAnimation<Color>(_memColor(m.usedRatio)),
              minHeight: 10,
            ),
          ),
          const SizedBox(height: 6),
          Text(_memStatus(m.usedRatio),
            style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 11)),
        ]),
      ),
      loading: () => _skeletonCard(),
      error: (_, __) => _skeletonCard(),
    );
  }

  // ── Performance Suggestions ──────────────────────────────────────────

  Widget _buildSuggestions(List<PerformanceSuggestion> suggestions) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.lightbulb_outline, size: 16, color: Colors.amber.shade400),
          const SizedBox(width: 6),
          const Text('优化建议',
            style: TextStyle(color: Colors.white70, fontSize: 13,
                fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 10),
        if (suggestions.isEmpty)
          Text('暂无优化建议，性能表现良好！',
            style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 12))
        else
          ...suggestions.map((s) => _suggestionTile(s)),
      ]),
    );
  }

  // ── Quick Actions ────────────────────────────────────────────────────

  Widget _buildQuickActions() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('快速操作',
        style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 13,
            fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _actionBtn('清理缓存', Icons.cleaning_services_outlined,
          Colors.blueAccent, _clearCache)),
        const SizedBox(width: 8),
        Expanded(child: _actionBtn(
          _smoothMode ? '关闭流畅模式' : '切换流畅模式',
          _smoothMode ? Icons.toggle_on : Icons.toggle_off_outlined,
          _smoothMode ? Colors.green : Colors.orangeAccent, _toggleSmooth)),
        const SizedBox(width: 8),
        Expanded(child: _actionBtn(
          _lowMemMode ? '关闭省内存' : '低内存模式',
          _lowMemMode ? Icons.memory : Icons.memory_outlined,
          _lowMemMode ? Colors.purpleAccent : Colors.tealAccent, _toggleLowMem)),
      ]),
    ]);
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  Widget _statCard(String label, String value, String unit, IconData icon,
      Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Expanded(child: Text(label,
            style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 11),
            overflow: TextOverflow.ellipsis)),
        ]),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic, children: [
          Text(value, style: TextStyle(color: color, fontSize: 24,
              fontWeight: FontWeight.bold)),
          const SizedBox(width: 3),
          Text(unit, style: TextStyle(
              color: Colors.white.withOpacity(0.3), fontSize: 10)),
        ]),
      ]),
    );
  }

  Widget _suggestionTile(PerformanceSuggestion s) {
    final (color, icon) = switch (s.priority) {
      SuggestionPriority.critical => (Colors.redAccent, Icons.priority_high),
      SuggestionPriority.warning => (Colors.orangeAccent, Icons.warning_amber),
      SuggestionPriority.info => (Colors.blueAccent, Icons.info_outline),
      SuggestionPriority.tip => (Colors.greenAccent, Icons.check_circle_outline),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: s.action != null ? () => s.action!(context) : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.07),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.18)),
          ),
          child: Row(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(s.message,
              style: TextStyle(color: Colors.white.withOpacity(0.82),
                  fontSize: 12))),
            if (s.action != null)
              Icon(Icons.arrow_forward_ios, size: 10,
                  color: color.withOpacity(0.5)),
          ]),
        ),
      ),
    );
  }

  Widget _actionBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 5),
          Text(label, style: TextStyle(color: color.withOpacity(0.85),
              fontSize: 10, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  Widget _gradeBadge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(16)),
    child: Text(label, style: TextStyle(color: color, fontSize: 12,
        fontWeight: FontWeight.w600)),
  );

  Widget _infoRow(String label, String value, {Color? valueColor}) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: Colors.white45, fontSize: 11)),
      Text(value, style: TextStyle(color: valueColor ?? Colors.white70,
          fontSize: 11, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _legendDot(Color color, String label) => Row(mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 7, height: 7,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 10)),
    ]);

  Widget _skeletonBox({required double width, required double height}) =>
    Container(width: width, height: height,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(4)));

  Widget _skeletonCard() => Container(
    padding: const EdgeInsets.all(14),
    decoration: _cardDecoration(),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _skeletonBox(width: 80, height: 14),
      const SizedBox(height: 10),
      _skeletonBox(width: double.infinity, height: 10),
    ]));

  static BoxDecoration _cardDecoration({Color? color}) => BoxDecoration(
    color: const Color(0xFF1A1D24),
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: color?.withOpacity(0.15) ?? Colors.white10),
    boxShadow: color != null ? [
      BoxShadow(color: color.withOpacity(0.1), blurRadius: 16, spreadRadius: 2),
    ] : null,
  );

  // ── Actions ──────────────────────────────────────────────────────────

  void _clearCache() {
    imageCache.clear();
    imageCache.clearLiveImages();
    _snack('缓存已清理');
    ref.invalidate(performanceSuggestionsProvider);
  }

  void _toggleSmooth() {
    setState(() => _smoothMode = !_smoothMode);
    _snack(_smoothMode ? '流畅模式已开启' : '流畅模式已关闭');
  }

  void _toggleLowMem() {
    setState(() => _lowMemMode = !_lowMemMode);
    _snack(_lowMemMode ? '低内存模式已开启' : '低内存模式已关闭');
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating));

  void _showInfoDialog() => showDialog(context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A1D24),
      title: const Text('关于性能监控', style: TextStyle(color: Colors.white)),
      content: const Text(
        '实时监控应用帧率、内存使用和渲染性能。\n\n'
        '• FPS: 每秒渲染帧数\n• 掉帧: 超过 16.67ms 的帧\n'
        '• 内存: 当前内存占用\n• 帧时间: 每帧渲染耗时',
        style: TextStyle(color: Colors.white70, fontSize: 13)),
      actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(),
        child: const Text('关闭'))],
    ));

  // ── Color helpers ────────────────────────────────────────────────────

  static Color _fpsColor(double fps) {
    if (fps >= 55) return const Color(0xFF4CAF50);
    if (fps >= 45) return const Color(0xFF8BC34A);
    if (fps >= 30) return const Color(0xFFFFC107);
    return const Color(0xFFF44336);
  }

  static Color _gradeColor(FpsGrade g) => switch (g) {
    FpsGrade.excellent => const Color(0xFF4CAF50),
    FpsGrade.good => const Color(0xFF8BC34A),
    FpsGrade.fair => const Color(0xFFFFC107),
    FpsGrade.poor => const Color(0xFFF44336),
  };

  static Color _memColor(double r) {
    if (r < 0.5) return const Color(0xFF4CAF50);
    if (r < 0.75) return const Color(0xFFFFC107);
    return const Color(0xFFF44336);
  }

  static String _memStatus(double r) {
    if (r < 0.5) return '内存使用正常';
    if (r < 0.75) return '内存使用偏高，建议关注';
    return '内存使用过高，建议优化';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FPS GAUGE PAINTER — Circular arc with progress
// ═══════════════════════════════════════════════════════════════════════════════

class _FpsGaugePainter extends CustomPainter {
  _FpsGaugePainter({required this.fps, required this.maxFps, required this.color});

  final double fps;
  final double maxFps;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 8;
    final sw = r * 0.11;
    const start = math.pi * 0.75;
    const sweep = math.pi * 1.5;

    // Background arc
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r), start, sweep, false,
      Paint()..color = Colors.white.withOpacity(0.07)
        ..strokeWidth = sw..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);

    // Progress arc with gradient
    final progress = (fps.clamp(0.0, maxFps) / maxFps);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r), start, sweep * progress, false,
      Paint()..strokeWidth = sw..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: start, endAngle: start + sweep * progress,
          colors: [color.withOpacity(0.5), color]).createShader(
            Rect.fromCircle(center: c, radius: r)));

    // Tick marks
    final tick = Paint()..color = Colors.white.withOpacity(0.12)..strokeWidth = 1.2;
    for (int i = 0; i <= 6; i++) {
      final a = start + (sweep * i / 6);
      final ir = r - sw - 3;
      final or = r - sw + 2;
      final p1 = c + Offset(math.cos(a) * ir, math.sin(a) * ir);
      final p2 = c + Offset(math.cos(a) * or, math.sin(a) * or);
      canvas.drawLine(p1, p2, tick);
    }
  }

  @override
  bool shouldRepaint(covariant _FpsGaugePainter old) =>
    old.fps != fps || old.color != color;
}

// ═══════════════════════════════════════════════════════════════════════════════
// FRAME TIME CHART PAINTER — Cubic bezier line chart
// ═══════════════════════════════════════════════════════════════════════════════

class _FrameTimePainter extends CustomPainter {
  _FrameTimePainter(this.data);
  final List<double> data;

  static Color _ftColor(double t) {
    if (t <= 16) return Colors.greenAccent;
    if (t <= 33) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final maxV = math.max(33.0, data.reduce(math.max));
    final drawH = size.height;

    // Grid lines at 16ms and 33ms
    final grid = Paint()..color = Colors.white.withOpacity(0.05)..strokeWidth = 1;
    for (final th in [16.0, 33.0]) {
      final y = drawH - (th / maxV) * drawH;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // Build cubic path
    final path = Path();
    final fill = Path();
    for (int i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * size.width;
      final y = drawH - (data[i] / maxV) * drawH;
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, drawH);
        fill.lineTo(x, y);
      } else {
        final px = ((i - 1) / (data.length - 1)) * size.width;
        final py = drawH - (data[i - 1] / maxV) * drawH;
        final cp = px + (x - px) * 0.5;
        path.cubicTo(cp, py, cp, y, x, y);
        fill.cubicTo(cp, py, cp, y, x, y);
      }
    }

    // Gradient fill
    fill.lineTo(size.width, drawH);
    fill.close();
    canvas.drawPath(fill, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [_ftColor(data.last).withOpacity(0.3),
                 _ftColor(data.last).withOpacity(0.02)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));

    // Line
    canvas.drawPath(path, Paint()
      ..color = _ftColor(data.last)..strokeWidth = 2.2
      ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);

    // End dot
    final lx = size.width;
    final ly = drawH - (data.last / maxV) * drawH;
    canvas.drawCircle(Offset(lx, ly), 4,
      Paint()..color = _ftColor(data.last).withOpacity(0.25));
    canvas.drawCircle(Offset(lx, ly), 2.5,
      Paint()..color = _ftColor(data.last));
  }

  @override
  bool shouldRepaint(covariant _FrameTimePainter old) =>
    old.data.length != data.length ||
    (old.data.isNotEmpty && data.isNotEmpty && old.data.last != data.last);
}
