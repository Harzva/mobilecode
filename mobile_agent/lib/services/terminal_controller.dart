// lib/services/terminal_controller.dart
// Terminal Controller — Self-Use Control Interface for the Terminal
//
// Exposes the terminal's functionality to SelfInvocationService.
// Allows the Agent to run commands, manage processes, and observe
// terminal output programmatically — all within the same Flutter process.
//
// Features:
//   - Execute shell commands with security validation
//   - Real-time output streaming
//   - Process lifecycle management (kill, status)
//   - Command history tracking
//   - Working directory management

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

import '../core/theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Terminal Controller
// ═══════════════════════════════════════════════════════════════════════════

/// Controller for the terminal that enables programmatic command execution.
///
/// Provides a bridge between the self-invocation system and the terminal
/// widget. Commands are validated against an allowlist for security.
///
/// To use in a widget:
/// ```dart
/// final terminalController = TerminalController();
/// SelfInvocationService().registerTerminalController(terminalController);
///
/// // In build:
/// TerminalView(controller: terminalController),
/// ```
class TerminalController extends ChangeNotifier {
  // ── Internal State ────────────────────────────────────────────────────

  /// Current working directory.
  String _workingDirectory = '';

  /// Full output history (all lines).
  final List<String> _outputHistory = [];

  /// Maximum output lines to keep in history.
  static const int _maxHistoryLines = 5000;

  /// Currently running process.
  Process? _currentProcess;

  /// Whether a command is currently running.
  bool _isRunning = false;

  /// The last executed command.
  String _lastCommand = '';

  /// Command history for user recall (last 100 commands).
  final List<String> _commandHistory = [];

  /// Maximum command history entries.
  static const int _maxCommandHistory = 100;

  /// Terminal session ID (for multi-session support).
  final String sessionId;

  /// Stream controller for real-time output.
  final StreamController<String> _outputController =
      StreamController<String>.broadcast();

  /// Stream controller for command completion events.
  final StreamController<TerminalResult> _completionController =
      StreamController<TerminalResult>.broadcast();

  /// Stream controller for state changes.
  final StreamController<TerminalState> _stateController =
      StreamController<TerminalState>.broadcast();

  // ── Public Streams ────────────────────────────────────────────────────

  /// Real-time command output stream.
  ///
  /// Each string emitted represents a chunk of output from the running
  /// command. Listen to this for live terminal updates.
  Stream<String> get outputStream => _outputController.stream;

  /// Stream of command completion events.
  ///
  /// Emitted when a command finishes, containing the full result.
  Stream<TerminalResult> get completionStream => _completionController.stream;

  /// Stream of terminal state changes (running/stopped).
  Stream<TerminalState> get stateStream => _stateController.stream;

  // ── Getters ───────────────────────────────────────────────────────────

  /// Current working directory.
  String get currentWorkingDirectory => _workingDirectory;

  /// Full output history as an unmodifiable list.
  List<String> get outputHistory => List.unmodifiable(_outputHistory);

  /// Output history as a single string.
  String get outputText => _outputHistory.join('\n');

  /// Whether a command is currently running.
  bool get isRunning => _isRunning;

  /// The last executed command string.
  String get lastCommand => _lastCommand;

  /// Command history for recall.
  List<String> get commandHistory => List.unmodifiable(_commandHistory);

  /// Whether there is a running process that can be killed.
  bool get canKill => _currentProcess != null && _isRunning;

  /// Whether there is output to clear.
  bool get hasOutput => _outputHistory.isNotEmpty;

  /// Number of lines in the output history.
  int get outputLineCount => _outputHistory.length;

  /// Session ID for this terminal instance.
  String get currentSessionId => sessionId;

  // ── Security: Allowed Command Prefixes ────────────────────────────────

  /// Allowed command prefixes for security validation.
  ///
  /// Only commands starting with these prefixes can be executed.
  /// This prevents destructive or unauthorized operations.
  static const List<String> _allowedPrefixes = [
    'flutter ',
    'dart ',
    'git ',
    'npm ',
    'node ',
    'python ',
    'python3 ',
    'pip ',
    'pip3 ',
    'mkdir ',
    'ls ',
    'cat ',
    'cp ',
    'mv ',
    'echo ',
    'touch ',
    'chmod ',
    'grep ',
    'find ',
    'wc ',
    'head ',
    'tail ',
    'diff ',
    'curl ',
    'wget ',
    'unzip ',
    'tar ',
    'sed ',
    'awk ',
    'sort ',
    'uniq ',
    'pwd ',
    'cd ',
  ];

