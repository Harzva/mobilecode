// lib/services/crash_recovery_service.dart
// Auto-Save and Crash Recovery Service for Mobile Agent

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/error_handler.dart';

// ---------------------------------------------------------------------------
// EditorSnapshot - Point-in-time editor state
// ---------------------------------------------------------------------------

/// A snapshot of the editor state at a specific point in time.
///
/// Snapshots can be created manually or automatically and are used
/// to restore the editor to a previous state after a crash or
/// accidental closure.
class EditorSnapshot {
  /// Unique identifier for this snapshot (UUID v4).
  final String id;

  /// The project this snapshot belongs to.
  final String projectId;

  /// The file path that was active when the snapshot was taken.
  final String filePath;

  /// The full content of the file at snapshot time.
  final String content;

  /// Human-readable description (e.g., "Auto-save at 14:32").
  final String description;

  /// When the snapshot was created.
  final DateTime timestamp;

  /// Cursor position (character offset) at snapshot time.
  final int cursorPosition;

  /// Scroll position (pixel offset) at snapshot time.
  final int scrollPosition;

  const EditorSnapshot({
    required this.id,
    required this.projectId,
    required this.filePath,
    required this.content,
    required this.description,
    required this.timestamp,
    this.cursorPosition = 0,
    this.scrollPosition = 0,
  });

  /// Serialize to JSON for persistent storage.
  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'filePath': filePath,
        'content': content,
        'description': description,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'cursorPosition': cursorPosition,
        'scrollPosition': scrollPosition,
      };

  /// Deserialize from JSON.
  factory EditorSnapshot.fromJson(Map<String, dynamic> json) => EditorSnapshot(
        id: json['id'] as String,
        projectId: json['projectId'] as String,
        filePath: json['filePath'] as String,
        content: json['content'] as String,
        description: json['description'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        cursorPosition: json['cursorPosition'] as int? ?? 0,
        scrollPosition: json['scrollPosition'] as int? ?? 0,
      );

  /// Age of this snapshot (how long ago it was created).
  Duration get age => DateTime.now().difference(timestamp);

  /// Formatted age string for display (e.g., "2m ago", "1h 30m ago").
  String get formattedAge {
    final a = age;
    if (a.inSeconds < 60) return '\${a.inSeconds}s ago';
    if (a.inMinutes < 60) return '\${a.inMinutes}m ago';
    if (a.inHours < 24) return '\${a.inHours}h \${a.inMinutes % 60}m ago';
    return '\${a.inDays}d ago';
  }
}

// ---------------------------------------------------------------------------
// OpenFileState - State for a single open file
// ---------------------------------------------------------------------------

/// Tracks the state of a single open file in the editor.
class OpenFileState {
  /// The file path (relative to project root).
  final String filePath;

  /// The current editor content.
  final String content;

  /// Cursor position (character offset).
  final int cursorPosition;

  /// Scroll position (pixel offset).
  final int scrollPosition;

  /// Whether the file has unsaved changes.
  final bool isModified;

  const OpenFileState({
    required this.filePath,
    required this.content,
    this.cursorPosition = 0,
    this.scrollPosition = 0,
    this.isModified = false,
  });

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'content': content,
        'cursorPosition': cursorPosition,
        'scrollPosition': scrollPosition,
        'isModified': isModified,
      };

  factory OpenFileState.fromJson(Map<String, dynamic> json) => OpenFileState(
        filePath: json['filePath'] as String,
        content: json['content'] as String,
        cursorPosition: json['cursorPosition'] as int? ?? 0,
        scrollPosition: json['scrollPosition'] as int? ?? 0,
        isModified: json['isModified'] as bool? ?? false,
      );

  OpenFileState copyWith({
    String? filePath,
    String? content,
    int? cursorPosition,
    int? scrollPosition,
    bool? isModified,
  }) =>
      OpenFileState(
        filePath: filePath ?? this.filePath,
        content: content ?? this.content,
        cursorPosition: cursorPosition ?? this.cursorPosition,
        scrollPosition: scrollPosition ?? this.scrollPosition,
        isModified: isModified ?? this.isModified,
      );
}

