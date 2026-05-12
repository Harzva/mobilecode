import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// FPS TRACKER — Real-time frame-rate monitoring for Flutter apps
// ═══════════════════════════════════════════════════════════════════════════════

/// Performance grade classification based on FPS thresholds.
///
/// - [excellent] : 55–60 FPS  → smooth, no perceptible drops
/// - [good]      : 45–54 FPS  → minor drops, still comfortable
/// - [fair]      : 30–44 FPS  → noticeable stutter
/// - [poor]      :  0–29 FPS  → severe jank
enum FpsGrade { excellent, good, fair, poor }

// ───────────────────────────────────────────────────────────────────────────────
// Data model
// ───────────────────────────────────────────────────────────────────────────────

/// Immutable snapshot of FPS metrics emitted every second.
class FpsData {
  const FpsData({
    required this.currentFps,
    required this.averageFps,
    required this.droppedFrames,
    required this.frameTimeMs,
    required this.grade,
    required this.timestamp,
    required this.totalFrames,
    required this.percentile95FrameTimeMs,
    required this.percentile99FrameTimeMs,
    this.jankSpikeCount = 0,
  });

  /// Frames rendered during the last 1-second window.
  final double currentFps;

  /// Rolling average over the last 60 seconds.
  final double averageFps;

  /// Cumulative count of frames that missed the 16.67 ms budget.
  final int droppedFrames;

  /// Mean frame duration (ms) in the last window.
  final double frameTimeMs;

  /// Derived performance grade.
  final FpsGrade grade;

  /// When this snapshot was captured.
  final DateTime timestamp;

  /// Total frames processed since tracking started.
  final int totalFrames;

  /// 95th percentile frame time (ms) — useful for detecting outliers.
  final double percentile95FrameTimeMs;

  /// 99th percentile frame time (ms) — highlights severe spikes.
  final double percentile99FrameTimeMs;

  /// Number of severe jank spikes (> 100 ms) in the last window.
  final int jankSpikeCount;

  // ── Convenience getters ──────────────────────────────────────────────

  /// Localised Chinese label for the grade.
  String get gradeLabel {
    switch (grade) {
      case FpsGrade.excellent:
        return '流畅';
      case FpsGrade.good:
        return '良好';
      case FpsGrade.fair:
        return '一般';
      case FpsGrade.poor:
        return '卡顿';
    }
  }

  /// Emoji visual indicator for the grade.
  String get gradeEmoji {
    switch (grade) {
      case FpsGrade.excellent:
        return '🚀';
      case FpsGrade.good:
        return '✅';
      case FpsGrade.fair:
        return '⚠️';
      case FpsGrade.poor:
        return '❌';
    }
  }

  /// Background colour hint (hex string) for UI theming.
  String get gradeColorHex {
    switch (grade) {
      case FpsGrade.excellent:
        return '#4CAF50';
      case FpsGrade.good:
        return '#8BC34A';
      case FpsGrade.fair:
        return '#FFC107';
      case FpsGrade.poor:
        return '#F44336';
    }
  }

  /// Copy helper for creating updated snapshots.
  FpsData copyWith({
    double? currentFps,
    double? averageFps,
    int? droppedFrames,
    double? frameTimeMs,
    FpsGrade? grade,
    DateTime? timestamp,
    int? totalFrames,
    double? percentile95FrameTimeMs,
    double? percentile99FrameTimeMs,
    int? jankSpikeCount,
  }) {
    return FpsData(
      currentFps: currentFps ?? this.currentFps,
      averageFps: averageFps ?? this.averageFps,
      droppedFrames: droppedFrames ?? this.droppedFrames,
      frameTimeMs: frameTimeMs ?? this.frameTimeMs,
      grade: grade ?? this.grade,
      timestamp: timestamp ?? this.timestamp,
      totalFrames: totalFrames ?? this.totalFrames,
      percentile95FrameTimeMs:
          percentile95FrameTimeMs ?? this.percentile95FrameTimeMs,
      percentile99FrameTimeMs:
          percentile99FrameTimeMs ?? this.percentile99FrameTimeMs,
      jankSpikeCount: jankSpikeCount ?? this.jankSpikeCount,
    );
  }

  @override
  String toString() =>
      'FpsData(current: ${currentFps.toStringAsFixed(1)} FPS, '
      'avg: ${averageFps.toStringAsFixed(1)} FPS, '
      'grade: $gradeLabel, dropped: $droppedFrames, '
      'spikes: $jankSpikeCount)';
}

// ───────────────────────────────────────────────────────────────────────────────
// FPS Tracker singleton
// ───────────────────────────────────────────────────────────────────────────────

