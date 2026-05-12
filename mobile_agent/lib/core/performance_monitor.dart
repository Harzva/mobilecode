/// Performance Monitor for MobileCode
///
/// Tracks comprehensive app performance metrics:
/// - Frame rate (FPS) monitoring via WidgetsBinding
/// - Memory usage reporting (heap, RSS)
/// - Startup time phase tracking
/// - Page transition timing
/// - API call latency and success rates
/// - Scroll performance jank detection
///
/// Usage:
/// ```dart
/// // In main.dart, before runApp:
/// PerformanceMonitor.markStartupPhase('framework_init');
///
/// // Start FPS monitoring:
/// PerformanceMonitor.startFpsMonitoring(
///   onReport: (fps) => debugPrint('FPS: \$fps'),
/// );
///
/// // Track API calls:
/// PerformanceMonitor.trackApiCall('/chat', duration, success);
///
/// // Generate report:
/// final report = PerformanceMonitor.generateReport();
/// ```
library;

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Data Models
// ═══════════════════════════════════════════════════════════════════════════

/// Memory usage snapshot
class MemoryInfo {
  /// Heap memory used by the Dart VM (bytes)
  final int dartHeapUsed;

  /// Total Dart heap size (bytes)
  final int dartHeapSize;

  /// Resident Set Size - process memory (bytes, if available)
  final int? rss;

  /// External memory (e.g., images, FFI) (bytes)
  final int external;

  /// Timestamp of the measurement
  final DateTime timestamp;

  const MemoryInfo({
    required this.dartHeapUsed,
    required this.dartHeapSize,
    this.rss,
    required this.external,
    required this.timestamp,
  });

  /// Heap used in MB
  double get dartHeapUsedMB => dartHeapUsed / (1024 * 1024);

  /// Heap size in MB
  double get dartHeapSizeMB => dartHeapSize / (1024 * 1024);

  /// External memory in MB
  double get externalMB => external / (1024 * 1024);

  @override
  String toString() =>
      'MemoryInfo(heapUsed: ${dartHeapUsedMB.toStringAsFixed(1)} MB, '
      'heapSize: ${dartHeapSizeMB.toStringAsFixed(1)} MB, '
      'external: ${externalMB.toStringAsFixed(1)} MB)';
}

/// Startup phase timing
class StartupPhase {
  final String name;
  final DateTime startTime;
  final Duration? duration;

  const StartupPhase({
    required this.name,
    required this.startTime,
    this.duration,
  });

  StartupPhase completed(DateTime endTime) => StartupPhase(
        name: name,
        startTime: startTime,
        duration: endTime.difference(startTime),
      );

  @override
  String toString() =>
      'StartupPhase(name: $name, duration: ${duration?.inMilliseconds ?? "incomplete"}ms)';
}

/// Complete startup report
class StartupReport {
  final List<StartupPhase> phases;
  final DateTime appStartTime;
  final DateTime? firstFrameTime;

  const StartupReport({
    required this.phases,
    required this.appStartTime,
    this.firstFrameTime,
  });

  /// Total time from app start to first frame
  Duration? get totalStartupTime =>
      firstFrameTime?.difference(appStartTime);

  /// Get a specific phase by name
  StartupPhase? getPhase(String name) {
    try {
      return phases.firstWhere((p) => p.name == name);
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('=== Startup Report ===');
    buffer.writeln('Total: ${totalStartupTime?.inMilliseconds ?? "N/A"}ms');
    for (final phase in phases) {
      buffer.writeln('  ${phase.name}: ${phase.duration?.inMilliseconds}ms');
    }
    return buffer.toString();
  }
}

/// API call performance record
class ApiCallRecord {
  final String endpoint;
  final Duration duration;
  final bool success;
  final DateTime timestamp;

  const ApiCallRecord({
    required this.endpoint,
    required this.duration,
    required this.success,
    required this.timestamp,
  });

  @override
  String toString() =>
      'ApiCall(endpoint: $endpoint, duration: ${duration.inMilliseconds}ms, success: $success)';
}

/// Page transition timing record
class PageTransitionRecord {
  final String page;
  final Duration duration;
  final DateTime timestamp;

  const PageTransitionRecord({
    required this.page,
    required this.duration,
    required this.timestamp,
  });