// ---------------------------------------------------------------------------
// EditorState - Complete editor session state
// ---------------------------------------------------------------------------

/// Represents the complete editor session state for crash recovery.
class EditorState {
  /// The project ID for this session.
  final String projectId;

  /// All files that were open in the editor.
  final List<OpenFileState> openFiles;

  /// Which file was active (in focus) when the session was saved.
  final String activeFilePath;

  /// When the session state was last saved.
  final DateTime lastSavedAt;

  const EditorState({
    required this.projectId,
    required this.openFiles,
    required this.activeFilePath,
    required this.lastSavedAt,
  });

  /// Whether there are unsaved changes in any open file.
  bool get hasUnsavedChanges => openFiles.any((f) => f.isModified);

  /// The active file's state.
  OpenFileState? get activeFile {
    try {
      return openFiles.firstWhere((f) => f.filePath == activeFilePath);
    } catch (_) {
      return openFiles.isNotEmpty ? openFiles.first : null;
    }
  }

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        'openFiles': openFiles.map((f) => f.toJson()).toList(),
        'activeFilePath': activeFilePath,
        'lastSavedAt': lastSavedAt.toUtc().toIso8601String(),
      };

  factory EditorState.fromJson(Map<String, dynamic> json) => EditorState(
        projectId: json['projectId'] as String,
        openFiles: (json['openFiles'] as List<dynamic>)
            .map((e) => OpenFileState.fromJson(e as Map<String, dynamic>))
            .toList(),
        activeFilePath: json['activeFilePath'] as String,
        lastSavedAt: DateTime.parse(json['lastSavedAt'] as String),
      );
}

// ---------------------------------------------------------------------------
// CrashRecoveryService - Auto-save and crash recovery
// ---------------------------------------------------------------------------

/// Service that automatically saves editor state and provides crash recovery.
///
/// ## Features
/// - Periodic auto-save every 30 seconds
/// - Debounced save on changes (2-second delay)
/// - Crash detection on startup
/// - Snapshot system for manual restore points
/// - Session restoration after unexpected termination
///
/// ## Usage
///
/// ```dart
/// final recovery = CrashRecoveryService();
/// await recovery.init();
///
/// // Start auto-save for current file
/// recovery.startAutoSave('project-1', 'lib/main.dart', editorContent);
///
/// // Create a manual snapshot
/// await recovery.saveSnapshot('project-1', 'Before refactoring');
///
/// // Check for crash on startup
/// if (await recovery.hasUnsavedChangesFromCrash()) {
///   final state = await recovery.recoverFromCrash();
///   // Restore editor from state...
/// }
/// ```
class CrashRecoveryService with ErrorLogging {
  // -- Configuration --

  /// Interval between automatic saves.
  static const Duration _autoSaveInterval = Duration(seconds: 30);

  /// Debounce delay for change-triggered saves.
  static const Duration _debounceInterval = Duration(seconds: 2);

  /// Maximum number of snapshots to keep per project.
  static const int _maxSnapshotsPerProject = 20;

  /// Maximum age for snapshots (30 days).
  static const Duration _maxSnapshotAge = Duration(days: 30);

  // -- State --

  /// Timer for periodic auto-save.
  Timer? _periodicTimer;

  /// Timer for debounced change saves.
  Timer? _debounceTimer;

  /// Current project ID being edited.
  String? _currentProjectId;

  /// Current file path being edited.
  String? _currentFilePath;

  /// Current editor content.
  String? _currentContent;

  /// Whether the service has been initialized.
  bool _initialized = false;

  /// Whether a save is currently in progress.
  bool _isSaving = false;

  /// Latest editor state cache.
  EditorState? _lastSavedState;

  /// Whether a crash was detected on initialization.
  bool _crashDetected = false;

  /// Cached app documents directory.
  Directory? _appDir;

  /// Whether the service is initialized.
  bool get isInitialized => _initialized;

  /// Whether a crash was detected during initialization.
  bool get crashDetected => _crashDetected;

