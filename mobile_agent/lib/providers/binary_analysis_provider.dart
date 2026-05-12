// lib/providers/binary_analysis_provider.dart
// Binary Analysis Provider — Riverpod state management for binary analysis.
//
// Manages the complete state of the binary analysis module:
// - Current analysis type and file path
// - Loading state during analysis
// - All analysis results (APK, IPA, security, dependencies, quality, size)
// - Computed statistics and summary data

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_agent/screens/binary_analysis_screen.dart';
import 'package:mobile_agent/services/binary_analysis_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// State
// ═══════════════════════════════════════════════════════════════════════════

/// Complete state of the binary analysis module.
///
/// Holds all analysis results and computed statistics.
/// Use [hasResults] to check if any analysis has been performed.
class BinaryAnalysisState {
  final bool isLoading;
  final String? error;

  // Analysis results.
  final ApkAnalysis? apkAnalysis;
  final IpaAnalysis? ipaAnalysis;
  final SecurityScanResult? securityResult;
  final DependencyAnalysis? dependencyAnalysis;
  final CodeQualityMetrics? qualityMetrics;
  final SizeAnalysis? sizeAnalysis;

  // Last analysis metadata.
  final AnalysisType? lastAnalysisType;
  final String? lastAnalyzedPath;

  const BinaryAnalysisState({
    this.isLoading = false,
    this.error,
    this.apkAnalysis,
    this.ipaAnalysis,
    this.securityResult,
    this.dependencyAnalysis,
    this.qualityMetrics,
    this.sizeAnalysis,
    this.lastAnalysisType,
    this.lastAnalyzedPath,
  });

  bool get hasResults => apkAnalysis != null || ipaAnalysis != null || securityResult != null || dependencyAnalysis != null || qualityMetrics != null || sizeAnalysis != null;
  int get totalFiles => apkAnalysis?.dexCount ?? qualityMetrics?.totalFiles ?? sizeAnalysis?.largestFiles.length ?? 0;
  int get totalLines => qualityMetrics?.totalLines ?? 0;
  int get totalIssues => securityResult?.totalIssues ?? 0;
  int get riskScore => securityResult?.riskScore ?? 0;
  int get totalDependencies => dependencyAnalysis?.directDependencies ?? 0;
  String get formattedSize => sizeAnalysis?.formattedSize ?? '—';