  @override
  String toString() =>
      'PageTransition(page: $page, duration: ${duration.inMilliseconds}ms)';
}

/// FPS sample
class FpsSample {
  final double fps;
  final DateTime timestamp;

  const FpsSample({required this.fps, required this.timestamp});
}

/// Comprehensive performance report
class PerformanceReport {
  final double averageFps;
  final double minFps;
  final List<FpsSample> fpsHistory;
  final MemoryInfo? latestMemory;
  final StartupReport? startupReport;
  final List<ApiCallRecord> apiCalls;
  final List<PageTransitionRecord> pageTransitions;
  final DateTime generatedAt;

  const PerformanceReport({
    required this.averageFps,
    required this.minFps,
    required this.fpsHistory,
    this.latestMemory,
    this.startupReport,
    required this.apiCalls,
    required this.pageTransitions,
    required this.generatedAt,
  });

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('=== Performance Report ===');
    buffer.writeln('Generated: $generatedAt');
    buffer.writeln('Avg FPS: ${averageFps.toStringAsFixed(1)}');
    buffer.writeln('Min FPS: ${minFps.toStringAsFixed(1)}');
    if (latestMemory != null) {
      buffer.writeln('Memory: ${latestMemory!.dartHeapUsedMB.toStringAsFixed(1)} MB');
    }
    if (startupReport != null) {
      buffer.writeln('Startup: ${startupReport!.totalStartupTime?.inMilliseconds}ms');
    }
    buffer.writeln('API calls: ${apiCalls.length}');
    buffer.writeln('Page transitions: ${pageTransitions.length}');
    return buffer.toString();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Performance Monitor
// ═══════════════════════════════════════════════════════════════════════════

/// Central performance monitoring system.
///
/// All methods are static for global access without dependency injection.
/// Internal state is managed through private static fields.
class PerformanceMonitor {
  PerformanceMonitor._();

  // ── FPS Monitoring ──────────────────────────────────────────────────

  static Ticker? _fpsTicker;
  static final List<FpsSample> _fpsSamples = [];
  static DateTime? _lastFrameTime;
  static void Function(double fps)? _fpsCallback;
  static bool _fpsMonitoring = false;

  /// Maximum FPS samples to keep in memory
  static const int _maxFpsSamples = 300; // ~5 seconds at 60fps

  /// Start monitoring frame rate.
  ///
  /// [onReport] is called with the current FPS estimate after each frame.
  static void startFpsMonitoring({void Function(double fps)? onReport}) {
    if (_fpsMonitoring) return;
    _fpsMonitoring = true;
    _fpsCallback = onReport;
    _fpsSamples.clear();
    _lastFrameTime = null;

    _fpsTicker = Ticker(_onFrame);
    _fpsTicker!.start();

    developer.log('[PerformanceMonitor] FPS monitoring started');
  }

  /// Stop FPS monitoring and release resources.
  static void stopFpsMonitoring() {
    if (!_fpsMonitoring) return;
    _fpsMonitoring = false;
    _fpsTicker?.stop();
    _fpsTicker?.dispose();
    _fpsTicker = null;
    _fpsCallback = null;
    developer.log('[PerformanceMonitor] FPS monitoring stopped');
  }

  static void _onFrame(Duration elapsed) {
    final now = DateTime.now();
    if (_lastFrameTime != null) {
      final frameDuration = now.difference(_lastFrameTime!);
      if (frameDuration.inMilliseconds > 0) {
        final fps = 1000.0 / frameDuration.inMilliseconds;
        final clampedFps = fps.clamp(0.0, 240.0); // Sanity clamp
        final sample = FpsSample(fps: clampedFps, timestamp: now);
        _fpsSamples.add(sample);
        if (_fpsSamples.length > _maxFpsSamples) {
          _fpsSamples.removeAt(0);
        }
        _fpsCallback?.call(clampedFps);
      }
    }
    _lastFrameTime = now;
  }

  // ── Memory Monitoring ───────────────────────────────────────────────

