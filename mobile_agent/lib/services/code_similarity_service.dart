// lib/services/code_similarity_service.dart
// Code Similarity Service — Detects how much user edited AI-generated code.
//
// Used to measure "code acceptance rate" and identify what specifically
// changed between AI-generated and user-edited versions.
//
// Algorithms implemented:
// - Levenshtein distance for text-level similarity
// - Normalized similarity score (0.0 = completely different, 1.0 = identical)
// - Change detection for variable names, logic, and style
// - Edit classification (naming, style, logic fix, etc.)
//
// Usage:
// ```dart
// final sim = CodeSimilarityService.calculateSimilarity(aiCode, userCode);
// final changes = CodeSimilarityService.detectChanges(aiCode, userCode);
// final editType = CodeSimilarityService.classifyEdit(aiCode, userCode);
// ```

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Code Similarity Service
// ═══════════════════════════════════════════════════════════════════════════

/// Detects code similarity between AI-generated and user-edited code.
///
/// This service provides static methods for comparing code strings
/// and classifying the nature of edits. It's used by the feedback
/// learning system to measure code acceptance and understand what
/// users typically change.
///
/// The similarity score ranges from 0.0 (completely different) to
/// 1.0 (identical). Scores above 0.8 indicate high acceptance.
class CodeSimilarityService {
  CodeSimilarityService._(); // Private constructor — all methods are static.

  // ── Similarity Calculation ─────────────────────────────────────────

  /// Calculate the similarity between two code strings.
  ///
  /// Uses the Levenshtein distance algorithm normalized by the
  /// maximum string length to produce a 0.0-1.0 similarity score.
  ///
  /// [original] the original AI-generated code.
  /// [modified] the user-edited version.
  /// Returns a value between 0.0 (completely different) and 1.0 (identical).
  static double calculateSimilarity(String original, String modified) {
    if (original == modified) return 1.0;
    if (original.isEmpty || modified.isEmpty) return 0.0;

    // Normalize whitespace before comparison.
    final normOriginal = _normalizeWhitespace(original);
    final normModified = _normalizeWhitespace(modified);

    if (normOriginal == normModified) return 1.0;

    // Use Levenshtein distance for character-level similarity.
    final distance = _levenshteinDistance(normOriginal, normModified);
    final maxLength = math.max(normOriginal.length, normModified.length);

    if (maxLength == 0) return 1.0;

    return 1.0 - (distance / maxLength);
  }

  /// Calculate a weighted similarity that considers both text and tokens.
  ///
  /// This combines character-level Levenshtein distance with
  /// token-level comparison to better capture code similarity.
  ///
  /// [original] the original code.
  /// [modified] the modified code.
  /// Returns a weighted similarity score between 0.0 and 1.0.
  static double calculateWeightedSimilarity(String original, String modified) {
    // Text similarity (60% weight).
    final textSim = calculateSimilarity(original, modified);

    // Token similarity (40% weight).
    final tokenSim = _tokenSimilarity(original, modified);

    return (textSim * 0.6) + (tokenSim * 0.4);
  }

  // ── Change Detection ───────────────────────────────────────────────

  /// Detect what specifically changed between two code versions.
  ///
  /// Analyzes the diff and categorizes changes by type:
  /// - variable renames
  /// - function renames
  /// - logic changes
  /// - style changes (whitespace, formatting)
  /// - comment additions/removals
  ///
  /// [original] the original AI-generated code.
  /// [modified] the user-edited version.
  /// Returns a list of classified changes.
  static List<CodeChange> detectChanges(String original, String modified) {
    final changes = <CodeChange>[];

    if (original == modified) return changes;

    // Detect variable renames.
    final variableChanges = _detectVariableRenames(original, modified);
    changes.addAll(variableChanges);

    // Detect function/method renames.
    final functionChanges = _detectFunctionRenames(original, modified);
    changes.addAll(functionChanges);

    // Detect logic changes (control flow, operators, values).
    final logicChanges = _detectLogicChanges(original, modified);
    changes.addAll(logicChanges);

    // Detect style changes (whitespace, formatting, semicolons).
    final styleChanges = _detectStyleChanges(original, modified);
    changes.addAll(styleChanges);

    // Detect comment changes.
    final commentChanges = _detectCommentChanges(original, modified);
    changes.addAll(commentChanges);

    // Detect import changes.
    final importChanges = _detectImportChanges(original, modified);
    changes.addAll(importChanges);

    return changes;
  }

