// lib/widgets/flutter_web_preview.dart
// Flutter Web Preview — Fast preview for Flutter projects using flutter build web.
//
// Much faster than APK build (seconds vs minutes). Shows approximate UI layout
// for quick iteration. Limitations: No platform-specific features.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:webview_flutter/webview_flutter.dart';

import '../core/theme.dart';
import '../services/termux_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Flutter Web Preview Widget
// ═══════════════════════════════════════════════════════════════════════════

/// Fast preview for Flutter projects using `flutter build web`.
///
/// This widget builds the Flutter project for the web platform and displays
/// the result in an embedded WebView. It's significantly faster than building
/// an APK (seconds vs minutes) making it ideal for quick UI iteration.
///
/// **Advantages:**
/// - Much faster than APK build (10-30s vs 2-5min)
/// - Shows approximate UI layout
/// - Good for quick iteration and visual feedback
///
/// **Limitations:**
/// - No platform-specific features (camera, GPS, etc.)
/// - Web-only behavior for some widgets
/// - May differ slightly from native rendering
///
/// **Usage:**
/// ```dart
/// FlutterWebPreview(
///   projectPath: '/path/to/project',
///   termuxService: termuxService,
/// )
/// ```
class FlutterWebPreview extends StatefulWidget {
  /// Absolute path to the Flutter project to preview.
  final String projectPath;

  /// TermuxService instance for running build commands.
  final TermuxService termuxService;

  /// Callback when the build completes successfully.
  final VoidCallback? onBuildSuccess;

  /// Callback when the build fails.
  final Function(String error)? onBuildError;

  /// Callback when the preview is ready to display.
  final VoidCallback? onPreviewReady;

  /// Whether to auto-start the build when the widget is first created.
  final bool autoStart;

  /// Custom HTTP headers for the WebView.
  final Map<String, String>? headers;

  const FlutterWebPreview({
    super.key,
    required this.projectPath,
    required this.termuxService,
    this.onBuildSuccess,
    this.onBuildError,
    this.onPreviewReady,
    this.autoStart = true,
    this.headers,
  });

  @override
  State<FlutterWebPreview> createState() => _FlutterWebPreviewState();
}

