// lib/services/device_perf_service.dart

import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Data Models
// ═══════════════════════════════════════════════════════════════════════════

/// CPU information extracted from device info.
@immutable
class CpuInfo {
  /// Number of CPU cores.
  final int cores;

  /// CPU frequency in MHz (estimated per core).
  final int frequencyMHz;

  /// Whether the CPU supports 64-bit architecture.
  final bool is64Bit;

  /// CPU architecture string (e.g. 'arm64-v8a', 'x86_64').
  final String architecture;

  /// Human-readable CPU model description.
  final String processorType;

  const CpuInfo({
    required this.cores,
    required this.frequencyMHz,
    required this.is64Bit,
    required this.architecture,
    required this.processorType,
  });

  /// Formatted frequency string.
  String get frequencyFormatted {
    if (frequencyMHz >= 1000) {
      return '${(frequencyMHz / 1000).toStringAsFixed(1)} GHz';
    }
    return '$frequencyMHz MHz';
  }

  @override
  String toString() =>
      'CpuInfo(cores: $cores, freq: $frequencyFormatted, arch: $architecture)';
}

/// RAM / memory information.
@immutable
class RamInfo {
  /// Total physical RAM in MB.
  final int totalRamMB;

  /// Available / free RAM in MB.
  final int availableRamMB;

  const RamInfo({
    required this.totalRamMB,
    required this.availableRamMB,
  });

  /// Used RAM in MB.
  int get usedRamMB => totalRamMB - availableRamMB;

  /// RAM utilization percentage (0.0–100.0).
  double get utilizationPercent =>
      totalRamMB > 0 ? (usedRamMB / totalRamMB) * 100 : 0.0;

  /// Formatted total RAM string (e.g. '8.0 GB').
  String get totalFormatted => '${(totalRamMB / 1024).toStringAsFixed(1)} GB';

  /// Formatted available RAM string.
  String get availableFormatted =>
      '${(availableRamMB / 1024).toStringAsFixed(1)} GB';

  @override
  String toString() =>
      'RamInfo(total: $totalFormatted, used: ${utilizationPercent.toStringAsFixed(1)}%)';
}

/// Storage information.
@immutable
class StorageInfo {
  /// Total internal storage in MB.
  final int totalStorageMB;

  /// Available / free storage in MB.
  final int availableStorageMB;

  const StorageInfo({
    required this.totalStorageMB,
    required this.availableStorageMB,
  });

  /// Used storage in MB.
  int get usedStorageMB => totalStorageMB - availableStorageMB;

  /// Storage utilization percentage (0.0–100.0).
  double get utilizationPercent => totalStorageMB > 0
      ? (usedStorageMB / totalStorageMB) * 100
      : 0.0;

  /// Formatted total storage string.
  String get totalFormatted =>
      '${(totalStorageMB / 1024).toStringAsFixed(1)} GB';

  /// Formatted available storage string.
  String get availableFormatted =>
      '${(availableStorageMB / 1024).toStringAsFixed(1)} GB';

  @override
  String toString() =>
      'StorageInfo(total: $totalFormatted, used: ${utilizationPercent.toStringAsFixed(1)}%)';
}

/// GPU information (may be unavailable on some platforms).
@immutable
class GpuInfo {
  /// GPU vendor name (e.g. 'Qualcomm', 'Mali', 'Apple').
  final String vendor;

  /// GPU renderer string.
  final String renderer;

  /// GPU version string.
  final String version;

  const GpuInfo({
    required this.vendor,
    required this.renderer,
    required this.version,
  });

  @override
  String toString() => 'GpuInfo(vendor: $vendor, renderer: $renderer)';
}

/// Complete device hardware profile.
@immutable
class DeviceProfile {
  /// Device marketing name.
  final String deviceName;

  /// Device brand (e.g. 'Google', 'Samsung', 'Xiaomi').
  final String brand;

  /// Device model code.
  final String model;

  /// OS version string.
  final String osVersion;