  // -- Initialization --

  /// Initialize the crash recovery service.
  ///
  /// Checks for previous crash state and cleans up old snapshots.
  Future<void> init() async {
    if (_initialized) return;

    try {
      _appDir = await getApplicationDocumentsDirectory();
      await _recoveryDir.create(recursive: true);
      await _snapshotsDir.create(recursive: true);

      // Check for previous crash.
      _crashDetected = await _detectPreviousCrash();
      if (_crashDetected) {
        logWarning('Previous crash detected — unsaved changes may be recoverable');
      }

      // Clean up old snapshots.
      await _cleanupOldSnapshots();

      _initialized = true;
      logInfo('CrashRecoveryService initialized');
    } catch (e, st) {
      logError('Failed to initialize CrashRecoveryService', e, st);
      // Allow the app to continue even if crash recovery fails.
      _initialized = true;
    }
  }

  // -- Auto-save --

  /// Start auto-save for the given project and file.
  ///
  /// This begins both periodic saves (every 30s) and enables
  /// debounced saves on content changes. Call [notifyChange] when
  /// the editor content changes.
  ///
  /// Only one auto-save session can be active at a time.
  /// Calling this again will stop the previous session.
  Future<void> startAutoSave(
    String projectId,
    String filePath,
    String content, {
    int cursorPosition = 0,
    int scrollPosition = 0,
  }) async {
    if (!_initialized) {
      logWarning('startAutoSave called before init');
      return;
    }

    // Stop any existing auto-save session.
    stopAutoSave();

    _currentProjectId = projectId;
    _currentFilePath = filePath;
    _currentContent = content;

    // Save initial state immediately.
    await _saveEditorState(projectId, [
      OpenFileState(
        filePath: filePath,
        content: content,
        cursorPosition: cursorPosition,
        scrollPosition: scrollPosition,
        isModified: true,
      ),
    ], filePath);

    // Start periodic auto-save.
    _periodicTimer = Timer.periodic(_autoSaveInterval, (_) async {
      await _performPeriodicSave();
    });

    logDebug('Auto-save started for \$filePath in project \$projectId');
  }

  /// Notify the service that editor content has changed.
  ///
  /// The save will be debounced by [_debounceInterval] to avoid
  /// excessive writes during rapid editing.
  void notifyChange(
    String content, {
    int cursorPosition = 0,
    int scrollPosition = 0,
  }) {
    if (!_initialized) return;
    if (_currentProjectId == null || _currentFilePath == null) return;

    _currentContent = content;

    // Cancel existing debounce timer.
    _debounceTimer?.cancel();

    // Start a new debounce timer.
    _debounceTimer = Timer(_debounceInterval, () async {
      await _saveEditorState(
        _currentProjectId!,
        [
          OpenFileState(
            filePath: _currentFilePath!,
            content: content,
            cursorPosition: cursorPosition,
            scrollPosition: scrollPosition,
            isModified: true,
          ),
        ],
        _currentFilePath!,
      );
      logDebug('Debounced save completed for \$_currentFilePath');
    });
  }

  /// Stop the current auto-save session.
  ///
  /// This also clears the crash state if the session ended normally.
  Future<void> stopAutoSave() async {
    _periodicTimer?.cancel();
    _debounceTimer?.cancel();
    _periodicTimer = null;
    _debounceTimer = null;

    // Mark as clean shutdown (no crash).
    await _clearCrashState();

    _currentProjectId = null;
    _currentFilePath = null;
    _currentContent = null;

    logDebug('Auto-save stopped');
  }

  // -- Snapshots --

