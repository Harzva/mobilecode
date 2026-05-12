// ignore_for_file: avoid_print

/// ============================================================================
/// Self-Action Registry
/// ============================================================================
///
/// All actions that MobileCode can perform on itself.
/// These are registered with SelfInvocationService at startup.
///
/// Categories:
/// - editor.*     -- Code editor actions
/// - terminal.*   -- Terminal actions
/// - project.*    -- Project management actions
/// - git.*        -- Git operations
/// - github.*     -- GitHub integration actions
/// - navigation.* -- Screen navigation actions
/// - ai.*         -- AI assistant actions
/// - ui.*         -- UI feedback actions (toast, dialog, snackbar)
/// - file.*       -- File system actions
/// - settings.*   -- Settings/configuration actions
///
/// Usage:
/// ```dart
/// final service = ref.read(selfInvocationServiceProvider);
/// SelfActionRegistry.registerAll(service);
/// ```
/// ============================================================================

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'self_invocation_service.dart';
import 'navigation_controller.dart';

// ---------------------------------------------------------------------------
// Registry
// ---------------------------------------------------------------------------

class SelfActionRegistry {
  const SelfActionRegistry._();

  /// Register every known action handler with [service].
  static void registerAll(SelfInvocationService service) {
    // -- Editor Actions ------------------------------------------------------
    service.registerActionHandler(
        'editor.createFile', _EditorCreateFileHandler());
    service.registerActionHandler(
        'editor.openFile', _EditorOpenFileHandler());
    service.registerActionHandler(
        'editor.writeCode', _EditorWriteCodeHandler());
    service.registerActionHandler(
        'editor.insertCode', _EditorInsertCodeHandler());
    service.registerActionHandler(
        'editor.deleteRange', _EditorDeleteRangeHandler());
    service.registerActionHandler(
        'editor.selectAll', _EditorSelectAllHandler());
    service.registerActionHandler('editor.format', _EditorFormatHandler());
    service.registerActionHandler('editor.save', _EditorSaveHandler());
    service.registerActionHandler('editor.closeFile', _EditorCloseFileHandler());
    service.registerActionHandler(
        'editor.goToLine', _EditorGoToLineHandler());
    service.registerActionHandler('editor.find', _EditorFindHandler());
    service.registerActionHandler('editor.replace', _EditorReplaceHandler());

    // -- Terminal Actions ----------------------------------------------------
    service.registerActionHandler('terminal.run', _TerminalRunHandler());
    service.registerActionHandler('terminal.kill', _TerminalKillHandler());
    service.registerActionHandler('terminal.clear', _TerminalClearHandler());

    // -- Project Actions -----------------------------------------------------
    service.registerActionHandler('project.create', _ProjectCreateHandler());
    service.registerActionHandler('project.open', _ProjectOpenHandler());
    service.registerActionHandler(
        'project.addFile', _ProjectAddFileHandler());
    service.registerActionHandler(
        'project.deleteFile', _ProjectDeleteFileHandler());
    service.registerActionHandler(
        'project.renameFile', _ProjectRenameFileHandler());

    // -- Git Actions ---------------------------------------------------------
    service.registerActionHandler('git.init', _GitInitHandler());
    service.registerActionHandler('git.add', _GitAddHandler());
    service.registerActionHandler('git.commit', _GitCommitHandler());
    service.registerActionHandler('git.push', _GitPushHandler());
    service.registerActionHandler('git.pull', _GitPullHandler());
    service.registerActionHandler('git.status', _GitStatusHandler());
    service.registerActionHandler(
        'git.createBranch', _GitCreateBranchHandler());
    service.registerActionHandler(
        'git.switchBranch', _GitSwitchBranchHandler());

    // -- GitHub Actions ------------------------------------------------------
    service.registerActionHandler(
        'github.createRepo', _GithubCreateRepoHandler());
    service.registerActionHandler(
        'github.pushFile', _GithubPushFileHandler());
    service.registerActionHandler(
        'github.createIssue', _GithubCreateIssueHandler());
    service.registerActionHandler(
        'github.createPR', _GithubCreatePRHandler());

    // -- Navigation Actions --------------------------------------------------
    service.registerActionHandler(
        'navigation.navigate', _NavNavigateHandler());
    service.registerActionHandler('navigation.goBack', _NavGoBackHandler());
    service.registerActionHandler(
        'navigation.openDrawer', _NavOpenDrawerHandler());
    service.registerActionHandler(
        'navigation.closeDrawer', _NavCloseDrawerHandler());

    // -- AI Actions ----------------------------------------------------------
    service.registerActionHandler('ai.chat', _AIChatHandler());
    service.registerActionHandler(
        'ai.generateCode', _AIGenerateCodeHandler());
    service.registerActionHandler(
        'ai.explainCode', _AIExplainCodeHandler());
    service.registerActionHandler('ai.fixCode', _AIFixCodeHandler());
    service.registerActionHandler(
        'ai.optimizeCode', _AIOptimizeCodeHandler());
    service.registerActionHandler(
        'ai.addComments', _AIAddCommentsHandler());

    // -- UI Actions ----------------------------------------------------------
    service.registerActionHandler('ui.showToast', _UIShowToastHandler());
    service.registerActionHandler('ui.showDialog', _UIShowDialogHandler());
    service.registerActionHandler(
        'ui.showSnackbar', _UIShowSnackbarHandler());
    service.registerActionHandler('ui.vibrate', _UIVibrateHandler());
    service.registerActionHandler('ui.playSound', _UIPlaySoundHandler());
    service.registerActionHandler(
        'ui.setBrightness', _UISetBrightnessHandler());

    // -- File Actions --------------------------------------------------------
    service.registerActionHandler('file.read', _FileReadHandler());
    service.registerActionHandler('file.write', _FileWriteHandler());
    service.registerActionHandler('file.delete', _FileDeleteHandler());
    service.registerActionHandler('file.exists', _FileExistsHandler());
    service.registerActionHandler('file.list', _FileListHandler());
    service.registerActionHandler('file.copy', _FileCopyHandler());
    service.registerActionHandler('file.move', _FileMoveHandler());

    // -- Settings Actions ----------------------------------------------------
    service.registerActionHandler('settings.set', _SettingsSetHandler());
    service.registerActionHandler('settings.get', _SettingsGetHandler());
    service.registerActionHandler(
        'settings.reset', _SettingsResetHandler());
    service.registerActionHandler(
        'settings.export', _SettingsExportHandler());
  }
}

