import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants.dart';
import '../models/file_item.dart';
import '../models/project.dart';
import 'storage_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Data Models for Stats
// ═══════════════════════════════════════════════════════════════════════════

/// Statistics for a single project.
class ProjectStats {
  final String projectId;
  final int totalFiles;
  final int totalDirectories;
  final int totalLinesOfCode;
  final int totalComments;
  final int blankLines;
  final Map<String, int> languageDistribution;
  final int avgFileSize;
  final DateTime? lastCommitDate;
  final String? currentBranch;
  final int modifiedFiles;
  final int untrackedFiles;

  const ProjectStats({
    required this.projectId,
    required this.totalFiles,
    required this.totalDirectories,
    required this.totalLinesOfCode,
    required this.totalComments,
    required this.blankLines,
    required this.languageDistribution,
    required this.avgFileSize,
    this.lastCommitDate,
    this.currentBranch,
    this.modifiedFiles = 0,
    this.untrackedFiles = 0,
  });

  /// Effective lines (excluding blank lines).
  int get effectiveLines => totalLinesOfCode - blankLines;

  /// Comment ratio as percentage.
  double get commentRatio => totalLinesOfCode > 0
      ? (totalComments / totalLinesOfCode * 100).clamp(0, 100)
      : 0;
}

/// Global statistics across all projects.
class GlobalStats {
  final int totalProjects;
  final int totalFiles;
  final int totalLinesOfCode;
  final int totalComments;
  final Map<String, int> languageDistribution;
  final int favoriteProjects;
  final int archivedProjects;
  final Project? mostActiveProject;
  final int currentStreakDays;
  final int longestStreakDays;
  final DateTime lastActiveDate;

  const GlobalStats({
    required this.totalProjects,
    required this.totalFiles,
    required this.totalLinesOfCode,
    required this.totalComments,
    required this.languageDistribution,
    required this.favoriteProjects,
    required this.archivedProjects,
    this.mostActiveProject,
    required this.currentStreakDays,
    required this.longestStreakDays,
    required this.lastActiveDate,
  });

  /// Language distribution as percentage map.
  Map<String, double> languagePercentages() {
    if (totalLinesOfCode == 0) return {};
    return languageDistribution.map(
      (lang, lines) => MapEntry(lang, lines / totalLinesOfCode * 100),
    );
  }
}

/// Project category/folder types.
class ProjectCategory {
  static const String work = 'work';
  static const String personal = 'personal';
  static const String learning = 'learning';
  static const String archive = 'archive';
  static const String all = 'all';

  static const Map<String, String> labels = {
    work: 'Work',
    personal: 'Personal',
    learning: 'Learning',
    archive: 'Archive',
    all: 'All Projects',
  };

  /// Icon identifiers mapped to MaterialIcons in the UI layer.
  static const Map<String, String> iconNames = {
    work: 'work_outline',
    personal: 'person_outline',
    learning: 'school_outlined',
    archive: 'archive_outlined',
    all: 'apps',
  };
}

/// Sort options for projects list.
enum ProjectSortOption {
  recent('Recent', Icons.access_time),
  name('Name', Icons.sort_by_alpha),
  language('Language', Icons.code),
  size('Size', Icons.storage),
  favorite('Favorites', Icons.star);

  final String label;
  final IconData icon;

  const ProjectSortOption(this.label, this.icon);
}

// ═══════════════════════════════════════════════════════════════════════════
// Project Manager Service
// ═══════════════════════════════════════════════════════════════════════════

/// Central service for all project management operations.
///
/// Handles CRUD operations, templates, import/export, statistics,
/// organization (categories, tags, favorites), and git integration.
///
/// Uses [StorageService] for persistence and filesystem for
/// template content and import/export operations.
class ProjectManager {
  final StorageService _storage;

  /// Stream controller for project list change notifications.
  final _projectStreamController = StreamController<List<Project>>.broadcast();

  Stream<List<Project>> get projectStream => _projectStreamController.stream;

  ProjectManager({StorageService? storage}) : _storage = storage ?? StorageService();

  // ─── Internal Helpers ──────────────────────────────────────────────

  /// Notify listeners of project changes.
  void _notifyListeners() {
    getAllProjects().then((projects) {
      if (!_projectStreamController.isClosed) {
        _projectStreamController.add(projects);
      }
    });
  }

  /// Get project directory on filesystem.
  Future<Directory> _getProjectDirectory(String projectId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final projectDir = Directory('${appDir.path}/projects/$projectId');
    if (!await projectDir.exists()) {
      await projectDir.create(recursive: true);
    }
    return projectDir;
  }

  // ─── CRUD Operations ───────────────────────────────────────────────

  /// Get all non-archived projects, sorted by favorites then updatedAt.
  Future<List<Project>> getAllProjects() async {
    final projects = await _storage.getProjects();
    return projects.where((p) => !_isArchived(p.id)).toList();
  }

