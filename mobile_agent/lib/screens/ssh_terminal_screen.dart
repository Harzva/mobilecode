// lib/screens/ssh_terminal_screen.dart
// SSH Terminal Screen — Interactive terminal connected to a remote host.
//
// Features: terminal output display, command input with history, host info
// header, file transfer actions, disconnect, and quick remote commands.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../providers/ssh_provider.dart';
import '../providers/terminal_provider.dart';
import '../services/ssh_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SSH Terminal Screen
// ═══════════════════════════════════════════════════════════════════════════

/// Terminal screen connected to a remote SSH host.
///
/// Provides an interactive terminal experience for executing commands
/// on a remote server. Features a host info header, command history,
/// file transfer actions, and disconnect capability.
class SshTerminalScreen extends ConsumerStatefulWidget {
  final SshHostConfig hostConfig;

  const SshTerminalScreen({
    super.key,
    required this.hostConfig,
  });

  @override
  ConsumerState<SshTerminalScreen> createState() => _SshTerminalScreenState();
}

class _SshTerminalScreenState extends ConsumerState<SshTerminalScreen> {
  final _inputController = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final _commandHistory = <String>[];
  var _historyIndex = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inputFocusNode.requestFocus();
      // Update last connected time.
      final updated = widget.hostConfig.copyWith(
        lastConnectedAt: DateTime.now(),
      );
      ref.read(sshProvider.notifier).saveHost(updated);
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
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

  /// Execute a command on the remote host.
  Future<void> _executeCommand(String command) async {
    if (command.trim().isEmpty) return;

    // Add to history.
    if (_commandHistory.isEmpty || _commandHistory.last != command) {
      _commandHistory.add(command);
    }
    _historyIndex = -1;

    // Add command line to output.
    ref.read(sshTerminalOutputProvider(widget.hostConfig.id).notifier).addLine(
          TerminalLine.command('${widget.hostConfig.username}@\$ $command'),
        );

    _inputController.clear();
    _scrollToBottom();

    try {
      final ssh = ref.read(sshProvider.notifier);
      final result = await ssh.executeOnHost(widget.hostConfig.id, command);

      // Output stdout.
      if (result.stdout.isNotEmpty) {
        const splitter = LineSplitter();
        for (final line in splitter.convert(result.stdout)) {
          if (line.isNotEmpty) {
            ref
                .read(sshTerminalOutputProvider(widget.hostConfig.id).notifier)
                .addLine(TerminalLine.normal(line));
          }
        }
      }

      // Output stderr.
      if (result.stderr.isNotEmpty) {
        const splitter = LineSplitter();
        for (final line in splitter.convert(result.stderr)) {
          if (line.isNotEmpty) {
            ref
                .read(sshTerminalOutputProvider(widget.hostConfig.id).notifier)
                .addLine(TerminalLine.error(line));
          }
        }
      }

      // Exit code indicator.
      if (result.exitCode != 0) {
        ref
            .read(sshTerminalOutputProvider(widget.hostConfig.id).notifier)
            .addLine(
          TerminalLine.error(
            '[exit code ${result.exitCode}] (${result.duration.inSeconds}s)',
          ),
        );
      } else {
        ref
            .read(sshTerminalOutputProvider(widget.hostConfig.id).notifier)
            .addLine(
          TerminalLine.success('[done] (${result.duration.inSeconds}s)'),
        );
      }
    } on SshServiceException catch (e) {
      ref.read(sshTerminalOutputProvider(widget.hostConfig.id).notifier).addLine(
            TerminalLine.error('SSH Error: $e'),
          );
    } catch (e) {
      ref.read(sshTerminalOutputProvider(widget.hostConfig.id).notifier).addLine(
            TerminalLine.error('Error: $e'),
          );
    }

    _scrollToBottom();
  }