// ---------------------------------------------------------------------------
// Editor Handlers
// ---------------------------------------------------------------------------

class _EditorCreateFileHandler implements SelfActionHandler {
  @override
  String get description => 'Create a new file in the editor';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final path = params['path'] as String?;
    if (path == null || path.isEmpty) {
      throw ArgumentError("Parameter 'path' is required for editor.createFile");
    }
    // SECURITY FIX: Validate path before use to prevent directory traversal.
    _validateFilePath(path);
    final controller = SelfInvocationService().editorController;
    await controller.createFile(path);
    return <String, dynamic>{'file': path, 'status': 'created'};
  }
}

class _EditorOpenFileHandler implements SelfActionHandler {
  @override
  String get description => 'Open an existing file in the editor';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final path = params['path'] as String?;
    if (path == null || path.isEmpty) {
      throw ArgumentError("Parameter 'path' is required for editor.openFile");
    }
    // SECURITY FIX: Validate path before use to prevent directory traversal.
    _validateFilePath(path);
    final controller = SelfInvocationService().editorController;
    await controller.openFile(path);
    return <String, dynamic>{'file': path, 'status': 'opened'};
  }
}

class _EditorWriteCodeHandler implements SelfActionHandler {
  @override
  String get description => 'Write (replace) code in the currently open file';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final path = params['path'] as String?;
    final code = params['code'] as String?;
    if (path == null || code == null) {
      throw ArgumentError(
          "Parameters 'path' and 'code' are required for editor.writeCode");
    }
    // SECURITY FIX: Validate path before use.
    _validateFilePath(path);
    final controller = SelfInvocationService().editorController;
    await controller.openFile(path);
    await controller.writeCode(code);
    final lineCount = code.split('\n').length;
    return <String, dynamic>{
      'file': path,
      'lines': lineCount,
      'chars': code.length,
      'status': 'written',
    };
  }
}

class _EditorInsertCodeHandler implements SelfActionHandler {
  @override
  String get description => 'Insert code at a specific position';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final path = params['path'] as String?;
    final code = params['code'] as String?;
    final line = params['line'] as int? ?? 0;
    final column = params['column'] as int? ?? 0;
    if (path == null || code == null) {
      throw ArgumentError(
          "Parameters 'path' and 'code' are required for editor.insertCode");
    }
    // SECURITY FIX: Validate path before use.
    _validateFilePath(path);
    final controller = SelfInvocationService().editorController;
    await controller.openFile(path);
    await controller.insertCode(code, line: line, column: column);
    return <String, dynamic>{
      'file': path,
      'insertedAt': {'line': line, 'column': column},
      'charsInserted': code.length,
      'status': 'inserted',
    };
  }
}

