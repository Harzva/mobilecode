// lib/screens/terminal_screen.dart
// Terminal Screen — Full-featured terminal UI for MobileCode.
//
// Features:
// - Terminal output display with color-coded lines
// - Command input with autocomplete suggestions
// - Quick action buttons for common commands
// - Command history navigation (up/down arrows)
// - Copy output and clear terminal buttons
// - Kill running process button
// - Dark terminal aesthetic matching GitHub dark theme

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../providers/terminal_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Terminal Screen
// ═══════════════════════════════════════════════════════════════════════════

/// Terminal screen with full command execution capabilities.
///
/// Provides a VS Code-like integrated terminal experience with
/// color-coded output, autocomplete, quick commands, and history.
class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({super.key});

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  final _inputController = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final _inputScrollController = ScrollController();

  bool _showSuggestions = false;
  List<String> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _inputController.addListener(_onInputChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inputFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _inputController.removeListener(_onInputChanged);
    _inputController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    _inputScrollController.dispose();
    super.dispose();
  }

  /// Auto-scroll to bottom when new output arrives.
  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Handle input changes for autocomplete.
  void _onInputChanged() {
    final text = _inputController.text;
    final notifier = ref.read(terminalStateProvider.notifier);
    notifier.setInputText(text);

    if (text.trim().isEmpty) {
      setState(() {
        _showSuggestions = false;
        _suggestions = [];
      });
      return;
    }

    final suggestions = notifier.getSuggestions(text);
    setState(() {
      _suggestions = suggestions;
      _showSuggestions = suggestions.isNotEmpty;
    });
  }

  /// Execute the current input command.
  void _executeCommand() {
    final command = _inputController.text.trim();
    if (command.isEmpty) return;

    setState(() {
      _showSuggestions = false;
      _suggestions = [];
    });

    ref.read(terminalStateProvider.notifier).executeCommand(command);
    _inputController.clear();
    _scrollToBottom();
  }

  /// Handle keyboard shortcuts (Enter to execute, Up/Down for history).
  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        ref.read(terminalStateProvider.notifier).historyUp();
        _inputController.text = ref.read(terminalStateProvider).inputText;
        _inputController.selection = TextSelection.collapsed(
          offset: _inputController.text.length,
        );
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        ref.read(terminalStateProvider.notifier).historyDown();
        _inputController.text = ref.read(terminalStateProvider).inputText;
        _inputController.selection = TextSelection.collapsed(
          offset: _inputController.text.length,
        );
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (!_showSuggestions) {
          _executeCommand();
          return KeyEventResult.handled;
        }
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (_showSuggestions) {
          setState(() => _showSuggestions = false);
          return KeyEventResult.handled;
        }
      }
      if (event.logicalKey == LogicalKeyboardKey.tab) {
        if (_suggestions.isNotEmpty) {
          _inputController.text = _suggestions.first;
          _inputController.selection = TextSelection.collapsed(
            offset: _inputController.text.length,
          );
          setState(() => _showSuggestions = false);
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(terminalStateProvider);
    final quickCommands = ref.watch(quickCommandsProvider);

    // Auto-scroll when output changes.
    if (state.autoScroll && state.outputLines.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }

    return Scaffold(
      backgroundColor: AppTheme.editorBackground,
      appBar: _buildAppBar(context, state),
      body: Column(
        children: [
          // ── Quick Commands Bar ─────────────────────────────
          _QuickCommandsBar(
            commands: quickCommands,
            onCommandTap: (cmd) {
              ref.read(terminalStateProvider.notifier).executeQuickCommand(cmd);
              _scrollToBottom();
            },
          ),

          // ── Terminal Output Area ───────────────────────────
          Expanded(
            child: Stack(
              children: [
                // Main output area.
                Container(
                  color: AppTheme.editorBackground,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: state.outputLines.length,
                    itemBuilder: (context, index) {
                      final line = state.outputLines[index];
                      return _TerminalLineWidget(line: line);
                    },
                  ),
                ),

                // Empty state.
                if (!state.hasOutput)
                  const Center(
                    child: _EmptyTerminalState(),
                  ),

                // Suggestions overlay.
                if (_showSuggestions && _suggestions.isNotEmpty)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _SuggestionsOverlay(
                      suggestions: _suggestions,
                      onSelect: (suggestion) {
                        _inputController.text = suggestion;
                        _inputController.selection = TextSelection.collapsed(
                          offset: _inputController.text.length,
                        );
                        setState(() => _showSuggestions = false);
                        _inputFocusNode.requestFocus();
                      },
                    ),
                  ),
              ],
            ),
          ),

          // ── Status Bar ─────────────────────────────────────
          _StatusBar(state: state),

          // ── Command Input ──────────────────────────────────
          _CommandInput(
            controller: _inputController,
            focusNode: _inputFocusNode,
            prompt: state.prompt,
            isExecuting: state.isExecuting,
            onSubmit: _executeCommand,
            onKeyEvent: _handleKeyEvent,
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, TerminalState state) {
    return AppBar(
      backgroundColor: AppTheme.backgroundElevated,
      foregroundColor: AppTheme.textPrimary,
      elevation: 0,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.terminal,
            size: 18,
            color: AppTheme.accent,
          ),
          const SizedBox(width: 8),
          const Text(
            'Terminal',
            style: TextStyle(
              fontFamily: AppTheme.fontCode,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(width: 12),
          // Executing indicator.
          if (state.isExecuting)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accent),
              ),
            ),
        ],
      ),
      actions: [
        // Kill button (visible when executing).
        if (state.isExecuting)
          IconButton(
            onPressed: () {
              ref.read(terminalStateProvider.notifier).killProcess();
            },
            icon: const Icon(Icons.stop, color: AppTheme.error, size: 20),
            tooltip: 'Kill process',
          ),

        // Copy output button.
        IconButton(
          onPressed: state.hasOutput
              ? () {
                  final text = state.outputLines
                      .map((l) => l.text)
                      .join('\n');
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Output copied to clipboard',
                        style: TextStyle(fontFamily: AppTheme.fontCode),
                      ),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              : null,
          icon: Icon(
            Icons.copy,
            size: 18,
            color: state.hasOutput ? AppTheme.textSecondary : AppTheme.textDisabled,
          ),
          tooltip: 'Copy output',
        ),

        // Clear button.
        IconButton(
          onPressed: state.hasOutput
              ? () => ref.read(terminalStateProvider.notifier).clearOutput()
              : null,
          icon: Icon(
            Icons.delete_outline,
            size: 18,
            color: state.hasOutput ? AppTheme.textSecondary : AppTheme.textDisabled,
          ),
          tooltip: 'Clear terminal',
        ),

        const SizedBox(width: 8),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Quick Commands Bar
// ═══════════════════════════════════════════════════════════════════════════

/// Horizontal scrollable bar of quick command chips.
class _QuickCommandsBar extends StatelessWidget {
  final List<QuickCommand> commands;
  final ValueChanged<String> onCommandTap;

  const _QuickCommandsBar({
    required this.commands,
    required this.onCommandTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      color: AppTheme.backgroundElevated,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: commands.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final cmd = commands[index];
          return _QuickCommandChip(
            label: cmd.label,
            onTap: () => onCommandTap(cmd.command),
          );
        },
      ),
    );
  }
}