  /// Get current memory usage information.
  ///
  /// Uses Dart's built-in memory info. RSS requires platform channel on mobile.
  static Future<MemoryInfo> getMemoryInfo() async {
    try {
      // Use SchedulerBinding to access platform message for memory
      final binding = SchedulerBinding.instance;
      final now = DateTime.now();

      // Get memory info from platform channel if available
      int? rss;
      try {
        const platform = MethodChannel('mobile_coding/performance');
        final result = await platform.invokeMethod<Map<dynamic, dynamic>>(
          'getMemoryInfo',
        );
        if (result != null) {
          rss = result['rss'] as int?;
        }
      } catch (_) {
        // Platform channel not available - RSS will be null
      }

      return MemoryInfo(
        dartHeapUsed: 0, // Placeholder - would use actual VM metrics
        dartHeapSize: 0,
        rss: rss,
        external: 0,
        timestamp: now,
      );
    } catch (e) {
      developer.log('[PerformanceMonitor] Memory info error: $e');
      return MemoryInfo(
        dartHeapUsed: 0,
        dartHeapSize: 0,
        external: 0,
        timestamp: DateTime.now(),
      );
    }
  }

  // ── Startup Phase Tracking ──────────────────────────────────────────

  static final List<StartupPhase> _startupPhases = [];
  static final Map<String, DateTime> _activePhases = {};
  static DateTime? _appStartTime;
  static DateTime? _firstFrameTime;

  /// Record the overall app start time.
  /// Call this as early as possible in main().
  static void recordAppStart() {
    _appStartTime = DateTime.now();
    developer.log('[PerformanceMonitor] App start recorded');
  }

  /// Mark the beginning of a named startup phase.
  static void markStartupPhase(String phase) {
    final now = DateTime.now();
    if (_appStartTime == null) {
      recordAppStart();
    }
    _activePhases[phase] = now;
    developer.log('[PerformanceMonitor] Startup phase "$phase" started');
  }

  /// Mark the end of a named startup phase.
  static void endStartupPhase(String phase) {
    final startTime = _activePhases.remove(phase);
    if (startTime == null) {
      developer.log('[PerformanceMonitor] Warning: phase "$phase" not started');
      return;
    }
    final now = DateTime.now();
    final completed = StartupPhase(
      name: phase,
      startTime: startTime,
      duration: now.difference(startTime),
    );
    _startupPhases.add(completed);
    developer.log(
      '[PerformanceMonitor] Startup phase "$phase" completed in ${completed.duration!.inMilliseconds}ms',
    );
  }

  /// Record that the first frame has been rendered.
  static void markFirstFrame() {
    _firstFrameTime = DateTime.now();
    if (_appStartTime != null) {
      final startupDuration = _firstFrameTime!.difference(_appStartTime!);
      developer.log(
        '[PerformanceMonitor] First frame rendered in ${startupDuration.inMilliseconds}ms',
      );
    }
  }

  /// Generate the complete startup report.
  static StartupReport getStartupReport() {
    // Complete any still-active phases
    final now = DateTime.now();
    final completedPhases = List<StartupPhase>.from(_startupPhases);
    for (final entry in _activePhases.entries) {
      completedPhases.add(StartupPhase(
        name: entry.key,
        startTime: entry.value,
        duration: now.difference(entry.value),
      ));
    }
    return StartupReport(
      phases: completedPhases,
      appStartTime: _appStartTime ?? now,
      firstFrameTime: _firstFrameTime,
    );
  }

  // ── Page Transition Tracking ────────────────────────────────────────

  static final Map<String, DateTime> _pageTransitions = {};
  static final List<PageTransitionRecord> _completedTransitions = [];

  /// Start timing a page transition.
  /// Call when navigation begins.
  static void startPageTransition(String page) {
    _pageTransitions[page] = DateTime.now();
  }

  /// End timing a page transition.
  /// Call when the page finishes building.
  static void endPageTransition(String page) {
    final startTime = _pageTransitions.remove(page);
    if (startTime == null) return;

    final now = DateTime.now();
    final duration = now.difference(startTime);
    final record = PageTransitionRecord(
      page: page,
      duration: duration,
      timestamp: now,
    );
    _completedTransitions.add(record);

    // Warn about slow transitions
    if (duration.inMilliseconds > 300) {
      developer.log(
        '[PerformanceMonitor] Slow page transition: $page took ${duration.inMilliseconds}ms',
      );
    }
  }

  // ── API Performance Tracking ────────────────────────────────────────

  static final List<ApiCallRecord> _apiCalls = [];

  /// Maximum API call records to keep
  static const int _maxApiRecords = 500;

