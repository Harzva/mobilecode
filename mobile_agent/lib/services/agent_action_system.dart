// lib/services/agent_action_system.dart
// Agent Action System — Defines all actions the AI Agent can perform.
//
// Inspired by AppAgent's simplified action space:
// - AppAgent: tap / text / long_press / swipe
// - MobileCode: writeFile / editFile / runCommand / gitCommit / etc.
//
// Each action is atomic, reversible, and observable.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'coding_prompts.dart';
import 'llm_service.dart';
import 'storage_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Action Result
// ═══════════════════════════════════════════════════════════════════════════

/// Result of executing an agent action.
///
/// Every action returns an [ActionResult] indicating success or failure,
/// along with a message and optional structured data.
class ActionResult {
  /// Whether the action succeeded.
  final bool success;

  /// Human-readable result message.
  final String message;

  /// Optional structured data (e.g., file content, diff).
  final Map<String, dynamic>? data;

  /// The action that produced this result.
  final String actionName;

  /// Timestamp of execution.
  final DateTime timestamp;

  /// Duration of execution.
  final Duration? duration;

  const ActionResult._({
    required this.success,
    required this.message,
    required this.actionName,
    this.data,
    this.duration,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? _now;

  /// Create a success result.
  factory ActionResult.success(
    String actionName,
    String message, {
    Map<String, dynamic>? data,
    Duration? duration,
  }) =>
      ActionResult._(
        success: true,
        message: message,
        actionName: actionName,
        data: data,
        duration: duration,
      );

  /// Create a failure result.
  factory ActionResult.failure(
    String actionName,
    String message, {
    Map<String, dynamic>? data,
    Duration? duration,
  }) =>
      ActionResult._(
        success: false,
        message: message,
        actionName: actionName,
        data: data,
        duration: duration,
      );

  static DateTime get _now => DateTime.now();

  /// Convert to JSON for serialization.
  Map<String, dynamic> toJson() => {
        'success': success,
        'message': message,
        'actionName': actionName,
        'data': data,
        'timestamp': timestamp.toIso8601String(),
        'durationMs': duration?.inMilliseconds,
      };

  @override
  String toString() =>
      'ActionResult[$actionName]: ${success ? 'SUCCESS' : 'FAILURE'} — $message';
}

// ═══════════════════════════════════════════════════════════════════════════
// Action Base Class
// ═══════════════════════════════════════════════════════════════════════════

/// Base class for all agent actions.
///
/// Every action must define:
/// - [name]: Unique action identifier
/// - [description]: Human-readable description
/// - [params]: Action parameters as a map
/// - [execute]: Perform the action and return a result
/// - [rollback]: Reverse the action if possible
/// - [toJson]: Serialize the action for logging/replay
///
/// Actions should be atomic — they either fully succeed or fully fail.
/// If an action modifies multiple things, it should handle partial
/// failure gracefully or support rollback.
abstract class AgentAction {
  /// Unique action name (e.g., 'writeFile', 'editFile').
  String get name;

  /// Human-readable description of what this action does.
  String get description;

  /// Action parameters as structured data.
  Map<String, dynamic> get params;

  /// Execute the action and return a result.
  ///
  /// This is the main operation. It should be atomic and handle
  /// its own errors, always returning an [ActionResult].
  Future<ActionResult> execute();

  /// Rollback (undo) the action.
  ///
  /// Not all actions are reversible. If rollback is not supported,
  /// this should return a failure result.
  ///
  /// Rollback should only be called after a successful [execute].
  Future<ActionResult> rollback();

  /// Whether this action supports rollback.
  bool get isReversible;

  /// Serialize the action to JSON for logging and replay.
  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'params': params,
        'isReversible': isReversible,
      };

  @override
  String toString() => 'AgentAction($name): $description';
}

// ═══════════════════════════════════════════════════════════════════════════
// File Actions
// ═══════════════════════════════════════════════════════════════════════════

/// Action: Write content to a file (create or overwrite).
///
/// Creates the file if it doesn't exist, overwrites if it does.
/// Rollback restores the previous file content or deletes if newly created.
class WriteFileAction extends AgentAction {
  final String filePath;
  final String content;
  final StorageService _storage;

  String? _previousContent;
  bool _wasCreated = false;

  WriteFileAction({
    required this.filePath,
    required this.content,
    required StorageService storage,
  }) : _storage = storage;

  @override
  String get name => 'writeFile';

