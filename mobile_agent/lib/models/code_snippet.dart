// lib/models/code_snippet.dart

import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

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

/// Manual Hive adapter for [CodeSnippet].
///
/// This keeps the legacy snippet model analyzable without requiring the old
/// generated `code_snippet.g.dart` artifact to be present in source control.
class CodeSnippetAdapter extends TypeAdapter<CodeSnippet> {
  @override
  final int typeId = 5;

  @override
  CodeSnippet read(BinaryReader reader) {
    final numberOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numberOfFields; i++) reader.readByte(): reader.read(),
    };

    return CodeSnippet(
      id: fields[0] as String,
      title: fields[1] as String,
      code: fields[2] as String,
      language: fields[3] as String,
      tags: (fields[4] as List?)?.cast<String>() ?? const <String>[],
      createdAt: fields[5] as String,
      updatedAt: fields[6] as String,
      description: fields[7] as String?,
      isFavorite: fields[8] as bool? ?? false,
      usageCount: fields[9] as int? ?? 0,
      source: fields[10] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, CodeSnippet obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.code)
      ..writeByte(3)
      ..write(obj.language)
      ..writeByte(4)
      ..write(obj.tags)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.updatedAt)
      ..writeByte(7)
      ..write(obj.description)
      ..writeByte(8)
      ..write(obj.isFavorite)
      ..writeByte(9)
      ..write(obj.usageCount)
      ..writeByte(10)
      ..write(obj.source);
  }
}
