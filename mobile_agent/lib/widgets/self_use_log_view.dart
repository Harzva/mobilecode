// lib/widgets/self_use_log_view.dart
// Self-Use Log View
//
// Scrolling log of all self-actions being executed.
// Like a terminal output but prettier.
//
// Features:
// - Auto-scrolls to latest entry
// - Color-coded by status:
//   - Running: cyan
//   - Success: green
//   - Failed: red
//   - Pending: gray
// - Timestamps
// - Collapsible details
// - Copy to clipboard
// - Clear log
//
// Design: Dark background, monospace font, colored text

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../models/self_use_session.dart';
import '../models/agent_task.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Self-Use Log View
// ═══════════════════════════════════════════════════════════════════════════

/// Real-time scrolling log of all self-actions being executed.
///
/// Features:
/// - Auto-scrolls to the latest entry
/// - Color-coded entries by action type and status
/// - Timestamps for each entry
/// - Expandable detail view for each entry
/// - Copy to clipboard functionality
/// - Clear log button
///
/// Design: Dark background, monospace font, colored text.
/// Terminal-like aesthetic with modern glassmorphism touches.
class SelfUseLogView extends StatefulWidget {
  /// List of action entries to display.
  final List<SelfActionEntry> actions;

  /// Callback when log is cleared.
  final VoidCallback? onClear;

  /// Whether to auto-scroll to the latest entry.
  final bool autoScroll;

  /// Maximum height of the log view.
  final double? maxHeight;

  const SelfUseLogView({
    super.key,
    required this.actions,
    this.onClear,
    this.autoScroll = true,
    this.maxHeight,
  });

  @override
  State<SelfUseLogView> createState() => _SelfUseLogViewState();
}