class _EditorDeleteRangeHandler implements SelfActionHandler {
  @override
  String get description => 'Delete a range of lines or characters';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final path = params['path'] as String?;
    final startLine = params['startLine'] as int?;
    final endLine = params['endLine'] as int?;
    if (path == null || startLine == null || endLine == null) {
      throw ArgumentError(
          "Parameters 'path', 'startLine', 'endLine' required for editor.deleteRange");
    }
    // SECURITY FIX: Validate path before use.
    _validateFilePath(path);
    final controller = SelfInvocationService().editorController;
    await controller.openFile(path);
    await controller.deleteRange(startLine, endLine);
    return <String, dynamic>{
      'file': path,
      'deletedRange': {'startLine': startLine, 'endLine': endLine},
      'status': 'deleted',
    };
  }
}

class _EditorSelectAllHandler implements SelfActionHandler {
  @override
  String get description => 'Select all text in the current editor';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final controller = SelfInvocationService().editorController;
    controller.selectAll();
    return <String, dynamic>{'status': 'all_selected'};
  }
}

class _EditorFormatHandler implements SelfActionHandler {
  @override
  String get description => 'Format the current file (DartFmt / Prettier)';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final path = params['path'] as String?;
    if (path == null) {
      throw ArgumentError("Parameter 'path' is required for editor.format");
    }
    final controller = SelfInvocationService().editorController;
    await controller.openFile(path);
    await controller.formatDocument();
    return <String, dynamic>{'file': path, 'status': 'formatted'};
  }
}

class _EditorSaveHandler implements SelfActionHandler {
  @override
  String get description => 'Save the currently open file';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final path = params['path'] as String?;
    final controller = SelfInvocationService().editorController;
    if (path != null) {
      await controller.openFile(path);
    }
    await controller.saveFile();
    return <String, dynamic>{
      'file': path ?? controller.currentFilePath,
      'status': 'saved',
    };
  }
}

class _EditorCloseFileHandler implements SelfActionHandler {
  @override
  String get description => 'Close the currently open file';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final path = params['path'] as String?;
    final controller = SelfInvocationService().editorController;
    if (path != null) {
      await controller.closeFile(path);
    } else {
      await controller.closeCurrentFile();
    }
    return <String, dynamic>{'file': path, 'status': 'closed'};
  }
}

class _EditorGoToLineHandler implements SelfActionHandler {
  @override
  String get description => 'Jump cursor to a specific line number';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final line = params['line'] as int?;
    if (line == null) {
      throw ArgumentError("Parameter 'line' is required for editor.goToLine");
    }
    final controller = SelfInvocationService().editorController;
    controller.goToLine(line);
    return <String, dynamic>{'line': line, 'status': 'navigated'};
  }
}

class _EditorFindHandler implements SelfActionHandler {
  @override
  String get description => 'Find text in the current file';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final query = params['query'] as String?;
    if (query == null) {
      throw ArgumentError("Parameter 'query' is required for editor.find");
    }
    final controller = SelfInvocationService().editorController;
    final matches = controller.findText(query);
    return <String, dynamic>{
      'query': query,
      'matches': matches,
      'status': 'found',
    };
  }
}

class _EditorReplaceHandler implements SelfActionHandler {
  @override
  String get description => 'Replace text in the current file';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final find = params['find'] as String?;
    final replace = params['replace'] as String?;
    final all = params['all'] as bool? ?? false;
    if (find == null || replace == null) {
      throw ArgumentError(
          "Parameters 'find' and 'replace' are required for editor.replace");
    }
    final controller = SelfInvocationService().editorController;
    final count = all
        ? controller.replaceAll(find, replace)
        : controller.replaceFirst(find, replace);
    return <String, dynamic>{
      'find': find,
      'replace': replace,
      'replacements': count,
      'all': all,
      'status': 'replaced',
    };
  }
}

// ---------------------------------------------------------------------------
// Terminal Handlers
// ---------------------------------------------------------------------------

class _TerminalRunHandler implements SelfActionHandler {
  @override
  String get description => 'Run a command in the integrated terminal';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final command = params['command'] as String?;
    if (command == null || command.isEmpty) {
      throw ArgumentError("Parameter 'command' is required for terminal.run");
    }
    final workingDir = params['workingDir'] as String?;
    final timeout = params['timeout'] as int? ?? 30000;
    final controller = SelfInvocationService().terminalController;
    final result = await controller.runCommand(
      command,
      workingDir: workingDir,
      timeout: Duration(milliseconds: timeout),
    );
    return <String, dynamic>{
      'command': command,
      'exitCode': result.exitCode,
      'output': result.output,
      'stderr': result.stderr,
      'status': result.exitCode == 0 ? 'success' : 'error',
    };
  }
}

class _TerminalKillHandler implements SelfActionHandler {
  @override
  String get description => 'Kill the running terminal process';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final controller = SelfInvocationService().terminalController;
    final killed = await controller.killProcess();
    return <String, dynamic>{'killed': killed, 'status': 'process_killed'};
  }
}

