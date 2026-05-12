// lib/services/preview_service.dart
// Preview Service — Local HTTP server + WebView preview for HTML/CSS/JS projects.
//
// Manages a local shelf HTTP server that serves files from a project directory,
// watches for file changes to auto-reload the preview, and provides device
// viewport simulation presets for mobile/tablet/desktop testing.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Preview Service
// ═══════════════════════════════════════════════════════════════════════════

/// Manages local HTTP server and WebView preview for HTML/CSS/JS projects.
///
/// Features:
/// - Local HTTP server on a dynamically allocated free port
/// - Static file serving from the project directory via shelf
/// - File watching with auto-reload for supported web file types
/// - Multi-device viewport simulation presets
/// - CORS middleware for cross-origin requests
/// - Support for: HTML, React, Vue, Angular, and plain JS projects
///
/// Usage:
/// ```dart
/// final preview = PreviewService();
/// final url = await preview.startPreview('/path/to/project');
/// // Listen for reload events
/// preview.onFileChange.listen((_) { /* trigger WebView reload */ });
/// // Clean up when done
/// await preview.stopPreview();
/// preview.dispose();
/// ```
class PreviewService {
  // Singleton for app-wide preview management
  static final PreviewService _instance = PreviewService._internal();
  factory PreviewService() => _instance;
  PreviewService._internal();

  // ── Internal State ─────────────────────────────────────────────────

  HttpServer? _server;
  String? _projectPath;
  int? _port;
  StreamSubscription<FileSystemEvent>? _fileWatcher;
  final StreamController<void> _reloadController =
      StreamController<void>.broadcast();
  Timer? _reloadDebounce;
  final Set<String> _activeWatchPaths = {};

  // ═══════════════════════════════════════════════════════════════════
  // Server Management
  // ═══════════════════════════════════════════════════════════════════

  /// Start the preview server for a project directory.
  ///
  /// Serves static files from [projectPath] on a dynamically allocated
  /// free port. Returns the preview URL (e.g., `http://127.0.0.1:8080`).
  /// Automatically starts watching for file changes.
  ///
  /// Throws [StateError] if the server fails to start.
  Future<String> startPreview(String projectPath) async {
    await stopPreview();

    _projectPath = projectPath;
    _port = await _findFreePort();

    // Create the request handler pipeline
    final handler = _createHandler(projectPath);

    try {
      _server = await shelf_io.serve(
        handler,
        InternetAddress.loopbackIPv4.address,
        _port!,
        shared: false,
      );

      debugPrint(
        '[PreviewService] Server started at http://127.0.0.1:$_port '
        'serving: $projectPath',
      );

      // Start watching for file changes
      _startFileWatcher(projectPath);

      return 'http://127.0.0.1:$_port';
    } catch (e) {
      debugPrint('[PreviewService] Failed to start server: $e');
      rethrow;
    }
  }

  /// Stop the preview server and clean up resources.
  ///
  /// Cancels file watchers, closes the HTTP server, and resets state.
  /// Safe to call even if the server is not running.
  Future<void> stopPreview() async {
    await _fileWatcher?.cancel();
    _fileWatcher = null;

    await _server?.close(force: true);
    _server = null;

    _reloadDebounce?.cancel();
    _reloadDebounce = null;

    _projectPath = null;
    _port = null;
    _activeWatchPaths.clear();

    debugPrint('[PreviewService] Server stopped');
  }

  /// Restart the preview server with the current project path.
  ///
  /// Useful for manually triggering a full server restart.
  Future<String?> restartPreview() async {
    if (_projectPath == null) {
      debugPrint('[PreviewService] No project path to restart');
      return null;
    }
    final path = _projectPath!;
    return startPreview(path);
  }

  // ── Public Accessors ───────────────────────────────────────────────

  /// The current preview URL, or `null` if the server is not running.
  String? get previewUrl =>
      _port != null ? 'http://127.0.0.1:$_port' : null;

  /// Whether the preview server is currently active.
  bool get isActive => _server != null;

  /// The project path being served, or `null` if not active.
  String? get projectPath => _projectPath;

  /// The port number the server is listening on, or `null` if not active.
  int? get port => _port;

  // ═══════════════════════════════════════════════════════════════════
  // Auto Reload
  // ═══════════════════════════════════════════════════════════════════

  /// Stream that emits whenever a relevant project file changes.
  ///
  /// Listen to this stream to trigger WebView reload on file changes.
  /// Events are debounced to prevent rapid successive reloads.
  Stream<void> get onFileChange => _reloadController.stream;

  /// Manually trigger a reload event.
  ///
  /// Use this to force a reload when programmatically making changes.
  void triggerReload() {
    _reloadController.add(null);
    debugPrint('[PreviewService] Manual reload triggered');
  }

  void _startFileWatcher(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      debugPrint('[PreviewService] Watch directory does not exist: $path');
      return;
    }