  // ── Edit Classification ────────────────────────────────────────────

  /// Classify the overall type of edit made to the code.
  ///
  /// Analyzes the changes and determines the primary motivation:
  /// - namingChange: only variable/function names changed
  /// - styleChange: only formatting/whitespace changed
  /// - logicFix: code logic was corrected or improved
  /// - bugFix: a specific bug was fixed
  /// - featureAdd: new functionality was added
  /// - refactoring: structural reorganization
  /// - none: no meaningful changes
  ///
  /// [original] the original AI-generated code.
  /// [modified] the user-edited version.
  /// Returns the classified [EditType].
  static EditType classifyEdit(String original, String modified) {
    if (original == modified) return EditType.none;

    final similarity = calculateSimilarity(original, modified);
    final changes = detectChanges(original, modified);

    // High similarity (>0.9) suggests minor changes.
    if (similarity > 0.9) {
      final hasOnlyStyle = changes.every((c) => c.type == 'style');
      if (hasOnlyStyle) return EditType.styleChange;

      final hasOnlyNaming = changes.every(
        (c) => c.type == 'variable_rename' || c.type == 'function_rename',
      );
      if (hasOnlyNaming) return EditType.namingChange;
    }

    // Medium similarity — could be logic fix or refactoring.
    if (similarity > 0.5) {
      // Check for logic changes.
      final hasLogicChanges = changes.any((c) => c.type == 'logic');
      if (hasLogicChanges) {
        // Check if it's a bug fix (small targeted change).
        if (similarity > 0.7 && changes.length <= 3) {
          return EditType.bugFix;
        }
        return EditType.logicFix;
      }

      // Check for structural changes (refactoring).
      final hasStructuralChanges = _hasStructuralChanges(original, modified);
      if (hasStructuralChanges) return EditType.refactoring;
    }

    // Low similarity — could be feature addition or major rewrite.
    if (similarity > 0.3) {
      final addedLines = _countAddedLines(original, modified);
      if (addedLines > 5) return EditType.featureAdd;
    }

    // If significant logic changed but structure is similar.
    final hasLogicChanges = changes.any((c) => c.type == 'logic');
    if (hasLogicChanges) return EditType.logicFix;

    // If code got shorter — likely refactoring or cleanup.
    if (modified.length < original.length * 0.8) {
      return EditType.refactoring;
    }

    return EditType.logicFix;
  }

  // ── Private: Levenshtein Distance ──────────────────────────────────

  /// Calculate the Levenshtein edit distance between two strings.
  ///
  /// This is the minimum number of single-character insertions,
  /// deletions, or substitutions required to transform one string
  /// into the other.
  static int _levenshteinDistance(String s, String t) {
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    // Use two rows for space efficiency (O(min(m,n)) space).
    final m = s.length;
    final n = t.length;

    // Ensure s is the shorter string for space optimization.
    if (m < n) {
      return _levenshteinDistance(t, s);
    }

    var previous = List<int>.filled(n + 1, 0);
    var current = List<int>.filled(n + 1, 0);

    // Initialize the first row.
    for (var j = 0; j <= n; j++) {
      previous[j] = j;
    }

    // Fill the matrix row by row.
    for (var i = 1; i <= m; i++) {
      current[0] = i;

      for (var j = 1; j <= n; j++) {
        final cost = s[i - 1] == t[j - 1] ? 0 : 1;

        current[j] = math.min(
          math.min(
            previous[j] + 1,      // Deletion.
            current[j - 1] + 1,    // Insertion.
          ),
          previous[j - 1] + cost,  // Substitution.
        );
      }

      // Swap rows.
      final temp = previous;
      previous = current;
      current = temp;
    }

    return previous[n];
  }

  // ── Private: Token Similarity ──────────────────────────────────────

  /// Calculate token-based similarity between two code strings.
  ///
  /// Tokenizes each string and computes Jaccard similarity
  /// on the token sets.
  static double _tokenSimilarity(String original, String modified) {
    final originalTokens = _tokenize(original);
    final modifiedTokens = _tokenize(modified);

    if (originalTokens.isEmpty && modifiedTokens.isEmpty) return 1.0;
    if (originalTokens.isEmpty || modifiedTokens.isEmpty) return 0.0;

    final originalSet = originalTokens.toSet();
    final modifiedSet = modifiedTokens.toSet();

    final intersection = originalSet.intersection(modifiedSet);
    final union = originalSet.union(modifiedSet);

    return intersection.length / union.length;
  }

