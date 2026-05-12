import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'file_item.dart';

/// {@template project}
/// Represents a code project in Mobile Agent.
///
/// A project is a collection of files and folders with metadata
/// for organization and quick access. Projects can be favorited,
/// filtered by language, and synced with GitHub repositories.
///
/// ## Usage
/// ```dart
/// final project = Project.create(
///   name: 'My Flutter App',
///   description: 'A cool mobile app',
///   language: 'dart',
/// );
/// ```
/// {@endtemplate}
@immutable
class Project {
  /// Unique identifier for the project
  final String id;

  /// Display name of the project
  final String name;

  /// Optional description of the project
  final String description;

  /// Primary programming language (e.g., 'dart', 'python')
  final String language;

  /// When the project was created
  final DateTime createdAt;

  /// When the project was last modified
  final DateTime updatedAt;

  /// List of files and folders in the project
  final List<FileItem> files;

  /// Whether the project is marked as favorite
  final bool isFavorite;

  /// Creates a [Project] with all fields specified.
  ///
  /// Use [Project.create] for creating new projects with auto-generated
  /// timestamps and UUID.
  const Project({
    required this.id,
    required this.name,
    required this.description,
    required this.language,
    required this.createdAt,
    required this.updatedAt,
    required this.files,
    required this.isFavorite,
  });

  /// Factory for creating a new project with auto-generated values.
  ///
  /// [name] and [language] are required. [description] defaults to empty string.
  factory Project.create({
    required String name,
    required String language,
    String description = '',
    List<FileItem>? files,
  }) {
    final now = DateTime.now();
    return Project(
      id: const Uuid().v4(),
      name: name,
      description: description,
      language: language,
      createdAt: now,
      updatedAt: now,
      files: files ?? [],
      isFavorite: false,
    );
  }

  /// Creates a [Project] from a JSON map.
  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      language: json['language'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      files: (json['files'] as List<dynamic>?)
              ?.map((e) => FileItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      isFavorite: json['isFavorite'] as bool? ?? false,
    );
  }

  /// Converts this project to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'language': language,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'files': files.map((f) => f.toJson()).toList(),
      'isFavorite': isFavorite,
    };
  }

  /// Creates a copy of this project with specified fields replaced.
  Project copyWith({
    String? id,
    String? name,
    String? description,
    String? language,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<FileItem>? files,
    bool? isFavorite,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      language: language ?? this.language,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      files: files ?? this.files,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  /// Returns a copy with updated timestamp.
  Project touch() => copyWith(updatedAt: DateTime.now());

  /// Adds a file to the project and returns updated project.
  Project addFile(FileItem file) {
    return copyWith(
      files: [...files, file],
      updatedAt: DateTime.now(),
    );
  }

  /// Removes a file by ID and returns updated project.
  Project removeFile(String fileId) {
    return copyWith(
      files: files.where((f) => f.id != fileId).toList(),
      updatedAt: DateTime.now(),
    );
  }

  /// Toggles favorite status.
  Project toggleFavorite() => copyWith(isFavorite: !isFavorite);

  /// Count of all files (non-directories) recursively.
  int get fileCount {
    int count = 0;
    for (final file in files) {
      if (file.isDirectory && file.children != null) {
        count += _countFiles(file.children!);
      } else if (!file.isDirectory) {
        count++;
      }
    }
    return count;
  }

  int _countFiles(List<FileItem> items) {
    int count = 0;
    for (final item in items) {
      if (item.isDirectory && item.children != null) {
        count += _countFiles(item.children!);
      } else if (!item.isDirectory) {
        count++;
      }
    }
    return count;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Project &&
        other.id == id &&
        other.name == name &&
        other.description == description &&
        other.language == language &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        listEquals(other.files, files) &&
        other.isFavorite == isFavorite;
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        description,
        language,
        createdAt,
        updatedAt,
        Object.hashAll(files),
        isFavorite,
      );

  @override
  String toString() {
    return 'Project(id: $id, name: $name, language: $language, '
        'files: ${files.length}, isFavorite: $isFavorite)';
  }
}