import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// {@template file_item}
/// Represents a file or folder within a project.
///
/// [FileItem] uses a recursive structure to represent the entire
/// file tree. Directories contain a [children] list, while files
/// have optional [content] for the file's text data.
///
/// ## Usage
/// ```dart
/// // Create a file
/// final file = FileItem.createFile(
///   name: 'main.dart',
///   path: 'lib/main.dart',
///   content: 'void main() {}',
/// );
///
/// // Create a directory
/// final folder = FileItem.createDirectory(
///   name: 'lib',
///   path: 'lib',
///   children: [file],
/// );
/// ```
/// {@endtemplate}
@immutable
class FileItem {
  /// Unique identifier for the file/folder
  final String id;

  /// Display name (e.g., 'main.dart', 'lib')
  final String name;

  /// Full path within the project (e.g., 'lib/main.dart')
  final String path;

  /// Whether this is a directory (true) or file (false)
  final bool isDirectory;

  /// File content (null for directories)
  final String? content;

  /// Child items for directories (null for files)
  final List<FileItem>? children;

  /// Last modification timestamp
  final DateTime modifiedAt;

  /// Creates a [FileItem] with all fields specified.
  const FileItem({
    required this.id,
    required this.name,
    required this.path,
    required this.isDirectory,
    this.content,
    this.children,
    required this.modifiedAt,
  });

  /// Factory for creating a new file with auto-generated values.
  factory FileItem.createFile({
    required String name,
    required String path,
    String? content,
  }) {
    return FileItem(
      id: const Uuid().v4(),
      name: name,
      path: path,
      isDirectory: false,
      content: content,
      children: null,
      modifiedAt: DateTime.now(),
    );
  }

  /// Factory for creating a new directory with auto-generated values.
  factory FileItem.createDirectory({
    required String name,
    required String path,
    List<FileItem>? children,
  }) {
    return FileItem(
      id: const Uuid().v4(),
      name: name,
      path: path,
      isDirectory: true,
      content: null,
      children: children ?? [],
      modifiedAt: DateTime.now(),
    );
  }

  /// Creates a [FileItem] from a JSON map.
  factory FileItem.fromJson(Map<String, dynamic> json) {
    return FileItem(
      id: json['id'] as String,
      name: json['name'] as String,
      path: json['path'] as String,
      isDirectory: json['isDirectory'] as bool,
      content: json['content'] as String?,
      children: json['children'] != null
          ? (json['children'] as List<dynamic>)
              .map((e) => FileItem.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
    );
  }

  /// Converts this file item to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'isDirectory': isDirectory,
      if (content != null) 'content': content,
      if (children != null)
        'children': children!.map((c) => c.toJson()).toList(),
      'modifiedAt': modifiedAt.toIso8601String(),
    };
  }

  /// Creates a copy with specified fields replaced.
  FileItem copyWith({
    String? id,
    String? name,
    String? path,
    bool? isDirectory,
    String? content,
    List<FileItem>? children,
    DateTime? modifiedAt,
  }) {
    return FileItem(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      isDirectory: isDirectory ?? this.isDirectory,
      content: content ?? this.content,
      children: children ?? this.children,
      modifiedAt: modifiedAt ?? this.modifiedAt,
    );
  }

  /// Returns a copy with updated content and timestamp.
  FileItem updateContent(String newContent) {
    if (isDirectory) {
      throw StateError('Cannot update content of a directory: $name');
    }
    return copyWith(
      content: newContent,
      modifiedAt: DateTime.now(),
    );
  }

  /// Returns a copy with a child added (directories only).
  FileItem addChild(FileItem child) {
    if (!isDirectory) {
      throw StateError('Cannot add child to a file: $name');
    }
    return copyWith(
      children: [...children ?? [], child],
      modifiedAt: DateTime.now(),
    );
  }

  /// Returns a copy with a child removed by ID (directories only).
  FileItem removeChild(String childId) {
    if (!isDirectory) {
      throw StateError('Cannot remove child from a file: $name');
    }
    return copyWith(
      children: children?.where((c) => c.id != childId).toList() ?? [],
      modifiedAt: DateTime.now(),
    );
  }

  /// File extension derived from name (e.g., 'main.dart' -> 'dart').
  /// Returns null for files without extension or directories.
  String? get extension {
    if (isDirectory) return null;
    final dotIndex = name.lastIndexOf('.');
    return dotIndex > 0 ? name.substring(dotIndex + 1) : null;
  }

  /// File name without extension (e.g., 'main.dart' -> 'main').
  String get basename {
    final dotIndex = name.lastIndexOf('.');
    return dotIndex > 0 ? name.substring(0, dotIndex) : name;
  }

  /// Approximate size in characters (content length for files, 0 for directories).
  int get size => content?.length ?? 0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FileItem &&
        other.id == id &&
        other.name == name &&
        other.path == path &&
        other.isDirectory == isDirectory &&
        other.content == content &&
        other.modifiedAt == modifiedAt &&
        (other.children == null && children == null ||
            other.children != null &&
                children != null &&
                listEquals(other.children, children));
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        path,
        isDirectory,
        content,
        modifiedAt,
        children == null ? null : Object.hashAll(children!),
      );

  @override
  String toString() {
    if (isDirectory) {
      return 'FileItem.dir(id: $id, name: $name, path: $path, '
          'children: ${children?.length ?? 0})';
    }
    return 'FileItem.file(id: $id, name: $name, path: $path, '
        'size: $size chars)';
  }
}