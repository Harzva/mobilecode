// lib/screens/agent_dashboard_screen.dart
// Multi-Agent Monitoring Dashboard
//
// Shows all active agents and their status:
// - Agent cards grid (2 columns) with status indicators
// - Active tasks section with running task plans
// - Activity log with real-time scrolling log
//
// Design: Dark theme, glassmorphism cards, pulsing status indicators.

import 'dart:async';
import 'dart:math' show max;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../models/agent_task.dart';
import '../services/agent_orchestrator.dart';
import '../widgets/task_plan_sidebar.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Agent Dashboard Screen
// ═══════════════════════════════════════════════════════════════════════════

/// Full-screen dashboard for monitoring all agents and task plans.
///
/// Provides a real-time view of:
/// - All 5 worker agents with their current state
/// - Active task plans with progress
/// - Shared activity log from all agents
class AgentDashboardScreen extends StatefulWidget {
  const AgentDashboardScreen({super.key});

  @override
  State<AgentDashboardScreen> createState() => _AgentDashboardScreenState();
}

class _AgentDashboardScreenState extends State<AgentDashboardScreen>
    with TickerProviderStateMixin {
  final AgentOrchestrator _orchestrator = AgentOrchestrator();

  // Agent data
  List<AgentStatus> _agents = [];
  List<TaskPlan> _activePlans = [];
  final List<AgentActivity> _activities = [];

  // Streams
  StreamSubscription<AgentStatus>? _agentSub;
  StreamSubscription<AgentActivity>? _activitySub;

  // Controllers
  late TabController _tabController;
  final ScrollController _logScroll = ScrollController();

  // Demo mode
  bool _demoRunning = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));

    // Initial data
    _agents = _orchestrator.getAllAgentStatuses();
    _activePlans = _orchestrator.activePlans;

    // Listen to agent updates
    _agentSub = _orchestrator.agentUpdates.listen((status) {
      if (!mounted) return;
      setState(() {
        final idx = _agents.indexWhere((a) => a.agentId == status.agentId);
        if (idx >= 0) {
          _agents[idx] = status;
        } else {
          _agents.add(status);
        }
      });
    });

    // Listen to activity log
    _activitySub = _orchestrator.activityLog.listen((activity) {
      if (!mounted) return;
      setState(() {
        _activities.insert(0, activity);
        if (_activities.length > 200) _activities.removeLast();
      });
      _scrollToTop();
    });

    // Auto-start demo
    Future.delayed(const Duration(milliseconds: 500), _startDemo);
  }

  void _scrollToTop() {
    if (_logScroll.hasClients && _logScroll.offset < 100) {
      _logScroll.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _agentSub?.cancel();
    _activitySub?.cancel();
    _tabController.dispose();
    _logScroll.dispose();
    super.dispose();
  }

  // ── Demo ──────────────────────────────────────────────────────────────

  Future<void> _startDemo() async {
    if (_demoRunning) return;
    setState(() => _demoRunning = true);

    // Create a demo plan
    final plan = await _orchestrator.createPlan(
      '\u521b\u5efa\u4e00\u4e2a\u8bb0\u8d26App\uff0c\u5e26\u6709\u6570\u636e\u5e93\u3001UI\u754c\u9762\u3001\u56fe\u8868\u7edf\u8ba1\u548c\u5355\u5143\u6d4b\u8bd5',
    );

    setState(() => _activePlans = [plan]);

    // Execute with progress updates
    await _orchestrator.executePlan(
      plan,
      onProgress: (p) {
        if (mounted) {
          setState(() {
            final idx = _activePlans.indexWhere((pl) => pl.id == p.id);
            if (idx >= 0) _activePlans[idx] = p;
          });
        }
      },
    );

    if (mounted) setState(() => _demoRunning = false);
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final activeCount = _agents.where((a) => a.isWorking || a.isThinking).length;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(children: [
          // Header
          _header(activeCount),

          // Tab bar
          _tabBar(),

          // Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _agentsTab(),
                _plansTab(),
              ],
            ),
          ),

          // Activity log (always visible at bottom)
          _activityLogPanel(),
        ]),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────

  Widget _header(int activeCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: AppTheme.surfaceGradient,
        border: const Border(
          bottom: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            // Back button
            InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceHover.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.arrow_back,
                  size: 20,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),

            const SizedBox(width: 12),

            // Title
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '\u667a\u80fd\u4f53\u76d1\u63a7\u4e2d\u5fc3',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '\u5b9e\u65f6\u76d1\u63a7\u591a\u4e2aAI\u667a\u80fd\u4f53\u7684\u6267\u884c\u72b6\u6001',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ],
              ),
            ),

            // Active count badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: activeCount > 0 ? AppTheme.primaryGradient : null,
                color: activeCount > 0 ? null : AppTheme.surfaceHover,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (activeCount > 0) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    '$activeCount \u6d3b\u8dc3',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: activeCount > 0 ? Colors.white : AppTheme.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ]),
        ],
      ),
    );
  }

  // ── Tab Bar ───────────────────────────────────────────────────────────

  Widget _tabBar() {
    return Container(
      color: AppTheme.backgroundElevated,
      child: TabBar(
        controller: _tabController,
        indicatorColor: AppTheme.primary,
        labelColor: AppTheme.primary,
        unselectedLabelColor: AppTheme.textTertiary,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        tabs: [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.smart_toy, size: 16),
                const SizedBox(width: 6),
                Text('\u667a\u80fd\u4f53 (${_agents.length})'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.assignment, size: 16),
                const SizedBox(width: 6),
                Text('\u4efb\u52a1 (${_activePlans.length})'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Agents Tab ────────────────────────────────────────────────────────

  Widget _agentsTab() {
    if (_agents.isEmpty) {
      return const Center(
        child: Text(
          '\u6682\u65e0\u667a\u80fd\u4f53\u6570\u636e',
          style: TextStyle(color: AppTheme.textTertiary),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _agents.length,
      itemBuilder: (context, index) => _AgentCard(agent: _agents[index]),
    );
  }

  // ── Plans Tab ─────────────────────────────────────────────────────────

  Widget _plansTab() {
    if (_activePlans.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.assignment_outlined,
              size: 48,
              color: AppTheme.textDisabled,
            ),
            const SizedBox(height: 12),
            const Text(
              '\u6682\u65e0\u8fdb\u884c\u4e2d\u7684\u4efb\u52a1',
              style: TextStyle(color: AppTheme.textTertiary),
            ),
            const SizedBox(height: 16),
            if (!_demoRunning)
              ElevatedButton.icon(
                onPressed: _startDemo,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('\u8fd0\u884c\u6f14\u793a'),
              ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _activePlans.length,
      itemBuilder: (context, index) => _PlanCard(
        plan: _activePlans[index],
        onTap: () => TaskPlanSidebar.show(
          context: context,
          plan: _activePlans[index],
          onPlanChanged: (p) {
            setState(() => _activePlans[index] = p);
          },
        ),
      ),
    );
  }

  // ── Activity Log ──────────────────────────────────────────────────────

  Widget _activityLogPanel() {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.background.withOpacity(0.0),
            AppTheme.background,
          ],
        ),
        border: const Border(
          top: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Log header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              const Icon(Icons.terminal, size: 14, color: AppTheme.textTertiary),
              const SizedBox(width: 6),
              const Text(
                '\u5b9e\u65f6\u65e5\u5fd7',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const Spacer(),
              if (_activities.isNotEmpty)
                Text(
                  '${_activities.length} \u6761\u8bb0\u5f55',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textDisabled,
                    fontFamily: AppTheme.fontCode,
                  ),
                ),
            ]),
          ),

          // Log entries
          Expanded(
            child: _activities.isEmpty
                ? const Center(
                    child: Text(
                      '\u7b49\u5f85\u6d3b\u52a8...',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textDisabled,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _logScroll,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _activities.length,
                    itemBuilder: (context, index) {
                      final activity = _activities[index];
                      return _ActivityRow(activity: activity);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Agent Card Widget
// ═══════════════════════════════════════════════════════════════════════════

class _AgentCard extends StatefulWidget {
  final AgentStatus agent;

  const _AgentCard({required this.agent});

  @override
  State<_AgentCard> createState() => _AgentCardState();
}

class _AgentCardState extends State<_AgentCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.agent.isWorking || widget.agent.isThinking) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _AgentCard old) {
    super.didUpdateWidget(old);
    final shouldPulse = widget.agent.isWorking || widget.agent.isThinking;
    if (shouldPulse && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!shouldPulse && _pulse.isAnimating) {
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
    final a = widget.agent;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.surface,
            AppTheme.backgroundElevated,
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: a.isWorking
              ? a.accentColor.withOpacity(0.4)
              : AppTheme.border,
          width: a.isWorking ? 1.5 : 1,
        ),
        boxShadow: a.isWorking
            ? [
                BoxShadow(
                  color: a.accentColor.withOpacity(0.1),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: icon + status
            Row(children: [
              // Agent icon
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      a.accentColor.withOpacity(0.3),
                      a.accentColor.withOpacity(0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _agentIcon(a.icon),
                  size: 18,
                  color: a.accentColor,
                ),
              ),

              const SizedBox(width: 10),

              // Name + state
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      a.stateLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: a.stateColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // Pulsing status dot
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) {
                  return Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: a.stateColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: a.stateColor.withOpacity(
                            0.3 + (_pulse.value * 0.4),
                          ),
                          blurRadius: 6 + (_pulse.value * 6),
                          spreadRadius: _pulse.value * 2,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ]),

            const SizedBox(height: 10),

            // Current task
            if (a.currentTask != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: a.accentColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: a.accentColor.withOpacity(0.15),
                  ),
                ),
                child: Text(
                  a.currentTask!,
                  style: TextStyle(
                    fontSize: 10,
                    color: a.accentColor.withOpacity(0.9),
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            const Spacer(),

            // Progress bar (if working)
            if (a.progress != null && a.isWorking) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: a.progress,
                  backgroundColor: AppTheme.surfaceHover,
                  valueColor: AlwaysStoppedAnimation(a.accentColor),
                  minHeight: 4,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(a.progress! * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: a.accentColor,
                      fontFamily: AppTheme.fontCode,
                    ),
                  ),
                  Text(
                    a.taskDurationFormatted,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.textTertiary,
                      fontFamily: AppTheme.fontCode,
                    ),
                  ),
                ],
              ),
            ] else
              // Recent actions
              if (a.recentActions.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '\u6700\u8fd1\u52a8\u4f5c',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.textDisabled,
                      ),
                    ),
                    const SizedBox(height: 3),
                    ...a.recentActions.take(2).map((action) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          children: [
                            Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: a.accentColor.withOpacity(0.6),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                action,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
          ],
        ),
      ),
    );
  }

  IconData _agentIcon(String icon) {
    switch (icon) {
      case 'code':
        return Icons.code;
      case 'bug':
        return Icons.bug_report;
      case 'git':
        return Icons.source;
      case 'terminal':
        return Icons.terminal;
      case 'folder':
        return Icons.folder;
      default:
        return Icons.smart_toy;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Plan Card Widget
// ═══════════════════════════════════════════════════════════════════════════

class _PlanCard extends StatelessWidget {
  final TaskPlan plan;
  final VoidCallback? onTap;

  const _PlanCard({required this.plan, this.onTap});

  @override
  Widget build(BuildContext context) {
    final pct = (plan.progress * 100).toStringAsFixed(0);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.surface,
              AppTheme.backgroundElevated,
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: plan.isActive
                ? AppTheme.primary.withOpacity(0.4)
                : AppTheme.border,
            width: plan.isActive ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              // Status
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: plan.status.color,
                  shape: BoxShape.circle,
                  boxShadow: plan.isActive
                      ? [
                          BoxShadow(
                            color: plan.status.color.withOpacity(0.4),
                            blurRadius: 6,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 10),

              // Title
              Expanded(
                child: Text(
                  plan.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Percentage
              Text(
                '$pct%',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.accent,
                  fontFamily: AppTheme.fontCode,
                ),
              ),
            ]),

            const SizedBox(height: 6),

            // Description
            Text(
              plan.description,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 12),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: plan.progress.clamp(0.0, 1.0),
                backgroundColor: AppTheme.surfaceHover,
                valueColor: AlwaysStoppedAnimation(plan.status.color),
                minHeight: 6,
              ),
            ),

            const SizedBox(height: 10),

            // Stats row
            Row(children: [
              _stat(Icons.check_circle, AppTheme.success,
                  '${plan.completedSteps} \u5b8c\u6210'),
              const SizedBox(width: 16),
              _stat(Icons.schedule, AppTheme.textTertiary,
                  '${plan.pendingSteps} \u5f85\u6267\u884c'),
              if (plan.failedSteps > 0) ...[
                const SizedBox(width: 16),
                _stat(Icons.error, AppTheme.error,
                    '${plan.failedSteps} \u5931\u8d25'),
              ],
              const Spacer(),
              Text(
                plan.elapsedTimeFormatted,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textTertiary,
                  fontFamily: AppTheme.fontCode,
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _stat(IconData icon, Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Activity Row Widget
// ═══════════════════════════════════════════════════════════════════════════

class _ActivityRow extends StatelessWidget {
  final AgentActivity activity;

  const _ActivityRow({required this.activity});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: const TextStyle(
            fontSize: 11,
            fontFamily: AppTheme.fontCode,
            height: 1.4,
          ),
          children: [
            // Timestamp
            TextSpan(
              text: '${activity.formattedTime} ',
              style: const TextStyle(color: AppTheme.textDisabled),
            ),
            // Agent name
            TextSpan(
              text: '[${activity.agentName}] ',
              style: TextStyle(
                color: activity.color.withOpacity(0.7),
                fontWeight: FontWeight.w600,
              ),
            ),
            // Action
            TextSpan(
              text: activity.action,
              style: TextStyle(color: activity.color),
            ),
          ],
        ),
      ),
    );
  }
}