class _TerminalClearHandler implements SelfActionHandler {
  @override
  String get description => 'Clear the terminal output';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final controller = SelfInvocationService().terminalController;
    controller.clearOutput();
    return <String, dynamic>{'status': 'cleared'};
  }
}

// ---------------------------------------------------------------------------
// Project Handlers
// ---------------------------------------------------------------------------

class _ProjectCreateHandler implements SelfActionHandler {
  @override
  String get description => 'Create a new Flutter / Dart project';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final name = params['name'] as String?;
    final template = params['template'] as String? ?? 'app';
    if (name == null || name.isEmpty) {
      throw ArgumentError("Parameter 'name' is required for project.create");
    }
    final service = SelfInvocationService().projectService;
    final path = await service.createProject(name, template: template);
    return <String, dynamic>{
      'name': name,
      'template': template,
      'path': path,
      'status': 'created',
    };
  }
}

class _ProjectOpenHandler implements SelfActionHandler {
  @override
  String get description => 'Open an existing project folder';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final path = params['path'] as String?;
    if (path == null || path.isEmpty) {
      throw ArgumentError("Parameter 'path' is required for project.open");
    }
    final service = SelfInvocationService().projectService;
    await service.openProject(path);
    return <String, dynamic>{'path': path, 'status': 'opened'};
  }
}

class _ProjectAddFileHandler implements SelfActionHandler {
  @override
  String get description => 'Add a new file to the project';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final path = params['path'] as String?;
    final content = params['content'] as String? ?? '';
    if (path == null || path.isEmpty) {
      throw ArgumentError("Parameter 'path' is required for project.addFile");
    }
    final service = SelfInvocationService().projectService;
    await service.addFile(path, content: content);
    return <String, dynamic>{
      'path': path,
      'contentLength': content.length,
      'status': 'added',
    };
  }
}

class _ProjectDeleteFileHandler implements SelfActionHandler {
  @override
  String get description => 'Delete a file from the project';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final path = params['path'] as String?;
    if (path == null || path.isEmpty) {
      throw ArgumentError(
          "Parameter 'path' is required for project.deleteFile");
    }
    final service = SelfInvocationService().projectService;
    await service.deleteFile(path);
    return <String, dynamic>{'path': path, 'status': 'deleted'};
  }
}

class _ProjectRenameFileHandler implements SelfActionHandler {
  @override
  String get description => 'Rename / move a file in the project';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final oldPath = params['oldPath'] as String?;
    final newPath = params['newPath'] as String?;
    if (oldPath == null || newPath == null) {
      throw ArgumentError(
          "Parameters 'oldPath' and 'newPath' are required for project.renameFile");
    }
    final service = SelfInvocationService().projectService;
    await service.renameFile(oldPath, newPath);
    return <String, dynamic>{
      'oldPath': oldPath,
      'newPath': newPath,
      'status': 'renamed',
    };
  }
}

// ---------------------------------------------------------------------------
// Git Handlers
// ---------------------------------------------------------------------------

class _GitInitHandler implements SelfActionHandler {
  @override
  String get description => 'Initialize a Git repository';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final service = SelfInvocationService().gitService;
    await service.init();
    return <String, dynamic>{'status': 'initialized'};
  }
}

class _GitAddHandler implements SelfActionHandler {
  @override
  String get description => 'Stage files for commit';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final files = params['files'] as List<dynamic>?;
    final service = SelfInvocationService().gitService;
    if (files == null || files.isEmpty) {
      await service.stageAll();
      return <String, dynamic>{'staged': 'all', 'status': 'staged'};
    } else {
      for (final file in files) {
        await service.stage(file as String);
      }
      return <String, dynamic>{
        'files': files,
        'status': 'staged',
      };
    }
  }
}

class _GitCommitHandler implements SelfActionHandler {
  @override
  String get description => 'Commit staged changes';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final message = params['message'] as String?;
    if (message == null || message.isEmpty) {
      throw ArgumentError(
          "Parameter 'message' is required for git.commit");
    }
    final service = SelfInvocationService().gitService;
    await service.stageAll();
    await service.commit(message);
    return <String, dynamic>{'message': message, 'status': 'committed'};
  }
}

class _GitPushHandler implements SelfActionHandler {
  @override
  String get description => 'Push commits to remote';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final remote = params['remote'] as String? ?? 'origin';
    final branch = params['branch'] as String?;
    final service = SelfInvocationService().gitService;
    await service.push(remote: remote, branch: branch);
    return <String, dynamic>{
      'remote': remote,
      'branch': branch,
      'status': 'pushed',
    };
  }
}

