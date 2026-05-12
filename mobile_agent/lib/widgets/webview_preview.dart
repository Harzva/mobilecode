// lib/widgets/webview_preview.dart
// WebView Preview Widget — Embedded browser with device simulation.
//
// Wraps a WebView in a simulated device frame with support for:
// - Device viewport simulation (iPhone, iPad, Pixel, Desktop)
// - Portrait / landscape rotation
// - Pinch-to-zoom and zoom controls
// - Auto-reload on file changes
// - URL address bar and refresh controls
// - Dark themed device bezels with notch/camera cutouts

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/theme.dart';
import '../services/preview_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// WebView Preview Widget
// ═══════════════════════════════════════════════════════════════════════════

/// Embeds a WebView for live HTML preview with device simulation.
///
/// Features device frame simulation with bezels, notch, auto-reload
/// on file change, zoom controls, rotate, device selector, URL bar.
///
/// Usage:
/// ```dart
/// WebViewPreview(
///   previewUrl: 'http://127.0.0.1:8080',
///   reloadStream: previewService.onFileChange,
///   initialDevice: PreviewService.devicePresets['iPhone 14'],
/// )
/// ```
class WebViewPreview extends StatefulWidget {
  /// URL to load in the WebView preview.
  final String previewUrl;

  /// Stream that triggers reload when an event fires.
  final Stream<void>? reloadStream;

  /// Initial device viewport. Defaults to iPhone 14.
  final DeviceViewport? initialDevice;

  /// Initial zoom level (1.0 = 100%).
  final double initialZoom;

  /// Show device frame chrome. When false, renders edge-to-edge.
  final bool showDeviceFrame;

  const WebViewPreview({
    super.key,
    required this.previewUrl,
    this.reloadStream,
    this.initialDevice,
    this.initialZoom = 1.0,
    this.showDeviceFrame = true,
  });

  @override
  State<WebViewPreview> createState() => _WebViewPreviewState();
}

// ── State ──────────────────────────────────────────────────────────────────

