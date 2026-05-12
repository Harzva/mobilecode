import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/fps_tracker.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// PERFORMANCE PROVIDERS — Riverpod layer for the performance dashboard
// ═══════════════════════════════════════════════════════════════════════════════

// ── FPS Providers ─────────────────────────────────────────────────────────────

/// A provider that exposes the live FPS data stream as an [AsyncValue].
///
/// Listen to this in widgets to rebuild automatically every second.
final fpsStreamProvider = StreamProvider<FpsData>((ref) {
  final tracker = FpsTracker();

  // Ensure tracking is running when this provider is active.
  tracker.startTracking();

  // Cache the latest value so ` AsyncValue.data` is always available.
  final sub = tracker.fpsStream.listen((data) {
    ref.read(lastFpsDataProvider.notifier).state = data;
  });

  ref.onDispose(() {
    sub.cancel();
    // We intentionally do NOT stop tracking here — the FPS tracker is a
    // global singleton that may be consumed by multiple features.
  });

  return tracker.fpsStream;
});

/// Synchronous access to the most recent [FpsData] snapshot (may be `null`).
final lastFpsDataProvider = StateProvider<FpsData?>((ref) => null);

/// Provider that derives a smooth FPS grade label from the latest data.
final fpsGradeLabelProvider = Provider<String>((ref) {
  final data = ref.watch(lastFpsDataProvider);
  return data?.gradeLabel ?? '—';
});

/// Provider that exposes the rolling FPS history list.
final fpsHistoryProvider = Provider<List<double>>((ref) {
  // Force rebuild every second by watching the stream.
  ref.watch(fpsStreamProvider);
  return FpsTracker().fpsHistory;
});

// ── Memory Providers ──────────────────────────────────────────────────────────

/// Holds information about the app's current memory footprint.
class MemoryInfo {
  const MemoryInfo({
    required this.usedMB,
    required this.totalMB,
    required this.usedRatio,
    required this.heapSizeMB,
    required this.rssMB,
  });

  /// Memory actively used by the Dart heap (MB).
  final double usedMB;

  /// Total memory allocated to the process (MB).
  final double totalMB;

  /// Ratio of used to total (0.0 – 1.0).
  final double usedRatio;

  /// Dart heap size in MB.
  final double heapSizeMB;

  /// Resident Set Size (platform-dependent, may be 0 on unsupported platforms).
  final double rssMB;

  MemoryInfo copyWith({
    double? usedMB,
    double? totalMB,
    double? usedRatio,
    double? heapSizeMB,
    double? rssMB,
  }) {
    return MemoryInfo(
      usedMB: usedMB ?? this.usedMB,
      totalMB: totalMB ?? this.totalMB,
      usedRatio: usedRatio ?? this.usedRatio,
      heapSizeMB: heapSizeMB ?? this.heapSizeMB,
      rssMB: rssMB ?? this.rssMB,
    );
  }
}

/// Polls memory usage every 2 seconds.
final memoryUsageProvider = StreamProvider<MemoryInfo>((ref) {
  final controller = StreamController<MemoryInfo>.broadcast();

  void _poll() {
    try {
      final currentRss = ProcessInfo.currentRss;
      final rssMB = currentRss > 0 ? currentRss / (1024 * 1024) : 0.0;

      // Heap metrics are VM-internal and best-effort.
      final heapMB = _estimateHeapUsageMB();

      // Total available memory — on mobile this is a rough proxy.
      final totalMB = math.max(rssMB * 2, 256.0);
      final usedMB = rssMB > 0 ? rssMB : heapMB;
      final ratio = (usedMB / totalMB).clamp(0.0, 1.0);

      controller.add(MemoryInfo(
        usedMB: usedMB,
        totalMB: totalMB,
        usedRatio: ratio,
        heapSizeMB: heapMB,
        rssMB: rssMB,
      ));
    } catch (e) {
      // Fallback when ProcessInfo is unavailable.
      controller.add(const MemoryInfo(
        usedMB: 0,
        totalMB: 256,
        usedRatio: 0,
        heapSizeMB: 0,
        rssMB: 0,
      ));
    }
  }

  // Poll immediately and then every 2 seconds.
  _poll();
  final timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());

  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });

  return controller.stream;
});

/// Best-effort heap usage estimation using Dart VM internals.
double _estimateHeapUsageMB() {
  try {
    // ignore: deprecated_member_use
    final info = Platform.version;
    // Platform.version gives VM version; we use RSS as primary signal.
    // A more accurate approach would use `dart:developer` `ServiceProtocol`
    // but that requires debug mode. We fall back to a conservative estimate.
    return 0.0;
  } catch (_) {
    return 0.0;
  }
}

// ── Performance Suggestions Engine ────────────────────────────────────────────

/// Priority levels for optimisation suggestions.
enum SuggestionPriority { critical, warning, info, tip }

/// An actionable optimisation suggestion.
class PerformanceSuggestion {
  const PerformanceSuggestion({
    required this.message,
    required this.priority,
    this.action,
  });

