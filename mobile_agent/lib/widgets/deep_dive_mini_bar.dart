// lib/widgets/deep_dive_mini_bar.dart
// Solo Mini Bar
//
// Compact progress bar shown at the bottom of EVERY screen when a Solo
// task is running. Always visible, doesn't block content.
//
// Layout (single row, ~48px height):
// [Robot] [Task name...] [Progress Bar + %] [Pause] [Stop]
//
// Interactions:
// - Tap -> opens Solo Mode page
// - Swipe up -> expands to show more details
// - Swipe down -> dismiss (hide until next task)
//
// Design:
// - Glassmorphism background
// - Height: 48px + SafeArea
// - Position: bottom of screen, above nav bar
// - Always on top (floating)
// - Semi-transparent when not focused
// - Animated border glow when task is running

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../models/self_use_session.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Extension Helpers for SessionStatus UI
// ═══════════════════════════════════════════════════════════════════════════

extension _MiniBarSessionStatusUI on SessionStatus {
  Color get color {
    switch (this) {
      case SessionStatus.pending:
        return const Color(0xFF6B7280);
      case SessionStatus.planning:
        return const Color(0xFF3B82F6);
      case SessionStatus.executing:
        return const Color(0xFF00D4AA);
      case SessionStatus.paused:
        return const Color(0xFFF59E0B);
      case SessionStatus.completed:
        return const Color(0xFF10B981);
      case SessionStatus.failed:
        return const Color(0xFFEF4444);
    }
  }

  String get label {
    switch (this) {
      case SessionStatus.pending:
        return '\u7B49\u5F85\u4E2D';
      case SessionStatus.planning:
        return '\u89C4\u5212\u4E2D';
      case SessionStatus.executing:
        return '\u6267\u884C\u4E2D';
      case SessionStatus.paused:
        return '\u5DF2\u6682\u505C';
      case SessionStatus.completed:
        return '\u5DF2\u5B8C\u6210';
      case SessionStatus.failed:
        return '\u5931\u8D25';
    }
  }

  bool get isRunning => this == SessionStatus.executing;
}

// ═══════════════════════════════════════════════════════════════════════════
// Solo Mini Bar
// ═══════════════════════════════════════════════════════════════════════════

/// Compact bar shown at the bottom of every screen when a Solo task is active.
///
/// Always visible, non-blocking, with glassmorphism design.
///
/// Features:
/// - Single-row compact layout (~48px height)
/// - Robot icon with pulse animation when running
/// - Task name with ellipsis truncation
/// - Animated mini progress bar with percentage
/// - Pause/Resume and Stop control buttons
/// - Swipe-up to expand details panel
/// - Swipe-down or tap X to dismiss
/// - Tap bar to navigate to Solo Mode
///
/// Design: Glassmorphism background, floating above nav bar,
///         subtle glow border when running.
class SoloMiniBar extends StatefulWidget {
  /// The active session to display.
  final SelfUseSession session;

  /// Called when the bar is tapped to open Solo Mode.
  final VoidCallback? onOpenDeepDiveMode;

  /// Called when pause/resume is tapped.
  final VoidCallback? onPauseResume;

  /// Called when stop/cancel is tapped.
  final VoidCallback? onStop;

  /// Called when the bar is dismissed.
  final VoidCallback? onDismiss;

  const SoloMiniBar({
    super.key,
    required this.session,
    this.onOpenDeepDiveMode,
    this.onPauseResume,
    this.onStop,
    this.onDismiss,
  });

  @override
  State<SoloMiniBar> createState() => _SoloMiniBarState();
}