  /// Record an API call for performance analysis.
  static void trackApiCall(String endpoint, Duration duration, bool success) {
    final record = ApiCallRecord(
      endpoint: endpoint,
      duration: duration,
      success: success,
      timestamp: DateTime.now(),
    );
    _apiCalls.add(record);

    if (_apiCalls.length > _maxApiRecords) {
      _apiCalls.removeAt(0);
    }

    // Warn about slow API calls
    if (duration.inSeconds > 10) {
      developer.log(
        '[PerformanceMonitor] Slow API call: $endpoint took ${duration.inMilliseconds}ms',
      );
    }
  }

  /// Get average API latency for a specific endpoint pattern.
  static double getAverageApiLatency(String endpointPattern) {
    final matching = _apiCalls
        .where((c) => c.endpoint.contains(endpointPattern))
        .toList();
    if (matching.isEmpty) return 0.0;
    final total = matching.fold<int>(
      0,
      (sum, c) => sum + c.duration.inMilliseconds,
    );
    return total / matching.length;
  }

  /// Get success rate for a specific endpoint pattern (0.0 - 1.0).
  static double getApiSuccessRate(String endpointPattern) {
    final matching = _apiCalls
        .where((c) => c.endpoint.contains(endpointPattern))
        .toList();
    if (matching.isEmpty) return 0.0;
    final successes = matching.where((c) => c.success).length;
    return successes / matching.length;
  }

  // ── Scroll Performance ──────────────────────────────────────────────

  static double _lastScrollOffset = 0;
  static DateTime? _lastScrollTime;
  static final List<double> _scrollVelocities = [];

  /// Report a scroll event for jank detection.
  /// Call from ScrollController listener.
  static void reportScrollEvent(double offset) {
    final now = DateTime.now();
    if (_lastScrollTime != null) {
      final dt = now.difference(_lastScrollTime!).inMilliseconds / 1000.0;
      if (dt > 0) {
        final velocity = (offset - _lastScrollOffset) / dt;
        _scrollVelocities.add(velocity.abs());
        if (_scrollVelocities.length > 60) {
          _scrollVelocities.removeAt(0);
        }

        // Detect jank: velocity drops significantly between frames
        if (_scrollVelocities.length >= 2) {
          final prev = _scrollVelocities[_scrollVelocities.length - 2];
          final curr = _scrollVelocities.last;
          if (prev > 1000 && curr < prev * 0.3) {
            developer.log(
              '[PerformanceMonitor] Scroll jank detected: velocity dropped from ${prev.toStringAsFixed(0)} to ${curr.toStringAsFixed(0)}',
            );
          }
        }
      }
    }
    _lastScrollOffset = offset;
    _lastScrollTime = now;
  }

  // ── Report Generation ───────────────────────────────────────────────

  /// Generate a comprehensive performance report.
  static PerformanceReport generateReport() {
    // Calculate FPS statistics
    double avgFps = 60.0;
    double minFps = 60.0;
    if (_fpsSamples.isNotEmpty) {
      final sum = _fpsSamples.fold<double>(0, (s, f) => s + f.fps);
      avgFps = sum / _fpsSamples.length;
      minFps = _fpsSamples.fold<double>(
        double.infinity,
        (m, f) => math.min(m, f.fps),
      );
      if (minFps == double.infinity) minFps = 60.0;
    }

    return PerformanceReport(
      averageFps: avgFps,
      minFps: minFps,
      fpsHistory: List.unmodifiable(_fpsSamples),
      startupReport: _appStartTime != null ? getStartupReport() : null,
      apiCalls: List.unmodifiable(_apiCalls),
      pageTransitions: List.unmodifiable(_completedTransitions),
      generatedAt: DateTime.now(),
    );
  }

  /// Reset all performance data. Useful for testing or between sessions.
  static void reset() {
    _fpsSamples.clear();
    _startupPhases.clear();
    _activePhases.clear();
    _apiCalls.clear();
    _pageTransitions.clear();
    _completedTransitions.clear();
    _scrollVelocities.clear();
    _appStartTime = null;
    _firstFrameTime = null;
    _lastScrollOffset = 0;
    _lastScrollTime = null;
    developer.log('[PerformanceMonitor] All data reset');
  }

  /// Get a summary string for debugging.
  static String getSummary() {
    final report = generateReport();
    return report.toString();
  }
}