    try {
      _fileWatcher = dir.watch(recursive: true).listen(
        _onFileEvent,
        onError: (Object e) {
          debugPrint('[PreviewService] File watcher error: $e');
        },
        onDone: () {
          debugPrint('[PreviewService] File watcher stopped');
        },
      );

      debugPrint('[PreviewService] File watcher started for: $path');
    } on FileSystemException catch (e) {
      debugPrint(
        '[PreviewService] Failed to start file watcher: ${e.message}',
      );
    }
  }

  void _onFileEvent(FileSystemEvent event) {
    // Only reload for relevant web file types
    final path = event.path.toLowerCase();
    if (_isRelevantFile(path)) {
      // Debounce reload events to batch rapid changes
      _reloadDebounce?.cancel();
      _reloadDebounce = Timer(const Duration(milliseconds: 300), () {
        debugPrint('[PreviewService] File changed: ${event.path}');
        _reloadController.add(null);
      });
    }
  }

  bool _isRelevantFile(String path) {
    return path.endsWith('.html') ||
        path.endsWith('.css') ||
        path.endsWith('.js') ||
        path.endsWith('.vue') ||
        path.endsWith('.jsx') ||
        path.endsWith('.tsx') ||
        path.endsWith('.json') ||
        path.endsWith('.svg') ||
        path.endsWith('.png') ||
        path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.gif') ||
        path.endsWith('.webp') ||
        path.endsWith('.ico') ||
        path.endsWith('.woff') ||
        path.endsWith('.woff2') ||
        path.endsWith('.ttf') ||
        path.endsWith('.eot') ||
        path.endsWith('.otf') ||
        path.endsWith('.md');
  }

  // ═══════════════════════════════════════════════════════════════════
  // Device Simulation
  // ═══════════════════════════════════════════════════════════════════

  /// Available device viewport presets for preview simulation.
  ///
  /// Maps device names to their screen dimensions and pixel ratios.
  /// Includes popular phones, tablets, and desktop sizes.
  static final Map<String, DeviceViewport> devicePresets = {
    'iPhone SE': DeviceViewport(
      width: 375,
      height: 667,
      devicePixelRatio: 2,
      userAgent:
          'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15',
    ),
    'iPhone 14': DeviceViewport(
      width: 390,
      height: 844,
      devicePixelRatio: 3,
      userAgent:
          'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15',
    ),
    'iPhone 14 Pro Max': DeviceViewport(
      width: 430,
      height: 932,
      devicePixelRatio: 3,
      userAgent:
          'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15',
    ),
    'Pixel 7': DeviceViewport(
      width: 412,
      height: 915,
      devicePixelRatio: 2.625,
      userAgent:
          'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 Chrome/112.0.0.0 Mobile',
    ),
    'Samsung S23': DeviceViewport(
      width: 384,
      height: 715,
      devicePixelRatio: 3,
      userAgent:
          'Mozilla/5.0 (Linux; Android 13; SM-S911B) AppleWebKit/537.36 Chrome/112.0.0.0 Mobile',
    ),
    'iPad Mini': DeviceViewport(
      width: 768,
      height: 1024,
      devicePixelRatio: 2,
      userAgent:
          'Mozilla/5.0 (iPad; CPU OS 16_0 like Mac OS X) AppleWebKit/605.1.15',
    ),
    'iPad Pro': DeviceViewport(
      width: 1024,
      height: 1366,
      devicePixelRatio: 2,
      userAgent:
          'Mozilla/5.0 (iPad; CPU OS 16_0 like Mac OS X) AppleWebKit/605.1.15',
    ),
    'Desktop 1080p': DeviceViewport(
      width: 1920,
      height: 1080,
      devicePixelRatio: 1,
      userAgent:
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/112.0.0.0',
    ),
    'Desktop 1440p': DeviceViewport(
      width: 2560,
      height: 1440,
      devicePixelRatio: 1,
      userAgent:
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/112.0.0.0',
    ),
  };

  /// Get a sorted list of device preset names.
  List<String> get deviceNames {
    final names = devicePresets.keys.toList();
    // Sort: phones first, then tablets, then desktop
    names.sort((a, b) {
      final aVp = devicePresets[a]!;
      final bVp = devicePresets[b]!;
      return (aVp.width * aVp.height).compareTo(bVp.width * bVp.height);
    });
    return names;
  }

  /// Look up a device viewport by name.
  DeviceViewport? getDeviceViewport(String name) => devicePresets[name];

  // ═══════════════════════════════════════════════════════════════════
  // SPA Support
  // ═══════════════════════════════════════════════════════════════════

  /// Serve a fallback `index.html` for Single Page Applications.
  ///
  /// When enabled, all non-file requests return `index.html` to support
  /// client-side routing in React, Vue, Angular apps.
  bool enableSpaFallback = true;

  // ═══════════════════════════════════════════════════════════════════
  // Internal
  // ═══════════════════════════════════════════════════════════════════

  /// Create the shelf handler pipeline with CORS and static file serving.
  Handler _createHandler(String projectPath) {
    final staticHandler = createStaticHandler(
      projectPath,
      defaultDocument: 'index.html',
      serveFilesOutsidePath: false,
      listDirectories: false,
    );

    return const Pipeline()
        .addMiddleware(_corsMiddleware)
        .addMiddleware(_loggingMiddleware)
        .addHandler(_spaFallbackHandler(staticHandler, projectPath));
  }

  /// Handler that adds SPA fallback support for client-side routing.
  Handler _spaFallbackHandler(Handler staticHandler, String projectPath) {
    final indexFile = File('$projectPath/index.html');
    final indexExists = indexFile.existsSync();

    return (Request request) async {
      // First, try to serve the static file
      final response = await staticHandler(request);

      // If file not found and SPA fallback is enabled, serve index.html
      if (response.statusCode == 404 && enableSpaFallback && indexExists) {
        final ext = request.url.path.toLowerCase();
        // Only fallback for non-API routes and non-file requests
        if (!ext.contains('.') || ext.endsWith('.html')) {
          debugPrint(
            '[PreviewService] SPA fallback: ${request.url.path} -> index.html',
          );
          return Response.ok(
            indexFile.readAsBytesSync(),
            headers: {
              'Content-Type': 'text/html; charset=utf-8',
              'Access-Control-Allow-Origin': '*',
            },
          );
        }
      }

      return response;
    };
  }

  /// Find an available TCP port on the loopback interface.
  Future<int> _findFreePort() async {
    final server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = server.port;
    await server.close();
    debugPrint('[PreviewService] Found free port: $port');
    return port;
  }

  // ── Middleware ─────────────────────────────────────────────────────

  /// CORS middleware for cross-origin requests.
  static Middleware get _corsMiddleware => (Handler innerHandler) {
    return (Request request) async {
      // Handle preflight OPTIONS requests
      if (request.method == 'OPTIONS') {
        return Response.ok(
          null,
          headers: {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods':
                'GET, POST, PUT, DELETE, OPTIONS, HEAD',
            'Access-Control-Allow-Headers':
                'Origin, Content-Type, Accept, Authorization, X-Requested-With',
            'Access-Control-Max-Age': '86400',
          },
        );
      }

      final response = await innerHandler(request);
      return response.change(headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods':
            'GET, POST, PUT, DELETE, OPTIONS, HEAD',
        'Access-Control-Allow-Headers':
            'Origin, Content-Type, Accept, Authorization, X-Requested-With',
        'Access-Control-Expose-Headers': 'Content-Length, Content-Type',
      });
    };
  };

  /// Logging middleware for request debugging.
  static Middleware get _loggingMiddleware => (Handler innerHandler) {
    return (Request request) async {
      final stopwatch = Stopwatch()..start();
      final response = await innerHandler(request);
      stopwatch.stop();

      if (kDebugMode) {
        debugPrint(
          '[PreviewServer] ${request.method} ${request.url.path} '
          '-> ${response.statusCode} (${stopwatch.elapsedMilliseconds}ms)',
        );
      }

      return response;
    };
  };

  // ═══════════════════════════════════════════════════════════════════
  // Lifecycle
  // ═══════════════════════════════════════════════════════════════════

  /// Dispose all resources and stop the server.
  ///
  /// Call this when the service is no longer needed (e.g., app shutdown).
  void dispose() {
    stopPreview();
    if (!_reloadController.isClosed) {
      _reloadController.close();
    }
    debugPrint('[PreviewService] Disposed');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Device Viewport Model
// ═══════════════════════════════════════════════════════════════════════════

/// Represents a device screen viewport for preview simulation.
///
/// Contains the logical width, height, and device pixel ratio used
/// to configure the WebView's viewport for accurate device simulation.
class DeviceViewport {
  /// Logical width in points (not pixels).
  final double width;

  /// Logical height in points (not pixels).
  final double height;

  /// Device pixel ratio (e.g., 2 for Retina, 3 for Super Retina).
  final double devicePixelRatio;

  /// Optional user agent string for the device.
  final String? userAgent;

  /// Whether this device is a mobile phone form factor.
  bool get isPhone => width <= 450;

  /// Whether this device is a tablet form factor.
  bool get isTablet => width > 450 && width <= 1100;

  /// Whether this device is a desktop form factor.
  bool get isDesktop => width > 1100;

  /// Screen area in square points.
  double get area => width * height;

  /// Aspect ratio (width / height).
  double get aspectRatio => width / height;

  const DeviceViewport({
    required this.width,
    required this.height,
    required this.devicePixelRatio,
    this.userAgent,
  });

  /// Create a copy with modified properties.
  DeviceViewport copyWith({
    double? width,
    double? height,
    double? devicePixelRatio,
    String? userAgent,
  }) {
    return DeviceViewport(
      width: width ?? this.width,
      height: height ?? this.height,
      devicePixelRatio: devicePixelRatio ?? this.devicePixelRatio,
      userAgent: userAgent ?? this.userAgent,
    );
  }

  /// Get the viewport in landscape orientation.
  DeviceViewport get landscape => DeviceViewport(
    width: height,
    height: width,
    devicePixelRatio: devicePixelRatio,
    userAgent: userAgent,
  );

  /// Get pixel dimensions (points * DPR).
  double get pixelWidth => width * devicePixelRatio;
  double get pixelHeight => height * devicePixelRatio;

  @override
  String toString() =>
      'DeviceViewport(${width.toInt()}x${height.toInt()} @ ${devicePixelRatio}x)';
}