class _GitPullHandler implements SelfActionHandler {
  @override
  String get description => 'Pull latest changes from remote';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final remote = params['remote'] as String? ?? 'origin';
    final branch = params['branch'] as String?;
    final service = SelfInvocationService().gitService;
    final result = await service.pull(remote: remote, branch: branch);
    return <String, dynamic>{
      'remote': remote,
      'branch': branch,
      'output': result,
      'status': 'pulled',
    };
  }
}

class _GitStatusHandler implements SelfActionHandler {
  @override
  String get description => 'Get working tree status';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final service = SelfInvocationService().gitService;
    final status = await service.status();
    return <String, dynamic>{
      'branch': status.branch,
      'ahead': status.ahead,
      'behind': status.behind,
      'modified': status.modified,
      'staged': status.staged,
      'untracked': status.untracked,
      'status': 'ok',
    };
  }
}

class _GitCreateBranchHandler implements SelfActionHandler {
  @override
  String get description => 'Create and check out a new branch';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final name = params['name'] as String?;
    if (name == null || name.isEmpty) {
      throw ArgumentError(
          "Parameter 'name' is required for git.createBranch");
    }
    final service = SelfInvocationService().gitService;
    await service.createBranch(name);
    return <String, dynamic>{'branch': name, 'status': 'created'};
  }
}

class _GitSwitchBranchHandler implements SelfActionHandler {
  @override
  String get description => 'Switch to an existing branch';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final name = params['name'] as String?;
    if (name == null || name.isEmpty) {
      throw ArgumentError(
          "Parameter 'name' is required for git.switchBranch");
    }
    final service = SelfInvocationService().gitService;
    await service.switchBranch(name);
    return <String, dynamic>{'branch': name, 'status': 'switched'};
  }
}

// ---------------------------------------------------------------------------
// GitHub Handlers
// ---------------------------------------------------------------------------

class _GithubCreateRepoHandler implements SelfActionHandler {
  @override
  String get description => 'Create a new GitHub repository';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final name = params['name'] as String?;
    final description = params['description'] as String? ?? '';
    final isPrivate = params['private'] as bool? ?? false;
    if (name == null || name.isEmpty) {
      throw ArgumentError(
          "Parameter 'name' is required for github.createRepo");
    }
    final service = SelfInvocationService().githubService;
    final repo = await service.createRepo(
      name: name,
      description: description,
      private: isPrivate,
    );
    return <String, dynamic>{
      'name': name,
      'url': repo['html_url'],
      'private': isPrivate,
      'status': 'created',
    };
  }
}

class _GithubPushFileHandler implements SelfActionHandler {
  @override
  String get description => 'Push a file to a GitHub repository';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final repo = params['repo'] as String?;
    final path = params['path'] as String?;
    final content = params['content'] as String?;
    final message = params['message'] as String? ?? 'Update via MobileCode';
    final branch = params['branch'] as String? ?? 'main';
    if (repo == null || path == null || content == null) {
      throw ArgumentError(
          "Parameters 'repo', 'path', 'content' are required for github.pushFile");
    }
    final service = SelfInvocationService().githubService;
    await service.pushFile(
      repo: repo,
      path: path,
      content: content,
      message: message,
      branch: branch,
    );
    return <String, dynamic>{
      'repo': repo,
      'path': path,
      'branch': branch,
      'status': 'pushed',
    };
  }
}

class _GithubCreateIssueHandler implements SelfActionHandler {
  @override
  String get description => 'Create a GitHub issue';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final repo = params['repo'] as String?;
    final title = params['title'] as String?;
    final body = params['body'] as String? ?? '';
    final labels = params['labels'] as List<dynamic>?;
    if (repo == null || title == null) {
      throw ArgumentError(
          "Parameters 'repo' and 'title' are required for github.createIssue");
    }
    final service = SelfInvocationService().githubService;
    final issue = await service.createIssue(
      repo: repo,
      title: title,
      body: body,
      labels: labels?.cast<String>(),
    );
    return <String, dynamic>{
      'repo': repo,
      'issueNumber': issue['number'],
      'url': issue['html_url'],
      'status': 'created',
    };
  }
}

class _GithubCreatePRHandler implements SelfActionHandler {
  @override
  String get description => 'Create a GitHub pull request';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final repo = params['repo'] as String?;
    final title = params['title'] as String?;
    final head = params['head'] as String?;
    final base = params['base'] as String? ?? 'main';
    final body = params['body'] as String? ?? '';
    if (repo == null || title == null || head == null) {
      throw ArgumentError(
          "Parameters 'repo', 'title', 'head' are required for github.createPR");
    }
    final service = SelfInvocationService().githubService;
    final pr = await service.createPullRequest(
      repo: repo,
      title: title,
      head: head,
      base: base,
      body: body,
    );
    return <String, dynamic>{
      'repo': repo,
      'prNumber': pr['number'],
      'url': pr['html_url'],
      'status': 'created',
    };
  }
}

