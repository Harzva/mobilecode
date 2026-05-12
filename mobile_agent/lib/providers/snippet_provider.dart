// lib/providers/snippet_provider.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/code_snippet.dart';
import '../services/storage_service.dart';
import 'storage_provider.dart';

// ─── Snippets List ─────────────────────────────────────────────────

/// Manages the collection of code snippets.
///
/// Provides full CRUD operations with local persistence,
/// plus search and filter capabilities.
class SnippetNotifier extends StateNotifier<List<CodeSnippet>> {
  final StorageService _storage;

  SnippetNotifier(this._storage) : super([]) {
    _loadSnippets();
  }

  /// Load snippets from local storage.
  Future<void> _loadSnippets() async {
    try {
      final snippets = await _storage.getSnippets();
      state = snippets;
    } catch (e) {
      debugPrint('[SnippetNotifier] Failed to load snippets: $e');
      state = [];
    }
  }

  /// Refresh snippets from storage.
  Future<void> refresh() async {
    await _loadSnippets();
  }

  /// Add a new snippet.
  Future<void> addSnippet(CodeSnippet snippet) async {
    await _storage.saveSnippet(snippet);
    state = [snippet, ...state];
  }

  /// Create and add a new snippet from raw data.
  Future<void> createSnippet({
    required String title,
    required String code,
    required String language,
    List<String> tags = const [],
    String? description,
    String? source,
  }) async {
    final snippet = CodeSnippet.create(
      title: title,
      code: code,
      language: language,
      tags: tags,
      description: description,
      source: source,
    );
    await addSnippet(snippet);
  }

  /// Update an existing snippet.
  Future<void> updateSnippet(CodeSnippet updated) async {
    await _storage.saveSnippet(updated);

    state = state.map((s) => s.id == updated.id ? updated : s).toList();
  }

  /// Delete a snippet by ID.
  Future<void> deleteSnippet(String id) async {
    await _storage.deleteSnippet(id);

    state = state.where((s) => s.id != id).toList();
  }

  /// Toggle favorite status for a snippet.
  Future<void> toggleFavorite(String id) async {
    final snippet = state.firstWhere((s) => s.id == id);
    final updated = snippet.copyWith(isFavorite: !snippet.isFavorite);
    await updateSnippet(updated);
  }

  /// Record usage of a snippet (increments counter).
  Future<void> recordUsage(String id) async {
    final snippet = state.firstWhere((s) => s.id == id);
    snippet.recordUsage();
    await _storage.saveSnippet(snippet);

    // Notify listeners.
    state = [...state];
  }

  /// Search snippets by query string.
  ///
  /// Searches across title, code, description, tags, and language.
  List<CodeSnippet> search(String query) {
    if (query.isEmpty) return state;

    final lowerQuery = query.toLowerCase();
    return state.where((s) {
      return s.title.toLowerCase().contains(lowerQuery) ||
          s.code.toLowerCase().contains(lowerQuery) ||
          s.language.toLowerCase().contains(lowerQuery) ||
          (s.description?.toLowerCase().contains(lowerQuery) ?? false) ||
          s.tags.any((tag) => tag.toLowerCase().contains(lowerQuery));
    }).toList();
  }

  /// Get snippets filtered by tag.
  List<CodeSnippet> getByTag(String tag) {
    if (tag.isEmpty) return state;
    return state.where((s) => s.tags.contains(tag)).toList();
  }

  /// Get snippets filtered by language.
  List<CodeSnippet> getByLanguage(String language) {
    return state.where((s) => s.language == language).toList();
  }

  /// Get all unique tags across all snippets.
  List<String> get allTags {
    final tags = <String>{};
    for (final snippet in state) {
      tags.addAll(snippet.tags);
    }
    return tags.toList()..sort();
  }

  /// Get all unique languages across all snippets.
  List<String> get allLanguages {
    final langs = state.map((s) => s.language).toSet().toList();
    langs.sort();
    return langs;
  }