  @override
  String get description => 'Write ${content.length} chars to $filePath';

  @override
  Map<String, dynamic> get params => {
        'filePath': filePath,
        'contentLength': content.length,
      };

  @override
  bool get isReversible => true;

  @override
  Future<ActionResult> execute() async {
    final stopwatch = Stopwatch()..start();
    try {
      final file = File(filePath);

      // Save previous content for rollback.
      if (await file.exists()) {
        _previousContent = await file.readAsString();
        _wasCreated = false;
      } else {
        _wasCreated = true;
        _previousContent = null;
      }

      // Ensure parent directory exists.
      final parent = file.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }

      await file.writeAsString(content, flush: true);
      stopwatch.stop();

      return ActionResult.success(
        name,
        _wasCreated ? 'Created $filePath (${content.length} chars)' : 'Updated $filePath (${content.length} chars)',
        data: {'filePath': filePath, 'wasCreated': _wasCreated, 'size': content.length},
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return ActionResult.failure(
        name,
        'Failed to write $filePath: $e',
        duration: stopwatch.elapsed,
      );
    }
  }

  @override
  Future<ActionResult> rollback() async {
    try {
      if (_wasCreated) {
        // Delete the file if we created it.
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
        return ActionResult.success(name, 'Rollback: Deleted newly created $filePath');
      } else if (_previousContent != null) {
        // Restore previous content.
        final file = File(filePath);
        await file.writeAsString(_previousContent!, flush: true);
        return ActionResult.success(name, 'Rollback: Restored previous content of $filePath');
      }
      return ActionResult.failure(name, 'Rollback failed: No previous state to restore');
    } catch (e) {
      return ActionResult.failure(name, 'Rollback failed: $e');
    }
  }
}

/// Action: Edit a specific portion of a file.
///
/// Replaces [oldText] with [newText] in the file.
/// Rollback restores the original text.
class EditFileAction extends AgentAction {
  final String filePath;
  final String oldText;
  final String newText;

  String? _fullPreviousContent;

  EditFileAction({
    required this.filePath,
    required this.oldText,
    required this.newText,
  });

  @override
  String get name => 'editFile';

  @override
  String get description => 'Replace "$oldText" with "$newText" in $filePath';

  @override
  Map<String, dynamic> get params => {
        'filePath': filePath,
        'oldText': oldText.substring(0, oldText.length > 50 ? 50 : oldText.length),
        'newText': newText.substring(0, newText.length > 50 ? 50 : newText.length),
      };

  @override
  bool get isReversible => true;

  @override
  Future<ActionResult> execute() async {
    final stopwatch = Stopwatch()..start();
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return ActionResult.failure(name, 'File not found: $filePath');
      }

      final fullContent = await file.readAsString();
      _fullPreviousContent = fullContent;

      if (!fullContent.contains(oldText)) {
        return ActionResult.failure(
          name,
          'Could not find the text to replace in $filePath',
          data: {'searchedFor': oldText},
        );
      }

      final updatedContent = fullContent.replaceFirst(oldText, newText);
      await file.writeAsString(updatedContent, flush: true);
      stopwatch.stop();

      return ActionResult.success(
        name,
        'Replaced text in $filePath',
        data: {
          'filePath': filePath,
          'replacements': 1,
          'oldLength': oldText.length,
          'newLength': newText.length,
        },
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return ActionResult.failure(name, 'Failed to edit $filePath: $e', duration: stopwatch.elapsed);
    }
  }

  @override
  Future<ActionResult> rollback() async {
    try {
      if (_fullPreviousContent == null) {
        return ActionResult.failure(name, 'No previous content to restore');
      }
      final file = File(filePath);
      await file.writeAsString(_fullPreviousContent!, flush: true);
      return ActionResult.success(name, 'Rollback: Restored $filePath');
    } catch (e) {
      return ActionResult.failure(name, 'Rollback failed: $e');
    }
  }
}

/// Action: Delete a file.
///
/// Rollback recreates the file with its previous content.
class DeleteFileAction extends AgentAction {
  final String filePath;

  String? _previousContent;
  bool _existed = false;

  DeleteFileAction({required this.filePath});

  @override
  String get name => 'deleteFile';

  @override
  String get description => 'Delete $filePath';

  @override
  Map<String, dynamic> get params => {'filePath': filePath};

  @override
  bool get isReversible => true;

