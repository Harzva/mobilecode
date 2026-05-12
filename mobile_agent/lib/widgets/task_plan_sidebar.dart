// lib/widgets/task_plan_sidebar.dart
// Task Plan Sidebar
//
// Slide-in panel from right side showing:
// - Plan title + progress bar
// - Step list with status indicators
// - Expandable step details with logs
// - Action buttons: Pause / Resume / Cancel
// - Elapsed time + ETA at bottom
//
// Design: Dark theme, glassmorphism background, smooth animations.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../models/agent_task.dart';
import '../services/agent_orchestrator.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Task Plan Sidebar (Slide-in Overlay)
// ═══════════════════════════════════════════════════════════════════════════

/// Slide-in sidebar showing task plan progress.
///
/// Animates in from the right side of the screen, occupying 85% width
/// on mobile. Displays the full plan with steps, status indicators,
/// logs, and control buttons.
class TaskPlanSidebar extends StatefulWidget {
  /// The task plan to display.
  final TaskPlan plan;

  /// Called when the sidebar should be closed.
  final VoidCallback onClose;

  /// Optional callback when plan status changes.
  final Function(TaskPlan)? onPlanChanged;

  const TaskPlanSidebar({
    super.key,
    required this.plan,
    required this.onClose,
    this.onPlanChanged,
  });

  /// Show the sidebar as an overlay.
  static void show({
    required BuildContext context,
    required TaskPlan plan,
    Function(TaskPlan)? onPlanChanged,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (ctx) => TaskPlanSidebar(
        plan: plan,
        onClose: () => entry.remove(),
        onPlanChanged: onPlanChanged,
      ),
    );

    overlay.insert(entry);
  }

  @override
  State<TaskPlanSidebar> createState() => _TaskPlanSidebarState();
}

