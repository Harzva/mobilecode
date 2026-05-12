// lib/screens/preview_screen.dart
// Preview Screen — Full-screen preview with toolbar controls.
//
// Provides a dedicated screen for WebView preview with:
// - Device selector with categorized presets
// - Rotate, zoom, refresh controls
// - Editable URL bar
// - Split view toggle (editor + preview side by side)
// - Full-screen mode toggle
// - Loading states and error handling

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../services/preview_service.dart';
import '../widgets/webview_preview.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Preview Screen
// ═══════════════════════════════════════════════════════════════════════════

/// Full-screen preview screen with comprehensive toolbar controls.
///
/// Layout:
/// ```
/// ┌────────────────────────────────────────┐
/// │ [Device] [Rotate] [Refresh] [Split]   │  ← App Bar
/// ┌────────────────────────────────────────┐
/// │     ┌──────────────────────┐          │
/// │     │   WebView            │          │  ← Preview Area
/// │     │   (device frame)     │          │
/// └────────────────────────────────────────┘
/// ```
///
/// Usage:
/// ```dart
/// Navigator.push(context, MaterialPageRoute(
///   builder: (_) => PreviewScreen(
///     projectPath: '/path/to/html/project',
///     initialUrl: 'http://127.0.0.1:8080',
///     reloadStream: previewService.onFileChange,
///   ),
/// ));
/// ```
class PreviewScreen extends StatefulWidget {
  /// Project path being previewed.
  final String projectPath;

  /// Initial URL to load.
  final String? initialUrl;

  /// Stream for auto-reload.
  final Stream<void>? reloadStream;

  /// Initial device preset name.
  final String? initialDeviceName;

  /// Start in split view.
  final bool startInSplitView;

  /// Child widget for split view (e.g., editor panel).
  final Widget? splitViewChild;