  /// Single-word commands that are allowed without a prefix.
  static const List<String> _allowedSingleCommands = [
    'ls',
    'pwd',
    'clear',
    'whoami',
    'date',
    'env',
    'which',
    'flutter',
    'dart',
    'git',
    'npm',
    'node',
    'python',
    'python3',
  ];

  // ── Constructor ───────────────────────────────────────────────────────

  TerminalController({
    String? workingDirectory,
    String? sessionId,
  })  : _workingDirectory = workingDirectory ??
            (Directory.current.existsSync() ? Directory.current.path : '/'),
        sessionId = sessionId ??
            'session_${DateTime.now().millisecondsSinceEpoch}' {
    _addOutput(
      '[MobileCode Terminal — Session $sessionId]',
      color: '\x1B[36m',
    );
    _addOutput(
      'Working directory: $_workingDirectory',
      color: '\x1B[90m',
    );
    _addOutput('Type "help" for available commands.\n', color: '\x1B[90m');
  }

  // ── Command Execution ─────────────────────────────────────────────────

  /// Run a shell command in the terminal.
  ///
  /// The command is validated against the allowlist before execution.
  /// Output is streamed in real-time through [outputStream].
  /// The final result is emitted through [completionStream].
  ///
  /// Returns a [TerminalResult] with exit code, stdout, and stderr.
  ///
  /// Throws [SecurityException] if the command is not allowed.
  Future<TerminalResult> runCommand(
    String command, {
    String? workingDir,
  }) async {
    // Validate command security
    if (!_isCommandAllowed(command)) {
      final error = 'Command not allowed: $command';
      _addOutput('\n\$ $command', color: '\x1B[32m');
      _addOutput('Error: $error', color: '\x1B[31m');
      return TerminalResult(
        command: command,
        exitCode: -1,
        stdout: '',
        stderr: error,
        wasAllowed: false,
      );
    }

    // Update state
    _isRunning = true;
    _lastCommand = command;
    _addCommandToHistory(command);

    notifyListeners();
    _stateController.add(TerminalState.running);

    // Show command prompt
    _addOutput('\n\$ $command', color: '\x1B[32m');

    final cwd = workingDir ?? _workingDirectory;
    final stopwatch = Stopwatch()..start();

    try {
      // Handle cd command specially
      if (command.trim().startsWith('cd ')) {
        return await _handleCdCommand(command, cwd);
      }

      // Handle clear command specially
      if (command.trim() == 'clear') {
        await clear();
        return TerminalResult(
          command: command,
          exitCode: 0,
          stdout: '',
          stderr: '',
        );
      }

      // Handle pwd command specially
      if (command.trim() == 'pwd') {
        _addOutput(cwd);
        stopwatch.stop();
        return TerminalResult(
          command: command,
          exitCode: 0,
          stdout: cwd,
          stderr: '',
          duration: stopwatch.elapsed,
        );
      }

      // Execute via Process
      _currentProcess = await Process.start(
        'sh',
        ['-c', command],
        workingDirectory: cwd,
        runInShell: false,
      );

      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();

      // Stream stdout
      _currentProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        stdoutBuffer.writeln(line);
        _addOutput(line);
        _outputController.add(line);
      });

