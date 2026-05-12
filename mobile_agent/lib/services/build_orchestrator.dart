// lib/services/build_orchestrator.dart
// Build Orchestrator — Intelligently selects the best preview/build method.
//
// Analyzes project type, checks available tools (Termux, remote hosts),
// and routes to the most appropriate preview method for fast iteration.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'termux_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Build Orchestrator
// ═══════════════════════════════════════════════════════════════════════════

/// Intelligently selects the best preview/build method for a project.
///
/// Decision tree:
/// - HTML/CSS/JS project:
///   -> WebView Preview (instant, no build needed)
/// - Flutter project:
///   -> Web preview (flutter build web, fast)
///   -> If Termux available: APK build (real app)
///   -> If remote host configured: Remote build
/// - Python project:
///   -> Terminal output
/// - React/Vue project:
///   -> WebView Preview (npm run dev via Termux)
///
/// Usage:
/// ```dart
/// final orchestrator = BuildOrchestrator(termuxService);
/// await orchestrator.initialize();
/// final method = await orchestrator.determineMethod('/path/to/project');
/// final session = await orchestrator.startPreview('/path/to/project');
/// ```
class BuildOrchestrator {
  final TermuxService _termux;

  /// Active preview sessions keyed by project path.
  final Map<String, PreviewSession> _activeSessions = {};

  /// Stream controller for orchestrator events.
  final StreamController<OrchestratorEvent> _eventController =
      StreamController<OrchestratorEvent>.broadcast();

  /// Whether the orchestrator is initialized.
  bool _initialized = false;

  /// Project type cache to avoid re-analysis.
  final Map<String, ProjectType> _projectTypeCache = {};

  // ═════════════════════════════════════════════════════════════════
  // Public Accessors
  // ═════════════════════════════════════════════════════════════════

  /// Stream of orchestrator events (preview started/stopped, etc.).
  Stream<OrchestratorEvent> get events => _eventController.stream;

  /// Currently active preview sessions.
  List<PreviewSession> get activeSessions => List.unmodifiable(_activeSessions.values);

  /// Number of active preview sessions.
  int get activeSessionCount => _activeSessions.length;

  /// Whether the orchestrator is initialized.
  bool get isInitialized => _initialized;

  // ═════════════════════════════════════════════════════════════════
  // Initialization
  // ═════════════════════════════════════════════════════════════════

  /// Create a BuildOrchestrator with a TermuxService instance.
  BuildOrchestrator(this._termux);

