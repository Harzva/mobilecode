// lib/providers/preview_provider.dart
// Preview Provider — Riverpod state management for the preview system.
//
// Provides reactive state for preview URL, device selection, zoom,
// orientation, auto-reload, and split view settings.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/preview_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Preview State
// ═══════════════════════════════════════════════════════════════════════════

/// Immutable state object for the preview system.
@immutable
class PreviewState {
  final bool isServerRunning;
  final String? previewUrl;
  final String? projectPath;
  final String selectedDeviceName;
  final bool isLandscape;
  final double zoomLevel;
  final bool autoReloadEnabled;
  final bool isSplitView;
  final double splitRatio;
  final bool showDeviceFrame;
  final bool isFullScreen;
  final String? error;
  final bool isLoading;

  DeviceViewport? get selectedDevice =>
      PreviewService.devicePresets[selectedDeviceName];

  const PreviewState({
    this.isServerRunning = false,
    this.previewUrl,
    this.projectPath,
    this.selectedDeviceName = 'iPhone 14',
    this.isLandscape = false,
    this.zoomLevel = 1.0,
    this.autoReloadEnabled = true,
    this.isSplitView = false,
    this.splitRatio = 0.5,
    this.showDeviceFrame = true,
    this.isFullScreen = false,
    this.error,
    this.isLoading = false,
  });

  PreviewState copyWith({
    bool? isServerRunning, String? previewUrl, String? projectPath,
    String? selectedDeviceName, bool? isLandscape, double? zoomLevel,
    bool? autoReloadEnabled, bool? isSplitView, double? splitRatio,
    bool? showDeviceFrame, bool? isFullScreen, String? error,
    bool? isLoading, bool clearError = false,
    bool clearUrl = false, bool clearProjectPath = false,
  }) => PreviewState(
    isServerRunning: isServerRunning ?? this.isServerRunning,
    previewUrl: clearUrl ? null : (previewUrl ?? this.previewUrl),
    projectPath: clearProjectPath ? null
      : (projectPath ?? this.projectPath),
    selectedDeviceName: selectedDeviceName ?? this.selectedDeviceName,
    isLandscape: isLandscape ?? this.isLandscape,
    zoomLevel: zoomLevel ?? this.zoomLevel,
    autoReloadEnabled: autoReloadEnabled ?? this.autoReloadEnabled,
    isSplitView: isSplitView ?? this.isSplitView,
    splitRatio: splitRatio ?? this.splitRatio,
    showDeviceFrame: showDeviceFrame ?? this.showDeviceFrame,
    isFullScreen: isFullScreen ?? this.isFullScreen,
    error: clearError ? null : (error ?? this.error),
    isLoading: isLoading ?? this.isLoading,
  );

  @override
  bool operator ==(Object other) =>
    identical(this, other) || other is PreviewState &&
    other.isServerRunning == isServerRunning &&
    other.previewUrl == previewUrl &&
    other.projectPath == projectPath &&
    other.selectedDeviceName == selectedDeviceName &&
    other.isLandscape == isLandscape &&
    other.zoomLevel == zoomLevel &&
    other.autoReloadEnabled == autoReloadEnabled &&
    other.isSplitView == isSplitView &&
    other.splitRatio == splitRatio &&
    other.showDeviceFrame == showDeviceFrame &&
    other.isFullScreen == isFullScreen &&
    other.error == error &&
    other.isLoading == isLoading;

  @override
  int get hashCode => Object.hash(isServerRunning, previewUrl, projectPath,
    selectedDeviceName, isLandscape, zoomLevel, autoReloadEnabled,
    isSplitView, splitRatio, showDeviceFrame, isFullScreen, error, isLoading);

  @override
  String toString() => 'PreviewState(url=$previewUrl, device=$selectedDeviceName, '
    'zoom=${zoomLevel.toStringAsFixed(1)}x, landscape=$isLandscape)';
}

// ═══════════════════════════════════════════════════════════════════════════
// Preview Notifier
// ═══════════════════════════════════════════════════════════════════════════