class _SoloMiniBarState extends State<SoloMiniBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;
  bool _isExpanded = false;
  bool _isDismissed = false;
  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.session.status == SessionStatus.executing) {
      _pulseController.repeat(reverse: true);
    }

    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _elapsed = widget.session.elapsedTime;
    _startElapsedTimer();
  }

  @override
  void didUpdateWidget(covariant SoloMiniBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasRunning = oldWidget.session.status == SessionStatus.executing;
    final isRunning = widget.session.status == SessionStatus.executing;
    if (isRunning && !wasRunning) {
      _pulseController.repeat(reverse: true);
    } else if (!isRunning && wasRunning) {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !widget.session.isComplete) {
        setState(() => _elapsed = widget.session.elapsedTime);
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _expandController.dispose();
    _elapsedTimer?.cancel();
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

  void _handleVerticalDrag(DragUpdateDetails details) {
    if (details.delta.dy < -6 && !_isExpanded) {
      _toggleExpand();
    } else if (details.delta.dy > 6 && _isExpanded) {
      _toggleExpand();
    } else if (details.delta.dy > 10 && !_isExpanded) {
      _dismiss();
    }
  }

  void _dismiss() {
    HapticFeedback.lightImpact();
    setState(() => _isDismissed = true);
    widget.onDismiss?.call();
  }

  void _handleTap() {
    if (!_isExpanded) {
      HapticFeedback.lightImpact();
      widget.onOpenDeepDiveMode?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDismissed) return const SizedBox.shrink();

    final session = widget.session;
    final status = session.status;
    final pct = session.progressPercent;
    final isRunning = status.isRunning;
    final currentAction = session.currentAction;

    return GestureDetector(
      onVerticalDragUpdate: _handleVerticalDrag,
      onTap: _handleTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Expanded Detail Panel ─────────────────────────────────
          SizeTransition(
            sizeFactor: _expandAnimation,
            child: _buildExpandedPanel(session, status),
          ),

          // ── Main Mini Bar ─────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppTheme.surface.withOpacity(0.9),
                  AppTheme.backgroundElevated.withOpacity(0.95),
                ],
              ),
              border: Border(
                top: BorderSide(
                  color: isRunning
                      ? status.color.withOpacity(0.5)
                      : AppTheme.border,
                  width: isRunning ? 1.5 : 1,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: isRunning
                      ? status.color.withOpacity(0.15)
                      : Colors.black.withOpacity(0.25),
                  blurRadius: isRunning ? 16 : 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle + dismiss
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 8, 0),
                    child: Row(
                      children: [
                        // Drag handle
                        GestureDetector(
                          onTap: _toggleExpand,
                          child: Container(
                            width: 32,
                            height: 3,
                            decoration: BoxDecoration(
                              color: AppTheme.textDisabled.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const Spacer(),
                        // Dismiss button
                        GestureDetector(
                          onTap: _dismiss,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceHover,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Main content row
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    child: Row(
                      children: [
                        // Robot icon with pulse
                        _RobotIcon(
                          isRunning: isRunning,
                          pulseController: _pulseController,
                          statusColor: status.color,
                        ),
                        const SizedBox(width: 10),

                        // Task info + progress
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Task name
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
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
                                  ),
                                ],
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
                                  duration: const Duration(milliseconds: 400),
                                  builder: (context, value, child) {
                                    return LinearProgressIndicator(
                                      value: value,
                                      backgroundColor: AppTheme.surfaceHover,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        status.color,
                                      ),
                                      minHeight: 4,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Progress percentage
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: status.color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '$pct%',
                            style: TextStyle(
                              fontFamily: AppTheme.fontCode,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: status.color,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),

                        // Pause/Resume button
                        _MiniIconButton(
                          icon: isRunning ? Icons.pause : Icons.play_arrow,
                          color: isRunning ? AppTheme.warning : AppTheme.success,
                          onTap: widget.onPauseResume,
                          tooltip: isRunning ? '\u6682\u505C' : '\u7EE7\u7EED',
                        ),

                        // Stop button
                        _MiniIconButton(
                          icon: Icons.stop,
                          color: AppTheme.error,
                          onTap: widget.onStop,
                          tooltip: '\u505C\u6B62',
                        ),
                      ],
                    ),
                  ),
                ],
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

  Widget _buildExpandedPanel(SelfUseSession session, SessionStatus status) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.surface.withOpacity(0.95),
            AppTheme.backgroundElevated.withOpacity(0.95),
          ],
        ),
        border: const Border(
          top: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Session header
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
                      '${status.label} \u00B7 ${_formatElapsed(_elapsed)} \u00B7 ${session.currentStep}/${session.plannedActions.length} \u6B65',
                      style: const TextStyle(
                        fontFamily: AppTheme.fontCode,
                        fontSize: 11,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Large progress bar
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
                  valueColor: AlwaysStoppedAnimation<Color>(status.color),
                  minHeight: 8,
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          // Stats grid
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem('\u5DF2\u5B8C\u6210', '${session.completedSteps}',
                  AppTheme.success),
              _statItem('\u603B\u6B65\u9AA4',
                  '${session.plannedActions.length}', AppTheme.textSecondary),
              if (session.failedSteps > 0)
                _statItem(
                    '\u5931\u8D25', '${session.failedSteps}', AppTheme.error),
              _statItem('\u8017\u65F6', _formatElapsed(_elapsed), AppTheme.accent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontFamily: AppTheme.fontCode,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 10,
            color: AppTheme.textTertiary,
          ),
        ),
      ],
    );
  }

  String _formatElapsed(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Robot Icon with Pulse Animation
// ═══════════════════════════════════════════════════════════════════════════

class _RobotIcon extends StatelessWidget {
  final bool isRunning;
  final AnimationController pulseController;
  final Color statusColor;

  const _RobotIcon({
    required this.isRunning,
    required this.pulseController,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseController,
      builder: (context, child) {
        return Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primary.withOpacity(0.8 + (pulseController.value * 0.2)),
                AppTheme.primary.withOpacity(0.6 + (pulseController.value * 0.2)),
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: isRunning
                ? [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(
                        0.3 * (1 - pulseController.value),
                      ),
                      blurRadius: 8 + (pulseController.value * 6),
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: const Icon(
            Icons.smart_toy,
            size: 16,
            color: AppTheme.textOnPrimary,
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Mini Icon Button
// ═══════════════════════════════════════════════════════════════════════════

class _MiniIconButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final String tooltip;

  const _MiniIconButton({
    required this.icon,
    required this.color,
    this.onTap,
    required this.tooltip,
  });

  @override
  State<_MiniIconButton> createState() => _MiniIconButtonState();
}

class _MiniIconButtonState extends State<_MiniIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        onTapDown: widget.onTap != null ? (_) => setState(() => _pressed = true) : null,
        onTapUp: widget.onTap != null
            ? (_) {
                setState(() => _pressed = false);
                HapticFeedback.lightImpact();
                widget.onTap!();
              }
            : null,
        onTapCancel: widget.onTap != null
            ? () => setState(() => _pressed = false)
            : null,
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