/// Singleton that hooks into Flutter's [SchedulerBinding] to monitor every
/// frame delivered by the engine.
///
/// Usage:
/// ```dart
/// FpsTracker().startTracking();
/// FpsTracker().fpsStream.listen((data) => print(data));
/// FpsTracker().stopTracking();
/// ```
class FpsTracker {
  FpsTracker._internal();

  static final FpsTracker _instance = FpsTracker._internal();
  factory FpsTracker() => _instance;

  // ── Configuration constants ──────────────────────────────────────────

  /// Target frame budget for 60 FPS (ms).
  static const double _kTargetFrameTimeMs = 1000.0 / 60.0; // ~16.67 ms

  /// Threshold above which a frame is counted as "dropped".
  static const double _kDroppedFrameThresholdMs = _kTargetFrameTimeMs;

  /// A "jank spike" is any frame taking longer than 100 ms.
  static const double _kJankSpikeThresholdMs = 100.0;

  /// How often (in seconds) we emit a new [FpsData] snapshot.
  static const int _kReportIntervalSeconds = 1;

  /// Maximum size of the rolling FPS history buffer.
  static const int _kMaxHistoryLength = 60;

  // ── Mutable state ────────────────────────────────────────────────────

  int _frameCount = 0;
  int _totalFrameCount = 0;
  int _droppedFrames = 0;
  double _currentFps = 60.0;
  double _averageFps = 60.0;

  /// Raw frame durations observed during the current 1-second window.
  final List<double> _currentWindowFrameTimes = [];

  /// Historical FPS values (one entry per second).
  final List<double> _fpsHistory = [];

  /// Historical frame-time values (one entry per second, mean value).
  final List<double> _frameTimeHistory = [];

  final StreamController<FpsData> _fpsController =
      StreamController<FpsData>.broadcast();

  Timer? _timer;
  bool _isTracking = false;

  /// Seconds elapsed since tracking started.
  int _elapsedSeconds = 0;

  /// Snapshot of the most recent data (cached for synchronous reads).
  FpsData? _lastData;

  // ── Lifecycle ────────────────────────────────────────────────────────

  /// Begin monitoring frame timings.
  /// Safe to call multiple times — subsequent calls are ignored.
  void startTracking() {
    if (_isTracking) return;
    _isTracking = true;

    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);