// ---------------------------------------------------------------------------
// Navigation Handlers
// ---------------------------------------------------------------------------

class _NavNavigateHandler implements SelfActionHandler {
  @override
  String get description => 'Navigate to a named route / screen';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final route = params['route'] as String?;
    if (route == null || route.isEmpty) {
      throw ArgumentError(
          "Parameter 'route' is required for navigation.navigate");
    }
    await NavigationController.navigateTo(route);
    return <String, dynamic>{'route': route, 'status': 'navigated'};
  }
}

class _NavGoBackHandler implements SelfActionHandler {
  @override
  String get description => 'Go back to the previous screen';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final result = NavigationController.goBack();
    return <String, dynamic>{'success': result, 'status': 'went_back'};
  }
}

class _NavOpenDrawerHandler implements SelfActionHandler {
  @override
  String get description => 'Open the side navigation drawer';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    NavigationController.openDrawer();
    return <String, dynamic>{'status': 'drawer_opened'};
  }
}

class _NavCloseDrawerHandler implements SelfActionHandler {
  @override
  String get description => 'Close the side navigation drawer';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    NavigationController.closeDrawer();
    return <String, dynamic>{'status': 'drawer_closed'};
  }
}

// ---------------------------------------------------------------------------
// AI Handlers
// ---------------------------------------------------------------------------

class _AIChatHandler implements SelfActionHandler {
  @override
  String get description => 'Send a chat message to the AI assistant';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final message = params['message'] as String?;
    if (message == null || message.isEmpty) {
      throw ArgumentError("Parameter 'message' is required for ai.chat");
    }
    final service = SelfInvocationService().llmService;
    final response = await service.chat(message);
    return <String, dynamic>{
      'response': response,
      'messageLength': message.length,
      'status': 'completed',
    };
  }
}

class _AIGenerateCodeHandler implements SelfActionHandler {
  @override
  String get description => 'Ask the AI to generate code';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final prompt = params['prompt'] as String?;
    final language = params['language'] as String? ?? 'dart';
    if (prompt == null || prompt.isEmpty) {
      throw ArgumentError("Parameter 'prompt' is required for ai.generateCode");
    }
    final service = SelfInvocationService().llmService;
    final code = await service.generateCode(prompt, language: language);
    return <String, dynamic>{
      'code': code,
      'language': language,
      'lines': code.split('\n').length,
      'status': 'generated',
    };
  }
}

class _AIExplainCodeHandler implements SelfActionHandler {
  @override
  String get description => 'Ask the AI to explain code';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final code = params['code'] as String?;
    if (code == null || code.isEmpty) {
      throw ArgumentError("Parameter 'code' is required for ai.explainCode");
    }
    final service = SelfInvocationService().llmService;
    final explanation = await service.explainCode(code);
    return <String, dynamic>{
      'explanation': explanation,
      'codeLength': code.length,
      'status': 'explained',
    };
  }
}

class _AIFixCodeHandler implements SelfActionHandler {
  @override
  String get description => 'Ask the AI to fix / debug code';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final code = params['code'] as String?;
    final error = params['error'] as String?;
    if (code == null || code.isEmpty) {
      throw ArgumentError("Parameter 'code' is required for ai.fixCode");
    }
    final service = SelfInvocationService().llmService;
    final fixed = await service.fixCode(code, error: error);
    return <String, dynamic>{
      'fixedCode': fixed,
      'originalLength': code.length,
      'fixedLength': fixed.length,
      'status': 'fixed',
    };
  }
}

class _AIOptimizeCodeHandler implements SelfActionHandler {
  @override
  String get description => 'Ask the AI to optimize code for performance';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final code = params['code'] as String?;
    if (code == null || code.isEmpty) {
      throw ArgumentError(
          "Parameter 'code' is required for ai.optimizeCode");
    }
    final service = SelfInvocationService().llmService;
    final optimized = await service.optimizeCode(code);
    return <String, dynamic>{
      'optimizedCode': optimized,
      'originalLength': code.length,
      'optimizedLength': optimized.length,
      'status': 'optimized',
    };
  }
}

class _AIAddCommentsHandler implements SelfActionHandler {
  @override
  String get description => 'Ask the AI to add documentation comments';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final code = params['code'] as String?;
    if (code == null || code.isEmpty) {
      throw ArgumentError(
          "Parameter 'code' is required for ai.addComments");
    }
    final service = SelfInvocationService().llmService;
    final commented = await service.addComments(code);
    return <String, dynamic>{
      'commentedCode': commented,
      'status': 'commented',
    };
  }
}

// ---------------------------------------------------------------------------
// UI Handlers
// ---------------------------------------------------------------------------

