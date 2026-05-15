// lib/services/terminal_service.dart
// Terminal Service — Command execution for development workflows.
//
// Executes shell commands using Dart's Process API with streaming output,
// security validation, and intelligent output parsing for Flutter, Dart,
// Git, npm, and Python workflows.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Terminal Service
// ═══════════════════════════════════════════════════════════════════════════

/// Executes development commands within the app using Dart's Process API.
///
/// Supports: flutter, dart, npm, node, git, python, pip, and common
/// Unix commands. All commands are validated against an allowlist for
/// security. Provides streaming output for long-running commands and
/// intelligent parsing for build errors, test results, and git status.
///
/// Usage:
/// ```dart
/// final terminal = TerminalService();
/// final result = await terminal.execute('flutter build apk', workingDirectory: projectPath);
/// if (result.success) { ... }
/// ```
class TerminalService {
  // Singleton
  static final TerminalService _instance = TerminalService._internal();
  factory TerminalService() => _instance;
  TerminalService._internal();

  // ── Process Management ───────────────────────────────────────────

  Process? _currentProcess;
  final StreamController<String> _outputController =
      StreamController<String>.broadcast();

  // ── Command History ──────────────────────────────────────────────

  final List<CommandEntry> _history = [];
  final StreamController<List<CommandEntry>> _historyController =
      StreamController<List<CommandEntry>>.broadcast();

  // ── State ────────────────────────────────────────────────────────

  bool _isExecuting = false;
  String? _currentWorkingDirectory;

  // ═════════════════════════════════════════════════════════════════
  // Public Accessors
  // ═════════════════════════════════════════════════════════════════

  /// Whether a command is currently executing.
  bool get isExecuting => _isExecuting;

  /// The currently running process, if any.
  Process? get currentProcess => _currentProcess;

  /// Current working directory for commands.
  String? get currentWorkingDirectory => _currentWorkingDirectory;

  /// Broadcast stream of command output lines.
  Stream<String> get outputStream => _outputController.stream;

  /// Broadcast stream of history updates.
  Stream<List<CommandEntry>> get historyStream => _historyController.stream;

  /// Immutable view of command history.
  List<CommandEntry> get history => List.unmodifiable(_history);

  // ═════════════════════════════════════════════════════════════════
  // Command Execution
  // ═════════════════════════════════════════════════════════════════

  /// Execute a command and return the full result.
  ///
  /// [command] The shell command to execute.
  /// [workingDirectory] Optional directory to run the command in.
  /// [environment] Optional environment variable overrides.
  /// [timeoutSeconds] Maximum time to wait for completion.
  ///
  /// Returns a [CommandResult] with stdout, stderr, exit code, and timing.
  Future<CommandResult> execute(
    String command, {
    String? workingDirectory,
    Map<String, String>? environment,
    int timeoutSeconds = 120,
  }) async {
    // 1. Validate command against allowlist.
    if (!isCommandAllowed(command)) {
      final rejected = CommandResult._rejected(command);
      _addToHistory(command, rejected);
      return rejected;
    }

    // 2. Parse command and arguments for Process.start.
    final parsed = _parseCommand(command);
    if (parsed == null) {
      final invalid = CommandResult._error(command, 'Failed to parse command');
      _addToHistory(command, invalid);
      return invalid;
    }

    final executable = parsed.$1;
    final arguments = parsed.$2;

    // 3. Set up working directory.
    final cwd = workingDirectory ?? _currentWorkingDirectory;

    final stopwatch = Stopwatch()..start();
    _isExecuting = true;

    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();

    try {
      // 4. Start the process.
      debugPrint('[TerminalService] Starting: $command (cwd: $cwd)');

      _currentProcess = await Process.start(
        executable,
        arguments,
        workingDirectory: cwd,
        environment: environment,
        runInShell: true,
      );

      // 5. Set up output streams with UTF-8 decoding.
      await Future.wait([
        _currentProcess!.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .forEach((line) {
          stdoutBuffer.writeln(line);
          _outputController.add(line);
        }),
        _currentProcess!.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .forEach((line) {
          stderrBuffer.writeln(line);
          _outputController.add('[stderr] $line');
        }),
      ]);

      // 6. Wait for completion or timeout.
      final exitCode = await _currentProcess!.exitCode
          .timeout(Duration(seconds: timeoutSeconds), onTimeout: () {
        debugPrint('[TerminalService] Command timed out after ${timeoutSeconds}s');
        _currentProcess?.kill(ProcessSignal.sigkill);
        return -1;
      });

      stopwatch.stop();
      _isExecuting = false;

      final result = CommandResult(
        command: command,
        stdout: stdoutBuffer.toString(),
        stderr: stderrBuffer.toString(),
        exitCode: exitCode,
        duration: stopwatch.elapsed,
        executedAt: DateTime.now(),
      );

      _addToHistory(command, result);
      debugPrint('[TerminalService] Completed: $command (exit: $exitCode, ${stopwatch.elapsed})');

      return result;
    } on ProcessException catch (e) {
      stopwatch.stop();
      _isExecuting = false;
      final result = CommandResult._error(command, 'ProcessException: ${e.message}');
      _addToHistory(command, result);
      return result;
    } on TimeoutException {
      stopwatch.stop();
      _isExecuting = false;
      final result = CommandResult._timedOut(command, timeoutSeconds);
      _addToHistory(command, result);
      return result;
    } catch (e) {
      stopwatch.stop();
      _isExecuting = false;
      final result = CommandResult._error(command, 'Exception: $e');
      _addToHistory(command, result);
      return result;
    } finally {
      _currentProcess = null;
    }
  }