  /// Create a named snapshot of the current editor state.
  ///
  /// [projectId] identifies the project.
  /// [description] is a human-readable label like "Before refactoring".
  /// [content] is the current file content.
  /// [filePath] is the file being edited.
  Future<EditorSnapshot> saveSnapshot(
    String projectId,
    String description, {
    String? content,
    String? filePath,
    int cursorPosition = 0,
    int scrollPosition = 0,
  }) async {
    if (!_initialized) {
      throw AppException.unexpected(message: 'CrashRecoveryService not initialized');
    }

    final snapshot = EditorSnapshot(
      id: _generateId(),
      projectId: projectId,
      filePath: filePath ?? _currentFilePath ?? 'unknown',
      content: content ?? _currentContent ?? '',
      description: description,
      timestamp: DateTime.now(),
      cursorPosition: cursorPosition,
      scrollPosition: scrollPosition,
    );

    final file = File('${_snapshotsDir.path}/\${snapshot.id}.json');
    await file.writeAsString(jsonEncode(snapshot.toJson()));

    logInfo('Snapshot saved: \$description for project \$projectId');

    // Clean up excess snapshots.
    await _enforceSnapshotLimit(projectId);

    return snapshot;
  }

  /// Get all snapshots for a project, sorted by timestamp (newest first).
  Future<List<EditorSnapshot>> getSnapshots(String projectId) async {
    if (!_initialized) return [];

    final snapshots = <EditorSnapshot>[];

    try {
      final files = await _snapshotsDir.list().toList();
      for (final entity in files.whereType<File>()) {
        try {
          final content = await entity.readAsString();
          final json = jsonDecode(content) as Map<String, dynamic>;
          final snapshot = EditorSnapshot.fromJson(json);
          if (snapshot.projectId == projectId) {
            snapshots.add(snapshot);
          }
        } catch (_) {
          // Skip malformed snapshot files.
        }
      }
    } catch (e, st) {
      logError('Failed to list snapshots', e, st);
    }

    snapshots.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return snapshots;
  }

  /// Restore the editor to a specific snapshot.
  Future<EditorSnapshot> restoreSnapshot(String snapshotId) async {
    final file = File('${_snapshotsDir.path}/\$snapshotId.json');
    if (!await file.exists()) {
      throw AppException.fileSystem(
        message: 'Snapshot \$snapshotId not found',
        path: file.path,
      );
    }

    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    final snapshot = EditorSnapshot.fromJson(json);

    // Update the current editor state to reflect the restored snapshot.
    _currentProjectId = snapshot.projectId;
    _currentFilePath = snapshot.filePath;
    _currentContent = snapshot.content;

    logInfo('Snapshot restored: \${snapshot.description}');
    return snapshot;
  }

  /// Delete a snapshot.
  Future<void> deleteSnapshot(String snapshotId) async {
    final file = File('${_snapshotsDir.path}/\$snapshotId.json');
    if (await file.exists()) {
      await file.delete();
      logDebug('Snapshot deleted: \$snapshotId');
    }
  }

  // -- Crash Recovery --

  /// Check if there are unsaved changes from a previous crash.
  Future<bool> hasUnsavedChangesFromCrash() async {
    if (!_initialized) return false;

    try {
      final crashFile = File('${_recoveryDir.path}/crash_state.json');
      if (!await crashFile.exists()) return false;

      final content = await crashFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final state = EditorState.fromJson(json);

      // Only report crash if there are unsaved changes and the save is recent (< 1 hour).
      final age = DateTime.now().difference(state.lastSavedAt);
      return state.hasUnsavedChanges && age.inHours < 1;
    } catch (e, st) {
      logError('Error checking crash state', e, st);
      return false;
    }
  }

  /// Recover editor state from a previous crash.
  ///
  /// Returns the saved [EditorState] or null if no crash state exists.
  /// Does NOT clear the crash state — call [clearCrashState] after
  /// successful restoration, or [stopAutoSave] for a clean shutdown.
  Future<EditorState?> recoverFromCrash() async {
    if (!_initialized) return null;

    try {
      final crashFile = File('${_recoveryDir.path}/crash_state.json');
      if (!await crashFile.exists()) return null;

      final content = await crashFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final state = EditorState.fromJson(json);

      logInfo('Crash recovery: \${state.openFiles.length} files, '
          'active: \${state.activeFilePath}, '
          'unsaved: \${state.hasUnsavedChanges}');

      return state;
    } catch (e, st) {
      logError('Failed to recover from crash', e, st);
      return null;
    }
  }