class _UIShowToastHandler implements SelfActionHandler {
  @override
  String get description => 'Show a toast message on screen';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final message = params['message'] as String?;
    final duration = params['duration'] as int? ?? 2000;
    if (message == null || message.isEmpty) {
      throw ArgumentError(
          "Parameter 'message' is required for ui.showToast");
    }
    NavigationController.showToast(message, duration: duration);
    return <String, dynamic>{'shown': true, 'message': message};
  }
}

class _UIShowDialogHandler implements SelfActionHandler {
  @override
  String get description => 'Show an alert dialog';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final title = params['title'] as String? ?? 'MobileCode';
    final message = params['message'] as String?;
    if (message == null || message.isEmpty) {
      throw ArgumentError(
          "Parameter 'message' is required for ui.showDialog");
    }
    final confirmText = params['confirmText'] as String? ?? 'OK';
    final cancelText = params['cancelText'] as String?;
    final result = await NavigationController.showDialog(
      title: title,
      message: message,
      confirmText: confirmText,
      cancelText: cancelText,
    );
    return <String, dynamic>{
      'confirmed': result,
      'title': title,
      'message': message,
    };
  }
}

class _UIShowSnackbarHandler implements SelfActionHandler {
  @override
  String get description => 'Show a snackbar message at the bottom';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final message = params['message'] as String?;
    final actionLabel = params['actionLabel'] as String?;
    if (message == null || message.isEmpty) {
      throw ArgumentError(
          "Parameter 'message' is required for ui.showSnackbar");
    }
    NavigationController.showSnackbar(
      message,
      actionLabel: actionLabel,
    );
    return <String, dynamic>{'shown': true, 'message': message};
  }
}

class _UIVibrateHandler implements SelfActionHandler {
  @override
  String get description => 'Trigger device haptic feedback';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final type = params['type'] as String? ?? 'light';
    switch (type) {
      case 'heavy':
        await HapticFeedback.heavyImpact();
      case 'medium':
        await HapticFeedback.mediumImpact();
      case 'light':
        await HapticFeedback.lightImpact();
      case 'success':
        await HapticFeedback.selectionClick();
      case 'error':
        await HapticFeedback.vibrate();
      default:
        await HapticFeedback.lightImpact();
    }
    return <String, dynamic>{'type': type, 'status': 'vibrated'};
  }
}

class _UIPlaySoundHandler implements SelfActionHandler {
  @override
  String get description => 'Play a system sound';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final soundId = params['soundId'] as int? ?? 1104; // default beep
    // SystemSound.play(SystemSoundType.alert); // simplified
    await SystemSound.play(SystemSoundType.alert);
    return <String, dynamic>{'soundId': soundId, 'status': 'played'};
  }
}

class _UISetBrightnessHandler implements SelfActionHandler {
  @override
  String get description => 'Set screen brightness (0.0 - 1.0)';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final brightness = params['brightness'] as double?;
    if (brightness == null) {
      throw ArgumentError(
          "Parameter 'brightness' is required for ui.setBrightness");
    }
    // Platform channel or screen_brightness plugin would go here
    NavigationController.setBrightness(brightness);
    return <String, dynamic>{
      'brightness': brightness,
      'status': 'set',
    };
  }
}

// ---------------------------------------------------------------------------
// File Handlers
// ---------------------------------------------------------------------------

class _FileReadHandler implements SelfActionHandler {
  @override
  String get description => 'Read a file from disk';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final path = params['path'] as String?;
    if (path == null || path.isEmpty) {
      throw ArgumentError("Parameter 'path' is required for file.read");
    }
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('File not found', path);
    }
    final content = await file.readAsString();
    return <String, dynamic>{
      'path': path,
      'content': content,
      'size': content.length,
      'lines': content.split('\n').length,
      'status': 'read',
    };
  }
}

class _FileWriteHandler implements SelfActionHandler {
  @override
  String get description => 'Write content to a file on disk';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final path = params['path'] as String?;
    final content = params['content'] as String?;
    if (path == null || content == null) {
      throw ArgumentError(
          "Parameters 'path' and 'content' are required for file.write");
    }
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return <String, dynamic>{
      'path': path,
      'size': content.length,
      'lines': content.split('\n').length,
      'status': 'written',
    };
  }
}

class _FileDeleteHandler implements SelfActionHandler {
  @override
  String get description => 'Delete a file from disk';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final path = params['path'] as String?;
    if (path == null || path.isEmpty) {
      throw ArgumentError("Parameter 'path' is required for file.delete");
    }
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    return <String, dynamic>{'path': path, 'status': 'deleted'};
  }
}

