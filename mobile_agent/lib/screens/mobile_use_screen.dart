// lib/screens/mobile_use_screen.dart
// Mobile Use Screen
//
// The main interface for Self-Use functionality.
// This is where users see MobileCode operating itself.
//
// Layout:
// - Header: "Mobile Use" + status indicator
// - Input area: Text field for user request
// - History: Past self-use sessions
// - Quick actions: Common self-use prompts
//
// When a session is active:
// - Shows real-time plan sidebar
// - Shows action log (scrolling)
// - Shows current action with animation
// - Progress bar
//
// Design: Dark theme, glassmorphism, violet/cyan accents
//         Real-time updates with smooth animations

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../models/self_use_session.dart';
import '../models/agent_task.dart';
import '../services/self_invocation_service.dart';
import '../widgets/task_plan_sidebar.dart';
import '../widgets/self_use_log_view.dart';
import '../widgets/self_use_mini_bar.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Mobile Use Screen
// ═══════════════════════════════════════════════════════════════════════════

/// The main "Mobile Use" screen where users watch MobileCode control itself.
///
/// Features:
/// - Input area for user requests with send button
/// - Quick prompt chips for common self-use tasks
/// - History list of past sessions with status indicators
/// - Real-time active session view with:
///   - Plan sidebar (slide-in from right)
///   - Scrolling action log
///   - Current action with pulse animation
///   - Progress bar
///
/// Design: Dark theme, glassmorphism, violet/cyan accents.
class MobileUseScreen extends StatefulWidget {
  const MobileUseScreen({super.key});

  @override
  State<MobileUseScreen> createState() => _MobileUseScreenState();
}

