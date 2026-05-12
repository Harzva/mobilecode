// lib/widgets/deep_dive_task_card.dart
// Solo Task Card
//
// Displays a single Solo Mode task with rich visual feedback:
// - Status indicator with pulsing dot when running
// - Title, description, and priority badge
// - Animated progress bar with percentage
// - Current action text and step counter
// - Elapsed time display
// - Control buttons (pause/resume, cancel, expand)
// - Expandable log section with real-time entries
//
// States:
// - Collapsed: compact view with key info
// - Expanded: shows full action log
//
// Animations:
// - Status change: smooth color transition
// - Progress bar: animated fill
// - Pulse: continuous when running
// - Slide in/out: when added/removed from list
//
// Design: Glassmorphism card, dark theme, status-colored accents

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../models/self_use_session.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Extension Helpers for SessionStatus UI
// ═══════════════════════════════════════════════════════════════════════════

extension _SessionStatusUI on SessionStatus {
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

  String get emoji {
    switch (this) {
      case SessionStatus.pending:
        return '\u23F3';
      case SessionStatus.planning:
        return '\uD83E\uDDD0';
      case SessionStatus.executing:
        return '\u26A1';
      case SessionStatus.paused:
        return '\u23F8';
      case SessionStatus.completed:
        return '\u2705';
      case SessionStatus.failed:
        return '\u274C';
    }
  }

  bool get isRunning => this == SessionStatus.executing;
  bool get isTerminal =>
      this == SessionStatus.completed || this == SessionStatus.failed;
}

// ═══════════════════════════════════════════════════════════════════════════
// Solo Task Card
// ═══════════════════════════════════════════════════════════════════════════

/// Displays a single Solo task with rich visual feedback.
///
/// Features:
/// - Status indicator with pulsing dot animation when running
/// - Title, description, and priority badge
/// - Animated progress bar with percentage display
/// - Current action text and step counter (e.g., "3 / 8")
/// - Elapsed time display
/// - Control buttons: Pause/Resume, Cancel, Expand
/// - Expandable log section showing real-time action logs
///
/// The card has two states:
/// - Collapsed: shows essential info in a compact layout
/// - Expanded: reveals the full action log for the task
///
/// Design: Glassmorphism card with status-colored accents.
class DeepDiveTaskCard extends StatefulWidget {
  /// The session to display.
  final SelfUseSession session;

  /// Called when pause is tapped.
  final VoidCallback? onPause;

  /// Called when resume is tapped.
  final VoidCallback? onResume;

  /// Called when cancel is tapped.
  final VoidCallback? onCancel;

  /// Called when the card is tapped (to navigate to detail).
  final VoidCallback? onTap;

  /// Called when the card is dismissed (swiped away).
  final VoidCallback? onDismiss;

  /// Whether this card can be dismissed.
  final bool dismissible;

  const DeepDiveTaskCard({
    super.key,
    required this.session,
    this.onPause,
    this.onResume,
    this.onCancel,
    this.onTap,
    this.onDismiss,
    this.dismissible = false,
  });

  @override
  State<DeepDiveTaskCard> createState() => _DeepDiveTaskCardState();
}