class _FileExistsHandler implements SelfActionHandler {
  @override
  String get description => 'Check whether a file exists';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final path = params['path'] as String?;
    if (path == null || path.isEmpty) {
      throw ArgumentError("Parameter 'path' is required for file.exists");
    }
    final exists = await File(path).exists();
    return <String, dynamic>{'path': path, 'exists': exists};
  }
}

class _FileListHandler implements SelfActionHandler {
  @override
  String get description => 'List files in a directory';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final path = params['path'] as String?;
    final recursive = params['recursive'] as bool? ?? false;
    if (path == null || path.isEmpty) {
      throw ArgumentError("Parameter 'path' is required for file.list");
    }
    final dir = Directory(path);
    if (!await dir.exists()) {
      return <String, dynamic>{
        'path': path,
        'files': <String>[],
        'error': 'Directory does not exist',
      };
    }
    final entities = await dir.list(recursive: recursive).toList();
    final files = entities
        .whereType<File>()
        .map((f) => f.path)
        .toList()
      ..sort();
    return <String, dynamic>{
      'path': path,
      'recursive': recursive,
      'files': files,
      'count': files.length,
      'status': 'listed',
    };
  }
}

class _FileCopyHandler implements SelfActionHandler {
  @override
  String get description => 'Copy a file from source to destination';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final source = params['source'] as String?;
    final dest = params['dest'] as String?;
    if (source == null || dest == null) {
      throw ArgumentError(
          "Parameters 'source' and 'dest' are required for file.copy");
    }
    await File(source).copy(dest);
    return <String, dynamic>{
      'source': source,
      'dest': dest,
      'status': 'copied',
    };
  }
}

class _FileMoveHandler implements SelfActionHandler {
  @override
  String get description => 'Move / rename a file';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final source = params['source'] as String?;
    final dest = params['dest'] as String?;
    if (source == null || dest == null) {
      throw ArgumentError(
          "Parameters 'source' and 'dest' are required for file.move");
    }
    await File(source).rename(dest);
    return <String, dynamic>{
      'source': source,
      'dest': dest,
      'status': 'moved',
    };
  }
}

// ---------------------------------------------------------------------------
// Settings Handlers
// ---------------------------------------------------------------------------

class _SettingsSetHandler implements SelfActionHandler {
  @override
  String get description => 'Set a configuration value';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final key = params['key'] as String?;
    final value = params['value'];
    if (key == null || value == null) {
      throw ArgumentError(
          "Parameters 'key' and 'value' are required for settings.set");
    }
    final service = SelfInvocationService().settingsService;
    await service.setValue(key, value);
    return <String, dynamic>{
      'key': key,
      'value': value,
      'status': 'set',
    };
  }
}

class _SettingsGetHandler implements SelfActionHandler {
  @override
  String get description => 'Get a configuration value';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final key = params['key'] as String?;
    final defaultValue = params['default'];
    if (key == null || key.isEmpty) {
      throw ArgumentError("Parameter 'key' is required for settings.get");
    }
    final service = SelfInvocationService().settingsService;
    final value = await service.getValue(key, defaultValue: defaultValue);
    return <String, dynamic>{
      'key': key,
      'value': value,
      'status': 'retrieved',
    };
  }
}

class _SettingsResetHandler implements SelfActionHandler {
  @override
  String get description => 'Reset all settings to defaults';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final service = SelfInvocationService().settingsService;
    await service.resetToDefaults();
    return <String, dynamic>{'status': 'reset'};
  }
}

class _SettingsExportHandler implements SelfActionHandler {
  @override
  String get description => 'Export settings as JSON';

  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final service = SelfInvocationService().settingsService;
    final allSettings = await service.exportAll();
    return <String, dynamic>{
      'settings': allSettings,
      'status': 'exported',
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Security Helpers
// ═══════════════════════════════════════════════════════════════════════════

/// Validates that a file path is safe (no directory traversal).
///
/// SECURITY: Prevents directory traversal attacks via ../ sequences
/// or absolute paths outside the project directory.
void _validateFilePath(String path) {
  if (path.isEmpty) {
    throw ArgumentError('Path cannot be empty');
  }
  // Reject directory traversal sequences.
  if (path.contains('../') || path.contains('..\\')) {
    throw ArgumentError(
        'Path contains directory traversal sequences which are not allowed');
  }
  // Reject absolute paths that could access system files.
  if (path.startsWith('/etc/') ||
      path.startsWith('/proc/') ||
      path.startsWith('/sys/') ||
      path.startsWith('/root/') ||
      path.startsWith('C:\\Windows') ||
      path.startsWith('C:\\Program')) {
    throw ArgumentError('Absolute system paths are not allowed');
  }
  // Reject null bytes (common in injection attacks).
  if (path.contains('\x00')) {
    throw ArgumentError('Path contains null bytes');
  }
}