class _WebViewPreviewState extends State<WebViewPreview>
    with TickerProviderStateMixin {
  late WebViewController _controller;
  late DeviceViewport _device;
  bool _isLandscape = false;
  double _zoom = 1.0;
  bool _isLoading = true;
  double _loadProgress = 0.0;
  String _currentUrl = '';
  StreamSubscription<void>? _reloadSub;
  final TextEditingController _urlCtrl = TextEditingController();
  final FocusNode _urlFocus = FocusNode();
  bool _isUrlEditing = false;
  bool _hasError = false;
  String _errorMsg = '';

  late AnimationController _rotateAnim;

  DeviceViewport get _effDevice => _isLandscape ? _device.landscape : _device;
  double get _frameW => _effDevice.width * _zoom;
  double get _frameH => _effDevice.height * _zoom;

  @override
  void initState() {
    super.initState();
    _device = widget.initialDevice ??
        PreviewService.devicePresets['iPhone 14']!;
    _zoom = widget.initialZoom;
    _currentUrl = widget.previewUrl;

    _rotateAnim = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300),
    );

    _initWebView();
    _subscribeToReload();
  }

  /// Console messages captured from the WebView's JavaScript console.
  final List<ConsoleMessage> _consoleMessages = [];

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppTheme.editorBackground)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) => setState(() {
          _isLoading = true; _loadProgress = 0; _hasError = false;
        }),
        onProgress: (p) => setState(() => _loadProgress = p / 100.0),
        onPageFinished: (url) {
          setState(() { _isLoading = false; _currentUrl = url;
            _urlCtrl.text = url; });
          _injectViewportMeta();
          _injectConsoleBridge();
        },
        onWebResourceError: (e) => setState(() {
          _isLoading = false; _hasError = true;
          _errorMsg = 'Error ${e.errorCode}: ${e.description}';
        }),
      ))
      ..addJavaScriptChannel(
        'MobileCodeBridge',
        onMessageReceived: (JavaScriptMessage msg) {
          _handleJsMessage(msg.message);
        },
      )
      ..loadRequest(Uri.parse(widget.previewUrl));
    _urlCtrl.text = widget.previewUrl;
  }

  /// Inject a JavaScript bridge to capture console.log / warn / error.
  Future<void> _injectConsoleBridge() async {
    try {
      await _controller.runJavaScript('''
        (function() {
          const origLog = console.log;
          const origWarn = console.warn;
          const origError = console.error;
          console.log = function() {
            const msg = Array.from(arguments).map(String).join(' ');
            MobileCodeBridge.postMessage(JSON.stringify({type:'log',msg:msg}));
            origLog.apply(console, arguments);
          };
          console.warn = function() {
            const msg = Array.from(arguments).map(String).join(' ');
            MobileCodeBridge.postMessage(JSON.stringify({type:'warn',msg:msg}));
            origWarn.apply(console, arguments);
          };
          console.error = function() {
            const msg = Array.from(arguments).map(String).join(' ');
            MobileCodeBridge.postMessage(JSON.stringify({type:'error',msg:msg}));
            origError.apply(console, arguments);
          };
        })();
      ''');
    } catch (_) {}
  }

  void _handleJsMessage(String raw) {
    try {
      final msg = ConsoleMessage.parse(raw);
      _consoleMessages.add(msg);
      debugPrint('[WebViewPreview] [${msg.level}] ${msg.message}');
    } catch (_) {
      debugPrint('[WebViewPreview] Console: \$raw');
    }
  }

  Future<void> _injectViewportMeta() async {
    try {
      await _controller.runJavaScript(
        '(function(){var m=document.querySelector("meta[name=viewport]");'
        'if(!m){m=document.createElement("meta");m.name="viewport";'
        'document.head.appendChild(m)}'
        'm.content="width=device-width,initial-scale=1,"'
        '"maximum-scale=5.0,user-scalable=yes"})();');
    } catch (_) {}
  }

  void _subscribeToReload() {
    if (widget.reloadStream != null) {
      _reloadSub = widget.reloadStream!.listen((_) => _reload());
    }
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _hasError = false; });
    try { await _controller.reload(); HapticFeedback.lightImpact(); }
    catch (e) { debugPrint('[WebViewPreview] Reload error: \$e'); }
  }

  void _rotate() { setState(() => _isLandscape = !_isLandscape);
    _rotateAnim.forward(from: 0); HapticFeedback.lightImpact(); }
  void _zoomIn() { setState(() => _zoom = math.min(_zoom + 0.1, 3.0));
    HapticFeedback.lightImpact(); }
  void _zoomOut() { setState(() => _zoom = math.max(_zoom - 0.1, 0.3));
    HapticFeedback.lightImpact(); }
  void _zoomReset() { setState(() => _zoom = 1.0); HapticFeedback.lightImpact(); }

  void _onDeviceChanged(DeviceViewport? d) {
    if (d == null) return; setState(() => _device = d);
    HapticFeedback.lightImpact();
  }

  Future<void> _navigateToUrl(String url) async {
    if (url.isEmpty) return; final uri = Uri.tryParse(url);
    if (uri == null) return; await _controller.loadRequest(uri);
    _urlFocus.unfocus(); setState(() => _isUrlEditing = false);
  }

  Future<void> _goBack() async { if (await _controller.canGoBack())
    await _controller.goBack(); }
  Future<void> _goForward() async { if (await _controller.canGoForward())
    await _controller.goForward(); }

  @override
  void dispose() {
    _reloadSub?.cancel(); _rotateAnim.dispose();
    _urlCtrl.dispose(); _urlFocus.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _buildToolbar(),
      if (_isLoading) _buildProgressBar(),
      Expanded(child: Center(
        child: _hasError ? _buildErrorView() : _buildPreviewArea(),
      )),
    ]);
  }

  // ── Toolbar ──────────────────────────────────────────────────────

  Widget _buildToolbar() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppTheme.backgroundElevated,
        border: Border(bottom: BorderSide(
          color: AppTheme.divider.withOpacity(0.6))),
      ),
      child: Row(children: [
        const SizedBox(width: 8),
        _buildDeviceSelector(),
        _div(),
        _btn(Icons.screen_rotation, 'Rotate', _rotate),
        _div(),
        _btn(Icons.arrow_back_ios, 'Back', _goBack),
        _btn(Icons.arrow_forward_ios, 'Forward', _goForward),
        _btn(_isLoading ? Icons.close : Icons.refresh,
          _isLoading ? 'Stop' : 'Refresh',
          _isLoading ? () => _controller.reload() : _reload),
        _div(),
        _btn(Icons.zoom_out, 'Zoom Out', _zoomOut),
        Container(constraints: const BoxConstraints(minWidth: 36),
          alignment: Alignment.center,
          child: Text('${_zoom.toStringAsFixed(1)}x',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary, fontFamily: AppTheme.fontCode))),
        _btn(Icons.zoom_in, 'Zoom In', _zoomIn),
        _btn(Icons.fit_screen, 'Reset Zoom', _zoomReset),
        const Spacer(),
        Expanded(flex: 2, child: _buildUrlBar()),
        const SizedBox(width: 8),
      ]),
    );
  }

  Widget _buildDeviceSelector() {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<DeviceViewport>(
          value: _device, isDense: true,
          icon: const Icon(Icons.arrow_drop_down,
            size: 18, color: AppTheme.textSecondary),
          dropdownColor: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary,
            fontFamily: AppTheme.fontBody),
          items: PreviewService.devicePresets.entries.map((e) {
            final vp = e.value;
            IconData icon;
            if (vp.isPhone) icon = Icons.smartphone;
            else if (vp.isTablet) icon = Icons.tablet_mac;
            else icon = Icons.desktop_windows;
            return DropdownMenuItem(value: vp,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 14, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text(e.key, style: const TextStyle(
                  fontSize: 12, color: AppTheme.textPrimary)),
                const SizedBox(width: 6),
                Text('${vp.width.toInt()}x${vp.height.toInt()}',
                  style: const TextStyle(fontSize: 10,
                    color: AppTheme.textTertiary,
                    fontFamily: AppTheme.fontCode)),
              ]));
          }).toList(),
          onChanged: _onDeviceChanged,
          selectedItemBuilder: (ctx) =>
            PreviewService.devicePresets.entries.map((e) {
              IconData i; final vp = e.value;
              if (vp.isPhone) i = Icons.smartphone;
              else if (vp.isTablet) i = Icons.tablet_mac;
              else i = Icons.desktop_windows;
              return Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(i, size: 14, color: AppTheme.primary),
                const SizedBox(width: 6),
                Text(e.key, style: const TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
              ]);
            }).toList(),
        ),
      ),
    );
  }

  Widget _buildUrlBar() {
    return Container(height: 34,
      decoration: BoxDecoration(color: AppTheme.surfaceInput,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _isUrlEditing
          ? AppTheme.primary.withOpacity(0.5) : AppTheme.border, width: 1)),
      child: Row(children: [
        const SizedBox(width: 8),
        Icon(Icons.lock_outline, size: 12,
          color: _currentUrl.startsWith('https')
            ? AppTheme.success : AppTheme.textTertiary),
        const SizedBox(width: 6),
        Expanded(child: TextField(controller: _urlCtrl, focusNode: _urlFocus,
          style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary,
            fontFamily: AppTheme.fontCode),
          decoration: const InputDecoration(isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 8),
            hintText: 'Enter URL...',
            hintStyle: TextStyle(fontSize: 12, color: AppTheme.textTertiary)),
          onTap: () => setState(() => _isUrlEditing = true),
          onSubmitted: _navigateToUrl, textInputAction: TextInputAction.go)),
        if (_isUrlEditing)
          InkWell(onTap: () { _urlFocus.unfocus();
            setState(() => _isUrlEditing = false); },
            child: const Padding(padding: EdgeInsets.all(6),
              child: Icon(Icons.close, size: 14, color: AppTheme.textTertiary))),
        const SizedBox(width: 4),
      ]));
  }

  Widget _buildProgressBar() => Container(height: 2, color: AppTheme.background,
    child: LinearProgressIndicator(value: _loadProgress,
      backgroundColor: Colors.transparent,
      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent),
      minHeight: 2));

  // ── Preview Area ─────────────────────────────────────────────────

  Widget _buildPreviewArea() {
    if (!widget.showDeviceFrame) {
      return InteractiveViewer(boundaryMargin: const EdgeInsets.all(20),
        minScale: 0.3, maxScale: 3.0,
        child: WebViewWidget(controller: _controller));
    }
    return InteractiveViewer(boundaryMargin: const EdgeInsets.all(40),
      minScale: 0.2, maxScale: 3.0,
      child: Center(child: AnimatedBuilder(
        animation: _rotateAnim,
        builder: (ctx, child) => _DeviceFrame(
          width: _frameW, height: _frameH,
          dpr: _effDevice.devicePixelRatio,
          isPhone: _effDevice.isPhone,
          child: WebViewWidget(controller: _controller),
        ),
      )),
    );
  }

  Widget _buildErrorView() {
    return Container(padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.error.withOpacity(0.3))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline, size: 48,
          color: AppTheme.error.withOpacity(0.6)),
        const SizedBox(height: 12),
        Text('Preview Error', style: Theme.of(ctx).textTheme.titleMedium
          ?.copyWith(color: AppTheme.error)),
        const SizedBox(height: 8),
        Text(_errorMsg, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        const SizedBox(height: 16),
        ElevatedButton.icon(onPressed: _reload,
          icon: const Icon(Icons.refresh, size: 16), label: const Text('Retry')),
      ]));
  }

  // ── Helpers ──────────────────────────────────────────────────────

  BuildContext get ctx => context;

  Widget _btn(IconData icon, String tip, VoidCallback? fn) => Tooltip(
    message: tip, child: Material(color: Colors.transparent,
      child: InkWell(onTap: fn, borderRadius: BorderRadius.circular(6),
        child: Container(width: 34, height: 34,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          alignment: Alignment.center,
          child: Icon(icon, size: 16, color: AppTheme.textSecondary)))));

  Widget _div() => Container(width: 1, height: 20,
    margin: const EdgeInsets.symmetric(horizontal: 4), color: AppTheme.divider);

  /// Clear captured console messages.
  void clearConsole() => _consoleMessages.clear();

  /// Get captured console messages.
  List<ConsoleMessage> get consoleMessages =>
      List.unmodifiable(_consoleMessages);
}

