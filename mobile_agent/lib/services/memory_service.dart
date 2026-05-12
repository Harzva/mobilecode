// lib/services/memory_service.dart
// Memory Service — Manages everything the AI has learned about the user.
//
// This service is the backbone of the AI's long-term memory, tracking:
// - Project knowledge (indexed files, functions, classes)
// - Code preferences (naming conventions, style, patterns)
// - Conversation history with the AI assistant
// - Error patterns (common mistakes and their solutions)
// - Frequently used code snippets
// - User corrections (when user edits AI-generated code)
//
// All memories can be viewed, edited, exported, and deleted through the
// Memory Manager screen.
//
// Usage:
// ```dart
// final memory = MemoryService();
// await memory.init();
// final projects = await memory.getProjectMemories();
// final prefs = await memory.getCodePreferences();
// ```

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Enums
// ═══════════════════════════════════════════════════════════════════════════

/// Naming convention preferences for code generation.
enum NamingConvention { camelCase, snakeCase, pascalCase, hungarian }

/// Extension for display labels.
extension NamingConventionExt on NamingConvention {
  String get label {
    switch (this) {
      case NamingConvention.camelCase:
        return 'camelCase';
      case NamingConvention.snakeCase:
        return 'snake_case';
      case NamingConvention.pascalCase:
        return 'PascalCase';
      case NamingConvention.hungarian:
        return 'Hungarian';
    }
  }

  String get displayName {
    switch (this) {
      case NamingConvention.camelCase:
        return '小驼峰 (camelCase)';
      case NamingConvention.snakeCase:
        return '蛇形 (snake_case)';
      case NamingConvention.pascalCase:
        return '大驼峰 (PascalCase)';
      case NamingConvention.hungarian:
        return '匈牙利 (Hungarian)';
    }
  }
}

/// Indentation style preference.
enum IndentStyle { spaces, tabs }

extension IndentStyleExt on IndentStyle {
  String get label => this == IndentStyle.spaces ? '空格' : '制表符';
}

/// Quote style preference.
enum QuoteStyle { single, double }

extension QuoteStyleExt on QuoteStyle {
  String get label => this == QuoteStyle.single ? "单引号 (')" : '双引号 (")';
}

/// Comment style preference.
enum CommentStyle { minimal, moderate, detailed }

