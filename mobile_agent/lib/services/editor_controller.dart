// lib/services/editor_controller.dart
// Editor Controller — Self-Use Control Interface for the Code Editor
//
// Exposes the code editor's functionality to SelfInvocationService.
// Registered as a GlobalKey in the Editor widget, this controller
// allows the Agent to perform every editor operation programmatically:
//
//   - Create, open, close files
//   - Read and write code content
//   - Navigate to specific lines
//   - Find and replace text
//   - Format code
//   - Track cursor position and selection
//
// All operations emit events through [events] stream for real-time
// observation by the Agent and UI layers.

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Editor Controller
// ═══════════════════════════════════════════════════════════════════════════

/// Controller for the code editor that enables programmatic control.
///
/// Used by both the UI layer (editor widget) and the self-invocation
/// system (Agent control). All state changes notify listeners and
/// emit events through the [events] stream.
///
/// To use in a widget:
/// ```dart
/// final editorController = EditorController();
/// SelfInvocationService().registerEditorController(editorController);
///
/// // In build:
/// CodeEditor(controller: editorController),
/// ```
class EditorController extends ChangeNotifier {
  // ── State ─────────────────────────────────────────────────────────────

  /// Currently open file path (empty string if none).
  String _currentFile = '';

  /// Current editor content.
  String _content = '';

  /// Cursor position (character offset from start).
  int _cursorPosition = 0;

  /// Selection start position.
  int _selectionStart = 0;

  /// Selection end position.
  int _selectionEnd = 0;

  /// List of currently open file paths (tab bar).
  final List<String> _openFiles = [];

  /// Map of file paths to their unsaved content.
  final Map<String, String> _fileContents = {};

  /// Set of files with unsaved changes.
  final Set<String> _modifiedFiles = {};

  /// Whether the editor is currently busy (e.g., formatting, saving).
  bool _isBusy = false;

  /// Last error message (cleared on next successful operation).
  String? _lastError;

  /// Undo stack: list of content snapshots.
  final List<EditSnapshot> _undoStack = [];

  /// Redo stack: list of content snapshots.
  final List<EditSnapshot> _redoStack = [];

  /// Maximum undo levels.
  static const int _maxUndoLevels = 50;

  /// Whether undo is available.
  bool get canUndo => _undoStack.isNotEmpty;

  /// Whether redo is available.
  bool get canRedo => _redoStack.isNotEmpty;

  // ── Stream Controller ─────────────────────────────────────────────────

  final StreamController<EditorEvent> _eventController =
      StreamController<EditorEvent>.broadcast();

  // ── Public Streams ────────────────────────────────────────────────────

  /// Stream of editor events for real-time observation.
  Stream<EditorEvent> get events => _eventController.stream;

  // ── Getters ───────────────────────────────────────────────────────────

  /// Path of the currently active file.
  String get currentFile => _currentFile;

  /// Current editor content.
  String get content => _content;

  /// Current cursor position (character offset).
  int get cursorPosition => _cursorPosition;

  /// Current selection range.
  TextRange get selection => TextRange(start: _selectionStart, end: _selectionEnd);

  /// Currently selected text.
  String get selectedText {
    if (_selectionStart == _selectionEnd) return '';
    final start = _selectionStart.clamp(0, _content.length);
    final end = _selectionEnd.clamp(0, _content.length);
    return _content.substring(start, end);
  }

  /// Number of lines in the current content.
  int get lineCount => _content.isEmpty ? 1 : '\n'.allMatches(_content).length + 1;

  /// List of open file paths (tabs).
  List<String> get openFiles => List.unmodifiable(_openFiles);

  /// Whether there are unsaved changes in the current file.
  bool get isModified => _currentFile.isNotEmpty && _modifiedFiles.contains(_currentFile);

  /// Whether any file has unsaved changes.
  bool get hasAnyUnsavedChanges => _modifiedFiles.isNotEmpty;