  @override
  Future<ActionResult> execute() async {
    final stopwatch = Stopwatch()..start();
    try {
      final file = File(filePath);
      _existed = await file.exists();

      if (_existed) {
        _previousContent = await file.readAsString();
        await file.delete();
        stopwatch.stop();
        return ActionResult.success(
          name,
          'Deleted $filePath',
          data: {'filePath': filePath, 'hadContent': _previousContent != null},
          duration: stopwatch.elapsed,
        );
      } else {
        stopwatch.stop();
        return ActionResult.failure(name, 'File does not exist: $filePath');
      }
    } catch (e) {
      stopwatch.stop();
      return ActionResult.failure(name, 'Failed to delete $filePath: $e', duration: stopwatch.elapsed);
    }
  }

  @override
  Future<ActionResult> rollback() async {
    try {
      if (!_existed || _previousContent == null) {
        return ActionResult.failure(name, 'Cannot rollback: file did not exist before deletion');
      }
      final file = File(filePath);
      await file.writeAsString(_previousContent!, flush: true);
      return ActionResult.success(name, 'Rollback: Restored deleted file $filePath');
    } catch (e) {
      return ActionResult.failure(name, 'Rollback failed: $e');
    }
  }
}

/// Action: Rename/move a file.
///
/// Rollback moves the file back to its original path.
class RenameFileAction extends AgentAction {
  final String oldPath;
  final String newPath;

  RenameFileAction({required this.oldPath, required this.newPath});

  @override
  String get name => 'renameFile';

  @override
  String get description => 'Rename $oldPath to $newPath';

  @override
  Map<String, dynamic> get params => {'oldPath': oldPath, 'newPath': newPath};

  @override
  bool get isReversible => true;

  @override
  Future<ActionResult> execute() async {
    final stopwatch = Stopwatch()..start();
    try {
      final oldFile = File(oldPath);
      if (!await oldFile.exists()) {
        return ActionResult.failure(name, 'Source file not found: $oldPath');
      }

      final newFile = File(newPath);
      if (await newFile.exists()) {
        return ActionResult.failure(name, 'Destination already exists: $newPath');
      }

      // Ensure parent directory exists.
      final parent = newFile.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }

      await oldFile.rename(newPath);
      stopwatch.stop();

      return ActionResult.success(
        name,
        'Renamed $oldPath to $newPath',
        data: {'oldPath': oldPath, 'newPath': newPath},
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return ActionResult.failure(name, 'Failed to rename $oldPath: $e', duration: stopwatch.elapsed);
    }
  }