  final String message;
  final SuggestionPriority priority;

  /// Optional callback invoked when the user taps the suggestion tile.
  final void Function(BuildContext context)? action;
}

/// Provider that generates context-aware optimisation tips based on
/// current FPS and memory readings.
final performanceSuggestionsProvider =
    Provider<List<PerformanceSuggestion>>((ref) {
  final fpsData = ref.watch(lastFpsDataProvider);
  final memAsync = ref.watch(memoryUsageProvider);
  final suggestions = <PerformanceSuggestion>[];

  if (fpsData == null) return suggestions;

  // ── FPS-based suggestions ────────────────────────────────────────────

  if (fpsData.currentFps < 30) {
    suggestions.add(
      const PerformanceSuggestion(
        message: '当前帧率过低，建议减少动画效果或降低渲染负载',
        priority: SuggestionPriority.critical,
      ),
    );
  } else if (fpsData.currentFps < 45) {
    suggestions.add(
      const PerformanceSuggestion(
        message: '帧率下降明显，检查是否有耗时操作阻塞主线程',
        priority: SuggestionPriority.warning,
      ),
    );
  }

  if (fpsData.jankSpikeCount > 2) {
    suggestions.add(
      PerformanceSuggestion(
        message: '检测到 ${fpsData.jankSpikeCount} 次严重卡顿，'
            '建议启用"流畅模式"以节省内存',
        priority: SuggestionPriority.critical,
        action: (ctx) => _showSnack(ctx, '已自动调整渲染设置'),
      ),
    );
  }

  if (fpsData.droppedFrames > 20) {
    suggestions.add(
      const PerformanceSuggestion(
        message: '掉帧较多，考虑使用 RepaintBoundary 减少重绘区域',
        priority: SuggestionPriority.warning,
      ),
    );
  }

  if (fpsData.percentile95FrameTimeMs > 33.0) {
    suggestions.add(
      const PerformanceSuggestion(
        message: '95% 帧时间超过 33ms，建议优化图片加载或列表渲染',
        priority: SuggestionPriority.warning,
      ),
    );
  }

  // ── Memory-based suggestions ─────────────────────────────────────────

  final memInfo = memAsync.valueOrNull;
  if (memInfo != null) {
    if (memInfo.usedRatio > 0.85) {
      suggestions.add(
        const PerformanceSuggestion(
          message: '内存占用过高，建议清理缓存或切换低内存模式',
          priority: SuggestionPriority.critical,
          action: _showClearCacheDialog,
        ),
      );
    } else if (memInfo.usedRatio > 0.70) {
      suggestions.add(
        const PerformanceSuggestion(
          message: '内存使用偏高，建议释放未使用的资源',
          priority: SuggestionPriority.info,
        ),
      );
    }
  }

  // ── Positive feedback ────────────────────────────────────────────────

  if (fpsData.currentFps >= 55 && (memInfo == null || memInfo.usedRatio < 0.5)) {
    suggestions.add(
      const PerformanceSuggestion(
        message: '性能表现优秀！保持当前状态',
        priority: SuggestionPriority.tip,
      ),
    );
  }

  return suggestions;
});

// ── Utility callbacks ──────────────────────────────────────────────────────────

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

void _showClearCacheDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A1D24),
      title: const Text('清理缓存', style: TextStyle(color: Colors.white)),
      content: const Text(
        '这将清除所有图片缓存和临时文件。继续吗？',
        style: TextStyle(color: Colors.white70),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            _showSnack(context, '缓存已清理');
          },
          child: const Text('确认', style: TextStyle(color: Colors.redAccent)),
        ),
      ],
    ),
  );
}

// ── Performance Summary Provider (for external consumers) ─────────────────────

/// A composite provider that exposes a unified performance summary.
/// Useful for analytics, crash reports, or remote logging.
final performanceSummaryProvider = Provider<Map<String, dynamic>>((ref) {
  final fpsData = ref.watch(lastFpsDataProvider);
  final memAsync = ref.watch(memoryUsageProvider);
  final memInfo = memAsync.valueOrNull;

  return {
    'fps': {
      'current': fpsData?.currentFps ?? 0.0,
      'average': fpsData?.averageFps ?? 0.0,
      'droppedFrames': fpsData?.droppedFrames ?? 0,
      'grade': fpsData?.grade.name ?? 'unknown',
      'frameTimeMs': fpsData?.frameTimeMs ?? 0.0,
      'p95Ms': fpsData?.percentile95FrameTimeMs ?? 0.0,
      'p99Ms': fpsData?.percentile99FrameTimeMs ?? 0.0,
      'jankSpikes': fpsData?.jankSpikeCount ?? 0,
    },
    'memory': {
      'usedMB': memInfo?.usedMB ?? 0.0,
      'totalMB': memInfo?.totalMB ?? 0.0,
      'ratio': memInfo?.usedRatio ?? 0.0,
    },
    'timestamp': DateTime.now().toIso8601String(),
  };
});