  /// Files with unsaved changes.
  Set<String> get modifiedFiles => Set.unmodifiable(_modifiedFiles);

  /// Whether the editor is busy.
  bool get isBusy => _isBusy;

  /// Last error message, if any.
  String? get lastError => _lastError;

  /// Whether a file is currently open.
  bool get hasOpenFile => _currentFile.isNotEmpty;

  /// Size of the current content in characters.
  int get contentLength => _content.length;

  /// Get the line number for a given character offset.
  int getLineForOffset(int offset) {
    if (_content.isEmpty || offset <= 0) return 1;
    final clamped = offset.clamp(0, _content.length);
    return '\n'.allMatches(_content.substring(0, clamped)).length + 1;
  }

  /// Get the column number for a given character offset.
  int getColumnForOffset(int offset) {
    if (_content.isEmpty || offset <= 0) return 1;
    final clamped = offset.clamp(0, _content.length);
    final lastNewline = _content.lastIndexOf('\n', clamped - 1);
    if (lastNewline == -1) return clamped + 1;
    return clamped - lastNewline;
  }

  /// Current line number based on cursor position.
  int get currentLine => getLineForOffset(_cursorPosition);

  /// Current column number based on cursor position.
  int get currentColumn => getColumnForOffset(_cursorPosition);

  /// Get content for a specific file (even if not currently open).
  String? getFileContent(String path) => _fileContents[path];

  // ── File Operations ───────────────────────────────────────────────────

