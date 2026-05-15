// lib/screens/build_preview_screen.dart
// Build & Preview Screen — Central hub for previewing and building apps.
//
// Features: project type detection, preview method cards, quick preview,
// build options (web/APK/split-screen/Termux), real-time build log viewer,
// build history, and settings. Dark theme with cards and progress indicators.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/theme.dart';
import '../services/build_orchestrator.dart';
import '../services/runtime_manager.dart';
import '../services/runtime_provider.dart';
import '../services/termux_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Build & Preview Screen
// ═══════════════════════════════════════════════════════════════════════════

/// Central hub for previewing and building apps.
///
/// Provides:
/// - Project type detection (auto)
/// - Available preview methods (cards)
/// - Quick preview button (best method)
/// - Build options: Web preview, APK build, Split-screen preview, Termux
/// - Build log viewer (real-time scrolling)
/// - Build history
/// - Settings: default preview method, auto-preview toggle
///
/// Design: Cards for each method, progress indicators, dark theme.
class BuildPreviewScreen extends StatefulWidget {
  /// Path to the project to preview/build.
  final String projectPath;

  const BuildPreviewScreen({
    super.key,
    required this.projectPath,
  });

  @override
  State<BuildPreviewScreen> createState() => _BuildPreviewScreenState();
}

class _BuildPreviewScreenState extends State<BuildPreviewScreen>
    with SingleTickerProviderStateMixin {
  // ── Services ────────────────────────────────────────────────────

  late final TermuxService _termux;
  late final RuntimeManager _runtimeManager;
  late final BuildOrchestrator _orchestrator;

  // ── State ───────────────────────────────────────────────────────

  /// Currently selected tab index.
  int _selectedTab = 0;

  /// Whether the screen is loading initial state.
  bool _isLoading = true;

  /// Whether a build/preview is currently running.
  bool _isBuilding = false;

  /// Whether Termux is installed.
  bool _termuxInstalled = false;

  /// Whether the setup is complete.
  bool _setupComplete = false;

  /// Runtime health checks in priority order.
  List<RuntimeHealth> _runtimeHealth = [];

  /// Current active runtime capabilities.
  RuntimeCapabilities _runtimeCapabilities = RuntimeCapabilities.none;

  /// Detected project type string.
  String _projectType = 'Unknown';

  /// Available preview methods.
  List<PreviewMethod> _availableMethods = [];

  /// Currently active preview method.
  PreviewMethod? _activeMethod;

  /// Active preview session.
  PreviewSession? _activeSession;

  /// Build log lines for display.
  final List<String> _buildLogs = [];

  /// Scroll controller for build log auto-scroll.
  final ScrollController _logScrollController = ScrollController();

  /// Stream subscription for build logs.
  StreamSubscription<String>? _logSubscription;

  /// Stream subscription for orchestrator events.
  StreamSubscription<OrchestratorEvent>? _eventSubscription;

  /// Tab controller for the main tabs.
  late TabController _tabController;

  /// Last build result.
  BuildResult? _lastBuildResult;

  /// Build history.
  final List<BuildHistoryEntry> _buildHistory = [];

  // ── Constants ───────────────────────────────────────────────────

  static const List<String> _tabLabels = ['Preview', 'Build Log', 'History', 'Settings'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabLabels.length, vsync: this);
    _tabController.addListener(() {
      setState(() => _selectedTab = _tabController.index);
    });

    _termux = TermuxService();
    _runtimeManager = RuntimeManager.withExternalTermux(_termux);
    _orchestrator = BuildOrchestrator(_termux, runtimeManager: _runtimeManager);

    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _termux.initialize();
      await _orchestrator.initialize();

      _termuxInstalled = await _termux.isTermuxInstalled();
      _setupComplete = await _termux.isSetupComplete();
      _runtimeHealth = await _runtimeManager.refresh();
      _runtimeCapabilities = await _runtimeManager.capabilities();

      // Detect available methods.
      _availableMethods = await _orchestrator.getAvailableMethods(widget.projectPath);

      // Detect project type.
      await _detectProjectType();

      // Subscribe to orchestrator events.
      await _eventSubscription?.cancel();
      _eventSubscription = _orchestrator.events.listen(_handleOrchestratorEvent);

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('[BuildPreviewScreen] Initialization error: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _detectProjectType() async {
    final dir = Directory(widget.projectPath);
    if (!await dir.exists()) return;

    final files = await dir.list().map((f) => p.basename(f.path)).toSet();

    if (files.contains('pubspec.yaml')) {
      final pubspec = File(p.join(widget.projectPath, 'pubspec.yaml'));
      final content = await pubspec.readAsString();
      setState(() {
        _projectType = content.contains('flutter:') ? 'Flutter' : 'Dart';
      });
    } else if (files.contains('package.json')) {
      setState(() => _projectType = 'Node.js');
    } else if (files.contains('requirements.txt') || files.any((f) => f.endsWith('.py'))) {
      setState(() => _projectType = 'Python');
    } else if (files.contains('index.html') || files.any((f) => f.endsWith('.html'))) {
      setState(() => _projectType = 'HTML');
    }
  }

  void _handleOrchestratorEvent(OrchestratorEvent event) {
    debugPrint('[BuildPreviewScreen] Event: ${event.type} - ${event.message}');

    switch (event.type) {
      case OrchestratorEventType.started:
        setState(() {
          _isBuilding = true;
          _activeMethod = event.method;
        });
        break;
      case OrchestratorEventType.stopped:
        setState(() {
          _isBuilding = false;
          _activeMethod = null;
          _activeSession = null;
        });
        break;
      case OrchestratorEventType.buildStarted:
        setState(() => _isBuilding = true);
        break;
      case OrchestratorEventType.buildCompleted:
        setState(() => _isBuilding = false);
        break;
      case OrchestratorEventType.error:
        setState(() => _isBuilding = false);
        break;
    }
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    _eventSubscription?.cancel();
    _logScrollController.dispose();
    _tabController.dispose();
    _orchestrator.dispose();
    super.dispose();
  }

  // ═════════════════════════════════════════════════════════════════
  // Build Actions
  // ═════════════════════════════════════════════════════════════════

  Future<void> _startPreview(PreviewMethod method) async {
    setState(() {
      _isBuilding = true;
      _buildLogs.clear();
      _activeMethod = method;
    });

    try {
      // Subscribe to build logs.
      _logSubscription?.cancel();
      _logSubscription = _runtimeManager.logStream.listen((line) {
        setState(() {
          _buildLogs.add(line);
          _scrollLogToBottom();
        });
      });

      final session = await _orchestrator.startPreview(
        widget.projectPath,
        preferredMethod: method,
      );

      setState(() {
        _activeSession = session;
        _isBuilding = false;
      });

      // Switch to log tab.
      _tabController.animateTo(1);
    } catch (e) {
      setState(() {
        _buildLogs.add('[error] Preview failed: $e');
        _isBuilding = false;
        _activeMethod = null;
      });
    }
  }

  Future<void> _stopPreview() async {
    if (_activeSession != null) {
      await _activeSession!.stop();
    }
    setState(() {
      _activeSession = null;
      _activeMethod = null;
      _isBuilding = false;
    });
  }

  Future<void> _buildApk(BuildMode mode) async {
    setState(() {
      _isBuilding = true;
      _buildLogs.clear();
      _activeMethod = PreviewMethod.flutterApk;
    });

    // Subscribe to build logs.
    _logSubscription?.cancel();
    _logSubscription = _runtimeManager.logStream.listen((line) {
      setState(() {
        _buildLogs.add(line);
        _scrollLogToBottom();
      });
    });

    try {
      final result = await _runtimeManager.buildApk(widget.projectPath, mode: mode);

      setState(() {
        _lastBuildResult = result;
        _isBuilding = false;
        _buildHistory.add(BuildHistoryEntry(
          type: 'APK (${mode.name})',
          success: result.success,
          timestamp: DateTime.now(),
          duration: result.buildTime,
          path: result.outputPath,
        ));
      });

      if (result.success && result.outputPath != null) {
        // Offer to install.
        _showInstallDialog(result.outputPath!);
      }
    } catch (e) {
      setState(() {
        _buildLogs.add('[error] Build failed: $e');
        _isBuilding = false;
      });
    }
  }

  void _showInstallDialog(String apkPath) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: const Text(
          'APK Build Complete',
          style: TextStyle(
            fontFamily: AppTheme.fontBody,
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'APK built successfully!\n\nPath: $apkPath\nSize: ${_lastBuildResult?.formattedSize ?? 'unknown'}\n\nInstall now?',
          style: const TextStyle(
            fontFamily: AppTheme.fontBody,
            color: AppTheme.textSecondary,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _installApk(apkPath);
            },
            child: const Text('Install'),
          ),
        ],
      ),
    );
  }

  Future<void> _installApk(String apkPath) async {
    setState(() {
      _buildLogs.add('[install] Installing APK...');
      _isBuilding = true;
    });

    try {
      final result = await _runtimeManager.installApk(apkPath);
      setState(() {
        _isBuilding = false;
        if (result.success) {
          _buildLogs.add('[install] APK installed: ${result.packageName}');
        } else {
          _buildLogs.add('[install] Install failed: ${result.error}');
        }
      });
    } catch (e) {
      setState(() {
        _buildLogs.add('[install] Error: $e');
        _isBuilding = false;
      });
    }
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
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background.withOpacity(0.8),
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Build & Preview',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              '${widget.projectPath.split('/').last} • $_projectType',
              style: const TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 12,
                color: AppTheme.textTertiary,
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: _tabLabels.map((label) => Tab(text: label)).toList(),
          labelStyle: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPreviewTab(),
          _buildBuildLogTab(),
          _buildHistoryTab(),
          _buildSettingsTab(),
        ],
      ),
    );
  }

  /// Build the Preview tab with method cards.
  Widget _buildPreviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status banner.
          _buildStatusBanner(),
          const SizedBox(height: 20),

          // Quick preview section.
          _buildQuickPreviewSection(),
          const SizedBox(height: 24),

          // Build options section.
          _buildBuildOptionsSection(),
          const SizedBox(height: 24),

          // Active preview indicator.
          if (_activeSession != null) _buildActivePreviewCard(),
        ],
      ),
    );
  }

  /// Status banner at the top.
  Widget _buildStatusBanner() {
    final active = _runtimeManager.activeHealth;
    final bool ready = active?.ready == true;
    final bool needsBuildSetup =
        !_runtimeCapabilities.flutter || !_runtimeCapabilities.androidBuild;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: ready ? AppTheme.accentGradient : AppTheme.surfaceGradient,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ready ? AppTheme.accent.withOpacity(0.3) : AppTheme.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            ready ? Icons.check_circle : Icons.info_outline,
            color: ready ? AppTheme.success : AppTheme.warning,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ready
                      ? 'Runtime Ready: ${active?.name ?? 'Provider'}'
                      : 'Runtime Setup Required',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  active?.status ??
                      (ready
                          ? 'Runtime provider is configured'
                          : 'Install or configure a runtime provider to enable builds'),
                  style: const TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (needsBuildSetup)
            TextButton(
              onPressed: _runSetupWizard,
              child: const Text('Setup'),
            ),
        ],
      ),
    );
  }

  /// Quick preview section.
  Widget _buildQuickPreviewSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Preview',
          style: TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        if (_availableMethods.isEmpty)
          _buildNoMethodsCard()
        else
          ..._availableMethods.map(_buildMethodCard),
      ],
    );
  }

  /// Card for a single preview method.
  Widget _buildMethodCard(PreviewMethod method) {
    final bool isActive = _activeMethod == method && _activeSession != null;
    final bool canUse = _canUseMethod(method);

    final Map<PreviewMethod, _MethodConfig> configs = {
      PreviewMethod.webview: _MethodConfig(
        icon: Icons.language,
        title: 'Web Preview',
        subtitle: 'Instant preview in WebView',
        color: AppTheme.info,
        timeEstimate: 'instant',
      ),
      PreviewMethod.flutterWeb: _MethodConfig(
        icon: Icons.flash_on,
        title: 'Flutter Web',
        subtitle: 'Fast web build preview',
        color: AppTheme.accent,
        timeEstimate: '10-30s',
      ),
      PreviewMethod.flutterApk: _MethodConfig(
        icon: Icons.android,
        title: 'APK Build',
        subtitle: 'Build and install real APK',
        color: AppTheme.success,
        timeEstimate: '2-5min',
      ),
      PreviewMethod.terminal: _MethodConfig(
        icon: Icons.terminal,
        title: 'Terminal',
        subtitle: 'Terminal output preview',
        color: AppTheme.textTertiary,
        timeEstimate: 'varies',
      ),
      PreviewMethod.remote: _MethodConfig(
        icon: Icons.cloud,
        title: 'Remote Build',
        subtitle: 'Build on remote server',
        color: AppTheme.primary,
        timeEstimate: '1-3min',
      ),
    };

    final config = configs[method]!;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Card(
        color: AppTheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isActive ? config.color : AppTheme.border,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: canUse && !_isBuilding ? () => _startPreview(method) : null,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: config.color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(config.icon, color: config.color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        config.title,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontBody,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        config.subtitle,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontBody,
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundElevated,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    config.timeEstimate,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 11,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (isActive)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primary,
                    ),
                  )
                else if (canUse)
                  const Icon(
                    Icons.play_circle_outline,
                    color: AppTheme.primary,
                    size: 24,
                  )
                else
                  const Icon(
                    Icons.lock_outline,
                    color: AppTheme.textDisabled,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _canUseMethod(PreviewMethod method) {
    switch (method) {
      case PreviewMethod.webview:
        return true;
      case PreviewMethod.flutterWeb:
        return _runtimeCapabilities.flutter;
      case PreviewMethod.flutterApk:
        return _runtimeCapabilities.flutter && _runtimeCapabilities.androidBuild;
      case PreviewMethod.terminal:
        return _runtimeCapabilities.shell;
      case PreviewMethod.remote:
        return _runtimeCapabilities.cloudBuild;
    }
  }

  /// Card shown when no preview methods are available.
  Widget _buildNoMethodsCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: const BorderSide(color: AppTheme.border),
      ),
      child: const Column(
        children: [
          Icon(Icons.build_outlined, color: AppTheme.textDisabled, size: 40),
          SizedBox(height: 12),
          Text(
            'No Preview Methods Available',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Complete the setup to enable preview methods',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 13,
              color: AppTheme.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  /// Build options section.
  Widget _buildBuildOptionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Build Options',
          style: TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildBuildButton(
                icon: Icons.web,
                label: 'Web',
                color: AppTheme.accent,
                onPressed: _runtimeCapabilities.flutter && !_isBuilding
                    ? () => _startPreview(PreviewMethod.flutterWeb)
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildBuildButton(
                icon: Icons.android,
                label: 'Debug APK',
                color: AppTheme.info,
                onPressed: _runtimeCapabilities.flutter &&
                        _runtimeCapabilities.androidBuild &&
                        !_isBuilding
                    ? () => _buildApk(BuildMode.debug)
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildBuildButton(
                icon: Icons.rocket_launch,
                label: 'Release APK',
                color: AppTheme.success,
                onPressed: _runtimeCapabilities.flutter &&
                        _runtimeCapabilities.androidBuild &&
                        !_isBuilding
                    ? () => _buildApk(BuildMode.release)
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildBuildButton(
                icon: Icons.splitscreen,
                label: 'Split Screen',
                color: AppTheme.warning,
                onPressed: _activeSession != null && !_isBuilding
                    ? _enableSplitScreen
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildBuildButton(
                icon: Icons.terminal,
                label: 'Open Termux',
                color: AppTheme.primary,
                onPressed: _termuxInstalled ? _openTermux : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBuildButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    final bool enabled = onPressed != null;

    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: enabled ? color.withOpacity(0.15) : AppTheme.surface,
        foregroundColor: enabled ? color : AppTheme.textDisabled,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: enabled ? color.withOpacity(0.3) : AppTheme.border,
          ),
        ),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Active preview indicator card.
  Widget _buildActivePreviewCard() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primaryMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.play_circle, color: AppTheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Active: ${_activeSession?.method.name ?? "Preview"}',
                style: const TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _stopPreview,
                icon: const Icon(Icons.stop, color: AppTheme.error, size: 18),
                label: const Text(
                  'Stop',
                  style: TextStyle(color: AppTheme.error),
                ),
              ),
            ],
          ),
          if (_activeSession?.previewUrl != null)
            Text(
              'Output: ${_activeSession!.previewUrl}',
              style: const TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  /// Build the Build Log tab.
  Widget _buildBuildLogTab() {
    return Column(
      children: [
        // Log header with controls.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
            color: AppTheme.backgroundElevated,
            border: Border(bottom: BorderSide(color: AppTheme.border)),
          ),
          child: Row(
            children: [
              const Icon(Icons.article_outlined, size: 16, color: AppTheme.textTertiary),
              const SizedBox(width: 8),
              Text(
                '${_buildLogs.length} lines',
                style: const TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 12,
                  color: AppTheme.textTertiary,
                ),
              ),
              const Spacer(),
              if (_isBuilding)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.primary,
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18, color: AppTheme.textTertiary),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _buildLogs.join('\n')));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Log copied to clipboard')),
                  );
                },
                tooltip: 'Copy log',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.textTertiary),
                onPressed: () => setState(() => _buildLogs.clear()),
                tooltip: 'Clear log',
              ),
            ],
          ),
        ),

        // Log content.
        Expanded(
          child: _buildLogs.isEmpty
              ? const Center(
                  child: Text(
                    'No build output yet.\nStart a preview or build to see logs.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 14,
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
      ],
    );
  }

  /// Single log line with syntax highlighting.
  Widget _buildLogLine(String line) {
    // Colorize log lines based on prefix.
    Color lineColor = AppTheme.textSecondary;
    if (line.startsWith('[error]') || line.contains('Error') || line.contains('FAILED')) {
      lineColor = AppTheme.error;
    } else if (line.startsWith('[warning]') || line.contains('Warning')) {
      lineColor = AppTheme.warning;
    } else if (line.startsWith('[setup]')) {
      lineColor = AppTheme.info;
    } else if (line.startsWith('[build]')) {
      lineColor = AppTheme.accent;
    } else if (line.startsWith('[install]')) {
      lineColor = AppTheme.success;
    } else if (line.startsWith('[preview]')) {
      lineColor = AppTheme.primary;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: SelectableText(
        line,
        style: TextStyle(
          fontFamily: AppTheme.fontCode,
          fontSize: 12,
          height: 1.4,
          color: lineColor,
        ),
      ),
    );
  }

  /// Build the History tab.
  Widget _buildHistoryTab() {
    if (_buildHistory.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 48, color: AppTheme.textDisabled),
            SizedBox(height: 12),
            Text(
              'No build history yet',
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 16,
                color: AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _buildHistory.length,
      itemBuilder: (context, index) {
        final entry = _buildHistory[_buildHistory.length - 1 - index];
        return _buildHistoryCard(entry);
      },
    );
  }

  Widget _buildHistoryCard(BuildHistoryEntry entry) {
    return Card(
      color: AppTheme.surface,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: entry.success ? AppTheme.success.withOpacity(0.3) : AppTheme.error.withOpacity(0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: entry.success
                    ? AppTheme.success.withOpacity(0.15)
                    : AppTheme.error.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                entry.success ? Icons.check : Icons.close,
                color: entry.success ? AppTheme.success : AppTheme.error,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.type,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    '${_formatTimestamp(entry.timestamp)} • ${entry.duration.inSeconds}s',
                    style: const TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (entry.path != null)
              IconButton(
                icon: const Icon(Icons.folder_open, size: 18, color: AppTheme.primary),
                onPressed: () {
                  // Open file location.
                },
                tooltip: 'Open output',
              ),
          ],
        ),
      ),
    );
  }

  /// Build the Settings tab.
  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Preview Settings',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 16),

          // Runtime section.
          _buildSettingsCard(
            title: 'Runtime Providers',
            children: [
              _buildSettingsRow(
                icon: Icons.hub_outlined,
                label: 'Active Runtime',
                value: _runtimeManager.activeHealth?.name ?? 'Unknown',
                valueColor: _runtimeManager.activeHealth?.ready == true
                    ? AppTheme.success
                    : AppTheme.warning,
              ),
              _buildSettingsRow(
                icon: Icons.extension_outlined,
                label: 'Capabilities',
                value: _formatCapabilities(_runtimeCapabilities),
              ),
              const SizedBox(height: 8),
              ..._runtimeHealth.map((health) => _buildSettingsRow(
                    icon: health.ready
                        ? Icons.check_circle_outline
                        : health.available
                            ? Icons.info_outline
                            : Icons.radio_button_unchecked,
                    label: health.name,
                    value: health.ready
                        ? 'Ready'
                        : health.available
                            ? 'Available'
                            : 'Missing',
                    valueColor: health.ready
                        ? AppTheme.success
                        : health.available
                            ? AppTheme.warning
                            : AppTheme.textTertiary,
                  )),
              const SizedBox(height: 12),
              _buildSettingsRow(
                icon: Icons.terminal,
                label: 'External Termux',
                value: _termuxInstalled ? 'Yes' : 'No',
                valueColor: _termuxInstalled ? AppTheme.success : AppTheme.error,
              ),
              _buildSettingsRow(
                icon: Icons.build,
                label: 'Setup Complete',
                value: _setupComplete ? 'Yes' : 'No',
                valueColor: _setupComplete ? AppTheme.success : AppTheme.warning,
              ),
              const SizedBox(height: 8),
              if (!_setupComplete)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _runSetupWizard,
                    child: const Text('Run Setup Wizard'),
                  ),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _copyTermuxSetupScript,
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy Termux Setup Script'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Environment section.
          _buildSettingsCard(
            title: 'Environment',
            children: [
              _buildSettingsRow(
                icon: Icons.folder,
                label: 'Project',
                value: widget.projectPath,
              ),
              _buildSettingsRow(
                icon: Icons.category,
                label: 'Project Type',
                value: _projectType,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Actions section.
          _buildSettingsCard(
            title: 'Actions',
            children: [
              ListTile(
                leading: const Icon(Icons.refresh, color: AppTheme.textSecondary),
                title: const Text(
                  'Refresh Environment',
                  style: TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                ),
                onTap: () {
                  _termux.clearCache();
                  _orchestrator.clearCache();
                  _initialize();
                },
              ),
              ListTile(
                leading: const Icon(Icons.cleaning_services, color: AppTheme.textSecondary),
                title: const Text(
                  'Clean Build Cache',
                  style: TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                ),
                onTap: () async {
                  setState(() => _isBuilding = true);
                  try {
                    await _runtimeManager.execute(
                      'flutter clean',
                      workingDir: widget.projectPath,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Build cache cleaned')),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                  setState(() => _isBuilding = false);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsCard({
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      color: AppTheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.textTertiary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: AppTheme.fontCode,
              fontSize: 12,
              color: valueColor ?? AppTheme.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // Actions
  // ═════════════════════════════════════════════════════════════════

  Future<void> _runSetupWizard() async {
    setState(() {
      _isBuilding = true;
      _buildLogs.clear();
      _activeMethod = null;
    });

    _logSubscription?.cancel();
    _logSubscription = _runtimeManager.logStream.listen((line) {
      setState(() {
        _buildLogs.add(line);
        _scrollLogToBottom();
      });
    });

    try {
      final result = await _termux.runSetupWizard();
      final runtimeHealth = await _runtimeManager.refresh();
      final runtimeCapabilities = await _runtimeManager.capabilities();
      final availableMethods = await _orchestrator.getAvailableMethods(widget.projectPath);

      setState(() {
        _setupComplete = result.success;
        _runtimeHealth = runtimeHealth;
        _runtimeCapabilities = runtimeCapabilities;
        _availableMethods = availableMethods;
        _isBuilding = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.success ? AppTheme.success : AppTheme.error,
        ),
      );
    } catch (e) {
      setState(() {
        _isBuilding = false;
      });
    }
  }

  Future<void> _openTermux() async {
    try {
      await _termux.execute('am start -n com.termux/.app.TermuxActivity');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open Termux: $e')),
      );
    }
  }

  void _copyTermuxSetupScript() {
    Clipboard.setData(ClipboardData(text: _termux.generateSetupScript()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Termux setup script copied')),
    );
  }

  Future<void> _enableSplitScreen() async {
    try {
      await _termux.execute(
        'am start -n com.termux/.app.TermuxActivity --ez "split_screen" true',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Split screen: $e')),
      );
    }
  }

  String _formatCapabilities(RuntimeCapabilities caps) {
    final labels = <String>[
      if (caps.shell) 'shell',
      if (caps.git) 'git',
      if (caps.node) 'node',
      if (caps.python) 'python',
      if (caps.flutter) 'flutter',
      if (caps.androidBuild) 'apk',
      if (caps.pty) 'pty',
      if (caps.backgroundService) 'bg',
      if (caps.cloudBuild) 'cloud',
      if (caps.webViewPreview) 'webview',
    ];
    return labels.isEmpty ? 'none' : labels.join(', ');
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Supporting Classes
// ═══════════════════════════════════════════════════════════════════════════

/// Configuration for a preview method card.
class _MethodConfig {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final String timeEstimate;

  _MethodConfig({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.timeEstimate,
  });
}

/// Single entry in the build history.
class BuildHistoryEntry {
  final String type;
  final bool success;
  final DateTime timestamp;
  final Duration duration;
  final String? path;

  BuildHistoryEntry({
    required this.type,
    required this.success,
    required this.timestamp,
    required this.duration,
    this.path,
  });
}