// ═══════════════════════════════════════════════════════════════════════════
// Console Message Model
// ═══════════════════════════════════════════════════════════════════════════

/// A console message captured from the WebView's JavaScript runtime.
class ConsoleMessage {
  /// Log level: 'log', 'warn', 'error', or 'info'.
  final String level;

  /// The message text.
  final String message;

  /// When the message was captured.
  final DateTime timestamp;

  const ConsoleMessage({
    required this.level,
    required this.message,
    required this.timestamp,
  });

  factory ConsoleMessage.parse(String raw) {
    try {
      // Simple JSON parsing for {type:"log",msg:"text"}
      final typeMatch = RegExp(r'"type":"([^"]+)"').firstMatch(raw);
      final msgMatch = RegExp(r'"msg":"([^"]*)"').firstMatch(raw);
      return ConsoleMessage(
        level: typeMatch?.group(1) ?? 'log',
        message: msgMatch?.group(1) ?? raw,
        timestamp: DateTime.now(),
      );
    } catch (_) {
      return ConsoleMessage(
        level: 'log', message: raw, timestamp: DateTime.now());
    }
  }

  /// Whether this is an error-level message.
  bool get isError => level == 'error';

  /// Whether this is a warning-level message.
  bool get isWarning => level == 'warn';

  @override
  String toString() => '[\$level] \$message';
}