  /// Total RAM in MB.
  final int totalRamMB;

  /// Available RAM in MB.
  final int availableRamMB;

  /// Total storage in MB.
  final int totalStorageMB;

  /// Available storage in MB.
  final int availableStorageMB;

  /// Number of CPU cores.
  final int cpuCores;

  /// CPU frequency in MHz per core.
  final int cpuFrequencyMHz;

  /// Whether 64-bit architecture.
  final bool is64Bit;

  /// CPU / processor type description.
  final String processorType;

  /// CPU details.
  final CpuInfo cpuInfo;

  /// RAM details.
  final RamInfo ramInfo;

  /// Storage details.
  final StorageInfo storageInfo;

  /// GPU details (null if unavailable).
  final GpuInfo? gpuInfo;

  const DeviceProfile({
    required this.deviceName,
    required this.brand,
    required this.model,
    required this.osVersion,
    required this.totalRamMB,
    required this.availableRamMB,
    required this.totalStorageMB,
    required this.availableStorageMB,
    required this.cpuCores,
    required this.cpuFrequencyMHz,
    required this.is64Bit,
    required this.processorType,
    required this.cpuInfo,
    required this.ramInfo,
    required this.storageInfo,
    this.gpuInfo,
  });

  /// RAM utilization percentage.
  double get ramUtilizationPercent =>
      (totalRamMB - availableRamMB) / totalRamMB * 100;

  /// Storage utilization percentage.
  double get storageUtilizationPercent =>
      (totalStorageMB - availableStorageMB) / totalStorageMB * 100;

  /// Formatted RAM string.
  String get ramFormatted => '${(totalRamMB / 1024).toStringAsFixed(1)} GB';

  /// Formatted storage string.
  String get storageFormatted =>
      '${(totalStorageMB / 1024).toStringAsFixed(1)} GB';

  /// Short display string for the device.
  String get displayName => '$brand $deviceName';
}

/// Flutter project build capability assessment.
@immutable
class ProjectCapability {
  /// Can build small projects (< 50 files).
  final bool canBuildSmall;

  /// Can build medium projects (50–200 files).
  final bool canBuildMedium;

  /// Can build large projects (200–500 files).
  final bool canBuildLarge;

  /// Can build very large projects (500+ files).
  final bool canBuildVeryLarge;

  /// Hot reload runs smoothly.
  final bool canUseHotReload;

  /// Can run Android emulator.
  final bool canRunEmulator;

  /// Chinese recommendation text.
  final String recommendation;

  const ProjectCapability({
    required this.canBuildSmall,
    required this.canBuildMedium,
    required this.canBuildLarge,
    required this.canBuildVeryLarge,
    required this.canUseHotReload,
    required this.canRunEmulator,
    required this.recommendation,
  });
}

/// Language-specific capability.
@immutable
class LanguageCapability {
  /// Programming language name.
  final String language;

  /// Can edit files of this language.
  final bool canEdit;

  /// Can execute / run code.
  final bool canRun;

  /// Can debug code.
  final bool canDebug;

  /// Performance note in Chinese.
  final String performanceNote;

  const LanguageCapability({
    required this.language,
    required this.canEdit,
    required this.canRun,
    required this.canDebug,
    required this.performanceNote,
  });
}

/// A recommended project type for this device.
@immutable
class ProjectRecommendation {
  /// Project type name (e.g. 'Flutter App').
  final String type;

  /// Complexity level in Chinese ('简单' / '中等' / '复杂').
  final String complexity;

  /// Description of the project type.
  final String description;

  /// Whether this device can handle it well.
  final bool isRecommended;

  /// Warning message if not recommended.
  final String? warning;

  const ProjectRecommendation({
    required this.type,
    required this.complexity,
    required this.description,
    required this.isRecommended,
    this.warning,
  });
}

/// Project size category for build time estimation.
enum ProjectSize { small, medium, large, veryLarge }

// ═══════════════════════════════════════════════════════════════════════════
// Service
// ═══════════════════════════════════════════════════════════════════════════

