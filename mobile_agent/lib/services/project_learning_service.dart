// lib/services/project_learning_service.dart
// Project Learning Service — Scans and learns the user's project structure,
// code conventions, and architecture patterns.
//
// Inspired by AppAgent's exploration phase: before acting, the agent learns
// the environment to make context-aware decisions.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/constants.dart';
import 'coding_prompts.dart';
import 'llm_service.dart';
import 'storage_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Project Learning Service
// ═══════════════════════════════════════════════════════════════════════════

/// Service that scans and learns a project's structure, conventions,
/// and architecture patterns.
///
/// This knowledge is used to generate context-aware code that matches
/// the existing codebase style. Inspired by AppAgent's exploration phase,
/// the agent first learns the environment before taking actions.
///
/// ```dart
/// final learning = ProjectLearningService(storage: storage, llm: llm);
/// final knowledge = await learning.learnProject('my_project');
/// print(knowledge.architecture.pattern); // 'mvvm'
/// ```
class ProjectLearningService {
  final StorageService _storage;
  final LLMService? _llm;

  /// In-memory cache of learned projects.
  final Map<String, ProjectKnowledge> _knowledgeCache = {};

  /// Maximum files to scan per project (performance limit).
  static const int _maxFilesToScan = 200;

  /// Maximum file size to read (bytes).
  static const int _maxFileSize = 50000;

  /// Number of representative files to sample for LLM analysis.
  static const int _sampleSize = 5;

  /// Creates a [ProjectLearningService].
  ///
  /// [storage] is required for persistence.
  /// [llm] is optional — if provided, enables AI-powered analysis
  /// of code style and architecture.
  ProjectLearningService({
    required StorageService storage,
    LLMService? llm,
  })  : _storage = storage,
        _llm = llm;

  /// Scan a project and build a knowledge base.
  ///
  /// [projectPath] is the absolute path to the project root directory.
  /// Uses cached knowledge if available and [forceRefresh] is false.
  ///
  /// Returns a [ProjectKnowledge] object containing all learned information.
  Future<ProjectKnowledge> learnProject(
    String projectPath, {
    bool forceRefresh = false,
  }) async {
    // Check cache first.
    if (!forceRefresh && _knowledgeCache.containsKey(projectPath)) {
      final cached = _knowledgeCache[projectPath]!;
      // Cache valid for 1 hour.
      if (DateTime.now().difference(cached.learnedAt).inHours < 1) {
        debugPrint('[ProjectLearningService] Using cached knowledge for $projectPath');
        return cached;
      }
    }

    debugPrint('[ProjectLearningService] Learning project: $projectPath');
    final stopwatch = Stopwatch()..start();

    // Phase 1: Collect file structure.
    final files = await _collectFiles(projectPath);
    debugPrint('[ProjectLearningService] Found ${files.length} files');

    // Phase 2: Detect architecture pattern.
    final filePaths = files.map((f) => f.path).toList();
    final architecture = detectArchitecture(filePaths);
    debugPrint('[ProjectLearningService] Detected architecture: ${architecture.pattern}');

    // Phase 3: Detect naming conventions.
    final naming = detectNamingConventions(filePaths);
    debugPrint('[ProjectLearningService] Naming conventions detected');

    // Phase 4: Detect code style (requires reading files).
    final codeStyle = await detectCodeStyle(files);
    debugPrint('[ProjectLearningService] Code style analyzed');

    // Phase 5: Extract key files (entry points, configs).
    final keyFiles = _extractKeyFiles(filePaths);
    debugPrint('[ProjectLearningService] Key files: ${keyFiles.length}');

    // Phase 6: Generate file summaries (if LLM available).
    final summaries = <String, String>{};
    if (_llm != null) {
      final sampleFiles = _selectRepresentativeFiles(files);
      for (final file in sampleFiles) {
        try {
          final summary = await _summarizeFile(file);
          summaries[p.relative(file.path, from: projectPath)] = summary;
        } catch (e) {
          debugPrint('[ProjectLearningService] Failed to summarize ${file.path}: $e');
        }
      }
    }

    stopwatch.stop();
    debugPrint('[ProjectLearningService] Learning completed in ${stopwatch.elapsedMilliseconds}ms');

    // Build and cache knowledge.
    final knowledge = ProjectKnowledge(
      projectPath: projectPath,
      architecture: architecture,
      naming: naming,
      style: codeStyle,
      keyFiles: keyFiles,
      fileSummaries: summaries,
      totalFiles: files.length,
      learnedAt: DateTime.now(),
    );

    _knowledgeCache[projectPath] = knowledge;
    return knowledge;
}