  /// Get a snippet by ID.
  CodeSnippet? getById(String id) {
    try {
      return state.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get favorite snippets.
  List<CodeSnippet> get favorites {
    return state.where((s) => s.isFavorite).toList();
  }

  /// Reorder a snippet in the list (for drag-and-drop).
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.length) return;
    if (newIndex < 0 || newIndex >= state.length) return;

    final newState = [...state];
    final item = newState.removeAt(oldIndex);
    newState.insert(newIndex, item);
    state = newState;
  }
}

/// Provider for all code snippets.
///
/// Returns the current list of snippets. Use the notifier
/// for CRUD operations.
///
/// ```dart
/// final snippets = ref.watch(snippetsProvider);
/// ref.read(snippetsProvider.notifier).addSnippet(newSnippet);
/// ```
final snippetsProvider =
    StateNotifierProvider<SnippetNotifier, List<CodeSnippet>>(
  (ref) => SnippetNotifier(ref.watch(storageServiceProvider)),
);

// ─── Search Query ──────────────────────────────────────────────────

/// Current search query for snippets.
///
/// Used to filter the snippet list in the UI.
final snippetSearchQueryProvider = StateProvider<String>((ref) => '');

/// Selected tag filter for snippets.
///
/// Empty string means no tag filter.
final snippetTagFilterProvider = StateProvider<String>((ref) => '');

/// Selected language filter for snippets.
///
/// Empty string means no language filter.
final snippetLanguageFilterProvider = StateProvider<String>((ref) => '');

// ─── Filtered Snippets ─────────────────────────────────────────────

/// Snippets filtered by tag.
///
/// Use with [ProviderFamily] to filter by a specific tag.
/// If [tag] is empty, returns all snippets.
///
/// ```dart
/// final dartSnippets = ref.watch(filteredSnippetsProvider('dart'));
/// ```
final filteredSnippetsProvider =
    Provider.family<List<CodeSnippet>, String>((ref, tag) {
  final snippets = ref.watch(snippetsProvider);
  if (tag.isEmpty) return snippets;

  return snippets.where((s) => s.tags.contains(tag)).toList();
});

/// Snippets filtered by search query and tag/language filters.
///
/// Combines all active filters for the snippets list view.
final filteredSnippetListProvider = Provider<List<CodeSnippet>>((ref) {
  final snippets = ref.watch(snippetsProvider);
  final query = ref.watch(snippetSearchQueryProvider);
  final tagFilter = ref.watch(snippetTagFilterProvider);
  final languageFilter = ref.watch(snippetLanguageFilterProvider);

  return snippets.where((s) {
    // Apply search query.
    if (query.isNotEmpty) {
      final lowerQuery = query.toLowerCase();
      final matchesQuery = s.title.toLowerCase().contains(lowerQuery) ||
          s.code.toLowerCase().contains(lowerQuery) ||
          s.language.toLowerCase().contains(lowerQuery) ||
          (s.description?.toLowerCase().contains(lowerQuery) ?? false) ||
          s.tags.any((tag) => tag.toLowerCase().contains(lowerQuery));
      if (!matchesQuery) return false;
    }

    // Apply tag filter.
    if (tagFilter.isNotEmpty && !s.tags.contains(tagFilter)) {
      return false;
    }

    // Apply language filter.
    if (languageFilter.isNotEmpty && s.language != languageFilter) {
      return false;
    }

    return true;
  }).toList();
});

// ─── Derived Providers ─────────────────────────────────────────────

/// All unique tags across all snippets.
final allSnippetTagsProvider = Provider<List<String>>((ref) {
  return ref.watch(snippetsProvider.notifier).allTags;
});

/// All unique languages across all snippets.
final allSnippetLanguagesProvider = Provider<List<String>>((ref) {
  return ref.watch(snippetsProvider.notifier).allLanguages;
});

/// The total number of snippets.
final snippetCountProvider = Provider<int>((ref) {
  return ref.watch(snippetsProvider).length;
});

/// The number of favorite snippets.
final favoriteSnippetCountProvider = Provider<int>((ref) {
  return ref.watch(snippetsProvider).where((s) => s.isFavorite).length;
});

/// Currently selected snippet (for detail view).
final selectedSnippetProvider = StateProvider<CodeSnippet?>((ref) => null);