class _DeepDiveTaskCardState extends State<DeepDiveTaskCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  bool _isExpanded = false;
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
    _elapsed = widget.session.elapsedTime;
    _startElapsedTimer();
  }

  @override
  void didUpdateWidget(covariant DeepDiveTaskCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.session.status == SessionStatus.executing &&
        !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (widget.session.status != SessionStatus.executing &&
        _pulseController.isAnimating) {
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
    _elapsedTimer?.cancel();
    super.dispose();
  }

  void _toggleExpand() {
    HapticFeedback.lightImpact();
    setState(() => _isExpanded = !_isExpanded);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final status = session.status;
    final pct = session.progressPercent;

    Widget card = Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.surface.withOpacity(0.9),
            AppTheme.backgroundElevated.withOpacity(0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: status.isRunning
              ? status.color.withOpacity(0.4)
              : AppTheme.border.withOpacity(0.6),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: status.isRunning
                ? status.color.withOpacity(0.08)
                : Colors.black.withOpacity(0.1),
            blurRadius: status.isRunning ? 16 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ────────────────────────────────────────────
                _buildHeader(session, status),

                // ── Progress Section ──────────────────────────────────
                _buildProgressSection(session, pct),

                // ── Action Row ────────────────────────────────────────
                _buildActionRow(session),

                // ── Expanded Log Section ──────────────────────────────
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: _buildLogSection(session),
                  crossFadeState: _isExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 250),
                ),

                // ── Control Buttons ───────────────────────────────────
                _buildControlButtons(session, status),
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.dismissible && status.isTerminal) {
      card = Dismissible(
        key: Key('dismiss_${session.id}'),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => widget.onDismiss?.call(),
        background: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.error.withOpacity(0.15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.error.withOpacity(0.3)),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '\u5220\u9664',
                style: TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.error,
                ),
              ),
              SizedBox(width: 8),
              Icon(Icons.delete_outline, color: AppTheme.error, size: 20),
            ],
          ),
        ),
        child: card,
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: card,
    );
  }

  // ── Header ──────────────────────────────────────────────────────────

  Widget _buildHeader(SelfUseSession session, SessionStatus status) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status icon with pulse animation
          _StatusIcon(status: status, pulseController: _pulseController),
          const SizedBox(width: 12),

          // Title & description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.userRequest,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (session.planDescription != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    session.planDescription!,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 12,
                      color: AppTheme.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                // Status badge + elapsed
                Row(
                  children: [
                    _StatusBadge(status: status),
                    const SizedBox(width: 10),
                    _ElapsedTime(elapsed: _elapsed),
                  ],
                ),
              ],
            ),
          ),

          // Expand/collapse button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _toggleExpand,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: AnimatedRotation(
                  turns: _isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.keyboard_arrow_down,
                    size: 20,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Progress Section ────────────────────────────────────────────────

  Widget _buildProgressSection(SelfUseSession session, int pct) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Step counter
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceHover,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Text(
                  '${session.currentStep} / ${session.plannedActions.length} \u6B65\u9AA4',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontCode,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              // Percentage
              Text(
                '$pct%',
                style: TextStyle(
                  fontFamily: AppTheme.fontCode,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: session.status.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: 0,
                end: session.progress.clamp(0.0, 1.0),
              ),
              duration: const Duration(milliseconds: 500),
              builder: (context, value, child) {
                return LinearProgressIndicator(
                  value: value,
                  backgroundColor: AppTheme.surfaceHover,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    session.status.color,
                  ),
                  minHeight: 6,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Action Row ──────────────────────────────────────────────────────

  Widget _buildActionRow(SelfUseSession session) {
    final currentAction = session.currentAction;
    if (currentAction == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.backgroundElevated.withOpacity(0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            Icon(
              _actionIcon(currentAction.category),
              size: 16,
              color: AppTheme.accent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                currentAction.description ?? currentAction.action,
                style: const TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _actionIcon(String category) {
    switch (category) {
      case 'editor':
        return Icons.code;
      case 'terminal':
        return Icons.terminal;
      case 'git':
        return Icons.commit;
      case 'navigation':
        return Icons.navigation;
      case 'ui':
        return Icons.touch_app;
      case 'github':
        return Icons.home;
      case 'project':
        return Icons.folder;
      default:
        return Icons.play_arrow;
    }
  }

  // ── Log Section ─────────────────────────────────────────────────────

  Widget _buildLogSection(SelfUseSession session) {
    final logs = session.logs;
    if (logs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.terminal_outlined,
                size: 28,
                color: AppTheme.textTertiary.withOpacity(0.4),
              ),
              const SizedBox(height: 6),
              Text(
                '\u6682\u65E0\u65E5\u5FD7',
                style: TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 12,
                  color: AppTheme.textTertiary.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.backgroundElevated.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border.withOpacity(0.5)),
      ),
      constraints: const BoxConstraints(maxHeight: 200),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Log header
          Row(
            children: [
              const Icon(Icons.terminal, size: 12, color: AppTheme.textTertiary),
              const SizedBox(width: 6),
              const Text(
                '\u6267\u884C\u65E5\u5FD7',
                style: TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceHover,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${logs.length} \u6761',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontCode,
                    fontSize: 10,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 12, color: AppTheme.divider),
          // Log entries
          Expanded(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[index];
                return _LogEntryTile(entry: log, isLast: index == logs.length - 1);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Control Buttons ─────────────────────────────────────────────────

  Widget _buildControlButtons(SelfUseSession session, SessionStatus status) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (!status.isTerminal) ...[
            // Pause/Resume
            _ControlButton(
              icon: status == SessionStatus.paused
                  ? Icons.play_arrow
                  : Icons.pause,
              label: status == SessionStatus.paused
                  ? '\u7EE7\u7EED'
                  : '\u6682\u505C',
              color: status == SessionStatus.paused
                  ? AppTheme.success
                  : AppTheme.warning,
              onTap: status == SessionStatus.paused
                  ? widget.onResume
                  : widget.onPause,
            ),
            const SizedBox(width: 6),
            // Cancel
            _ControlButton(
              icon: Icons.stop,
              label: '\u53D6\u6D88',
              color: AppTheme.error,
              onTap: widget.onCancel,
            ),
          ] else ...[
            // Completed/failed - show status
            _ControlButton(
              icon: status == SessionStatus.completed
                  ? Icons.check_circle
                  : Icons.error,
              label: status.label,
              color: status.color,
              onTap: null,
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Status Icon with Pulse Animation
// ═══════════════════════════════════════════════════════════════════════════

class _StatusIcon extends StatelessWidget {
  final SessionStatus status;
  final AnimationController pulseController;

  const _StatusIcon({
    required this.status,
    required this.pulseController,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseController,
      builder: (context, child) {
        return Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                status.color.withOpacity(0.3 + (pulseController.value * 0.15)),
                status.color.withOpacity(0.1 + (pulseController.value * 0.1)),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: status.isRunning
                ? [
                    BoxShadow(
                      color: status.color.withOpacity(
                        0.25 * (1 - pulseController.value),
                      ),
                      blurRadius: 10 + (pulseController.value * 6),
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              status.emoji,
              style: const TextStyle(fontSize: 20),
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Status Badge
// ═══════════════════════════════════════════════════════════════════════════

class _StatusBadge extends StatelessWidget {
  final SessionStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: status.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: status.color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: status.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: status.color,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Elapsed Time Display
// ═══════════════════════════════════════════════════════════════════════════

class _ElapsedTime extends StatelessWidget {
  final Duration elapsed;

  const _ElapsedTime({required this.elapsed});

  @override
  Widget build(BuildContext context) {
    final formatted = _formatDuration(elapsed);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.timer_outlined,
          size: 12,
          color: AppTheme.textTertiary,
        ),
        const SizedBox(width: 4),
        Text(
          formatted,
          style: const TextStyle(
            fontFamily: AppTheme.fontCode,
            fontSize: 11,
            color: AppTheme.textTertiary,
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '${h}h ${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
    }
    if (m > 0) {
      return '${m}m ${s.toString().padLeft(2, '0')}s';
    }
    return '${s}s';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Control Button
// ═══════════════════════════════════════════════════════════════════════════

class _ControlButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  State<_ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<_ControlButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
            ? (Matrix4.identity()..scale(0.94))
            : Matrix4.identity(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: widget.onTap != null
                ? widget.color.withOpacity(0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.onTap != null
                  ? widget.color.withOpacity(0.25)
                  : widget.color.withOpacity(0.15),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 14,
                color: widget.onTap != null ? widget.color : widget.color.withOpacity(0.5),
              ),
              const SizedBox(width: 5),
              Text(
                widget.label,
                style: TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: widget.onTap != null ? widget.color : widget.color.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Log Entry Tile
// ═══════════════════════════════════════════════════════════════════════════

class _LogEntryTile extends StatelessWidget {
  final SessionLogEntry entry;
  final bool isLast;

  const _LogEntryTile({
    required this.entry,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp
          SizedBox(
            width: 52,
            child: Text(
              _formatTime(entry.timestamp),
              style: const TextStyle(
                fontFamily: AppTheme.fontCode,
                fontSize: 10,
                color: AppTheme.textDisabled,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Level indicator
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: _levelColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Center(
              child: Text(
                _levelIndicator,
                style: TextStyle(
                  fontFamily: AppTheme.fontCode,
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: _levelColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Message
          Expanded(
            child: Text(
              entry.message,
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 11,
                color: entry.level == LogLevel.error
                    ? AppTheme.error
                    : entry.level == LogLevel.warning
                        ? AppTheme.warning
                        : AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _levelIndicator {
    switch (entry.level) {
      case LogLevel.debug:
        return 'D';
      case LogLevel.info:
        return 'I';
      case LogLevel.warning:
        return 'W';
      case LogLevel.error:
        return 'E';
    }
  }

  Color get _levelColor {
    switch (entry.level) {
      case LogLevel.debug:
        return AppTheme.textDisabled;
      case LogLevel.info:
        return AppTheme.info;
      case LogLevel.warning:
        return AppTheme.warning;
      case LogLevel.error:
        return AppTheme.error;
    }
  }

  String _formatTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