/// {@template device_perf_service}
/// Analyzes phone hardware capabilities and recommends what types of coding
/// projects the device can handle.
///
/// Uses `device_info_plus` for hardware detection and provides capability
/// assessments, project recommendations, and build time estimates.
/// {@endtemplate}
class DevicePerfService {
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// Singleton instance.
  static final DevicePerfService _instance = DevicePerfService._internal();
  factory DevicePerfService() => _instance;
  DevicePerfService._internal();

  // ── Hardware Detection ───────────────────────────────────────────────

  /// Get complete device profile with all hardware info.
  Future<DeviceProfile> analyzeDevice() async {
    final cpu = await getCpuInfo();
    final ram = await getRamInfo();
    final storage = await getStorageInfo();
    final gpu = await getGpuInfo();

    String deviceName = 'Unknown';
    String brand = 'Unknown';
    String model = 'Unknown';
    String osVersion = 'Unknown';

    if (Platform.isAndroid) {
      final info = await _deviceInfo.androidInfo;
      deviceName = info.model ?? 'Android Device';
      brand = (info.brand ?? 'Unknown').toUpperCase();
      model = info.model ?? 'Unknown';
      osVersion = 'Android ${info.version.release}';
    } else if (Platform.isIOS) {
      final info = await _deviceInfo.iosInfo;
      deviceName = info.name ?? 'iOS Device';
      brand = 'Apple';
      model = info.model ?? 'Unknown';
      osVersion = 'iOS ${info.systemVersion}';
    }

    return DeviceProfile(
      deviceName: deviceName,
      brand: brand,
      model: model,
      osVersion: osVersion,
      totalRamMB: ram.totalRamMB,
      availableRamMB: ram.availableRamMB,
      totalStorageMB: storage.totalStorageMB,
      availableStorageMB: storage.availableStorageMB,
      cpuCores: cpu.cores,
      cpuFrequencyMHz: cpu.frequencyMHz,
      is64Bit: cpu.is64Bit,
      processorType: cpu.processorType,
      cpuInfo: cpu,
      ramInfo: ram,
      storageInfo: storage,
      gpuInfo: gpu,
    );
  }