class _FlutterWebPreviewState extends State<FlutterWebPreview>
    with SingleTickerProviderStateMixin {
  // ── Build State ─────────────────────────────────────────────────

  /// Current build phase.
  _BuildPhase _phase = _BuildPhase.idle;

  /// WebView controller for displaying the preview.
  WebViewController? _webViewController;

  /// URL to load in the WebView.
  String? _previewUrl;

  /// Build log lines for the progress display.
  final List<String> _buildLogs = [];

  /// Scroll controller for build log.
  final ScrollController _logScrollController = ScrollController();

  /// Stream subscription for build logs.
  StreamSubscription<String>? _logSubscription;

  /// Build result from the last build operation.
  BuildResult? _buildResult;

  /// Animation controller for the loading indicator.
  late AnimationController _animationController;

  /// Whether the WebView has finished loading.
  bool _webViewLoaded = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    if (widget.autoStart) {
      _startBuild();
    }
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    _logScrollController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // ═════════════════════════════════════════════════════════════════
  // Build Logic
  // ═════════════════════════════════════════════════════════════════

  /// Start the Flutter Web build process.
  Future<void> _startBuild() async {
    if (_phase == _BuildPhase.building) return;

    setState(() {
      _phase = _BuildPhase.building;
      _buildLogs.clear();
      _previewUrl = null;
      _webViewLoaded = false;
    });

    // Subscribe to build log stream.
    _logSubscription?.cancel();
    _logSubscription = widget.termuxService.buildLogStream.listen(
      (line) {
        if (mounted) {
          setState(() {
            _buildLogs.add(line);
            _scrollLogToBottom();
          });
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() => _buildLogs.add('[error] Stream error: $e'));
        }
      },
    );

    try {
      final result = await widget.termuxService.buildWeb(widget.projectPath);

      if (!mounted) return;

      setState(() {
        _buildResult = result;
        _logSubscription?.cancel();
      });

      if (result.success && result.outputPath != null) {
        await _onBuildComplete(result.outputPath!);
      } else {
        _onBuildFailed(result.error ?? 'Build failed with no error message');
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _phase = _BuildPhase.error;
        _buildLogs.add('[error] Exception: $e');
        _logSubscription?.cancel();
      });

      widget.onBuildError?.call(e.toString());
    }
  }

  /// Called when the build completes successfully.
  Future<void> _onBuildComplete(String outputPath) async {
    final indexPath = p.join(outputPath, 'index.html');
    final indexFile = File(indexPath);

    if (!await indexFile.exists()) {
      _onBuildFailed('index.html not found in build output');
      return;
    }

    setState(() {
      _previewUrl = indexPath;
      _phase = _BuildPhase.previewing;
    });

    // Initialize WebView controller.
    await _initializeWebView(indexPath);

    widget.onBuildSuccess?.call();
  }

  /// Called when the build fails.
  void _onBuildFailed(String error) {
    if (!mounted) return;

    setState(() {
      _phase = _BuildPhase.error;
      _buildLogs.add('[error] $error');
    });

    widget.onBuildError?.call(error);
  }

  /// Initialize the WebView controller with the built output.
  Future<void> _initializeWebView(String filePath) async {
    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(AppTheme.background)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (url) {
              if (mounted) {
                setState(() => _webViewLoaded = true);
                widget.onPreviewReady?.call();
              }
            },
            onWebResourceError: (error) {
              if (mounted) {
                setState(() {
                  _buildLogs.add('[webview] Error: ${error.description}');
                });
              }
            },
          ),
        )
        ..loadFile(filePath);

      setState(() {
        _webViewController = controller;
      });
    } catch (e) {
      setState(() {
        _buildLogs.add('[error] WebView init failed: $e');
        _phase = _BuildPhase.error;
      });
    }
  }

  /// Retry the build after a failure.
  Future<void> _retryBuild() async {
    setState(() {
      _phase = _BuildPhase.idle;
      _previewUrl = null;
      _webViewController = null;
      _webViewLoaded = false;
      _buildResult = null;
    });
    await _startBuild();
  }

  void _scrollLogToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ═════════════════════════════════════════════════════════════════
  // UI Build
  // ═════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: _buildContent(),
      ),
    );
  }

  /// Build the appropriate content based on the current phase.
  Widget _buildContent() {
    switch (_phase) {
      case _BuildPhase.idle:
        return _buildIdleState();
      case _BuildPhase.building:
        return _buildBuildingState();
      case _BuildPhase.previewing:
        return _buildPreviewingState();
      case _BuildPhase.error:
        return _buildErrorState();
    }
  }

  /// Idle state - show start button.
  Widget _buildIdleState() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.flash_on,
              color: AppTheme.accent,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Flutter Web Preview',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Fast preview using flutter build web.\nBuilds in 10-30 seconds.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _startBuild,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('Start Preview'),
          ),
        ],
      ),
    );
  }

  /// Building state - show progress and logs.
  Widget _buildBuildingState() {
    return Column(
      children: [
        // Progress header.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: AppTheme.backgroundElevated,
            border: Border(bottom: BorderSide(color: AppTheme.border)),
          ),
          child: Row(
            children: [
              RotationTransition(
                turns: _animationController,
                child: const Icon(
                  Icons.refresh,
                  color: AppTheme.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Building for Web...',
                      style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      _buildLogs.isNotEmpty
                          ? _buildLogs.last.substring(0, _buildLogs.last.length.clamp(0, 60))
                          : 'Starting build...',
                      style: const TextStyle(
                        fontFamily: AppTheme.fontCode,
                        fontSize: 11,
                        color: AppTheme.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Text(
                '${_buildLogs.length} lines',
                style: const TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 11,
                  color: AppTheme.textTertiary,
                ),
              ),
            ],
          ),
        ),

        // Build log.
        Expanded(
          child: Container(
            color: AppTheme.editorBackground,
            child: _buildLogs.isEmpty
                ? const Center(
                    child: Text(
                      'Waiting for build output...',
                      style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 13,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _logScrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _buildLogs.length,
                    itemBuilder: (context, index) {
                      return _buildLogLine(_buildLogs[index]);
                    },
                  ),
          ),
        ),

        // Cancel button.
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: AppTheme.backgroundElevated,
            border: Border(top: BorderSide(color: AppTheme.border)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  await widget.termuxService.stopCurrentBuild();
                  setState(() => _phase = _BuildPhase.idle);
                },
                icon: const Icon(Icons.stop, size: 16, color: AppTheme.error),
                label: const Text(
                  'Cancel',
                  style: TextStyle(color: AppTheme.error),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Previewing state - show WebView.
  Widget _buildPreviewingState() {
    return Stack(
      children: [
        // WebView display.
        if (_webViewController != null)
          WebViewWidget(controller: _webViewController!)
        else
          Container(
            color: AppTheme.background,
            child: const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            ),
          ),

        // Overlay controls.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.background.withOpacity(0.9),
              border: const Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _webViewLoaded ? AppTheme.success : AppTheme.warning,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _webViewLoaded ? 'Web preview loaded' : 'Loading preview...',
                    style: const TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Refresh button.
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18, color: AppTheme.textSecondary),
                  onPressed: _startBuild,
                  tooltip: 'Rebuild',
                ),
                // Info button.
                if (_buildResult != null)
                  Tooltip(
                    message: 'Build time: ${_buildResult!.buildTime.inSeconds}s\n'
                        'Size: ${_buildResult!.formattedSize}',
                    child: const Icon(
                      Icons.info_outline,
                      size: 18,
                      color: AppTheme.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Error state - show error message and retry button.
  Widget _buildErrorState() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.error.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.error_outline,
              color: AppTheme.error,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Build Failed',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          // Show last error lines.
          if (_buildLogs.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 150),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.editorBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.error.withOpacity(0.3)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _buildLogs
                      .where((l) => l.startsWith('[error]'))
                      .toList()
                      .reversed
                      .take(5)
                      .map((l) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              l,
                              style: const TextStyle(
                                fontFamily: AppTheme.fontCode,
                                fontSize: 11,
                                color: AppTheme.error,
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _retryBuild,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry Build'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () {
              setState(() => _phase = _BuildPhase.idle);
            },
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Back'),
          ),
        ],
      ),
    );
  }

  /// Single log line with color coding.
  Widget _buildLogLine(String line) {
    Color lineColor = AppTheme.textSecondary;
    if (line.startsWith('[error]')) lineColor = AppTheme.error;
    if (line.startsWith('[build]')) lineColor = AppTheme.accent;
    if (line.startsWith('[setup]')) lineColor = AppTheme.info;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        line,
        style: TextStyle(
          fontFamily: AppTheme.fontCode,
          fontSize: 11,
          height: 1.4,
          color: lineColor,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Build Phases
// ═══════════════════════════════════════════════════════════════════════════

/// Internal build phase state machine.
enum _BuildPhase {
  /// Initial state, waiting to start.
  idle,

  /// Build is in progress.
  building,

  /// Build complete, showing preview.
  previewing,

  /// Build failed.
  error,
}