  /// Handle keyboard events for history navigation.
  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        if (_commandHistory.isNotEmpty) {
          setState(() {
            _historyIndex = (_historyIndex < 0
                    ? _commandHistory.length - 1
                    : (_historyIndex - 1).clamp(0, _commandHistory.length - 1));
            _inputController.text = _commandHistory[_historyIndex];
            _inputController.selection = TextSelection.collapsed(
              offset: _inputController.text.length,
            );
          });
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        if (_historyIndex >= 0) {
          setState(() {
            _historyIndex++;
            if (_historyIndex >= _commandHistory.length) {
              _historyIndex = -1;
              _inputController.clear();
            } else {
              _inputController.text = _commandHistory[_historyIndex];
              _inputController.selection = TextSelection.collapsed(
                offset: _inputController.text.length,
              );
            }
          });
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        _executeCommand(_inputController.text);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final outputLines = ref.watch(sshTerminalOutputProvider(widget.hostConfig.id));
    final connectionState = ref.watch(
      sshConnectionStateProvider(widget.hostConfig.id),
    );

    // Auto-scroll when output changes.
    if (outputLines.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }

    final isConnected = connectionState == SshConnectionStatus.connected;

    return Scaffold(
      backgroundColor: AppTheme.editorBackground,
      appBar: _buildAppBar(isConnected),
      body: Column(
        children: [
          // Host info header.
          _HostInfoHeader(
            hostConfig: widget.hostConfig,
            isConnected: isConnected,
          ),

          // Quick commands bar.
          _QuickRemoteCommands(
            onCommandTap: (cmd) => _executeCommand(cmd),
            isEnabled: isConnected,
          ),

          // Terminal output area.
          Expanded(
            child: Container(
              color: AppTheme.editorBackground,
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: outputLines.length,
                itemBuilder: (context, index) {
                  final line = outputLines[index];
                  return _TerminalLineWidget(line: line);
                },
              ),
            ),
          ),

          // Empty state.
          if (outputLines.isEmpty)
            Expanded(
              child: _EmptySshTerminal(
                hostName: widget.hostConfig.name,
                isConnected: isConnected,
              ),
            ),

          // Command input.
          _SshCommandInput(
            controller: _inputController,
            focusNode: _inputFocusNode,
            prompt: '${widget.hostConfig.username}@\$ ',
            isEnabled: isConnected,
            onSubmit: _executeCommand,
            onKeyEvent: _handleKeyEvent,
          ),
        ],
      ),
      floatingActionButton: isConnected
          ? FloatingActionButton.small(
              onPressed: () => _showFileActions(context),
              backgroundColor: AppTheme.primary,
              child: const Icon(Icons.folder_open,
                  color: AppTheme.textOnPrimary, size: 20),
            )
          : null,
    );
  }