  /// Clear the crash state file (call after successful restoration
  /// or clean shutdown).
  Future<void> clearCrashState() async {
    try {
      final crashFile = File('${_recoveryDir.path}/crash_state.json');
      if (await crashFile.exists()) {
        await crashFile.delete();
        logDebug('Crash state cleared');
      }
    } catch (e, st) {
      logError('Failed to clear crash state', e, st);
    }
  }

  // -- Private Methods --

  Directory get _recoveryDir => Directory('\${_appDir!.path}/recovery');
  Directory get _snapshotsDir => Directory('\${_appDir!.path}/snapshots');

  Future<void> _saveEditorState(
    String projectId,
    List<OpenFileState> openFiles,
    String activeFilePath,
  ) async {
    if (_isSaving) return;
    _isSaving = true;

    try {
      final state = EditorState(
        projectId: projectId,
        openFiles: openFiles,
        activeFilePath: activeFilePath,
        lastSavedAt: DateTime.now(),
      );

      _lastSavedState = state;

      final crashFile = File('${_recoveryDir.path}/crash_state.json');
      await crashFile.writeAsString(
        jsonEncode(state.toJson()),
        flush: true,
      );

      logDebug('Editor state saved: \$activeFilePath');
    } catch (e, st) {
      logError('Failed to save editor state', e, st);
    } finally {
      _isSaving = false;
    }
  }

  Future<void> _performPeriodicSave() async {
    if (_currentProjectId == null || _currentFilePath == null) return;

    logDebug('Periodic auto-save triggered');

    await _saveEditorState(
      _currentProjectId!,
      [
        OpenFileState(
          filePath: _currentFilePath!,
          content: _currentContent ?? '',
          isModified: true,
        ),
      ],
      _currentFilePath!,
    );
  }

  Future<bool> _detectPreviousCrash() async {
    try {
      final crashFile = File('${_recoveryDir.path}/crash_state.json');
      if (!await crashFile.exists()) return false;

      final content = await crashFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final state = EditorState.fromJson(json);

      // If the state is very old (> 1 day), consider it stale.
      final age = DateTime.now().difference(state.lastSavedAt);
      if (age.inDays > 1) {
        logInfo('Stale crash state detected (\${age.inDays} days old), ignoring');
        await clearCrashState();
        return false;
      }

      logInfo('Previous crash detected — \${state.openFiles.length} files open');
      return true;
    } catch (e) {
      // If we can't read the crash file, ignore it.
      return false;
    }
  }

  Future<void> _cleanupOldSnapshots() async {
    try {
      final files = await _snapshotsDir.list().toList();
      for (final entity in files.whereType<File>()) {
        try {
          final stat = await entity.stat();
          final age = DateTime.now().difference(stat.modified);
          if (age > _maxSnapshotAge) {
            await entity.delete();
            logDebug('Deleted old snapshot: \${entity.path}');
          }
        } catch (_) {
          // Best effort.
        }
      }
    } catch (e, st) {
      logError('Failed to cleanup old snapshots', e, st);
    }
  }

  Future<void> _enforceSnapshotLimit(String projectId) async {
    try {
      final snapshots = await getSnapshots(projectId);
      if (snapshots.length <= _maxSnapshotsPerProject) return;

      // Delete oldest snapshots exceeding the limit.
      final toDelete = snapshots.sublist(_maxSnapshotsPerProject);
      for (final snapshot in toDelete) {
        await deleteSnapshot(snapshot.id);
      }

      logDebug('Enforced snapshot limit: deleted \${toDelete.length} old snapshots');
    } catch (e, st) {
      logError('Failed to enforce snapshot limit', e, st);
    }
  }

  String _generateId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rand = now.hashCode.abs();
    return '\${now.toRadixString(36)}_\${rand.toRadixString(36)}';
  }

  /// Dispose of timers and resources.
  Future<void> dispose() async {
    _periodicTimer?.cancel();
    _debounceTimer?.cancel();
    _periodicTimer = null;
    _debounceTimer = null;
    logDebug('CrashRecoveryService disposed');
  }
}