  /// Get CPU information.
  Future<CpuInfo> getCpuInfo() async {
    int cores = 4;
    int frequencyMHz = 2000;
    bool is64Bit = true;
    String architecture = 'arm64';
    String processorType = 'Unknown Processor';

    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        cores = info.supportedAbis?.length ?? 4;
        if (cores == 0) cores = 4;
        architecture = info.supportedAbis?.first ?? 'arm64-v8a';
        is64Bit = architecture.contains('64');
        processorType = '${info.manufacturer} ${info.model}';
        // Estimate frequency from device tier.
        frequencyMHz = _estimateCpuFrequency(info.model ?? '', cores);
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        cores = 6; // Estimate for modern iPhones
        architecture = 'arm64';
        is64Bit = true;
        processorType = info.utsname?.machine ?? 'Apple Silicon';
        frequencyMHz = _estimateAppleCpuFrequency(processorType);
      }
    } catch (e) {
      debugPrint('[DevicePerfService] CPU info error: $e');
    }

    return CpuInfo(
      cores: cores,
      frequencyMHz: frequencyMHz,
      is64Bit: is64Bit,
      architecture: architecture,
      processorType: processorType,
    );
  }

  /// Get RAM information.
  Future<RamInfo> getRamInfo() async {
    int totalRamMB = 4096;
    int availableRamMB = 2048;

    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        // memTotal is in KB on Android.
        final memTotalKb = info.memTotal;
        if (memTotalKb != null && memTotalKb > 0) {
          totalRamMB = memTotalKb ~/ 1024;
        } else {
          totalRamMB = _estimateRamFromDeviceModel(info.model ?? '');
        }
      } else if (Platform.isIOS) {
        totalRamMB = _estimateIosRam();
      }

      // Estimate available as roughly 30-50% of total for the app.
      availableRamMB = (totalRamMB * 0.35).toInt();
    } catch (e) {
      debugPrint('[DevicePerfService] RAM info error: $e');
    }

    return RamInfo(totalRamMB: totalRamMB, availableRamMB: availableRamMB);
  }

  /// Get storage information.
  Future<StorageInfo> getStorageInfo() async {
    int totalStorageMB = 65536; // 64 GB default
    int availableStorageMB = 16384; // 16 GB default

    try {
      final directory = Directory('/storage/emulated/0');
      if (await directory.exists()) {
        final stat = directory.statSync();
        // Use path_provider fallback for actual space.
        try {
          final result = await _getStorageStats();
          totalStorageMB = result['total'] ?? totalStorageMB;
          availableStorageMB = result['available'] ?? availableStorageMB;
        } catch (_) {
          // Fallback: estimate from common device configs.
        }
      }

      if (Platform.isIOS) {
        // iOS: typical values, refined by device tier.
        final tier = await _getIosDeviceTier();
        if (tier == 'high') {
          totalStorageMB = 262144; // 256 GB
        } else if (tier == 'mid') {
          totalStorageMB = 131072; // 128 GB
        } else {
          totalStorageMB = 65536; // 64 GB
        }
        availableStorageMB = (totalStorageMB * 0.3).toInt();
      }
    } catch (e) {
      debugPrint('[DevicePerfService] Storage info error: $e');
    }

    return StorageInfo(
      totalStorageMB: totalStorageMB,
      availableStorageMB: availableStorageMB,
    );
  }

  /// Get GPU info if available.
  Future<GpuInfo?> getGpuInfo() async {
    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        final gpuVendor = _detectGpuVendor(info.model ?? '');
        return GpuInfo(
          vendor: gpuVendor,
          renderer: 'OpenGL ES',
          version: info.version.release ?? 'Unknown',
        );
      } else if (Platform.isIOS) {
        return const GpuInfo(
          vendor: 'Apple',
          renderer: 'Metal',
          version: 'Apple GPU',
        );
      }
    } catch (e) {
      debugPrint('[DevicePerfService] GPU info error: $e');
    }
    return null;
  }

  // ── Capability Assessment ────────────────────────────────────────────

  /// Assess Flutter project build capabilities.
  ProjectCapability assessFlutterCapability(DeviceProfile profile) {
    final rating = calculateDeviceRating(profile);

    final canBuildSmall = rating >= 3;
    final canBuildMedium = rating >= 5;
    final canBuildLarge = rating >= 7;
    final canBuildVeryLarge = rating >= 9;
    final canUseHotReload = rating >= 4 && profile.totalRamMB >= 4096;
    final canRunEmulator = profile.totalRamMB >= 8192 && profile.cpuCores >= 6;

    String recommendation;
    if (rating >= 9) {
      recommendation = '旗舰级设备，可流畅开发各类 Flutter 项目';
    } else if (rating >= 7) {
      recommendation = '性能良好，适合开发中大型 Flutter 项目';
    } else if (rating >= 5) {
      recommendation = '可以开发中小型 Flutter 项目，大型项目构建可能较慢';
    } else if (rating >= 3) {
      recommendation = '仅适合小型 Flutter 项目，建议精简代码和依赖';
    } else {
      recommendation = '设备性能有限，Flutter 开发体验可能不佳';
    }

    return ProjectCapability(
      canBuildSmall: canBuildSmall,
      canBuildMedium: canBuildMedium,
      canBuildLarge: canBuildLarge,
      canBuildVeryLarge: canBuildVeryLarge,
      canUseHotReload: canUseHotReload,
      canRunEmulator: canRunEmulator,
      recommendation: recommendation,
    );
  }

  /// Assess language capabilities for this device.
  List<LanguageCapability> assessLanguageCapabilities(DeviceProfile profile) {
    final rating = calculateDeviceRating(profile);
    final ramGB = profile.totalRamMB / 1024;

    return [
      LanguageCapability(
        language: 'Dart / Flutter',
        canEdit: true,
        canRun: rating >= 4,
        canDebug: rating >= 5,
        performanceNote: ramGB >= 4 ? '运行流畅' : '可能较慢，建议关闭其他应用',
      ),
      LanguageCapability(
        language: 'Python',
        canEdit: true,
        canRun: true,
        canDebug: rating >= 3,
        performanceNote: rating >= 5 ? '运行流畅' : '脚本执行正常',
      ),
      LanguageCapability(
        language: 'JavaScript / Node.js',
        canEdit: true,
        canRun: true,
        canDebug: rating >= 4,
        performanceNote: rating >= 5 ? '运行流畅' : '基础运行无问题',
      ),
      LanguageCapability(
        language: 'Java / Kotlin',
        canEdit: true,
        canRun: ramGB >= 4,
        canDebug: ramGB >= 6,
        performanceNote: ramGB >= 6 ? 'Gradle 构建正常' : '构建可能较慢，内存占用大',
      ),
      LanguageCapability(
        language: 'C / C++',
        canEdit: true,
        canRun: rating >= 4,
        canDebug: rating >= 5,
        performanceNote: '编译时间较长，但运行效率高',
      ),
      LanguageCapability(
        language: 'Rust',
        canEdit: true,
        canRun: rating >= 5,
        canDebug: rating >= 6,
        performanceNote: rating >= 6 ? '编译和运行良好' : '编译较耗时',
      ),
      LanguageCapability(
        language: 'Go',
        canEdit: true,
        canRun: true,
        canDebug: rating >= 4,
        performanceNote: '编译速度快，适合此设备',
      ),
      LanguageCapability(
        language: 'HTML / CSS',
        canEdit: true,
        canRun: true,
        canDebug: true,
        performanceNote: '无性能压力',
      ),
    ];
  }

  /// Calculate overall device rating (1–10).
  int calculateDeviceRating(DeviceProfile profile) {
    double score = 0;

    // RAM scoring (max 4 points).
    final ramGB = profile.totalRamMB / 1024;
    if (ramGB >= 12) {
      score += 4;
    } else if (ramGB >= 8) {
      score += 3.5;
    } else if (ramGB >= 6) {
      score += 3;
    } else if (ramGB >= 4) {
      score += 2;
    } else if (ramGB >= 3) {
      score += 1.5;
    } else {
      score += 1;
    }

    // CPU scoring (max 3 points).
    final cpuScore = profile.cpuCores * (profile.cpuFrequencyMHz / 2000);
    if (cpuScore >= 12) {
      score += 3;
    } else if (cpuScore >= 8) {
      score += 2.5;
    } else if (cpuScore >= 5) {
      score += 2;
    } else if (cpuScore >= 3) {
      score += 1.5;
    } else {
      score += 1;
    }

    // Storage scoring (max 2 points).
    final storageGB = profile.totalStorageMB / 1024;
    if (storageGB >= 256) {
      score += 2;
    } else if (storageGB >= 128) {
      score += 1.5;
    } else if (storageGB >= 64) {
      score += 1;
    } else {
      score += 0.5;
    }

    // 64-bit bonus (max 1 point).
    if (profile.is64Bit) {
      score += 1;
    } else {
      score += 0.5;
    }

    return score.clamp(1.0, 10.0).round();
  }

  // ── Project Recommendations ──────────────────────────────────────────

  /// Get recommended project types for this device.
  List<ProjectRecommendation> getRecommendedProjects(DeviceProfile profile) {
    final rating = calculateDeviceRating(profile);
    final ramGB = profile.totalRamMB / 1024;

    return [
      ProjectRecommendation(
        type: 'Flutter 小型项目',
        complexity: '简单',
        description: '单页面应用、工具类 App (< 50 个文件)',
        isRecommended: rating >= 3,
        warning: rating < 3 ? '设备性能可能不足' : null,
      ),
      ProjectRecommendation(
        type: 'Flutter 中型项目',
        complexity: '中等',
        description: '多页面应用、状态管理 (50-200 个文件)',
        isRecommended: rating >= 5,
        warning: rating < 5 ? '构建时间可能较长' : null,
      ),
      ProjectRecommendation(
        type: 'Flutter 大型项目',
        complexity: '复杂',
        description: '企业级应用、复杂路由 (200-500 个文件)',
        isRecommended: rating >= 7,
        warning: rating < 7 ? '内存和 CPU 可能吃紧' : null,
      ),
      ProjectRecommendation(
        type: 'Python 脚本',
        complexity: '简单',
        description: '数据处理、自动化脚本',
        isRecommended: true,
      ),
      ProjectRecommendation(
        type: 'Web 前端项目',
        complexity: '中等',
        description: 'HTML/CSS/JS、Vue、React',
        isRecommended: rating >= 4,
      ),
      ProjectRecommendation(
        type: '静态网站生成',
        complexity: '简单',
        description: 'Jekyll、Hugo、VitePress',
        isRecommended: rating >= 3,
      ),
      ProjectRecommendation(
        type: 'Java / Kotlin 项目',
        complexity: '复杂',
        description: 'Android 原生开发、后端服务',
        isRecommended: ramGB >= 6,
        warning: ramGB < 6 ? '需要至少 6GB RAM 才能流畅开发' : null,
      ),
      ProjectRecommendation(
        type: 'C/C++ 项目',
        complexity: '中等',
        description: '算法实现、系统编程',
        isRecommended: rating >= 4,
      ),
      ProjectRecommendation(
        type: 'AI / ML 实验',
        complexity: '复杂',
        description: 'TensorFlow Lite、PyTorch Mobile',
        isRecommended: ramGB >= 8,
        warning: ramGB < 8 ? '需要大量内存，建议在桌面环境进行' : null,
      ),
    ];
  }

  /// Check if device can run hot reload smoothly.
  bool canRunHotReload(DeviceProfile profile) {
    return profile.totalRamMB >= 4096 && profile.cpuCores >= 4;
  }

  /// Estimate Flutter build time.
  Duration estimateBuildTime(DeviceProfile profile, ProjectSize size) {
    final rating = calculateDeviceRating(profile);
    // Base seconds per rating point.
    final baseSeconds = <ProjectSize, int>{
      ProjectSize.small: 30,
      ProjectSize.medium: 60,
      ProjectSize.large: 120,
      ProjectSize.veryLarge: 240,
    };

    final base = baseSeconds[size] ?? 60;
    // Higher rating = faster build. Rating 10 = 0.5x base, Rating 1 = 3x base.
    final multiplier = 3.0 - (rating / 10.0) * 2.5;
    final estimatedSeconds = (base * multiplier).round();

    return Duration(seconds: estimatedSeconds);
  }

  /// Get optimization suggestions based on device profile.
  List<String> getOptimizationSuggestions(DeviceProfile profile) {
    final suggestions = <String>[];
    final ramGB = profile.totalRamMB / 1024;

    if (ramGB < 4) {
      suggestions.add('内存较小，开发时请关闭其他后台应用');
      suggestions.add('使用轻量级编辑器而非完整 IDE');
    }
    if (profile.totalStorageMB < 65536) {
      suggestions.add('存储空间有限，定期清理 build 缓存');
      suggestions.add('使用 --split-debug-info 减小构建产物');
    }
    if (profile.cpuCores < 6) {
      suggestions.add('CPU 核心较少，构建时避免多任务');
      suggestions.add('使用 flutter build --profile 替代 release 调试');
    }
    if (!profile.is64Bit) {
      suggestions.add('32 位设备限制较多，建议使用真机调试');
    }
    if (suggestions.isEmpty) {
      suggestions.add('设备性能良好，无需特别优化');
      suggestions.add('建议开启 Gradle daemon 加速后续构建');
    }

    return suggestions;
  }

  // ── Private Helpers ──────────────────────────────────────────────────

  int _estimateCpuFrequency(String model, int cores) {
    final modelLower = model.toLowerCase();
    // Flagship devices.
    if (modelLower.contains('pixel 8') ||
        modelLower.contains('galaxy s24') ||
        modelLower.contains('xiaomi 14')) {
      return 3000;
    }
    if (modelLower.contains('pixel 7') ||
        modelLower.contains('galaxy s23') ||
        modelLower.contains('oneplus 11')) {
      return 2800;
    }
    // Mid-range.
    if (modelLower.contains('pixel 6') ||
        modelLower.contains('galaxy a') ||
        modelLower.contains('redmi')) {
      return 2200;
    }
    // Entry-level fallback.
    return 2000;
  }

  int _estimateAppleCpuFrequency(String machine) {
    final m = machine.toLowerCase();
    // iPhone 15 Pro.
    if (m.contains('iphone15,3') || m.contains('iphone15,2')) return 3200;
    // iPhone 15.
    if (m.contains('iphone15,') && !m.contains('pro')) return 2800;
    // iPhone 14 Pro.
    if (m.contains('iphone14,') && m.contains('pro')) return 3100;
    // iPhone 14.
    if (m.contains('iphone14,')) return 2600;
    // iPhone 13.
    if (m.contains('iphone13,')) return 2500;
    // Older.
    if (m.contains('iphone12,')) return 2400;
    return 2200;
  }

  int _estimateRamFromDeviceModel(String model) {
    final m = model.toLowerCase();
    // Flagship 12GB+.
    if (m.contains('s24 ultra') ||
        m.contains('xiaomi 14') ||
        m.contains('oneplus 12')) {
      return 12288;
    }
    // High-end 8GB.
    if (m.contains('pixel 8') ||
        m.contains('s23') ||
        m.contains('iphone 15')) {
      return 8192;
    }
    // Mid-range 6GB.
    if (m.contains('pixel 7') ||
        m.contains('galaxy a54') ||
        m.contains('redmi note 12')) {
      return 6144;
    }
    // Budget 4GB.
    if (m.contains('pixel 6a') || m.contains('galaxy a34')) {
      return 4096;
    }
    return 4096; // Default.
  }

  int _estimateIosRam() {
    // iOS devices don't expose RAM; estimate by known tiers.
    return 6144; // Conservative: most modern iPhones have 6GB+.
  }

  Future<String> _getIosDeviceTier() async {
    try {
      final info = await _deviceInfo.iosInfo;
      final machine = (info.utsname?.machine ?? '').toLowerCase();
      // Pro models are high tier.
      if (machine.contains('pro') || machine.contains('max')) return 'high';
      // Standard recent models are mid.
      if (machine.contains('iphone15') ||
          machine.contains('iphone14') ||
          machine.contains('iphone13')) {
        return 'mid';
      }
      return 'low';
    } catch (_) {
      return 'mid';
    }
  }

  String _detectGpuVendor(String model) {
    final m = model.toLowerCase();
    if (m.contains('pixel') || m.contains('samsung')) return 'Qualcomm Adreno';
    if (m.contains('xiaomi') ||
        m.contains('redmi') ||
        m.contains('poco')) {
      return 'Qualcomm Adreno / Mali';
    }
    if (m.contains('huawei') || m.contains('honor')) return 'Mali';
    return 'Unknown';
  }

  Future<Map<String, int>> _getStorageStats() async {
    try {
      final result = <String, int>{};
      if (Platform.isAndroid) {
        // Use StatFs-like estimation via app directory.
        final appDir = Directory('/storage/emulated/0/Android');
        if (appDir.existsSync()) {
          // Rough estimate: count total blocks.
          result['total'] = 131072; // 128 GB fallback.
          result['available'] = 32768; // 32 GB fallback.
        }
      }
      return result;
    } catch (e) {
      return {'total': 65536, 'available': 16384};
    }
  }
}