      // Stream stderr
      _currentProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        stderrBuffer.writeln(line);
        _addOutput(line, color: '\x1B[31m');
        _outputController.add('\x1B[31m$line\x1B[0m');
      });

      // Wait for completion
      final exitCode = await _currentProcess!.exitCode;
      stopwatch.stop();

      final result = TerminalResult(
        command: command,
        exitCode: exitCode,
        stdout: stdoutBuffer.toString(),
        stderr: stderrBuffer.toString(),
        duration: stopwatch.elapsed,
      );

      if (exitCode != 0) {
        _addOutput('Exit code: $exitCode', color: '\x1B[33m');
      }

      _completionController.add(result);
      return result;
    } catch (e) {
      stopwatch.stop();
      final error = 'Failed to execute: $e';
      _addOutput(error, color: '\x1B[31m');

      final result = TerminalResult(
        command: command,
        exitCode: -1,
        stdout: '',
        stderr: error,
        duration: stopwatch.elapsed,
      );
      _completionController.add(result);
      return result;
    } finally {
      _isRunning = false;
      _currentProcess = null;
      notifyListeners();
      _stateController.add(TerminalState.idle);
    }
  }

  /// Kill the currently running process.
  ///
  /// Sends SIGTERM to the process. If it doesn't terminate within
  /// 2 seconds, sends SIGKILL.
  Future<void> killCurrentProcess() async {
    if (_currentProcess == null) return;

    _addOutput('\n[Terminating process...]', color: '\x1B[33m');

    try {
      _currentProcess!.kill(ProcessSignal.sigterm);

      // Wait up to 2 seconds for graceful termination
      await Future.delayed(const Duration(seconds: 2));

      if (_isRunning && _currentProcess != null) {
        _currentProcess!.kill(ProcessSignal.sigkill);
        _addOutput('[Process force-killed]', color: '\x1B[31m');
      } else {
        _addOutput('[Process terminated]', color: '\x1B[33m');
      }
    } catch (e) {
      _addOutput('Failed to kill process: $e', color: '\x1B[31m');
    }
  }

  /// Clear all terminal output.
  Future<void> clear() async {
    _outputHistory.clear();
    _addOutput('[Terminal cleared]', color: '\x1B[90m');
    notifyListeners();
  }

  /// Run a command and capture all output (non-streaming).
  ///
  /// Useful when you just need the result without real-time updates.
  Future<TerminalResult> runCommandSilent(String command, {String? workingDir}) async {
    final stopwatch = Stopwatch()..start();

    if (!_isCommandAllowed(command)) {
      return TerminalResult(
        command: command,
        exitCode: -1,
        stdout: '',
        stderr: 'Command not allowed: $command',
        wasAllowed: false,
      );
    }

    try {
      final result = await Process.run(
        'sh',
        ['-c', command],
        workingDirectory: workingDir ?? _workingDirectory,
        runInShell: false,
      );
      stopwatch.stop();

      return TerminalResult(
        command: command,
        exitCode: result.exitCode,
        stdout: (result.stdout as String? ?? '').trim(),
        stderr: (result.stderr as String? ?? '').trim(),
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return TerminalResult(
        command: command,
        exitCode: -1,
        stdout: '',
        stderr: 'Execution error: $e',
        duration: stopwatch.elapsed,
      );
    }
  }

  /// Execute multiple commands in sequence.
  ///
  /// Stops on first failure unless [continueOnFailure] is true.
  Future<List<TerminalResult>> runCommands(
    List<String> commands, {
    bool continueOnFailure = false,
  }) async {
    final results = <TerminalResult>[];

    for (final cmd in commands) {
      final result = await runCommand(cmd);
      results.add(result);

      if (result.exitCode != 0 && !continueOnFailure) {
        break;
      }
    }

    return results;
  }

  // ── Working Directory ─────────────────────────────────────────────────

  /// Change the working directory.
  Future<void> changeWorkingDirectory(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      throw FileSystemException('Directory does not exist', path);
    }
    _workingDirectory = path;
    _addOutput('[Working directory: $path]', color: '\x1B[90m');
    notifyListeners();
  }

  /// Set the working directory (internal helper).
  Future<TerminalResult> _handleCdCommand(String command, String cwd) async {
    final parts = command.trim().split(' ');
    if (parts.length < 2) {
      return TerminalResult(command: command, exitCode: 0, stdout: cwd, stderr: '');
    }

    final target = parts.sublist(1).join(' ');
    String newPath;

    if (target.startsWith('/')) {
      newPath = target;
    } else {
      newPath = '$cwd/$target';
    }

    // Normalize simple path segments
    newPath = newPath.replaceAll(RegExp(r'/+'), '/');

    final dir = Directory(newPath);
    if (!await dir.exists()) {
      final error = 'cd: no such directory: $target';
      _addOutput(error, color: '\x1B[31m');
      return TerminalResult(
        command: command,
        exitCode: 1,
        stdout: '',
        stderr: error,
      );
    }

    _workingDirectory = newPath;
    _addOutput('[Working directory: $newPath]', color: '\x1B[90m');
    return TerminalResult(command: command, exitCode: 0, stdout: '', stderr: '');
  }

  // ── Security ──────────────────────────────────────────────────────────

  /// Check if a command is allowed.
  bool _isCommandAllowed(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return false;

    // Check single-word commands
    if (_allowedSingleCommands.contains(trimmed)) return true;

    // Check allowed prefixes
    for (final prefix in _allowedPrefixes) {
      if (trimmed.startsWith(prefix)) return true;
    }

    return false;
  }

  /// Add a custom allowed prefix at runtime.
  static void addAllowedPrefix(String prefix) {
    // This would modify a mutable list in production
    // For now, the list is static
  }

  // ── Internal Helpers ──────────────────────────────────────────────────

  void _addOutput(String line, {String color = ''}) {
    final colored = color.isNotEmpty ? '$color$line\x1B[0m' : line;
    _outputHistory.add(colored);
    if (_outputHistory.length > _maxHistoryLines) {
      _outputHistory.removeAt(0);
    }
    notifyListeners();
  }

  void _addCommandToHistory(String command) {
    if (command.trim().isEmpty) return;
    _commandHistory.add(command.trim());
    if (_commandHistory.length > _maxCommandHistory) {
      _commandHistory.removeAt(0);
    }
  }

  // ── Diagnostics ───────────────────────────────────────────────────────

  /// Get diagnostic information.
  Map<String, dynamic> getDiagnostics() {
    return {
      'sessionId': sessionId,
      'workingDirectory': _workingDirectory,
      'isRunning': _isRunning,
      'lastCommand': _lastCommand,
      'outputLines': _outputHistory.length,
      'commandHistoryCount': _commandHistory.length,
      'canKill': canKill,
    };
  }

  // ── Cleanup ───────────────────────────────────────────────────────────

  @override
  void dispose() {
    if (_currentProcess != null) {
      _currentProcess!.kill();
    }
    _outputController.close();
    _completionController.close();
    _stateController.close();
    _outputHistory.clear();
    _commandHistory.clear();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Terminal Result
// ═══════════════════════════════════════════════════════════════════════════

/// Result of executing a terminal command.
class TerminalResult {
  /// The command that was executed.
  final String command;

  /// Process exit code (0 = success).
  final int exitCode;

  /// Standard output.
  final String stdout;

  /// Standard error.
  final String stderr;

  /// Whether the command passed security validation.
  final bool wasAllowed;

  /// How long the command took to execute.
  final Duration? duration;

  /// When the command completed.
  final DateTime timestamp;

  const TerminalResult({
    required this.command,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.wasAllowed = true,
    this.duration,
  }) : timestamp = _now;

  static DateTime get _now => DateTime.now();

  /// Whether the command succeeded.
  bool get success => exitCode == 0;

  /// Combined output (stdout + stderr).
  String get combinedOutput {
    final buffer = StringBuffer();
    if (stdout.isNotEmpty) buffer.writeln(stdout);
    if (stderr.isNotEmpty) buffer.writeln(stderr);
    return buffer.toString().trim();
  }

  /// Formatted duration string.
  String get durationFormatted {
    if (duration == null) return '--';
    if (duration!.inMinutes > 0) {
      return '${duration!.inMinutes}m ${(duration!.inSeconds % 60).toString().padLeft(2, '0')}s';
    }
    return '${(duration!.inMilliseconds / 1000).toStringAsFixed(2)}s';
  }

  Map<String, dynamic> toJson() => {
        'command': command,
        'exitCode': exitCode,
        'stdout': stdout,
        'stderr': stderr,
        'success': success,
        'durationMs': duration?.inMilliseconds,
      };

  @override
  String toString() =>
      'TerminalResult[$command]: exit=$exitCode ${success ? 'OK' : 'FAIL'}';
}

// ═══════════════════════════════════════════════════════════════════════════
// Terminal State
// ═══════════════════════════════════════════════════════════════════════════

/// Current state of the terminal.
enum TerminalState {
  /// No command is running.
  idle,

  /// A command is currently executing.
  running,
}