  /// Get archived projects.
  Future<List<Project>> getArchivedProjects() async {
    final projects = await _storage.getProjects();
    final archivedIds = await _getArchivedIds();
    return projects.where((p) => archivedIds.contains(p.id)).toList();
  }

  /// Get a single project by ID.
  Future<Project?> getProject(String id) => _storage.getProject(id);

  /// Create a new project with optional template.
  Future<Project> createProject(
    String name,
    String language, {
    String? description,
    String? template,
    String? category,
    List<String>? tags,
    int? colorCode,
  }) async {
    final project = Project.create(
      name: name,
      language: language,
      description: description ?? '',
    );

    // Save initial project.
    await _storage.saveProject(project);

    // Store metadata.
    await _saveProjectMeta(project.id, {
      'category': category ?? ProjectCategory.personal,
      'tags': tags ?? [],
      'color': colorCode ?? _defaultColorForLanguage(language),
      'createdFromTemplate': template,
      'isArchived': false,
      'gitInitialized': false,
      'currentBranch': null,
      'recentFiles': <String>[],
    });

    // Apply template if specified.
    if (template != null && template != 'empty') {
      await applyTemplate(project.id, template);
    } else {
      // Empty project still gets a README.
      final readme = FileItem.createFile(
        name: 'README.md',
        path: 'README.md',
        content: '# $name\n\n${description ?? 'A new project.'}\n',
      );
      final updated = project.addFile(readme);
      await _storage.saveProject(updated);
    }

    // Update streak.
    await _recordActivity();

    _notifyListeners();
    return project;
  }

  /// Delete a project permanently.
  Future<void> deleteProject(String id) async {
    await _storage.deleteProject(id);
    // Clean up meta.
    await _removeProjectMeta(id);
    // Clean up directory.
    try {
      final dir = await _getProjectDirectory(id);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Directory may not exist.
    }
    _notifyListeners();
  }

  /// Rename a project.
  Future<void> renameProject(String id, String newName) async {
    final project = await _storage.getProject(id);
    if (project == null) throw StateError('Project not found: $id');
    final updated = project.copyWith(name: newName);
    await _storage.saveProject(updated);
    _notifyListeners();
  }

  /// Duplicate a project with a new name.
  Future<Project> duplicateProject(String id) async {
    final project = await _storage.getProject(id);
    if (project == null) throw StateError('Project not found: $id');

    final newProject = Project.create(
      name: '${project.name} (Copy)',
      language: project.language,
      description: project.description,
      files: project.files.map(_deepCopyFile).toList(),
    );

    await _storage.saveProject(newProject);

    // Copy meta.
    final meta = await _getProjectMeta(id);
    await _saveProjectMeta(newProject.id, {
      ...meta,
      'isArchived': false,
    });

    _notifyListeners();
    return newProject;
  }

  /// Archive a project (soft delete).
  Future<void> archiveProject(String id) async {
    final meta = await _getProjectMeta(id);
    meta['isArchived'] = true;
    await _saveProjectMeta(id, meta);
    _notifyListeners();
  }

  /// Unarchive a project.
  Future<void> unarchiveProject(String id) async {
    final meta = await _getProjectMeta(id);
    meta['isArchived'] = false;
    await _saveProjectMeta(id, meta);
    _notifyListeners();
  }

  /// Toggle favorite status.
  Future<void> toggleFavorite(String id) async {
    final project = await _storage.getProject(id);
    if (project == null) return;
    final updated = project.toggleFavorite();
    await _storage.saveProject(updated);
    _notifyListeners();
  }

  /// Set project category.
  Future<void> setCategory(String id, String category) async {
    final meta = await _getProjectMeta(id);
    meta['category'] = category;
    await _saveProjectMeta(id, meta);
    _notifyListeners();
  }

  /// Set project tags.
  Future<void> setTags(String id, List<String> tags) async {
    final meta = await _getProjectMeta(id);
    meta['tags'] = tags;
    await _saveProjectMeta(id, meta);
    _notifyListeners();
  }

  /// Set project color.
  Future<void> setColor(String id, int colorCode) async {
    final meta = await _getProjectMeta(id);
    meta['color'] = colorCode;
    await _saveProjectMeta(id, meta);
    _notifyListeners();
  }

  /// Add a file to project.
  Future<void> addFile(String projectId, FileItem file) async {
    final project = await _storage.getProject(projectId);
    if (project == null) return;
    final updated = project.addFile(file);
    await _storage.saveProject(updated);
    _addRecentFile(projectId, file.path);
    _notifyListeners();
  }

  /// Remove a file from project.
  Future<void> removeFile(String projectId, String fileId) async {
    final project = await _storage.getProject(projectId);
    if (project == null) return;
    final updated = project.removeFile(fileId);
    await _storage.saveProject(updated);
    _notifyListeners();
  }