  const PreviewScreen({
    super.key,
    required this.projectPath,
    this.initialUrl,
    this.reloadStream,
    this.initialDeviceName,
    this.startInSplitView = false,
    this.splitViewChild,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

// ── State ──────────────────────────────────────────────────────────────────

class _PreviewScreenState extends State<PreviewScreen> {
  late PreviewService _previewService;
  String? _previewUrl;
  bool _isServerStarting = false;
  String? _serverError;
  bool _isSplitView = false;
  double _splitRatio = 0.5;

  late String _selectedDeviceName;
  DeviceViewport get _selectedDevice =>
      PreviewService.devicePresets[_selectedDeviceName]!;

  bool _isFullScreen = false;

  @override
  void initState() {
    super.initState();
    _previewService = PreviewService();
    _selectedDeviceName = widget.initialDeviceName ?? 'iPhone 14';
    _isSplitView = widget.startInSplitView;

    if (widget.initialUrl != null) {
      _previewUrl = widget.initialUrl;
    } else {
      _startServer();
    }
  }

  Future<void> _startServer() async {
    setState(() { _isServerStarting = true; _serverError = null; });
    try {
      final url = await _previewService.startPreview(widget.projectPath);
      setState(() { _previewUrl = url; _isServerStarting = false; });
    } catch (e) {
      setState(() { _serverError = e.toString(); _isServerStarting = false; });
    }
  }

  void _toggleSplitView() {
    setState(() => _isSplitView = !_isSplitView);
    HapticFeedback.lightImpact();
  }

  void _toggleFullScreen() {
    setState(() => _isFullScreen = !_isFullScreen);
    if (_isFullScreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void _onDeviceSelected(String? name) {
    if (name == null) return;
    setState(() => _selectedDeviceName = name);
    HapticFeedback.lightImpact();
  }

  void _onSplitDragUpdate(DragUpdateDetails d, double totalW) {
    setState(() => _splitRatio =
      (_splitRatio + d.delta.dx / totalW).clamp(0.2, 0.8));
  }

  @override
  void dispose() {
    _previewService.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_isFullScreen) {
      return Scaffold(backgroundColor: AppTheme.background,
        body: SafeArea(child: Stack(children: [
          _buildPreviewContent(),
          Positioned(top: 12, right: 12,
            child: _floatingBtn(Icons.fullscreen_exit,
              'Exit Fullscreen', _toggleFullScreen)),
        ])),
      );
    }
    return Scaffold(backgroundColor: AppTheme.background,
      appBar: _buildAppBar(),
      body: SafeArea(child: _buildBody()),
    );
  }

  // ── App Bar ──────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppTheme.backgroundElevated,
      foregroundColor: AppTheme.textPrimary, elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(icon: const Icon(Icons.arrow_back, size: 20),
        onPressed: () => Navigator.of(context).pop(), tooltip: 'Back'),
      title: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.preview, size: 18, color: AppTheme.primary),
        const SizedBox(width: 8),
        const Text('Preview', style: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w600)),
        if (_previewUrl != null) ...[
          const SizedBox(width: 12),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: AppTheme.success.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6,
                decoration: const BoxDecoration(
                  color: AppTheme.success, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('Live', style: TextStyle(fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppTheme.success.withOpacity(0.9),
                fontFamily: AppTheme.fontCode)),
            ])),
        ],
      ]),
      actions: [
        _buildDeviceMenu(), const SizedBox(width: 4),
        _ABtn(icon: _isSplitView ? Icons.view_agenda : Icons.vertical_split,
          tip: _isSplitView ? 'Close Split' : 'Split View',
          onPressed: _toggleSplitView, active: _isSplitView),
        _ABtn(icon: Icons.fullscreen, tip: 'Fullscreen',
          onPressed: _toggleFullScreen),
        const SizedBox(width: 8),
      ],
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, color: AppTheme.divider)),
    );
  }

  Widget _buildDeviceMenu() {
    return PopupMenuButton<String>(
      tooltip: 'Select Device',
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.border)),
      offset: const Offset(0, 40),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_devIcon(_selectedDevice), size: 16, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(_selectedDeviceName, style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_down, size: 18, color: AppTheme.textSecondary),
        ])),
      itemBuilder: (ctx) => _deviceMenuItems(),
      onSelected: _onDeviceSelected,
    );
  }

  List<PopupMenuEntry<String>> _deviceMenuItems() {
    final entries = <PopupMenuEntry<String>>[];
    void addCat(String label) => entries.add(
      const PopupMenuDivider(height: 8));
    void addDevices(Iterable<bool> Function(DeviceViewport) filter) =>
      entries.addAll(PreviewService.devicePresets.entries
        .where((e) => filter(e.value))
        .map((e) => _devItem(e.key, e.value)));

    entries.add(const PopupMenuItem<String>(enabled: false, height: 32,
      child: Text('PHONES', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
        color: AppTheme.textTertiary, letterSpacing: 1))));
    addDevices((v) => v.isPhone);
    addCat('TABLETS');
    entries.add(const PopupMenuItem<String>(enabled: false, height: 32,
      child: Text('TABLETS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
        color: AppTheme.textTertiary, letterSpacing: 1))));
    addDevices((v) => v.isTablet);
    addCat('DESKTOP');
    entries.add(const PopupMenuItem<String>(enabled: false, height: 32,
      child: Text('DESKTOP', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
        color: AppTheme.textTertiary, letterSpacing: 1))));
    addDevices((v) => v.isDesktop);
    return entries;
  }

  PopupMenuItem<String> _devItem(String name, DeviceViewport vp) {
    final sel = name == _selectedDeviceName;
    return PopupMenuItem<String>(value: name, height: 40,
      child: Row(children: [
        Icon(_devIcon(vp), size: 16,
          color: sel ? AppTheme.primary : AppTheme.textSecondary),
        const SizedBox(width: 10),
        Expanded(child: Text(name, style: TextStyle(fontSize: 13,
          fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
          color: sel ? AppTheme.primary : AppTheme.textPrimary))),
        Text('${vp.width.toInt()}x${vp.height.toInt()}',
          style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary,
            fontFamily: AppTheme.fontCode)),
        if (sel) ...[const SizedBox(width: 8),
          const Icon(Icons.check, size: 16, color: AppTheme.primary)],
      ]));
  }

  // ── Body ─────────────────────────────────────────────────────────

  Widget _buildBody() {
    if (_isServerStarting) return _buildLoading();
    if (_serverError != null) return _buildError();
    if (_previewUrl == null) return _buildNoPreview();
    if (_isSplitView && widget.splitViewChild != null) return _buildSplit();
    return _buildPreviewContent();
  }

  Widget _buildPreviewContent() => WebViewPreview(
    key: ValueKey(_previewUrl),
    previewUrl: _previewUrl!,
    reloadStream: widget.reloadStream ?? _previewService.onFileChange,
    initialDevice: _selectedDevice,
    debuggingEnabled: true,
  );

  Widget _buildSplit() => LayoutBuilder(
    builder: (ctx, c) => Row(children: [
      SizedBox(width: c.maxWidth * _splitRatio,
        child: widget.splitViewChild),
      GestureDetector(
        onHorizontalDragUpdate: (d) => _onSplitDragUpdate(d, c.maxWidth),
        child: MouseRegion(cursor: SystemMouseCursors.resizeColumn,
          child: Container(width: 8,
            color: AppTheme.divider.withOpacity(0.3),
            child: Center(child: Container(width: 2, height: 32,
              decoration: BoxDecoration(
                color: AppTheme.textTertiary.withOpacity(0.5),
                borderRadius: BorderRadius.circular(1)))))),
      Expanded(child: _buildPreviewContent()),
    ]),
  );

  // ── Loading State ────────────────────────────────────────────────

  Widget _buildLoading() => Center(child: Column(
    mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 48, height: 48,
        child: CircularProgressIndicator(strokeWidth: 2,
          valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
          backgroundColor: AppTheme.primary.withOpacity(0.1))),
      const SizedBox(height: 24),
      Text('Starting Preview Server...',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: AppTheme.textPrimary)),
      const SizedBox(height: 8),
      Text('Serving: ${widget.projectPath}',
        style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary,
          fontFamily: AppTheme.fontCode)),
      const SizedBox(height: 24),
      _LoadingDots(),
    ]));

  // ── Error State ──────────────────────────────────────────────────

  Widget _buildError() => Center(child: Container(
    constraints: const BoxConstraints(maxWidth: 400),
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppTheme.error.withOpacity(0.1),
          shape: BoxShape.circle),
        child: Icon(Icons.error_outline, size: 48,
          color: AppTheme.error.withOpacity(0.7))),
      const SizedBox(height: 20),
      Text('Server Error',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: AppTheme.error)),
      const SizedBox(height: 8),
      Text(_serverError!, textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
      const SizedBox(height: 24),
      ElevatedButton.icon(onPressed: _startServer,
        icon: const Icon(Icons.refresh, size: 16), label: const Text('Retry')),
      const SizedBox(height: 8),
      TextButton(onPressed: () => Navigator.of(context).pop(),
        child: const Text('Go Back')),
    ])));

  // ── No Preview State ─────────────────────────────────────────────

  Widget _buildNoPreview() => Center(child: Column(
    mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.preview_outlined, size: 64,
        color: AppTheme.textTertiary.withOpacity(0.4)),
      const SizedBox(height: 16),
      Text('No Preview Available',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: AppTheme.textSecondary)),
      const SizedBox(height: 8),
      Text('Open an HTML project to start previewing',
        style: TextStyle(fontSize: 13,
          color: AppTheme.textTertiary.withOpacity(0.7))),
      const SizedBox(height: 24),
      ElevatedButton.icon(onPressed: _startServer,
        icon: const Icon(Icons.play_arrow, size: 16),
        label: const Text('Start Preview')),
    ]));

  // ── Helpers ──────────────────────────────────────────────────────

  Widget _floatingBtn(IconData icon, String tip, VoidCallback fn) =>
    Material(color: Colors.transparent,
      child: InkWell(onTap: fn, borderRadius: BorderRadius.circular(8),
        child: Container(padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.surface.withOpacity(0.8),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.border)),
          child: Icon(icon, size: 20, color: AppTheme.textPrimary))));

  IconData _devIcon(DeviceViewport vp) {
    if (vp.isPhone) return Icons.smartphone;
    if (vp.isTablet) return Icons.tablet_mac;
    return Icons.desktop_windows;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// App Bar Icon Button
// ═══════════════════════════════════════════════════════════════════════════

class _ABtn extends StatelessWidget {
  final IconData icon; final String tip; final VoidCallback onPressed;
  final bool active;
  const _ABtn({required this.icon, required this.tip,
    required this.onPressed, this.active = false});

  @override
  Widget build(BuildContext context) => Tooltip(message: tip,
    child: Material(color: Colors.transparent,
      child: InkWell(onTap: onPressed, borderRadius: BorderRadius.circular(8),
        child: Container(width: 40, height: 40,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: active ? BoxDecoration(
            color: AppTheme.primary.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8)) : null,
          alignment: Alignment.center,
          child: Icon(icon, size: 20,
            color: active ? AppTheme.primary : AppTheme.textSecondary)))));

// ═══════════════════════════════════════════════════════════════════════════
// Animated Loading Dots
// ═══════════════════════════════════════════════════════════════════════════

class _LoadingDots extends StatefulWidget {
  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with TickerProviderStateMixin {
  late final List<AnimationController> _ctrls;
  late final List<Animation<double>> _anims;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(3, (i) => AnimationController(
      vsync: this, duration: const Duration(milliseconds: 400))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          Future.delayed(Duration(milliseconds: i * 150), () {
            if (mounted) _ctrls[i].reverse();
          });
        } else if (s == AnimationStatus.dismissed) {
          Future.delayed(Duration(milliseconds: i * 150), () {
            if (mounted) _ctrls[i].forward();
          });
        }
      }));
    _anims = _ctrls.map((c) =>
      Tween<double>(begin: 0.3, end: 1.0).animate(c)).toList();
    for (var i = 0; i < _ctrls.length; i++) {
      Future.delayed(Duration(milliseconds: i * 150), () {
        if (mounted) _ctrls[i].forward();
      });
    }
  }

  @override
  void dispose() { for (final c in _ctrls) { c.dispose(); } super.dispose(); }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: List.generate(3, (i) => AnimatedBuilder(
      animation: _anims[i],
      builder: (ctx, ch) => Container(
        width: 8, height: 8, margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: AppTheme.primary.withOpacity(_anims[i].value),
          shape: BoxShape.circle),
    ))),
  );
}
