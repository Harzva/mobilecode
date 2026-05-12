// lib/widgets/self_use_mini_bar.dart
// Self-Use Mini Bar
//
// Compact bar shown at bottom of screen when self-use is active.
// Doesn't take much space but shows essential info.
//
// Layout (single row):
// [Robot] [Action name...] [Progress Bar] [Pause] [Cancel]
//
// Tap to expand full plan sidebar.
// Swipe up to expand.
//
// Design: Glassmorphism, compact, unobtrusive

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../models/self_use_session.dart';
import '../models/agent_task.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Self-Use Mini Bar
// ═══════════════════════════════════════════════════════════════════════════

/// Compact status bar shown at the bottom of the screen during self-use.
///
/// Displays essential session information in a single row:
/// - Robot icon with session status
/// - Current action name
/// - Progress percentage with bar
/// - Pause/Resume and Cancel buttons
///
/// Features:
/// - Tap to expand full plan sidebar
/// - Swipe up gesture to expand
/// - Glassmorphism design that doesn't obstruct content
/// - Smooth animations for progress updates
class SelfUseMiniBar extends StatefulWidget {
  /// The active self-use session to display.
  final SelfUseSession session;

  /// Called when the bar is tapped to expand.
  final VoidCallback? onExpand;

  /// Called when pause/resume is tapped.
  final VoidCallback? onPause;

  /// Called when cancel is tapped.
  final VoidCallback? onCancel;

  /// Called when the log toggle is tapped.
  final VoidCallback? onToggleLog;

  /// Whether the log panel is currently visible.
  final bool isLogVisible;

  const SelfUseMiniBar({
    super.key,
    required this.session,
    this.onExpand,
    this.onPause,
    this.onCancel,
    this.onToggleLog,
    this.isLogVisible = false,
  });

  @override
  State<SelfUseMiniBar> createState() => _SelfUseMiniBarState();
}