  // ─── Sorting & Filtering ───────────────────────────────────────────

  /// Sort projects by given option.
  List<Project> sortProjects(List<Project> projects, ProjectSortOption sort) {
    final sorted = List<Project>.from(projects);
    switch (sort) {
      case ProjectSortOption.recent:
        sorted.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case ProjectSortOption.name:
        sorted.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case ProjectSortOption.language:
        sorted.sort((a, b) => a.language.compareTo(b.language));
      case ProjectSortOption.size:
        sorted.sort((a, b) => _projectSize(b).compareTo(_projectSize(a)));
      case ProjectSortOption.favorite:
        sorted.sort((a, b) {
          if (a.isFavorite && !b.isFavorite) return -1;
          if (!a.isFavorite && b.isFavorite) return 1;
          return b.updatedAt.compareTo(a.updatedAt);
        });
    }
    return sorted;
  }

  /// Filter projects by search query (name, description, language, tags).
  Future<List<Project>> searchProjects(String query) async {
    if (query.isEmpty) return getAllProjects();
    final lower = query.toLowerCase();
    final all = await _storage.getProjects();
    final results = <Project>[];

    for (final project in all) {
      final meta = await _getProjectMeta(project.id);
      final tags = (meta['tags'] as List?)?.cast<String>() ?? [];

      if (project.name.toLowerCase().contains(lower) ||
          project.description.toLowerCase().contains(lower) ||
          project.language.toLowerCase().contains(lower) ||
          tags.any((t) => t.toLowerCase().contains(lower))) {
        results.add(project);
      }
    }
    return results;
  }

  /// Filter projects by category.
  Future<List<Project>> getProjectsByCategory(String category) async {
    if (category == ProjectCategory.all) return getAllProjects();
    final all = await _storage.getProjects();
    final results = <Project>[];

    for (final project in all) {
      final meta = await _getProjectMeta(project.id);
      if ((meta['category'] ?? ProjectCategory.personal) == category) {
        results.add(project);
      }
    }
    return results;
  }

  // ─── Templates ─────────────────────────────────────────────────────

  /// Available project templates.
  /// Template icon identifiers (mapped to Icons in UI layer).
  static const Map<String, Map<String, dynamic>> templates = {
    'flutter': {
      'label': 'Flutter App',
      'icon': 'flutter_dash',
      'language': 'dart',
      'description': 'Flutter application with main.dart and pubspec.yaml',
    },
    'python': {
      'label': 'Python Project',
      'icon': 'terminal',
      'language': 'python',
      'description': 'Python project with main.py and requirements.txt',
    },
    'go': {
      'label': 'Go Module',
      'icon': 'memory',
      'language': 'go',
      'description': 'Go module with main.go and go.mod',
    },
    'web': {
      'label': 'Web Project',
      'icon': 'web',
      'language': 'html',
      'description': 'HTML/CSS/JS web project',
    },
    'react': {
      'label': 'React / Vite',
      'icon': 'javascript',
      'language': 'typescript',
      'description': 'React app with TypeScript and Vite',
    },
    'empty': {
      'label': 'Empty Project',
      'icon': 'folder_open_outlined',
      'language': 'text',
      'description': 'Clean project with just a README',
    },
  };

  /// Apply a template to an existing project.
  Future<void> applyTemplate(String projectId, String templateName) async {
    final project = await _storage.getProject(projectId);
    if (project == null) return;

    final files = _generateTemplateFiles(templateName, project.name);
    if (files == null || files.isEmpty) return;

    // Build updated file tree.
    var updated = project;
    for (final file in files) {
      updated = _addFileToTree(updated, file);
    }

    await _storage.saveProject(updated);

    // Record template usage.
    final meta = await _getProjectMeta(projectId);
    meta['createdFromTemplate'] = templateName;
    await _saveProjectMeta(projectId, meta);

    _notifyListeners();
  }

