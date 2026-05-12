// lib/providers/terminal_provider.dart
// Terminal State Provider — Riverpod state management for the terminal.
//
// Manages command execution state, output buffer, history navigation,
// working directory, and provides computed properties for the UI.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/terminal_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Providers
// ═══════════════════════════════════════════════════════════════════════════

/// The terminal service instance (singleton).
final terminalServiceProvider = Provider<TerminalService>((ref) {
  final service = TerminalService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Terminal state notifier — manages all mutable terminal state.
///
/// Access via:
/// ```dart
/// final state = ref.watch(terminalStateProvider);
/// ref.read(terminalStateProvider.notifier).executeCommand('flutter doctor');
/// ```
final terminalStateProvider =
    StateNotifierProvider<TerminalNotifier, TerminalState>((ref) {
  final service = ref.watch(terminalServiceProvider);
  return TerminalNotifier(service);
});

/// Computed provider for the list of available quick commands.
final quickCommandsProvider = Provider<List<QuickCommand>>((ref) {
  return const [
    QuickCommand(label: 'flutter doctor', command: 'flutter doctor', icon: 'stethoscope'),
    QuickCommand(label: 'pub get', command: 'flutter pub get', icon: 'download'),
    QuickCommand(label: 'flutter run', command: 'flutter run', icon: 'play'),
    QuickCommand(label: 'build apk', command: 'flutter build apk', icon: 'build'),
    QuickCommand(label: 'flutter test', command: 'flutter test', icon: 'check'),
    QuickCommand(label: 'dart analyze', command: 'dart analyze', icon: 'search'),
    QuickCommand(label: 'dart format', command: 'dart format .', icon: 'format'),
    QuickCommand(label: 'flutter clean', command: 'flutter clean', icon: 'clean'),
    QuickCommand(label: 'git status', command: 'git status', icon: 'git'),
    QuickCommand(label: 'git log', command: 'git log --oneline -10', icon: 'history'),
    QuickCommand(label: 'npm install', command: 'npm install', icon: 'download'),
    QuickCommand(label: 'npm run build', command: 'npm run build', icon: 'build'),
  ];
});

// ═══════════════════════════════════════════════════════════════════════════
// Terminal State
// ═══════════════════════════════════════════════════════════════════════════

/// Immutable state object representing the terminal's current condition.
///
/// All mutations go through [TerminalNotifier] which produces a new
/// [TerminalState] instance on each change.
@immutable
class TerminalState {
  /// Output lines displayed in the terminal.
  final List<TerminalLine> outputLines;

  /// Whether a command is currently running.
  final bool isExecuting;

  /// The current working directory.
  final String? workingDirectory;

  /// Command history for up/down arrow navigation.
  final List<String> commandHistory;

  /// Current position in command history (-1 = not navigating).
  final int historyIndex;

  /// The last executed command result, if any.
  final CommandResult? lastResult;

  /// Current input text.
  final String inputText;

  /// Whether auto-scroll is enabled.
  final bool autoScroll;

  const TerminalState({
    this.outputLines = const [],
    this.isExecuting = false,
    this.workingDirectory,
    this.commandHistory = const [],
    this.historyIndex = -1,
    this.lastResult,
    this.inputText = '',
    this.autoScroll = true,
  });

  /// Create a copy with modified fields.
  TerminalState copyWith({
    List<TerminalLine>? outputLines,
    bool? isExecuting,
    String? workingDirectory,
    List<String>? commandHistory,
    int? historyIndex,
    CommandResult? lastResult,
    String? inputText,
    bool? autoScroll,
  }) {
    return TerminalState(
      outputLines: outputLines ?? this.outputLines,
      isExecuting: isExecuting ?? this.isExecuting,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      commandHistory: commandHistory ?? this.commandHistory,
      historyIndex: historyIndex ?? this.historyIndex,
      lastResult: lastResult ?? this.lastResult,
      inputText: inputText ?? this.inputText,
      autoScroll: autoScroll ?? this.autoScroll,
    );
  }

  /// The prompt string displayed before input.
  String get prompt {
    if (workingDirectory == null) return '\$ ';
    final path = workingDirectory!.split('/').last;
    return 'mobile-coding:$path\$ ';
  }

  /// Whether there is output to display.
  bool get hasOutput => outputLines.isNotEmpty;

  /// Number of output lines.
  int get lineCount => outputLines.length;
}

/// A single line in the terminal output with styling metadata.
@immutable
class TerminalLine {
  /// The text content of the line.
  final String text;

  /// The line type determining color/style.
  final TerminalLineType type;

  /// When this line was added.
  final DateTime timestamp;

  const TerminalLine({
    required this.text,
    this.type = TerminalLineType.normal,
    required this.timestamp,
  });

  TerminalLine.normal(String text)
      : this(text: text, type: TerminalLineType.normal, timestamp: DateTime.now());

  TerminalLine.error(String text)
      : this(text: text, type: TerminalLineType.error, timestamp: DateTime.now());

  TerminalLine.warning(String text)
      : this(text: text, type: TerminalLineType.warning, timestamp: DateTime.now());

  TerminalLine.success(String text)
      : this(text: text, type: TerminalLineType.success, timestamp: DateTime.now());

  TerminalLine.info(String text)
      : this(text: text, type: TerminalLineType.info, timestamp: DateTime.now());

  TerminalLine.command(String text)
      : this(text: text, type: TerminalLineType.command, timestamp: DateTime.now());

  TerminalLine.system(String text)
      : this(text: text, type: TerminalLineType.system, timestamp: DateTime.now());
}

/// Classification of terminal line types for color-coding.
enum TerminalLineType {
  /// Regular output.
  normal,

  /// Error messages (red).
  error,

  /// Warning messages (yellow).
  warning,

  /// Success messages (green).
  success,

  /// Informational messages (blue).
  info,

  /// User-entered commands.
  command,

  /// System messages (prompt, process status).
  system,
}

/// Definition of a quick action command button.
@immutable
class QuickCommand {
  /// Display label for the button.
  final String label;

  /// The command to execute.
  final String command;

  /// Icon identifier (maps to Icons.* in the UI).
  final String icon;

  const QuickCommand({
    required this.label,
    required this.command,
    required this.icon,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Terminal Notifier
// ═══════════════════════════════════════════════════════════════════════════

/// State notifier that manages terminal execution and output.
///
/// Bridges the [TerminalService] with the UI by maintaining an
/// output buffer and exposing a clean API for the terminal screen.
class TerminalNotifier extends StateNotifier<TerminalState> {
  final TerminalService _service;
  StreamSubscription<String>? _outputSubscription;

  TerminalNotifier(this._service) : super(const TerminalState()) {
    _listenToOutput();
  }

  /// Subscribe to the service's output stream and buffer lines.
  void _listenToOutput() {
    _outputSubscription = _service.outputStream.listen((line) {
      _appendLine(_classifyLine(line));
    });
  }

  /// Classify a raw output line into a styled [TerminalLine].
  TerminalLine _classifyLine(String line) {
    final trimmed = line.trim();

    // Check for stderr prefix.
    if (trimmed.startsWith('[stderr]')) {
      return TerminalLine.error(trimmed.substring('[stderr]'.length).trim());
    }

    // Check for system prefix.
    if (trimmed.startsWith('[system]')) {
      return TerminalLine.system(trimmed.substring('[system]'.length).trim());
    }

    // Check for exit prefix.
    if (trimmed.startsWith('[exit]')) {
      return TerminalLine.info(trimmed);
    }

    // Check for error prefix.
    if (trimmed.startsWith('[error]')) {
      return TerminalLine.error(trimmed.substring('[error]'.length).trim());
    }

    // Heuristic classification based on content.
    final lower = trimmed.toLowerCase();

    if (lower.contains('error:') ||
        lower.contains('exception:') ||
        lower.contains('failed') ||
        lower.contains('failure')) {
      return TerminalLine.error(trimmed);
    }

    if (lower.contains('warning:') || lower.contains('warn:')) {
      return TerminalLine.warning(trimmed);
    }

    if (lower.contains('success') ||
        lower.contains('✓') ||
        lower.contains('completed') ||
        (lower.contains('passed') && !lower.contains('failed'))) {
      return TerminalLine.success(trimmed);
    }

    if (lower.contains('info:') || lower.contains('note:')) {
      return TerminalLine.info(trimmed);
    }

    return TerminalLine.normal(trimmed);
  }

  /// Append a line to the output buffer.
  void _appendLine(TerminalLine line) {
    final newLines = [...state.outputLines, line];
    // Cap at 5000 lines to prevent memory issues.
    if (newLines.length > 5000) {
      newLines.removeAt(0);
    }
    state = state.copyWith(outputLines: newLines);
  }

  // ── Command Execution ────────────────────────────────────────────

  /// Execute a command and append results to the output buffer.
  Future<void> executeCommand(String command) async {
    if (command.trim().isEmpty) return;

    // Show the command in the terminal.
    _appendLine(TerminalLine.command('${state.prompt}$command'));

    // Update state to executing.
    state = state.copyWith(
      isExecuting: true,
      inputText: '',
      commandHistory: [...state.commandHistory, command],
      historyIndex: -1,
    );

    try {
      final result = await _service.execute(
        command,
        workingDirectory: state.workingDirectory,
      );

      // Append stdout lines.
      if (result.stdout.isNotEmpty) {
        const splitter = LineSplitter();
        for (final line in splitter.convert(result.stdout)) {
          if (line.isNotEmpty) {
            _appendLine(_classifyLine(line));
          }
        }
      }

      // Append stderr lines.
      if (result.stderr.isNotEmpty) {
        const splitter = LineSplitter();
        for (final line in splitter.convert(result.stderr)) {
          if (line.isNotEmpty) {
            _appendLine(TerminalLine.error(line));
          }
        }
      }

      // Show exit status.
      if (result.exitCode != 0) {
        _appendLine(TerminalLine.error(
          '[exit code ${result.exitCode}] (${result.duration.inSeconds}s)',
        ));
      } else {
        _appendLine(TerminalLine.success(
          '[done] (${result.duration.inSeconds}s)',
        ));
      }

      state = state.copyWith(
        isExecuting: false,
        lastResult: result,
      );
    } catch (e) {
      _appendLine(TerminalLine.error('Exception: $e'));
      state = state.copyWith(isExecuting: false);
    }
  }

  /// Execute a quick command by its label.
  void executeQuickCommand(String command) {
    executeCommand(command);
  }

  /// Kill the currently running process.
  Future<void> killProcess() async {
    await _service.kill();
    _appendLine(TerminalLine.system('Process killed by user'));
    state = state.copyWith(isExecuting: false);
  }

  // ── Input Management ─────────────────────────────────────────────

  /// Update the current input text.
  void setInputText(String text) {
    state = state.copyWith(inputText: text);
  }

  /// Navigate to the previous command in history (Up arrow).
  void historyUp() {
    if (state.commandHistory.isEmpty) return;
    final newIndex = state.historyIndex < 0
        ? state.commandHistory.length - 1
        : (state.historyIndex - 1).clamp(0, state.commandHistory.length - 1);
    state = state.copyWith(
      historyIndex: newIndex,
      inputText: state.commandHistory[newIndex],
    );
  }

  /// Navigate to the next command in history (Down arrow).
  void historyDown() {
    if (state.historyIndex < 0) return;
    final newIndex = state.historyIndex + 1;
    if (newIndex >= state.commandHistory.length) {
      state = state.copyWith(historyIndex: -1, inputText: '');
    } else {
      state = state.copyWith(
        historyIndex: newIndex,
        inputText: state.commandHistory[newIndex],
      );
    }
  }

  // ── Output Management ────────────────────────────────────────────

  /// Clear all output lines.
  void clearOutput() {
    state = state.copyWith(outputLines: []);
  }

  /// Append a system message to the output.
  void appendSystemMessage(String message) {
    _appendLine(TerminalLine.system(message));
  }

  // ── Working Directory ────────────────────────────────────────────

  /// Set the working directory for future commands.
  void setWorkingDirectory(String path) {
    _service.setWorkingDirectory(path);
    state = state.copyWith(workingDirectory: path);
    _appendLine(TerminalLine.system('Working directory: $path'));
  }

  /// Toggle auto-scroll behavior.
  void toggleAutoScroll() {
    state = state.copyWith(autoScroll: !state.autoScroll);
  }

  // ── Suggestions ──────────────────────────────────────────────────

  /// Get autocomplete suggestions for the current input.
  List<String> getSuggestions(String input) {
    if (input.trim().isEmpty) return [];
    
    final suggestions = <String>{
      'flutter run',
      'flutter build',
      'flutter test',
      'flutter pub get',
      'flutter clean',
      'flutter doctor',
      'dart analyze',
      'dart format',
      'dart run',
      'git status',
      'git add',
      'git commit',
      'git push',
      'git pull',
      'git log',
      'git branch',
      'git checkout',
      'git merge',
      'npm install',
      'npm run',
      'npm build',
      'npm test',
      'node',
      'python',
      'pip install',
      'ls',
      'pwd',
      'cd',
      'cat',
      'mkdir',
      'rm',
      'cp',
      'mv',
      'clear',
    };

    return suggestions
        .where((s) => s.startsWith(input.trim()))
        .take(6)
        .toList();
  }

  @override
  void dispose() {
    _outputSubscription?.cancel();
    super.dispose();
  }
}
