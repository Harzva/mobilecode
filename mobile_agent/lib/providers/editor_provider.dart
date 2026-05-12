// lib/providers/editor_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';

// ─── Service Provider (for DI) ─────────────────────────────────────

/// Provider for the ApiService singleton (initialized in main).
/// This is overridden in the ProviderScope during app startup.
// final apiServiceProvider = Provider<ApiService>((ref) {
//   throw UnimplementedError('apiServiceProvider must be overridden in main.dart');
// });

// ─── Editor State ──────────────────────────────────────────────────

/// The currently active/open file in the editor.
///
/// Null means no file is currently open (editor shows empty/welcome state).
///
/// ```dart
/// final file = ref.watch(currentFileProvider);
/// if (file != null) { ... }
/// ```
final currentFileProvider = StateProvider<FileItem?>((ref) => null);

/// The text content of the current editor buffer.
///
/// This is the in-memory buffer content, which may differ from the
/// saved file content (tracked by [isEditingProvider]).
///
/// ```dart
/// final content = ref.watch(editorContentProvider);
/// ref.read(editorContentProvider.notifier).state = newContent;
/// ```
final editorContentProvider = StateProvider<String>((ref) => '');

/// Whether the editor has unsaved changes.
///
/// Set to true when the content is modified, false when saved.
/// Used to show the "unsaved changes" indicator and handle
/// back-navigation confirmation dialogs.
///
/// ```dart
/// final hasChanges = ref.watch(isEditingProvider);
/// ```
final isEditingProvider = StateProvider<bool>((ref) => false);

/// Whether the editor is currently loading a file.
///
/// Set to true while reading file content from disk or GitHub,
/// false once the content is loaded into the editor buffer.
final isEditorLoadingProvider = StateProvider<bool>((ref) => false);

/// The current cursor position (line, column) in the editor.
///
/// Used to display cursor position in the status bar.
/// Format: (line, column) as (int, int).
final cursorPositionProvider = StateProvider<(int, int)>((ref) => (1, 1));

/// The current selection range in the editor.
///
/// Format: (startOffset, endOffset) or null if no selection.
final selectionRangeProvider = StateProvider<(int, int)?>((ref) => null);

/// Whether the editor should use word wrap.
final wordWrapProvider = StateProvider<bool>((ref) => false);

/// The currently open files (tabs).
///
/// Maintains the list of open file tabs in the editor.
/// The [currentFileProvider] should always point to one of these
/// unless no files are open.
///
/// ```dart
/// final openFiles = ref.watch(openFilesProvider);
/// ```
final openFilesProvider = StateProvider<List<FileItem>>((ref) => []);

// ─── Notifiers for complex operations ──────────────────────────────

/// Notifier for managing editor tab operations.
class EditorTabsNotifier extends StateNotifier<List<FileItem>> {
  EditorTabsNotifier() : super([]);

  /// Open a file in the tabs.
  ///
  /// If the file is already open, this is a no-op (tabs stay unique).
  void openFile(FileItem file) {
    if (state.any((f) => f.path == file.path)) return;
    state = [...state, file];
  }

  /// Close a specific tab by file path.
  ///
  /// Returns the path of the file that should become active next,
  /// or null if all tabs are closed.
  String? closeFile(String path) {
    final index = state.indexWhere((f) => f.path == path);
    if (index == -1) return null;

    final newState = [...state]..removeAt(index);
    state = newState;

    // Determine which file to focus next.
    if (newState.isEmpty) return null;
    if (index < newState.length) return newState[index].path;
    return newState.last.path;
  }

  /// Close all tabs.
  void closeAll() {
    state = [];
  }

  /// Close all tabs except the given one.
  void closeOthers(String keepPath) {
    state = state.where((f) => f.path == keepPath).toList();
  }

  /// Check if a file is open.
  bool isOpen(String path) {
    return state.any((f) => f.path == path);
  }

  /// Reorder tabs.
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.length) return;
    if (newIndex < 0 || newIndex >= state.length) return;

    final newState = [...state];
    final item = newState.removeAt(oldIndex);
    newState.insert(newIndex, item);
    state = newState;
  }
}

/// Provider for the editor tabs notifier.
///
/// Use this for programmatic tab management (open, close, reorder).
/// Use [openFilesProvider] for reading the tab list.
final editorTabsProvider = StateNotifierProvider<EditorTabsNotifier, List<FileItem>>(
  (ref) => EditorTabsNotifier(),
);

// ─── Derived/Computed Providers ────────────────────────────────────

/// The filename of the currently open file.
///
/// Returns null if no file is open.
final currentFileNameProvider = Provider<String?>((ref) {
  final file = ref.watch(currentFileProvider);
  return file?.name;
});

/// The language of the currently open file.
///
/// Returns null if no file is open.
final currentFileLanguageProvider = Provider<String?>((ref) {
  final file = ref.watch(currentFileProvider);
  return file?.language;
});

/// The number of lines in the current editor content.
final lineCountProvider = Provider<int>((ref) {
  final content = ref.watch(editorContentProvider);
  if (content.isEmpty) return 1;
  return '\n'.allMatches(content).length + 1;
});

/// Whether the current file has unsaved changes.
///
/// Combines [isEditingProvider] with file state for a definitive answer.
final hasUnsavedChangesProvider = Provider<bool>((ref) {
  return ref.watch(isEditingProvider);
});