  @override
  Future<ActionResult> rollback() async {
    try {
      final file = File(newPath);
      if (await file.exists()) {
        await file.rename(oldPath);
        return ActionResult.success(name, 'Rollback: Renamed back to $oldPath');
      }
      return ActionResult.failure(name, 'Cannot rollback: $newPath no longer exists');
    } catch (e) {
      return ActionResult.failure(name, 'Rollback failed: $e');
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Code Actions
// ═══════════════════════════════════════════════════════════════════════════

/// Action: Insert code at a specific position in a file.
///
/// Finds [anchor] text and inserts [newCode] after it.
/// Rollback removes the inserted code.
class InsertCodeAction extends AgentAction {
  final String filePath;
  final String anchor;
  final String newCode;

  String? _previousContent;

  InsertCodeAction({
    required this.filePath,
    required this.anchor,
    required this.newCode,
  });

  @override
  String get name => 'insertCode';

  @override
  String get description => 'Insert code after "$anchor" in $filePath';

  @override
  Map<String, dynamic> get params => {
        'filePath': filePath,
        'anchor': anchor.length > 30 ? '${anchor.substring(0, 30)}...' : anchor,
        'insertLength': newCode.length,
      };

  @override
  bool get isReversible => true;

  @override
  Future<ActionResult> execute() async {
    final stopwatch = Stopwatch()..start();
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return ActionResult.failure(name, 'File not found: $filePath');
      }

      final content = await file.readAsString();
      _previousContent = content;

      if (!content.contains(anchor)) {
        return ActionResult.failure(name, 'Anchor text not found in $filePath');
      }

      final updated = content.replaceFirst(anchor, '$anchor\n$newCode');
      await file.writeAsString(updated, flush: true);
      stopwatch.stop();

      return ActionResult.success(
        name,
        'Inserted ${newCode.length} chars after anchor in $filePath',
        data: {'filePath': filePath, 'insertedLength': newCode.length},
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return ActionResult.failure(name, 'Failed to insert code: $e', duration: stopwatch.elapsed);
    }
  }

  @override
  Future<ActionResult> rollback() async {
    try {
      if (_previousContent == null) {
        return ActionResult.failure(name, 'No previous content to restore');
      }
      final file = File(filePath);
      await file.writeAsString(_previousContent!, flush: true);
      return ActionResult.success(name, 'Rollback: Removed inserted code from $filePath');
    } catch (e) {
      return ActionResult.failure(name, 'Rollback failed: $e');
    }
  }
}

/// Action: Replace a specific code block with new code.
///
/// This is a more precise version of [EditFileAction] designed for code.
/// Rollback restores the original code block.
class ReplaceCodeAction extends AgentAction {
  final String filePath;
  final String oldCode;
  final String newCode;

  String? _previousContent;

  ReplaceCodeAction({
    required this.filePath,
    required this.oldCode,
    required this.newCode,
  });

  @override
  String get name => 'replaceCode';

  @override
  String get description => 'Replace code block (${oldCode.length} -> ${newCode.length} chars) in $filePath';

  @override
  Map<String, dynamic> get params => {
        'filePath': filePath,
        'oldLength': oldCode.length,
        'newLength': newCode.length,
      };

  @override
  bool get isReversible => true;

  @override
  Future<ActionResult> execute() async {
    final stopwatch = Stopwatch()..start();
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return ActionResult.failure(name, 'File not found: $filePath');
      }

      final content = await file.readAsString();
      _previousContent = content;

      if (!content.contains(oldCode)) {
        return ActionResult.failure(
          name,
          'Code block not found in $filePath',
          data: {'searchedLength': oldCode.length},
        );
      }

      final updated = content.replaceFirst(oldCode, newCode);
      await file.writeAsString(updated, flush: true);
      stopwatch.stop();

      return ActionResult.success(
        name,
        'Replaced code block in $filePath',
        data: {'filePath': filePath, 'oldLength': oldCode.length, 'newLength': newCode.length},
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return ActionResult.failure(name, 'Failed to replace code: $e', duration: stopwatch.elapsed);
    }
  }

  @override
  Future<ActionResult> rollback() async {
    try {
      if (_previousContent == null) {
        return ActionResult.failure(name, 'No previous content to restore');
      }
      final file = File(filePath);
      await file.writeAsString(_previousContent!, flush: true);
      return ActionResult.success(name, 'Rollback: Restored code block in $filePath');
    } catch (e) {
      return ActionResult.failure(name, 'Rollback failed: $e');
    }
  }
}

/// Action: Delete a specific code block from a file.
///
/// Rollback restores the deleted code.
class DeleteCodeAction extends AgentAction {
  final String filePath;
  final String codeToDelete;

  String? _previousContent;

  DeleteCodeAction({required this.filePath, required this.codeToDelete});

  @override
  String get name => 'deleteCode';

  @override
  String get description => 'Delete code block (${codeToDelete.length} chars) from $filePath';

  @override
  Map<String, dynamic> get params => {
        'filePath': filePath,
        'deleteLength': codeToDelete.length,
      };

  @override
  bool get isReversible => true;

  @override
  Future<ActionResult> execute() async {
    final stopwatch = Stopwatch()..start();
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return ActionResult.failure(name, 'File not found: $filePath');
      }

      final content = await file.readAsString();
      _previousContent = content;

      if (!content.contains(codeToDelete)) {
        return ActionResult.failure(name, 'Code block not found in $filePath');
      }

      final updated = content.replaceFirst(codeToDelete, '');
      await file.writeAsString(updated, flush: true);
      stopwatch.stop();

      return ActionResult.success(
        name,
        'Deleted code block from $filePath',
        data: {'filePath': filePath, 'deletedLength': codeToDelete.length},
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return ActionResult.failure(name, 'Failed to delete code: $e', duration: stopwatch.elapsed);
    }
  }