extension CommentStyleExt on CommentStyle {
  String get displayName {
    switch (this) {
      case CommentStyle.minimal:
        return '简洁';
      case CommentStyle.moderate:
        return '适中';
      case CommentStyle.detailed:
        return '详细';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Data Models
// ═══════════════════════════════════════════════════════════════════════════

/// Memory about an indexed project.
@immutable
class ProjectMemory {
  final String id;
  final String projectId;
  final String projectName;
  final int indexedFiles;
  final int indexedFunctions;
  final int indexedClasses;
  final DateTime lastIndexed;
  final double indexSizeKB;

  const ProjectMemory({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.indexedFiles,
    required this.indexedFunctions,
    required this.indexedClasses,
    required this.lastIndexed,
    required this.indexSizeKB,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'projectName': projectName,
        'indexedFiles': indexedFiles,
        'indexedFunctions': indexedFunctions,
        'indexedClasses': indexedClasses,
        'lastIndexed': lastIndexed.toIso8601String(),
        'indexSizeKB': indexSizeKB,
      };

  factory ProjectMemory.fromJson(Map<String, dynamic> json) => ProjectMemory(
        id: json['id'] as String,
        projectId: json['projectId'] as String,
        projectName: json['projectName'] as String,
        indexedFiles: json['indexedFiles'] as int,
        indexedFunctions: json['indexedFunctions'] as int,
        indexedClasses: json['indexedClasses'] as int,
        lastIndexed: DateTime.parse(json['lastIndexed'] as String),
        indexSizeKB: (json['indexSizeKB'] as num).toDouble(),
      );
}

/// User's code style preferences.
class CodePreferences {
  NamingConvention namingConvention;
  IndentStyle indentStyle;
  int indentSize;
  bool useTrailingCommas;
  int maxLineLength;
  QuoteStyle quoteStyle;
  CommentStyle commentStyle;
  bool preferConst;
  bool preferFinal;
  List<String> importOrder;
  Map<String, dynamic> customRules;

  CodePreferences({
    this.namingConvention = NamingConvention.camelCase,
    this.indentStyle = IndentStyle.spaces,
    this.indentSize = 2,
    this.useTrailingCommas = true,
    this.maxLineLength = 80,
    this.quoteStyle = QuoteStyle.single,
    this.commentStyle = CommentStyle.moderate,
    this.preferConst = true,
    this.preferFinal = true,
    this.importOrder = const ['dart:', 'package:', 'relative'],
    this.customRules = const {},
  });

  Map<String, dynamic> toJson() => {
        'namingConvention': namingConvention.index,
        'indentStyle': indentStyle.index,
        'indentSize': indentSize,
        'useTrailingCommas': useTrailingCommas,
        'maxLineLength': maxLineLength,
        'quoteStyle': quoteStyle.index,
        'commentStyle': commentStyle.index,
        'preferConst': preferConst,
        'preferFinal': preferFinal,
        'importOrder': importOrder,
        'customRules': customRules,
      };

  factory CodePreferences.fromJson(Map<String, dynamic> json) => CodePreferences(
        namingConvention: NamingConvention.values[json['namingConvention'] as int? ?? 0],
        indentStyle: IndentStyle.values[json['indentStyle'] as int? ?? 0],
        indentSize: json['indentSize'] as int? ?? 2,
        useTrailingCommas: json['useTrailingCommas'] as bool? ?? true,
        maxLineLength: json['maxLineLength'] as int? ?? 80,
        quoteStyle: QuoteStyle.values[json['quoteStyle'] as int? ?? 0],
        commentStyle: CommentStyle.values[json['commentStyle'] as int? ?? 1],
        preferConst: json['preferConst'] as bool? ?? true,
        preferFinal: json['preferFinal'] as bool? ?? true,
        importOrder: (json['importOrder'] as List<dynamic>?)?.cast<String>() ??
            const ['dart:', 'package:', 'relative'],
        customRules: (json['customRules'] as Map<String, dynamic>?) ?? const {},
      );
}

/// A single conversation record with the AI.
@immutable
class ConversationRecord {
  final String id;
  final DateTime timestamp;
  final String userMessage;
  final String aiResponse;
  final String? projectId;
  final List<String> tags;
  bool isPinned;

  ConversationRecord({
    required this.id,
    required this.timestamp,
    required this.userMessage,
    required this.aiResponse,
    this.projectId,
    this.tags = const [],
    this.isPinned = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'userMessage': userMessage,
        'aiResponse': aiResponse,
        if (projectId != null) 'projectId': projectId,
        'tags': tags,
        'isPinned': isPinned,
      };

  factory ConversationRecord.fromJson(Map<String, dynamic> json) =>
      ConversationRecord(
        id: json['id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        userMessage: json['userMessage'] as String,
        aiResponse: json['aiResponse'] as String,
        projectId: json['projectId'] as String?,
        tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
        isPinned: json['isPinned'] as bool? ?? false,
      );
}

/// A recorded error pattern and its solution.
@immutable
class ErrorPattern {
  final String id;
  final String errorType;
  final String errorMessage;
  final String solution;
  final int occurrenceCount;
  final DateTime lastOccurred;
  final String? relatedFile;

  const ErrorPattern({
    required this.id,
    required this.errorType,
    required this.errorMessage,
    required this.solution,
    required this.occurrenceCount,
    required this.lastOccurred,
    this.relatedFile,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'errorType': errorType,
        'errorMessage': errorMessage,
        'solution': solution,
        'occurrenceCount': occurrenceCount,
        'lastOccurred': lastOccurred.toIso8601String(),
        if (relatedFile != null) 'relatedFile': relatedFile,
      };

  factory ErrorPattern.fromJson(Map<String, dynamic> json) => ErrorPattern(
        id: json['id'] as String,
        errorType: json['errorType'] as String,
        errorMessage: json['errorMessage'] as String,
        solution: json['solution'] as String,
        occurrenceCount: json['occurrenceCount'] as int,
        lastOccurred: DateTime.parse(json['lastOccurred'] as String),
        relatedFile: json['relatedFile'] as String?,
      );
}

/// A frequently used code snippet.
@immutable
class FrequentSnippet {
  final String id;
  final String code;
  final String language;
  final int usageCount;
  final DateTime lastUsed;
  bool isPinned;

  FrequentSnippet({
    required this.id,
    required this.code,
    required this.language,
    required this.usageCount,
    required this.lastUsed,
    this.isPinned = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'language': language,
        'usageCount': usageCount,
        'lastUsed': lastUsed.toIso8601String(),
        'isPinned': isPinned,
      };

  factory FrequentSnippet.fromJson(Map<String, dynamic> json) => FrequentSnippet(
        id: json['id'] as String,
        code: json['code'] as String,
        language: json['language'] as String,
        usageCount: json['usageCount'] as int,
        lastUsed: DateTime.parse(json['lastUsed'] as String),
        isPinned: json['isPinned'] as bool? ?? false,
      );
}

/// A user correction to AI-generated code.
@immutable
class UserCorrection {
  final String id;
  final String originalCode;
  final String correctedCode;
  final String reason;
  final DateTime timestamp;
  final String? projectId;

  const UserCorrection({
    required this.id,
    required this.originalCode,
    required this.correctedCode,
    required this.reason,
    required this.timestamp,
    this.projectId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'originalCode': originalCode,
        'correctedCode': correctedCode,
        'reason': reason,
        'timestamp': timestamp.toIso8601String(),
        if (projectId != null) 'projectId': projectId,
      };

  factory UserCorrection.fromJson(Map<String, dynamic> json) => UserCorrection(
        id: json['id'] as String,
        originalCode: json['originalCode'] as String,
        correctedCode: json['correctedCode'] as String,
        reason: json['reason'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        projectId: json['projectId'] as String?,
      );
}

/// Aggregate memory statistics.
@immutable
class MemoryStats {
  final int totalProjects;
  final int totalConversations;
  final int totalErrorPatterns;
  final int totalSnippets;
  final int memorySizeKB;
  final DateTime lastSync;

  const MemoryStats({
    required this.totalProjects,
    required this.totalConversations,
    required this.totalErrorPatterns,
    required this.totalSnippets,
    required this.memorySizeKB,
    required this.lastSync,
  });

  int get totalItems =>
      totalProjects + totalConversations + totalErrorPatterns + totalSnippets;

  Map<String, dynamic> toJson() => {
        'totalProjects': totalProjects,
        'totalConversations': totalConversations,
        'totalErrorPatterns': totalErrorPatterns,
        'totalSnippets': totalSnippets,
        'memorySizeKB': memorySizeKB,
        'lastSync': lastSync.toIso8601String(),
      };
}

// ═══════════════════════════════════════════════════════════════════════════
// Memory Service
// ═══════════════════════════════════════════════════════════════════════════

/// Manages everything the AI has remembered about the user.
///
/// This service persists all memory data via SharedPreferences and provides
/// CRUD operations for project memories, code preferences, conversation
/// history, error patterns, frequently used snippets, and user corrections.
///
/// Memories can be exported/imported as JSON for backup and migration.
class MemoryService extends ChangeNotifier {
  SharedPreferences? _prefs;
  bool _initialized = false;

  // In-memory caches
  final List<ProjectMemory> _projectCache = [];
  CodePreferences? _prefsCache;
  final List<ConversationRecord> _conversationCache = [];
  final List<ErrorPattern> _errorCache = [];
  final List<FrequentSnippet> _snippetCache = [];
  final List<UserCorrection> _correctionCache = [];

  // Storage keys
  static const String _keyProjects = 'memory_projects';
  static const String _keyCodePrefs = 'memory_code_prefs';
  static const String _keyConversations = 'memory_conversations';
  static const String _keyErrors = 'memory_errors';
  static const String _keySnippets = 'memory_snippets';
  static const String _keyCorrections = 'memory_corrections';
  static const String _keyLastSync = 'memory_last_sync';

  // Singleton
  static MemoryService? _instance;
  factory MemoryService() {
    _instance ??= MemoryService._internal();
    return _instance!;
  }
  MemoryService._internal();

  // ── Initialization ─────────────────────────────────────────────────

  /// Initialize the service and load all cached memories from storage.
  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    await _loadAll();
    _initialized = true;
    debugPrint('[MemoryService] Initialized with ${_projectCache.length} projects, '
        '${_conversationCache.length} conversations');
  }

  void _ensureInit() {
    if (!_initialized) throw StateError('MemoryService not initialized. Call init() first.');
  }

  // ── Project Memory ─────────────────────────────────────────────────

  /// Get all indexed project memories.
  Future<List<ProjectMemory>> getProjectMemories() async {
    _ensureInit();
    return List.unmodifiable(_projectCache);
  }

  /// Delete a project memory by its ID.
  Future<void> deleteProjectMemory(String id) async {
    _ensureInit();
    _projectCache.removeWhere((p) => p.id == id);
    await _persistProjects();
    notifyListeners();
    debugPrint('[MemoryService] Deleted project memory: $id');
  }

  /// Refresh (re-index) a project's memory.
  Future<void> refreshProjectMemory(String projectId) async {
    _ensureInit();
    debugPrint('[MemoryService] Refreshing project memory: $projectId');
    // In production, this triggers the ProjectLearningService to re-scan.
    // For now, update the timestamp.
    final idx = _projectCache.indexWhere((p) => p.projectId == projectId);
    if (idx >= 0) {
      final old = _projectCache[idx];
      _projectCache[idx] = ProjectMemory(
        id: old.id,
        projectId: old.projectId,
        projectName: old.projectName,
        indexedFiles: old.indexedFiles,
        indexedFunctions: old.indexedFunctions,
        indexedClasses: old.indexedClasses,
        lastIndexed: DateTime.now(),
        indexSizeKB: old.indexSizeKB,
      );
      await _persistProjects();
      notifyListeners();
    }
  }

  /// Add or update a project memory (internal/API use).
  Future<void> upsertProjectMemory(ProjectMemory memory) async {
    _ensureInit();
    final idx = _projectCache.indexWhere((p) => p.id == memory.id);
    if (idx >= 0) {
      _projectCache[idx] = memory;
    } else {
      _projectCache.add(memory);
    }
    await _persistProjects();
    notifyListeners();
  }

  // ── Code Preferences ───────────────────────────────────────────────

  /// Get the user's current code preferences.
  Future<CodePreferences> getCodePreferences() async {
    _ensureInit();
    return _prefsCache ?? CodePreferences();
  }

  /// Update code preferences.
  Future<void> updateCodePreferences(CodePreferences prefs) async {
    _ensureInit();
    _prefsCache = prefs;
    await _persistCodePrefs();
    notifyListeners();
    debugPrint('[MemoryService] Code preferences updated');
  }

  /// Reset code preferences to defaults.
  Future<void> resetCodePreferences() async {
    _ensureInit();
    _prefsCache = CodePreferences();
    await _persistCodePrefs();
    notifyListeners();
    debugPrint('[MemoryService] Code preferences reset to defaults');
  }

  // ── Conversation History ───────────────────────────────────────────

  /// Get conversation history, optionally limited.
  Future<List<ConversationRecord>> getConversationHistory({int limit = 100}) async {
    _ensureInit();
    final sorted = List<ConversationRecord>.from(_conversationCache)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (sorted.length > limit) return sorted.sublist(0, limit);
    return sorted;
  }

  /// Add a conversation record.
  Future<void> addConversation(ConversationRecord record) async {
    _ensureInit();
    _conversationCache.add(record);
    // Keep max 500 conversations.
    if (_conversationCache.length > 500) {
      _conversationCache.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      _conversationCache.removeAt(0);
    }
    await _persistConversations();
    notifyListeners();
  }

  /// Delete a single conversation by ID.
  Future<void> deleteConversation(String id) async {
    _ensureInit();
    _conversationCache.removeWhere((c) => c.id == id);
    await _persistConversations();
    notifyListeners();
  }

  /// Clear all conversation history.
  Future<void> clearConversationHistory() async {
    _ensureInit();
    _conversationCache.clear();
    await _persistConversations();
    notifyListeners();
    debugPrint('[MemoryService] Conversation history cleared');
  }

  /// Search conversations by query string.
  Future<List<ConversationRecord>> searchConversations(String query) async {
    _ensureInit();
    final lower = query.toLowerCase();
    return _conversationCache.where((c) {
      return c.userMessage.toLowerCase().contains(lower) ||
          c.aiResponse.toLowerCase().contains(lower) ||
          c.tags.any((t) => t.toLowerCase().contains(lower));
    }).toList();
  }

  /// Toggle pin status on a conversation.
  Future<void> togglePinConversation(String id) async {
    _ensureInit();
    final record = _conversationCache.firstWhere((c) => c.id == id);
    record.isPinned = !record.isPinned;
    await _persistConversations();
    notifyListeners();
  }

  // ── Error Patterns ─────────────────────────────────────────────────

  /// Get all recorded error patterns.
  Future<List<ErrorPattern>> getErrorPatterns() async {
    _ensureInit();
    return List.unmodifiable(_errorCache);
  }

  /// Record a new error pattern.
  Future<void> recordErrorPattern(ErrorPattern pattern) async {
    _ensureInit();
    final existing = _errorCache.indexWhere((e) => e.errorType == pattern.errorType);
    if (existing >= 0) {
      final old = _errorCache[existing];
      _errorCache[existing] = ErrorPattern(
        id: old.id,
        errorType: old.errorType,
        errorMessage: pattern.errorMessage,
        solution: pattern.solution,
        occurrenceCount: old.occurrenceCount + 1,
        lastOccurred: DateTime.now(),
        relatedFile: pattern.relatedFile ?? old.relatedFile,
      );
    } else {
      _errorCache.add(pattern);
    }
    await _persistErrors();
    notifyListeners();
  }

  /// Delete an error pattern by ID.
  Future<void> deleteErrorPattern(String id) async {
    _ensureInit();
    _errorCache.removeWhere((e) => e.id == id);
    await _persistErrors();
    notifyListeners();
  }

  // ── Frequently Used Snippets ───────────────────────────────────────

  /// Get all frequently used snippets.
  Future<List<FrequentSnippet>> getFrequentSnippets() async {
    _ensureInit();
    final sorted = List<FrequentSnippet>.from(_snippetCache)
      ..sort((a, b) {
        // Pinned first, then by usage count.
        if (a.isPinned && !b.isPinned) return -1;
        if (!a.isPinned && b.isPinned) return 1;
        return b.usageCount.compareTo(a.usageCount);
      });
    return sorted;
  }

  /// Record usage of a snippet (increments counter).
  Future<void> recordSnippetUsage(String snippetId) async {
    _ensureInit();
    final idx = _snippetCache.indexWhere((s) => s.id == snippetId);
    if (idx >= 0) {
      final old = _snippetCache[idx];
      _snippetCache[idx] = FrequentSnippet(
        id: old.id,
        code: old.code,
        language: old.language,
        usageCount: old.usageCount + 1,
        lastUsed: DateTime.now(),
        isPinned: old.isPinned,
      );
      await _persistSnippets();
      notifyListeners();
    }
  }

  /// Pin or unpin a snippet.
  Future<void> pinSnippet(String snippetId) async {
    _ensureInit();
    final snippet = _snippetCache.firstWhere((s) => s.id == snippetId);
    snippet.isPinned = !snippet.isPinned;
    await _persistSnippets();
    notifyListeners();
  }

  /// Add a new frequent snippet.
  Future<void> addFrequentSnippet(FrequentSnippet snippet) async {
    _ensureInit();
    _snippetCache.add(snippet);
    await _persistSnippets();
    notifyListeners();
  }

  // ── User Corrections ───────────────────────────────────────────────

  /// Get all user corrections.
  Future<List<UserCorrection>> getUserCorrections() async {
    _ensureInit();
    return List.unmodifiable(_correctionCache);
  }

  /// Add a user correction.
  Future<void> addUserCorrection(UserCorrection correction) async {
    _ensureInit();
    _correctionCache.add(correction);
    // Keep max 200 corrections.
    if (_correctionCache.length > 200) {
      _correctionCache.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      _correctionCache.removeAt(0);
    }
    await _persistCorrections();
    notifyListeners();
  }

  /// Delete a user correction by ID.
  Future<void> deleteCorrection(String id) async {
    _ensureInit();
    _correctionCache.removeWhere((c) => c.id == id);
    await _persistCorrections();
    notifyListeners();
  }

  // ── Memory Statistics ──────────────────────────────────────────────

  /// Get aggregate statistics about all stored memories.
  Future<MemoryStats> getMemoryStats() async {
    _ensureInit();
    var size = 0;
    for (final p in _projectCache) size += p.indexSizeKB.ceil();
    size += _conversationCache.length * 2; // ~2KB per conversation
    size += _snippetCache.length; // ~1KB per snippet
    size += _correctionCache.length; // ~1KB per correction

    return MemoryStats(
      totalProjects: _projectCache.length,
      totalConversations: _conversationCache.length,
      totalErrorPatterns: _errorCache.length,
      totalSnippets: _snippetCache.length,
      memorySizeKB: size,
      lastSync: DateTime.now(),
    );
  }

  // ── Export / Import ────────────────────────────────────────────────

  /// Export all memories as a JSON string.
  Future<String> exportMemories() async {
    _ensureInit();
    final export = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'projects': _projectCache.map((p) => p.toJson()).toList(),
      'codePreferences': (_prefsCache ?? CodePreferences()).toJson(),
      'conversations': _conversationCache.map((c) => c.toJson()).toList(),
      'errorPatterns': _errorCache.map((e) => e.toJson()).toList(),
      'snippets': _snippetCache.map((s) => s.toJson()).toList(),
      'corrections': _correctionCache.map((c) => c.toJson()).toList(),
    };
    return jsonEncode(export);
  }

  /// Import memories from a JSON string.
  Future<void> importMemories(String jsonData) async {
    _ensureInit();
    try {
      final decoded = jsonDecode(jsonData) as Map<String, dynamic>;

      if (decoded['projects'] != null) {
        final list = decoded['projects'] as List<dynamic>;
        _projectCache.clear();
        _projectCache.addAll(list.map((j) => ProjectMemory.fromJson(j as Map<String, dynamic>)));
      }

      if (decoded['codePreferences'] != null) {
        _prefsCache = CodePreferences.fromJson(decoded['codePreferences'] as Map<String, dynamic>);
      }

      if (decoded['conversations'] != null) {
        final list = decoded['conversations'] as List<dynamic>;
        _conversationCache.clear();
        _conversationCache.addAll(
            list.map((j) => ConversationRecord.fromJson(j as Map<String, dynamic>)));
      }

      if (decoded['errorPatterns'] != null) {
        final list = decoded['errorPatterns'] as List<dynamic>;
        _errorCache.clear();
        _errorCache.addAll(list.map((j) => ErrorPattern.fromJson(j as Map<String, dynamic>)));
      }

      if (decoded['snippets'] != null) {
        final list = decoded['snippets'] as List<dynamic>;
        _snippetCache.clear();
        _snippetCache.addAll(list.map((j) => FrequentSnippet.fromJson(j as Map<String, dynamic>)));
      }

      if (decoded['corrections'] != null) {
        final list = decoded['corrections'] as List<dynamic>;
        _correctionCache.clear();
        _correctionCache
            .addAll(list.map((j) => UserCorrection.fromJson(j as Map<String, dynamic>)));
      }

      await _persistAll();
      notifyListeners();
      debugPrint('[MemoryService] Memories imported successfully');
    } catch (e) {
      debugPrint('[MemoryService] Import failed: $e');
      throw FormatException('Invalid memory export data: $e');
    }
  }

  /// Clear all memories (dangerous — used by Memory Manager).
  Future<void> clearAllMemories() async {
    _ensureInit();
    _projectCache.clear();
    _prefsCache = null;
    _conversationCache.clear();
    _errorCache.clear();
    _snippetCache.clear();
    _correctionCache.clear();
    await _persistAll();
    notifyListeners();
    debugPrint('[MemoryService] All memories cleared');
  }

  // ── Persistence ────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    await _loadProjects();
    await _loadCodePrefs();
    await _loadConversations();
    await _loadErrors();
    await _loadSnippets();
    await _loadCorrections();
  }

  Future<void> _persistAll() async {
    await _persistProjects();
    await _persistCodePrefs();
    await _persistConversations();
    await _persistErrors();
    await _persistSnippets();
    await _persistCorrections();
  }

  Future<void> _loadProjects() async {
    try {
      final jsonStr = _prefs?.getString(_keyProjects);
      if (jsonStr == null) return;
      final list = jsonDecode(jsonStr) as List<dynamic>;
      _projectCache.clear();
      _projectCache.addAll(list.map((j) => ProjectMemory.fromJson(j as Map<String, dynamic>)));
    } catch (e) {
      debugPrint('[MemoryService] Failed to load projects: $e');
    }
  }

  Future<void> _persistProjects() async {
    try {
      final data = _projectCache.map((p) => p.toJson()).toList();
      await _prefs?.setString(_keyProjects, jsonEncode(data));
    } catch (e) {
      debugPrint('[MemoryService] Failed to persist projects: $e');
    }
  }

  Future<void> _loadCodePrefs() async {
    try {
      final jsonStr = _prefs?.getString(_keyCodePrefs);
      if (jsonStr == null) return;
      _prefsCache = CodePreferences.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[MemoryService] Failed to load code prefs: $e');
    }
  }

  Future<void> _persistCodePrefs() async {
    try {
      final data = (_prefsCache ?? CodePreferences()).toJson();
      await _prefs?.setString(_keyCodePrefs, jsonEncode(data));
    } catch (e) {
      debugPrint('[MemoryService] Failed to persist code prefs: $e');
    }
  }

  Future<void> _loadConversations() async {
    try {
      final jsonStr = _prefs?.getString(_keyConversations);
      if (jsonStr == null) return;
      final list = jsonDecode(jsonStr) as List<dynamic>;
      _conversationCache.clear();
      _conversationCache
          .addAll(list.map((j) => ConversationRecord.fromJson(j as Map<String, dynamic>)));
    } catch (e) {
      debugPrint('[MemoryService] Failed to load conversations: $e');
    }
  }

  Future<void> _persistConversations() async {
    try {
      final data = _conversationCache.map((c) => c.toJson()).toList();
      await _prefs?.setString(_keyConversations, jsonEncode(data));
    } catch (e) {
      debugPrint('[MemoryService] Failed to persist conversations: $e');
    }
  }

  Future<void> _loadErrors() async {
    try {
      final jsonStr = _prefs?.getString(_keyErrors);
      if (jsonStr == null) return;
      final list = jsonDecode(jsonStr) as List<dynamic>;
      _errorCache.clear();
      _errorCache.addAll(list.map((j) => ErrorPattern.fromJson(j as Map<String, dynamic>)));
    } catch (e) {
      debugPrint('[MemoryService] Failed to load errors: $e');
    }
  }

  Future<void> _persistErrors() async {
    try {
      final data = _errorCache.map((e) => e.toJson()).toList();
      await _prefs?.setString(_keyErrors, jsonEncode(data));
    } catch (e) {
      debugPrint('[MemoryService] Failed to persist errors: $e');
    }
  }

  Future<void> _loadSnippets() async {
    try {
      final jsonStr = _prefs?.getString(_keySnippets);
      if (jsonStr == null) return;
      final list = jsonDecode(jsonStr) as List<dynamic>;
      _snippetCache.clear();
      _snippetCache.addAll(list.map((j) => FrequentSnippet.fromJson(j as Map<String, dynamic>)));
    } catch (e) {
      debugPrint('[MemoryService] Failed to load snippets: $e');
    }
  }

  Future<void> _persistSnippets() async {
    try {
      final data = _snippetCache.map((s) => s.toJson()).toList();
      await _prefs?.setString(_keySnippets, jsonEncode(data));
    } catch (e) {
      debugPrint('[MemoryService] Failed to persist snippets: $e');
    }
  }

  Future<void> _loadCorrections() async {
    try {
      final jsonStr = _prefs?.getString(_keyCorrections);
      if (jsonStr == null) return;
      final list = jsonDecode(jsonStr) as List<dynamic>;
      _correctionCache.clear();
      _correctionCache
          .addAll(list.map((j) => UserCorrection.fromJson(j as Map<String, dynamic>)));
    } catch (e) {
      debugPrint('[MemoryService] Failed to load corrections: $e');
    }
  }

  Future<void> _persistCorrections() async {
    try {
      final data = _correctionCache.map((c) => c.toJson()).toList();
      await _prefs?.setString(_keyCorrections, jsonEncode(data));
    } catch (e) {
      debugPrint('[MemoryService] Failed to persist corrections: $e');
    }
  }
}