  // ── Private: Tokenization ──────────────────────────────────────────

  /// Tokenize a code string into meaningful tokens.
  ///
  /// Splits on whitespace and punctuation while preserving
  /// identifiers and keywords as atomic units.
  static List<String> _tokenize(String code) {
    // Split on non-alphanumeric characters while keeping identifiers intact.
    final tokens = <String>[];
    final regex = RegExp(r'[a-zA-Z_][a-zA-Z0-9_]*|[0-9]+|[{}()\[\];,.+\-*/=<>!&|^~?]');

    for (final match in regex.allMatches(code)) {
      final token = match.group(0);
      if (token != null && token.isNotEmpty) {
        tokens.add(token);
      }
    }

    return tokens;
  }

  // ── Private: Whitespace Normalization ──────────────────────────────

  /// Normalize whitespace for fair comparison.
  ///
  /// Collapses multiple whitespace characters to a single space
  /// and trims leading/trailing whitespace.
  static String _normalizeWhitespace(String code) {
    return code
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(' ;', ';')
        .replaceAll(' ,', ',');
  }

  // ── Private: Variable Rename Detection ─────────────────────────────

  /// Detect variable renames between two code versions.
  ///
  /// Compares variable declarations and assignments to find
  /// cases where the same logic uses different variable names.
  static List<CodeChange> _detectVariableRenames(String original, String modified) {
    final changes = <CodeChange>[];

    // Extract likely variable names from both versions.
    final originalVars = _extractVariableNames(original);
    final modifiedVars = _extractVariableNames(modified);

    // Find variables that exist in one version but not the other.
    final removedVars = originalVars.difference(modifiedVars);
    final addedVars = modifiedVars.difference(originalVars);

    // Heuristic: if similar count of variables were removed and added,
    // they might be renames of each other.
    if (removedVars.length == addedVars.length && removedVars.isNotEmpty) {
      final removedList = removedVars.toList();
      final addedList = addedVars.toList();

      for (var i = 0; i < removedList.length && i < addedList.length; i++) {
        changes.add(CodeChange(
          type: 'variable_rename',
          original: removedList[i],
          modified: addedList[i],
          description: 'Variable renamed: ${removedList[i]} → ${addedList[i]}',
        ));
      }
    }

    return changes;
  }

  // ── Private: Function Rename Detection ─────────────────────────────

  /// Detect function/method renames between two code versions.
  static List<CodeChange> _detectFunctionRenames(String original, String modified) {
    final changes = <CodeChange>[];

    final originalFuncs = _extractFunctionNames(original);
    final modifiedFuncs = _extractFunctionNames(modified);

    final removedFuncs = originalFuncs.difference(modifiedFuncs);
    final addedFuncs = modifiedFuncs.difference(originalFuncs);

    if (removedFuncs.length == addedFuncs.length && removedFuncs.isNotEmpty) {
      final removedList = removedFuncs.toList();
      final addedList = addedFuncs.toList();

      for (var i = 0; i < removedList.length && i < addedList.length; i++) {
        changes.add(CodeChange(
          type: 'function_rename',
          original: removedList[i],
          modified: addedList[i],
          description: 'Function renamed: ${removedList[i]}() → ${addedList[i]}()',
        ));
      }
    }

    return changes;
  }

  // ── Private: Logic Change Detection ────────────────────────────────

  /// Detect logic changes between two code versions.
  ///
  /// Looks for changes in control flow keywords, operators,
  /// literals, and function calls.
  static List<CodeChange> _detectLogicChanges(String original, String modified) {
    final changes = <CodeChange>[];

    // Check for control flow changes.
    final controlFlowKeywords = [
      'if', 'else', 'for', 'while', 'switch', 'case',
      'try', 'catch', 'finally', 'return', 'break', 'continue',
    ];

    for (final keyword in controlFlowKeywords) {
      final inOriginal = original.contains(RegExp(r'\b' + keyword + r'\b'));
      final inModified = modified.contains(RegExp(r'\b' + keyword + r'\b'));

      if (inOriginal != inModified) {
        changes.add(CodeChange(
          type: 'logic',
          original: inOriginal ? keyword : '<missing>',
          modified: inModified ? keyword : '<removed>',
          description: inModified
              ? 'Added $keyword statement'
              : 'Removed $keyword statement',
        ));
      }
    }

    // Check for operator changes.
    final operators = ['==', '!=', '<=', '>=', '&&', '||', '??', '?', '??='];
    for (final op in operators) {
      final originalCount = op.allMatches(original).length;
      final modifiedCount = op.allMatches(modified).length;

      if (originalCount != modifiedCount) {
        changes.add(CodeChange(
          type: 'logic',
          original: '$originalCount × $op',
          modified: '$modifiedCount × $op',
          description: 'Operator "$op" changed: $originalCount → $modifiedCount',
        ));
      }
    }

    return changes;
  }