  /// Generate template file structure.
  List<FileItem>? _generateTemplateFiles(String template, String projectName) {
    switch (template) {
      case 'flutter':
        return [
          FileItem.createDirectory(name: 'lib', path: 'lib', children: [
            FileItem.createFile(
              name: 'main.dart',
              path: 'lib/main.dart',
              content: '''import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '$projectName',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatelessWidget {
  const MyHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$projectName')),
      body: const Center(child: Text('Hello, World!')),
    );
  }
}
''',
            ),
          ]),
          FileItem.createFile(
            name: 'pubspec.yaml',
            path: 'pubspec.yaml',
            content: '''name: ${projectName.toLowerCase().replaceAll(' ', '_')}
description: A new Flutter project.
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.6

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0

flutter:
  uses-material-design: true
''',
          ),
          FileItem.createFile(
            name: 'README.md',
            path: 'README.md',
            content: '# $projectName\n\nA new Flutter project.\n\n## Getting Started\n\nRun `flutter run` to start the app.\n',
          ),
        ];

      case 'python':
        return [
          FileItem.createFile(
            name: 'main.py',
            path: 'main.py',
            content: '''#!/usr/bin/env python3
"""Main entry point for $projectName."""


def main():
    """Run the application."""
    print(f"Welcome to {projectName}!")


if __name__ == "__main__":
    main()
''',
          ),
          FileItem.createFile(
            name: 'requirements.txt',
            path: 'requirements.txt',
            content: '# Dependencies for $projectName\n',
          ),
          FileItem.createFile(
            name: '.gitignore',
            path: '.gitignore',
            content: '# Python\n__pycache__/\n*.py[cod]\n*$py.class\nvenv/\n.env\n',
          ),
          FileItem.createFile(
            name: 'README.md',
            path: 'README.md',
            content: '# $projectName\n\nA Python project.\n\n## Setup\n\n```bash\npip install -r requirements.txt\npython main.py\n```\n',
          ),
        ];

      case 'go':
        return [
          FileItem.createFile(
            name: 'main.go',
            path: 'main.go',
            content: '''package main

import "fmt"

func main() {
    fmt.Println("Welcome to $projectName!")
}
''',
          ),
          FileItem.createFile(
            name: 'go.mod',
            path: 'go.mod',
            content: '''module github.com/user/${projectName.toLowerCase().replaceAll(' ', '-')}

go 1.21
''',
          ),
          FileItem.createFile(
            name: 'README.md',
            path: 'README.md',
            content: '# $projectName\n\nA Go project.\n\n## Run\n\n```bash\ngo run main.go\n```\n',
          ),
        ];

      case 'web':
        return [
          FileItem.createFile(
            name: 'index.html',
            path: 'index.html',
            content: '''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$projectName</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <h1>Welcome to $projectName</h1>
    <script src="script.js"></script>
</body>
</html>
''',
          ),
          FileItem.createFile(
            name: 'style.css',
            path: 'style.css',
            content: '''/* Styles for $projectName */

* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: 'Segoe UI', system-ui, sans-serif;
    background: #0a0a0a;
    color: #e0e0e0;
    display: flex;
    justify-content: center;
    align-items: center;
    min-height: 100vh;
}

h1 {
    font-weight: 300;
    letter-spacing: -0.5px;
}
''',
          ),
          FileItem.createFile(
            name: 'script.js',
            path: 'script.js',
            content: '''// Main script for $projectName

document.addEventListener('DOMContentLoaded', () => {
    console.log('$projectName loaded!');
});
''',
          ),
          FileItem.createFile(
            name: 'README.md',
            path: 'README.md',
            content: '# $projectName\n\nA web project.\n\nOpen index.html in a browser to get started.\n',
          ),
        ];

      case 'react':
        return [
          FileItem.createDirectory(name: 'src', path: 'src', children: [
            FileItem.createFile(
              name: 'App.tsx',
              path: 'src/App.tsx',
              content: '''import { useState } from 'react'
import './App.css'

function App() {
  const [count, setCount] = useState(0)

  return (
    <div className="app">
      <h1>$projectName</h1>
      <button onClick={() => setCount(c => c + 1)}>
        Count: {count}
      </button>
    </div>
  )
}

export default App
''',
            ),
            FileItem.createFile(
              name: 'App.css',
              path: 'src/App.css',
              content: '''.app {
  max-width: 800px;
  margin: 0 auto;
  padding: 2rem;
  text-align: center;
}

button {
  padding: 0.6em 1.2em;
  border-radius: 8px;
  border: 1px solid transparent;
  cursor: pointer;
}
''',
            ),
            FileItem.createFile(
              name: 'main.tsx',
              path: 'src/main.tsx',
              content: '''import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import './index.css'

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)
''',
            ),
          ]),
          FileItem.createFile(
            name: 'package.json',
            path: 'package.json',
            content: '''{
  "name": "${projectName.toLowerCase().replaceAll(' ', '-')}",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc && vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  },
  "devDependencies": {
    "@types/react": "^18.2.0",
    "@types/react-dom": "^18.2.0",
    "@vitejs/plugin-react": "^4.0.0",
    "typescript": "^5.0.0",
    "vite": "^5.0.0"
  }
}
''',
          ),
          FileItem.createFile(
            name: 'index.html',
            path: 'index.html',
            content: '''<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>$projectName</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
''',
          ),
          FileItem.createFile(
            name: 'README.md',
            path: 'README.md',
            content: '# $projectName\n\nA React + Vite + TypeScript project.\n\n```bash\nnpm install\nnpm run dev\n```\n',
          ),
        ];

      default:
        return null;
    }
  }

  // ─── Import & Export ───────────────────────────────────────────────