  @override
  Future<ActionResult> rollback() async {
    try {
      if (_previousContent == null) {
        return ActionResult.failure(name, 'No previous content to restore');
      }
      final file = File(filePath);
      await file.writeAsString(_previousContent!, flush: true);
      return ActionResult.success(name, 'Rollback: Restored deleted code in $filePath');
    } catch (e) {
      return ActionResult.failure(name, 'Rollback failed: $e');
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Terminal / Command Actions
// ═══════════════════════════════════════════════════════════════════════════

/// Action: Run a terminal/command.
///
/// Executes a shell command in the project directory.
/// Rollback is not supported for commands.
///
/// SECURITY: Commands are validated against an allowlist.
class RunCommandAction extends AgentAction {
  final String command;
  final String? workingDirectory;

  /// Allowed command prefixes for security.
  static const List<String> _allowedPrefixes = [
    'flutter ',
    'dart ',
    'git ',
    'npm ',
    'node ',
    'python ',
    'python3 ',
    'pip ',
    'mkdir ',
    'ls ',
    'cat ',
    'cp ',
    'mv ',
    'rm ',
    'echo ',
  ];

  RunCommandAction({
    required this.command,
    this.workingDirectory,
  });

  @override
  String get name => 'runCommand';

  @override
  String get description => 'Run: $command';

  @override
  Map<String, dynamic> get params => {
        'command': command,
        'workingDirectory': workingDirectory,
      };

  @override
  bool get isReversible => false;

  /// Validate that the command is allowed.
  bool _isCommandAllowed() {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return false;
    for (final prefix in _allowedPrefixes) {
      if (trimmed.startsWith(prefix)) return true;
    }
    // Also allow common single commands.
    final singleCommands = ['ls', 'pwd', 'clear', 'whoami'];
    if (singleCommands.contains(trimmed)) return true;
    return false;
  }

  @override
  Future<ActionResult> execute() async {
    final stopwatch = Stopwatch()..start();
    try {
      if (!_isCommandAllowed()) {
        return ActionResult.failure(
          name,
          'Command not allowed for security: $command',
          data: {'allowedPrefixes': _allowedPrefixes},
        );
      }

      final result = await Process.run(
        'sh',
        ['-c', command],
        workingDirectory: workingDirectory,
        runInShell: false,
      );

      stopwatch.stop();

      final success = result.exitCode == 0;
      final output = (result.stdout as String? ?? '').trim();
      final error = (result.stderr as String? ?? '').trim();

      if (success) {
        return ActionResult.success(
          name,
          'Command completed: $command',
          data: {
            'command': command,
            'exitCode': result.exitCode,
            'output': output,
            'outputLength': output.length,
          },
          duration: stopwatch.elapsed,
        );
      } else {
        return ActionResult.failure(
          name,
          'Command failed (exit ${result.exitCode}): $command\n$error',
          data: {
            'command': command,
            'exitCode': result.exitCode,
            'stderr': error,
            'stdout': output,
          },
          duration: stopwatch.elapsed,
        );
      }
    } catch (e) {
      stopwatch.stop();
      return ActionResult.failure(name, 'Failed to run command: $e', duration: stopwatch.elapsed);
    }
  }

  @override
  Future<ActionResult> rollback() async {
    return ActionResult.failure(name, 'Commands cannot be rolled back');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Git Actions
// ═══════════════════════════════════════════════════════════════════════════

/// Action: Commit changes to git.
///
/// Automatically stages all changes and commits with the given message.
class GitCommitAction extends AgentAction {
  final String message;
  final String? workingDirectory;

  GitCommitAction({
    required this.message,
    this.workingDirectory,
  });

  @override
  String get name => 'gitCommit';

  @override
  String get description => 'Git commit: "$message"';

  @override
  Map<String, dynamic> get params => {
        'message': message,
        'workingDirectory': workingDirectory,
      };

  @override
  bool get isReversible => false;

  @override
  Future<ActionResult> execute() async {
    final stopwatch = Stopwatch()..start();
    try {
      // Stage all changes.
      final addResult = await Process.run(
        'git',
        ['add', '.'],
        workingDirectory: workingDirectory,
      );
      if (addResult.exitCode != 0) {
        return ActionResult.failure(
          name,
          'Git add failed: ${addResult.stderr}',
          data: {'stderr': addResult.stderr},
        );
      }

      // Commit.
      final commitResult = await Process.run(
        'git',
        ['commit', '-m', message],
        workingDirectory: workingDirectory,
      );
      stopwatch.stop();

      if (commitResult.exitCode == 0) {
        return ActionResult.success(
          name,
          'Committed: "$message"',
          data: {'message': message, 'output': commitResult.stdout},
          duration: stopwatch.elapsed,
        );
      } else {
        return ActionResult.failure(
          name,
          'Git commit failed: ${commitResult.stderr}',
          data: {'stderr': commitResult.stderr},
          duration: stopwatch.elapsed,
        );
      }
    } catch (e) {
      stopwatch.stop();
      return ActionResult.failure(name, 'Git commit error: $e', duration: stopwatch.elapsed);
    }
  }

  @override
  Future<ActionResult> rollback() async {
    return ActionResult.failure(name, 'Git commits cannot be rolled back automatically');
  }
}

/// Action: Push commits to remote.
class GitPushAction extends AgentAction {
  final String? remote;
  final String? branch;
  final String? workingDirectory;

  GitPushAction({
    this.remote = 'origin',
    this.branch,
    this.workingDirectory,
  });

  @override
  String get name => 'gitPush';

  @override
  String get description => 'Git push to ${remote ?? 'origin'} ${branch ?? 'current'}';

  @override
  Map<String, dynamic> get params => {
        'remote': remote,
        'branch': branch,
        'workingDirectory': workingDirectory,
      };

  @override
  bool get isReversible => false;

  @override
  Future<ActionResult> execute() async {
    final stopwatch = Stopwatch()..start();
    try {
      final args = ['push', remote ?? 'origin'];
      if (branch != null) args.add(branch!);

      final result = await Process.run(
        'git',
        args,
        workingDirectory: workingDirectory,
      );
      stopwatch.stop();

      if (result.exitCode == 0) {
        return ActionResult.success(
          name,
          'Pushed to ${remote ?? 'origin'}',
          data: {'output': result.stdout},
          duration: stopwatch.elapsed,
        );
      } else {
        return ActionResult.failure(
          name,
          'Git push failed: ${result.stderr}',
          data: {'stderr': result.stderr},
          duration: stopwatch.elapsed,
        );
      }
    } catch (e) {
      stopwatch.stop();
      return ActionResult.failure(name, 'Git push error: $e', duration: stopwatch.elapsed);
    }
  }

  @override
  Future<ActionResult> rollback() async {
    return ActionResult.failure(name, 'Git push cannot be rolled back');
  }
}

/// Action: Pull changes from remote.
class GitPullAction extends AgentAction {
  final String? remote;
  final String? branch;
  final String? workingDirectory;

  GitPullAction({
    this.remote = 'origin',
    this.branch,
    this.workingDirectory,
  });

  @override
  String get name => 'gitPull';

  @override
  String get description => 'Git pull from ${remote ?? 'origin'}';

  @override
  Map<String, dynamic> get params => {
        'remote': remote,
        'branch': branch,
        'workingDirectory': workingDirectory,
      };

  @override
  bool get isReversible => false;

  @override
  Future<ActionResult> execute() async {
    final stopwatch = Stopwatch()..start();
    try {
      final args = ['pull', remote ?? 'origin'];
      if (branch != null) args.add(branch!);

      final result = await Process.run(
        'git',
        args,
        workingDirectory: workingDirectory,
      );
      stopwatch.stop();

      if (result.exitCode == 0) {
        return ActionResult.success(
          name,
          'Pulled from ${remote ?? 'origin'}',
          data: {'output': result.stdout},
          duration: stopwatch.elapsed,
        );
      } else {
        return ActionResult.failure(
          name,
          'Git pull failed: ${result.stderr}',
          data: {'stderr': result.stderr},
          duration: stopwatch.elapsed,
        );
      }
    } catch (e) {
      stopwatch.stop();
      return ActionResult.failure(name, 'Git pull error: $e', duration: stopwatch.elapsed);
    }
  }

  @override
  Future<ActionResult> rollback() async {
    return ActionResult.failure(name, 'Git pull cannot be rolled back');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Action Factory
// ═══════════════════════════════════════════════════════════════════════════

/// Factory for creating agent actions from JSON descriptions.
///
/// This allows the LLM to describe an action in JSON, and the
/// factory creates the corresponding [AgentAction] instance.
class ActionFactory {
  final StorageService _storage;

  ActionFactory({required StorageService storage}) : _storage = storage;

  /// Create an action from a JSON map.
  ///
  /// [json] Must contain 'name' and 'params' keys.
  /// Returns null if the action type is unknown.
  AgentAction? fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String?;
    final params = json['params'] as Map<String, dynamic>? ?? {};

    switch (name) {
      case 'writeFile':
        return WriteFileAction(
          filePath: params['filePath'] as String,
          content: params['content'] as String,
          storage: _storage,
        );
      case 'editFile':
        return EditFileAction(
          filePath: params['filePath'] as String,
          oldText: params['oldText'] as String,
          newText: params['newText'] as String,
        );
      case 'deleteFile':
        return DeleteFileAction(filePath: params['filePath'] as String);
      case 'renameFile':
        return RenameFileAction(
          oldPath: params['oldPath'] as String,
          newPath: params['newPath'] as String,
        );
      case 'insertCode':
        return InsertCodeAction(
          filePath: params['filePath'] as String,
          anchor: params['anchor'] as String,
          newCode: params['newCode'] as String,
        );
      case 'replaceCode':
        return ReplaceCodeAction(
          filePath: params['filePath'] as String,
          oldCode: params['oldCode'] as String,
          newCode: params['newCode'] as String,
        );
      case 'deleteCode':
        return DeleteCodeAction(
          filePath: params['filePath'] as String,
          codeToDelete: params['codeToDelete'] as String,
        );
      case 'runCommand':
        return RunCommandAction(
          command: params['command'] as String,
          workingDirectory: params['workingDirectory'] as String?,
        );
      case 'gitCommit':
        return GitCommitAction(
          message: params['message'] as String,
          workingDirectory: params['workingDirectory'] as String?,
        );
      case 'gitPush':
        return GitPushAction(
          remote: params['remote'] as String?,
          branch: params['branch'] as String?,
          workingDirectory: params['workingDirectory'] as String?,
        );
      case 'gitPull':
        return GitPullAction(
          remote: params['remote'] as String?,
          branch: params['branch'] as String?,
          workingDirectory: params['workingDirectory'] as String?,
        );
      default:
        debugPrint('[ActionFactory] Unknown action type: $name');
        return null;
    }
  }

  /// Get a description of all available actions for LLM context.
  ///
  /// Returns a string that can be included in prompts to teach
  /// the LLM about available actions.
  static String getAvailableActionsDescription() {
    return '''
Available Actions:
1. writeFile — Write content to a file (creates or overwrites)
   Params: filePath, content
2. editFile — Replace specific text in a file
   Params: filePath, oldText, newText
3. deleteFile — Delete a file
   Params: filePath
4. renameFile — Rename/move a file
   Params: oldPath, newPath
5. insertCode — Insert code after an anchor text
   Params: filePath, anchor, newCode
6. replaceCode — Replace a code block
   Params: filePath, oldCode, newCode
7. deleteCode — Delete a specific code block
   Params: filePath, codeToDelete
8. runCommand — Run a terminal command
   Params: command, workingDirectory?
9. gitCommit — Commit changes
   Params: message, workingDirectory?
10. gitPush — Push to remote
    Params: remote?, branch?, workingDirectory?
11. gitPull — Pull from remote
    Params: remote?, branch?, workingDirectory?
'''.trim();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Agent Task Plan
// ═══════════════════════════════════════════════════════════════════════════

/// A plan consisting of multiple agent actions to execute.
///
/// Created by [AgentTaskPlanner] and executed sequentially.
/// Supports full rollback if any step fails.
class AgentTaskPlan {
  /// The original user request.
  final String originalRequest;

  /// The list of actions to execute (in order).
  final List<AgentAction> actions;

  /// Optional description of the plan.
  final String? description;

  /// Results of executed actions.
  final List<ActionResult> results;

  /// Whether the plan has been executed.
  bool get isExecuted => results.isNotEmpty;

  /// Whether all actions succeeded.
  bool get allSucceeded => results.every((r) => r.success);

  /// Number of actions in the plan.
  int get actionCount => actions.length;

  /// Number of successfully completed actions.
  int get completedCount => results.where((r) => r.success).length;

  AgentTaskPlan({
    required this.originalRequest,
    required this.actions,
    this.description,
  }) : results = [];

  /// Execute all actions in the plan sequentially.
  ///
  /// If [stopOnFailure] is true (default), execution stops at the
  /// first failure and previously executed actions are rolled back.
  ///
  /// Returns a [PlanResult] with the overall outcome.
  Future<PlanResult> execute({bool stopOnFailure = true}) async {
    results.clear();
    final executedActions = <AgentAction>[];

    for (var i = 0; i < actions.length; i++) {
      final action = actions[i];
      debugPrint('[AgentTaskPlan] Executing step ${i + 1}/${actions.length}: ${action.name}');

      final result = await action.execute();
      results.add(result);
      executedActions.add(action);

      if (!result.success && stopOnFailure) {
        debugPrint('[AgentTaskPlan] Step ${i + 1} failed, rolling back...');
        await _rollback(executedActions);
        return PlanResult.failure(
          failedStep: i,
          errorMessage: result.message,
          partialResults: List.unmodifiable(results),
        );
      }
    }

    return PlanResult.success(
      executedActions: actions.length,
      results: List.unmodifiable(results),
    );
  }

  /// Rollback all executed actions in reverse order.
  Future<void> rollback() async {
    final executed = <AgentAction>[];
    for (var i = 0; i < results.length && i < actions.length; i++) {
      if (results[i].success) {
        executed.add(actions[i]);
      }
    }
    await _rollback(executed);
  }

  /// Rollback a list of actions in reverse order.
  Future<void> _rollback(List<AgentAction> executedActions) async {
    for (var i = executedActions.length - 1; i >= 0; i--) {
      final action = executedActions[i];
      if (action.isReversible) {
        try {
          await action.rollback();
        } catch (e) {
          debugPrint('[AgentTaskPlan] Rollback failed for ${action.name}: $e');
        }
      }
    }
  }

  /// Convert the plan to JSON for logging.
  Map<String, dynamic> toJson() => {
        'originalRequest': originalRequest,
        'description': description,
        'actionCount': actionCount,
        'actions': actions.map((a) => a.toJson()).toList(),
        'results': results.map((r) => r.toJson()).toList(),
        'allSucceeded': allSucceeded,
      };
}

// ═══════════════════════════════════════════════════════════════════════════
// Plan Result
// ═══════════════════════════════════════════════════════════════════════════

/// Result of executing an [AgentTaskPlan].
class PlanResult {
  /// Whether the entire plan succeeded.
  final bool success;

  /// Number of actions that were executed.
  final int executedActions;

  /// Individual action results.
  final List<ActionResult> results;

  /// If the plan failed, which step failed (0-indexed).
  final int? failedStep;

  /// If the plan failed, the error message.
  final String? errorMessage;

  const PlanResult._({
    required this.success,
    required this.executedActions,
    required this.results,
    this.failedStep,
    this.errorMessage,
  });

  /// Create a success result.
  factory PlanResult.success({
    required int executedActions,
    required List<ActionResult> results,
  }) =>
      PlanResult._(
        success: true,
        executedActions: executedActions,
        results: results,
      );

  /// Create a failure result.
  factory PlanResult.failure({
    required int failedStep,
    required String errorMessage,
    required List<ActionResult> partialResults,
  }) =>
      PlanResult._(
        success: false,
        executedActions: partialResults.length,
        results: partialResults,
        failedStep: failedStep,
        errorMessage: errorMessage,
      );

  @override
  String toString() {
    if (success) {
      return 'PlanResult: SUCCESS — $executedActions actions completed';
    } else {
      return 'PlanResult: FAILURE at step $failedStep — $errorMessage';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Action History
// ═══════════════════════════════════════════════════════════════════════════

/// Maintains a history of executed actions for undo/redo and logging.
class ActionHistory {
  final List<HistoryEntry> _entries = [];

  /// All history entries (chronological order).
  List<HistoryEntry> get entries => List.unmodifiable(_entries);

  /// Number of entries in the history.
  int get length => _entries.length;

  /// Whether the history is empty.
  bool get isEmpty => _entries.isEmpty;

  /// Add an entry to the history.
  void add(AgentAction action, ActionResult result) {
    _entries.add(HistoryEntry(
      action: action,
      result: result,
      timestamp: DateTime.now(),
    ));
  }

  /// Get the last N entries.
  List<HistoryEntry> recent(int n) {
    if (_entries.length <= n) return List.unmodifiable(_entries);
    return List.unmodifiable(_entries.sublist(_entries.length - n));
  }

  /// Get entries for a specific action type.
  List<HistoryEntry> byAction(String actionName) {
    return List.unmodifiable(_entries.where((e) => e.action.name == actionName));
  }

  /// Clear all history.
  void clear() => _entries.clear();

  /// Export history as JSON.
  List<Map<String, dynamic>> toJson() => _entries.map((e) => e.toJson()).toList();
}

/// A single entry in the action history.
class HistoryEntry {
  final AgentAction action;
  final ActionResult result;
  final DateTime timestamp;

  HistoryEntry({
    required this.action,
    required this.result,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'action': action.toJson(),
        'result': result.toJson(),
        'timestamp': timestamp.toIso8601String(),
      };
}