  // ── Private: Style Change Detection ────────────────────────────────

  /// Detect formatting/style changes between two code versions.
  static List<CodeChange> _detectStyleChanges(String original, String modified) {
    final changes = <CodeChange>[];

    // Check indentation style.
    final originalIndent2 = original.split('\n').where((l) => l.startsWith('  ')).length;
    final originalIndent4 = original.split('\n').where((l) => l.startsWith('    ')).length;
    final modifiedIndent2 = modified.split('\n').where((l) => l.startsWith('  ')).length;
    final modifiedIndent4 = modified.split('\n').where((l) => l.startsWith('    ')).length;

    if ((originalIndent4 > originalIndent2) && (modifiedIndent2 > modifiedIndent4)) {
      changes.add(const CodeChange(
        type: 'style',
        original: '4-space indent',
        modified: '2-space indent',
        description: 'Indentation changed from 4 spaces to 2 spaces',
      ));
    } else if ((originalIndent2 > originalIndent4) && (modifiedIndent4 > modifiedIndent2)) {
      changes.add(const CodeChange(
        type: 'style',
        original: '2-space indent',
        modified: '4-space indent',
        description: 'Indentation changed from 2 spaces to 4 spaces',
      ));
    }

    // Check trailing comma usage.
    final originalTrailing = original.split(',\n').length - 1;
    final modifiedTrailing = modified.split(',\n').length - 1;
    if ((originalTrailing > 0) != (modifiedTrailing > 0)) {
      changes.add(CodeChange(
        type: 'style',
        original: originalTrailing > 0 ? 'trailing commas' : 'no trailing commas',
        modified: modifiedTrailing > 0 ? 'trailing commas' : 'no trailing commas',
        description: 'Trailing comma style changed',
      ));
    }

    return changes;
  }

  // ── Private: Comment Change Detection ──────────────────────────────

  /// Detect comment additions, removals, or modifications.
  static List<CodeChange> _detectCommentChanges(String original, String modified) {
    final changes = <CodeChange>[];

    final originalComments = _extractComments(original);
    final modifiedComments = _extractComments(modified);

    final removedComments = originalComments.difference(modifiedComments);
    final addedComments = modifiedComments.difference(originalComments);

    for (final comment in removedComments) {
      changes.add(CodeChange(
        type: 'comment',
        original: comment,
        modified: '<removed>',
        description: 'Comment removed: $comment',
      ));
    }

    for (final comment in addedComments) {
      changes.add(CodeChange(
        type: 'comment',
        original: '<missing>',
        modified: comment,
        description: 'Comment added: $comment',
      ));
    }

    return changes;
  }

  // ── Private: Import Change Detection ───────────────────────────────

  /// Detect import statement changes.
  static List<CodeChange> _detectImportChanges(String original, String modified) {
    final changes = <CodeChange>[];

    final originalImports = _extractImports(original);
    final modifiedImports = _extractImports(modified);

    final removedImports = originalImports.difference(modifiedImports);
    final addedImports = modifiedImports.difference(originalImports);

    for (final imp in removedImports) {
      changes.add(CodeChange(
        type: 'import',
        original: imp,
        modified: '<removed>',
        description: 'Import removed: $imp',
      ));
    }

    for (final imp in addedImports) {
      changes.add(CodeChange(
        type: 'import',
        original: '<missing>',
        modified: imp,
        description: 'Import added: $imp',
      ));
    }

    return changes;
  }

  // ── Private: Extraction Helpers ────────────────────────────────────

  /// Extract variable names from code (simplified heuristic).
  static Set<String> _extractVariableNames(String code) {
    final names = <String>{};

    // Match variable declarations (var/final/const/Type name = ...).
    final patterns = [
      RegExp(r'\b(?:var|final|const)\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*='),
      RegExp(r'\b(?:String|int|double|bool|List|Map|Set)\??\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*[;=)]'),
    ];

    for (final pattern in patterns) {
      for (final match in pattern.allMatches(code)) {
        final name = match.group(1);
        if (name != null && !_isKeyword(name)) {
          names.add(name);
        }
      }
    }

    return names;
  }