  /// Create a new file and open it in the editor.
  ///
  /// Creates the file on disk if it doesn't exist, then opens it.
  Future<void> createFile(String path) async {
    _setBusy(true);
    _clearError();

    try {
      final file = File(path);
      if (!await file.exists()) {
        final parent = file.parent;
        if (!await parent.exists()) {
          await parent.create(recursive: true);
        }
        await file.writeAsString('', flush: true);
      }

      // Add to open files if not already open
      if (!_openFiles.contains(path)) {
        _openFiles.add(path);
      }

      _currentFile = path;
      _content = '';
      _fileContents[path] = '';
      _cursorPosition = 0;
      _selectionStart = 0;
      _selectionEnd = 0;
      _clearUndoRedo();

      _emitEvent(EditorEventType.fileOpened, file: path, data: {'created': true});
      notifyListeners();
    } catch (e) {
      _setError('Failed to create file: $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  /// Open an existing file in the editor.
  ///
  /// Reads the file from disk and displays it. If the file is already
  /// open, switches to its tab.
  Future<void> openFile(String path) async {
    _setBusy(true);
    _clearError();

    try {
      final file = File(path);
      if (!await file.exists()) {
        throw FileSystemException('File not found', path);
      }

      final content = await file.readAsString();

      // Add to open files if not already there
      if (!_openFiles.contains(path)) {
        _openFiles.add(path);
      }

      _currentFile = path;
      _content = content;
      _fileContents[path] = content;
      _cursorPosition = 0;
      _selectionStart = 0;
      _selectionEnd = 0;
      _clearUndoRedo();

      _emitEvent(EditorEventType.fileOpened, file: path, data: {
        'size': content.length,
        'lines': lineCount,
      });
      notifyListeners();
    } catch (e) {
      _setError('Failed to open file: $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  /// Write (replace all) code in the current file.
  ///
  /// Saves the previous content to the undo stack before writing.
  Future<void> writeCode(String code) async {
    if (_currentFile.isEmpty) {
      throw StateError('No file is currently open');
    }

    _pushUndo(_content, _cursorPosition);
    _content = code;
    _fileContents[_currentFile] = code;
    _modifiedFiles.add(_currentFile);
    _cursorPosition = code.length;
    _selectionStart = code.length;
    _selectionEnd = code.length;
    _redoStack.clear();

    _emitEvent(EditorEventType.contentChanged, file: _currentFile, data: {
      'length': code.length,
      'lines': lineCount,
    });
    notifyListeners();
  }

  /// Insert code at a specific position in the current file.
  ///
  /// If [position] is -1, inserts at the current cursor position.
  Future<void> insertCode(int position, String code) async {
    if (_currentFile.isEmpty) {
      throw StateError('No file is currently open');
    }

    _pushUndo(_content, _cursorPosition);

    final insertPos = position < 0 ? _cursorPosition : position;
    final clampedPos = insertPos.clamp(0, _content.length);

    final before = _content.substring(0, clampedPos);
    final after = _content.substring(clampedPos);
    _content = before + code + after;
    _fileContents[_currentFile] = _content;
    _modifiedFiles.add(_currentFile);
    _cursorPosition = clampedPos + code.length;
    _selectionStart = _cursorPosition;
    _selectionEnd = _cursorPosition;
    _redoStack.clear();

    _emitEvent(EditorEventType.contentChanged, file: _currentFile, data: {
      'insertedAt': clampedPos,
      'insertLength': code.length,
    });
    notifyListeners();
  }

  /// Delete a range of characters from the current file.
  Future<void> deleteRange(int start, int end) async {
    if (_currentFile.isEmpty) {
      throw StateError('No file is currently open');
    }

    final clampedStart = start.clamp(0, _content.length);
    final clampedEnd = end.clamp(0, _content.length);
    if (clampedStart >= clampedEnd) return;

    _pushUndo(_content, _cursorPosition);

    final before = _content.substring(0, clampedStart);
    final after = _content.substring(clampedEnd);
    _content = before + after;
    _fileContents[_currentFile] = _content;
    _modifiedFiles.add(_currentFile);
    _cursorPosition = clampedStart;
    _selectionStart = clampedStart;
    _selectionEnd = clampedStart;
    _redoStack.clear();

    _emitEvent(EditorEventType.contentChanged, file: _currentFile, data: {
      'deletedRange': [clampedStart, clampedEnd],
    });
    notifyListeners();
  }

  /// Select all content in the current file.
  Future<void> selectAll() async {
    _selectionStart = 0;
    _selectionEnd = _content.length;
    _cursorPosition = _content.length;

    _emitEvent(EditorEventType.cursorMoved, file: _currentFile, data: {
      'selection': [0, _content.length],
    });
    notifyListeners();
  }

  /// Format the current file's code.
  ///
  /// Applies basic formatting. In production, this would use dart_style.
  Future<void> format() async {
    if (_currentFile.isEmpty) return;

    _setBusy(true);
    try {
      _pushUndo(_content, _cursorPosition);

      // Basic Dart formatting: normalize indentation
      final formatted = _formatDartCode(_content);

      if (formatted != _content) {
        _content = formatted;
        _fileContents[_currentFile] = formatted;
        _modifiedFiles.add(_currentFile);

        _emitEvent(EditorEventType.contentChanged, file: _currentFile, data: {
          'formatted': true,
        });
        notifyListeners();
      }

      _emitEvent(EditorEventType.fileFormatted, file: _currentFile);
    } finally {
      _setBusy(false);
    }
  }

  /// Save the current file to disk.
  Future<void> save() async {
    if (_currentFile.isEmpty) return;

    _setBusy(true);
    _clearError();

    try {
      final file = File(_currentFile);
      await file.writeAsString(_content, flush: true);
      _modifiedFiles.remove(_currentFile);

      _emitEvent(EditorEventType.fileSaved, file: _currentFile, data: {
        'size': _content.length,
      });
      notifyListeners();
    } catch (e) {
      _setError('Failed to save file: $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  /// Save all open files.
  Future<void> saveAll() async {
    for (final path in List.of(_modifiedFiles)) {
      if (_fileContents.containsKey(path)) {
        try {
          final file = File(path);
          await file.writeAsString(_fileContents[path]!, flush: true);
        } catch (e) {
          _setError('Failed to save $path: $e');
        }
      }
    }
    _modifiedFiles.clear();

    _emitEvent(EditorEventType.fileSaved, data: {'savedAll': true});
    notifyListeners();
  }

  /// Close the current file.
  ///
  /// If there are unsaved changes, they are discarded. Use [save] first
  /// to preserve changes.
  Future<void> closeFile() async {
    if (_currentFile.isEmpty) return;

    final closedFile = _currentFile;
    _openFiles.remove(closedFile);
    _fileContents.remove(closedFile);
    _modifiedFiles.remove(closedFile);

    // Switch to the next available file
    if (_openFiles.isNotEmpty) {
      _currentFile = _openFiles.last;
      _content = _fileContents[_currentFile] ?? '';
    } else {
      _currentFile = '';
      _content = '';
    }

    _cursorPosition = 0;
    _selectionStart = 0;
    _selectionEnd = 0;
    _clearUndoRedo();

    _emitEvent(EditorEventType.fileClosed, file: closedFile);
    notifyListeners();
  }

  /// Close a specific file by path.
  Future<void> closeFileByPath(String path) async {
    if (path == _currentFile) {
      await closeFile();
      return;
    }
    _openFiles.remove(path);
    _fileContents.remove(path);
    _modifiedFiles.remove(path);
    notifyListeners();
  }

  /// Switch to an already-open file.
  void switchToFile(String path) {
    if (!_openFiles.contains(path)) {
      throw ArgumentError('File is not open: $path');
    }

    _currentFile = path;
    _content = _fileContents[path] ?? '';
    _cursorPosition = 0;
    _selectionStart = 0;
    _selectionEnd = 0;

    _emitEvent(EditorEventType.fileOpened, file: path, data: {'switched': true});
    notifyListeners();
  }

  // ── Navigation ────────────────────────────────────────────────────────

  /// Move cursor to a specific line number.
  Future<void> goToLine(int line) async {
    if (_content.isEmpty) return;

    final lines = _content.split('\n');
    final targetLine = line.clamp(1, lines.length);

    int offset = 0;
    for (int i = 0; i < targetLine - 1 && i < lines.length; i++) {
      offset += lines[i].length + 1; // +1 for \n
    }

    _cursorPosition = offset;
    _selectionStart = offset;
    _selectionEnd = offset;

    _emitEvent(EditorEventType.cursorMoved, file: _currentFile, data: {
      'line': targetLine,
      'column': 1,
      'offset': offset,
    });
    notifyListeners();
  }

  /// Find text in the current content.
  ///
  /// Returns the offset of the first match, or -1 if not found.
  Future<int> find(String text) async {
    if (text.isEmpty || _content.isEmpty) return -1;

    final offset = _content.indexOf(text, _cursorPosition);
    if (offset != -1) {
      _selectionStart = offset;
      _selectionEnd = offset + text.length;
      _cursorPosition = offset;

      _emitEvent(EditorEventType.cursorMoved, file: _currentFile, data: {
        'found': text,
        'offset': offset,
        'length': text.length,
      });
      notifyListeners();
    }

    return offset;
  }

  /// Replace the first occurrence of [find] with [replace].
  Future<bool> replace(String find, String replace) async {
    if (find.isEmpty || !_content.contains(find)) return false;

    _pushUndo(_content, _cursorPosition);

    final offset = _content.indexOf(find);
    _content = _content.replaceFirst(find, replace);
    _fileContents[_currentFile] = _content;
    _modifiedFiles.add(_currentFile);

    _cursorPosition = offset + replace.length;
    _selectionStart = offset;
    _selectionEnd = offset + replace.length;
    _redoStack.clear();

    _emitEvent(EditorEventType.contentChanged, file: _currentFile, data: {
      'replaced': find,
      'with': replace,
      'offset': offset,
    });
    notifyListeners();
    return true;
  }

  /// Replace all occurrences of [find] with [replace].
  Future<int> replaceAll(String find, String replace) async {
    if (find.isEmpty || !_content.contains(find)) return 0;

    _pushUndo(_content, _cursorPosition);

    int count = 0;
    String result = _content;
    while (result.contains(find)) {
      result = result.replaceFirst(find, replace);
      count++;
    }

    _content = result;
    _fileContents[_currentFile] = result;
    _modifiedFiles.add(_currentFile);
    _redoStack.clear();

    _emitEvent(EditorEventType.contentChanged, file: _currentFile, data: {
      'replaceAll': find,
      'with': replace,
      'count': count,
    });
    notifyListeners();
    return count;
  }

  // ── Undo / Redo ───────────────────────────────────────────────────────

  /// Undo the last change.
  void undo() {
    if (_undoStack.isEmpty) return;

    final snapshot = _undoStack.removeLast();
    _redoStack.add(EditSnapshot(
      content: _content,
      cursorPosition: _cursorPosition,
      timestamp: DateTime.now(),
    ));

    _content = snapshot.content;
    if (_currentFile.isNotEmpty) {
      _fileContents[_currentFile] = snapshot.content;
      _modifiedFiles.add(_currentFile);
    }
    _cursorPosition = snapshot.cursorPosition;
    _selectionStart = _cursorPosition;
    _selectionEnd = _cursorPosition;

    _emitEvent(EditorEventType.contentChanged, file: _currentFile, data: {
      'undo': true,
    });
    notifyListeners();
  }

  /// Redo the last undone change.
  void redo() {
    if (_redoStack.isEmpty) return;

    final snapshot = _redoStack.removeLast();
    _undoStack.add(EditSnapshot(
      content: _content,
      cursorPosition: _cursorPosition,
      timestamp: DateTime.now(),
    ));

    _content = snapshot.content;
    if (_currentFile.isNotEmpty) {
      _fileContents[_currentFile] = snapshot.content;
      _modifiedFiles.add(_currentFile);
    }
    _cursorPosition = snapshot.cursorPosition;
    _selectionStart = _cursorPosition;
    _selectionEnd = _cursorPosition;

    _emitEvent(EditorEventType.contentChanged, file: _currentFile, data: {
      'redo': true,
    });
    notifyListeners();
  }

  // ── Cursor & Selection ────────────────────────────────────────────────

  /// Move the cursor to a specific offset.
  void moveCursor(int offset) {
    _cursorPosition = offset.clamp(0, _content.length);
    _selectionStart = _cursorPosition;
    _selectionEnd = _cursorPosition;

    _emitEvent(EditorEventType.cursorMoved, file: _currentFile, data: {
      'offset': _cursorPosition,
    });
    notifyListeners();
  }

  /// Set the selection range.
  void setSelection(int start, int end) {
    _selectionStart = start.clamp(0, _content.length);
    _selectionEnd = end.clamp(0, _content.length);
    _cursorPosition = _selectionEnd;

    _emitEvent(EditorEventType.cursorMoved, file: _currentFile, data: {
      'selection': [_selectionStart, _selectionEnd],
    });
    notifyListeners();
  }

  /// Get the text at a specific line.
  String getLineText(int lineNumber) {
    if (_content.isEmpty) return '';
    final lines = _content.split('\n');
    if (lineNumber < 1 || lineNumber > lines.length) return '';
    return lines[lineNumber - 1];
  }

  /// Get all lines as a list.
  List<String> get lines => _content.split('\n');

  // ── Internal Helpers ──────────────────────────────────────────────────

  void _setBusy(bool value) {
    _isBusy = value;
    notifyListeners();
  }

  void _setError(String message) {
    _lastError = message;
    notifyListeners();
  }

  void _clearError() {
    _lastError = null;
  }

  void _pushUndo(String content, int cursorPos) {
    _undoStack.add(EditSnapshot(
      content: content,
      cursorPosition: cursorPos,
      timestamp: DateTime.now(),
    ));
    if (_undoStack.length > _maxUndoLevels) {
      _undoStack.removeAt(0);
    }
  }

  void _clearUndoRedo() {
    _undoStack.clear();
    _redoStack.clear();
  }

  void _emitEvent(EditorEventType type, {String? file, dynamic data}) {
    _eventController.add(EditorEvent(
      type: type,
      file: file,
      data: data,
      timestamp: DateTime.now(),
    ));
  }

  /// Basic Dart code formatter.
  ///
  /// In production, this would use the `dart_style` package.
  String _formatDartCode(String code) {
    // Simple formatting: consistent indentation and spacing
    final lines = code.split('\n');
    final formatted = <String>[];
    int indentLevel = 0;
    const String indent = '  ';

    for (var line in lines) {
      final trimmed = line.trim();

      // Decrease indent for closing braces
      if (trimmed.startsWith('}') ||
          trimmed.startsWith(')') ||
          trimmed.startsWith(']')) {
        indentLevel = (indentLevel - 1).clamp(0, 100);
      }

      // Format the line with proper indentation
      if (trimmed.isEmpty) {
        formatted.add('');
      } else {
        formatted.add(indent * indentLevel + trimmed);
      }

      // Increase indent for opening braces
      if (trimmed.endsWith('{') ||
          trimmed.endsWith('(') ||
          trimmed.endsWith('[') ||
          trimmed.endsWith(':')) {
        indentLevel++;
      }
    }

    return formatted.join('\n');
  }

  // ── Cleanup ───────────────────────────────────────────────────────────

  @override
  void dispose() {
    _eventController.close();
    _openFiles.clear();
    _fileContents.clear();
    _modifiedFiles.clear();
    _undoStack.clear();
    _redoStack.clear();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Editor Event
// ═══════════════════════════════════════════════════════════════════════════

/// Types of events that the editor can emit.
enum EditorEventType {
  /// A file was opened.
  fileOpened,

  /// A file was saved.
  fileSaved,

  /// Content was modified.
  contentChanged,

  /// Cursor position or selection changed.
  cursorMoved,

  /// Code was formatted.
  fileFormatted,

  /// A file was closed.
  fileClosed,
}

/// A single event emitted by the editor controller.
class EditorEvent {
  /// Type of the event.
  final EditorEventType type;

  /// File path associated with the event (if applicable).
  final String? file;

  /// Additional event data.
  final dynamic data;

  /// When the event occurred.
  final DateTime timestamp;

  const EditorEvent({
    required this.type,
    this.file,
    this.data,
    required this.timestamp,
  });

  /// Human-readable event description.
  String get description {
    switch (type) {
      case EditorEventType.fileOpened:
        return 'File opened${file != null ? ': $file' : ''}';
      case EditorEventType.fileSaved:
        return 'File saved${file != null ? ': $file' : ''}';
      case EditorEventType.contentChanged:
        return 'Content changed${file != null ? ' in $file' : ''}';
      case EditorEventType.cursorMoved:
        return 'Cursor moved${file != null ? ' in $file' : ''}';
      case EditorEventType.fileFormatted:
        return 'Code formatted${file != null ? ': $file' : ''}';
      case EditorEventType.fileClosed:
        return 'File closed${file != null ? ': $file' : ''}';
    }
  }

  @override
  String toString() => 'EditorEvent[${type.name}] $description';
}

// ═══════════════════════════════════════════════════════════════════════════
// Edit Snapshot (for Undo/Redo)
// ═══════════════════════════════════════════════════════════════════════════

/// A snapshot of the editor state for undo/redo functionality.
class EditSnapshot {
  /// Content at the time of the snapshot.
  final String content;

  /// Cursor position at the time of the snapshot.
  final int cursorPosition;

  /// When the snapshot was taken.
  final DateTime timestamp;

  const EditSnapshot({
    required this.content,
    required this.cursorPosition,
    required this.timestamp,
  });
}