class _SelfUseMiniBarState extends State<SelfUseMiniBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;
  bool _isExpanded = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    HapticFeedback.lightImpact();
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    });
  }

  void _handleTap() {
    if (!_isExpanded) {
      widget.onExpand?.call();
    }
  }

  void _handleVerticalDrag(DragUpdateDetails details) {
    if (details.delta.dy < -5 && !_isExpanded) {
      _toggleExpand();
    } else if (details.delta.dy > 5 && _isExpanded) {
      _toggleExpand();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final currentAction = session.currentAction;
    final pct = (session.progress * 100).toStringAsFixed(0);
    final isRunning = session.isActive;

    return GestureDetector(
      onVerticalDragUpdate: _handleVerticalDrag,
      onTap: _handleTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Expanded Panel (when swiped up) ───────────────────────────
          SizeTransition(
            sizeFactor: _expandAnimation,
            child: _expandedPanel(),
          ),

          // ── Main Mini Bar ─────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppTheme.surface.withOpacity(0.85),
                  AppTheme.backgroundElevated.withOpacity(0.95),
                ],
              ),
              border: Border(
                top: BorderSide(
                  color: isRunning
                      ? AppTheme.primary.withOpacity(0.4)
                      : AppTheme.border,
                  width: 1,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: isRunning
                      ? AppTheme.primary.withOpacity(0.1)
                      : Colors.black.withOpacity(0.2),
                  blurRadius: 12,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                transform: _isPressed
                    ? (Matrix4.identity()..scale(0.99))
                    : Matrix4.identity(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Drag handle
                    Center(
                      child: GestureDetector(
                        onTap: _toggleExpand,
                        child: Container(
                          margin: const EdgeInsets.only(top: 6, bottom: 4),
                          width: 32,
                          height: 3,
                          decoration: BoxDecoration(
                            color: AppTheme.textDisabled.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),

                    // Main row
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: Row(
                        children: [
                          // Robot icon with status pulse
                          _RobotIcon(
                            isRunning: isRunning,
                            statusColor: session.statusColor,
                          ),
                          const SizedBox(width: 10),

                          // Current action text
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  currentAction?.description ??
                                      session.userRequest,
                                  style: const TextStyle(
                                    fontFamily: AppTheme.fontBody,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                // Mini progress bar
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: TweenAnimationBuilder<double>(
                                    tween: Tween<double>(
                                      begin: 0,
                                      end: session.progress.clamp(0.0, 1.0),
                                    ),
                                    duration:
                                        const Duration(milliseconds: 400),
                                    builder: (context, value, child) {
                                      return LinearProgressIndicator(
                                        value: value,
                                        backgroundColor:
                                            AppTheme.surfaceHover,
                                        valueColor:
                                            const AlwaysStoppedAnimation<
                                                Color>(AppTheme.primary),
                                        minHeight: 4,
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Progress percentage
                          Text(
                            '$pct%',
                            style: const TextStyle(
                              fontFamily: AppTheme.fontCode,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.accent,
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Pause/Resume button
                          _MiniBarButton(
                            icon: isRunning
                                ? Icons.pause
                                : Icons.play_arrow,
                            color: isRunning
                                ? AppTheme.warning
                                : AppTheme.success,
                            onTap: widget.onPause,
                            tooltip:
                                isRunning ? '\u6682\u505C' : '\u7EE7\u7EED',
                          ),

                          // Cancel button
                          _MiniBarButton(
                            icon: Icons.stop,
                            color: AppTheme.error,
                            onTap: widget.onCancel,
                            tooltip: '\u53D6\u6D88',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // Expanded Panel
  // ════════════════════════════════════════════════════════════════════════

  Widget _expandedPanel() {
    final session = widget.session;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.surface.withOpacity(0.9),
            AppTheme.backgroundElevated.withOpacity(0.95),
          ],
        ),
        border: const Border(
          top: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Session info header
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.smart_toy,
                    size: 18,
                    color: AppTheme.textOnPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.userRequest,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontBody,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        session.statusLabel,
                        style: TextStyle(
                          fontFamily: AppTheme.fontBody,
                          fontSize: 12,
                          color: session.statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Progress bar (large)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  begin: 0,
                  end: session.progress.clamp(0.0, 1.0),
                ),
                duration: const Duration(milliseconds: 400),
                builder: (context, value, child) {
                  return LinearProgressIndicator(
                    value: value,
                    backgroundColor: AppTheme.surfaceHover,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                    minHeight: 8,
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            // Stats row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statItem('\u5DF2\u5B8C\u6210',
                    '${session.completedActionsCount}', AppTheme.success),
                _statItem(
                    '\u603B\u6B65\u9AA4', '${session.totalActions}', AppTheme.textSecondary),
                if (session.failedActionsCount > 0)
                  _statItem(
                      '\u5931\u8D25', '${session.failedActionsCount}', AppTheme.error),
                _statItem('\u8017\u65F6', session.elapsedTimeFormatted, AppTheme.accent),
              ],
            ),

            const SizedBox(height: 12),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: _actionButton(
                    icon: session.isActive ? Icons.pause : Icons.play_arrow,
                    label: session.isActive ? '\u6682\u505C' : '\u7EE7\u7EED',
                    color: session.isActive ? AppTheme.warning : AppTheme.success,
                    onTap: widget.onPause,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _actionButton(
                    icon: Icons.stop,
                    label: '\u53D6\u6D88',
                    color: AppTheme.error,
                    onTap: widget.onCancel,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _actionButton(
                    icon: Icons.terminal,
                    label: '\u65E5\u5FD7',
                    color: widget.isLogVisible ? AppTheme.accent : AppTheme.textSecondary,
                    onTap: widget.onToggleLog,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontFamily: AppTheme.fontCode,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 11,
            color: AppTheme.textTertiary,
          ),
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap?.call();
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Robot Icon with Pulse Animation
// ═══════════════════════════════════════════════════════════════════════════

class _RobotIcon extends StatefulWidget {
  final bool isRunning;
  final Color statusColor;

  const _RobotIcon({
    required this.isRunning,
    required this.statusColor,
  });

  @override
  State<_RobotIcon> createState() => _RobotIconState();
}

class _RobotIconState extends State<_RobotIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.isRunning) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _RobotIcon old) {
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
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primary.withOpacity(0.8 + (_pulse.value * 0.2)),
                AppTheme.primary.withOpacity(0.6 + (_pulse.value * 0.2)),
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: widget.isRunning
                ? [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(
                        0.3 * (1 - _pulse.value),
                      ),
                      blurRadius: 8 + (_pulse.value * 6),
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: const Icon(
            Icons.smart_toy,
            size: 18,
            color: AppTheme.textOnPrimary,
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Mini Bar Button
// ═══════════════════════════════════════════════════════════════════════════

class _MiniBarButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final String tooltip;

  const _MiniBarButton({
    required this.icon,
    required this.color,
    this.onTap,
    required this.tooltip,
  });

  @override
  State<_MiniBarButton> createState() => _MiniBarButtonState();
}

class _MiniBarButtonState extends State<_MiniBarButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          HapticFeedback.lightImpact();
          widget.onTap?.call();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          transform: _pressed
              ? (Matrix4.identity()..scale(0.88))
              : Matrix4.identity(),
          child: Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: widget.color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.color.withOpacity(0.2),
              ),
            ),
            child: Icon(
              widget.icon,
              size: 16,
              color: widget.color,
            ),
          ),
        ),
      ),
    );
  }
}