  /// Extract function/method names from code.
  static Set<String> _extractFunctionNames(String code) {
    final names = <String>{};

    // Match function declarations.
    final pattern = RegExp(r'\b(?:void|[A-Za-z_][A-Za-z0-9_<>?]*)\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(');

    for (final match in pattern.allMatches(code)) {
      final name = match.group(1);
      if (name != null && !_isKeyword(name)) {
        names.add(name);
      }
    }

    return names;
  }

  /// Extract comments from code.
  static Set<String> _extractComments(String code) {
    final comments = <String>{};

    // Line comments.
    final linePattern = RegExp(r'//(.+)$', multiLine: true);
    for (final match in linePattern.allMatches(code)) {
      final comment = match.group(1)?.trim();
      if (comment != null && comment.isNotEmpty) {
        comments.add(comment);
      }
    }

    // Block comments.
    final blockPattern = RegExp(r'/\*([\s\S]*?)\*/');
    for (final match in blockPattern.allMatches(code)) {
      final comment = match.group(1)?.trim();
      if (comment != null && comment.isNotEmpty) {
        comments.add(comment);
      }
    }

    return comments;
  }

  /// Extract import statements from code.
  static Set<String> _extractImports(String code) {
    final imports = <String>{};

    final pattern = RegExp(r"import\s+['\"]([^'\"]+)['\"]");
    for (final match in pattern.allMatches(code)) {
      final imp = match.group(1);
      if (imp != null) imports.add(imp);
    }

    return imports;
  }

  /// Check if a string is a programming language keyword.
  static bool _isKeyword(String word) {
    final keywords = {
      'var', 'final', 'const', 'void', 'return', 'if', 'else', 'for',
      'while', 'do', 'switch', 'case', 'break', 'continue', 'default',
      'class', 'extends', 'implements', 'mixin', 'with', 'on', 'as',
      'is', 'new', 'this', 'super', 'abstract', 'static', 'get', 'set',
      'try', 'catch', 'finally', 'throw', 'async', 'await', 'yield',
      'import', 'export', 'part', 'library', 'typedef', 'enum',
      'true', 'false', 'null', 'required', 'factory',
    };
    return keywords.contains(word);
  }

  /// Check if there are structural changes (class structure, function signatures).
  static bool _hasStructuralChanges(String original, String modified) {
    // Compare class counts.
    final originalClasses = RegExp(r'\bclass\b').allMatches(original).length;
    final modifiedClasses = RegExp(r'\bclass\b').allMatches(modified).length;

    // Compare function counts.
    final originalFunctions = _extractFunctionNames(original).length;
    final modifiedFunctions = _extractFunctionNames(modified).length;

    return originalClasses != modifiedClasses ||
        originalFunctions != modifiedFunctions;
  }

  /// Count lines added in the modified version.
  static int _countAddedLines(String original, String modified) {
    final originalLines = original.split('\n').length;
    final modifiedLines = modified.split('\n').length;
    return math.max(0, modifiedLines - originalLines);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Edit Type Classification
// ═══════════════════════════════════════════════════════════════════════════

/// Classification of the type of edit made to code.
///
/// Used to categorize what the user changed and why,
/// which helps the learning system understand patterns.
enum EditType {
  /// Only variable or function names changed.
  namingChange,

  /// Only formatting, whitespace, or style changed.
  styleChange,

  /// Code logic was corrected or improved.
  logicFix,

  /// A specific bug was fixed.
  bugFix,

  /// New functionality was added.
  featureAdd,

  /// Code was reorganized without changing behavior.
  refactoring,

  /// No meaningful changes detected.
  none,
}

// ═══════════════════════════════════════════════════════════════════════════
// Code Change
// ═══════════════════════════════════════════════════════════════════════════

/// A single detected change between two code versions.
///
/// Represents one atomic change with its type, original value,
/// modified value, and a human-readable description.
class CodeChange {
  /// Category of change (e.g., 'variable_rename', 'logic', 'style').
  final String type;

  /// The original value before the change.
  final String original;

  /// The modified value after the change.
  final String modified;

  /// Human-readable description of the change.
  final String description;

  const CodeChange({
    required this.type,
    required this.original,
    required this.modified,
    required this.description,
  });

  @override
  String toString() => '[$type] $description';

  /// Convert to JSON.
  Map<String, dynamic> toJson() => {
        'type': type,
        'original': original,
        'modified': modified,
        'description': description,
      };
}