  /// Create a copy with updated fields.
  BinaryAnalysisState copyWith({
    bool? isLoading,
    String? error,
    ApkAnalysis? apkAnalysis,
    IpaAnalysis? ipaAnalysis,
    SecurityScanResult? securityResult,
    DependencyAnalysis? dependencyAnalysis,
    CodeQualityMetrics? qualityMetrics,
    SizeAnalysis? sizeAnalysis,
    AnalysisType? lastAnalysisType,
    String? lastAnalyzedPath,
    bool clearError = false,
  }) {
    return BinaryAnalysisState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      apkAnalysis: apkAnalysis ?? this.apkAnalysis,
      ipaAnalysis: ipaAnalysis ?? this.ipaAnalysis,
      securityResult: securityResult ?? this.securityResult,
      dependencyAnalysis: dependencyAnalysis ?? this.dependencyAnalysis,
      qualityMetrics: qualityMetrics ?? this.qualityMetrics,
      sizeAnalysis: sizeAnalysis ?? this.sizeAnalysis,
      lastAnalysisType: lastAnalysisType ?? this.lastAnalysisType,
      lastAnalyzedPath: lastAnalyzedPath ?? this.lastAnalyzedPath,
    );
  }

  /// Reset all state to initial values.
  BinaryAnalysisState clear() {
    return const BinaryAnalysisState();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Notifier
// ═══════════════════════════════════════════════════════════════════════════

/// Manages binary analysis state and orchestrates analysis runs.
///
/// Provides methods to run different analysis types and
/// maintains all results in a single unified state.
class BinaryAnalysisNotifier extends StateNotifier<BinaryAnalysisState> {
  BinaryAnalysisNotifier() : super(const BinaryAnalysisState());

  /// Run an analysis of the specified type on the given path.
  ///
  /// [type] the type of analysis to perform.
  /// [path] the file or directory path to analyze.
  Future<void> runAnalysis({
    required AnalysisType type,
    required String path,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      switch (type) {
        case AnalysisType.apk:
          await _runApkAnalysis(path);
        case AnalysisType.ipa:
          await _runIpaAnalysis(path);
        case AnalysisType.codeQuality:
          await _runCodeQualityAnalysis(path);
        case AnalysisType.security:
          await _runSecurityAnalysis(path);
        case AnalysisType.dependencies:
          await _runDependencyAnalysis(path);
        case AnalysisType.size:
          await _runSizeAnalysis(path);
      }

      state = state.copyWith(
        isLoading: false,
        lastAnalysisType: type,
        lastAnalyzedPath: path,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Run APK file structure analysis.
  Future<void> _runApkAnalysis(String apkPath) async {
    final result = await BinaryAnalysisService.analyzeApk(apkPath);
    state = state.copyWith(apkAnalysis: result);

    // Also extract and set security info from APK.
    final manifest = await BinaryAnalysisService.analyzeManifest(apkPath);
    if (manifest.permissions.isNotEmpty) {
      final permissionIssues = manifest.permissions.where((p) {
        final dangerous = [
          'READ_CONTACTS', 'WRITE_CONTACTS', 'READ_SMS', 'SEND_SMS',
          'READ_PHONE_STATE', 'ACCESS_FINE_LOCATION', 'CAMERA', 'RECORD_AUDIO',
          'WRITE_EXTERNAL_STORAGE',
        ];
        return dangerous.any((d) => p.contains(d));
      }).map((p) => SecurityIssue(
        id: 'PERM_${p.hashCode}',
        title: 'Dangerous Permission: $p',
        description: 'APK declares dangerous permission $p.',
        severity: 'medium',
        category: 'permissions',
        recommendation: 'Review if this permission is necessary.',
      )).toList();

      final debugIssue = manifest.isDebuggable
          ? const SecurityIssue(
              id: 'APK_DEBUG',
              title: 'Debug Mode Enabled',
              description: 'APK has debuggable flag set to true. This should not be enabled in release builds.',
              severity: 'critical',
              category: 'permissions',
              recommendation: 'Set android:debuggable to false in release builds.',
            )
          : null;

      final allIssues = [...permissionIssues, if (debugIssue != null) debugIssue];
      if (allIssues.isNotEmpty) {
        final riskScore = debugIssue != null ? 40 : 15;
        state = state.copyWith(
          securityResult: SecurityScanResult(
            totalIssues: allIssues.length,
            criticalIssues: debugIssue != null ? 1 : 0,
            highIssues: 0,
            mediumIssues: permissionIssues.length,
            lowIssues: 0,
            issues: allIssues,
            riskScore: riskScore,
          ),
        );
      }
    }
  }

  /// Run IPA file structure analysis.
  Future<void> _runIpaAnalysis(String ipaPath) async {
    final result = await BinaryAnalysisService.analyzeIpa(ipaPath);
    state = state.copyWith(ipaAnalysis: result);
  }

  /// Run code quality analysis.
  Future<void> _runCodeQualityAnalysis(String projectPath) async {
    final metrics = await BinaryAnalysisService.getCodeQuality(projectPath);
    state = state.copyWith(qualityMetrics: metrics);
  }

  /// Run security vulnerability scan.
  Future<void> _runSecurityAnalysis(String projectPath) async {
    final result = await BinaryAnalysisService.securityScan(projectPath);
    state = state.copyWith(securityResult: result);
  }

  /// Run dependency analysis.
  Future<void> _runDependencyAnalysis(String pubspecPath) async {
    final result = await BinaryAnalysisService.analyzePubspec(pubspecPath);
    state = state.copyWith(dependencyAnalysis: result);
  }

  /// Run size analysis.
  Future<void> _runSizeAnalysis(String projectPath) async {
    final result = await BinaryAnalysisService.analyzeSize(projectPath);
    state = state.copyWith(sizeAnalysis: result);
  }

  /// Clear all analysis results.
  void clear() {
    state = state.clear();
  }

  /// Update the security result directly (e.g., after marking issues resolved).
  void updateSecurityResult(SecurityScanResult result) {
    state = state.copyWith(securityResult: result);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Providers
// ═══════════════════════════════════════════════════════════════════════════

/// Main binary analysis state provider.
///
/// Use this to access all analysis results and trigger new analyses.
///
/// ```dart
/// final state = ref.watch(binaryAnalysisProvider);
/// ref.read(binaryAnalysisProvider.notifier).runAnalysis(
///   type: AnalysisType.security,
///   path: '/path/to/project',
/// );
/// ```
final binaryAnalysisProvider =
    StateNotifierProvider<BinaryAnalysisNotifier, BinaryAnalysisState>(
  (ref) => BinaryAnalysisNotifier(),
);

/// Computed provider: whether any analysis is currently running.
final analysisLoadingProvider = Provider<bool>(
  (ref) => ref.watch(binaryAnalysisProvider.select((s) => s.isLoading)),
);

/// Computed provider: current error message, if any.
final analysisErrorProvider = Provider<String?>(
  (ref) => ref.watch(binaryAnalysisProvider.select((s) => s.error)),
);

/// Computed provider: whether any results are available.
final analysisHasResultsProvider = Provider<bool>(
  (ref) => ref.watch(binaryAnalysisProvider.select((s) => s.hasResults)),
);

/// Computed provider: risk score (0-100).
final riskScoreProvider = Provider<int>(
  (ref) => ref.watch(binaryAnalysisProvider.select((s) => s.riskScore)),
);

/// Computed provider: security issues, if available.
final securityIssuesProvider = Provider<List<SecurityIssue>>(
  (ref) =>
      ref.watch(binaryAnalysisProvider.select((s) => s.securityResult?.issues)) ??
          [],
);

/// Computed provider: APK analysis, if available.
final apkAnalysisProvider = Provider<ApkAnalysis?>(
  (ref) => ref.watch(binaryAnalysisProvider.select((s) => s.apkAnalysis)),
);

/// Computed provider: dependency analysis, if available.
final dependencyAnalysisProvider = Provider<DependencyAnalysis?>(
  (ref) =>
      ref.watch(binaryAnalysisProvider.select((s) => s.dependencyAnalysis)),
);

/// Computed provider: code quality metrics, if available.
final qualityMetricsProvider = Provider<CodeQualityMetrics?>(
  (ref) => ref.watch(binaryAnalysisProvider.select((s) => s.qualityMetrics)),
);

/// Provider for the list of analysis types available.
final analysisTypesProvider = Provider<List<AnalysisType>>(
  (ref) => AnalysisType.values,
);

/// Provider for a quick security summary (for dashboard integration).
final securitySummaryProvider = Provider<Map<String, int>>(
  (ref) {
    final result = ref.watch(
      binaryAnalysisProvider.select((s) => s.securityResult),
    );
    if (result == null) {
      return {
        'total': 0,
        'critical': 0,
        'high': 0,
        'medium': 0,
        'low': 0,
        'riskScore': 0,
      };
    }
    return {
      'total': result.totalIssues,
      'critical': result.criticalIssues,
      'high': result.highIssues,
      'medium': result.mediumIssues,
      'low': result.lowIssues,
      'riskScore': result.riskScore,
    };
  },
);