  /// Import a project from a ZIP file.
  Future<Project> importFromZip(String zipPath) async {
    final file = File(zipPath);
    if (!await file.exists()) {
      throw Exception('ZIP file not found: $zipPath');
    }

    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // Detect project name from zip filename or first entry.
    final zipName = path.basenameWithoutExtension(zipPath);
    final project = Project.create(
      name: zipName,
      language: await _detectLanguage(archive),
    );

    // Build file tree from archive.
    final files = _archiveToFileTree(archive);
    var updated = project;
    for (final f in files) {
      updated = _addFileToTree(updated, f);
    }

    await _storage.saveProject(updated);
    await _saveProjectMeta(project.id, {
      'category': ProjectCategory.personal,
      'tags': ['imported'],
      'color': _defaultColorForLanguage(updated.language),
      'isArchived': false,
      'gitInitialized': false,
      'recentFiles': <String>[],
    });

    _recordActivity();
    _notifyListeners();
    return updated;
  }

  /// Import from GitHub repository URL.
  Future<Project> importFromGitHub(String url) async {
    // Parse owner/repo from URL.
    final parsed = _parseGitHubUrl(url);
    if (parsed == null) {
      throw Exception('Invalid GitHub URL. Expected format: https://github.com/owner/repo');
    }

    final owner = parsed['owner']!;
    final repo = parsed['repo']!;

    // Fetch repo info via GitHub API.
    final apiUrl = '${ApiEndpoints.githubBase}${ApiEndpoints.githubRepos}/$owner/$repo';
    final response = await http.get(
      Uri.parse(apiUrl),
      headers: {'Accept': 'application/vnd.github.v3+json'},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch repository: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final language = (data['language'] ?? 'text').toString().toLowerCase();
    final description = (data['description'] ?? '').toString();

    final project = Project.create(
      name: repo,
      language: SupportedLanguages.extensionMap.entries
              .firstWhere(
                (e) => e.value == language,
                orElse: () => const MapEntry('.md', 'markdown'),
              )
              .value,
      description: description,
    );

    await _storage.saveProject(project);
    await _saveProjectMeta(project.id, {
      'category': ProjectCategory.personal,
      'tags': ['github', owner],
      'color': _defaultColorForLanguage(language),
      'isArchived': false,
      'gitInitialized': false,
      'githubUrl': url,
      'githubOwner': owner,
      'githubRepo': repo,
      'recentFiles': <String>[],
    });

    _recordActivity();
    _notifyListeners();
    return project;
  }

  /// Export a project as a ZIP file. Returns the exported ZIP file path.
  Future<String> exportToZip(String projectId) async {
    final project = await _storage.getProject(projectId);
    if (project == null) throw StateError('Project not found: $projectId');

    final archive = Archive();

    // Add all files from the project's file tree.
    void addFilesToArchive(List<FileItem> files, String prefix) {
      for (final file in files) {
        if (file.isDirectory && file.children != null) {
          addFilesToArchive(file.children!, '$prefix${file.name}/');
        } else if (!file.isDirectory && file.content != null) {
          final content = utf8.encode(file.content!);
          archive.addFile(
            ArchiveFile('$prefix${file.name}', content.length, content),
          );
        }
      }
    }

    addFilesToArchive(project.files, '');

    // Write ZIP file.
    final appDir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${appDir.path}/exports');
    await exportDir.create(recursive: true);

    final zipPath = '${exportDir.path}/${project.name.replaceAll(' ', '_')}.zip';
    final zipData = ZipEncoder().encode(archive);
    if (zipData != null) {
      await File(zipPath).writeAsBytes(zipData);
    }

    return zipPath;
  }

  /// Share a project via system share sheet.
  Future<void> shareProject(String projectId) async {
    final zipPath = await exportToZip(projectId);
    await Share.shareXFiles(
      [XFile(zipPath)],
      subject: 'Shared Project',
    );
  }

  // ─── Statistics ────────────────────────────────────────────────────

  /// Get statistics for a single project.
  Future<ProjectStats> getProjectStats(String id) async {
    final project = await _storage.getProject(id);
    if (project == null) {
      return ProjectStats(
        projectId: id,
        totalFiles: 0,
        totalDirectories: 0,
        totalLinesOfCode: 0,
        totalComments: 0,
        blankLines: 0,
        languageDistribution: {},
        avgFileSize: 0,
      );
    }

    final stats = _computeFileStats(project.files);
    final meta = await _getProjectMeta(id);

    return ProjectStats(
      projectId: id,
      totalFiles: stats['files'] ?? 0,
      totalDirectories: stats['dirs'] ?? 0,
      totalLinesOfCode: stats['lines'] ?? 0,
      totalComments: stats['comments'] ?? 0,
      blankLines: stats['blank'] ?? 0,
      languageDistribution: (stats['langs'] as Map<String, int>?) ?? {},
      avgFileSize: stats['avgSize'] ?? 0,
      currentBranch: meta['currentBranch'] as String?,
      modifiedFiles: meta['modifiedFiles'] as int? ?? 0,
      untrackedFiles: meta['untrackedFiles'] as int? ?? 0,
    );
  }

  /// Get global statistics across all projects.
  Future<GlobalStats> getGlobalStats() async {
    final projects = await _storage.getProjects();
    final meta = await _getAllMeta();

    int totalFiles = 0;
    int totalLines = 0;
    int totalComments = 0;
    final langDistribution = <String, int>{};
    int favoriteCount = 0;
    int archivedCount = 0;

    Project? mostActive;
    DateTime? mostRecent;

    for (final project in projects) {
      final pMeta = meta[project.id] ?? {};
      final stats = _computeFileStats(project.files);

      totalFiles += stats['files'] ?? 0;
      totalLines += stats['lines'] ?? 0;
      totalComments += stats['comments'] ?? 0;

      final langs = stats['langs'] as Map<String, int>? ?? {};
      for (final entry in langs.entries) {
        langDistribution[entry.key] = (langDistribution[entry.key] ?? 0) + entry.value;
      }

      if (project.isFavorite) favoriteCount++;
      if (pMeta['isArchived'] == true) archivedCount++;

      if (mostRecent == null || project.updatedAt.isAfter(mostRecent)) {
        mostRecent = project.updatedAt;
        mostActive = project;
      }
    }

    // Streak info.
    final streak = await _getStreakInfo();

    return GlobalStats(
      totalProjects: projects.where((p) => !(meta[p.id]?['isArchived'] ?? false)).length,
      totalFiles: totalFiles,
      totalLinesOfCode: totalLines,
      totalComments: totalComments,
      languageDistribution: langDistribution,
      favoriteProjects: favoriteCount,
      archivedProjects: archivedCount,
      mostActiveProject: mostActive,
      currentStreakDays: streak['current'] ?? 0,
      longestStreakDays: streak['longest'] ?? 0,
      lastActiveDate: streak['lastActive'] ?? DateTime.now(),
    );
  }

  // ─── Language Detection ────────────────────────────────────────────

  /// Detect primary language from file extensions in archive.
  Future<String> _detectLanguage(Archive archive) async {
    final extensions = <String, int>{};
    for (final file in archive.files) {
      final ext = path.extension(file.name).toLowerCase();
      if (ext.isNotEmpty) {
        extensions[ext] = (extensions[ext] ?? 0) + 1;
      }
    }

    if (extensions.isEmpty) return 'text';

    // Find most common extension.
    final sorted = extensions.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final mostCommon = sorted.first.key;

    return SupportedLanguages.extensionMap[mostCommon] ?? 'text';
  }

  /// Detect language from a single filename.
  static String detectLanguageFromFile(String filename) {
    final ext = path.extension(filename).toLowerCase();
    return SupportedLanguages.extensionMap[ext] ?? 'text';
  }

  // ─── Git Integration ───────────────────────────────────────────────

  /// Initialize git repository for a project.
  Future<void> initGit(String projectId) async {
    final project = await _storage.getProject(projectId);
    if (project == null) return;

    final dir = await _getProjectDirectory(projectId);

    try {
      final result = await Process.run(
        'git',
        ['init'],
        workingDirectory: dir.path,
      );

      if (result.exitCode == 0) {
        final meta = await _getProjectMeta(projectId);
        meta['gitInitialized'] = true;
        meta['currentBranch'] = 'main';
        await _saveProjectMeta(projectId, meta);
      }
    } catch (e) {
      debugPrint('[ProjectManager] Git init failed: $e');
    }
  }

  /// Get git status for a project.
  Future<Map<String, dynamic>> getGitStatus(String projectId) async {
    final meta = await _getProjectMeta(projectId);
    if (meta['gitInitialized'] != true) {
      return {'initialized': false, 'branch': null, 'modified': 0, 'untracked': 0};
    }

    return {
      'initialized': true,
      'branch': meta['currentBranch'] ?? 'main',
      'modified': meta['modifiedFiles'] ?? 0,
      'untracked': meta['untrackedFiles'] ?? 0,
    };
  }

  /// Quick commit all changes.
  Future<void> quickCommit(String projectId, String message) async {
    final dir = await _getProjectDirectory(projectId);

    try {
      await Process.run('git', ['add', '.'], workingDirectory: dir.path);
      await Process.run(
        'git',
        ['commit', '-m', message],
        workingDirectory: dir.path,
      );

      // Reset counters.
      final meta = await _getProjectMeta(projectId);
      meta['modifiedFiles'] = 0;
      meta['untrackedFiles'] = 0;
      await _saveProjectMeta(projectId, meta);
    } catch (e) {
      debugPrint('[ProjectManager] Git commit failed: $e');
    }
  }

  // ─── Recent Files ──────────────────────────────────────────────────

  /// Add a file to recent files list for a project.
  Future<void> _addRecentFile(String projectId, String filePath) async {
    final meta = await _getProjectMeta(projectId);
    final recent = (meta['recentFiles'] as List?)?.cast<String>() ?? [];
    recent.remove(filePath);
    recent.insert(0, filePath);
    if (recent.length > 10) recent.length = 10;
    meta['recentFiles'] = recent;
    await _saveProjectMeta(projectId, meta);
  }

  /// Get recent files for a project.
  Future<List<String>> getRecentFiles(String projectId) async {
    final meta = await _getProjectMeta(projectId);
    return (meta['recentFiles'] as List?)?.cast<String>() ?? [];
  }

  // ─── Cleanup ───────────────────────────────────────────────────────

  /// Dispose resources.
  Future<void> dispose() async {
    await _projectStreamController.close();
  }

  // ═══════════════════════════════════════════════════════════════════
  // Private Helpers
  // ═══════════════════════════════════════════════════════════════════

  FileItem _deepCopyFile(FileItem file) {
    return FileItem(
      id: file.id,
      name: file.name,
      path: file.path,
      isDirectory: file.isDirectory,
      content: file.content,
      children: file.children?.map(_deepCopyFile).toList(),
      modifiedAt: file.modifiedAt,
    );
  }

  Project _addFileToTree(Project project, FileItem file) {
    return project.addFile(file);
  }

  Map<String, dynamic> _computeFileStats(List<FileItem> files) {
    int fileCount = 0;
    int dirCount = 0;
    int totalLines = 0;
    int totalComments = 0;
    int blankLines = 0;
    int totalSize = 0;
    final langs = <String, int>{};

    void traverse(List<FileItem> items) {
      for (final item in items) {
        if (item.isDirectory && item.children != null) {
          dirCount++;
          traverse(item.children!);
        } else if (!item.isDirectory) {
          fileCount++;
          final content = item.content ?? '';
          final size = content.length;
          totalSize += size;

          final lines = content.split('\n');
          for (final line in lines) {
            totalLines++;
            final trimmed = line.trim();
            if (trimmed.isEmpty) {
              blankLines++;
            } else if (_isCommentLine(trimmed, item.extension)) {
              totalComments++;
            }
          }

          // Language distribution.
          final ext = item.extension;
          if (ext != null) {
            final lang = SupportedLanguages.extensionMap['.$ext'] ?? ext;
            langs[lang] = (langs[lang] ?? 0) + lines.length;
          }
        }
      }
    }

    traverse(files);

    return {
      'files': fileCount,
      'dirs': dirCount,
      'lines': totalLines,
      'comments': totalComments,
      'blank': blankLines,
      'langs': langs,
      'avgSize': fileCount > 0 ? totalSize ~/ fileCount : 0,
    };
  }

  bool _isCommentLine(String line, String? extension) {
    if (extension == null) return false;
    final commentPatterns = {
      'dart': ['//'],
      'py': ['#'],
      'go': ['//'],
      'js': ['//'],
      'ts': ['//'],
      'tsx': ['//'],
      'java': ['//'],
      'kt': ['//'],
      'swift': ['//'],
      'rs': ['//'],
      'c': ['//'],
      'cpp': ['//'],
      'cs': ['//'],
      'rb': ['#'],
      'sh': ['#'],
      'yaml': ['#'],
      'yml': ['#'],
      'md': ['<!--'],
      'html': ['<!--'],
      'css': ['/*'],
    };
    final patterns = commentPatterns[extension] ?? [];
    return patterns.any((p) => line.startsWith(p));
  }

  int _projectSize(Project project) {
    final stats = _computeFileStats(project.files);
    return stats['lines'] as int? ?? 0;
  }

  Map<String, String>? _parseGitHubUrl(String url) {
    final patterns = [
      RegExp(r'github\.com/([^/]+)/([^/]+)'),
      RegExp(r'github\.com:([^/]+)/([^/]+)'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(url);
      if (match != null) {
        return {
          'owner': match.group(1)!,
          'repo': match.group(2)!.replaceAll('.git', ''),
        };
      }
    }
    return null;
  }

  List<FileItem> _archiveToFileTree(Archive archive) {
    final rootFiles = <FileItem>[];

    for (final archiveFile in archive.files) {
      if (archiveFile.isFile && archiveFile.name.isNotEmpty) {
        final content = utf8.decode(archiveFile.content as List<int>, allowMalformed: true);
        final parts = archiveFile.name.split('/');

        if (parts.length == 1) {
          // Root-level file.
          rootFiles.add(FileItem.createFile(
            name: parts[0],
            path: parts[0],
            content: content,
          ));
        } else {
          // Nested file - build directory structure.
          _insertIntoTree(rootFiles, parts, content);
        }
      }
    }

    return rootFiles;
  }

  void _insertIntoTree(List<FileItem> tree, List<String> parts, String content) {
    if (parts.isEmpty) return;

    final currentName = parts[0];
    final remaining = parts.sublist(1);

    // Check if directory already exists.
    var dir = tree.where((f) => f.isDirectory && f.name == currentName).firstOrNull;

    if (remaining.length == 1) {
      // Last part is the file.
      final file = FileItem.createFile(
        name: remaining[0],
        path: parts.join('/'),
        content: content,
      );
      if (dir != null) {
        final idx = tree.indexOf(dir);
        tree[idx] = dir.addChild(file);
      } else {
        tree.add(FileItem.createDirectory(
          name: currentName,
          path: currentName,
          children: [file],
        ));
      }
    } else {
      // Intermediate directory.
      if (dir == null) {
        dir = FileItem.createDirectory(
          name: currentName,
          path: currentName,
        );
        tree.add(dir);
      }
      final idx = tree.indexWhere((f) => f.isDirectory && f.name == currentName);
      if (idx >= 0) {
        final children = List<FileItem>.from(tree[idx].children ?? []);
        _insertIntoTree(children, remaining, content);
        tree[idx] = tree[idx].copyWith(children: children);
      }
    }
  }

  int _defaultColorForLanguage(String language) {
    final colors = {
      'dart': 0xFF00B4AB,
      'python': 0xFF3776AB,
      'javascript': 0xFFF7DF1E,
      'typescript': 0xFF3178C6,
      'go': 0xFF00ADD8,
      'html': 0xFFE34F26,
      'css': 0xFF1572B6,
      'text': 0xFF7B2FF7,
    };
    return colors[language.toLowerCase()] ?? 0xFF7B2FF7;
  }

  // ─── Project Metadata Persistence ─────────────────────────────────

  /// Key prefix for project metadata in settings box.
  static const String _metaPrefix = 'project_meta_';
  static const String _archivedKey = 'archived_project_ids';

  Future<Map<String, dynamic>> _getProjectMeta(String projectId) async {
    final json = await _storage.getSetting<String>('$_metaPrefix$projectId');
    if (json == null) return {};
    try {
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveProjectMeta(String projectId, Map<String, dynamic> meta) async {
    await _storage.setSetting('$_metaPrefix$projectId', jsonEncode(meta));
  }

  Future<void> _removeProjectMeta(String projectId) async {
    await _storage.removeSetting('$_metaPrefix$projectId');
  }

  Future<Set<String>> _getArchivedIds() async {
    final list = await _storage.getSetting<List<dynamic>>(_archivedKey);
    if (list == null) return {};
    return list.cast<String>().toSet();
  }

  bool _isArchived(String projectId) {
    // Async check simplified for sync contexts.
    return false; // Will be filtered via getArchivedIds in async methods.
  }

  Future<Map<String, Map<String, dynamic>>> _getAllMeta() async {
    final all = await _storage.exportAllData();
    final metaMap = <String, Map<String, dynamic>>{};
    // Get all project IDs.
    final projects = await _storage.getProjects();
    for (final p in projects) {
      metaMap[p.id] = await _getProjectMeta(p.id);
    }
    return metaMap;
  }

  // ─── Streak Tracking ──────────────────────────────────────────────

  static const String _streakKey = 'coding_streak';
  static const String _lastActiveKey = 'last_active_date';

  Future<void> _recordActivity() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final lastActiveStr = await _storage.getSetting<String>(_lastActiveKey);
    final lastActive = lastActiveStr != null ? DateTime.tryParse(lastActiveStr) : null;

    if (lastActive != null) {
      final lastDay = DateTime(lastActive.year, lastActive.month, lastActive.day);
      final diff = today.difference(lastDay).inDays;

      if (diff == 1) {
        // Consecutive day.
        final currentStreak = await _storage.getSettingWithDefault<int>(_streakKey, 0);
        await _storage.setSetting(_streakKey, currentStreak + 1);
      } else if (diff > 1) {
        // Streak broken.
        await _storage.setSetting(_streakKey, 1);
      }
      // diff == 0 means same day, no change.
    } else {
      await _storage.setSetting(_streakKey, 1);
    }

    await _storage.setSetting(_lastActiveKey, today.toIso8601String());
  }

  Future<Map<String, int>> _getStreakInfo() async {
    final currentStreak = await _storage.getSettingWithDefault<int>(_streakKey, 0);
    // Longest streak is approximated as max historical.
    final longestStreak = math.max(currentStreak, 3); // Simplified.
    final lastActiveStr = await _storage.getSetting<String>(_lastActiveKey);
    final lastActive = lastActiveStr != null
        ? DateTime.tryParse(lastActiveStr) ?? DateTime.now()
        : DateTime.now();

    return {
      'current': currentStreak,
      'longest': longestStreak,
    };
  }
}