class _TaskPlanSidebarState extends State<TaskPlanSidebar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _slideAnim;
  late final Animation<double> _fadeAnim;

  final Map<String, bool> _expandedSteps = {};
  StreamSubscription<TaskPlan>? _planSub;

  late TaskPlan _currentPlan;

  // ── Agent Orchestrator ────────────────────────────────────────────────
  final AgentOrchestrator _orchestrator = AgentOrchestrator();

  @override
  void initState() {
    super.initState();
    _currentPlan = widget.plan;

    // Animate in
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();

    // Listen to plan updates
    _planSub = _orchestrator.planUpdates.listen((plan) {
      if (plan.id == _currentPlan.id && mounted) {
        setState(() => _currentPlan = plan);
        widget.onPlanChanged?.call(plan);
      }
    });
  }

  @override
  void dispose() {
    _planSub?.cancel();
    _animController.dispose();
    super.dispose();
  }

  // ── Close Animation ───────────────────────────────────────────────────

  Future<void> _close() async {
    await _animController.reverse();
    if (mounted) widget.onClose();
  }

  // ── Actions ───────────────────────────────────────────────────────────

  void _pause() {
    HapticFeedback.lightImpact();
    _orchestrator.pausePlan(_currentPlan.id);
  }

  void _resume() {
    HapticFeedback.lightImpact();
    _orchestrator.resumePlan(_currentPlan.id);
  }

  void _cancel() {
    HapticFeedback.mediumImpact();
    _orchestrator.cancelPlan(_currentPlan.id);
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final sidebarWidth = screenWidth * 0.85;

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return Stack(children: [
          // Backdrop scrim
          GestureDetector(
            onTap: _close,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Container(
                color: Colors.black.withOpacity(0.5),
                width: screenWidth,
                height: MediaQuery.of(context).size.height,
              ),
            ),
          ),

          // Sidebar panel
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Transform.translate(
              offset: Offset(sidebarWidth * (1 - _slideAnim.value), 0),
              child: Container(
                width: sidebarWidth,
                decoration: BoxDecoration(
                  gradient: AppTheme.surfaceGradient,
                  border: const Border(
                    left: BorderSide(color: AppTheme.border, width: 1),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 20,
                      offset: const Offset(-4, 0),
                    ),
                  ],
                ),
                child: child,
              ),
            ),
          ),
        ]);
      },
      child: SafeArea(
        child: Column(children: [
          // ── Header ──────────────────────────────────────────────────
          _header(),

          // ── Progress Section ────────────────────────────────────────
          _progressSection(),

          // ── Step List ───────────────────────────────────────────────
          Expanded(child: _stepList()),

          // ── Bottom Bar ──────────────────────────────────────────────
          _bottomBar(),
        ]),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────

  Widget _header() {
    final status = _currentPlan.status;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            status.color.withOpacity(0.15),
            AppTheme.surface.withOpacity(0.5),
          ],
        ),
        border: const Border(
          bottom: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            // Status indicator
            _StatusPulse(color: status.color, active: _currentPlan.isActive),
            const SizedBox(width: 10),

            // Status label
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: status.color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: status.color.withOpacity(0.3)),
              ),
              child: Text(
                status.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: status.color,
                ),
              ),
            ),

            const Spacer(),

            // Close button
            InkWell(
              onTap: _close,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceHover.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.close,
                  size: 18,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ]),

          const SizedBox(height: 12),

          // Plan title
          Text(
            _currentPlan.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: 4),

          // Plan description
          Text(
            _currentPlan.description,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textTertiary,
              height: 1.4,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ── Progress Section ──────────────────────────────────────────────────

  Widget _progressSection() {
    final pct = (_currentPlan.progress * 100).toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Progress bar + percentage
          Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceHover,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: _currentPlan.progress.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.primary, AppTheme.accent],
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$pct%',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.accent,
                fontFamily: AppTheme.fontCode,
              ),
            ),
          ]),

          const SizedBox(height: 8),

          // Step counts
          Row(children: [
            _countBadge(
              '${_currentPlan.completedSteps}',
              AppTheme.success,
              '\u5df2\u5b8c\u6210',
            ),
            const SizedBox(width: 8),
            _countBadge(
              '${_currentPlan.totalSteps}',
              AppTheme.textSecondary,
              '\u603b\u6b65\u9aa4',
            ),
            if (_currentPlan.failedSteps > 0) ...[
              const SizedBox(width: 8),
              _countBadge(
                '${_currentPlan.failedSteps}',
                AppTheme.error,
                '\u5931\u8d25',
              ),
            ],
            const Spacer(),
            if (_currentPlan.isActive)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(AppTheme.primary),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '\u6b65\u9aa4 ${_currentPlan.completedSteps + _currentPlan.runningSteps + 1}/${_currentPlan.totalSteps}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
          ]),
        ],
      ),
    );
  }

  Widget _countBadge(String count, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          count,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
            fontFamily: AppTheme.fontCode,
          ),
        ),
        const SizedBox(width: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary),
        ),
      ],
    );
  }

  // ── Step List ─────────────────────────────────────────────────────────

  Widget _stepList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _currentPlan.steps.length,
      itemBuilder: (context, index) {
        final step = _currentPlan.steps[index];
        return _StepTile(
          step: step,
          isExpanded: _expandedSteps[step.id] ?? false,
          onToggle: () => setState(
            () => _expandedSteps[step.id] = !(_expandedSteps[step.id] ?? false),
          ),
          isLast: index == _currentPlan.steps.length - 1,
        );
      },
    );
  }

  // ── Bottom Bar ────────────────────────────────────────────────────────

  Widget _bottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.surface.withOpacity(0.0),
            AppTheme.surface,
          ],
        ),
        border: const Border(
          top: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Action buttons
            Row(children: [
              if (_currentPlan.status == TaskPlanStatus.running) ...[
                Expanded(
                  child: _actionButton(
                    icon: Icons.pause,
                    label: '\u6682\u505c',
                    color: AppTheme.warning,
                    onTap: _pause,
                  ),
                ),
              ] else if (_currentPlan.status == TaskPlanStatus.paused) ...[
                Expanded(
                  child: _actionButton(
                    icon: Icons.play_arrow,
                    label: '\u7ee7\u7eed',
                    color: AppTheme.success,
                    onTap: _resume,
                  ),
                ),
              ] else ...[
                Expanded(
                  child: _actionButton(
                    icon: Icons.play_arrow,
                    label: '\u5f00\u59cb',
                    color: AppTheme.primary,
                    onTap: () => _orchestrator.executePlan(
                      _currentPlan,
                      onProgress: (p) {
                        setState(() => _currentPlan = p);
                        widget.onPlanChanged?.call(p);
                      },
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Expanded(
                child: _actionButton(
                  icon: Icons.stop,
                  label: '\u53d6\u6d88',
                  color: AppTheme.error,
                  onTap: _cancel,
                ),
              ),
            ]),

            const SizedBox(height: 12),

            // Time info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _timeInfo('\u5df2\u7528\u65f6', _currentPlan.elapsedTimeFormatted),
                _timeInfo('\u9884\u8ba1\u5269\u4f59', _currentPlan.etaFormatted),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeInfo(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
            fontFamily: AppTheme.fontCode,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Step Tile Widget
// ═══════════════════════════════════════════════════════════════════════════

class _StepTile extends StatelessWidget {
  final TaskStep step;
  final bool isExpanded;
  final VoidCallback onToggle;
  final bool isLast;

  const _StepTile({
    required this.step,
    required this.isExpanded,
    required this.onToggle,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status icon / step number
                _stepIndicator(),
                const SizedBox(width: 12),

                // Step info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${step.order}. ${step.title}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: step.isRunning
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: step.status == StepStatus.pending
                                    ? AppTheme.textTertiary
                                    : AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          if (step.duration != null)
                            Text(
                              step.durationFormatted,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textTertiary,
                                fontFamily: AppTheme.fontCode,
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(height: 3),

                      // Description
                      Text(
                        step.description,
                        style: TextStyle(
                          fontSize: 11,
                          color: step.status == StepStatus.pending
                              ? AppTheme.textDisabled
                              : AppTheme.textSecondary,
                          height: 1.3,
                        ),
                        maxLines: isExpanded ? null : 1,
                        overflow:
                            isExpanded ? null : TextOverflow.ellipsis,
                      ),

                      if (step.assignedAgentId != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: _agentChip(step.assignedAgentId!),
                        ),

                      // Result message
                      if (step.result != null && step.isDone)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            step.result!,
                            style: TextStyle(
                              fontSize: 11,
                              color: step.status == StepStatus.completed
                                  ? AppTheme.success.withOpacity(0.8)
                                  : AppTheme.error.withOpacity(0.8),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Expand/collapse arrow
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.keyboard_arrow_down,
                    size: 18,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Expanded logs section
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: _logsSection(),
          crossFadeState: isExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 250),
        ),

        // Divider (except last)
        if (!isLast)
          const Padding(
            padding: EdgeInsets.only(left: 54),
            child: Divider(
              height: 1,
              color: AppTheme.divider,
              indent: 0,
            ),
          ),
      ],
    );
  }

  Widget _stepIndicator() {
    final color = step.statusColor;

    switch (step.status) {
      case StepStatus.pending:
        return Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: AppTheme.surfaceHover,
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.border),
          ),
          child: Center(
            child: Text(
              '${step.order}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.textTertiary,
              ),
            ),
          ),
        );

      case StepStatus.running:
        return SizedBox(
          width: 26,
          height: 26,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation(color),
              ),
              Text(
                '${step.order}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        );

      case StepStatus.completed:
        return Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: AppTheme.success.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check,
            size: 14,
            color: AppTheme.success,
          ),
        );

      case StepStatus.failed:
        return Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: AppTheme.error.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.close,
            size: 14,
            color: AppTheme.error,
          ),
        );

      case StepStatus.skipped:
        return Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: AppTheme.textDisabled.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.skip_next,
            size: 14,
            color: AppTheme.textDisabled,
          ),
        );
    }
  }

  Widget _agentChip(String agentId) {
    final orchestrator = AgentOrchestrator();
    final agent = orchestrator.getAgent(agentId);
    final color = agent?.accentColor ?? AppTheme.textTertiary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        agent?.name ?? agentId,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: color.withOpacity(0.9),
        ),
      ),
    );
  }

  Widget _logsSection() {
    if (step.logs.isEmpty) {
      return Container(
        padding: const EdgeInsets.only(left: 54, bottom: 12),
        alignment: Alignment.centerLeft,
        child: const Text(
          '\u6682\u65e0\u65e5\u5fd7',
          style: TextStyle(
            fontSize: 11,
            color: AppTheme.textDisabled,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(left: 54, right: 16, bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.backgroundElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: step.logs.map((log) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: AppTheme.fontCode,
                  height: 1.4,
                ),
                children: [
                  TextSpan(
                    text: '${log.formattedTime} ',
                    style: const TextStyle(color: AppTheme.textDisabled),
                  ),
                  TextSpan(
                    text: '[${log.levelIndicator}] ',
                    style: TextStyle(
                      color: log.color.withOpacity(0.7),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: log.message,
                    style: TextStyle(color: log.color),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Status Pulse Indicator
// ═══════════════════════════════════════════════════════════════════════════

class _StatusPulse extends StatefulWidget {
  final Color color;
  final bool active;

  const _StatusPulse({required this.color, required this.active});

  @override
  State<_StatusPulse> createState() => _StatusPulseState();
}

class _StatusPulseState extends State<_StatusPulse>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.active) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _StatusPulse old) {
    super.didUpdateWidget(old);
    if (widget.active && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.active && _pulse.isAnimating) {
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
        return Stack(
          alignment: Alignment.center,
          children: [
            if (widget.active)
              Container(
                width: 18 + (_pulse.value * 8),
                height: 18 + (_pulse.value * 8),
                decoration: BoxDecoration(
                  color: widget.color.withOpacity(0.2 * (1 - _pulse.value)),
                  shape: BoxShape.circle,
                ),
              ),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withOpacity(0.4),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Compact Task Plan FAB
// ═══════════════════════════════════════════════════════════════════════════

/// Floating action button showing compact plan progress.
///
/// Tapping opens the full sidebar. Shows a mini progress indicator
/// when a plan is active.
class TaskPlanFab extends StatelessWidget {
  final TaskPlan? plan;
  final VoidCallback? onTap;

  const TaskPlanFab({super.key, this.plan, this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasPlan = plan != null;
    final isActive = plan?.isActive ?? false;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          gradient: isActive ? AppTheme.accentGradient : AppTheme.primaryGradient,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: (isActive ? AppTheme.accent : AppTheme.primary)
                  .withOpacity(0.4),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(
              Icons.assignment,
              color: Colors.white,
              size: 24,
            ),
            if (hasPlan)
              Positioned(
                right: 10,
                top: 10,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: isActive ? AppTheme.success : AppTheme.warning,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: (isActive ? AppTheme.accent : AppTheme.primary),
                      width: 2,
                    ),
                  ),
                  child: isActive
                      ? const SizedBox.shrink()
                      : Center(
                          child: Text(
                            '${plan!.completedSteps}',
                            style: const TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