  PreferredSizeWidget _buildAppBar(bool isConnected) {
    return AppBar(
      backgroundColor: AppTheme.backgroundElevated,
      foregroundColor: AppTheme.textPrimary,
      elevation: 0,
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back, color: AppTheme.textSecondary, size: 20),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.terminal,
            size: 16,
            color: isConnected ? AppTheme.accent : AppTheme.error,
          ),
          const SizedBox(width: 8),
          Text(
            widget.hostConfig.name,
            style: const TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isConnected ? AppTheme.success : AppTheme.error,
              boxShadow: isConnected
                  ? [
                      BoxShadow(
                        color: AppTheme.success.withOpacity(0.4),
                        blurRadius: 4,
                      ),
                    ]
                  : null,
            ),
          ),
        ],
      ),
      actions: [
        // Copy output.
        Consumer(
          builder: (context, ref, _) {
            final outputLines = ref.watch(
              sshTerminalOutputProvider(widget.hostConfig.id),
            );
            return IconButton(
              onPressed: outputLines.isNotEmpty
                  ? () {
                      final text = outputLines.map((l) => l.text).join('\n');
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
                color: outputLines.isNotEmpty
                    ? AppTheme.textSecondary
                    : AppTheme.textDisabled,
              ),
              tooltip: 'Copy output',
            );
          },
        ),

        // Clear.
        IconButton(
          onPressed: () {
            ref
                .read(sshTerminalOutputProvider(widget.hostConfig.id).notifier)
                .clear();
          },
          icon: const Icon(Icons.delete_outline,
              color: AppTheme.textSecondary, size: 18),
          tooltip: 'Clear terminal',
        ),

        // Disconnect.
        IconButton(
          onPressed: () => _confirmDisconnect(context),
          icon: const Icon(Icons.link_off, color: AppTheme.error, size: 18),
          tooltip: 'Disconnect',
        ),

        const SizedBox(width: 8),
      ],
    );
  }

  void _showFileActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _FileActionsSheet(hostConfig: widget.hostConfig),
    );
  }

  void _confirmDisconnect(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text(
          'Disconnect?',
          style: TextStyle(
            fontFamily: AppTheme.fontBody,
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Disconnect from "${widget.hostConfig.name}"?',
          style: const TextStyle(
            fontFamily: AppTheme.fontBody,
            color: AppTheme.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(sshProvider.notifier).disconnect(widget.hostConfig.id);
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text(
              'Disconnect',
              style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Host Info Header
// ═══════════════════════════════════════════════════════════════════════════

/// Header bar showing connection status and host details.
class _HostInfoHeader extends StatelessWidget {
  final SshHostConfig hostConfig;
  final bool isConnected;

  const _HostInfoHeader({
    required this.hostConfig,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppTheme.backgroundElevated,
      child: Row(
        children: [
          Icon(
            Icons.computer,
            size: 14,
            color: isConnected ? AppTheme.accent : AppTheme.textTertiary,
          ),
          const SizedBox(width: 8),
          Text(
            hostConfig.displayAddress,
            style: TextStyle(
              fontFamily: AppTheme.fontCode,
              fontSize: 11,
              color: isConnected ? AppTheme.accent : AppTheme.textSecondary,
            ),
          ),
          const Spacer(),
          if (hostConfig.workingDirectory != null)
            Flexible(
              child: Text(
                hostConfig.workingDirectory!,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppTheme.fontCode,
                  fontSize: 10,
                  color: AppTheme.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Quick Remote Commands Bar
// ═══════════════════════════════════════════════════════════════════════════

/// Horizontal scrollable bar of quick remote command chips.
class _QuickRemoteCommands extends StatelessWidget {
  final ValueChanged<String> onCommandTap;
  final bool isEnabled;

  const _QuickRemoteCommands({
    required this.onCommandTap,
    required this.isEnabled,
  });

  static const _commands = [
    _QuickCmd(label: 'ls -la', command: 'ls -la'),
    _QuickCmd(label: 'pwd', command: 'pwd'),
    _QuickCmd(label: 'whoami', command: 'whoami'),
    _QuickCmd(label: 'uname -a', command: 'uname -a'),
    _QuickCmd(label: 'df -h', command: 'df -h'),
    _QuickCmd(label: 'free -m', command: 'free -m'),
    _QuickCmd(label: 'top -bn1', command: 'top -bn1 | head -20'),
    _QuickCmd(label: 'ps aux', command: 'ps aux --sort=-%cpu | head -20'),
    _QuickCmd(label: 'netstat', command: 'ss -tlnp'),
    _QuickCmd(label: 'docker ps', command: 'docker ps'),
    _QuickCmd(label: 'git status', command: 'git status'),
    _QuickCmd(label: 'npm list', command: 'npm list -g --depth=0'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: AppTheme.backgroundElevated,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: _commands.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final cmd = _commands[index];
          return _QuickCmdChip(
            label: cmd.label,
            onTap: isEnabled ? () => onCommandTap(cmd.command) : null,
          );
        },
      ),
    );
  }
}

class _QuickCmd {
  final String label;
  final String command;
  const _QuickCmd({required this.label, required this.command});
}

class _QuickCmdChip extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _QuickCmdChip({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onTap != null
          ? AppTheme.surface.withOpacity(0.6)
          : AppTheme.surface.withOpacity(0.2),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppTheme.fontCode,
              fontSize: 11,
              color: onTap != null ? AppTheme.textSecondary : AppTheme.textDisabled,
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

/// Displays a single line of terminal output with color-coding.
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
        return const Color(0xFFF87171);
      case TerminalLineType.warning:
        return const Color(0xFFFBBF24);
      case TerminalLineType.success:
        return const Color(0xFF34D399);
      case TerminalLineType.info:
        return const Color(0xFF60A5FA);
      case TerminalLineType.command:
        return const Color(0xFFA78BFA);
      case TerminalLineType.system:
        return const Color(0xFF9CA3AF);
      case TerminalLineType.normal:
        return const Color(0xFFD1D5DB);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SSH Command Input
// ═══════════════════════════════════════════════════════════════════════════

/// Command input area for the SSH terminal.
class _SshCommandInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String prompt;
  final bool isEnabled;
  final void Function(String) onSubmit;
  final KeyEventResult Function(KeyEvent) onKeyEvent;

  const _SshCommandInput({
    required this.controller,
    required this.focusNode,
    required this.prompt,
    required this.isEnabled,
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
          // Prompt indicator.
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isEnabled ? AppTheme.accent : AppTheme.error,
            ),
          ),
          const SizedBox(width: 8),

          // Prompt text.
          Text(
            prompt,
            style: TextStyle(
              fontFamily: AppTheme.fontCode,
              fontSize: 12.5,
              color: isEnabled ? AppTheme.accent : AppTheme.error,
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
                enabled: isEnabled,
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
                  hintText: isEnabled
                      ? 'Type a remote command...'
                      : 'Disconnected',
                  hintStyle: TextStyle(
                    fontFamily: AppTheme.fontCode,
                    fontSize: 12.5,
                    color: AppTheme.textDisabled,
                  ),
                ),
                onSubmitted: onSubmit,
                cursorColor: AppTheme.accent,
                cursorWidth: 2,
                cursorHeight: 16,
              ),
            ),
          ),

          // Send button.
          if (isEnabled)
            IconButton(
              onPressed: () => onSubmit(controller.text),
              icon: const Icon(Icons.arrow_forward,
                  size: 18, color: AppTheme.accent),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: 'Execute',
            )
          else
            const Icon(Icons.cloud_off,
                size: 18, color: AppTheme.error),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Empty SSH Terminal State
// ═══════════════════════════════════════════════════════════════════════════

/// Shown when the SSH terminal has no output.
class _EmptySshTerminal extends StatelessWidget {
  final String hostName;
  final bool isConnected;

  const _EmptySshTerminal({
    required this.hostName,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isConnected ? Icons.cloud_done : Icons.cloud_off,
            size: 48,
            color: isConnected
                ? AppTheme.accent.withOpacity(0.5)
                : AppTheme.error.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            isConnected ? 'Connected to $hostName' : 'Disconnected',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isConnected ? AppTheme.textTertiary : AppTheme.error,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isConnected
                ? 'Type commands to execute on the remote server'
                : 'Connection lost. Reconnect from the hosts screen.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 12,
              color: AppTheme.textDisabled,
            ),
          ),
          if (isConnected) ...[
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _HintChip(label: 'ls -la'),
                _HintChip(label: 'uname -a'),
                _HintChip(label: 'pwd'),
                _HintChip(label: 'whoami'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

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
// File Actions Sheet
// ═══════════════════════════════════════════════════════════════════════════

/// Bottom sheet with file transfer and remote file management actions.
class _FileActionsSheet extends ConsumerWidget {
  final SshHostConfig hostConfig;

  const _FileActionsSheet({required this.hostConfig});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.folder_open, color: AppTheme.accent, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'File Operations',
                    style: TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AppTheme.border, height: 1),
            const SizedBox(height: 8),

            // List remote directory.
            _FileActionTile(
              icon: Icons.folder_copy_outlined,
              title: 'List Remote Directory',
              subtitle: 'Browse files on the remote host',
              onTap: () {
                Navigator.pop(context);
                _promptListDirectory(context, ref);
              },
            ),

            // Upload file.
            _FileActionTile(
              icon: Icons.upload_file,
              title: 'Upload File',
              subtitle: 'Send a file to the remote host',
              onTap: () {
                Navigator.pop(context);
                _promptUpload(context, ref);
              },
            ),

            // Download file.
            _FileActionTile(
              icon: Icons.download,
              title: 'Download File',
              subtitle: 'Fetch a file from the remote host',
              onTap: () {
                Navigator.pop(context);
                _promptDownload(context, ref);
              },
            ),

            // Create directory.
            _FileActionTile(
              icon: Icons.create_new_folder_outlined,
              title: 'Create Directory',
              subtitle: 'Make a new directory on the remote host',
              onTap: () {
                Navigator.pop(context);
                _promptCreateDir(context, ref);
              },
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _promptListDirectory(BuildContext context, WidgetRef ref) {
    _showPromptDialog(
      context,
      title: 'List Directory',
      label: 'Remote path',
      hint: '/home/${hostConfig.username}',
      icon: Icons.folder_copy_outlined,
      onConfirm: (path) async {
        try {
          final ssh = ref.read(sshProvider.notifier);
          final files = await ssh.listDirectory(hostConfig.id, path);

          if (!context.mounted) return;

          // Show results in a bottom sheet.
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: AppTheme.surface,
            builder: (_) => _DirectoryListingSheet(files: files, path: path),
          );
        } catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error),
          );
        }
      },
    );
  }

  void _promptUpload(BuildContext context, WidgetRef ref) {
    // Simplified: would use file_picker in production.
    _showTwoFieldDialog(
      context,
      title: 'Upload File',
      label1: 'Local path',
      hint1: '/storage/emulated/0/Download/file.txt',
      label2: 'Remote path',
      hint2: '/home/${hostConfig.username}/file.txt',
      icon: Icons.upload_file,
      onConfirm: (local, remote) async {
        try {
          final ssh = ref.read(sshProvider.notifier);
          await ssh.uploadFile(hostConfig.id, local, remote);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File uploaded successfully'),
              backgroundColor: AppTheme.success,
            ),
          );
        } catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Upload failed: $e'), backgroundColor: AppTheme.error),
          );
        }
      },
    );
  }

  void _promptDownload(BuildContext context, WidgetRef ref) {
    _showTwoFieldDialog(
      context,
      title: 'Download File',
      label1: 'Remote path',
      hint1: '/home/${hostConfig.username}/file.txt',
      label2: 'Local path',
      hint2: '/storage/emulated/0/Download/file.txt',
      icon: Icons.download,
      onConfirm: (remote, local) async {
        try {
          final ssh = ref.read(sshProvider.notifier);
          await ssh.downloadFile(hostConfig.id, remote, local);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File downloaded successfully'),
              backgroundColor: AppTheme.success,
            ),
          );
        } catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Download failed: $e'), backgroundColor: AppTheme.error),
          );
        }
      },
    );
  }

  void _promptCreateDir(BuildContext context, WidgetRef ref) {
    _showPromptDialog(
      context,
      title: 'Create Directory',
      label: 'Directory path',
      hint: '/home/${hostConfig.username}/newdir',
      icon: Icons.create_new_folder_outlined,
      onConfirm: (path) async {
        try {
          final ssh = ref.read(sshProvider.notifier);
          await ssh.createDirectory(hostConfig.id, path);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Directory created'),
              backgroundColor: AppTheme.success,
            ),
          );
        } catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error),
          );
        }
      },
    );
  }

  void _showPromptDialog(
    BuildContext context, {
    required String title,
    required String label,
    required String hint,
    required IconData icon,
    required ValueChanged<String> onConfirm,
  }) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Row(
          children: [
            Icon(icon, color: AppTheme.accent, size: 20),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    fontFamily: AppTheme.fontBody,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(
              fontFamily: AppTheme.fontCode,
              fontSize: 13,
              color: AppTheme.textPrimary),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            filled: true,
            fillColor: AppTheme.surfaceInput,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirm(controller.text.trim());
            },
            child: const Text('Confirm',
                style: TextStyle(
                    color: AppTheme.accent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _showTwoFieldDialog(
    BuildContext context, {
    required String title,
    required String label1,
    required String hint1,
    required String label2,
    required String hint2,
    required IconData icon,
    required void Function(String, String) onConfirm,
  }) {
    final controller1 = TextEditingController();
    final controller2 = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Row(
          children: [
            Icon(icon, color: AppTheme.accent, size: 20),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    fontFamily: AppTheme.fontBody,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller1,
              style: const TextStyle(
                  fontFamily: AppTheme.fontCode,
                  fontSize: 13,
                  color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: label1,
                hintText: hint1,
                filled: true,
                fillColor: AppTheme.surfaceInput,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller2,
              style: const TextStyle(
                  fontFamily: AppTheme.fontCode,
                  fontSize: 13,
                  color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: label2,
                hintText: hint2,
                filled: true,
                fillColor: AppTheme.surfaceInput,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirm(controller1.text.trim(), controller2.text.trim());
            },
            child: const Text('Confirm',
                style: TextStyle(
                    color: AppTheme.accent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// File Action Tile
// ═══════════════════════════════════════════════════════════════════════════

/// List tile for file action items.
class _FileActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _FileActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.accent, size: 22),
      title: Text(title,
          style: const TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppTheme.textPrimary)),
      subtitle: Text(subtitle,
          style: const TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 12,
              color: AppTheme.textTertiary)),
      trailing: const Icon(Icons.chevron_right,
          color: AppTheme.textTertiary, size: 18),
      onTap: onTap,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Directory Listing Sheet
// ═══════════════════════════════════════════════════════════════════════════

/// Bottom sheet displaying a remote directory listing.
class _DirectoryListingSheet extends StatelessWidget {
  final List<RemoteFileInfo> files;
  final String path;

  const _DirectoryListingSheet({
    required this.files,
    required this.path,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(Icons.folder_copy_outlined,
                        color: AppTheme.accent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        path,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontCode,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${files.length} items',
                      style: const TextStyle(
                        fontFamily: AppTheme.fontCode,
                        fontSize: 11,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: AppTheme.border, height: 1),
              Expanded(
                child: files.isEmpty
                    ? const Center(
                        child: Text(
                          'Empty directory',
                          style: TextStyle(
                            fontFamily: AppTheme.fontBody,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: files.length,
                        itemBuilder: (context, index) {
                          final file = files[index];
                          return ListTile(
                            leading: Icon(
                              file.isDirectory
                                  ? Icons.folder
                                  : Icons.insert_drive_file,
                              color: file.isDirectory
                                  ? AppTheme.warning
                                  : AppTheme.textSecondary,
                              size: 20,
                            ),
                            title: Text(file.name,
                                style: const TextStyle(
                                    fontFamily: AppTheme.fontCode,
                                    fontSize: 13,
                                    color: AppTheme.textPrimary)),
                            subtitle: Text(
                              '${file.permissions}  ${file.formattedSize}',
                              style: const TextStyle(
                                  fontFamily: AppTheme.fontCode,
                                  fontSize: 11,
                                  color: AppTheme.textTertiary),
                            ),
                            trailing: file.modifiedAt != null
                                ? Text(
                                    '${file.modifiedAt!.month}/${file.modifiedAt!.day}',
                                    style: const TextStyle(
                                        fontFamily: AppTheme.fontCode,
                                        fontSize: 11,
                                        color: AppTheme.textTertiary),
                                  )
                                : null,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