class _MobileUseScreenState extends State<MobileUseScreen>
    with TickerProviderStateMixin {
  // ── Services ──────────────────────────────────────────────────────────

  final SelfInvocationService _service = SelfInvocationService();

  // ── Controllers ───────────────────────────────────────────────────────

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late AnimationController _pulseController;
  late AnimationController _progressController;
  late Animation<double> _pulseAnimation;

  // ── State ─────────────────────────────────────────────────────────────

  SelfUseSession? _activeSession;
  List<SelfUseSession> _history = [];
  List<SelfActionEntry> _actions = [];
  bool _isSending = false;
  bool _showLogPanel = false;

  // ── Stream Subscriptions ──────────────────────────────────────────────

  StreamSubscription<SelfUseSession?>? _sessionSub;
  StreamSubscription<List<SelfActionEntry>>? _actionsSub;
  StreamSubscription<List<SelfUseSession>>? _historySub;

  // ── Constants ─────────────────────────────────────────────────────────

  static const List<String> _quickPrompts = [
    '\u521B\u5EFA\u4E00\u4E2A\u5F85\u529E\u4E8B\u9879 App',
    '\u4FEE\u590D\u5F53\u524D\u9879\u76EE\u7684\u7F16\u8BD1\u9519\u8BEF',
    '\u7ED9\u9879\u76EE\u6DFB\u52A0\u7528\u6237\u8BA4\u8BC1',
    '\u751F\u6210\u4E00\u4E2A\u767B\u5F55\u9875\u9762',
    '\u63D0\u4EA4\u4EE3\u7801\u5230 GitHub',
    '\u90E8\u7F72\u9879\u76EE\u5230 GitHub Pages',
  ];

  // ── Lifecycle ─────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    // Listen to streams
    _sessionSub = _service.activeSessionStream.listen((session) {
      setState(() {
        _activeSession = session;
        if (session?.isActive == true) {
          _pulseController.repeat(reverse: true);
          _progressController.animateTo(session?.progress ?? 0.0);
        } else {
          _pulseController.stop();
        }
      });
    });

    _actionsSub = _service.actionsStream.listen((actions) {
      setState(() => _actions = actions);
    });

    _historySub = _service.historyStream.listen((history) {
      setState(() => _history = history);
    });

    // Load existing history
    _history = _service.history;
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    _actionsSub?.cancel();
    _historySub?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    _pulseController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────────────

  void _sendRequest() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    HapticFeedback.mediumImpact();
    setState(() => _isSending = true);
    _inputController.clear();

    _service.startSession(text);

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _isSending = false);
    });
  }

  void _sendQuickPrompt(String prompt) {
    HapticFeedback.lightImpact();
    _inputController.text = prompt;
    _sendRequest();
  }

  void _showPlanSidebar() {
    if (_activeSession?.taskPlan == null) return;
    HapticFeedback.lightImpact();
    TaskPlanSidebar.show(
      context: context,
      plan: _activeSession!.taskPlan!,
    );
  }

  void _toggleLogPanel() {
    setState(() => _showLogPanel = !_showLogPanel);
  }

  void _pauseSession() {
    HapticFeedback.lightImpact();
    _service.pauseSession();
  }

  void _resumeSession() {
    HapticFeedback.lightImpact();
    _service.resumeSession();
  }

  void _cancelSession() {
    HapticFeedback.mediumImpact();
    _service.cancelSession();
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasActive = _activeSession != null;
    final isRunning = _activeSession?.isActive ?? false;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // Main content
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              // ── App Bar ───────────────────────────────────────────
              _appBar(),

              // ── Content ───────────────────────────────────────────
              if (!hasActive) ...[
                // Idle state
                SliverToBoxAdapter(child: _inputSection()),
                SliverToBoxAdapter(child: _quickPromptsSection()),
                if (_history.isNotEmpty)
                  SliverToBoxAdapter(child: _historyHeader()),
                _historyList(),
                const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
              ] else ...[
                // Active session state
                SliverToBoxAdapter(child: _activeSessionHeader()),
                SliverToBoxAdapter(child: _progressSection()),
                SliverToBoxAdapter(child: _currentActionCard()),
                if (_showLogPanel) _buildLogPanel() else const SliverToBoxAdapter(child: SizedBox.shrink()),
                const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
              ],
            ],
          ),

          // Mini bar (active session only)
          if (hasActive)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SelfUseMiniBar(
                session: _activeSession!,
                onExpand: _showPlanSidebar,
                onPause: isRunning ? _pauseSession : _resumeSession,
                onCancel: _cancelSession,
                onToggleLog: _toggleLogPanel,
                isLogVisible: _showLogPanel,
              ),
            ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // App Bar
  // ════════════════════════════════════════════════════════════════════════

  Widget _appBar() {
    final hasActive = _activeSession != null;
    final status = _activeSession?.status;

    return SliverAppBar(
      floating: true,
      pinned: true,
      elevation: 0,
      backgroundColor: AppTheme.background.withOpacity(0.9),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Mobile Use',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          if (hasActive) ...[
            const SizedBox(width: 10),
            _StatusBadge(
              status: status ?? SelfUseSessionStatus.idle,
              color: _activeSession?.statusColor ?? AppTheme.textTertiary,
            ),
          ],
        ],
      ),
      actions: [
        if (hasActive)
          IconButton(
            icon: Icon(
              _showLogPanel ? Icons.terminal : Icons.terminal_outlined,
              color: _showLogPanel ? AppTheme.accent : AppTheme.textSecondary,
            ),
            onPressed: _toggleLogPanel,
            tooltip: '\u5207\u6362\u65E5\u5FD7\u9762\u677F',
          ),
        const SizedBox(width: 8),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // Input Section (idle state)
  // ════════════════════════════════════════════════════════════════════════

  Widget _inputSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.surface.withOpacity(0.8),
            AppTheme.backgroundElevated.withOpacity(0.6),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.border,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label
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
                  size: 20,
                  color: AppTheme.textOnPrimary,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '\u544A\u8BC9 MobileCode \u505A\u4EC0\u4E48',
                      style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'MobileCode \u4F1A\u81EA\u52A8\u5206\u6790\u3001\u89C4\u5212\u5E76\u6267\u884C\u4EFB\u52A1',
                      style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 12,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Input field
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceInput,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 14,
                      color: AppTheme.textPrimary,
                    ),
                    decoration: const InputDecoration(
                      hintText: '\u4F8B\u5982\uFF1A\u521B\u5EFA\u4E00\u4E2A\u5F85\u529E\u4E8B\u9879 App...',
                      hintStyle: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 14,
                        color: AppTheme.textTertiary,
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      border: InputBorder.none,
                    ),
                    maxLines: 3,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendRequest(),
                  ),
                ),
                // Send button
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    child: Material(
                      color: _isSending
                          ? AppTheme.primaryMuted
                          : AppTheme.primary,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: _isSending ? null : _sendRequest,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          child: _isSending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(
                                        AppTheme.textOnPrimary),
                                  ),
                                )
                              : const Icon(
                                  Icons.send,
                                  size: 18,
                                  color: AppTheme.textOnPrimary,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // Quick Prompts Section
  // ════════════════════════════════════════════════════════════════════════

  Widget _quickPromptsSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              '\u5FEB\u6377\u64CD\u4F5C',
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickPrompts.map((prompt) {
              return _QuickPromptChip(
                label: prompt,
                onTap: () => _sendQuickPrompt(prompt),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // History Section
  // ════════════════════════════════════════════════════════════════════════

  Widget _historyHeader() {
    return Container(
      margin: const EdgeInsets.only(top: 24, left: 20, right: 20, bottom: 8),
      child: Row(
        children: [
          const Text(
            '\u5386\u53F2\u8BB0\u5F55',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const Spacer(),
          if (_history.isNotEmpty)
            TextButton(
              onPressed: () {
                // Clear history
                setState(() => _history = []);
              },
              child: const Text(
                '\u6E05\u7A7A',
                style: TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 12,
                  color: AppTheme.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _historyList() {
    if (_history.isEmpty) {
      return SliverToBoxAdapter(child: _emptyState());
    }

    return SliverList.builder(
      itemCount: _history.length,
      itemBuilder: (context, index) {
        final session = _history[index];
        return _HistoryTile(session: session);
      },
    );
  }

  Widget _emptyState() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.surface.withOpacity(0.3),
            AppTheme.backgroundElevated.withOpacity(0.2),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.border.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primary.withOpacity(0.2),
                  AppTheme.accent.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.auto_fix_high,
              size: 32,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'MobileCode \u53EF\u4EE5\u64CD\u4F5C\u81EA\u5DF1',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '\u8BD5\u8BD5\u8BF4\u201C\u521B\u5EFA\u4E00\u4E2A App\u201D\uFF0C\u770B\u770B MobileCode \u80FD\u505A\u4EC0\u4E48',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 13,
              color: AppTheme.textTertiary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // Active Session View
  // ════════════════════════════════════════════════════════════════════════

  Widget _activeSessionHeader() {
    final session = _activeSession!;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary.withOpacity(0.1),
            AppTheme.surface.withOpacity(0.6),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.primary.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Robot icon with pulse
              ScaleTransition(
                scale: _pulseAnimation,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.smart_toy,
                    size: 22,
                    color: AppTheme.textOnPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Session info
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _StatusBadge(
                          status: session.status,
                          color: session.statusColor,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          session.elapsedTimeFormatted,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontCode,
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _progressSection() {
    final session = _activeSession!;
    final pct = (session.progress * 100).toStringAsFixed(0);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '\u6267\u884C\u8FDB\u5EA6',
                style: TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary,
                ),
              ),
              Text(
                '$pct%',
                style: const TextStyle(
                  fontFamily: AppTheme.fontCode,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: session.progress.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 400),
              builder: (context, value, child) {
                return LinearProgressIndicator(
                  value: value,
                  backgroundColor: AppTheme.surfaceHover,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                  minHeight: 8,
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _miniStat(
                '\u5DF2\u5B8C\u6210',
                '${session.completedActionsCount}',
                AppTheme.success,
              ),
              const SizedBox(width: 16),
              _miniStat(
                '\u603B\u6B65\u9AA4',
                '${session.totalActions}',
                AppTheme.textSecondary,
              ),
              if (session.failedActionsCount > 0) ...[
                const SizedBox(width: 16),
                _miniStat(
                  '\u5931\u8D25',
                  '${session.failedActionsCount}',
                  AppTheme.error,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 11,
            color: AppTheme.textTertiary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: AppTheme.fontCode,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _currentActionCard() {
    if (_actions.isEmpty) return const SizedBox.shrink();

    final current = _activeSession?.currentAction;
    if (current == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            current.typeColor.withOpacity(0.1),
            AppTheme.surface.withOpacity(0.5),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: current.typeColor.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: current.typeColor.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Pulsing icon
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    current.typeColor.withOpacity(0.3),
                    current.typeColor.withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                current.icon,
                size: 22,
                color: current.typeColor,
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Action info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current.isRunning
                      ? '\u6B63\u5728\u6267\u884C: ${current.type.label}'
                      : current.description,
                  style: TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: current.typeColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  current.description,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (current.detail != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    current.detail!,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 11,
                      color: AppTheme.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // Status indicator
          if (current.isRunning)
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(current.typeColor),
              ),
            )
          else if (current.status == StepStatus.completed)
            const Icon(
              Icons.check_circle,
              color: AppTheme.success,
              size: 24,
            )
          else if (current.status == StepStatus.failed)
            const Icon(
              Icons.error,
              color: AppTheme.error,
              size: 24,
            ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // Log Panel
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildLogPanel() {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        height: 300,
        decoration: BoxDecoration(
          color: AppTheme.backgroundElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SelfUseLogView(
            actions: _actions,
            onClear: () {},
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Quick Prompt Chip
// ═══════════════════════════════════════════════════════════════════════════

class _QuickPromptChip extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickPromptChip({
    required this.label,
    required this.onTap,
  });

  @override
  State<_QuickPromptChip> createState() => _QuickPromptChipState();
}

class _QuickPromptChipState extends State<_QuickPromptChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        transform: _pressed
            ? (Matrix4.identity()..scale(0.96))
            : Matrix4.identity(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.surface.withOpacity(0.8),
                AppTheme.surfaceHover.withOpacity(0.5),
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _pressed
                  ? AppTheme.primary.withOpacity(0.5)
                  : AppTheme.border,
              width: 1,
            ),
          ),
          child: Text(
            widget.label,
            style: const TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 13,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Status Badge
// ═══════════════════════════════════════════════════════════════════════════

class _StatusBadge extends StatelessWidget {
  final SelfUseSessionStatus status;
  final Color color;

  const _StatusBadge({
    required this.status,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            _statusLabel,
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String get _statusLabel {
    switch (status) {
      case SelfUseSessionStatus.idle:
        return '\u7B49\u5F85\u4E2D';
      case SelfUseSessionStatus.running:
        return '\u6267\u884C\u4E2D';
      case SelfUseSessionStatus.paused:
        return '\u5DF2\u6682\u505C';
      case SelfUseSessionStatus.completed:
        return '\u5DF2\u5B8C\u6210';
      case SelfUseSessionStatus.failed:
        return '\u5931\u8D25';
      case SelfUseSessionStatus.cancelled:
        return '\u5DF2\u53D6\u6D88';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// History Tile
// ═══════════════════════════════════════════════════════════════════════════

class _HistoryTile extends StatelessWidget {
  final SelfUseSession session;

  const _HistoryTile({required this.session});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border.withOpacity(0.5)),
      ),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Status icon
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: session.statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    session.statusEmoji,
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.userRequest,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: session.statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          session.statusLabel,
                          style: TextStyle(
                            fontFamily: AppTheme.fontBody,
                            fontSize: 11,
                            color: session.statusColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${session.totalActions} \u6B65\u9AA4',
                          style: const TextStyle(
                            fontFamily: AppTheme.fontBody,
                            fontSize: 11,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                        if (session.totalDuration != null) ...[
                          const SizedBox(width: 12),
                          Text(
                            _formatDuration(session.totalDuration!),
                            style: const TextStyle(
                              fontFamily: AppTheme.fontCode,
                              fontSize: 11,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Arrow
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: AppTheme.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${(d.inSeconds % 60).toString().padLeft(2, '0')}s';
    }
    return '${d.inSeconds}s';
  }
}