  /// Initialize the orchestrator.
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      debugPrint('[BuildOrchestrator] Initializing...');
      await _termux.initialize();
      _initialized = true;
      debugPrint('[BuildOrchestrator] Initialized successfully');
    } catch (e) {
      debugPrint('[BuildOrchestrator] Initialization warning: $e');
      // Continue with partial initialization - some methods may be unavailable.
      _initialized = true;
    }
  }

  // ═════════════════════════════════════════════════════════════════
  // Project Analysis
  // ═════════════════════════════════════════════════════════════════

  /// Analyze a project and determine its type.
  ///
  /// Examines key files in the project directory to identify
  /// what kind of project it is.
  Future<ProjectType> _detectProjectType(String projectPath) async {
    // Check cache first.
    if (_projectTypeCache.containsKey(projectPath)) {
      return _projectTypeCache[projectPath]!;
    }

    final dir = Directory(projectPath);
    if (!await dir.exists()) {
      return ProjectType.unknown;
    }

    final files = await dir.list().toList();
    final fileNames = files.map((f) => p.basename(f.path)).toSet();

    // Flutter project check.
    if (fileNames.contains('pubspec.yaml')) {
      final pubspec = File(p.join(projectPath, 'pubspec.yaml'));
      final content = await pubspec.readAsString();
      if (content.contains('flutter:')) {
        _projectTypeCache[projectPath] = ProjectType.flutter;
        return ProjectType.flutter;
      }
      _projectTypeCache[projectPath] = ProjectType.dart;
      return ProjectType.dart;
    }

    // React/Vue/Node project check.
    if (fileNames.contains('package.json')) {
      final packageJson = File(p.join(projectPath, 'package.json'));
      final content = await packageJson.readAsString();

      if (content.contains('"react"') || content.contains('"react-dom"')) {
        _projectTypeCache[projectPath] = ProjectType.react;
        return ProjectType.react;
      }
      if (content.contains('"vue"')) {
        _projectTypeCache[projectPath] = ProjectType.vue;
        return ProjectType.vue;
      }
      _projectTypeCache[projectPath] = ProjectType.node;
      return ProjectType.node;
    }

    // Python project check.
    if (fileNames.contains('requirements.txt') ||
        fileNames.contains('setup.py') ||
        fileNames.contains('pyproject.toml') ||
        fileNames.any((f) => f.endsWith('.py'))) {
      _projectTypeCache[projectPath] = ProjectType.python;
      return ProjectType.python;
    }

    // HTML/CSS/JS project check.
    if (fileNames.contains('index.html') ||
        fileNames.contains('index.htm') ||
        fileNames.any((f) => f.endsWith('.html'))) {
      _projectTypeCache[projectPath] = ProjectType.html;
      return ProjectType.html;
    }

    // Generic check for source files.
    if (fileNames.any((f) => f.endsWith('.js') || f.endsWith('.css'))) {
      _projectTypeCache[projectPath] = ProjectType.html;
      return ProjectType.html;
    }

    _projectTypeCache[projectPath] = ProjectType.unknown;
    return ProjectType.unknown;
  }

  /// Determine the best preview method for a project.
  ///
  /// Considers project type, available tools, and user preferences
  /// to recommend the optimal preview method.
  Future<PreviewMethod> determineMethod(String projectPath) async {
    _ensureInitialized();

    debugPrint('[BuildOrchestrator] Determining method for: $projectPath');

    final projectType = await _detectProjectType(projectPath);
    final methods = await getAvailableMethods(projectPath);

    if (methods.isEmpty) {
      debugPrint('[BuildOrchestrator] No methods available');
      return PreviewMethod.terminal; // Fallback.
    }

    // Select best method based on project type and availability.
    switch (projectType) {
      case ProjectType.flutter:
      case ProjectType.dart:
        // Prefer: web preview (fastest) > APK (real) > terminal.
        if (methods.contains(PreviewMethod.flutterWeb)) {
          return PreviewMethod.flutterWeb;
        }
        if (methods.contains(PreviewMethod.flutterApk)) {
          return PreviewMethod.flutterApk;
        }
        return PreviewMethod.terminal;

      case ProjectType.react:
      case ProjectType.vue:
      case ProjectType.node:
        // Prefer: webview (instant) > terminal.
        if (methods.contains(PreviewMethod.webview)) {
          return PreviewMethod.webview;
        }
        return PreviewMethod.terminal;

      case ProjectType.python:
        // Python: terminal output.
        return PreviewMethod.terminal;

      case ProjectType.html:
        // HTML: webview preview.
        if (methods.contains(PreviewMethod.webview)) {
          return PreviewMethod.webview;
        }
        return PreviewMethod.terminal;

      case ProjectType.unknown:
        // Default to terminal for unknown projects.
        return PreviewMethod.terminal;
    }
  }

  /// Get all available preview methods for a project.
  ///
  /// Checks which tools and environments are available and
  /// returns the list of supported preview methods.
  Future<List<PreviewMethod>> getAvailableMethods(String projectPath) async {
    _ensureInitialized();

    final methods = <PreviewMethod>[];
    final projectType = await _detectProjectType(projectPath);

    debugPrint('[BuildOrchestrator] Checking methods for $projectType project');

    switch (projectType) {
      case ProjectType.flutter:
      case ProjectType.dart:
        // Flutter Web preview: always available for Flutter projects.
        methods.add(PreviewMethod.flutterWeb);

        // Flutter APK build: requires Termux with Flutter SDK.
        if (await _termux.isSetupComplete()) {
          methods.add(PreviewMethod.flutterApk);
        }

        // Terminal: always available as fallback.
        methods.add(PreviewMethod.terminal);
        break;

      case ProjectType.react:
      case ProjectType.vue:
      case ProjectType.html:
        // WebView preview: available for web projects.
        methods.add(PreviewMethod.webview);
        methods.add(PreviewMethod.terminal);
        break;

      case ProjectType.python:
      case ProjectType.node:
        // Terminal: for interpreted languages.
        methods.add(PreviewMethod.terminal);
        break;

      case ProjectType.unknown:
        methods.add(PreviewMethod.terminal);
        break;
    }

    return methods;
  }

  /// Get a human-readable description of a preview method.
  String getMethodDescription(PreviewMethod method) {
    switch (method) {
      case PreviewMethod.webview:
        return 'WebView Preview';
      case PreviewMethod.flutterWeb:
        return 'Flutter Web Preview';
      case PreviewMethod.flutterApk:
        return 'Flutter APK Build';
      case PreviewMethod.terminal:
        return 'Terminal Output';
      case PreviewMethod.remote:
        return 'Remote Build';
    }
  }

  /// Get an icon hint for a preview method.
  String getMethodIcon(PreviewMethod method) {
    switch (method) {
      case PreviewMethod.webview:
        return '🌐';
      case PreviewMethod.flutterWeb:
        return '⚡';
      case PreviewMethod.flutterApk:
        return '📱';
      case PreviewMethod.terminal:
        return '💻';
      case PreviewMethod.remote:
        return '☁️';
    }
  }

  /// Get estimated time for a preview method.
  String getMethodTimeEstimate(PreviewMethod method) {
    switch (method) {
      case PreviewMethod.webview:
        return 'instant';
      case PreviewMethod.flutterWeb:
        return '10-30s';
      case PreviewMethod.flutterApk:
        return '2-5min';
      case PreviewMethod.terminal:
        return 'varies';
      case PreviewMethod.remote:
        return '1-3min';
    }
  }

  // ═════════════════════════════════════════════════════════════════
  // Preview Session Management
  // ═════════════════════════════════════════════════════════════════

  /// Start a preview session for a project.
  ///
  /// Auto-selects the best preview method and starts the session.
  /// Returns a [PreviewSession] that can be used to monitor and
  /// control the preview.
  Future<PreviewSession> startPreview(
    String projectPath, {
    PreviewMethod? preferredMethod,
  }) async {
    _ensureInitialized();

    // Stop any existing session for this project.
    if (_activeSessions.containsKey(projectPath)) {
      debugPrint('[BuildOrchestrator] Stopping existing session for: $projectPath');
      await stopPreview(projectPath);
    }

    final method = preferredMethod ?? await determineMethod(projectPath);
    debugPrint('[BuildOrchestrator] Starting preview with method: $method');

    final stopwatch = Stopwatch()..start();

    try {
      switch (method) {
        case PreviewMethod.flutterWeb:
          return await _startFlutterWebPreview(projectPath);

        case PreviewMethod.flutterApk:
          return await _startFlutterApkPreview(projectPath);

        case PreviewMethod.webview:
          return await _startWebviewPreview(projectPath);

        case PreviewMethod.terminal:
          return await _startTerminalPreview(projectPath);

        case PreviewMethod.remote:
          return await _startRemotePreview(projectPath);
      }
    } catch (e) {
      stopwatch.stop();
      debugPrint('[BuildOrchestrator] Preview start failed: $e');
      _eventController.add(OrchestratorEvent(
        type: OrchestratorEventType.error,
        projectPath: projectPath,
        method: method,
        message: 'Preview failed: $e',
      ));
      rethrow;
    }
  }

  /// Stop a preview session for a project.
  Future<void> stopPreview(String projectPath) async {
    final session = _activeSessions.remove(projectPath);
    if (session != null) {
      debugPrint('[BuildOrchestrator] Stopping preview: $projectPath');
      try {
        await session.stop();
        _eventController.add(OrchestratorEvent(
          type: OrchestratorEventType.stopped,
          projectPath: projectPath,
          method: session.method,
          message: 'Preview stopped',
        ));
      } catch (e) {
        debugPrint('[BuildOrchestrator] Error stopping preview: $e');
      }
    }
  }

  /// Stop all active preview sessions.
  Future<void> stopAllPreviews() async {
    final paths = _activeSessions.keys.toList();
    for (final path in paths) {
      await stopPreview(path);
    }
  }

  // ═════════════════════════════════════════════════════════════════
  // Build for Production
  // ═════════════════════════════════════════════════════════════════

  /// Build a project for production.
  ///
  /// Creates a release build suitable for distribution.
  Future<BuildResult> buildProduction(String projectPath) async {
    _ensureInitialized();

    debugPrint('[BuildOrchestrator] Building for production: $projectPath');

    final projectType = await _detectProjectType(projectPath);

    switch (projectType) {
      case ProjectType.flutter:
        // For Flutter, build APK in release mode.
        final termuxReady = await _termux.isSetupComplete();
        if (!termuxReady) {
          return BuildResult(
            success: false,
            error: 'Termux setup incomplete. Run setup wizard first.',
            buildTime: Duration.zero,
          );
        }

        _eventController.add(OrchestratorEvent(
          type: OrchestratorEventType.buildStarted,
          projectPath: projectPath,
          method: PreviewMethod.flutterApk,
          message: 'Starting release APK build...',
        ));

        final result = await _termux.buildApk(
          projectPath,
          mode: BuildMode.release,
        );

        _eventController.add(OrchestratorEvent(
          type: result.success
              ? OrchestratorEventType.buildCompleted
              : OrchestratorEventType.error,
          projectPath: projectPath,
          method: PreviewMethod.flutterApk,
          message: result.success
              ? 'Release APK built: ${result.outputPath}'
              : 'Build failed: ${result.error}',
        ));

        return result;

      case ProjectType.react:
      case ProjectType.vue:
      case ProjectType.node:
        return await _termux.execute('npm run build', workingDir: projectPath).then(
          (r) => BuildResult(
            success: r.success,
            outputPath: p.join(projectPath, 'build'),
            error: r.stderr.isNotEmpty ? r.stderr : null,
            buildTime: r.duration,
          ),
        );

      case ProjectType.dart:
        return await _termux.execute('dart compile exe bin/main.dart', workingDir: projectPath).then(
          (r) => BuildResult(
            success: r.success,
            error: r.stderr.isNotEmpty ? r.stderr : null,
            buildTime: r.duration,
          ),
        );

      default:
        return BuildResult(
          success: false,
          error: 'Production build not supported for project type: $projectType',
          buildTime: Duration.zero,
        );
    }
  }

  // ═════════════════════════════════════════════════════════════════
  // Private Preview Starters
  // ═════════════════════════════════════════════════════════════════

  /// Start a Flutter Web preview.
  Future<PreviewSession> _startFlutterWebPreview(String projectPath) async {
    debugPrint('[BuildOrchestrator] Starting Flutter Web preview');

    final logController = StreamController<String>.broadcast();
    final stopController = StreamController<void>.broadcast();

    // Subscribe to Termux build logs.
    final logSubscription = _termux.buildLogStream.listen(
      (line) => logController.add(line),
      onError: (e) => logController.add('[error] $e'),
    );

    // Build the web output.
    final buildResult = await _termux.buildWeb(projectPath);

    if (!buildResult.success) {
      await logSubscription.cancel();
      await logController.close();
      await stopController.close();
      throw BuildOrchestratorException(
        'Flutter Web build failed: ${buildResult.error}',
      );
    }

    final indexHtmlPath = p.join(buildResult.outputPath!, 'index.html');

    final session = PreviewSession(
      method: PreviewMethod.flutterWeb,
      previewUrl: indexHtmlPath,
      status: 'Web preview ready',
      logStream: logController.stream,
      stop: () async {
        debugPrint('[BuildOrchestrator] Stopping Flutter Web preview');
        await logSubscription.cancel();
        await logController.close();
        await stopController.close();
        _activeSessions.remove(projectPath);
      },
    );

    _activeSessions[projectPath] = session;

    _eventController.add(OrchestratorEvent(
      type: OrchestratorEventType.started,
      projectPath: projectPath,
      method: PreviewMethod.flutterWeb,
      message: 'Flutter Web preview ready: $indexHtmlPath',
    ));

    return session;
  }

  /// Start a Flutter APK preview.
  Future<PreviewSession> _startFlutterApkPreview(String projectPath) async {
    debugPrint('[BuildOrchestrator] Starting Flutter APK preview');

    final logController = StreamController<String>.broadcast();

    // Subscribe to Termux build logs.
    final logSubscription = _termux.buildLogStream.listen(
      (line) => logController.add(line),
      onError: (e) => logController.add('[error] $e'),
    );

    // Build debug APK.
    final buildResult = await _termux.buildApk(
      projectPath,
      mode: BuildMode.debug,
    );

    if (!buildResult.success) {
      await logSubscription.cancel();
      await logController.close();
      throw BuildOrchestratorException(
        'APK build failed: ${buildResult.error}',
      );
    }

    // Install the APK.
    logController.add('[install] Installing APK...');
    final installResult = await _termux.installApk(buildResult.outputPath!);

    if (!installResult.success) {
      await logSubscription.cancel();
      await logController.close();
      throw BuildOrchestratorException(
        'APK install failed: ${installResult.error}',
      );
    }

    // Launch the app.
    await _termux.launchApp(installResult.packageName);

    final session = PreviewSession(
      method: PreviewMethod.flutterApk,
      previewUrl: buildResult.outputPath,
      status: 'APK installed and launched',
      logStream: logController.stream,
      stop: () async {
        debugPrint('[BuildOrchestrator] Stopping APK preview');
        await _termux.uninstallApp(installResult.packageName);
        await logSubscription.cancel();
        await logController.close();
        _activeSessions.remove(projectPath);
      },
    );

    _activeSessions[projectPath] = session;

    _eventController.add(OrchestratorEvent(
      type: OrchestratorEventType.started,
      projectPath: projectPath,
      method: PreviewMethod.flutterApk,
      message: 'APK installed: ${installResult.packageName}',
    ));

    return session;
  }

  /// Start a WebView preview for HTML/JS projects.
  Future<PreviewSession> _startWebviewPreview(String projectPath) async {
    debugPrint('[BuildOrchestrator] Starting WebView preview');

    final indexPath = p.join(projectPath, 'index.html');
    final indexFile = File(indexPath);

    // Find the main HTML file.
    String? htmlPath;
    if (await indexFile.exists()) {
      htmlPath = indexPath;
    } else {
      // Search for any HTML file.
      final htmlFiles = await Directory(projectPath)
          .list()
          .where((f) => f is File && f.path.endsWith('.html'))
          .map((f) => f.path)
          .toList();
      if (htmlFiles.isNotEmpty) {
        htmlPath = htmlFiles.first;
      }
    }

    if (htmlPath == null) {
      throw BuildOrchestratorException('No HTML file found in project');
    }

    final logController = StreamController<String>.broadcast();
    logController.add('[preview] WebView ready: $htmlPath');

    final session = PreviewSession(
      method: PreviewMethod.webview,
      previewUrl: htmlPath,
      status: 'WebView ready',
      logStream: logController.stream,
      stop: () async {
        debugPrint('[BuildOrchestrator] Stopping WebView preview');
        await logController.close();
        _activeSessions.remove(projectPath);
      },
    );

    _activeSessions[projectPath] = session;

    _eventController.add(OrchestratorEvent(
      type: OrchestratorEventType.started,
      projectPath: projectPath,
      method: PreviewMethod.webview,
      message: 'WebView preview: $htmlPath',
    ));

    return session;
  }

  /// Start a terminal preview for Python/terminal projects.
  Future<PreviewSession> _startTerminalPreview(String projectPath) async {
    debugPrint('[BuildOrchestrator] Starting Terminal preview');

    final logController = StreamController<String>.broadcast();

    logController.add('[preview] Terminal preview active');
    logController.add('[preview] Project: $projectPath');

    final session = PreviewSession(
      method: PreviewMethod.terminal,
      previewUrl: null,
      status: 'Terminal active',
      logStream: logController.stream,
      stop: () async {
        debugPrint('[BuildOrchestrator] Stopping Terminal preview');
        await logController.close();
        _activeSessions.remove(projectPath);
      },
    );

    _activeSessions[projectPath] = session;

    _eventController.add(OrchestratorEvent(
      type: OrchestratorEventType.started,
      projectPath: projectPath,
      method: PreviewMethod.terminal,
      message: 'Terminal preview started',
    ));

    return session;
  }

  /// Start a remote build preview (placeholder for future implementation).
  Future<PreviewSession> _startRemotePreview(String projectPath) async {
    debugPrint('[BuildOrchestrator] Starting Remote preview');

    final logController = StreamController<String>.broadcast();
    logController.add('[preview] Remote build preview started');

    final session = PreviewSession(
      method: PreviewMethod.remote,
      previewUrl: null,
      status: 'Remote build queued',
      logStream: logController.stream,
      stop: () async {
        debugPrint('[BuildOrchestrator] Stopping Remote preview');
        await logController.close();
        _activeSessions.remove(projectPath);
      },
    );

    _activeSessions[projectPath] = session;

    _eventController.add(OrchestratorEvent(
      type: OrchestratorEventType.started,
      projectPath: projectPath,
      method: PreviewMethod.remote,
      message: 'Remote build started',
    ));

    return session;
  }

  // ═════════════════════════════════════════════════════════════════
  // Utility
  // ═════════════════════════════════════════════════════════════════

  void _ensureInitialized() {
    if (!_initialized) {
      throw const BuildOrchestratorException(
          'BuildOrchestrator not initialized. Call initialize() first.');
    }
  }

  /// Clear the project type cache.
  void clearCache() {
    _projectTypeCache.clear();
    debugPrint('[BuildOrchestrator] Cache cleared');
  }

  /// Dispose all resources.
  void dispose() {
    stopAllPreviews();
    if (!_eventController.isClosed) {
      _eventController.close();
    }
    _initialized = false;
    debugPrint('[BuildOrchestrator] Disposed');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Enums
// ═══════════════════════════════════════════════════════════════════════════

/// Available preview methods.
enum PreviewMethod {
  /// WebView preview for HTML/JS projects.
  webview,

  /// Flutter Web build preview (fast).
  flutterWeb,

  /// Flutter APK build and install (real app).
  flutterApk,

  /// Terminal output for interpreted languages.
  terminal,

  /// Remote build on a server.
  remote,
}

/// Project type detected from directory contents.
enum ProjectType {
  flutter,
  dart,
  react,
  vue,
  node,
  python,
  html,
  unknown,
}

/// Event types for the orchestrator event stream.
enum OrchestratorEventType {
  started,
  stopped,
  buildStarted,
  buildCompleted,
  error,
}

// ═══════════════════════════════════════════════════════════════════════════
// Data Classes
// ═══════════════════════════════════════════════════════════════════════════

/// An active preview session.
class PreviewSession {
  /// The preview method being used.
  final PreviewMethod method;

  /// Path or URL to the preview content.
  final String? previewUrl;

  /// Human-readable status message.
  final String? status;

  /// Stream of log output from the preview.
  final Stream<String>? logStream;

  /// Function to stop this preview session.
  final Future<void> Function() stop;

  PreviewSession({
    required this.method,
    this.previewUrl,
    this.status,
    this.logStream,
    required this.stop,
  });

  @override
  String toString() => 'PreviewSession($method, status=$status)';
}

/// Event emitted by the BuildOrchestrator.
class OrchestratorEvent {
  /// Type of event.
  final OrchestratorEventType type;

  /// Project path this event relates to.
  final String projectPath;

  /// Preview method involved.
  final PreviewMethod? method;

  /// Human-readable message.
  final String message;

  OrchestratorEvent({
    required this.type,
    required this.projectPath,
    this.method,
    required this.message,
  });

  @override
  String toString() => 'OrchestratorEvent($type, $projectPath, $message)';
}

// ═══════════════════════════════════════════════════════════════════════════
// Exceptions
// ═══════════════════════════════════════════════════════════════════════════

/// Exception thrown by the Build Orchestrator.
class BuildOrchestratorException implements Exception {
  final String message;

  const BuildOrchestratorException(this.message);

  @override
  String toString() => 'BuildOrchestratorException: $message';
}