    _timer = Timer.periodic(
      const Duration(seconds: _kReportIntervalSeconds),
      (_) => _updateFps(),
    );
  }

  /// Pause monitoring and release the frame callback.
  void stopTracking() {
    _isTracking = false;
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    _timer?.cancel();
    _timer = null;
  }

  /// Release all resources. After calling this the tracker is unusable.
  void dispose() {
    stopTracking();
    if (!_fpsController.isClosed) {
      _fpsController.close();
    }
  }

  // ── Frame callback (engine → framework) ──────────────────────────────

  void _onFrameTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _frameCount++;
      _totalFrameCount++;

      final frameTimeMs = timing.totalSpan.inMicroseconds / 1000.0;
      _currentWindowFrameTimes.add(frameTimeMs);

      // Count frames that missed the 16.67 ms budget.
      if (frameTimeMs > _kDroppedFrameThresholdMs) {
        _droppedFrames++;
      }
    }
  }

  // ── Periodic aggregation ─────────────────────────────────────────────

  void _updateFps() {
    _elapsedSeconds++;

    // Derive current FPS from frame count.
    _currentFps = _frameCount.toDouble();

    // Derive mean frame time for the window.
    final meanFrameTimeMs = _currentWindowFrameTimes.isNotEmpty
        ? _currentWindowFrameTimes.reduce((a, b) => a + b) /
            _currentWindowFrameTimes.length
        : 0.0;

    // Compute percentiles.
    final sorted = List<double>.from(_currentWindowFrameTimes)..sort();
    final p95 = _percentile(sorted, 0.95);
    final p99 = _percentile(sorted, 0.99);
    final spikes = _currentWindowFrameTimes
        .where((t) => t > _kJankSpikeThresholdMs)
        .length;

    // Update rolling history.
    _fpsHistory.add(_currentFps);
    if (_fpsHistory.length > _kMaxHistoryLength) {
      _fpsHistory.removeAt(0);
    }

    _frameTimeHistory.add(meanFrameTimeMs);
    if (_frameTimeHistory.length > _kMaxHistoryLength) {
      _frameTimeHistory.removeAt(0);
    }

    // Rolling average.
    _averageFps = _fpsHistory.isNotEmpty
        ? _fpsHistory.reduce((a, b) => a + b) / _fpsHistory.length
        : 0.0;

    final grade = _getGrade(_currentFps);

    final data = FpsData(
      currentFps: _currentFps,
      averageFps: _averageFps,
      droppedFrames: _droppedFrames,
      frameTimeMs: meanFrameTimeMs,
      grade: grade,
      timestamp: DateTime.now(),
      totalFrames: _totalFrameCount,
      percentile95FrameTimeMs: p95,
      percentile99FrameTimeMs: p99,
      jankSpikeCount: spikes,
    );

    _lastData = data;

    if (!_fpsController.isClosed) {
      _fpsController.add(data);
    }

    // Reset window counters.
    _frameCount = 0;
    _currentWindowFrameTimes.clear();
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  FpsGrade _getGrade(double fps) {
    if (fps >= 55) return FpsGrade.excellent;
    if (fps >= 45) return FpsGrade.good;
    if (fps >= 30) return FpsGrade.fair;
    return FpsGrade.poor;
  }

  /// Compute a percentile from a *sorted* list.
  static double _percentile(List<double> sorted, double p) {
    if (sorted.isEmpty) return 0.0;
    if (sorted.length == 1) return sorted.first;
    final idx = p * (sorted.length - 1);
    final lower = idx.floor();
    final upper = idx.ceil();
    if (lower == upper) return sorted[lower];
    final weight = idx - lower;
    return sorted[lower] * (1 - weight) + sorted[upper] * weight;
  }

  // ── Synchronous getters ──────────────────────────────────────────────

  double get currentFps => _currentFps;
  double get averageFps => _averageFps;
  int get droppedFrames => _droppedFrames;
  int get totalFrames => _totalFrameCount;
  bool get isTracking => _isTracking;
  int get elapsedSeconds => _elapsedSeconds;

  /// The stream consumers should listen to for real-time updates.
  Stream<FpsData> get fpsStream => _fpsController.stream;

  /// Rolling FPS history (one sample per second, up to 60 entries).
  List<double> get fpsHistory => List.unmodifiable(_fpsHistory);

  /// Rolling frame-time history (mean per second, up to 60 entries).
  List<double> get frameTimeHistory => List.unmodifiable(_frameTimeHistory);

  /// The most recently computed data snapshot (may be `null` before first tick).
  FpsData? get lastData => _lastData;

  // ── Diagnostics / export ─────────────────────────────────────────────

  /// Reset all counters and history. Does **not** change tracking state.
  void reset() {
    _frameCount = 0;
    _totalFrameCount = 0;
    _droppedFrames = 0;
    _currentFps = 60.0;
    _averageFps = 60.0;
    _elapsedSeconds = 0;
    _fpsHistory.clear();
    _frameTimeHistory.clear();
    _currentWindowFrameTimes.clear();
    _lastData = null;
  }

  /// Export a JSON-friendly map for crash reporting or remote analytics.
  Map<String, dynamic> toReportMap() {
    return {
      'currentFps': _currentFps,
      'averageFps': _averageFps,
      'droppedFrames': _droppedFrames,
      'totalFrames': _totalFrameCount,
      'elapsedSeconds': _elapsedSeconds,
      'fpsHistory': List<double>.from(_fpsHistory),
      'frameTimeHistoryMs': List<double>.from(_frameTimeHistory),
      'grade': _getGrade(_currentFps).name,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  @override
  String toString() =>
      'FpsTracker(tracking: $_isTracking, current: ${_currentFps.toStringAsFixed(1)} FPS, '
      'avg: ${_averageFps.toStringAsFixed(1)} FPS, dropped: $_droppedFrames, '
      'history: ${_fpsHistory.length}s)';
}

// ───────────────────────────────────────────────────────────────────────────────
// Smoothness estimator (optional helper)
// ───────────────────────────────────────────────────────────────────────────────

/// Computes a single smoothness score (0.0 – 1.0) from a list of frame times.
///
/// A score of `1.0` means every frame hit the target budget perfectly;
/// `0.0` means every frame missed by a wide margin.
class SmoothnessEstimator {
  SmoothnessEstimator._();

  /// Target frame budget in ms (default 16.67 ms for 60 FPS).
  static const double _kBudgetMs = 16.67;

  /// Score each frame and average.
  ///
  /// [frameTimesMs] — list of individual frame durations in milliseconds.
  static double estimate(List<double> frameTimesMs) {
    if (frameTimesMs.isEmpty) return 1.0;

    double totalScore = 0.0;
    for (final t in frameTimesMs) {
      totalScore += _frameScore(t);
    }
    return totalScore / frameTimesMs.length;
  }

  static double _frameScore(double frameTimeMs) {
    if (frameTimeMs <= _kBudgetMs) return 1.0;
    // Linear penalty up to 3× budget, then clamped at 0.
    final ratio = frameTimeMs / _kBudgetMs;
    return math.max(0.0, 1.0 - (ratio - 1.0) / 2.0);
  }

  /// Human-readable label for a smoothness score.
  static String label(double score) {
    if (score >= 0.95) return '丝滑';
    if (score >= 0.85) return '流畅';
    if (score >= 0.70) return '基本流畅';
    if (score >= 0.50) return '轻微卡顿';
    return '明显卡顿';
  }
}