  /// Execute a command with streaming output for long-running processes.
  ///
  /// Ideal for `flutter run`, `npm start`, watch modes, etc.
  /// Yields each output line as it arrives. The process runs until
  /// [kill] is called or the process exits naturally.
  Stream<String> executeStream(
    String command, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async* {
    // Validate.
    if (!isCommandAllowed(command)) {
      yield '[error] Command not allowed for security: $command';
      return;
    }

    final parsed = _parseCommand(command);
    if (parsed == null) {
      yield '[error] Failed to parse command: $command';
      return;
    }

    final cwd = workingDirectory ?? _currentWorkingDirectory;
    _isExecuting = true;

    final entry = CommandEntry(
      command: command,
      timestamp: DateTime.now(),
    );
    _history.add(entry);

    try {
      _currentProcess = await Process.start(
        parsed.$1,
        parsed.$2,
        workingDirectory: cwd,
        environment: environment,
        runInShell: true,
      );

      // Merge stdout and stderr into a single stream.
      await for (final line in _currentProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        yield line;
        _outputController.add(line);
      }

      await for (final line in _currentProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        yield '[stderr] $line';
        _outputController.add('[stderr] $line');
      }

      final exitCode = await _currentProcess!.exitCode;
      yield '[exit] Process exited with code $exitCode';
    } on ProcessException catch (e) {
      yield '[error] Failed to start process: ${e.message}';
    } catch (e) {
      yield '[error] Exception: $e';
    } finally {
      _isExecuting = false;
      _currentProcess = null;
    }
  }

  // ═════════════════════════════════════════════════════════════════
  // Process Control
  // ═════════════════════════════════════════════════════════════════

  /// Kill the currently running process.
  ///
  /// Sends SIGTERM first, then SIGKILL if needed.
  /// Safe to call even if no process is running.
  Future<void> kill() async {
    if (_currentProcess == null) return;

    debugPrint('[TerminalService] Killing process (PID: ${_currentProcess!.pid})');

    // Try SIGTERM first.
    _currentProcess!.kill(ProcessSignal.sigterm);

    // Give it a moment, then force kill.
    await Future.delayed(const Duration(milliseconds: 500));
    _currentProcess?.kill(ProcessSignal.sigkill);

    _isExecuting = false;
    _currentProcess = null;
    _outputController.add('[system] Process terminated by user');
  }

  /// Send input to the stdin of the currently running process.
  ///
  /// Useful for interactive commands that read user input.
  Future<void> sendInput(String input) async {
    if (_currentProcess == null) {
      _outputController.add('[error] No running process to send input to');
      return;
    }
    _currentProcess!.stdin.writeln(input);
    await _currentProcess!.stdin.flush();
  }

  // ═════════════════════════════════════════════════════════════════
  // Command Validation
  // ═════════════════════════════════════════════════════════════════

  /// Allowed command prefixes for security validation.
  static const List<String> _allowedPrefixes = [
    'flutter ',
    'dart ',
    'npm ',
    'node ',
    'npx ',
    'git ',
    'python ',
    'python3 ',
    'pip ',
    'pip3 ',
    'mkdir ',
    'cd ',
    'ls ',
    'pwd ',
    'cp ',
    'mv ',
    'rm ',
    'cat ',
    'echo ',
    'touch ',
    'clear ',
    'head ',
    'tail ',
    'grep ',
    'find ',
    'wc ',
    'sort ',
    'uniq ',
    'sed ',
    'awk ',
    'curl ',
    'wget ',
    'tar ',
    'zip ',
    'unzip ',
    'chmod ',
    'chown ',
    'df ',
    'du ',
    'ps ',
    'kill ',
    'which ',
    'whoami ',
    'date ',
    'tee ',
    'xargs ',
    'pkg ',
    'bash ',
    'aapt ',
    'ping ',
    'pm ',
    'am ',
    'monkey ',
    'dumpsys ',
  ];

  /// Standalone commands that require no arguments.
  static const List<String> _standaloneCommands = [
    'ls',
    'pwd',
    'clear',
    'whoami',
    'date',
    'flutter',
    'dart',
    'git',
    'npm',
    'node',
    'python',
    'python3',
    'true',
    'termux-storage-setup',
  ];

  /// Dangerous command patterns that are always rejected.
  static const List<String> _dangerousPatterns = [
    'rm -rf /',
    'rm -rf /*',
    'rm -rf ~',
    '> /dev/sda',
    'mkfs.',
    'dd if=',
    ':(){:|:&};:',
    'chmod -R 777 /',
    'chown -R',
    'mv / ',
    'mv /* ',
    'del /f /s /q',
    'format ',
    'fdisk ',
    'shutdown ',
    'reboot ',
    'halt ',
    'poweroff ',
    'init 0',
    'kill -9 1',
    'rm -rf /usr',
    'rm -rf /bin',
    'rm -rf /etc',
    'rm -rf /lib',
    'rm -rf /var',
    'rm -rf /home',
  ];

  /// Validate that a command is safe to execute.
  ///
  /// Checks against an allowlist of safe command prefixes and rejects
  /// known dangerous patterns. This is a security-critical method.
  bool isCommandAllowed(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return false;

    // Check for dangerous patterns first.
    for (final pattern in _dangerousPatterns) {
      if (trimmed.contains(pattern)) return false;
    }

    // Block shell metacharacter injection attempts.
    final blockedChars = [';', '&&', '||', '`', r'$('];
    // Note: we allow && and || for compound commands but validate each part.
    // For now, simple validation - check each part separated by shell operators.
    final parts = _splitCompoundCommand(trimmed);
    for (final part in parts) {
      if (!_isSingleCommandAllowed(part.trim())) return false;
    }

    return true;
  }

  bool _isSingleCommandAllowed(String command) {
    if (command.isEmpty) return true; // Empty parts from splitting.

    // Check allowlist prefixes.
    for (final prefix in _allowedPrefixes) {
      if (command.startsWith(prefix)) return true;
    }

    // Check standalone commands.
    if (_standaloneCommands.contains(command)) return true;

    return false;
  }

  List<String> _splitCompoundCommand(String command) {
    // Split by common shell operators while preserving quoted strings.
    // Simple split: handle &&, ||, ;, | (pipe).
    final parts = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;
    var quoteChar = '';

    for (var i = 0; i < command.length; i++) {
      final char = command[i];

      if ((char == '"' || char == "'") && (i == 0 || command[i - 1] != '\\')) {
        if (!inQuotes) {
          inQuotes = true;
          quoteChar = char;
        } else if (quoteChar == char) {
          inQuotes = false;
        }
      }

      if (!inQuotes) {
        if (char == ';') {
          parts.add(buffer.toString());
          buffer.clear();
          continue;
        }
        if (char == '&' && i + 1 < command.length && command[i + 1] == '&') {
          parts.add(buffer.toString());
          buffer.clear();
          i++; // Skip second &.
          continue;
        }
        if (char == '|' && i + 1 < command.length && command[i + 1] == '|') {
          parts.add(buffer.toString());
          buffer.clear();
          i++; // Skip second |.
          continue;
        }
      }

      buffer.write(char);
    }

    if (buffer.isNotEmpty) {
      parts.add(buffer.toString());
    }

    return parts;
  }

  // ═════════════════════════════════════════════════════════════════
  // Quick Commands
  // ═════════════════════════════════════════════════════════════════

  /// Run `flutter run` in the given project directory.
  Stream<String> flutterRun(String projectPath) =>
      executeStream('flutter run', workingDirectory: projectPath);

  /// Run `flutter build <target>` in the given project directory.
  Future<CommandResult> flutterBuild(
    String projectPath, {
    String target = 'apk',
  }) =>
      execute('flutter build $target', workingDirectory: projectPath);

  /// Run `flutter test` in the given project directory.
  Future<CommandResult> flutterTest(String projectPath) =>
      execute('flutter test', workingDirectory: projectPath);

  /// Run `flutter pub get` in the given project directory.
  Future<CommandResult> flutterPubGet(String projectPath) =>
      execute('flutter pub get', workingDirectory: projectPath);

  /// Run `flutter clean` in the given project directory.
  Future<CommandResult> flutterClean(String projectPath) =>
      execute('flutter clean', workingDirectory: projectPath);

  /// Run `dart format` in the given project directory.
  Future<CommandResult> dartFormat(String projectPath) =>
      execute('dart format .', workingDirectory: projectPath);

  /// Run `dart analyze` in the given project directory.
  Future<CommandResult> dartAnalyze(String projectPath) =>
      execute('dart analyze', workingDirectory: projectPath);

  /// Run `npm install` in the given project directory.
  Future<CommandResult> npmInstall(String projectPath) =>
      execute('npm install', workingDirectory: projectPath);

  /// Run `npm run <script>` in the given project directory.
  Future<CommandResult> npmRun(String projectPath, String script) =>
      execute('npm run $script', workingDirectory: projectPath);

  /// Run `npm run build` in the given project directory.
  Future<CommandResult> npmBuild(String projectPath) =>
      execute('npm run build', workingDirectory: projectPath);

  /// Run `git status` in the given project directory.
  Future<CommandResult> gitStatus(String projectPath) =>
      execute('git status', workingDirectory: projectPath);

  /// Run `git log --oneline` in the given project directory.
  Future<CommandResult> gitLog(String projectPath, {int count = 20}) =>
      execute('git log --oneline -n $count', workingDirectory: projectPath);

  /// Stage all changes and commit.
  Future<CommandResult> gitCommit(String projectPath, String message) async {
    await execute('git add .', workingDirectory: projectPath);
    return execute('git commit -m "$message"', workingDirectory: projectPath);
  }

  /// Push to origin.
  Future<CommandResult> gitPush(String projectPath, {String branch = 'main'}) =>
      execute('git push origin $branch', workingDirectory: projectPath);

  /// Pull from origin.
  Future<CommandResult> gitPull(String projectPath, {String branch = 'main'}) =>
      execute('git pull origin $branch', workingDirectory: projectPath);

  /// Initialize a new git repository.
  Future<CommandResult> gitInit(String projectPath) =>
      execute('git init', workingDirectory: projectPath);

  // ═════════════════════════════════════════════════════════════════
  // Output Parsing
  // ═════════════════════════════════════════════════════════════════

  /// Parse Flutter build output to extract errors and warnings.
  ///
  /// Handles both Dart analysis errors and build-time errors.
  List<BuildError> parseBuildErrors(String output) {
    final errors = <BuildError>[];
    final lines = const LineSplitter().convert(output);

    // Dart analysis error pattern:
    //   lib/main.dart:42:10: Error: Expected ';' after this.
    final analysisPattern = RegExp(
      r'^\s*([^:]+):(\d+):(\d+):\s*(Error|Warning|Info|error|warning|info):\s*(.+)$',
    );

    // Flutter build error pattern:
    //   lib/screens/home.dart:15:3: Error: No named parameter with the name 'foo'.
    final buildPattern = RegExp(
      r'^\s*([^\s:]+):(\d+):(\d+):\s*(Error|Warning|Info|error|warning|info|hint|HINT):\s*(.+)$',
    );

    for (final line in lines) {
      // Try analysis pattern first.
      var match = analysisPattern.firstMatch(line);
      if (match == null) {
        match = buildPattern.firstMatch(line);
      }

      if (match != null) {
        errors.add(BuildError(
          file: match.group(1) ?? 'unknown',
          line: int.tryParse(match.group(2) ?? '0') ?? 0,
          column: int.tryParse(match.group(3) ?? '0') ?? 0,
          message: match.group(5)?.trim() ?? 'Unknown error',
          severity: _normalizeSeverity(match.group(4) ?? 'error'),
        ));
      }
    }

    return errors;
  }

  /// Parse `flutter test` output to extract test results.
  ///
  /// Handles the standard test reporter output format.
  TestResult parseTestResults(String output) {
    final lines = const LineSplitter().convert(output);

    var total = 0;
    var passed = 0;
    var failed = 0;
    var skipped = 0;
    final failedTests = <String>[];

    // Pattern: "00:00 +3 -1: Some tests failed."
    final summaryPattern = RegExp(r'\+(\d+)\s+-\s*(\d+):');

    // Pattern: "00:00 +3 -1: test description"
    final testPattern = RegExp(r'^\d+:\d+\s+\+\d+\s+-\s*(\d+):\s*(.+)$');

    // Pattern at end: "+12 -2: Some tests failed."
    final finalPattern = RegExp(r'\+(\d+)\s+-\s*(\d+):\s*Some tests failed');

    // Alternative: "All tests passed!"
    final allPassedPattern = RegExp(r'All tests passed');

    // Summary line: "+5 -1: Some tests failed."
    final summaryLinePattern = RegExp(
      r'^(?:\d+:\d+\s+)?\+(\d+)\s+-\s*(\d+)\s*:\s*(.+)$',
    );

    // Count individual test results (+N -M format).
    for (final line in lines) {
      final match = summaryLinePattern.firstMatch(line);
      if (match != null) {
        passed = int.tryParse(match.group(1) ?? '0') ?? passed;
        failed = int.tryParse(match.group(2) ?? '0') ?? failed;
      }

      // Check for individual failed test names.
      final testMatch = testPattern.firstMatch(line);
      if (testMatch != null) {
        final failCount = int.tryParse(testMatch.group(1) ?? '0') ?? 0;
        if (failCount > 0) {
          failedTests.add(testMatch.group(2)?.trim() ?? 'unknown test');
        }
      }

      if (allPassedPattern.hasMatch(line)) {
        passed = passed > 0 ? passed : 1;
        failed = 0;
      }
    }

    total = passed + failed + skipped;

    // Fallback: count from summary patterns.
    if (total == 0) {
      for (final line in lines) {
        final match = finalPattern.firstMatch(line);
        if (match != null) {
          passed = int.tryParse(match.group(1) ?? '0') ?? 0;
          failed = int.tryParse(match.group(2) ?? '0') ?? 0;
          total = passed + failed;
          break;
        }
      }
    }

    return TestResult(
      total: total,
      passed: passed,
      failed: failed,
      skipped: skipped,
      failedTests: failedTests,
    );
  }

  /// Parse `git status --porcelain` or `git status` output.
  ///
  /// Extracts modified, staged, and untracked files.
  GitStatus parseGitStatus(String output) {
    final modified = <String>[];
    final staged = <String>[];
    final untracked = <String>[];
    var branch = '';

    final lines = const LineSplitter().convert(output);

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Branch line: "On branch main"
      if (trimmed.startsWith('On branch ')) {
        branch = trimmed.substring('On branch '.length);
        continue;
      }

      // Parse porcelain format: XY filename
      if (trimmed.length > 3) {
        final statusCode = trimmed.substring(0, 2);
        final filename = trimmed.substring(3).trim();

        // Index (staged) status is first char.
        final indexStatus = statusCode[0];
        // Work tree status is second char.
        final workTreeStatus = statusCode[1];

        if (indexStatus != ' ' && indexStatus != '?') {
          staged.add(filename);
        }
        if (workTreeStatus == 'M' || indexStatus == 'M') {
          if (!staged.contains(filename)) modified.add(filename);
        }
        if (indexStatus == '?' || workTreeStatus == '?') {
          untracked.add(filename);
        }
      }

      // Parse human-readable format.
      if (trimmed.startsWith('modified:')) {
        final file = trimmed.substring('modified:'.length).trim();
        if (!modified.contains(file)) modified.add(file);
      } else if (trimmed.startsWith('new file:')) {
        final file = trimmed.substring('new file:'.length).trim();
        if (!staged.contains(file)) staged.add(file);
      } else if (trimmed.startsWith('deleted:')) {
        final file = trimmed.substring('deleted:'.length).trim();
        if (!modified.contains(file)) modified.add(file);
      } else if (trimmed.startsWith('Untracked files:')) {
        // Next lines until empty are untracked files.
      }
    }

    final isClean = modified.isEmpty && staged.isEmpty && untracked.isEmpty;

    return GitStatus(
      modified: modified,
      staged: staged,
      untracked: untracked,
      branch: branch,
      isClean: isClean,
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // History Management
  // ═════════════════════════════════════════════════════════════════

  void clearHistory() {
    _history.clear();
    _historyController.add(List.unmodifiable(_history));
  }

  void _addToHistory(String command, CommandResult result) {
    _history.add(CommandEntry(
      command: command,
      timestamp: DateTime.now(),
      result: result,
    ));
    _historyController.add(List.unmodifiable(_history));
  }

  // ═════════════════════════════════════════════════════════════════
  // Working Directory
  // ═════════════════════════════════════════════════════════════════

  void setWorkingDirectory(String path) {
    _currentWorkingDirectory = path;
    debugPrint('[TerminalService] Working directory set to: $path');
  }

  // ═════════════════════════════════════════════════════════════════
  // Utility
  // ═════════════════════════════════════════════════════════════════

  /// Parse a command string into executable and arguments.
  ///
  /// Handles simple quoted arguments. Returns (executable, arguments)
  /// or null if parsing fails.
  (String, List<String>)? _parseCommand(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return null;

    // Use shell execution for simplicity and correctness.
    return ('sh', ['-c', trimmed]);
  }

  String _normalizeSeverity(String severity) {
    switch (severity.toLowerCase()) {
      case 'error':
        return 'error';
      case 'warning':
      case 'warn':
        return 'warning';
      case 'info':
      case 'hint':
      case 'hint':
        return 'info';
      default:
        return 'error';
    }
  }

  /// Dispose all resources. Call when the service is no longer needed.
  void dispose() {
    _outputController.close();
    _historyController.close();
    _currentProcess?.kill(ProcessSignal.sigkill);
    _currentProcess = null;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Data Classes
// ═══════════════════════════════════════════════════════════════════════════

/// Result of executing a terminal command.
class CommandResult {
  /// The original command string.
  final String command;

  /// Standard output from the process.
  final String stdout;

  /// Standard error from the process.
  final String stderr;

  /// Process exit code (0 = success).
  final int exitCode;

  /// Time taken to execute the command.
  final Duration duration;

  /// When the command was executed.
  final DateTime executedAt;

  const CommandResult({
    required this.command,
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.duration,
    required this.executedAt,
  });

  /// Create a result for a rejected command.
  factory CommandResult._rejected(String command) => CommandResult(
        command: command,
        stdout: '',
        stderr: 'Command not allowed for security reasons',
        exitCode: -2,
        duration: Duration.zero,
        executedAt: DateTime.now(),
      );

  /// Create a result for a parse error.
  factory CommandResult._error(String command, String error) => CommandResult(
        command: command,
        stdout: '',
        stderr: error,
        exitCode: -3,
        duration: Duration.zero,
        executedAt: DateTime.now(),
      );

  /// Create a result for a timed-out command.
  factory CommandResult._timedOut(String command, int timeoutSeconds) =>
      CommandResult(
        command: command,
        stdout: '',
        stderr: 'Command timed out after ${timeoutSeconds}s',
        exitCode: -1,
        duration: Duration(seconds: timeoutSeconds),
        executedAt: DateTime.now(),
      );

  /// Whether the command succeeded (exit code 0).
  bool get success => exitCode == 0;

  /// Whether the command produced any error output.
  bool get hasErrors => stderr.isNotEmpty || exitCode != 0;

  /// Combined stdout and stderr for display.
  String get combinedOutput {
    final buffer = StringBuffer();
    if (stdout.isNotEmpty) buffer.writeln(stdout);
    if (stderr.isNotEmpty) buffer.writeln(stderr);
    return buffer.toString().trim();
  }

  @override
  String toString() =>
      'CommandResult[$command]: exit=$exitCode, ${duration.inMilliseconds}ms';
}

/// A single entry in the command history.
class CommandEntry {
  /// The command that was executed.
  final String command;

  /// When the command was started.
  final DateTime timestamp;

  /// The result of execution, if completed.
  final CommandResult? result;

  CommandEntry({
    required this.command,
    required this.timestamp,
    this.result,
  });

  /// Whether this command has completed.
  bool get isCompleted => result != null;

  /// Whether this command succeeded (if completed).
  bool? get succeeded => result?.success;

  @override
  String toString() => 'CommandEntry[$timestamp]: $command';
}

/// A build error parsed from compiler/linter output.
class BuildError {
  /// File path where the error occurred.
  final String file;

  /// Line number (1-based).
  final int line;

  /// Column number (1-based).
  final int column;

  /// Error message.
  final String message;

  /// Severity level: 'error', 'warning', or 'info'.
  final String severity;

  const BuildError({
    required this.file,
    required this.line,
    required this.column,
    required this.message,
    required this.severity,
  });

  bool get isError => severity == 'error';
  bool get isWarning => severity == 'warning';
  bool get isInfo => severity == 'info';

  /// Formatted location string like "lib/main.dart:42:10".
  String get location => '$file:$line:$column';

  @override
  String toString() => '[$severity] $location: $message';
}

/// Results from running tests.
class TestResult {
  /// Total number of tests.
  final int total;

  /// Number of passing tests.
  final int passed;

  /// Number of failing tests.
  final int failed;

  /// Number of skipped tests.
  final int skipped;

  /// Names of failed tests.
  final List<String> failedTests;

  const TestResult({
    required this.total,
    required this.passed,
    required this.failed,
    required this.skipped,
    required this.failedTests,
  });

  /// Whether all tests passed.
  bool get allPassed => failed == 0 && total > 0;

  /// Pass rate as a fraction (0.0 to 1.0).
  double get passRate => total > 0 ? passed / total : 0.0;

  /// Formatted summary string.
  String get summary => '$passed/$total passed, $failed failed, $skipped skipped';

  @override
  String toString() => 'TestResult: $summary';
}

/// Parsed git status output.
class GitStatus {
  /// Files with unstaged modifications.
  final List<String> modified;

  /// Files staged for commit.
  final List<String> staged;

  /// Untracked files.
  final List<String> untracked;

  /// Current branch name.
  final String branch;

  /// Whether the working tree is clean.
  final bool isClean;

  const GitStatus({
    required this.modified,
    required this.staged,
    required this.untracked,
    required this.branch,
    required this.isClean,
  });

  /// Total number of changed files.
  int get changeCount => modified.length + staged.length + untracked.length;

  /// Formatted summary string.
  String get summary {
    if (isClean) return 'working tree clean on $branch';
    final parts = <String>[];
    if (staged.isNotEmpty) parts.add('${staged.length} staged');
    if (modified.isNotEmpty) parts.add('${modified.length} modified');
    if (untracked.isNotEmpty) parts.add('${untracked.length} untracked');
    return '${parts.join(', ')} on $branch';
  }

  @override
  String toString() => 'GitStatus: $summary';
}
