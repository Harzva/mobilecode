// lib/providers/project_provider.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../models/project.dart';
import '../services/storage_service.dart';
import 'storage_provider.dart';

// ─── Projects List ─────────────────────────────────────────────────

/// Manages the list of projects with CRUD operations.
///
/// Uses [AsyncValue] to represent loading/error/ready states.
/// All mutations automatically persist to local storage.
class ProjectNotifier extends StateNotifier<AsyncValue<List<Project>>> {
  final StorageService _storage;

  ProjectNotifier(this._storage) : super(const AsyncValue.loading()) {
    _loadProjects();
  }

  /// Load projects from local storage.
  Future<void> _loadProjects() async {
    try {
      final projects = await _storage.getProjects();
      state = AsyncValue.data(projects);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  /// Refresh the projects list from storage.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await _loadProjects();
  }

  /// Create and save a new project.
  Future<void> createProject({
    required String name,
    required String rootPath,
    required String language,
    String? description,
    String? colorTag,
  }) async {
    final now = DateTime.now().toIso8601String();
    final project = Project(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      rootPath: rootPath,
      language: language,
      createdAt: now,
      updatedAt: now,
      description: description,
      colorTag: colorTag,
    );

    await _storage.saveProject(project);

    state = state.whenData((projects) => [project, ...projects]);
  }

  /// Update an existing project.
  Future<void> updateProject(Project updated) async {
    await _storage.saveProject(updated);

    state = state.whenData(
      (projects) => projects
          .map((p) => p.id == updated.id ? updated : p)
          .toList(),
    );
  }

  /// Delete a project by ID.
  Future<void> deleteProject(String id) async {
    await _storage.deleteProject(id);

    state = state.whenData(
      (projects) => projects.where((p) => p.id != id).toList(),
    );
  }

  /// Toggle favorite status for a project.
  Future<void> toggleFavorite(String id) async {
    final currentProjects = state.valueOrNull;
    if (currentProjects == null) return;

    final project = currentProjects.firstWhere((p) => p.id == id);
    final updated = project.copyWith(isFavorite: !project.isFavorite);

    await _storage.saveProject(updated);

    state = state.whenData(
      (projects) {
        final updatedList = projects.map((p) => p.id == id ? updated : p).toList();
        // Re-sort: favorites first, then by updatedAt.
        updatedList.sort((a, b) {
          if (a.isFavorite && !b.isFavorite) return -1;
          if (!a.isFavorite && b.isFavorite) return 1;
          return b.updatedAt.compareTo(a.updatedAt);
        });
        return updatedList;
      },
    );
  }

  /// Set the last opened file for a project.
  Future<void> setLastOpenedFile(String projectId, String filePath) async {
    final currentProjects = state.valueOrNull;
    if (currentProjects == null) return;

    final project = currentProjects.firstWhere((p) => p.id == projectId);
    final updated = project.copyWith(lastOpenedFilePath: filePath);

    await _storage.saveProject(updated);

    state = state.whenData(
      (projects) => projects.map((p) => p.id == projectId ? updated : p).toList(),
    );
  }

  /// Get a single project by ID (from current state).
  Project? getProjectById(String id) {
    return state.valueOrNull?.firstWhere((p) => p.id == id);
  }
}

/// Provider for the projects list.
///
/// Returns [AsyncValue<List<Project>>] representing the current state
/// of the projects list.
///
/// ```dart
/// final projectsAsync = ref.watch(projectsProvider);
/// projectsAsync.when(
///   data: (projects) => ...,
///   loading: () => CircularProgressIndicator(),
///   error: (e, _) => Text('Error: $e'),
/// );
/// ```
final projectsProvider =
    StateNotifierProvider<ProjectNotifier, AsyncValue<List<Project>>>(
  (ref) => ProjectNotifier(ref.watch(storageServiceProvider)),
);

// ─── Selected Project ──────────────────────────────────────────────

/// The currently selected/active project.
///
/// Null means no project is selected (show project picker).
/// When set, triggers loading of project files via [projectFilesProvider].
///
/// ```dart
/// final project = ref.watch(selectedProjectProvider);
/// ref.read(selectedProjectProvider.notifier).state = myProject;
/// ```
final selectedProjectProvider = StateProvider<Project?>((ref) => null);

// ─── Project Files ─────────────────────────────────────────────────

/// Manages file tree for the currently selected project.
///
/// Handles loading file listings from local storage,
/// filtering, and tree operations.
class ProjectFilesNotifier extends StateNotifier<AsyncValue<List<FileItem>>> {
  final StorageService _storage;
  final String? _projectId;

  ProjectFilesNotifier(this._storage, this._projectId)
      : super(const AsyncValue.loading()) {
    if (_projectId != null) {
      _loadFiles();
    } else {
      state = const AsyncValue.data([]);
    }
  }

  Future<void> _loadFiles() async {
    if (_projectId == null) {
      state = const AsyncValue.data([]);
      return;
    }

    try {
      final files = await _storage.getCachedFilesForProject(_projectId!);
      state = AsyncValue.data(files);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  /// Add a file to the project tree.
  Future<void> addFile(FileItem file) async {
    await _storage.cacheFileItem(file);

    state = state.whenData((files) => [...files, file]);
  }

  /// Update a file in the tree.
  Future<void> updateFile(FileItem updated) async {
    await _storage.cacheFileItem(updated);

    state = state.whenData(
      (files) => files.map((f) => f.id == updated.id ? updated : f).toList(),
    );
  }

  /// Remove a file from the tree.
  Future<void> removeFile(String fileId) async {
    state = state.whenData(
      (files) => files.where((f) => f.id != fileId).toList(),
    );
  }

  /// Refresh the file list.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await _loadFiles();
  }
}

/// Provider for the current project's files.
///
/// Automatically rebuilds when the selected project changes.
/// Returns [AsyncValue<List<FileItem>>] for the current project's file tree.
///
/// ```dart
/// final filesAsync = ref.watch(projectFilesProvider);
/// filesAsync.when(
///   data: (files) => FileTree(files: files),
///   loading: () => CircularProgressIndicator(),
///   error: (e, _) => Text('Error: $e'),
/// );
/// ```
final projectFilesProvider =
    StateNotifierProvider.family<ProjectFilesNotifier, AsyncValue<List<FileItem>>, String?>(
  (ref, projectId) => ProjectFilesNotifier(
    ref.watch(storageServiceProvider),
    projectId,
  ),
);

// ─── Derived Providers ─────────────────────────────────────────────

/// The number of projects.
final projectCountProvider = Provider<int>((ref) {
  return ref.watch(projectsProvider).when(
        data: (projects) => projects.length,
        loading: () => 0,
        error: (_, __) => 0,
      );
});

/// Filtered list of favorite projects.
final favoriteProjectsProvider = Provider<List<Project>>((ref) {
  final projectsAsync = ref.watch(projectsProvider);
  return projectsAsync.when(
    data: (projects) => projects.where((p) => p.isFavorite).toList(),
    loading: () => [],
    error: (_, __) => [],
  );
});

/// The currently selected project's name.
final selectedProjectNameProvider = Provider<String?>((ref) {
  return ref.watch(selectedProjectProvider)?.name;
});

/// The currently selected project's language.
final selectedProjectLanguageProvider = Provider<String?>((ref) {
  return ref.watch(selectedProjectProvider)?.language;
});
