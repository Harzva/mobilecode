// lib/models/code_snippet.dart

import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'code_snippet.g.dart';

/// A reusable code snippet stored locally by the user.
///
/// Snippets can be tagged, searched, and quickly inserted into
/// the editor during coding sessions.
@HiveType(typeId: 5)
class CodeSnippet extends HiveObject {
  /// Unique snippet identifier (UUID v4).
  @HiveField(0)
  final String id;

  /// Display title for the snippet.
  @HiveField(1)
  String title;

  /// The code content.
  @HiveField(2)
  String code;

  /// Programming language.
  @HiveField(3)
  String language;

  /// User-defined tags for categorization.
  @HiveField(4)
  List<String> tags;

  /// ISO 8601 creation timestamp.
  @HiveField(5)
  final String createdAt;

  /// ISO 8601 last-modified timestamp.
  @HiveField(6)
  String updatedAt;

  /// Optional description / usage notes.
  @HiveField(7)
  String? description;

  /// Whether this snippet is favorited.
  @HiveField(8)
  bool isFavorite;

  /// Usage count (for sorting by frequency).
  @HiveField(9)
  int usageCount;

  /// Source URL or reference (if copied from somewhere).
  @HiveField(10)
  String? source;

  CodeSnippet({
    required this.id,
    required this.title,
    required this.code,
    required this.language,
    required this.createdAt,
    required this.updatedAt,
    this.tags = const [],
    this.description,
    this.isFavorite = false,
    this.usageCount = 0,
    this.source,
  });

  /// Factory to create a new snippet with auto-generated ID and timestamps.
  factory CodeSnippet.create({
    required String title,
    required String code,
    required String language,
    List<String> tags = const [],
    String? description,
    String? source,
  }) {
    final now = DateTime.now().toIso8601String();
    return CodeSnippet(
      id: const Uuid().v4(),
      title: title,
      code: code,
      language: language,
      tags: tags,
      description: description,
      source: source,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Update modification timestamp.
  void touch() {
    updatedAt = DateTime.now().toIso8601String();
  }

  /// Increment usage counter.
  void recordUsage() {
    usageCount++;
    touch();
  }

  /// Create a copy with modified fields.
  CodeSnippet copyWith({
    String? title,
    String? code,
    String? language,
    List<String>? tags,
    String? description,
    bool? isFavorite,
    String? source,
  }) {
    return CodeSnippet(
      id: id,
      title: title ?? this.title,
      code: code ?? this.code,
      language: language ?? this.language,
      tags: tags ?? this.tags,
      description: description ?? this.description,
      isFavorite: isFavorite ?? this.isFavorite,
      source: source ?? this.source,
      createdAt: createdAt,
      updatedAt: DateTime.now().toIso8601String(),
      usageCount: usageCount,
    );
  }

  @override
  String toString() =>
      'CodeSnippet(id: $id, title: $title, language: $language, tags: $tags)';
}