class _SelfUseLogViewState extends State<SelfUseLogView> {
  final ScrollController _scrollController = ScrollController();
  final Set<String> _expandedEntries = {};
  final GlobalKey _listKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  @override
  void didUpdateWidget(covariant SelfUseLogView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.actions.length > oldWidget.actions.length && widget.autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _toggleExpanded(String id) {
    setState(() {
      if (_expandedEntries.contains(id)) {
        _expandedEntries.remove(id);
      } else {
        _expandedEntries.add(id);
      }
    });
  }

  Future<void> _copyToClipboard() async {
    final buffer = StringBuffer();
    for (final action in widget.actions) {
      buffer.writeln(
          '[${action.formattedTime}] ${action.statusEmoji} ${action.type.label}: ${action.description}');
      if (action.detail != null) {
        buffer.writeln('    ${action.detail}');
      }
      if (action.result != null) {
        buffer.writeln('    -> ${action.result}');
      }
      if (action.error != null) {
        buffer.writeln('    ERROR: ${action.error}');
      }
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u65E5\u5FD7\u5DF2\u590D\u5236\u5230\u526A\u8D34\u677F',
            style: TextStyle(fontFamily: AppTheme.fontBody),
          ),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.actions.isEmpty) {
      return _emptyLog();
    }

    return Column(
      children: [
        // ── Toolbar ───────────────────────────────────────────────────
        _toolbar(),

        // ── Divider ───────────────────────────────────────────────────
        const Divider(
          height: 1,
          color: AppTheme.divider,
        ),

        // ── Log entries ───────────────────────────────────────────────
        Expanded(
          child: ListView.builder(
            key: _listKey,
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: widget.actions.length,
            itemBuilder: (context, index) {
              final action = widget.actions[index];
              final isLast = index == widget.actions.length - 1;
              return _LogEntryTile(
                action: action,
                isExpanded: _expandedEntries.contains(action.id),
                onToggleExpand: () => _toggleExpanded(action.id),
                isLast: isLast,
              );
            },
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // Toolbar
  // ════════════════════════════════════════════════════════════════════════

  Widget _toolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.surface.withOpacity(0.8),
            AppTheme.surface.withOpacity(0.4),
          ],
        ),
      ),
      child: Row(
        children: [
          // Terminal icon + title
          const Icon(
            Icons.terminal,
            size: 14,
            color: AppTheme.textTertiary,
          ),
          const SizedBox(width: 6),
          const Text(
            '\u6267\u884C\u65E5\u5FD7',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const Spacer(),

          // Entry count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.surfaceHover,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${widget.actions.length} \u6761\u8BB0\u5F55',
              style: const TextStyle(
                fontFamily: AppTheme.fontCode,
                fontSize: 10,
                color: AppTheme.textTertiary,
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Copy button
          _toolbarButton(
            icon: Icons.copy,
            tooltip: '\u590D\u5236\u65E5\u5FD7',
            onTap: _copyToClipboard,
          ),

          // Clear button
          _toolbarButton(
            icon: Icons.clear_all,
            tooltip: '\u6E05\u7A7A\u65E5\u5FD7',
            onTap: () {
              HapticFeedback.lightImpact();
              widget.onClear?.call();
            },
          ),
        ],
      ),
    );
  }

  Widget _toolbarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 14,
            color: AppTheme.textTertiary,
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // Empty Log State
  // ════════════════════════════════════════════════════════════════════════

  Widget _emptyLog() {
    return Column(
      children: [
        _toolbar(),
        const Divider(height: 1, color: AppTheme.divider),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.terminal_outlined,
                  size: 36,
                  color: AppTheme.textTertiary.withOpacity(0.4),
                ),
                const SizedBox(height: 10),
                Text(
                  '\u6682\u65E0\u6267\u884C\u65E5\u5FD7',
                  style: TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 13,
                    color: AppTheme.textTertiary.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '\u5F00\u59CB\u4E00\u4E2A\u4F1A\u8BDD\u540E\u5C06\u663E\u793A\u5B9E\u65F6\u65E5\u5FD7',
                  style: TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 11,
                    color: AppTheme.textDisabled,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Log Entry Tile
// ═══════════════════════════════════════════════════════════════════════════

class _LogEntryTile extends StatelessWidget {
  final SelfActionEntry action;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final bool isLast;

  const _LogEntryTile({
    required this.action,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      color: isLast
          ? action.typeColor.withOpacity(0.03)
          : Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onToggleExpand,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Timestamp
                  _Timestamp(text: action.formattedTime),
                  const SizedBox(width: 8),

                  // Status indicator
                  _StatusDot(color: action.statusColor, isRunning: action.isRunning),
                  const SizedBox(width: 8),

                  // Type label
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: action.typeColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      action.type.label,
                      style: TextStyle(
                        fontFamily: AppTheme.fontCode,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: action.typeColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Description
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          action.description,
                          style: TextStyle(
                            fontFamily: AppTheme.fontBody,
                            fontSize: 12,
                            fontWeight: action.isRunning
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: action.isRunning
                                ? AppTheme.textPrimary
                                : AppTheme.textSecondary,
                          ),
                        ),
                        // Detail (when collapsed, show truncated)
                        if (action.detail != null && !isExpanded)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              action.detail!,
                              style: const TextStyle(
                                fontFamily: AppTheme.fontCode,
                                fontSize: 10,
                                color: AppTheme.textTertiary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Duration (if done)
                  if (action.isDone && action.duration != null)
                    Text(
                      action.durationFormatted,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontCode,
                        fontSize: 10,
                        color: AppTheme.textTertiary,
                      ),
                    ),

                  // Expand arrow
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      size: 16,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expanded detail section
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _detailSection(),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),

          // Divider
          if (!isLast)
            const Divider(
              height: 1,
              indent: 60,
              endIndent: 12,
              color: AppTheme.divider,
            ),
        ],
      ),
    );
  }

  Widget _detailSection() {
    return Container(
      margin: const EdgeInsets.only(left: 60, right: 12, bottom: 8, top: 2),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.background.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Detail text
          if (action.detail != null)
            _DetailRow(label: '\u8BE6\u60C5', value: action.detail!),

          // Result
          if (action.result != null)
            _DetailRow(
              label: '\u7ED3\u679C',
              value: action.result!,
              valueColor: AppTheme.success,
            ),

          // Error
          if (action.error != null)
            _DetailRow(
              label: '\u9519\u8BEF',
              value: action.error!,
              valueColor: AppTheme.error,
            ),

          // Timing info
          const SizedBox(height: 6),
          Row(
            children: [
              _DetailRow(
                label: '\u5F00\u59CB',
                value: action.formattedTime,
                compact: true,
              ),
              if (action.completedAt != null) ...[
                const SizedBox(width: 16),
                _DetailRow(
                  label: '\u7ED3\u675F',
                  value: _formatTime(action.completedAt!),
                  compact: true,
                ),
                const SizedBox(width: 16),
                _DetailRow(
                  label: '\u8017\u65F6',
                  value: action.durationFormatted,
                  valueColor: AppTheme.accent,
                  compact: true,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Timestamp Widget
// ═══════════════════════════════════════════════════════════════════════════

class _Timestamp extends StatelessWidget {
  final String text;

  const _Timestamp({required this.text});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 50,
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: AppTheme.fontCode,
          fontSize: 10,
          color: AppTheme.textDisabled,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Status Dot Widget
// ═══════════════════════════════════════════════════════════════════════════

class _StatusDot extends StatefulWidget {
  final Color color;
  final bool isRunning;

  const _StatusDot({required this.color, required this.isRunning});

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (widget.isRunning) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _StatusDot old) {
    super.didUpdateWidget(old);
    if (widget.isRunning && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.isRunning && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        return Container(
          width: 7 + (_pulse.value * 3),
          height: 7 + (_pulse.value * 3),
          decoration: BoxDecoration(
            color: widget.color.withOpacity(0.8 + (_pulse.value * 0.2)),
            shape: BoxShape.circle,
            boxShadow: widget.isRunning
                ? [
                    BoxShadow(
                      color: widget.color.withOpacity(0.3 * (1 - _pulse.value)),
                      blurRadius: 6 + (_pulse.value * 4),
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Detail Row
// ═══════════════════════════════════════════════════════════════════════════

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool compact;

  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontFamily: AppTheme.fontCode,
              fontSize: 10,
              color: AppTheme.textDisabled,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: AppTheme.fontCode,
              fontSize: 10,
              color: valueColor ?? AppTheme.textSecondary,
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontFamily: AppTheme.fontCode,
              fontSize: 10,
              color: AppTheme.textDisabled,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: AppTheme.fontCode,
                fontSize: 11,
                color: valueColor ?? AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
