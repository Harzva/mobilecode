import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// {@template snippet_source}
/// The origin method used to capture a code snippet.
///
/// - [voice]: Recorded via voice-to-text
/// - [text]: Typed or pasted manually
/// - [screenshot]: Extracted from a screenshot via OCR
/// {@endtemplate}
enum SnippetSource {
  voice,
  text,
  screenshot;

  /// Converts a string to [SnippetSource], defaulting to [text].
  static SnippetSource fromString(String value) {
    return SnippetSource.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SnippetSource.text,
    );
  }
}

/// {@template code_snippet}
/// Represents a reusable code snippet or inspiration capture.
///
/// Snippets are quick-access pieces of code that can be tagged,
/// searched, and inserted into the editor. They support multiple
/// capture sources including voice, text, and screenshots.
///
/// ## Usage
/// ```dart
/// final snippet = CodeSnippet.create(
///   title: 'Riverpod Provider',
///   content: 'final provider = Provider((ref) => ...);',
///   language: 'dart',
///   tags: ['state-management', 'riverpod'],
/// );
/// ```
/// {@endtemplate}
@immutable
class CodeSnippet {
  /// Unique identifier for the snippet
  final String id;

  /// Human-readable title
  final String title;

  /// The code content or note text
  final String content;

  /// Programming language for syntax highlighting (nullable)
  final String? language;

  /// Searchable tags for organization
  final List<String> tags;

  /// When the snippet was created
  final DateTime createdAt;

  /// How the snippet was captured
  final SnippetSource source;

  /// Creates a [CodeSnippet] with all fields specified.
  const CodeSnippet({
    required this.id,
    required this.title,
    required this.content,
    this.language,
    required this.tags,
    required this.createdAt,
    required this.source,
  });

  /// Factory for creating a new snippet with auto-generated values.
  ///
  /// [title] and [content] are required. All other fields have defaults.
  factory CodeSnippet.create({
    required String title,
    required String content,
    String? language,
    List<String>? tags,
    SnippetSource source = SnippetSource.text,
  }) {
    return CodeSnippet(
      id: const Uuid().v4(),
      title: title,
      content: content,
      language: language,
      tags: tags ?? [],
      createdAt: DateTime.now(),
      source: source,
    );
  }

  /// Creates a [CodeSnippet] from a JSON map.
  factory CodeSnippet.fromJson(Map<String, dynamic> json) {
    return CodeSnippet(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      language: json['language'] as String?,
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      createdAt: DateTime.parse(json['createdAt'] as String),
      source: SnippetSource.fromString(json['source'] as String? ?? 'text'),
    );
  }

  /// Converts this snippet to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      if (language != null) 'language': language,
      'tags': tags,
      'createdAt': createdAt.toIso8601String(),
      'source': source.name,
    };
  }

  /// Creates a copy with specified fields replaced.
  CodeSnippet copyWith({
    String? id,
    String? title,
    String? content,
    String? language,
    List<String>? tags,
    DateTime? createdAt,
    SnippetSource? source,
  }) {
    return CodeSnippet(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      language: language ?? this.language,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      source: source ?? this.source,
    );
  }

  /// Adds a tag and returns updated snippet.
  CodeSnippet addTag(String tag) {
    if (tags.contains(tag)) return this;
    return copyWith(tags: [...tags, tag]);
  }

  /// Removes a tag and returns updated snippet.
  CodeSnippet removeTag(String tag) {
    return copyWith(tags: tags.where((t) => t != tag).toList());
  }

  /// Approximate word count of the content.
  int get wordCount {
    return content.trim().split(RegExp(r'\s+')).length;
  }

  /// Approximate line count of the content.
  int get lineCount {
    return content.split('\n').length;
  }

  /// Formatted source label for display.
  String get sourceLabel {
    switch (source) {
      case SnippetSource.voice:
        return 'Voice';
      case SnippetSource.text:
        return 'Text';
      case SnippetSource.screenshot:
        return 'Screenshot';
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CodeSnippet &&
        other.id == id &&
        other.title == title &&
        other.content == content &&
        other.language == language &&
        listEquals(other.tags, tags) &&
        other.createdAt == createdAt &&
        other.source == source;
  }

  @override
  int get hashCode => Object.hash(
        id,
        title,
        content,
        language,
        Object.hashAll(tags),
        createdAt,
        source,
      );

  @override
  String toString() {
    return 'CodeSnippet(id: $id, title: $title, '
        'language: $language, source: ${source.name})';
  }
}