  /// Collect all relevant files from a project directory.
  Future<List<_ScannedFile>> _collectFiles(String projectPath) async {
    final dir = Directory(projectPath);
    if (!await dir.exists()) {
      throw ProjectLearningException('Project directory not found: $projectPath');
    }

    final files = <_ScannedFile>[];
    final excludedDirs = {
      '.git',
      'node_modules',
      '.dart_tool',
      'build',
      'ios/Pods',
      'android/.gradle',
      '.idea',
      '.vscode',
      'vendor',
      'target',
      'dist',
      '.pub',
      '.flutter-plugins',
    };

    final excludedExtensions = {
      '.lock',
      '.log',
      '.tmp',
      '.temp',
      '.class',
      '.jar',
      '.aar',
      '.ipa',
      '.apk',
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.ico',
      '.svg',
      '.mp3',
      '.mp4',
      '.db',
    };

    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;

        final relativePath = p.relative(entity.path, from: projectPath);

        // Skip excluded directories.
        final pathParts = p.split(relativePath);
        if (pathParts.any((part) => excludedDirs.contains(part))) {
          continue;
        }

        // Skip excluded extensions.
        if (excludedExtensions.any((ext) => entity.path.endsWith(ext))) {
          continue;
        }

        // Skip very large files.
        final stat = await entity.stat();
        if (stat.size > _maxFileSize) continue;

        files.add(_ScannedFile(
          path: entity.path,
          relativePath: relativePath,
          size: stat.size,
          extension: p.extension(entity.path),
        ));

        if (files.length >= _maxFilesToScan) break;
      }
    } catch (e) {
      debugPrint('[ProjectLearningService] Error scanning files: $e');
    }

    return files;
  }

  /// Detect architecture pattern from file structure.
  ArchitecturePattern detectArchitecture(List<String> files) {
    final lowerFiles = files.map((f) => f.toLowerCase()).toList();
    final allPaths = lowerFiles.join('\n');

    // Pattern detection heuristics.
    var pattern = ArchitecturePattern.unknown;
    var confidence = 0.0;

    // Check for Clean Architecture (layers).
    final hasData = lowerFiles.any((f) => f.contains('/data/') || f.contains('/repository/'));
    final hasDomain = lowerFiles.any((f) => f.contains('/domain/') || f.contains('/entity/'));
    final hasPresentation =
        lowerFiles.any((f) => f.contains('/presentation/') || f.contains('/ui/'));

    if (hasData && hasDomain && hasPresentation) {
      pattern = ArchitecturePattern.clean;
      confidence = 0.9;
    }

    // Check for MVC.
    final hasModels = lowerFiles.any((f) => f.contains('/models/') || f.contains('/model/'));
    final hasViews = lowerFiles.any((f) => f.contains('/views/') || f.contains('/view/'));
    final hasControllers =
        lowerFiles.any((f) => f.contains('/controllers/') || f.contains('/controller/'));

    if (hasModels && hasViews && hasControllers && confidence < 0.8) {
      pattern = ArchitecturePattern.mvc;
      confidence = 0.8;
    }

    // Check for MVVM.
    final hasViewModels =
        lowerFiles.any((f) => f.contains('/viewmodels/') || f.contains('/view_model/'));
    if (hasModels && hasViews && hasViewModels && confidence < 0.8) {
      pattern = ArchitecturePattern.mvvm;
      confidence = 0.75;
    }

    // Check for Bloc pattern.
    final hasBloc = lowerFiles.any((f) => f.contains('/bloc/') || f.contains('/blocs/'));
    final hasEvents = lowerFiles.any((f) => f.contains('/event/') || f.contains('/events/'));
    final hasStates = lowerFiles.any((f) => f.contains('/state/') || f.contains('/states/'));
    if (hasBloc || (hasEvents && hasStates)) {
      pattern = ArchitecturePattern.bloc;
      confidence = 0.85;
    }

    // Check for Provider / Riverpod (simpler structure).
    final hasProvider = allPaths.contains('provider') || allPaths.contains('riverpod');
    if (hasProvider && confidence < 0.5) {
      pattern = ArchitecturePattern.provider;
      confidence = 0.6;
    }

    // Check for Feature-based / Modular.
    final hasFeatures = lowerFiles.any((f) => f.contains('/features/') || f.contains('/modules/'));
    if (hasFeatures) {
      if (confidence < 0.5) {
        pattern = ArchitecturePattern.feature;
        confidence = 0.7;
      } else {
        // Feature-based can combine with other patterns.
        confidence = math.min(confidence + 0.1, 1.0);
      }
    }

    // Check for simple / no architecture.
    if (confidence < 0.3) {
      pattern = ArchitecturePattern.simple;
      confidence = 0.5;
    }

    return ArchitecturePattern(
      pattern: pattern.name,
      confidence: confidence,
      indicators: {
        if (hasData) 'data_layer': true,
        if (hasDomain) 'domain_layer': true,
        if (hasPresentation) 'presentation_layer': true,
        if (hasModels) 'models': true,
        if (hasViews) 'views': true,
        if (hasControllers) 'controllers': true,
        if (hasViewModels) 'viewmodels': true,
        if (hasBloc) 'bloc': true,
        if (hasEvents) 'events': true,
        if (hasStates) 'states': true,
        if (hasFeatures) 'features': true,
      },
    );
  }

  /// Detect naming conventions from file paths.
  NamingConventions detectNamingConventions(List<String> files) {
    var camelCase = 0;
    var pascalCase = 0;
    var snakeCase = 0;
    var kebabCase = 0;

    for (final file in files) {
      final name = p.basenameWithoutExtension(file);
      if (name.isEmpty) continue;

      if (_isPascalCase(name)) {
        pascalCase++;
      } else if (_isCamelCase(name)) {
        camelCase++;
      } else if (_isSnakeCase(name)) {
        snakeCase++;
      } else if (_isKebabCase(name)) {
        kebabCase++;
      }
    }

    final total = camelCase + pascalCase + snakeCase + kebabCase;
    if (total == 0) {
      return const NamingConventions(
        primary: 'unknown',
        fileNaming: 'unknown',
        classNaming: 'unknown',
        variableNaming: 'unknown',
      );
    }

    // Determine primary convention.
    final scores = {
      'camelCase': camelCase,
      'PascalCase': pascalCase,
      'snake_case': snakeCase,
      'kebab-case': kebabCase,
    };
    final primary = scores.entries.reduce((a, b) => a.value > b.value ? a : b).key;

    // Classes typically use PascalCase, variables/functions camelCase.
    return NamingConventions(
      primary: primary,
      fileNaming: primary,
      classNaming: pascalCase >= camelCase ? 'PascalCase' : 'camelCase',
      variableNaming: camelCase >= pascalCase ? 'camelCase' : 'PascalCase',
      confidence: total > 0 ? scores[primary]! / total : 0.0,
    );
  }

  /// Detect code style from file content.
  Future<CodeStyle> detectCodeStyle(List<_ScannedFile> files) async {
    var indent2Spaces = 0;
    var indent4Spaces = 0;
    var indentTabs = 0;
    var usesTrailingCommas = 0;
    var usesSemicolons = 0;
    var totalImports = 0;
    var groupedImports = 0;

    // Sample up to 20 files for style analysis.
    final sampleSize = math.min(files.length, 20);
    final sampled = _selectSample(files, sampleSize);

    for (final file in sampled) {
      try {
        final content = await File(file.path).readAsString();
        final lines = content.split('\n');

        // Detect indentation.
        for (final line in lines) {
          if (line.startsWith('  ') && line.length > 2) {
            if (line.startsWith('    ')) {
              indent4Spaces++;
            } else {
              indent2Spaces++;
            }
          } else if (line.startsWith('\t')) {
            indentTabs++;
          }
        }

        // Check trailing commas (Dart style).
        if (content.contains(',\n') || content.contains(', \n')) {
          usesTrailingCommas++;
        }

        // Check semicolons.
        if (content.contains(';')) {
          usesSemicolons++;
        }

        // Check import grouping.
        if (content.contains('import ')) {
          totalImports++;
          if (content.contains('\n\nimport ') || content.contains('import \'dart:')) {
            groupedImports++;
          }
        }
      } catch (e) {
        // Skip files that can't be read.
        continue;
      }
    }

    // Determine indentation preference.
    String indentation;
    if (indent2Spaces > indent4Spaces && indent2Spaces > indentTabs) {
      indentation = '2_spaces';
    } else if (indent4Spaces > indentTabs) {
      indentation = '4_spaces';
    } else if (indentTabs > 0) {
      indentation = 'tabs';
    } else {
      indentation = 'unknown';
    }

    // Determine max line length from common patterns.
    final maxLineLength = _estimateMaxLineLength(sampled);

    return CodeStyle(
      indentation: indentation,
      maxLineLength: maxLineLength,
      trailingCommas: usesTrailingCommas > sampled.length ~/ 2,
      semicolonsRequired: usesSemicolons > sampled.length ~/ 2,
      groupedImports: groupedImports > totalImports ~/ 2,
    );
  }

  /// Estimate max line length from sampled files.
  int _estimateMaxLineLength(List<_ScannedFile> files) {
    // Default to common values based on detected patterns.
    final hasDart = files.any((f) => f.extension == '.dart');
    if (hasDart) return 80; // Dart default.
    final hasJs = files.any((f) => f.extension == '.js' || f.extension == '.ts');
    if (hasJs) return 100; // JS/TS common.
    return 80;
  }

  /// Extract key/important files from the project.
  List<String> _extractKeyFiles(List<String> files) {
    final keyPatterns = [
      RegExp(r'pubspec\.yaml$', caseSensitive: false),
      RegExp(r'package\.json$', caseSensitive: false),
      RegExp(r'Cargo\.toml$', caseSensitive: false),
      RegExp(r'go\.mod$', caseSensitive: false),
      RegExp(r'main\.(dart|js|ts|py|go|rs|java|kt|swift)$', caseSensitive: false),
      RegExp(r'app\.(dart|js|ts)$', caseSensitive: false),
      RegExp(r'lib/main\.dart$', caseSensitive: false),
      RegExp(r'lib/src/app\.dart$', caseSensitive: false),
      RegExp(r'README', caseSensitive: false),
      RegExp(r'analysis_options\.yaml$', caseSensitive: false),
      RegExp(r'tsconfig\.json$', caseSensitive: false),
    ];

    final keyFiles = <String>[];
    for (final file in files) {
      for (final pattern in keyPatterns) {
        if (pattern.hasMatch(file)) {
          keyFiles.add(file);
          break;
        }
      }
    }

    return keyFiles;
  }

  /// Select representative files for LLM analysis.
  List<_ScannedFile> _selectRepresentativeFiles(List<_ScannedFile> files) {
    // Pick one file from each extension type.
    final byExtension = <String, List<_ScannedFile>>{};
    for (final file in files) {
      byExtension.putIfAbsent(file.extension, () => []).add(file);
    }

    final selected = <_ScannedFile>[];
    for (final entry in byExtension.entries) {
      // Pick the smallest file as representative.
      final sorted = entry.value..sort((a, b) => a.size.compareTo(b.size));
      if (sorted.isNotEmpty) {
        selected.add(sorted.first);
      }
    }

    // Limit to sample size.
    if (selected.length > _sampleSize) {
      return _selectSample(selected, _sampleSize);
    }
    return selected;
  }

  /// Select a random sample of files.
  List<_ScannedFile> _selectSample(List<_ScannedFile> files, int size) {
    if (files.length <= size) return files;
    final shuffled = List<_ScannedFile>.from(files)..shuffle();
    return shuffled.sublist(0, size);
  }

  /// Summarize a file using the LLM (if available).
  Future<String> _summarizeFile(_ScannedFile file) async {
    // For now, return a simple summary based on file path.
    // When LLM is available, this can generate richer summaries.
    final fileName = p.basename(file.path);
    final lang = detectLanguageFromPath(file.path);
    return '$fileName (${SupportedLanguages.languages[lang] ?? lang}) — ${file.size} bytes';
  }

  /// Clear the knowledge cache.
  void clearCache() => _knowledgeCache.clear();

  /// Get cached knowledge without re-learning.
  ProjectKnowledge? getCachedKnowledge(String projectPath) {
    return _knowledgeCache[projectPath];
  }

  // ── Naming convention helpers ─────────────────────────────────────

  bool _isPascalCase(String s) {
    if (s.isEmpty || s[0] != s[0].toUpperCase()) return false;
    return !s.contains('_') && !s.contains('-');
  }

  bool _isCamelCase(String s) {
    if (s.isEmpty || s[0] != s[0].toLowerCase()) return false;
    return !s.contains('_') && !s.contains('-');
  }

  bool _isSnakeCase(String s) {
    return s.contains('_') && !s.contains('-') && s == s.toLowerCase();
  }

  bool _isKebabCase(String s) {
    return s.contains('-') && !s.contains('_') && s == s.toLowerCase();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Internal: Scanned File
// ═══════════════════════════════════════════════════════════════════════════

/// Internal representation of a scanned file.
class _ScannedFile {
  final String path;
  final String relativePath;
  final int size;
  final String extension;

  _ScannedFile({
    required this.path,
    required this.relativePath,
    required this.size,
    required this.extension,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Project Knowledge
// ═══════════════════════════════════════════════════════════════════════════

/// Complete knowledge about a learned project.
///
/// This object is immutable and serializable. It's used as context
/// when generating code to ensure consistency with the existing codebase.
class ProjectKnowledge {
  /// Absolute path to the project root.
  final String projectPath;

  /// Detected architecture pattern.
  final ArchitecturePattern architecture;

  /// Detected naming conventions.
  final NamingConventions naming;

  /// Detected code style.
  final CodeStyle style;

  /// Important/key files in the project.
  final List<String> keyFiles;

  /// LLM-generated summaries of representative files.
  final Map<String, String> fileSummaries;

  /// Total number of files scanned.
  final int totalFiles;

  /// When this knowledge was generated.
  final DateTime learnedAt;

  const ProjectKnowledge({
    required this.projectPath,
    required this.architecture,
    required this.naming,
    required this.style,
    required this.keyFiles,
    required this.fileSummaries,
    required this.totalFiles,
    required this.learnedAt,
  });

  /// Format this knowledge as a context string for LLM prompts.
  ///
  /// This is the primary method for integrating project knowledge
  /// into code generation prompts.
  String toPromptContext() {
    final buffer = StringBuffer();
    buffer.writeln('Project Knowledge:');
    buffer.writeln('  Path: $projectPath');
    buffer.writeln('  Files: $totalFiles total');
    buffer.writeln('  Architecture: ${architecture.pattern} (confidence: ${(architecture.confidence * 100).toStringAsFixed(0)}%)');
    buffer.writeln('  Naming: ${naming.primary}');
    buffer.writeln('  Indentation: ${style.indentation}');
    buffer.writeln('  Max Line Length: ${style.maxLineLength}');
    if (keyFiles.isNotEmpty) {
      buffer.writeln('  Key Files:');
      for (final file in keyFiles.take(10)) {
        buffer.writeln('    - ${p.relative(file, from: projectPath)}');
      }
    }
    return buffer.toString();
  }

  /// Convert to JSON for caching/persistence.
  Map<String, dynamic> toJson() => {
        'projectPath': projectPath,
        'architecture': architecture.toJson(),
        'naming': naming.toJson(),
        'style': style.toJson(),
        'keyFiles': keyFiles,
        'fileSummaries': fileSummaries,
        'totalFiles': totalFiles,
        'learnedAt': learnedAt.toIso8601String(),
      };
}

// ═══════════════════════════════════════════════════════════════════════════
// Architecture Pattern
// ═══════════════════════════════════════════════════════════════════════════

/// Detected architecture pattern of a project.
class ArchitecturePattern {
  /// Pattern name (e.g., 'clean', 'mvc', 'bloc').
  final String pattern;

  /// Confidence score 0.0-1.0.
  final double confidence;

  /// Boolean indicators that led to detection.
  final Map<String, bool> indicators;

  const ArchitecturePattern({
    required this.pattern,
    required this.confidence,
    this.indicators = const {},
  });

  Map<String, dynamic> toJson() => {
        'pattern': pattern,
        'confidence': confidence,
        'indicators': indicators,
      };
}

/// Known architecture patterns.
enum ArchitecturePatternType {
  clean,
  mvc,
  mvvm,
  bloc,
  provider,
  feature,
  simple,
  unknown,
}

// ═══════════════════════════════════════════════════════════════════════════
// Naming Conventions
// ═══════════════════════════════════════════════════════════════════════════

/// Detected naming conventions of a project.
class NamingConventions {
  /// Primary naming convention (e.g., 'camelCase', 'PascalCase').
  final String primary;

  /// File naming convention.
  final String fileNaming;

  /// Class/type naming convention.
  final String classNaming;

  /// Variable/function naming convention.
  final String variableNaming;

  /// Confidence score 0.0-1.0.
  final double confidence;

  const NamingConventions({
    required this.primary,
    required this.fileNaming,
    required this.classNaming,
    required this.variableNaming,
    this.confidence = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'primary': primary,
        'fileNaming': fileNaming,
        'classNaming': classNaming,
        'variableNaming': variableNaming,
        'confidence': confidence,
      };
}

// ═══════════════════════════════════════════════════════════════════════════
// Code Style
// ═══════════════════════════════════════════════════════════════════════════

/// Detected code style of a project.
class CodeStyle {
  /// Indentation style (e.g., '2_spaces', '4_spaces', 'tabs').
  final String indentation;

  /// Maximum line length.
  final int maxLineLength;

  /// Whether trailing commas are used.
  final bool trailingCommas;

  /// Whether semicolons are required.
  final bool semicolonsRequired;

  /// Whether imports are grouped (dart: first, then package:, then relative).
  final bool groupedImports;

  const CodeStyle({
    required this.indentation,
    required this.maxLineLength,
    required this.trailingCommas,
    required this.semicolonsRequired,
    required this.groupedImports,
  });

  /// Format configuration as a style guide string.
  String toStyleGuide() {
    return '''
Code Style Guide:
- Indentation: $indentation
- Max Line Length: $maxLineLength
- Trailing Commas: ${trailingCommas ? 'required' : 'optional'}
- Semicolons: ${semicolonsRequired ? 'required' : 'optional'}
- Import Grouping: ${groupedImports ? 'required' : 'optional'}
'''.trim();
  }

  Map<String, dynamic> toJson() => {
        'indentation': indentation,
        'maxLineLength': maxLineLength,
        'trailingCommas': trailingCommas,
        'semicolonsRequired': semicolonsRequired,
        'groupedImports': groupedImports,
      };
}

// ═══════════════════════════════════════════════════════════════════════════
// Code Snippet
// ═══════════════════════════════════════════════════════════════════════════

/// A relevant code snippet found in the project.
class CodeSnippet {
  /// File path relative to project root.
  final String filePath;

  /// The code content.
  final String code;

  /// Programming language.
  final String language;

  /// Relevance score (0.0-1.0, higher = more relevant).
  final double relevance;

  /// Line number where the snippet starts.
  final int? lineNumber;

  const CodeSnippet({
    required this.filePath,
    required this.code,
    required this.language,
    this.relevance = 0.0,
    this.lineNumber,
  });

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'code': code,
        'language': language,
        'relevance': relevance,
        'lineNumber': lineNumber,
      };
}

// ═══════════════════════════════════════════════════════════════════════════
// Project Learning Exception
// ═══════════════════════════════════════════════════════════════════════════

/// Exception for project learning operations.
class ProjectLearningException implements Exception {
  final String message;
  final String? operation;

  const ProjectLearningException(this.message, {this.operation});

  @override
  String toString() => 'ProjectLearningException [$operation]: $message';
}