// ═══════════════════════════════════════════════════════════════════════════
// Device Frame Widget
// ═══════════════════════════════════════════════════════════════════════════

/// Realistic device frame with bezels, notch, and home indicator.
class _DeviceFrame extends StatelessWidget {
  final double width, height, dpr;
  final bool isPhone;
  final Widget child;

  const _DeviceFrame({required this.width, required this.height,
    required this.dpr, required this.isPhone, required this.child});

  @override
  Widget build(BuildContext context) {
    final bezel = isPhone ? 14.0 : 8.0;
    final radius = isPhone ? 36.0 : 8.0;

    return Container(
      width: width + bezel * 2,
      height: height + bezel * 2 + (isPhone ? 8.0 : 0.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a1a),
        borderRadius: BorderRadius.circular(radius + 4),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.4),
            blurRadius: 30, spreadRadius: 2, offset: const Offset(0, 10)),
          BoxShadow(color: Colors.black.withOpacity(0.2),
            blurRadius: 60, spreadRadius: 10, offset: const Offset(0, 20)),
        ],
        border: Border.all(color: const Color(0xFF3a3a3a), width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(alignment: Alignment.center, children: [
          Container(width: width, height: height,
            color: AppTheme.editorBackground,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius - bezel * 0.5),
              child: child)),
          if (isPhone) ...[
            // Notch
            Positioned(top: bezel - 2,
              child: Container(width: 120, height: 28,
                decoration: const BoxDecoration(
                  color: Color(0xFF1a1a1a),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(18))),
                child: Row(mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(width: 12, height: 12,
                      decoration: BoxDecoration(color: const Color(0xFF1a1a2e),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF2a2a3e), width: 1),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5),
                          blurRadius: 2, spreadRadius: 0)])),
                    const SizedBox(width: 8),
                    Container(width: 48, height: 4,
                      decoration: BoxDecoration(color: const Color(0xFF1a1a2e),
                        borderRadius: BorderRadius.circular(2))),
                  ])),
            ),
            // Home indicator
            Positioned(bottom: 6,
              child: Container(width: 100, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2)))),
          ],
        ]),
      ),
    );
  }
}