/// Riverpod StateNotifier managing preview business logic.
class PreviewNotifier extends StateNotifier<PreviewState> {
  final PreviewService _service = PreviewService();
  StreamSubscription<void>? _reloadSub;

  PreviewNotifier() : super(const PreviewState());

  // ── Server Control ───────────────────────────────────────────────

  Future<void> startPreview(String path) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final url = await _service.startPreview(path);
      state = state.copyWith(isLoading: false, isServerRunning: true,
        previewUrl: url, projectPath: path);
      _subscribeToReload();
    } catch (e) {
      state = state.copyWith(isLoading: false,
        error: 'Failed to start preview: \$e');
    }
  }

  Future<void> stopPreview() async {
    await _service.stopPreview(); _reloadSub?.cancel();
    state = state.copyWith(isServerRunning: false,
      clearUrl: true, clearProjectPath: true, clearError: true);
  }

  Future<void> restartPreview() async {
    final p = state.projectPath; if (p == null) return;
    await stopPreview(); await startPreview(p);
  }

  void triggerReload() => _service.triggerReload();

  // ── Device Control ───────────────────────────────────────────────

  void selectDevice(String name) {
    if (PreviewService.devicePresets.containsKey(name)) {
      state = state.copyWith(selectedDeviceName: name);
    }
  }

  void toggleOrientation() {
    state = state.copyWith(isLandscape: !state.isLandscape);
  }

  // ── Zoom Control ─────────────────────────────────────────────────

  void setZoom(double z) => state = state.copyWith(
    zoomLevel: z.clamp(0.3, 3.0));
  void zoomIn() => setZoom(state.zoomLevel + 0.1);
  void zoomOut() => setZoom(state.zoomLevel - 0.1);
  void resetZoom() => setZoom(1.0);

  // ── View Mode ────────────────────────────────────────────────────

  void toggleSplitView() {
    state = state.copyWith(isSplitView: !state.isSplitView);
  }

  void setSplitRatio(double r) {
    state = state.copyWith(splitRatio: r.clamp(0.2, 0.8));
  }

  void toggleDeviceFrame() {
    state = state.copyWith(showDeviceFrame: !state.showDeviceFrame);
  }

  void toggleFullScreen() {
    state = state.copyWith(isFullScreen: !state.isFullScreen);
  }

  // ── Auto Reload ──────────────────────────────────────────────────

  void toggleAutoReload() {
    state = state.copyWith(
      autoReloadEnabled: !state.autoReloadEnabled);
    if (state.autoReloadEnabled) { _subscribeToReload(); }
    else { _reloadSub?.cancel(); }
  }

  // ── Internal ─────────────────────────────────────────────────────

  void _subscribeToReload() {
    _reloadSub?.cancel();
    _reloadSub = _service.onFileChange.listen((_) {});
  }

  @override
  void dispose() {
    _reloadSub?.cancel();
    _service.dispose();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Riverpod Providers
// ═══════════════════════════════════════════════════════════════════════════

/// Primary preview state provider.
final previewProvider = StateNotifierProvider<PreviewNotifier, PreviewState>(
  (ref) => PreviewNotifier());

/// Current preview URL (null if server not running).
final previewUrlProvider = Provider<String?>((ref) =>
  ref.watch(previewProvider).previewUrl);

/// Currently selected device viewport.
final selectedDeviceProvider = Provider<DeviceViewport?>((ref) =>
  ref.watch(previewProvider).selectedDevice);

/// Whether the preview server is active.
final isServerRunningProvider = Provider<bool>((ref) =>
  ref.watch(previewProvider).isServerRunning);

/// Whether the server is starting.
final isPreviewLoadingProvider = Provider<bool>((ref) =>
  ref.watch(previewProvider).isLoading);

/// Error message or null.
final previewErrorProvider = Provider<String?>((ref) =>
  ref.watch(previewProvider).error);

/// Sorted device preset names.
final deviceNamesProvider = Provider<List<String>>((ref) {
  final s = PreviewService();
  return s.deviceNames;
});

/// Stream for auto-reload events.
final reloadStreamProvider = Provider<Stream<void>>((ref) {
  final s = PreviewService();
  return s.onFileChange;
});