/// A single quick command chip.
class _QuickCommandChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickCommandChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface.withOpacity(0.6),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: AppTheme.fontCode,
              fontSize: 11,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Terminal Line Widget
// ═══════════════════════════════════════════════════════════════════════════

/// Displays a single line of terminal output with appropriate color-coding.
class _TerminalLineWidget extends StatelessWidget {
  final TerminalLine line;

  const _TerminalLineWidget({required this.line});

  @override
  Widget build(BuildContext context) {
    return SelectableText(
      line.text,
      style: TextStyle(
        fontFamily: AppTheme.fontCode,
        fontSize: 12.5,
        height: 1.4,
        color: _colorForType(line.type),
      ),
      enableInteractiveSelection: true,
    );
  }

  Color _colorForType(TerminalLineType type) {
    switch (type) {
      case TerminalLineType.error:
        return const Color(0xFFF87171); // Red-400
      case TerminalLineType.warning:
        return const Color(0xFFFBBF24); // Amber-400
      case TerminalLineType.success:
        return const Color(0xFF34D399); // Emerald-400
      case TerminalLineType.info:
        return const Color(0xFF60A5FA); // Blue-400
      case TerminalLineType.command:
        return const Color(0xFFA78BFA); // Violet-400
      case TerminalLineType.system:
        return const Color(0xFF9CA3AF); // Gray-400
      case TerminalLineType.normal:
        return const Color(0xFFD1D5DB); // Gray-300
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Suggestions Overlay
// ═══════════════════════════════════════════════════════════════════════════

/// Dropdown overlay showing command autocomplete suggestions.
class _SuggestionsOverlay extends StatelessWidget {
  final List<String> suggestions;
  final ValueChanged<String> onSelect;

  const _SuggestionsOverlay({
    required this.suggestions,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: suggestions.asMap().entries.map((entry) {
            final index = entry.key;
            final suggestion = entry.value;
            return Material(
              color: index == 0 ? AppTheme.surfaceHover : AppTheme.surface,
              child: InkWell(
                onTap: () => onSelect(suggestion),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    suggestion,
                    style: TextStyle(
                      fontFamily: AppTheme.fontCode,
                      fontSize: 13,
                      color: index == 0
                          ? AppTheme.accent
                          : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Status Bar
// ═══════════════════════════════════════════════════════════════════════════

/// Bottom status bar showing execution state and line count.
class _StatusBar extends StatelessWidget {
  final TerminalState state;

  const _StatusBar({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      color: AppTheme.editorGutter,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Execution indicator.
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: state.isExecuting
                  ? AppTheme.warning
                  : AppTheme.success,
            ),
          ),
          const SizedBox(width: 8),

          // Status text.
          Text(
            state.isExecuting
                ? 'Running...'
                : state.lastResult != null
                    ? (state.lastResult!.success
                        ? 'Done'
                        : 'Failed (exit ${state.lastResult!.exitCode})')
                    : 'Ready',
            style: const TextStyle(
              fontFamily: AppTheme.fontCode,
              fontSize: 10,
              color: AppTheme.textTertiary,
            ),
          ),

          const Spacer(),

          // Line count.
          Text(
            '${state.lineCount} lines',
            style: const TextStyle(
              fontFamily: AppTheme.fontCode,
              fontSize: 10,
              color: AppTheme.textTertiary,
            ),
          ),

          const SizedBox(width: 12),

          // Working directory.
          if (state.workingDirectory != null)
            Flexible(
              child: Text(
                state.workingDirectory!.split('/').last,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppTheme.fontCode,
                  fontSize: 10,
                  color: AppTheme.accent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Command Input
// ═══════════════════════════════════════════════════════════════════════════

/// The command input area at the bottom of the terminal.
///
/// Features a green prompt indicator and handles keyboard events
/// for history navigation and command execution.
class _CommandInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String prompt;
  final bool isExecuting;
  final VoidCallback onSubmit;
  final KeyEventResult Function(KeyEvent) onKeyEvent;

  const _CommandInput({
    required this.controller,
    required this.focusNode,
    required this.prompt,
    required this.isExecuting,
    required this.onSubmit,
    required this.onKeyEvent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.backgroundElevated,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Green prompt indicator.
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.accent,
            ),
          ),
          const SizedBox(width: 8),

          // Prompt text.
          Text(
            prompt,
            style: const TextStyle(
              fontFamily: AppTheme.fontCode,
              fontSize: 12.5,
              color: AppTheme.accent,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(width: 4),

          // Input field.
          Expanded(
            child: KeyboardListener(
              focusNode: FocusNode(),
              onKeyEvent: onKeyEvent,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: !isExecuting,
                style: const TextStyle(
                  fontFamily: AppTheme.fontCode,
                  fontSize: 12.5,
                  color: AppTheme.textPrimary,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: isExecuting
                      ? 'Command running...'
                      : 'Type a command...',
                  hintStyle: TextStyle(
                    fontFamily: AppTheme.fontCode,
                    fontSize: 12.5,
                    color: AppTheme.textDisabled,
                  ),
                ),
                onSubmitted: (_) => onSubmit(),
                cursorColor: AppTheme.accent,
                cursorWidth: 2,
                cursorHeight: 16,
              ),
            ),
          ),

          // Send / executing indicator.
          if (isExecuting)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accent),
              ),
            )
          else
            IconButton(
              onPressed: onSubmit,
              icon: const Icon(
                Icons.arrow_forward,
                size: 18,
                color: AppTheme.accent,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: 'Execute',
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Empty Terminal State
// ═══════════════════════════════════════════════════════════════════════════

/// Shown when the terminal has no output yet.
class _EmptyTerminalState extends StatelessWidget {
  const _EmptyTerminalState();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.terminal,
          size: 48,
          color: AppTheme.textDisabled.withOpacity(0.5),
        ),
        const SizedBox(height: 16),
        Text(
          'MobileCode Terminal',
          style: TextStyle(
            fontFamily: AppTheme.fontCode,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.textTertiary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Run flutter, dart, git, npm, and more',
          style: TextStyle(
            fontFamily: AppTheme.fontCode,
            fontSize: 12,
            color: AppTheme.textDisabled,
          ),
        ),
        const SizedBox(height: 24),
        // Quick hint chips.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            _HintChip(label: 'flutter doctor'),
            _HintChip(label: 'flutter pub get'),
            _HintChip(label: 'git status'),
            _HintChip(label: 'dart analyze'),
          ],
        ),
      ],
    );
  }
}

/// A hint chip showing example commands.
class _HintChip extends StatelessWidget {
  final String label;

  const _HintChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppTheme.fontCode,
          fontSize: 11,
          color: AppTheme.textTertiary,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Terminal FAB Menu
// ═══════════════════════════════════════════════════════════════════════════

/// Floating action button with a menu of terminal actions.
///
/// Attach to the terminal screen for quick access to common operations.
class TerminalFabMenu extends StatelessWidget {
  final VoidCallback? onClear;
  final VoidCallback? onCopy;
  final VoidCallback? onKill;
  final bool isExecuting;

  const TerminalFabMenu({
    super.key,
    this.onClear,
    this.onCopy,
    this.onKill,
    this.isExecuting = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Clear button.
        if (onClear != null)
          _MiniFab(
            icon: Icons.delete_outline,
            tooltip: 'Clear',
            onTap: onClear!,
          ),

        const SizedBox(height: 8),

        // Copy button.
        if (onCopy != null)
          _MiniFab(
            icon: Icons.copy,
            tooltip: 'Copy output',
            onTap: onCopy!,
          ),

        const SizedBox(height: 8),

        // Kill button.
        if (isExecuting && onKill != null)
          _MiniFab(
            icon: Icons.stop,
            tooltip: 'Kill process',
            color: AppTheme.error,
            onTap: onKill!,
          ),
      ],
    );
  }
}

/// Small floating action button.
class _MiniFab extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback onTap;

  const _MiniFab({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      elevation: 4,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.border),
          ),
          child: Icon(
            icon,
            size: 18,
            color: color ?? AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
